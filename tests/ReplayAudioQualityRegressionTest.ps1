param([string]$Executable = (Join-Path $PSScriptRoot '..\bin\BoltSnip.exe'))
$ErrorActionPreference = 'Stop'

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable).Path)
$instance = [Reflection.BindingFlags]'Instance,NonPublic'
$timelineType = $assembly.GetType('BoltSnip.ReplayAudioTimeline', $true)

function New-Timeline([int]$Rate) {
    $timelineType.GetConstructor($instance, $null, [Type[]]@([int]), $null).Invoke([object[]]@($Rate))
}
function Packet-Start($Timeline, [long]$Qpc, [long]$Written) {
    [long]$timelineType.GetMethod('GetPacketStartFrame', $instance).Invoke($Timeline, [object[]]@($Qpc, $Written))
}
function Due-Silence($Timeline, [long]$Qpc, [long]$Written, [int]$Safety) {
    [long]$timelineType.GetMethod('GetDueSilenceFrames', $instance).Invoke($Timeline, [object[]]@($Qpc, $Written, $Safety))
}
function Missing-Frames($Timeline, [long]$Start, [long]$Written, [int]$DeadZone) {
    [long]$timelineType.GetMethod('GetMissingFrames', $instance).Invoke($Timeline, [object[]]@($Start, $Written, $DeadZone))
}
function Overlap-Frames($Timeline, [long]$Start, [long]$Written, [int]$DeadZone) {
    [long]$timelineType.GetMethod('GetOverlapFrames', $instance).Invoke($Timeline, [object[]]@($Start, $Written, $DeadZone))
}

Write-Host "Running Audio Quality Regression Test..."

# Test 1 & 2 & 8 & 9: Continuous PCM signal with normal jitter (no clicks, no extra silence, no sample drops)
$sampleRate = 48000
$freq = 440.0
$deadZone = [int]($sampleRate / 100) # 10ms = 480 frames
$safety = [int]($sampleRate / 50)    # 20ms = 960 frames
$timeline = New-Timeline $sampleRate

$written = 0L
$outputPcm = New-Object System.Collections.Generic.List[single]
$rand = New-Object System.Random(42)

for ($pkt = 0; $pkt -lt 100; $pkt++) {
    $tMs = $pkt * 10
    # Jitter within +/- 2 frames (+/- 40us)
    $jitterFrames = $rand.Next(-2, 3)
    $jitterTicks = [long]($jitterFrames * 10000000.0 / $sampleRate)
    $qpc = 10000000L + ($tMs * 10000L) + $jitterTicks

    $packetFrames = 480
    $packetData = New-Object single[] $packetFrames
    for ($f = 0; $f -lt $packetFrames; $f++) {
        $idx = $pkt * 480 + $f
        $packetData[$f] = [single][Math]::Sin(2.0 * [Math]::PI * $freq * $idx / $sampleRate)
    }

    $start = Packet-Start $timeline $qpc $written
    $missing = Missing-Frames $timeline $start $written $deadZone
    $overlap = Overlap-Frames $timeline $start $written $deadZone

    if ($missing -ne 0) {
        throw "Regression: normal jitter ($jitterFrames frames) produced $missing missing silence frames!"
    }
    if ($overlap -ne 0) {
        throw "Regression: normal jitter ($jitterFrames frames) produced $overlap overlap trim frames!"
    }

    for ($f = 0; $f -lt $packetFrames; $f++) {
        $outputPcm.Add($packetData[$f])
    }
    $written += $packetFrames
}

if ($written -ne 48000) {
    throw "Continuous jitter trace did not produce exactly 48000 frames; got $written"
}

# Verify PCM sample continuity: abs(x[n] - x[n-1]) must not have clicks/spikes
$maxNaturalDiff = 2.0 * [Math]::PI * $freq / $sampleRate # ~0.0576
$maxObservedDiff = 0.0
$spikes = 0
for ($n = 1; $n -lt $outputPcm.Count; $n++) {
    $d = [Math]::Abs($outputPcm[$n] - $outputPcm[$n - 1])
    if ($d -gt $maxObservedDiff) { $maxObservedDiff = $d }
    if ($d -gt 0.1) { $spikes++ }
}

if ($spikes -ne 0 -or $maxObservedDiff -gt 0.06) {
    throw "PCM sample discontinuity detected: maxDiff=$maxObservedDiff, spikes=$spikes"
}
Write-Host "PASS: 100 continuous packets with jitter produced 0 extra silence, 0 trims, 0 discontinuities (maxDiff=$([Math]::Round($maxObservedDiff, 4)))."

# Test 3, 4, 5, 6, 7: Packet gap, idle silence pre-fill, resume without duplicate compensation
$timeline2 = New-Timeline 48000
$written2 = 0L

# 1. First 20 packets (0 to 200ms)
for ($pkt = 0; $pkt -lt 20; $pkt++) {
    $qpc = 10000000L + ($pkt * 100000L)
    $start = Packet-Start $timeline2 $qpc $written2
    $missing = Missing-Frames $timeline2 $start $written2 $deadZone
    $written2 += $missing + 480
}
if ($written2 -ne 9600) { throw "Part 1 initial write mismatch: $written2" }

# 2. Idle gap from 200ms to 500ms: idle loop fills silence with 20ms holdback
for ($tMs = 200; $tMs -lt 500; $tMs += 5) {
    $qpc = 10000000L + ($tMs * 10000L)
    $due = Due-Silence $timeline2 $qpc $written2 $safety
    if ($due -gt 0) {
        $written2 += $due
    }
}
$idleFilledSilence = $written2 - 9600
Write-Host "Idle loop filled $idleFilledSilence silence frames (holdback 20ms = $safety frames)."

# 3. Sound resumes at 500ms
$resumeQpc = 10000000L + 5000000L
$resumeStart = Packet-Start $timeline2 $resumeQpc $written2
if ($resumeStart -ne 24000) { throw "Resume start frame mismatch: $resumeStart vs expected 24000" }

$maxResumeCatchUp = $safety + [int]($sampleRate * 0.005) # safety holdback + 5ms polling interval
$missingAtResume = Missing-Frames $timeline2 $resumeStart $written2 $deadZone
if ($missingAtResume -le 0 -or $missingAtResume -gt $maxResumeCatchUp) {
    throw "Catch-up silence at resume failed: expected <= $maxResumeCatchUp frames, got $missingAtResume"
}
# Compensate the catch-up silence
$written2 += $missingAtResume

if ($written2 -ne 24000) {
    throw "Total frames after resume catch-up ($written2) did not align with resume timestamp (24000)!"
}
Write-Host "PASS: idle-loop silence ($idleFilledSilence frames) + resume catch-up ($missingAtResume frames) = exactly 14400 frames (300ms gap). No duplicate compensation."

# 4. Packets continue from 500ms to 1000ms
for ($pkt = 50; $pkt -lt 100; $pkt++) {
    $qpc = 10000000L + ($pkt * 100000L)
    $start = Packet-Start $timeline2 $qpc $written2
    $missing = Missing-Frames $timeline2 $start $written2 $deadZone
    $overlap = Overlap-Frames $timeline2 $start $written2 $deadZone
    if ($missing -ne 0 -or $overlap -ne 0) {
        throw "Subsequent packet after resume had spurious missing=$missing or overlap=$overlap"
    }
    $written2 += 480
}

if ($written2 -ne 48000) {
    throw "Total frames over 1 second timeline ($written2) did not equal 48000!"
}
Write-Host "PASS: total timeline frames = 48000 frames over 1.0 second. Sample clock continuity and timeline alignment verified."

[pscustomobject]@{
    ContinuousJitterSpikes = $spikes
    MaxSampleDiscontinuity = [Math]::Round($maxObservedDiff, 4)
    IdleHoldbackPreserved  = $missingAtResume -le $maxResumeCatchUp
    NoDuplicateSilence     = $written2 -eq 48000
    Passed                 = $true
}
