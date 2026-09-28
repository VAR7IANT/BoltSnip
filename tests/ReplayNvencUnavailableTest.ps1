param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('BoltSnip-ReplayNoNvenc-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$fakeFfmpeg = Join-Path $testRoot 'ffmpeg.exe'
$previousPath = [Environment]::GetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', 'Process')
$previousLogPath = [Environment]::GetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', 'Process')

try {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not [IO.File]::Exists($compiler)) {
        $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
    }
    $source = Join-Path $testRoot 'FakeFfmpeg.cs'
    [IO.File]::WriteAllText($source, @'
using System;
public static class FakeFfmpeg
{
    public static void Main(string[] args)
    {
        Console.WriteLine("Encoders:");
        Console.WriteLine(" V..... libx264 H.264 encoder");
    }
}
'@)
    & $compiler /nologo /target:exe /out:$fakeFfmpeg $source
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile the FFmpeg capability test stub.' }
    [Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $fakeFfmpeg, 'Process')
    [Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', (Join-Path $testRoot 'diagnostic.log'), 'Process')

    $assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
    $managerType = $assembly.GetType('BoltSnip.ReplayManager', $true)
    $flags = [Reflection.BindingFlags]'Instance,NonPublic'
    $manager = [Activator]::CreateInstance($managerType, $true)
    $start = $managerType.GetMethod('Start', $flags)
    $dispose = $managerType.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
    $state = $managerType.GetProperty('State', $flags)
    $lastError = $managerType.GetProperty('LastError', $flags)

    [void]$start.Invoke($manager, $null)
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline -and $state.GetValue($manager, $null).ToString() -ne 'Error') {
        Start-Sleep -Milliseconds 50
    }
    $errorMessage = [string]$lastError.GetValue($manager, $null)
    $errorState = $state.GetValue($manager, $null).ToString()
    $rejectedWithoutFallback = $errorState -eq 'Error' -and $errorMessage.Contains('h264_nvenc') -and
        -not $errorMessage.Contains('实验版')
    [void]$dispose.Invoke($manager, $null)

    [pscustomobject]@{
        MissingNvencRejectedClearly = $rejectedWithoutFallback
        ExperimentalProductCopyRemoved = -not $errorMessage.Contains('实验版')
        State = $errorState
        ErrorMessage = $errorMessage
        Passed = $rejectedWithoutFallback
    } | Format-List
    if (-not $rejectedWithoutFallback) { exit 1 }
}
finally {
    if ($null -ne $manager -and $null -ne $dispose) {
        [void]$dispose.Invoke($manager, $null)
    }
    if ($previousPath) {
        [Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $previousPath, 'Process')
    }
    else {
        [Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $null, 'Process')
    }
    if ($previousLogPath) {
        [Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $previousLogPath, 'Process')
    }
    else {
        [Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $null, 'Process')
    }
    if ([IO.Directory]::Exists($testRoot)) { [IO.Directory]::Delete($testRoot, $true) }
}
