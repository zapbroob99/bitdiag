# Troubleshooting Coverage

BitDiag focuses on the common cases that block BitLocker enablement or make protected data drives hard to use:

- TPM missing, disabled, not ready, or incompatible with the current boot mode.
- Legacy BIOS instead of UEFI for modern TPM-based BitLocker.
- Secure Boot disabled or unavailable.
- Missing or invalid EFI System Partition, with a manual `BdeHdCfg.exe -target default -size 550` repair recommendation.
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
