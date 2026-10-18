# Counts "GET_ALL fail" lines per hour in today's (or a given) MSI Center PSU log. No admin rights needed.
param(
    [string]$MsiCenterDir = (Join-Path ${env:ProgramFiles(x86)} 'MSI\MSI Center'),
    [datetime]$Date = (Get-Date)
)
$log = Join-Path $MsiCenterDir "Log\Power Supply Unit\Library_$($Date.ToString('MM_dd_yyyy')).log"
if (-not (Test-Path -LiteralPath $log)) { "Log not found: $log"; exit 1 }
$fails = Select-String -LiteralPath $log -Pattern 'Read data of PSU GET_ALL fail' -SimpleMatch
"$log"
"GET_ALL fail lines: $($fails.Count)"
$fails | ForEach-Object { $_.Line.Substring(11, 2) } | Group-Object | Sort-Object Name |
    ForEach-Object { '  {0}:00  {1}' -f $_.Name, $_.Count }
