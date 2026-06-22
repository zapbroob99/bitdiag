<#
.SYNOPSIS
    Bootstraps BitDiag installation from GitHub.
#>

[CmdletBinding()]
param(
    [string]$RepositoryZipUrl = "https://github.com/zapbroob99/bitdiag/archive/refs/heads/main.zip",
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "BitDiag")
)

$ErrorActionPreference = "Stop"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("bitdiag-install-{0}" -f ([guid]::NewGuid()))
$zipPath = Join-Path $tempRoot "bitdiag.zip"
$extractPath = Join-Path $tempRoot "extract"

New-Item -ItemType Directory -Path $tempRoot, $extractPath -Force | Out-Null

try {
    Invoke-WebRequest -Uri $RepositoryZipUrl -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    $installScript = Get-ChildItem -Path $extractPath -Filter install.ps1 -Recurse | Select-Object -First 1
    if (-not $installScript) {
        throw "install.ps1 was not found in the downloaded BitDiag archive."
    }

    & $installScript.FullName -InstallDir $InstallDir
} finally {
    if (Test-Path $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
