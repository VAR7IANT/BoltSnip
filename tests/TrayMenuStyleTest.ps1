param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot 'TrayPopupTestSupport.ps1')

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$styleType = $assembly.GetType('BoltSnip.BoltSnipMenuStyle', $true)
$rendererType = $assembly.GetType('BoltSnip.BoltSnipMenuRenderer', $true)
$popupType = $assembly.GetType('BoltSnip.TrayPopupForm', $true)
$contextType = $assembly.GetType('BoltSnip.TrayApplicationContext', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$apply = $styleType.GetMethod('Apply', $flags)
$applyItem = $styleType.GetMethod('ApplyItem', $flags)

$menu = New-Object Windows.Forms.ContextMenuStrip
$font = New-Object Drawing.Font 'Microsoft YaHei UI', 9.25
$item = New-Object Windows.Forms.ToolStripMenuItem 'Capture'
$popup = $null
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

    $popup = New-TrayPopupTestForm -Executable $Executable
    $popupSize = $popupType.GetMethod('GetLogicalSize', $flags).Invoke($null, [object[]]@($false))
    $replayTitleWidth = $popupType.GetField('ReplayTitleLogicalWidth', $flags).GetRawConstantValue()
    $contextFlags = [Reflection.BindingFlags]'Instance,NonPublic'
    $popupField = $contextType.GetField('_trayPopup', $contextFlags)
    $contextHasCustomPopup = $null -ne $popupField -and $popupField.FieldType -eq $popupType
    $usesDefaultTrayMenu = @($contextType.GetFields($contextFlags) | Where-Object {
        $_.FieldType -eq [Windows.Forms.ContextMenuStrip]
    }).Count -gt 0
    $popupPresentation = $popup.FormBorderStyle -eq [Windows.Forms.FormBorderStyle]::None -and
        -not $popup.ShowInTaskbar -and $popup.AutoScaleMode -eq [Windows.Forms.AutoScaleMode]::None -and
        $popupSize.Width -eq 336 -and $popupSize.Height -eq 430 -and
        $replayTitleWidth -eq 158 -and
        $contextHasCustomPopup -and -not $usesDefaultTrayMenu
    $passed = $rendererMatches -and $minimumWidth -and $comfortablePadding -and $accentMatches -and $popupPresentation

    [pscustomobject]@{
        LicenseDialogMenuRenderer = $rendererMatches
        LegacyDialogMinimumWidth248 = $minimumWidth
        LegacyDialogComfortableSpacing = $comfortablePadding
        LegacyDialogAccent = $accentMatches
        TrayUsesBorderlessCustomPopup = $contextHasCustomPopup -and -not $usesDefaultTrayMenu
        PopupHasCompactDpiAwareLayout = $popupPresentation
        ReplayTitleHasRoomForFullLabel = $replayTitleWidth -eq 158
        Passed = $passed
    } | Format-List

    if (-not $passed) {
        exit 1
    }
}
finally {
    if ($null -ne $popup) { $popup.Dispose() }
    $menu.Dispose()
    $font.Dispose()
}
