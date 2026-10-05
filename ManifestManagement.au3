#include-once

#include <AutoItConstants.au3>
#include <FileConstants.au3>
#include <WinAPIProc.au3>

Global Const $__MANIFEST_MANAGEMENT__MSXML = 'Msxml2.DOMDocument.6.0'
Global Const $__MANIFEST_MANAGEMENT__ACTCTX_FLAG_RESOURCE_NAME_VALID = 0x00000008

Global Const $MANIFEST_COMCLASS_PROGID = 0
Global Const $MANIFEST_COMCLASS_CLSID = 1
Global Const $MANIFEST_COMCLASS_DESCRIPTION = 2
Global Const $MANIFEST_COMCLASS_THREADINGMODEL = 3
Global Const $MANIFEST_COMCLASS_TYPELIB_ID = 4
Global Const $MANIFEST_COMCLASS_TYPELIB_VERSION = 5
Global Const $MANIFEST_COMCLASS_COLUMNS = 6

Global Const $MANIFEST_TYPELIB_ID = 0
Global Const $MANIFEST_TYPELIB_VERSION = 1
Global Const $MANIFEST_TYPELIB_PATH = 2
Global Const $MANIFEST_TYPELIB_EMBEDDED = 3
Global Const $MANIFEST_TYPELIB_COLUMNS = 4

; ===============================================================================================================================
; ManifestManagement.au3
; Common functions for creating, merging, activating, and testing Windows manifests.
; Author: mLipok
; ===============================================================================================================================

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_TargetX64_Get
; Description ...: Determines the target architecture from #AutoIt3Wrapper_UseX64 or from the compiled executable.
; Syntax ........: _ManifestManagement_TargetX64_Get()
; Parameters ....: None.
; Return values .: Success - True for x64 or False for x86.
;                  Failure - False and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: In compiled mode @AutoItX64 is authoritative.
; Related .......:
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_TargetX64_Get()
	If @Compiled Then Return @AutoItX64

	Local $hFile = FileOpen(@ScriptFullPath, $FO_READ)
	If $hFile = -1 Then Return SetError(1, 0, False)

	Local $sSource = FileRead($hFile)
	Local $iReadError = @error
	FileClose($hFile)
	If $iReadError Then Return SetError(2, $iReadError, False)

	Local $aMatch = StringRegExp($sSource, '(?im)^\s*#AutoIt3Wrapper_UseX64\s*=\s*([yn])\s*$', $STR_REGEXPARRAYMATCH)
	If @error Or Not IsArray($aMatch) Then Return SetError(3, @error, False)

	Switch StringLower($aMatch[0])
		Case 'y'
			Return True
		Case 'n'
			Return False
	EndSwitch

	Return SetError(4, 0, False)
EndFunc   ;==>_ManifestManagement_TargetX64_Get

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_Regsvr32_Get
; Description ...: Returns the regsvr32.exe path matching the requested COM architecture.
; Syntax ........: _ManifestManagement_Regsvr32_Get($bX64)
; Parameters ....: $bX64 - True for x64, False for x86.
; Return values .: Success - Full path to regsvr32.exe.
;                  Failure - Empty string and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: On 64-bit Windows, SysWOW64 contains the 32-bit regsvr32.exe.
; Related .......: _ManifestManagement_Regsvr32_Run
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_Regsvr32_Get($bX64)
	Local $sPath

	If @OSArch = 'X64' Then
		$sPath = @WindowsDir & ($bX64 ? '\System32\regsvr32.exe' : '\SysWOW64\regsvr32.exe')
	Else
		If $bX64 Then Return SetError(1, 0, '')
		$sPath = @SystemDir & '\regsvr32.exe'
	EndIf

	If Not FileExists($sPath) Then Return SetError(2, 0, '')
	Return $sPath
EndFunc   ;==>_ManifestManagement_Regsvr32_Get

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_Regsvr32_Run
; Description ...: Registers or unregisters a COM DLL using regsvr32.exe.
; Syntax ........: _ManifestManagement_Regsvr32_Run($sRegsvr32, $sDLLPath, $bUnregister)
; Parameters ....: $sRegsvr32 - Full path to regsvr32.exe.
;                  $sDLLPath - Full path to the COM DLL.
;                  $bUnregister - True to unregister, False to register.
; Return values .: Success - 1.
;                  Failure - 0 and sets @error; @extended contains the process exit code when available.
; Author ........: mLipok
; Modified ......:
; Remarks .......: Uses silent regsvr32 mode.
; Related .......: _ManifestManagement_Regsvr32_Get
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_Regsvr32_Run($sRegsvr32, $sDLLPath, $bUnregister)
	Local $sParameters = '/s '
	If $bUnregister Then $sParameters &= '/u '
	$sParameters &= '"' & $sDLLPath & '"'

	Local $iExitCode = RunWait('"' & $sRegsvr32 & '" ' & $sParameters, '', @SW_HIDE)
	If @error Then Return SetError(1, @error, 0)
	If $iExitCode <> 0 Then Return SetError(2, $iExitCode, 0)

	Return 1
EndFunc   ;==>_ManifestManagement_Regsvr32_Run

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_COMInfo_Get
; Description ...: Creates and verifies a COM object and collects manifest-related information.
; Syntax ........: _ManifestManagement_COMInfo_Get($sDLLPath[, $sProgID = ''[, $sDialogTitle = 'ManifestCreator']])
; Parameters ....: $sDLLPath - Full path to the selected COM DLL.
;                  $sProgID - Optional known ProgID.
;                  $sDialogTitle - Dialog title used if multiple COM classes are discovered.
; Return values .: Success - Array: ProgID, CLSID, IID, ObjFile, Description, ThreadingModel, TypeLibID, TypeLibVersion.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: ObjName($oObject, $OBJ_FILE) must resolve to the selected DLL.
; Related .......: _ManifestManagement_Path_Equals
; Link ..........: https://www.autoitscript.com/autoit3/docs/functions/ObjName.htm
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_COMInfo_Get($sDLLPath, $sProgID = '', $sDialogTitle = 'ManifestCreator')
	If $sProgID = '' Then
		$sProgID = __ManifestManagement__ProgID_FindByDLL($sDLLPath, $sDialogTitle)
		If @error Or $sProgID = '' Then Return SetError(1, @extended, 0)
	EndIf

	; Error monitoring. This will trap all COM errors while alive.
	; This particular object is declared as local, meaning after the function returns it will not exist.
	Local $__ManifestManagement_COM_Handler = ObjEvent('AutoIt.Error', __ManifestManagement__COM_Error)
	#forceref $__ManifestManagement_COM_Handler

	Local $oObject = ObjCreate($sProgID)
	If Not IsObj($oObject) Then Return SetError(2, 0, 0)

	Local $sActualProgID = ObjName($oObject, $OBJ_PROGID)
	If @error Or $sActualProgID = '' Then $sActualProgID = $sProgID

	Local $sObjFile = ObjName($oObject, $OBJ_FILE)
	If @error Or $sObjFile = '' Then Return SetError(3, @error, 0)
	$sObjFile = _ManifestManagement_Path_Normalize($sObjFile)

	Local $sCLSID = ObjName($oObject, $OBJ_CLSID)
	If @error Or $sCLSID = '' Then Return SetError(4, @error, 0)

	Local $sIID = ObjName($oObject, $OBJ_IID)
	If @error Then $sIID = ''

	Local $sDescription = ObjName($oObject, $OBJ_NAME)
	If @error Then $sDescription = ''

	If Not _ManifestManagement_Path_Equals($sObjFile, $sDLLPath) Then Return SetError(5, 0, 0)

	Local $sCLSIDKey = 'HKEY_CLASSES_ROOT\CLSID\' & $sCLSID
	Local $sThreadingModel = RegRead($sCLSIDKey & '\InprocServer32', 'ThreadingModel')
	If @error Then $sThreadingModel = ''

	Local $sTypeLibID = RegRead($sCLSIDKey & '\TypeLib', '')
	If @error Then $sTypeLibID = ''

	Local $sTypeLibVersion = RegRead($sCLSIDKey & '\Version', '')
	If @error Then $sTypeLibVersion = ''

	Local $aResult[8]
	$aResult[0] = $sActualProgID
	$aResult[1] = $sCLSID
	$aResult[2] = $sIID
	$aResult[3] = $sObjFile
	$aResult[4] = $sDescription
	$aResult[5] = $sThreadingModel
	$aResult[6] = $sTypeLibID
	$aResult[7] = $sTypeLibVersion

	$oObject = 0
	Return $aResult
EndFunc   ;==>_ManifestManagement_COMInfo_Get


; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_COMClasses_Get
; Description ...: Discovers all registered in-process COM classes whose InprocServer32 points to the selected DLL.
; Syntax ........: _ManifestManagement_COMClasses_Get($sDLLPath)
; Parameters ....: $sDLLPath - Full path to the selected COM DLL.
; Return values .: Success - 2D array containing ProgID, CLSID, description, ThreadingModel, TypeLib GUID and TypeLib version.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: Call this function while the DLL is temporarily registered with the architecture-matching regsvr32.exe.
;                  Classes without a ProgID are still returned and can be activated by CLSID-aware clients.
;                  Displays an activity progress bar while scanning HKCR\CLSID and writes scan counters to the console.
; Related .......: _ManifestManagement_COMInfo_Get, _ManifestManagement_TypeLibs_Get, _ManifestManagement_Path_Equals
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_COMClasses_Get($sDLLPath)
	Local $aClasses[1][$MANIFEST_COMCLASS_COLUMNS]
	Local $iCount = 0
	Local $iIndex = 1
	Local $iChecked = 0
	Local $iProgress = 0

	ProgressOn('ManifestCreator', 'Scanning registered COM classes...', _
			'Preparing registry scan...', Default, Default, $DLG_MOVEABLE)

	While 1
		Local $sCLSID = RegEnumKey('HKEY_CLASSES_ROOT\CLSID', $iIndex)
		If @error Then ExitLoop

		$iIndex += 1
		$iChecked += 1

		; The total number of CLSID keys is not known in advance without scanning the registry twice.
		; Use a cyclic activity indicator instead of a percentage-complete value.
		$iProgress += 1
		If $iProgress > 100 Then $iProgress = 1

		If Mod($iChecked, 25) = 0 Then
			ProgressSet($iProgress, _
					'Registry CLSID checked: ' & $iChecked & @CRLF & _
					'COM classes matching DLL: ' & $iCount, _
					'Scanning registered COM classes...')
		EndIf

		If Mod($iChecked, 500) = 0 Then
			ConsoleWrite('[ManifestManagement] CLSID scan: checked=' & $iChecked & _
					' matched=' & $iCount & @CRLF)
		EndIf

		Local $sCLSIDKey = 'HKEY_CLASSES_ROOT\CLSID\' & $sCLSID
		Local $sServerPath = RegRead($sCLSIDKey & '\InprocServer32', '')
		If @error Or $sServerPath = '' Then ContinueLoop
		If Not _ManifestManagement_Path_Equals($sServerPath, $sDLLPath) Then ContinueLoop

		Local $sProgID = RegRead($sCLSIDKey & '\ProgID', '')
		If @error Then $sProgID = ''

		Local $sDescription = RegRead($sCLSIDKey, '')
		If @error Then $sDescription = ''

		Local $sThreadingModel = RegRead($sCLSIDKey & '\InprocServer32', 'ThreadingModel')
		If @error Then $sThreadingModel = ''

		Local $sTypeLibID = RegRead($sCLSIDKey & '\TypeLib', '')
		If @error Then $sTypeLibID = ''

		Local $sTypeLibVersion = RegRead($sCLSIDKey & '\Version', '')
		If @error Then $sTypeLibVersion = ''

		ReDim $aClasses[$iCount + 1][$MANIFEST_COMCLASS_COLUMNS]
		$aClasses[$iCount][$MANIFEST_COMCLASS_PROGID] = $sProgID
		$aClasses[$iCount][$MANIFEST_COMCLASS_CLSID] = $sCLSID
		$aClasses[$iCount][$MANIFEST_COMCLASS_DESCRIPTION] = $sDescription
		$aClasses[$iCount][$MANIFEST_COMCLASS_THREADINGMODEL] = $sThreadingModel
		$aClasses[$iCount][$MANIFEST_COMCLASS_TYPELIB_ID] = $sTypeLibID
		$aClasses[$iCount][$MANIFEST_COMCLASS_TYPELIB_VERSION] = $sTypeLibVersion
		$iCount += 1

		ProgressSet($iProgress, _
				'Registry CLSID checked: ' & $iChecked & @CRLF & _
				'COM classes matching DLL: ' & $iCount, _
				'Scanning registered COM classes...')
	WEnd

	ProgressOff()

	ConsoleWrite('[ManifestManagement] CLSID scan finished: checked=' & $iChecked & _
			' matched=' & $iCount & @CRLF)

	If $iCount = 0 Then Return SetError(1, $iChecked, 0)
	Return $aClasses
EndFunc   ;==>_ManifestManagement_COMClasses_Get

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_COMClass_FindByProgID
; Description ...: Finds a COM class row by ProgID.
; Syntax ........: _ManifestManagement_COMClass_FindByProgID(ByRef $aClasses, $sProgID)
; Parameters ....: $aClasses - 2D array returned by _ManifestManagement_COMClasses_Get().
;                  $sProgID - ProgID to find.
; Return values .: Success - Zero-based class row index.
;                  Failure - -1 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: Comparison is case-insensitive.
; Related .......: _ManifestManagement_COMClasses_Get
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_COMClass_FindByProgID(ByRef $aClasses, $sProgID)
	If Not IsArray($aClasses) Then Return SetError(1, 0, -1)
	If UBound($aClasses, 0) <> 2 Or UBound($aClasses, 2) < $MANIFEST_COMCLASS_COLUMNS Then Return SetError(2, 0, -1)

	For $i = 0 To UBound($aClasses) - 1
		If StringLower($aClasses[$i][$MANIFEST_COMCLASS_PROGID]) = StringLower($sProgID) Then Return $i
	Next

	Return SetError(3, 0, -1)
EndFunc   ;==>_ManifestManagement_COMClass_FindByProgID

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_COMClass_TestProgID_Get
; Description ...: Selects the ProgID used by the generated runtime test.
; Syntax ........: _ManifestManagement_COMClass_TestProgID_Get(ByRef $aClasses[, $sPreferredProgID = ''])
; Parameters ....: $aClasses - 2D array returned by _ManifestManagement_COMClasses_Get().
;                  $sPreferredProgID - Optional user-selected ProgID.
; Return values .: Success - ProgID.
;                  Failure - Empty string and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: If no preferred ProgID is supplied, the first discovered class that has a ProgID is used.
; Related .......: _ManifestManagement_COMClasses_Get, _ManifestManagement_COMClass_FindByProgID
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_COMClass_TestProgID_Get(ByRef $aClasses, $sPreferredProgID = '')
	If Not IsArray($aClasses) Then Return SetError(1, 0, '')

	If $sPreferredProgID <> '' Then
		Local $iPreferred = _ManifestManagement_COMClass_FindByProgID($aClasses, $sPreferredProgID)
		If @error Or $iPreferred < 0 Then Return SetError(2, 0, '')
		Return $aClasses[$iPreferred][$MANIFEST_COMCLASS_PROGID]
	EndIf

	For $i = 0 To UBound($aClasses) - 1
		If $aClasses[$i][$MANIFEST_COMCLASS_PROGID] <> '' Then Return $aClasses[$i][$MANIFEST_COMCLASS_PROGID]
	Next

	Return SetError(3, 0, '')
EndFunc   ;==>_ManifestManagement_COMClass_TestProgID_Get

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_TypeLibs_Get
; Description ...: Builds a unique list of Type Libraries referenced by discovered COM classes and resolves their registered paths.
; Syntax ........: _ManifestManagement_TypeLibs_Get(ByRef $aClasses, $sDLLPath, $bTargetX64)
; Parameters ....: $aClasses - 2D array returned by _ManifestManagement_COMClasses_Get().
;                  $sDLLPath - Full path to the selected COM DLL.
;                  $bTargetX64 - True for x64 registration, False for x86 registration.
; Return values .: Success - 2D array containing TypeLib GUID, version, path and embedded flag.
;                  No TypeLib references - 0 with @error = 0.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: Duplicate TypeLib GUID/version pairs are returned only once.
; Related .......: _ManifestManagement_COMClasses_Get, _ManifestManagement_TypeLibPath_Get, _ManifestManagement_Path_Equals
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_TypeLibs_Get(ByRef $aClasses, $sDLLPath, $bTargetX64)
	If Not IsArray($aClasses) Then Return SetError(1, 0, 0)

	Local $aTypeLibs[1][$MANIFEST_TYPELIB_COLUMNS]
	Local $iCount = 0

	For $iClass = 0 To UBound($aClasses) - 1
		Local $sTypeLibID = $aClasses[$iClass][$MANIFEST_COMCLASS_TYPELIB_ID]
		Local $sTypeLibVersion = $aClasses[$iClass][$MANIFEST_COMCLASS_TYPELIB_VERSION]

		If $sTypeLibID = '' Or $sTypeLibVersion = '' Then ContinueLoop

		Local $bExists = False
		For $iTypeLib = 0 To $iCount - 1
			If StringLower($aTypeLibs[$iTypeLib][$MANIFEST_TYPELIB_ID]) = StringLower($sTypeLibID) And _
					StringLower($aTypeLibs[$iTypeLib][$MANIFEST_TYPELIB_VERSION]) = StringLower($sTypeLibVersion) Then
				$bExists = True
				ExitLoop
			EndIf
		Next
		If $bExists Then ContinueLoop

		Local $sTypeLibPath = _ManifestManagement_TypeLibPath_Get($sTypeLibID, $sTypeLibVersion, $bTargetX64)
		If @error Then $sTypeLibPath = ''

		ReDim $aTypeLibs[$iCount + 1][$MANIFEST_TYPELIB_COLUMNS]
		$aTypeLibs[$iCount][$MANIFEST_TYPELIB_ID] = $sTypeLibID
		$aTypeLibs[$iCount][$MANIFEST_TYPELIB_VERSION] = $sTypeLibVersion
		$aTypeLibs[$iCount][$MANIFEST_TYPELIB_PATH] = $sTypeLibPath
		$aTypeLibs[$iCount][$MANIFEST_TYPELIB_EMBEDDED] = ($sTypeLibPath <> '' And _ManifestManagement_Path_Equals($sTypeLibPath, $sDLLPath))
		$iCount += 1
	Next

	If $iCount = 0 Then Return 0
	Return $aTypeLibs
EndFunc   ;==>_ManifestManagement_TypeLibs_Get


; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_TypeLibPath_Get
; Description ...: Resolves the registered Type Library file path for a TypeLib GUID and version.
; Syntax ........: _ManifestManagement_TypeLibPath_Get($sTypeLibID, $sTypeLibVersion, $bTargetX64)
; Parameters ....: $sTypeLibID - Registered TypeLib GUID.
;                  $sTypeLibVersion - Registered TypeLib version.
;                  $bTargetX64 - True for x64 registration, False for x86 registration.
; Return values .: Success - Registered Type Library path.
;                  Failure - Empty string and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: Prefers win64 for x64 and win32 for x86, then checks the other platform as a fallback.
;                  Locale subkeys are enumerated instead of assuming locale 0 only.
; Related .......: _ManifestManagement_COMInfo_Get, _ManifestManagement_Path_Normalize
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_TypeLibPath_Get($sTypeLibID, $sTypeLibVersion, $bTargetX64)
	If $sTypeLibID = '' Or $sTypeLibVersion = '' Then Return SetError(1, 0, '')

	Local $sBaseKey = 'HKEY_CLASSES_ROOT\TypeLib\' & $sTypeLibID & '\' & $sTypeLibVersion
	Local $sPreferredPlatform = ($bTargetX64 ? 'win64' : 'win32')
	Local $sFallbackPlatform = ($bTargetX64 ? 'win32' : 'win64')

	Local $sPath = __ManifestManagement__TypeLibPath_FindInLocales($sBaseKey, $sPreferredPlatform)
	If $sPath <> '' Then Return _ManifestManagement_Path_Normalize($sPath)

	$sPath = __ManifestManagement__TypeLibPath_FindInLocales($sBaseKey, $sFallbackPlatform)
	If $sPath <> '' Then Return _ManifestManagement_Path_Normalize($sPath)

	Return SetError(2, 0, '')
EndFunc   ;==>_ManifestManagement_TypeLibPath_Get

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_Manifest_Build
; Description ...: Builds Registration-Free COM manifest XML for one COM class.
; Syntax ........: _ManifestManagement_Manifest_Build($sDLLName, $sTLBPath, $sArchitecture, $sProgID, $sCLSID, $sIID, $sDescription, $sThreadingModel, $sTypeLibID, $sTypeLibVersion)
; Parameters ....: $sDLLName - COM DLL file name without path.
;                  $sTLBPath - Optional external TLB path.
;                  $sArchitecture - "x86" or "x64".
;                  $sProgID - COM ProgID.
;                  $sCLSID - COM CLSID.
;                  $sIID - Default interface IID returned by ObjName().
;                  $sDescription - COM description.
;                  $sThreadingModel - Registered ThreadingModel value.
;                  $sTypeLibID - Registered TypeLib GUID.
;                  $sTypeLibVersion - Registered TypeLib version.
; Return values .: Manifest XML text.
; Author ........: mLipok
; Modified ......:
; Remarks .......: Compatibility wrapper for older callers. New code should use _ManifestManagement_Manifest_BuildClasses().
; Related .......: _ManifestManagement_Manifest_BuildClasses
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_Manifest_Build($sDLLName, $sTLBPath, $sArchitecture, $sProgID, $sCLSID, $sIID, $sDescription, $sThreadingModel, $sTypeLibID, $sTypeLibVersion)
	Local $aClasses[1][$MANIFEST_COMCLASS_COLUMNS]
	$aClasses[0][$MANIFEST_COMCLASS_PROGID] = $sProgID
	$aClasses[0][$MANIFEST_COMCLASS_CLSID] = $sCLSID
	$aClasses[0][$MANIFEST_COMCLASS_DESCRIPTION] = $sDescription
	$aClasses[0][$MANIFEST_COMCLASS_THREADINGMODEL] = $sThreadingModel
	$aClasses[0][$MANIFEST_COMCLASS_TYPELIB_ID] = $sTypeLibID
	$aClasses[0][$MANIFEST_COMCLASS_TYPELIB_VERSION] = $sTypeLibVersion

	Local $vTypeLibs = 0
	If $sTypeLibID <> '' And $sTypeLibVersion <> '' Then
		Local $aTypeLibs[1][$MANIFEST_TYPELIB_COLUMNS]
		$aTypeLibs[0][$MANIFEST_TYPELIB_ID] = $sTypeLibID
		$aTypeLibs[0][$MANIFEST_TYPELIB_VERSION] = $sTypeLibVersion
		$aTypeLibs[0][$MANIFEST_TYPELIB_PATH] = $sTLBPath
		$aTypeLibs[0][$MANIFEST_TYPELIB_EMBEDDED] = ($sTLBPath = '')
		$vTypeLibs = $aTypeLibs
	EndIf

	Local $sResult = _ManifestManagement_Manifest_BuildClasses($sDLLName, $sArchitecture, $aClasses, $vTypeLibs, $sIID)
	Local $iError = @error
	Local $iExtended = @extended
	Return SetError($iError, $iExtended, $sResult)
EndFunc   ;==>_ManifestManagement_Manifest_Build

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_Manifest_BuildClasses
; Description ...: Builds Registration-Free COM manifest XML for all COM classes discovered in one DLL.
; Syntax ........: _ManifestManagement_Manifest_BuildClasses($sDLLName, $sArchitecture, ByRef $aClasses, $vTypeLibs[, $sTestIID = ''])
; Parameters ....: $sDLLName - COM DLL file name without path.
;                  $sArchitecture - "x86" or "x64".
;                  $aClasses - 2D array returned by _ManifestManagement_COMClasses_Get().
;                  $vTypeLibs - 2D array returned by _ManifestManagement_TypeLibs_Get(), or 0 if none were discovered.
;                  $sTestIID - Optional IID returned by ObjName() for the test class, stored as an informational XML comment.
; Return values .: Success - Manifest XML text.
;                  Failure - Empty string and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: Every discovered CLSID is emitted as a separate <comClass> entry.
; Related .......: _ManifestManagement_COMClasses_Get, _ManifestManagement_TypeLibs_Get
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_Manifest_BuildClasses($sDLLName, $sArchitecture, ByRef $aClasses, $vTypeLibs, $sTestIID = '')
	If Not IsArray($aClasses) Then Return SetError(1, 0, '')
	If UBound($aClasses, 0) <> 2 Or UBound($aClasses, 2) < $MANIFEST_COMCLASS_COLUMNS Then Return SetError(2, 0, '')

	Local $sAssemblyName = StringRegExpReplace($sDLLName, '(?i)\.dll$', '') & '.RegFreeCOM.' & $sArchitecture
	Local $sXML = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' & @CRLF & _
			'<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">' & @CRLF & _
			'  <assemblyIdentity' & @CRLF & _
			'      type="win32"' & @CRLF & _
			'      name="' & __ManifestManagement__XML_Escape($sAssemblyName) & '"' & @CRLF & _
			'      version="1.0.0.0"' & @CRLF & _
			'      processorArchitecture="' & $sArchitecture & '" />' & @CRLF & _
			'  <!-- COM classes discovered from temporary DLL registration: ' & UBound($aClasses) & ' -->' & @CRLF

	If $sTestIID <> '' Then
		$sXML &= '  <!-- IID returned by ObjName() for the generated test class: ' & __ManifestManagement__XML_Comment_Escape($sTestIID) & ' -->' & @CRLF
	EndIf

	$sXML &= '  <file name="' & __ManifestManagement__XML_Escape($sDLLName) & '">' & @CRLF

	For $i = 0 To UBound($aClasses) - 1
		Local $sProgID = $aClasses[$i][$MANIFEST_COMCLASS_PROGID]
		Local $sCLSID = _ManifestManagement_GUID_Normalize($aClasses[$i][$MANIFEST_COMCLASS_CLSID])
		If @error Then Return SetError(3, $i, '')
		Local $sDescription = $aClasses[$i][$MANIFEST_COMCLASS_DESCRIPTION]
		Local $sThreadingModel = $aClasses[$i][$MANIFEST_COMCLASS_THREADINGMODEL]
		Local $sTypeLibID = _ManifestManagement_GUID_Normalize($aClasses[$i][$MANIFEST_COMCLASS_TYPELIB_ID])
		If @error Then Return SetError(4, $i, '')

		Local $sAttributes = ' clsid="' & __ManifestManagement__XML_Escape($sCLSID) & '"'
		If $sProgID <> '' Then $sAttributes &= ' progid="' & __ManifestManagement__XML_Escape($sProgID) & '"'
		If $sDescription <> '' Then $sAttributes &= ' description="' & __ManifestManagement__XML_Escape($sDescription) & '"'
		If $sThreadingModel <> '' Then $sAttributes &= ' threadingModel="' & __ManifestManagement__XML_Escape($sThreadingModel) & '"'
		If $sTypeLibID <> '' Then $sAttributes &= ' tlbid="' & __ManifestManagement__XML_Escape($sTypeLibID) & '"'

		$sXML &= '    <comClass' & $sAttributes & ' />' & @CRLF
	Next

	If IsArray($vTypeLibs) Then
		For $i = 0 To UBound($vTypeLibs) - 1
			If Not $vTypeLibs[$i][$MANIFEST_TYPELIB_EMBEDDED] Then ContinueLoop
			Local $sEmbeddedTLBID = _ManifestManagement_GUID_Normalize($vTypeLibs[$i][$MANIFEST_TYPELIB_ID])
			If @error Or $sEmbeddedTLBID = '' Then Return SetError(5, $i, '')
			$sXML &= '    <typelib tlbid="' & __ManifestManagement__XML_Escape($sEmbeddedTLBID) & _
					'" version="' & __ManifestManagement__XML_Escape($vTypeLibs[$i][$MANIFEST_TYPELIB_VERSION]) & _
					'" helpdir="" />' & @CRLF
		Next
	EndIf

	$sXML &= '  </file>' & @CRLF

	If IsArray($vTypeLibs) Then
		For $i = 0 To UBound($vTypeLibs) - 1
			If $vTypeLibs[$i][$MANIFEST_TYPELIB_EMBEDDED] Then ContinueLoop
			If $vTypeLibs[$i][$MANIFEST_TYPELIB_PATH] = '' Then ContinueLoop

			Local $sTLBName = StringRegExpReplace($vTypeLibs[$i][$MANIFEST_TYPELIB_PATH], '^.*\\', '')
			Local $sExternalTLBID = _ManifestManagement_GUID_Normalize($vTypeLibs[$i][$MANIFEST_TYPELIB_ID])
			If @error Or $sExternalTLBID = '' Then Return SetError(6, $i, '')
			$sXML &= '  <file name="' & __ManifestManagement__XML_Escape($sTLBName) & '">' & @CRLF & _
					'    <typelib tlbid="' & __ManifestManagement__XML_Escape($sExternalTLBID) & _
					'" version="' & __ManifestManagement__XML_Escape($vTypeLibs[$i][$MANIFEST_TYPELIB_VERSION]) & _
					'" helpdir="" />' & @CRLF & _
					'  </file>' & @CRLF
		Next
	EndIf

	$sXML &= '</assembly>' & @CRLF
	Local $sValidationReason = ''
	If Not _ManifestManagement_Manifest_Validate($sXML, $sValidationReason) Then Return SetError(7, @error, '')
	Return $sXML
EndFunc   ;==>_ManifestManagement_Manifest_BuildClasses

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_GUID_Normalize
; Description ...: Returns a strict braced GUID for Windows manifests. An empty optional GUID remains empty.
; ===============================================================================================================================
Func _ManifestManagement_GUID_Normalize($sGUID)
	$sGUID = StringStripWS($sGUID, 3)
	If $sGUID = '' Then Return ''
	If StringLeft($sGUID, 1) = '{' And StringRight($sGUID, 1) = '}' Then $sGUID = StringMid($sGUID, 2, StringLen($sGUID) - 2)
	If Not StringRegExp($sGUID, '(?i)^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$') Then Return SetError(1, 0, '')
	Return '{' & StringUpper($sGUID) & '}'
EndFunc   ;==>_ManifestManagement_GUID_Normalize

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_Manifest_Validate
; Description ...: Checks XML syntax and the manifest fields used by generated RegFree COM assemblies.
; Parameters ....: $sXML - Manifest XML text; $sReason - human readable error; $sBaseDir - optional referenced-file directory.
; Return values .: Success - 1; failure - 0 with @error set.
; Remarks .......: Windows CreateActCtxW remains the authority for complete SxS schema validation.
; ===============================================================================================================================
Func _ManifestManagement_Manifest_Validate($sXML, ByRef $sReason, $sBaseDir = '')
	$sReason = ''
	Local $oDoc = ObjCreate($__MANIFEST_MANAGEMENT__MSXML)
	If Not IsObj($oDoc) Then Return SetError(1, 0, 0)
	$oDoc.async = False
	$oDoc.resolveExternals = False
	$oDoc.validateOnParse = False
	$oDoc.setProperty('SelectionLanguage', 'XPath')
	If Not $oDoc.loadXML($sXML) Then
		$sReason = 'Invalid XML: ' & $oDoc.parseError.reason
		Return SetError(2, $oDoc.parseError.errorCode, 0)
	EndIf
	Local $oRoot = $oDoc.documentElement
	If Not IsObj($oRoot) Then
		$sReason = 'Manifest has no document element.'
		Return SetError(3, 0, 0)
	EndIf
	If $oRoot.baseName <> 'assembly' Or $oRoot.namespaceURI <> 'urn:schemas-microsoft-com:asm.v1' Then
		$sReason = 'Expected an assembly element in the Windows assembly namespace.'
		Return SetError(3, 0, 0)
	EndIf
	If $oRoot.getAttribute('manifestVersion') <> '1.0' Then
		$sReason = 'Missing or unsupported manifestVersion.'
		Return SetError(4, 0, 0)
	EndIf
	Local $oIdentity = $oRoot.selectSingleNode('./*[local-name()="assemblyIdentity"]')
	If Not IsObj($oIdentity) Then
		$sReason = 'Missing assemblyIdentity.'
		Return SetError(5, 0, 0)
	EndIf
	If String($oIdentity.getAttribute('name')) = '' Or String($oIdentity.getAttribute('version')) = '' Then
		$sReason = 'Missing assemblyIdentity name or version.'
		Return SetError(5, 0, 0)
	EndIf
	For $oFile In $oRoot.selectNodes('./*[local-name()="file"]')
		Local $sName = String($oFile.getAttribute('name'))
		If $sName = '' Or StringInStr($sName, '\') Or StringInStr($sName, '/') Then
			$sReason = 'Invalid file name in manifest: ' & $sName
			Return SetError(6, 0, 0)
		EndIf
		If $sBaseDir <> '' And Not FileExists($sBaseDir & '\' & $sName) Then
			$sReason = 'Manifest references a missing file: ' & $sName
			Return SetError(7, 0, 0)
		EndIf
		For $oClass In $oFile.selectNodes('./*[local-name()="comClass"]')
			Local $sCLSID = String($oClass.getAttribute('clsid'))
			If $sCLSID = '' Or _ManifestManagement_GUID_Normalize($sCLSID) <> $sCLSID Then
				$sReason = 'Invalid comClass CLSID: ' & $sCLSID
				Return SetError(8, 0, 0)
			EndIf
			Local $sTLBID = String($oClass.getAttribute('tlbid'))
			If $sTLBID <> '' And _ManifestManagement_GUID_Normalize($sTLBID) <> $sTLBID Then
				$sReason = 'Invalid comClass TypeLib GUID: ' & $sTLBID
				Return SetError(9, 0, 0)
			EndIf
		Next
		For $oTypeLib In $oFile.selectNodes('./*[local-name()="typelib"]')
			Local $sTypeLibGUID = String($oTypeLib.getAttribute('tlbid'))
			If $sTypeLibGUID = '' Or _ManifestManagement_GUID_Normalize($sTypeLibGUID) <> $sTypeLibGUID Then
				$sReason = 'Invalid typelib GUID: ' & $sTypeLibGUID
				Return SetError(10, 0, 0)
			EndIf
		Next
	Next
	Return 1
EndFunc   ;==>_ManifestManagement_Manifest_Validate

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_TestScript_CreateFromTemplate
; Description ...: Creates a Registration-Free COM test script from ManifestTestingTemplate.au3.
; Syntax ........: _ManifestManagement_TestScript_CreateFromTemplate($sTemplatePath, $sDestinationPath, $sArchitecture, $sProgID, $sDLLName, $sManifestName, $sCLSID, $sIID[, $iResourceID = 101])
; Parameters ....: $sTemplatePath - Full path to the template.
;                  $sDestinationPath - Full path of the generated test script.
;                  $sArchitecture - "x86" or "x64".
;                  $sProgID - COM ProgID.
;                  $sDLLName - COM DLL file name.
;                  $sManifestName - Generated manifest file name.
;                  $sCLSID - COM CLSID.
;                  $sIID - Default interface IID.
;                  $iResourceID - RT_MANIFEST resource identifier.
; Return values .: Success - 1.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: Copies the template first, then modifies only the copied file.
; Related .......: _ManifestManagement_File_WriteUTF8
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_TestScript_CreateFromTemplate($sTemplatePath, $sDestinationPath, $sArchitecture, $sProgID, $sDLLName, $sManifestName, $sCLSID, $sIID, $iResourceID = 101)
	If Not FileExists($sTemplatePath) Then Return SetError(1, 0, 0)
	If Not FileCopy($sTemplatePath, $sDestinationPath, $FC_OVERWRITE) Then Return SetError(2, @error, 0)

	Local $hFile = FileOpen($sDestinationPath, $FO_READ)
	If $hFile = -1 Then Return SetError(3, 0, 0)

	Local $sCode = FileRead($hFile)
	Local $iReadError = @error
	FileClose($hFile)
	If $iReadError Then Return SetError(4, $iReadError, 0)

	Local $sUseX64 = ($sArchitecture = 'x64' ? 'y' : 'n')
	Local $sOutFile = StringRegExpReplace($sDLLName, '(?i)\.dll$', '') & '_RegFreeCOM_Test_' & $sArchitecture & '.exe'

	$sCode = StringReplace($sCode, '{{USE_X64}}', $sUseX64)
	$sCode = StringReplace($sCode, '{{OUT_FILE}}', $sOutFile)
	$sCode = StringReplace($sCode, '{{MANIFEST_RESOURCE_ID}}', String($iResourceID))
	$sCode = StringReplace($sCode, '{{PROGID}}', __ManifestManagement__AutoIt_String($sProgID))
	$sCode = StringReplace($sCode, '{{CLSID}}', __ManifestManagement__AutoIt_String($sCLSID))
	$sCode = StringReplace($sCode, '{{IID}}', __ManifestManagement__AutoIt_String($sIID))
	$sCode = StringReplace($sCode, '{{DLL_NAME}}', __ManifestManagement__AutoIt_String($sDLLName))
	$sCode = StringReplace($sCode, '{{MANIFEST_NAME}}', __ManifestManagement__AutoIt_String($sManifestName))
	$sCode = StringReplace($sCode, '{{MANIFEST_RESOURCE_FILE}}', $sManifestName)

	If StringInStr($sCode, '{{') Or StringInStr($sCode, '}}') Then Return SetError(5, 0, 0)
	If Not _ManifestManagement_File_WriteUTF8($sDestinationPath, $sCode) Then Return SetError(6, @extended, 0)

	Return 1
EndFunc   ;==>_ManifestManagement_TestScript_CreateFromTemplate

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_Merge
; Description ...: Merges exactly two Windows assembly manifests into one output manifest.
; Syntax ........: _ManifestManagement_Merge($sManifest1, $sManifest2, $sManifestOut)
; Parameters ....: $sManifest1 - Full path to the base manifest.
;                  $sManifest2 - Full path to the second manifest.
;                  $sManifestOut - Full path to a new output manifest.
; Return values .: Success - 1.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: Compatibility wrapper around _ManifestManagement_MergeMany().
; Related .......: _ManifestManagement_MergeMany
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_Merge($sManifest1, $sManifest2, $sManifestOut)
	Local $aManifestInputs[2] = [$sManifest1, $sManifest2]
	Return _ManifestManagement_MergeMany($aManifestInputs, $sManifestOut)
EndFunc   ;==>_ManifestManagement_Merge

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_MergeMany
; Description ...: Merges two or more Windows assembly manifests into one output manifest.
; Syntax ........: _ManifestManagement_MergeMany(ByRef $aManifestInputs, $sManifestOut)
; Parameters ....: $aManifestInputs - One-dimensional array containing at least two input manifest paths.
;                  $sManifestOut - Full path to a new output manifest.
; Return values .: Success - 1.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: The assemblyIdentity from the first manifest is preserved. Later assemblyIdentity elements are skipped.
;                  Existing output files are never overwritten.
; Related .......: _ManifestManagement_Merge
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_MergeMany(ByRef $aManifestInputs, $sManifestOut)
	If Not IsArray($aManifestInputs) Then Return SetError(1, 0, 0)
	If UBound($aManifestInputs, 0) <> 1 Then Return SetError(2, 0, 0)
	If UBound($aManifestInputs) < 2 Then Return SetError(3, UBound($aManifestInputs), 0)
	If FileExists($sManifestOut) Then Return SetError(4, 0, 0)

	For $i = 0 To UBound($aManifestInputs) - 1
		If Not FileExists($aManifestInputs[$i]) Then Return SetError(5, $i, 0)
		If _ManifestManagement_Path_Equals($aManifestInputs[$i], $sManifestOut) Then Return SetError(6, $i, 0)
	Next

	Local $oBase = __ManifestManagement__XML_Load($aManifestInputs[0])
	If @error Then Return SetError(10, @extended, 0)

	Local $oOut = ObjCreate($__MANIFEST_MANAGEMENT__MSXML)
	If Not IsObj($oOut) Then Return SetError(11, 0, 0)

	$oOut.async = False
	$oOut.preserveWhiteSpace = True
	$oOut.resolveExternals = False
	$oOut.validateOnParse = False

	If Not $oOut.loadXML($oBase.xml) Then Return SetError(12, $oOut.parseError.errorCode, 0)

	Local $oRootOut = $oOut.documentElement
	If Not IsObj($oRootOut) Or StringLower($oRootOut.baseName) <> 'assembly' Then Return SetError(13, 0, 0)

	For $iManifest = 1 To UBound($aManifestInputs) - 1
		Local $oInput = __ManifestManagement__XML_Load($aManifestInputs[$iManifest])
		If @error Then Return SetError(20 + $iManifest, @extended, 0)

		Local $oRootInput = $oInput.documentElement
		If Not IsObj($oRootInput) Or StringLower($oRootInput.baseName) <> 'assembly' Then Return SetError(30 + $iManifest, 0, 0)

		For $oNode In $oRootInput.childNodes
			If $oNode.nodeType <> 1 Then ContinueLoop

			Local $sBaseName = StringLower($oNode.baseName)
			If $sBaseName = 'assemblyidentity' Then ContinueLoop

			If $sBaseName = 'file' Then
				Local $sFileName = $oNode.getAttribute('name')
				If $sFileName <> '' And __ManifestManagement__FileExistsInAssembly($oRootOut, $sFileName) Then
					Return SetError(40 + $iManifest, 0, 0)
				EndIf
			EndIf

			Local $oImported = $oOut.importNode($oNode, True)
			If Not IsObj($oImported) Then Return SetError(50 + $iManifest, 0, 0)
			$oRootOut.appendChild($oImported)
		Next
	Next

	$oOut.save($sManifestOut)
	If Not FileExists($sManifestOut) Then Return SetError(60, 0, 0)

	Local $oVerify = __ManifestManagement__XML_Load($sManifestOut)
	#forceref $oVerify
	If @error Then
		FileDelete($sManifestOut)
		Return SetError(61, @extended, 0)
	EndIf

	Return 1
EndFunc   ;==>_ManifestManagement_MergeMany

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_Manifest_VerifyWindows
; Description ...: Asks Windows SxS to parse a physical manifest without activating its context.
; Return values .: Success - 1; failure - 0, with native CreateActCtxW error in @extended.
; ===============================================================================================================================
Func _ManifestManagement_Manifest_VerifyWindows($sManifestPath)
	Local $tSourcePath = DllStructCreate('wchar[' & StringLen($sManifestPath) + 1 & ']')
	DllStructSetData($tSourcePath, 1, $sManifestPath)
	Local $tACTCTX = DllStructCreate( _
			'dword cbSize;' & _
			'dword dwFlags;' & _
			'ptr lpSource;' & _
			'ushort wProcessorArchitecture;' & _
			'ushort wLangId;' & _
			'ptr lpAssemblyDirectory;' & _
			'ptr lpResourceName;' & _
			'ptr lpApplicationName;' & _
			'ptr hModule')
	DllStructSetData($tACTCTX, 'cbSize', DllStructGetSize($tACTCTX))
	DllStructSetData($tACTCTX, 'lpSource', DllStructGetPtr($tSourcePath))
	Local $aCreate = DllCall('kernel32.dll', 'handle', 'CreateActCtxW', 'ptr', DllStructGetPtr($tACTCTX))
	Local $iCallError = @error
	If $iCallError Or Not IsArray($aCreate) Then Return SetError(1, $iCallError, 0)
	If $aCreate[0] = Ptr(-1) Then
		Local $iNativeError = __ManifestManagement__GetLastError()
		Return SetError(2, $iNativeError, 0)
	EndIf
	DllCall('kernel32.dll', 'none', 'ReleaseActCtx', 'handle', $aCreate[0])
	Return 1
EndFunc   ;==>_ManifestManagement_Manifest_VerifyWindows

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_ActivateFromFile
; Description ...: Creates and activates a Windows Activation Context from a physical manifest file.
; Syntax ........: _ManifestManagement_ActivateFromFile($sManifestPath)
; Parameters ....: $sManifestPath - Full path to the manifest.
; Return values .: Success - Two-element array containing activation-context handle and cookie.
;                  Failure - 0 and sets @error; @extended contains GetLastError().
; Author ........: mLipok
; Modified ......:
; Remarks .......:
; Related .......: _ManifestManagement_ActivateFromPE, _ManifestManagement_Deactivate
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_ActivateFromFile($sManifestPath)
	Return __ManifestManagement__Activate($sManifestPath, 0)
EndFunc   ;==>_ManifestManagement_ActivateFromFile

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_ActivateFromPE
; Description ...: Creates and activates a Windows Activation Context from an RT_MANIFEST resource in a PE file.
; Syntax ........: _ManifestManagement_ActivateFromPE($sPEPath, $iResourceID)
; Parameters ....: $sPEPath - Full path to the PE file.
;                  $iResourceID - RT_MANIFEST resource identifier.
; Return values .: Success - Two-element array containing activation-context handle and cookie.
;                  Failure - 0 and sets @error; @extended contains GetLastError().
; Author ........: mLipok
; Modified ......:
; Remarks .......:
; Related .......: _ManifestManagement_ActivateFromFile, _ManifestManagement_Deactivate
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_ActivateFromPE($sPEPath, $iResourceID)
	Return __ManifestManagement__Activate($sPEPath, $iResourceID)
EndFunc   ;==>_ManifestManagement_ActivateFromPE

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_Deactivate
; Description ...: Deactivates and releases a previously created Activation Context.
; Syntax ........: _ManifestManagement_Deactivate($hActCtx, $iActCtxCookie)
; Parameters ....: $hActCtx - Activation-context handle.
;                  $iActCtxCookie - Activation cookie.
; Return values .: Success - 1.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......:
; Related .......: _ManifestManagement_ActivateFromFile, _ManifestManagement_ActivateFromPE
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_Deactivate($hActCtx, $iActCtxCookie)
	Local $aDeactivateActCtx = DllCall('kernel32.dll', 'bool', 'DeactivateActCtx', 'dword', 0, 'ulong_ptr', $iActCtxCookie)
	Local $iDllCallError = @error
	Local $iLastError = 0

	If $iDllCallError Or Not IsArray($aDeactivateActCtx) Or Not $aDeactivateActCtx[0] Then
		$iLastError = __ManifestManagement__GetLastError()
	EndIf

	DllCall('kernel32.dll', 'none', 'ReleaseActCtx', 'handle', $hActCtx)

	If $iDllCallError Then Return SetError(1, $iLastError, 0)
	If Not IsArray($aDeactivateActCtx) Or Not $aDeactivateActCtx[0] Then Return SetError(2, $iLastError, 0)
	Return 1
EndFunc   ;==>_ManifestManagement_Deactivate

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_ProcessModules_List
; Description ...: Returns all modules loaded in the current process.
; Syntax ........: _ManifestManagement_ProcessModules_List()
; Parameters ....: None.
; Return values .: Success - 2D module array.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......:
; Related .......: _ManifestManagement_ProcessModules_Find
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_ProcessModules_List()
	Local $aModules = _WinAPI_EnumProcessModules()
	If @error Then Return SetError(@error, @extended, 0)
	Return $aModules
EndFunc   ;==>_ManifestManagement_ProcessModules_List

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_ProcessModules_Find
; Description ...: Finds a loaded module by full path.
; Syntax ........: _ManifestManagement_ProcessModules_Find(ByRef $aModules, $sModulePath)
; Parameters ....: $aModules - Module array returned by _ManifestManagement_ProcessModules_List().
;                  $sModulePath - Full path to find.
; Return values .: Success - Matching row index.
;                  Failure - 0 if not found or input is invalid.
; Author ........: mLipok
; Modified ......:
; Remarks .......:
; Related .......: _ManifestManagement_ProcessModules_List, _ManifestManagement_Path_Equals
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_ProcessModules_Find(ByRef $aModules, $sModulePath)
	If Not IsArray($aModules) Then Return SetError(1, 0, 0)
	If UBound($aModules, 0) <> 2 Then Return SetError(2, 0, 0)
	If UBound($aModules, 2) < 2 Then Return SetError(3, 0, 0)

	For $i = 1 To UBound($aModules) - 1
		If _ManifestManagement_Path_Equals($aModules[$i][1], $sModulePath) Then Return $i
	Next

	Return 0
EndFunc   ;==>_ManifestManagement_ProcessModules_Find

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_Path_Normalize
; Description ...: Normalizes a Windows path for reliable comparison.
; Syntax ........: _ManifestManagement_Path_Normalize($sPath)
; Parameters ....: $sPath - Path to normalize.
; Return values .: Normalized path.
; Author ........: mLipok
; Modified ......:
; Remarks .......: Removes surrounding quotes, prefers the long file-system path when available, and preserves path casing.
; Related .......: _ManifestManagement_Path_Equals
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_Path_Normalize($sPath)
	$sPath = StringStripWS($sPath, 3)
	If StringLeft($sPath, 1) = '"' And StringRight($sPath, 1) = '"' Then $sPath = StringTrimLeft(StringTrimRight($sPath, 1), 1)

	Local $sLongPath = FileGetLongName($sPath)
	If Not @error And $sLongPath <> '' Then $sPath = $sLongPath

	Return $sPath
EndFunc   ;==>_ManifestManagement_Path_Normalize

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_Path_Equals
; Description ...: Compares two Windows paths after normalization.
; Syntax ........: _ManifestManagement_Path_Equals($sPath1, $sPath2)
; Parameters ....: $sPath1 - First path.
;                  $sPath2 - Second path.
; Return values .: True if equal, otherwise False.
; Author ........: mLipok
; Modified ......:
; Remarks .......: Comparison is case-insensitive while normalized path casing is preserved.
; Related .......: _ManifestManagement_Path_Normalize
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_Path_Equals($sPath1, $sPath2)
	Return StringLower(_ManifestManagement_Path_Normalize($sPath1)) = StringLower(_ManifestManagement_Path_Normalize($sPath2))
EndFunc   ;==>_ManifestManagement_Path_Equals

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_File_WriteUTF8
; Description ...: Writes text as UTF-8 without BOM.
; Syntax ........: _ManifestManagement_File_WriteUTF8($sPath, $sText)
; Parameters ....: $sPath - Destination path.
;                  $sText - Text to write.
; Return values .: Success - 1.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......:
; Related .......:
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_File_WriteUTF8($sPath, $sText)
	Local $hFile = FileOpen($sPath, $FO_OVERWRITE + $FO_UTF8_NOBOM)
	If $hFile = -1 Then Return SetError(1, 0, 0)

	Local $iResult = FileWrite($hFile, $sText)
	Local $iError = @error
	FileClose($hFile)
	If $iError Or Not $iResult Then Return SetError(2, $iError, 0)

	Return 1
EndFunc   ;==>_ManifestManagement_File_WriteUTF8

; #FUNCTION# ====================================================================================================================
; Name ..........: _ManifestManagement_IsFullPath
; Description ...: Checks whether a path is an absolute drive-letter or UNC path.
; Syntax ........: _ManifestManagement_IsFullPath($sPath)
; Parameters ....: $sPath - Path to check.
; Return values .: True for an absolute path, otherwise False.
; Author ........: mLipok
; Modified ......:
; Remarks .......:
; Related .......:
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _ManifestManagement_IsFullPath($sPath)
	Return StringRegExp($sPath, '(?i)^(?:[A-Z]:\\|\\\\)')
EndFunc   ;==>_ManifestManagement_IsFullPath

; #INTERNAL_USE_ONLY# ===========================================================================================================
Func __ManifestManagement__ProgID_FindByDLL($sDLLPath, $sDialogTitle)
	Local $aProgIDs[1]
	Local $aCLSIDs[1]
	Local $iCount = 0
	Local $iIndex = 1

	While 1
		Local $sCLSID = RegEnumKey('HKEY_CLASSES_ROOT\CLSID', $iIndex)
		If @error Then ExitLoop
		$iIndex += 1

		Local $sServerPath = RegRead('HKEY_CLASSES_ROOT\CLSID\' & $sCLSID & '\InprocServer32', '')
		If @error Or $sServerPath = '' Then ContinueLoop
		If Not _ManifestManagement_Path_Equals($sServerPath, $sDLLPath) Then ContinueLoop

		Local $sProgID = RegRead('HKEY_CLASSES_ROOT\CLSID\' & $sCLSID & '\ProgID', '')
		If @error Or $sProgID = '' Then ContinueLoop

		$iCount += 1
		ReDim $aProgIDs[$iCount + 1]
		ReDim $aCLSIDs[$iCount + 1]
		$aProgIDs[$iCount] = $sProgID
		$aCLSIDs[$iCount] = $sCLSID
	WEnd

	If $iCount = 0 Then Return SetError(1, 0, '')
	If $iCount = 1 Then Return $aProgIDs[1]

	Local $sPrompt = 'Multiple COM classes registered by this DLL were found.' & @CRLF & @CRLF
	For $i = 1 To $iCount
		$sPrompt &= $i & '. ' & $aProgIDs[$i] & '  ' & $aCLSIDs[$i] & @CRLF
	Next
	$sPrompt &= @CRLF & 'Enter class number:'

	Local $sSelection = InputBox($sDialogTitle, $sPrompt, '1', '', 850, 220 + ($iCount * 18))
	If @error Then Return SetError(2, 0, '')

	Local $iSelection = Int($sSelection)
	If $iSelection < 1 Or $iSelection > $iCount Then Return SetError(3, 0, '')
	Return $aProgIDs[$iSelection]
EndFunc   ;==>__ManifestManagement__ProgID_FindByDLL


; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __ManifestManagement__TypeLibPath_FindInLocales
; Description ...: Searches TypeLib locale subkeys for a registered platform-specific Type Library path.
; Syntax ........: __ManifestManagement__TypeLibPath_FindInLocales($sBaseKey, $sPlatform)
; Parameters ....: $sBaseKey - Registry path ending at the TypeLib version key.
;                  $sPlatform - Registry platform key, usually "win32" or "win64".
; Return values .: Success - Registered Type Library path.
;                  Failure - Empty string.
; Author ........: mLipok
; Modified ......:
; Remarks .......:
; Related .......: _ManifestManagement_TypeLibPath_Get
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __ManifestManagement__TypeLibPath_FindInLocales($sBaseKey, $sPlatform)
	Local $iIndex = 1

	While 1
		Local $sLocale = RegEnumKey($sBaseKey, $iIndex)
		If @error Then ExitLoop
		$iIndex += 1

		If Not StringRegExp($sLocale, '^\d+$') Then ContinueLoop

		Local $sPath = RegRead($sBaseKey & '\' & $sLocale & '\' & $sPlatform, '')
		If @error Or $sPath = '' Then ContinueLoop

		$sPath = StringStripWS($sPath, 3)
		If StringLeft($sPath, 1) = '"' And StringRight($sPath, 1) = '"' Then
			$sPath = StringTrimLeft(StringTrimRight($sPath, 1), 1)
		EndIf

		Return $sPath
	WEnd

	Return ''
EndFunc   ;==>__ManifestManagement__TypeLibPath_FindInLocales

; #INTERNAL_USE_ONLY# ===========================================================================================================
Func __ManifestManagement__XML_Load($sPath)
	Local $oDoc = ObjCreate($__MANIFEST_MANAGEMENT__MSXML)
	If Not IsObj($oDoc) Then Return SetError(1, 0, 0)

	$oDoc.async = False
	$oDoc.preserveWhiteSpace = True
	$oDoc.resolveExternals = False
	$oDoc.validateOnParse = False

	If Not $oDoc.load($sPath) Then Return SetError(2, $oDoc.parseError.errorCode, 0)
	If Not IsObj($oDoc.documentElement) Then Return SetError(3, 0, 0)

	Return $oDoc
EndFunc   ;==>__ManifestManagement__XML_Load

; #INTERNAL_USE_ONLY# ===========================================================================================================
Func __ManifestManagement__FileExistsInAssembly($oAssembly, $sFileName)
	For $oNode In $oAssembly.childNodes
		If $oNode.nodeType <> 1 Then ContinueLoop
		If StringLower($oNode.baseName) <> 'file' Then ContinueLoop
		If StringLower($oNode.getAttribute('name')) = StringLower($sFileName) Then Return True
	Next
	Return False
EndFunc   ;==>__ManifestManagement__FileExistsInAssembly

; #INTERNAL_USE_ONLY# ===========================================================================================================
Func __ManifestManagement__Activate($sSourcePath, $iResourceID)
	Local $tSourcePath = DllStructCreate('wchar[' & StringLen($sSourcePath) + 1 & ']')
	DllStructSetData($tSourcePath, 1, $sSourcePath)

	Local $tACTCTX = DllStructCreate( _
			'dword cbSize;' & _
			'dword dwFlags;' & _
			'ptr lpSource;' & _
			'ushort wProcessorArchitecture;' & _
			'ushort wLangId;' & _
			'ptr lpAssemblyDirectory;' & _
			'ptr lpResourceName;' & _
			'ptr lpApplicationName;' & _
			'ptr hModule')

	DllStructSetData($tACTCTX, 'cbSize', DllStructGetSize($tACTCTX))
	DllStructSetData($tACTCTX, 'lpSource', DllStructGetPtr($tSourcePath))

	If $iResourceID Then
		DllStructSetData($tACTCTX, 'dwFlags', $__MANIFEST_MANAGEMENT__ACTCTX_FLAG_RESOURCE_NAME_VALID)
		DllStructSetData($tACTCTX, 'lpResourceName', Ptr($iResourceID))
	Else
		DllStructSetData($tACTCTX, 'dwFlags', 0)
	EndIf

	Local $aCreateActCtx = DllCall('kernel32.dll', 'handle', 'CreateActCtxW', 'ptr', DllStructGetPtr($tACTCTX))
	If @error Or Not IsArray($aCreateActCtx) Then Return SetError(1, __ManifestManagement__GetLastError(), 0)

	Local $hActCtx = $aCreateActCtx[0]
	If $hActCtx = Ptr(-1) Then Return SetError(2, __ManifestManagement__GetLastError(), 0)

	Local $aActivateActCtx = DllCall('kernel32.dll', 'bool', 'ActivateActCtx', 'handle', $hActCtx, 'ulong_ptr*', 0)
	If @error Or Not IsArray($aActivateActCtx) Or Not $aActivateActCtx[0] Then
		Local $iLastError = __ManifestManagement__GetLastError()
		DllCall('kernel32.dll', 'none', 'ReleaseActCtx', 'handle', $hActCtx)
		Return SetError(3, $iLastError, 0)
	EndIf

	Local $aResult[2]
	$aResult[0] = $hActCtx
	$aResult[1] = $aActivateActCtx[2]
	Return $aResult
EndFunc   ;==>__ManifestManagement__Activate

; #INTERNAL_USE_ONLY# ===========================================================================================================
Func __ManifestManagement__GetLastError()
	Local $aResult = DllCall('kernel32.dll', 'dword', 'GetLastError')
	If @error Or Not IsArray($aResult) Then Return 0
	Return $aResult[0]
EndFunc   ;==>__ManifestManagement__GetLastError

; #INTERNAL_USE_ONLY# ===========================================================================================================
Func __ManifestManagement__XML_Escape($sText)
	$sText = StringReplace($sText, '&', '&amp;')
	$sText = StringReplace($sText, '"', '&quot;')
	$sText = StringReplace($sText, '<', '&lt;')
	$sText = StringReplace($sText, '>', '&gt;')
	Return $sText
EndFunc   ;==>__ManifestManagement__XML_Escape

; #INTERNAL_USE_ONLY# ===========================================================================================================
Func __ManifestManagement__XML_Comment_Escape($sText)
	Return StringReplace($sText, '--', '- -')
EndFunc   ;==>__ManifestManagement__XML_Comment_Escape

; #INTERNAL_USE_ONLY# ===========================================================================================================
Func __ManifestManagement__AutoIt_String($sText)
	Return "'" & StringReplace($sText, "'", "''") & "'"
EndFunc   ;==>__ManifestManagement__AutoIt_String

; #INTERNAL_USE_ONLY# ===========================================================================================================
Func __ManifestManagement__COM_Error($oError)
	ConsoleWrite('! COM ERROR 0x' & Hex($oError.number) & ' line=' & $oError.scriptline & ' ' & $oError.windescription & @CRLF)
EndFunc   ;==>__ManifestManagement__COM_Error
