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
}
'@

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$flags = [Reflection.BindingFlags]'Instance,NonPublic'
$gestureType = $assembly.GetType('BoltSnip.HotkeyGesture', $true)
$gestureConstructor = $gestureType.GetConstructor($flags, $null, [Type[]]@([uint32],[Windows.Forms.Keys]), $null)
$windowType = $assembly.GetType('BoltSnip.HotkeyWindow', $true)
$windowConstructor = $windowType.GetConstructor($flags, $null, [Type[]]@([Action],[Action],$gestureType,$gestureType), $null)
$tryChange = $windowType.GetMethod('TryChange', $flags)
$dispose = $windowType.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
$isRegistered = $windowType.GetProperty('IsRegistered', $flags)
$isReplayRegistered = $windowType.GetProperty('IsReplayHotkeyRegistered', $flags)
$currentGesture = $windowType.GetProperty('CurrentGesture', $flags)
$modifiers = [uint32]7
$dummyId = 0x5A79
$reservedTarget = $false
$window = $null
$gestureFactory = { param([int]$VirtualKey) $gestureConstructor.Invoke([object[]]@($modifiers, [Windows.Forms.Keys]$VirtualKey)) }.GetNewClosure()

try {
    $chosen = $null
    foreach ($preferredVk in 0x7C..0x87) {
        foreach ($replayVk in 0x7C..0x87) {
            if ($preferredVk -eq $replayVk) { continue }
            $preferred = & $gestureFactory $preferredVk
            $replay = & $gestureFactory $replayVk
            $candidate = $windowConstructor.Invoke([object[]]@([Action]{}, [Action]{}, $preferred, $replay))
            $registeredAsRequested = [bool]$isRegistered.GetValue($candidate, $null) -and
                [bool]$isReplayRegistered.GetValue($candidate, $null) -and
                $currentGesture.GetValue($candidate, $null).Equals($preferred)
            if ($registeredAsRequested) {
                $window = $candidate
                $chosen = [pscustomobject]@{ Preferred = $preferred; Replay = $replay; PreferredVk = $preferredVk; ReplayVk = $replayVk }
                break
            }
            [void]$dispose.Invoke($candidate, $null)
        }
        if ($null -ne $chosen) { break }
    }
    if ($null -eq $chosen) { throw 'Could not reserve two test hotkeys for the rollback test.' }

    $target = $null
    foreach ($targetVk in 0x7C..0x87) {
        if ($targetVk -eq $chosen.PreferredVk -or $targetVk -eq $chosen.ReplayVk) { continue }
        if ([HotkeyRollbackTestNative]::RegisterHotKey([IntPtr]::Zero, $dummyId, $modifiers, [uint32]$targetVk)) {
            $reservedTarget = $true
            $target = & $gestureFactory $targetVk
            break
        }
    }
    if (-not $reservedTarget) { throw 'Could not reserve a conflicting target hotkey.' }

    $invokeArguments = New-Object 'object[]' 2
    $invokeArguments[0] = $target
    $invokeArguments[1] = $null
    $changed = [bool]$tryChange.Invoke($window, $invokeArguments)
    $existingScreenshotRestored = [bool]$isRegistered.GetValue($window, $null) -and
        $currentGesture.GetValue($window, $null).Equals($chosen.Preferred)
    $replayHotkeyRestored = [bool]$isReplayRegistered.GetValue($window, $null)
    $passed = -not $changed -and $existingScreenshotRestored -and $replayHotkeyRestored

    [pscustomobject]@{
        ChangeRejectedForOccupiedGesture = -not $changed
        PreviousScreenshotHotkeyRestored = $existingScreenshotRestored
        ReplayHotkeyRestoredWithoutResume = $replayHotkeyRestored
        Error = [string]$invokeArguments[1]
        Passed = $passed
    } | Format-List
    if (-not $passed) { exit 1 }
}
finally {
    if ($null -ne $window) { [void]$dispose.Invoke($window, $null) }
    if ($reservedTarget) { [void][HotkeyRollbackTestNative]::UnregisterHotKey([IntPtr]::Zero, $dummyId) }
}
