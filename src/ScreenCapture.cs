using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace BoltSnip
{
    internal static class ScreenCapture
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct DibInfo
        {
            internal uint HeaderSize;
            internal int Width, Height;
            internal ushort Planes, BitCount;
            internal uint Compression, ImageBytes;
            internal int XPixelsPerMeter, YPixelsPerMeter;
            internal uint ColorsUsed, ImportantColors, Color0, Color1;
        }

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern IntPtr CreateCompatibleDC(IntPtr source);
        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern IntPtr CreateDIBSection(IntPtr source, ref DibInfo info,
            uint usage, out IntPtr pixels, IntPtr section, uint offset);
        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern IntPtr SelectObject(IntPtr dc, IntPtr bitmap);
        [DllImport("gdi32.dll")]
        private static extern bool DeleteObject(IntPtr bitmap);
        [DllImport("gdi32.dll")]
        private static extern bool DeleteDC(IntPtr dc);

        internal static Bitmap Capture(Rectangle bounds)
        {
            if (bounds.Width <= 0 || bounds.Height <= 0)
                throw new ArgumentOutOfRangeException("bounds");
            // Validate allocation arithmetic before acquiring any GDI resources.
            int imageBytes = checked(checked(bounds.Width * 4) * bounds.Height);
            IntPtr source = NativeMethods.GetDC(IntPtr.Zero);
            if (source == IntPtr.Zero)
                throw new InvalidOperationException("无法获取桌面设备上下文。");

            IntPtr memory = IntPtr.Zero, dib = IntPtr.Zero, previous = IntPtr.Zero;
            bool selected = false;
            try
            {
                memory = CreateCompatibleDC(source);
                if (memory == IntPtr.Zero)
                    throw new InvalidOperationException("无法创建屏幕捕获设备上下文。");
                DibInfo info = new DibInfo();
                info.HeaderSize = 40; // BITMAPINFOHEADER, followed by optional color entries.
                info.Width = bounds.Width;
                info.Height = -bounds.Height; // Top-down, physical desktop coordinates.
                info.Planes = 1;
                info.BitCount = 32;
                info.ImageBytes = (uint)imageBytes;
                IntPtr pixels;
                dib = CreateDIBSection(source, ref info, 0, out pixels, IntPtr.Zero, 0);
                if (dib == IntPtr.Zero || pixels == IntPtr.Zero)
                    throw new InvalidOperationException("无法创建屏幕捕获位图。");
                previous = SelectObject(memory, dib);
                if (previous == IntPtr.Zero || previous == new IntPtr(-1))
                    throw new InvalidOperationException("无法选择屏幕捕获位图。");
                selected = true;
                if (!NativeMethods.BitBlt(memory, 0, 0, bounds.Width, bounds.Height,
                    source, bounds.Left, bounds.Top, NativeMethods.SRCCOPY | NativeMethods.CAPTUREBLT))
                    throw new InvalidOperationException("无法从桌面复制图像。");

                // GDI+ bitmap HDC targets erase some dark desktop pixels (including
                // RGB 13,11,12). A native BI_RGB DIB preserves them. FromHbitmap
                // copies to an owned opaque RGB bitmap; the desktop has no alpha.
                return Bitmap.FromHbitmap(dib);
            }
            finally
            {
                if (selected) SelectObject(memory, previous);
                if (dib != IntPtr.Zero) DeleteObject(dib);
                if (memory != IntPtr.Zero) DeleteDC(memory);
                NativeMethods.ReleaseDC(IntPtr.Zero, source);
            }
        }

        internal static Bitmap Crop(Bitmap source, Rectangle rectangle)
        {
            if (source == null)
            {
                throw new ArgumentNullException("source");
            }

            Rectangle bounds = new Rectangle(0, 0, source.Width, source.Height);
            if (rectangle.Width <= 0 || rectangle.Height <= 0 || !bounds.Contains(rectangle))
            {
                throw new ArgumentOutOfRangeException("rectangle");
            }

            // Clone copies the requested pixels directly. Keeping this path free of Graphics.DrawImage
            // avoids a second rendering pass and guarantees a 1:1 physical-pixel crop.
            return source.Clone(rectangle, PixelFormat.Format32bppPArgb);
        }
    }
}
