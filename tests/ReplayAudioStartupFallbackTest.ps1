param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
if (-not [IO.File]::Exists($Executable)) { throw "Required file was not found: $Executable" }

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$managerType = $assembly.GetType('BoltSnip.ReplayManager', $true)
$method = $managerType.GetMethod('TryStartWithAudioAndFallback', [Reflection.BindingFlags]'Static,NonPublic')
if ($null -eq $method) { throw 'The testable startup fallback helper was not found.' }

$script:connected = $false
$script:fallbackCount = 0
$script:videoOnlyStarted = $false
$script:stopRequested = $false
$startAndStabilize = [Action] {
    $script:connected = $true
    throw [InvalidOperationException]::new('simulated encoder exit during audio stabilization')
}
$isStopRequested = [Func[bool]] { return $script:stopRequested }
$cleanupAndStartVideoOnly = [Action] {
    $script:fallbackCount++
    $script:videoOnlyStarted = $true
}
$arguments = [object[]]@($startAndStabilize, $isStopRequested, $cleanupAndStartVideoOnly, $null)
$audioSucceeded = [bool]$method.Invoke($null, $arguments)
$audioFailure = [Exception]$arguments[3]

$fallbackPassed = $script:connected -and -not $audioSucceeded -and
    $script:fallbackCount -eq 1 -and $script:videoOnlyStarted -and
    $null -ne $audioFailure -and $audioFailure.Message.Contains('stabilization')

$fallbackFailurePropagated = $false
$failedVideoFallback = [Action] { throw [InvalidOperationException]::new('simulated video-only encoder exit') }
$arguments = [object[]]@($startAndStabilize, $isStopRequested, $failedVideoFallback, $null)
try { [void]$method.Invoke($null, $arguments) }
catch { $fallbackFailurePropagated = $_.Exception.GetBaseException().Message.Contains('video-only encoder exit') }

$script:stopRequested = $true
$stopFallbackCount = 0
$arguments = [object[]]@(
    $startAndStabilize,
    [Func[bool]] { return $script:stopRequested },
    [Action] { $script:stopFallbackCount++ },
    $null)
$stopWasCancellation = $false
$stopExceptionType = $null
try { [void]$method.Invoke($null, $arguments) }
catch {
    $caught = $_.Exception
    while ($null -ne $caught) {
        if ($caught -is [OperationCanceledException]) {
            $stopWasCancellation = $true
            $stopExceptionType = $caught.GetType().FullName
            break
        }
        $caught = $caught.InnerException
    }
}

[pscustomobject]@{
    AudioConnectedBeforeStabilizationFailure = $script:connected
    AudioFailureRecorded = $null -ne $audioFailure
    VideoOnlyFallbackCount = $script:fallbackCount
    VideoOnlyFallbackStarted = $script:videoOnlyStarted
    SecondEncoderFailurePropagates = $fallbackFailurePropagated
    StopExceptionType = $stopExceptionType
    StopFallbackCount = $script:stopFallbackCount
    StopCancelsWithoutFallback = $stopWasCancellation -and $script:stopFallbackCount -eq 0
    Passed = $fallbackPassed -and $fallbackFailurePropagated -and $stopWasCancellation -and $script:stopFallbackCount -eq 0
} | Format-List

if (-not ($fallbackPassed -and $fallbackFailurePropagated -and $stopWasCancellation -and $script:stopFallbackCount -eq 0)) { exit 1 }
