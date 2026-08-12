param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$styleType = $assembly.GetType('BoltSnip.BoltSnipMenuStyle', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$apply = $styleType.GetMethod('Apply', $flags)
$applyItem = $styleType.GetMethod('ApplyItem', $flags)

$menu = New-Object Windows.Forms.ContextMenuStrip
$font = New-Object Drawing.Font 'Microsoft YaHei UI', 9.25
$bitmap = $null
try {
    $applyArguments = New-Object 'object[]' 2
    $applyArguments[0] = $menu.PSObject.BaseObject
    $applyArguments[1] = $font.PSObject.BaseObject
    [void]$apply.Invoke($null, $applyArguments)

    $spacerA = New-Object Windows.Forms.ToolStripMenuItem 'First item'
    $spacerB = New-Object Windows.Forms.ToolStripMenuItem 'Second item'
    $spacerC = New-Object Windows.Forms.ToolStripMenuItem 'Third item'
    $startup = New-Object Windows.Forms.ToolStripMenuItem 'Start with Windows'
    $startup.Checked = $true
    foreach ($item in @($spacerA, $spacerB, $spacerC, $startup)) {
        $itemArguments = New-Object 'object[]' 1
        $itemArguments[0] = $item.PSObject.BaseObject
        [void]$applyItem.Invoke($null, $itemArguments)
        [void]$menu.Items.Add($item)
    }

    $menu.PerformLayout()
    $menu.Size = $menu.GetPreferredSize([Drawing.Size]::Empty)
    $bitmap = New-Object Drawing.Bitmap $menu.Width, $menu.Height
    $menu.DrawToBitmap($bitmap, [Drawing.Rectangle]::new(0, 0, $bitmap.Width, $bitmap.Height))

    $itemTop = $startup.Bounds.Top
    $itemBottom = $startup.Bounds.Bottom
    $checkMinY = $itemBottom
    $checkMaxY = -1
    $textMinY = $itemBottom
    $textMaxY = -1
    for ($y = $itemTop; $y -lt $itemBottom; $y++) {
        for ($x = 10; $x -lt [Math]::Min(30, $bitmap.Width); $x++) {
            $pixel = $bitmap.GetPixel($x, $y)
            if ($pixel.G -gt 140 -and $pixel.B -gt 140 -and $pixel.R -lt 130) {
                $checkMinY = [Math]::Min($checkMinY, $y)
                $checkMaxY = [Math]::Max($checkMaxY, $y)
            }
        }
        for ($x = 34; $x -lt $bitmap.Width - 8; $x++) {
            $pixel = $bitmap.GetPixel($x, $y)
            if ($pixel.R -lt 100 -and $pixel.G -lt 110 -and $pixel.B -lt 120) {
                $textMinY = [Math]::Min($textMinY, $y)
                $textMaxY = [Math]::Max($textMaxY, $y)
            }
        }
    }

    $checkCenter = ($checkMinY + $checkMaxY) / 2
    $textCenter = ($textMinY + $textMaxY) / 2
    $centerDelta = $checkCenter - $textCenter
    $passed = $checkMaxY -ge 0 -and $textMaxY -ge 0 -and [Math]::Abs($centerDelta) -le 1

    [pscustomobject]@{
        CheckCenterY = $checkCenter
        TextCenterY = $textCenter
        CenterDeltaPixels = $centerDelta
        OpticallyAligned = $passed
        Passed = $passed
    } | Format-List

    if (-not $passed) {
        exit 1
    }
}
finally {
    if ($null -ne $bitmap) { $bitmap.Dispose() }
    $menu.Dispose()
    $font.Dispose()
}
