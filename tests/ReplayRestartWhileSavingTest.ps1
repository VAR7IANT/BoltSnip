param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$flags = [Reflection.BindingFlags]'Instance,NonPublic'
$publicInstanceFlags = [Reflection.BindingFlags]'Instance,Public'
$managerType = $assembly.GetType('BoltSnip.ReplayManager', $true)
$bufferType = $assembly.GetType('BoltSnip.ReplayBuffer', $true)
$segmentType = $assembly.GetType('BoltSnip.ReplaySegment', $true)
$snapshotType = $assembly.GetType('BoltSnip.ReplayBufferSnapshot', $true)
$manager = $null
$buffer = $null
$snapshot = $null

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('BoltSnip-ReplayRestart-' + [Guid]::NewGuid().ToString('N'))
$cacheRoot = Join-Path ([IO.Path]::GetTempPath()) 'BoltSnip\replay-cache'
$cacheDirectory = Join-Path $cacheRoot ([Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
[IO.Directory]::CreateDirectory($cacheDirectory) | Out-Null
$previousFfmpegPath = [Environment]::GetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', 'Process')
$previousLogPath = [Environment]::GetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', 'Process')
[Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', (Join-Path $testRoot 'diagnostic.log'), 'Process')

try {
    $bufferConstructor = $bufferType.GetConstructor($flags, $null, [Type[]]@([string],[TimeSpan]), $null)
    $segmentConstructor = $segmentType.GetConstructor($flags, $null, [Type[]]@([int],[string],[double]), $null)
    $addSegment = $bufferType.GetMethod('AddSegment', $flags)
    $acquireSnapshot = $bufferType.GetMethod('AcquireSnapshot', $flags)
    $disposeBuffer = $bufferType.GetMethod('Dispose', $publicInstanceFlags)
    $snapshotDispose = $snapshotType.GetMethod('Dispose', $publicInstanceFlags)
    $snapshotSegments = $snapshotType.GetProperty('Segments', $flags)
    $bufferField = $managerType.GetField('_buffer', $flags)

    $cachePathArgument = [string]$cacheDirectory
    $buffer = $bufferConstructor.Invoke([object[]]@($cachePathArgument, [TimeSpan]::FromSeconds(5)))
    $segmentPath = Join-Path $cacheDirectory 'segment_00000000.mp4'
    [IO.File]::WriteAllBytes($segmentPath, [byte[]]@(1,2,3,4))
    $segment = $segmentConstructor.Invoke([object[]]@([int]0, [string]$segmentPath, [double]2))
    [void]$addSegment.Invoke($buffer, @($segment))
    $snapshot = $acquireSnapshot.Invoke($buffer, $null)
    [void]$disposeBuffer.Invoke($buffer, $null)

    $manager = [Activator]::CreateInstance($managerType, $true)
    $stateField = $managerType.GetField('_state', $flags)
    $isSavingField = $managerType.GetField('_isSaving', $flags)
    $recordingThreadField = $managerType.GetField('_recordingThread', $flags)
    $start = $managerType.GetMethod('Start', $flags)
    $stop = $managerType.GetMethod('Stop', $flags)
    $stateProperty = $managerType.GetProperty('State', $flags)
    $isSavingProperty = $managerType.GetProperty('IsSaving', $flags)
    $lastErrorProperty = $managerType.GetProperty('LastError', $flags)
    $tryDequeue = $managerType.GetMethod('TryDequeueNotification', $flags)
    $notificationType = $assembly.GetType('BoltSnip.ReplayNotification', $true)
    $notificationMessage = $notificationType.GetProperty('Message', $flags)

    $bufferField.SetValue($manager, $buffer)
    $stateField.SetValue($manager, [Enum]::Parse($stateField.FieldType, 'Recording'))
    $isSavingField.SetValue($manager, $true)
    [void]$stop.Invoke($manager, $null)
    $notificationArguments = New-Object 'object[]' 1
    $stopNotice = $null
    if ($tryDequeue.Invoke($manager, $notificationArguments)) {
        $stopNotice = [string]$notificationMessage.GetValue($notificationArguments[0], $null)
    }
    $stopCompleted = $stateProperty.GetValue($manager, $null).ToString() -eq 'Disabled' -and
        $stopNotice -eq '正在关闭即时回放…'
    [void]$start.Invoke($manager, $null)

    $notificationArguments = New-Object 'object[]' 1
    $blockedNotice = $null
    if ($tryDequeue.Invoke($manager, $notificationArguments)) {
        $blockedNotice = [string]$notificationMessage.GetValue($notificationArguments[0], $null)
    }
    $startWasBlocked = $stopCompleted -and $stateProperty.GetValue($manager, $null).ToString() -eq 'Disabled' -and
        [bool]$isSavingProperty.GetValue($manager, $null) -and
        $null -eq $recordingThreadField.GetValue($manager) -and
        $blockedNotice -eq '上一段即时回放仍在保存，请等待保存完成后再重新开启。'
    $oldCacheSurvivedBlockedStart = [IO.Directory]::Exists($cacheDirectory) -and
        [IO.File]::Exists($segmentPath) -and $snapshotSegments.GetValue($snapshot, $null).Length -eq 1

    $stateField.SetValue($manager, [Enum]::Parse($stateField.FieldType, 'Error'))
    [void]$start.Invoke($manager, $null)
    $notificationArguments = New-Object 'object[]' 1
    $errorStateNotice = $null
    if ($tryDequeue.Invoke($manager, $notificationArguments)) {
        $errorStateNotice = [string]$notificationMessage.GetValue($notificationArguments[0], $null)
    }
    $errorStateStartWasBlocked = $stateProperty.GetValue($manager, $null).ToString() -eq 'Error' -and
        [bool]$isSavingProperty.GetValue($manager, $null) -and
        $null -eq $recordingThreadField.GetValue($manager) -and
        $errorStateNotice -eq '上一段即时回放仍在保存，请等待保存完成后再重新开启。'

    $missingFfmpegPath = Join-Path $testRoot 'ffmpeg-does-not-exist.exe'
    [Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $missingFfmpegPath, 'Process')
    $isSavingField.SetValue($manager, $false)
    $stateField.SetValue($manager, [Enum]::Parse($stateField.FieldType, 'Disabled'))
    $notificationArguments = New-Object 'object[]' 1
    [void]$start.Invoke($manager, $null)
    $restartNotice = $null
    if ($tryDequeue.Invoke($manager, $notificationArguments)) {
        $restartNotice = [string]$notificationMessage.GetValue($notificationArguments[0], $null)
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline -and
        $stateProperty.GetValue($manager, $null).ToString() -notin @('Error','Recording')) {
        Start-Sleep -Milliseconds 25
    }
    $restartAcceptedAfterSave = $restartNotice -eq '正在开启即时回放…' -and
        $stateProperty.GetValue($manager, $null).ToString() -eq 'Error' -and
        ([string]$lastErrorProperty.GetValue($manager, $null)).Contains('BOLTSNIP_FFMPEG_PATH')
    $oldCacheSurvivedNewSession = [IO.Directory]::Exists($cacheDirectory) -and
        [IO.File]::Exists($segmentPath)

    [void]$snapshotDispose.Invoke($snapshot, $null)
    $snapshot = $null
    $oldCacheRemovedAfterSave = -not [IO.Directory]::Exists($cacheDirectory)
    $passed = $startWasBlocked -and $errorStateStartWasBlocked -and $oldCacheSurvivedBlockedStart -and
        $restartAcceptedAfterSave -and $oldCacheSurvivedNewSession -and $oldCacheRemovedAfterSave

    [pscustomobject]@{
        ImmediateStartRejectedWhileSaving = $startWasBlocked
        StopCompletedWhileSnapshotWasLeased = $stopCompleted
        ErrorStateStartRejectedWhileSaving = $errorStateStartWasBlocked
        Notification = $blockedNotice
        LeasedCacheSurvivedBlockedStart = $oldCacheSurvivedBlockedStart
        RestartAcceptedAfterSaveCompletion = $restartAcceptedAfterSave
        LeasedCacheSurvivedNewSession = $oldCacheSurvivedNewSession
        LeasedCacheRemovedAfterSnapshotRelease = $oldCacheRemovedAfterSave
        Passed = $passed
    } | Format-List
    if (-not $passed) { exit 1 }
}
finally {
    if ($null -ne $snapshot) { [void]$snapshotType.GetMethod('Dispose', $publicInstanceFlags).Invoke($snapshot, $null) }
    if ($null -ne $buffer) { [void]$bufferType.GetMethod('Dispose', $publicInstanceFlags).Invoke($buffer, $null) }
    if ($null -ne $manager) { [void]$managerType.GetMethod('Dispose', $publicInstanceFlags).Invoke($manager, $null) }
    if ($previousFfmpegPath) {
        [Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $previousFfmpegPath, 'Process')
    } else {
        [Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $null, 'Process')
    }
    if ($previousLogPath) {
        [Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $previousLogPath, 'Process')
    } else {
        [Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $null, 'Process')
    }
    if ([IO.Directory]::Exists($testRoot)) { [IO.Directory]::Delete($testRoot, $true) }
}
