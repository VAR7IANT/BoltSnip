param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$harnessSource = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;

public sealed class BeginCaptureFailureHarness
{
    public readonly List<Bitmap> Bitmaps = new List<Bitmap>();
    public int CoordinateCalls;
    public int ShowCalls;

    public string GetSaveDirectory() { return Path.GetTempPath(); }

    public Bitmap Capture(Rectangle bounds)
    {
        Bitmap bitmap = new Bitmap(64, 64);
        Bitmaps.Add(bitmap);
        return bitmap;
    }

    public List<Rectangle> Snapshot(Rectangle bounds)
    {
        return new List<Rectangle>();
    }

    public void FailCoordinatesOnce()
    {
        CoordinateCalls++;
        if (CoordinateCalls == 1) throw new InvalidOperationException("Simulated coordinate initialization failure.");
    }

    public void FailShowOnce()
    {
        ShowCalls++;
        if (ShowCalls == 1) throw new InvalidOperationException("Simulated Show failure.");
    }

    public void NoOpShow() { ShowCalls++; }

    public bool IsBitmapDisposed(int index)
    {
        try
        {
            int width = Bitmaps[index].Width;
            return false;
        }
        catch (ArgumentException)
        {
            return true;
        }
    }
}
"@
Add-Type -TypeDefinition $harnessSource -ReferencedAssemblies 'System.dll', 'System.Drawing.dll'

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$overlayType = $assembly.GetType('BoltSnip.CaptureOverlay', $true)
$instanceFlags = [Reflection.BindingFlags]'Instance,NonPublic'
$funcStringType = [Func[string]]
$captureFuncType = [Func[Drawing.Rectangle,Drawing.Bitmap]]
$rectangleListType = [System.Collections.Generic.List[object]].GetGenericTypeDefinition().MakeGenericType([Drawing.Rectangle])
$snapshotFuncType = [Func[object,object]].GetGenericTypeDefinition().MakeGenericType([Drawing.Rectangle], $rectangleListType)
$constructorTypes = [Type[]]@($funcStringType, $captureFuncType, $snapshotFuncType, [Action], [Action])
$constructor = $overlayType.GetConstructor($instanceFlags, $null, $constructorTypes, $null)

if ($null -eq $constructor) {
    throw 'The transactional CaptureOverlay test constructor was not found.'
}

$beginCapture = $overlayType.GetMethod('BeginCapture', $instanceFlags)
$finish = $overlayType.GetMethod('Finish', $instanceFlags)
$captureActiveField = $overlayType.GetField('_captureActive', $instanceFlags)
$screenField = $overlayType.GetField('_screen', $instanceFlags)
$virtualScreenField = $overlayType.GetField('_virtualScreen', $instanceFlags)
$windowRectanglesField = $overlayType.GetField('_windowRectangles', $instanceFlags)
$selectionField = $overlayType.GetField('_selection', $instanceFlags)
$hoverRectangleField = $overlayType.GetField('_hoverRectangle', $instanceFlags)
$hasMagnifierField = $overlayType.GetField('_hasMagnifierPoint', $instanceFlags)
$hasGuideField = $overlayType.GetField('_hasAlignmentGuidePoint', $instanceFlags)
$timerField = $overlayType.GetField('_windowTrackingTimer', $instanceFlags)

function New-Delegate([Type]$delegateType, [object]$target, [string]$methodName) {
    $method = $target.GetType().GetMethod($methodName)
    return [Delegate]::CreateDelegate($delegateType, $target, $method)
}

function Invoke-RollbackScenario([string]$failureStage) {
    $harness = [BeginCaptureFailureHarness]::new()
    $saveDirectory = New-Delegate $funcStringType $harness 'GetSaveDirectory'
    $capture = New-Delegate $captureFuncType $harness 'Capture'
    $snapshot = New-Delegate $snapshotFuncType $harness 'Snapshot'
    $coordinateHook = $null
    $showHook = $null
    if ($failureStage -eq 'Coordinates') {
        $coordinateHook = New-Delegate ([Action]) $harness 'FailCoordinatesOnce'
        $showHook = New-Delegate ([Action]) $harness 'NoOpShow'
    }
    else {
        $showHook = New-Delegate ([Action]) $harness 'FailShowOnce'
    }

    $overlay = $constructor.Invoke(@($saveDirectory, $capture, $snapshot, $coordinateHook, $showHook))
    try {
        $failureObserved = $false
        try {
            [void]$beginCapture.Invoke($overlay, $null)
        }
        catch {
            $failure = $_.Exception
            while ($null -ne $failure.InnerException) {
                $failure = $failure.InnerException
            }
            $failureObserved = $failure -is [InvalidOperationException]
        }

        $timer = $timerField.GetValue($overlay)
        $rolledBack = $failureObserved -and
            -not $captureActiveField.GetValue($overlay) -and
            $null -eq $screenField.GetValue($overlay) -and
            $virtualScreenField.GetValue($overlay).IsEmpty -and
            $windowRectanglesField.GetValue($overlay).Count -eq 0 -and
            $selectionField.GetValue($overlay).IsEmpty -and
            $hoverRectangleField.GetValue($overlay).IsEmpty -and
            -not $hasMagnifierField.GetValue($overlay) -and
            -not $hasGuideField.GetValue($overlay) -and
            -not $timer.Enabled -and
            -not $overlay.Visible -and
            $harness.IsBitmapDisposed(0)

        # Both hooks fail only on their first call. The same overlay must be reusable.
        [void]$beginCapture.Invoke($overlay, $null)
        $retrySucceeded = $captureActiveField.GetValue($overlay) -and
            $null -ne $screenField.GetValue($overlay) -and
            $harness.Bitmaps.Count -eq 2

        [void]$finish.Invoke($overlay, @($false, 'test'))
        $retryCleanedUp = -not $captureActiveField.GetValue($overlay) -and
            $null -eq $screenField.GetValue($overlay) -and
            $harness.IsBitmapDisposed(1)

        return [pscustomobject]@{
            Stage = $failureStage
            FailureObserved = $failureObserved
            BitmapDisposed = $harness.IsBitmapDisposed(0)
            StateRolledBack = $rolledBack
            SameOverlayRetrySucceeded = $retrySucceeded
            RetryBitmapDisposed = $retryCleanedUp
            Passed = $rolledBack -and $retrySucceeded -and $retryCleanedUp
        }
    }
    finally {
        $overlay.Dispose()
    }
}

$coordinateResult = Invoke-RollbackScenario 'Coordinates'
$showResult = Invoke-RollbackScenario 'Show'
$coordinateResult | Format-List
$showResult | Format-List

if (-not $coordinateResult.Passed -or -not $showResult.Passed) {
    exit 1
}
