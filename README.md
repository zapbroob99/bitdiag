# BitDiag

`bitdiag` is a Windows PowerShell CLI tool for BitLocker readiness and troubleshooting diagnostics.

It checks platform security, disk layout, BitLocker policy, volume file systems, encryption status, protection status, and recovery password protectors. The tool can run interactively, produce console reports, or export JSON/HTML output for automation.

## Features

- Runs as a normal CLI command: `bitdiag`.
- Opens an interactive menu when called without arguments.
- Keeps automation-friendly flags for scripted usage.
- Detects target drives automatically by default.
- Shows a quick BitLocker overview for each drive.
- Groups console output into system, disk layout, policy, and per-drive sections.
- Reports encryption method, encryption progress, key protector types, recovery backup visibility, and suspended protection signals.
- Interprets common BitLocker policy registry values when they are present.
- Provides stable exit codes for automation.
- Keeps `diagnose.ps1` as a backward-compatible wrapper.

## Requirements

- Windows PowerShell 5.1 or PowerShell on Windows.
- Windows BitLocker tooling, such as `Get-BitLockerVolume` or `manage-bde`.
- Administrator PowerShell is recommended. Some disk, TPM, Secure Boot, and BitLocker checks may be incomplete without elevation.

## Install From GitHub

Clone the repository, then run:

```powershell
.\install.ps1
```

The installer copies the tool to:

```text
%LOCALAPPDATA%\BitDiag
```

It also adds that folder to your user `PATH` if needed. Open a new PowerShell window after installation, then run:

```powershell
bitdiag
```

To uninstall:

```powershell
.\uninstall.ps1
```

## Manual Usage Without Install

You can run the CLI directly from the repository:

```powershell
.\bitdiag.ps1
```

Or import the module manually:

```powershell
Import-Module .\BitDiag\BitDiag.psd1
bitdiag -Run
```

The legacy script entry point still works:

```powershell
.\diagnose.ps1
.\diagnose.ps1 -ProblemsOnly
```

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
6. Show help
7. Exit
```

Use `-Run` when you want diagnostics immediately without the menu:

```powershell
bitdiag -Run
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

Filter by category and status:

```powershell
bitdiag -Category Platform,BitLocker -Status Warning,Alert,Error
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

## Parameters

| Parameter | Description |
| --- | --- |
| `-Run` | Run diagnostics immediately instead of opening the interactive menu. |
| `-Interactive` | Open the interactive menu explicitly. |
| `-Drives`, `-DriveLetters` | Drive letters to inspect. If omitted, detected fixed/removable drives are checked automatically. |
| `-AllDrives` | Discover fixed/removable volumes automatically. This is also the default when `-Drives` is omitted. |
| `-Format`, `-OutputFormat` | Output format: `Console`, `Json`, `Html`, or `None`. |
| `-OutFile`, `-OutputPath` | Destination path for JSON or HTML output. |
| `-Category` | Filter results by category: `Runtime`, `Platform`, `Disk`, `Policy`, `Volume`, `BitLocker`. |
| `-Status` | Filter results by status: `OK`, `Warning`, `Alert`, `Error`, `Info`. |
| `-ProblemsOnly` | Show/export only `Warning`, `Alert`, and `Error` results. |
| `-Detailed` | Include raw diagnostic details in console output. |
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

## Notes

- Run PowerShell as Administrator for the most complete results.
- If no drives are specified, `bitdiag` checks only detected drives. It does not report missing `D:` or `E:` drives unless you explicitly request them with `-Drives`.
- JSON and HTML exports use the same filtered result set shown by options such as `-ProblemsOnly`, `-Category`, and `-Status`.
- Square brackets shown in command documentation usually mean optional syntax. Do not type them into PowerShell commands.
