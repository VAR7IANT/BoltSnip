param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class BoltSnipTestNative
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindow(string className, string windowName);

    public static IntPtr FindWindowByTitle(string windowName)
    {
        return FindWindow(null, windowName);
    }

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr window);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
}
"@

$process = Start-Process -FilePath $Executable -WindowStyle Hidden -PassThru
try {
    $hotkeyWindow = [IntPtr]::Zero
    for ($attempt = 0; $attempt -lt 50 -and $hotkeyWindow -eq [IntPtr]::Zero; $attempt++) {
        Start-Sleep -Milliseconds 20
        $hotkeyWindow = [BoltSnipTestNative]::FindWindowByTitle('BoltSnip.Hotkey')
    }
    if ($hotkeyWindow -eq [IntPtr]::Zero) {
        throw 'The hotkey window was not created.'
    }

    $watch = [Diagnostics.Stopwatch]::StartNew()
    [void][BoltSnipTestNative]::PostMessage($hotkeyWindow, 0x0312, [IntPtr]0x5A71, [IntPtr]::Zero)

    $overlay = [IntPtr]::Zero
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        $overlay = [BoltSnipTestNative]::FindWindowByTitle('BoltSnip.Overlay')
        if ($overlay -ne [IntPtr]::Zero -and [BoltSnipTestNative]::IsWindowVisible($overlay)) {
            break
        }
        Start-Sleep -Milliseconds 5
    }
    $watch.Stop()

    if ($overlay -eq [IntPtr]::Zero -or -not [BoltSnipTestNative]::IsWindowVisible($overlay)) {
        throw 'The capture overlay did not become visible.'
    }

    $running = Get-Process -Id $process.Id
    $captureWorkingSet = [math]::Round($running.WorkingSet64 / 1MB, 1)
    [void][BoltSnipTestNative]::PostMessage($overlay, 0x0100, [IntPtr]0x1B, [IntPtr]::Zero)

    for ($attempt = 0; $attempt -lt 50 -and [BoltSnipTestNative]::IsWindowVisible($overlay); $attempt++) {
        Start-Sleep -Milliseconds 10
    }

    if ([BoltSnipTestNative]::IsWindowVisible($overlay)) {
        throw 'Escape did not close the capture overlay.'
    }

    $running = Get-Process -Id $process.Id
    [pscustomobject]@{
        OverlayLatencyMs = $watch.ElapsedMilliseconds
        CaptureWorkingSetMB = $captureWorkingSet
        ProcessAliveAfterCancel = -not $running.HasExited
        OverlayClosedAfterEscape = $true
    }
}
finally {
    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id
    }
}
