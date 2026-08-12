using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace BoltSnip
{
    internal sealed class CaptureOverlay : Form
    {
        private const int WindowMagnetRadius = 8;
        private const int WindowTrackingIntervalMilliseconds = 8;

        private enum ToolbarAction
        {
            None,
            Copy,
            Save,
            Cancel
        }

        private readonly Brush _shadeBrush = new SolidBrush(Color.FromArgb(116, 10, 16, 22));
        private readonly Brush _labelBrush = new SolidBrush(Color.FromArgb(226, 20, 26, 32));
        private readonly Brush _toolbarBrush = new SolidBrush(Color.FromArgb(242, 246, 248, 250));
        private readonly Brush _toolbarHoverBrush = new SolidBrush(Color.FromArgb(255, 225, 241, 247));
        private readonly Pen _borderShadowPen = new Pen(Color.FromArgb(140, 0, 0, 0), 3f);
        private readonly Pen _borderPen = new Pen(Color.FromArgb(255, 52, 190, 208), 1f);
        private readonly Font _utilityFont = new Font("Microsoft YaHei UI", 9f, FontStyle.Regular, GraphicsUnit.Point);
        private readonly Font _toolbarFont = new Font("Microsoft YaHei UI", 9f, FontStyle.Regular, GraphicsUnit.Point);
        private readonly Timer _windowTrackingTimer;

        private Bitmap _screen;
        private Rectangle _virtualScreen;
        private List<Rectangle> _windowRectangles = new List<Rectangle>();
        private Rectangle _hoverRectangle = Rectangle.Empty;
        private Rectangle _selection = Rectangle.Empty;
        private Point _dragOrigin;
        private bool _mouseDown;
        private bool _dragging;
        private bool _hasSelection;
        private ToolbarAction _hoverAction;
        private bool _captureActive;
        private Point _lastTrackedCursor;
        private bool _hasTrackedCursor;

        internal CaptureOverlay()
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            TopMost = true;
            KeyPreview = true;
            AutoScaleMode = AutoScaleMode.None;
            BackColor = Color.Black;
            Cursor = Cursors.Cross;
            Text = "BoltSnip.Overlay";

            _windowTrackingTimer = new Timer();
            _windowTrackingTimer.Interval = WindowTrackingIntervalMilliseconds;
            _windowTrackingTimer.Tick += WindowTrackingTimerTick;

            SetStyle(
                ControlStyles.UserPaint |
                ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.ResizeRedraw,
                true);

            MouseDown += OverlayMouseDown;
            MouseMove += OverlayMouseMove;
            MouseUp += OverlayMouseUp;
            MouseDoubleClick += OverlayMouseDoubleClick;
            KeyDown += OverlayKeyDown;
        }

        internal event EventHandler<CaptureStatusEventArgs> CaptureFinished;

        internal bool IsCapturing
        {
            get { return _captureActive; }
        }

        internal void BeginCapture()
        {
            if (_captureActive)
            {
                return;
            }

            ResetSelection();
            _virtualScreen = SystemInformation.VirtualScreen;

            Bitmap captured = ScreenCapture.Capture(_virtualScreen);
            List<Rectangle> windows;
            try
            {
                windows = WindowProbe.Snapshot(_virtualScreen);
            }
            catch
            {
                captured.Dispose();
                throw;
            }

            DisposeCapturedScreen();
            _screen = captured;
            _windowRectangles = windows;
            _captureActive = true;

            Bounds = _virtualScreen;
            Point cursor = Cursor.Position;
            _hoverRectangle = FindWindowAt(new Point(
                cursor.X - _virtualScreen.Left,
                cursor.Y - _virtualScreen.Top));
            Show();
            NativeMethods.SetForegroundWindow(Handle);
            Activate();
            Focus();
            _windowTrackingTimer.Start();
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            if (_screen == null)
            {
                return;
            }

            Graphics graphics = e.Graphics;
            graphics.CompositingQuality = CompositingQuality.HighSpeed;
            graphics.InterpolationMode = InterpolationMode.NearestNeighbor;
            graphics.PixelOffsetMode = PixelOffsetMode.Half;

            GraphicsState state = graphics.Save();
            graphics.SetClip(e.ClipRectangle);
            graphics.DrawImageUnscaled(_screen, 0, 0);
            graphics.FillRectangle(_shadeBrush, e.ClipRectangle);

            Rectangle active = ActiveRectangle;
            if (!active.IsEmpty)
            {
                Rectangle visible = Rectangle.Intersect(active, e.ClipRectangle);
                if (!visible.IsEmpty)
                {
                    graphics.DrawImage(
                        _screen,
                        visible,
                        visible,
                        GraphicsUnit.Pixel);
                }
            }
            graphics.Restore(state);

            if (!active.IsEmpty)
            {
                DrawSelectionChrome(graphics, active);
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                DisposeCapturedScreen();
                _shadeBrush.Dispose();
                _labelBrush.Dispose();
                _toolbarBrush.Dispose();
                _toolbarHoverBrush.Dispose();
                _borderShadowPen.Dispose();
                _borderPen.Dispose();
                _utilityFont.Dispose();
                _toolbarFont.Dispose();
                _windowTrackingTimer.Dispose();
            }

            base.Dispose(disposing);
        }

        private Rectangle ActiveRectangle
        {
            get { return _hasSelection || _dragging ? _selection : _hoverRectangle; }
        }

        private void OverlayMouseDown(object sender, MouseEventArgs e)
        {
            if (!_captureActive)
            {
                return;
            }

            ToolbarAction completionAction = GetSelectionClickAction(e.Button, e.Location);
            if (completionAction != ToolbarAction.None)
            {
                PerformToolbarAction(completionAction);
                return;
            }

            if (e.Button == MouseButtons.Right)
            {
                Finish(false, "已取消");
                return;
            }

            if (e.Button != MouseButtons.Left)
            {
                return;
            }

            _mouseDown = true;
            _dragging = false;
            _dragOrigin = ClampToClient(e.Location);
            _selection = _hoverRectangle;
            Capture = true;
        }

        private void OverlayMouseMove(object sender, MouseEventArgs e)
        {
            if (!_captureActive)
            {
                return;
            }

            if (_mouseDown)
            {
                Point current = ClampToClient(e.Location);
                int distance = Math.Abs(current.X - _dragOrigin.X) + Math.Abs(current.Y - _dragOrigin.Y);
                if (!_dragging && distance >= 4)
                {
                    _dragging = true;
                    _hasSelection = false;
                }

                if (_dragging)
                {
                    Rectangle old = _selection;
                    _selection = RectangleFromPoints(_dragOrigin, current);
                    InvalidateSelectionTransition(old, _selection, false);
                }
                return;
            }

            if (_hasSelection)
            {
                ToolbarAction oldAction = _hoverAction;
                _hoverAction = HitTestToolbar(e.Location);
                Cursor = _hoverAction == ToolbarAction.None ? Cursors.Cross : Cursors.Hand;
                if (oldAction != _hoverAction)
                {
                    Invalidate(GetToolbarBounds(_selection));
                }
                return;
            }

            TrackWindowAt(e.Location);
        }

        private void WindowTrackingTimerTick(object sender, EventArgs e)
        {
            if (!_captureActive || _mouseDown || _hasSelection)
            {
                return;
            }

            Point location = PointToClient(Cursor.Position);
            if (!ClientRectangle.Contains(location) ||
                (_hasTrackedCursor && location == _lastTrackedCursor))
            {
                return;
            }

            TrackWindowAt(location);
        }

        private void TrackWindowAt(Point location)
        {
            _lastTrackedCursor = location;
            _hasTrackedCursor = true;

            Rectangle oldHover = _hoverRectangle;
            _hoverRectangle = FindWindowAt(location);
            if (oldHover != _hoverRectangle)
            {
                InvalidateSelectionTransition(oldHover, _hoverRectangle, false);
            }
        }

        private void OverlayMouseUp(object sender, MouseEventArgs e)
        {
            if (!_mouseDown || e.Button != MouseButtons.Left)
            {
                return;
            }

            _mouseDown = false;
            Capture = false;

            if (!_dragging)
            {
                _selection = _hoverRectangle;
            }

            _dragging = false;
            _hasSelection = _selection.Width > 1 && _selection.Height > 1;
            _hoverAction = ToolbarAction.None;
            InvalidateSelectionChrome(_selection, true);
        }

        private void OverlayMouseDoubleClick(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left && _hasSelection && _selection.Contains(e.Location))
            {
                CopySelection();
            }
        }

        private void OverlayKeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Escape)
            {
                Finish(false, "已取消");
                e.Handled = true;
                return;
            }

            if (!_hasSelection)
            {
                return;
            }

            if (e.KeyCode == Keys.Enter || (e.Control && e.KeyCode == Keys.C))
            {
                CopySelection();
                e.Handled = true;
            }
            else if (e.Control && e.KeyCode == Keys.S)
            {
                SaveSelection();
                e.Handled = true;
            }
        }

        private void DrawSelectionChrome(Graphics graphics, Rectangle rectangle)
        {
            Rectangle border = rectangle;
            border.Width = Math.Max(1, border.Width - 1);
            border.Height = Math.Max(1, border.Height - 1);
            graphics.DrawRectangle(_borderShadowPen, border);
            graphics.DrawRectangle(_borderPen, border);

            string dimensions = rectangle.Width + " × " + rectangle.Height;
            Size labelSize = TextRenderer.MeasureText(
                dimensions,
                _utilityFont,
                Size.Empty,
                TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);

            Rectangle label = new Rectangle(
                rectangle.Left,
                rectangle.Top - labelSize.Height - 10,
                labelSize.Width + 14,
                labelSize.Height + 6);

            if (label.Top < 4)
            {
                label.Y = rectangle.Top + 6;
            }

            using (GraphicsPath path = RoundedRectangle(label, 5))
            {
                graphics.FillPath(_labelBrush, path);
            }

            TextRenderer.DrawText(
                graphics,
                dimensions,
                _utilityFont,
                new Rectangle(label.Left + 7, label.Top + 3, label.Width - 14, label.Height - 6),
                Color.White,
                TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter);

            if (_hasSelection)
            {
                DrawToolbar(graphics, rectangle);
            }
        }

        private void DrawToolbar(Graphics graphics, Rectangle selection)
        {
            Rectangle toolbar = GetToolbarBounds(selection);
            using (GraphicsPath path = RoundedRectangle(toolbar, 8))
            {
                graphics.FillPath(_toolbarBrush, path);
            }

            DrawToolbarButton(graphics, ToolbarAction.Copy, "复制 · 左键", 0);
            DrawToolbarButton(graphics, ToolbarAction.Save, "保存 · 右键", 1);
            DrawToolbarButton(graphics, ToolbarAction.Cancel, "取消", 2);
        }

        private void DrawToolbarButton(Graphics graphics, ToolbarAction action, string text, int index)
        {
            Rectangle button = GetToolbarButtonBounds(index);
            if (_hoverAction == action)
            {
                using (GraphicsPath path = RoundedRectangle(button, 6))
                {
                    graphics.FillPath(_toolbarHoverBrush, path);
                }
            }

            TextRenderer.DrawText(
                graphics,
                text,
                _toolbarFont,
                button,
                action == ToolbarAction.Copy ? Color.FromArgb(20, 118, 132) : Color.FromArgb(42, 48, 54),
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
        }

        private Rectangle GetToolbarBounds(Rectangle selection)
        {
            const int width = 244;
            const int height = 40;
            int x = selection.Right - width;
            int y = selection.Bottom + 9;

            x = Math.Max(6, Math.Min(ClientSize.Width - width - 6, x));
            if (y + height > ClientSize.Height - 6)
            {
                y = selection.Top - height - 9;
            }
            y = Math.Max(6, y);
            return new Rectangle(x, y, width, height);
        }

        private Rectangle GetToolbarButtonBounds(int index)
        {
            Rectangle toolbar = GetToolbarBounds(_selection);
            int[] widths = { 100, 80, 60 };
            int x = toolbar.Left + 2;
            for (int i = 0; i < index; i++)
            {
                x += widths[i];
            }
            return new Rectangle(x, toolbar.Top + 2, widths[index], toolbar.Height - 4);
        }

        private ToolbarAction HitTestToolbar(Point location)
        {
            if (!_hasSelection || !GetToolbarBounds(_selection).Contains(location))
            {
                return ToolbarAction.None;
            }

            if (GetToolbarButtonBounds(0).Contains(location)) return ToolbarAction.Copy;
            if (GetToolbarButtonBounds(1).Contains(location)) return ToolbarAction.Save;
            if (GetToolbarButtonBounds(2).Contains(location)) return ToolbarAction.Cancel;
            return ToolbarAction.None;
        }

        private ToolbarAction GetSelectionClickAction(MouseButtons button, Point location)
        {
            if (!_hasSelection)
            {
                return ToolbarAction.None;
            }

            if (button == MouseButtons.Right)
            {
                return ToolbarAction.Save;
            }

            if (button != MouseButtons.Left)
            {
                return ToolbarAction.None;
            }

            ToolbarAction toolbarAction = HitTestToolbar(location);
            return toolbarAction == ToolbarAction.None
                ? ToolbarAction.Copy
                : toolbarAction;
        }

        private void PerformToolbarAction(ToolbarAction action)
        {
            if (action == ToolbarAction.Copy) CopySelection();
            else if (action == ToolbarAction.Save) SaveSelection();
            else if (action == ToolbarAction.Cancel) Finish(false, "已取消");
        }

        private void CopySelection()
        {
            if (!_hasSelection || _screen == null)
            {
                return;
            }

            try
            {
                using (Bitmap cropped = ScreenCapture.Crop(_screen, _selection))
                {
                    Clipboard.SetDataObject(cropped, true, 5, 40);
                }
                Finish(true, "已复制到剪贴板");
            }
            catch (ExternalException)
            {
                System.Media.SystemSounds.Exclamation.Play();
            }
        }

        private void SaveSelection()
        {
            if (!_hasSelection || _screen == null)
            {
                return;
            }

            try
            {
                using (SaveFileDialog dialog = new SaveFileDialog())
                {
                    dialog.Title = "保存截图";
                    dialog.Filter = "PNG 图像 (*.png)|*.png|JPEG 图像 (*.jpg)|*.jpg";
                    dialog.DefaultExt = "png";
                    dialog.AddExtension = true;
                    dialog.FileName = "截图_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".png";

                    if (dialog.ShowDialog(this) != DialogResult.OK)
                    {
                        return;
                    }

                    using (Bitmap cropped = ScreenCapture.Crop(_screen, _selection))
                    {
                        ImageFormat format = dialog.FileName.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase)
                            ? ImageFormat.Jpeg
                            : ImageFormat.Png;
                        cropped.Save(dialog.FileName, format);
                    }
                }

                Finish(true, "截图已保存");
            }
            catch (Exception exception)
            {
                MessageBox.Show(this, exception.Message, "保存失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private Rectangle FindWindowAt(Point point)
        {
            for (int i = 0; i < _windowRectangles.Count; i++)
            {
                if (_windowRectangles[i].Contains(point))
                {
                    return _windowRectangles[i];
                }
            }

            // Keep window snapping responsive around thin borders and shadows. Exact hits are
            // always preferred, then the topmost window within a small magnetic edge radius.
            for (int i = 0; i < _windowRectangles.Count; i++)
            {
                Rectangle magneticBounds = _windowRectangles[i];
                magneticBounds.Inflate(WindowMagnetRadius, WindowMagnetRadius);
                if (magneticBounds.Contains(point))
                {
                    return _windowRectangles[i];
                }
            }

            Screen monitor = Screen.FromPoint(PointToScreen(point));
            Rectangle bounds = monitor.Bounds;
            return new Rectangle(
                bounds.Left - _virtualScreen.Left,
                bounds.Top - _virtualScreen.Top,
                bounds.Width,
                bounds.Height);
        }

        private void Finish(bool succeeded, string message)
        {
            if (!_captureActive)
            {
                return;
            }

            _captureActive = false;
            _windowTrackingTimer.Stop();
            Capture = false;
            Hide();
            DisposeCapturedScreen();
            ResetSelection();

            EventHandler<CaptureStatusEventArgs> handler = CaptureFinished;
            if (handler != null)
            {
                handler(this, new CaptureStatusEventArgs(succeeded, message));
            }
        }

        private void ResetSelection()
        {
            _hoverRectangle = Rectangle.Empty;
            _selection = Rectangle.Empty;
            _mouseDown = false;
            _dragging = false;
            _hasSelection = false;
            _hoverAction = ToolbarAction.None;
            _hasTrackedCursor = false;
            Cursor = Cursors.Cross;
        }

        private void DisposeCapturedScreen()
        {
            if (_screen != null)
            {
                _screen.Dispose();
                _screen = null;
            }
        }

        private Point ClampToClient(Point point)
        {
            return new Point(
                Math.Max(0, Math.Min(ClientSize.Width, point.X)),
                Math.Max(0, Math.Min(ClientSize.Height, point.Y)));
        }

        private static Rectangle RectangleFromPoints(Point first, Point second)
        {
            return Rectangle.FromLTRB(
                Math.Min(first.X, second.X),
                Math.Min(first.Y, second.Y),
                Math.Max(first.X, second.X),
                Math.Max(first.Y, second.Y));
        }

        private void InvalidateSelectionTransition(Rectangle oldRectangle, Rectangle newRectangle, bool includeToolbar)
        {
            if (oldRectangle.IsEmpty && newRectangle.IsEmpty)
            {
                return;
            }

            Region changed = oldRectangle.IsEmpty
                ? new Region(newRectangle)
                : new Region(oldRectangle);
            try
            {
                if (!newRectangle.IsEmpty && !oldRectangle.IsEmpty)
                {
                    changed.Xor(newRectangle);
                }

                AddSelectionChrome(changed, oldRectangle, includeToolbar);
                AddSelectionChrome(changed, newRectangle, includeToolbar);
                Invalidate(changed);
            }
            finally
            {
                changed.Dispose();
            }
        }

        private void InvalidateSelectionChrome(Rectangle rectangle, bool includeToolbar)
        {
            if (rectangle.IsEmpty)
            {
                return;
            }

            Region chrome = new Region(Rectangle.Empty);
            try
            {
                AddSelectionChrome(chrome, rectangle, includeToolbar);
                Invalidate(chrome);
            }
            finally
            {
                chrome.Dispose();
            }
        }

        private void AddSelectionChrome(Region region, Rectangle rectangle, bool includeToolbar)
        {
            if (rectangle.IsEmpty)
            {
                return;
            }

            const int edge = 5;
            region.Union(new Rectangle(rectangle.Left - edge, rectangle.Top - edge, rectangle.Width + edge * 2, edge * 2));
            region.Union(new Rectangle(rectangle.Left - edge, rectangle.Bottom - edge, rectangle.Width + edge * 2, edge * 2));
            region.Union(new Rectangle(rectangle.Left - edge, rectangle.Top, edge * 2, rectangle.Height));
            region.Union(new Rectangle(rectangle.Right - edge, rectangle.Top, edge * 2, rectangle.Height));
            region.Union(GetDimensionLabelBounds(rectangle));
            if (includeToolbar)
            {
                region.Union(GetToolbarBounds(rectangle));
            }
        }

        private Rectangle GetDimensionLabelBounds(Rectangle rectangle)
        {
            string dimensions = rectangle.Width + " × " + rectangle.Height;
            Size size = TextRenderer.MeasureText(
                dimensions,
                _utilityFont,
                Size.Empty,
                TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);

            Rectangle label = new Rectangle(
                rectangle.Left,
                rectangle.Top - size.Height - 10,
                size.Width + 14,
                size.Height + 6);
            if (label.Top < 4)
            {
                label.Y = rectangle.Top + 6;
            }
            return label;
        }

        private static GraphicsPath RoundedRectangle(Rectangle rectangle, int radius)
        {
            int diameter = radius * 2;
            GraphicsPath path = new GraphicsPath();
            path.AddArc(rectangle.Left, rectangle.Top, diameter, diameter, 180, 90);
            path.AddArc(rectangle.Right - diameter, rectangle.Top, diameter, diameter, 270, 90);
            path.AddArc(rectangle.Right - diameter, rectangle.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(rectangle.Left, rectangle.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }
    }

    internal sealed class CaptureStatusEventArgs : EventArgs
    {
        internal CaptureStatusEventArgs(bool succeeded, string message)
        {
            Succeeded = succeeded;
            Message = message;
        }

        internal bool Succeeded { get; private set; }
        internal string Message { get; private set; }
    }
}
