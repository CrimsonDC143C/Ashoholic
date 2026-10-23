# AshoholicSync.ps1
# Auto-detects the WoW/Ebonhold install from the script's own location.
# Expected to live in:  <InstallRoot>\Interface\AddOns\Ashoholic\

$ErrorActionPreference = "Stop"
$configPath = Join-Path $PSScriptRoot "sync_config.txt"

function Get-WowRootFromScript {
    try {
        $p = (Resolve-Path $PSScriptRoot).Path
        # Try 3 levels up first (standard WoW layout), then 4 (extra-nested installs)
        foreach ($levels in @("..\..\..", "..\..\..\..")) {
            try {
                $up = (Resolve-Path (Join-Path $p $levels)).Path
                if (Test-Path (Join-Path $up "Interface")) { return $up }
            } catch {}
        }
    } catch {}
    return $null
}

function Get-WowRootFromConfig {
    if (Test-Path $configPath) {
        $r = (Get-Content $configPath -Raw).Trim()
        if ($r -and (Test-Path (Join-Path $r "Interface"))) { return $r }
    }
    return $null
}

function Save-WowRoot($root) {
    Set-Content -Path $configPath -Value $root -Encoding UTF8
}

$wowRoot = Get-WowRootFromScript
if (-not $wowRoot) { $wowRoot = Get-WowRootFromConfig }

if (-not $wowRoot) {
    Write-Host ""
    Write-Host "Could not auto-detect the WoW/Ebonhold install folder."
    Write-Host "This script normally lives at <InstallRoot>\Interface\AddOns\Ashoholic\."
    Write-Host ""
    Write-Host "Please paste the FULL path to the folder that contains 'Interface'\ (usually the one with Wow.exe):"
    $input_ = Read-Host ">"
    if (-not $input_ -or -not (Test-Path (Join-Path $input_ "Interface"))) {
        Write-Host "That folder does not contain an 'Interface' subfolder. Aborting."
        Read-Host "Press Enter to exit"; exit 1
    }
    $wowRoot = (Resolve-Path $input_).Path
    Save-WowRoot $wowRoot
    Write-Host "Saved to $configPath - you won't be asked again."
}

$WtfRoot = Join-Path $wowRoot "WTF"

function Find-ClientExe($root) {
    $candidates = @("Wow.exe","wow.exe","Wow-64.exe","WowClassic.exe",
                    "Ebonhold.exe","ebonhold.exe","Ebonhold-64.exe")
    foreach ($c in $candidates) {
        $p = Join-Path $root $c
        if (Test-Path $p) { return $p }
    }
    # Fallback: biggest .exe in the root (the client is by far the largest)
    $exe = Get-ChildItem -Path $root -Filter *.exe -File -ErrorAction SilentlyContinue |
           Sort-Object Length -Descending | Select-Object -First 1
    if ($exe) { return $exe.FullName }
    return $null
}

$WowExe = Find-ClientExe $wowRoot
if (-not $WowExe) {
    Write-Host "Could not find a client .exe in $wowRoot"
    Read-Host "Press Enter to exit"; exit 1
}

$exeName = [System.IO.Path]::GetFileNameWithoutExtension($WowExe)
$wowRunning = $null -ne (Get-Process -Name $exeName -ErrorAction SilentlyContinue)

if ($wowRunning) {
    # Merge is unsafe while WoW holds the DB in memory (it overwrites the
    # file on logout). But the merge has already been done at least once
    # this session - just launch another instance.
    Write-Host "$exeName already running - skipping merge, launching additional instance."
    Start-Process -FilePath $WowExe
    exit 0
}

$MergePs1 = Join-Path $PSScriptRoot "AshoholicMerge.ps1"
if (-not (Test-Path $MergePs1)) {
    Write-Host "AshoholicMerge.ps1 not found next to this script."
    Read-Host "Press Enter to exit"; exit 1
}

$files = Get-ChildItem -Path (Join-Path $WtfRoot "Account") -Recurse -Filter "Ashoholic.lua" -ErrorAction SilentlyContinue

if ($files.Count -ge 2) {
    Write-Host "Merging $($files.Count) account(s)..."
    $paths = @($files | ForEach-Object { $_.FullName })
    & $MergePs1 @paths
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Merge failed. WoW will still launch, but accounts may not be synced."
    }
} else {
    Write-Host "Only $($files.Count) Ashoholic.lua found; no merge needed yet."
}

Write-Host "Launching $WowExe..."
Start-Process -FilePath $WowExe