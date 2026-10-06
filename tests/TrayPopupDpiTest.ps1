param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path -LiteralPath $Executable).Path)
$popupType = $assembly.GetType('BoltSnip.TrayPopupForm', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$scale = $popupType.GetMethod('ScaleLogicalValue', $flags)
$fit = $popupType.GetMethod('FitToWorkingArea', $flags)
$logicalSizeMethod = $popupType.GetMethod('GetLogicalSize', $flags)
$logicalSize = $logicalSizeMethod.Invoke($null, [object[]]@($false))
$sizes = @{}
foreach ($dpi in @(96, 120, 144, 192)) {
    $width = [int]$scale.Invoke($null, [object[]]@([int]$logicalSize.Width, [int]$dpi))
    $height = [int]$scale.Invoke($null, [object[]]@([int]$logicalSize.Height, [int]$dpi))
    $sizes[$dpi] = [Drawing.Size]::new($width, $height)
}

$workAreas = @(
    [Drawing.Rectangle]::new(0, 0, 1920, 1040),
    [Drawing.Rectangle]::new(-2560, 0, 2560, 1440))
$anchors = @(
    [Drawing.Point]::new(1918, 1038),
    [Drawing.Point]::new(-4, 1438))
$fits = @()
for ($index = 0; $index -lt $workAreas.Count; $index++) {
    $popupSize = $sizes[120]
    $result = $fit.Invoke($null, [object[]]@($anchors[$index], $workAreas[$index], $popupSize))
    $fits += $result.Left -ge $workAreas[$index].Left -and
        $result.Top -ge $workAreas[$index].Top -and
        $result.Right -le $workAreas[$index].Right -and
        $result.Bottom -le $workAreas[$index].Bottom
}

$expected = @{
    96 = @(336, 498)
    120 = @(420, 623)
    144 = @(504, 747)
    192 = @(672, 996)
}
$scaledSizesCorrect = $true
foreach ($dpi in $expected.Keys) {
    $scaledSizesCorrect = $scaledSizesCorrect -and
        $sizes[$dpi].Width -eq $expected[$dpi][0] -and
        $sizes[$dpi].Height -eq $expected[$dpi][1]
}
$passed = $scaledSizesCorrect -and $fits.Count -eq 2 -and $fits[0] -and $fits[1]
[pscustomobject]@{
    TestedDpi = '100%, 125%, 150%, 200%'
    ScaledDimensionsCorrect = $scaledSizesCorrect
    MultiMonitorWorkingAreaFit = $fits -join ','
    Passed = $passed
} | Format-List
if (-not $passed) { exit 1 }
