# BitDiag PowerShell module.
# Public command: bitdiag

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

function Get-DefaultReportPath {
    param([string]$Format)

    $extension = switch ($Format) {
        "Json" { "json" }
        "Html" { "html" }
        default { "txt" }
    }

    ".\bitlocker-diagnostics-$((Get-Date).ToString("yyyyMMdd-HHmmss")).$extension"
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
    Write-ConsoleLine -Message "  -Detailed                 Include raw details in console output" -UseColor $UseColor
    Write-ConsoleLine -Message "  -Color                    Auto, Always, or Never" -UseColor $UseColor
    Write-ConsoleLine -Message "  -Quiet                    Suppress informational CLI output" -UseColor $UseColor
    Write-ConsoleLine -Message "  -PassThru                 Emit result objects to the pipeline" -UseColor $UseColor
    Write-ConsoleLine -Message "  -Help, -h                 Show this help screen" -UseColor $UseColor
    Write-ConsoleLine -Message "  -Run                      Run diagnostics instead of opening the interactive menu" -UseColor $UseColor
    Write-ConsoleLine -Message "  -Interactive              Open the interactive menu" -UseColor $UseColor
    Write-ConsoleLine -Message "  -NoExitCode               Do not set process exit code" -UseColor $UseColor
    Write-ConsoleLine -Message "" -UseColor $UseColor
    Write-ConsoleLine -Message "Exit codes: 0 OK, 1 Warning, 2 Alert/Error, 3 not administrator." -ForegroundColor Gray -UseColor $UseColor
}

function Test-RunningAsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if ($isAdmin) {
            return New-CheckResult -Category "Runtime" -CheckName "Administrator" -Status "OK" -Message "PowerShell is running as administrator."
        }

        return New-CheckResult `
            -Category "Runtime" `
            -CheckName "Administrator" `
            -Status "Warning" `
            -Message "PowerShell is not running as administrator; some diagnostics may be incomplete." `
            -Fix "Run PowerShell as Administrator and run this script again."
    } catch {
        return New-CheckResult -Category "Runtime" -CheckName "Administrator" -Status "Error" -Message "Administrator check failed: $($_.Exception.Message)"
    }
}

function Get-BootMode {
    try {
        $firmware = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "PEFirmwareType" -ErrorAction Stop
        switch ([int]$firmware.PEFirmwareType) {
            1 { return "Legacy BIOS" }
            2 { return "UEFI" }
        }
    } catch {
        # Fall back to bcdedit below.
    }

    try {
        $bcd = (& bcdedit 2>$null) -join "`n"
        if ($bcd -match "winload\.efi|\\EFI\\") {
            return "UEFI"
        }
        if ($bcd -match "winload\.exe") {
            return "Legacy BIOS"
        }
    } catch {
        # Unknown is handled by the caller.
    }

    "Unknown"
}

function Test-BootMode {
    param([string]$BootMode)

    switch ($BootMode) {
        "UEFI" {
            New-CheckResult -Category "Platform" -CheckName "Boot mode" -Status "OK" -Message "System boots in UEFI mode."
        }
        "Legacy BIOS" {
            New-CheckResult `
                -Category "Platform" `
                -CheckName "Boot mode" `
                -Status "Warning" `
                -Message "System boots in Legacy BIOS mode." `
                -Fix "For TPM-based BitLocker on modern Windows, convert the OS disk to GPT if needed and switch firmware to UEFI Only."
        }
        default {
            New-CheckResult -Category "Platform" -CheckName "Boot mode" -Status "Warning" -Message "Boot mode could not be detected."
        }
    }
}

function Test-SecureBoot {
    param([string]$BootMode)

    if (Get-Command Confirm-SecureBootUEFI -ErrorAction SilentlyContinue) {
        try {
            $enabled = Confirm-SecureBootUEFI -ErrorAction Stop
            if ($enabled) {
                return New-CheckResult -Category "Platform" -CheckName "Secure Boot" -Status "OK" -Message "Secure Boot is enabled."
            }

            return New-CheckResult `
                -Category "Platform" `
                -CheckName "Secure Boot" `
                -Status "Warning" `
                -Message "Secure Boot is disabled." `
                -Fix "Enable Secure Boot in firmware settings after confirming the system boots in UEFI mode."
        } catch {
            if ($BootMode -eq "Legacy BIOS") {
                return New-CheckResult `
                    -Category "Platform" `
                    -CheckName "Secure Boot" `
                    -Status "Warning" `
                    -Message "Secure Boot is unavailable while booting in Legacy BIOS mode." `
                    -Fix "Switch firmware to UEFI mode before enabling Secure Boot."
            }

            return New-CheckResult -Category "Platform" -CheckName "Secure Boot" -Status "Error" -Message "Secure Boot check failed: $($_.Exception.Message)"
        }
    }

    try {
        $secureBoot = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -ErrorAction Stop
        if ($secureBoot.UEFISecureBootEnabled -eq 1) {
            return New-CheckResult -Category "Platform" -CheckName "Secure Boot" -Status "OK" -Message "Secure Boot is enabled."
        }

        return New-CheckResult `
            -Category "Platform" `
            -CheckName "Secure Boot" `
            -Status "Warning" `
            -Message "Secure Boot is disabled." `
            -Fix "Enable Secure Boot in firmware settings."
    } catch {
        New-CheckResult -Category "Platform" -CheckName "Secure Boot" -Status "Error" -Message "Secure Boot check failed: $($_.Exception.Message)"
    }
}

function Get-TpmState {
    if (Get-Command Get-Tpm -ErrorAction SilentlyContinue) {
        try {
            $tpm = Get-Tpm -ErrorAction Stop
            return [PSCustomObject]@{
                Present   = [bool]$tpm.TpmPresent
                Enabled   = [bool]$tpm.TpmEnabled
                Activated = [bool]$tpm.TpmActivated
                Ready     = [bool]$tpm.TpmReady
                Owned     = [bool]$tpm.TpmOwned
                Source    = "Get-Tpm"
            }
        } catch {
            return [PSCustomObject]@{
                Present = $false
                Error   = $_.Exception.Message
                Source  = "Get-Tpm"
            }
        }
    }

    try {
        $tpm = Get-CimInstance -Namespace "root\cimv2\Security\MicrosoftTpm" -ClassName Win32_Tpm -ErrorAction Stop
        return [PSCustomObject]@{
            Present   = [bool]$tpm
            Enabled   = [bool]$tpm.IsEnabled_InitialValue
            Activated = [bool]$tpm.IsActivated_InitialValue
            Ready     = ([bool]$tpm.IsEnabled_InitialValue -and [bool]$tpm.IsActivated_InitialValue)
            Owned     = [bool]$tpm.IsOwned_InitialValue
            Source    = "Win32_Tpm"
        }
    } catch {
        [PSCustomObject]@{
            Present = $false
            Error   = $_.Exception.Message
            Source  = "Win32_Tpm"
        }
    }
}

function Test-Tpm {
    param([object]$TpmState)

    if ($TpmState.Error) {
        return New-CheckResult -Category "Platform" -CheckName "TPM" -Status "Error" -Message "TPM check failed: $($TpmState.Error)" -Details $TpmState
    }

    if (-not $TpmState.Present) {
        return New-CheckResult `
            -Category "Platform" `
            -CheckName "TPM" `
            -Status "Alert" `
            -Message "TPM is not present or could not be detected." `
            -Fix "Confirm TPM 2.0 support in firmware settings." `
            -Details $TpmState
    }

    if ($TpmState.Ready -or ($TpmState.Enabled -and $TpmState.Activated)) {
        return New-CheckResult -Category "Platform" -CheckName "TPM" -Status "OK" -Message "TPM is present and enabled." -Details $TpmState
    }

    New-CheckResult `
        -Category "Platform" `
        -CheckName "TPM" `
        -Status "Warning" `
        -Message "TPM is present but not ready/enabled." `
        -Fix "Enable and initialize TPM in firmware or Windows Security." `
        -Details $TpmState
}

function Test-TpmBootCompatibility {
    param(
        [object]$TpmState,
        [string]$BootMode
    )

    if ($TpmState.Present -and ($TpmState.Ready -or $TpmState.Enabled) -and $BootMode -eq "Legacy BIOS") {
        return New-CheckResult `
            -Category "Platform" `
            -CheckName "TPM + boot mode" `
            -Status "Alert" `
            -Message "TPM is enabled but the system is booting in Legacy BIOS mode." `
            -Fix "Switch to UEFI Only after validating or converting the OS disk to GPT."
    }

    if ($TpmState.Present -and ($TpmState.Ready -or $TpmState.Enabled) -and $BootMode -eq "UEFI") {
        return New-CheckResult -Category "Platform" -CheckName "TPM + boot mode" -Status "OK" -Message "TPM and UEFI boot mode are compatible for BitLocker."
    }

    New-CheckResult -Category "Platform" -CheckName "TPM + boot mode" -Status "Info" -Message "TPM and boot mode compatibility could not be fully confirmed."
}

function Test-DiskPartitionStyle {
    try {
        $disks = Get-Disk -ErrorAction Stop
        foreach ($disk in $disks) {
            $label = "Disk $($disk.Number)"
            if ($disk.FriendlyName) {
                $label = "$label ($($disk.FriendlyName))"
            }

            switch ($disk.PartitionStyle) {
                "GPT" {
                    New-CheckResult -Category "Disk" -CheckName "$label partition style" -Status "OK" -Message "$label uses GPT." -Details $disk.PartitionStyle
                }
                "MBR" {
                    New-CheckResult `
                        -Category "Disk" `
                        -CheckName "$label partition style" `
                        -Status "Warning" `
                        -Message "$label uses MBR." `
                        -Fix "GPT is recommended for UEFI and modern BitLocker deployments." `
                        -Details $disk.PartitionStyle
                }
                "RAW" {
                    New-CheckResult `
                        -Category "Disk" `
                        -CheckName "$label partition style" `
                        -Status "Warning" `
                        -Message "$label has RAW partition style." `
                        -Fix "Initialize or repair the disk partition table before using BitLocker." `
                        -Details $disk.PartitionStyle
                }
                default {
                    New-CheckResult -Category "Disk" -CheckName "$label partition style" -Status "Info" -Message "$label partition style is $($disk.PartitionStyle)." -Details $disk.PartitionStyle
                }
            }
        }
    } catch {
        New-CheckResult -Category "Disk" -CheckName "Partition style" -Status "Error" -Message "Disk partition style check failed: $($_.Exception.Message)"
    }
}

function Test-DiskDynamic {
    try {
        $disks = Get-Disk -ErrorAction Stop
        foreach ($disk in $disks) {
            $dynamicProperty = $disk.PSObject.Properties["IsDynamic"]
            $isDynamic = $false
            $dynamicDetails = @()

            if ($null -ne $dynamicProperty) {
                $isDynamic = [bool]$disk.IsDynamic
                $dynamicDetails += "Get-Disk IsDynamic=$($disk.IsDynamic)"
            } else {
                $partitions = @(Get-Partition -DiskNumber $disk.Number -ErrorAction Stop)
                $dynamicPartitions = @(
                    $partitions | Where-Object {
                        $_.GptType -in @(
                            "{5808C8AA-7E8F-42E0-85D2-E1E90434CFB3}",
                            "{AF9B60A0-1431-4F62-BC68-3311714A69AD}"
                        ) -or
                        $_.Type -match "Dynamic|Logical Disk Manager|LDM"
                    }
                )

                $isDynamic = $dynamicPartitions.Count -gt 0
                $dynamicDetails += "Dynamic markers found in partitions: $($dynamicPartitions.Count)"
            }

            if ($isDynamic) {
                New-CheckResult `
                    -Category "Disk" `
                    -CheckName "Disk $($disk.Number) type" `
                    -Status "Warning" `
                    -Message "Disk $($disk.Number) is Dynamic." `
                    -Fix "Use a Basic disk for BitLocker OS volume scenarios." `
                    -Details $dynamicDetails
            } else {
                New-CheckResult `
                    -Category "Disk" `
                    -CheckName "Disk $($disk.Number) type" `
                    -Status "OK" `
                    -Message "Disk $($disk.Number) appears to be Basic; no dynamic disk markers were found." `
                    -Details $dynamicDetails
            }
        }
    } catch {
        New-CheckResult -Category "Disk" -CheckName "Dynamic disk" -Status "Error" -Message "Dynamic disk check failed: $($_.Exception.Message)"
    }
}

function Test-EfiSystemPartition {
    try {
        $espPartitions = Get-Partition -ErrorAction Stop | Where-Object { $_.GptType -eq "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}" }
        if (-not $espPartitions) {
            return New-CheckResult `
                -Category "Disk" `
                -CheckName "EFI System Partition" `
                -Status "Warning" `
                -Message "EFI System Partition was not found." `
                -Fix "UEFI boot normally requires an EFI System Partition formatted as FAT32."
        }

        foreach ($partition in $espPartitions) {
            $name = "ESP on disk $($partition.DiskNumber), partition $($partition.PartitionNumber)"
            try {
                $volume = Get-Volume -Partition $partition -ErrorAction Stop
                if ($volume.FileSystem -eq "FAT32") {
                    New-CheckResult -Category "Disk" -CheckName $name -Status "OK" -Message "$name is FAT32." -Details $volume.FileSystem
                } else {
                    New-CheckResult `
                        -Category "Disk" `
                        -CheckName $name `
                        -Status "Warning" `
                        -Message "$name is $($volume.FileSystem), not FAT32." `
                        -Fix "EFI System Partition should be FAT32." `
                        -Details $volume.FileSystem
                }
            } catch {
                New-CheckResult -Category "Disk" -CheckName $name -Status "Warning" -Message "$name was found, but its volume could not be read: $($_.Exception.Message)"
            }
        }
    } catch {
        New-CheckResult -Category "Disk" -CheckName "EFI System Partition" -Status "Error" -Message "EFI System Partition check failed: $($_.Exception.Message)"
    }
}

function Test-ActiveMbrPartition {
    try {
        $activePartitions = Get-Partition -ErrorAction Stop | Where-Object {
            $property = $_.PSObject.Properties["IsActive"]
            $null -ne $property -and $_.IsActive -eq $true
        }

        if (-not $activePartitions) {
            return New-CheckResult -Category "Disk" -CheckName "Active MBR partition" -Status "OK" -Message "No active MBR partition was found."
        }

        foreach ($partition in $activePartitions) {
            $drive = if ($partition.DriveLetter) { "$($partition.DriveLetter):" } else { "no drive letter" }
            New-CheckResult `
                -Category "Disk" `
                -CheckName "Active MBR partition" `
                -Status "Warning" `
                -Message "Disk $($partition.DiskNumber), partition $($partition.PartitionNumber) is active ($drive)." `
                -Fix "If switching to UEFI/GPT, validate the boot layout before changing active partition state."
        }
    } catch {
        New-CheckResult -Category "Disk" -CheckName "Active MBR partition" -Status "Error" -Message "Active partition check failed: $($_.Exception.Message)"
    }
}

function Test-UnallocatedSpace {
    try {
        $disks = Get-Disk -ErrorAction Stop
        $found = $false

        foreach ($disk in $disks) {
            $largestFreeExtent = $disk.PSObject.Properties["LargestFreeExtent"]
            if ($null -ne $largestFreeExtent -and [int64]$disk.LargestFreeExtent -gt 104857600) {
                $found = $true
                $freeGb = [math]::Round($disk.LargestFreeExtent / 1GB, 2)
                New-CheckResult `
                    -Category "Disk" `
                    -CheckName "Disk $($disk.Number) unallocated space" `
                    -Status "Info" `
                    -Message "Disk $($disk.Number) has about $freeGb GB unallocated space." `
                    -Details @{ LargestFreeExtentBytes = $disk.LargestFreeExtent }
            } elseif ($disk.NumberOfPartitions -eq 0) {
                $found = $true
                New-CheckResult `
                    -Category "Disk" `
                    -CheckName "Disk $($disk.Number) unallocated space" `
                    -Status "Warning" `
                    -Message "Disk $($disk.Number) has no partitions." `
                    -Fix "Initialize or partition the disk before using BitLocker."
            }
        }

        if (-not $found) {
            New-CheckResult -Category "Disk" -CheckName "Unallocated space" -Status "OK" -Message "No large unallocated disk ranges were detected."
        }
    } catch {
        New-CheckResult -Category "Disk" -CheckName "Unallocated space" -Status "Error" -Message "Unallocated space check failed: $($_.Exception.Message)"
    }
}

function Test-FileSystem {
    param([string]$DriveLetter)

    if (-not (Test-Path "${DriveLetter}:\")) {
        return New-CheckResult -Category "Volume" -CheckName "${DriveLetter}: filesystem" -Status "Info" -Message "${DriveLetter}: was not found; skipped."
    }

    try {
        $volume = Get-Volume -DriveLetter $DriveLetter -ErrorAction Stop
        if ($volume.FileSystem -eq "NTFS") {
            return New-CheckResult -Category "Volume" -CheckName "${DriveLetter}: filesystem" -Status "OK" -Message "${DriveLetter}: filesystem is NTFS." -Details $volume.FileSystem
        }

        New-CheckResult `
            -Category "Volume" `
            -CheckName "${DriveLetter}: filesystem" `
            -Status "Warning" `
            -Message "${DriveLetter}: filesystem is $($volume.FileSystem)." `
            -Fix "Use NTFS for BitLocker OS and fixed data volumes." `
            -Details $volume.FileSystem
    } catch {
        New-CheckResult -Category "Volume" -CheckName "${DriveLetter}: filesystem" -Status "Error" -Message "${DriveLetter}: filesystem check failed: $($_.Exception.Message)"
    }
}

function Format-KeyProtectorTypes {
    param([object[]]$KeyProtectors)

    $types = @(
        $KeyProtectors |
            Where-Object { $_.KeyProtectorType } |
            ForEach-Object { [string]$_.KeyProtectorType } |
            Select-Object -Unique
    )

    if (-not $types -or $types.Count -eq 0) {
        return "None"
    }

    $types -join ", "
}

function Test-EncryptionMethod {
    param(
        [string]$DriveLetter,
        [object]$Volume
    )

    $method = $Volume.PSObject.Properties["EncryptionMethod"]
    if ($null -eq $method -or [string]::IsNullOrWhiteSpace([string]$Volume.EncryptionMethod)) {
        return New-CheckResult `
            -Category "BitLocker" `
            -CheckName "${DriveLetter}: encryption method" `
            -Status "Info" `
            -Message "${DriveLetter}: encryption method is not exposed by this BitLocker provider."
    }

    if ([string]$Volume.EncryptionMethod -eq "None") {
        return New-CheckResult `
            -Category "BitLocker" `
            -CheckName "${DriveLetter}: encryption method" `
            -Status "Warning" `
            -Message "${DriveLetter}: encryption method is None." `
            -Fix "Enable BitLocker if this volume should be encrypted." `
            -Details $Volume.EncryptionMethod
    }

    New-CheckResult `
        -Category "BitLocker" `
        -CheckName "${DriveLetter}: encryption method" `
        -Status "OK" `
        -Message "${DriveLetter}: encryption method is $($Volume.EncryptionMethod)." `
        -Details $Volume.EncryptionMethod
}

function Test-EncryptionScope {
    param(
        [string]$DriveLetter,
        [object]$Volume
    )

    $percentage = $Volume.PSObject.Properties["EncryptionPercentage"]
    if ($null -ne $percentage) {
        $status = if ([int]$Volume.EncryptionPercentage -eq 100) { "OK" } else { "Info" }
        return New-CheckResult `
            -Category "BitLocker" `
            -CheckName "${DriveLetter}: encryption progress" `
            -Status $status `
            -Message "${DriveLetter}: encryption percentage is $($Volume.EncryptionPercentage)%." `
            -Details @{ EncryptionPercentage = $Volume.EncryptionPercentage; VolumeStatus = $Volume.VolumeStatus }
    }

    New-CheckResult `
        -Category "BitLocker" `
        -CheckName "${DriveLetter}: encryption progress" `
        -Status "Info" `
        -Message "${DriveLetter}: encryption percentage is not exposed by this BitLocker provider." `
        -Details $Volume.VolumeStatus
}

function Test-KeyProtectors {
    param(
        [string]$DriveLetter,
        [object[]]$KeyProtectors
    )

    $protectorTypes = Format-KeyProtectorTypes -KeyProtectors $KeyProtectors
    if ($protectorTypes -eq "None") {
        return New-CheckResult `
            -Category "BitLocker" `
            -CheckName "${DriveLetter}: key protectors" `
            -Status "Warning" `
            -Message "${DriveLetter}: no BitLocker key protectors were detected." `
            -Fix "Add a suitable BitLocker protector before relying on this volume for protection."
    }

    New-CheckResult `
        -Category "BitLocker" `
        -CheckName "${DriveLetter}: key protectors" `
        -Status "OK" `
        -Message "${DriveLetter}: key protector types: $protectorTypes." `
        -Details $KeyProtectors
}

function Test-RecoveryBackupVisibility {
    param(
        [string]$DriveLetter,
        [object[]]$RecoveryProtectors
    )

    if (-not $RecoveryProtectors -or $RecoveryProtectors.Count -eq 0) {
        return
    }

    New-CheckResult `
        -Category "BitLocker" `
        -CheckName "${DriveLetter}: recovery backup" `
        -Status "Info" `
        -Message "${DriveLetter}: recovery password exists, but local diagnostics cannot verify AD DS or Entra ID backup status." `
        -Fix "Confirm the recovery key is backed up to your organization-approved location before changing protectors."
}

function Test-SuspendedProtection {
    param(
        [string]$DriveLetter,
        [object]$Volume
    )

    if ($Volume.ProtectionStatus -eq "On") {
        return New-CheckResult `
            -Category "BitLocker" `
            -CheckName "${DriveLetter}: suspension" `
            -Status "OK" `
            -Message "${DriveLetter}: BitLocker protection is not suspended."
    }

    New-CheckResult `
        -Category "BitLocker" `
        -CheckName "${DriveLetter}: suspension" `
        -Status "Warning" `
        -Message "${DriveLetter}: BitLocker protection may be suspended or disabled because protection is $($Volume.ProtectionStatus)." `
        -Fix "Run: Resume-BitLocker -MountPoint ${DriveLetter}: after confirming recovery keys are backed up."
}

function Test-BitLockerVolume {
    param([string]$DriveLetter)

    if (-not (Test-Path "${DriveLetter}:\")) {
        return New-CheckResult -Category "BitLocker" -CheckName "${DriveLetter}: BitLocker" -Status "Info" -Message "${DriveLetter}: was not found; skipped."
    }

    if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
        try {
            $volume = Get-BitLockerVolume -MountPoint "${DriveLetter}:" -ErrorAction Stop
            $results = @()

            if ($volume.VolumeStatus -eq "FullyEncrypted") {
                $results += New-CheckResult -Category "BitLocker" -CheckName "${DriveLetter}: encryption" -Status "OK" -Message "${DriveLetter}: is fully encrypted." -Details $volume.VolumeStatus
            } elseif ($volume.VolumeStatus -eq "FullyDecrypted") {
                $results += New-CheckResult `
                    -Category "BitLocker" `
                    -CheckName "${DriveLetter}: encryption" `
                    -Status "Warning" `
                    -Message "${DriveLetter}: is not encrypted." `
                    -Fix "Enable BitLocker if this volume should be protected." `
                    -Details $volume.VolumeStatus
            } else {
                $results += New-CheckResult -Category "BitLocker" -CheckName "${DriveLetter}: encryption" -Status "Info" -Message "${DriveLetter}: encryption status is $($volume.VolumeStatus)." -Details $volume.VolumeStatus
            }

            $results += Test-EncryptionMethod -DriveLetter $DriveLetter -Volume $volume
            $results += Test-EncryptionScope -DriveLetter $DriveLetter -Volume $volume

            if ($volume.ProtectionStatus -eq "On") {
                $results += New-CheckResult -Category "BitLocker" -CheckName "${DriveLetter}: protection" -Status "OK" -Message "${DriveLetter}: BitLocker protection is on." -Details $volume.ProtectionStatus
            } else {
                $results += New-CheckResult `
                    -Category "BitLocker" `
                    -CheckName "${DriveLetter}: protection" `
                    -Status "Warning" `
                    -Message "${DriveLetter}: BitLocker protection is $($volume.ProtectionStatus)." `
                    -Fix "Resume or enable BitLocker protection after confirming recovery keys are backed up." `
                    -Details $volume.ProtectionStatus
            }

            $results += Test-SuspendedProtection -DriveLetter $DriveLetter -Volume $volume
            $results += Test-KeyProtectors -DriveLetter $DriveLetter -KeyProtectors $volume.KeyProtector

            $hasRecoveryPassword = $volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }
            if ($hasRecoveryPassword) {
                $results += New-CheckResult -Category "BitLocker" -CheckName "${DriveLetter}: recovery password" -Status "OK" -Message "${DriveLetter}: has a recovery password protector."
                $results += Test-RecoveryBackupVisibility -DriveLetter $DriveLetter -RecoveryProtectors $hasRecoveryPassword
            } else {
                $results += New-CheckResult `
                    -Category "BitLocker" `
                    -CheckName "${DriveLetter}: recovery password" `
                    -Status "Warning" `
                    -Message "${DriveLetter}: recovery password protector is missing." `
                    -Fix "Run: Add-BitLockerKeyProtector -MountPoint ${DriveLetter}: -RecoveryPasswordProtector"
            }

            $systemDrive = $env:SystemDrive.TrimEnd(":").ToUpperInvariant()
            if ($DriveLetter -ne $systemDrive -and $null -ne $volume.AutoUnlockEnabled) {
                if ($volume.AutoUnlockEnabled) {
                    $results += New-CheckResult -Category "BitLocker" -CheckName "${DriveLetter}: auto-unlock" -Status "OK" -Message "${DriveLetter}: auto-unlock is enabled."
                } else {
                    $results += New-CheckResult `
                        -Category "BitLocker" `
                        -CheckName "${DriveLetter}: auto-unlock" `
                        -Status "Warning" `
                        -Message "${DriveLetter}: auto-unlock is disabled." `
                        -Fix "Run: Enable-BitLockerAutoUnlock -MountPoint ${DriveLetter}:"
                }
            }

            return $results
        } catch {
            return New-CheckResult -Category "BitLocker" -CheckName "${DriveLetter}: BitLocker" -Status "Error" -Message "${DriveLetter}: BitLocker check failed: $($_.Exception.Message)"
        }
    }

    try {
        $status = (& manage-bde -status "${DriveLetter}:" 2>&1) -join "`n"
        $protectors = (& manage-bde -protectors -get "${DriveLetter}:" 2>&1) -join "`n"
        $results = @()

        if ($status -match "Fully Encrypted|Percentage Encrypted:\s*100") {
            $results += New-CheckResult -Category "BitLocker" -CheckName "${DriveLetter}: encryption" -Status "OK" -Message "${DriveLetter}: appears fully encrypted." -Details $status
        } else {
            $results += New-CheckResult -Category "BitLocker" -CheckName "${DriveLetter}: encryption" -Status "Info" -Message "${DriveLetter}: manage-bde status was collected." -Details $status
        }

        if ($status -match "Encryption Method:\s*(.+)") {
            $method = $Matches[1].Trim()
            $methodStatus = if ($method -match "None") { "Warning" } else { "OK" }
            $methodFix = if ($methodStatus -eq "Warning") { "Enable BitLocker if this volume should be encrypted." } else { $null }
            $results += New-CheckResult `
                -Category "BitLocker" `
                -CheckName "${DriveLetter}: encryption method" `
                -Status $methodStatus `
                -Message "${DriveLetter}: encryption method is $method." `
                -Fix $methodFix `
                -Details $method
        }

        if ($status -match "Percentage Encrypted:\s*(.+)") {
            $percentageText = $Matches[1].Trim()
            $percentageStatus = if ($percentageText -match "^100(\.0+)?%") { "OK" } else { "Info" }
            $results += New-CheckResult `
                -Category "BitLocker" `
                -CheckName "${DriveLetter}: encryption progress" `
                -Status $percentageStatus `
                -Message "${DriveLetter}: encryption percentage is $percentageText." `
                -Details $percentageText
        }

        if ($status -match "Protection Status:\s*(.+)") {
            $protectionText = $Matches[1].Trim()
            if ($protectionText -match "Protection On") {
                $results += New-CheckResult -Category "BitLocker" -CheckName "${DriveLetter}: protection" -Status "OK" -Message "${DriveLetter}: BitLocker protection is on." -Details $protectionText
                $results += New-CheckResult -Category "BitLocker" -CheckName "${DriveLetter}: suspension" -Status "OK" -Message "${DriveLetter}: BitLocker protection is not suspended."
            } else {
                $results += New-CheckResult `
                    -Category "BitLocker" `
                    -CheckName "${DriveLetter}: protection" `
                    -Status "Warning" `
                    -Message "${DriveLetter}: BitLocker protection status is $protectionText." `
                    -Fix "Run: manage-bde -protectors -enable ${DriveLetter}: after confirming recovery keys are backed up." `
                    -Details $protectionText
                $results += New-CheckResult `
                    -Category "BitLocker" `
                    -CheckName "${DriveLetter}: suspension" `
                    -Status "Warning" `
                    -Message "${DriveLetter}: BitLocker protection may be suspended or disabled." `
                    -Fix "Run: manage-bde -protectors -enable ${DriveLetter}: after confirming recovery keys are backed up."
            }
        }

        $protectorTypes = @()
        foreach ($protectorName in @("TPM", "TPM And PIN", "Numerical Password", "Recovery Password", "External Key", "Password", "SID")) {
            if ($protectors -match [regex]::Escape($protectorName)) {
                $protectorTypes += $protectorName
            }
        }

        if ($protectorTypes.Count -gt 0) {
            $results += New-CheckResult `
                -Category "BitLocker" `
                -CheckName "${DriveLetter}: key protectors" `
                -Status "OK" `
                -Message "${DriveLetter}: key protector types: $(($protectorTypes | Select-Object -Unique) -join ', ')." `
                -Details $protectors
        } else {
            $results += New-CheckResult `
                -Category "BitLocker" `
                -CheckName "${DriveLetter}: key protectors" `
                -Status "Warning" `
                -Message "${DriveLetter}: no BitLocker key protectors were detected." `
                -Fix "Add a suitable BitLocker protector before relying on this volume for protection." `
                -Details $protectors
        }

        if ($protectors -match "Numerical Password|Recovery Password") {
            $results += New-CheckResult -Category "BitLocker" -CheckName "${DriveLetter}: recovery password" -Status "OK" -Message "${DriveLetter}: has a recovery password protector." -Details $protectors
            $results += New-CheckResult `
                -Category "BitLocker" `
                -CheckName "${DriveLetter}: recovery backup" `
                -Status "Info" `
                -Message "${DriveLetter}: recovery password exists, but local diagnostics cannot verify AD DS or Entra ID backup status." `
                -Fix "Confirm the recovery key is backed up to your organization-approved location before changing protectors."
        } else {
            $results += New-CheckResult `
                -Category "BitLocker" `
                -CheckName "${DriveLetter}: recovery password" `
                -Status "Warning" `
                -Message "${DriveLetter}: recovery password protector was not detected." `
                -Fix "Run: manage-bde -protectors -add ${DriveLetter}: -RecoveryPassword" `
                -Details $protectors
        }

        $systemDrive = $env:SystemDrive.TrimEnd(":").ToUpperInvariant()
        if ($DriveLetter -ne $systemDrive) {
            if ($protectors -match "External Key") {
                $results += New-CheckResult -Category "BitLocker" -CheckName "${DriveLetter}: auto-unlock" -Status "OK" -Message "${DriveLetter}: auto-unlock protector was detected."
            } else {
                $results += New-CheckResult `
                    -Category "BitLocker" `
                    -CheckName "${DriveLetter}: auto-unlock" `
                    -Status "Warning" `
                    -Message "${DriveLetter}: auto-unlock protector was not detected." `
                    -Fix "Run: manage-bde -autounlock -enable ${DriveLetter}:"
            }
        }

        return $results
    } catch {
        New-CheckResult -Category "BitLocker" -CheckName "${DriveLetter}: BitLocker" -Status "Error" -Message "${DriveLetter}: manage-bde check failed: $($_.Exception.Message)"
    }
}

function Get-BitLockerPolicyInterpretation {
    param([object[]]$ConfiguredPolicies)

    $knownPolicies = @{
        UseAdvancedStartup          = "Controls advanced startup authentication options for OS drives."
        EnableBDEWithNoTPM          = "Controls whether BitLocker can be enabled without a compatible TPM."
        UseTPM                      = "Controls TPM startup protector usage."
        UseTPMPIN                   = "Controls TPM+PIN startup protector usage."
        UseTPMKey                   = "Controls TPM+startup key protector usage."
        UseTPMKeyPIN                = "Controls TPM+PIN+startup key protector usage."
        OSRecovery                  = "Controls OS drive recovery options."
        OSRequireActiveDirectoryBackup = "Controls whether OS drive recovery information must be backed up before BitLocker is enabled."
        OSActiveDirectoryBackup     = "Controls OS drive recovery backup to Active Directory Domain Services."
        FDVRecovery                 = "Controls fixed data drive recovery options."
        FDVRequireActiveDirectoryBackup = "Controls whether fixed data drive recovery information must be backed up before BitLocker is enabled."
        RDVRecovery                 = "Controls removable data drive recovery options."
        RDVRequireActiveDirectoryBackup = "Controls whether removable data drive recovery information must be backed up before BitLocker is enabled."
        EncryptionMethod            = "Controls legacy encryption method policy."
        EncryptionMethodWithXtsOs   = "Controls OS drive encryption method policy."
        EncryptionMethodWithXtsFdv  = "Controls fixed data drive encryption method policy."
        EncryptionMethodWithXtsRdv  = "Controls removable data drive encryption method policy."
        UsePartialEncryptionKey     = "Controls enhanced PIN or startup key requirements."
        UseEnhancedPin              = "Controls whether enhanced startup PINs are allowed."
    }

    $interpretations = @()
    foreach ($policy in $ConfiguredPolicies) {
        foreach ($value in $policy.Values) {
            $parts = $value -split "=", 2
            if ($parts.Count -ne 2) {
                continue
            }

            $name = $parts[0]
            if (-not $knownPolicies.ContainsKey($name)) {
                continue
            }

            $interpretations += [PSCustomObject]@{
                Path        = $policy.Path
                Name        = $name
                Value       = $parts[1]
                Meaning     = $knownPolicies[$name]
            }
        }
    }

    $interpretations
}

function Test-BitLockerPolicy {
    $policyPaths = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\FVE",
        "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FVE"
    )

    try {
        $configuredPolicies = @()
        foreach ($path in $policyPaths) {
            if (-not (Test-Path $path)) {
                continue
            }

            $values = Get-ItemProperty -Path $path -ErrorAction Stop
            $policyValues = $values.PSObject.Properties |
                Where-Object { $_.Name -notlike "PS*" } |
                ForEach-Object { "$($_.Name)=$($_.Value)" }

            $configuredPolicies += [PSCustomObject]@{
                Path   = $path
                Values = $policyValues
            }
        }

        if (-not $configuredPolicies) {
            return New-CheckResult -Category "Policy" -CheckName "BitLocker policy" -Status "OK" -Message "No BitLocker policy registry keys were found."
        }

        $results = @()
        $results += New-CheckResult `
            -Category "Policy" `
            -CheckName "BitLocker policy" `
            -Status "Warning" `
            -Message "BitLocker policy registry keys are configured." `
            -Fix "Review Group Policy or MDM BitLocker settings if encryption or protector changes fail." `
            -Details $configuredPolicies

        $interpretedPolicies = @(Get-BitLockerPolicyInterpretation -ConfiguredPolicies $configuredPolicies)
        if ($interpretedPolicies.Count -gt 0) {
            $policyNames = ($interpretedPolicies | Select-Object -ExpandProperty Name -Unique) -join ", "
            $results += New-CheckResult `
                -Category "Policy" `
                -CheckName "BitLocker policy interpretation" `
                -Status "Info" `
                -Message "Interpreted BitLocker policy values: $policyNames." `
                -Details $interpretedPolicies
        } else {
            $results += New-CheckResult `
                -Category "Policy" `
                -CheckName "BitLocker policy interpretation" `
                -Status "Info" `
                -Message "No known BitLocker policy values were recognized for interpretation." `
                -Details $configuredPolicies
        }

        $results
    } catch {
        New-CheckResult -Category "Policy" -CheckName "BitLocker policy" -Status "Error" -Message "BitLocker policy check failed: $($_.Exception.Message)"
    }
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

function Export-JsonReport {
    param(
        [object[]]$Results,
        [string]$Path
    )

    $Results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Export-HtmlReport {
    param(
        [object[]]$Results,
        [string]$Path
    )

    $rows = foreach ($result in $Results) {
        $status = [System.Net.WebUtility]::HtmlEncode($result.Status)
        $category = [System.Net.WebUtility]::HtmlEncode($result.Category)
        $checkName = [System.Net.WebUtility]::HtmlEncode($result.CheckName)
        $message = [System.Net.WebUtility]::HtmlEncode($result.Message)
        $fix = [System.Net.WebUtility]::HtmlEncode($result.Fix)

        "<tr class='$status'><td>$category</td><td>$checkName</td><td>$status</td><td>$message</td><td>$fix</td></tr>"
    }

    $generatedAt = [System.Net.WebUtility]::HtmlEncode((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
    $html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>BitLocker Diagnostics</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #1f2933; background: #f6f8fa; }
h1 { margin-bottom: 4px; }
p { color: #52606d; }
table { width: 100%; border-collapse: collapse; background: white; border: 1px solid #d9e2ec; }
th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid #e4e7eb; vertical-align: top; }
th { background: #e9eef3; }
tr.OK td:nth-child(3) { color: #137333; font-weight: 600; }
tr.Warning td:nth-child(3) { color: #9a6700; font-weight: 600; }
tr.Alert td:nth-child(3), tr.Error td:nth-child(3) { color: #b42318; font-weight: 600; }
tr.Info td:nth-child(3) { color: #52606d; font-weight: 600; }
</style>
</head>
<body>
<h1>BitLocker Diagnostics</h1>
<p>Generated at $generatedAt</p>
<table>
<thead>
<tr><th>Category</th><th>Check</th><th>Status</th><th>Message</th><th>Fix</th></tr>
</thead>
<tbody>
$($rows -join "`n")
</tbody>
</table>
</body>
</html>
"@

    $html | Set-Content -LiteralPath $Path -Encoding UTF8
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


function Invoke-BitDiagInteractive {
    param(
        [ValidateSet("Auto", "Always", "Never")]
        [string]$Color = "Auto"
    )

    $useColor = Test-UseColor -Mode $Color
    while ($true) {
        Write-ConsoleBanner -UseColor $useColor
        Write-ConsoleLine -Message "" -UseColor $useColor
        Write-ConsoleLine -Message "BitDiag interactive menu" -ForegroundColor Cyan -UseColor $useColor
        Write-ConsoleLine -Message "  1. Run all diagnostics" -UseColor $useColor
        Write-ConsoleLine -Message "  2. Show problems only" -UseColor $useColor
        Write-ConsoleLine -Message "  3. Select drives" -UseColor $useColor
        Write-ConsoleLine -Message "  4. Export HTML report" -UseColor $useColor
        Write-ConsoleLine -Message "  5. Export JSON report" -UseColor $useColor
        Write-ConsoleLine -Message "  6. Show help" -UseColor $useColor
        Write-ConsoleLine -Message "  7. Exit" -UseColor $useColor
        Write-ConsoleLine -Message "" -UseColor $useColor

        $choice = Read-Host "Choose an option"
        switch ($choice) {
            "1" { bitdiag -Run -NoExitCode -Color $Color; return }
            "2" { bitdiag -Run -ProblemsOnly -NoExitCode -Color $Color; return }
            "3" {
                $driveInput = Read-Host "Drive letters (example: C,D)"
                if ([string]::IsNullOrWhiteSpace($driveInput)) {
                    Write-ConsoleLine -Message "No drive letters entered." -ForegroundColor Yellow -UseColor $useColor
                    continue
                }

                $driveLetters = $driveInput -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 }
                bitdiag -Run -Drives $driveLetters -NoExitCode -Color $Color
                return
            }
            "4" {
                $path = Read-Host "HTML report path (blank for automatic name)"
                if ([string]::IsNullOrWhiteSpace($path)) {
                    bitdiag -Run -Format Html -NoExitCode -Color $Color
                } else {
                    bitdiag -Run -Format Html -OutFile $path -NoExitCode -Color $Color
                }
                return
            }
            "5" {
                $path = Read-Host "JSON report path (blank for automatic name)"
                if ([string]::IsNullOrWhiteSpace($path)) {
                    bitdiag -Run -Format Json -NoExitCode -Color $Color
                } else {
                    bitdiag -Run -Format Json -OutFile $path -NoExitCode -Color $Color
                }
                return
            }
            "6" { bitdiag -Help -NoExitCode -Color $Color; return }
            "7" { return }
            default { Write-ConsoleLine -Message "Invalid choice." -ForegroundColor Yellow -UseColor $useColor }
        }
    }
}

function bitdiag {
    [CmdletBinding()]
    param(
        [Alias("Drive", "Drives")]
        [string[]]$DriveLetters,

        [switch]$AllDrives,

        [Alias("Format")]
        [ValidateSet("Console", "Json", "Html", "None")]
        [string]$OutputFormat = "Console",

        [Alias("OutFile", "Path")]
        [string]$OutputPath,

        [ValidateSet("Runtime", "Platform", "Disk", "Policy", "Volume", "BitLocker")]
        [string[]]$Category,

        [ValidateSet("OK", "Warning", "Alert", "Error", "Info")]
        [string[]]$Status,

        [Alias("OnlyProblems")]
        [switch]$ProblemsOnly,

        [switch]$Detailed,

        [ValidateSet("Auto", "Always", "Never")]
        [string]$Color = "Auto",

        [switch]$Quiet,

        [switch]$PassThru,

        [Alias("h")]
        [switch]$Help,

        [switch]$NoExitCode,

        [switch]$Run,

        [switch]$Interactive,

        [switch]$ExitProcess
    )

    $userParameterNames = @($PSBoundParameters.Keys | Where-Object { $_ -ne "ExitProcess" })
    if ($Interactive -or (-not $Run -and $userParameterNames.Count -eq 0)) {
        Invoke-BitDiagInteractive -Color $Color
        return
    }

    $useColor = Test-UseColor -Mode $Color
    if ($Help) {
        if (-not $Quiet) {
            Show-Usage -UseColor $useColor
        }

        if (-not $NoExitCode -and $ExitProcess) {
            exit 0
        }

        if (-not $NoExitCode -and -not $ExitProcess) {
            $global:LASTEXITCODE = 0
        }

        return
    }

    $driveDiscoveryResults = @()
    $driveLettersSpecified = $PSBoundParameters.ContainsKey("DriveLetters")
    if ($AllDrives -or -not $driveLettersSpecified) {
        $detectedDrives = @(Get-DetectedDriveLetters)
        $driveDiscoveryResults = @($detectedDrives | Where-Object { $_.PSObject.Properties["Category"] })
        $normalizedDriveLetters = @($detectedDrives | Where-Object { $_ -is [string] })

        if (-not $normalizedDriveLetters -or $normalizedDriveLetters.Count -eq 0) {
            if ($driveLettersSpecified) {
                $normalizedDriveLetters = ConvertTo-DriveLetter -Letters $DriveLetters
            } elseif ($env:SystemDrive) {
                $normalizedDriveLetters = ConvertTo-DriveLetter -Letters $env:SystemDrive
            } else {
                $normalizedDriveLetters = @("C")
            }

            $driveDiscoveryResults += New-CheckResult `
                -Category "Runtime" `
                -CheckName "Drive discovery" `
                -Status "Warning" `
                -Message "No drives were discovered automatically; falling back to $($normalizedDriveLetters -join ', ')." `
                -Fix "Run as administrator or pass drive letters explicitly with -DriveLetters C."
        }
    } else {
        $normalizedDriveLetters = ConvertTo-DriveLetter -Letters $DriveLetters
    }

    $bootMode = Get-BootMode
    $tpmState = Get-TpmState

    $results = @()
    $results += Test-RunningAsAdmin
    $results += $driveDiscoveryResults
    $results += Test-BootMode -BootMode $bootMode
    $results += Test-SecureBoot -BootMode $bootMode
    $results += Test-Tpm -TpmState $tpmState
    $results += Test-TpmBootCompatibility -TpmState $tpmState -BootMode $bootMode
    $results += Test-DiskPartitionStyle
    $results += Test-EfiSystemPartition
    $results += Test-DiskDynamic
    $results += Test-ActiveMbrPartition
    $results += Test-UnallocatedSpace
    $results += Test-BitLockerPolicy

    foreach ($driveLetter in $normalizedDriveLetters) {
        $results += Test-FileSystem -DriveLetter $driveLetter
        $results += Test-BitLockerVolume -DriveLetter $driveLetter
    }

    $reportResults = Select-DiagnosticResults -Results $results -Category $Category -Status $Status -ProblemsOnly:$ProblemsOnly

    switch ($OutputFormat) {
        "Console" {
            if (-not $Quiet) {
                Write-ConsoleReport -Results $reportResults -AllResults $results -DriveLetters $normalizedDriveLetters -Detailed:$Detailed -UseColor $useColor
            }
        }
        "Json" {
            if (-not $OutputPath) {
                $OutputPath = Get-DefaultReportPath -Format $OutputFormat
            }

            Export-JsonReport -Results $reportResults -Path $OutputPath
            if (-not $Quiet) {
                Write-ConsoleLine -Message "JSON report written to $OutputPath" -ForegroundColor Cyan -UseColor $useColor
            }
        }
        "Html" {
            if (-not $OutputPath) {
                $OutputPath = Get-DefaultReportPath -Format $OutputFormat
            }

            Export-HtmlReport -Results $reportResults -Path $OutputPath
            if (-not $Quiet) {
                Write-ConsoleLine -Message "HTML report written to $OutputPath" -ForegroundColor Cyan -UseColor $useColor
            }
        }
        "None" {
            if (-not $Quiet) {
                Write-ConsoleLine -Message ("Diagnostics completed. Results: {0}; exit code: {1}" -f $results.Count, (Get-DiagnosticsExitCode -Results $results)) -ForegroundColor Cyan -UseColor $useColor
            }
        }
    }

    if ($PassThru) {
        $reportResults
    }

    $exitCode = Get-DiagnosticsExitCode -Results $results
    if (-not $NoExitCode -and $ExitProcess) {
        exit $exitCode
    }

    if (-not $NoExitCode -and -not $ExitProcess) {
        $global:LASTEXITCODE = $exitCode
    }
}
