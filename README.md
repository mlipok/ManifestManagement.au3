# AutoIt Registration-Free COM Manifest Tools

A small set of AutoIt utilities for creating, testing, and merging Windows Registration-Free COM manifests.

The project is intended to simplify working with native COM DLLs that normally require system registration through `regsvr32.exe`.

## Included files

### `ManifestCreator.au3`

Creates a Registration-Free COM manifest for a selected COM DLL, discovers all COM classes registered by that DLL, and generates a matching AutoIt test script.

The tool:

1. Determines the target architecture from `#AutoIt3Wrapper_UseX64`.
2. Verifies that the current AutoIt process uses the expected architecture.
3. Prompts for:
   - the COM DLL,
   - an optional ProgID.
4. Temporarily registers the DLL with `regsvr32.exe`.
5. Discovers every `HKCR\CLSID` registration whose `InprocServer32` points to the selected DLL.
6. Selects one discovered ProgID as the generated runtime test class and creates that COM object.
7. Uses AutoIt's `ObjName()` to obtain COM information for the selected test class such as:
   - ProgID,
   - CLSID,
   - IID,
   - associated module path.
8. Verifies that `ObjName(..., $OBJ_FILE)` points to exactly the DLL selected by the user.
9. Collects the ProgID, CLSID, description, ThreadingModel, TypeLib GUID and TypeLib version for every discovered COM class.
10. Resolves all unique Type Libraries used by those classes and detects whether each Type Library is embedded in the DLL or stored in a separate registered file.
11. Copies external Type Library files beside the selected DLL when required.
12. Unregisters the DLL.
13. Creates one Registration-Free COM manifest containing all discovered `<comClass>` entries.
14. Creates a test script from `ManifestTestingTemplate.au3`.

The generated test script is created from a copy of the template. The template itself is not embedded as a large string inside `ManifestCreator.au3`.

---

### `ManifestTestingTemplate.au3`

Template used by `ManifestCreator.au3` to generate a dedicated test script for a COM DLL and its manifest.

The generated test verifies Registration-Free COM activation without requiring permanent COM registration.

The template supports:

- running directly as an `.au3` script with an external manifest file,
- running as a compiled executable,
- activation context creation,
- COM object creation,
- verification of the module reported by `ObjName()`,
- verification that the expected DLL is loaded into the current process.

Do not normally edit generated test scripts manually. Changes intended for all future generated tests should be made in `ManifestTestingTemplate.au3`.

If the selected COM DLL is in a different directory than `ManifestCreator.au3`, the creator also copies `ManifestManagement.au3` into the generated test directory.

---

### `ManifestMerge.au3`

Merges two Windows manifest files into one manifest.

Typical use case:

- one manifest contains Registration-Free COM information for an application-specific DLL,
- another manifest is supplied by a third-party library such as Chilkat,
- both sets of activation data must be available from the same activation context.

The first manifest is treated as the base manifest.

Its `assemblyIdentity` is preserved.

The second manifest's `assemblyIdentity` is skipped, while its other top-level assembly elements are imported into the resulting manifest.

The merge is performed with `MSXML2.DOMDocument.6.0` rather than by concatenating XML as plain text.

The tool also checks for duplicate top-level `<file name="...">` entries.

## Requirements

- Windows
- AutoIt
- SciTE4AutoIt3 recommended
- MSXML 6.0
- Administrator privileges when COM registration is required
- A COM DLL compatible with the selected AutoIt architecture

`ManifestCreator.au3` requires the process architecture to match the target COM DLL architecture.

For example:

```autoit
#AutoIt3Wrapper_UseX64=n
```

creates/runs a 32-bit AutoIt process.

For a 64-bit COM DLL, use:

```autoit
#AutoIt3Wrapper_UseX64=y
```

## `ManifestCreator.au3` workflow

A typical workflow is:

```text
COM DLL
   |
   v
temporary regsvr32 registration
   |
   v
ObjCreate()
   |
   v
ObjName()
   |
   +--> ProgID
   +--> CLSID
   +--> IID
   +--> module path verification
   |
   v
read additional COM registration data
   |
   v
regsvr32 /u
   |
   v
Registration-Free COM manifest
   |
   v
generated test script
```

The important verification step is that the file returned by `ObjName()` must match the DLL selected by the user.

This helps avoid generating a manifest for another COM server that happens to expose the same or a related ProgID.




## ManifestCreator operating modes

`ManifestCreator.au3` asks which workflow should be used after the COM DLL is selected.

### Manufacturer-supplied manifest

If the ActiveX/COM component manufacturer already provides a Registration-Free COM manifest, select **YES** when asked.

The creator then asks for that manifest and places it beside the selected DLL when necessary.

This mode intentionally skips:

- `regsvr32`,
- the full `HKCR\CLSID` scan,
- ProgID selection,
- TypeLib discovery,
- `ObjName()`,
- generated test-script creation.

The manufacturer-supplied manifest is treated as the authoritative COM activation description.

### Full registry scan

If no manufacturer manifest is available, the creator asks whether the Windows COM registry should be scanned for every CLSID whose `InprocServer32` points to the selected DLL.

Selecting **YES** keeps the comprehensive behavior:

```text
DLL
  |
  v
regsvr32
  |
  v
scan HKCR\CLSID
  |
  v
discover all matching COM classes
  |
  v
select test ProgID
  |
  v
ObjName() verification
  |
  v
TypeLib discovery
  |
  v
regsvr32 /u
  |
  v
multi-class manifest + generated test
```

This mode can take a long time on systems with many registered COM classes. The progress window and console scan counters remain enabled.

### Fast single-class mode

Selecting **NO** for the full registry scan avoids enumerating all `HKCR\CLSID` entries.

The fast workflow is:

```text
DLL
  |
  +--> ProgID (required)
  |
  +--> optional external TLB
  |
  v
regsvr32
  |
  v
ObjCreate() / ObjName()
  |
  v
CLSID / IID / ThreadingModel / TypeLib data
  |
  v
regsvr32 /u
  |
  v
single-class manifest + generated test
```

A ProgID is required in this mode because leaving it empty would require searching the CLSID registry to discover a suitable class, which would defeat the purpose of skipping the full scan.

If no external TLB is selected, the creator still attempts to resolve the registered TypeLib location automatically from the selected COM class.

## Multiple COM classes in one DLL

A single in-process COM DLL may expose many COM classes.

`ManifestCreator.au3` no longer assumes that one DLL means one ProgID or one CLSID. After temporary registration, it enumerates `HKCR\CLSID` and selects every class whose `InprocServer32` resolves to exactly the selected DLL.

For each discovered class, the generated manifest can contain a separate entry such as:

```xml
<file name="Example.dll">
    <comClass clsid="{...}" progid="Example.Object1" threadingModel="Both" tlbid="{...}" />
    <comClass clsid="{...}" progid="Example.Object2" threadingModel="Both" tlbid="{...}" />
    <comClass clsid="{...}" progid="Example.Object3" threadingModel="Both" tlbid="{...}" />
</file>
```

The optional ProgID entered in `ManifestCreator.au3` is used only to choose the class exercised by the generated `ObjCreate()` test. It does not limit which classes are written to the manifest.

If no test ProgID is entered, the first discovered class that has a ProgID is used.

Classes that do not have a registered ProgID are still written to the manifest when their CLSID points to the selected DLL.

This approach is useful for ActiveX/COM libraries that expose many automation objects from one physical DLL.

## Type Libraries (TLB)

A COM component may expose its type information through a **Type Library**.

The Type Library can be:

- embedded directly inside the COM DLL,
- stored in a separate `.tlb` file,
- registered under a TypeLib GUID and version in the Windows Registry.

`ManifestCreator.au3` does not require the user to manually select a `.tlb` file.

Instead, after temporarily registering the selected COM DLL with `regsvr32.exe`, the tool reads the COM registration information and determines whether the registered Type Library is embedded in the DLL or stored in a separate file.

The relevant COM registration normally includes entries similar to:

```text
HKCR\CLSID\{CLSID}\TypeLib
HKCR\CLSID\{CLSID}\Version
HKCR\TypeLib\{TypeLib-GUID}\{Version}\{Locale}\win32
HKCR\TypeLib\{TypeLib-GUID}\{Version}\{Locale}\win64
```

The exact platform key depends on the COM architecture.

### Embedded Type Library

If the registered Type Library path points to the same DLL selected in `ManifestCreator.au3`, the Type Library is treated as embedded in that DLL.

Example:

```text
Selected COM DLL:
C:\MyApp\SomeLibrary.dll

Registered TypeLib path:
C:\MyApp\SomeLibrary.dll
```

In this case, no additional `.tlb` file is required.

The generated manifest can contain the appropriate `<typelib>` information inside the DLL `<file>` element.

Conceptually:

```xml
<file name="SomeLibrary.dll">
    <comClass
        clsid="{...}"
        progid="SomeLibrary.Object"
        threadingModel="Apartment"
        tlbid="{...}" />

    <typelib
        tlbid="{...}"
        version="1.0"
        helpdir="" />
</file>
```

### Separate Type Library file

If the registered Type Library points to another file, for example:

```text
C:\Program Files\Vendor\SomeLibrary.tlb
```

then the COM component is treated as using a separate Type Library file.

`ManifestCreator.au3` automatically detects this situation.

If the `.tlb` file is not already located beside the selected COM DLL, the tool copies it into the target directory used by the generated Registration-Free COM assembly.

For example:

```text
MyApp\
    SomeLibrary.dll
    SomeLibrary.tlb
    SomeLibrary_RegFreeCOM_x86.manifest
    SomeLibrary_RegFreeCOM_Test_x86.au3
    ManifestManagement.au3
```

The generated manifest then contains a separate `<file>` entry for the Type Library.

Conceptually:

```xml
<file name="SomeLibrary.dll">
    <comClass
        clsid="{...}"
        progid="SomeLibrary.Object"
        threadingModel="Apartment"
        tlbid="{...}" />
</file>

<file name="SomeLibrary.tlb">
    <typelib
        tlbid="{...}"
        version="1.0"
        helpdir="" />
</file>
```


### TLB, CLSID and ProgID discovery

A Type Library can describe coclasses and their CLSIDs, but ProgID is registration data rather than a reliable Type Library property.

For this reason, the project does not attempt to derive ProgIDs from the `.tlb` binary itself. Instead, after temporary DLL registration it uses the Windows COM registry as the authoritative mapping:

```text
DLL
  |
  +--> HKCR\CLSID\{CLSID}\InprocServer32
  |
  +--> HKCR\CLSID\{CLSID}\ProgID
  |
  +--> HKCR\CLSID\{CLSID}\TypeLib
  |
  `--> HKCR\CLSID\{CLSID}\Version
```

The TypeLib GUID/version is then used to resolve the physical embedded or external Type Library location.

### Automatic TypeLib detection

The TypeLib detection process is:

```text
selected COM DLL
    |
    v
temporary regsvr32 registration
    |
    v
ObjCreate()
    |
    v
ObjName() / CLSID discovery
    |
    v
HKCR\CLSID\{CLSID}\TypeLib
HKCR\CLSID\{CLSID}\Version
    |
    v
HKCR\TypeLib\{TypeLib-GUID}\{Version}\...\win32|win64
    |
    +--> path points to selected DLL
    |       |
    |       `--> TypeLib embedded in DLL
    |
    `--> path points to another file
            |
            `--> separate Type Library file
```

`ManifestManagement.au3` provides the reusable registry lookup logic used by `ManifestCreator.au3`.

### Missing external Type Library

If the registry points to a separate Type Library file but that file does not exist, `ManifestCreator.au3` stops instead of silently generating an incomplete Registration-Free COM package.

This is intentional because a manifest should not reference an external Type Library that cannot be deployed together with the COM DLL.

### Why this matters

A COM class can sometimes be created without explicitly loading its Type Library, but Type Library information may still be required by COM clients, automation, interface discovery, marshaling scenarios, development tools, or other parts of the component.

For that reason, `ManifestCreator.au3` preserves the TypeLib information exposed by the component's normal registration instead of assuming that the DLL alone is always sufficient.




### COM registry scan progress

Discovering all COM classes for a DLL requires scanning the registered `HKCR\CLSID` entries and comparing each `InprocServer32` path with the selected DLL.

Because the total number of CLSID keys is not known without performing a separate preliminary scan, `ManifestManagement.au3` uses an activity-style progress bar rather than a true percentage-complete progress value.

During the scan it displays:

```text
Registry CLSID checked: 12500
COM classes matching DLL: 3
```

and periodically writes console diagnostics such as:

```text
[ManifestManagement] CLSID scan: checked=500 matched=0
[ManifestManagement] CLSID scan: checked=1000 matched=1
...
[ManifestManagement] CLSID scan finished: checked=14872 matched=4
```

This makes long registry scans visibly active instead of appearing to hang.

### File-operation diagnostics

`ManifestCreator.au3` writes file-operation diagnostics to the console.

For every copied or created project file it reports the full source and/or destination path, for example:

```text
[ManifestCreator] Copy:
  Source:      C:\Tools\ManifestManagement.au3
  Destination: D:\COM\ManifestManagement.au3

[ManifestCreator] Create:
  Destination: D:\COM\Example_RegFreeCOM_x86.manifest

[ManifestCreator] Create from template:
  Source:      C:\Tools\ManifestTestingTemplate.au3
  Destination: D:\COM\Example_RegFreeCOM_Test_x86.au3
```

This makes it easier to diagnose output-directory and file-generation problems.


## `ManifestMerge.au3` usage

### Running as an AutoIt script

When `ManifestMerge.au3` is not compiled, the first dialog uses MULTISELECT and requires at least two input manifests. The second dialog selects the new output manifest path and file name.

Existing output files are never overwritten.

### Running as a compiled executable

The compiled executable does not display file selection dialogs.

Without `-f`, all arguments are file names resolved relative to the directory containing `ManifestMerge.exe`. The first two or more arguments are input manifests and the final argument is the new output manifest:

```text
ManifestMerge.exe first.manifest second.manifest [more.manifest ...] result.manifest
```

With `-f` as the first argument, every following argument must be a full path:

```text
ManifestMerge.exe -f "C:\Path\first.manifest" "C:\Path\second.manifest" ["C:\Path\more.manifest" ...] "C:\Path\result.manifest"
```

Existing output files are never overwritten.

`ManifestMerge.au3` uses:

```autoit
#AutoIt3Wrapper_Change2CUI=y
```

so the compiled version can be conveniently used from a command prompt, batch file, build process, or another application.

## Merge behavior

Given two manifests:

```text
Manifest A
Manifest B
```

the resulting manifest uses:

```text
assemblyIdentity from Manifest A

+ elements from Manifest A
+ non-assemblyIdentity elements from Manifest B
```

Conceptually:

```xml
<assembly>
    <assemblyIdentity ... />

    <!-- content from Manifest A -->

    <!-- imported content from Manifest B -->
</assembly>
```

The tool does not simply append one complete `<assembly>` document to another, because that would produce invalid manifest XML.

## Example use case: Debenu + Chilkat

Suppose an application needs both:

```text
debenupdflibraryax1811_RegFreeCOM_x86.manifest
```

and:

```text
chilkat.manifest
```

They can be merged into one application manifest:

```text
Application_x86.manifest
```

using:

```text
ManifestMerge.exe ^
"C:\Application\debenupdflibraryax1811_RegFreeCOM_x86.manifest" ^
"C:\Application\chilkat.manifest" ^
"C:\Application\Application_x86.manifest"
```

The resulting activation context can then contain Registration-Free COM information for both libraries.

## Manifest validation and diagnostics

ManifestCreator.au3 normalizes generated CLSID and TypeLib identifiers to the Windows {GUID} form. It checks the generated XML and referenced files before writing the manifest. After writing, it asks Windows to parse the manifest with CreateActCtxW without activating the context. A generated test script is created only after these checks succeed.

The generated test reports the native CreateActCtxW error code when activation fails. Its focused diagnostic checks for a missing RT_MANIFEST resource, invalid manifest XML or Windows SxS schema, an EXE/DLL architecture mismatch, and missing files referenced by a physical manifest. An unclassified failure retains its native error code for further investigation.

Run tests/ManifestManagementSmoke.au3 with AutoIt to check GUID normalization, XML validation, PE architecture detection, resource lookup, and native error propagation. These checks do not replace a real activation test with the target COM DLL.
## Safety and limitations

Temporary COM registration modifies the Windows COM registry and therefore normally requires administrator privileges.

`ManifestCreator.au3` unregisters the DLL after collecting the required COM information, but the tool should still be tested with the target library before being integrated into an automated build process.

Some COM servers may:

- register multiple COM classes,
- use an external type library,
- use unusual registry layouts,
- require additional dependencies,
- use custom registration logic.

Such libraries may require additional manifest handling.

`ManifestMerge.au3` currently treats a duplicate top-level `<file name="...">` entry as an error instead of attempting to merge the contents of both `<file>` elements automatically.

## Project structure

```text
ManifestCreator.au3
ManifestTestingTemplate.au3
ManifestMerge.au3
README.md
```

Generated files are not part of the core source set and may include files such as:

```text
MyLibrary_RegFreeCOM_x86.manifest
MyLibrary_RegFreeCOM_Test_x86.au3
```

or their x64 equivalents.

## References

- AutoIt `ObjName()` documentation:
  https://www.autoitscript.com/autoit3/docs/functions/ObjName.htm

- Microsoft Registration-Free COM documentation:
  https://learn.microsoft.com/windows/win32/sbscs/registration-free-com-portal

- Microsoft application manifest documentation:
  https://learn.microsoft.com/windows/win32/sbscs/application-manifests

## License

This project is licensed under the **MIT License**. See the [LICENSE](LICENSE) file for details.
