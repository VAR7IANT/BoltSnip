param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$saverType = $assembly.GetType('BoltSnip.ReplaySaver', $true)
$build = $saverType.GetMethod('BuildArguments', [Reflection.BindingFlags]'Static,NonPublic')
if ($null -eq $build) { throw 'ReplaySaver.BuildArguments is not present.' }
$arguments = [string]$build.Invoke($null, [object[]]@('segments.ffconcat', 'output.mp4'))
$checks = [ordered]@{
    VideoMap = $arguments.Contains('-map 0:v:0')
    OptionalAudioMap = $arguments.Contains('-map 0:a:0?')
    CopyVideo = $arguments.Contains('-c:v copy')
    CopyAudio = $arguments.Contains('-c:a copy')
}
$checks.GetEnumerator() | ForEach-Object { '{0}: {1}' -f $_.Key, $_.Value }
if ($checks.Values -contains $false) { exit 1 }
