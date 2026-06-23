<#
.SYNOPSIS
    Basic smoke tests for BitDiag.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot "BitDiag\BitDiag.psd1"
$launcherPath = Join-Path $repoRoot "bitdiag.ps1"
$diagnosePath = Join-Path $repoRoot "diagnose.ps1"
$buildPath = Join-Path $repoRoot "build.ps1"

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$manifest = Test-ModuleManifest -Path $modulePath
Assert-True -Condition ($manifest.Name -eq "BitDiag") -Message "Module manifest name should be BitDiag."
Assert-True -Condition ($manifest.ExportedFunctions.Keys -contains "bitdiag") -Message "Module should export bitdiag."

. (Join-Path $repoRoot "BitDiag\Private\00-Core.ps1")
. (Join-Path $repoRoot "BitDiag\Private\60-Remediation.ps1")
. (Join-Path $repoRoot "BitDiag\Private\70-EnableBitLocker.ps1")
$syntheticResults = @(
    [PSCustomObject]@{
        Timestamp = "2026-01-01T00:00:00"
        Category  = "BitLocker"
        CheckName = "D: encryption"
        Status    = "Warning"
        Message   = "D: is not encrypted."
        Fix       = "Enable BitLocker on D:."
        Details   = $null
    },
    [PSCustomObject]@{
        Timestamp = "2026-01-01T00:00:00"
        Category  = "BitLocker"
        CheckName = "D: protection"
        Status    = "Warning"
        Message   = "D: BitLocker protection is off."
        Fix       = "Enable BitLocker on D:."
        Details   = $null
    },
    [PSCustomObject]@{
        Timestamp = "2026-01-01T00:00:00"
        Category  = "BitLocker"
        CheckName = "D: recovery password"
        Status    = "Warning"
        Message   = "D: does not have a recovery password protector."
        Fix       = "Add a recovery password protector."
        Details   = $null
    }
)
$defaultConsoleResults = Select-ConsoleDiagnosticResults -Results $syntheticResults
$detailedConsoleResults = Select-ConsoleDiagnosticResults -Results $syntheticResults -Detailed
Assert-True -Condition (@($defaultConsoleResults).Count -eq 1) -Message "Default console view should collapse dependent BitLocker checks for unencrypted drives."
Assert-True -Condition (@($detailedConsoleResults).Count -eq 3) -Message "Detailed console view should keep dependent BitLocker checks."
Assert-True -Condition ($defaultConsoleResults[0].Message -match "use -Detailed") -Message "Collapsed console result should explain how to show dependent checks."

$defaultRemediationPlan = @(Get-RemediationPlan -Results $syntheticResults)
$detailedRemediationPlan = @(Get-RemediationPlan -Results $syntheticResults -Detailed)
Assert-True -Condition ($defaultRemediationPlan.Count -eq 1) -Message "Default remediation plan should collapse dependent BitLocker actions for unencrypted drives."
Assert-True -Condition ($defaultRemediationPlan[0].ReasonType -eq "EncryptionOff") -Message "Collapsed remediation plan should keep the encryption root cause."
Assert-True -Condition (-not $defaultRemediationPlan[0].CanApply) -Message "Collapsed encryption remediation should not be an automatic candidate."
Assert-True -Condition ($defaultRemediationPlan[0].Notes -match "use -Detailed") -Message "Collapsed remediation plan should explain how to show dependent actions."
Assert-True -Condition ($detailedRemediationPlan.Count -eq 3) -Message "Detailed remediation plan should keep dependent BitLocker actions."

$tpmPlan = @(Get-RemediationPlan -Results @(
    [PSCustomObject]@{
        Timestamp = "2026-01-01T00:00:00"
        Category  = "Platform"
        CheckName = "TPM"
        Status    = "Warning"
        Message   = "TPM is not present or could not be detected."
        Fix       = "Confirm TPM 2.0 support in firmware settings."
        Details   = $null
    }
))
Assert-True -Condition ($tpmPlan.Count -eq 1) -Message "TPM platform issues should generate one remediation item."
Assert-True -Condition ($tpmPlan[0].ActionType -eq "Manual") -Message "TPM platform issues should be manual remediation."
Assert-True -Condition ($tpmPlan[0].ReasonType -eq "Platform") -Message "TPM platform issues should be classified as Platform."
Assert-True -Condition ($tpmPlan[0].RiskLevel -eq "High") -Message "TPM platform issues should be high risk."

$readyEnableItem = New-BitLockerEnablePlanItem `
    -DriveLetter "C" `
    -Title "C: ready to enable BitLocker on OS drive" `
    -ActionType "AutomaticCandidate" `
    -Reason "C: is not encrypted." `
    -Command "Enable-BitLocker -MountPoint C: -EncryptionMethod XtsAes256 -UsedSpaceOnly -TpmProtector" `
    -Notes "Method: XtsAes256. Mode: UsedSpaceOnly. Protectors: TPM + RecoveryPassword. After enabling, verify that the recovery password is backed up." `
    -ReasonType "EncryptionOff" `
    -RiskLevel "Medium" `
    -CanApply:$true `
    -IsSystemDrive:$true
$blockedEnableItem = New-BitLockerEnablePlanItem `
    -DriveLetter "C" `
    -Title "C: TPM is not ready" `
    -ActionType "Manual" `
    -Reason "TPM is required before BitDiag can auto-enable BitLocker on the OS drive." `
    -Notes "Enable and initialize TPM first, then retry." `
    -ReasonType "Platform" `
    -RiskLevel "High" `
    -IsSystemDrive:$true
$alreadyEncryptedItem = New-BitLockerEnablePlanItem `
    -DriveLetter "C" `
    -Title "C: already encrypted" `
    -ActionType "Review" `
    -Reason "C: is already fully encrypted." `
    -Notes "No BitLocker enable action is needed." `
    -ReasonType "Other" `
    -RiskLevel "Low" `
    -IsSystemDrive:$true
Assert-True -Condition ((Get-BitLockerEnableApplyText -Item $readyEnableItem) -eq "ready with -Apply") -Message "Ready enablement items should show ready apply text."
Assert-True -Condition ((Get-BitLockerEnableApplyText -Item $blockedEnableItem) -eq "blocked until resolved") -Message "Manual high-risk enablement items should show blocked apply text."
Assert-True -Condition ((Get-BitLockerEnableApplyText -Item $alreadyEncryptedItem) -eq "no action needed") -Message "Already encrypted enablement items should show no action text."
Assert-True -Condition ($readyEnableItem.Notes -notmatch "escrow") -Message "Enablement notes should not present escrow as an enablement blocker."
Assert-True -Condition ($readyEnableItem.Notes -match "recovery password is backed up") -Message "Enablement notes should include recovery password backup verification."

Import-Module $modulePath -Force -DisableNameChecking
Assert-True -Condition ($null -ne (Get-Command bitdiag -ErrorAction SilentlyContinue)) -Message "bitdiag command should be importable."

$versionOutput = & $launcherPath -Version -NoExitCode
Assert-True -Condition ($versionOutput -match "^bitdiag\s+\d+\.\d+\.\d+") -Message "bitdiag -Version should print a semantic version."

& $launcherPath -Help -NoExitCode -Color Never | Out-Null
Assert-True -Condition ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) -Message "bitdiag help should not fail."

& $diagnosePath -Help -NoExitCode -Color Never | Out-Null
Assert-True -Condition ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) -Message "diagnose.ps1 wrapper help should not fail."

& $launcherPath -Run -PlanFixes -PassThru -Quiet -NoExitCode | Out-Null
& $launcherPath -Run -Fix -WhatIf -Quiet -NoExitCode | Out-Null
& $launcherPath -Run -EnableBitLocker -Quiet -NoExitCode | Out-Null
& $launcherPath -Run -EnableBitLocker -WhatIf -Quiet -NoExitCode | Out-Null

$portablePath = Join-Path ([System.IO.Path]::GetTempPath()) ("bitdiag-portable-{0}.ps1" -f ([guid]::NewGuid()))
try {
    & $buildPath -OutputPath $portablePath | Out-Null
    Assert-True -Condition (Test-Path $portablePath) -Message "Portable build should create a single-file script."

    $portableVersion = & $portablePath -Version -NoExitCode
    Assert-True -Condition ($portableVersion -eq $versionOutput) -Message "Portable build should report the same version as the launcher."

    & $portablePath -Help -NoExitCode -Color Never | Out-Null
} finally {
    if (Test-Path $portablePath) {
        Remove-Item -LiteralPath $portablePath -Force
    }
}

$enterpriseOut = Join-Path ([System.IO.Path]::GetTempPath()) ("bitdiag-smoke-{0}" -f ([guid]::NewGuid()))
try {
    & $launcherPath -Run -EnterpriseReport -OutDirectory $enterpriseOut -Quiet -NoExitCode
    $report = Get-ChildItem -Path $enterpriseOut -Filter *.ndjson | Select-Object -First 1
    Assert-True -Condition ($null -ne $report) -Message "Enterprise report should create an NDJSON file."

    $firstLine = Get-Content -LiteralPath $report.FullName | Select-Object -First 1
    $record = $firstLine | ConvertFrom-Json
    Assert-True -Condition ($null -ne $record.RunId) -Message "Enterprise record should include RunId."
    Assert-True -Condition ($null -ne $record.DeviceGuid) -Message "Enterprise record should include DeviceGuid."
    Assert-True -Condition ($null -ne $record.CheckName) -Message "Enterprise record should include CheckName."
    Assert-True -Condition (-not ($record.PSObject.Properties.Name -contains "Details")) -Message "Enterprise record should not include raw Details."

    Start-Sleep -Seconds 1
    & $launcherPath -Run -EnterpriseReport -OutDirectory $enterpriseOut -Quiet -NoExitCode
    $guids = Get-ChildItem -Path $enterpriseOut -Filter *.ndjson |
        ForEach-Object { (Get-Content -LiteralPath $_.FullName | Select-Object -First 1 | ConvertFrom-Json).DeviceGuid } |
        Select-Object -Unique
    Assert-True -Condition (@($guids).Count -eq 1) -Message "Enterprise DeviceGuid should remain stable across runs."
} finally {
    if (Test-Path $enterpriseOut) {
        Remove-Item -LiteralPath $enterpriseOut -Recurse -Force
    }
}

Write-Host "Smoke tests passed."
