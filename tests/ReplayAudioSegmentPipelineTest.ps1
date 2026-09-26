param(
    [ValidateSet('Audio30', 'Silence', 'Long')]
    [string]$Mode = 'Audio30',
    [int]$DurationSeconds = 0,
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'obj\instant-replay-audio\bin\BoltSnip.exe'),
    [string]$Ffmpeg = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\ffmpeg.exe'),
    [string]$Ffprobe = (Join-Path (Split-Path $PSScriptRoot -Parent) '.tools\ffmpeg\ffprobe.exe'),
    [string]$EvidenceDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) '.tools\instant-replay-audio-evidence')
)

$ErrorActionPreference = 'Stop'
if ($DurationSeconds -le 0) { $DurationSeconds = if ($Mode -eq 'Long') { 320 } else { 36 } }
if ($Mode -eq 'Long' -and $DurationSeconds -lt 320) { throw 'Long mode must run for at least 320 seconds.' }
foreach ($path in @($Executable, $Ffmpeg, $Ffprobe)) {
    if (-not [IO.File]::Exists($path)) { throw "Required file was not found: $path" }
}

$runId = $Mode + '-synthetic-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$runDirectory = Join-Path $EvidenceDirectory $runId
[IO.Directory]::CreateDirectory($runDirectory) | Out-Null
$captureLimitSeconds = if ($Mode -eq 'Audio30') { [Math]::Min($DurationSeconds + 10, 46) } else { $DurationSeconds + 10 }
[IO.File]::WriteAllText(
    (Join-Path $runDirectory 'test-parameters.txt'),
    ('Mode={0}; RequestedDurationSeconds={1}; CaptureLimitSeconds={2}' -f $Mode, $DurationSeconds, $captureLimitSeconds),
    [Text.UTF8Encoding]::new($false))
$diagnosticPath = Join-Path $runDirectory 'diagnostic.log'
$previousFfmpegPath = [Environment]::GetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', 'Process')
$previousDiagnosticPath = [Environment]::GetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', 'Process')
[Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $Ffmpeg, 'Process')
[Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $diagnosticPath, 'Process')

function Invoke-Process([string]$Path, [string]$Arguments, [switch]$ReadOutput) {
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Path
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.RedirectStandardOutput = [bool]$ReadOutput
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw "Could not start $Path" }
    $output = if ($ReadOutput) { $process.StandardOutput.ReadToEnd() } else { '' }
    $errorText = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $result = [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output; Error = $errorText }
    $process.Dispose()
    return $result
}

function New-BeepWave([string]$Path) {
    $sampleRate = 48000
    $sampleCount = $sampleRate * 2
    $writer = New-Object IO.BinaryWriter([IO.File]::Create($Path))
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
        $writer.Write([int]($sampleCount * 2 + 36))
        $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
        $writer.Write([int]16)
        $writer.Write([int16]1)
        $writer.Write([int16]1)
        $writer.Write([int]$sampleRate)
        $writer.Write([int]($sampleRate * 2))
        $writer.Write([int16]2)
        $writer.Write([int16]16)
        $writer.Write([Text.Encoding]::ASCII.GetBytes('data'))
        $writer.Write([int]($sampleCount * 2))
        for ($sample = 0; $sample -lt $sampleCount; $sample++) {
            $phase = $sample
            $value = 0
            if ($phase -ge 4800 -and $phase -lt 14400) {
                $value = [int][Math]::Round(8192 * [Math]::Sin(2 * [Math]::PI * 880 * $phase / $sampleRate))
            }
            $writer.Write([int16]$value)
        }
    }
    finally { $writer.Dispose() }
}

function Get-CompletedSegments([string]$ListPath) {
    if (-not [IO.File]::Exists($ListPath)) { return @() }
    $items = @()
    foreach ($line in [IO.File]::ReadAllLines($ListPath)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $fields = $line.Split(',')
        if ($fields.Length -lt 3) { continue }
        $segmentStart = 0.0
        $segmentEnd = 0.0
        if (-not [double]::TryParse($fields[1], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$segmentStart) -or
            -not [double]::TryParse($fields[2], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$segmentEnd) -or
            ($segmentEnd - $segmentStart) -lt 1.9) { continue }
        $field = $fields[0].Trim('"')
        if ([string]::IsNullOrWhiteSpace($field)) { continue }
        $path = if ([IO.Path]::IsPathRooted($field)) { $field } else { Join-Path (Split-Path $ListPath -Parent) $field }
        if ([IO.File]::Exists($path)) { $items += $path }
    }
    return $items
}

function Save-CompletedSegments([string[]]$Segments, [string]$Name) {
    if ($Segments.Count -eq 0) { throw 'No completed audio/video segments are available to save.' }
    $manifest = Join-Path $runDirectory ($Name + '.ffconcat')
    $contents = New-Object System.Collections.Generic.List[string]
    $contents.Add('ffconcat version 1.0')
    foreach ($segment in $Segments) {
        $safePath = $segment.Replace('\', '/').Replace("'", "'\''")
        $contents.Add("file '$safePath'")
    }
    [IO.File]::WriteAllLines($manifest, $contents, (New-Object Text.UTF8Encoding($false)))
    $output = Join-Path $runDirectory ($Name + '.mp4')
    $saveArguments = New-Object 'object[]' 2
    $saveArguments[0] = [string]$manifest
    $saveArguments[1] = [string]$output
    $arguments = [string]$buildSaver.Invoke($null, $saveArguments)
    $result = Invoke-Process $Ffmpeg $arguments
    if ($result.ExitCode -ne 0) { throw "ReplaySaver remux failed: $($result.Error)" }
    return $output
}

function Get-Probe([string]$Path) {
    $arguments = '-v error -show_entries stream=index,codec_type,codec_name,sample_rate,channels,duration:format=duration -of json "' + $Path + '"'
    $result = Invoke-Process $Ffprobe $arguments -ReadOutput
    if ($result.ExitCode -ne 0) { throw "ffprobe failed: $($result.Error)" }
    return ($result.Output | ConvertFrom-Json)
}

function Select-StreamCompleteSegments([string[]]$Segments) {
    $complete = @()
    foreach ($segment in $Segments) {
        try {
            $probe = Get-Probe $segment
            $video = @($probe.streams | Where-Object codec_type -eq 'video' | Select-Object -First 1)[0]
            $audio = @($probe.streams | Where-Object codec_type -eq 'audio' | Select-Object -First 1)[0]
            if ($null -eq $video -or $null -eq $audio -or $null -eq $video.duration -or $null -eq $audio.duration) { continue }
            if ([Math]::Abs([double]$video.duration - [double]$audio.duration) -le 0.25 -and [double]$video.duration -ge 1.8) {
                $complete += $segment
            }
        }
        catch { }
    }
    return $complete
}

function Get-StableSegments([string]$ListPath) {
    $items = @(Get-CompletedSegments $ListPath)
    if ($items.Count -le 1) { return @() }
    return @($items[0..($items.Count - 2)])
}

function Test-Decode([string]$Path) {
    $result = Invoke-Process $Ffmpeg ('-hide_banner -v error -i "' + $Path + '" -f null NUL')
    [pscustomobject]@{ ExitCode = $result.ExitCode; Error = $result.Error.Trim() }
}

function Get-AudioToneOnsets([string]$Path) {
    $rawPath = Join-Path $runDirectory 'audio-tone-analysis.s16le'
    $result = Invoke-Process $Ffmpeg ('-hide_banner -loglevel error -i "' + $Path + '" -map 0:a:0 -ac 1 -ar 48000 -f s16le -y "' + $rawPath + '"')
    if ($result.ExitCode -ne 0) { throw "Audio signal decode failed: $($result.Error)" }
    $analyzerDll = Join-Path $runDirectory 'ReplayAudioSignalAnalyzer.dll'
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not [IO.File]::Exists($compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
    & $compiler /nologo /target:library ("/out:" + $analyzerDll) (Join-Path $PSScriptRoot 'ReplayAudioSignalAnalyzer.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile the audio signal analyzer.' }
    $analyzerType = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($analyzerDll)).GetType('ReplayAudioSignalAnalyzer', $true)
    $analyzerArguments = New-Object 'object[]' 5
    $analyzerArguments[0] = [string]$rawPath
    $analyzerArguments[1] = [int]48000
    $analyzerArguments[2] = [int]880
    $analyzerArguments[3] = [int]50
    $analyzerArguments[4] = [double]2500
    return $analyzerType.GetMethod('FindToneOnsets').Invoke($null, $analyzerArguments)
}

function Get-VisualOnsets([string]$Path) {
    $rawPath = Join-Path $runDirectory 'visual-signal.rgb'
    $arguments = '-hide_banner -loglevel error -i "' + $Path + '" -vf "crop=2:2:0:0,scale=1:1:flags=neighbor,format=rgb24" -fps_mode passthrough -pix_fmt rgb24 -f rawvideo "' + $rawPath + '"'
    $result = Invoke-Process $Ffmpeg $arguments
    if ($result.ExitCode -ne 0) { throw "Visual signal extraction failed: $($result.Error)" }
    $bytes = [IO.File]::ReadAllBytes($rawPath)
    $events = @()
    $wasRed = $false
    $frame = 0
    for ($index = 0; $index + 2 -lt $bytes.Length; $index += 3) {
        $isRed = $bytes[$index] -ge 120 -and $bytes[$index + 1] -le 115 -and $bytes[$index + 2] -le 115
        if ($isRed -and -not $wasRed) { $events += ($frame / 60.0) }
        $wasRed = $isRed
        $frame++
    }
    Remove-Item -LiteralPath $rawPath -Force
    return $events
}

function Get-SyncMeasurements([double[]]$Visual, [double[]]$Audio) {
    $pairs = @()
    foreach ($visualTime in $Visual) {
        $nearest = $null
        $nearestDistance = [double]::MaxValue
        foreach ($audioTime in $Audio) {
            $distance = [Math]::Abs($visualTime - $audioTime)
            if ($distance -lt $nearestDistance) { $nearestDistance = $distance; $nearest = $audioTime }
        }
        if ($null -ne $nearest -and $nearestDistance -lt 0.5) {
            $pairs += [pscustomobject]@{ Visual = $visualTime; OffsetMs = ($visualTime - $nearest) * 1000 }
        }
    }
    if ($pairs.Count -lt 3) {
        return [pscustomobject]@{ Method = 'Subjective playback sync only'; StartOffsetMs = $null; MiddleOffsetMs = $null; EndOffsetMs = $null; MaxOffsetMs = $null; PairedEvents = $pairs.Count }
    }
    $middleIndex = [int][Math]::Floor(($pairs.Count - 1) / 2)
    $maxOffset = ($pairs | ForEach-Object { [Math]::Abs($_.OffsetMs) } | Measure-Object -Maximum).Maximum
    [pscustomobject]@{
        Method = 'Repeated flash/beep onset comparison'
        StartOffsetMs = [Math]::Round($pairs[0].OffsetMs, 1)
        MiddleOffsetMs = [Math]::Round($pairs[$middleIndex].OffsetMs, 1)
        EndOffsetMs = [Math]::Round($pairs[-1].OffsetMs, 1)
        MaxOffsetMs = [Math]::Round($maxOffset, 1)
        PairedEvents = $pairs.Count
    }
}

$audioSession = $null
$soundPlayer = $null
$encoderProcess = $null
$startAudio = $null
$stopAudio = $null
$disposeAudio = $null
$audioStateProperty = $null
$pipeNameProperty = $null
$formatProperty = $null
$sessionWorker = $null
$performanceSamples = New-Object System.Collections.Generic.List[object]
$savePaths = @()
function Write-TestProgress([string]$Stage) {
    $elapsed = if ($null -ne $watch) { [Math]::Round($watch.Elapsed.TotalSeconds, 2) } else { 0 }
    $text = '{0:o} elapsed={1}s stage={2}' -f [DateTime]::UtcNow, $elapsed, $Stage
    [IO.File]::AppendAllText((Join-Path $runDirectory 'test-progress.txt'), $text + [Environment]::NewLine)
}
try {
    $wavePath = Join-Path $runDirectory 'beep-pattern.wav'
    if ($Mode -ne 'Silence') { New-BeepWave $wavePath }

    $assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
    $audioType = $assembly.GetType('BoltSnip.ReplayAudioCaptureSession', $true)
    $encoderType = $assembly.GetType('BoltSnip.ReplayEncoder', $true)
    $settingsType = $assembly.GetType('BoltSnip.ReplaySettings', $true)
    $buildEncoder = $encoderType.GetMethod('BuildArguments', [Reflection.BindingFlags]'Static,NonPublic')
    $buildSaver = $assembly.GetType('BoltSnip.ReplaySaver', $true).GetMethod('BuildArguments', [Reflection.BindingFlags]'Static,NonPublic')
    $settings = [Activator]::CreateInstance($settingsType, $true)

    $audioSession = [Activator]::CreateInstance($audioType, $true)
    $audioType.GetMethod('WaitUntilPrepared', [Reflection.BindingFlags]'Instance,NonPublic').Invoke($audioSession, [object[]]@(5000))
    $formatProperty = $audioType.GetProperty('Format', [Reflection.BindingFlags]'Instance,NonPublic')
    $audioStateProperty = $audioType.GetProperty('State', [Reflection.BindingFlags]'Instance,NonPublic')
    $pipeNameProperty = $audioType.GetProperty('PipeArgument', [Reflection.BindingFlags]'Instance,NonPublic')
    $startAudio = $audioType.GetMethod('ConnectAndStart', [Reflection.BindingFlags]'Instance,NonPublic')
    $stopAudio = $audioType.GetMethod('Stop', [Reflection.BindingFlags]'Instance,NonPublic')
    $disposeAudio = $audioType.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
    $connectRunnerPath = Join-Path $runDirectory 'ReplayAudioConnectRunner.dll'
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not [IO.File]::Exists($compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
    & $compiler /nologo /target:library ("/out:" + $connectRunnerPath) (Join-Path $PSScriptRoot 'ReplayAudioConnectRunner.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile the audio startup runner.' }
    $connectRunnerType = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($connectRunnerPath)).GetType('ReplayAudioConnectRunner', $true)
    $format = $formatProperty.GetValue($audioSession, $null)
    $audioFormatType = $assembly.GetType('BoltSnip.ReplayAudioFormat', $true)
    $formatSampleRate = [int]$audioFormatType.GetProperty('SampleRate', [Reflection.BindingFlags]'Instance,NonPublic').GetValue($format, $null)
    $formatChannels = [int]$audioFormatType.GetProperty('Channels', [Reflection.BindingFlags]'Instance,NonPublic').GetValue($format, $null)
    $formatBits = [int]$audioFormatType.GetProperty('BitsPerSample', [Reflection.BindingFlags]'Instance,NonPublic').GetValue($format, $null)
    $formatName = [string]$audioFormatType.GetProperty('FfmpegSampleFormat', [Reflection.BindingFlags]'Instance,NonPublic').GetValue($format, $null)
    $audioInputBuilder = $audioType.GetMethod('BuildInputArguments', [Reflection.BindingFlags]'Static,NonPublic')
    $audioInput = [string]$audioInputBuilder.Invoke($null, [object[]]@($format, $pipeNameProperty.GetValue($audioSession, $null)))

    $cacheDirectory = Join-Path $runDirectory 'segments'
    [IO.Directory]::CreateDirectory($cacheDirectory) | Out-Null
    $listPath = Join-Path $cacheDirectory 'segments.csv'
    $pattern = Join-Path $cacheDirectory 'segment_%08d.mp4'
    $videoInput = '-re -f lavfi -i "color=c=blue:s=640x360:r=60,drawbox=x=0:y=0:w=200:h=200:color=red:t=fill:enable=''between(mod(t\,2)\,0.1\,0.3)''" '
    $encoderCallArguments = New-Object 'object[]' 6
    $encoderCallArguments[0] = [string]$listPath
    $encoderCallArguments[1] = [string]$pattern
    $encoderCallArguments[2] = [string]$videoInput
    $encoderCallArguments[3] = [string]$audioInput
    $encoderCallArguments[4] = $format
    $encoderCallArguments[5] = $settings
    $arguments = [string]$buildEncoder.Invoke($null, $encoderCallArguments)
    $arguments | Set-Content -LiteralPath (Join-Path $runDirectory 'ffmpeg-command.txt') -Encoding UTF8

    if ($Mode -ne 'Silence') {
        $soundPlayer = New-Object System.Media.SoundPlayer($wavePath)
        $soundPlayer.Load()
    }

    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Ffmpeg
    $startInfo.Arguments = $arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $encoderProcess = New-Object Diagnostics.Process
    $encoderProcess.StartInfo = $startInfo
    $watch = [Diagnostics.Stopwatch]::StartNew()
    if (-not $encoderProcess.Start()) { throw 'FFmpeg did not start.' }
    Write-TestProgress 'ffmpeg-started'
    $sessionWorker = [Activator]::CreateInstance($connectRunnerType, [object[]]@($audioSession, $startAudio, 5000))
    [void]$sessionWorker.GetType().GetMethod('Start').Invoke($sessionWorker, $null)
    $connectWorker = $sessionWorker.GetType().GetProperty('Worker').GetValue($sessionWorker, $null)
    Write-TestProgress 'connect-thread-started'
    if (-not $connectWorker.Join(10000)) {
        [void]$stopAudio.Invoke($audioSession, $null)
        if (-not $connectWorker.Join(3000)) { throw 'Audio startup thread did not exit after stop.' }
    }
    $connectFailure = [string]$sessionWorker.GetType().GetProperty('FailureType').GetValue($sessionWorker, $null)
    if (-not [string]::IsNullOrEmpty($connectFailure)) {
        $message = [string]$sessionWorker.GetType().GetProperty('FailureMessage').GetValue($sessionWorker, $null)
        throw ('Audio startup failed: {0}: {1}' -f $connectFailure, $message)
    }
    Write-TestProgress 'audio-started'
    if ([string]$audioStateProperty.GetValue($audioSession, $null) -ne 'Active') { throw 'WASAPI did not become active.' }
    if ($null -ne $soundPlayer) {
        $nextPulseBoundary = ([Math]::Floor($watch.Elapsed.TotalSeconds / 2) + 1) * 2
        while ($watch.Elapsed.TotalSeconds -lt $nextPulseBoundary) { Start-Sleep -Milliseconds 10 }
        $soundPlayer.PlayLooping()
    }
    $previousCpu = 0.0
    $checkpointA = $false
    $checkpointB = $false
    $lastProgressSecond = -30

    while ($watch.Elapsed.TotalSeconds -lt $DurationSeconds) {
        if ($watch.Elapsed.TotalSeconds -ge $captureLimitSeconds) {
            throw ('Synthetic segment test exceeded its bounded capture period; mode={0}; requested={1}s; cap={2}s.' -f
                $Mode, $DurationSeconds, $captureLimitSeconds)
        }
        if ($Mode -eq 'Long' -and -not $checkpointA -and $watch.Elapsed.TotalSeconds -ge 40) {
            $segments = @(Get-StableSegments $listPath)
            $segments = @(Select-StreamCompleteSegments $segments)
            $savePaths += Save-CompletedSegments @($segments | Select-Object -Last 20) 'Save-A'
            $checkpointA = $true
            Write-Output 'Save A remuxed while encoder remained active.'
        }
        if ($Mode -eq 'Long' -and -not $checkpointB -and $watch.Elapsed.TotalSeconds -ge 70) {
            $segments = @(Get-StableSegments $listPath)
            $segments = @(Select-StreamCompleteSegments $segments)
            $savePaths += Save-CompletedSegments @($segments | Select-Object -Last 30) 'Save-B'
            $checkpointB = $true
            Write-Output 'Save B remuxed while encoder remained active.'
        }

        $wholeSecond = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if ($wholeSecond -ge ($lastProgressSecond + 30)) {
            Write-Output ("{0}: {1}s; completed segments={2}" -f $Mode, $wholeSecond, @(Get-CompletedSegments $listPath).Count)
            $lastProgressSecond = $wholeSecond
        }
        try {
            $encoderProcess.Refresh()
            if ($encoderProcess.HasExited) { throw 'FFmpeg exited while the synthetic pipeline was running.' }
            $performanceSamples.Add([pscustomobject]@{
                ElapsedSeconds = [Math]::Round($watch.Elapsed.TotalSeconds, 1)
                WorkingSetMb = [Math]::Round($encoderProcess.WorkingSet64 / 1MB, 1)
                PrivateMb = [Math]::Round($encoderProcess.PrivateMemorySize64 / 1MB, 1)
                CpuSeconds = [Math]::Round($encoderProcess.TotalProcessorTime.TotalSeconds, 1)
            })
        }
        catch [InvalidOperationException] {
            if ($_.Exception.Message -like 'FFmpeg exited*') { throw }
        }
        Start-Sleep -Milliseconds 200
    }
    $watch.Stop()

    Write-TestProgress 'capture-loop-ended'
    Write-TestProgress 'before-audio-stop'
    [void]$stopAudio.Invoke($audioSession, $null)
    Write-TestProgress 'after-audio-stop'
    [void]$disposeAudio.Invoke($audioSession, $null)
    Write-TestProgress 'after-audio-dispose'
    $audioSession = $null
    if ($null -ne $soundPlayer) { $soundPlayer.Stop() }
    Write-TestProgress 'before-ffmpeg-q'
    $encoderProcess.StandardInput.WriteLine('q')
    $encoderProcess.StandardInput.Flush()
    if (-not $encoderProcess.WaitForExit(15000)) {
        try { $encoderProcess.Kill() } catch { }
        throw 'FFmpeg did not stop after audio pipe shutdown and q input.'
    }
    Write-TestProgress ('after-ffmpeg-exit-' + $encoderProcess.ExitCode)
    if ($encoderProcess.ExitCode -ne 0) { throw "FFmpeg exited with code $($encoderProcess.ExitCode)." }

    $segments = @(Select-StreamCompleteSegments (Get-CompletedSegments $listPath))
    if ($segments.Count -eq 0) { throw 'FFmpeg did not complete any MP4 segments.' }
    $maxSegments = [int][Math]::Floor(300 / $settingsType.GetField('segment_duration_seconds', [Reflection.BindingFlags]'Instance,NonPublic').GetValue($settings))
    $finalSegments = @($segments | Select-Object -Last $maxSegments)
    $savePaths += Save-CompletedSegments $finalSegments 'Final-Replay'
    Write-TestProgress 'after-final-remux'

    $randomIndexes = @(0, [int][Math]::Floor(($segments.Count - 1) / 2), ($segments.Count - 1)) | Select-Object -Unique
    $segmentProbes = @()
    foreach ($index in $randomIndexes) {
        $segmentPath = $segments[$index]
        $probe = Get-Probe $segmentPath
        $video = @($probe.streams | Where-Object codec_type -eq 'video' | Select-Object -First 1)[0]
        $audio = @($probe.streams | Where-Object codec_type -eq 'audio' | Select-Object -First 1)[0]
        if ($null -eq $video -or $video.codec_name -ne 'h264' -or $null -eq $audio -or $audio.codec_name -ne 'aac') {
            throw "Segment lacks expected H.264/AAC streams: $segmentPath"
        }
        $segmentProbes += [pscustomobject]@{ Path = $segmentPath; Video = $video.codec_name; Audio = $audio.codec_name; AudioRate = $audio.sample_rate; AudioChannels = $audio.channels }
    }

    $replays = @()
    foreach ($path in $savePaths) {
        $probe = Get-Probe $path
        $video = @($probe.streams | Where-Object codec_type -eq 'video' | Select-Object -First 1)[0]
        $audio = @($probe.streams | Where-Object codec_type -eq 'audio' | Select-Object -First 1)[0]
        $decode = Test-Decode $path
        if ($null -eq $video -or $video.codec_name -ne 'h264') { throw "Expected H.264 in $path" }
        if ($null -eq $audio -or $audio.codec_name -ne 'aac' -or $audio.sample_rate -ne '48000' -or $audio.channels -ne 2) { throw "Expected 48 kHz AAC stereo in $path" }
        if ($decode.ExitCode -ne 0) { throw "Decode failed for $path : $($decode.Error)" }
        $replays += [pscustomobject]@{
            Path = $path
            VideoDuration = if ($null -ne $video.duration) { [double]$video.duration } else { $null }
            AudioDuration = if ($null -ne $audio.duration) { [double]$audio.duration } else { $null }
            DeltaMs = if ($null -ne $video.duration -and $null -ne $audio.duration) { [Math]::Round(([double]$audio.duration - [double]$video.duration) * 1000, 1) } else { $null }
            FormatDuration = [double]$probe.format.duration
            DecodeExitCode = $decode.ExitCode
            DecodeError = $decode.Error
        }
    }

    $audioEvents = @()
    $visualEvents = @()
    $sync = $null
    if ($Mode -ne 'Silence') {
        $audioEvents = @(Get-AudioToneOnsets $replays[-1].Path)
        $visualEvents = @(Get-VisualOnsets $replays[-1].Path)
        $sync = Get-SyncMeasurements $visualEvents $audioEvents
        if ($Mode -eq 'Audio30' -and $audioEvents.Count -lt 5) { throw 'The 880 Hz loopback test tone was not detected reliably.' }
        if ($Mode -eq 'Long' -and $sync.PairedEvents -lt 30) { throw 'Too few beep/flash events were measured in the five-minute replay.' }
    }

    $performance = [pscustomobject]@{
        FfmpegPeakWorkingSetMb = [Math]::Round((($performanceSamples | Measure-Object WorkingSetMb -Maximum).Maximum), 1)
        FfmpegPeakPrivateMb = [Math]::Round((($performanceSamples | Measure-Object PrivateMb -Maximum).Maximum), 1)
        FfmpegCpuSecondsAtLastSample = if ($performanceSamples.Count -gt 0) { $performanceSamples[-1].CpuSeconds } else { $null }
        AudioWorkerCpu = 'Not measured separately'
        GPU = 'Not measured'
        VRAM = 'Not measured'
        NVENCUtilization = 'Not measured'
    }
    $concatCommand = [string]$buildSaver.Invoke($null, [object[]]@('Replay.ffconcat', 'Final-Replay.mp4'))
    $concatCommand | Set-Content -LiteralPath (Join-Path $runDirectory 'concat-command.txt') -Encoding UTF8
    $report = [pscustomobject]@{
        Mode = $Mode
        CapturePath = 'Synthetic 640x360 flash video + real WASAPI system loopback audio'
        RequestedDurationSeconds = $DurationSeconds
        ActualDurationSeconds = [Math]::Round($watch.Elapsed.TotalSeconds, 1)
        AudioEndpointFormat = ('{0} Hz, {1} channels, {2}-bit {3}' -f $formatSampleRate, $formatChannels, $formatBits, $formatName)
        AudioStateAfterStart = 'Active'
        CompletedSegmentCount = $segments.Count
        RandomSegmentProbes = $segmentProbes
        Replays = $replays
        Sync = $sync
        AudioEvents = $audioEvents.Count
        VisualEvents = $visualEvents.Count
        AudioOnsetSeconds = $audioEvents
        VisualOnsetSeconds = $visualEvents
        Performance = $performance
        DiagnosticLog = $diagnosticPath
        EvidenceDirectory = $runDirectory
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDirectory 'result.json') -Encoding UTF8
    $report | Format-List
}
finally {
    if ($null -ne $soundPlayer) { try { $soundPlayer.Stop(); $soundPlayer.Dispose() } catch { } }
    if ($null -ne $audioSession) {
        try { [void]$stopAudio.Invoke($audioSession, $null) } catch { }
        try { [void]$disposeAudio.Invoke($audioSession, $null) } catch { }
    }
    if ($null -ne $encoderProcess -and -not $encoderProcess.HasExited) {
        try { $encoderProcess.StandardInput.WriteLine('q'); $encoderProcess.StandardInput.Flush() } catch { }
        if (-not $encoderProcess.WaitForExit(5000)) { try { $encoderProcess.Kill() } catch { } }
    }
    if ($null -ne $encoderProcess) { $encoderProcess.Dispose() }
    if ($previousFfmpegPath) { [Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $previousFfmpegPath, 'Process') }
    else { [Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $null, 'Process') }
    if ($previousDiagnosticPath) { [Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $previousDiagnosticPath, 'Process') }
    else { [Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $null, 'Process') }
}
