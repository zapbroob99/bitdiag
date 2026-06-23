# BitDiag PowerShell module loader.

$script:BitDiagModuleRoot = $PSScriptRoot

$sourceFiles = @(
    'Private\00-Core.ps1'
    'Private\10-Console.ps1'
    'Private\20-Diagnostics.Platform.ps1'
    'Private\30-Diagnostics.Disk.ps1'
    'Private\40-Diagnostics.BitLocker.ps1'
    'Private\50-Diagnostics.Policy.ps1'
    'Private\60-Remediation.ps1'
    'Private\70-EnableBitLocker.ps1'
    'Private\80-EnterpriseReport.ps1'
    'Private\90-Export.ps1'
    'Public\bitdiag.ps1'
)

foreach ($sourceFile in $sourceFiles) {
    $sourcePath = Join-Path -Path $PSScriptRoot -ChildPath $sourceFile
    . $sourcePath
}

Export-ModuleMember -Function bitdiag
