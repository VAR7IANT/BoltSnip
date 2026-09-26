param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$formatType = $assembly.GetType('BoltSnip.ReplayAudioFormat', $true)
$encoderType = $assembly.GetType('BoltSnip.ReplayEncoder', $true)
$captureType = $assembly.GetType('BoltSnip.ReplayAudioCaptureSession', $true)
$parse = $formatType.GetMethod('Parse', [Reflection.BindingFlags]'Static,NonPublic')
$format = $parse.Invoke($null, [object[]]@(
    0xfffe, 2, 44100, 32, 8, 22, 32,
    [Guid]'00000003-0000-0010-8000-00aa00389b71'))
$settingsType = $assembly.GetType('BoltSnip.ReplaySettings', $true)
$settings = [Activator]::CreateInstance($settingsType, $true)
$build = $encoderType.GetMethod('BuildArguments', [Reflection.BindingFlags]'Static,NonPublic')
if ($null -eq $build) { throw 'ReplayEncoder.BuildArguments is not present.' }
$videoInput = '-f gdigrab -framerate 60 -i desktop '
$inputBuilder = $captureType.GetMethod('BuildInputArguments', [Reflection.BindingFlags]'Static,NonPublic')
$audioInput = [string]$inputBuilder.Invoke($null, [object[]]@($format, '\\.\pipe\test-audio'))
$withAudio = [string]$build.Invoke($null, [object[]]@('segments.csv', 'segment_%08d.mp4', $videoInput, $audioInput, $format, $settings))
$videoOnly = [string]$build.Invoke($null, [object[]]@('segments.csv', 'segment_%08d.mp4', $videoInput, $null, $null, $settings))

$checks = [ordered]@{
    AudioRawFormat = $withAudio.Contains('-f f32le -ar 44100 -ac 2')
    AudioUsesSampleClock = -not $audioInput.Contains('-use_wallclock_as_timestamps 1')
    NoManualAudioDelay = -not $withAudio.Contains('-af adelay=')
    ExplicitVideoMap = $withAudio.Contains('-map 0:v:0')
    ExplicitAudioMap = $withAudio.Contains('-map 1:a:0')
    AAC192k48kStereo = $withAudio.Contains('-c:a aac -b:a 192k -ar 48000 -ac 2')
    NoShortest = -not $withAudio.Contains('-shortest')
    VideoOnlyHasNoAudioInput = -not $videoOnly.Contains('test-audio') -and -not $videoOnly.Contains('-map 1:a:0')
    VideoOnlyKeepsOriginalAudioDisable = $videoOnly.Contains('-an')
}
$checks.GetEnumerator() | ForEach-Object { '{0}: {1}' -f $_.Key, $_.Value }
if ($checks.Values -contains $false) { exit 1 }
