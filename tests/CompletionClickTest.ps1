param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$overlayType = $assembly.GetType('BoltSnip.CaptureOverlay', $true)
$overlay = [Activator]::CreateInstance($overlayType, $true)

try {
    $flags = [Reflection.BindingFlags]'Instance,NonPublic'
    $hasSelection = $overlayType.GetField('_hasSelection', $flags)
    $selection = $overlayType.GetField('_selection', $flags)
    $resolveAction = $overlayType.GetMethod('GetSelectionClickAction', $flags)

    $overlay.ClientSize = [Drawing.Size]::new(1280, 720)
    $selection.SetValue($overlay, [Drawing.Rectangle]::new(100, 100, 500, 300))
    $hasSelection.SetValue($overlay, $true)

    $point = [Drawing.Point]::new(20, 20)
    $leftAction = $resolveAction.Invoke($overlay, @([Windows.Forms.MouseButtons]::Left, $point)).ToString()
    $rightAction = $resolveAction.Invoke($overlay, @([Windows.Forms.MouseButtons]::Right, $point)).ToString()
    $middleAction = $resolveAction.Invoke($overlay, @([Windows.Forms.MouseButtons]::Middle, $point)).ToString()

    $hasSelection.SetValue($overlay, $false)
    $rightWithoutSelection = $resolveAction.Invoke($overlay, @([Windows.Forms.MouseButtons]::Right, $point)).ToString()

    $passed = $leftAction -eq 'Copy' -and
              $rightAction -eq 'Save' -and
              $middleAction -eq 'None' -and
              $rightWithoutSelection -eq 'None'

    [pscustomobject]@{
        LeftClickWithSelection = $leftAction
        RightClickWithSelection = $rightAction
        MiddleClickWithSelection = $middleAction
        RightClickWithoutSelection = $rightWithoutSelection
        Passed = $passed
    }

    if (-not $passed) {
        exit 1
    }
}
finally {
    $overlay.Dispose()
}
