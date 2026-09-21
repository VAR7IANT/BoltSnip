param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)
$ErrorActionPreference='Stop'
$logPath = Join-Path $env:TEMP ('BoltSnip-diagnostic-' + [Guid]::NewGuid().ToString('N') + '.log')
$env:BOLTSNIP_DIAGNOSTIC_LOG='1'
$env:BOLTSNIP_DIAGNOSTIC_LOG_PATH=$logPath
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System; using System.Collections.Generic; using System.Drawing; using System.IO;
public sealed class DiagnosticHarness {
 public string Save(){return Path.GetTempPath();} public Bitmap Capture(Rectangle r){return new Bitmap(32,32);}
 public List<Rectangle> Snapshot(Rectangle r){return new List<Rectangle>();} public void Show(){} public void Fail(){throw new InvalidOperationException("log failure");}
}
"@ -ReferencedAssemblies 'System.dll','System.Drawing.dll'
try {
    $assembly=[Reflection.Assembly]::LoadFile((Resolve-Path $Executable));$type=$assembly.GetType('BoltSnip.CaptureOverlay',$true);$flags=[Reflection.BindingFlags]'Instance,NonPublic'
    $f1=[Func[string]];$f2=[Func[Drawing.Rectangle,Drawing.Bitmap]];$list=[System.Collections.Generic.List[object]].GetGenericTypeDefinition().MakeGenericType([Drawing.Rectangle]);$f3=[Func[object,object]].GetGenericTypeDefinition().MakeGenericType([Drawing.Rectangle],$list)
    $ctor=$type.GetConstructor($flags,$null,[Type[]]@($f1,$f2,$f3,[Action],[Action]),$null);$begin=$type.GetMethod('BeginCapture',$flags);$finish=$type.GetMethod('Finish',$flags)
    function DD([Type]$t,[object]$o,[string]$n){[Delegate]::CreateDelegate($t,$o,$o.GetType().GetMethod($n))}
    $h=[DiagnosticHarness]::new();$common=@((DD $f1 $h 'Save'),(DD $f2 $h 'Capture'),(DD $f3 $h 'Snapshot'),$null)
    $ok=$ctor.Invoke($common + @((DD ([Action]) $h 'Show')));[void]$begin.Invoke($ok,$null);[void]$finish.Invoke($ok,@($false,'test'));$ok.Dispose()
    $bad=$ctor.Invoke($common + @((DD ([Action]) $h 'Fail')));try{[void]$begin.Invoke($bad,$null)}catch{};$bad.Dispose()
    $text=Get-Content -LiteralPath $logPath -Raw
    $events=@('Capture Start','Overlay Show','Capture End','Capture Failed','Overlay Hide','Resource Cleanup')
    $missing=@($events|Where-Object{$text -notmatch [regex]::Escape($_)})
    [pscustomobject]@{LoggingOptIn=$true;RequiredEventsPresent=$missing.Count -eq 0;MissingEvents=$missing -join ',';Passed=$missing.Count -eq 0}|Format-List
    if($missing.Count){exit 1}
} finally {
    Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    Remove-Item Env:BOLTSNIP_DIAGNOSTIC_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:BOLTSNIP_DIAGNOSTIC_LOG_PATH -ErrorAction SilentlyContinue
}
