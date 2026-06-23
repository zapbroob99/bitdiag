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

        [string]$Operation,

        [string]$DriveLetter,

        [ValidateSet("EncryptionOff", "MissingProtector", "ProtectionOff", "AutoUnlockOff", "Platform", "DiskLayout", "Policy", "Runtime", "Other")]
        [string]$ReasonType = "Other",

        [ValidateSet("Low", "Medium", "High")]
        [string]$RiskLevel = "Medium"
    )

    $canApply = [bool]($ActionType -eq "AutomaticCandidate" -and $Operation -and $DriveLetter -and $RiskLevel -eq "Low")

    [PSCustomObject]@{
        Title      = $Title
        ActionType = $ActionType
        ReasonType = $ReasonType
        RiskLevel  = $RiskLevel
        CanApply   = $canApply
        Reason     = $Reason
        Command    = $Command
        Notes      = $Notes
        Operation  = $Operation
        DriveLetter = $DriveLetter
    }
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
                    -Notes "Enable BitLocker only after TPM, boot layout, policy, and recovery key escrow requirements are reviewed." `
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
                    -Notes "Confirm recovery key escrow requirements before or immediately after adding the protector." `
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

        if ($result.CheckName -eq "Secure Boot" -and $result.Status -in @("Warning", "Error")) {
            $plan += New-FixPlanItem `
                -Title "Review Secure Boot configuration" `
                -ActionType "Manual" `
                -Reason $result.Message `
                -Notes "Secure Boot must be changed in firmware/UEFI settings; do not automate this from BitDiag." `
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
                -ReasonType "Platform" `
                -RiskLevel "High"
            continue
        }

        if ($result.CheckName -match "EFI System Partition|^ESP on" -and $result.Status -in @("Warning", "Alert", "Error")) {
            $plan += New-FixPlanItem `
                -Title "Repair or create EFI System Partition" `
                -ActionType "Manual" `
                -Reason $result.Message `
                -Command "bdecfg -target default -size 550" `
                -Notes "Validate backups first. If the OS volume cannot shrink, review Event Viewer and move or back up blocking files before retrying." `
                -ReasonType "DiskLayout" `
                -RiskLevel "High"
            continue
        }

        if ($result.CheckName -match "active MBR partition" -and $result.Status -in @("Warning", "Alert", "Error")) {
            $plan += New-FixPlanItem `
                -Title "Review active MBR partition on secondary disk" `
                -ActionType "Manual" `
                -Reason $result.Message `
                -Command "diskpart -> select disk X -> list partition -> select partition Y -> inactive" `
                -Notes "Only make a partition inactive after confirming it is not required for boot and backups exist." `
                -ReasonType "DiskLayout" `
                -RiskLevel "High"
            continue
        }

        if ($result.CheckName -match "partition style|TPM \\+ boot mode|Boot mode" -and $result.Status -in @("Warning", "Alert", "Error")) {
            $plan += New-FixPlanItem `
                -Title "Review boot and disk layout before changing firmware or partitioning" `
                -ActionType "Manual" `
                -Reason $result.Message `
                -Notes "MBR/GPT conversion, firmware mode changes, and boot partition changes require a separate backup and migration plan." `
                -ReasonType "DiskLayout" `
                -RiskLevel "High"
            continue
        }

        if ($result.CheckName -match "BitLocker policy") {
            $plan += New-FixPlanItem `
                -Title "Review BitLocker policy" `
                -ActionType "Review" `
                -Reason $result.Message `
                -Notes "Policy is usually managed by Group Policy or MDM; review the source of authority before editing registry values." `
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

        $applyText = if ($item.CanApply) { "safe automatic candidate" } else { "manual/review only" }
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

function Invoke-SafeRemediation {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [object[]]$Plan,
        [switch]$Apply,
        [bool]$UseColor = $true
    )

    $automaticItems = @($Plan | Where-Object { $_.CanApply -and $_.Operation -and $_.DriveLetter })
    if (-not $automaticItems -or $automaticItems.Count -eq 0) {
        Write-ConsoleLine -Message "No safe automatic remediation candidates were found." -ForegroundColor Yellow -UseColor $UseColor
        return
    }

    if (-not $Apply -and -not $WhatIfPreference) {
        Write-ConsoleLine -Message "No changes were made. Re-run with -Fix -WhatIf to preview or -Fix -Apply to execute safe actions." -ForegroundColor Yellow -UseColor $UseColor
        Write-RemediationPlan -Plan $automaticItems -UseColor $UseColor
        return
    }

    foreach ($item in $automaticItems) {
        $target = "$($item.DriveLetter):"
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

