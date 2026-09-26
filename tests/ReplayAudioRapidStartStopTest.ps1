param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe'),
    [string]$Ffmpeg = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\ffmpeg.exe')
)

$ErrorActionPreference = 'Stop'
foreach ($path in @($Executable, $Ffmpeg)) {
    if (-not [IO.File]::Exists($path)) { throw "Required file was not found: $path" }
}

$oldFfmpegPath = [Environment]::GetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', 'Process')
[Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $Ffmpeg, 'Process')
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$managerType = $assembly.GetType('BoltSnip.ReplayManager', $true)
$flags = [Reflection.BindingFlags]'Instance,Static,NonPublic'
$manager = [Activator]::CreateInstance($managerType, $true)
$start = $managerType.GetMethod('Start', $flags)
$stop = $managerType.GetMethod('Stop', $flags)
$dispose = $managerType.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
$state = $managerType.GetProperty('State', $flags)
$audioState = $managerType.GetProperty('AudioState', $flags)
$lastError = $managerType.GetProperty('LastError', $flags)
$results = @()
$cacheRoot = Join-Path ([IO.Path]::GetTempPath()) 'BoltSnip\replay-cache'
$baselineCache = if ([IO.Directory]::Exists($cacheRoot)) { @([IO.Directory]::GetDirectories($cacheRoot)) } else { @() }

try {
    for ($round = 1; $round -le 3; $round++) {
        $ffmpegBefore = @(Get-Process -Name ffmpeg -ErrorAction SilentlyContinue | ForEach-Object Id)
        $watch = [Diagnostics.Stopwatch]::StartNew()
        [void]$start.Invoke($manager, $null)
        [void]$stop.Invoke($manager, $null)
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        while ([DateTime]::UtcNow -lt $deadline -and $state.GetValue($manager, $null).ToString() -notin @('Disabled', 'Error')) {
            Start-Sleep -Milliseconds 25
        }
        $watch.Stop()
        $stateAfterStop = $state.GetValue($manager, $null).ToString()
        $audioAfterStop = $audioState.GetValue($manager, $null).ToString()
        Start-Sleep -Milliseconds 100
        $ffmpegAfter = @(Get-Process -Name ffmpeg -ErrorAction SilentlyContinue | ForEach-Object Id)
        $newFfmpeg = @($ffmpegAfter | Where-Object { $_ -notin $ffmpegBefore })
        $cacheNow = if ([IO.Directory]::Exists($cacheRoot)) { @([IO.Directory]::GetDirectories($cacheRoot)) } else { @() }
        $newCache = @($cacheNow | Where-Object { $_ -notin $baselineCache })
        $passed = $stateAfterStop -eq 'Disabled' -and $audioAfterStop -eq 'Disabled' -and
            $watch.Elapsed.TotalSeconds -lt 5 -and $newFfmpeg.Count -eq 0 -and $newCache.Count -eq 0
        $results += [pscustomobject]@{
            Round = $round
            StateAfterStop = $stateAfterStop
            AudioStateAfterStop = $audioAfterStop
            ElapsedMs = [Math]::Round($watch.Elapsed.TotalMilliseconds)
            NewFfmpegProcesses = $newFfmpeg.Count
            NewCacheDirectories = $newCache.Count
            LastError = $lastError.GetValue($manager, $null)
            Passed = $passed
        }
        if ($stateAfterStop -ne 'Disabled') { break }
    }
}
finally {
    try { [void]$stop.Invoke($manager, $null) } catch { }
    try { [void]$dispose.Invoke($manager, $null) } catch { }
    if ($oldFfmpegPath) { [Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $oldFfmpegPath, 'Process') }
    else { [Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $null, 'Process') }
}

$results | Format-List
if ($results.Count -ne 3 -or @($results | Where-Object { -not $_.Passed }).Count -gt 0) { exit 1 }
