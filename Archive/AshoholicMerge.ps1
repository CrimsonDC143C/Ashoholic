# AshoholicMerge.ps1
# Pure PowerShell merger - no Python, no lupa, nothing to install.
# Usage: AshoholicMerge.ps1 file1.lua file2.lua [...]

param([Parameter(ValueFromRemainingArguments=$true)]$Files)

function Get-BraceMatch {
    param([string]$Text, [int]$OpenPos)
    $depth = 1
    $i = $OpenPos + 1
    while ($i -lt $Text.Length -and $depth -gt 0) {
        $c = $Text[$i]
        if ($c -eq '"') {
            $i++
            while ($i -lt $Text.Length -and $Text[$i] -ne '"') {
                if ($Text[$i] -eq '\') { $i++ }
                $i++
            }
        } elseif ($c -eq '{') { $depth++ }
        elseif ($c -eq '}')   { $depth-- }
        $i++
    }
    return $i - 1
}

function Get-CharactersBlock {
    param([string]$Text)
    $m = [regex]::Match($Text, '\["Characters"\]\s*=\s*\{')
    if (-not $m.Success) { return $null }
    $openPos = $Text.IndexOf('{', $m.Index)
    $closePos = Get-BraceMatch -Text $Text -OpenPos $openPos
    return @{
        Open  = $openPos
        Close = $closePos
        Body  = $Text.Substring($openPos + 1, $closePos - $openPos - 1)
    }
}

function Get-CharacterEntries {
    param([string]$Body)
    $entries = @{}
    $i = 0
    $len = $Body.Length
    while ($i -lt $len) {
        $tail = $Body.Substring($i)
        $m = [regex]::Match($tail, '^\s*\["((?:[^"\\]|\\.)*)"\]\s*=\s*\{')
        if ($m.Success) {
            $key = $m.Groups[1].Value
            $openPos = $i + $m.Index + $m.Length - 1
            $closePos = Get-BraceMatch -Text $Body -OpenPos $openPos
            $entries[$key] = $Body.Substring($openPos, $closePos - $openPos + 1)
            $i = $closePos + 1
        } else {
            $i++
        }
    }
    return $entries
}

function Get-CharStat {
    param([string]$Body, [string]$Field)
    $m = [regex]::Match($Body, '\["' + [regex]::Escape($Field) + '"\]\s*=\s*(\d+)')
    if ($m.Success) { return [int64]$m.Groups[1].Value }
    return [int64]0
}

function Get-CharScore {
    param([string]$Body)
    return (Get-CharStat -Body $Body -Field "lastSeen") * 1000000000 +
           (Get-CharStat -Body $Body -Field "level")    * 10000000 +
           (Get-CharStat -Body $Body -Field "money")    * 100 +
           (Get-CharStat -Body $Body -Field "SoulAsh")
}

if (-not $Files -or $Files.Count -lt 2) {
    Write-Host "Usage: AshoholicMerge.ps1 file1.lua file2.lua [...]"
    exit 1
}

$sources = @()
foreach ($f in $Files) {
    if (-not (Test-Path $f)) {
        Write-Host "ERROR: missing $f"
        exit 2
    }
    $text = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
    $block = Get-CharactersBlock -Text $text
    if (-not $block) {
        Write-Host "ERROR: no Characters block in $f"
        exit 2
    }
    $entries = Get-CharacterEntries -Body $block.Body
    $sources += @{
        Path    = $f
        Text    = $text
        Block   = $block
        Entries = $entries
    }
}

$merged = @{}
foreach ($src in $sources) {
    foreach ($key in $src.Entries.Keys) {
        $body = $src.Entries[$key]
        if (-not $merged.ContainsKey($key)) {
            $merged[$key] = $body
        } else {
            if ((Get-CharScore -Body $body) -gt (Get-CharScore -Body $merged[$key])) {
                $merged[$key] = $body
            }
        }
    }
}

Write-Host "Merged $($sources.Count) files into $($merged.Count) characters"

$newBody = "`r`n"
foreach ($key in ($merged.Keys | Sort-Object)) {
    $escaped = $key -replace '\\', '\\' -replace '"', '\"'
    $newBody += "        [`"$escaped`"] = $($merged[$key]),`r`n"
}
$newBody += "    "

foreach ($src in $sources) {
    $block = $src.Block
    $newText = $src.Text.Substring(0, $block.Open + 1) + $newBody + $src.Text.Substring($block.Close)
    $backup = $src.Path + ".bak"
    if (-not (Test-Path $backup)) {
        Copy-Item -Path $src.Path -Destination $backup
    }
    [System.IO.File]::WriteAllText($src.Path, $newText, [System.Text.Encoding]::UTF8)
    Write-Host "  wrote $($src.Path)"
}