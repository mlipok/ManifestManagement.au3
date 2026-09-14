#AutoIt3Wrapper_Change2CUI=y

#include <FileConstants.au3>
#include <MsgBoxConstants.au3>
#include "ManifestManagement.au3"


_Main()

; #FUNCTION# ====================================================================================================================
; Name ..........: _Main
; Description ...: Selects or reads input manifest paths, merges the manifests, and writes the result.
; Syntax ........: _Main()
; Parameters ....: None.
; Return values .: Success - 1.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: Supports two or more input manifests. The final argument/path is always the new output manifest.
; Related .......: __ManifestMerge_GetPaths, _ManifestManagement_MergeMany, __ManifestMerge_Message
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _Main()
	Local $aManifestInputs
	Local $sManifestOut = ''

	__ManifestMerge_GetPaths($aManifestInputs, $sManifestOut)
	If @error Then Exit @error

	For $i = 0 To UBound($aManifestInputs) - 1
		__ManifestMerge_Message('Manifest ' & ($i + 1) & ': ' & $aManifestInputs[$i])
	Next
	__ManifestMerge_Message('Output    : ' & $sManifestOut)

	If Not _ManifestManagement_MergeMany($aManifestInputs, $sManifestOut) Then
		Local $iError = @error
		Local $iExtended = @extended
		__ManifestMerge_Message('ERROR: Manifest merge failed. @error=' & $iError & ' @extended=' & $iExtended, True)
		Exit $iError
	EndIf

	__ManifestMerge_Message('OK: Manifest created: ' & $sManifestOut)

	If Not @Compiled Then
		MsgBox($MB_ICONINFORMATION, 'ManifestMerge', 'Manifest has been created:' & @CRLF & $sManifestOut)
	EndIf

	Return 1
EndFunc   ;==>_Main

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __ManifestMerge_GetPaths
; Description ...: Gets two or more source manifests and a new output manifest path.
; Syntax ........: __ManifestMerge_GetPaths(ByRef $aManifestInputs, ByRef $sManifestOut)
; Parameters ....: $aManifestInputs - Receives a one-dimensional array containing input manifest paths.
;                  $sManifestOut - Receives the full path to the new output manifest.
; Return values .: Success - 1.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: Script mode uses MULTISELECT and requires at least two input manifests.
;                  Compiled mode resolves file-name-only arguments relative to @ScriptDir.
;                  Optional first switch -f makes all following arguments full paths.
;                  The last argument is always the new output manifest.
; Related .......: _ManifestManagement_IsFullPath, __ManifestMerge_Message
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __ManifestMerge_GetPaths(ByRef $aManifestInputs, ByRef $sManifestOut)
	If @Compiled Then
		Local $bFullPaths = False
		Local $iFirstArgument = 1

		If $CmdLine[0] >= 1 And StringLower($CmdLine[1]) = '-f' Then
			$bFullPaths = True
			$iFirstArgument = 2
		EndIf

		Local $iRemainingArguments = $CmdLine[0] - $iFirstArgument + 1
		If $iRemainingArguments < 3 Then
			__ManifestMerge_Message('Usage:' & @CRLF & _
					'  ManifestMerge.exe first.manifest second.manifest [more.manifest ...] result.manifest' & @CRLF & _
					'  ManifestMerge.exe -f "C:\Path\first.manifest" "C:\Path\second.manifest" ["C:\Path\more.manifest" ...] "C:\Path\result.manifest"', True)
			Return SetError(1, $CmdLine[0], 0)
		EndIf

		Local $iInputCount = $iRemainingArguments - 1
		Local $aInputs[$iInputCount]

		For $i = 0 To $iInputCount - 1
			Local $sArgument = $CmdLine[$iFirstArgument + $i]

			If $bFullPaths Then
				If Not _ManifestManagement_IsFullPath($sArgument) Then
					__ManifestMerge_Message('ERROR: -f requires full paths. Invalid input: ' & $sArgument, True)
					Return SetError(2, $i, 0)
				EndIf
				$aInputs[$i] = $sArgument
			Else
				If StringInStr($sArgument, '\') Or StringInStr($sArgument, '/') Or StringInStr($sArgument, ':') Then
					__ManifestMerge_Message('ERROR: Without -f, input arguments must contain file names only: ' & $sArgument, True)
					Return SetError(3, $i, 0)
				EndIf
				$aInputs[$i] = @ScriptDir & '\' & $sArgument
			EndIf
		Next

		Local $sOutputArgument = $CmdLine[$CmdLine[0]]
		If $bFullPaths Then
			If Not _ManifestManagement_IsFullPath($sOutputArgument) Then
				__ManifestMerge_Message('ERROR: -f requires a full output path: ' & $sOutputArgument, True)
				Return SetError(4, 0, 0)
			EndIf
			$sManifestOut = $sOutputArgument
		Else
			If StringInStr($sOutputArgument, '\') Or StringInStr($sOutputArgument, '/') Or StringInStr($sOutputArgument, ':') Then
				__ManifestMerge_Message('ERROR: Without -f, the output argument must contain a file name only: ' & $sOutputArgument, True)
				Return SetError(5, 0, 0)
			EndIf
			$sManifestOut = @ScriptDir & '\' & $sOutputArgument
		EndIf

		$aManifestInputs = $aInputs
	Else
		Local $sSelected = FileOpenDialog('Select at least two manifests to merge', @ScriptDir, _
				'Manifest (*.manifest)|All files (*.*)', BitOR($FD_FILEMUSTEXIST, $FD_MULTISELECT))
		If @error Or $sSelected = '' Then Return SetError(10, 0, 0)

		Local $aSelected = StringSplit($sSelected, '|', $STR_NOCOUNT)
		If Not IsArray($aSelected) Then Return SetError(11, 0, 0)

		If UBound($aSelected) < 3 Then
			__ManifestMerge_Message('ERROR: Select at least two manifest files.', True)
			Return SetError(12, UBound($aSelected), 0)
		EndIf

		Local $sDirectory = $aSelected[0]
		Local $aInputs[UBound($aSelected) - 1]

		For $i = 1 To UBound($aSelected) - 1
			$aInputs[$i - 1] = $sDirectory & '\' & $aSelected[$i]
		Next

		$aManifestInputs = $aInputs

		$sManifestOut = FileSaveDialog('Select a new output manifest', @ScriptDir, _
				'Manifest (*.manifest)|All files (*.*)', $FD_PATHMUSTEXIST, 'Merged.manifest')
		If @error Or $sManifestOut = '' Then Return SetError(13, 0, 0)

		If StringRight(StringLower($sManifestOut), 9) <> '.manifest' Then $sManifestOut &= '.manifest'
	EndIf

	For $i = 0 To UBound($aManifestInputs) - 1
		If Not FileExists($aManifestInputs[$i]) Then
			__ManifestMerge_Message('ERROR: Input manifest does not exist: ' & $aManifestInputs[$i], True)
			Return SetError(20, $i, 0)
		EndIf

		If _ManifestManagement_Path_Equals($aManifestInputs[$i], $sManifestOut) Then
			__ManifestMerge_Message('ERROR: Output manifest must be different from every input manifest.', True)
			Return SetError(21, $i, 0)
		EndIf
	Next

	If FileExists($sManifestOut) Then
		__ManifestMerge_Message('ERROR: Output manifest already exists. Choose a new file name:' & @CRLF & $sManifestOut, True)
		Return SetError(22, 0, 0)
	EndIf

	Return 1
EndFunc   ;==>__ManifestMerge_GetPaths

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __ManifestMerge_Message
; Description ...: Writes a message to the console and optionally shows an error dialog in script mode.
; Syntax ........: __ManifestMerge_Message($sMessage[, $bError = False])
; Parameters ....: $sMessage - Message text.
;                  $bError - True for an error message.
; Return values .: None.
; Author ........: mLipok
; Modified ......:
; Remarks .......: Compiled CUI mode uses the console only. Script mode can additionally display errors in a MsgBox.
; Related .......:
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __ManifestMerge_Message($sMessage, $bError = False)
	ConsoleWrite($sMessage & @CRLF)

	If $bError And Not @Compiled Then
		MsgBox($MB_ICONERROR, "ManifestMerge", $sMessage)
	EndIf
EndFunc
