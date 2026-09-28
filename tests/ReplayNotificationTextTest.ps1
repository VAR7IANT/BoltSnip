param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$managerType = $assembly.GetType('BoltSnip.ReplayManager', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$captureFallback = $managerType.GetMethod('BuildCaptureFallbackNotification', $flags)
$saveFailure = $managerType.GetMethod('BuildSaveFailureNotificationMessage', $flags)
if ($null -eq $captureFallback -or $null -eq $saveFailure) {
    throw 'The replay user notification helpers were not found.'
}

$startupFallbackText = [string]$captureFallback.Invoke($null, [object[]]@($false))
$runtimeFallbackText = [string]$captureFallback.Invoke($null, [object[]]@($true))
$rawStderr = 'FFmpeg 合并片段失败：' + ('raw stderr detail ' * 100)
$safeSaveFailureText = [string]$saveFailure.Invoke($null, [object[]]@($rawStderr))
$diskFailureText = '磁盘空间不足。'
$preservedDiskFailureText = [string]$saveFailure.Invoke($null, [object[]]@($diskFailureText))

$checks = [ordered]@{
    StartupFallbackNamesBothBackends = $startupFallbackText.Contains('DDA') -and $startupFallbackText.Contains('GDI')
    RuntimeFallbackExplainsContinuedRecording = $runtimeFallbackText.Contains('继续录制') -and $runtimeFallbackText.Contains('缓存')
    SaveFailureDoesNotExposeFfmpegStderr = -not $safeSaveFailureText.Contains('raw stderr detail')
    SaveFailureSuggestsUsefulChecks = $safeSaveFailureText.Contains('磁盘空间') -and $safeSaveFailureText.Contains('诊断日志')
    DiskFailureRemainsActionable = $preservedDiskFailureText -eq $diskFailureText
}
$checks.GetEnumerator() | ForEach-Object { '{0}: {1}' -f $_.Key, $_.Value }
if ($checks.Values -contains $false) { exit 1 }
