param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$menuType = $assembly.GetType('BoltSnip.BoltSnipContextMenuStrip', $true)
$styleType = $assembly.GetType('BoltSnip.BoltSnipMenuStyle', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$apply = $styleType.GetMethod('Apply', $flags)
$applyItem = $styleType.GetMethod('ApplyItem', $flags)
$cornerRadiusField = $styleType.GetField('CornerRadius', $flags)

$menu = [Activator]::CreateInstance($menuType, $true)
$font = New-Object Drawing.Font 'Microsoft YaHei UI', 9.25
try {
    $applyArguments = New-Object 'object[]' 2
    $applyArguments[0] = $menu
    $applyArguments[1] = $font.PSObject.BaseObject
    [void]$apply.Invoke($null, $applyArguments)

    foreach ($label in @('Capture', 'Settings', 'Start with Windows', 'Exit')) {
        $item = New-Object Windows.Forms.ToolStripMenuItem $label
        $itemArguments = New-Object 'object[]' 1
        $itemArguments[0] = $item.PSObject.BaseObject
        [void]$applyItem.Invoke($null, $itemArguments)
        [void]$menu.Items.Add($item)
    }

    $menu.PerformLayout()
    $menu.Size = $menu.GetPreferredSize([Drawing.Size]::Empty)

    $regionPresent = $null -ne $menu.Region
    $cornersClipped = $regionPresent -and
        -not $menu.Region.IsVisible(0, 0) -and
        -not $menu.Region.IsVisible($menu.Width - 1, 0) -and
        -not $menu.Region.IsVisible(0, $menu.Height - 1) -and
        -not $menu.Region.IsVisible($menu.Width - 1, $menu.Height - 1)
    $edgeCentersVisible = $regionPresent -and
        $menu.Region.IsVisible([int]($menu.Width / 2), 1) -and
        $menu.Region.IsVisible(1, [int]($menu.Height / 2))
    $cornerRadius = [int]$cornerRadiusField.GetRawConstantValue()
    $passed = $cornersClipped -and $edgeCentersVisible -and $cornerRadius -ge 12

    [pscustomobject]@{
        RoundedRegionPresent = $regionPresent
        FourCornersClipped = $cornersClipped
        EdgeCentersVisible = $edgeCentersVisible
        CornerRadius = $cornerRadius
        Passed = $passed
    } | Format-List

    if (-not $passed) {
        exit 1
    }
}
finally {
    $menu.Dispose()
    $font.Dispose()
}
