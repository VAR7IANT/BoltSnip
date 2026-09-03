param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$overlayType = $assembly.GetType('BoltSnip.CaptureOverlay', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$adjust = $overlayType.GetMethod('AdjustSelection', $flags)

function Invoke-Adjust([Drawing.Rectangle]$selection, [Windows.Forms.Keys]$key, [bool]$resize, [Drawing.Rectangle]$bounds) {
    $arguments = New-Object 'object[]' 4
    $arguments[0] = $selection.PSObject.BaseObject
    $arguments[1] = $key
    $arguments[2] = $resize
    $arguments[3] = $bounds.PSObject.BaseObject
    return $adjust.Invoke($null, $arguments)
}

$bounds = [Drawing.Rectangle]::new(0, 0, 800, 600)
$selection = [Drawing.Rectangle]::new(100, 100, 300, 200)
$movedLeft = Invoke-Adjust $selection ([Windows.Forms.Keys]::Left) $false $bounds
$movedDown = Invoke-Adjust $selection ([Windows.Forms.Keys]::Down) $false $bounds
$shrunkWidth = Invoke-Adjust $selection ([Windows.Forms.Keys]::Left) $true $bounds
$expandedWidth = Invoke-Adjust $selection ([Windows.Forms.Keys]::Right) $true $bounds
$shrunkHeight = Invoke-Adjust $selection ([Windows.Forms.Keys]::Up) $true $bounds
$expandedHeight = Invoke-Adjust $selection ([Windows.Forms.Keys]::Down) $true $bounds
$atEdge = Invoke-Adjust ([Drawing.Rectangle]::new(0, 0, 300, 200)) ([Windows.Forms.Keys]::Left) $false $bounds

$passed = $movedLeft.X -eq 99 -and $movedDown.Y -eq 101 -and
    $shrunkWidth.Width -eq 299 -and $expandedWidth.Width -eq 301 -and
    $shrunkHeight.Height -eq 199 -and $expandedHeight.Height -eq 201 -and
    $atEdge.X -eq 0

[pscustomobject]@{
    OnePixelMove = $movedLeft.X -eq 99 -and $movedDown.Y -eq 101
    ShiftResizesWidth = $shrunkWidth.Width -eq 299 -and $expandedWidth.Width -eq 301
    ShiftResizesHeight = $shrunkHeight.Height -eq 199 -and $expandedHeight.Height -eq 201
    ScreenEdgeClamp = $atEdge.X -eq 0
    Passed = $passed
} | Format-List

if (-not $passed) {
    exit 1
}
