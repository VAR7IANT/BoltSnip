param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HotkeySettingsDpiTestNative
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
$settingsType = $assembly.GetType('BoltSnip.AppSettings', $true)
$loadSettings = $settingsType.GetMethod('Load', $staticFlags, $null, [Type[]]@([string], [string]), $null)
$dialogType = $assembly.GetType('BoltSnip.HotkeySettingsDialog', $true)
$dialogConstructor = $dialogType.GetConstructor($instanceFlags, $null, [Type[]]@($settingsType, $assembly.GetType('BoltSnip.HotkeyWindow', $true)), $null)
$applyDpi = $dialogType.GetMethod('ApplyDpi', $instanceFlags)
$setStatus = $dialogType.GetMethod('SetCardStatus', $instanceFlags, $null, [Type[]]@(
    $assembly.GetType('BoltSnip.HotkeySlot', $true), [string], [Drawing.Color], [string]), $null)
$windowType = $assembly.GetType('BoltSnip.HotkeyWindow', $true)
$windowConstructor = $windowType.GetConstructor($instanceFlags, $null, [Type[]]@(
    [Action], [Action], $gestureType, $gestureType), $null)
$windowDispose = $windowType.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
$keyProperty = $gestureType.GetProperty('Key', $instanceFlags)
$modifiersProperty = $gestureType.GetProperty('Modifiers', $instanceFlags)
$captureDefault = $gestureType.GetProperty('Default', $staticFlags).GetValue($null, $null)
$replayDefault = $gestureType.GetProperty('ReplaySaveDefault', $staticFlags).GetValue($null, $null)
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('BoltSnip-HotkeyDpi-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$settingsPath = Join-Path $testRoot 'settings.ini'
$legacyPath = Join-Path $testRoot 'legacy.ini'
$testId = 0x5A7C
$testModifiers = [uint32]7
$registrationProbeModifiers = [uint32]0x4007
$plainModifiers = [uint32]7
$availableKeys = New-Object 'System.Collections.Generic.List[int]'
$window = $null
$dialog = $null

try {
    foreach ($virtualKey in 0x7c..0x87) {
        if ([HotkeySettingsDpiTestNative]::RegisterHotKey([IntPtr]::Zero, $testId, $registrationProbeModifiers, [uint32]$virtualKey)) {
            [void][HotkeySettingsDpiTestNative]::UnregisterHotKey([IntPtr]::Zero, $testId)
            $availableKeys.Add($virtualKey)
        }
    }
    if ($availableKeys.Count -lt 2) { throw 'Could not find two available test shortcuts.' }

    $captureGesture = $gestureConstructor.Invoke([object[]]@($testModifiers, [Windows.Forms.Keys]$availableKeys[0]))
    $replayGesture = $gestureConstructor.Invoke([object[]]@($testModifiers, [Windows.Forms.Keys]$availableKeys[1]))
    $settingsText = "CaptureModifiers=$($modifiersProperty.GetValue($captureGesture, $null))`r`n" +
        "CaptureKey=$([int]$keyProperty.GetValue($captureGesture, $null))`r`n" +
        "ReplaySaveModifiers=$($modifiersProperty.GetValue($replayGesture, $null))`r`n" +
        "ReplaySaveKey=$([int]$keyProperty.GetValue($replayGesture, $null))`r`n"
    [IO.File]::WriteAllText($settingsPath, $settingsText, [Text.UTF8Encoding]::new($false))
    $loadArguments = New-Object 'object[]' 2
    $loadArguments[0] = [string]$settingsPath
    $loadArguments[1] = [string]$legacyPath
    $settings = $loadSettings.Invoke($null, $loadArguments)
    $window = $windowConstructor.Invoke([object[]]@([Action] {}, [Action] {}, $captureGesture, $replayGesture))
    $dialog = $dialogConstructor.Invoke([object[]]@($settings, $window))

    $expected = @{
        96 = @(396, 297)
        120 = @(495, 371)
        144 = @(594, 446)
        192 = @(792, 594)
    }
    $dimensionResults = @()
    $allControlsFit = $true
    $statusTextFits = $true
    foreach ($dpi in @(96, 120, 144, 192)) {
        [void]$applyDpi.Invoke($dialog, [object[]]@($dpi))
        $size = $dialog.ClientSize
        $dimensionsCorrect = $size.Width -eq $expected[$dpi][0] -and $size.Height -eq $expected[$dpi][1]
        $withinBounds = $dimensionsCorrect
        foreach ($control in $dialog.Controls) {
            if ($control.Left -lt 0 -or $control.Top -lt 0 -or
                $control.Right -gt $dialog.ClientSize.Width -or $control.Bottom -gt $dialog.ClientSize.Height) {
                $withinBounds = $false
            }
            if ($control -is [Windows.Forms.Panel]) {
                foreach ($child in $control.Controls) {
                    if ($child.Left -lt 0 -or $child.Top -lt 0 -or
                        $child.Right -gt $control.ClientSize.Width -or $child.Bottom -gt $control.ClientSize.Height) {
                        $withinBounds = $false
                    }
                }
            }
        }

        $captureConflict = '与“保存即时回放”快捷键冲突。'
        [void]$setStatus.Invoke($dialog, [object[]]@(
            [Enum]::ToObject($assembly.GetType('BoltSnip.HotkeySlot', $true), 0),
            $captureConflict,
            [Drawing.Color]::Firebrick,
            $captureConflict))
        $statusLabel = $dialog.Controls[3].Controls[3]
        $measuredStatus = [Windows.Forms.TextRenderer]::MeasureText(
            $statusLabel.Text,
            $statusLabel.Font,
            [Drawing.Size]::new($statusLabel.Width, 100),
            [Windows.Forms.TextFormatFlags]::WordBreak -bor [Windows.Forms.TextFormatFlags]::NoPadding)
        $statusFits = $measuredStatus.Height -le $statusLabel.Height
        $statusTextFits = $statusTextFits -and $statusFits
        $allControlsFit = $allControlsFit -and $withinBounds
        $dimensionResults += [pscustomobject]@{
            Dpi = $dpi
            ClientSize = $size.ToString()
            BoundsFit = $withinBounds
            ConflictStatusFits = $statusFits
        }
    }

    $dialog.Dispose()
    $dialog = $null
    [void]$windowDispose.Invoke($window, $null)
    $window = $null
    $passed = $allControlsFit -and $statusTextFits -and $dimensionResults.Count -eq 4
    $dimensionResults | Format-Table -AutoSize
    [pscustomobject]@{
        DpiLevels = '100%, 125%, 150%, 200%'
        AllControlsStayInsideFormAndCards = $allControlsFit
        LongConflictStatusFits = $statusTextFits
        Passed = $passed
    } | Format-List
    if (-not $passed) { exit 1 }
}
finally {
    if ($null -ne $dialog) { $dialog.Dispose() }
    if ($null -ne $window) { [void]$windowDispose.Invoke($window, $null) }
    if ([IO.Directory]::Exists($testRoot)) { [IO.Directory]::Delete($testRoot, $true) }
}
