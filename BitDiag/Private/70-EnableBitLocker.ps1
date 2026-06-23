# BitDiag internal source: 70-EnableBitLocker.ps1

function New-BitLockerEnablePlanItem {
    param(
        [Parameter(Mandatory)]
        [string]$DriveLetter,

        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [ValidateSet("AutomaticCandidate", "Manual", "Review")]
        [string]$ActionType,

        [Parameter(Mandatory)]
        [string]$Reason,

        [string]$Command,

        [string]$Notes,

        [bool]$EnableAutoUnlock = $false,

        [ValidateSet("EncryptionOff", "Platform", "DiskLayout", "Runtime", "Other")]
        [string]$ReasonType = "EncryptionOff",

        [ValidateSet("Low", "Medium", "High")]
        [string]$RiskLevel = "Medium",

        [bool]$CanApply = $false,

        [bool]$IsSystemDrive = $false
    )

    [PSCustomObject]@{
        Title         = $Title
        ActionType    = $ActionType
        ReasonType    = $ReasonType
        RiskLevel     = $RiskLevel
        CanApply      = $CanApply
        Reason        = $Reason
        Command       = $Command
        Notes         = $Notes
        Operation     = "EnableBitLocker"
        DriveLetter   = $DriveLetter
        IsSystemDrive = $IsSystemDrive
        EnableAutoUnlock = $EnableAutoUnlock
    }
}

function Get-LogicalDiskInfo {
    param([string]$DriveLetter)

    try {
        Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}:'" -f $DriveLetter) -ErrorAction Stop
    } catch {
        $null
    }
}

function Get-BitLockerEnablePlan {
    param(
        [string[]]$DriveLetters,
        [object[]]$Results,
        [string]$BootMode,
        [object]$TpmState
    )

    $plan = @()
    $adminOk = -not ($Results | Where-Object { $_.Category -eq "Runtime" -and $_.CheckName -eq "Administrator" -and $_.Status -ne "OK" })
    $enableCommandAvailable = [bool](Get-Command Enable-BitLocker -ErrorAction SilentlyContinue)
    $systemDrive = if ($env:SystemDrive) { $env:SystemDrive.TrimEnd(":").ToUpperInvariant() } else { "C" }
    $canAutoUnlockDataDrives = $false
    try {
        $osVolume = Get-BitLockerVolume -MountPoint "${systemDrive}:" -ErrorAction Stop
        $canAutoUnlockDataDrives = ($osVolume.VolumeStatus -eq "FullyEncrypted" -and $osVolume.ProtectionStatus -eq "On")
    } catch {
        $canAutoUnlockDataDrives = $false
    }

    foreach ($driveLetter in $DriveLetters) {
        $drive = $driveLetter.Trim().TrimEnd(":").ToUpperInvariant()
        $target = "${drive}:"
        $isSystemDrive = ($drive -eq $systemDrive)

        if (-not (Test-Path "${drive}:\")) {
            $plan += New-BitLockerEnablePlanItem `
                -DriveLetter $drive `
                -Title "${drive}: skipped" `
                -ActionType "Review" `
                -Reason "${drive}: was not found." `
                -Notes "BitDiag only enables BitLocker on detected local fixed drives." `
                -ReasonType "Runtime" `
                -RiskLevel "Low" `
                -IsSystemDrive:$isSystemDrive
            continue
        }

        if (-not $adminOk) {
            $plan += New-BitLockerEnablePlanItem `
                -DriveLetter $drive `
                -Title "${drive}: cannot enable BitLocker without administrator rights" `
                -ActionType "Manual" `
                -Reason "PowerShell is not running as administrator." `
                -Notes "Run PowerShell as Administrator, then retry the same command." `
                -ReasonType "Runtime" `
                -RiskLevel "Medium" `
                -IsSystemDrive:$isSystemDrive
            continue
        }

        if (-not $enableCommandAvailable) {
            $plan += New-BitLockerEnablePlanItem `
                -DriveLetter $drive `
                -Title "${drive}: Enable-BitLocker is not available" `
                -ActionType "Manual" `
                -Reason "The BitLocker PowerShell cmdlet is not available in this session." `
                -Notes "Run on Windows with the BitLocker module available." `
                -ReasonType "Runtime" `
                -RiskLevel "Medium" `
                -IsSystemDrive:$isSystemDrive
            continue
        }

        $logicalDisk = Get-LogicalDiskInfo -DriveLetter $drive
        if ($logicalDisk -and [int]$logicalDisk.DriveType -ne 3) {
            $plan += New-BitLockerEnablePlanItem `
                -DriveLetter $drive `
                -Title "${drive}: skipped non-fixed drive" `
                -ActionType "Review" `
                -Reason "${drive}: is not a fixed local drive." `
                -Notes "Automatic BitLocker enablement is intentionally limited to fixed drives." `
                -ReasonType "DiskLayout" `
                -RiskLevel "Medium" `
                -IsSystemDrive:$isSystemDrive
            continue
        }

        if ($logicalDisk -and $logicalDisk.FileSystem -and $logicalDisk.FileSystem -ne "NTFS") {
            $plan += New-BitLockerEnablePlanItem `
                -DriveLetter $drive `
                -Title "${drive}: unsupported filesystem" `
                -ActionType "Manual" `
                -Reason "${drive}: filesystem is $($logicalDisk.FileSystem), expected NTFS." `
                -Notes "Convert or reformat the volume only through a separate storage change plan." `
                -ReasonType "DiskLayout" `
                -RiskLevel "High" `
                -IsSystemDrive:$isSystemDrive
            continue
        }

        try {
            $volume = Get-BitLockerVolume -MountPoint $target -ErrorAction Stop
        } catch {
            $plan += New-BitLockerEnablePlanItem `
                -DriveLetter $drive `
                -Title "${drive}: BitLocker state could not be read" `
                -ActionType "Review" `
                -Reason $_.Exception.Message `
                -Notes "Resolve the diagnostic error before enabling BitLocker." `
                -ReasonType "Runtime" `
                -RiskLevel "Medium" `
                -IsSystemDrive:$isSystemDrive
            continue
        }

        if ($volume.VolumeStatus -eq "FullyEncrypted") {
            $plan += New-BitLockerEnablePlanItem `
                -DriveLetter $drive `
                -Title "${drive}: already encrypted" `
                -ActionType "Review" `
                -Reason "${drive}: is already fully encrypted." `
                -Notes "No BitLocker enable action is needed." `
                -ReasonType "Other" `
                -RiskLevel "Low" `
                -IsSystemDrive:$isSystemDrive
            continue
        }

        if ($volume.VolumeStatus -ne "FullyDecrypted") {
            $plan += New-BitLockerEnablePlanItem `
                -DriveLetter $drive `
                -Title "${drive}: encryption already in progress or partial" `
                -ActionType "Review" `
                -Reason "${drive}: BitLocker volume status is $($volume.VolumeStatus)." `
                -Notes "Let the current encryption, decryption, or conversion state finish before starting a new enable action." `
                -ReasonType "EncryptionOff" `
                -RiskLevel "Medium" `
                -IsSystemDrive:$isSystemDrive
            continue
        }

        if ($isSystemDrive) {
            if ($BootMode -ne "UEFI") {
                $plan += New-BitLockerEnablePlanItem `
                    -DriveLetter $drive `
                    -Title "${drive}: review boot mode before enabling BitLocker" `
                    -ActionType "Manual" `
                    -Reason "The system boot mode is $BootMode." `
                    -Notes "BitDiag only auto-enables the OS drive on UEFI systems." `
                    -ReasonType "Platform" `
                    -RiskLevel "High" `
                    -IsSystemDrive:$isSystemDrive
                continue
            }

            if (-not $TpmState -or -not $TpmState.Present -or -not ($TpmState.Ready -or ($TpmState.Enabled -and $TpmState.Activated))) {
                $plan += New-BitLockerEnablePlanItem `
                    -DriveLetter $drive `
                    -Title "${drive}: TPM is not ready" `
                    -ActionType "Manual" `
                    -Reason "TPM is required before BitDiag can auto-enable BitLocker on the OS drive." `
                    -Notes "Enable and initialize TPM first, then retry." `
                    -ReasonType "Platform" `
                    -RiskLevel "High" `
                    -IsSystemDrive:$isSystemDrive
                continue
            }

            $plan += New-BitLockerEnablePlanItem `
                -DriveLetter $drive `
                -Title "${drive}: enable BitLocker on OS drive" `
                -ActionType "AutomaticCandidate" `
                -Reason "${drive}: is not encrypted." `
                -Command "Enable-BitLocker -MountPoint ${drive}: -EncryptionMethod XtsAes256 -UsedSpaceOnly -TpmProtector; Add-BitLockerKeyProtector -MountPoint ${drive}: -RecoveryPasswordProtector" `
                -Notes "Uses TPM protector, XtsAes256, and used-space-only encryption. Confirm recovery key escrow after enabling." `
                -ReasonType "EncryptionOff" `
                -RiskLevel "Medium" `
                -CanApply:$true `
                -IsSystemDrive:$isSystemDrive
            continue
        }

        $autoUnlockCommand = if ($canAutoUnlockDataDrives) { "; Enable-BitLockerAutoUnlock -MountPoint ${drive}:" } else { "" }
        $autoUnlockNotes = if ($canAutoUnlockDataDrives) {
            "Uses a recovery password protector, XtsAes256, used-space-only encryption, and enables auto-unlock because the OS drive is protected."
        } else {
            "Uses a recovery password protector, XtsAes256, and used-space-only encryption. Auto-unlock is skipped until the OS drive is fully protected."
        }

        $plan += New-BitLockerEnablePlanItem `
            -DriveLetter $drive `
            -Title "${drive}: enable BitLocker on data drive" `
            -ActionType "AutomaticCandidate" `
            -Reason "${drive}: is not encrypted." `
            -Command "Enable-BitLocker -MountPoint ${drive}: -EncryptionMethod XtsAes256 -UsedSpaceOnly -RecoveryPasswordProtector$autoUnlockCommand" `
            -Notes $autoUnlockNotes `
            -EnableAutoUnlock:$canAutoUnlockDataDrives `
            -ReasonType "EncryptionOff" `
            -RiskLevel "Medium" `
            -CanApply:$true `
            -IsSystemDrive:$isSystemDrive
    }

    $plan
}

function Write-BitLockerEnablePlan {
    param(
        [object[]]$Plan,
        [bool]$UseColor = $true
    )

    $width = Get-ConsoleWidth
    Write-ConsoleBanner -UseColor $UseColor
    Write-ConsoleLine -Message "" -UseColor $UseColor
    Write-ConsoleLine -Message "BitLocker enable plan" -ForegroundColor Cyan -UseColor $UseColor
    Write-Rule -Width $width -UseColor $UseColor

    if (-not $Plan -or $Plan.Count -eq 0) {
        Write-ConsoleLine -Message "No drives were found for BitLocker enablement." -ForegroundColor Yellow -UseColor $UseColor
        return
    }

    $index = 1
    foreach ($item in $Plan) {
        $color = if ($item.CanApply) { "Yellow" } elseif ($item.RiskLevel -eq "High") { "Red" } else { "Gray" }
        $applyText = if ($item.CanApply) { "eligible with -Apply" } else { "not applied automatically" }
        Write-ConsoleLine -Message ("{0,2}. [{1} / {2} / {3}] {4}" -f $index, $item.ActionType, $item.ReasonType, $item.RiskLevel, $item.Title) -ForegroundColor $color -UseColor $UseColor
        Write-ConsoleLine -Message ("    reason  {0}" -f $item.Reason) -ForegroundColor Gray -UseColor $UseColor
        Write-ConsoleLine -Message ("    apply   {0}" -f $applyText) -ForegroundColor Gray -UseColor $UseColor
        if ($item.Command) {
            Write-ConsoleLine -Message ("    command {0}" -f $item.Command) -ForegroundColor DarkYellow -UseColor $UseColor
        }
        if ($item.Notes) {
            Write-ConsoleLine -Message ("    notes   {0}" -f $item.Notes) -ForegroundColor DarkGray -UseColor $UseColor
        }
        $index++
    }
}

function Invoke-BitLockerEnable {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [object[]]$Plan,
        [switch]$Apply,
        [switch]$Quiet,
        [bool]$UseColor = $true
    )

    $items = @($Plan | Where-Object { $_.CanApply -and $_.DriveLetter })
    if (-not $items -or $items.Count -eq 0) {
        if (-not $Quiet) {
            Write-ConsoleLine -Message "No eligible unencrypted fixed drives were found for BitLocker enablement." -ForegroundColor Yellow -UseColor $UseColor
            Write-BitLockerEnablePlan -Plan $Plan -UseColor $UseColor
        }
        return
    }

    if (-not $Apply -and -not $WhatIfPreference) {
        if (-not $Quiet) {
            Write-ConsoleLine -Message "No changes were made. Re-run with -EnableBitLocker -WhatIf to preview or -EnableBitLocker -Apply to start encryption." -ForegroundColor Yellow -UseColor $UseColor
            Write-BitLockerEnablePlan -Plan $Plan -UseColor $UseColor
        }
        return
    }

    foreach ($item in $items) {
        $target = "$($item.DriveLetter):"
        if (-not $PSCmdlet.ShouldProcess($target, $item.Command)) {
            continue
        }

        if (-not $Apply) {
            continue
        }

        try {
            if ($item.IsSystemDrive) {
                Enable-BitLocker -MountPoint $target -EncryptionMethod XtsAes256 -UsedSpaceOnly -TpmProtector -ErrorAction Stop | Out-Null
                $updatedVolume = Get-BitLockerVolume -MountPoint $target -ErrorAction Stop
                $hasRecoveryPassword = $updatedVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }
                if (-not $hasRecoveryPassword) {
                    Add-BitLockerKeyProtector -MountPoint $target -RecoveryPasswordProtector -ErrorAction Stop | Out-Null
                }
            } else {
                Enable-BitLocker -MountPoint $target -EncryptionMethod XtsAes256 -UsedSpaceOnly -RecoveryPasswordProtector -ErrorAction Stop | Out-Null
                if ($item.EnableAutoUnlock) {
                    try {
                        Enable-BitLockerAutoUnlock -MountPoint $target -ErrorAction Stop | Out-Null
                    } catch {
                        Write-ConsoleLine -Message "Warning: BitLocker started on $target, but auto-unlock could not be enabled: $($_.Exception.Message)" -ForegroundColor Yellow -UseColor $UseColor
                    }
                }
            }

            if (-not $Quiet) {
                Write-ConsoleLine -Message "Started BitLocker: $($item.Title)" -ForegroundColor Green -UseColor $UseColor
            }
        } catch {
            Write-ConsoleLine -Message "Failed: $($item.Title) - $($_.Exception.Message)" -ForegroundColor Red -UseColor $UseColor
        }
    }
}

