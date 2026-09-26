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
if ($DurationSeconds -le 0) {
    $DurationSeconds = if ($Mode -eq 'Long') { 320 } else { 36 }
}
if ($Mode -eq 'Long' -and $DurationSeconds -lt 320) { throw 'Long mode must run for at least 320 seconds.' }
if (-not [IO.File]::Exists($Executable)) { throw "Build the executable first: $Executable" }
if (-not [IO.File]::Exists($Ffmpeg)) { throw "FFmpeg was not found: $Ffmpeg" }
if (-not [IO.File]::Exists($Ffprobe)) { throw "ffprobe was not found: $Ffprobe" }

$runId = $Mode + '-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$runDirectory = Join-Path $EvidenceDirectory $runId
[IO.Directory]::CreateDirectory($runDirectory) | Out-Null
$diagnosticPath = Join-Path $runDirectory 'diagnostic.log'
$previousFfmpegPath = [Environment]::GetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', 'Process')
$previousDiagnosticPath = [Environment]::GetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', 'Process')
$previousReplayOutputDirectory = [Environment]::GetEnvironmentVariable('BOLTSNIP_REPLAY_OUTPUT_DIRECTORY', 'Process')
[Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $Ffmpeg, 'Process')
[Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $diagnosticPath, 'Process')
[Environment]::SetEnvironmentVariable('BOLTSNIP_REPLAY_OUTPUT_DIRECTORY', $runDirectory, 'Process')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path (Join-Path $PSScriptRoot 'ReplayAudioSyncWave.cs')
. (Join-Path $PSScriptRoot 'ReplayAudioSyncPairing.ps1')
$nvidiaSmi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue

function Invoke-CapturedProcess([string]$Path, [string]$Arguments, [switch]$ReadOutput) {
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
    [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output; Error = $errorText }
    $process.Dispose()
}

function Get-GpuMetrics {
    if ($null -eq $nvidiaSmi) { return $null }
    $arguments = '--query-gpu=utilization.gpu,memory.used,utilization.encoder --format=csv,noheader,nounits'
    $result = Invoke-CapturedProcess $nvidiaSmi.Source $arguments -ReadOutput
    if ($result.ExitCode -ne 0) { return $null }
    $values = $result.Output.Trim() -split ','
    if ($values.Count -lt 3) { return $null }
    $utilization = $null
    $memoryUsed = $null
    $encoderUtilization = $null
    if ($values[0].Trim() -match '^\d+$') { $utilization = [double]$values[0].Trim() }
    if ($values[1].Trim() -match '^\d+$') { $memoryUsed = [double]$values[1].Trim() }
    if ($values[2].Trim() -match '^\d+$') { $encoderUtilization = [double]$values[2].Trim() }
    [pscustomobject]@{
        UtilizationPercent = $utilization
        MemoryUsedMb = $memoryUsed
        EncoderUtilizationPercent = $encoderUtilization
    }
}

function Get-SavedReplayPath([int]$SaveOrdinal) {
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    while ([DateTime]::UtcNow -lt $deadline -and [bool]$isSaving.GetValue($manager, $null)) {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }
    if ([bool]$isSaving.GetValue($manager, $null)) { throw 'Timed out waiting for ReplaySaver.' }
    if (-not [IO.File]::Exists($diagnosticPath)) { throw "Replay diagnostics were not written: $diagnosticPath" }
    $lines = [IO.File]::ReadAllLines($diagnosticPath)
    for ($index = $lines.Length - 1; $index -ge 0; $index--) {
        if ($lines[$index] -match 'Replay saved: (.+); duration=') {
            $source = $Matches[1]
            $destination = Join-Path $runDirectory ($Mode + '-save-' + $SaveOrdinal.ToString('00') + '.mp4')
            Move-Item -LiteralPath $source -Destination $destination -Force
            return $destination
        }
    }
    throw 'ReplaySaver finished without a saved output path in diagnostics.'
}

function Save-Replay([int]$SaveOrdinal) {
    if (-not [bool]$saveReplay.Invoke($manager, $null)) { throw "Replay save $SaveOrdinal was rejected." }
    return Get-SavedReplayPath $SaveOrdinal
}

function Get-Probe([string]$Path) {
    $arguments = '-v error -show_entries stream=index,codec_type,codec_name,width,height,sample_rate,channels,duration:format=duration -of json "' + $Path + '"'
    $result = Invoke-CapturedProcess $Ffprobe $arguments -ReadOutput
    if ($result.ExitCode -ne 0) { throw "ffprobe failed for $Path : $($result.Error)" }
    return ($result.Output | ConvertFrom-Json)
}

function Test-Decode([string]$Path) {
    $arguments = '-hide_banner -v error -i "' + $Path + '" -f null NUL'
    $result = Invoke-CapturedProcess $Ffmpeg $arguments
    [pscustomobject]@{ ExitCode = $result.ExitCode; Error = $result.Error.Trim() }
}

function Get-AudioVolume([string]$Path) {
    $arguments = '-hide_banner -i "' + $Path + '" -map 0:a:0 -af volumedetect -f null NUL'
    $result = Invoke-CapturedProcess $Ffmpeg $arguments
    if ($result.ExitCode -ne 0) { throw "Audio level analysis failed: $($result.Error)" }
    $mean = $null
    $maximum = $null
    if ($result.Error -match 'mean_volume:\s*(-?[0-9.]+) dB') { $mean = [double]$Matches[1] }
    if ($result.Error -match 'max_volume:\s*(-?[0-9.]+) dB') { $maximum = [double]$Matches[1] }
    [pscustomobject]@{ MeanVolumeDb = $mean; MaxVolumeDb = $maximum }
}

function Get-AudioToneOnsets([string]$Path) {
    $rawPath = Join-Path $runDirectory 'audio-tone-analysis.s16le'
    $arguments = '-hide_banner -loglevel error -i "' + $Path + '" -map 0:a:0 -ac 1 -ar 48000 -f s16le -y "' + $rawPath + '"'
    $result = Invoke-CapturedProcess $Ffmpeg $arguments
    if ($result.ExitCode -ne 0) { throw "Audio signal decode failed: $($result.Error)" }
    $analyzerDll = Join-Path $runDirectory 'ReplayAudioSignalAnalyzer.dll'
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not [IO.File]::Exists($compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
    & $compiler /nologo /target:library ("/out:" + $analyzerDll) (Join-Path $PSScriptRoot 'ReplayAudioSignalAnalyzer.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile the audio signal analyzer.' }
    $analyzerType = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($analyzerDll)).GetType('ReplayAudioSignalAnalyzer', $true)
    $invokeArguments = New-Object 'object[]' 5
    $invokeArguments[0] = [string]$rawPath
    $invokeArguments[1] = [int]48000
    $invokeArguments[2] = [int]880
    $invokeArguments[3] = [int]10
    $invokeArguments[4] = [double]2500
    return $analyzerType.GetMethod('FindToneOnsets').Invoke($null, $invokeArguments)
}

function Get-VisualOnsets([string]$Path, [int]$FrameWidth, [int]$FrameHeight) {
    $rawPath = Join-Path $runDirectory 'visual-signal.rgb'
    $scaleX = [double]$FrameWidth / [double]$screen.Bounds.Width
    $scaleY = [double]$FrameHeight / [double]$screen.Bounds.Height
    $cropLeft = [int][Math]::Round($playerLeft * $scaleX)
    $cropTop = [int][Math]::Round($playerTop * $scaleY)
    $cropWidth = [Math]::Min($FrameWidth - $cropLeft, [int][Math]::Round($playerWidth * $scaleX))
    $cropHeight = [Math]::Min($FrameHeight - $cropTop, [int][Math]::Round($playerHeight * $scaleY))
    if ($cropWidth -le 0 -or $cropHeight -le 0) { throw 'The DPI-scaled visual marker crop is outside the encoded frame.' }
    $script:visualCaptureRoi = [pscustomobject]@{
        EncodedFrame = '{0}x{1}' -f $FrameWidth, $FrameHeight
        ScreenBoundsSeenByHarness = $screen.Bounds.ToString()
        ScaleX = [Math]::Round($scaleX, 5)
        ScaleY = [Math]::Round($scaleY, 5)
        CropPixels = '{0},{1},{2},{3}' -f $cropLeft, $cropTop, $cropWidth, $cropHeight
    }
    $filter = 'crop=' + $cropWidth + ':' + $cropHeight + ':' + $cropLeft + ':' + $cropTop + ',scale=64:40:flags=area,format=rgb24'
    $arguments = '-hide_banner -loglevel error -i "' + $Path + '" -vf "' + $filter + '" -fps_mode passthrough -pix_fmt rgb24 -f rawvideo "' + $rawPath + '"'
    $result = Invoke-CapturedProcess $Ffmpeg $arguments
    if ($result.ExitCode -ne 0) { throw "Visual signal extraction failed: $($result.Error)" }
    $bytes = [IO.File]::ReadAllBytes($rawPath)
    $events = @()
    $wasRed = $false
    $frame = 0
    $bytesPerFrame = 64 * 40 * 3
    for ($frameStart = 0; $frameStart + $bytesPerFrame -le $bytes.Length; $frameStart += $bytesPerFrame) {
        $redPixels = 0
        for ($index = $frameStart; $index -lt $frameStart + $bytesPerFrame; $index += 3) {
            if ($bytes[$index] -ge 120 -and $bytes[$index + 1] -le 115 -and $bytes[$index + 2] -le 115) {
                $redPixels++
            }
        }
        $isRed = $redPixels -ge 80
        if ($isRed -and -not $wasRed) { $events += ($frame / 60.0) }
        $wasRed = $isRed
        $frame++
    }
    Remove-Item -LiteralPath $rawPath -Force
    return $events
}

$manager = $null
$stimulusForm = $null
$soundPlayer = $null
$lastStimulusColor = $null
$savePaths = @()
$performanceSamples = New-Object System.Collections.Generic.List[object]
try {
    $screen = [Windows.Forms.Screen]::PrimaryScreen
    if ($null -eq $screen) { throw 'No primary display is available for the capture test.' }
    $playerWidth = 480
    $playerHeight = 285
    $playerLeft = $screen.Bounds.Left + [int](($screen.Bounds.Width - $playerWidth) / 2)
    $playerTop = $screen.Bounds.Top + [int](($screen.Bounds.Height - $playerHeight) / 2)
    if ($Mode -ne 'Silence') {
        $wavePath = Join-Path $runDirectory 'beep-pattern.wav'
        $sampleRate = 48000
        [ReplayAudioSyncWave]::WritePattern($wavePath, $sampleRate, 2, 880, 2000, 100, 200, 8192)

        $stimulusForm = New-Object Windows.Forms.Form
        $stimulusForm.Text = 'BoltSnip synchronized audio integration test'
        $stimulusForm.FormBorderStyle = [Windows.Forms.FormBorderStyle]::None
        $stimulusForm.ShowInTaskbar = $false
        $stimulusForm.TopMost = $true
        $stimulusForm.StartPosition = [Windows.Forms.FormStartPosition]::Manual
        $stimulusForm.Location = New-Object Drawing.Point($playerLeft, $playerTop)
        $stimulusForm.ClientSize = New-Object Drawing.Size($playerWidth, $playerHeight)
        $stimulusForm.BackColor = [Drawing.Color]::Navy
        $stimulusForm.Show()
        $stimulusForm.Activate()
        [Windows.Forms.Application]::DoEvents()

        $soundPlayer = New-Object System.Media.SoundPlayer($wavePath)
    }

    [pscustomobject]@{
        DesktopBounds = $screen.Bounds.ToString()
        PlaybackBounds = if ($Mode -ne 'Silence') { '{0},{1},{2},{3}' -f $playerLeft, $playerTop, $playerWidth, $playerHeight } else { $null }
        Stimulus = if ($Mode -ne 'Silence') { 'WinForms navy/red flash + SoundPlayer 880 Hz repeat' } else { $null }
        StimulusWindowHandle = if ($Mode -ne 'Silence') { '0x{0:X}' -f $stimulusForm.Handle.ToInt64() } else { $null }
        StimulusWindowTopMost = if ($Mode -ne 'Silence') { $stimulusForm.TopMost } else { $null }
        Measurement = 'WinForms flash + WASAPI-captured SoundPlayer 880 Hz onset comparison; 64x40 stimulus-window red area detection'
        RedPixelThreshold = 80
    } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDirectory 'sync-window.json') -Encoding UTF8

    $assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
    $managerType = $assembly.GetType('BoltSnip.ReplayManager', $true)
    $flags = [Reflection.BindingFlags]'Instance,Static,NonPublic'
    $manager = [Activator]::CreateInstance($managerType, $true)
    $start = $managerType.GetMethod('Start', $flags)
    $dispose = $managerType.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
    $state = $managerType.GetProperty('State', $flags)
    $audioState = $managerType.GetProperty('AudioState', $flags)
    $bufferedSegmentCount = $managerType.GetProperty('BufferedSegmentCount', $flags)
    $bufferedDuration = $managerType.GetProperty('BufferedDurationSeconds', $flags)
    $audioWorkerCpu = $managerType.GetProperty('AudioWorkerCpuSeconds', $flags)
    $audioInputDuration = $managerType.GetProperty('AudioInputDurationSeconds', $flags)
    $lastError = $managerType.GetProperty('LastError', $flags)
    $saveReplay = $managerType.GetMethod('SaveReplay', $flags)
    $isSaving = $managerType.GetProperty('IsSaving', $flags)

    [void]$start.Invoke($manager, $null)
    $startupDeadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $startupDeadline -and $state.GetValue($manager, $null).ToString() -notin @('Recording', 'Error')) {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }
    if ($state.GetValue($manager, $null).ToString() -ne 'Recording') {
        throw "Replay did not start: $([string]$lastError.GetValue($manager, $null))"
    }
    if ($Mode -ne 'Silence') {
        if (-not $stimulusForm.Visible -or -not $stimulusForm.TopMost) { throw 'The WinForms flash stimulus is not visible and topmost on the Default desktop.' }
    }
    $startTime = [DateTime]::UtcNow
    $watch = [Diagnostics.Stopwatch]::StartNew()
    if ($Mode -ne 'Silence') { $soundPlayer.PlayLooping() }
    $hostProcess = [Diagnostics.Process]::GetCurrentProcess()
    $lastHostCpu = $hostProcess.TotalProcessorTime
    $lastSample = [DateTime]::UtcNow
    $checkpointA = $false
    $checkpointB = $false
    $lastProgressMinute = -1

    while ($watch.Elapsed.TotalSeconds -lt $DurationSeconds) {
        [Windows.Forms.Application]::DoEvents()
        if ($Mode -ne 'Silence') {
            $phaseMilliseconds = $watch.ElapsedMilliseconds % 2000
            $stimulusColor = if ($phaseMilliseconds -ge 90 -and $phaseMilliseconds -lt 290) { [Drawing.Color]::Red } else { [Drawing.Color]::Navy }
            if ($stimulusColor -ne $lastStimulusColor) {
                $stimulusForm.BackColor = $stimulusColor
                $stimulusForm.Refresh()
                $lastStimulusColor = $stimulusColor
            }
        }
        if ($Mode -eq 'Long' -and -not $checkpointA -and $watch.Elapsed.TotalSeconds -ge 40 -and -not [bool]$isSaving.GetValue($manager, $null)) {
            $savePaths += Save-Replay 1
            $checkpointA = $true
            $checkpointASavedAt = [Math]::Round($watch.Elapsed.TotalSeconds, 1)
        }
        if ($Mode -eq 'Long' -and -not $checkpointB -and $watch.Elapsed.TotalSeconds -ge 70 -and -not [bool]$isSaving.GetValue($manager, $null)) {
            $savePaths += Save-Replay 2
            $checkpointB = $true
            $checkpointBSavedAt = [Math]::Round($watch.Elapsed.TotalSeconds, 1)
        }

        if (([DateTime]::UtcNow - $lastSample).TotalSeconds -ge 5) {
            $hostProcess.Refresh()
            $ffmpegProcesses = @(Get-Process -Name ffmpeg -ErrorAction SilentlyContinue)
            $gpuMetrics = Get-GpuMetrics
            $gpuUtilization = $null
            $gpuMemoryUsed = $null
            $gpuEncoderUtilization = $null
            if ($null -ne $gpuMetrics) {
                $gpuUtilization = $gpuMetrics.UtilizationPercent
                $gpuMemoryUsed = $gpuMetrics.MemoryUsedMb
                $gpuEncoderUtilization = $gpuMetrics.EncoderUtilizationPercent
            }
            $performanceSamples.Add([pscustomobject]@{
                ElapsedSeconds = [Math]::Round($watch.Elapsed.TotalSeconds, 1)
                HarnessWorkingSetMb = [Math]::Round($hostProcess.WorkingSet64 / 1MB, 1)
                HarnessPrivateMb = [Math]::Round($hostProcess.PrivateMemorySize64 / 1MB, 1)
                HarnessCpuSeconds = [Math]::Round($hostProcess.TotalProcessorTime.TotalSeconds, 1)
                FfmpegWorkingSetMb = [Math]::Round((($ffmpegProcesses | Measure-Object WorkingSet64 -Sum).Sum) / 1MB, 1)
                FfmpegPrivateMb = [Math]::Round((($ffmpegProcesses | Measure-Object PrivateMemorySize64 -Sum).Sum) / 1MB, 1)
                FfmpegCpuSeconds = [Math]::Round((($ffmpegProcesses | Measure-Object CPU -Sum).Sum), 1)
                ReplayState = $state.GetValue($manager, $null).ToString()
                AudioState = $audioState.GetValue($manager, $null).ToString()
                BufferedSegments = [int]$bufferedSegmentCount.GetValue($manager, $null)
                BufferedSeconds = [Math]::Round([double]$bufferedDuration.GetValue($manager, $null), 2)
                GpuUtilizationPercent = $gpuUtilization
                GpuMemoryUsedMb = $gpuMemoryUsed
                NvencUtilizationPercent = $gpuEncoderUtilization
            })
            $lastSample = [DateTime]::UtcNow
        }

        $currentMinute = [int][Math]::Floor($watch.Elapsed.TotalSeconds / 60)
        if ($currentMinute -gt $lastProgressMinute) {
            $lastProgressMinute = $currentMinute
            Write-Output ("{0}: recording {1}s; state={2}; audio={3}; buffered={4}s/{5} segments" -f $Mode, [Math]::Floor($watch.Elapsed.TotalSeconds), $state.GetValue($manager, $null), $audioState.GetValue($manager, $null), [Math]::Round([double]$bufferedDuration.GetValue($manager, $null), 1), $bufferedSegmentCount.GetValue($manager, $null))
        }
        Start-Sleep -Milliseconds 20
    }

    $savePaths += Save-Replay ($savePaths.Count + 1)
    $managerStateAtSaveCompletion = $state.GetValue($manager, $null).ToString()
    $audioStateAtSaveCompletion = $audioState.GetValue($manager, $null).ToString()
    $bufferedSegmentCountAtSaveCompletion = [int]$bufferedSegmentCount.GetValue($manager, $null)
    $bufferedDurationAtSaveCompletion = [double]$bufferedDuration.GetValue($manager, $null)
    if ($managerStateAtSaveCompletion -ne 'Recording') { throw "Replay stopped during $Mode capture: $([string]$lastError.GetValue($manager, $null))" }
    $watch.Stop()
    if ($null -ne $soundPlayer) { $soundPlayer.Stop() }
    if ($null -ne $stimulusForm) { $stimulusForm.Close() }
    [void]$dispose.Invoke($manager, $null)
    $audioWorkerCpuSeconds = [double]$audioWorkerCpu.GetValue($manager, $null)
    $audioInputDurationSeconds = [double]$audioInputDuration.GetValue($manager, $null)

    $replays = @()
    foreach ($path in $savePaths) {
        $probe = Get-Probe $path
        $video = @($probe.streams | Where-Object codec_type -eq 'video' | Select-Object -First 1)[0]
        $audio = @($probe.streams | Where-Object codec_type -eq 'audio' | Select-Object -First 1)[0]
        $decode = Test-Decode $path
        $volume = Get-AudioVolume $path
        $toneOnsets = @()
        if ($Mode -ne 'Silence') { $toneOnsets = @(Get-AudioToneOnsets $path) }
        $result = [pscustomobject]@{
            Path = $path
            VideoCodec = if ($null -ne $video) { $video.codec_name } else { $null }
            AudioCodec = if ($null -ne $audio) { $audio.codec_name } else { $null }
            SampleRate = if ($null -ne $audio) { $audio.sample_rate } else { $null }
            Channels = if ($null -ne $audio) { $audio.channels } else { $null }
            VideoStartTime = if ($null -ne $video.start_time) { [double]$video.start_time } else { $null }
            AudioStartTime = if ($null -ne $audio.start_time) { [double]$audio.start_time } else { $null }
            AudioMeanVolumeDb = $volume.MeanVolumeDb
            AudioMaxVolumeDb = $volume.MaxVolumeDb
            AudioToneOnsetCount = $toneOnsets.Count
            AudioToneFirstOnsetSeconds = if ($toneOnsets.Count -gt 0) { [double]$toneOnsets[0] } else { $null }
            AudioToneLastOnsetSeconds = if ($toneOnsets.Count -gt 0) { [double]$toneOnsets[-1] } else { $null }
            AudioToneOnsetSeconds = $toneOnsets
            VideoDuration = if ($null -ne $video.duration) { [double]$video.duration } else { $null }
            AudioDuration = if ($null -ne $audio.duration) { [double]$audio.duration } else { $null }
            FormatDuration = [double]$probe.format.duration
            DecodeExitCode = $decode.ExitCode
            DecodeError = $decode.Error
        }
        if ($null -eq $video -or $video.codec_name -ne 'h264') { throw "Expected H.264 video in $path" }
        if ($null -eq $audio -or $audio.codec_name -ne 'aac') { throw "Expected AAC audio in $path" }
        if ($audio.sample_rate -ne '48000' -or $audio.channels -ne 2) { throw "Expected 48 kHz stereo audio in $path" }
        if ($decode.ExitCode -ne 0) { throw "Decode failed for $path : $($decode.Error)" }
        $replays += $result
    }

    $audioAnalysis = $null
    $audioEvents = if ($null -ne $replays[-1].AudioToneOnsetSeconds) { @($replays[-1].AudioToneOnsetSeconds) } else { @() }
    if ($Mode -ne 'Silence') {
        $target = $replays[-1].Path
        $visualEvents = Get-VisualOnsets $target $video.width $video.height
        $audioAnalysis = Get-SyncMeasurements $visualEvents $audioEvents
    }

    $hostCpuSeconds = [Math]::Max(0, $hostProcess.TotalProcessorTime.TotalSeconds - $lastHostCpu.TotalSeconds)
    $gpuSamples = @($performanceSamples.ToArray() | Where-Object { $null -ne $_.GpuUtilizationPercent })
    $gpuPeakUtilizationPercent = $null
    $gpuPeakMemoryUsedMb = $null
    $nvencPeakUtilizationPercent = $null
    if ($gpuSamples.Count -gt 0) {
        $gpuPeakUtilizationPercent = ($gpuSamples | Measure-Object GpuUtilizationPercent -Maximum).Maximum
        $gpuPeakMemoryUsedMb = ($gpuSamples | Measure-Object GpuMemoryUsedMb -Maximum).Maximum
        $nvencPeakUtilizationPercent = ($gpuSamples | Measure-Object NvencUtilizationPercent -Maximum).Maximum
    }
    $performance = [pscustomobject]@{
        HarnessProcessName = $hostProcess.ProcessName
        HarnessCpuSeconds = [Math]::Round($hostCpuSeconds, 1)
        HarnessPeakWorkingSetMb = [Math]::Round((($performanceSamples | Measure-Object HarnessWorkingSetMb -Maximum).Maximum), 1)
        HarnessPeakPrivateMb = [Math]::Round((($performanceSamples | Measure-Object HarnessPrivateMb -Maximum).Maximum), 1)
        FfmpegPeakWorkingSetMb = [Math]::Round((($performanceSamples | Measure-Object FfmpegWorkingSetMb -Maximum).Maximum), 1)
        FfmpegPeakPrivateMb = [Math]::Round((($performanceSamples | Measure-Object FfmpegPrivateMb -Maximum).Maximum), 1)
        FfmpegCpuSecondsAtLastSample = $null
        Samples = $performanceSamples.ToArray()
        AudioWorkerCpuSeconds = [Math]::Round($audioWorkerCpuSeconds, 3)
        GpuPeakUtilizationPercent = $gpuPeakUtilizationPercent
        GpuPeakMemoryUsedMb = $gpuPeakMemoryUsedMb
        NvencPeakUtilizationPercent = $nvencPeakUtilizationPercent
        GpuMetricsSamples = $gpuSamples.Count
        GpuMetricsSource = if ($null -ne $nvidiaSmi) { $nvidiaSmi.Source } else { 'Not measured' }
    }
    if ($performanceSamples.Count -gt 0) {
        $performance.FfmpegCpuSecondsAtLastSample = [double]$performanceSamples[-1].FfmpegCpuSeconds
    }
    $syncStimulusVisualDelay = $null
    if ($Mode -ne 'Silence') { $syncStimulusVisualDelay = 90 }
    $report = [pscustomobject]@{
        Mode = $Mode
        RequestedDurationSeconds = $DurationSeconds
        ActualRecordingSeconds = [Math]::Round($watch.Elapsed.TotalSeconds, 1)
        RecordingStartedUtc = $startTime.ToString('o')
        ReplayAudioState = $audioStateAtSaveCompletion
        AudioStateAtSaveCompletion = $audioStateAtSaveCompletion
        AudioInputDurationSeconds = [Math]::Round($audioInputDurationSeconds, 2)
        ManagerStateAtSaveCompletion = $managerStateAtSaveCompletion
        BufferedSegmentCountAtSaveCompletion = $bufferedSegmentCountAtSaveCompletion
        BufferedDurationAtSaveCompletion = [Math]::Round($bufferedDurationAtSaveCompletion, 2)
        CaptureSource = 'WASAPI default render endpoint loopback'
        SyncStimulusVisualDelayMilliseconds = $syncStimulusVisualDelay
        SyncStimulusToneDelayMilliseconds = if ($Mode -ne 'Silence') { 100 } else { $null }
        SavePaths = $savePaths
        CheckpointASavedAtSeconds = $checkpointASavedAt
        CheckpointBSavedAtSeconds = $checkpointBSavedAt
        Replays = $replays
        AudioVideoSync = $audioAnalysis
        VisualCaptureRoi = $script:visualCaptureRoi
        VisualOnsetCount = $visualEvents.Count
        VisualOnsetSeconds = $visualEvents
        AudioOnsetCount = $audioEvents.Count
        AudioOnsetSeconds = $audioEvents
        Performance = $performance
        DiagnosticLog = $diagnosticPath
        EvidenceDirectory = $runDirectory
    }
    $report | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $runDirectory 'result.json') -Encoding UTF8
    $report | Format-List
    if ($Mode -eq 'Audio30' -and $audioAnalysis.PairedEvents -lt 10) { throw 'Too few flash/beep events were measured in the 30-second recording.' }
    if ($Mode -eq 'Long' -and $audioAnalysis.PairedEvents -lt 100) { throw 'Too few flash/beep events were measured in the five-minute recording.' }
    if ($null -ne $audioAnalysis -and $null -ne $audioAnalysis.MaxOffsetMs -and $audioAnalysis.MaxOffsetMs -ge 100) { throw 'Measured A/V onset error exceeded the 100 ms target.' }
    if ($Mode -eq 'Silence' -and $audioEvents.Count -gt 0) { throw 'The silent test unexpectedly contains the 880 Hz system test tone.' }
    if ($Mode -eq 'Silence' -and $replays[-1].VideoDuration -lt 30) { throw 'The silent replay was shorter than 30 seconds.' }
    if ($Mode -eq 'Long' -and $replays[-1].VideoDuration -lt 290) { throw 'The long replay was shorter than the 290-second validation minimum.' }
    if ($Mode -eq 'Silence' -and $null -ne $replays[-1].AudioMaxVolumeDb -and $replays[-1].AudioMaxVolumeDb -ge -60) { throw 'The silent replay audio exceeded the -60 dBFS silence threshold.' }
}
catch {
    $_ | Format-List * -Force | Out-String | Set-Content -LiteralPath (Join-Path $runDirectory 'failure.txt') -Encoding UTF8
    throw
}
finally {
    if ($null -ne $soundPlayer) { try { $soundPlayer.Stop(); $soundPlayer.Dispose() } catch { } }
    if ($null -ne $stimulusForm) { try { $stimulusForm.Close(); $stimulusForm.Dispose() } catch { } }
    if ($null -ne $manager -and $null -ne $dispose) { try { [void]$dispose.Invoke($manager, $null) } catch { } }
    if ($previousFfmpegPath) { [Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $previousFfmpegPath, 'Process') }
    else { [Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $null, 'Process') }
    if ($previousDiagnosticPath) { [Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $previousDiagnosticPath, 'Process') }
    else { [Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $null, 'Process') }
    if ($previousReplayOutputDirectory) { [Environment]::SetEnvironmentVariable('BOLTSNIP_REPLAY_OUTPUT_DIRECTORY', $previousReplayOutputDirectory, 'Process') }
    else { [Environment]::SetEnvironmentVariable('BOLTSNIP_REPLAY_OUTPUT_DIRECTORY', $null, 'Process') }
}
