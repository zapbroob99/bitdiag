<#
.SYNOPSIS
    Backward-compatible wrapper for the bitdiag CLI.

.DESCRIPTION
    Existing usages such as .\diagnose.ps1 -ProblemsOnly continue to work.
    New installations should use the bitdiag command.
#>

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath "BitDiag\BitDiag.psm1"
Import-Module $modulePath -Force
bitdiag -Run -ExitProcess @args
