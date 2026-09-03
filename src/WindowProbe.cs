using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;

namespace BoltSnip
{
    internal static class WindowProbe
    {
        internal static List<Rectangle> Snapshot(Rectangle virtualScreen)
        {
            List<Rectangle> rectangles = new List<Rectangle>();
            uint currentProcessId = (uint)Process.GetCurrentProcess().Id;

            NativeMethods.EnumWindows(delegate(IntPtr hWnd, IntPtr unused)
            {
                if (!NativeMethods.IsWindowVisible(hWnd) || NativeMethods.IsIconic(hWnd))
                {
                    return true;
                }

                uint processId;
                NativeMethods.GetWindowThreadProcessId(hWnd, out processId);
                if (processId == currentProcessId)
                {
                    return true;
                }

                int extendedStyle = NativeMethods.GetWindowLong(hWnd, NativeMethods.GWL_EXSTYLE);
                if ((((long)extendedStyle) & NativeMethods.WS_EX_TOOLWINDOW) != 0)
                {
                    return true;
                }

                int cloaked;
                if (NativeMethods.DwmGetWindowAttributeInt(
                    hWnd,
                    NativeMethods.DWMWA_CLOAKED,
                    out cloaked,
                    sizeof(int)) == 0 && cloaked != 0)
                {
                    return true;
                }

                NativeMethods.RECT nativeRect;
                int dwmResult = NativeMethods.DwmGetWindowAttribute(
                    hWnd,
                    NativeMethods.DWMWA_EXTENDED_FRAME_BOUNDS,
                    out nativeRect,
                    System.Runtime.InteropServices.Marshal.SizeOf(typeof(NativeMethods.RECT)));

                if (dwmResult != 0 && !NativeMethods.GetWindowRect(hWnd, out nativeRect))
                {
                    return true;
                }

                Rectangle screenRectangle = Rectangle.FromLTRB(
                    nativeRect.Left,
                    nativeRect.Top,
                    nativeRect.Right,
                    nativeRect.Bottom);

                screenRectangle.Intersect(virtualScreen);
                if (screenRectangle.Width < 40 || screenRectangle.Height < 30)
                {
                    return true;
                }

                rectangles.Add(new Rectangle(
                    screenRectangle.Left - virtualScreen.Left,
                    screenRectangle.Top - virtualScreen.Top,
                    screenRectangle.Width,
                    screenRectangle.Height));

                return true;
            }, IntPtr.Zero);

            return rectangles;
        }
    }
}
