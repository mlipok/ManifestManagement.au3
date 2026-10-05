#AutoIt3Wrapper_UseX64=n

#include "..\ManifestManagement.au3"

Global Const $TEST_GUID = '{01234567-89AB-CDEF-0123-456789ABCDEF}'

_Assert(_ManifestManagement_GUID_Normalize('01234567-89ab-cdef-0123-456789abcdef') = $TEST_GUID, 'Unbraced GUID normalization')
_Assert(_ManifestManagement_GUID_Normalize($TEST_GUID) = $TEST_GUID, 'Braced GUID normalization')

Global $sInvalidGUID = _ManifestManagement_GUID_Normalize('not-a-guid')
Global $iGUIDError = @error
_Assert($sInvalidGUID = '' And $iGUIDError <> 0, 'Invalid GUID rejection')

Global $aClasses[1][$MANIFEST_COMCLASS_COLUMNS]
$aClasses[0][$MANIFEST_COMCLASS_PROGID] = 'Example.Object'
$aClasses[0][$MANIFEST_COMCLASS_CLSID] = '01234567-89ab-cdef-0123-456789abcdef'
$aClasses[0][$MANIFEST_COMCLASS_DESCRIPTION] = 'Example object'
$aClasses[0][$MANIFEST_COMCLASS_THREADINGMODEL] = 'Both'
$aClasses[0][$MANIFEST_COMCLASS_TYPELIB_ID] = ''
$aClasses[0][$MANIFEST_COMCLASS_TYPELIB_VERSION] = ''

Global $sManifest = _ManifestManagement_Manifest_BuildClasses('Example.dll', 'x86', $aClasses, 0)
_Assert(@error = 0 And StringInStr($sManifest, 'clsid="' & $TEST_GUID & '"') > 0, 'Generated manifest GUID')

Global $sReason = ''
_Assert(_ManifestManagement_Manifest_Validate($sManifest, $sReason) = 1, 'Generated manifest XML validation')
Global $sInvalidBuild = _ManifestManagement_Manifest_Build('Example.dll', '', 'x86', 'Example.Object', 'bad-guid', '', '', 'Both', '', '')
_Assert(@error <> 0 And $sInvalidBuild = '', 'Invalid GUID build rejection')
_Assert(_ManifestManagement_Manifest_Validate('<broken>', $sReason) = 0 And $sReason <> '', 'Invalid XML diagnostic')

Global $sArchitecture = _ManifestManagement_PE_Architecture_Get(@AutoItExe)
_Assert($sArchitecture = (@AutoItX64 ? 'x64' : 'x86'), 'PE architecture reading')
If @OSArch = 'X64' And Not @AutoItX64 Then
	Global $sX64DLL = @WindowsDir & '\Sysnative\kernel32.dll'
	_Assert(_ManifestManagement_PE_Architecture_Get($sX64DLL) = 'x64', 'x64 DLL PE architecture reading')
	_Assert(_ManifestManagement_Activation_Diagnostic(0, False, 0, $sX64DLL) = 'Architecture mismatch between the EXE and COM DLL', 'Architecture mismatch classification')
EndIf

Global $bResource = _ManifestManagement_ManifestResource_Exists(65000)
_Assert(@error = 0 And Not $bResource, 'Missing RT_MANIFEST detection')

Global $vMissingContext = _ManifestManagement_ActivateFromPE(@AutoItExe, 65000)
Global $iMissingContextError = @error
Global $iMissingContextNative = @extended
ConsoleWrite('Missing resource activation: error=' & $iMissingContextError & ', native=' & $iMissingContextNative & @CRLF)
_Assert($iMissingContextError = 2 And $iMissingContextNative <> 0, 'CreateActCtxW native error preservation')
_Assert(_ManifestManagement_Activation_Diagnostic($iMissingContextNative, True, 65000, @AutoItExe) = 'Missing RT_MANIFEST resource', 'Missing resource classification')

Global $sNativeManifest = @TempDir & '\ManifestManagementSmoke-' & @AutoItPID & '.manifest'
_Assert(_ManifestManagement_File_WriteUTF8($sNativeManifest, $sManifest) = 1, 'Write missing DLL fixture')
_Assert(StringInStr(_ManifestManagement_Activation_Diagnostic(0, False, 0, @AutoItExe, $sNativeManifest), 'missing file') > 0, 'Missing manifest DLL classification')
Global $sSimpleManifest = '<?xml version="1.0" encoding="UTF-8"?>' & _
		'<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">' & _
		'<assemblyIdentity type="win32" name="ManifestManagement.Smoke" version="1.0.0.0" processorArchitecture="x86" />' & _
		'</assembly>'
_Assert(_ManifestManagement_File_WriteUTF8($sNativeManifest, $sSimpleManifest) = 1, 'Write native-validation fixture')
Global $bNativeValid = _ManifestManagement_Manifest_VerifyWindows($sNativeManifest)
Global $iNativeValidError = @extended
FileDelete($sNativeManifest)
_Assert($bNativeValid = 1, 'Windows manifest validation, native error=' & $iNativeValidError)

_Assert(_ManifestManagement_File_WriteUTF8($sNativeManifest, '<assembly') = 1, 'Write invalid manifest fixture')
Global $bNativeInvalid = _ManifestManagement_Manifest_VerifyWindows($sNativeManifest)
Global $iNativeInvalidError = @extended
Global $vInvalidContext = _ManifestManagement_ActivateFromFile($sNativeManifest)
Global $iInvalidContextError = @error
Global $iInvalidContextNative = @extended
FileDelete($sNativeManifest)
_Assert($bNativeInvalid = 0 And $iNativeInvalidError <> 0, 'Windows invalid manifest error propagation')
_Assert($iInvalidContextError = 2 And $iInvalidContextNative <> 0, 'File activation native error preservation')

Global $sDiagnostic = _ManifestManagement_Activation_Diagnostic(14004, False, 0, @AutoItExe)
_Assert(StringInStr($sDiagnostic, 'Invalid manifest') > 0, 'Native manifest error classification')

ConsoleWrite('PASS: ManifestManagement smoke tests' & @CRLF)
Exit 0

Func _Assert($bCondition, $sName)
	If $bCondition Then Return
	ConsoleWrite('FAIL: ' & $sName & @CRLF)
	Exit 1
EndFunc   ;==>_Assert
