# Regenerates modules/collections/Data/appearances_data.lua from world.item_template.
#
#   .\gen_appearances.ps1                       # localhost / root / root / world
#   .\gen_appearances.ps1 -DbHost 10.0.0.5 -User trinity -Password secret
#
# The query lives in collections.sql next to this script; edit it there, not here.

param(
    [string] $DbHost   = "127.0.0.1",
    [int]    $Port     = 3306,
    [string] $User     = "root",
    [string] $Password = "root",
    [string] $Database = "world",
    [string] $MysqlExe = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
)

$ErrorActionPreference = "Stop"

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$sqlFile = Join-Path $here "collections.sql"
$outFile = Join-Path $here "..\Data\appearances_data.lua"

if (-not (Test-Path $MysqlExe)) { throw "mysql.exe not found at $MysqlExe (pass -MysqlExe)" }

# -N -B: no column headers, tab separated.
$rows = & $MysqlExe "-h$DbHost" "-P$Port" "-u$User" "-p$Password" $Database "-N" "-B" "-e" (Get-Content $sqlFile -Raw) |
        Where-Object { $_ -notmatch '^mysql: \[Warning\]' -and $_.Trim() -ne "" }

if ($rows.Count -eq 0) { throw "query returned no rows" }

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("-- GENERATED from world.item_template. Regenerate via modules/collections/server/collections.sql (see gen_appearances.ps1).")
[void]$sb.AppendLine("-- Flat rows of 6: itemID, displayID, quality, itemClass, itemSubClass, invType. Folded by data/appearances.lua.")
[void]$sb.AppendLine("Ebonhold = Ebonhold or {}")
[void]$sb.AppendLine("Ebonhold.AppearanceFlat = {")

# 16 items per line, one item = 6 numbers.
$line = New-Object System.Text.StringBuilder
$onLine = 0
foreach ($row in $rows) {
    [void]$line.Append((($row -split "`t") -join ",")).Append(",")
    $onLine++
    if ($onLine -eq 16) {
        [void]$sb.AppendLine($line.ToString())
        [void]$line.Clear()
        $onLine = 0
    }
}
if ($onLine -gt 0) { [void]$sb.AppendLine($line.ToString()) }
[void]$sb.AppendLine("}")

[System.IO.File]::WriteAllText((Resolve-Path $outFile), $sb.ToString())
Write-Host "wrote $($rows.Count) appearances to $outFile"
