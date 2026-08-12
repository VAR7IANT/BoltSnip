using System;
using System.Drawing;
using System.Drawing.Drawing2D;
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
            Bitmap result = new Bitmap(rectangle.Width, rectangle.Height, PixelFormat.Format32bppPArgb);
            using (Graphics graphics = Graphics.FromImage(result))
            {
                graphics.CompositingMode = CompositingMode.SourceCopy;
                graphics.CompositingQuality = CompositingQuality.HighSpeed;
                graphics.InterpolationMode = InterpolationMode.NearestNeighbor;
                graphics.PixelOffsetMode = PixelOffsetMode.Half;
                graphics.DrawImage(
                    source,
                    new Rectangle(0, 0, result.Width, result.Height),
                    rectangle,
                    GraphicsUnit.Pixel);
            }

            return result;
        }
    }
}
