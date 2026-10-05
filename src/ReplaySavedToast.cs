using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace BoltSnip
{
    internal sealed class ReplaySavedToast : Form
    {
        private readonly Timer _animationTimer;
        private readonly Stopwatch _elapsed = new Stopwatch();
        private readonly Font _titleFont = new Font("Microsoft YaHei UI", 11F, FontStyle.Bold);
        private readonly Font _detailFont = new Font("Microsoft YaHei UI", 8.5F);
        private string _message = string.Empty;
        private float _scale = 1F;

        internal ReplaySavedToast()
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            AutoScaleMode = AutoScaleMode.None;
            TopMost = true;
            DoubleBuffered = true;
            BackColor = Color.FromArgb(22, 24, 26);
            ClientSize = new Size(344, 76);
            _animationTimer = new Timer();
            _animationTimer.Interval = 30;
            _animationTimer.Tick += AnimationTick;
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams parameters = base.CreateParams;
                // Tool window, layered, mouse-through, and never activate.
                parameters.ExStyle |= 0x00000080 | 0x00080000 | 0x00000020 | 0x08000000;
                return parameters;
            }
        }

        internal void ShowSaved(string message)
        {
            if (IsDisposed) { return; }
            _message = message ?? string.Empty;
            _scale = DeviceDpi / 96F;
            ClientSize = new Size((int)Math.Round(344 * _scale), (int)Math.Round(76 * _scale));
            Screen screen = Screen.PrimaryScreen ?? Screen.FromPoint(Cursor.Position);
            Rectangle area = screen.WorkingArea;
            int inset = (int)Math.Round(20 * _scale);
            Location = new Point(Math.Max(area.Left, area.Right - Width - inset), area.Top + inset);
            Opacity = 0;
            Invalidate();
            _elapsed.Restart();
            Show();
            _animationTimer.Start();
        }

        private void AnimationTick(object sender, EventArgs e)
        {
            double milliseconds = _elapsed.Elapsed.TotalMilliseconds;
            if (milliseconds >= 3000)
            {
                _animationTimer.Stop();
                Hide();
                return;
            }
            Opacity = milliseconds < 120
                ? milliseconds / 120 * 0.96
                : (milliseconds > 2700 ? (3000 - milliseconds) / 300 * 0.96 : 0.96);
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
            Color green = Color.FromArgb(118, 185, 0);
            using (Brush accent = new SolidBrush(green))
            using (Pen border = new Pen(Color.FromArgb(53, 57, 59)))
            using (Pen check = new Pen(green, 2.5F))
            {
                graphics.FillRectangle(accent, 0, 0, 4, 76);
                graphics.DrawRectangle(border, 4, 0, 339, 75);
                graphics.DrawEllipse(check, 20, 24, 26, 26);
                check.StartCap = LineCap.Round;
                check.EndCap = LineCap.Round;
                graphics.DrawLines(check, new PointF[] {
                    new PointF(27, 37), new PointF(32, 42), new PointF(40, 32) });
            }
            using (Brush title = new SolidBrush(Color.FromArgb(247, 249, 246)))
            using (Brush detail = new SolidBrush(Color.FromArgb(175, 181, 177)))
            using (StringFormat format = new StringFormat())
            {
                format.FormatFlags = StringFormatFlags.NoWrap;
                format.Trimming = StringTrimming.EllipsisCharacter;
                graphics.DrawString("即时回放已保存", _titleFont, title, new RectangleF(60, 14, 268, 25), format);
                graphics.DrawString(_message, _detailFont, detail, new RectangleF(60, 42, 268, 20), format);
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _animationTimer.Stop();
                _animationTimer.Dispose();
                _titleFont.Dispose();
                _detailFont.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}