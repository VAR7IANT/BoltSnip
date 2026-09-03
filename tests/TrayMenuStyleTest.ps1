param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$styleType = $assembly.GetType('BoltSnip.BoltSnipMenuStyle', $true)
$rendererType = $assembly.GetType('BoltSnip.BoltSnipMenuRenderer', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$apply = $styleType.GetMethod('Apply', $flags)
$applyItem = $styleType.GetMethod('ApplyItem', $flags)

$menu = New-Object Windows.Forms.ContextMenuStrip
$font = New-Object Drawing.Font 'Microsoft YaHei UI', 9.25
$item = New-Object Windows.Forms.ToolStripMenuItem 'Capture'
try {
    $arguments = New-Object 'object[]' 2
    $arguments[0] = $menu.PSObject.BaseObject
    $arguments[1] = $font.PSObject.BaseObject
    [void]$apply.Invoke($null, $arguments)
    $itemArguments = New-Object 'object[]' 1
    $itemArguments[0] = $item.PSObject.BaseObject
    [void]$applyItem.Invoke($null, $itemArguments)
    [void]$menu.Items.Add($item)

    $rendererMatches = $menu.Renderer.GetType() -eq $rendererType
    $minimumWidth = $menu.MinimumSize.Width -eq 248
    $comfortablePadding = $item.Padding.Top -eq 4 -and $item.Margin.Top -eq 1
    $accentField = $styleType.GetField('AccentColor', $flags)
    $accent = $accentField.GetValue($null)
    $accentMatches = $accent.R -eq 52 -and $accent.G -eq 190 -and $accent.B -eq 208
    $passed = $rendererMatches -and $minimumWidth -and $comfortablePadding -and $accentMatches

    [pscustomobject]@{
        CustomRenderer = $rendererMatches
        MinimumWidth248 = $minimumWidth
        MenuPaddingTop = $menu.Padding.Top
        ItemPaddingTop = $item.Padding.Top
        ComfortableSpacing = $comfortablePadding
        BoltAccentColor = $accentMatches
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
