<#
.SYNOPSIS
    Launcher for the bitdiag CLI.
#>

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath "BitDiag\BitDiag.psm1"
Import-Module $modulePath -Force
bitdiag -ExitProcess @args
