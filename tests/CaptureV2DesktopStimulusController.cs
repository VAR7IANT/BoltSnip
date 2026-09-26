using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

internal static class CaptureV2DesktopStimulusController
{
    private const int SmCxScreen = 0;
    private const int SmCyScreen = 1;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpShowWindow = 0x0040;
    private const uint WmClose = 0x0010;
    private static readonly IntPtr HwndTopmost = new IntPtr(-1);
    private static string _windowTitle;
    private static IntPtr _windowHandle;

    private delegate bool EnumWindowsCallback(IntPtr window, IntPtr parameter);

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        internal int X;
        internal int Y;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetCursorPos(out Point point);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr parameter);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr window, StringBuilder text, int maximumCount);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr window);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

    private static int Main(string[] args)
    {
        if (args.Length >= 2 && string.Equals(args[0], "--close", StringComparison.OrdinalIgnoreCase))
        {
            IntPtr window = FindWindow(args[1]);
            return window != IntPtr.Zero && PostMessage(window, WmClose, IntPtr.Zero, IntPtr.Zero) ? 0 : 1;
        }

        if (args.Length < 2)
        {
            Console.Error.WriteLine("Usage: CaptureV2DesktopStimulusController <window title> <duration seconds>");
            return 2;
        }

        int durationSeconds;
        if (!int.TryParse(args[1], out durationSeconds) || durationSeconds < 1)
        {
            Console.Error.WriteLine("Duration must be a positive number of seconds.");
            return 2;
        }

        IntPtr previousDpiContext = SetThreadDpiAwarenessContext(new IntPtr(-4));
        _windowTitle = args[0];
        _windowHandle = FindWindow(_windowTitle);
        if (_windowHandle == IntPtr.Zero)
        {
            Console.Error.WriteLine("The dynamic benchmark window was not found: " + _windowTitle);
            return 3;
        }

        int screenWidth = GetSystemMetrics(SmCxScreen);
        int screenHeight = GetSystemMetrics(SmCyScreen);
        int windowWidth = Math.Min(1480, screenWidth);
        int windowHeight = Math.Min(940, screenHeight);
        Point originalCursor;
        bool restoreCursor = GetCursorPos(out originalCursor);
        SetWindowPos(_windowHandle, HwndTopmost, 24, 24, windowWidth, windowHeight, SwpShowWindow | SwpNoActivate);

        Stopwatch elapsed = Stopwatch.StartNew();
        long nextWindowMove = 0;
        long nextCursorMove = 0;
        try
        {
            while (elapsed.Elapsed.TotalSeconds < durationSeconds)
            {
                long milliseconds = elapsed.ElapsedMilliseconds;
                if (milliseconds >= nextWindowMove)
                {
                    double seconds = elapsed.Elapsed.TotalSeconds;
                    int maximumX = Math.Max(1, screenWidth - windowWidth);
                    int maximumY = Math.Max(1, screenHeight - windowHeight);
                    int x = (int)((0.5 + 0.5 * Math.Sin(seconds * 0.23)) * maximumX);
                    int y = (int)((0.5 + 0.5 * Math.Sin(seconds * 0.31 + 1.2)) * maximumY);
                    if (!SetWindowPos(_windowHandle, HwndTopmost, x, y, windowWidth, windowHeight, SwpShowWindow | SwpNoActivate))
                    {
                        Console.Error.WriteLine("Could not reposition the dynamic benchmark window.");
                        return 4;
                    }
                    nextWindowMove = milliseconds + 50;
                }

                if (milliseconds >= nextCursorMove)
                {
                    double seconds = elapsed.Elapsed.TotalSeconds;
                    int margin = 32;
                    int cursorX = margin + (int)((0.5 + 0.47 * Math.Sin(seconds * 7.0)) * Math.Max(1, screenWidth - margin * 2));
                    int cursorY = margin + (int)((0.5 + 0.47 * Math.Sin(seconds * 5.0 + 0.4)) * Math.Max(1, screenHeight - margin * 2));
                    SetCursorPos(cursorX, cursorY);
                    nextCursorMove = milliseconds + 16;
                }

                Thread.Sleep(4);
            }
        }
        finally
        {
            if (restoreCursor)
            {
                SetCursorPos(originalCursor.X, originalCursor.Y);
            }
            if (previousDpiContext != IntPtr.Zero)
            {
                SetThreadDpiAwarenessContext(previousDpiContext);
            }
        }

        Console.WriteLine(
            "Dynamic stimulus complete: display=" + screenWidth + "x" + screenHeight +
            "; duration=" + durationSeconds + "s; window=" + _windowTitle);
        return 0;
    }

    private static IntPtr FindWindow(string title)
    {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr window, IntPtr parameter)
        {
            if (!IsWindowVisible(window))
            {
                return true;
            }

            StringBuilder text = new StringBuilder(512);
            GetWindowText(window, text, text.Capacity);
            if (text.ToString().IndexOf(title, StringComparison.OrdinalIgnoreCase) >= 0)
            {
                found = window;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
