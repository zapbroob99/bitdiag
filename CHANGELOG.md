# Changelog

## 0.6.0

- Added best-effort AD DS recovery escrow visibility check using recovery protector IDs.
- Added specific findings for fixed/removable write-deny BitLocker policies.
- Added specific findings for AD DS recovery backup requirement policies.
- Improved ESP remediation planning with `bdecfg -target default -size 550` as a manual high-risk action.
- Improved active MBR partition reporting by associating drive letters when available.
- Data drive BitLocker enablement now plans and applies auto-unlock when the OS drive is fully protected.
- Enterprise classification now maps ESP, active MBR, and policy-specific findings to clearer reason types.

## 0.5.0

- Added explicit BitLocker enablement flow with `-EnableBitLocker`.
- Keeps encryption start separate from low-risk `-Fix` actions.
- Uses `XtsAes256` and used-space-only encryption by default.
- Auto-enables only eligible unencrypted fixed drives; removable and unsafe cases remain review/manual.
- Requires `-Apply` to start encryption and supports `-WhatIf` preview.
- Added interactive menu entry for BitLocker enablement with confirmation.

## 0.4.0

- Added `-EnterpriseReport -OutDirectory` for SCCM-triggered, share-based Power BI reporting.
- Exports flat NDJSON with one diagnostic finding per line.
- Adds device identity, run metadata, remediation classification, and exit code fields.
- Writes enterprise reports through local temp, remote temp, then final rename to avoid partially-read files.
- Excludes raw diagnostic details and truncates long text fields for safer enterprise ingestion.

## 0.3.1

- Improved remediation plan classification with reason type, risk level, and safe-apply visibility.
- Made `-Fix` rely on explicit safe automatic candidates instead of generic recommendations.

## 0.3.0

- Added safe remediation preview and apply flow with `-Fix`, `-WhatIf`, and `-Apply`.
- Supports automatic candidates for adding recovery password protectors, resuming BitLocker protection, and enabling auto-unlock on data drives.
- Keeps risky actions manual-only, including Secure Boot, firmware mode changes, MBR/GPT conversion, and BitLocker policy edits.
- Added interactive menu option to preview safe fixes.

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
