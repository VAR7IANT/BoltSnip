param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class BaselineNative {
 [DllImport("user32.dll")] public static extern int GetGuiResources(IntPtr p,int f);
}
"@
$logPath=Join-Path $env:TEMP ('BoltSnip-baseline-'+[Guid]::NewGuid().ToString('N')+'.log')
$launch=[Diagnostics.Stopwatch]::StartNew();$process=Start-Process -FilePath $Executable -WindowStyle Hidden -PassThru
try {
    $ready=$false
    for($i=0;$i -lt 500;$i++){$process.Refresh();if($process.HasExited){throw 'BoltSnip exited during startup.'};if($process.WorkingSet64 -gt 10MB -and [BaselineNative]::GetGuiResources($process.Handle,0) -gt 0){$ready=$true;break};Start-Sleep -Milliseconds 10}
    if(-not $ready){throw 'BoltSnip did not reach the tray-ready resource baseline.'}
    $launch.Stop()
    $process.Refresh();$working=[Math]::Round($process.WorkingSet64/1MB,1);$private=[Math]::Round($process.PrivateMemorySize64/1MB,1);$gdi=[BaselineNative]::GetGuiResources($process.Handle,0);$user=[BaselineNative]::GetGuiResources($process.Handle,1)

    $env:BOLTSNIP_DIAGNOSTIC_LOG='1';$env:BOLTSNIP_DIAGNOSTIC_LOG_PATH=$logPath
    $assembly=[Reflection.Assembly]::LoadFile((Resolve-Path $Executable));$ot=$assembly.GetType('BoltSnip.CaptureOverlay',$true);$at=$assembly.GetType('BoltSnip.GuideColorAnalyzer',$true);$flags=[Reflection.BindingFlags]'Instance,NonPublic'
    $measuredOverlay=[Activator]::CreateInstance($ot,$true);$begin=$ot.GetMethod('BeginCapture',$flags);$finish=$ot.GetMethod('Finish',$flags);$capture=[Diagnostics.Stopwatch]::StartNew();[void]$begin.Invoke($measuredOverlay,$null);$capture.Stop();[Windows.Forms.Application]::DoEvents();[void]$finish.Invoke($measuredOverlay,@($false,'baseline'));$measuredOverlay.Dispose();[Windows.Forms.Application]::DoEvents()
    $log=Get-Content -LiteralPath $logPath -Raw;$match=[regex]::Match($log,'Overlay Show \| elapsedMs=([0-9.]+)');$overlayShow=if($match.Success){[double]::Parse($match.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)}else{-1}
    $draw=$ot.GetMethod('DrawAlignmentGuides',$flags);$o=[Activator]::CreateInstance($ot,$true);$b=[Drawing.Bitmap]::new(512,512);$g=[Drawing.Graphics]::FromImage($b);$p=[Drawing.Point]::new(256,256);$r=[Drawing.Rectangle]::new(0,0,512,512)
    $watch=[Diagnostics.Stopwatch]::StartNew();for($i=0;$i -lt 10000;$i++){[void]$draw.Invoke($o,@($g,$p.PSObject.BaseObject,$r.PSObject.BaseObject))};$watch.Stop();$guideUs=$watch.Elapsed.TotalMilliseconds*1000/10000;$g.Dispose();$o.Dispose()
    $update=$at.GetMethod('TryUpdateAt',$flags);$a=[Activator]::CreateInstance($at,$true);$watch.Restart();for($i=0;$i -lt 1000;$i++){$q=[Drawing.Point]::new(20+($i%470),20+(($i*7)%470));[void]$update.Invoke($a,@($b,$q.PSObject.BaseObject,$i))};$watch.Stop();$analyzerUs=$watch.Elapsed.TotalMilliseconds*1000/1000;$b.Dispose()
    [pscustomobject]@{RecordedAt=(Get-Date).ToString('o');ProcessStartupMs=$launch.ElapsedMilliseconds;CaptureStartupMs=$capture.ElapsedMilliseconds;OverlayShowMs=$overlayShow;GuideDrawMicroseconds=[Math]::Round($guideUs,2);ColorAnalyzerCallMicroseconds=[Math]::Round($analyzerUs,2);CaptureWorkingSetMB=$working;CapturePrivateMemoryMB=$private;GdiObjects=$gdi;UserObjects=$user}|Format-List
} finally {
    Start-Sleep -Milliseconds 100
    if(-not $process.HasExited){Stop-Process -Id $process.Id}
    Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    Remove-Item Env:BOLTSNIP_DIAGNOSTIC_LOG -ErrorAction SilentlyContinue;Remove-Item Env:BOLTSNIP_DIAGNOSTIC_LOG_PATH -ErrorAction SilentlyContinue
}
