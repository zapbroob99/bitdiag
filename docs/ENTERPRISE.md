# Enterprise Reporting

Use SCCM only to run BitDiag on endpoints. Let BitDiag write Power BI-friendly NDJSON files to a central SMB share.

For SCCM, build the isolated reporting script:

```powershell
.\build-sccm.ps1
```

The generated SCCM artifact is:

```text
dist\bitdiag-sccm-report.ps1
```

Deploy that file with this SCCM command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\bitdiag-sccm-report.ps1 -OutDirectory "\\server\share\BitDiag" -Quiet
```

The SCCM script only runs diagnostics and writes the enterprise report. It does not expose the interactive menu, automatic remediation, or BitLocker enablement.

The full CLI can also write the same report when needed:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\bitdiag.ps1 -Run -EnterpriseReport -OutDirectory "\\server\share\BitDiag" -Quiet -NoExitCode
```

Each output file is named with computer name, device GUID, and timestamp:

```text
<ComputerName>_<DeviceGuid>_<yyyyMMdd-HHmmss>.ndjson
```

Each line is one finding with stable columns for Power BI:

```text
RunId, TimestampUtc, ComputerName, Domain, DeviceGuid, UserContext,
BitDiagVersion, DriveLetter, Category, CheckName, Status, Message,
Fix, ReasonType, RiskLevel, CanApply, ExitCode
```

BitDiag writes to a local temp file, copies to a remote `.tmp` file, then renames to final `.ndjson`. This prevents Power BI from reading half-written files.

Enterprise export intentionally excludes raw `Details` values and does not export recovery passwords.
