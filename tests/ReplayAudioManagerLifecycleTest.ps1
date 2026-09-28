param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'obj\instant-replay-audio\bin\BoltSnip.exe'),
    [string]$Ffmpeg = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\ffmpeg.exe'),
    [string]$EvidenceDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) '.tools\instant-replay-audio-evidence'),
    [int]$Cycles = 3
)

$ErrorActionPreference = 'Stop'
foreach ($path in @($Executable, $Ffmpeg)) {
    if (-not [IO.File]::Exists($path)) { throw "Required file was not found: $path" }
}

$runDirectory = Join-Path $EvidenceDirectory ('ManagerLifecycle-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($runDirectory) | Out-Null
$oldFfmpegPath = [Environment]::GetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', 'Process')
$oldDiagnosticPath = [Environment]::GetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', 'Process')
$diagnosticPath = Join-Path $runDirectory 'diagnostic.log'
[Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $Ffmpeg, 'Process')
[Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $diagnosticPath, 'Process')

$manager = $null
$results = @()
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$managerType = $assembly.GetType('BoltSnip.ReplayManager', $true)
$flags = [Reflection.BindingFlags]'Instance,Static,NonPublic'
$start = $managerType.GetMethod('Start', $flags)
$stop = $managerType.GetMethod('Stop', $flags)
$dispose = $managerType.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
$state = $managerType.GetProperty('State', $flags)
$audioState = $managerType.GetProperty('AudioState', $flags)
$lastError = $managerType.GetProperty('LastError', $flags)
$bufferedSegments = $managerType.GetProperty('BufferedSegmentCount', $flags)
$cacheRoot = Join-Path ([IO.Path]::GetTempPath()) 'BoltSnip\replay-cache'
$baselineCacheDirectories = if ([IO.Directory]::Exists($cacheRoot)) { @([IO.Directory]::GetDirectories($cacheRoot)) } else { @() }

try {
    $manager = [Activator]::CreateInstance($managerType, $true)
    for ($round = 1; $round -le $Cycles; $round++) {
        $ffmpegBefore = @(Get-Process -Name ffmpeg -ErrorAction SilentlyContinue | ForEach-Object Id)
        [void]$start.Invoke($manager, $null)
        $startupDeadline = [DateTime]::UtcNow.AddSeconds(20)
        while ([DateTime]::UtcNow -lt $startupDeadline -and $state.GetValue($manager, $null).ToString() -notin @('Recording', 'Error')) {
            Start-Sleep -Milliseconds 50
        }
        if ($state.GetValue($manager, $null).ToString() -ne 'Recording') {
            throw "Manager failed to record in round $round : $([string]$lastError.GetValue($manager, $null))"
        }

        $segmentDeadline = [DateTime]::UtcNow.AddSeconds(20)
        while ([DateTime]::UtcNow -lt $segmentDeadline -and [int]$bufferedSegments.GetValue($manager, $null) -lt 1) {
            Start-Sleep -Milliseconds 50
        }
        $segmentCountAtStop = [int]$bufferedSegments.GetValue($manager, $null)
        if ($segmentCountAtStop -lt 1) { throw "No encoded segment was buffered in round $round." }
        $audioStateAtStop = $audioState.GetValue($manager, $null).ToString()
        if ($audioStateAtStop -ne 'Active') { throw "WASAPI was not active in round $round (state=$audioStateAtStop)." }
        $ffmpegDuring = @(Get-Process -Name ffmpeg -ErrorAction SilentlyContinue | ForEach-Object Id)

        [void]$stop.Invoke($manager, $null)
        $stopDeadline = [DateTime]::UtcNow.AddSeconds(15)
        while ([DateTime]::UtcNow -lt $stopDeadline -and $state.GetValue($manager, $null).ToString() -ne 'Disabled') {
            Start-Sleep -Milliseconds 50
        }
        if ($state.GetValue($manager, $null).ToString() -ne 'Disabled') { throw "Manager did not disable in round $round." }
        Start-Sleep -Milliseconds 150

        $ffmpegAfter = @(Get-Process -Name ffmpeg -ErrorAction SilentlyContinue | ForEach-Object Id)
        $spawnedFfmpeg = @($ffmpegDuring | Where-Object { $_ -notin $ffmpegBefore })
        $leftoverFfmpeg = @($spawnedFfmpeg | Where-Object { $_ -in $ffmpegAfter })
        $currentCacheDirectories = if ([IO.Directory]::Exists($cacheRoot)) { @([IO.Directory]::GetDirectories($cacheRoot)) } else { @() }
        $leftoverCache = @($currentCacheDirectories | Where-Object { $_ -notin $baselineCacheDirectories })
        $audioStateAfterStop = $audioState.GetValue($manager, $null).ToString()
        $results += [pscustomobject]@{
            Round = $round
            ManagerStateAfterStop = $state.GetValue($manager, $null).ToString()
            AudioStateDuringCapture = $audioStateAtStop
            AudioStateAfterStop = $audioStateAfterStop
            BufferedSegmentsBeforeStop = $segmentCountAtStop
            SpawnedFfmpegCount = $spawnedFfmpeg.Count
            LeftoverFfmpegCount = $leftoverFfmpeg.Count
            LeftoverCacheCount = $leftoverCache.Count
            Passed = $spawnedFfmpeg.Count -eq 1 -and $leftoverFfmpeg.Count -eq 0 -and $leftoverCache.Count -eq 0 -and $audioStateAfterStop -eq 'Disabled'
        }
    }
}
catch {
    $_ | Format-List * -Force | Out-String | Set-Content -LiteralPath (Join-Path $runDirectory 'failure.txt') -Encoding UTF8
    throw
}
finally {
    if ($null -ne $manager) {
        try { [void]$stop.Invoke($manager, $null) } catch { }
        try { [void]$dispose.Invoke($manager, $null) } catch { }
    }
    if ($oldFfmpegPath) { [Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $oldFfmpegPath, 'Process') }
    else { [Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $null, 'Process') }
    if ($oldDiagnosticPath) { [Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $oldDiagnosticPath, 'Process') }
    else { [Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $null, 'Process') }
}

$report = [pscustomobject]@{ Rounds = $results; Passed = $results.Count -eq $Cycles -and @($results | Where-Object { -not $_.Passed }).Count -eq 0; DiagnosticLog = $diagnosticPath }
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runDirectory 'result.json') -Encoding UTF8
$report | Format-List
if (-not $report.Passed) { exit 1 }
