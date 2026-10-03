param(
    [Parameter(Mandatory=$true)][string]$Executable,
    [Parameter(Mandatory=$true)][string]$FfmpegPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [ValidateSet('ddagrab','gdigrab')][string]$Backend='ddagrab',
    [string]$ExpectedBuildId='',
    [switch]$ValidateOnly
)
# Fresh Windows PowerShell -STA process. Desktop execution is opt-in by invocation.
# SendInput tests OS hotkey delivery, never a claim of a physical human key press.
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RecordingHotkeyNative {
 [DllImport("user32.dll",SetLastError=true)] public static extern bool RegisterHotKey(IntPtr window,int id,uint modifiers,uint key);
 [DllImport("user32.dll",SetLastError=true)] public static extern bool UnregisterHotKey(IntPtr window,int id);
 [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx,dy; public uint mouseData,flags,time; public UIntPtr extra; }
 [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk,scan; public uint flags,time; public UIntPtr extra; }
 [StructLayout(LayoutKind.Sequential)] struct HARDWAREINPUT { public uint message; public ushort low,high; }
 [StructLayout(LayoutKind.Explicit)] struct INPUTUNION {
  [FieldOffset(0)] public MOUSEINPUT mouse;
  [FieldOffset(0)] public KEYBDINPUT keyboard;
  [FieldOffset(0)] public HARDWAREINPUT hardware;
 }
 [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public INPUTUNION data; }
 [DllImport("user32.dll",SetLastError=true)] static extern uint SendInput(uint count,INPUT[] inputs,int size);
 [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
 static void Key(ushort vk,bool up) {
  var item=new INPUT(); item.type=1; item.data.keyboard.vk=vk; item.data.keyboard.flags=up?2u:0u;
  if(SendInput(1,new INPUT[]{item},Marshal.SizeOf(typeof(INPUT)))!=1)
   throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(),"SendInput keyboard event failed; UIPI may block input");
 }
 public static void InjectShortcut(ushort functionKey) {
  ushort[] keys=new ushort[]{0x11,0x10,functionKey};
  foreach(ushort key in keys) if((GetAsyncKeyState(key)&0x8000)!=0) throw new InvalidOperationException("An injection key is already held; release modifiers and retry");
  int pressed=0;
  try {
   foreach(ushort key in keys){Key(key,false);pressed++;}
   System.Threading.Thread.Sleep(60);
  } finally {
   // Attempt every release even when one SendInput call fails.
   Exception failure=null;
   for(int index=pressed-1;index>=0;index--){try{Key(keys[index],true);}catch(Exception error){failure=error;}}
   if(failure!=null)throw failure;
  }
 }
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
if($ValidateOnly) { 'PASS: native helper compiled; no Forms, manager, desktop or capture created.'; return }
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Run with powershell.exe -STA -File.' }
[RecordingHotkeyNative]::EnableDpi()
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$Executable=(Resolve-Path -LiteralPath $Executable).Path
$FfmpegPath=(Resolve-Path -LiteralPath $FfmpegPath).Path
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $OutputDirectory) { throw 'Output directory must be new.' }
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$envNames=@('TEMP','TMP','BOLTSNIP_REPLAY_CAPTURE_BACKEND','BOLTSNIP_FFMPEG_PATH','BOLTSNIP_REPLAY_OUTPUT_DIRECTORY','BOLTSNIP_DIAGNOSTIC_LOG_PATH','BOLTSNIP_DIAGNOSTIC_LOG')
$oldEnv=@{}; foreach($name in $envNames) { $oldEnv[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
$flags=[Reflection.BindingFlags]'Instance,NonPublic,Public'
$staticFlags=[Reflection.BindingFlags]'Static,NonPublic,Public'
$assembly=[Reflection.Assembly]::LoadFile($Executable)
$metadata=@{}; foreach($item in $assembly.GetCustomAttributes($false)) { if($item.GetType().FullName -eq 'System.Reflection.AssemblyMetadataAttribute') { $metadata[$item.Key]=$item.Value } }
if($ExpectedBuildId -and $metadata.BuildId -ne $ExpectedBuildId) { throw 'BuildId mismatch.' }
$manager=$null; $window=$null; $dialog=$null; $events=$null; $failure=$null; $before=$null; $after=$null; $saveAfter=$null; $screenshot=$null
$callback=[pscustomobject]@{Calls=0;Accepted=$false}
function Get-Value($Object,[string]$Name) { $Object.GetType().GetProperty($Name,$flags).GetValue($Object.PSObject.BaseObject,$null) }
function Get-Field($Object,[string]$Name) { $Object.GetType().GetField($Name,$flags).GetValue($Object.PSObject.BaseObject) }
function Invoke-Reflection($Method,$Target,[object[]]$Arguments=@()) {
 # Pipeline and Join-Path results may carry PSObject wrappers inside object[].
 # Reflection does not apply PowerShell's normal argument binder conversions.
 $parameters=$Method.GetParameters()
 $normalized=New-Object 'object[]' $Arguments.Length
 for($index=0;$index -lt $Arguments.Length;$index++) {
  $value=$Arguments[$index]
  if($null -ne $value) {
   $value=$value.PSObject.BaseObject
   $parameterType=$parameters[$index].ParameterType
   if($parameterType.IsByRef){$parameterType=$parameterType.GetElementType()}
   if(-not $parameterType.IsInstanceOfType($value)) { $value=[Management.Automation.LanguagePrimitives]::ConvertTo($value,$parameterType) }
   $normalized[$index]=$value.PSObject.BaseObject
  } else { $normalized[$index]=$null }
 }
 if($Method -is [Reflection.ConstructorInfo]) { return $Method.Invoke($normalized) }
 if($null -ne $Target){$Target=$Target.PSObject.BaseObject}
 return $Method.Invoke($Target,$normalized)
}
function Invoke-Method($Object,[string]$Name,[object[]]$Arguments=@()) { Invoke-Reflection ($Object.GetType().GetMethod($Name,$flags)) $Object $Arguments }
function Get-Snapshot([string]$Event) {
 $encoder=Get-Field $manager '_encoder'; $process=$null; if($encoder) { $process=Get-Field $encoder '_process' }
 $buffer=Get-Field $manager '_buffer'; $pipe=$null; $encoderPid=$null; $started=$null; $exited=$null
 if($process) {
  $encoderPid=$process.Id; $started=$process.StartTime.ToUniversalTime().ToString('O'); $exited=$process.HasExited
  $match=[regex]::Match($process.StartInfo.Arguments,'BoltSnipReplayAudio-[a-fA-F0-9]{32}')
  if($match.Success) { $pipe=$match.Value }
 }
 $result=[pscustomobject]@{Event=$Event;Qpc=[Diagnostics.Stopwatch]::GetTimestamp();State=[string](Get-Value $manager 'State');AudioState=[string](Get-Value $manager 'AudioState');BufferedSeconds=[double](Get-Value $manager 'BufferedDurationSeconds');Segments=[int](Get-Value $manager 'BufferedSegmentCount');AudioInputSeconds=[double](Get-Value $manager 'AudioInputDurationSeconds');EncoderPID=$encoderPid;EncoderStartUtc=$started;EncoderExited=$exited;AudioPipe=$pipe;BufferIdentity=if($buffer){[Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($buffer)}else{$null};StopRequested=[bool](Get-Field $manager '_stopRequested');IsSaving=[bool](Get-Value $manager 'IsSaving')}
 $events.WriteLine(($result | ConvertTo-Json -Compress)); $events.Flush(); return $result
}
function Assert-Continuous($Reference,$Current) {
 if($Current.State -ne 'Recording' -or $Current.AudioState -ne 'Active' -or $Current.StopRequested -or $Current.EncoderExited -or
 $Current.EncoderPID -ne $Reference.EncoderPID -or $Current.EncoderStartUtc -ne $Reference.EncoderStartUtc -or
 -not $Current.AudioPipe -or $Current.AudioPipe -ne $Reference.AudioPipe -or $Current.BufferIdentity -ne $Reference.BufferIdentity -or
 $Current.BufferedSeconds -lt 60) { throw ('Recording continuity failed: '+($Current|ConvertTo-Json -Compress)) }
}
function Test-GestureAvailable([int]$Key) {
 $registered=[RecordingHotkeyNative]::RegisterHotKey([IntPtr]::Zero,0x6B01,[uint32]0x4006,[uint32]$Key)
 if($registered -and -not [RecordingHotkeyNative]::UnregisterHotKey([IntPtr]::Zero,0x6B01)) { throw 'Availability probe cleanup failed.' }
 return $registered
}
try {
 $temp=Join-Path $OutputDirectory 'temp'; [IO.Directory]::CreateDirectory($temp)|Out-Null
 $env:TEMP=$temp; $env:TMP=$temp; $env:BOLTSNIP_REPLAY_CAPTURE_BACKEND=$Backend; $env:BOLTSNIP_FFMPEG_PATH=$FfmpegPath
 $env:BOLTSNIP_REPLAY_OUTPUT_DIRECTORY=Join-Path $OutputDirectory 'replays'; $env:BOLTSNIP_DIAGNOSTIC_LOG_PATH=Join-Path $OutputDirectory 'diagnostic.log'; $env:BOLTSNIP_DIAGNOSTIC_LOG='1'
 $events=New-Object IO.StreamWriter((Join-Path $OutputDirectory 'lifecycle.jsonl'),$false)
 $manager=[Activator]::CreateInstance($assembly.GetType('BoltSnip.ReplayManager',$true),$true)
 Invoke-Method $manager 'Start' | Out-Null
 $deadline=[DateTime]::UtcNow.AddSeconds(100)
 do {
  $current=Get-Snapshot 'AccumulatingBuffer'
  if($current.State -eq 'Error') { throw [string](Get-Value $manager 'LastError') }
  if($current.State -eq 'Recording' -and $current.AudioState -eq 'Active' -and $current.BufferedSeconds -ge 60) { break }
  [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100
 } while([DateTime]::UtcNow -lt $deadline)
 if($current.State -ne 'Recording' -or $current.AudioState -ne 'Active' -or $current.BufferedSeconds -lt 60) { throw '60-second audio-active buffer was not reached.' }
 $available=@(0x7C..0x87 | Where-Object { Test-GestureAvailable $_ }); if($available.Count -lt 3) { throw 'Three available isolated F13-F24 gestures required.' }
 $captureKey=$available[0]; $oldKey=$available[1]; $newKey=$available[2]
 $settingsPath=Join-Path $OutputDirectory 'settings.ini'
 [IO.File]::WriteAllText($settingsPath,"CaptureModifiers=6`r`nCaptureKey=$captureKey`r`nReplaySaveModifiers=6`r`nReplaySaveKey=$oldKey`r`nSaveDirectory=$OutputDirectory`r`n")
 $settingsType=$assembly.GetType('BoltSnip.AppSettings',$true)
 $legacyPath=[string](Join-Path $OutputDirectory 'legacy.ini')
 $loadMethod=$settingsType.GetMethod('Load',$staticFlags,$null,[Type[]]@([string],[string]),$null)
 $settings=Invoke-Reflection $loadMethod $null ([object[]]@([string]$settingsPath,[string]$legacyPath))
 $gestureType=$assembly.GetType('BoltSnip.HotkeyGesture',$true)
 $windowType=$assembly.GetType('BoltSnip.HotkeyWindow',$true)
 $replayAction=[Action]{$callback.Calls++;$callback.Accepted=[bool](Invoke-Method $manager 'SaveReplay')}.GetNewClosure()
 $windowConstructor=$windowType.GetConstructor($flags,$null,[Type[]]@([Action],[Action],$gestureType,$gestureType),$null)
 $window=Invoke-Reflection $windowConstructor $null ([object[]]@([Action]{},$replayAction,(Get-Value $settings 'CaptureHotkey'),(Get-Value $settings 'ReplaySaveHotkey')))
 if(-not (Get-Value $window 'ReplaySaveIsRegistered') -or -not (Get-Value $window 'CaptureIsRegistered')) { throw 'Initial hotkey registration failed.' }
 $before=Get-Snapshot 'BeforeSettings'
 $dialogType=$assembly.GetType('BoltSnip.HotkeySettingsDialog',$true)
 $dialogConstructor=$dialogType.GetConstructor($flags,$null,[Type[]]@($settingsType,$windowType),$null)
 $dialog=Invoke-Reflection $dialogConstructor $null ([object[]]@($settings,$window))
 Invoke-Method $window 'SetCallbacksSuppressed' @($true)|Out-Null
 $dialog.Show(); [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 300
 $dialog.Activate(); [Windows.Forms.Application]::DoEvents()
 $dpi=[RecordingHotkeyNative]::GetDpiForWindow($dialog.Handle)
 $rect=$dialog.Bounds; $bitmap=New-Object Drawing.Bitmap($rect.Width,$rect.Height); $graphics=[Drawing.Graphics]::FromImage($bitmap)
 try { $graphics.CopyFromScreen($rect.Location,[Drawing.Point]::Empty,$rect.Size); $screenshot=Join-Path $OutputDirectory 'hotkey-real-desktop-current-dpi.png';$bitmap.Save($screenshot,[Drawing.Imaging.ImageFormat]::Png) } finally { $graphics.Dispose();$bitmap.Dispose() }
 $slot=[Enum]::ToObject($assembly.GetType('BoltSnip.HotkeySlot',$true),1)
 Invoke-Method $dialog 'BeginRecording' @($slot)|Out-Null
 $keyArgs=[object[]]@([Windows.Forms.Message]::Create([IntPtr]::Zero,0,[IntPtr]::Zero,[IntPtr]::Zero),([Windows.Forms.Keys]($newKey -bor [int][Windows.Forms.Keys]::Control -bor [int][Windows.Forms.Keys]::Shift)))
 Invoke-Reflection ($dialogType.GetMethod('ProcessCmdKey',$flags)) $dialog $keyArgs|Out-Null
 Invoke-Method $dialog 'SaveButtonClick' @($null,[EventArgs]::Empty)|Out-Null
 if($dialog.DialogResult -ne [Windows.Forms.DialogResult]::OK) { throw 'Hotkey dialog did not save successfully.' }
 Invoke-Method $window 'SetCallbacksSuppressed' @($false)|Out-Null
 $oldReleased=Test-GestureAvailable $oldKey; $newOccupied=-not (Test-GestureAvailable $newKey)
 if(-not $oldReleased -or -not $newOccupied) { throw 'Old/new OS registration state incorrect.' }
 $after=Get-Snapshot 'AfterSettings'; Assert-Continuous $before $after
 if($callback.Calls -ne 0) { throw 'Unexpected callback while editing settings.' }
 # Pump the real Windows message queue after OS keyboard injection. No direct
 # WM_HOTKEY construction: old gesture must stop delivering the replay action.
 [RecordingHotkeyNative]::InjectShortcut([uint16]$oldKey)
 $oldDeadline=[DateTime]::UtcNow.AddMilliseconds(600)
 do { [Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 20 }while([DateTime]::UtcNow -lt $oldDeadline)
 $oldCallbackCalls=$callback.Calls
 if($oldCallbackCalls -ne 0){throw 'Old shortcut still delivered a callback after change.'}
 Assert-Continuous $before (Get-Snapshot 'AfterOldKeyboardInput')
 [RecordingHotkeyNative]::InjectShortcut([uint16]$newKey)
 $newDeadline=[DateTime]::UtcNow.AddSeconds(2)
 do { [Windows.Forms.Application]::DoEvents();if($callback.Calls -gt 0){break};Start-Sleep -Milliseconds 20 }while([DateTime]::UtcNow -lt $newDeadline)
 if($callback.Calls -ne 1 -or -not $callback.Accepted) { throw 'New OS hotkey delivery did not accept exactly one save.' }
 $deadline=[DateTime]::UtcNow.AddSeconds(40)
 do { $saveAfter=Get-Snapshot 'SavePoll'; Assert-Continuous $before $saveAfter; if(-not $saveAfter.IsSaving){break};[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 100 }while([DateTime]::UtcNow -lt $deadline)
 if($saveAfter.IsSaving){throw 'Save did not complete.'}
 $saved=@(Get-ChildItem -LiteralPath $env:BOLTSNIP_REPLAY_OUTPUT_DIRECTORY -Filter '*.mp4' -File)
 if($saved.Count -ne 1 -or $saved[0].Length -le 0){throw 'Expected exactly one saved replay.'}
 $reloaded=Invoke-Reflection $loadMethod $null ([object[]]@([string]$settingsPath,[string]$legacyPath))
 if(-not (Get-Value $reloaded 'ReplaySaveHotkey').Equals((Get-Value $window 'ReplaySaveGesture'))){throw 'Persisted gesture mismatch.'}
} catch { $failure=$_.Exception.ToString() }
finally {
 if($dialog){$dialog.Dispose()};if($window){$window.Dispose()}
 # Stop is invoked only after all change/save measurements, solely for cleanup.
 if($manager){try{Invoke-Method $manager 'Stop'|Out-Null;Invoke-Method $manager 'Dispose'|Out-Null}catch{$failure=([string]$failure+'; Cleanup: '+$_.Exception.ToString())}}
 if($events){$events.Dispose()};foreach($name in $oldEnv.Keys){[Environment]::SetEnvironmentVariable($name,$oldEnv[$name],'Process')}
}
$report=[ordered]@{Executable=$Executable;ExecutableSHA256=(Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash;BuildId=$metadata.BuildId;Backend=$Backend;Before=$before;AfterChange=$after;AfterSave=$saveAfter;OldGestureReleased=$oldReleased;NewGestureOccupied=$newOccupied;OldKeyboardCallbackCalls=$oldCallbackCalls;CallbackCalls=$callback.Calls;SaveAccepted=$callback.Accepted;ActualWindowDpi=$dpi;DesktopScreenshot=$screenshot;Failure=$failure;Passed=($null -eq $failure);KeyboardEvidence='Synthetic OS keyboard input through SendInput + actual WM_HOTKEY queue delivery; old shortcut must yield 0 callbacks, new shortcut 1; no physical human key press tested';AudioIdentityEvidence='Unique session pipe GUID in unchanged FFmpeg command + Active state; local audio object is not exposed';AudioInputSecondsSemantics='ReplayManager caches WrittenDurationSeconds only in recording-loop finally cleanup; zero during recording is not live duration evidence';StopCallEvidence='Settings source call chain contains no Stop; runtime samples require StopRequested=false; no method-entry instrumentation';VisualVerdict='Screenshot requires independent inspection; other system DPIs not tested'}
$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $OutputDirectory 'result.json') -Encoding UTF8
$report|ConvertTo-Json -Depth 8
if($failure){exit 1}
