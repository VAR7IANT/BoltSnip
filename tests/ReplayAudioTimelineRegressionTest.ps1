param([string]$Executable)
$ErrorActionPreference='Stop'
$assembly=[Reflection.Assembly]::LoadFile((Resolve-Path $Executable).Path)
$static=[Reflection.BindingFlags]'Static,NonPublic'
$instance=[Reflection.BindingFlags]'Instance,NonPublic'
$old=$assembly.GetType('BoltSnip.ReplayAudioCaptureSession').GetMethod('GetDueSilenceFrameCount',$static)
$timelineType=$assembly.GetType('BoltSnip.ReplayAudioTimeline',$true)
function New-Timeline([int]$Rate) {
    $timelineType.GetConstructor($instance,$null,[Type[]]@([int]),$null).Invoke([object[]]@($Rate))
}
function Packet-Start($Timeline,[long]$Qpc,[long]$Written) {
    [long]$timelineType.GetMethod('GetPacketStartFrame',$instance).Invoke($Timeline,[object[]]@($Qpc,$Written))
}
function Due-Silence($Timeline,[long]$Qpc,[long]$Written,[int]$Safety) {
    [long]$timelineType.GetMethod('GetDueSilenceFrames',$instance).Invoke($Timeline,[object[]]@($Qpc,$Written,$Safety))
}
$written=0L; $deadline=20L; $remainder=0
for($ms=0;$ms -lt 1000;$ms++) {
    if($ms % 30 -eq 0) { $written+=480; $deadline=$ms+20 }
    else {
        $args=[object[]]@([long]$ms,10L,[long]$deadline,48000,[int]$remainder)
        $written += [int]$old.Invoke($null,$args)
        $deadline=[long]$args[2]; $remainder=[int]$args[4]
    }
}
if($written -ne 32160) { throw 'Old capture-loop trace reproduction changed unexpectedly' }
"REPRODUCED: old deadline-reset loop supplies $written of 48000 frames on a one-second intermittent packet trace."
foreach($rate in @(44100,48000)) {
    foreach($period in @(10,30,100)) {
        $timeline=New-Timeline $rate
        $written=0L; $payloadFrames=[int]($rate/100)
        for($ms=0;$ms -lt 1000;$ms+=5) {
            $qpc=10000000L+$ms*10000L
            if($ms % $period -eq 0) {
                $start=Packet-Start $timeline $qpc $written
                $padding=[Math]::Max(0,$start-$written)
                $skip=[Math]::Min($payloadFrames,[Math]::Max(0,$written-$start))
                $written += $padding+$payloadFrames-$skip
            } else { $written += Due-Silence $timeline $qpc $written ([int]($rate/50)) }
        }
        if($written -gt $rate -or $written -lt $rate-[int]($rate/40)) {
            throw "Sample clock continuity failed: rate=$rate period=$period written=$written"
        }
        "PASS: packet/silence trace at $rate Hz, packet period ${period}ms, supplied $written frames; bounded 20ms silence holdback."
    }
}
$timeline=New-Timeline 48000
if((Packet-Start $timeline 10000000 12345) -ne 12345 -or (Packet-Start $timeline 10100000 12345) -ne 12825) { throw 'Pre-existing startup silence changed the source anchor' }
$overlapStart=Packet-Start $timeline 10100000 13305
$overlap=[Math]::Min(480,[Math]::Max(0,13305-$overlapStart))
if($overlap -ne 480) { throw 'Late packet duplicates audio already supplied as silence' }
'PASS: startup-silence anchor preserved; overlapping late packet prefix discarded instead of extending the sample clock.'
