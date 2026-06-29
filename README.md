# BitDiag

`bitdiag` is a Windows PowerShell CLI tool for BitLocker readiness and troubleshooting diagnostics.

It checks the things that usually block or weaken BitLocker: platform security, disk layout, BitLocker policy, encryption status, protection status, and recovery password protectors. Run it interactively, use it from scripts, or export JSON/HTML reports.

## Features

- Runs as a normal CLI command: `bitdiag`.
- Opens an interactive menu when called without arguments.
- Detects target drives automatically by default.
- Shows a focused console report with the root cause first.
- Exports JSON and HTML reports.
- Provides stable exit codes for automation.
- Keeps `diagnose.ps1` as a backward-compatible wrapper.

## Requirements

- Windows PowerShell 5.1 or PowerShell on Windows.
- Windows BitLocker tooling, such as `Get-BitLockerVolume` or `manage-bde`.
- Administrator PowerShell is recommended for complete disk, TPM, Secure Boot, and BitLocker checks.

## Install

Clone the repository, then run:

```powershell
.\install.ps1
```

Or install directly from GitHub:

```powershell
irm https://raw.githubusercontent.com/zapbroob99/bitdiag/main/install-github.ps1 | iex
```

Open a new PowerShell window after installation, then run:

```powershell
bitdiag
```

To uninstall:

```powershell
.\uninstall.ps1
```

## Quick Use

Open the interactive menu:

```powershell
bitdiag
```

Run diagnostics immediately:

```powershell
bitdiag -Run
```

Show only warnings, alerts, and errors:

```powershell
bitdiag -Run -ProblemsOnly
```

Check specific drives:

```powershell
bitdiag -Run -Drives C,D
```

Export a report:

```powershell
bitdiag -Run -Format Html -OutFile .\report.html
bitdiag -Run -Format Json -OutFile .\report.json
```

Generate a remediation plan without changing the system:

```powershell
bitdiag -Run -PlanFixes
```

The legacy entry point still works:

```powershell
.\diagnose.ps1 -ProblemsOnly
```

## Portable Script

Generate a single-file script for copy/paste, SCCM, or offline use:

```powershell
.\build.ps1
.\dist\bitdiag.ps1 -Run
```

Generate the narrower SCCM-only enterprise report script:

```powershell
.\build-sccm.ps1
.\dist\bitdiag-sccm-report.ps1 -OutDirectory "\\server\share\BitDiag" -Quiet
```

## Documentation

- [Usage](docs/USAGE.md): interactive mode, examples, parameters, exit codes, and smoke tests.
- [Remediation](docs/REMEDIATION.md): `-PlanFixes`, `-Fix`, and `-EnableBitLocker`.
- [Enterprise Reporting](docs/ENTERPRISE.md): SCCM-triggered NDJSON output for Power BI.
- [Troubleshooting Coverage](docs/TROUBLESHOOTING.md): checks BitDiag performs and current limits.

## Notes

- Run PowerShell as Administrator for the most complete results.
- JSON and HTML exports use the same filtered result set shown by options such as `-ProblemsOnly`, `-Category`, and `-Status`.
- Square brackets shown in command documentation usually mean optional syntax. Do not type them into PowerShell commands.
