<#
.SYNOPSIS
    Installs bitdiag for the current Windows user.
#>

[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "BitDiag")
)

$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleSource = Join-Path $sourceRoot "BitDiag"
$launcherSource = Join-Path $sourceRoot "bitdiag.ps1"
$cmdSource = Join-Path $sourceRoot "bitdiag.cmd"

if (-not (Test-Path $moduleSource)) {
    throw "BitDiag module folder was not found at $moduleSource."
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -Path $moduleSource -Destination $InstallDir -Recurse -Force
Copy-Item -Path $launcherSource -Destination $InstallDir -Force
Copy-Item -Path $cmdSource -Destination $InstallDir -Force

$readmeSource = Join-Path $sourceRoot "README.md"
if (Test-Path $readmeSource) {
    Copy-Item -Path $readmeSource -Destination $InstallDir -Force
}

$diagnoseSource = Join-Path $sourceRoot "diagnose.ps1"
if (Test-Path $diagnoseSource) {
    Copy-Item -Path $diagnoseSource -Destination $InstallDir -Force
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathEntries = @($userPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$alreadyInPath = $pathEntries | Where-Object { $_.TrimEnd("\") -ieq $InstallDir.TrimEnd("\") }

if (-not $alreadyInPath) {
    $newPath = (@($pathEntries) + $InstallDir) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $env:Path = (@($env:Path -split ";") + $InstallDir | Select-Object -Unique) -join ";"
    Write-Host "Added $InstallDir to your user PATH."
}

Write-Host "bitdiag installed to $InstallDir."
Write-Host "Open a new PowerShell window, then run: bitdiag"
