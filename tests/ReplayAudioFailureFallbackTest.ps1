param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('BoltSnip-AudioFallback-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$helperSource = Join-Path $testRoot 'FailingAudioStart.cs'
$helperAssemblyPath = Join-Path $testRoot 'FailingAudioStart.dll'
[IO.File]::WriteAllText($helperSource, @'
using System;
public static class FailingAudioStart
{
    public static void Start()
    {
        throw new InvalidOperationException("simulated WASAPI startup failure");
    }
}
'@)

try {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not [IO.File]::Exists($compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
    & $compiler /nologo /target:library ("/out:" + $helperAssemblyPath) $helperSource
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile the simulated audio failure helper.' }

    $assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
    $managerType = $assembly.GetType('BoltSnip.ReplayManager', $true)
    $tryStart = $managerType.GetMethod('TryStartWithAudio', [Reflection.BindingFlags]'Static,NonPublic')
    $helperType = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($helperAssemblyPath)).GetType('FailingAudioStart', $true)
    $action = [Delegate]::CreateDelegate([Action], $null, $helperType.GetMethod('Start'))
    $arguments = [object[]]@($action, $null)
    $audioStarted = [bool]$tryStart.Invoke($null, $arguments)
    $failure = [Exception]$arguments[1]

    $settingsType = $assembly.GetType('BoltSnip.ReplaySettings', $true)
    $settings = [Activator]::CreateInstance($settingsType, $true)
    $audioEnabledByDefault = [bool]$settingsType.GetField('capture_system_audio', [Reflection.BindingFlags]'Instance,NonPublic').GetValue($settings)

    $encoderType = $assembly.GetType('BoltSnip.ReplayEncoder', $true)
    $build = $encoderType.GetMethod('BuildArguments', [Reflection.BindingFlags]'Static,NonPublic')
    $videoOnlyCommand = [string]$build.Invoke($null, [object[]]@(
        'segments.csv', 'segment_%08d.mp4', '-f gdigrab -framerate 60 -i desktop ', $null, $null, $settings))
    $fallbackCommandIsVideoOnly = $videoOnlyCommand.Contains('-an') -and
        -not $videoOnlyCommand.Contains('-map 1:a:0') -and
        -not $videoOnlyCommand.Contains('pipe')

    [pscustomobject]@{
        SimulatedAudioFailureWasCaught = (-not $audioStarted -and $null -ne $failure -and $failure.Message.Contains('simulated WASAPI'))
        DefaultCaptureAudioEnabled = $audioEnabledByDefault
        VideoOnlyFallbackCommandAvailable = $fallbackCommandIsVideoOnly
        Passed = (-not $audioStarted -and $null -ne $failure -and $audioEnabledByDefault -and $fallbackCommandIsVideoOnly)
    } | Format-List
    if (-not (-not $audioStarted -and $null -ne $failure -and $audioEnabledByDefault -and $fallbackCommandIsVideoOnly)) { exit 1 }
}
finally {
    if ([IO.Directory]::Exists($testRoot)) {
        try { [IO.Directory]::Delete($testRoot, $true) } catch { }
    }
}
