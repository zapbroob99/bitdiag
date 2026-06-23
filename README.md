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
- Keeps the default console view focused on root causes while preserving full detail with `-Detailed`.
- Reports encryption method, encryption progress, key protector types, recovery backup visibility, and suspended protection signals.
- Interprets common BitLocker policy registry values when they are present.
- Provides stable exit codes for automation.
- Keeps `diagnose.ps1` as a backward-compatible wrapper.
- Keeps the repository source modular while supporting a generated single-file portable script.

## Requirements

- Windows PowerShell 5.1 or PowerShell on Windows.
- Windows BitLocker tooling, such as `Get-BitLockerVolume` or `manage-bde`.
- Administrator PowerShell is recommended. Some disk, TPM, Secure Boot, and BitLocker checks may be incomplete without elevation.

## Install From GitHub

Clone the repository, then run:

```powershell
.\install.ps1
```

Or bootstrap the install directly from GitHub:

```powershell
irm https://raw.githubusercontent.com/zapbroob99/bitdiag/main/install-github.ps1 | iex
```

Manual clone/install flow:

```powershell
git clone https://github.com/zapbroob99/bitdiag.git
cd bitdiag
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
7. Preview safe fixes
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

The remediation plan classifies each item by action type, reason type, risk level, and whether it is safe to apply automatically:

```text
[AutomaticCandidate / MissingProtector / Low]
[Manual / Platform / High]
[Review / Policy / Medium]
```

When a drive is not encrypted, the default remediation plan focuses on the primary BitLocker enablement action and hides dependent actions such as protection resume, key protector creation, recovery password checks, and escrow checks. Use `-Detailed -PlanFixes` to show every dependent remediation item.

Preview safe automatic fixes without changing the system:

```powershell
bitdiag -Fix -WhatIf
```

Apply only safe automatic fixes:

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

When a drive is not encrypted, the default console view shows the primary encryption finding and hides dependent BitLocker checks such as protection, key protector, recovery password, and escrow status. This reduces repeated warnings for the same root cause. Use `-Detailed` to show every collected check.

## Parameters

| Parameter | Description |
| --- | --- |
| `-Run` | Run diagnostics immediately instead of opening the interactive menu. |
| `-Interactive` | Open the interactive menu explicitly. |
| `-Version` | Show the installed BitDiag version. |
| `-PlanFixes` | Generate a remediation plan without changing the system. |
| `-Fix` | Prepare safe automatic remediation candidates. Does not change the system by itself. |
| `-Apply` | Execute safe automatic remediation candidates with `-Fix` or start eligible `-EnableBitLocker` actions. |
| `-EnableBitLocker` | Prepare BitLocker enablement for eligible unencrypted fixed drives. Requires `-Apply` to start encryption. |
| `-WhatIf` | Preview `-Fix` or `-EnableBitLocker` actions without changing the system. |
| `-EnterpriseReport` | Write flat NDJSON for SCCM-triggered Power BI reporting. |
| `-OutDirectory` | Directory or share path for enterprise NDJSON output. |
| `-Drives`, `-DriveLetters` | Drive letters to inspect. If omitted, detected fixed/removable drives are checked automatically. |
| `-AllDrives` | Discover fixed/removable volumes automatically. This is also the default when `-Drives` is omitted. |
| `-Format`, `-OutputFormat` | Output format: `Console`, `Json`, `Html`, or `None`. |
| `-OutFile`, `-OutputPath` | Destination path for JSON or HTML output. |
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

## SCCM and Power BI Reporting

Use SCCM only to run BitDiag on endpoints. Let BitDiag write Power BI-friendly NDJSON files to a central SMB share:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\bitdiag.ps1 -Run -EnterpriseReport -OutDirectory "\\server\share\BitDiag" -Quiet -NoExitCode
```

Each output file is named with computer name, device GUID, and timestamp:

```text
<ComputerName>_<DeviceGuid>_<yyyyMMdd-HHmmss>.ndjson
```

Each line is one finding with stable columns for Power BI:

```text
RunId, TimestampUtc, ComputerName, Domain, DeviceGuid, UserContext,
BitDiagVersion, DriveLetter, Category, CheckName, Status, Message,
Fix, ReasonType, RiskLevel, CanApply, ExitCode
```

BitDiag writes to a local temp file, copies to a remote `.tmp` file, then renames to final `.ndjson`. This prevents Power BI from reading half-written files. Enterprise export intentionally excludes raw `Details` values and does not export recovery passwords.

## Safe Remediation

`bitdiag -Fix -Apply` is intentionally limited to low-risk actions:

- Add a missing recovery password protector.
- Resume BitLocker protection when protection appears suspended/off.
- Enable auto-unlock for data drives.

BitDiag does not automatically change firmware settings, convert MBR/GPT layouts, edit BitLocker policy registry values, or enable Secure Boot. Those items remain manual or review-only recommendations.

## Enabling BitLocker

`bitdiag -EnableBitLocker` is intentionally separate from `-Fix` because starting disk encryption is a higher-impact action. By default it only shows an enablement plan.

Use `-Apply` to start encryption:

```powershell
bitdiag -EnableBitLocker -Apply
```

BitDiag keeps this flow simple:

- Fixed local drives only.
- Removable drives are skipped.
- Already encrypted drives are skipped.
- Default encryption is `XtsAes256` with used-space-only encryption.
- OS drive enablement requires administrator rights, UEFI boot mode, and a ready TPM.
- Data drive enablement uses a recovery password protector.
- Data drive enablement also enables auto-unlock when the OS drive is already fully protected.
- OS drive enablement uses a TPM protector and then ensures a recovery password protector exists.

Recovery password backup verification is a post-enable note, not an enablement blocker:

```text
After enabling, verify that the recovery password is backed up.
```

## Troubleshooting Coverage

BitDiag focuses on the common cases that block BitLocker enablement or make protected data drives hard to use:

- TPM missing, disabled, not ready, or incompatible with the current boot mode.
- Legacy BIOS instead of UEFI for modern TPM-based BitLocker.
- Secure Boot disabled or unavailable.
- Missing or invalid EFI System Partition, with a manual `bdecfg -target default -size 550` repair recommendation.
- Dynamic disk markers.
- Active MBR partitions, including the drive letter when Windows exposes it.
- Large unallocated disk ranges or disks without partitions.
- Unsupported filesystems such as ExFAT/ReFS for fixed BitLocker volumes.
- Unencrypted volumes that are candidates for `-EnableBitLocker`.
- Missing recovery password protectors.
- Suspended/off BitLocker protection.
- Missing data-drive auto-unlock.
- BitLocker policy registry keys under `HKLM:\SOFTWARE\Policies\Microsoft\FVE` and `HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FVE`.
- Fixed/removable drive write-deny policies that can make unencrypted drives read-only.
- AD DS recovery backup requirement policies.
- Best-effort AD DS recovery escrow visibility by matching recovery protector IDs when directory access is available. Matching tolerates AD byte-order differences, raw byte-order GUIDs, braces, hyphens, and GUIDs embedded in AD recovery object names.

When validating AD DS recovery escrow in a closed corporate network, run:

```powershell
.\bitdiag.ps1 -Run -Detailed -Category BitLocker
```

The detailed recovery backup result shows visible AD recovery object count and comparable protector IDs, but it does not print recovery passwords.

AD DS escrow verification is currently a best-effort feature under development. It depends on the account running BitDiag having delegated permission to read BitLocker recovery objects in AD. If BitDiag is running as a local administrator or another account without that AD permission, it may report that escrow could not be verified even when the recovery password is actually backed up.

BitDiag does not automatically perform destructive storage operations such as Dynamic-to-Basic conversion, partition deletion, formatting, or making MBR partitions inactive. Those remain manual high-risk actions in the remediation plan.

## Notes

- Run PowerShell as Administrator for the most complete results.
- If no drives are specified, `bitdiag` checks only detected drives. It does not report missing `D:` or `E:` drives unless you explicitly request them with `-Drives`.
- JSON and HTML exports use the same filtered result set shown by options such as `-ProblemsOnly`, `-Category`, and `-Status`.
- Square brackets shown in command documentation usually mean optional syntax. Do not type them into PowerShell commands.
