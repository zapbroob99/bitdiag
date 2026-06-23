# BitDiag internal source: bitdiag.ps1

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
        Write-ConsoleLine -Message "  6. Generate remediation plan" -UseColor $useColor
        Write-ConsoleLine -Message "  7. Preview automatic fixes" -UseColor $useColor
        Write-ConsoleLine -Message "  8. Enable BitLocker on unprotected drives" -UseColor $useColor
        Write-ConsoleLine -Message "  9. Show help" -UseColor $useColor
        Write-ConsoleLine -Message "  10. Exit" -UseColor $useColor
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
            "6" { bitdiag -Run -PlanFixes -NoExitCode -Color $Color; return }
            "7" { bitdiag -Run -Fix -WhatIf -NoExitCode -Color $Color; return }
            "8" {
                bitdiag -Run -EnableBitLocker -NoExitCode -Color $Color
                Write-ConsoleLine -Message "" -UseColor $useColor
                $confirm = Read-Host "Type APPLY to start BitLocker on eligible drives"
                if ($confirm -eq "APPLY") {
                    bitdiag -Run -EnableBitLocker -Apply -NoExitCode -Color $Color
                }
                return
            }
            "9" { bitdiag -Help -NoExitCode -Color $Color; return }
            "10" { return }
            default { Write-ConsoleLine -Message "Invalid choice." -ForegroundColor Yellow -UseColor $useColor }
        }
    }
}

function bitdiag {
    [CmdletBinding(SupportsShouldProcess = $true)]
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

        [switch]$PlanFixes,

        [switch]$Fix,

        [switch]$Risky,

        [switch]$EnableBitLocker,

        [switch]$Apply,

        [switch]$EnterpriseReport,

        [string]$OutDirectory,

        [switch]$Version,

        [switch]$ExitProcess
    )

    if ($Version) {
        Write-Output ("bitdiag {0}" -f (Get-BitDiagVersion))
        if (-not $NoExitCode -and $ExitProcess) {
            exit 0
        }
        if (-not $NoExitCode -and -not $ExitProcess) {
            $global:LASTEXITCODE = 0
        }
        return
    }

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

    if ($EnterpriseReport -and $EnableBitLocker) {
        Write-ConsoleLine -Message "Enterprise reporting and BitLocker enablement should be run as separate commands." -ForegroundColor Yellow -UseColor $useColor
    } elseif ($EnterpriseReport) {
        $enterpriseExitCode = Get-DiagnosticsExitCode -Results $results
        $enterprisePath = Export-EnterpriseReport -Results $results -OutDirectory $OutDirectory -ExitCode $enterpriseExitCode
        if (-not $Quiet) {
            Write-ConsoleLine -Message "Enterprise NDJSON report written to $enterprisePath" -ForegroundColor Cyan -UseColor $useColor
        }
    } elseif ($EnableBitLocker) {
        $enablePlan = @(Get-BitLockerEnablePlan -DriveLetters $normalizedDriveLetters -Results $results -BootMode $bootMode -TpmState $tpmState)
        Invoke-BitLockerEnable -Plan $enablePlan -Apply:$Apply -Quiet:$Quiet -UseColor $useColor
    } elseif ($Fix) {
        $fixPlan = @(Get-RemediationPlan -Results $reportResults)
        Invoke-SafeRemediation -Plan $fixPlan -Apply:$Apply -Risky:$Risky -UseColor $useColor
    } elseif ($PlanFixes) {
        $fixPlan = @(Get-RemediationPlan -Results $reportResults -Detailed:$Detailed)
        if ($PassThru) {
            $fixPlan
        } elseif (-not $Quiet) {
            Write-RemediationPlan -Plan $fixPlan -UseColor $useColor
        }
    } else {
        switch ($OutputFormat) {
            "Console" {
                if (-not $Quiet) {
                    $consoleResults = Select-ConsoleDiagnosticResults -Results $reportResults -Detailed:$Detailed
                    Write-ConsoleReport -Results $consoleResults -AllResults $results -DriveLetters $normalizedDriveLetters -Detailed:$Detailed -UseColor $useColor
                }
            }
            "Json" {
                if (-not $OutputPath) {
                    $OutputPath = Get-DefaultReportPath -Format $OutputFormat
                }
                $OutputPath = Resolve-ReportPath -Path $OutputPath -Format $OutputFormat

                Export-JsonReport -Results $reportResults -Path $OutputPath
                if (-not $Quiet) {
                    Write-ConsoleLine -Message "JSON report written to $OutputPath" -ForegroundColor Cyan -UseColor $useColor
                }
            }
            "Html" {
                if (-not $OutputPath) {
                    $OutputPath = Get-DefaultReportPath -Format $OutputFormat
                }
                $OutputPath = Resolve-ReportPath -Path $OutputPath -Format $OutputFormat

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
    }

    $exitCode = Get-DiagnosticsExitCode -Results $results
    if (-not $NoExitCode -and $ExitProcess) {
        exit $exitCode
    }

    if (-not $NoExitCode -and -not $ExitProcess) {
        $global:LASTEXITCODE = $exitCode
    }
}

