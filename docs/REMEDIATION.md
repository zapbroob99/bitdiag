# Remediation

## Remediation Plan

Generate a remediation plan without changing the system:

```powershell
bitdiag -PlanFixes
```

The remediation plan classifies each item by action type, reason type, risk level, and whether BitDiag can apply it automatically:

```text
[AutomaticCandidate / MissingProtector / Low]
[Manual / Platform / High]
[Review / Policy / Medium]
```

When a drive is not encrypted, the default remediation plan focuses on the primary BitLocker enablement action and hides dependent actions such as protection resume, key protector creation, recovery password checks, and escrow checks. Use `-Detailed -PlanFixes` to show every dependent remediation item.

Manual and high-risk remediation items include guided steps when BitDiag should not apply the change automatically:

```text
auto    no - System partition changes can affect boot and must be reviewed on the target device.
steps
  1. Back up the device or confirm a recovery path.
  2. Open an elevated PowerShell or Command Prompt.
  3. Run: BdeHdCfg.exe -target default -size 550
  4. Reboot if Windows asks you to.
  5. Run: bitdiag -Run
```

Some BIOS-free system actions can be applied explicitly with `-Fix -Apply` after review:

```text
BdeHdCfg.exe -target default -size 550
mbr2gpt.exe /validate /allowFullOS
```

Firmware/BIOS-dependent actions such as enabling Secure Boot or enabling TPM remain guided manual steps.

## Automatic Remediation

Preview automatic remediation candidates without changing the system:

```powershell
bitdiag -Fix -WhatIf
```

Apply automatic remediation candidates selected by BitDiag:

```powershell
bitdiag -Fix -Apply
```

Preview and apply boot-risky automatic candidates:

```powershell
bitdiag -Fix -Risky -WhatIf
bitdiag -Fix -Risky -Apply
```

`bitdiag -Fix -Apply` applies only remediation candidates that BitDiag can map to a bounded command. It includes low-risk actions such as:

- Add a missing recovery password protector.
- Resume BitLocker protection when protection appears suspended/off.
- Enable auto-unlock for data drives.

It can also apply BIOS-free system actions after review, such as:

- Repair/create the system partition with `BdeHdCfg.exe -target default -size 550`.
- Run `mbr2gpt.exe /validate /allowFullOS` validation.

With explicit `-Risky`, BitDiag can also apply boot-risky Windows-side changes when the target partition is detected, such as making a non-system active MBR partition inactive.

BitDiag does not automatically change firmware settings, run MBR/GPT conversion, edit BitLocker policy registry values, or enable Secure Boot/TPM. Those items remain guided manual recommendations.

## Enabling BitLocker

`bitdiag -EnableBitLocker` is intentionally separate from `-Fix` because starting disk encryption is a higher-impact action. By default it only shows an enablement plan.

Show which unencrypted fixed drives can have BitLocker enabled:

```powershell
bitdiag -EnableBitLocker
```

Preview BitLocker enablement without changing the system:

```powershell
bitdiag -EnableBitLocker -WhatIf
```

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
