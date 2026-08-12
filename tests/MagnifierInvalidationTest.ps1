param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$overlayType = $assembly.GetType('BoltSnip.CaptureOverlay', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$getDirty = $overlayType.GetMethod('GetMagnifierInvalidationRectangles', $flags)

$oldBounds = [Drawing.Rectangle]::new(100, 100, 138, 103)
$newBounds = [Drawing.Rectangle]::new(700, 400, 138, 103)
$dirty = $getDirty.Invoke($null, @($oldBounds, $newBounds))
$union = [Drawing.Rectangle]::Union($oldBounds, $newBounds)
$dirtyArea = 0
foreach ($rectangle in $dirty) {
    $dirtyArea += $rectangle.Width * $rectangle.Height
}
$unionArea = $union.Width * $union.Height

$passed = $dirty.Count -eq 2 -and $dirtyArea -lt ($unionArea / 4)
[pscustomobject]@{
    SeparateDirtyRectangles = $dirty.Count
    DirtyArea = $dirtyArea
    PreviousUnionArea = $unionArea
    Passed = $passed
} | Format-List

if (-not $passed) {
    exit 1
}
