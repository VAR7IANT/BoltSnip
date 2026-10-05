param(
    [string]$Executable,
    [string]$Ffmpeg,
    [string]$Sample,
    [string]$WorkDirectory
)
$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$instance = [Reflection.BindingFlags]'Instance,NonPublic'
$publicInstance = [Reflection.BindingFlags]'Instance,Public'
$managerType = $assembly.GetType('BoltSnip.ReplayManager', $true)
$bufferType = $assembly.GetType('BoltSnip.ReplayBuffer', $true)
$segmentType = $assembly.GetType('BoltSnip.ReplaySegment', $true)
$saverType = $assembly.GetType('BoltSnip.ReplaySaver', $true)
$saveLoop = $managerType.GetMethod('SaveLoop', $instance)
$dequeue = $managerType.GetMethod('TryDequeueNotification', $instance)
$bufferCtor = $bufferType.GetConstructor($instance, $null, [Type[]]@([string],[TimeSpan]), $null)
$segmentCtor = $segmentType.GetConstructor($instance, $null, [Type[]]@([int],[string],[double]), $null)
$previousOutput = $env:BOLTSNIP_REPLAY_OUTPUT_DIRECTORY
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
try {
    New-Item -ItemType Directory -Path $WorkDirectory -Force | Out-Null
    $env:TEMP = $WorkDirectory
    $env:TMP = $WorkDirectory
    foreach ($mode in 'success','failure') {
        $runDirectory = Join-Path $WorkDirectory ($mode + '-' + [Guid]::NewGuid().ToString('N'))
        $cache = Join-Path $runDirectory 'cache'
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        $env:BOLTSNIP_REPLAY_OUTPUT_DIRECTORY = Join-Path $runDirectory 'output'
        $inputPath = Join-Path $cache 'segment_00000000.mp4'
        Copy-Item -LiteralPath $Sample -Destination $inputPath
        $buffer = $bufferCtor.Invoke([object[]]@([string]$cache,[TimeSpan]::FromSeconds(300)))
        $segment = $segmentCtor.Invoke([object[]]@([int]0,[string]$inputPath,[double]2))
        [void]$bufferType.GetMethod('AddSegment',$instance).Invoke($buffer,[object[]]@($segment))
        $manager = [Activator]::CreateInstance($managerType,$true)
        $saver = [Activator]::CreateInstance($saverType,$true)
        try {
            $encoderPath = if ($mode -eq 'success') { $Ffmpeg } else { Join-Path $runDirectory 'missing-ffmpeg.exe' }
            [void]$saveLoop.Invoke($manager,[object[]]@($buffer,$saver,[string]$encoderPath,[int]-1))
            $notificationArgument = [object[]]@($null)
            if (-not $dequeue.Invoke($manager,$notificationArgument)) { throw 'No save notification emitted' }
            $notification = $notificationArgument[0]
            $kind = $notification.GetType().GetProperty('Kind',$instance).GetValue($notification,$null).ToString()
            $errorFlag = $notification.GetType().GetProperty('IsError',$instance).GetValue($notification,$null)
            if ($mode -eq 'success') {
                $finalFiles = @(Get-ChildItem $env:BOLTSNIP_REPLAY_OUTPUT_DIRECTORY -Filter '*.mp4' -File | Where-Object { $_.Name -notlike '*.partial.mp4' })
                if ($kind -ne 'SaveSucceeded' -or $errorFlag -or $finalFiles.Count -ne 1 -or $finalFiles[0].Length -eq 0) { throw 'Success feedback occurred without a finalized MP4' }
            } elseif ($kind -ne 'General' -or -not $errorFlag) { throw 'Failed save incorrectly emitted success feedback' }
            if ($dequeue.Invoke($manager,[object[]]@($null))) { throw 'Duplicate save feedback emitted' }
            Write-Output ('PASS: ' + $mode + ' save kind=' + $kind + ', error=' + $errorFlag)
        } finally {
            [void]$managerType.GetMethod('Dispose',$publicInstance).Invoke($manager,$null)
            [void]$bufferType.GetMethod('Dispose',$publicInstance).Invoke($buffer,$null)
        }
    }
} finally {
    $env:BOLTSNIP_REPLAY_OUTPUT_DIRECTORY = $previousOutput
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
}