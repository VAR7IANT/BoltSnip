param(
    [string]$ExecutablePath = (Join-Path $PSScriptRoot "..\bin\BoltSnip.exe")
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

if (-not (Test-Path -LiteralPath $ExecutablePath)) {
    throw "BoltSnip executable not found: $ExecutablePath"
}

$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $ExecutablePath))
$screenCaptureType = $assembly.GetType("BoltSnip.ScreenCapture", $true)
$cropMethod = $screenCaptureType.GetMethod(
    "Crop",
    [Reflection.BindingFlags]::Static -bor [Reflection.BindingFlags]::NonPublic)

$source = New-Object System.Drawing.Bitmap 8, 7, ([System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
$cropped = $null
try {
    for ($y = 0; $y -lt $source.Height; $y++) {
        for ($x = 0; $x -lt $source.Width; $x++) {
            $color = [System.Drawing.Color]::FromArgb(255, (($x * 31) % 256), (($y * 37) % 256), ((($x + $y) * 43) % 256))
            $source.SetPixel($x, $y, $color)
        }
    }

    $rectangle = New-Object System.Drawing.Rectangle 2, 1, 4, 5
    $arguments = New-Object 'object[]' 2
    $arguments[0] = $source.PSObject.BaseObject
    $arguments[1] = $rectangle.PSObject.BaseObject
    $cropped = $cropMethod.Invoke($null, $arguments)

    if ($cropped.Width -ne $rectangle.Width -or $cropped.Height -ne $rectangle.Height) {
        throw "Crop dimensions changed: expected $($rectangle.Width)x$($rectangle.Height), got $($cropped.Width)x$($cropped.Height)."
    }

    for ($y = 0; $y -lt $cropped.Height; $y++) {
        for ($x = 0; $x -lt $cropped.Width; $x++) {
            $expected = $source.GetPixel($rectangle.X + $x, $rectangle.Y + $y).ToArgb()
            $actual = $cropped.GetPixel($x, $y).ToArgb()
            if ($actual -ne $expected) {
                throw "Pixel mismatch at ($x,$y): expected $expected, got $actual."
            }
        }
    }

    [pscustomobject]@{
        PixelPerfectCrop = $true
        SourceSize = "$($source.Width)x$($source.Height)"
        CropSize = "$($cropped.Width)x$($cropped.Height)"
        Passed = $true
    } | Format-List
}
finally {
    if ($null -ne $cropped) { $cropped.Dispose() }
    $source.Dispose()
}
