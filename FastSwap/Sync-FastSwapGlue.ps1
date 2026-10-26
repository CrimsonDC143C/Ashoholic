param(
    [string]$GameRoot = "D:\Games\Ebonhold",
    [switch]$Force,
    [switch]$Watch,
    [switch]$InstallTask,
    [switch]$UninstallTask
)

$ErrorActionPreference = "Stop"
$TaskName = "Ebonhold_FastSwap_GlueSync"
$DllPath  = Join-Path $GameRoot "ebonhold.dll"
$GlueOut  = Join-Path $GameRoot "ebonhold_glue.lua"
$HookPath = Join-Path $GameRoot "Interface\AddOns\FastSwap\FastSwap_Glue.lua"

function Sync-FastSwapGlue {
    param([switch]$ForceSync)

    if (-not (Test-Path $DllPath)) {
        Write-Warning "ebonhold.dll not found at $DllPath"
        return $false
    }
    if (-not (Test-Path $HookPath)) {
        Write-Warning "FastSwap_Glue.lua not found at $HookPath"
        return $false
    }

    $dllHash  = (Get-FileHash -Path $DllPath -Algorithm SHA256).Hash
    $hookHash = (Get-FileHash -Path $HookPath -Algorithm SHA256).Hash
    $stamp    = "-- @fastswap-sync-sha256: $dllHash`:$hookHash"

    if (-not $ForceSync -and (Test-Path $GlueOut)) {
        $firstLine = Get-Content -Path $GlueOut -TotalCount 1 -ErrorAction SilentlyContinue
        if ($firstLine -eq $stamp) {
            Write-Host "[FastSwap] ebonhold_glue.lua is already up to date with ebonhold.dll ($($dllHash.Substring(0, 12))...)."
            return $false
        }
    }

    $bytes = [System.IO.File]::ReadAllBytes($DllPath)
    $text  = [System.Text.Encoding]::UTF8.GetString($bytes)
    $marker = "-- ebonhold_glue.lua"
    $start = $text.IndexOf($marker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) {
        throw "Could not locate embedded '$marker' header inside $DllPath"
    }
    $end = $text.IndexOf("`0", $start)
    if ($end -lt 0) {
        throw "Could not locate null terminator for embedded glue script inside $DllPath"
    }

    $embeddedGlue = $text.Substring($start, $end - $start).TrimEnd()
    $hookGlue     = [System.IO.File]::ReadAllText($HookPath, [System.Text.Encoding]::UTF8).Trim()

    $combined = "$stamp`r`n$embeddedGlue`r`n`r`n$hookGlue`r`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($GlueOut, $combined, $utf8NoBom)

    Write-Host "[FastSwap] Synced ebonhold_glue.lua from ebonhold.dll ($($embeddedGlue.Length) bytes embedded + $($hookGlue.Length) bytes FastSwap hook)."
    return $true
}

if ($UninstallTask) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "[FastSwap] Removed scheduled task '$TaskName'."
    return
}

if ($InstallTask) {
    $scriptPath = $MyInvocation.MyCommand.Path
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" -GameRoot `"$GameRoot`" -Watch"
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description "Automatically syncs ebonhold_glue.lua with FastSwap whenever Project Ebonhold updates ebonhold.dll" -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "[FastSwap] Installed and started background watcher task '$TaskName'."
    return
}

Sync-FastSwapGlue -ForceSync:$Force | Out-Null

if ($Watch) {
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $GameRoot
    $watcher.Filter = "ebonhold.dll"
    $watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::Size
    $watcher.EnableRaisingEvents = $true

    Write-Host "[FastSwap] Watching $DllPath for updates..."
    while ($true) {
        $result = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::Changed -bor [System.IO.WatcherChangeTypes]::Created -bor [System.IO.WatcherChangeTypes]::Renamed, 30000)
        if (-not $result.TimedOut) {
            Start-Sleep -Milliseconds 500
            try {
                Sync-FastSwapGlue | Out-Null
            } catch {
                Write-Warning "[FastSwap] Sync retry after error: $_"
            }
        }
    }
}
