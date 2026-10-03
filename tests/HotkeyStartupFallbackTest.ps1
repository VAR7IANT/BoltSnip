param([string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class StartupFallbackNative { [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr h,int id,uint mods,uint key); [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr h,int id); }'
$asm=[Reflection.Assembly]::LoadFile((Resolve-Path -LiteralPath $Executable).Path)
$flags=[Reflection.BindingFlags]'Instance,NonPublic,Public'
$gt=$asm.GetType('BoltSnip.HotkeyGesture',$true)
$ctor=$gt.GetConstructor($flags,$null,[Type[]]@([uint32],[Windows.Forms.Keys]),$null)
$wt=$asm.GetType('BoltSnip.HotkeyWindow',$true)
$window=$null;$occupied=$false;$id=0x6B10
try {
 if(-not [StartupFallbackNative]::RegisterHotKey([IntPtr]::Zero,$id,0x4006,0x41)){throw 'Ctrl+Shift+A unavailable; startup fallback cannot be tested.'}
 [void][StartupFallbackNative]::UnregisterHotKey([IntPtr]::Zero,$id)
 $keys=@();foreach($key in 0x7c..0x87){if([StartupFallbackNative]::RegisterHotKey([IntPtr]::Zero,$id,0x4006,$key)){[void][StartupFallbackNative]::UnregisterHotKey([IntPtr]::Zero,$id);$keys+=$key}}
 if($keys.Count -lt 2){throw 'Two available isolated keys required.'}
 $preferred=$ctor.Invoke([object[]]@([uint32]6,[Windows.Forms.Keys]$keys[0]))
 $replay=$ctor.Invoke([object[]]@([uint32]6,[Windows.Forms.Keys]$keys[1]))
 $occupied=[StartupFallbackNative]::RegisterHotKey([IntPtr]::Zero,$id,0x4006,$keys[0]);if(-not $occupied){throw 'Occupancy setup failed.'}
 $window=$wt.GetConstructor($flags,$null,[Type[]]@([Action],[Action],$gt,$gt),$null).Invoke([object[]]@([Action]{},[Action]{},$preferred,$replay))
 $actual=$wt.GetProperty('CaptureGesture',$flags).GetValue($window,$null)
 $fallback=$ctor.Invoke([object[]]@([uint32]6,[Windows.Forms.Keys]::A))
 $passed=$actual.Equals($fallback) -and $wt.GetProperty('CaptureIsRegistered',$flags).GetValue($window,$null) -and $wt.GetProperty('ReplaySaveIsRegistered',$flags).GetValue($window,$null)
 [pscustomobject]@{OccupiedPreferredUsesProductFallback=$passed;ActualShortcut=$actual.ToString();Passed=$passed}|Format-List
 if(-not $passed){exit 1}
}finally{if($window){$window.Dispose()};if($occupied){[void][StartupFallbackNative]::UnregisterHotKey([IntPtr]::Zero,$id)}}