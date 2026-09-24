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
    $selectionField = $overlayType.GetField('_selection', $flags)
    $hasSelectionField = $overlayType.GetField('_hasSelection', $flags)
    $getToolbar = $overlayType.GetMethod('GetToolbarBounds', $flags)
    $getButton = $overlayType.GetMethod('GetToolbarButtonBounds', $flags)
    $hitTest = $overlayType.GetMethod('HitTestToolbar', $flags)
    $drawToolbar = $overlayType.GetMethod('DrawToolbar', $flags)
    $hasSelectionField.SetValue($overlay, $true)

    $overlay.ClientSize = [Drawing.Size]::new(1280, 720)
    $wideSelection = [Drawing.Rectangle]::new(60, 60, 800, 300)
    $selectionField.SetValue($overlay, $wideSelection)
    $wideToolbar = $getToolbar.Invoke($overlay, @($wideSelection))
    if ($wideToolbar.Width -ne 160 -or $wideToolbar.Height -ne 34) {
        throw "Wide selection still uses the expanded toolbar: $wideToolbar"
    }

    $bitmap = [Drawing.Bitmap]::new(1280, 720)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        [void]$drawToolbar.Invoke($overlay, @($graphics, $wideSelection))
        $middleY = $wideToolbar.Top + [int]($wideToolbar.Height / 2)
        if ($bitmap.GetPixel($wideToolbar.Left + 5, $middleY).A -eq 0 -or
            $bitmap.GetPixel($wideToolbar.Right + 2, $middleY).A -ne 0) {
            throw 'Painted toolbar does not match its compact bounds.'
        }
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }

    $cases = @(
        [pscustomobject]@{ Name = 'Wide selection on large screen'; Size = [Drawing.Size]::new(1280, 720); Selection = $wideSelection; Width = 160 },
        [pscustomobject]@{ Name = 'Narrow selection on large screen'; Size = [Drawing.Size]::new(1280, 720); Selection = [Drawing.Rectangle]::new(60, 60, 320, 120); Width = 160 },
        [pscustomobject]@{ Name = 'Wide selection on small screen'; Size = [Drawing.Size]::new(800, 600); Selection = [Drawing.Rectangle]::new(60, 60, 700, 300); Width = 160 },
        [pscustomobject]@{ Name = 'Small screen and selection'; Size = [Drawing.Size]::new(534, 244); Selection = [Drawing.Rectangle]::new(60, 60, 320, 120); Width = 160 },
        [pscustomobject]@{ Name = 'Narrow screen'; Size = [Drawing.Size]::new(150, 240); Selection = [Drawing.Rectangle]::new(20, 20, 130, 100); Width = 138 }
    )
    foreach ($case in $cases) {
        $overlay.ClientSize = $case.Size
        $selection = $case.Selection
        $selectionField.SetValue($overlay, $selection)
        $toolbar = $getToolbar.Invoke($overlay, @($selection))
        if ($toolbar.Width -ne $case.Width -or $toolbar.Height -ne 34 -or
            $toolbar.Left -lt 0 -or $toolbar.Right -gt $case.Size.Width) {
            throw "Toolbar did not compact or fit for $($case.Name): $toolbar"
        }

        $previousRight = $toolbar.Left + 2
        for ($index = 0; $index -lt 3; $index++) {
            $button = $getButton.Invoke($overlay, @($index))
            $expected = @('Copy', 'Save', 'Cancel')[$index]
            $center = [Drawing.Point]::new($button.Left + [int]($button.Width / 2), $button.Top + [int]($button.Height / 2))
            $actual = $hitTest.Invoke($overlay, @($center)).ToString()
            if ($button.Left -ne $previousRight -or $button.Width -le 0 -or
                $button.Right -gt ($toolbar.Right - 2) -or $actual -ne $expected) {
                throw "Button $index has incorrect layout or hit target for $($case.Name): $button, action $actual"
            }
            $previousRight = $button.Right
        }
        if ($previousRight -ne ($toolbar.Right - 2)) {
            throw "Buttons do not fill toolbar for $($case.Name): $toolbar"
        }
    }

    'Responsive toolbar layout and hit targets passed.'
}
finally {
    $overlay.Dispose()
}
