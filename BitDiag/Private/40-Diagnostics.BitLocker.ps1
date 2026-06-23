# BitDiag internal source: 40-Diagnostics.BitLocker.ps1

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

function Normalize-BitLockerProtectorId {
    param([object]$Value)

    if ($null -eq $Value) {
        return ""
    }

    $text = ([string]$Value).Trim().Trim("{", "}").ToUpperInvariant()
    $text = $text -replace "[^0-9A-F]", ""

    if ($text.Length -eq 32) {
        return $text
    }

    ""
}

function ConvertTo-CanonicalGuidFromBytes {
    param([byte[]]$Bytes)

    if (-not $Bytes -or $Bytes.Length -ne 16) {
        return @()
    }

    $ids = @()
    try {
        $ids += Normalize-BitLockerProtectorId -Value ([guid]::new($Bytes)).ToString()
    } catch {
        # Keep trying the raw byte order below.
    }

    try {
        $hex = @($Bytes | ForEach-Object { $_.ToString("X2") })
        $rawGuid = "{0}{1}{2}{3}-{4}{5}-{6}{7}-{8}{9}-{10}{11}{12}{13}{14}{15}" -f $hex
        $ids += Normalize-BitLockerProtectorId -Value $rawGuid
    } catch {
        # Ignore malformed byte values.
    }

    @($ids | Where-Object { $_ } | Select-Object -Unique)
}

function Get-BitLockerProtectorIdCandidates {
    param([object]$Value)

    if ($null -eq $Value) {
        return @()
    }

    $ids = @()
    if ($Value -is [byte[]]) {
        $ids += ConvertTo-CanonicalGuidFromBytes -Bytes $Value
    } else {
        $text = [string]$Value
        foreach ($match in [regex]::Matches($text, "(?i)\{?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}?")) {
            $ids += Normalize-BitLockerProtectorId -Value $match.Value
        }

        foreach ($match in [regex]::Matches($text, "(?i)(?<![0-9a-f])[0-9a-f]{32}(?![0-9a-f])")) {
            $ids += Normalize-BitLockerProtectorId -Value $match.Value
        }

        $direct = Normalize-BitLockerProtectorId -Value $text
        if ($direct) {
            $ids += $direct
        }
    }

    @($ids | Where-Object { $_ } | Select-Object -Unique)
}

function ConvertTo-LdapFilterValue {
    param([string]$Value)

    if ($null -eq $Value) {
        return ""
    }

    $Value.Replace("\", "\5c").Replace("*", "\2a").Replace("(", "\28").Replace(")", "\29").Replace([string][char]0, "\00")
}

function Get-AdDsRecoveryEscrowState {
    if ($script:BitDiagAdDsRecoveryEscrowState) {
        return $script:BitDiagAdDsRecoveryEscrowState
    }

    $state = [PSCustomObject]@{
        Available    = $false
        ProtectorIds = @()
        ObjectCount  = 0
        Message      = "AD DS recovery escrow could not be checked."
    }

    try {
        Add-Type -AssemblyName System.DirectoryServices -ErrorAction Stop | Out-Null

        $rootDse = [ADSI]"LDAP://RootDSE"
        $defaultNamingContext = [string]$rootDse.defaultNamingContext
        if ([string]::IsNullOrWhiteSpace($defaultNamingContext)) {
            $state.Message = "This machine does not appear to be joined to an AD DS domain."
            $script:BitDiagAdDsRecoveryEscrowState = $state
            return $state
        }

        $directoryRoot = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$defaultNamingContext")
        $computerSearcher = New-Object System.DirectoryServices.DirectorySearcher($directoryRoot)
        $computerSearcher.Filter = "(&(objectCategory=computer)(sAMAccountName=$(ConvertTo-LdapFilterValue -Value ("{0}$" -f $env:COMPUTERNAME))))"
        $computerSearcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        [void]$computerSearcher.PropertiesToLoad.Add("distinguishedName")
        $computerResult = $computerSearcher.FindOne()
        if (-not $computerResult -or -not $computerResult.Properties["distinguishedname"]) {
            $state.Message = "The local computer object was not found in AD DS."
            $script:BitDiagAdDsRecoveryEscrowState = $state
            return $state
        }

        $computerDn = [string]$computerResult.Properties["distinguishedname"][0]
        $computerEntry = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$computerDn")
        $recoverySearcher = New-Object System.DirectoryServices.DirectorySearcher($computerEntry)
        $recoverySearcher.Filter = "(objectClass=msFVE-RecoveryInformation)"
        $recoverySearcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $recoverySearcher.PageSize = 200
        [void]$recoverySearcher.PropertiesToLoad.Add("msFVE-RecoveryGuid")
        [void]$recoverySearcher.PropertiesToLoad.Add("name")
        [void]$recoverySearcher.PropertiesToLoad.Add("cn")
        [void]$recoverySearcher.PropertiesToLoad.Add("distinguishedName")
        [void]$recoverySearcher.PropertiesToLoad.Add("adspath")

        $ids = @()
        $objectCount = 0
        $searchResults = $recoverySearcher.FindAll()
        foreach ($recoveryResult in $searchResults) {
            $objectCount++
            foreach ($propertyName in @("msfve-recoveryguid", "msFVE-RecoveryGuid", "name", "cn", "distinguishedname", "distinguishedName", "adspath")) {
                if (-not $recoveryResult.Properties.Contains($propertyName)) {
                    continue
                }

                foreach ($propertyValue in $recoveryResult.Properties[$propertyName]) {
                    $ids += Get-BitLockerProtectorIdCandidates -Value $propertyValue
                }
            }
        }

        $ids = @($ids | Where-Object { $_ } | Select-Object -Unique)
        $state = [PSCustomObject]@{
            Available    = $true
            ProtectorIds = $ids
            ObjectCount  = $objectCount
            Message      = if ($objectCount -gt 0) {
                if ($ids.Count -gt 0) {
                    "AD DS recovery objects were visible for this computer and comparable protector IDs were extracted."
                } else {
                    "AD DS recovery objects were visible for this computer, but comparable protector IDs could not be extracted from visible attributes."
                }
            } else {
                "No AD DS recovery objects were visible for this computer."
            }
        }
    } catch {
        $state = [PSCustomObject]@{
            Available    = $false
            ProtectorIds = @()
            ObjectCount  = 0
            Message      = "AD DS recovery escrow check failed or was not permitted: $($_.Exception.Message)"
        }
    }

    $script:BitDiagAdDsRecoveryEscrowState = $state
    $state
}

function Get-AdDsEscrowDevelopmentNote {
    "AD DS escrow verification is currently a best-effort feature under development and depends on the current account's permission to read BitLocker recovery objects."
}

function Test-RecoveryBackupVisibility {
    param(
        [string]$DriveLetter,
        [object[]]$RecoveryProtectors
    )

    if (-not $RecoveryProtectors -or $RecoveryProtectors.Count -eq 0) {
        return
    }

    $localProtectorIds = @(
        $RecoveryProtectors |
            ForEach-Object { Get-BitLockerProtectorIdCandidates -Value $_.KeyProtectorId } |
            Where-Object { $_ } |
            Select-Object -Unique
    )

    $adEscrow = Get-AdDsRecoveryEscrowState
    if ($adEscrow.Available -and $adEscrow.ProtectorIds.Count -gt 0) {
        $matchedIds = @($localProtectorIds | Where-Object { $_ -in $adEscrow.ProtectorIds })
        if ($matchedIds.Count -gt 0) {
            return New-CheckResult `
                -Category "BitLocker" `
                -CheckName "${DriveLetter}: recovery backup" `
                -Status "OK" `
                -Message "${DriveLetter}: recovery password protector appears backed up to AD DS." `
                -Details @{
                    LocalRecoveryProtectorIds = $localProtectorIds
                    MatchedAdDsProtectorIds   = $matchedIds
                    VisibleAdDsObjectCount    = $adEscrow.ObjectCount
                    Source                    = "AD DS"
                }
        }

        return New-CheckResult `
            -Category "BitLocker" `
            -CheckName "${DriveLetter}: recovery backup" `
            -Status "Info" `
            -Message "${DriveLetter}: recovery password exists, but AD DS escrow could not be matched from the current user context. $(Get-AdDsEscrowDevelopmentNote)" `
            -Fix "Confirm escrow with an account delegated to read BitLocker recovery objects, or validate escrow centrally." `
            -Details @{
                LocalRecoveryProtectorIds = $localProtectorIds
                VisibleAdDsProtectorIds   = $adEscrow.ProtectorIds
                VisibleAdDsObjectCount    = $adEscrow.ObjectCount
                Source                    = "AD DS"
                Note                      = Get-AdDsEscrowDevelopmentNote
            }
    }

    New-CheckResult `
        -Category "BitLocker" `
        -CheckName "${DriveLetter}: recovery backup" `
        -Status "Info" `
        -Message "${DriveLetter}: recovery password exists, but AD DS or Entra ID escrow could not be verified from the current user context. $($adEscrow.Message) $(Get-AdDsEscrowDevelopmentNote)" `
        -Fix "Confirm escrow with an account delegated to read BitLocker recovery objects, or validate escrow centrally." `
        -Details @{
            LocalRecoveryProtectorIds = $localProtectorIds
            VisibleAdDsObjectCount    = $adEscrow.ObjectCount
            Source                    = "Local/Unknown"
            Message                   = $adEscrow.Message
            Note                      = Get-AdDsEscrowDevelopmentNote
        }
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

