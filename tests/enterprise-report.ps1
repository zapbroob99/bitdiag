<#
.SYNOPSIS
    Local validation for BitDiag enterprise NDJSON reporting.
#>

[CmdletBinding()]
param(
    [string]$OutDirectory
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$launcherPath = Join-Path $repoRoot "bitdiag.ps1"
$createdTempDirectory = $false

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

function Get-NdjsonRecords {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Get-Content -LiteralPath $Path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        $_ | ConvertFrom-Json
    }
}

if ([string]::IsNullOrWhiteSpace($OutDirectory)) {
    $OutDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("bitdiag-enterprise-{0}" -f ([guid]::NewGuid()))
    $createdTempDirectory = $true
}

try {
    if (-not (Test-Path $OutDirectory)) {
        New-Item -ItemType Directory -Path $OutDirectory -Force | Out-Null
    }

    & $launcherPath -Run -EnterpriseReport -OutDirectory $OutDirectory -Quiet -NoExitCode

    $reports = @(Get-ChildItem -Path $OutDirectory -Filter *.ndjson)
    Assert-True -Condition ($reports.Count -eq 1) -Message "Enterprise report should create exactly one NDJSON file for one local run."

    $report = $reports[0]
    Assert-True -Condition ($report.Name -match "^[A-Za-z0-9._-]+_[A-Za-z0-9._-]+_\d{8}-\d{6}\.ndjson$") -Message "Enterprise report file name should include computer, device guid, and timestamp."

    $records = @(Get-NdjsonRecords -Path $report.FullName)
    Assert-True -Condition ($records.Count -gt 0) -Message "Enterprise report should contain at least one JSON record."

    $requiredColumns = @(
        "RunId",
        "TimestampUtc",
        "ComputerName",
        "Domain",
        "DeviceGuid",
        "UserContext",
        "BitDiagVersion",
        "DriveLetter",
        "Category",
        "CheckName",
        "Status",
        "Message",
        "Fix",
        "ReasonType",
        "RiskLevel",
        "CanApply",
        "ExitCode"
    )

    foreach ($record in $records) {
        foreach ($column in $requiredColumns) {
            Assert-True -Condition ($record.PSObject.Properties.Name -contains $column) -Message "Enterprise record should include column '$column'."
        }

        Assert-True -Condition (-not ($record.PSObject.Properties.Name -contains "Details")) -Message "Enterprise records should not export raw Details."
        $sensitiveColumns = @($record.PSObject.Properties.Name -match "RecoveryPassword|RecoveryKey|KeyProtectorId")
        Assert-True -Condition ($sensitiveColumns.Count -eq 0) -Message "Enterprise records should not expose sensitive recovery-specific fields."
        Assert-True -Condition ($record.TimestampUtc -match "^\d{4}-\d{2}-\d{2}T") -Message "TimestampUtc should use an ISO-like timestamp."
        Assert-True -Condition ($record.Status -in @("OK", "Info", "Warning", "Alert", "Error")) -Message "Status should be a known diagnostic status."
        Assert-True -Condition ($record.CanApply -is [bool]) -Message "CanApply should be a boolean."
    }

    $runIds = @($records | Select-Object -ExpandProperty RunId -Unique)
    Assert-True -Condition ($runIds.Count -eq 1) -Message "All records in one report should share one RunId."

    $deviceGuids = @($records | Select-Object -ExpandProperty DeviceGuid -Unique)
    Assert-True -Condition ($deviceGuids.Count -eq 1) -Message "All records in one report should share one DeviceGuid."

    Start-Sleep -Seconds 1
    & $launcherPath -Run -EnterpriseReport -OutDirectory $OutDirectory -Quiet -NoExitCode

    $reportsAfterSecondRun = @(Get-ChildItem -Path $OutDirectory -Filter *.ndjson)
    Assert-True -Condition ($reportsAfterSecondRun.Count -eq 2) -Message "A second local run should create a second NDJSON file, not append to the first one."

    $allDeviceGuids = @(
        $reportsAfterSecondRun | ForEach-Object {
            @(Get-NdjsonRecords -Path $_.FullName | Select-Object -First 1).DeviceGuid
        } | Select-Object -Unique
    )
    Assert-True -Condition ($allDeviceGuids.Count -eq 1) -Message "DeviceGuid should remain stable across local enterprise report runs."

    Write-Host "Enterprise report validation passed: $OutDirectory"
} finally {
    if ($createdTempDirectory -and (Test-Path $OutDirectory)) {
        Remove-Item -LiteralPath $OutDirectory -Recurse -Force
    }
}
