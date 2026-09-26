param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'obj\instant-replay-audio\bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$type = $assembly.GetType('BoltSnip.ReplayAudioCaptureSession', $true)
$method = $type.GetMethod('GetDueSilenceFrameCount', [Reflection.BindingFlags]'Static,NonPublic')
if ($null -eq $method) { throw 'The silence continuity clock helper is missing.' }

function Get-DueFrames([long]$Now, [long]$Interval, [long]$Deadline, [int]$SampleRate, [int]$Remainder) {
    $arguments = New-Object 'object[]' 5
    $arguments[0] = [long]$Now
    $arguments[1] = [long]$Interval
    $arguments[2] = [long]$Deadline
    $arguments[3] = [int]$SampleRate
    $arguments[4] = [int]$Remainder
    $frames = [int]$method.Invoke($null, $arguments)
    [pscustomobject]@{ Frames = $frames; Deadline = [long]$arguments[2]; Remainder = [int]$arguments[4] }
}

$notDue = Get-DueFrames 99 10 100 48000 0
$onTime = Get-DueFrames 100 10 100 48000 0
$late = Get-DueFrames 135 10 110 48000 0
$lateAgain = Get-DueFrames 159 10 $late.Deadline 48000 0
if ($notDue.Frames -ne 0 -or $notDue.Deadline -ne 100) { throw 'Silence frames were emitted before their deadline.' }
if ($onTime.Frames -ne 480 -or $onTime.Deadline -ne 110) { throw 'An on-time 10 ms interval did not produce the expected PCM frames.' }
if ($late.Frames -ne 1440 -or $late.Deadline -ne 140) { throw 'A late wake failed to catch up all elapsed 10 ms intervals.' }
if ($lateAgain.Frames -ne 960 -or $lateAgain.Deadline -ne 160) { throw 'Repeated late wakes lost PCM time.' }

$deadline = 10L
$remainder = 0
$totalFrames = 0L
for ($index = 1; $index -le 100; $index++) {
    $result = Get-DueFrames ($index * 10) 10 $deadline 44100 $remainder
    $totalFrames += $result.Frames
    $deadline = $result.Deadline
    $remainder = $result.Remainder
}
if ($totalFrames -ne 44100 -or $remainder -ne 0) { throw '44.1 kHz fractional frame accounting drifted.' }

[pscustomobject]@{
    NoEarlyWrite = $notDue.Frames -eq 0
    TenMillisecondFramesAt48k = $onTime.Frames
    LateWakeCatchUpFrames = $late.Frames
    RepeatedLateWakeFrames = $lateAgain.Frames
    Exact44100FramesOverOneSecond = $totalFrames
    Passed = $true
}
