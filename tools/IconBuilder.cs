using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

namespace BoltSnip.Tools
{
    internal static class IconBuilder
    {
        private static readonly int[] IconSizes = { 16, 20, 24, 32, 40, 48, 64, 128, 256 };
        private const float DesignSize = 1254f;

        private sealed class IconImage
        {
            internal int Size;
            internal byte[] Data;
        }

        private static int Main(string[] arguments)
        {
            if (arguments.Length < 1 || arguments.Length > 2)
            {
                Console.Error.WriteLine("Usage: IconBuilder <output.ico> [preview.png]");
                return 2;
            }

            try
            {
                using (Bitmap source = DrawSourceIcon(1024))
                {
                    if (arguments.Length == 2)
                    {
                        source.Save(arguments[1], ImageFormat.Png);
                    }

                    WriteIcon(source, arguments[0]);
                }
                return 0;
            }
            catch (Exception exception)
            {
                Console.Error.WriteLine(exception.ToString());
                return 1;
            }
        }

        private static Bitmap DrawSourceIcon(int size)
        {
            Bitmap bitmap = new Bitmap(size, size, PixelFormat.Format32bppArgb);
            float scale = size / DesignSize;

            using (Graphics graphics = Graphics.FromImage(bitmap))
            {
                graphics.Clear(Color.Transparent);
                graphics.CompositingMode = CompositingMode.SourceOver;
                graphics.CompositingQuality = CompositingQuality.HighQuality;
                graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
                graphics.SmoothingMode = SmoothingMode.AntiAlias;

                using (GraphicsPath card = RoundedRectangle(
                    new RectangleF(1f, 1f, size - 2f, size - 2f),
                    204f * scale))
                using (SolidBrush white = new SolidBrush(Color.White))
                using (Pen outline = new Pen(Color.FromArgb(25, 180, 186, 192), Math.Max(1f, scale)))
                {
                    graphics.FillPath(white, card);
                    graphics.DrawPath(outline, card);
                }

                DrawViewfinder(graphics, scale);
                DrawBolt(graphics, scale);
            }

            return bitmap;
        }

        private static void DrawViewfinder(Graphics graphics, float scale)
        {
            using (Pen pen = new Pen(Color.FromArgb(8, 9, 9), 31f * scale))
            {
                pen.StartCap = LineCap.Round;
                pen.EndCap = LineCap.Round;
                pen.LineJoin = LineJoin.Round;

                using (GraphicsPath path = new GraphicsPath())
                {
                    path.StartFigure();
                    path.AddLine(P(443, 251, scale), P(311, 251, scale));
                    path.AddBezier(P(311, 251, scale), P(277, 251, scale), P(258, 270, scale), P(258, 304, scale));
                    path.AddLine(P(258, 304, scale), P(258, 421, scale));
                    graphics.DrawPath(pen, path);
                }

                using (GraphicsPath path = new GraphicsPath())
                {
                    path.StartFigure();
                    path.AddLine(P(812, 251, scale), P(943, 251, scale));
                    path.AddBezier(P(943, 251, scale), P(977, 251, scale), P(996, 270, scale), P(996, 304, scale));
                    path.AddLine(P(996, 304, scale), P(996, 421, scale));
                    graphics.DrawPath(pen, path);
                }

                using (GraphicsPath path = new GraphicsPath())
                {
                    path.StartFigure();
                    path.AddLine(P(258, 815, scale), P(258, 930, scale));
                    path.AddBezier(P(258, 930, scale), P(258, 964, scale), P(277, 982, scale), P(311, 982, scale));
                    path.AddLine(P(311, 982, scale), P(443, 982, scale));
                    graphics.DrawPath(pen, path);
                }

                using (GraphicsPath path = new GraphicsPath())
                {
                    path.StartFigure();
                    path.AddLine(P(812, 982, scale), P(943, 982, scale));
                    path.AddBezier(P(943, 982, scale), P(977, 982, scale), P(996, 964, scale), P(996, 930, scale));
                    path.AddLine(P(996, 930, scale), P(996, 815, scale));
                    graphics.DrawPath(pen, path);
                }
            }
        }

        private static void DrawBolt(Graphics graphics, float scale)
        {
            using (GraphicsPath bolt = new GraphicsPath())
            using (SolidBrush black = new SolidBrush(Color.FromArgb(6, 7, 7)))
            {
                bolt.StartFigure();
                bolt.AddLine(P(945, 372, scale), P(586, 652, scale));
                bolt.AddLine(P(586, 652, scale), P(682, 651, scale));
                bolt.AddBezier(P(682, 651, scale), P(698, 651, scale), P(710, 657, scale), P(708, 667, scale));
                bolt.AddBezier(P(708, 667, scale), P(706, 675, scale), P(699, 681, scale), P(691, 688, scale));
                bolt.AddLine(P(691, 688, scale), P(311, 939, scale));
                bolt.AddLine(P(311, 939, scale), P(548, 734, scale));
                bolt.AddLine(P(548, 734, scale), P(389, 718, scale));
                bolt.CloseFigure();
                graphics.FillPath(black, bolt);
            }
        }

        private static PointF P(float x, float y, float scale)
        {
            return new PointF(x * scale, y * scale);
        }

        private static GraphicsPath RoundedRectangle(RectangleF rectangle, float radius)
        {
            float diameter = radius * 2f;
            GraphicsPath path = new GraphicsPath();
            path.AddArc(rectangle.Left, rectangle.Top, diameter, diameter, 180, 90);
            path.AddArc(rectangle.Right - diameter, rectangle.Top, diameter, diameter, 270, 90);
            path.AddArc(rectangle.Right - diameter, rectangle.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(rectangle.Left, rectangle.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }

        private static void WriteIcon(Bitmap source, string outputPath)
        {
            List<IconImage> images = new List<IconImage>();
            for (int index = 0; index < IconSizes.Length; index++)
            {
                int size = IconSizes[index];
                using (Bitmap resized = new Bitmap(size, size, PixelFormat.Format32bppArgb))
                using (Graphics graphics = Graphics.FromImage(resized))
                using (MemoryStream stream = new MemoryStream())
                {
                    graphics.Clear(Color.Transparent);
                    graphics.CompositingMode = CompositingMode.SourceCopy;
                    graphics.CompositingQuality = CompositingQuality.HighQuality;
                    graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    graphics.SmoothingMode = SmoothingMode.HighQuality;
                    graphics.DrawImage(source, new Rectangle(0, 0, size, size));
                    resized.Save(stream, ImageFormat.Png);
                    images.Add(new IconImage { Size = size, Data = stream.ToArray() });
                }
            }

            using (FileStream stream = File.Create(outputPath))
            using (BinaryWriter writer = new BinaryWriter(stream))
            {
                writer.Write((ushort)0);
                writer.Write((ushort)1);
                writer.Write((ushort)images.Count);

                int offset = 6 + images.Count * 16;
                for (int index = 0; index < images.Count; index++)
                {
                    IconImage image = images[index];
                    writer.Write((byte)(image.Size == 256 ? 0 : image.Size));
                    writer.Write((byte)(image.Size == 256 ? 0 : image.Size));
                    writer.Write((byte)0);
                    writer.Write((byte)0);
                    writer.Write((ushort)1);
                    writer.Write((ushort)32);
                    writer.Write((uint)image.Data.Length);
                    writer.Write((uint)offset);
                    offset += image.Data.Length;
                }

                for (int index = 0; index < images.Count; index++)
                {
                    writer.Write(images[index].Data);
                }
            }
        }
    }
}
