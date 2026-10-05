using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace BoltSnip
{
    internal sealed class ReplaySavedToast : Form
    {
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

        private readonly Timer _animationTimer;
        private readonly Stopwatch _elapsed = new Stopwatch();
        private readonly Font _brandFont = new Font("Segoe UI", 6.8F, FontStyle.Bold);
        private readonly Font _titleFont = new Font("Microsoft YaHei UI", 11.5F, FontStyle.Bold);
        private readonly Font _detailFont = new Font("Microsoft YaHei UI", 8F);
        private string _message = string.Empty;
        private float _scale = 1F;
        private Point _restingLocation;
        private double _startOpacity;
        private double _startOffset;

        internal ReplaySavedToast()
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            AutoScaleMode = AutoScaleMode.None;
            TopMost = true;
            DoubleBuffered = true;
            BackColor = Color.FromArgb(17, 24, 36);
            ClientSize = new Size(352, 92);
            _animationTimer = new Timer();
            _animationTimer.Interval = 15;
            _animationTimer.Tick += AnimationTick;
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams parameters = base.CreateParams;
                parameters.ExStyle |= 0x00000080 | 0x00080000 | 0x00000020 | 0x08000000;
                return parameters;
            }
        }

        internal void ShowSaved(string message)
        {
            if (IsDisposed) { return; }
            _message = message ?? string.Empty;
            int separator = _message.LastIndexOf(" · ", StringComparison.Ordinal);
            if (separator > 0 && _message.EndsWith(" 秒", StringComparison.Ordinal))
            {
                _message = _message.Substring(separator + 3) + " · " + _message.Substring(0, separator);
            }
            if (!IsHandleCreated) { CreateHandle(); }
            _scale = DeviceDpi / 96F;
            ClientSize = new Size((int)Math.Round(352 * _scale), (int)Math.Round(92 * _scale));
            UpdateShape();
            Screen screen = Screen.PrimaryScreen ?? Screen.FromPoint(Cursor.Position);
            Rectangle area = screen.WorkingArea;
            int inset = (int)Math.Round(20 * _scale);
            _restingLocation = new Point(Math.Max(area.Left, area.Right - Width), area.Top + inset);
            _startOpacity = Visible ? Opacity : 0;
            _startOffset = Visible ? Location.X - _restingLocation.X : 36 * _scale;
            if (!Visible)
            {
                Location = new Point(_restingLocation.X + (int)Math.Round(_startOffset), _restingLocation.Y);
                Opacity = 0;
            }
            _elapsed.Restart();
            Invalidate();
            if (!Visible) { Show(); }
            // ShowWithoutActivation alone does not reliably promote a hidden Form to the topmost band.
            SetWindowPos(Handle, new IntPtr(-1), Left, Top, 0, 0, 0x0010 | 0x0001);
            _animationTimer.Start();
        }

        private void AnimationTick(object sender, EventArgs e)
        {
            double milliseconds = _elapsed.Elapsed.TotalMilliseconds;
            if (milliseconds >= 3250)
            {
                _animationTimer.Stop();
                Hide();
                return;
            }
            double opacity;
            double offset;
            if (milliseconds < 320)
            {
                double progress = Math.Max(0, milliseconds / 320);
                double eased = 1 - Math.Pow(1 - progress, 3);
                opacity = _startOpacity + (0.96 - _startOpacity) * eased;
                offset = _startOffset * (1 - eased);
            }
            else if (milliseconds < 2850)
            {
                opacity = 0.96;
                offset = 0;
            }
            else
            {
                double progress = Math.Min(1, (milliseconds - 2850) / 400);
                double eased = progress * progress * (3 - 2 * progress);
                opacity = 0.96 * (1 - eased);
                offset = 12 * _scale * eased;
            }
            SetWindowPos(Handle, new IntPtr(-1), _restingLocation.X + (int)Math.Round(offset), _restingLocation.Y, 0, 0, 0x0010 | 0x0001 | 0x0200);
            Opacity = Math.Max(0, Math.Min(0.96, opacity));
            Invalidate();
        }

        private static GraphicsPath RoundedPath(RectangleF bounds, float radius, bool rightSquare = false)
        {
            GraphicsPath path = new GraphicsPath();
            float diameter = radius * 2;
            path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
            if (rightSquare) { path.AddLine(bounds.Right, bounds.Top, bounds.Right, bounds.Bottom); }
            else {
                path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
                path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
            }
            path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }

        private void UpdateShape()
        {
            if (ClientSize.Width <= 0 || ClientSize.Height <= 0) { return; }
            using (GraphicsPath shape = RoundedPath(new RectangleF(0, 0, Width, Height), 16 * _scale, true))
            {
                Region previous = Region;
                Region = new Region(shape);
                if (previous != null) { previous.Dispose(); }
            }
        }

        protected override void OnSizeChanged(EventArgs e)
        {
            base.OnSizeChanged(e);
            UpdateShape();
        }

        protected override void WndProc(ref Message message)
        {
            if (message.Msg == 0x0084) { message.Result = new IntPtr(-1); return; }
            if (message.Msg == 0x0021) { message.Result = new IntPtr(3); return; }
            base.WndProc(ref message);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Graphics graphics = e.Graphics;
            graphics.ScaleTransform(_scale, _scale);
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath card = RoundedPath(new RectangleF(0.5F, 0.5F, 351, 91), 16, true))
            using (Brush background = new LinearGradientBrush(new Point(0, 0), new Point(352, 92),
                Color.FromArgb(26, 39, 60), Color.FromArgb(17, 24, 36)))
            using (Pen border = new Pen(Color.FromArgb(61, 77, 100)))
            {
                graphics.FillPath(background, card);
                graphics.DrawPath(border, card);
            }
            using (GraphicsPath tile = RoundedPath(new RectangleF(20, 26, 40, 40), 12))
            using (Brush light = new LinearGradientBrush(new Point(20, 26), new Point(60, 66),
                Color.FromArgb(94, 129, 255), Color.FromArgb(41, 207, 214)))
            using (Brush white = new SolidBrush(Color.FromArgb(249, 253, 255)))
            {
                graphics.FillPath(light, tile);
                graphics.FillPolygon(white, new PointF[] { new PointF(44, 33), new PointF(32, 49),
                    new PointF(40, 49), new PointF(36, 59), new PointF(49, 43), new PointF(41, 43) });
            }
            using (Brush brand = new SolidBrush(Color.FromArgb(129, 153, 187)))
            using (Brush title = new SolidBrush(Color.FromArgb(239, 246, 255)))
            using (Brush detail = new SolidBrush(Color.FromArgb(162, 181, 207)))
            using (StringFormat format = new StringFormat())
            {
                format.FormatFlags = StringFormatFlags.NoWrap;
                format.Trimming = StringTrimming.EllipsisCharacter;
                graphics.DrawString("BOLTSNIP", _brandFont, brand, new RectangleF(78, 13, 254, 13), format);
                graphics.DrawString("回放已保存", _titleFont, title, new RectangleF(76, 28, 256, 26), format);
                graphics.DrawString(_message, _detailFont, detail, new RectangleF(78, 59, 254, 20), format);
            }
            double remaining = _elapsed.IsRunning ? Math.Max(0, 1 - _elapsed.Elapsed.TotalMilliseconds / 3250) : 1;
            using (Pen track = new Pen(Color.FromArgb(43, 58, 78), 2))
            using (Pen progress = new Pen(Color.FromArgb(80, 175, 235), 2))
            {
                track.StartCap = track.EndCap = LineCap.Round;
                progress.StartCap = progress.EndCap = LineCap.Round;
                graphics.DrawLine(track, 78, 85, 328, 85);
                if (remaining > 0) { graphics.DrawLine(progress, 78, 85, 78 + (float)(250 * remaining), 85); }
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _animationTimer.Stop();
                _animationTimer.Dispose();
                _brandFont.Dispose();
                _titleFont.Dispose();
                _detailFont.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}