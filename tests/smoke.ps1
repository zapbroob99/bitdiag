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
