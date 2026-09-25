param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$previousPath = [Environment]::GetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', 'Process')
$previousLogPath = [Environment]::GetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', 'Process')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('BoltSnip-ReplayUnavailable-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
[Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', (Join-Path ([IO.Path]::GetTempPath()) 'missing-ffmpeg.exe'), 'Process')
[Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', (Join-Path $testRoot 'diagnostic.log'), 'Process')
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$managerType = $assembly.GetType('BoltSnip.ReplayManager', $true)
$flags = [Reflection.BindingFlags]'Instance,NonPublic'
$manager = [Activator]::CreateInstance($managerType, $true)
$start = $managerType.GetMethod('Start', $flags)
$dispose = $managerType.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
$state = $managerType.GetProperty('State', $flags)
$lastError = $managerType.GetProperty('LastError', $flags)

try {
    [void]$start.Invoke($manager, $null)
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline -and $state.GetValue($manager, $null).ToString() -ne 'Error') {
        Start-Sleep -Milliseconds 50
    }

    $stateValue = $state.GetValue($manager, $null).ToString()
    $message = [string]$lastError.GetValue($manager, $null)
    $failureSurfacedWithoutCrash = $stateValue -eq 'Error' -and $message.Contains('BOLTSNIP_FFMPEG_PATH')
    [void]$dispose.Invoke($manager, $null)
    $resourcesStopped = $state.GetValue($manager, $null).ToString() -eq 'Disabled'
    $passed = $failureSurfacedWithoutCrash -and $resourcesStopped

    [pscustomobject]@{
        UnsupportedEncoderConditionHandled = $failureSurfacedWithoutCrash
        StateAfterDispose = $state.GetValue($manager, $null).ToString()
        NoApplicationCrash = $resourcesStopped
        Passed = $passed
    } | Format-List
    if (-not $passed) { exit 1 }
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
