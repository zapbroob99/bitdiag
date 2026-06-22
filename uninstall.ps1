<#
.SYNOPSIS
    Uninstalls bitdiag for the current Windows user.
#>

[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "BitDiag")
)

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath) {
    $pathEntries = @(
        $userPath -split ";" |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                $_.TrimEnd("\") -ine $InstallDir.TrimEnd("\")
            }
    )
    [Environment]::SetEnvironmentVariable("Path", ($pathEntries -join ";"), "User")
}

if (Test-Path $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Host "Removed $InstallDir."
}

Write-Host "bitdiag was removed. Open a new PowerShell window to refresh PATH."
