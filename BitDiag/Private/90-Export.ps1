# BitDiag internal source: 90-Export.ps1

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

