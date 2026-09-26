function Get-SyncMeasurements(
    [double[]]$Visual,
    [double[]]$Audio,
    [double]$MaximumPairingDistanceSeconds = 0.5)
{
    if ($MaximumPairingDistanceSeconds -le 0) {
        throw 'The marker pairing window must be greater than zero.'
    }

    $visualMarkers = @($Visual | ForEach-Object { [double]$_ } | Sort-Object)
    $audioMarkers = @($Audio | ForEach-Object { [double]$_ } | Sort-Object)
    $visualCount = $visualMarkers.Count
    $audioCount = $audioMarkers.Count
    $matchCounts = [int[,]]::new($visualCount + 1, $audioCount + 1)
    $matchCosts = [double[,]]::new($visualCount + 1, $audioCount + 1)
    $actions = [string[,]]::new($visualCount + 1, $audioCount + 1)
    $epsilon = 0.0000001

    for ($visualIndex = $visualCount; $visualIndex -ge 0; $visualIndex--) {
        for ($audioIndex = $audioCount; $audioIndex -ge 0; $audioIndex--) {
            if ($visualIndex -eq $visualCount -and $audioIndex -eq $audioCount) {
                continue
            }

            $bestCount = -1
            $bestCost = [double]::MaxValue
            $bestAction = ''

            if ($visualIndex -lt $visualCount) {
                $nextVisual = $visualIndex + 1
                $bestCount = $matchCounts[$nextVisual, $audioIndex]
                $bestCost = $matchCosts[$nextVisual, $audioIndex]
                $bestAction = 'V'
            }

            if ($audioIndex -lt $audioCount) {
                $nextAudio = $audioIndex + 1
                $candidateCount = $matchCounts[$visualIndex, $nextAudio]
                $candidateCost = $matchCosts[$visualIndex, $nextAudio]
                if ($candidateCount -gt $bestCount -or
                    ($candidateCount -eq $bestCount -and $candidateCost -lt ($bestCost - $epsilon))) {
                    $bestCount = $candidateCount
                    $bestCost = $candidateCost
                    $bestAction = 'A'
                }
            }

            if ($visualIndex -lt $visualCount -and $audioIndex -lt $audioCount) {
                $distance = [Math]::Abs($visualMarkers[$visualIndex] - $audioMarkers[$audioIndex])
                if ($distance -lt $MaximumPairingDistanceSeconds) {
                    $nextVisual = $visualIndex + 1
                    $nextAudio = $audioIndex + 1
                    $candidateCount = 1 + $matchCounts[$nextVisual, $nextAudio]
                    $candidateCost = $distance + $matchCosts[$nextVisual, $nextAudio]
                    if ($candidateCount -gt $bestCount -or
                        ($candidateCount -eq $bestCount -and $candidateCost -lt ($bestCost - $epsilon)) -or
                        ($candidateCount -eq $bestCount -and [Math]::Abs($candidateCost - $bestCost) -le $epsilon)) {
                        $bestCount = $candidateCount
                        $bestCost = $candidateCost
                        $bestAction = 'P'
                    }
                }
            }

            $matchCounts[$visualIndex, $audioIndex] = $bestCount
            $matchCosts[$visualIndex, $audioIndex] = $bestCost
            $actions[$visualIndex, $audioIndex] = $bestAction
        }
    }

    $pairs = New-Object 'System.Collections.Generic.List[object]'
    $unmatchedVisual = New-Object 'System.Collections.Generic.List[double]'
    $unmatchedAudio = New-Object 'System.Collections.Generic.List[double]'
    $visualIndex = 0
    $audioIndex = 0
    while ($visualIndex -lt $visualCount -or $audioIndex -lt $audioCount) {
        $action = $actions[$visualIndex, $audioIndex]
        switch ($action) {
            'P' {
                $visualTime = $visualMarkers[$visualIndex]
                $audioTime = $audioMarkers[$audioIndex]
                $pairs.Add([pscustomobject]@{
                    Visual = $visualTime
                    Audio = $audioTime
                    OffsetMs = ($visualTime - $audioTime) * 1000
                })
                $visualIndex++
                $audioIndex++
            }
            'V' {
                $unmatchedVisual.Add([double]$visualMarkers[$visualIndex])
                $visualIndex++
            }
            'A' {
                $unmatchedAudio.Add([double]$audioMarkers[$audioIndex])
                $audioIndex++
            }
            default { throw 'Marker alignment reconstruction failed.' }
        }
    }

    $pairArray = $pairs.ToArray()
    $offsets = @($pairArray | ForEach-Object { [double]$_.OffsetMs })
    $medianOffset = $null
    $maximumOffset = $null
    $startOffset = $null
    $endOffset = $null
    if ($pairArray.Count -gt 0) {
        $orderedOffsets = @($offsets | Sort-Object)
        $middle = [int][Math]::Floor($orderedOffsets.Count / 2)
        if (($orderedOffsets.Count % 2) -eq 1) {
            $medianOffset = $orderedOffsets[$middle]
        }
        else {
            $medianOffset = ($orderedOffsets[$middle - 1] + $orderedOffsets[$middle]) / 2.0
        }
        $maximumOffset = ($offsets | ForEach-Object { [Math]::Abs($_) } | Measure-Object -Maximum).Maximum
        $startOffset = $pairArray[0].OffsetMs
        $endOffset = $pairArray[-1].OffsetMs
    }

    [pscustomobject]@{
        Method = 'Monotonic one-to-one maximum-cardinality pairing; minimum total offset among matches; candidate window < 500 ms'
        VisualMarkers = $visualCount
        AudioMarkers = $audioCount
        MatchedEvents = $pairArray.Count
        PairedEvents = $pairArray.Count
        UnmatchedVisualEvents = $visualCount - $pairArray.Count
        UnmatchedAudioEvents = $audioCount - $pairArray.Count
        UnmatchedVisualSeconds = @($unmatchedVisual.ToArray() | ForEach-Object { [Math]::Round($_, 3) })
        UnmatchedAudioSeconds = @($unmatchedAudio.ToArray() | ForEach-Object { [Math]::Round($_, 3) })
        StartOffsetMs = if ($null -ne $startOffset) { [Math]::Round($startOffset, 1) } else { $null }
        MedianOffsetMs = if ($null -ne $medianOffset) { [Math]::Round($medianOffset, 1) } else { $null }
        EndOffsetMs = if ($null -ne $endOffset) { [Math]::Round($endOffset, 1) } else { $null }
        MaxOffsetMs = if ($null -ne $maximumOffset) { [Math]::Round($maximumOffset, 1) } else { $null }
        EventMeasurements = @($pairArray | ForEach-Object {
            [pscustomobject]@{
                VisualSeconds = [Math]::Round($_.Visual, 3)
                AudioSeconds = [Math]::Round($_.Audio, 3)
                OffsetMs = [Math]::Round($_.OffsetMs, 1)
            }
        })
    }
}
