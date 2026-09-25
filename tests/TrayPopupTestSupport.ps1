function New-TrayPopupTestForm {
    param([string]$Executable)

    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    $assembly = [Reflection.Assembly]::LoadFile((Resolve-Path -LiteralPath $Executable).Path)
    $popupType = $assembly.GetType('BoltSnip.TrayPopupForm', $true)
    $actionType = [Type[]]@(
        [Action], [Action], [Action], [Action],
        [Action], [Action], [Action], [Action])
    $constructor = $popupType.GetConstructor(
        [Reflection.BindingFlags]'Instance,NonPublic',
        $null,
        $actionType,
        $null)
    if ($null -eq $constructor) {
        throw 'TrayPopupForm callback constructor was not found.'
    }

    $noop = [Action] { }
    return $constructor.Invoke([object[]]@(
        $noop, $noop, $noop, $noop,
        $noop, $noop, $noop, $noop))
}
