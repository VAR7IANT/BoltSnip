using System;
using System.Runtime.InteropServices;

namespace BoltSnip
{
    internal static class NativeMethods
    {
        internal const int WM_HOTKEY = 0x0312;
        internal const uint MOD_ALT = 0x0001;
        internal const uint MOD_CONTROL = 0x0002;
        internal const uint MOD_SHIFT = 0x0004;
        internal const uint MOD_NOREPEAT = 0x4000;
        internal const uint SRCCOPY = 0x00CC0020;
        internal const uint CAPTUREBLT = 0x40000000;
        internal const int GWL_EXSTYLE = -20;
        internal const long WS_EX_TOOLWINDOW = 0x00000080L;
        internal const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
        internal const int DWMWA_CLOAKED = 14;

        internal delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        internal struct RECT
        {
            internal int Left;
            internal int Top;
            internal int Right;
            internal int Bottom;
        }

        [DllImport("user32.dll", SetLastError = true)]
        internal static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint virtualKey);

        [DllImport("user32.dll", SetLastError = true)]
        internal static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [DllImport("user32.dll")]
        internal static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        internal static extern IntPtr GetDC(IntPtr hWnd);

        [DllImport("user32.dll")]
        internal static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

        [DllImport("gdi32.dll")]
        internal static extern bool BitBlt(
            IntPtr hdcDestination,
            int xDestination,
            int yDestination,
            int width,
            int height,
            IntPtr hdcSource,
            int xSource,
            int ySource,
            uint rasterOperation);

        [DllImport("user32.dll")]
        internal static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

        [DllImport("user32.dll")]
        internal static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        internal static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll")]
        internal static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

        [DllImport("user32.dll")]
        internal static extern int GetWindowLong(IntPtr hWnd, int index);

        [DllImport("user32.dll")]
        internal static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("dwmapi.dll")]
        internal static extern int DwmGetWindowAttribute(
            IntPtr hWnd,
            int attribute,
            out RECT value,
            int valueSize);

        [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")]
        internal static extern int DwmGetWindowAttributeInt(
            IntPtr hWnd,
            int attribute,
            out int value,
            int valueSize);

        [DllImport("user32.dll", EntryPoint = "SetProcessDpiAwarenessContext")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetProcessDPIAware();

        internal static void EnableBestDpiAwareness()
        {
            try
            {
                // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
                if (SetProcessDpiAwarenessContext(new IntPtr(-4)))
                {
                    return;
                }
            }
            catch (EntryPointNotFoundException)
            {
            }

            try
            {
                SetProcessDPIAware();
            }
            catch (EntryPointNotFoundException)
            {
            }
        }
    }
}
