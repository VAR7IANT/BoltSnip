param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HotkeySettingsInteractionTestNative
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint virtualKey);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool UnregisterHotKey(IntPtr window, int id);
}
'@

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path -LiteralPath $Executable).Path)
$instanceFlags = [Reflection.BindingFlags]'Instance,NonPublic'
$staticFlags = [Reflection.BindingFlags]'Static,NonPublic'
$gestureType = $assembly.GetType('BoltSnip.HotkeyGesture', $true)
$gestureConstructor = $gestureType.GetConstructor($instanceFlags, $null, [Type[]]@([uint32], [Windows.Forms.Keys]), $null)
$keyProperty = $gestureType.GetProperty('Key', $instanceFlags)
$settingsType = $assembly.GetType('BoltSnip.AppSettings', $true)
$settingsLoad = $settingsType.GetMethod('Load', $staticFlags, $null, [Type[]]@([string], [string]), $null)
$captureProperty = $settingsType.GetProperty('CaptureHotkey', $instanceFlags)
$replayProperty = $settingsType.GetProperty('ReplaySaveHotkey', $instanceFlags)
$windowType = $assembly.GetType('BoltSnip.HotkeyWindow', $true)
$windowConstructor = $windowType.GetConstructor($instanceFlags, $null, [Type[]]@(
    [Action], [Action], $gestureType, $gestureType), $null)
$windowDispose = $windowType.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
$captureGestureProperty = $windowType.GetProperty('CaptureGesture', $instanceFlags)
$replayGestureProperty = $windowType.GetProperty('ReplaySaveGesture', $instanceFlags)
$captureRegisteredProperty = $windowType.GetProperty('CaptureIsRegistered', $instanceFlags)
$replayRegisteredProperty = $windowType.GetProperty('ReplaySaveIsRegistered', $instanceFlags)
$dialogType = $assembly.GetType('BoltSnip.HotkeySettingsDialog', $true)
$dialogConstructor = $dialogType.GetConstructor($instanceFlags, $null, [Type[]]@($settingsType, $windowType), $null)
$beginRecording = $dialogType.GetMethod('BeginRecording', $instanceFlags)
$processCmdKey = $dialogType.GetMethod('ProcessCmdKey', $instanceFlags)
$saveButtonClick = $dialogType.GetMethod('SaveButtonClick', $instanceFlags)
$cancelChanges = $dialogType.GetMethod('CancelChanges', $instanceFlags)
$captureDraftProperty = $dialogType.GetProperty('CaptureDraft', $instanceFlags)
$replayDraftProperty = $dialogType.GetProperty('ReplaySaveDraft', $instanceFlags)
$captureStatusField = $dialogType.GetField('_captureStatus', $instanceFlags)
$popupType = $assembly.GetType('BoltSnip.TrayPopupForm', $true)
$popupConstructor = $popupType.GetConstructor($instanceFlags, $null, [Type[]]@(
    [Action], [Action], [Action], [Action], [Action], [Action], [Action], [Action]), $null)
$popupUpdate = $popupType.GetMethod('UpdatePresentation', $instanceFlags)
$popupCaptureField = $popupType.GetField('_captureShortcut', $instanceFlags)
$popupReplayField = $popupType.GetField('_replayShortcut', $instanceFlags)
$popupDispose = $popupType.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
$slotType = $assembly.GetType('BoltSnip.HotkeySlot', $true)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('BoltSnip-HotkeyDialog-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tempRoot) | Out-Null
$settingsPath = Join-Path $tempRoot 'settings.ini'
$legacyPath = Join-Path $tempRoot 'legacy.ini'
$failureSettingsPath = Join-Path $tempRoot 'settings-failure.ini'
$failureLegacyPath = Join-Path $tempRoot 'legacy-failure.ini'
$registrationProbeId = 0x5A7D
$availableKeys = New-Object 'System.Collections.Generic.List[int]'
$window = $null
$failureWindow = $null
$popup = $null
$dialogs = New-Object 'System.Collections.Generic.List[object]'
$dialogActionError = $null
$interactionResults = [pscustomobject]@{
    DuplicateRejected = $false
    SettingsWriteFailureRestoresOldShortcuts = $false
}

foreach ($virtualKey in 0x7c..0x87) {
    if ([HotkeySettingsInteractionTestNative]::RegisterHotKey(
        [IntPtr]::Zero, $registrationProbeId, [uint32]0x4006, [uint32]$virtualKey)) {
        [void][HotkeySettingsInteractionTestNative]::UnregisterHotKey([IntPtr]::Zero, $registrationProbeId)
        $availableKeys.Add($virtualKey)
    }
}
if ($availableKeys.Count -lt 8) {
    throw 'Could not find eight available F13-F24 test shortcuts.'
}

function New-HotkeyGesture([int]$VirtualKey) {
    return $gestureConstructor.Invoke([object[]]@([uint32]6, [Windows.Forms.Keys]$VirtualKey))
}

function New-SettingsDialog($Settings, $HotkeyWindow) {
    $arguments = New-Object 'object[]' 2
    $arguments[0] = $Settings
    $arguments[1] = $HotkeyWindow
    $dialog = $dialogConstructor.Invoke($arguments)
    $dialogs.Add($dialog)
    return $dialog
}

function Invoke-DialogWithAction($Dialog, $Action) {
    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 120
    $timer.Add_Tick({
        $timer.Stop()
        try {
            & $Action
        }
        catch {
            $script:dialogActionError = $_.Exception
            try { $Dialog.Close() } catch { }
        }
    }.GetNewClosure())
    $timer.Start()
    [void]$Dialog.ShowDialog()
    $timer.Dispose()
    if ($null -ne $script:dialogActionError) {
        throw $script:dialogActionError
    }
    return $Dialog.DialogResult
}

function Invoke-RecordedKey($Dialog, [Windows.Forms.Keys]$KeyData) {
    $arguments = New-Object 'object[]' 2
    $arguments[0] = [Windows.Forms.Message]::Create([IntPtr]::Zero, 0, [IntPtr]::Zero, [IntPtr]::Zero)
    $arguments[1] = $KeyData
    return [bool]$processCmdKey.Invoke($Dialog, $arguments)
}

try {
    $oldCapture = New-HotkeyGesture $availableKeys[0]
    $oldReplay = New-HotkeyGesture $availableKeys[1]
    $newCapture = New-HotkeyGesture $availableKeys[2]
    $newReplay = New-HotkeyGesture $availableKeys[3]
    $canceledCapture = New-HotkeyGesture $availableKeys[4]
    $failureCapture = New-HotkeyGesture $availableKeys[5]
    $failureReplay = New-HotkeyGesture $availableKeys[6]
    $failureCandidate = New-HotkeyGesture $availableKeys[7]
    $settingsText = "CaptureModifiers=6`r`nCaptureKey=$([int]$keyProperty.GetValue($oldCapture, $null))`r`n" +
        "ReplaySaveModifiers=6`r`nReplaySaveKey=$([int]$keyProperty.GetValue($oldReplay, $null))`r`n"
    [IO.File]::WriteAllText($settingsPath, $settingsText, [Text.UTF8Encoding]::new($false))
    $loadArguments = New-Object 'object[]' 2
    $loadArguments[0] = [string]$settingsPath
    $loadArguments[1] = [string]$legacyPath
    $settings = $settingsLoad.Invoke($null, $loadArguments)
    $window = $windowConstructor.Invoke([object[]]@([Action] {}, [Action] {}, $oldCapture, $oldReplay))

    $captureDialog = New-SettingsDialog $settings $window
    $saveCaptureAction = {
        [void]$beginRecording.Invoke($captureDialog, [object[]]@([Enum]::ToObject($slotType, 0)))
        [void](Invoke-RecordedKey $captureDialog ([Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::Shift -bor
            [Windows.Forms.Keys][int]$keyProperty.GetValue($newCapture, $null)))
        if (-not $captureDraftProperty.GetValue($captureDialog, $null).Equals($newCapture)) {
            throw 'The capture recording card did not accept the requested gesture.'
        }
        [void]$saveButtonClick.Invoke($captureDialog, [object[]]@($captureDialog, [EventArgs]::Empty))
    }.GetNewClosure()
    $captureDialogResult = Invoke-DialogWithAction $captureDialog $saveCaptureAction
    $captureChangedImmediately = $captureDialogResult -eq [Windows.Forms.DialogResult]::OK -and
        $captureGestureProperty.GetValue($window, $null).Equals($newCapture) -and
        $replayGestureProperty.GetValue($window, $null).Equals($oldReplay)

    $settingsAfterCapture = $settingsLoad.Invoke($null, $loadArguments)
    $capturePersisted = $captureProperty.GetValue($settingsAfterCapture, $null).Equals($newCapture) -and
        $replayProperty.GetValue($settingsAfterCapture, $null).Equals($oldReplay)

    $replayDialog = New-SettingsDialog $settings $window
    $saveReplayAction = {
        [void]$beginRecording.Invoke($replayDialog, [object[]]@([Enum]::ToObject($slotType, 1)))
        [void](Invoke-RecordedKey $replayDialog ([Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::Shift -bor
            [Windows.Forms.Keys][int]$keyProperty.GetValue($newReplay, $null)))
        if (-not $replayDraftProperty.GetValue($replayDialog, $null).Equals($newReplay)) {
            throw 'The Replay recording card did not accept the requested gesture.'
        }
        [void]$saveButtonClick.Invoke($replayDialog, [object[]]@($replayDialog, [EventArgs]::Empty))
    }.GetNewClosure()
    $replayDialogResult = Invoke-DialogWithAction $replayDialog $saveReplayAction
    $replayChangedImmediately = $replayDialogResult -eq [Windows.Forms.DialogResult]::OK -and
        $captureGestureProperty.GetValue($window, $null).Equals($newCapture) -and
        $replayGestureProperty.GetValue($window, $null).Equals($newReplay)
    $settingsAfterReplay = $settingsLoad.Invoke($null, $loadArguments)
    $bothPersisted = $captureProperty.GetValue($settingsAfterReplay, $null).Equals($newCapture) -and
        $replayProperty.GetValue($settingsAfterReplay, $null).Equals($newReplay)

    $popup = $popupConstructor.Invoke([object[]]@(
        [Action] {}, [Action] {}, [Action] {}, [Action] {},
        [Action] {}, [Action] {}, [Action] {}, [Action] {}))
    $popupUpdate.Invoke($popup, [object[]]@(
        '1.0.0',
        [string]$windowType.GetProperty('CaptureShortcutText', $instanceFlags).GetValue($window, $null),
        [string]$windowType.GetProperty('ReplaySaveShortcutText', $instanceFlags).GetValue($window, $null),
        $false,
        $false))
    $trayLabelsRefresh = [string]$popupCaptureField.GetValue($popup) -eq
        ([string]$windowType.GetProperty('CaptureShortcutText', $instanceFlags).GetValue($window, $null)).Replace('+', ' + ') -and
        [string]$popupReplayField.GetValue($popup) -eq
        ([string]$windowType.GetProperty('ReplaySaveShortcutText', $instanceFlags).GetValue($window, $null)).Replace('+', ' + ')

    $beforeCancel = [IO.File]::ReadAllText($settingsPath)
    $cancelDialog = New-SettingsDialog $settings $window
    $cancelAction = {
        [void]$beginRecording.Invoke($cancelDialog, [object[]]@([Enum]::ToObject($slotType, 0)))
        [void](Invoke-RecordedKey $cancelDialog ([Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::Shift -bor
            [Windows.Forms.Keys][int]$keyProperty.GetValue($canceledCapture, $null)))
        [void]$cancelChanges.Invoke($cancelDialog, $null)
    }.GetNewClosure()
    $cancelDialogResult = Invoke-DialogWithAction $cancelDialog $cancelAction
    $cancelLeavesSettingsAndRegistrationsUntouched =
        $cancelDialogResult -eq [Windows.Forms.DialogResult]::Cancel -and
        [IO.File]::ReadAllText($settingsPath) -ceq $beforeCancel -and
        $captureGestureProperty.GetValue($window, $null).Equals($newCapture) -and
        $replayGestureProperty.GetValue($window, $null).Equals($newReplay)

    $duplicateDialog = New-SettingsDialog $settings $window
    $duplicateAction = {
        [void]$beginRecording.Invoke($duplicateDialog, [object[]]@([Enum]::ToObject($slotType, 0)))
        [void](Invoke-RecordedKey $duplicateDialog ([Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::Shift -bor
            [Windows.Forms.Keys][int]$keyProperty.GetValue($newReplay, $null)))
        [void]$saveButtonClick.Invoke($duplicateDialog, [object[]]@($duplicateDialog, [EventArgs]::Empty))
        $status = $captureStatusField.GetValue($duplicateDialog)
        $interactionResults.DuplicateRejected = $duplicateDialog.DialogResult -ne [Windows.Forms.DialogResult]::OK -and
            $status.AccessibleDescription.Contains('保存即时回放')
        [void]$cancelChanges.Invoke($duplicateDialog, $null)
    }.GetNewClosure()
    [void](Invoke-DialogWithAction $duplicateDialog $duplicateAction)

    [IO.Directory]::CreateDirectory($failureSettingsPath) | Out-Null
    [IO.File]::WriteAllText(
        $failureLegacyPath,
        "Modifiers=6`r`nKey=$([int]$keyProperty.GetValue($failureCapture, $null))`r`n" +
            "ReplaySaveModifiers=6`r`nReplaySaveKey=$([int]$keyProperty.GetValue($failureReplay, $null))`r`n",
        [Text.UTF8Encoding]::new($false))
    $failureLoadArguments = New-Object 'object[]' 2
    $failureLoadArguments[0] = [string]$failureSettingsPath
    $failureLoadArguments[1] = [string]$failureLegacyPath
    $failureSettings = $settingsLoad.Invoke($null, $failureLoadArguments)
    $failureWindow = $windowConstructor.Invoke([object[]]@(
        [Action] {}, [Action] {}, $failureCapture, $failureReplay))
    $failureDialog = New-SettingsDialog $failureSettings $failureWindow
    $failureAction = {
        [void]$beginRecording.Invoke($failureDialog, [object[]]@([Enum]::ToObject($slotType, 0)))
        [void](Invoke-RecordedKey $failureDialog ([Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::Shift -bor
            [Windows.Forms.Keys][int]$keyProperty.GetValue($failureCandidate, $null)))
        [void]$saveButtonClick.Invoke($failureDialog, [object[]]@($failureDialog, [EventArgs]::Empty))
        $failureStatus = $captureStatusField.GetValue($failureDialog)
        $interactionResults.SettingsWriteFailureRestoresOldShortcuts =
            $failureDialog.DialogResult -ne [Windows.Forms.DialogResult]::OK -and
            $captureGestureProperty.GetValue($failureWindow, $null).Equals($failureCapture) -and
            $replayGestureProperty.GetValue($failureWindow, $null).Equals($failureReplay) -and
            [bool]$captureRegisteredProperty.GetValue($failureWindow, $null) -and
            [bool]$replayRegisteredProperty.GetValue($failureWindow, $null) -and
            $captureProperty.GetValue($failureSettings, $null).Equals($failureCapture) -and
            $replayProperty.GetValue($failureSettings, $null).Equals($failureReplay) -and
            $failureStatus.AccessibleDescription.Contains('已恢复原快捷键')
        [void]$cancelChanges.Invoke($failureDialog, $null)
    }.GetNewClosure()
    [void](Invoke-DialogWithAction $failureDialog $failureAction)

    $passed = $captureChangedImmediately -and $capturePersisted -and $replayChangedImmediately -and
        $bothPersisted -and $trayLabelsRefresh -and $cancelLeavesSettingsAndRegistrationsUntouched -and
        $interactionResults.DuplicateRejected -and $interactionResults.SettingsWriteFailureRestoresOldShortcuts
    [pscustomobject]@{
        CaptureLiveApply = $captureChangedImmediately
        CapturePersists = $capturePersisted
        ReplayLiveApply = $replayChangedImmediately
        BothPersistAfterReload = $bothPersisted
        TrayShortcutsRefresh = $trayLabelsRefresh
        CancelKeepsSettingsAndRegistrations = $cancelLeavesSettingsAndRegistrationsUntouched
        SameGestureRejectedInCard = $interactionResults.DuplicateRejected
        SettingsWriteFailureRestoresOldShortcuts = $interactionResults.SettingsWriteFailureRestoresOldShortcuts
        Passed = $passed
    } | Format-List
    if (-not $passed) { exit 1 }
}
finally {
    for ($index = 0; $index -lt $dialogs.Count; $index++) {
        if (-not $dialogs[$index].IsDisposed) { $dialogs[$index].Dispose() }
    }
    if ($null -ne $window) { [void]$windowDispose.Invoke($window, $null) }
    if ($null -ne $failureWindow) { [void]$windowDispose.Invoke($failureWindow, $null) }
    if ($null -ne $popup) { [void]$popupDispose.Invoke($popup, $null) }
    if ([IO.Directory]::Exists($tempRoot)) { [IO.Directory]::Delete($tempRoot, $true) }
}
