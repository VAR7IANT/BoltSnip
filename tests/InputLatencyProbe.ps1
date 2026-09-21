param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe'),
    [ValidateSet('Sweep', 'Circle')]
    [string]$Pattern = 'Sweep',
    [int]$DurationMilliseconds = 1200,
    [int]$TargetInputHz = 1000,
    [switch]$Drag,
    [switch]$SuppressMagnifierPaint
)

$ErrorActionPreference = 'Stop'
$assemblyPath = $Executable
if (-not (Test-Path -LiteralPath $assemblyPath)) {
    throw "Build output not found: $assemblyPath"
}

$source = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

public sealed class BoltSnipInputProbe : NativeWindow, IDisposable
{
    private const int WmMouseMove = 0x0200;
    private const int WmPaint = 0x000F;
    private readonly Form form;
    private readonly FieldInfo guidePointField;
    private readonly FieldInfo hasMagnifierPointField;
    private readonly ConcurrentDictionary<long, GeneratedPoint> generated =
        new ConcurrentDictionary<long, GeneratedPoint>();
    private int latestGeneratedSequence;
    private int lastHandledSequence;
    private long firstMouseTimestamp;
    private long lastMouseTimestamp;
    private long firstPaintTimestamp;
    private long lastPaintTimestamp;

    public readonly List<double> HandlerMilliseconds = new List<double>();
    public readonly List<double> QueueMilliseconds = new List<double>();
    public readonly List<double> PaintMilliseconds = new List<double>();
    public readonly List<double> EndToEndMilliseconds = new List<double>();
    public readonly List<int> ArrivalSequenceLag = new List<int>();
    public readonly List<int> PaintSequenceLag = new List<int>();
    public int OutOfOrderCount;
    public int UnknownCoordinateCount;
    public bool SuppressMagnifierPaint;

    public BoltSnipInputProbe(Form target)
    {
        form = target;
        Type type = target.GetType();
        guidePointField = type.GetField("_alignmentGuidePoint", BindingFlags.Instance | BindingFlags.NonPublic);
        hasMagnifierPointField = type.GetField("_hasMagnifierPoint", BindingFlags.Instance | BindingFlags.NonPublic);
        AssignHandle(target.Handle);
    }

    public double MouseArrivalHz
    {
        get
        {
            double seconds = (lastMouseTimestamp - firstMouseTimestamp) / (double)Stopwatch.Frequency;
            return seconds > 0 ? (HandlerMilliseconds.Count - 1) / seconds : 0;
        }
    }

    public double PaintHz
    {
        get
        {
            double seconds = (lastPaintTimestamp - firstPaintTimestamp) / (double)Stopwatch.Frequency;
            return seconds > 0 ? (PaintMilliseconds.Count - 1) / seconds : 0;
        }
    }

    public void Run(string pattern, int durationMilliseconds, int targetHz, bool drag)
    {
        Rectangle client = form.ClientRectangle;
        Point screenOrigin = form.PointToScreen(Point.Empty);
        int width = Math.Max(200, client.Width - 80);
        int height = Math.Max(160, client.Height - 80);
        Point originalCursor = Cursor.Position;
        Exception workerFailure = null;
        Thread worker = new Thread(delegate()
        {
            try
            {
                if (drag) mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
                long intervalTicks = Math.Max(1L, Stopwatch.Frequency / Math.Max(1, targetHz));
                long start = Stopwatch.GetTimestamp();
                long deadline = start + ((long)durationMilliseconds * Stopwatch.Frequency / 1000);
                int sequence = 0;
                long next = start;
                while (Stopwatch.GetTimestamp() < deadline)
                {
                    sequence++;
                    double phase = sequence * 0.11;
                    int x;
                    int y;
                    if (string.Equals(pattern, "Circle", StringComparison.OrdinalIgnoreCase))
                    {
                        x = 40 + width / 2 + (int)(Math.Cos(phase) * width * 0.44);
                        y = 40 + height / 2 + (int)(Math.Sin(phase) * height * 0.44);
                    }
                    else
                    {
                        int period = Math.Max(2, width * 2);
                        int offset = (sequence * 31) % period;
                        x = 40 + (offset < width ? offset : period - offset);
                        y = 40 + ((sequence * 37) % height);
                    }

                    long timestamp = Stopwatch.GetTimestamp();
                    generated[Key(x, y)] = new GeneratedPoint(sequence, timestamp);
                    Volatile.Write(ref latestGeneratedSequence, sequence);
                    SetCursorPos(screenOrigin.X + x, screenOrigin.Y + y);
                    next += intervalTicks;
                    while (Stopwatch.GetTimestamp() < next)
                    {
                        Thread.SpinWait(20);
                    }
                }
                if (drag) mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
            }
            catch (Exception exception)
            {
                workerFailure = exception;
            }
        });
        worker.IsBackground = true;
        worker.Priority = ThreadPriority.AboveNormal;
        worker.Start();

        while (worker.IsAlive)
        {
            Application.DoEvents();
            Thread.Yield();
        }
        worker.Join();

        Stopwatch drain = Stopwatch.StartNew();
        while (drain.ElapsedMilliseconds < 250)
        {
            Application.DoEvents();
            Thread.Yield();
        }
        SetCursorPos(originalCursor.X, originalCursor.Y);
        Application.DoEvents();
        if (workerFailure != null)
        {
            throw new InvalidOperationException("Input worker failed.", workerFailure);
        }
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == WmMouseMove)
        {
            long entry = Stopwatch.GetTimestamp();
            if (firstMouseTimestamp == 0) firstMouseTimestamp = entry;
            lastMouseTimestamp = entry;
            int packed = unchecked((int)(long)message.LParam);
            int x = unchecked((short)(packed & 0xffff));
            int y = unchecked((short)((packed >> 16) & 0xffff));
            GeneratedPoint point;
            int sequence = 0;
            if (generated.TryGetValue(Key(x, y), out point))
            {
                sequence = point.Sequence;
                QueueMilliseconds.Add(ToMilliseconds(entry - point.Timestamp));
                int lag = Math.Max(0, Volatile.Read(ref latestGeneratedSequence) - sequence);
                ArrivalSequenceLag.Add(lag);
                if (sequence < lastHandledSequence) OutOfOrderCount++;
                if (sequence > lastHandledSequence) lastHandledSequence = sequence;
            }
            else
            {
                UnknownCoordinateCount++;
            }

            base.WndProc(ref message);
            HandlerMilliseconds.Add(ToMilliseconds(Stopwatch.GetTimestamp() - entry));
            return;
        }

        if (message.Msg == WmPaint)
        {
            long entry = Stopwatch.GetTimestamp();
            if (firstPaintTimestamp == 0) firstPaintTimestamp = entry;
            lastPaintTimestamp = entry;
            bool restoreMagnifier = false;
            if (SuppressMagnifierPaint && hasMagnifierPointField != null)
            {
                restoreMagnifier = (bool)hasMagnifierPointField.GetValue(form);
                hasMagnifierPointField.SetValue(form, false);
            }
            base.WndProc(ref message);
            long completed = Stopwatch.GetTimestamp();
            if (SuppressMagnifierPaint && hasMagnifierPointField != null)
            {
                hasMagnifierPointField.SetValue(form, restoreMagnifier);
            }
            PaintMilliseconds.Add(ToMilliseconds(completed - entry));

            Point guide = guidePointField == null ? Point.Empty : (Point)guidePointField.GetValue(form);
            GeneratedPoint point;
            if (generated.TryGetValue(Key(guide.X, guide.Y), out point))
            {
                EndToEndMilliseconds.Add(ToMilliseconds(completed - point.Timestamp));
                PaintSequenceLag.Add(Math.Max(0, Volatile.Read(ref latestGeneratedSequence) - point.Sequence));
            }
            return;
        }

        base.WndProc(ref message);
    }

    public void Dispose()
    {
        ReleaseHandle();
    }

    private static long Key(int x, int y)
    {
        return ((long)x << 32) ^ (uint)y;
    }

    private static double ToMilliseconds(long ticks)
    {
        return ticks * 1000.0 / Stopwatch.Frequency;
    }

    private sealed class GeneratedPoint
    {
        internal readonly int Sequence;
        internal readonly long Timestamp;

        internal GeneratedPoint(int sequence, long timestamp)
        {
            Sequence = sequence;
            Timestamp = timestamp;
        }
    }

    [DllImport("user32.dll")]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
}
'@

Add-Type -TypeDefinition $source -ReferencedAssemblies System.dll,System.Core.dll,System.Drawing.dll,System.Windows.Forms.dll
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $assemblyPath))
$overlayType = $assembly.GetType('BoltSnip.CaptureOverlay', $true)
$overlay = [Activator]::CreateInstance($overlayType, $true)
$beginCapture = $overlayType.GetMethod('BeginCapture', [Reflection.BindingFlags]'Instance,NonPublic')
$cleanup = $overlayType.GetMethod('CleanupCaptureState', [Reflection.BindingFlags]'Instance,NonPublic')
$probe = $null

function Get-Distribution([double[]]$Values) {
    if ($null -eq $Values -or $Values.Count -eq 0) {
        return [pscustomobject]@{ Count = 0; Average = 0; P95 = 0; P99 = 0; Maximum = 0 }
    }
    $sorted = @($Values | Sort-Object)
    function Pick([double]$p) {
        $index = [Math]::Max(0, [Math]::Min($sorted.Count - 1, [Math]::Ceiling($sorted.Count * $p) - 1))
        return [double]$sorted[$index]
    }
    [pscustomobject]@{
        Count = $sorted.Count
        Average = [Math]::Round(($sorted | Measure-Object -Average).Average, 3)
        P95 = [Math]::Round((Pick 0.95), 3)
        P99 = [Math]::Round((Pick 0.99), 3)
        Maximum = [Math]::Round([double]$sorted[-1], 3)
    }
}

function Measure-OverlayComponent($Overlay, [string]$MethodName, [int]$Iterations) {
    $flags = [Reflection.BindingFlags]'Instance,NonPublic'
    $type = $Overlay.GetType()
    $dirtyType = $type.GetNestedType('DirtyRegionAccumulator', [Reflection.BindingFlags]'NonPublic')
    $method = @($type.GetMethods($flags) | Where-Object {
        $_.Name -eq $MethodName -and $_.GetParameters().Count -eq 2
    })[0]
    $values = New-Object 'System.Collections.Generic.List[double]'
    for ($index = 0; $index -lt $Iterations; $index++) {
        $dirty = [Activator]::CreateInstance($dirtyType, $true)
        $point = [Drawing.Point]::new(40 + (($index * 31) % ([Math]::Max(80, $Overlay.ClientSize.Width - 80))), 40 + (($index * 37) % ([Math]::Max(80, $Overlay.ClientSize.Height - 80))))
        $started = [Diagnostics.Stopwatch]::GetTimestamp()
        [void]$method.Invoke($Overlay, @($point, $dirty))
        $elapsed = [Diagnostics.Stopwatch]::GetTimestamp() - $started
        $values.Add($elapsed * 1000.0 / [Diagnostics.Stopwatch]::Frequency)
        $dirty.Dispose()
    }
    return Get-Distribution ([double[]]$values.ToArray())
}

try {
    $beginCapture.Invoke($overlay, @())
    [Windows.Forms.Application]::DoEvents()
    $probe = [BoltSnipInputProbe]::new([Windows.Forms.Form]$overlay)
    $probe.SuppressMagnifierPaint = $SuppressMagnifierPaint.IsPresent
    $probe.Run($Pattern, $DurationMilliseconds, $TargetInputHz, $Drag.IsPresent)

    $componentTimings = [ordered]@{}
    $componentTimings.UpdateAlignmentGuides = Measure-OverlayComponent $overlay 'UpdateAlignmentGuides' 500
    $componentTimings.UpdateMagnifier = Measure-OverlayComponent $overlay 'UpdateMagnifier' 500
    $componentTimings.TrackWindowAt = Measure-OverlayComponent $overlay 'TrackWindowAt' 500

    [pscustomobject]@{
        Pattern = $Pattern
        MagnifierPaint = -not $SuppressMagnifierPaint.IsPresent
        Drag = $Drag.IsPresent
        MouseArrivalHz = [Math]::Round($probe.MouseArrivalHz, 1)
        PaintHz = [Math]::Round($probe.PaintHz, 1)
        MouseHandlerMs = Get-Distribution ([double[]]$probe.HandlerMilliseconds.ToArray())
        QueueDelayMs = Get-Distribution ([double[]]$probe.QueueMilliseconds.ToArray())
        PaintMs = Get-Distribution ([double[]]$probe.PaintMilliseconds.ToArray())
        EndToEndMs = Get-Distribution ([double[]]$probe.EndToEndMilliseconds.ToArray())
        ArrivalLag = Get-Distribution ([double[]]@($probe.ArrivalSequenceLag.ToArray()))
        PaintLag = Get-Distribution ([double[]]@($probe.PaintSequenceLag.ToArray()))
        OutOfOrder = $probe.OutOfOrderCount
        UnknownCoordinates = $probe.UnknownCoordinateCount
        ComponentsMs = $componentTimings
    } | ConvertTo-Json -Depth 4
}
finally {
    if ($null -ne $probe) { $probe.Dispose() }
    if ($null -ne $overlay) {
        try { $cleanup.Invoke($overlay, @()) } catch {}
        $overlay.Dispose()
    }
}
