# BitDiag internal source: 50-Diagnostics.Policy.ps1

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
        FDVDenyWriteAccess          = "Denies write access to fixed data drives that are not protected by BitLocker."
        RDVDenyWriteAccess          = "Denies write access to removable data drives that are not protected by BitLocker."
        FDVActiveDirectoryBackup    = "Controls fixed data drive recovery backup to Active Directory Domain Services."
        RDVActiveDirectoryBackup    = "Controls removable data drive recovery backup to Active Directory Domain Services."
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

function Get-BitLockerPolicySpecificFindings {
    param([object[]]$ConfiguredPolicies)

    $flatValues = @()
    foreach ($policy in $ConfiguredPolicies) {
        foreach ($value in $policy.Values) {
            $parts = $value -split "=", 2
            if ($parts.Count -ne 2) {
                continue
            }

            $flatValues += [PSCustomObject]@{
                Path  = $policy.Path
                Name  = $parts[0]
                Value = $parts[1]
            }
        }
    }

    $results = @()
    foreach ($policyValue in $flatValues) {
        switch ($policyValue.Name) {
            "FDVDenyWriteAccess" {
                if ([string]$policyValue.Value -eq "1") {
                    $results += New-CheckResult `
                        -Category "Policy" `
                        -CheckName "Fixed data drive write policy" `
                        -Status "Warning" `
                        -Message "Policy denies write access to fixed data drives that are not protected by BitLocker." `
                        -Fix "Enable BitLocker on the fixed data drive, or review the FDVDenyWriteAccess policy in Group Policy/MDM." `
                        -Details $policyValue
                }
            }
            "RDVDenyWriteAccess" {
                if ([string]$policyValue.Value -eq "1") {
                    $results += New-CheckResult `
                        -Category "Policy" `
                        -CheckName "Removable drive write policy" `
                        -Status "Warning" `
                        -Message "Policy denies write access to removable drives that are not protected by BitLocker." `
                        -Fix "Enable BitLocker To Go where appropriate, or review the RDVDenyWriteAccess policy in Group Policy/MDM." `
                        -Details $policyValue
                }
            }
            "OSRequireActiveDirectoryBackup" {
                if ([string]$policyValue.Value -eq "1") {
                    $results += New-CheckResult `
                        -Category "Policy" `
                        -CheckName "OS recovery escrow policy" `
                        -Status "Info" `
                        -Message "Policy requires OS drive recovery information to be backed up before BitLocker is enabled." `
                        -Fix "Confirm AD DS recovery escrow succeeds before relying on OS drive protection changes." `
                        -Details $policyValue
                }
            }
            "FDVRequireActiveDirectoryBackup" {
                if ([string]$policyValue.Value -eq "1") {
                    $results += New-CheckResult `
                        -Category "Policy" `
                        -CheckName "Fixed data recovery escrow policy" `
                        -Status "Info" `
                        -Message "Policy requires fixed data drive recovery information to be backed up before BitLocker is enabled." `
                        -Fix "Confirm AD DS recovery escrow succeeds before relying on fixed data drive protection changes." `
                        -Details $policyValue
                }
            }
            "RDVRequireActiveDirectoryBackup" {
                if ([string]$policyValue.Value -eq "1") {
                    $results += New-CheckResult `
                        -Category "Policy" `
                        -CheckName "Removable recovery escrow policy" `
                        -Status "Info" `
                        -Message "Policy requires removable drive recovery information to be backed up before BitLocker is enabled." `
                        -Fix "Confirm AD DS recovery escrow succeeds before relying on removable drive protection changes." `
                        -Details $policyValue
                }
            }
        }
    }

    $results
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

        $results += Get-BitLockerPolicySpecificFindings -ConfiguredPolicies $configuredPolicies

        $results
    } catch {
        New-CheckResult -Category "Policy" -CheckName "BitLocker policy" -Status "Error" -Message "BitLocker policy check failed: $($_.Exception.Message)"
    }
}

