# BitDiag internal source: 20-Diagnostics.Platform.ps1

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

