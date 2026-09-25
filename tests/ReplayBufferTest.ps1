param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$instanceFlags = [Reflection.BindingFlags]'Instance,NonPublic'
$bufferType = $assembly.GetType('BoltSnip.ReplayBuffer', $true)
$segmentType = $assembly.GetType('BoltSnip.ReplaySegment', $true)
$bufferConstructor = $bufferType.GetConstructor($instanceFlags, $null, [Type[]]@([string],[TimeSpan]), $null)
$segmentConstructor = $segmentType.GetConstructor($instanceFlags, $null, [Type[]]@([int],[string],[double]), $null)
$addSegment = $bufferType.GetMethod('AddSegment', $instanceFlags)
$acquireSnapshot = $bufferType.GetMethod('AcquireSnapshot', $instanceFlags)
$disposeBufferMethod = $bufferType.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
$segmentCount = $bufferType.GetProperty('SegmentCount', $instanceFlags)
$duration = $bufferType.GetProperty('CurrentDurationSeconds', $instanceFlags)
$snapshotType = $assembly.GetType('BoltSnip.ReplayBufferSnapshot', $true)
$snapshotSegments = $snapshotType.GetProperty('Segments', $instanceFlags)
$snapshotDispose = $snapshotType.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
$segmentIndex = $segmentType.GetProperty('Index', $instanceFlags)

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('BoltSnip-ReplayBuffer-' + [Guid]::NewGuid().ToString('N'))
$cacheDirectory = Join-Path $testRoot 'cache'
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$previousLogPath = [Environment]::GetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', 'Process')
[Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', (Join-Path $testRoot 'diagnostic.log'), 'Process')
[IO.Directory]::CreateDirectory($cacheDirectory) | Out-Null
$bufferArguments = New-Object 'object[]' 2
$bufferArguments[0] = $cacheDirectory.PSObject.BaseObject
$bufferArguments[1] = [TimeSpan]::FromSeconds(5)
$buffer = $null
$snapshot = $null
try {
    $buffer = $bufferConstructor.Invoke($bufferArguments)
    for ($index = 0; $index -lt 4; $index++) {
        $segmentPath = Join-Path $cacheDirectory ('segment_{0:D8}.mp4' -f $index)
        [IO.File]::WriteAllBytes($segmentPath, [byte[]]@(1,2,3))
        $segmentArguments = New-Object 'object[]' 3
        $segmentArguments[0] = [int]$index
        $segmentArguments[1] = $segmentPath.PSObject.BaseObject
        $segmentArguments[2] = [double]2
        $segment = $segmentConstructor.Invoke($segmentArguments)
        [void]$addSegment.Invoke($buffer, @($segment))
    }

    $boundedAfterFour = $segmentCount.GetValue($buffer, $null) -eq 2 -and
        [Math]::Abs(([double]$duration.GetValue($buffer, $null)) - 4) -lt 0.001 -and
        -not [IO.File]::Exists((Join-Path $cacheDirectory 'segment_00000000.mp4')) -and
        -not [IO.File]::Exists((Join-Path $cacheDirectory 'segment_00000001.mp4'))

    $snapshot = $acquireSnapshot.Invoke($buffer, $null)
    $snapshotItems = $snapshotSegments.GetValue($snapshot, $null)
    $snapshotIndexes = @($snapshotItems | ForEach-Object { $segmentIndex.GetValue($_, $null) })

    foreach ($index in 4,5) {
        $segmentPath = Join-Path $cacheDirectory ('segment_{0:D8}.mp4' -f $index)
        [IO.File]::WriteAllBytes($segmentPath, [byte[]]@(1,2,3))
        $segmentArguments = New-Object 'object[]' 3
        $segmentArguments[0] = [int]$index
        $segmentArguments[1] = $segmentPath.PSObject.BaseObject
        $segmentArguments[2] = [double]2
        $segment = $segmentConstructor.Invoke($segmentArguments)
        [void]$addSegment.Invoke($buffer, @($segment))
    }

    $leasedFilesSurviveTrim = [IO.File]::Exists((Join-Path $cacheDirectory 'segment_00000002.mp4')) -and
        [IO.File]::Exists((Join-Path $cacheDirectory 'segment_00000003.mp4'))
    [void]$snapshotDispose.Invoke($snapshot, $null)
    $snapshot = $null
    $leasedFilesReleased = -not [IO.File]::Exists((Join-Path $cacheDirectory 'segment_00000002.mp4')) -and
        -not [IO.File]::Exists((Join-Path $cacheDirectory 'segment_00000003.mp4'))

    [void]$disposeBufferMethod.Invoke($buffer, $null)
    $buffer = $null
    $cacheRemovedOnDispose = -not [IO.Directory]::Exists($cacheDirectory)

    $disposeCacheDirectory = Join-Path $testRoot 'dispose-cache'
    [IO.Directory]::CreateDirectory($disposeCacheDirectory) | Out-Null
    $disposeBufferArguments = New-Object 'object[]' 2
    $disposeBufferArguments[0] = $disposeCacheDirectory.PSObject.BaseObject
    $disposeBufferArguments[1] = [TimeSpan]::FromSeconds(5)
    $lifecycleBuffer = $bufferConstructor.Invoke($disposeBufferArguments)
    $leasedPath = Join-Path $disposeCacheDirectory 'segment_00000010.mp4'
    [IO.File]::WriteAllBytes($leasedPath, [byte[]]@(1,2,3))
    $leasedSegmentArguments = New-Object 'object[]' 3
    $leasedSegmentArguments[0] = [int]10
    $leasedSegmentArguments[1] = $leasedPath.PSObject.BaseObject
    $leasedSegmentArguments[2] = [double]2
    $leasedSegment = $segmentConstructor.Invoke($leasedSegmentArguments)
    [void]$addSegment.Invoke($lifecycleBuffer, @($leasedSegment))
    $disposeSnapshot = $acquireSnapshot.Invoke($lifecycleBuffer, $null)
    [void]$disposeBufferMethod.Invoke($lifecycleBuffer, $null)
    $leasedFilesSurviveBufferDispose = [IO.Directory]::Exists($disposeCacheDirectory) -and
        [IO.File]::Exists($leasedPath)
    [void]$snapshotDispose.Invoke($disposeSnapshot, $null)
    $disposeSnapshot = $null
    $leasedFilesDeletedAfterSnapshotDispose = -not [IO.Directory]::Exists($disposeCacheDirectory) -and
        -not [IO.File]::Exists($leasedPath)

    $passed = $boundedAfterFour -and
        ($snapshotIndexes -join ',') -eq '2,3' -and
        $leasedFilesSurviveTrim -and $leasedFilesReleased -and $cacheRemovedOnDispose -and
        $leasedFilesSurviveBufferDispose -and $leasedFilesDeletedAfterSnapshotDispose

    [pscustomobject]@{
        RingDurationBounded = $boundedAfterFour
        SnapshotIndexes = $snapshotIndexes -join ','
        SnapshotFilesLeasedDuringSave = $leasedFilesSurviveTrim
        SnapshotFilesDeletedAfterSave = $leasedFilesReleased
        CacheDeletedOnDisable = $cacheRemovedOnDispose
        SnapshotFilesSurviveBufferDispose = $leasedFilesSurviveBufferDispose
        CacheDeletedAfterSnapshotRelease = $leasedFilesDeletedAfterSnapshotDispose
        Passed = $passed
    } | Format-List
    if (-not $passed) { exit 1 }
}
finally {
    if ($null -ne $snapshot) { [void]$snapshotDispose.Invoke($snapshot, $null) }
    if ($null -ne $buffer) { [void]$disposeBufferMethod.Invoke($buffer, $null) }
    if ($null -ne $disposeSnapshot) { [void]$snapshotDispose.Invoke($disposeSnapshot, $null) }
    if ($null -ne $lifecycleBuffer) { [void]$disposeBufferMethod.Invoke($lifecycleBuffer, $null) }
    if ($previousLogPath) {
        [Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $previousLogPath, 'Process')
    }
    else {
        [Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $null, 'Process')
    }
    if ([IO.Directory]::Exists($testRoot)) { [IO.Directory]::Delete($testRoot, $true) }
}
