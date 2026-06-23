# BitDiag internal source: 30-Diagnostics.Disk.ps1

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
            $checkName = if ($partition.DriveLetter) { "$($partition.DriveLetter): active MBR partition" } else { "Active MBR partition" }
            New-CheckResult `
                -Category "Disk" `
                -CheckName $checkName `
                -Status "Warning" `
                -Message "Disk $($partition.DiskNumber), partition $($partition.PartitionNumber) is active ($drive)." `
                -Fix "If this is a secondary MBR data disk, make the partition inactive only after validating boot layout and backups." `
                -Details @{
                    DiskNumber      = $partition.DiskNumber
                    PartitionNumber = $partition.PartitionNumber
                    DriveLetter     = $partition.DriveLetter
                    IsActive        = $partition.IsActive
                }
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

