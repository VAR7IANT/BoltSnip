param([string]$Executable, [string]$WorkDirectory)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot 'TrayPopupTestSupport.ps1')
[IO.Directory]::CreateDirectory($WorkDirectory) | Out-Null
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable).Path)
$flags = [Reflection.BindingFlags]'NonPublic,Instance,Static'
$type = $assembly.GetType('BoltSnip.AppSettings', $true)
$load = $type.GetMethod('Load', $flags, $null, [Type[]]@([string],[string]), $null)
$save = $type.GetMethod('Save', $flags, $null, [Type[]]@(), $null)
$option = $type.GetProperty('AutoStartReplay', $flags)
$path = Join-Path $WorkDirectory 'settings.ini'
$missing = Join-Path $WorkDirectory 'missing.ini'
function Assert($condition, $message) { if (-not $condition) { throw $message } }
$settings = $load.Invoke($null, [object[]]@([string]$missing,[string]$missing))
Assert (-not $option.GetValue($settings, $null)) 'New settings must default to off'
[IO.File]::WriteAllText($path, "Modifiers=6" + [Environment]::NewLine + "Key=65")
$settings = $load.Invoke($null, [object[]]@([string]$path,[string]$missing))
Assert (-not $option.GetValue($settings, $null)) 'Migrated settings must default to off'
$option.SetValue($settings, $true, $null)
$save.Invoke($settings, @())
$settings = $load.Invoke($null, [object[]]@([string]$path,[string]$missing))
Assert ($option.GetValue($settings, $null)) 'Enabled option did not survive reload'
$option.SetValue($settings, $false, $null)
$save.Invoke($settings, @())
$settings = $load.Invoke($null, [object[]]@([string]$path,[string]$missing))
Assert (-not $option.GetValue($settings, $null)) 'Disabled option did not survive reload'
[IO.File]::WriteAllText($path, 'AutoStartReplay=invalid')
$settings = $load.Invoke($null, [object[]]@([string]$path,[string]$missing))
Assert (-not $option.GetValue($settings, $null)) 'Invalid value must default to off'
$popup = New-TrayPopupTestForm $Executable
try {
    $popupType = $popup.GetType()
    $actionType = $assembly.GetType('BoltSnip.TrayPopupAction', $true)
    $action = [Enum]::Parse($actionType, 'AutoStartReplay')
    $boundsMethod = $popupType.GetMethod('GetLogicalBounds', $flags)
    $script:clicks = 0
    $popupType.GetProperty('ToggleAutoStartReplay', $flags).SetValue($popup, [Action]{ $script:clicks++ }, $null)
    $popupType.GetMethod('InvokeAction', $flags).Invoke($popup, [object[]]@($action))
    Assert ($script:clicks -eq 1) 'Toggle callback was not invoked once'
    foreach ($license in @($false,$true)) {
        $popupType.GetMethod('UpdatePresentation', $flags).Invoke($popup, [object[]]@('2.0.1','Ctrl+Alt+A','Ctrl+Alt+S',$true,$license))
        foreach ($dpi in @(96,120,144,192)) {
            $popupType.GetMethod('ApplyDpi', $flags).Invoke($popup, [object[]]@($dpi))
            $bounds = $boundsMethod.Invoke($null, [object[]]@($action,$license))
            $point = [Drawing.Point]::new([int](($bounds.X+100)*$dpi/96),[int](($bounds.Y+16)*$dpi/96))
            $hit = $popupType.GetMethod('ActionAt', $flags).Invoke($popup, [object[]]@($point))
            Assert ($hit -eq $action) "Incorrect hit target at DPI $dpi"
            $exit = $boundsMethod.Invoke($null, [object[]]@([Enum]::Parse($actionType,'Exit'),$license))
            Assert ($exit.Top -gt $bounds.Bottom) 'Settings and exit overlap'
            $popupType.GetMethod('UpdateAutoStartReplay', $flags).Invoke($popup, [object[]]@($true))
            $bitmap = [Drawing.Bitmap]::new($popup.Width,$popup.Height)
            try { $popup.DrawToBitmap($bitmap, $popup.ClientRectangle); $bitmap.Save((Join-Path $WorkDirectory ("popup-$license-$dpi.png"))) }
            finally { $bitmap.Dispose() }
        }
    }
} finally { $popup.Dispose() }
'AutoStartReplay: defaults, migration, on/off persistence, invalid input, callback, DPI hit targets and layout PASS'