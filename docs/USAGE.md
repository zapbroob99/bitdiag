# Usage

## Manual Usage Without Install

You can run the CLI directly from the repository:

```powershell
.\bitdiag.ps1
```

Or import the module manually:

```powershell
Import-Module .\BitDiag\BitDiag.psd1 -DisableNameChecking
bitdiag -Run
```

The legacy script entry point still works:

```powershell
.\diagnose.ps1
.\diagnose.ps1 -ProblemsOnly
```

## Portable Single-File Build

The repository uses a modular source layout under `BitDiag\Private` and `BitDiag\Public`. To generate a copy-paste/SCCM-friendly single-file script, run:

```powershell
.\build.ps1
```

The generated file is:

```text
dist\bitdiag.ps1
```

You can run it without installing the module:

```powershell
.\dist\bitdiag.ps1 -Run
.\dist\bitdiag.ps1 -Run -ProblemsOnly
.\dist\bitdiag.ps1 -Run -EnterpriseReport -OutDirectory "\\server\share\BitDiag" -Quiet -NoExitCode
```

For SCCM-only reporting, generate the narrower enterprise artifact:

```powershell
.\build-sccm.ps1
.\dist\bitdiag-sccm-report.ps1 -OutDirectory "\\server\share\BitDiag" -Quiet
```

This SCCM script only writes the enterprise NDJSON report. It does not expose remediation, BitLocker enablement, or the interactive menu.

## Interactive Mode

Run `bitdiag` without arguments to open the menu:

```powershell
bitdiag
```

Menu options:

```text
1. Run all diagnostics
2. Show problems only
3. Select drives
4. Export HTML report
5. Export JSON report
6. Generate remediation plan
7. Preview automatic fixes
8. Enable BitLocker on unprotected drives
9. Show help
10. Exit
```

Use `-Run` when you want diagnostics immediately without the menu:

```powershell
bitdiag -Run
```

Show the installed version:

```powershell
bitdiag -Version
```

## CLI Examples

Show only warnings, alerts, and errors:

```powershell
bitdiag -ProblemsOnly
```

Check specific drives:

```powershell
bitdiag -Drives C,D
```

Include raw details:

```powershell
bitdiag -Detailed
```

Generate a JSON report:

```powershell
bitdiag -Format Json -OutFile .\report.json
```

Generate an HTML report:

```powershell
bitdiag -Format Html -OutFile .\report.html
```

If `-OutFile` has no extension, BitDiag appends the expected extension automatically:

```powershell
bitdiag -Format Html -OutFile .\report
# writes .\report.html
```

Filter by category and status:

```powershell
bitdiag -Category Platform,BitLocker -Status Warning,Alert,Error
```

Write a Power BI-friendly NDJSON report for SCCM-triggered fleet reporting:

```powershell
bitdiag -EnterpriseReport -OutDirectory "\\server\share\BitDiag" -Quiet -NoExitCode
```

Generate a remediation plan without changing the system:

```powershell
bitdiag -PlanFixes
```

Preview automatic remediation candidates without changing the system:

```powershell
bitdiag -Fix -WhatIf
```

Apply automatic remediation candidates selected by BitDiag:

```powershell
bitdiag -Fix -Apply
```

Show which unencrypted fixed drives can have BitLocker enabled:

```powershell
bitdiag -EnableBitLocker
```

Preview BitLocker enablement without changing the system:

```powershell
bitdiag -EnableBitLocker -WhatIf
```

Start BitLocker on eligible unencrypted fixed drives:

```powershell
bitdiag -EnableBitLocker -Apply
```

Use results in a PowerShell pipeline:

```powershell
bitdiag -PassThru -Quiet -NoExitCode |
    Where-Object Status -in Warning,Alert,Error |
    Select-Object Category,CheckName,Status,Message
```

## Console Output

The report starts with a summary and drive overview:

```text
Drive    Encrypted     Method          Protection    Recovery      AutoUnlock    FileSystem
C:       Yes           XtsAes256       On            Present       Unknown       NTFS
D:       No            None            Off           Missing       Off           NTFS
```

Detailed results are grouped into sections:

```text
System
Disk layout
Policy
C: Volume / BitLocker
D: Volume / BitLocker
```

When a drive is not encrypted, the default console view shows the primary encryption finding and hides dependent BitLocker checks such as protection, key protector, recovery password, and escrow status. Use `-Detailed` to show every collected check.

## Parameters

| Parameter | Description |
| --- | --- |
| `-Run` | Run diagnostics immediately instead of opening the interactive menu. |
| `-Interactive` | Open the interactive menu explicitly. |
| `-Version` | Show the installed BitDiag version. |
| `-PlanFixes` | Generate a remediation plan without changing the system. |
| `-Fix` | Prepare automatic remediation candidates. Does not change the system by itself. |
| `-Risky` | Include boot-risky automatic remediation candidates with `-Fix`. |
| `-Apply` | Execute remediation candidates with `-Fix` or start eligible `-EnableBitLocker` actions. |
| `-EnableBitLocker` | Prepare BitLocker enablement for eligible unencrypted fixed drives. Requires `-Apply` to start encryption. |
| `-WhatIf` | Preview `-Fix` or `-EnableBitLocker` actions without changing the system. |
| `-EnterpriseReport` | Write flat NDJSON for SCCM-triggered Power BI reporting. |
| `-OutDirectory` | Directory or share path for enterprise NDJSON output. |
| `-Drives`, `-DriveLetters` | Drive letters to inspect. If omitted, detected fixed/removable drives are checked automatically. |
| `-AllDrives` | Discover fixed/removable volumes automatically. This is also the default when `-Drives` is omitted. |
| `-Format`, `-OutputFormat` | Output format: `Console`, `Json`, `Html`, or `None`. |
| `-OutFile`, `-OutputPath` | Destination path for JSON or HTML output. Missing `.json`/`.html` extensions are added automatically. |
| `-Category` | Filter results by category: `Runtime`, `Platform`, `Disk`, `Policy`, `Volume`, `BitLocker`. |
| `-Status` | Filter results by status: `OK`, `Warning`, `Alert`, `Error`, `Info`. |
| `-ProblemsOnly` | Show/export only `Warning`, `Alert`, and `Error` results. |
| `-Detailed` | Include raw diagnostic details and dependent BitLocker checks/actions in console or remediation output. |
| `-Color` | Console color mode: `Auto`, `Always`, or `Never`. |
| `-Quiet` | Suppress informational console output. Useful for automation. |
| `-PassThru` | Emit diagnostic result objects to the PowerShell pipeline. |
| `-Help`, `-h` | Show the help screen. |
| `-NoExitCode` | Do not set the process exit code. Useful while testing interactively. |

## Exit Codes

| Code | Meaning |
| --- | --- |
| `0` | OK |
| `1` | Warning |
| `2` | Alert or Error |
| `3` | Not running as administrator |

## Smoke Tests

Run the basic smoke test script from the repository root:

```powershell
.\tests\smoke.ps1
```

The smoke tests validate module import, version output, help output, the backward-compatible wrapper, remediation plan generation, and safe-fix preview.
