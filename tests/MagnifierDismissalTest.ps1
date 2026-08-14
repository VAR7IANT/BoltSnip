param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$overlayType = $assembly.GetType('BoltSnip.CaptureOverlay', $true)
$flags = [Reflection.BindingFlags]'Instance,NonPublic'
$staticFlags = [Reflection.BindingFlags]'Static,NonPublic'
$overlay = [Activator]::CreateInstance($overlayType, $true)
$screen = New-Object Drawing.Bitmap 500, 400
$canvas = New-Object Drawing.Bitmap 500, 400

try {
    $overlay.ClientSize = [Drawing.Size]::new(500, 400)
    $screenField = $overlayType.GetField('_screen', $flags)
    $screenField.SetValue($overlay, $screen)
    $overlayType.GetField('_virtualScreen', $flags).SetValue(
        $overlay,
        [Drawing.Rectangle]::new(0, 0, 500, 400))

    $point = [Drawing.Point]::new(100, 100)
    $bounds = $overlayType.GetMethod('GetMagnifierBounds', $flags).Invoke($overlay, @($point))
    $cleanupMethod = $overlayType.GetMethod('GetMagnifierCleanupBounds', $staticFlags)
    $cleanupBounds = if ($null -eq $cleanupMethod) {
        # v0.11 repainted only the nominal bounds when dismissing the magnifier.
        $bounds
    } else {
        $cleanupMethod.Invoke($null, @($bounds))
    }

    $mouseUpUsesCleanup = $false
    if ($null -ne $cleanupMethod) {
        $tokenBytes = [BitConverter]::GetBytes($cleanupMethod.MetadataToken)
        $mouseUpIl = $overlayType.GetMethod('OverlayMouseUp', $flags).GetMethodBody().GetILAsByteArray()
        for ($index = 0; $index -le $mouseUpIl.Length - 5; $index++) {
            if ($mouseUpIl[$index] -eq 0x28 -and
                $mouseUpIl[$index + 1] -eq $tokenBytes[0] -and
                $mouseUpIl[$index + 2] -eq $tokenBytes[1] -and
                $mouseUpIl[$index + 3] -eq $tokenBytes[2] -and
                $mouseUpIl[$index + 4] -eq $tokenBytes[3]) {
                $mouseUpUsesCleanup = $true
                break
            }
        }
    }

    $background = [Drawing.Color]::Magenta
    $graphics = [Drawing.Graphics]::FromImage($canvas)
    try {
        $graphics.Clear($background)
        $drawArguments = New-Object 'object[]' 2
        $drawArguments[0] = $graphics.PSObject.BaseObject
        $drawArguments[1] = $point
        [void]$overlayType.GetMethod('DrawMagnifier', $flags).Invoke($overlay, $drawArguments)

        # Repaint exactly the area the mouse-up path invalidates.
        $graphics.FillRectangle([Drawing.Brushes]::Magenta, $cleanupBounds)
    }
    finally {
        $graphics.Dispose()
    }

    $scan = $bounds
    $scan.Inflate(2, 2)
    $residualPixels = 0
    for ($y = $scan.Top; $y -lt $scan.Bottom; $y++) {
        for ($x = $scan.Left; $x -lt $scan.Right; $x++) {
            if (-not $cleanupBounds.Contains($x, $y) -and
                $canvas.GetPixel($x, $y).ToArgb() -ne $background.ToArgb()) {
                $residualPixels++
            }
        }
    }

    $cleanupPadding = $bounds.Left - $cleanupBounds.Left
    $passed = $mouseUpUsesCleanup -and $cleanupPadding -ge 2 -and $residualPixels -eq 0
    [pscustomobject]@{
        MouseUpUsesCleanupBounds = $mouseUpUsesCleanup
        CleanupPaddingPixels = $cleanupPadding
        ResidualBorderPixels = $residualPixels
        Passed = $passed
    } | Format-List

    if (-not $passed) {
        exit 1
    }
}
finally {
    $overlayType.GetField('_screen', $flags).SetValue($overlay, $null)
    $canvas.Dispose()
    $screen.Dispose()
    $overlay.Dispose()
}
