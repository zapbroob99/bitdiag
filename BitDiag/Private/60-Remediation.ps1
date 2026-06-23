# BitDiag internal source: 60-Remediation.ps1

function New-FixPlanItem {
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [ValidateSet("AutomaticCandidate", "Manual", "Review")]
        [string]$ActionType,

        [Parameter(Mandatory)]
        [string]$Reason,

        [string]$Command,

        [string]$Notes,

        [string[]]$Steps,

        [string]$AutoApplyReason,

        [string]$Operation,

        [string]$DriveLetter,

        [ValidateSet("EncryptionOff", "MissingProtector", "ProtectionOff", "AutoUnlockOff", "Platform", "DiskLayout", "Policy", "Runtime", "Other")]
        [string]$ReasonType = "Other",

        [ValidateSet("Low", "Medium", "High")]
        [string]$RiskLevel = "Medium",

        [bool]$CanApply = $false,

        [bool]$RequiresRisky = $false,

        [int]$DiskNumber = -1,

        [int]$PartitionNumber = -1
    )

    $canApply = [bool]($CanApply -or ($ActionType -eq "AutomaticCandidate" -and $Operation -and $DriveLetter -and $RiskLevel -eq "Low"))

    [PSCustomObject]@{
        Title      = $Title
        ActionType = $ActionType
        ReasonType = $ReasonType
        RiskLevel  = $RiskLevel
        CanApply   = $canApply
        Reason     = $Reason
        Command    = $Command
        Notes      = $Notes
        Steps      = @($Steps)
        AutoApplyReason = $AutoApplyReason
        Operation  = $Operation
        DriveLetter = $DriveLetter
        RequiresRisky = $RequiresRisky
        DiskNumber = $DiskNumber
        PartitionNumber = $PartitionNumber
    }
}

function Get-ResultDetailValue {
    param(
        [object]$Details,
        [string]$Name
    )

    if ($null -eq $Details) {
        return $null
    }

    if ($Details -is [System.Collections.IDictionary] -and $Details.Contains($Name)) {
        return $Details[$Name]
    }

    $property = $Details.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    $null
}

function Get-RemediationPlan {
    param(
        [object[]]$Results,
        [switch]$Detailed
    )

    $plan = @()
    $dependentPatterns = @(
        "encryption method",
        "encryption progress",
        "protection",
        "suspension",
        "key protectors",
        "recovery password",
        "recovery backup",
        "auto-unlock"
    )
    $disabledDrives = @(
        $Results |
            Where-Object {
                $_.CheckName -match "^([A-Z]): encryption$" -and
                $_.Status -in @("Warning", "Alert", "Error") -and
                $_.Message -match "not encrypted|encryption.*off|not protected"
            } |
            ForEach-Object {
                if ($_.CheckName -match "^([A-Z]):") {
                    $Matches[1]
                }
            } |
            Select-Object -Unique
    )
    $hiddenDependentCounts = @{}

    foreach ($result in $Results) {
        if ($result.Status -notin @("Warning", "Alert", "Error")) {
            continue
        }

        $drive = $null
        if (-not $Detailed -and $result.CheckName -match "^([A-Z]): (.+)$") {
            $drive = $Matches[1]
            $check = $Matches[2]
            if ($drive -in $disabledDrives -and $check -in $dependentPatterns) {
                if (-not $hiddenDependentCounts.ContainsKey($drive)) {
                    $hiddenDependentCounts[$drive] = 0
                }
                $hiddenDependentCounts[$drive]++
                continue
            }
        }

        if ($result.CheckName -match "^([A-Z]): encryption$") {
            $drive = $Matches[1]
            if ($result.Message -match "not encrypted|encryption.*off|not protected") {
                $plan += New-FixPlanItem `
                    -Title "${drive}: enable BitLocker" `
                -ActionType "Manual" `
                -Reason $result.Message `
                -Command "bitdiag -EnableBitLocker -Drives $drive -Apply" `
                -Notes "Enable BitLocker only after TPM and boot layout prerequisites are reviewed. After enabling, verify that the recovery password is backed up." `
                -AutoApplyReason "Starting disk encryption is a higher-impact action and requires explicit -EnableBitLocker -Apply." `
                -Steps @(
                    "Run: bitdiag -EnableBitLocker -Drives $drive",
                    "Review the ready/blocked/review summary.",
                    "Resolve any blockers shown in the enablement plan.",
                    "Run: bitdiag -EnableBitLocker -Drives $drive -Apply",
                    "After encryption starts, run: bitdiag -Run -Drives $drive"
                ) `
                -DriveLetter $drive `
                -ReasonType "EncryptionOff" `
                -RiskLevel "High"
                continue
            }
        }

        if ($result.CheckName -match "^([A-Z]): recovery password") {
            $drive = $Matches[1]
            if ($result.Message -match "missing|not detected") {
                $plan += New-FixPlanItem `
                    -Title "${drive}: add recovery password protector" `
                    -ActionType "AutomaticCandidate" `
                    -Reason $result.Message `
                    -Command "Add-BitLockerKeyProtector -MountPoint ${drive}: -RecoveryPasswordProtector" `
                    -Notes "After adding the protector, verify that the recovery password is backed up." `
                    -Operation "AddRecoveryPassword" `
                    -DriveLetter $drive `
                    -ReasonType "MissingProtector" `
                    -RiskLevel "Low"
                continue
            }
        }

        if ($result.CheckName -match "^([A-Z]): protection" -and $result.Status -in @("Warning", "Error")) {
            $drive = $Matches[1]
            $plan += New-FixPlanItem `
                -Title "${drive}: resume or enable BitLocker protection" `
                -ActionType "AutomaticCandidate" `
                -Reason $result.Message `
                -Command "Resume-BitLocker -MountPoint ${drive}:" `
                -Notes "Only run after confirming recovery keys are backed up." `
                -Operation "ResumeProtection" `
                -DriveLetter $drive `
                -ReasonType "ProtectionOff" `
                -RiskLevel "Low"
            continue
        }

        if ($result.CheckName -match "^([A-Z]): suspension" -and $result.Status -eq "Warning") {
            $drive = $Matches[1]
            $plan += New-FixPlanItem `
                -Title "${drive}: clear suspended protection state" `
                -ActionType "AutomaticCandidate" `
                -Reason $result.Message `
                -Command "Resume-BitLocker -MountPoint ${drive}:" `
                -Notes "This is safe only when recovery keys are available." `
                -Operation "ResumeProtection" `
                -DriveLetter $drive `
                -ReasonType "ProtectionOff" `
                -RiskLevel "Low"
            continue
        }

        if ($result.CheckName -match "^([A-Z]): auto-unlock" -and $result.Status -eq "Warning") {
            $drive = $Matches[1]
            $plan += New-FixPlanItem `
                -Title "${drive}: enable auto-unlock" `
                -ActionType "AutomaticCandidate" `
                -Reason $result.Message `
                -Command "Enable-BitLockerAutoUnlock -MountPoint ${drive}:" `
                -Notes "Use for data drives only, after the OS drive is protected." `
                -Operation "EnableAutoUnlock" `
                -DriveLetter $drive `
                -ReasonType "AutoUnlockOff" `
                -RiskLevel "Low"
            continue
        }

        if ($result.Category -eq "Platform" -and $result.CheckName -ne "TPM" -and $result.Message -match "Access denied|access is denied|proper privileges|check failed|could not be detected") {
            $plan += New-FixPlanItem `
                -Title "Run platform checks as administrator" `
                -ActionType "Review" `
                -Reason $result.Message `
                -Command "Start PowerShell as Administrator, then run: bitdiag -Run" `
                -Notes "BitDiag should not recommend firmware or TPM changes until platform checks complete successfully." `
                -AutoApplyReason "The diagnostic needs elevated platform access before a safe remediation can be selected." `
                -Steps @(
                    "Open PowerShell as Administrator.",
                    "Run: bitdiag -Run",
                    "Review the updated System section.",
                    "Generate a fresh remediation plan with: bitdiag -PlanFixes"
                ) `
                -ReasonType "Runtime" `
                -RiskLevel "Medium"
            continue
        }

        if ($result.CheckName -eq "Secure Boot" -and $result.Status -in @("Warning", "Error")) {
            $plan += New-FixPlanItem `
                -Title "Review Secure Boot configuration" `
                -ActionType "Manual" `
                -Reason $result.Message `
                -Notes "Secure Boot must be changed in firmware/UEFI settings; do not automate this from BitDiag." `
                -AutoApplyReason "Secure Boot is controlled by firmware/UEFI and cannot be safely changed by BitDiag." `
                -Steps @(
                    "Confirm the device boots in UEFI mode.",
                    "Restart into firmware/UEFI settings.",
                    "Enable Secure Boot.",
                    "Save firmware settings and boot Windows.",
                    "Run: bitdiag -Run"
                ) `
                -ReasonType "Platform" `
                -RiskLevel "High"
            continue
        }

        if ($result.CheckName -eq "TPM" -and $result.Status -in @("Warning", "Alert", "Error")) {
            $plan += New-FixPlanItem `
                -Title "Review TPM availability" `
                -ActionType "Manual" `
                -Reason $result.Message `
                -Command "Confirm TPM 2.0 support in firmware settings." `
                -Notes "TPM availability is a platform prerequisite for standard BitLocker protection and usually requires firmware, BIOS, or hardware review." `
                -AutoApplyReason "TPM presence/readiness depends on firmware or hardware state." `
                -Steps @(
                    "Run: tpm.msc",
                    "Confirm TPM is present and ready for use.",
                    "If TPM is disabled or hidden, enable it in firmware/UEFI settings.",
                    "Boot Windows and run: bitdiag -Run"
                ) `
                -ReasonType "Platform" `
                -RiskLevel "High"
            continue
        }

        if ($result.Category -eq "Disk" -and $result.Message -match "Access denied|access is denied|proper privileges|check failed") {
            $plan += New-FixPlanItem `
                -Title "Run disk layout checks as administrator" `
                -ActionType "Review" `
                -Reason $result.Message `
                -Command "Start PowerShell as Administrator, then run: bitdiag -Run" `
                -Notes "BitDiag should not recommend partition repair steps when the disk layout check itself could not complete." `
                -AutoApplyReason "The diagnostic needs elevated disk access before a safe remediation can be selected." `
                -Steps @(
                    "Open PowerShell as Administrator.",
                    "Run: bitdiag -Run",
                    "Review the updated Disk layout section.",
                    "Generate a fresh remediation plan with: bitdiag -PlanFixes"
                ) `
                -ReasonType "Runtime" `
                -RiskLevel "Medium"
            continue
        }

        if ($result.CheckName -match "EFI System Partition|^ESP on" -and $result.Status -in @("Warning", "Alert", "Error")) {
            $plan += New-FixPlanItem `
                -Title "Repair or create EFI System Partition" `
                -ActionType "AutomaticCandidate" `
                -Reason $result.Message `
                -Command "BdeHdCfg.exe -target default -size 550" `
                -Notes "Validate backups first. If the OS volume cannot shrink, review Event Viewer and move or back up blocking files before retrying." `
                -AutoApplyReason "BIOS access is not required, but this can change system partition layout and may request a reboot." `
                -Steps @(
                    "Back up the device or confirm a recovery path.",
                    "Open an elevated PowerShell or Command Prompt.",
                    "Run: BdeHdCfg.exe -target default -size 550",
                    "Reboot if Windows asks you to.",
                    "Run: bitdiag -Run"
                ) `
                -Operation "RepairSystemPartition" `
                -ReasonType "DiskLayout" `
                -RiskLevel "High" `
                -CanApply:$true
            continue
        }

        if ($result.CheckName -match "active MBR partition" -and $result.Status -in @("Warning", "Alert", "Error")) {
            $activeDrive = Get-ResultDetailValue -Details $result.Details -Name "DriveLetter"
            $diskNumber = Get-ResultDetailValue -Details $result.Details -Name "DiskNumber"
            $partitionNumber = Get-ResultDetailValue -Details $result.Details -Name "PartitionNumber"
            $systemDrive = if ($env:SystemDrive) { $env:SystemDrive.TrimEnd(":").ToUpperInvariant() } else { "C" }
            $hasTarget = ($null -ne $diskNumber -and $null -ne $partitionNumber -and -not [string]::IsNullOrWhiteSpace([string]$activeDrive))
            $activeDriveText = if ($activeDrive) { ([string]$activeDrive).TrimEnd(":").ToUpperInvariant() } else { "" }

            if ($hasTarget -and $activeDriveText -ne $systemDrive) {
                $plan += New-FixPlanItem `
                    -Title "${activeDriveText}: make active MBR partition inactive" `
                    -ActionType "AutomaticCandidate" `
                    -Reason $result.Message `
                    -Command "Set-Partition -DiskNumber $diskNumber -PartitionNumber $partitionNumber -IsActive `$false" `
                    -Notes "This is intended for secondary data disks only. It requires -Risky because selecting the wrong partition can affect boot." `
                    -AutoApplyReason "BIOS access is not required, but changing active flags is boot-risky and requires explicit -Risky." `
                    -Steps @(
                        "Confirm $activeDriveText`: is not the Windows system or boot volume.",
                        "Preview with: bitdiag -Fix -Risky -WhatIf",
                        "Apply with: bitdiag -Fix -Risky -Apply",
                        "Run: bitdiag -Run"
                    ) `
                    -Operation "SetPartitionInactive" `
                    -DriveLetter $activeDriveText `
                    -ReasonType "DiskLayout" `
                    -RiskLevel "High" `
                    -CanApply:$true `
                    -RequiresRisky:$true `
                    -DiskNumber ([int]$diskNumber) `
                    -PartitionNumber ([int]$partitionNumber)
            } else {
                $plan += New-FixPlanItem `
                    -Title "Review active MBR partition on secondary disk" `
                    -ActionType "Manual" `
                    -Reason $result.Message `
                    -Command "diskpart -> select disk X -> list partition -> select partition Y -> inactive" `
                    -Notes "Only make a partition inactive after confirming it is not required for boot and backups exist." `
                    -AutoApplyReason "Changing active/inactive partition flags can make Windows unbootable if the wrong partition is selected." `
                    -Steps @(
                        "Confirm the disk and partition number from Disk Management or BitDiag output.",
                        "Open an elevated Command Prompt.",
                        "Run: diskpart",
                        "Run: list disk",
                        "Run: select disk X",
                        "Run: list partition",
                        "Run: select partition Y",
                        "Run: inactive",
                        "Run: exit",
                        "Run: bitdiag -Run"
                    ) `
                    -ReasonType "DiskLayout" `
                    -RiskLevel "High"
            }
            continue
        }

        if ($result.CheckName -match "partition style|TPM \\+ boot mode" -and $result.Status -in @("Warning", "Alert", "Error")) {
            $plan += New-FixPlanItem `
                -Title "Validate boot and disk layout before changing firmware or partitioning" `
                -ActionType "AutomaticCandidate" `
                -Reason $result.Message `
                -Command "mbr2gpt.exe /validate /allowFullOS" `
                -Notes "MBR/GPT conversion, firmware mode changes, and boot partition changes require a separate backup and migration plan." `
                -AutoApplyReason "BitDiag can run validation automatically, but conversion or firmware changes remain manual." `
                -Steps @(
                    "Back up the device or confirm a recovery path.",
                    "If conversion is being considered, run: mbr2gpt.exe /validate /allowFullOS",
                    "Do not convert or change firmware mode until validation succeeds and the migration path is approved.",
                    "After approved changes, boot Windows and run: bitdiag -Run"
                ) `
                -Operation "ValidateMbr2Gpt" `
                -ReasonType "DiskLayout" `
                -RiskLevel "High" `
                -CanApply:$true
            continue
        }

        if ($result.CheckName -match "BitLocker policy") {
            $plan += New-FixPlanItem `
                -Title "Review BitLocker policy" `
                -ActionType "Review" `
                -Reason $result.Message `
                -Notes "Policy is usually managed by Group Policy or MDM; review the source of authority before editing registry values." `
                -AutoApplyReason "BitLocker policy is usually centrally managed and should be changed at the source of authority." `
                -Steps @(
                    "Identify whether policy comes from Group Policy, MDM, or local registry.",
                    "Review the configured BitLocker policy with the endpoint management owner.",
                    "Apply policy changes from the source of authority.",
                    "Run: gpupdate /force",
                    "Run: bitdiag -Run"
                ) `
                -ReasonType "Policy" `
                -RiskLevel "Medium"
            continue
        }

        if ($result.Fix) {
            $reasonType = if ($result.Category -eq "Runtime") { "Runtime" } else { "Other" }
            $plan += New-FixPlanItem `
                -Title $result.CheckName `
                -ActionType "Review" `
                -Reason $result.Message `
                -Command $result.Fix `
                -Notes "Review this recommendation before applying it." `
                -ReasonType $reasonType `
                -RiskLevel "Medium"
        }
    }

    foreach ($drive in $disabledDrives) {
        if (-not $hiddenDependentCounts.ContainsKey($drive) -or $hiddenDependentCounts[$drive] -eq 0) {
            continue
        }

        $primary = $plan | Where-Object { $_.Title -eq "${drive}: enable BitLocker" } | Select-Object -First 1
        if ($primary) {
            $primary.Notes = "$($primary.Notes) $($hiddenDependentCounts[$drive]) dependent remediation items are hidden in the default plan; use -Detailed with -PlanFixes to show them."
        }
    }

    $plan | Sort-Object Title, ActionType -Unique
}

function Write-RemediationPlan {
    param(
        [object[]]$Plan,
        [bool]$UseColor = $true
    )

    $width = Get-ConsoleWidth
    Write-ConsoleBanner -UseColor $UseColor
    Write-ConsoleLine -Message "" -UseColor $UseColor
    Write-ConsoleLine -Message "Remediation plan" -ForegroundColor Cyan -UseColor $UseColor
    Write-Rule -Width $width -UseColor $UseColor

    if (-not $Plan -or $Plan.Count -eq 0) {
        Write-ConsoleLine -Message "No remediation actions were generated from the current diagnostics." -ForegroundColor Green -UseColor $UseColor
        return
    }

    $index = 1
    foreach ($item in $Plan) {
        $color = switch ($item.ActionType) {
            "AutomaticCandidate" { "Yellow" }
            "Manual"             { "Red" }
            default              { "Gray" }
        }

        $applyText = if ($item.CanApply) {
            if ($item.RequiresRisky) { "risk accepted with -Risky -Apply" }
            elseif ($item.RiskLevel -eq "Low") { "safe automatic candidate" }
            else { "automatic with -Apply after review" }
        } else {
            "manual/review only"
        }
        Write-ConsoleLine -Message ("{0,2}. [{1} / {2} / {3}] {4}" -f $index, $item.ActionType, $item.ReasonType, $item.RiskLevel, $item.Title) -ForegroundColor $color -UseColor $UseColor
        Write-ConsoleLine -Message ("    reason  {0}" -f $item.Reason) -ForegroundColor Gray -UseColor $UseColor
        Write-ConsoleLine -Message ("    apply   {0}" -f $applyText) -ForegroundColor Gray -UseColor $UseColor
        if ($item.AutoApplyReason) {
            $autoPrefix = if ($item.CanApply) {
                if ($item.RequiresRisky) { "yes with -Risky" } else { "yes" }
            } else {
                "no"
            }
            $autoText = "$autoPrefix - $($item.AutoApplyReason)"
            Write-ConsoleLine -Message ("    auto    {0}" -f $autoText) -ForegroundColor DarkGray -UseColor $UseColor
        }
        if ($item.Command) {
            Write-ConsoleLine -Message ("    command {0}" -f $item.Command) -ForegroundColor DarkYellow -UseColor $UseColor
        }
        if ($item.Notes) {
            Write-ConsoleLine -Message ("    notes   {0}" -f $item.Notes) -ForegroundColor DarkGray -UseColor $UseColor
        }
        if ($item.Steps -and $item.Steps.Count -gt 0) {
            Write-ConsoleLine -Message "    steps" -ForegroundColor Gray -UseColor $UseColor
            $stepIndex = 1
            foreach ($step in $item.Steps) {
                Write-ConsoleLine -Message ("      {0}. {1}" -f $stepIndex, $step) -ForegroundColor Gray -UseColor $UseColor
                $stepIndex++
            }
        }
        $index++
    }
}

function Invoke-SafeRemediation {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [object[]]$Plan,
        [switch]$Apply,
        [switch]$Risky,
        [bool]$UseColor = $true
    )

    $riskFilteredItems = @($Plan | Where-Object { $_.CanApply -and $_.Operation })
    $automaticItems = @($riskFilteredItems | Where-Object { $Risky -or -not $_.RequiresRisky })
    if (-not $automaticItems -or $automaticItems.Count -eq 0) {
        $riskyCount = @($riskFilteredItems | Where-Object { $_.RequiresRisky }).Count
        if ($riskyCount -gt 0 -and -not $Risky) {
            Write-ConsoleLine -Message "Only risky automatic remediation candidates were found. Re-run with -Fix -Risky -WhatIf to preview or -Fix -Risky -Apply to execute them." -ForegroundColor Yellow -UseColor $UseColor
        } else {
            Write-ConsoleLine -Message "No automatic remediation candidates were found." -ForegroundColor Yellow -UseColor $UseColor
        }
        return
    }

    if (-not $Apply -and -not $WhatIfPreference) {
        $riskHint = if ($Risky) { " Risky candidates are included." } else { "" }
        Write-ConsoleLine -Message "No changes were made. Re-run with -Fix -WhatIf to preview or -Fix -Apply to execute automatic actions.$riskHint" -ForegroundColor Yellow -UseColor $UseColor
        Write-RemediationPlan -Plan $automaticItems -UseColor $UseColor
        return
    }

    foreach ($item in $automaticItems) {
        $target = if ($item.DriveLetter) { "$($item.DriveLetter):" } else { $item.Title }
        $action = $item.Command

        if (-not $PSCmdlet.ShouldProcess($target, $action)) {
            continue
        }

        if (-not $Apply) {
            continue
        }

        try {
            switch ($item.Operation) {
                "AddRecoveryPassword" {
                    Add-BitLockerKeyProtector -MountPoint $target -RecoveryPasswordProtector -ErrorAction Stop | Out-Null
                }
                "ResumeProtection" {
                    Resume-BitLocker -MountPoint $target -ErrorAction Stop | Out-Null
                }
                "EnableAutoUnlock" {
                    Enable-BitLockerAutoUnlock -MountPoint $target -ErrorAction Stop | Out-Null
                }
                "RepairSystemPartition" {
                    $tool = Get-Command BdeHdCfg.exe -ErrorAction Stop
                    $process = Start-Process -FilePath $tool.Source -ArgumentList @("-target", "default", "-size", "550") -Wait -PassThru -WindowStyle Hidden
                    if ($process.ExitCode -ne 0) {
                        throw "BdeHdCfg.exe exited with code $($process.ExitCode)."
                    }
                }
                "ValidateMbr2Gpt" {
                    $tool = Get-Command mbr2gpt.exe -ErrorAction Stop
                    $process = Start-Process -FilePath $tool.Source -ArgumentList @("/validate", "/allowFullOS") -Wait -PassThru -WindowStyle Hidden
                    if ($process.ExitCode -ne 0) {
                        throw "mbr2gpt.exe validation exited with code $($process.ExitCode)."
                    }
                }
                "SetPartitionInactive" {
                    if ($item.DiskNumber -lt 0 -or $item.PartitionNumber -lt 0) {
                        throw "Disk and partition numbers are required to make a partition inactive."
                    }

                    Set-Partition -DiskNumber $item.DiskNumber -PartitionNumber $item.PartitionNumber -IsActive $false -ErrorAction Stop
                }
                default {
                    Write-ConsoleLine -Message "Skipped unsupported remediation operation: $($item.Operation)" -ForegroundColor Yellow -UseColor $UseColor
                    continue
                }
            }

            Write-ConsoleLine -Message "Applied: $($item.Title)" -ForegroundColor Green -UseColor $UseColor
        } catch {
            Write-ConsoleLine -Message "Failed: $($item.Title) - $($_.Exception.Message)" -ForegroundColor Red -UseColor $UseColor
        }
    }
}

