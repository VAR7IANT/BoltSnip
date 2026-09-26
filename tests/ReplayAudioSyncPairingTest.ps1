$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ReplayAudioSyncPairing.ps1')

$ordered = Get-SyncMeasurements -Visual ([double[]]@(1, 3, 5)) -Audio ([double[]]@(1.09, 3.11, 5.12))
$orderedPairingPassed = $ordered.VisualMarkers -eq 3 -and $ordered.AudioMarkers -eq 3 -and
    $ordered.MatchedEvents -eq 3 -and $ordered.UnmatchedVisualEvents -eq 0 -and
    $ordered.UnmatchedAudioEvents -eq 0 -and $ordered.MedianOffsetMs -eq -110 -and
    $ordered.MaxOffsetMs -eq 120

$singleAudio = Get-SyncMeasurements -Visual ([double[]]@(1.0, 1.09)) -Audio ([double[]]@(1.04))
$markerIsUsedOnce = $singleAudio.MatchedEvents -eq 1 -and
    $singleAudio.UnmatchedVisualEvents -eq 1 -and $singleAudio.UnmatchedAudioEvents -eq 0

$extraAudio = Get-SyncMeasurements -Visual ([double[]]@(1, 3, 5)) -Audio ([double[]]@(0.8, 1.02, 3.04, 4.5, 5.01))
$extraAudioReported = $extraAudio.MatchedEvents -eq 3 -and
    $extraAudio.UnmatchedVisualEvents -eq 0 -and $extraAudio.UnmatchedAudioEvents -eq 2 -and
    $extraAudio.UnmatchedAudioSeconds.Count -eq 2

$missingMarkers = Get-SyncMeasurements -Visual ([double[]]@(1, 3, 5)) -Audio ([double[]]@(1.02, 3.03, 8))
$missingMarkersReported = $missingMarkers.MatchedEvents -eq 2 -and
    $missingMarkers.UnmatchedVisualEvents -eq 1 -and $missingMarkers.UnmatchedAudioEvents -eq 1 -and
    $missingMarkers.UnmatchedVisualSeconds.Count -eq 1 -and $missingMarkers.UnmatchedAudioSeconds.Count -eq 1

$monotonic = Get-SyncMeasurements -Visual ([double[]]@(1, 1.2)) -Audio ([double[]]@(1.19, 1.21))
$eventOrderPreserved = $monotonic.MatchedEvents -eq 2 -and
    $monotonic.EventMeasurements[0].VisualSeconds -lt $monotonic.EventMeasurements[1].VisualSeconds -and
    $monotonic.EventMeasurements[0].AudioSeconds -lt $monotonic.EventMeasurements[1].AudioSeconds

$outsideWindow = Get-SyncMeasurements -Visual ([double[]]@(1)) -Audio ([double[]]@(1.5))
$thresholdApplied = $outsideWindow.MatchedEvents -eq 0 -and
    $outsideWindow.UnmatchedVisualEvents -eq 1 -and $outsideWindow.UnmatchedAudioEvents -eq 1

[pscustomobject]@{
    MonotonicPairing = $orderedPairingPassed
    OneAudioMarkerCannotBeReused = $markerIsUsedOnce
    ExtraAudioMarkersAreReported = $extraAudioReported
    MissingMarkersAreReported = $missingMarkersReported
    PairOrderIsPreserved = $eventOrderPreserved
    PairingWindowIsEnforced = $thresholdApplied
    Passed = $orderedPairingPassed -and $markerIsUsedOnce -and $extraAudioReported -and
        $missingMarkersReported -and $eventOrderPreserved -and $thresholdApplied
} | Format-List

if (-not ($orderedPairingPassed -and $markerIsUsedOnce -and $extraAudioReported -and
    $missingMarkersReported -and $eventOrderPreserved -and $thresholdApplied)) { exit 1 }
