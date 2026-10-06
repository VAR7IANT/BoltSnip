# Regenerate the checked-in installer artwork from the application's icon.
param([string]$IconPath = (Join-Path $PSScriptRoot '..\bin\app-icon.ico'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$assetDirectory = Join-Path $PSScriptRoot 'assets'
New-Item -ItemType Directory -Force -Path $assetDirectory | Out-Null
$icon = [Drawing.Icon]::new([IO.Path]::GetFullPath($IconPath), 256, 256)
$image = $icon.ToBitmap()
$panel = [Drawing.Bitmap]::new(492, 942)
$graphics = [Drawing.Graphics]::FromImage($panel)
$font = [Drawing.Font]::new('Segoe UI', 38, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$ink = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(32, 36, 42))
$line = [Drawing.Pen]::new([Drawing.Color]::FromArgb(219, 223, 229), 3)
$accent = [Drawing.Pen]::new([Drawing.Color]::FromArgb(240, 187, 49), 7)
try {
    $image.Save((Join-Path $assetDirectory 'wizard-icon.png'), [Drawing.Imaging.ImageFormat]::Png)
    $graphics.Clear([Drawing.Color]::FromArgb(245, 245, 245))
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.DrawImage($image, 126, 186, 240, 240)
    $format = [Drawing.StringFormat]::new()
    try {
        $format.Alignment = [Drawing.StringAlignment]::Center
        $graphics.DrawString('BoltSnip', $font, $ink, [Drawing.RectangleF]::new(0, 464, 492, 70), $format)
    } finally { $format.Dispose() }
    # A quiet capture-frame motif carries the app's identity without extra copy.
    $graphics.DrawLine($line, 80, 630, 412, 630)
    $graphics.DrawLine($accent, 80, 700, 80, 748)
    $graphics.DrawLine($accent, 80, 700, 128, 700)
    $graphics.DrawLine($accent, 412, 846, 412, 798)
    $graphics.DrawLine($accent, 412, 846, 364, 846)
    $panel.Save((Join-Path $assetDirectory 'wizard-panel.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally {
    $accent.Dispose(); $line.Dispose(); $ink.Dispose(); $font.Dispose()
    $graphics.Dispose(); $panel.Dispose(); $image.Dispose(); $icon.Dispose()
}
