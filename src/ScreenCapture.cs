using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace BoltSnip
{
    internal static class ScreenCapture
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct BitmapInfoHeader
        {
            internal uint Size;
            internal int Width;
            internal int Height;
            internal ushort Planes;
            internal ushort BitCount;
            internal uint Compression;
            internal uint SizeImage;
            internal int XPelsPerMeter;
            internal int YPelsPerMeter;
            internal uint ColorsUsed;
            internal uint ColorsImportant;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct BitmapInfo
        {
            internal BitmapInfoHeader Header;
            internal uint Color0;
            internal uint Color1;
        }

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern IntPtr CreateCompatibleDC(IntPtr hdc);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern IntPtr CreateDIBSection(
            IntPtr hdc,
            ref BitmapInfo bitmapInfo,
            uint usage,
            out IntPtr bits,
            IntPtr section,
            uint offset);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern IntPtr SelectObject(IntPtr hdc, IntPtr objectHandle);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern bool DeleteObject(IntPtr objectHandle);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern bool DeleteDC(IntPtr hdc);

        internal static Bitmap Capture(Rectangle bounds)
        {
            if (bounds.Width <= 0 || bounds.Height <= 0)
            {
                throw new ArgumentOutOfRangeException("bounds");
            }

            IntPtr source = NativeMethods.GetDC(IntPtr.Zero);
            if (source == IntPtr.Zero)
            {
                throw new InvalidOperationException("无法获取桌面设备上下文。");
            }

            IntPtr memory = IntPtr.Zero;
            IntPtr dib = IntPtr.Zero;
            IntPtr previousBitmap = IntPtr.Zero;
            try
            {
                memory = CreateCompatibleDC(source);
                if (memory == IntPtr.Zero)
                {
                    throw new InvalidOperationException("无法创建屏幕捕获内存设备上下文。");
                }

                BitmapInfo bitmapInfo = new BitmapInfo();
                bitmapInfo.Header.Size = (uint)Marshal.SizeOf(typeof(BitmapInfoHeader));
                bitmapInfo.Header.Width = bounds.Width;
                bitmapInfo.Header.Height = -bounds.Height;
                bitmapInfo.Header.Planes = 1;
                bitmapInfo.Header.BitCount = 32;
                bitmapInfo.Header.Compression = 0; // BI_RGB
                bitmapInfo.Header.SizeImage = checked((uint)((long)bounds.Width * bounds.Height * 4));

                IntPtr bits;
                dib = CreateDIBSection(source, ref bitmapInfo, 0, out bits, IntPtr.Zero, 0);
                if (dib == IntPtr.Zero || bits == IntPtr.Zero)
                {
                    throw new InvalidOperationException("无法创建屏幕捕获位图。");
                }

                previousBitmap = SelectObject(memory, dib);
                if (previousBitmap == IntPtr.Zero || previousBitmap == new IntPtr(-1))
                {
                    throw new InvalidOperationException("无法选择屏幕捕获位图。");
                }

                bool copied = NativeMethods.BitBlt(
                    memory,
                    0,
                    0,
                    bounds.Width,
                    bounds.Height,
                    source,
                    bounds.Left,
                    bounds.Top,
                    NativeMethods.SRCCOPY | NativeMethods.CAPTUREBLT);

                if (!copied)
                {
                    throw new InvalidOperationException("无法从桌面复制图像。");
                }

                // FromHbitmap materializes an opaque 32bpp RGB bitmap from the DIB section.
                // A GDI+ Bitmap HDC target corrupts some dark RGB pixels when BitBlt writes to it.
                return Bitmap.FromHbitmap(dib);
            }
            finally
            {
                if (previousBitmap != IntPtr.Zero && previousBitmap != new IntPtr(-1))
                {
                    SelectObject(memory, previousBitmap);
                }
                if (dib != IntPtr.Zero)
                {
                    DeleteObject(dib);
                }
                if (memory != IntPtr.Zero)
                {
                    DeleteDC(memory);
                }
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
