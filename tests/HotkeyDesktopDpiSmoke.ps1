param(
 [Parameter(Mandatory=$true)][string]$Executable,
 [Parameter(Mandatory=$true)][string]$OutputDirectory,
 [switch]$ValidateOnly
)
# Fresh Windows PowerShell -STA. No ReplayManager, recording or keyboard injection.
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HotkeyDpiSmokeNative {
 [DllImport("user32.dll",SetLastError=true)] public static extern bool RegisterHotKey(IntPtr window,int id,uint modifiers,uint key);
 [DllImport("user32.dll",SetLastError=true)] public static extern bool UnregisterHotKey(IntPtr window,int id);
 [DllImport("user32.dll",SetLastError=true)] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr window);
 [DllImport("user32.dll")] static extern IntPtr GetThreadDpiAwarenessContext();
 [DllImport("user32.dll")] static extern int GetAwarenessFromDpiAwarenessContext(IntPtr context);
 public static void EnableDpi() {
  SetProcessDpiAwarenessContext(new IntPtr(-4));
  if(SetThreadDpiAwarenessContext(new IntPtr(-4))==IntPtr.Zero || GetAwarenessFromDpiAwarenessContext(GetThreadDpiAwarenessContext())!=2)
   throw new InvalidOperationException("Per-monitor DPI awareness unavailable");
 }
}
'@
if($ValidateOnly){'PASS: native compiled; no Forms/window created.';return}
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Use powershell.exe -STA.'}
[HotkeyDpiSmokeNative]::EnableDpi()
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$Executable=(Resolve-Path -LiteralPath $Executable).Path
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $OutputDirectory){throw 'Use a new evidence directory.'}
[IO.Directory]::CreateDirectory($OutputDirectory)|Out-Null
$assembly=[Reflection.Assembly]::LoadFile($Executable)
$flags=[Reflection.BindingFlags]'Instance,NonPublic,Public'
$staticFlags=[Reflection.BindingFlags]'Static,NonPublic,Public'
$window=$null;$dialog=$null;$failure=$null;$labels=New-Object 'System.Collections.Generic.List[object]'
function Invoke-Reflection($Method,$Target,[object[]]$Arguments=@()) {
 $parameters=$Method.GetParameters();$normalized=New-Object 'object[]' $Arguments.Length
 for($i=0;$i -lt $Arguments.Length;$i++){
  $value=$Arguments[$i]
  if($null -ne $value){$value=$value.PSObject.BaseObject;$expected=$parameters[$i].ParameterType;if($expected.IsByRef){$expected=$expected.GetElementType()};if(-not $expected.IsInstanceOfType($value)){$value=[Management.Automation.LanguagePrimitives]::ConvertTo($value,$expected)};$normalized[$i]=$value.PSObject.BaseObject}
 }
 if($Method -is [Reflection.ConstructorInfo]){return $Method.Invoke($normalized)}
 if($null -ne $Target){$Target=$Target.PSObject.BaseObject}
 return $Method.Invoke($Target,$normalized)
}
function Inspect-Controls($Parent,[string]$Path){
 foreach($control in $Parent.Controls){
  $name=$Path+'/'+$control.GetType().Name+':'+$control.Text
  $boundsInside=$Parent.ClientRectangle.Contains($control.Bounds)
  if(-not $boundsInside){throw ('Control bounds leave parent: '+$name+' '+$control.Bounds)}
  if($control -is [Windows.Forms.Label]){
   $graphics=$control.CreateGraphics()
   try{$size=[Windows.Forms.TextRenderer]::MeasureText($graphics,$control.Text,$control.Font,[Drawing.Size]::Empty,[Windows.Forms.TextFormatFlags]([int][Windows.Forms.TextFormatFlags]::NoPadding -bor [int][Windows.Forms.TextFormatFlags]::SingleLine))}
   finally{$graphics.Dispose()}
   $heightFits=$size.Height -le $control.ClientSize.Height
   $widthFits=$size.Width -le $control.ClientSize.Width
   $labels.Add([pscustomobject]@{Path=$name;Text=$control.Text;Bounds=[string]$control.Bounds;FontSizePt=$control.Font.SizeInPoints;TextWidth=$size.Width;TextHeight=$size.Height;ClientWidth=$control.ClientSize.Width;ClientHeight=$control.ClientSize.Height;BoundsInsideParent=$boundsInside;TextHeightFits=$heightFits;TextWidthFits=$widthFits})
   if(-not $heightFits -or -not $widthFits){throw ('Label text does not fit: '+$name)}
  }
  Inspect-Controls $control $name
 }
}
try{
 $keys=New-Object 'System.Collections.Generic.List[int]'
 foreach($key in 0x7C..0x87){
  if([HotkeyDpiSmokeNative]::RegisterHotKey([IntPtr]::Zero,0x6B11,[uint32]0x4006,[uint32]$key)){
   if(-not [HotkeyDpiSmokeNative]::UnregisterHotKey([IntPtr]::Zero,0x6B11)){throw 'Availability probe cleanup failed.'};$keys.Add($key)
  }
 }
 if($keys.Count -lt 2){throw 'Two free Ctrl+Shift+F13-F24 gestures required.'}
 $settingsPath=[string](Join-Path $OutputDirectory 'settings.ini');$legacyPath=[string](Join-Path $OutputDirectory 'legacy.ini')
 [IO.File]::WriteAllText($settingsPath,"CaptureModifiers=6`r`nCaptureKey=$($keys[0])`r`nReplaySaveModifiers=6`r`nReplaySaveKey=$($keys[1])`r`nSaveDirectory=$OutputDirectory`r`n")
 $settingsType=$assembly.GetType('BoltSnip.AppSettings',$true);$gestureType=$assembly.GetType('BoltSnip.HotkeyGesture',$true);$windowType=$assembly.GetType('BoltSnip.HotkeyWindow',$true);$dialogType=$assembly.GetType('BoltSnip.HotkeySettingsDialog',$true)
 $load=$settingsType.GetMethod('Load',$staticFlags,$null,[Type[]]@([string],[string]),$null)
 $settings=Invoke-Reflection $load $null ([object[]]@([string]$settingsPath,[string]$legacyPath))
 $capture=$settingsType.GetProperty('CaptureHotkey',$flags).GetValue($settings.PSObject.BaseObject,$null)
 $replay=$settingsType.GetProperty('ReplaySaveHotkey',$flags).GetValue($settings.PSObject.BaseObject,$null)
 $ctor=$windowType.GetConstructor($flags,$null,[Type[]]@([Action],[Action],$gestureType,$gestureType),$null)
 $window=Invoke-Reflection $ctor $null ([object[]]@([Action]{},[Action]{},$capture,$replay))
 if(-not $windowType.GetProperty('CaptureIsRegistered',$flags).GetValue($window.PSObject.BaseObject,$null) -or -not $windowType.GetProperty('ReplaySaveIsRegistered',$flags).GetValue($window.PSObject.BaseObject,$null)){throw 'Isolated shortcuts unavailable.'}
 $ctor=$dialogType.GetConstructor($flags,$null,[Type[]]@($settingsType,$windowType),$null)
 $dialog=Invoke-Reflection $ctor $null ([object[]]@($settings,$window))
 $dialog.Show();$dialog.Activate()
 $deadline=[DateTime]::UtcNow.AddMilliseconds(500)
 do{[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 20}while([DateTime]::UtcNow -lt $deadline)
 $actualDpi=[int][HotkeyDpiSmokeNative]::GetDpiForWindow($dialog.Handle)
 $layoutDpi=[int]$dialogType.GetField('_dpi',$flags).GetValue($dialog.PSObject.BaseObject)
 $expectedWidth=[int][Math]::Floor(396*$actualDpi/96.0+0.5);$expectedHeight=[int][Math]::Floor(297*$actualDpi/96.0+0.5)
 $actualWidth=$dialog.ClientSize.Width;$actualHeight=$dialog.ClientSize.Height
 $rect=$dialog.Bounds;$bitmap=New-Object Drawing.Bitmap($rect.Width,$rect.Height);$graphics=[Drawing.Graphics]::FromImage($bitmap)
 $screenshot=[string](Join-Path $OutputDirectory 'hotkey-current-real-dpi.png')
 try{$graphics.CopyFromScreen($rect.Location,[Drawing.Point]::Empty,$rect.Size);$bitmap.Save($screenshot,[Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$bitmap.Dispose()}
 if($actualDpi -le 0 -or $layoutDpi -ne $actualDpi -or $actualWidth -ne $expectedWidth -or $actualHeight -ne $expectedHeight){throw 'Native DPI/layout/client dimensions disagree.'}
 Inspect-Controls $dialog 'Dialog'
}catch{$failure=$_.Exception.ToString()}
finally{if($dialog){$dialog.Dispose()};if($window){$window.Dispose()}}
$result=[ordered]@{Executable=$Executable;ExecutableSHA256=(Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash;ActualWindowDpi=$actualDpi;LayoutDpi=$layoutDpi;ExpectedClientWidth=$expectedWidth;ExpectedClientHeight=$expectedHeight;ActualClientWidth=$actualWidth;ActualClientHeight=$actualHeight;LabelChecks=$labels.ToArray();Screenshot=$screenshot;Failure=$failure;Passed=($null -eq $failure);Limitations='Current real desktop DPI only; screenshot requires visual inspection; no recording or other system DPI tested'}
$result|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $OutputDirectory 'result.json') -Encoding UTF8
$result|ConvertTo-Json -Depth 7
if($failure){exit 1}
