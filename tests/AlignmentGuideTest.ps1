param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$overlayType = $assembly.GetType('BoltSnip.CaptureOverlay', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$horizontalMethod = $overlayType.GetMethod('GetHorizontalAlignmentGuideBounds', $flags)
$verticalMethod = $overlayType.GetMethod('GetVerticalAlignmentGuideBounds', $flags)
$instanceFlags = [Reflection.BindingFlags]'Instance,NonPublic'
$drawMethod = $overlayType.GetMethod('DrawAlignmentGuides', $instanceFlags)

if ($null -eq $horizontalMethod -or $null -eq $verticalMethod -or $null -eq $drawMethod) {
    throw 'Alignment guide geometry methods were not found.'
}

# The coordinates use the overlay client space. This case represents a secondary monitor
# whose physical screen bounds were translated from a negative virtual-desktop origin.
$monitor = [Drawing.Rectangle]::new(1920, 0, 2560, 1440)
$cursor = [Drawing.Point]::new(3142, 731)
$horizontal = $horizontalMethod.Invoke($null, @($cursor.PSObject.BaseObject, $monitor.PSObject.BaseObject))
$vertical = $verticalMethod.Invoke($null, @($cursor.PSObject.BaseObject, $monitor.PSObject.BaseObject))

$overlay = [Activator]::CreateInstance($overlayType, $true)
$bitmap = [Drawing.Bitmap]::new(64, 64, [Drawing.Imaging.PixelFormat]::Format32bppPArgb)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
try {
    # OnPaint uses PixelOffsetMode.Half for the screenshot. DrawAlignmentGuides must
    # isolate its one-pixel pen from that state so pixels land inside its invalidation bounds.
    $graphics.Clear([Drawing.Color]::Transparent)
    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::Half
    $linePoint = [Drawing.Point]::new(30, 20)
    $lineScreen = [Drawing.Rectangle]::new(0, 20, 64, 1)
    $drawMethod.Invoke($overlay, @($graphics, $linePoint.PSObject.BaseObject, $lineScreen.PSObject.BaseObject))

    $paintedPixelsOnInvalidatedRow = 0
    for ($x = 0; $x -lt $bitmap.Width; $x++) {
        if ($bitmap.GetPixel($x, 20).A -gt 0) {
            $paintedPixelsOnInvalidatedRow++
        }
    }
}
finally {
    $graphics.Dispose()
    $bitmap.Dispose()
    $overlay.Dispose()
}

$passed = $horizontal -eq [Drawing.Rectangle]::new(1920, 731, 2560, 1) -and
    $vertical -eq [Drawing.Rectangle]::new(3142, 0, 1, 1440) -and
    $paintedPixelsOnInvalidatedRow -gt 1

[pscustomobject]@{
    HorizontalCoversCurrentMonitor = $horizontal.Left -eq $monitor.Left -and $horizontal.Right -eq $monitor.Right
    VerticalCoversCurrentMonitor = $vertical.Top -eq $monitor.Top -and $vertical.Bottom -eq $monitor.Bottom
    OnePhysicalPixel = $horizontal.Height -eq 1 -and $vertical.Width -eq 1
    CursorAligned = $horizontal.Top -eq $cursor.Y -and $vertical.Left -eq $cursor.X
    PaintMatchesInvalidationBounds = $paintedPixelsOnInvalidatedRow -gt 1
    Passed = $passed
} | Format-List

if (-not $passed) {
    exit 1
}
