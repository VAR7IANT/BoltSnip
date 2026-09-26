param(
    [Parameter(Mandatory = $true)]
    [int]$BoltSnipProcessId,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedBoltSnipPath,
    [Parameter(Mandatory = $true)]
    [string]$FfmpegPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputCsv,
    [string]$ReplayCacheRoot = (Join-Path ([IO.Path]::GetTempPath()) 'BoltSnip\replay-cache'),
    [int]$DurationSeconds = 60,
    [int]$IntervalMilliseconds = 1000
)

$ErrorActionPreference = 'Stop'
if ($DurationSeconds -lt 1) { throw 'DurationSeconds must be positive.' }
if ($IntervalMilliseconds -lt 100) { throw 'IntervalMilliseconds must be at least 100.' }

$expectedAppPath = [IO.Path]::GetFullPath($ExpectedBoltSnipPath)
$ffmpegFullPath = [IO.Path]::GetFullPath($FfmpegPath)
$outputFullPath = [IO.Path]::GetFullPath($OutputCsv)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFullPath)) | Out-Null

$app = Get-Process -Id $BoltSnipProcessId -ErrorAction Stop
if ($app.ProcessName -ne 'BoltSnip' -or
    -not [string]::Equals([IO.Path]::GetFullPath($app.Path), $expectedAppPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw "PID $BoltSnipProcessId is not the requested BoltSnip executable: $($app.Path)"
}

$nvidiaSmi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
$processorCount = [Math]::Max(1, [Environment]::ProcessorCount)
$rows = New-Object 'System.Collections.Generic.List[object]'
$previousAppCpu = $null
$previousFfmpegCpu = $null
$previousSampleTime = [DateTime]::UtcNow
$stopwatch = [Diagnostics.Stopwatch]::StartNew()

while ($stopwatch.Elapsed.TotalSeconds -lt $DurationSeconds) {
    $sampleTime = [DateTime]::UtcNow
    $elapsedSeconds = [Math]::Max(0.001, ($sampleTime - $previousSampleTime).TotalSeconds)
    $appCpuSeconds = 0.0
    $appWorkingSetMb = $null
    $appPrivateMb = $null
    try {
        $app.Refresh()
        if (-not $app.HasExited) {
            $appCpuSeconds = $app.CPU
            $appWorkingSetMb = [Math]::Round($app.WorkingSet64 / 1MB, 2)
            $appPrivateMb = [Math]::Round($app.PrivateMemorySize64 / 1MB, 2)
        }
    } catch { }

    $ffmpegProcesses = @(Get-Process -Name 'ffmpeg' -ErrorAction SilentlyContinue | Where-Object {
        try { [string]::Equals([IO.Path]::GetFullPath($_.Path), $ffmpegFullPath, [StringComparison]::OrdinalIgnoreCase) }
        catch { $false }
    })
    $ffmpegCpuSeconds = 0.0
    $ffmpegWorkingSetMb = 0.0
    $ffmpegPrivateMb = 0.0
    foreach ($process in $ffmpegProcesses) {
        try {
            $process.Refresh()
            if (-not $process.HasExited) {
                $ffmpegCpuSeconds += $process.CPU
                $ffmpegWorkingSetMb += $process.WorkingSet64 / 1MB
                $ffmpegPrivateMb += $process.PrivateMemorySize64 / 1MB
            }
        } catch { }
    }

    $appCpuPercent = $null
    if ($null -ne $previousAppCpu -and $null -ne $appWorkingSetMb) {
        $appCpuPercent = [Math]::Round([Math]::Max(0, ($appCpuSeconds - $previousAppCpu) / $elapsedSeconds / $processorCount * 100), 2)
    }
    $ffmpegCpuPercent = $null
    if ($null -ne $previousFfmpegCpu -and $ffmpegProcesses.Count -gt 0) {
        $ffmpegCpuPercent = [Math]::Round([Math]::Max(0, ($ffmpegCpuSeconds - $previousFfmpegCpu) / $elapsedSeconds / $processorCount * 100), 2)
    }

    $gpuUtilization = $null
    $gpuMemoryMb = $null
    $nvencUtilization = $null
    if ($null -ne $nvidiaSmi) {
        $gpuValues = @(& $nvidiaSmi.Source '--query-gpu=utilization.gpu,memory.used,utilization.encoder' '--format=csv,noheader,nounits' 2>$null)
        if ($LASTEXITCODE -eq 0 -and $gpuValues.Count -gt 0) {
            $parts = ([string]$gpuValues[0]) -split ','
            if ($parts.Count -ge 3) {
                $number = 0.0
                if ([double]::TryParse($parts[0].Trim(), [ref]$number)) { $gpuUtilization = $number }
                if ([double]::TryParse($parts[1].Trim(), [ref]$number)) { $gpuMemoryMb = $number }
                if ([double]::TryParse($parts[2].Trim(), [ref]$number)) { $nvencUtilization = $number }
            }
        }
    }

    $segmentCount = 0
    $cacheMb = 0.0
    if (Test-Path -LiteralPath $ReplayCacheRoot) {
        $session = Get-ChildItem -LiteralPath $ReplayCacheRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($null -ne $session) {
            $segments = @(Get-ChildItem -LiteralPath $session.FullName -Filter 'segment_*.mp4' -File -ErrorAction SilentlyContinue)
            $segmentCount = $segments.Count
            foreach ($segment in $segments) { $cacheMb += $segment.Length / 1MB }
        }
    }

    $rows.Add([pscustomobject]@{
        Utc = $sampleTime.ToString('O')
        ElapsedSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
        BoltSnipProcessId = $BoltSnipProcessId
        BoltSnipCpuPercent = $appCpuPercent
        BoltSnipCpuSeconds = [Math]::Round($appCpuSeconds, 3)
        BoltSnipWorkingSetMb = $appWorkingSetMb
        BoltSnipPrivateBytesMb = $appPrivateMb
        FfmpegProcessCount = $ffmpegProcesses.Count
        FfmpegCpuPercent = $ffmpegCpuPercent
        FfmpegCpuSeconds = [Math]::Round($ffmpegCpuSeconds, 3)
        FfmpegWorkingSetMb = [Math]::Round($ffmpegWorkingSetMb, 2)
        FfmpegPrivateBytesMb = [Math]::Round($ffmpegPrivateMb, 2)
        GpuUtilizationPercent = $gpuUtilization
        GpuMemoryUsedMb = $gpuMemoryMb
        NvencUtilizationPercent = $nvencUtilization
        BufferedSegmentFiles = $segmentCount
        CacheSizeMb = [Math]::Round($cacheMb, 2)
    })

    if ($null -ne $appWorkingSetMb) { $previousAppCpu = $appCpuSeconds }
    if ($ffmpegProcesses.Count -gt 0) { $previousFfmpegCpu = $ffmpegCpuSeconds }
    $previousSampleTime = $sampleTime
    Start-Sleep -Milliseconds $IntervalMilliseconds
}

$rows | Export-Csv -LiteralPath $outputFullPath -NoTypeInformation -Encoding UTF8
$summary = [ordered]@{
    BoltSnipProcessId = $BoltSnipProcessId
    BoltSnipPath = $expectedAppPath
    FfmpegPath = $ffmpegFullPath
    RequestedDurationSeconds = $DurationSeconds
    SampleCount = $rows.Count
    CpuMetric = 'Percent of total logical processor capacity, derived from process CPU-time deltas'
    GpuMetric = 'Device-wide NVIDIA GPU, VRAM, and NVENC values from nvidia-smi'
    BoltSnipCpuPercentAverage = ($rows | Measure-Object -Property BoltSnipCpuPercent -Average).Average
    BoltSnipCpuPercentMaximum = ($rows | Measure-Object -Property BoltSnipCpuPercent -Maximum).Maximum
    BoltSnipWorkingSetMbAverage = ($rows | Measure-Object -Property BoltSnipWorkingSetMb -Average).Average
    BoltSnipWorkingSetMbMaximum = ($rows | Measure-Object -Property BoltSnipWorkingSetMb -Maximum).Maximum
    BoltSnipPrivateBytesMbAverage = ($rows | Measure-Object -Property BoltSnipPrivateBytesMb -Average).Average
    BoltSnipPrivateBytesMbMaximum = ($rows | Measure-Object -Property BoltSnipPrivateBytesMb -Maximum).Maximum
    FfmpegCpuPercentAverage = ($rows | Measure-Object -Property FfmpegCpuPercent -Average).Average
    FfmpegCpuPercentMaximum = ($rows | Measure-Object -Property FfmpegCpuPercent -Maximum).Maximum
    FfmpegWorkingSetMbAverage = ($rows | Measure-Object -Property FfmpegWorkingSetMb -Average).Average
    FfmpegWorkingSetMbMaximum = ($rows | Measure-Object -Property FfmpegWorkingSetMb -Maximum).Maximum
    FfmpegPrivateBytesMbAverage = ($rows | Measure-Object -Property FfmpegPrivateBytesMb -Average).Average
    FfmpegPrivateBytesMbMaximum = ($rows | Measure-Object -Property FfmpegPrivateBytesMb -Maximum).Maximum
    GpuUtilizationPercentAverage = ($rows | Measure-Object -Property GpuUtilizationPercent -Average).Average
    GpuUtilizationPercentMaximum = ($rows | Measure-Object -Property GpuUtilizationPercent -Maximum).Maximum
    GpuMemoryUsedMbAverage = ($rows | Measure-Object -Property GpuMemoryUsedMb -Average).Average
    GpuMemoryUsedMbMaximum = ($rows | Measure-Object -Property GpuMemoryUsedMb -Maximum).Maximum
    NvencUtilizationPercentAverage = ($rows | Measure-Object -Property NvencUtilizationPercent -Average).Average
    NvencUtilizationPercentMaximum = ($rows | Measure-Object -Property NvencUtilizationPercent -Maximum).Maximum
    BufferedSegmentFilesMaximum = ($rows | Measure-Object -Property BufferedSegmentFiles -Maximum).Maximum
    CacheSizeMbMaximum = ($rows | Measure-Object -Property CacheSizeMb -Maximum).Maximum
}
$summaryPath = [IO.Path]::ChangeExtension($outputFullPath, '.summary.json')
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | Format-List
Write-Output "Samples=$outputFullPath"
