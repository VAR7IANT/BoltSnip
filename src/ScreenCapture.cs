using System;
using System.Drawing;
using System.Drawing.Imaging;

namespace BoltSnip
{
    internal static class ScreenCapture
    {
        internal static Bitmap Capture(Rectangle bounds)
        {
            if (bounds.Width <= 0 || bounds.Height <= 0)
            {
                throw new ArgumentOutOfRangeException("bounds");
            }

            Bitmap bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppPArgb);
            try
            {
                using (Graphics graphics = Graphics.FromImage(bitmap))
                {
                    IntPtr destination = graphics.GetHdc();
                    IntPtr source = NativeMethods.GetDC(IntPtr.Zero);
                    try
                    {
                        bool copied = NativeMethods.BitBlt(
                            destination,
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
                    }
                    finally
                    {
                        NativeMethods.ReleaseDC(IntPtr.Zero, source);
                        graphics.ReleaseHdc(destination);
                    }
                }

                return bitmap;
            }
            catch
            {
                bitmap.Dispose();
                throw;
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
