# Enterprise Reporting

Use SCCM only to run BitDiag on endpoints. Let BitDiag write Power BI-friendly NDJSON files to a central SMB share:

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
