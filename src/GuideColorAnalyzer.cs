using System;
using System.Drawing;

namespace BoltSnip
{
    internal sealed class GuideColorAnalyzer
    {
        internal const int SamplingIntervalMilliseconds = 150;
        private const int SamplingRadius = 8;
        private const int InitialDarkGuideThreshold = 135;
        private const int SwitchToDarkGuideThreshold = 150;
        private const int SwitchToLightGuideThreshold = 110;

        internal static readonly Color DefaultGuideColor = Color.FromArgb(96, 132, 156, 166);
        internal static readonly Color DarkGuideColor = Color.FromArgb(104, 42, 55, 63);
        internal static readonly Color LightGuideColor = Color.FromArgb(112, 230, 237, 240);

        private Color _cachedColor = DefaultGuideColor;
        private int _lastSampleTick;
        private int _sampleCount;
        private bool _hasSample;

        internal Color CachedColor
        {
            get { return _cachedColor; }
        }

        internal int SampleCount
        {
            get { return _sampleCount; }
        }

        internal bool TryUpdate(Bitmap screenshot, Point point)
        {
            return TryUpdateAt(screenshot, point, Environment.TickCount);
        }

        internal bool TryUpdateAt(Bitmap screenshot, Point point, int tickCount)
        {
            if (screenshot == null)
            {
                throw new ArgumentNullException("screenshot");
            }

            if (_hasSample &&
                unchecked((uint)(tickCount - _lastSampleTick)) < SamplingIntervalMilliseconds)
            {
                return false;
            }

            Rectangle bounds = GetSampleBounds(screenshot.Size, point);
            if (bounds.IsEmpty)
            {
                return false;
            }

            int luminance = CalculateAverageLuminance(screenshot, bounds);
            Color nextColor;
            if (!_hasSample)
            {
                nextColor = luminance >= InitialDarkGuideThreshold
                    ? DarkGuideColor
                    : LightGuideColor;
            }
            else if (_cachedColor.ToArgb() == DarkGuideColor.ToArgb())
            {
                nextColor = luminance <= SwitchToLightGuideThreshold
                    ? LightGuideColor
                    : DarkGuideColor;
            }
            else
            {
                nextColor = luminance >= SwitchToDarkGuideThreshold
                    ? DarkGuideColor
                    : LightGuideColor;
            }

            bool changed = nextColor.ToArgb() != _cachedColor.ToArgb();
            _cachedColor = nextColor;
            _lastSampleTick = tickCount;
            _sampleCount++;
            _hasSample = true;
            return changed;
        }

        internal void Reset()
        {
            _cachedColor = DefaultGuideColor;
            _lastSampleTick = 0;
            _sampleCount = 0;
            _hasSample = false;
        }

        internal static Rectangle GetSampleBounds(Size bitmapSize, Point point)
        {
            if (bitmapSize.Width <= 0 || bitmapSize.Height <= 0)
            {
                return Rectangle.Empty;
            }

            int x = Math.Max(0, Math.Min(bitmapSize.Width - 1, point.X));
            int y = Math.Max(0, Math.Min(bitmapSize.Height - 1, point.Y));
            int left = Math.Max(0, x - SamplingRadius);
            int top = Math.Max(0, y - SamplingRadius);
            int right = Math.Min(bitmapSize.Width, x + SamplingRadius + 1);
            int bottom = Math.Min(bitmapSize.Height, y + SamplingRadius + 1);
            return Rectangle.FromLTRB(left, top, right, bottom);
        }

        private static int CalculateAverageLuminance(Bitmap screenshot, Rectangle bounds)
        {
            long total = 0;
            for (int y = bounds.Top; y < bounds.Bottom; y++)
            {
                for (int x = bounds.Left; x < bounds.Right; x++)
                {
                    Color pixel = screenshot.GetPixel(x, y);
                    total += (54 * pixel.R + 183 * pixel.G + 19 * pixel.B) >> 8;
                }
            }

            return (int)(total / (bounds.Width * bounds.Height));
        }
    }
}
