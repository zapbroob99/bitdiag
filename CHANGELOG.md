# Changelog

## 0.2.0

- Added `-Version`.
- Added `-PlanFixes` to generate a remediation plan without changing the system.
- Added remediation planning for recovery password protectors, suspended/off protection, auto-unlock, Secure Boot, boot layout, and BitLocker policy review.
- Added smoke test script.

## 0.1.1

- Expanded diagnostics with encryption method, encryption progress, key protector types, recovery backup visibility, suspended protection signals, and BitLocker policy interpretation.
- Added generated report patterns to `.gitignore`.

## 0.1.0

- Converted the original diagnostics script into the `bitdiag` CLI.
- Added module manifest, launchers, installer, uninstaller, interactive menu, and backward-compatible `diagnose.ps1` wrapper.
