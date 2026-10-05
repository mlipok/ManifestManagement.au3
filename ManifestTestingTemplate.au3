#AutoIt3Wrapper_UseX64={{USE_X64}}
#AutoIt3Wrapper_UseUpx=N

#AutoIt3Wrapper_OutFile={{OUT_FILE}}

; The manifest must exist at COMPILE TIME.
; It is embedded as an RT_MANIFEST resource in the compiled EXE.
#AutoIt3Wrapper_Res_File_Add={{MANIFEST_RESOURCE_FILE}},RT_MANIFEST,{{MANIFEST_RESOURCE_ID}}

#include <Array.au3>
#include <AutoItConstants.au3>
#include <MsgBoxConstants.au3>
#include "ManifestManagement.au3"

; ===============================================================================================================================
; Registration-Free COM testing template
; Author: mLipok
;
; This file is a template used by ManifestCreator.au3.
; ManifestCreator.au3 first copies this file and then replaces the template placeholders in the copy.
;
; COMPILED MODE:
;   The manifest is embedded into the EXE as an RT_MANIFEST resource.
;   CreateActCtxW() loads the manifest directly from the current EXE.
;   No physical manifest file is required at runtime.
;
; UNCOMPILED MODE:
;   The physical manifest file is loaded from @ScriptDir.
;
; The COM DLL does NOT need to be registered using regsvr32.
; ===============================================================================================================================

Global Const $__REGFREE_MANIFEST_RESOURCE_ID = {{MANIFEST_RESOURCE_ID}}
Global Const $__REGFREE_PROGID = {{PROGID}}
Global Const $__REGFREE_CLSID = {{CLSID}}
Global Const $__REGFREE_IID = {{IID}}
Global Const $__REGFREE_DLL = {{DLL_NAME}}
Global Const $__REGFREE_MANIFEST = {{MANIFEST_NAME}}

_Example()
Exit @error

Func _Example()
	; Error monitoring. This will trap all COM errors while alive.
	; This particular object is declared as local, meaning after the function returns it will not exist.
	Local $oErrorHandler = ObjEvent('AutoIt.Error', __ManifestTesting_COM_Error)
	#forceref $oErrorHandler

	ConsoleWrite('! @Compiled = ' & @Compiled & @CRLF)
	ConsoleWrite('! @AutoItX64 = ' & @AutoItX64 & @CRLF)

	Local $sDLLPath = @ScriptDir & '\' & $__REGFREE_DLL
	Local $sManifestPath = @ScriptDir & '\' & $__REGFREE_MANIFEST

	ConsoleWrite('+ ProgID = ' & $__REGFREE_PROGID & @CRLF)
	ConsoleWrite('+ CLSID = ' & $__REGFREE_CLSID & @CRLF)
	ConsoleWrite('+ IID = ' & $__REGFREE_IID & @CRLF)
	ConsoleWrite('+ DLL = ' & $sDLLPath & @CRLF)

	If @Compiled Then
		ConsoleWrite('+ Manifest source = PE resource' & @CRLF)
		ConsoleWrite('+ PE file = ' & @ScriptFullPath & @CRLF)
		ConsoleWrite('+ RT_MANIFEST resource ID = ' & $__REGFREE_MANIFEST_RESOURCE_ID & @CRLF)
	Else
		ConsoleWrite('+ Manifest source = physical file' & @CRLF)
		ConsoleWrite('+ Manifest = ' & $sManifestPath & @CRLF)
	EndIf

	If Not FileExists($sDLLPath) Then
		MsgBox($MB_ICONERROR, 'Registration-Free COM test', _
				'Required DLL file is missing.' & @CRLF & @CRLF & _
				'Process: ' & (@AutoItX64 ? 'x64' : 'x86') & @CRLF & _
				'Required DLL: ' & $__REGFREE_DLL & @CRLF & _
				'Expected location:' & @CRLF & _
				$sDLLPath)
		Return SetError(1, 0, 0)
	EndIf

	If Not @Compiled And Not FileExists($sManifestPath) Then
		MsgBox($MB_ICONERROR, 'Registration-Free COM test', _
				'Required manifest file is missing.' & @CRLF & @CRLF & _
				'Process: ' & (@AutoItX64 ? 'x64' : 'x86') & @CRLF & _
				'Required manifest: ' & $__REGFREE_MANIFEST & @CRLF & _
				'Expected location:' & @CRLF & _
				$sManifestPath)
		Return SetError(2, 0, 0)
	EndIf

	Local $aActCtx

	If @Compiled Then
		; Activate Registration-Free COM directly from the RT_MANIFEST resource embedded in the current EXE.
		$aActCtx = _ManifestManagement_ActivateFromPE(@ScriptFullPath, $__REGFREE_MANIFEST_RESOURCE_ID)
	Else
		; Activate Registration-Free COM from the physical manifest file.
		$aActCtx = _ManifestManagement_ActivateFromFile($sManifestPath)
	EndIf

	If @error Then
		Local $iError = @error
		Local $iExtended = @extended
		Local $sDiagnostic = _ManifestManagement_Activation_Diagnostic($iExtended, @Compiled, $__REGFREE_MANIFEST_RESOURCE_ID, $sDLLPath, $sManifestPath)
		ConsoleWrite('! Activation diagnostic: ' & $sDiagnostic & '; CreateActCtxW GetLastError=' & $iExtended & @CRLF)

		MsgBox($MB_ICONERROR, 'Registration-Free COM test', _
				'Failed to activate Registration-Free COM.' & @CRLF & @CRLF & _
				'Process: ' & (@AutoItX64 ? 'x64' : 'x86') & @CRLF & _
				'Mode: ' & (@Compiled ? 'PE RT_MANIFEST resource' : 'physical manifest file') & @CRLF & _
				(@Compiled ? _
				('PE file: ' & @ScriptFullPath & @CRLF & 'Resource ID: ' & $__REGFREE_MANIFEST_RESOURCE_ID) : _
				('Manifest: ' & $sManifestPath)) & @CRLF & @CRLF & _
				'Diagnostic: ' & $sDiagnostic & @CRLF & _
				'@error = ' & $iError & @CRLF & _
				'CreateActCtxW GetLastError = ' & $iExtended & ' (0x' & Hex($iExtended, 8) & ')')

		Return SetError(3, $iExtended, 0)
	EndIf

	Local $hActCtx = $aActCtx[0]
	Local $iActCtxCookie = $aActCtx[1]

	ConsoleWrite('+ Activation Context = ACTIVE' & @CRLF)

	; ObjCreate must be called while the Activation Context is active.
	Local $oObject = ObjCreate($__REGFREE_PROGID)

	If Not IsObj($oObject) Then
		_ManifestManagement_Deactivate($hActCtx, $iActCtxCookie)

		Local $sObjectDiagnostic = _ManifestManagement_Activation_Diagnostic(0, @Compiled, $__REGFREE_MANIFEST_RESOURCE_ID, $sDLLPath, $sManifestPath)
		MsgBox($MB_ICONERROR, 'Registration-Free COM test', _
				'Failed to create the COM object.' & @CRLF & @CRLF & _
				'Diagnostic: ' & $sObjectDiagnostic & @CRLF & _
				'Process: ' & (@AutoItX64 ? 'x64' : 'x86') & @CRLF & _
				'ProgID: ' & $__REGFREE_PROGID & @CRLF & _
				'DLL: ' & $sDLLPath)

		Return SetError(4, 0, 0)
	EndIf

	ConsoleWrite('+ COM object created' & @CRLF)

	Local $sObjProgID = ObjName($oObject, $OBJ_PROGID)
	Local $sObjFile = ObjName($oObject, $OBJ_FILE)
	Local $sObjCLSID = ObjName($oObject, $OBJ_CLSID)
	Local $sObjIID = ObjName($oObject, $OBJ_IID)

	ConsoleWrite('+ ObjName PROGID = ' & $sObjProgID & @CRLF)
	ConsoleWrite('+ ObjName FILE = ' & $sObjFile & @CRLF)
	ConsoleWrite('+ ObjName CLSID = ' & $sObjCLSID & @CRLF)
	ConsoleWrite('+ ObjName IID = ' & $sObjIID & @CRLF)

	Local $aProcessModules = _ManifestManagement_ProcessModules_List()
	If @error Then
		ConsoleWrite('! _ManifestManagement_ProcessModules_List() ERROR = ' & @error & ', EXTENDED = ' & @extended & @CRLF)
	Else
		_ArrayDisplay($aProcessModules, _
				'Loaded process modules - ' & (@AutoItX64 ? 'x64' : 'x86'), _
				Default, _
				Default, _
				Default, _
				'Module handle|Module path')
	EndIf

	Local $iModuleIndex = _ManifestManagement_ProcessModules_Find($aProcessModules, $sDLLPath)
	Local $bObjNameFileCorrect = _ManifestManagement_Path_Equals($sObjFile, $sDLLPath)

	If $iModuleIndex > 0 Then
		ConsoleWrite('+ CORRECT DLL - Registration-Free COM is working' & @CRLF)
		ConsoleWrite('+ Module index = ' & $iModuleIndex & @CRLF)
		ConsoleWrite('+ Loaded DLL = ' & $aProcessModules[$iModuleIndex][1] & @CRLF)
	Else
		ConsoleWrite('! EXPECTED DLL WAS NOT FOUND IN THE PROCESS MODULE LIST' & @CRLF)
		ConsoleWrite('! Expected DLL = ' & $sDLLPath & @CRLF)
	EndIf

	If $bObjNameFileCorrect Then
		ConsoleWrite('+ ObjName($oObject, $OBJ_FILE) points to the expected DLL' & @CRLF)
	Else
		ConsoleWrite('! ObjName($oObject, $OBJ_FILE) DOES NOT point to the expected DLL' & @CRLF)
		ConsoleWrite('! ObjName FILE = ' & $sObjFile & @CRLF)
		ConsoleWrite('! Expected DLL = ' & $sDLLPath & @CRLF)
	EndIf

	MsgBox($MB_ICONINFORMATION, 'Registration-Free COM test', _
			'COM object created successfully.' & @CRLF & @CRLF & _
			'Process: ' & (@AutoItX64 ? 'x64' : 'x86') & @CRLF & _
			'Manifest source: ' & (@Compiled ? 'embedded RT_MANIFEST resource' : 'physical manifest file') & @CRLF & _
			'ProgID: ' & $sObjProgID & @CRLF & _
			'CLSID: ' & $sObjCLSID & @CRLF & _
			'IID: ' & $sObjIID & @CRLF & _
			'ObjName FILE: ' & $sObjFile & @CRLF & @CRLF & _
			'ObjName FILE points to expected DLL: ' & ($bObjNameFileCorrect ? 'YES' : 'NO') & @CRLF & _
			'Local DLL found in process modules: ' & ($iModuleIndex > 0 ? 'YES' : 'NO'))

	$oObject = 0

	_ManifestManagement_Deactivate($hActCtx, $iActCtxCookie)
	If @error Then
		ConsoleWrite('! DeactivateActCtx error: ' & @extended & @CRLF)
	Else
		ConsoleWrite('+ Activation Context = DEACTIVATED' & @CRLF)
	EndIf

	If Not $bObjNameFileCorrect Then Return SetError(5, 0, 0)
	If $iModuleIndex <= 0 Then Return SetError(6, 0, 0)
	Return 1

EndFunc   ;==>_Example


; #INTERNAL_USE_ONLY# ===========================================================================================================
; Name ..........: __ManifestTesting_COM_Error
; Description ...: Reports COM errors raised by the generated Registration-Free COM test.
; Syntax ........: __ManifestTesting_COM_Error($oError)
; Parameters ....: $oError - AutoIt COM error object.
; Return values .: None.
; Author ........: mLipok
; Modified ......:
; Remarks .......:
; Related .......:
; Link ..........:
; Example .......: No
; ===============================================================================================================================
Func __ManifestTesting_COM_Error($oError)
	Local $sMessage = @ScriptName & ' (' & $oError.scriptline & ') : ==> COM Error intercepted!' & @CRLF & _
			@TAB & 'err.number: ' & @TAB & @TAB & '0x' & Hex($oError.number) & @CRLF & _
			@TAB & 'err.windescription: ' & @TAB & $oError.windescription & @CRLF & _
			@TAB & 'err.description: ' & @TAB & $oError.description & @CRLF & _
			@TAB & 'err.source: ' & @TAB & @TAB & $oError.source & @CRLF & _
			@TAB & 'err.scriptline: ' & @TAB & $oError.scriptline & @CRLF

	MsgBox($MB_TOPMOST, 'COM ERROR', $sMessage)
EndFunc   ;==>__ManifestTesting_COM_Error
