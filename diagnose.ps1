# ============================
# BitLocker Troubleshooter 
# ============================


function Check-SecureBoot {
    try {
        $sb = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State"
        if ($sb.UEFISecureBootEnabled -eq 1) {
            Write-Host "[OK] Secure Boot is enabled." -ForegroundColor Green
        } else {
            Write-Host "[WARNING] Secure Boot is disabled -> Enable it in BIOS." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Secure Boot check failed: $_" -ForegroundColor Red
    }
}


function Check-TPM {
    try {
        $tpm = Get-CimInstance -Namespace "root\cimv2\Security\MicrosoftTpm" -ClassName Win32_Tpm -ErrorAction SilentlyContinue
        if ($tpm -and $tpm.IsEnabled_InitialValue) {
            Write-Host "[OK] TPM is enabled." -ForegroundColor Green
        } else {
            Write-Host "[WARNING] TPM is disabled -> Enable + reset in BIOS." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "TPM check failed: $_" -ForegroundColor Red
    }
}


function Check-BootMode {
    try {
        $BootMode = bcdedit | Select-String "path"
        if ($BootMode -match "efi") {
            Write-Host "[OK] Boot mode is UEFI." -ForegroundColor Green
        } else {
            Write-Host "[OK] Boot mode is Legacy BIOS." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Boot mode check failed: $_" -ForegroundColor Red
    }
}






function Check-DiskType {
    $disks = Get-Disk
    foreach ($disk in $disks) {
        if ($disk.PartitionStyle -eq "RAW") {
            Write-Host "[WARNING] Disk partition is invalid." -ForegroundColor Yellow
        } elseif ($disk.PartitionStyle -eq "GPT") {
            Write-Host "[OK] Disk is GPT." -ForegroundColor Green
        } elseif ($disk.PartitionStyle -eq "MBR") {
            Write-Host "[WARNING] Disk is MBR -> GPT is recommended." -ForegroundColor Yellow
        }
    }
}


function Check-ESP {
    $esp = Get-Partition | Where-Object { $_.GptType -eq "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}" }
    if ($esp) {
        $vol = Get-Volume -Partition $esp
        if ($vol.FileSystem -eq "FAT32") {
            Write-Host "[OK] EFI System Partition is FAT32." -ForegroundColor Green
        } else {
            Write-Host "[WARNING] EFI System Partition is not FAT32 -> BitLocker may fail." -ForegroundColor Yellow
        }
    } else {
        Write-Host "[WARNING] EFI System Partition not found." -ForegroundColor Yellow
    }
}


function Check-DiskDynamic {
    $disks = Get-Disk
    foreach ($disk in $disks) {
        if ($disk.IsDynamic) {
            Write-Host "[WARNING] Disk $($disk.Number) is Dynamic -> BitLocker not supported." -ForegroundColor Yellow
        } else {
            Write-Host "[OK] Disk $($disk.Number) is Basic." -ForegroundColor Green
        }
    }
}


function Check-MBRActive {
    $parts = Get-Partition | Where-Object { $_.IsActive -eq $true }
    foreach ($p in $parts) {
        Write-Host "[WARNING] Partition $($p.DriveLetter) is Active (MBR) -> Set Inactive before BitLocker." -ForegroundColor Yellow
    }
}


function Check-FileSystem($driveLetter) {
    $vol = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue
    if ($null -eq $vol) { return }
    $fs = $vol.FileSystem
    if ($fs -eq "NTFS" -or $fs -eq "FAT32") {
        Write-Host "[OK] ${driveLetter}: filesystem is compatible ($fs)." -ForegroundColor Green
    } else {
        Write-Host "[WARNING] ${driveLetter}: filesystem is $fs -> BitLocker not supported." -ForegroundColor Yellow
    }
}

# Unallocated space check
function Check-Unallocated {
    $disks = Get-Disk
    foreach ($disk in $disks) {
        if ($disk.NumberOfPartitions -eq 0) {
            Write-Host "[WARNING] Disk $($disk.Number) has unallocated space -> Fix partition table." -ForegroundColor Yellow
        }
    }
}


function Check-RegistryPolicy {
    try {
        if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FVE") {
            $val = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FVE"
            Write-Host "[WARNING] BitLocker policy may block writes -> Set registry value to 0 if needed." -ForegroundColor Yellow
        } else {
            Write-Host "[OK] No blocking BitLocker policy found." -ForegroundColor Green
        }
    } catch {
        Write-Host "Registry policy check failed: $_" -ForegroundColor Red
    }
}
function Check-TPMAndBoot {
    try {
        $tpm = Get-CimInstance -Namespace "root\cimv2\Security\MicrosoftTpm" -ClassName Win32_Tpm -ErrorAction SilentlyContinue
        $BootMode = bcdedit | Select-String "path"

        if ($tpm -and $tpm.IsEnabled_InitialValue) {
            if ($BootMode -notmatch "efi") {
                Write-Host "[ALERT] TPM 2.0 is enabled but system is in Legacy BIOS mode -> BitLocker auto-unlock will fail. Switch BIOS to UEFI Only." -ForegroundColor Red
            } else {
                Write-Host "[OK] TPM 2.0 is enabled and system is UEFI." -ForegroundColor Green
            }
        } else {
            Write-Host "[WARNING] TPM is disabled -> Enable + reset in BIOS." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "TPM/Boot mode check failed: $_" -ForegroundColor Red
    }
}



function Check-Protectors($driveLetter) {
    if (-not (Test-Path "${driveLetter}:\\")) { return }

    $status = manage-bde -status "${driveLetter}:"

    if ($status -match "Numerical Password") {
        Write-Host "[OK] ${driveLetter}: Numerical Password exists." -ForegroundColor Green
    } else {
        Write-Host "[WARNING] ${driveLetter}: Numerical Password missing -> Run: manage-bde -protectors -add ${driveLetter}: -RecoveryPassword" -ForegroundColor Yellow
    }

    if ($driveLetter -ne "C") {
        if ($status -notmatch "External Key") {
            Write-Host "[WARNING] ${driveLetter}: Auto-unlock not enabled -> Run: manage-bde -autounlock -enable ${driveLetter}:" -ForegroundColor Yellow
        } else {
            Write-Host "[OK] ${driveLetter}: Auto-unlock enabled." -ForegroundColor Green
        }
    }

    
    Write-Host "=== ${driveLetter}: Current Protectors ===" -ForegroundColor Cyan
    try {
        $protectors = manage-bde -protectors -get "${driveLetter}:"
        $protectors | ForEach-Object { Write-Host $_ }
    } catch {
        Write-Host "Protector list failed: $_" -ForegroundColor Red
    }
}

function Check-TPMAndBoot {
    try {
        # TPM bilgisi
        $tpm = Get-CimInstance -Namespace "root\cimv2\Security\MicrosoftTpm" -ClassName Win32_Tpm -ErrorAction SilentlyContinue
        # Boot mode bilgisi (bcdedit üzerinden)
        $BootMode = bcdedit | Select-String "path"

        if ($tpm -and $tpm.IsEnabled_InitialValue) {
            if ($BootMode -match "efi") {
                Write-Host "[OK] TPM 2.0 is enabled and system is UEFI." -ForegroundColor Green
            } else {
                Write-Host "[ALERT] TPM 2.0 is enabled but system is Legacy BIOS -> BitLocker auto-unlock will fail. Switch BIOS to UEFI Only." -ForegroundColor Red
            }
        } else {
            Write-Host "[WARNING] TPM is disabled -> Enable + reset in BIOS." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "TPM/Boot mode check failed: $_" -ForegroundColor Red
    }
}



# ============================
# Main Execution
# ============================

Write-Host "=== Starting BitLocker Diagnostics ===" -ForegroundColor Cyan

Check-SecureBoot
Check-TPMAndBoot
Check-DiskType
Check-ESP
Check-DiskDynamic
Check-MBRActive
Check-Unallocated
Check-RegistryPolicy
Check-FileSystem -driveLetter "C"
Check-FileSystem -driveLetter "D"
Check-Protectors -driveLetter "C"
Check-Protectors -driveLetter "D"

Write-Host "=== Diagnostics Completed ===" -ForegroundColor Cyan

