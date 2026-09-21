param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
public sealed class CaptureStabilityHarness
{
    public readonly List<Bitmap> Bitmaps = new List<Bitmap>();
    public int ShowCalls;
    public string SaveDirectory() { return Path.GetTempPath(); }
    public Bitmap Capture(Rectangle bounds) { Bitmap bitmap = new Bitmap(64, 64); Bitmaps.Add(bitmap); return bitmap; }
    public List<Rectangle> Snapshot(Rectangle bounds) { return new List<Rectangle>(); }
    public void NoOpShow() { ShowCalls++; }
    public void FailOddShow() { ShowCalls++; if ((ShowCalls & 1) == 1) throw new InvalidOperationException("Injected Show failure."); }
    public bool AllDisposed()
    {
        foreach (Bitmap bitmap in Bitmaps) { try { int width = bitmap.Width; return false; } catch (ArgumentException) { } }
        return true;
    }
}
"@ -ReferencedAssemblies 'System.dll','System.Drawing.dll'

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$type = $assembly.GetType('BoltSnip.CaptureOverlay', $true)
$flags = [Reflection.BindingFlags]'Instance,NonPublic'
$funcString = [Func[string]]
$captureFunc = [Func[Drawing.Rectangle,Drawing.Bitmap]]
$rectangleList = [System.Collections.Generic.List[object]].GetGenericTypeDefinition().MakeGenericType([Drawing.Rectangle])
$snapshotFunc = [Func[object,object]].GetGenericTypeDefinition().MakeGenericType([Drawing.Rectangle], $rectangleList)
$constructor = $type.GetConstructor($flags, $null, [Type[]]@($funcString,$captureFunc,$snapshotFunc,[Action],[Action]), $null)
$begin = $type.GetMethod('BeginCapture', $flags)
$finish = $type.GetMethod('Finish', $flags)
$keyDown = $type.GetMethod('OverlayKeyDown', $flags)
$recover = $type.GetMethod('RecoverFromCaptureFailure', $flags)
$activeField = $type.GetField('_captureActive', $flags)
$screenField = $type.GetField('_screen', $flags)
$guideField = $type.GetField('_hasAlignmentGuidePoint', $flags)

function D([Type]$delegateType,[object]$target,[string]$name) {
    return [Delegate]::CreateDelegate($delegateType,$target,$target.GetType().GetMethod($name))
}
function New-Overlay([CaptureStabilityHarness]$h,[string]$showMethod) {
    return $constructor.Invoke(@(
        (D $funcString $h 'SaveDirectory'),
        (D $captureFunc $h 'Capture'),
        (D $snapshotFunc $h 'Snapshot'),
        $null,
        (D ([Action]) $h $showMethod)))
}
function Is-Clean([object]$overlay) {
    return -not $activeField.GetValue($overlay) -and $null -eq $screenField.GetValue($overlay)
}

$normalHarness = [CaptureStabilityHarness]::new()
$normalOverlay = New-Overlay $normalHarness 'NoOpShow'
$guidesPresent = $true
$rapidCyclesClean = $true
try {
    for($i=0;$i -lt 100;$i++) {
        [void]$begin.Invoke($normalOverlay,$null)
        $guidesPresent = $guidesPresent -and $guideField.GetValue($normalOverlay)
        [void]$finish.Invoke($normalOverlay,@($false,'test'))
        $rapidCyclesClean = $rapidCyclesClean -and (Is-Clean $normalOverlay)
    }

    $escape = [Windows.Forms.KeyEventArgs]::new([Windows.Forms.Keys]::Escape)
    for($i=0;$i -lt 100;$i++) {
        [void]$begin.Invoke($normalOverlay,$null)
        [void]$keyDown.Invoke($normalOverlay,@($normalOverlay,$escape))
        $rapidCyclesClean = $rapidCyclesClean -and (Is-Clean $normalOverlay)
    }

    [void]$begin.Invoke($normalOverlay,$null)
    [void]$recover.Invoke($normalOverlay,@('Paint',[Runtime.InteropServices.ExternalException]::new('Injected GDI+ failure.')))
    $gdiFailureRecovered = Is-Clean $normalOverlay
}
finally {
    $normalOverlay.Dispose()
}

$failureHarness = [CaptureStabilityHarness]::new()
$failureOverlay = New-Overlay $failureHarness 'FailOddShow'
$hundredFailuresRecovered = $true
try {
    for($i=0;$i -lt 100;$i++) {
        try { [void]$begin.Invoke($failureOverlay,$null) } catch { }
        $hundredFailuresRecovered = $hundredFailuresRecovered -and (Is-Clean $failureOverlay)
        [void]$begin.Invoke($failureOverlay,$null)
        [void]$finish.Invoke($failureOverlay,@($false,'test'))
        $hundredFailuresRecovered = $hundredFailuresRecovered -and (Is-Clean $failureOverlay)
    }
}
finally {
    $failureOverlay.Dispose()
}

$passed = $rapidCyclesClean -and $guidesPresent -and $gdiFailureRecovered -and
    $hundredFailuresRecovered -and $normalHarness.AllDisposed() -and $failureHarness.AllDisposed()
[pscustomobject]@{
    ConsecutiveCaptureCycles = 100
    RapidEscapeCycles = 100
    FailureRecoveryCycles = 100
    GuidesPresentEveryCapture = $guidesPresent
    GdiFailureRecovered = $gdiFailureRecovered
    AllBitmapsDisposed = $normalHarness.AllDisposed() -and $failureHarness.AllDisposed()
    Passed = $passed
} | Format-List
if(-not $passed){exit 1}
