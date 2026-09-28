param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$saverType = $assembly.GetType('BoltSnip.ReplaySaver', $true)
$segmentType = $assembly.GetType('BoltSnip.ReplaySegment', $true)
$buildManifest = $saverType.GetMethod('BuildManifestText', [Reflection.BindingFlags]'Static,NonPublic')
if ($null -eq $buildManifest) { throw 'ReplaySaver.BuildManifestText is not present.' }
$segmentConstructor = $segmentType.GetConstructor(
    [Reflection.BindingFlags]'Instance,NonPublic',
    $null,
    [Type[]]@([int], [string], [double]),
    $null)
if ($null -eq $segmentConstructor) { throw 'ReplaySegment constructor is not present.' }

$oldCulture = [Threading.Thread]::CurrentThread.CurrentCulture
$testCulture = New-Object Globalization.CultureInfo('fr-FR')
try {
    [Threading.Thread]::CurrentThread.CurrentCulture = $testCulture
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('ReplaySaverTimeline-' + [Guid]::NewGuid().ToString('N'))
    $paths = @(
        [IO.Path]::GetFullPath((Join-Path $temp 'first segment.mp4')),
        [IO.Path]::GetFullPath((Join-Path $temp "second's segment.mp4")),
        [IO.Path]::GetFullPath((Join-Path $temp 'third-segment.mp4'))
    )
    $durations = [double[]]@(1.999833, 2.000167, 0.5)
    $segments = [Array]::CreateInstance($segmentType, $paths.Count)
    for ($index = 0; $index -lt $paths.Count; $index++) {
        $arguments = New-Object 'object[]' 3
        $arguments[0] = [int]$index
        $arguments[1] = [string]$paths[$index]
        $arguments[2] = [double]$durations[$index]
        $segments.SetValue($segmentConstructor.Invoke($arguments), $index)
    }

    $invokeArguments = New-Object 'object[]' 1
    $invokeArguments[0] = $segments
    $manifest = [string]$buildManifest.Invoke($null, $invokeArguments)
    $actual = @($manifest -split [regex]::Escape([Environment]::NewLine) | Where-Object { $_ -ne '' })
    $quoteEscape = [string]([char]39) + [char]92 + [char]39 + [char]39
    $escapedPaths = @($paths | ForEach-Object { $_.Replace([string][char]39, $quoteEscape) })
    $expected = @(
        'ffconcat version 1.0',
        "file '$($escapedPaths[0])'",
        'duration 1.999833',
        "file '$($escapedPaths[1])'",
        'duration 2.000167',
        "file '$($escapedPaths[2])'",
        'duration 0.5'
    )

    $headerCorrect = $actual.Count -gt 0 -and $actual[0] -eq 'ffconcat version 1.0'
    $allFilesIncluded = @($paths | ForEach-Object { $escapedPaths -contains $_.Replace([string][char]39, $quoteEscape) })
    $ordered = $actual.Count -eq $expected.Count
    if ($ordered) {
        for ($index = 0; $index -lt $expected.Count; $index++) {
            if ($actual[$index] -cne $expected[$index]) { $ordered = $false; break }
        }
    }
    $durationCount = @($actual | Where-Object { $_ -match '^duration ' }).Count
    $invariantDecimals = (@($actual | Where-Object { $_ -match '^duration \d+,\d+$' }).Count -eq 0)
    $fractionalTimeline = $actual -contains 'duration 1.999833' -and $actual -contains 'duration 2.000167'
    $quoteEscaping = $actual -contains "file '$($escapedPaths[1])'"

    $buildArguments = $saverType.GetMethod('BuildArguments', [Reflection.BindingFlags]'Static,NonPublic')
    $argumentsText = [string]$buildArguments.Invoke($null, [object[]]@('segments.ffconcat', 'output.mp4'))
    $streamCopyPreserved = $argumentsText.Contains('-c:v copy') -and $argumentsText.Contains('-c:a copy')

    $checks = [ordered]@{
        FfconcatHeader = $headerCorrect
        EverySegmentFileIncluded = ($allFilesIncluded.Count -eq 3 -and -not ($allFilesIncluded -contains $false))
        PerSegmentDurationDirective = $durationCount -eq 3
        DurationUsesReplaySegmentValues = $fractionalTimeline
        InvariantDecimalFormattingUnderFrCulture = $invariantDecimals
        QuoteEscapingPreserved = $quoteEscaping
        SegmentOrderPreserved = $ordered
        StreamCopyPreserved = $streamCopyPreserved
    }
    $checks.GetEnumerator() | ForEach-Object { '{0}: {1}' -f $_.Key, $_.Value }
    if ($checks.Values -contains $false) { exit 1 }
}
finally {
    [Threading.Thread]::CurrentThread.CurrentCulture = $oldCulture
}
