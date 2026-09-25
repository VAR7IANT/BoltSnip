param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$instanceFlags = [Reflection.BindingFlags]'Instance,NonPublic'
$encoderType = $assembly.GetType('BoltSnip.ReplayEncoder', $true)
$encoder = [Activator]::CreateInstance($encoderType, $true)
$listPathField = $encoderType.GetField('_segmentListPath', $instanceFlags)
$readSegments = $encoderType.GetMethod('ReadCompletedSegments', $instanceFlags)
$segmentType = $assembly.GetType('BoltSnip.ReplaySegment', $true)
$segmentIndex = $segmentType.GetProperty('Index', $instanceFlags)
$segmentDuration = $segmentType.GetProperty('DurationSeconds', $instanceFlags)

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('BoltSnip-Replay,Segments-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
try {
    $firstPath = Join-Path $testRoot 'segment_00000003.mp4'
    $secondPath = Join-Path $testRoot 'segment_00000004.mp4'
    [IO.File]::WriteAllBytes($firstPath, [byte[]]@(1,2,3))
    [IO.File]::WriteAllBytes($secondPath, [byte[]]@(1,2,3))
    $csv = '"' + $firstPath.Replace('"','""') + '",0.000000,2.000000' + [Environment]::NewLine +
        '"' + $secondPath.Replace('"','""') + '",0.000000,1.500000'
    $listPath = Join-Path $testRoot 'segments.csv'
    [IO.File]::WriteAllText($listPath, $csv, [Text.UTF8Encoding]::new($false))
    $listPathField.SetValue($encoder, $listPath)

    $parsed = $readSegments.Invoke($encoder, @([int]2))
    $count = $parsed.Count
    $first = $parsed[0]
    $second = $parsed[1]
    $passed = $count -eq 2 -and
        $segmentIndex.GetValue($first, $null) -eq 3 -and
        [Math]::Abs(([double]$segmentDuration.GetValue($first, $null)) - 2) -lt 0.001 -and
        $segmentIndex.GetValue($second, $null) -eq 4 -and
        [Math]::Abs(([double]$segmentDuration.GetValue($second, $null)) - 1.5) -lt 0.001

    [pscustomobject]@{
        CommaInCachePathParsed = $count -eq 2
        SegmentOrder = if ($count -eq 2) { "$($segmentIndex.GetValue($first, $null)),$($segmentIndex.GetValue($second, $null))" } else { 'invalid' }
        DurationsParsed = $passed
        Passed = $passed
    } | Format-List
    if (-not $passed) { exit 1 }
}
finally {
    if ([IO.Directory]::Exists($testRoot)) { [IO.Directory]::Delete($testRoot, $true) }
}
