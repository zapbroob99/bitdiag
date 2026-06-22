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

Import-Module $modulePath -Force
Assert-True -Condition ($null -ne (Get-Command bitdiag -ErrorAction SilentlyContinue)) -Message "bitdiag command should be importable."

$versionOutput = & $launcherPath -Version -NoExitCode
Assert-True -Condition ($versionOutput -match "^bitdiag\s+\d+\.\d+\.\d+") -Message "bitdiag -Version should print a semantic version."

& $launcherPath -Help -NoExitCode -Color Never | Out-Null
Assert-True -Condition ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) -Message "bitdiag help should not fail."

& $diagnosePath -Help -NoExitCode -Color Never | Out-Null
Assert-True -Condition ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) -Message "diagnose.ps1 wrapper help should not fail."

& $launcherPath -Run -PlanFixes -PassThru -Quiet -NoExitCode | Out-Null
& $launcherPath -Run -Fix -WhatIf -Quiet -NoExitCode | Out-Null

Write-Host "Smoke tests passed."
