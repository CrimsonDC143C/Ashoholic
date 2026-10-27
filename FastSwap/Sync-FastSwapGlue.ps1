param(
    [string]$GameRoot = "D:\Games\Ebonhold",
    [switch]$Force,
    [switch]$Watch,
    [switch]$LaunchGame,
    [switch]$InstallTask,
    [switch]$UninstallTask
)

$ErrorActionPreference = "Stop"
$TaskName = "Ebonhold_FastSwap_GlueSync"
$DllPath  = Join-Path $GameRoot "ebonhold.dll"
$GlueOut  = Join-Path $GameRoot "ebonhold_glue.lua"
$HookPath = Join-Path $GameRoot "Interface\AddOns\FastSwap\FastSwap_Glue.lua"
$ScriptPath = $PSCommandPath
$LauncherPath = Join-Path $env:LOCALAPPDATA "ebonhold\ebonhold.exe"
$ShortcutPaths = @(
    (Join-Path ([Environment]::GetFolderPath("Desktop")) "ebonhold.lnk"),
    (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ebonhold.lnk")
)

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

function Set-EbonholdShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$LinkPath,
        [Parameter(Mandatory = $true)][bool]$LaunchWithWatcher
    )

    $parent = Split-Path $LinkPath -Parent
    if (-not (Test-Path $parent)) {
        return
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($LinkPath)
    if ($LaunchWithWatcher) {
        $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
        $shortcut.TargetPath = $powershell
        $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -GameRoot `"$GameRoot`" -LaunchGame"
        $shortcut.WorkingDirectory = $GameRoot
        $shortcut.Description = "Launch Ebonhold and watch ebonhold.dll for FastSwap glue updates"
    } else {
        $shortcut.TargetPath = $LauncherPath
        $shortcut.Arguments = ""
        $shortcut.WorkingDirectory = Split-Path $LauncherPath -Parent
        $shortcut.Description = ""
    }
    $shortcut.WindowStyle = 1
    if (Test-Path $LauncherPath) {
        $shortcut.IconLocation = "$LauncherPath,0"
    }
    $shortcut.Save()
}

function Test-EbonholdRunning {
    $launcher = Get-Process -Name "ebonhold" -ErrorAction SilentlyContinue
    if ($launcher) {
        return $true
    }

    $wow = Get-Process -Name "Wow" -ErrorAction SilentlyContinue
    foreach ($proc in $wow) {
        $path = $null
        try { $path = $proc.Path } catch { }
        if ($path -and $path.StartsWith($GameRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

if ($UninstallTask) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    foreach ($link in $ShortcutPaths) {
        if (Test-Path $link) {
            Set-EbonholdShortcut -LinkPath $link -LaunchWithWatcher $false
        }
    }
    Write-Host "[FastSwap] Removed scheduled task '$TaskName' and pointed Ebonhold shortcuts at the launcher."
    return
}

if ($InstallTask) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    foreach ($link in $ShortcutPaths) {
        Set-EbonholdShortcut -LinkPath $link -LaunchWithWatcher $true
    }
    Write-Host "[FastSwap] Ebonhold shortcuts now start the watcher with the game. It no longer runs at logon."
    return
}

if ($LaunchGame) {
    try {
        $host.UI.RawUI.WindowTitle = "Ebonhold FastSwap"
    } catch { }

    if (-not (Test-Path $LauncherPath)) {
        throw "Ebonhold launcher not found at $LauncherPath"
    }

    $createdMutex = $false
    $mutex = New-Object System.Threading.Mutex($false, "Local\EbonholdFastSwapLaunch")
    try {
        $createdMutex = $mutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $createdMutex = $true
    }

    if (-not $createdMutex) {
        Write-Host "[FastSwap] Watcher is already running. Launching Ebonhold."
        Start-Process -FilePath $LauncherPath -WorkingDirectory (Split-Path $LauncherPath -Parent) | Out-Null
        $mutex.Dispose()
        return
    }

    try {
        Sync-FastSwapGlue -ForceSync:$Force | Out-Null
        Write-Host "[FastSwap] Launching Ebonhold. This window closes when the game exits."
        Start-Process -FilePath $LauncherPath -WorkingDirectory (Split-Path $LauncherPath -Parent) | Out-Null

        $watcher = New-Object System.IO.FileSystemWatcher
        $watcher.Path = $GameRoot
        $watcher.Filter = "ebonhold.dll"
        $watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::Size
        $watcher.EnableRaisingEvents = $true

        Write-Host "[FastSwap] Watching $DllPath for updates..."
        $startedAt = Get-Date
        $seenRunning = $false
        $quietSince = $null
        try {
            while ($true) {
                $result = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::Changed -bor [System.IO.WatcherChangeTypes]::Created -bor [System.IO.WatcherChangeTypes]::Renamed, 2000)
                if (-not $result.TimedOut) {
                    Start-Sleep -Milliseconds 500
                    try {
                        Sync-FastSwapGlue | Out-Null
                    } catch {
                        Write-Warning "[FastSwap] Sync retry after error: $_"
                    }
                }

                if (Test-EbonholdRunning) {
                    $seenRunning = $true
                    $quietSince = $null
                } elseif (-not $seenRunning) {
                    if (((Get-Date) - $startedAt).TotalSeconds -ge 60) {
                        Write-Host "[FastSwap] Ebonhold did not stay running. Stopped watching."
                        break
                    }
                } else {
                    if (-not $quietSince) {
                        $quietSince = Get-Date
                    } elseif (((Get-Date) - $quietSince).TotalSeconds -ge 15) {
                        Write-Host "[FastSwap] Ebonhold closed. Stopped watching."
                        break
                    }
                }
            }
        } finally {
            $watcher.EnableRaisingEvents = $false
            $watcher.Dispose()
        }
    } catch {
        Write-Host "[FastSwap] $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Press Enter to close."
        [void](Read-Host)
    } finally {
        if ($createdMutex) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
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
