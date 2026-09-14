#RequireAdmin
#AutoIt3Wrapper_UseX64=n
#AutoIt3Wrapper_UseUpx=N

#include <AutoItConstants.au3>
#include <FileConstants.au3>
#include <MsgBoxConstants.au3>
#include "ManifestManagement.au3"

ConsoleWrite('START' & @CRLF)

; ===============================================================================================================================
; ManifestCreator.au3
; Creates or deploys a Registration-Free COM manifest and can generate a matching AutoIt test script.
; Author: mLipok
;
; Workflow:
;   1. Determine target architecture from #AutoIt3Wrapper_UseX64.
;   2. Ask for the COM DLL.
;   3. Ask whether a manufacturer-supplied ActiveX/COM manifest is already available.
;      - YES: select that manifest and copy it beside the DLL when required. No registry scan, ProgID, TLB or ObjName() workflow is used.
;      - NO: ask whether to scan HKCR\CLSID for every COM class registered by the DLL.
;   4. Full registry-scan mode:
;      - register the DLL temporarily,
;      - scan HKCR\CLSID and discover all matching COM classes,
;      - select one test ProgID,
;      - verify the DLL using ObjName(),
;      - resolve all TypeLib information,
;      - unregister the DLL,
;      - generate the manifest and test script.
;   5. Fast single-class mode:
;      - ask for ProgID and optional external TLB,
;      - register the DLL temporarily,
;      - use ObjName() and the COM registry data for the selected ProgID,
;      - unregister the DLL,
;      - generate a single-class manifest and test script.
;
; IMPORTANT:
;   An in-process x86 COM DLL can only be loaded by an x86 AutoIt process.
;   An in-process x64 COM DLL can only be loaded by an x64 AutoIt process.
; ===============================================================================================================================

Global Const $__MANIFESTCREATOR_TITLE = 'ManifestCreator'
Global Const $__MANIFESTCREATOR_RESOURCE_ID = 101

_Main()
ConsoleWrite('END' & @CRLF)
Exit @error

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __ManifestCreator_FileOperation_Log
; Description ...: Writes file copy/create diagnostics to the console.
; Syntax ........: __ManifestCreator_FileOperation_Log($sOperation, $sDestination[, $sSource = ''])
; Parameters ....: $sOperation - Operation label, for example "Copy", "Create", or "Create from template".
;                  $sDestination - Full destination path.
;                  $sSource - Optional full source path.
; Return values .: None.
; Author ........: mLipok
; Modified ......:
; Remarks .......: Diagnostic helper for file operations performed by ManifestCreator.au3.
; Related .......:
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __ManifestCreator_FileOperation_Log($sOperation, $sDestination, $sSource = '')
	ConsoleWrite('[ManifestCreator] ' & $sOperation & ':' & @CRLF)

	If $sSource <> '' Then
		ConsoleWrite('  Source:      ' & $sSource & @CRLF)
	EndIf

	ConsoleWrite('  Destination: ' & $sDestination & @CRLF & @CRLF)
EndFunc   ;==>__ManifestCreator_FileOperation_Log

; #FUNCTION# ====================================================================================================================
; Name ..........: _Main
; Description ...: Selects the manifest creation/deployment workflow and runs it.
; Syntax ........: _Main()
; Parameters ....: None.
; Return values .: Success - 1.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: The selected COM architecture must match the current AutoIt process architecture.
; Related .......:
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func _Main()

	Local $bTargetX64 = _ManifestManagement_TargetX64_Get()
	If @error Then
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
				'Unable to determine target architecture from #AutoIt3Wrapper_UseX64.')
		Return SetError(1, @extended, 0)
	EndIf

	Local $sArchitecture = ($bTargetX64 ? 'x64' : 'x86')
	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)

	If $bTargetX64 <> @AutoItX64 Then
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
				'Target COM architecture does not match the current AutoIt process.' & @CRLF & @CRLF & _
				'#AutoIt3Wrapper_UseX64 target: ' & $sArchitecture & @CRLF & _
				'Current AutoIt process: ' & (@AutoItX64 ? 'x64' : 'x86') & @CRLF & @CRLF & _
				'Run the script using the matching AutoIt interpreter or compile it for the configured architecture.')
		Return SetError(2, 0, 0)
	EndIf

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	Local $sDLLPath = FileOpenDialog('Select COM DLL - ' & $sArchitecture, @ScriptDir, 'DLL files (*.dll)', $FD_FILEMUSTEXIST)
	If @error Or $sDLLPath = '' Then Return SetError(3, 0, 0)

	$sDLLPath = _ManifestManagement_Path_Normalize($sDLLPath)
	If Not FileExists($sDLLPath) Then Return SetError(4, 0, 0)

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	Local $iManufacturerManifest = MsgBox(BitOR($MB_ICONQUESTION, $MB_YESNO), $__MANIFESTCREATOR_TITLE, _
			'Do you already have a Registration-Free COM manifest supplied by the ActiveX/COM component manufacturer?' & @CRLF & @CRLF & _
			'YES - use the manufacturer-supplied manifest.' & @CRLF & _
			'NO  - create a manifest from the selected DLL.')
	If $iManufacturerManifest = $IDYES Then
		Return __ManifestCreator_ManufacturerManifest_Process($sDLLPath)
	EndIf

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	Local $iRegistryScan = MsgBox(BitOR($MB_ICONQUESTION, $MB_YESNO), $__MANIFESTCREATOR_TITLE, _
			'Scan the Windows COM registry for all CLSID entries whose InprocServer32 points to the selected DLL?' & @CRLF & @CRLF & _
			'YES - full scan; discovers all COM classes registered by this DLL. This can take a long time.' & @CRLF & _
			'NO  - fast single-class mode using DLL + regsvr32 + ProgID + optional TLB + ObjName().')

	If $iRegistryScan = $IDYES Then
		Return __ManifestCreator_FullRegistryScan_Create($sDLLPath, $bTargetX64, $sArchitecture)
	EndIf

	Return __ManifestCreator_SingleClass_Create($sDLLPath, $bTargetX64, $sArchitecture)

EndFunc   ;==>_Main

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __ManifestCreator_ManufacturerManifest_Process
; Description ...: Selects and deploys a manufacturer-supplied manifest beside the selected DLL.
; Syntax ........: __ManifestCreator_ManufacturerManifest_Process($sDLLPath)
; Parameters ....: $sDLLPath - Full path to the selected COM DLL.
; Return values .: Success - 1.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: This mode intentionally skips regsvr32, ProgID, TLB discovery, ObjName(), registry scanning and generated test creation.
; Related .......: __ManifestCreator_FileOperation_Log
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __ManifestCreator_ManufacturerManifest_Process($sDLLPath)

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	Local $sManifestSource = FileOpenDialog('Select manufacturer-supplied manifest', @ScriptDir, _
			'Manifest files (*.manifest)|All files (*.*)', $FD_FILEMUSTEXIST)
	If @error Or $sManifestSource = '' Then Return SetError(20, 0, 0)

	$sManifestSource = _ManifestManagement_Path_Normalize($sManifestSource)
	Local $sOutputDir = StringRegExpReplace($sDLLPath, '\\[^\\]+$', '')
	Local $sManifestName = StringRegExpReplace($sManifestSource, '^.*\\', '')
	Local $sManifestDestination = $sOutputDir & '\' & $sManifestName

	ConsoleWrite('[ManifestCreator] Output directory: ' & $sOutputDir & @CRLF & @CRLF)
	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)

	If _ManifestManagement_Path_Equals($sManifestSource, $sManifestDestination) Then
		ConsoleWrite('[ManifestCreator] Manufacturer manifest is already beside the selected DLL:' & @CRLF & _
				'  ' & $sManifestDestination & @CRLF & @CRLF)
	Else
		If FileExists($sManifestDestination) Then
			MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
					'A manifest with the same file name already exists beside the selected DLL.' & @CRLF & @CRLF & _
					'Existing file:' & @CRLF & $sManifestDestination)
			Return SetError(21, 0, 0)
		EndIf

		__ManifestCreator_FileOperation_Log('Copy manufacturer manifest', $sManifestDestination, $sManifestSource)
		If Not FileCopy($sManifestSource, $sManifestDestination, $FC_NOOVERWRITE) Then
			MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
					'Unable to copy the manufacturer-supplied manifest beside the selected DLL.' & @CRLF & @CRLF & _
					'Source:' & @CRLF & $sManifestSource & @CRLF & @CRLF & _
					'Destination:' & @CRLF & $sManifestDestination)
			Return SetError(22, 0, 0)
		EndIf
	EndIf

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	MsgBox($MB_ICONINFORMATION, $__MANIFESTCREATOR_TITLE, _
			'Manufacturer-supplied manifest is ready beside the selected DLL.' & @CRLF & @CRLF & _
			'Manifest:' & @CRLF & $sManifestDestination)

	Return 1

EndFunc   ;==>__ManifestCreator_ManufacturerManifest_Process

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __ManifestCreator_FullRegistryScan_Create
; Description ...: Creates a manifest containing all COM classes registered by the selected DLL.
; Syntax ........: __ManifestCreator_FullRegistryScan_Create($sDLLPath, $bTargetX64, $sArchitecture)
; Parameters ....: $sDLLPath - Full path to the selected COM DLL.
;                  $bTargetX64 - True for x64, False for x86.
;                  $sArchitecture - Architecture label: x64 or x86.
; Return values .: Success - 1.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: Uses the full HKCR\CLSID scan with progress reporting.
; Related .......:
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __ManifestCreator_FullRegistryScan_Create($sDLLPath, $bTargetX64, $sArchitecture)

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	Local $sProgID = InputBox($__MANIFESTCREATOR_TITLE, _
			'Enter an optional ProgID to use for the generated test script.' & @CRLF & @CRLF & _
			'Leave it empty to use the first discovered COM class that has a ProgID.', _
			'', '', 700, 180)
	If @error Then Return SetError(30, 0, 0)
	$sProgID = StringStripWS($sProgID, 3)

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	Local $sRegsvr32 = _ManifestManagement_Regsvr32_Get($bTargetX64)
	If @error Then
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, 'Unable to locate the required regsvr32.exe.')
		Return SetError(31, 0, 0)
	EndIf

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	If Not _ManifestManagement_Regsvr32_Run($sRegsvr32, $sDLLPath, False) Then
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
				'regsvr32 failed to register the selected DLL.' & @CRLF & @CRLF & _
				'DLL: ' & $sDLLPath & @CRLF & _
				'regsvr32: ' & $sRegsvr32 & @CRLF & _
				'Exit code: ' & @extended)
		Return SetError(32, @extended, 0)
	EndIf

	Local $bRegistered = True

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	Local $aCOMClasses = _ManifestManagement_COMClasses_Get($sDLLPath)
	Local $iClassesError = @error
	Local $iClassesExtended = @extended
	If $iClassesError Or Not IsArray($aCOMClasses) Then
		If $bRegistered Then _ManifestManagement_Regsvr32_Run($sRegsvr32, $sDLLPath, True)
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
				'No COM classes registered by the selected DLL were discovered.' & @CRLF & @CRLF & _
				'@error = ' & $iClassesError & @CRLF & _
				'@extended = ' & $iClassesExtended)
		Return SetError(33, $iClassesExtended, 0)
	EndIf

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	Local $sTestProgID = _ManifestManagement_COMClass_TestProgID_Get($aCOMClasses, $sProgID)
	If @error Or $sTestProgID = '' Then
		If $bRegistered Then _ManifestManagement_Regsvr32_Run($sRegsvr32, $sDLLPath, True)

		Local $sReason = 'No discovered COM class has a ProgID that can be used by the generated ObjCreate() test.'
		If $sProgID <> '' Then $sReason = 'The requested test ProgID was not found among the COM classes registered by the selected DLL.'

		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
				$sReason & @CRLF & @CRLF & _
				'Requested ProgID: ' & $sProgID & @CRLF & _
				'Discovered COM classes: ' & UBound($aCOMClasses))
		Return SetError(34, 0, 0)
	EndIf

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	Local $aCOMInfo = _ManifestManagement_COMInfo_Get($sDLLPath, $sTestProgID)
	Local $iCOMInfoError = @error
	Local $iCOMInfoExtended = @extended

	If $iCOMInfoError Then
		If $bRegistered Then _ManifestManagement_Regsvr32_Run($sRegsvr32, $sDLLPath, True)
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
				'Unable to create and verify the selected test COM class.' & @CRLF & @CRLF & _
				'Test ProgID: ' & $sTestProgID & @CRLF & _
				'@error = ' & $iCOMInfoError & @CRLF & _
				'@extended = ' & $iCOMInfoExtended)
		Return SetError(35, $iCOMInfoExtended, 0)
	EndIf

	$sProgID = $aCOMInfo[0]
	Local $sCLSID = $aCOMInfo[1]
	Local $sIID = $aCOMInfo[2]
	Local $sObjFile = $aCOMInfo[3]

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	If Not _ManifestManagement_Path_Equals($sObjFile, $sDLLPath) Then
		If $bRegistered Then _ManifestManagement_Regsvr32_Run($sRegsvr32, $sDLLPath, True)
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
				'ObjName() does not point to the selected DLL.' & @CRLF & @CRLF & _
				'Selected DLL:' & @CRLF & $sDLLPath & @CRLF & @CRLF & _
				'ObjName($oObject, $OBJ_FILE):' & @CRLF & $sObjFile)
		Return SetError(36, 0, 0)
	EndIf

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	Local $vTypeLibs = _ManifestManagement_TypeLibs_Get($aCOMClasses, $sDLLPath, $bTargetX64)
	If @error Then
		If $bRegistered Then _ManifestManagement_Regsvr32_Run($sRegsvr32, $sDLLPath, True)
		Local $iTypeLibError = @error
		Local $iTypeLibExtended = @extended
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
				'Unable to collect Type Library information for the discovered COM classes.' & @CRLF & @CRLF & _
				'@error = ' & $iTypeLibError & @CRLF & _
				'@extended = ' & $iTypeLibExtended)
		Return SetError(37, $iTypeLibExtended, 0)
	EndIf

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	If $bRegistered Then
		If Not _ManifestManagement_Regsvr32_Run($sRegsvr32, $sDLLPath, True) Then
			MsgBox($MB_ICONWARNING, $__MANIFESTCREATOR_TITLE, _
					'The COM information was collected, but regsvr32 failed to unregister the DLL.' & @CRLF & @CRLF & _
					'DLL: ' & $sDLLPath & @CRLF & _
					'Exit code: ' & @extended)
			Return SetError(38, @extended, 0)
		EndIf
		$bRegistered = False
	EndIf

	Local $sOutputDir = StringRegExpReplace($sDLLPath, '\\[^\\]+$', '')
	Local $sDLLName = StringRegExpReplace($sDLLPath, '^.*\\', '')
	Local $sBaseName = StringRegExpReplace($sDLLName, '(?i)\.dll$', '')
	Local $sManifestPath = $sOutputDir & '\' & $sBaseName & '_RegFreeCOM_' & $sArchitecture & '.manifest'
	Local $sTestScriptPath = $sOutputDir & '\' & $sBaseName & '_RegFreeCOM_Test_' & $sArchitecture & '.au3'

	ConsoleWrite('[ManifestCreator] Output directory: ' & $sOutputDir & @CRLF & @CRLF)
	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)

	If Not __ManifestCreator_RuntimeFiles_Prepare($sOutputDir, $vTypeLibs) Then Return SetError(39, @extended, 0)

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	Local $sManifest = _ManifestManagement_Manifest_BuildClasses($sDLLName, $sArchitecture, $aCOMClasses, $vTypeLibs, $sIID)
	If @error Then Return SetError(40, @extended, 0)

	__ManifestCreator_FileOperation_Log('Create', $sManifestPath)
	If Not _ManifestManagement_File_WriteUTF8($sManifestPath, $sManifest) Then
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, 'Unable to write manifest:' & @CRLF & $sManifestPath)
		Return SetError(41, @extended, 0)
	EndIf

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	If Not __ManifestCreator_TestScript_Create($sTestScriptPath, $sArchitecture, $sProgID, $sDLLName, $sManifestPath, $sCLSID, $sIID) Then
		Return SetError(42, @extended, 0)
	EndIf

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	MsgBox($MB_ICONINFORMATION, $__MANIFESTCREATOR_TITLE, _
			'Manifest and test script created successfully.' & @CRLF & @CRLF & _
			'Mode: full registry scan' & @CRLF & _
			'Architecture: ' & $sArchitecture & @CRLF & _
			'Discovered COM classes: ' & UBound($aCOMClasses) & @CRLF & _
			'Test ProgID: ' & $sProgID & @CRLF & _
			'Test CLSID: ' & $sCLSID & @CRLF & _
			'Test IID: ' & $sIID & @CRLF & _
			'DLL verified by ObjName(): YES' & @CRLF & _
			'Type Libraries: ' & (IsArray($vTypeLibs) ? UBound($vTypeLibs) : 0) & @CRLF & @CRLF & _
			'Manifest:' & @CRLF & $sManifestPath & @CRLF & @CRLF & _
			'Test script:' & @CRLF & $sTestScriptPath)

	Return 1

EndFunc   ;==>__ManifestCreator_FullRegistryScan_Create

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __ManifestCreator_SingleClass_Create
; Description ...: Creates a single-class Registration-Free COM manifest without scanning all HKCR\CLSID entries.
; Syntax ........: __ManifestCreator_SingleClass_Create($sDLLPath, $bTargetX64, $sArchitecture)
; Parameters ....: $sDLLPath - Full path to the selected COM DLL.
;                  $bTargetX64 - True for x64, False for x86.
;                  $sArchitecture - Architecture label: x64 or x86.
; Return values .: Success - 1.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......: Requires a ProgID so _ManifestManagement_COMInfo_Get() does not need to scan HKCR\CLSID.
; Related .......:
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __ManifestCreator_SingleClass_Create($sDLLPath, $bTargetX64, $sArchitecture)

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	Local $sProgID = InputBox($__MANIFESTCREATOR_TITLE, _
			'Enter the ProgID of the COM class to use.' & @CRLF & @CRLF & _
			'Fast single-class mode requires a ProgID because the full CLSID registry scan is being skipped.', _
			'', '', 700, 180)
	If @error Then Return SetError(50, 0, 0)

	$sProgID = StringStripWS($sProgID, 3)
	If $sProgID = '' Then
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
				'ProgID is required when the full registry scan is skipped.')
		Return SetError(51, 0, 0)
	EndIf

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	Local $sTLBPath = FileOpenDialog('Optional: select external Type Library (Cancel to detect automatically)', _
			@ScriptDir, 'Type Library (*.tlb)|All files (*.*)', $FD_FILEMUSTEXIST)
	If @error Then $sTLBPath = ''
	If $sTLBPath <> '' Then $sTLBPath = _ManifestManagement_Path_Normalize($sTLBPath)

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	Local $sRegsvr32 = _ManifestManagement_Regsvr32_Get($bTargetX64)
	If @error Then
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, 'Unable to locate the required regsvr32.exe.')
		Return SetError(52, 0, 0)
	EndIf

	If Not _ManifestManagement_Regsvr32_Run($sRegsvr32, $sDLLPath, False) Then
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
				'regsvr32 failed to register the selected DLL.' & @CRLF & @CRLF & _
				'DLL: ' & $sDLLPath & @CRLF & _
				'regsvr32: ' & $sRegsvr32 & @CRLF & _
				'Exit code: ' & @extended)
		Return SetError(53, @extended, 0)
	EndIf

	Local $bRegistered = True

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	Local $aCOMInfo = _ManifestManagement_COMInfo_Get($sDLLPath, $sProgID)
	Local $iCOMInfoError = @error
	Local $iCOMInfoExtended = @extended
	If $iCOMInfoError Then
		If $bRegistered Then _ManifestManagement_Regsvr32_Run($sRegsvr32, $sDLLPath, True)
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
				'Unable to create and verify the selected COM class.' & @CRLF & @CRLF & _
				'ProgID: ' & $sProgID & @CRLF & _
				'@error = ' & $iCOMInfoError & @CRLF & _
				'@extended = ' & $iCOMInfoExtended)
		Return SetError(54, $iCOMInfoExtended, 0)
	EndIf

	$sProgID = $aCOMInfo[0]
	Local $sCLSID = $aCOMInfo[1]
	Local $sIID = $aCOMInfo[2]
	Local $sObjFile = $aCOMInfo[3]
	Local $sDescription = $aCOMInfo[4]
	Local $sThreadingModel = $aCOMInfo[5]
	Local $sTypeLibID = $aCOMInfo[6]
	Local $sTypeLibVersion = $aCOMInfo[7]

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	If Not _ManifestManagement_Path_Equals($sObjFile, $sDLLPath) Then
		If $bRegistered Then _ManifestManagement_Regsvr32_Run($sRegsvr32, $sDLLPath, True)
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
				'ObjName() does not point to the selected DLL.' & @CRLF & @CRLF & _
				'Selected DLL:' & @CRLF & $sDLLPath & @CRLF & @CRLF & _
				'ObjName($oObject, $OBJ_FILE):' & @CRLF & $sObjFile)
		Return SetError(55, 0, 0)
	EndIf

	If $sTLBPath = '' And $sTypeLibID <> '' And $sTypeLibVersion <> '' Then
		Local $sDetectedTypeLibPath = _ManifestManagement_TypeLibPath_Get($sTypeLibID, $sTypeLibVersion, $bTargetX64)
		If Not @error And $sDetectedTypeLibPath <> '' Then
			If Not _ManifestManagement_Path_Equals($sDetectedTypeLibPath, $sDLLPath) Then
				$sTLBPath = $sDetectedTypeLibPath
			EndIf
		EndIf
	EndIf

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	If $bRegistered Then
		If Not _ManifestManagement_Regsvr32_Run($sRegsvr32, $sDLLPath, True) Then
			MsgBox($MB_ICONWARNING, $__MANIFESTCREATOR_TITLE, _
					'The COM information was collected, but regsvr32 failed to unregister the DLL.' & @CRLF & @CRLF & _
					'DLL: ' & $sDLLPath & @CRLF & _
					'Exit code: ' & @extended)
			Return SetError(56, @extended, 0)
		EndIf
		$bRegistered = False
	EndIf

	Local $sOutputDir = StringRegExpReplace($sDLLPath, '\\[^\\]+$', '')
	Local $sDLLName = StringRegExpReplace($sDLLPath, '^.*\\', '')
	Local $sBaseName = StringRegExpReplace($sDLLName, '(?i)\.dll$', '')
	Local $sManifestPath = $sOutputDir & '\' & $sBaseName & '_RegFreeCOM_' & $sArchitecture & '.manifest'
	Local $sTestScriptPath = $sOutputDir & '\' & $sBaseName & '_RegFreeCOM_Test_' & $sArchitecture & '.au3'

	ConsoleWrite('[ManifestCreator] Output directory: ' & $sOutputDir & @CRLF & @CRLF)
	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)

	If Not __ManifestCreator_ManagementUDF_Copy($sOutputDir) Then Return SetError(57, @extended, 0)

	If $sTLBPath <> '' Then
		If Not FileExists($sTLBPath) Then
			MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
					'The selected or detected Type Library file does not exist.' & @CRLF & @CRLF & _
					'TypeLib:' & @CRLF & $sTLBPath)
			Return SetError(58, 0, 0)
		EndIf

		Local $sTLBName = StringRegExpReplace($sTLBPath, '^.*\\', '')
		Local $sTLBLocalPath = $sOutputDir & '\' & $sTLBName

		If Not _ManifestManagement_Path_Equals($sTLBPath, $sTLBLocalPath) Then
			If FileExists($sTLBLocalPath) Then
				MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
						'A Type Library file with the same name already exists beside the selected DLL.' & @CRLF & @CRLF & _
						'Existing file:' & @CRLF & $sTLBLocalPath)
				Return SetError(59, 0, 0)
			EndIf

			__ManifestCreator_FileOperation_Log('Copy', $sTLBLocalPath, $sTLBPath)
			If Not FileCopy($sTLBPath, $sTLBLocalPath, $FC_NOOVERWRITE) Then
				MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
						'Unable to copy the external Type Library beside the selected DLL.' & @CRLF & @CRLF & _
						'Source:' & @CRLF & $sTLBPath & @CRLF & @CRLF & _
						'Destination:' & @CRLF & $sTLBLocalPath)
				Return SetError(60, 0, 0)
			EndIf

			$sTLBPath = $sTLBLocalPath
		EndIf
	EndIf

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	Local $sManifest = _ManifestManagement_Manifest_Build($sDLLName, $sTLBPath, $sArchitecture, _
			$sProgID, $sCLSID, $sIID, $sDescription, $sThreadingModel, $sTypeLibID, $sTypeLibVersion)
	If @error Then Return SetError(61, @extended, 0)

	__ManifestCreator_FileOperation_Log('Create', $sManifestPath)
	If Not _ManifestManagement_File_WriteUTF8($sManifestPath, $sManifest) Then
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, 'Unable to write manifest:' & @CRLF & $sManifestPath)
		Return SetError(62, @extended, 0)
	EndIf

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	If Not __ManifestCreator_TestScript_Create($sTestScriptPath, $sArchitecture, $sProgID, $sDLLName, $sManifestPath, $sCLSID, $sIID) Then
		Return SetError(63, @extended, 0)
	EndIf

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)
	MsgBox($MB_ICONINFORMATION, $__MANIFESTCREATOR_TITLE, _
			'Manifest and test script created successfully.' & @CRLF & @CRLF & _
			'Mode: fast single class' & @CRLF & _
			'Architecture: ' & $sArchitecture & @CRLF & _
			'ProgID: ' & $sProgID & @CRLF & _
			'CLSID: ' & $sCLSID & @CRLF & _
			'IID: ' & $sIID & @CRLF & _
			'DLL verified by ObjName(): YES' & @CRLF & _
			'TypeLib: ' & ($sTLBPath = '' ? 'embedded in DLL or not separately registered' : $sTLBPath) & @CRLF & @CRLF & _
			'Manifest:' & @CRLF & $sManifestPath & @CRLF & @CRLF & _
			'Test script:' & @CRLF & $sTestScriptPath)

	Return 1

EndFunc   ;==>__ManifestCreator_SingleClass_Create

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __ManifestCreator_RuntimeFiles_Prepare
; Description ...: Copies ManifestManagement.au3 and any external Type Libraries required by a full-scan manifest.
; Syntax ........: __ManifestCreator_RuntimeFiles_Prepare($sOutputDir, ByRef $vTypeLibs)
; Parameters ....: $sOutputDir - Target directory beside the selected COM DLL.
;                  $vTypeLibs - Type Library array returned by _ManifestManagement_TypeLibs_Get(), or 0.
; Return values .: Success - 1.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......:
; Related .......:
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __ManifestCreator_RuntimeFiles_Prepare($sOutputDir, ByRef $vTypeLibs)

	If Not __ManifestCreator_ManagementUDF_Copy($sOutputDir) Then Return SetError(1, @extended, 0)

	If Not IsArray($vTypeLibs) Then Return 1

	For $iTypeLib = 0 To UBound($vTypeLibs) - 1
		If $vTypeLibs[$iTypeLib][$MANIFEST_TYPELIB_EMBEDDED] Then ContinueLoop

		Local $sTLBPath = $vTypeLibs[$iTypeLib][$MANIFEST_TYPELIB_PATH]
		If $sTLBPath = '' Then
			MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
					'A TypeLib GUID/version referenced by a COM class has no registered physical path.' & @CRLF & @CRLF & _
					'TypeLib GUID: ' & $vTypeLibs[$iTypeLib][$MANIFEST_TYPELIB_ID] & @CRLF & _
					'TypeLib version: ' & $vTypeLibs[$iTypeLib][$MANIFEST_TYPELIB_VERSION])
			Return SetError(2, $iTypeLib, 0)
		EndIf

		If Not FileExists($sTLBPath) Then
			MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
					'The registered Type Library points to a separate file that does not exist.' & @CRLF & @CRLF & _
					'Registered TypeLib:' & @CRLF & $sTLBPath)
			Return SetError(3, $iTypeLib, 0)
		EndIf

		Local $sTLBName = StringRegExpReplace($sTLBPath, '^.*\\', '')
		Local $sTLBLocalPath = $sOutputDir & '\' & $sTLBName

		If Not _ManifestManagement_Path_Equals($sTLBPath, $sTLBLocalPath) Then
			If FileExists($sTLBLocalPath) Then
				MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
						'A Type Library file with the same name already exists beside the selected DLL.' & @CRLF & @CRLF & _
						'Existing file:' & @CRLF & $sTLBLocalPath)
				Return SetError(4, $iTypeLib, 0)
			EndIf

			__ManifestCreator_FileOperation_Log('Copy', $sTLBLocalPath, $sTLBPath)
			If Not FileCopy($sTLBPath, $sTLBLocalPath, $FC_NOOVERWRITE) Then
				MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
						'Unable to copy the registered external Type Library beside the selected DLL.' & @CRLF & @CRLF & _
						'Source:' & @CRLF & $sTLBPath & @CRLF & @CRLF & _
						'Destination:' & @CRLF & $sTLBLocalPath)
				Return SetError(5, $iTypeLib, 0)
			EndIf

			$vTypeLibs[$iTypeLib][$MANIFEST_TYPELIB_PATH] = $sTLBLocalPath
		EndIf
	Next

	Return 1

EndFunc   ;==>__ManifestCreator_RuntimeFiles_Prepare

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __ManifestCreator_ManagementUDF_Copy
; Description ...: Copies ManifestManagement.au3 beside generated test files when the output directory differs from @ScriptDir.
; Syntax ........: __ManifestCreator_ManagementUDF_Copy($sOutputDir)
; Parameters ....: $sOutputDir - Target directory.
; Return values .: Success - 1.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......:
; Related .......:
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __ManifestCreator_ManagementUDF_Copy($sOutputDir)

	Local $sManagementSourcePath = @ScriptDir & '\ManifestManagement.au3'
	Local $sManagementDestinationPath = $sOutputDir & '\ManifestManagement.au3'

	ConsoleWrite("#" & @ScriptLineNumber & " - " & @CRLF)

	If _ManifestManagement_Path_Equals($sManagementSourcePath, $sManagementDestinationPath) Then Return 1

	If Not FileExists($sManagementSourcePath) Then
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
				'ManifestManagement.au3 was not found beside ManifestCreator.au3.' & @CRLF & @CRLF & _
				'Expected:' & @CRLF & $sManagementSourcePath)
		Return SetError(1, 0, 0)
	EndIf

	__ManifestCreator_FileOperation_Log('Copy', $sManagementDestinationPath, $sManagementSourcePath)
	If Not FileCopy($sManagementSourcePath, $sManagementDestinationPath, $FC_OVERWRITE) Then
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
				'Unable to copy ManifestManagement.au3 to the generated test directory.' & @CRLF & @CRLF & _
				'Source:' & @CRLF & $sManagementSourcePath & @CRLF & @CRLF & _
				'Destination:' & @CRLF & $sManagementDestinationPath)
		Return SetError(2, 0, 0)
	EndIf

	Return 1

EndFunc   ;==>__ManifestCreator_ManagementUDF_Copy

; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __ManifestCreator_TestScript_Create
; Description ...: Creates the generated Registration-Free COM test script from ManifestTestingTemplate.au3.
; Syntax ........: __ManifestCreator_TestScript_Create($sTestScriptPath, $sArchitecture, $sProgID, $sDLLName, $sManifestPath, $sCLSID, $sIID)
; Parameters ....: $sTestScriptPath - Full path to the generated test script.
;                  $sArchitecture - Architecture label: x64 or x86.
;                  $sProgID - COM ProgID used by the generated test.
;                  $sDLLName - COM DLL file name.
;                  $sManifestPath - Full path to the generated manifest.
;                  $sCLSID - COM CLSID used by the test.
;                  $sIID - Interface IID returned by ObjName().
; Return values .: Success - 1.
;                  Failure - 0 and sets @error.
; Author ........: mLipok
; Modified ......:
; Remarks .......:
; Related .......:
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __ManifestCreator_TestScript_Create($sTestScriptPath, $sArchitecture, $sProgID, $sDLLName, $sManifestPath, $sCLSID, $sIID)

	Local $sTemplatePath = @ScriptDir & '\ManifestTestingTemplate.au3'
	__ManifestCreator_FileOperation_Log('Create from template', $sTestScriptPath, $sTemplatePath)

	If Not _ManifestManagement_TestScript_CreateFromTemplate($sTemplatePath, $sTestScriptPath, $sArchitecture, _
			$sProgID, $sDLLName, StringRegExpReplace($sManifestPath, '^.*\\', ''), $sCLSID, $sIID, $__MANIFESTCREATOR_RESOURCE_ID) Then
		Local $iTemplateError = @error
		Local $iTemplateExtended = @extended
		MsgBox($MB_ICONERROR, $__MANIFESTCREATOR_TITLE, _
				'Unable to create the test script from ManifestTestingTemplate.au3.' & @CRLF & @CRLF & _
				'Template:' & @CRLF & $sTemplatePath & @CRLF & @CRLF & _
				'Destination:' & @CRLF & $sTestScriptPath & @CRLF & @CRLF & _
				'@error = ' & $iTemplateError & @CRLF & _
				'@extended = ' & $iTemplateExtended)
		Return SetError(1, $iTemplateExtended, 0)
	EndIf

	Return 1

EndFunc   ;==>__ManifestCreator_TestScript_Create
