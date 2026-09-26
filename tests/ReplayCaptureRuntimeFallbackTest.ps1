param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$managerType = $assembly.GetType('BoltSnip.ReplayManager', $true)
$backendType = $assembly.GetType('BoltSnip.ReplayCaptureBackend', $true)
$fallbackMethod = $managerType.GetMethod('TryRunDdaRuntimeFallback', [Reflection.BindingFlags]'Static,NonPublic')
$classifyMethod = $managerType.GetMethod('ClassifyDdaRuntimeFailure', [Reflection.BindingFlags]'Static,NonPublic')
if ($null -eq $fallbackMethod -or $null -eq $classifyMethod) {
    throw 'The DDA runtime recovery seam was not found.'
}

$dda = [Enum]::Parse($backendType, 'DdaGrab')
$gdi = [Enum]::Parse($backendType, 'GdiGrab')
$state = [pscustomobject]@{
    Backend = $dda
    Calls = 0
    Buffer = [object]::new()
    ReplayState = 'Recording'
    AudioState = 'Active'
}
$oldBuffer = $state.Buffer
$recovery = [Action] {
    $state.Calls++
    $state.Buffer = [object]::new()
    $state.Backend = $gdi
    $state.ReplayState = 'Recording'
    $state.AudioState = 'Active'
}

$firstRecovery = $fallbackMethod.Invoke($null, [object[]]@($dda, $true, $false, $false, $recovery))
$firstFallbackPassed = $firstRecovery -and $state.Calls -eq 1 -and
    $state.Backend -eq $gdi -and -not [object]::ReferenceEquals($oldBuffer, $state.Buffer) -and
    $state.ReplayState -eq 'Recording' -and $state.AudioState -eq 'Active'

$secondRecovery = $fallbackMethod.Invoke($null, [object[]]@($state.Backend, $true, $false, $true, $recovery))
$secondFailurePropagates = $false
try {
    if ($secondRecovery) { throw 'A second runtime failure unexpectedly requested another fallback.' }
    throw [InvalidOperationException]::new('second GDI runtime failure')
}
catch {
    $secondFailurePropagates = $_.Exception.GetBaseException().Message -eq 'second GDI runtime failure'
}

$stopRecoveryCalls = 0
$stopRecovery = $fallbackMethod.Invoke($null, [object[]]@(
    $dda, $true, $true, $false, [Action] { $script:stopRecoveryCalls++ }))
$stopSkipsRecovery = -not $stopRecovery -and $stopRecoveryCalls -eq 0

$gdiRecoveryCalls = 0
$gdiFailureDoesNotFallback = -not $fallbackMethod.Invoke($null, [object[]]@(
    $gdi, $true, $false, $false, [Action] { $script:gdiRecoveryCalls++ })) -and $gdiRecoveryCalls -eq 0

$nonExitDoesNotFallback = -not $fallbackMethod.Invoke($null, [object[]]@(
    $dda, $false, $false, $false, [Action] { throw 'Recovery must not run before process exit.' }))

$accessLostClassified = $classifyMethod.Invoke($null, [object[]]@(
    '[Parsed_ddagrab] AcquireNextFrame failed: 887a0026')) -eq 'DXGI_ERROR_ACCESS_LOST'
$unknownErrorStillAllowsRecovery =
    $classifyMethod.Invoke($null, [object[]]@('vendor encoder failure')) -eq 'unclassified DDA runtime failure' -and
    $fallbackMethod.Invoke($null, [object[]]@($dda, $true, $false, $false, [Action] { }))

[pscustomobject]@{
    RuntimeDdaFailureFallsBackExactlyOnce = $firstFallbackPassed -and $state.Calls -eq 1
    BufferIsReplacedAndRecordingContinues = $firstFallbackPassed
    StopRequestedSkipsFallback = $stopSkipsRecovery
    GdiFailureDoesNotFallbackToDda = $gdiFailureDoesNotFallback
    SecondFailureAfterFallbackPropagates = $secondFailurePropagates
    StillRunningEncoderDoesNotFallback = $nonExitDoesNotFallback
    AccessLostIsClassifiedForDiagnostics = $accessLostClassified
    UnknownDdaExitStillAllowsRecovery = $unknownErrorStillAllowsRecovery
    Passed = $firstFallbackPassed -and $stopSkipsRecovery -and $gdiFailureDoesNotFallback -and
        $secondFailurePropagates -and $nonExitDoesNotFallback -and $accessLostClassified -and
        $unknownErrorStillAllowsRecovery
} | Format-List

if (-not ($firstFallbackPassed -and $stopSkipsRecovery -and $gdiFailureDoesNotFallback -and
    $secondFailurePropagates -and $nonExitDoesNotFallback -and $accessLostClassified -and
    $unknownErrorStillAllowsRecovery)) { exit 1 }
