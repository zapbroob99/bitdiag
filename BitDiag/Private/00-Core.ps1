# BitDiag internal source: 00-Core.ps1

function New-CheckResult {
    param(
        [Parameter(Mandatory)]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$CheckName,

        [Parameter(Mandatory)]
        [ValidateSet("OK", "Warning", "Alert", "Error", "Info")]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Fix,

        [object]$Details
    )

    [PSCustomObject]@{
        Timestamp = (Get-Date).ToString("s")
        Category  = $Category
        CheckName = $CheckName
        Status    = $Status
        Message   = $Message
        Fix       = $Fix
        Details   = $Details
    }
}

function Get-BitDiagVersion {
    if ($script:BitDiagVersion) {
        return [string]$script:BitDiagVersion
    }

    $moduleRoot = if ($script:BitDiagModuleRoot) { $script:BitDiagModuleRoot } else { $PSScriptRoot }
    $manifestPath = Join-Path -Path $moduleRoot -ChildPath "BitDiag.psd1"
    try {
        $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
        return [string]$manifest.Version
    } catch {
        return "unknown"
    }
}

function ConvertTo-DriveLetter {
    param([string[]]$Letters)

    $Letters |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim().TrimEnd(":").ToUpperInvariant() } |
        Select-Object -Unique
}

function Get-DetectedDriveLetters {
    try {
        Get-Volume -ErrorAction Stop |
            Where-Object {
                $_.DriveLetter -and
                $_.DriveType -in @("Fixed", "Removable") -and
                $_.FileSystem
            } |
            Sort-Object DriveLetter |
            ForEach-Object { ([string]$_.DriveLetter).ToUpperInvariant() } |
            Select-Object -Unique
    } catch {
        New-CheckResult `
            -Category "Runtime" `
            -CheckName "Drive discovery" `
            -Status "Warning" `
            -Message "Automatic drive discovery failed: $($_.Exception.Message)" `
            -Fix "Run as administrator or pass drive letters explicitly with -DriveLetters C."
    }
}

function Select-DiagnosticResults {
    param(
        [object[]]$Results,
        [string[]]$Category,
        [string[]]$Status,
        [switch]$ProblemsOnly
    )

    $selected = $Results

    if ($Category) {
        $selected = $selected | Where-Object { $_.Category -in $Category }
    }

    if ($Status) {
        $selected = $selected | Where-Object { $_.Status -in $Status }
    }

    if ($ProblemsOnly) {
        $selected = $selected | Where-Object { $_.Status -in @("Warning", "Alert", "Error") }
    }

    @($selected)
}

function Copy-DiagnosticResult {
    param([object]$Result)

    [PSCustomObject]@{
        Timestamp = $Result.Timestamp
        Category  = $Result.Category
        CheckName = $Result.CheckName
        Status    = $Result.Status
        Message   = $Result.Message
        Fix       = $Result.Fix
        Details   = $Result.Details
    }
}

function Select-ConsoleDiagnosticResults {
    param(
        [object[]]$Results,
        [switch]$Detailed
    )

    if ($Detailed) {
        return @($Results)
    }

    $dependentPatterns = @(
        "encryption method",
        "encryption progress",
        "protection",
        "suspension",
        "key protectors",
        "recovery password",
        "recovery backup",
        "auto-unlock"
    )

    $disabledDrives = @(
        $Results |
            Where-Object {
                $_.CheckName -match "^([A-Z]): encryption$" -and
                $_.Status -eq "Warning" -and
                $_.Message -match "not encrypted"
            } |
            ForEach-Object {
                if ($_.CheckName -match "^([A-Z]):") {
                    $Matches[1]
                }
            } |
            Select-Object -Unique
    )

    if (-not $disabledDrives -or $disabledDrives.Count -eq 0) {
        return @($Results)
    }

    $hiddenCounts = @{}
    $visible = foreach ($result in $Results) {
        $isDependent = $false
        $drive = $null
        if ($result.CheckName -match "^([A-Z]): (.+)$") {
            $drive = $Matches[1]
            $check = $Matches[2]
            if ($drive -in $disabledDrives -and $check -in $dependentPatterns) {
                $isDependent = $true
            }
        }

        if ($isDependent) {
            if (-not $hiddenCounts.ContainsKey($drive)) {
                $hiddenCounts[$drive] = 0
            }
            $hiddenCounts[$drive]++
            continue
        }

        Copy-DiagnosticResult -Result $result
    }

    foreach ($drive in $disabledDrives) {
        if (-not $hiddenCounts.ContainsKey($drive) -or $hiddenCounts[$drive] -eq 0) {
            continue
        }

        $primary = $visible | Where-Object { $_.CheckName -eq "${drive}: encryption" } | Select-Object -First 1
        if ($primary) {
            $primary.Message = "$($primary.Message) $($hiddenCounts[$drive]) dependent BitLocker checks are hidden in the default console view; use -Detailed to show them."
        }
    }

    @($visible)
}

function Get-DefaultReportPath {
    param([string]$Format)

    $extension = switch ($Format) {
        "Json" { "json" }
        "Html" { "html" }
        default { "txt" }
    }

    ".\bitlocker-diagnostics-$((Get-Date).ToString("yyyyMMdd-HHmmss")).$extension"
}

function Resolve-ReportPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet("Json", "Html")]
        [string]$Format
    )

    $extension = switch ($Format) {
        "Json" { ".json" }
        "Html" { ".html" }
    }

    $leaf = Split-Path -Path $Path -Leaf
    if ([string]::IsNullOrWhiteSpace([System.IO.Path]::GetExtension($leaf))) {
        return "$Path$extension"
    }

    $Path
}

function Get-DiagnosticsExitCode {
    param([object[]]$Results)

    $adminIssue = $Results | Where-Object { $_.Category -eq "Runtime" -and $_.CheckName -eq "Administrator" -and $_.Status -ne "OK" }
    if ($adminIssue) {
        return 3
    }

    if ($Results | Where-Object { $_.Status -in @("Alert", "Error") }) {
        return 2
    }

    if ($Results | Where-Object { $_.Status -eq "Warning" }) {
        return 1
    }

    0
}

