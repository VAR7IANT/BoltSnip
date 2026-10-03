param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HotkeyRollbackTestNative
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint virtualKey);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool UnregisterHotKey(IntPtr window, int id);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool PostMessage(IntPtr window, int message, IntPtr wParam, IntPtr lParam);
}
'@

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path -LiteralPath $Executable).Path)
$instanceFlags = [Reflection.BindingFlags]'Instance,NonPublic'
$publicInstanceFlags = [Reflection.BindingFlags]'Instance,Public'
$gestureType = $assembly.GetType('BoltSnip.HotkeyGesture', $true)
$gestureConstructor = $gestureType.GetConstructor($instanceFlags, $null, [Type[]]@([uint32], [Windows.Forms.Keys]), $null)
$slotType = $assembly.GetType('BoltSnip.HotkeySlot', $true)
$windowType = $assembly.GetType('BoltSnip.HotkeyWindow', $true)
$windowConstructor = $windowType.GetConstructor($instanceFlags, $null, [Type[]]@([Action], [Action], $gestureType, $gestureType), $null)
$tryApply = $windowType.GetMethod('TryApply', $instanceFlags)
$dispose = $windowType.GetMethod('Dispose', $publicInstanceFlags)
$captureRegisteredProperty = $windowType.GetProperty('CaptureIsRegistered', $instanceFlags)
$replayRegisteredProperty = $windowType.GetProperty('ReplaySaveIsRegistered', $instanceFlags)
$captureGestureProperty = $windowType.GetProperty('CaptureGesture', $instanceFlags)
$replayGestureProperty = $windowType.GetProperty('ReplaySaveGesture', $instanceFlags)
$captureTextProperty = $windowType.GetProperty('CaptureShortcutText', $instanceFlags)
$replayTextProperty = $windowType.GetProperty('ReplaySaveShortcutText', $instanceFlags)
$keyProperty = $gestureType.GetProperty('Key', $instanceFlags)
$suppressCallbacks = $windowType.GetMethod('SetCallbacksSuppressed', $instanceFlags)
$handleProperty = $windowType.GetProperty('Handle', $publicInstanceFlags)
$hotkeyMessage = 0x0312
$modifiers = [uint32]7
$plainModifiers = [uint32]7
$externalId = 0x5A79
$availabilityProbeId = 0x5A7A
$startupExternalId = 0x5A7B
$callbackState = [pscustomobject]@{ Capture = 0; Replay = 0 }
$captureAction = [Action] { $callbackState.Capture++ }.GetNewClosure()
$replayAction = [Action] { $callbackState.Replay++ }.GetNewClosure()
$window = $null
$partialWindow = $null
$reservedReplayTarget = $false
$reservedStartupCapture = $false
$testGestures = New-Object 'System.Collections.Generic.List[object]'
$gestureFactory = {
    param([int]$VirtualKey)
    return $gestureConstructor.Invoke([object[]]@($modifiers, [Windows.Forms.Keys]$VirtualKey))
}.GetNewClosure()

foreach ($virtualKey in 0x7c..0x87) {
    if ([HotkeyRollbackTestNative]::RegisterHotKey([IntPtr]::Zero, $externalId, $modifiers, [uint32]$virtualKey)) {
        [void][HotkeyRollbackTestNative]::UnregisterHotKey([IntPtr]::Zero, $externalId)
        $testGestures.Add((& $gestureFactory $virtualKey))
    }
}
if ($testGestures.Count -lt 8) {
    throw 'Could not find eight available F13-F24 hotkey combinations for the isolated test.'
}

function Test-ReleaseHotkey([int]$VirtualKey) {
    if ([HotkeyRollbackTestNative]::RegisterHotKey([IntPtr]::Zero, $availabilityProbeId, $modifiers, [uint32]$VirtualKey)) {
        return [HotkeyRollbackTestNative]::UnregisterHotKey([IntPtr]::Zero, $availabilityProbeId)
    }
    return $false
}

try {
    $oldCapture = $testGestures[0]
    $oldReplay = $testGestures[1]
    $newCapture = $testGestures[2]
    $blockedReplay = $testGestures[3]
    $newReplay = $testGestures[4]
    $blockedStartupCapture = $testGestures[5]
    $startupReplay = $testGestures[6]
    $updatedStartupReplay = $testGestures[7]

    $window = $windowConstructor.Invoke([object[]]@($captureAction, $replayAction, $oldCapture, $oldReplay))
    if (-not [bool]$captureRegisteredProperty.GetValue($window, $null) -or
        -not [bool]$replayRegisteredProperty.GetValue($window, $null)) {
        throw 'The two initial test hotkeys could not be registered.'
    }

    $blockedVirtualKey = [int]$keyProperty.GetValue($blockedReplay, $null)
    $reservedReplayTarget = [HotkeyRollbackTestNative]::RegisterHotKey(
        [IntPtr]::Zero, $externalId, $plainModifiers, [uint32]$blockedVirtualKey)
    if (-not $reservedReplayTarget) { throw 'Could not reserve the rollback target hotkey.' }

    $applyArguments = New-Object 'object[]' 6
    $applyArguments[0] = $newCapture
    $applyArguments[1] = $blockedReplay
    $applyArguments[2] = $false
    $applyArguments[3] = $false
    $applyArguments[4] = [Enum]::ToObject($slotType, 0)
    $applyArguments[5] = $null
    $failedApply = [bool]$tryApply.Invoke($window, $applyArguments)
    $failureSlot = $applyArguments[4].ToString()
    $failureMessage = [string]$applyArguments[5]
    $rollbackPassed = -not $failedApply -and $failureSlot -eq 'ReplaySave' -and
        [bool]$captureRegisteredProperty.GetValue($window, $null) -and
        [bool]$replayRegisteredProperty.GetValue($window, $null) -and
        $captureGestureProperty.GetValue($window, $null).Equals($oldCapture) -and
        $replayGestureProperty.GetValue($window, $null).Equals($oldReplay) -and
        $failureMessage.Contains('其他程序占用')
    $newCaptureWasReleased = Test-ReleaseHotkey ([int]$keyProperty.GetValue($newCapture, $null))

    $applyArguments = New-Object 'object[]' 6
    $applyArguments[0] = $newCapture
    $applyArguments[1] = $oldReplay
    $applyArguments[2] = $false
    $applyArguments[3] = $false
    $applyArguments[4] = [Enum]::ToObject($slotType, 0)
    $applyArguments[5] = $null
    $captureOnlyChanged = [bool]$tryApply.Invoke($window, $applyArguments)
    $captureOnlyPreservesReplay = $captureOnlyChanged -and
        $captureGestureProperty.GetValue($window, $null).Equals($newCapture) -and
        $replayGestureProperty.GetValue($window, $null).Equals($oldReplay) -and
        [bool]$replayRegisteredProperty.GetValue($window, $null)

    $applyArguments = New-Object 'object[]' 6
    $applyArguments[0] = $newCapture
    $applyArguments[1] = $newReplay
    $applyArguments[2] = $false
    $applyArguments[3] = $false
    $applyArguments[4] = [Enum]::ToObject($slotType, 0)
    $applyArguments[5] = $null
    $replayOnlyChanged = [bool]$tryApply.Invoke($window, $applyArguments)
    $replayOnlyPreservesCapture = $replayOnlyChanged -and
        $captureGestureProperty.GetValue($window, $null).Equals($newCapture) -and
        $replayGestureProperty.GetValue($window, $null).Equals($newReplay) -and
        [bool]$captureRegisteredProperty.GetValue($window, $null)

    $applyArguments = New-Object 'object[]' 6
    $applyArguments[0] = $newReplay
    $applyArguments[1] = $newReplay
    $applyArguments[2] = $false
    $applyArguments[3] = $false
    $applyArguments[4] = [Enum]::ToObject($slotType, 0)
    $applyArguments[5] = $null
    $duplicateAccepted = [bool]$tryApply.Invoke($window, $applyArguments)
    $duplicateRejected = -not $duplicateAccepted -and
        $captureGestureProperty.GetValue($window, $null).Equals($newCapture) -and
        $replayGestureProperty.GetValue($window, $null).Equals($newReplay)

    $handle = [IntPtr]$handleProperty.GetValue($window, $null)
    [void]$suppressCallbacks.Invoke($window, [object[]]@($true))
    [void][HotkeyRollbackTestNative]::PostMessage($handle, $hotkeyMessage, [IntPtr]0x5A72, [IntPtr]::Zero)
    [Windows.Forms.Application]::DoEvents()
    $replayIgnoredDuringSettings = $callbackState.Replay -eq 0
    [void]$suppressCallbacks.Invoke($window, [object[]]@($false))
    [void][HotkeyRollbackTestNative]::PostMessage($handle, $hotkeyMessage, [IntPtr]0x5A72, [IntPtr]::Zero)
    [Windows.Forms.Application]::DoEvents()
    $replayCallbackResumesAfterSettings = $callbackState.Replay -eq 1

    $blockedStartupVk = [int]$keyProperty.GetValue($blockedStartupCapture, $null)
    $reservedStartupCapture = [HotkeyRollbackTestNative]::RegisterHotKey(
        [IntPtr]::Zero, $startupExternalId, $plainModifiers, [uint32]$blockedStartupVk)
    if (-not $reservedStartupCapture) { throw 'Could not reserve the startup partial-failure test hotkey.' }
    $fallbackReserved = [HotkeyRollbackTestNative]::RegisterHotKey([IntPtr]::Zero, 0x6B05, [uint32]0x4006, [uint32]0x41)
    $partialWindow = $windowConstructor.Invoke([object[]]@(
        [Action] {}, [Action] {}, $blockedStartupCapture, $startupReplay))
    $startupRegistrationIsIndependent =
        -not [bool]$captureRegisteredProperty.GetValue($partialWindow, $null) -and
        [bool]$replayRegisteredProperty.GetValue($partialWindow, $null) -and
        ([string]$captureTextProperty.GetValue($partialWindow, $null)).Contains('不可用') -and
        -not ([string]$replayTextProperty.GetValue($partialWindow, $null)).Contains('不可用')

    $applyArguments = New-Object 'object[]' 6
    $applyArguments[0] = $blockedStartupCapture
    $applyArguments[1] = $updatedStartupReplay
    $applyArguments[2] = $false
    $applyArguments[3] = $false
    $applyArguments[4] = [Enum]::ToObject($slotType, 0)
    $applyArguments[5] = $null
    $otherSlotChanged = [bool]$tryApply.Invoke($partialWindow, $applyArguments)
    $unavailableCaptureUnaffected = $otherSlotChanged -and
        -not [bool]$captureRegisteredProperty.GetValue($partialWindow, $null) -and
        [bool]$replayRegisteredProperty.GetValue($partialWindow, $null) -and
        $replayGestureProperty.GetValue($partialWindow, $null).Equals($updatedStartupReplay)

    [void][HotkeyRollbackTestNative]::UnregisterHotKey([IntPtr]::Zero, $startupExternalId)
    $reservedStartupCapture = $false
    $applyArguments = New-Object 'object[]' 6
    $applyArguments[0] = $blockedStartupCapture
    $applyArguments[1] = $updatedStartupReplay
    $applyArguments[2] = $true
    $applyArguments[3] = $false
    $applyArguments[4] = [Enum]::ToObject($slotType, 0)
    $applyArguments[5] = $null
    $explicitRetrySucceeded = [bool]$tryApply.Invoke($partialWindow, $applyArguments) -and
        [bool]$captureRegisteredProperty.GetValue($partialWindow, $null) -and
        [bool]$replayRegisteredProperty.GetValue($partialWindow, $null)

    $passed = $rollbackPassed -and $newCaptureWasReleased -and $captureOnlyPreservesReplay -and
        $replayOnlyPreservesCapture -and $duplicateRejected -and $replayIgnoredDuringSettings -and
        $replayCallbackResumesAfterSettings -and $startupRegistrationIsIndependent -and
        $unavailableCaptureUnaffected -and $explicitRetrySucceeded
    [pscustomobject]@{
        OccupiedReplayRegistrationRejected = -not $failedApply
        BothPreviousShortcutsRestored = $rollbackPassed
        FailedCaptureCandidateReleased = $newCaptureWasReleased
        CaptureOnlyChangeKeepsReplay = $captureOnlyPreservesReplay
        ReplayOnlyChangeKeepsCapture = $replayOnlyPreservesCapture
        DuplicateGesturesRejected = $duplicateRejected
        ReplayCallbackSuppressedDuringSettings = $replayIgnoredDuringSettings
        ReplayCallbackResumesAfterSettings = $replayCallbackResumesAfterSettings
        StartupRegistersUnconflictedShortcut = $startupRegistrationIsIndependent
        UnchangedUnavailableShortcutUnaffected = $unavailableCaptureUnaffected
        EditedUnavailableShortcutCanRetry = $explicitRetrySucceeded
        FailedRegistrationMessage = $failureMessage
        Passed = $passed
    } | Format-List
    if (-not $passed) { exit 1 }
}
finally {
    if ($fallbackReserved) { [void][HotkeyRollbackTestNative]::UnregisterHotKey([IntPtr]::Zero, 0x6B05) }
    if ($null -ne $partialWindow) { [void]$dispose.Invoke($partialWindow, $null) }
    if ($null -ne $window) { [void]$dispose.Invoke($window, $null) }
    if ($reservedReplayTarget) { [void][HotkeyRollbackTestNative]::UnregisterHotKey([IntPtr]::Zero, $externalId) }
    if ($reservedStartupCapture) { [void][HotkeyRollbackTestNative]::UnregisterHotKey([IntPtr]::Zero, $startupExternalId) }
}
