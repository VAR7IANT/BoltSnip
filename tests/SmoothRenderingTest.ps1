param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$overlayType = $assembly.GetType('BoltSnip.CaptureOverlay', $true)
$flags = [Reflection.BindingFlags]'Instance,NonPublic'
$overlay = [Activator]::CreateInstance($overlayType, $true)
$screen = [Drawing.Bitmap]::new(500, 400)
$canvas = [Drawing.Bitmap]::new(500, 400)
$script:invalidations = 0
$invalidatedHandler = [Windows.Forms.InvalidateEventHandler]{
    param($sender, $eventArgs)
    $script:invalidations++
}

try {
    $overlay.ClientSize = [Drawing.Size]::new(500, 400)
    $overlayType.GetField('_screen', $flags).SetValue($overlay, $screen)
    $overlayType.GetField('_virtualScreen', $flags).SetValue(
        $overlay,
        [Drawing.Rectangle]::new(0, 0, 500, 400))
    $overlayType.GetField('_captureActive', $flags).SetValue($overlay, $true)
    $overlayType.GetField('_hasAlignmentGuidePoint', $flags).SetValue($overlay, $true)
    $overlayType.GetField('_alignmentGuidePoint', $flags).SetValue(
        $overlay,
        [Drawing.Point]::new(100, 100))
    $overlayType.GetField('_alignmentGuideScreen', $flags).SetValue(
        $overlay,
        [Drawing.Rectangle]::new(0, 0, 500, 400))
    $overlayType.GetField('_hasMagnifierPoint', $flags).SetValue($overlay, $true)
    $overlayType.GetField('_magnifierPoint', $flags).SetValue(
        $overlay,
        [Drawing.Point]::new(100, 100))
    $overlayType.GetField('_hoverRectangle', $flags).SetValue(
        $overlay,
        [Drawing.Rectangle]::new(0, 0, 500, 400))

    $overlay.add_Invalidated($invalidatedHandler)
    $mouseArguments = [Windows.Forms.MouseEventArgs]::new(
        [Windows.Forms.MouseButtons]::None,
        0,
        200,
        160,
        0)
    [void]$overlayType.GetMethod('OverlayMouseMoveCore', $flags).Invoke(
        $overlay,
        @($mouseArguments))
    $scheduler = $overlayType.GetMethod('InvalidateDirtyRegion', $flags)
    $schedulerToken = [BitConverter]::GetBytes($scheduler.MetadataToken)
    $mouseMoveIl = $overlayType.GetMethod('OverlayMouseMoveCore', $flags).GetMethodBody().GetILAsByteArray()
    $schedulerCalls = 0
    for ($index = 0; $index -le $mouseMoveIl.Length - 5; $index++) {
        if ($mouseMoveIl[$index] -eq 0x28 -and
            $mouseMoveIl[$index + 1] -eq $schedulerToken[0] -and
            $mouseMoveIl[$index + 2] -eq $schedulerToken[1] -and
            $mouseMoveIl[$index + 3] -eq $schedulerToken[2] -and
            $mouseMoveIl[$index + 4] -eq $schedulerToken[3]) {
            $schedulerCalls++
        }
    }
    $oneInvalidationPerMove = $schedulerCalls -eq 1
    $pendingBeforePaint = [bool]$overlayType.GetField('_hasPendingPaintRegion', $flags).GetValue($overlay)
    $pendingRegion = $overlayType.GetField('_pendingPaintRegion', $flags).GetValue($overlay)
    $outsideIncludedInPending = $pendingRegion.IsVisible(50, 50)
    $insideIncludedInPending = $pendingRegion.IsVisible(200, 50)

    $graphics = [Drawing.Graphics]::FromImage($canvas)
    try {
        $graphics.Clear([Drawing.Color]::Magenta)
        $paintArguments = [Windows.Forms.PaintEventArgs]::new(
            $graphics,
            [Drawing.Rectangle]::new(0, 0, 500, 400))
        try {
            $overlayType.GetField('_captureActive', $flags).SetValue($overlay, $false)
            [void]$overlayType.GetMethod('PaintOverlay', $flags).Invoke(
                $overlay,
                @($paintArguments))
        }
        finally {
            $paintArguments.Dispose()
        }

        $outsidePreserved = $canvas.GetPixel(50, 50).ToArgb() -eq [Drawing.Color]::Magenta.ToArgb()
        $insidePainted = $canvas.GetPixel(200, 50).ToArgb() -ne [Drawing.Color]::Magenta.ToArgb()
        $complexClipPreserved = $outsidePreserved -and $insidePainted
    }
    finally {
        $graphics.Dispose()
    }

    $passed = $oneInvalidationPerMove -and $complexClipPreserved
    [pscustomobject]@{
        RenderSchedulerCalls = $schedulerCalls
        InvalidatedRegionEvents = $script:invalidations
        OneInvalidationPerMouseMove = $oneInvalidationPerMove
        PendingRegionAvailable = $pendingBeforePaint
        OutsideIncludedInPending = $outsideIncludedInPending
        InsideIncludedInPending = $insideIncludedInPending
        OutsideDirtyRegionPreserved = $outsidePreserved
        InsideDirtyRegionPainted = $insidePainted
        ComplexClipPreserved = $complexClipPreserved
        Passed = $passed
    } | Format-List

    if (-not $passed) { exit 1 }
}
finally {
    $overlay.remove_Invalidated($invalidatedHandler)
    $overlayType.GetField('_screen', $flags).SetValue($overlay, $null)
    $screen.Dispose()
    $canvas.Dispose()
    $overlay.Dispose()
}
