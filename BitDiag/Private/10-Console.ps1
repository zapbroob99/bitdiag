# BitDiag internal source: 10-Console.ps1

function Get-StatusColor {
    param([string]$Status)

    switch ($Status) {
        "OK"      { "Green" }
        "Warning" { "Yellow" }
        "Alert"   { "Red" }
        "Error"   { "Red" }
        "Info"    { "Gray" }
        default   { "White" }
    }
}

function Test-UseColor {
    param([string]$Mode)

    switch ($Mode) {
        "Always" { return $true }
        "Never"  { return $false }
        default {
            try {
                return -not [Console]::IsOutputRedirected
            } catch {
                return $true
            }
        }
    }
}

function Write-ConsoleLine {
    param(
        [string]$Message = "",
        [string]$ForegroundColor = "White",
        [bool]$UseColor = $true
    )

    if ($UseColor) {
        Write-Host $Message -ForegroundColor $ForegroundColor
    } else {
        Write-Host $Message
    }
}

function Write-ConsoleInline {
    param(
        [string]$Message = "",
        [string]$ForegroundColor = "White",
        [bool]$UseColor = $true
    )

    if ($UseColor) {
        Write-Host $Message -ForegroundColor $ForegroundColor -NoNewline
    } else {
        Write-Host $Message -NoNewline
    }
}

function Get-ConsoleWidth {
    try {
        if ([Console]::WindowWidth -gt 0) {
            return [Math]::Min([Console]::WindowWidth, 140)
        }
    } catch {
        # Use a stable fallback below.
    }

    120
}

function Format-ColumnText {
    param(
        [string]$Text,
        [int]$Width
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return "".PadRight($Width)
    }

    $clean = ($Text -replace "\s+", " ").Trim()
    if ($clean.Length -le $Width) {
        return $clean.PadRight($Width)
    }

    if ($Width -le 3) {
        return $clean.Substring(0, $Width)
    }

    ($clean.Substring(0, $Width - 3) + "...").PadRight($Width)
}

function Format-StatusLabel {
    param([string]$Status)

    switch ($Status) {
        "OK"      { "[ OK ]" }
        "Warning" { "[WARN]" }
        "Alert"   { "[ALRT]" }
        "Error"   { "[ERR ]" }
        "Info"    { "[INFO]" }
        default   { "[$Status]" }
    }
}

function Write-ConsoleBanner {
    param([bool]$UseColor = $true)

    $bannerText = @'
            .-""-.
           / .--. \
          / /    \ \      
          | |    | |      
          | |.-""-.|      
         ///`.::::.`\      ____ ___ _____ ____ ___    _    ____ 
        ||| ::/  \:: ;    | __ )_ _|_   _|  _ \_ _|  / \  / ___|
        ||; ::\__/:: ;    |  _ \| |  | | | | | | |  / _ \| |  _                                                                              
         \\\ '::::' /     | |_) | |  | | | |_| | | / ___ \ |_| |                                                     
          `=':-..-'`      |____/___| |_| |____/___/_/   \_\____| ASELSAN
'@
    $banner = $bannerText -split "\r?\n"

    foreach ($line in $banner) {
        Write-ConsoleLine -Message $line -ForegroundColor Yellow -UseColor $UseColor
    }
}

function Write-StatusSummary {
    param(
        [object[]]$Results,
        [bool]$UseColor = $true
    )

    $statuses = @("OK", "Warning", "Alert", "Error", "Info")

    Write-ConsoleInline -Message "Summary      : " -ForegroundColor Gray -UseColor $UseColor
    foreach ($statusName in $statuses) {
        $count = @($Results | Where-Object { $_.Status -eq $statusName }).Count
        $colorName = Get-StatusColor -Status $statusName
        Write-ConsoleInline -Message ("{0} {1}  " -f (Format-StatusLabel -Status $statusName), $count) -ForegroundColor $colorName -UseColor $UseColor
    }

    Write-Host ""
}

function Write-Rule {
    param(
        [int]$Width,
        [bool]$UseColor = $true
    )

    Write-ConsoleLine -Message ("-" * $Width) -ForegroundColor DarkGray -UseColor $UseColor
}

function Write-RecommendedActions {
    param(
        [object[]]$Results,
        [int]$Width,
        [bool]$UseColor = $true
    )

    $fixes = $Results |
        Where-Object { $_.Fix -and $_.Status -in @("Warning", "Alert", "Error") } |
        Select-Object Status, CheckName, Fix -Unique

    if (-not $fixes) {
        return
    }

    Write-ConsoleLine -Message "" -UseColor $UseColor
    Write-ConsoleLine -Message "Recommended actions" -ForegroundColor Cyan -UseColor $UseColor
    Write-Rule -Width $Width -UseColor $UseColor

    $index = 1
    foreach ($fix in $fixes) {
        $colorName = Get-StatusColor -Status $fix.Status
        Write-ConsoleLine -Message ("{0,2}. {1} - {2}" -f $index, $fix.CheckName, $fix.Fix) -ForegroundColor $colorName -UseColor $UseColor
        $index++
    }
}

function Show-Usage {
    param([bool]$UseColor = $true)

    Write-ConsoleBanner -UseColor $UseColor
    Write-ConsoleLine -Message "" -UseColor $UseColor
    Write-ConsoleLine -Message "Usage:" -ForegroundColor Cyan -UseColor $UseColor
    Write-ConsoleLine -Message "  bitdiag" -UseColor $UseColor
    Write-ConsoleLine -Message "  bitdiag -Run" -UseColor $UseColor
    Write-ConsoleLine -Message "  bitdiag -Drives C,D -ProblemsOnly -Detailed" -UseColor $UseColor
    Write-ConsoleLine -Message "  bitdiag -AllDrives -ProblemsOnly" -UseColor $UseColor
    Write-ConsoleLine -Message "  bitdiag -Format Json -OutFile .\report.json -ProblemsOnly" -UseColor $UseColor
    Write-ConsoleLine -Message "  bitdiag -Format Html -OutFile .\report.html -ProblemsOnly" -UseColor $UseColor
    Write-ConsoleLine -Message "  bitdiag -Category Platform,BitLocker -Status Warning,Alert,Error" -UseColor $UseColor
    Write-ConsoleLine -Message "  bitdiag -PlanFixes" -UseColor $UseColor
    Write-ConsoleLine -Message "  bitdiag -Fix -WhatIf" -UseColor $UseColor
    Write-ConsoleLine -Message "  bitdiag -Fix -Apply" -UseColor $UseColor
    Write-ConsoleLine -Message "  bitdiag -EnableBitLocker" -UseColor $UseColor
    Write-ConsoleLine -Message "  bitdiag -EnableBitLocker -Apply" -UseColor $UseColor
    Write-ConsoleLine -Message "  bitdiag -EnterpriseReport -OutDirectory \\server\share\BitDiag" -UseColor $UseColor
    Write-ConsoleLine -Message "  bitdiag -Version" -UseColor $UseColor
    Write-ConsoleLine -Message "" -UseColor $UseColor
    Write-ConsoleLine -Message "Note: Do not type square brackets from documentation syntax; they only mean optional." -ForegroundColor Gray -UseColor $UseColor
    Write-ConsoleLine -Message "" -UseColor $UseColor
    Write-ConsoleLine -Message "Options:" -ForegroundColor Cyan -UseColor $UseColor
    Write-ConsoleLine -Message "  -Drives, -DriveLetters    Drive letters to inspect. Default: detected drives" -UseColor $UseColor
    Write-ConsoleLine -Message "  -AllDrives                Discover fixed/removable volumes automatically; default when -Drives is omitted" -UseColor $UseColor
    Write-ConsoleLine -Message "  -Format, -OutputFormat    Console, Json, Html, or None" -UseColor $UseColor
    Write-ConsoleLine -Message "  -OutFile, -OutputPath     Report destination for Json/Html" -UseColor $UseColor
    Write-ConsoleLine -Message "  -Category                 Runtime, Platform, Disk, Policy, Volume, BitLocker" -UseColor $UseColor
    Write-ConsoleLine -Message "  -Status                   OK, Warning, Alert, Error, Info" -UseColor $UseColor
    Write-ConsoleLine -Message "  -ProblemsOnly             Show/export Warning, Alert, and Error only" -UseColor $UseColor
    Write-ConsoleLine -Message "  -Detailed                 Include raw details and dependent checks/actions" -UseColor $UseColor
    Write-ConsoleLine -Message "  -Color                    Auto, Always, or Never" -UseColor $UseColor
    Write-ConsoleLine -Message "  -Quiet                    Suppress informational CLI output" -UseColor $UseColor
    Write-ConsoleLine -Message "  -PassThru                 Emit result objects to the pipeline" -UseColor $UseColor
    Write-ConsoleLine -Message "  -Help, -h                 Show this help screen" -UseColor $UseColor
    Write-ConsoleLine -Message "  -Run                      Run diagnostics instead of opening the interactive menu" -UseColor $UseColor
    Write-ConsoleLine -Message "  -Interactive              Open the interactive menu" -UseColor $UseColor
    Write-ConsoleLine -Message "  -PlanFixes                Generate a remediation plan without changing the system" -UseColor $UseColor
    Write-ConsoleLine -Message "  -Fix                      Prepare safe automatic remediation candidates" -UseColor $UseColor
    Write-ConsoleLine -Message "  -Apply                    Execute -Fix candidates or start eligible -EnableBitLocker actions" -UseColor $UseColor
    Write-ConsoleLine -Message "  -EnableBitLocker          Prepare BitLocker enablement for eligible unencrypted fixed drives" -UseColor $UseColor
    Write-ConsoleLine -Message "  -WhatIf                   Preview -Fix or -EnableBitLocker actions without changing the system" -UseColor $UseColor
    Write-ConsoleLine -Message "  -EnterpriseReport         Write flat NDJSON for SCCM-triggered Power BI reporting" -UseColor $UseColor
    Write-ConsoleLine -Message "  -OutDirectory             Directory or share path for enterprise NDJSON output" -UseColor $UseColor
    Write-ConsoleLine -Message "  -Version                  Show BitDiag version" -UseColor $UseColor
    Write-ConsoleLine -Message "  -NoExitCode               Do not set process exit code" -UseColor $UseColor
    Write-ConsoleLine -Message "" -UseColor $UseColor
    Write-ConsoleLine -Message "Exit codes: 0 OK, 1 Warning, 2 Alert/Error, 3 not administrator." -ForegroundColor Gray -UseColor $UseColor
}

function Get-DriveResult {
    param(
        [object[]]$Results,
        [string]$DriveLetter,
        [string]$NamePattern
    )

    $Results |
        Where-Object { $_.CheckName -like "${DriveLetter}: $NamePattern" } |
        Select-Object -First 1
}

function Get-DriveOverviewValue {
    param(
        [object]$Result,
        [string]$Kind
    )

    if (-not $Result) {
        return "Unknown"
    }

    if ($Result.Message -match "was not found") {
        return "Not found"
    }

    switch ($Kind) {
        "FileSystem" {
            if ($Result.Details) {
                return [string]$Result.Details
            }
        }
        "Encryption" {
            if ($Result.Status -eq "OK") {
                return "Yes"
            }

            if ($Result.Status -eq "Warning" -and $Result.Message -match "not encrypted") {
                return "No"
            }

            if ($Result.Details) {
                return [string]$Result.Details
            }
        }
        "Method" {
            if ($Result.Details) {
                return [string]$Result.Details
            }

            if ($Result.Message -match "encryption method is (.+)\.?$") {
                return $Matches[1].TrimEnd(".")
            }
        }
        "Protection" {
            if ($Result.Status -eq "OK") {
                return "On"
            }

            if ($Result.Message -match "protection is (.+)\.?$") {
                return $Matches[1].TrimEnd(".")
            }
        }
        "Recovery" {
            if ($Result.Status -eq "OK") {
                return "Present"
            }

            if ($Result.Status -in @("Warning", "Alert", "Error")) {
                return "Missing"
            }
        }
        "AutoUnlock" {
            if ($Result.Status -eq "OK") {
                return "On"
            }

            if ($Result.Status -eq "Warning") {
                return "Off"
            }
        }
    }

    if ($Result.Status -eq "Error") {
        return "Error"
    }

    "Unknown"
}

function Get-WorstStatus {
    param([object[]]$Results)

    if ($Results | Where-Object { $_.Status -in @("Alert", "Error") }) {
        return "Error"
    }

    if ($Results | Where-Object { $_.Status -eq "Warning" }) {
        return "Warning"
    }

    if ($Results | Where-Object { $_.Status -eq "Info" }) {
        return "Info"
    }

    "OK"
}

function Write-DriveOverview {
    param(
        [object[]]$AllResults,
        [string[]]$DriveLetters,
        [int]$Width,
        [bool]$UseColor = $true
    )

    if (-not $DriveLetters -or $DriveLetters.Count -eq 0) {
        return
    }

    $driveWidth = 7
    $encryptedWidth = 12
    $methodWidth = 14
    $protectionWidth = 12
    $recoveryWidth = 12
    $autoUnlockWidth = 12
    $fileSystemWidth = [Math]::Max(10, $Width - $driveWidth - $encryptedWidth - $methodWidth - $protectionWidth - $recoveryWidth - $autoUnlockWidth - 14)

    Write-ConsoleLine -Message "" -UseColor $UseColor
    Write-ConsoleLine -Message "Drive BitLocker overview" -ForegroundColor Cyan -UseColor $UseColor
    Write-Rule -Width $Width -UseColor $UseColor

    $header = "{0}  {1}  {2}  {3}  {4}  {5}  {6}" -f `
        (Format-ColumnText -Text "Drive" -Width $driveWidth),
        (Format-ColumnText -Text "Encrypted" -Width $encryptedWidth),
        (Format-ColumnText -Text "Method" -Width $methodWidth),
        (Format-ColumnText -Text "Protection" -Width $protectionWidth),
        (Format-ColumnText -Text "Recovery" -Width $recoveryWidth),
        (Format-ColumnText -Text "AutoUnlock" -Width $autoUnlockWidth),
        (Format-ColumnText -Text "FileSystem" -Width $fileSystemWidth)
    Write-ConsoleLine -Message $header -ForegroundColor Cyan -UseColor $UseColor
    Write-Rule -Width $Width -UseColor $UseColor

    foreach ($driveLetter in $DriveLetters) {
        $fileSystem = Get-DriveResult -Results $AllResults -DriveLetter $driveLetter -NamePattern "filesystem"
        $encryption = Get-DriveResult -Results $AllResults -DriveLetter $driveLetter -NamePattern "encryption"
        if (-not $encryption) {
            $encryption = Get-DriveResult -Results $AllResults -DriveLetter $driveLetter -NamePattern "BitLocker"
        }

        $method = Get-DriveResult -Results $AllResults -DriveLetter $driveLetter -NamePattern "encryption method"
        $protection = Get-DriveResult -Results $AllResults -DriveLetter $driveLetter -NamePattern "protection"
        $recovery = Get-DriveResult -Results $AllResults -DriveLetter $driveLetter -NamePattern "recovery password"
        $autoUnlock = Get-DriveResult -Results $AllResults -DriveLetter $driveLetter -NamePattern "auto-unlock"
        $status = Get-WorstStatus -Results @($fileSystem, $encryption, $method, $protection, $recovery, $autoUnlock)

        $row = "{0}  {1}  {2}  {3}  {4}  {5}  {6}" -f `
            (Format-ColumnText -Text "${driveLetter}:" -Width $driveWidth),
            (Format-ColumnText -Text (Get-DriveOverviewValue -Result $encryption -Kind "Encryption") -Width $encryptedWidth),
            (Format-ColumnText -Text (Get-DriveOverviewValue -Result $method -Kind "Method") -Width $methodWidth),
            (Format-ColumnText -Text (Get-DriveOverviewValue -Result $protection -Kind "Protection") -Width $protectionWidth),
            (Format-ColumnText -Text (Get-DriveOverviewValue -Result $recovery -Kind "Recovery") -Width $recoveryWidth),
            (Format-ColumnText -Text (Get-DriveOverviewValue -Result $autoUnlock -Kind "AutoUnlock") -Width $autoUnlockWidth),
            (Format-ColumnText -Text (Get-DriveOverviewValue -Result $fileSystem -Kind "FileSystem") -Width $fileSystemWidth)

        Write-ConsoleLine -Message $row -ForegroundColor (Get-StatusColor -Status $status) -UseColor $UseColor
    }

    Write-Rule -Width $Width -UseColor $UseColor
}

function Get-ResultSectionName {
    param([object]$Result)

    if ($Result.CheckName -match "^([A-Z]):") {
        return "$($Matches[1]): Volume / BitLocker"
    }

    switch ($Result.Category) {
        "Runtime"  { "System" }
        "Platform" { "System" }
        "Disk"     { "Disk layout" }
        "Policy"   { "Policy" }
        "Volume"   { "Other volumes" }
        "BitLocker" { "Other BitLocker" }
        default    { $Result.Category }
    }
}

function Write-ResultRows {
    param(
        [object[]]$Results,
        [int]$StatusWidth,
        [int]$CategoryWidth,
        [int]$CheckWidth,
        [int]$MessageWidth,
        [switch]$Detailed,
        [bool]$UseColor = $true
    )

    foreach ($result in $Results) {
        $colorName = Get-StatusColor -Status $result.Status
        $row = "{0}  {1}  {2}  {3}" -f `
            (Format-ColumnText -Text (Format-StatusLabel -Status $result.Status) -Width $StatusWidth),
            (Format-ColumnText -Text $result.Category -Width $CategoryWidth),
            (Format-ColumnText -Text $result.CheckName -Width $CheckWidth),
            (Format-ColumnText -Text $result.Message -Width $MessageWidth)

        Write-ConsoleLine -Message $row -ForegroundColor $colorName -UseColor $UseColor

        if ($result.Fix) {
            Write-ConsoleLine -Message ("  fix      {0}" -f $result.Fix) -ForegroundColor DarkYellow -UseColor $UseColor
        }

        if ($Detailed -and $null -ne $result.Details) {
            $detailText = $result.Details | ConvertTo-Json -Depth 6 -Compress
            Write-ConsoleLine -Message ("  details  {0}" -f $detailText) -ForegroundColor DarkGray -UseColor $UseColor
        }
    }
}

function Write-ConsoleReport {
    param(
        [object[]]$Results,
        [object[]]$AllResults,
        [string[]]$DriveLetters,
        [switch]$Detailed,
        [bool]$UseColor = $true
    )

    $width = Get-ConsoleWidth
    $tableWidth = [Math]::Max(92, $width - 2)
    $statusWidth = 7
    $categoryWidth = 11
    $checkWidth = 30
    $messageWidth = [Math]::Max(32, $tableWidth - $statusWidth - $categoryWidth - $checkWidth - 9)

    Write-ConsoleBanner -UseColor $UseColor
    Write-ConsoleLine -Message "" -UseColor $UseColor
    Write-ConsoleLine -Message ("Target drives : {0}" -f ($DriveLetters -join ", ")) -ForegroundColor Gray -UseColor $UseColor
    Write-ConsoleLine -Message ("Results       : {0} shown / {1} collected" -f $Results.Count, $AllResults.Count) -ForegroundColor Gray -UseColor $UseColor
    Write-StatusSummary -Results $AllResults -UseColor $UseColor
    Write-DriveOverview -AllResults $AllResults -DriveLetters $DriveLetters -Width $tableWidth -UseColor $UseColor

    if (-not $Results -or $Results.Count -eq 0) {
        Write-ConsoleLine -Message "" -UseColor $UseColor
        Write-ConsoleLine -Message "No diagnostics matched the selected filters." -ForegroundColor Yellow -UseColor $UseColor
        return
    }

    Write-ConsoleLine -Message "" -UseColor $UseColor
    Write-Rule -Width $tableWidth -UseColor $UseColor

    $header = "{0}  {1}  {2}  {3}" -f `
        (Format-ColumnText -Text "Status" -Width $statusWidth),
        (Format-ColumnText -Text "Category" -Width $categoryWidth),
        (Format-ColumnText -Text "Check" -Width $checkWidth),
        (Format-ColumnText -Text "Message" -Width $messageWidth)
    Write-ConsoleLine -Message $header -ForegroundColor Cyan -UseColor $UseColor

    $sectionNames = @("System", "Disk layout", "Policy")
    foreach ($driveLetter in $DriveLetters) {
        $sectionNames += "${driveLetter}: Volume / BitLocker"
    }
    $sectionNames += @("Other volumes", "Other BitLocker")

    $writtenSections = @()
    foreach ($sectionName in $sectionNames) {
        $sectionResults = @($Results | Where-Object { (Get-ResultSectionName -Result $_) -eq $sectionName })
        if (-not $sectionResults -or $sectionResults.Count -eq 0) {
            continue
        }

        Write-Rule -Width $tableWidth -UseColor $UseColor
        Write-ConsoleLine -Message $sectionName -ForegroundColor Cyan -UseColor $UseColor
        Write-ResultRows `
            -Results $sectionResults `
            -StatusWidth $statusWidth `
            -CategoryWidth $categoryWidth `
            -CheckWidth $checkWidth `
            -MessageWidth $messageWidth `
            -Detailed:$Detailed `
            -UseColor $UseColor
        $writtenSections += $sectionName
    }

    $remainingResults = @($Results | Where-Object { (Get-ResultSectionName -Result $_) -notin $writtenSections })
    if ($remainingResults -and $remainingResults.Count -gt 0) {
        Write-Rule -Width $tableWidth -UseColor $UseColor
        Write-ConsoleLine -Message "Other" -ForegroundColor Cyan -UseColor $UseColor
        Write-ResultRows `
            -Results $remainingResults `
            -StatusWidth $statusWidth `
            -CategoryWidth $categoryWidth `
            -CheckWidth $checkWidth `
            -MessageWidth $messageWidth `
            -Detailed:$Detailed `
            -UseColor $UseColor
    }

    Write-Rule -Width $tableWidth -UseColor $UseColor
    Write-RecommendedActions -Results $Results -Width $tableWidth -UseColor $UseColor
}

