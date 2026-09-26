param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
if (-not [IO.File]::Exists($Executable)) { throw "Required file was not found: $Executable" }

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$type = $assembly.GetType('BoltSnip.ReplayAudioCaptureSession', $true)
$flags = [Reflection.BindingFlags]'Instance,Static,NonPublic'
$constructor = $type.GetConstructor([Reflection.BindingFlags]'Instance,NonPublic', $null, [Type[]]@(), $null)
$pipeField = $type.GetField('_pipe', $flags)
$pendingField = $type.GetField('_pipeEndWaitPending', $flags)
$activeCompletionField = $type.GetField('_activePipeWaitCompletion', $flags)
$disposeSafely = $type.GetMethod('DisposePipeSafely', $flags)
$completePendingWait = $type.GetMethod('CompletePendingPipeWait', $flags)
$completionType = $type.GetNestedType('PipeWaitCompletion', [Reflection.BindingFlags]'NonPublic')

$session = $constructor.Invoke(@())
$pipe = $pipeField.GetValue($session)
$handle = $pipe.SafePipeHandle
$completion = $null
$failure = $null
try {
    if ($null -ne $activeCompletionField -and $null -ne $completePendingWait -and $null -ne $completionType) {
        $completion = [Activator]::CreateInstance($completionType, $true)
        $activeCompletionField.SetValue($session, $completion)
    }

    # Hold the production cleanup path at the same pending state as an outstanding EndWait.
    $pendingField.SetValue($session, 1)
    [void]$disposeSafely.Invoke($session, $null)
    Start-Sleep -Milliseconds 100
    $closedBeforeEndWaitSettled = [bool]$handle.IsClosed

    if ($null -ne $completion) {
        [void]$completePendingWait.Invoke($session, [object[]]@($completion, $null))
    }
    else {
        # Baseline behavior has no completion object; clearing this state cannot undo early disposal.
        $pendingField.SetValue($session, 0)
    }

    $deadline = [DateTime]::UtcNow.AddSeconds(2)
    while (-not $handle.IsClosed -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 10 }
    $closedAfterEndWaitSettled = [bool]$handle.IsClosed
    $failure = [pscustomobject]@{
        ActiveCompletionSeamPresent = $null -ne $completion
        PipeClosedBeforeEndWaitSettled = $closedBeforeEndWaitSettled
        PipeClosedAfterEndWaitSettled = $closedAfterEndWaitSettled
        Passed = (-not $closedBeforeEndWaitSettled -and $closedAfterEndWaitSettled)
    }
    $failure | Format-List
    if (-not $failure.Passed) { exit 1 }
}
finally {
    try { $type.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public').Invoke($session, $null) } catch { }
    if ($null -ne $completion) {
        try { $completionType.GetMethod('FinishWaiting', $flags).Invoke($completion, $null) } catch { }
    }
}
