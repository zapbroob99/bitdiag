# BitDiag internal source: 80-EnterpriseReport.ps1

function Format-EnterpriseText {
    param(
        [object]$Value,
        [int]$MaxLength = 500
    )

    if ($null -eq $Value) {
        return ""
    }

    $text = ([string]$Value -replace "\s+", " ").Trim()
    if ($text.Length -le $MaxLength) {
        return $text
    }

    $text.Substring(0, $MaxLength)
}

function Get-SafeFileNamePart {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return "unknown"
    }

    ($Value -replace "[^A-Za-z0-9._-]", "_").Trim("_")
}

function Get-ComputerDomainName {
    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($computerSystem.Domain) {
            return [string]$computerSystem.Domain
        }
    } catch {
        # Fall back below.
    }

    if ($env:USERDNSDOMAIN) {
        return [string]$env:USERDNSDOMAIN
    }

    if ($env:USERDOMAIN) {
        return [string]$env:USERDOMAIN
    }

    "WORKGROUP"
}

function Get-BitDiagDeviceGuid {
    $registryPath = "HKLM:\SOFTWARE\BitDiag"
    $valueName = "DeviceGuid"

    try {
        if (-not (Test-Path $registryPath)) {
            New-Item -Path $registryPath -Force -ErrorAction Stop | Out-Null
        }

        $existing = (Get-ItemProperty -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
        if ($existing) {
            return [string]$existing
        }

        $newGuid = [guid]::NewGuid().ToString()
        New-ItemProperty -Path $registryPath -Name $valueName -Value $newGuid -PropertyType String -Force -ErrorAction Stop | Out-Null
        return $newGuid
    } catch {
        try {
            $machineGuid = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid" -ErrorAction Stop).MachineGuid
            if ($machineGuid) {
                return [string]$machineGuid
            }
        } catch {
            # Fall back below.
        }
    }

    "unknown"
}

function Get-EnterpriseIdentity {
    [PSCustomObject]@{
        ComputerName = [string]$env:COMPUTERNAME
        Domain       = Get-ComputerDomainName
        DeviceGuid   = Get-BitDiagDeviceGuid
        UserContext  = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    }
}

function Get-ResultDriveLetter {
    param([object]$Result)

    if ($Result.CheckName -match "^([A-Z]):") {
        return $Matches[1]
    }

    ""
}

function Get-EnterpriseClassification {
    param(
        [object]$Result
    )

    if ($Result.Status -notin @("Warning", "Alert", "Error")) {
        return [PSCustomObject]@{ ReasonType = ""; RiskLevel = ""; CanApply = $false }
    }

    if ($Result.CheckName -match "^([A-Z]): recovery password" -and $Result.Message -match "missing|not detected") {
        return [PSCustomObject]@{ ReasonType = "MissingProtector"; RiskLevel = "Low"; CanApply = $true }
    }

    if ($Result.CheckName -match "^([A-Z]): protection" -and $Result.Status -in @("Warning", "Error")) {
        return [PSCustomObject]@{ ReasonType = "ProtectionOff"; RiskLevel = "Low"; CanApply = $true }
    }

    if ($Result.CheckName -match "^([A-Z]): suspension" -and $Result.Status -eq "Warning") {
        return [PSCustomObject]@{ ReasonType = "ProtectionOff"; RiskLevel = "Low"; CanApply = $true }
    }

    if ($Result.CheckName -match "^([A-Z]): auto-unlock" -and $Result.Status -eq "Warning") {
        return [PSCustomObject]@{ ReasonType = "AutoUnlockOff"; RiskLevel = "Low"; CanApply = $true }
    }

    if ($Result.CheckName -match "^([A-Z]): encryption" -and $Result.Message -match "not encrypted|method is None") {
        return [PSCustomObject]@{ ReasonType = "EncryptionOff"; RiskLevel = "Medium"; CanApply = $false }
    }

    if ($Result.CheckName -eq "Secure Boot") {
        return [PSCustomObject]@{ ReasonType = "Platform"; RiskLevel = "High"; CanApply = $false }
    }

    if ($Result.CheckName -match "partition style|TPM \+ boot mode|Boot mode|EFI System Partition|^ESP on|active MBR partition") {
        return [PSCustomObject]@{ ReasonType = "DiskLayout"; RiskLevel = "High"; CanApply = $false }
    }

    if ($Result.CheckName -match "BitLocker policy|write policy|escrow policy") {
        return [PSCustomObject]@{ ReasonType = "Policy"; RiskLevel = "Medium"; CanApply = $false }
    }

    if ($Result.Category -eq "Runtime") {
        return [PSCustomObject]@{ ReasonType = "Runtime"; RiskLevel = "Medium"; CanApply = $false }
    }

    [PSCustomObject]@{
        ReasonType = "Other"
        RiskLevel  = "Medium"
        CanApply   = $false
    }
}

function ConvertTo-EnterpriseRecord {
    param(
        [object]$Result,
        [object]$Identity,
        [string]$RunId,
        [string]$TimestampUtc,
        [string]$Version,
        [int]$ExitCode
    )

    $classification = Get-EnterpriseClassification -Result $Result

    [PSCustomObject]@{
        RunId          = $RunId
        TimestampUtc   = $TimestampUtc
        ComputerName   = Format-EnterpriseText -Value $Identity.ComputerName -MaxLength 128
        Domain         = Format-EnterpriseText -Value $Identity.Domain -MaxLength 256
        DeviceGuid     = Format-EnterpriseText -Value $Identity.DeviceGuid -MaxLength 64
        UserContext    = Format-EnterpriseText -Value $Identity.UserContext -MaxLength 256
        BitDiagVersion = $Version
        DriveLetter    = Get-ResultDriveLetter -Result $Result
        Category       = Format-EnterpriseText -Value $Result.Category -MaxLength 64
        CheckName      = Format-EnterpriseText -Value $Result.CheckName -MaxLength 160
        Status         = Format-EnterpriseText -Value $Result.Status -MaxLength 32
        Message        = Format-EnterpriseText -Value $Result.Message -MaxLength 500
        Fix            = Format-EnterpriseText -Value $Result.Fix -MaxLength 500
        ReasonType     = Format-EnterpriseText -Value $classification.ReasonType -MaxLength 64
        RiskLevel      = Format-EnterpriseText -Value $classification.RiskLevel -MaxLength 32
        CanApply       = [bool]$classification.CanApply
        ExitCode       = $ExitCode
    }
}

function Export-EnterpriseReport {
    param(
        [object[]]$Results,
        [string]$OutDirectory,
        [int]$ExitCode
    )

    if ([string]::IsNullOrWhiteSpace($OutDirectory)) {
        throw "OutDirectory is required when -EnterpriseReport is used."
    }

    $identity = Get-EnterpriseIdentity
    $runId = [guid]::NewGuid().ToString()
    $timestamp = Get-Date
    $timestampUtc = $timestamp.ToUniversalTime().ToString("o")
    $version = Get-BitDiagVersion

    $records = @(
        $Results | ForEach-Object {
            ConvertTo-EnterpriseRecord `
                -Result $_ `
                -Identity $identity `
                -RunId $runId `
                -TimestampUtc $timestampUtc `
                -Version $version `
                -ExitCode $ExitCode
        }
    )

    if (-not (Test-Path $OutDirectory)) {
        New-Item -ItemType Directory -Path $OutDirectory -Force | Out-Null
    }

    $safeComputer = Get-SafeFileNamePart -Value $identity.ComputerName
    $safeGuid = Get-SafeFileNamePart -Value $identity.DeviceGuid
    $stamp = $timestamp.ToString("yyyyMMdd-HHmmss")
    $fileName = "{0}_{1}_{2}.ndjson" -f $safeComputer, $safeGuid, $stamp
    $finalPath = Join-Path -Path $OutDirectory -ChildPath $fileName
    $remoteTempPath = "$finalPath.tmp"
    $localTempPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) ("bitdiag-{0}.ndjson" -f $runId)

    try {
        $lines = @($records | ForEach-Object { $_ | ConvertTo-Json -Depth 6 -Compress })
        Set-Content -LiteralPath $localTempPath -Value $lines -Encoding UTF8
        Copy-Item -LiteralPath $localTempPath -Destination $remoteTempPath -Force
        Move-Item -LiteralPath $remoteTempPath -Destination $finalPath -Force
    } finally {
        if (Test-Path $localTempPath) {
            Remove-Item -LiteralPath $localTempPath -Force
        }
    }

    $finalPath
}

