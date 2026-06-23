# Changelog

## 0.7.6

- Added guided manual remediation steps for high-risk actions that BitDiag should not apply automatically.
- Shows why manual actions are not automatically applied when changing firmware, TPM, ESP, active partition, boot layout, or policy state.
- Corrected the ESP repair recommendation to use `BdeHdCfg.exe -target default -size 550`.

## 0.7.5

- Refined `-EnableBitLocker` output with a ready/blocked/review summary and clearer apply states.
- Treats recovery password backup verification as a post-enable note, not an enablement blocker.
- Clarified BitLocker enablement notes for OS and data drives.

## 0.7.4

- Improved remediation planning for unencrypted drives by collapsing dependent protector/protection actions behind the primary BitLocker enablement action.
- Prevents dependent actions such as `Resume-BitLocker` from appearing as safe automatic candidates when the drive is not encrypted.
- Keeps the full remediation detail available with `-Detailed -PlanFixes`.

## 0.7.3

- Improved default console UX for unencrypted drives by hiding dependent BitLocker checks behind the primary encryption finding.
- Keeps full detail available with `-Detailed`.
- Leaves JSON, HTML, enterprise NDJSON, and `-PassThru` output unchanged so automation still receives every finding.

## 0.7.2

- Clarified AD DS recovery escrow verification messages.
- Marks AD DS escrow verification as a best-effort feature under development when the current account cannot verify escrow.
- Explains that AD escrow validation requires delegated permission to read BitLocker recovery objects.

## 0.7.1

- Improved AD DS recovery escrow matching for closed enterprise networks.
- Matches recovery protector IDs across braces, hyphenated/non-hyphenated GUID forms, AD byte order, raw byte order, and GUIDs embedded in AD object names.
- Adds visible AD recovery object count to detailed recovery backup diagnostics without exporting recovery passwords.

## 0.7.0

- Split the module source into `Private` and `Public` files while keeping `bitdiag` as the only exported command.
- Converted `BitDiag.psm1` into a lightweight module loader.
- Added `build.ps1` to generate a portable single-file `dist\bitdiag.ps1` bundle.
- Updated launchers to suppress PowerShell approved-verb warnings for the CLI-style `bitdiag` command.
- Added smoke coverage for the portable single-file build.

## 0.6.0

- Added best-effort AD DS recovery escrow visibility check using recovery protector IDs.
- Added specific findings for fixed/removable write-deny BitLocker policies.
- Added specific findings for AD DS recovery backup requirement policies.
- Improved ESP remediation planning with `BdeHdCfg.exe -target default -size 550` as a manual high-risk action.
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
