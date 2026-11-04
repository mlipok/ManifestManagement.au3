; Chilkat ActiveX via chilkat.manifest: four simultaneous HTTP range downloads.
; Inspired by: https://www.example-code.com/autoit/http_download_range_parallel.asp
; Uses GetHead(), supported by 10.1.2, instead of the vendor's newer HttpNoBody().
;
; Place the original ChilkatAx-10.1.2.0-win32.dll beside this script.
; The matching chilkat.manifest is already included in this directory.
; Run with 32-bit AutoIt; no COM registration or Chilkat.au3 UDF is required.
;   AutoIt3.exe chilkat.au3 [URL]
;   AutoIt3.exe chilkat.au3 --check-activation
; Uses ManifestManagement.au3 + ObjCreate(ProgID), without COM registration.
; The activation-only check does not unlock the API or access the network.
; A unique output directory keeps all chunks and the comparison download.
; Requires a server with HEAD, byte ranges, and a strong ETag or Last-Modified.
; This bounded example accepts files between 4 bytes and 2 GiB minus one byte.
#AutoIt3Wrapper_UseX64=N
#AutoIt3Wrapper_Run_Au3Check=Y
#AutoIt3Wrapper_Au3Check_Parameters=-d -w 1 -w 2 -w 3 -w 4 -w 5 -w 6 -w 7

#include "..\ManifestManagement.au3"

; Replace with your own unlock code for licensed use. Never commit a purchased code.
Global Const $CHILKAT_UNLOCK_CODE = "Anything for 30-day trial"
Global Const $CHUNK_COUNT = 4
Global $g_hContext = 0, $g_iCookie = 0
Global $g_aHttp[$CHUNK_COUNT], $g_aTask[$CHUNK_COUNT]
Global $g_iCOMError = 0
Global $g_oCOMHandler = ObjEvent("AutoIt.Error", _COMError)
OnAutoItExitRegister(_Cleanup)

Exit _Example()

Func _Example()
	If @AutoItX64 Then Return _Fail("Use 32-bit AutoIt with the supplied win32 manifest and DLL.")
	If $CmdLine[0] > 1 Then Return _Usage()
	Local $bCheckOnly = False
	Local $sURL = "https://www.chilkatsoft.com/hamlet.xml"
	If $CmdLine[0] = 1 Then
		$bCheckOnly = ($CmdLine[1] = "--check-activation")
		If Not $bCheckOnly Then $sURL = $CmdLine[1]
	EndIf
	If Not StringRegExp($sURL, "(?i)^https?://") Then Return _Usage()

	Local $sDLL = @ScriptDir & "\ChilkatAx-10.1.2.0-win32.dll"
	If Not FileExists($sDLL) Then Return _Fail("Missing DLL: " & $sDLL)
	If Not StringRegExp(FileGetVersion($sDLL), "^10\.1\.2(?:\.0)?$") Then Return _Fail("Use the original Chilkat ActiveX 10.1.2 win32 DLL.")
	Local $aContext = _ManifestManagement_ActivateFromFile(@ScriptDir & "\chilkat.manifest")
	Local $iError = @error, $iNativeError = @extended
	If $iError Then Return _Fail("Manifest activation failed: " & $iError & "/" & $iNativeError)
	$g_hContext = $aContext[0]
	$g_iCookie = $aContext[1]

	Local $oGlobal = _NewObject("Global")
	Local $oProbe = _NewObject("Http")
	Local $oFiles = _NewObject("FileAccess")
	If Not IsObj($oGlobal) Or Not IsObj($oProbe) Or Not IsObj($oFiles) Then Return _Fail("COM object creation failed.")
	ConsoleWrite("Manifest activation: Chilkat " & $oGlobal.Version & @CRLF)
	_ConfigureHttp($oProbe)
	If $g_iCOMError Then Return _Fail("COM method invocation failed.")
	If $bCheckOnly Then
		If Not $oFiles.FileExists($sDLL) Then Return _Fail("FileAccess method invocation failed.")
		If $g_iCOMError Then Return _Fail("FileAccess method invocation failed.")
		ConsoleWrite("Global, Http and FileAccess activation and method calls: OK." & @CRLF)
		Return 0
	EndIf
	If Not $oGlobal.UnlockBundle($CHILKAT_UNLOCK_CODE) Then Return _Fail("Chilkat unlock failed. Configure a valid unlock code or an available trial.")
	Local $oHead = $oProbe.GetHead($sURL)
	If Not IsObj($oHead) Then Return _Fail("HEAD failed: " & $oProbe.LastErrorText)
	If $oHead.StatusCode <> 200 Then Return _Fail("HEAD must return 200. Use the final URL without redirects.")
	Local $iSize = Number($oHead.ContentLength)
	If $iSize < $CHUNK_COUNT Or $iSize > 2147483647 Then Return _Fail("Unsupported or missing Content-Length.")
	Local $sValidator = $oHead.GetHeaderField("ETag")
	If $sValidator = "" Or StringLeft($sValidator, 2) = "W/" Then $sValidator = $oHead.GetHeaderField("Last-Modified")
	If $sValidator = "" Then Return _Fail("A strong ETag or Last-Modified is required to pin all ranges to one resource version.")
	$oHead = 0

	Local $sOutput = @ScriptDir & "\chilkat-download-" & @AutoItPID & "-" & @YEAR & @MON & @MDAY & @HOUR & @MIN & @SEC
	If FileExists($sOutput) Then Return _Fail("Output directory already exists.")
	If Not DirCreate($sOutput) Then Return _Fail("Cannot create output directory.")
	Local $iChunkSize = Int($iSize / $CHUNK_COUNT)
	Local $aStart[$CHUNK_COUNT], $aEnd[$CHUNK_COUNT]
	For $i = 0 To $CHUNK_COUNT - 1
		$aStart[$i] = $i * $iChunkSize
		$aEnd[$i] = ($i = $CHUNK_COUNT - 1 ? $iSize - 1 : ($i + 1) * $iChunkSize - 1)
		$g_aHttp[$i] = _NewObject("Http")
		If Not IsObj($g_aHttp[$i]) Then Return _Fail("Cannot create range HTTP object.")
		_ConfigureHttp($g_aHttp[$i])
		$g_aHttp[$i].SetRequestHeader("Range", "bytes=" & $aStart[$i] & "-" & $aEnd[$i])
		$g_aHttp[$i].SetRequestHeader("If-Range", $sValidator)
		$g_aTask[$i] = $g_aHttp[$i].DownloadAsync($sURL, $sOutput & "\part" & ($i + 1) & ".bin")
		If Not IsObj($g_aTask[$i]) Then Return _Fail("Cannot create download task.")
		If Not $g_aTask[$i].Run() Then Return _Fail("Cannot start download task.")
	Next

	Local $hTimer = TimerInit(), $bFinished
	Do
		$bFinished = True
		For $i = 0 To $CHUNK_COUNT - 1
			If Not $g_aTask[$i].Finished Then $bFinished = False
		Next
		If $g_iCOMError Then Return _Fail("COM failed during download.")
		If TimerDiff($hTimer) > 120000 Then Return _Fail("Parallel download timed out.")
		If Not $bFinished Then Sleep(20)
	Until $bFinished

	For $i = 0 To $CHUNK_COUNT - 1
		If Not $g_aTask[$i].GetResultBool() Then Return _Fail("Range task failed: " & $g_aTask[$i].ResultErrorText)
		If $g_aHttp[$i].LastStatus <> 206 Then Return _Fail("Server did not return 206 Partial Content.")
		Local $sExpected = $aStart[$i] & "-" & $aEnd[$i] & "/" & $iSize
		Local $aRange = StringRegExp($g_aHttp[$i].LastResponseHeader, "(?im)^Content-Range:\h*bytes\h+([0-9]+-[0-9]+/[0-9]+)\h*\r?$", 1)
		If Not IsArray($aRange) Then Return _Fail("Missing or invalid Content-Range.")
		If $aRange[0] <> $sExpected Then Return _Fail("Unexpected Content-Range: " & $aRange[0])
		If FileGetSize($sOutput & "\part" & ($i + 1) & ".bin") <> $aEnd[$i] - $aStart[$i] + 1 Then Return _Fail("Range file size mismatch.")
		ConsoleWrite("Range " & ($i + 1) & ": " & $sExpected & " OK" & @CRLF)
	Next

	Local $sPending = $sOutput & "\assembled.pending"
	If Not $oFiles.ReassembleFile($sOutput, "part", "bin", $sPending) Then Return _Fail("Reassembly failed: " & $oFiles.LastErrorText)
	If FileGetSize($sPending) <> $iSize Then Return _Fail("Assembled file size mismatch.")
	; Compare with a regular download, as in the vendor example.
	If Not $oProbe.Download($sURL, $sOutput & "\reference.bin") Then Return _Fail("Comparison download failed: " & $oProbe.LastErrorText)
	If $oProbe.LastStatus <> 200 Then Return _Fail("Comparison download must return 200.")
	If Not $oFiles.FileContentsEqual($sPending, $sOutput & "\reference.bin") Then Return _Fail("Parallel and regular downloads differ.")
	If $g_iCOMError Then Return _Fail("COM failed while checking the result.")
	If Not FileMove($sPending, $sOutput & "\download.bin", 0) Then Return _Fail("Cannot publish the verified download.")
	ConsoleWrite("Verified download: " & $sOutput & "\download.bin" & @CRLF)
	Return 0
EndFunc   ;==>_Example

Func _NewObject($sClass)
	Local $oObject = ObjCreate("Chilkat." & $sClass & ".1")
	Local $iError = @error
	If $iError Or Not IsObj($oObject) Then Return SetError(1, $iError, 0)
	Return $oObject
EndFunc   ;==>_NewObject

Func _ConfigureHttp($oHttp)
	$oHttp.ConnectTimeout = 15
	$oHttp.ReadTimeout = 30
	$oHttp.FollowRedirects = False
	$oHttp.SetRequestHeader("Accept-Encoding", "identity")
EndFunc   ;==>_ConfigureHttp

Func _Cleanup()
	; A task may still hold DLL code and HTTP objects after a failure.
	; Cancel and wait before releasing objects and the activation context.
	Local $bStopped = True
	For $i = 0 To $CHUNK_COUNT - 1
		If Not IsObj($g_aTask[$i]) Then ContinueLoop
		If Not $g_aTask[$i].Finished Then
			$g_aTask[$i].Cancel()
			If Not $g_aTask[$i].Wait(5000) Then $bStopped = False
		EndIf
	Next
	If Not $bStopped Then
		ConsoleWrite("A task is still active; keeping its context until process termination." & @CRLF)
		Return
	EndIf
	For $i = 0 To $CHUNK_COUNT - 1
		$g_aTask[$i] = 0
		$g_aHttp[$i] = 0
	Next
	If $g_hContext Then _ManifestManagement_Deactivate($g_hContext, $g_iCookie)
EndFunc   ;==>_Cleanup

Func _COMError($oError)
	$g_iCOMError = $oError.number
	ConsoleWrite("COM error 0x" & Hex($g_iCOMError, 8) & " at line " & $oError.scriptline & @CRLF)
EndFunc   ;==>_COMError

Func _Fail($sMessage)
	ConsoleWrite("ERROR: " & $sMessage & @CRLF)
	Return 1
EndFunc   ;==>_Fail

Func _Usage()
	ConsoleWrite("Usage: chilkat.au3 [HTTP(S) URL | --check-activation]" & @CRLF)
	Return 2
EndFunc   ;==>_Usage
