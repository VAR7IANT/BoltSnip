param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$managerType = $assembly.GetType('BoltSnip.ReplayManager', $true)
$backendType = $assembly.GetType('BoltSnip.ReplayCaptureBackend', $true)
$method = $managerType.GetMethod('TryStartWithCaptureBackendFallback', [Reflection.BindingFlags]'Static,NonPublic')
if ($null -eq $method) { throw 'The capture backend fallback helper was not found.' }
$ddaBackend = [Enum]::Parse($backendType, 'DdaGrab')
$gdiBackend = [Enum]::Parse($backendType, 'GdiGrab')

$oldDiagnosticPath = [Environment]::GetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', 'Process')
$testDiagnosticPath = Join-Path $env:TEMP ('BoltSnip-CaptureFallback-' + [Guid]::NewGuid().ToString('N') + '.log')
[Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $testDiagnosticPath, 'Process')
try {
    $script:unavailable = $true
    $script:stopping = $false
    $script:fallbackCount = 0
    $arguments = [object[]]@(
        $ddaBackend,
        [Action] { throw [InvalidOperationException]::new('simulated ddagrab startup failure') },
        [Func[bool]] { return $script:unavailable },
        [Func[bool]] { return $script:stopping },
        [Action] { $script:fallbackCount++ },
        $null)
    $selected = $method.Invoke($null, $arguments)
    $fallbackPassed = $selected -eq $gdiBackend -and $script:fallbackCount -eq 1 -and
        $null -ne $arguments[5] -and $arguments[5].Message.Contains('simulated ddagrab startup failure')

    $script:fallbackCount = 0
    $arguments = [object[]]@(
        $ddaBackend,
        [Action] { },
        [Func[bool]] { return $true },
        [Func[bool]] { return $false },
        [Action] { $script:fallbackCount++ },
        $null)
    $selected = $method.Invoke($null, $arguments)
    $successfulDdaWasKept = $selected -eq $ddaBackend -and $script:fallbackCount -eq 0 -and $null -eq $arguments[5]

    $script:fallbackCount = 0
    $script:unavailable = $false
    $nonBackendFailurePropagated = $false
    $arguments = [object[]]@(
        $ddaBackend,
        [Action] { throw [InvalidOperationException]::new('simulated audio startup failure') },
        [Func[bool]] { return $script:unavailable },
        [Func[bool]] { return $false },
        [Action] { $script:fallbackCount++ },
        $null)
    try { [void]$method.Invoke($null, $arguments) }
    catch { $nonBackendFailurePropagated = $_.Exception.GetBaseException().Message.Contains('simulated audio startup failure') }
    $audioFailureDidNotSwitchBackend = $nonBackendFailurePropagated -and $script:fallbackCount -eq 0

    $script:unavailable = $true
    $script:stopping = $true
    $script:fallbackCount = 0
    $stopWasCancellation = $false
    $arguments = [object[]]@(
        $ddaBackend,
        [Action] { throw [InvalidOperationException]::new('simulated ddagrab startup failure') },
        [Func[bool]] { return $script:unavailable },
        [Func[bool]] { return $script:stopping },
        [Action] { $script:fallbackCount++ },
        $null)
    try { [void]$method.Invoke($null, $arguments) }
    catch {
        $caught = $_.Exception
        while ($null -ne $caught) {
            if ($caught -is [OperationCanceledException]) {
                $stopWasCancellation = $true
                break
            }
            $caught = $caught.InnerException
        }
    }

    [pscustomobject]@{
        DdagrabStartupFailureFallsBackToGdi = $fallbackPassed
        SuccessfulDdagrabKeepsBackend = $successfulDdaWasKept
        NonCaptureFailureDoesNotSwitchBackend = $audioFailureDidNotSwitchBackend
        StopCancelsWithoutFallback = $stopWasCancellation -and $script:fallbackCount -eq 0
        Passed = $fallbackPassed -and $successfulDdaWasKept -and $audioFailureDidNotSwitchBackend -and
            $stopWasCancellation -and $script:fallbackCount -eq 0
    } | Format-List

    if (-not ($fallbackPassed -and $successfulDdaWasKept -and $audioFailureDidNotSwitchBackend -and
        $stopWasCancellation -and $script:fallbackCount -eq 0)) { exit 1 }
}
finally {
    if ($oldDiagnosticPath) { [Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $oldDiagnosticPath, 'Process') }
    else { [Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $null, 'Process') }
}
