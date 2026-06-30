let
    SourceFolder = "C:\Users\enesadisen\Projects\bitlocker-troubleshooter\tmp-powerbi-report",
    Source = Folder.Files(SourceFolder),
    NdjsonFiles = Table.SelectRows(Source, each [Extension] = ".ndjson"),
    SourceMetadata = Table.SelectColumns(NdjsonFiles, {"Name", "Content", "Date modified"}),
    Lines = Table.AddColumn(SourceMetadata, "Lines", each Lines.FromBinary([Content], null, null, 65001)),
    ExpandedLines = Table.ExpandListColumn(Lines, "Lines"),
    NonBlankLines = Table.SelectRows(ExpandedLines, each Text.Trim([Lines]) <> ""),
    JsonRecords = Table.AddColumn(NonBlankLines, "Record", each Json.Document([Lines])),
    ExpandedRecords = Table.ExpandRecordColumn(
        JsonRecords,
        "Record",
        {
            "RunId",
            "TimestampUtc",
            "ComputerName",
            "Domain",
            "DeviceGuid",
            "UserContext",
            "BitDiagVersion",
            "DriveLetter",
            "Category",
            "CheckName",
            "Status",
            "Message",
            "Fix",
            "ReasonType",
            "RiskLevel",
            "CanApply",
            "ExitCode"
        },
        {
            "RunId",
            "TimestampUtc",
            "ComputerName",
            "Domain",
            "DeviceGuid",
            "UserContext",
            "BitDiagVersion",
            "DriveLetter",
            "Category",
            "CheckName",
            "Status",
            "Message",
            "Fix",
            "ReasonType",
            "RiskLevel",
            "CanApply",
            "ExitCode"
        }
    ),
    WithSourceModifiedUtc = Table.RenameColumns(ExpandedRecords, {{"Date modified", "SourceModifiedUtc"}}),
    WithTypedBaseColumns = Table.TransformColumnTypes(
        WithSourceModifiedUtc,
        {
            {"SourceModifiedUtc", type datetimezone},
            {"TimestampUtc", type datetimezone},
            {"CanApply", type logical},
            {"ExitCode", Int64.Type}
        }
    ),
    LatestRunByDevice = Table.Group(
        WithTypedBaseColumns,
        {"DeviceGuid"},
        {{"LatestTimestampUtc", each List.Max([TimestampUtc]), type datetimezone}}
    ),
    WithLatestTimestamp = Table.NestedJoin(
        WithTypedBaseColumns,
        {"DeviceGuid"},
        LatestRunByDevice,
        {"DeviceGuid"},
        "Latest",
        JoinKind.LeftOuter
    ),
    ExpandedLatestTimestamp = Table.ExpandTableColumn(WithLatestTimestamp, "Latest", {"LatestTimestampUtc"}, {"LatestTimestampUtc"}),
    WithLatestFlag = Table.AddColumn(ExpandedLatestTimestamp, "IsLatestDeviceRun", each [TimestampUtc] = [LatestTimestampUtc], type logical),
    LatestRowsOnly = Table.SelectRows(WithLatestFlag, each [IsLatestDeviceRun] = true),
    DeviceBitLockerSummary = Table.Group(
        LatestRowsOnly,
        {"DeviceGuid"},
        {
            {
                "DeviceBitLockerState",
                each
                    let
                        encryptionRows = Table.SelectRows(_, each [Category] = "BitLocker" and Text.EndsWith(Text.From([CheckName]), ": encryption")),
                        bitLockerRows = Table.SelectRows(_, each [Category] = "BitLocker"),
                        hasEncryptionRows = Table.RowCount(encryptionRows) > 0,
                        hasMissingDrive = Table.RowCount(Table.SelectRows(encryptionRows, each [ReasonType] = "EncryptionOff" or Text.Contains(Text.Lower(Text.From([Message])), "not encrypted") or Text.Contains(Text.Lower(Text.From([Message])), "method is none"))) > 0,
                        hasReadError = Table.RowCount(Table.SelectRows(bitLockerRows, each [Status] = "Error")) > 0
                    in
                        if hasMissingDrive then "BitLocker missing on at least one drive"
                        else if (not hasEncryptionRows) or hasReadError then "BitLocker status unknown"
                        else "BitLocker enabled on reported drives",
                type text
            },
            {
                "IsDeviceBitLockerMissing",
                each
                    let
                        encryptionRows = Table.SelectRows(_, each [Category] = "BitLocker" and Text.EndsWith(Text.From([CheckName]), ": encryption")),
                        missingRows = Table.SelectRows(encryptionRows, each [ReasonType] = "EncryptionOff" or Text.Contains(Text.Lower(Text.From([Message])), "not encrypted") or Text.Contains(Text.Lower(Text.From([Message])), "method is none"))
                    in
                        Table.RowCount(missingRows) > 0,
                type logical
            },
            {
                "BitLockerMissingDriveCount",
                each
                    let
                        encryptionRows = Table.SelectRows(_, each [Category] = "BitLocker" and Text.EndsWith(Text.From([CheckName]), ": encryption")),
                        missingRows = Table.SelectRows(encryptionRows, each [ReasonType] = "EncryptionOff" or Text.Contains(Text.Lower(Text.From([Message])), "not encrypted") or Text.Contains(Text.Lower(Text.From([Message])), "method is none")),
                        missingDrives = List.Distinct(Table.Column(missingRows, "DriveLetter"))
                    in
                        List.Count(missingDrives),
                Int64.Type
            }
        }
    ),
    WithDeviceBitLockerSummary = Table.NestedJoin(
        WithLatestFlag,
        {"DeviceGuid"},
        DeviceBitLockerSummary,
        {"DeviceGuid"},
        "DeviceBitLocker",
        JoinKind.LeftOuter
    ),
    ExpandedDeviceBitLockerSummary = Table.ExpandTableColumn(
        WithDeviceBitLockerSummary,
        "DeviceBitLocker",
        {"DeviceBitLockerState", "IsDeviceBitLockerMissing", "BitLockerMissingDriveCount"},
        {"DeviceBitLockerState", "IsDeviceBitLockerMissing", "BitLockerMissingDriveCount"}
    ),
    SelectedColumns = Table.SelectColumns(
        ExpandedDeviceBitLockerSummary,
        {
            "Name",
            "SourceModifiedUtc",
            "RunId",
            "TimestampUtc",
            "IsLatestDeviceRun",
            "DeviceBitLockerState",
            "IsDeviceBitLockerMissing",
            "BitLockerMissingDriveCount",
            "ComputerName",
            "Domain",
            "DeviceGuid",
            "UserContext",
            "BitDiagVersion",
            "DriveLetter",
            "Category",
            "CheckName",
            "Status",
            "Message",
            "Fix",
            "ReasonType",
            "RiskLevel",
            "CanApply",
            "ExitCode"
        }
    ),
    TypedColumns = Table.TransformColumnTypes(
        SelectedColumns,
        {
            {"Name", type text},
            {"SourceModifiedUtc", type datetimezone},
            {"RunId", type text},
            {"TimestampUtc", type datetimezone},
            {"IsLatestDeviceRun", type logical},
            {"DeviceBitLockerState", type text},
            {"IsDeviceBitLockerMissing", type logical},
            {"BitLockerMissingDriveCount", Int64.Type},
            {"ComputerName", type text},
            {"Domain", type text},
            {"DeviceGuid", type text},
            {"UserContext", type text},
            {"BitDiagVersion", type text},
            {"DriveLetter", type text},
            {"Category", type text},
            {"CheckName", type text},
            {"Status", type text},
            {"Message", type text},
            {"Fix", type text},
            {"ReasonType", type text},
            {"RiskLevel", type text},
            {"CanApply", type logical},
            {"ExitCode", Int64.Type}
        }
    )
in
    TypedColumns
