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
        private const long JpegQuality = 95L;
        private const int MagnifierColumns = 13;
        private const int MagnifierRows = 7;
        private const int MagnifierScale = 10;
        private const int MagnifierPadding = 4;
        private const int MagnifierCaptionHeight = 25;
        private const int MagnifierCursorOffset = 20;

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
        private readonly Brush _magnifierBrush = new SolidBrush(Color.FromArgb(242, 20, 26, 32));
        private readonly Brush _magnifierPixelAreaBrush = new SolidBrush(Color.FromArgb(255, 8, 12, 16));
        private readonly Pen _borderShadowPen = new Pen(Color.FromArgb(140, 0, 0, 0), 3f);
        private readonly Pen _borderPen = new Pen(Color.FromArgb(255, 52, 190, 208), 1f);
        private readonly Pen _magnifierBorderPen = new Pen(Color.FromArgb(210, 255, 255, 255), 1f);
        private readonly Pen _magnifierGridPen = new Pen(Color.FromArgb(58, 255, 255, 255), 1f);
        private readonly Pen _magnifierCrosshairPen = new Pen(Color.FromArgb(255, 52, 190, 208), 2f);
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
        private Point _magnifierPoint;
        private bool _hasMagnifierPoint;

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
            Point clientCursor = new Point(
                cursor.X - _virtualScreen.Left,
                cursor.Y - _virtualScreen.Top);
            _hoverRectangle = FindWindowAt(clientCursor);
            UpdateMagnifier(clientCursor);
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

            if (_captureActive && !_hasSelection && _hasMagnifierPoint)
            {
                DrawMagnifier(graphics, _magnifierPoint);
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
                _magnifierBrush.Dispose();
                _magnifierPixelAreaBrush.Dispose();
                _borderShadowPen.Dispose();
                _borderPen.Dispose();
                _magnifierBorderPen.Dispose();
                _magnifierGridPen.Dispose();
                _magnifierCrosshairPen.Dispose();
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
                Finish(false, "å·²å–æ¶ˆ");
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

            if (!_hasSelection)
            {
                UpdateMagnifier(e.Location);
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

            UpdateMagnifier(location);
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

            Rectangle magnifierBounds = _hasMagnifierPoint
                ? GetMagnifierBounds(_magnifierPoint)
                : Rectangle.Empty;

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
            if (!magnifierBounds.IsEmpty)
            {
                Invalidate(magnifierBounds);
            }
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
                Finish(false, "å·²å–æ¶ˆ");
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

            string dimensions = rectangle.Width + " Ã— " + rectangle.Height;
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

        private void DrawMagnifier(Graphics graphics, Point point)
        {
            if (_screen == null || point.X < 0 || point.Y < 0 ||
                point.X >= _screen.Width || point.Y >= _screen.Height)
            {
                return;
            }

            Rectangle bounds = GetMagnifierBounds(point);
            Rectangle pixels = new Rectangle(
                bounds.Left + MagnifierPadding,
                bounds.Top + MagnifierPadding,
                MagnifierColumns * MagnifierScale,
                MagnifierRows * MagnifierScale);

            using (GraphicsPath shell = RoundedRectangle(bounds, 7))
          ×n¼¶‰ËkºwµçUÑÕÉ¸ì(€€€€€€€€€€€ô((€€€€€€€€€€€½±‘	½Õ¹‘Ì¹%¹™±…Ñ” È°€È¤ì(€€€€€€€€€€€¹•İ	½Õ¹‘Ì¹%¹™±…Ñ” È°€È¤ì(€€€€€€€€€€€%¹Ù…±¥‘…Ñ”¡I•Ñ…¹±”¹U¹¥½¸¡½±‘	½Õ¹‘Ì°¹•İ	½Õ¹‘Ì¤¤ì(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”I•Ñ…¹±”•Ñ5…¹¥™¥•É	½Õ¹‘Ì¡A½¥¹ĞÁ½¥¹Ğ¤(€€€€€€€ì(€€€€€€€€€€€¥¹Ğİ¥‘Ñ €ô€¡5…¹¥™¥•É½±Õµ¹Ì€¨5…¹¥™¥•ÉM…±”¤€¬€¡5…¹¥™¥•ÉA…‘‘¥¹œ€¨€È¤ì(€€€€€€€€€€€¥¹Ğ¡•¥¡Ğ€ô€¡5…¹¥™¥•ÉI½İÌ€¨5…¹¥™¥•ÉM…±”¤€¬5…¹¥™¥•É…ÁÑ¥½¹!•¥¡Ğ€¬(€€€€€€€€€€€€€€€€¡5…¹¥™¥•ÉA…‘‘¥¹œ€¨€È¤ì(€€€€€€€€€€€¥¹Ğà€ôÁ½¥¹Ğ¹`€¬5…¹¥™¥•ÉÕÉÍ½É=™™Í•Ğì(€€€€€€€€€€€¥¹Ğä€ôÁ½¥¹Ğ¹d€¬5…¹¥™¥•ÉÕÉÍ½É=™™Í•Ğì((€€€€€€€€€€€¥˜€¡à€¬İ¥‘Ñ €ø±¥•¹ÑM¥é”¹]¥‘Ñ €´€Ø¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€à€ôÁ½¥¹Ğ¹`€´5…¹¥™¥•ÉÕÉÍ½É=™™Í•Ğ€´İ¥‘Ñ ì(€€€€€€€€€€€ô(€€€€€€€€€€€¥˜€¡ä€¬¡•¥¡Ğ€ø±¥•¹ÑM¥é”¹!•¥¡Ğ€´€Ø¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€ä€ôÁ½¥¹Ğ¹d€´5…¹¥™¥•ÉÕÉÍ½É=™™Í•Ğ€´¡•¥¡Ğì(€€€€€€€€€€€ô((€€€€€€€€€€€à€ô5…Ñ ¹5…à Ø°5…Ñ ¹5¥¸¡±¥•¹ÑM¥é”¹]¥‘Ñ €´İ¥‘Ñ €´€Ø°à¤¤ì(€€€€€€€€€€€ä€ô5…Ñ ¹5…à Ø°5…Ñ ¹5¥¸¡±¥•¹ÑM¥é”¹!•¥¡Ğ€´¡•¥¡Ğ€´€Ø°ä¤¤ì(€€€€€€€€€€€É•ÑÕÉ¸¹•ÜI•Ñ…¹±”¡à°ä°İ¥‘Ñ °¡•¥¡Ğ¤ì(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥ŒI•Ñ…¹±”•Ñ5…¹¥™¥•ÉM…µÁ±•I•Ñ…¹±”¡A½¥¹ĞÁ½¥¹Ğ¤(€€€€€€€ì(€€€€€€€€€€€É•ÑÕÉ¸¹•ÜI•Ñ…¹±” (€€€€€€€€€€€€€€€Á½¥¹Ğ¹`€´€¡5…¹¥™¥•É½±Õµ¹Ì€¼€È¤°(€€€€€€€€€€€€€€€Á½¥¹Ğ¹d€´€¡5…¹¥™¥•ÉI½İÌ€¼€È¤°(€€€€€€€€€€€€€€€5…¹¥™¥•É½±Õµ¹Ì°(€€€€€€€€€€€€€€€5…¹¥™¥•ÉI½İÌ¤ì(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”Ù½¥É…İQ½½±‰…È¡É…Á¡¥ÌÉ…Á¡¥Ì°I•Ñ…¹±”Í•±•Ñ¥½¸¤(€€€€€€€ì(€€€€€€€€€€€I•Ñ…¹±”Ñ½½±‰…È€ô•ÑQ½½±‰…É	½Õ¹‘Ì¡Í•±•Ñ¥½¸¤ì(€€€€€€€€€€€ÕÍ¥¹œ€¡É…Á¡¥ÍA…Ñ Á…Ñ €ôI½Õ¹‘•‘I•Ñ…¹±”¡Ñ½½±‰…È°€à¤¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€É…Á¡¥Ì¹¥±±A…Ñ ¡}Ñ½½±‰…É	ÉÕÍ °Á…Ñ ¤ì(€€€€€€€€€€€ô((€€€€€€€€€€€É…İQ½½±‰…É	ÕÑÑ½¸¡É…Á¡¥Ì°Q½½±‰…ÉÑ¥½¸¹½Áä°€‹–’7–"Øƒ
Üƒ–Ş›¦R¸ˆ°€À¤ì(€€€€€€€€€€€É…İQ½½±‰…É	ÕÑÑ½¸¡É…Á¡¥Ì°Q½½±‰…ÉÑ¥½¸¹M…Ù”°€‹’şw–¶`ƒ
Üƒ–>Ï¦R¸ˆ°€Ä¤ì(€€€€€€€€€€€É…İQ½½±‰…É	ÕÑÑ½¸¡É…Á¡¥Ì°Q½½±‰…ÉÑ¥½¸¹…¹•°°€‹–>[šÚ ˆ°€È¤ì(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”Ù½¥É…İQ½½±‰…É	ÕÑÑ½¸¡É…Á¡¥ÌÉ…Á¡¥Ì°Q½½±‰…ÉÑ¥½¸…Ñ¥½¸°ÍÑÉ¥¹œÑ•áĞ°¥¹Ğ¥¹‘•à¤(€€€€€€€ì(€€€€€€€€€€€I•Ñ…¹±”‰ÕÑÑ½¸€ô•ÑQ½½±‰…É	ÕÑÑ½¹	½Õ¹‘Ì¡¥¹‘•à¤ì(€€€€€€€€€€€¥˜€¡}¡½Ù•ÉÑ¥½¸€ôô…Ñ¥½¸¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€ÕÍ¥¹œ€¡É…Á¡¥ÍA…Ñ Á…Ñ €ôI½Õ¹‘•‘I•Ñ…¹±”¡‰ÕÑÑ½¸°€Ø¤¤(€€€€€€€€€€€€€€€ì(€€€€€€€€€€€€€€€€€€€É…Á¡¥Ì¹¥±±A…Ñ ¡}Ñ½½±‰…É!½Ù•É	ÉÕÍ °Á…Ñ ¤ì(€€€€€€€€€€€€€€€ô(€€€€€€€€€€€ô((€€€€€€€€€€€Q•áÑI•¹‘•É•È¹É…İQ•áĞ (€€€€€€€€€€€€€€€É…Á¡¥Ì°(€€€€€€€€€€€€€€€Ñ•áĞ°(€€€€€€€€€€€€€€€}Ñ½½±‰…É½¹Ğ°(€€€€€€€€€€€€€€€‰ÕÑÑ½¸°(€€€€€€€€€€€€€€€…Ñ¥½¸€ôôQ½½±‰…ÉÑ¥½¸¹½Áä€ü½±½È¹É½µÉˆ ÈÀ°€ÄÄà°€ÄÌÈ¤€è½±½È¹É½µÉˆ ĞÈ°€Ğà°€ÔĞ¤°(€€€€€€€€€€€€€€€Q•áÑ½Éµ…Ñ±…Ì¹!½É¥é½¹Ñ…±•¹Ñ•ÈğQ•áÑ½Éµ…Ñ±…Ì¹Y•ÉÑ¥…±•¹Ñ•ÈğQ•áÑ½Éµ…Ñ±…Ì¹9½A…‘‘¥¹œğQ•áÑ½Éµ…Ñ±…Ì¹M¥¹±•1¥¹”¤ì(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”I•Ñ…¹±”•ÑQ½½±‰…É	½Õ¹‘Ì¡I•Ñ…¹±”Í•±•Ñ¥½¸¤(€€€€€€€ì(€€€€€€€€€€€½¹ÍĞ¥¹Ğİ¥‘Ñ €ô€ÈĞĞì(€€€€€€€€€€€½¹ÍĞ¥¹Ğ¡•¥¡Ğ€ô€ĞÀì(€€€€€€€€€€€¥¹Ğà€ôÍ•±•Ñ¥½¸¹I¥¡Ğ€´İ¥‘Ñ ì(€€€€€€€€€€€¥¹Ğä€ôÍ•±•Ñ¥½¸¹	½ÑÑ½´€¬€äì((€€€€€€€€€€€à€ô5…Ñ ¹5…à Ø°5…Ñ ¹5¥¸¡±¥•¹ÑM¥é”¹]¥‘Ñ €´İ¥‘Ñ €´€Ø°à¤¤ì(€€€€€€€€€€€¥˜€¡ä€¬¡•¥¡Ğ€ø±¥•¹ÑM¥é”¹!•¥¡Ğ€´€Ø¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€ä€ôÍ•±•Ñ¥½¸¹Q½À€´¡•¥¡Ğ€´€äì(€€€€€€€€€€€ô(€€€€€€€€€€€ä€ô5…Ñ ¹5…à Ø°ä¤ì(€€€€€€€€€€€É•ÑÕÉ¸¹•ÜI•Ñ…¹±”¡à°ä°İ¥‘Ñ °¡•¥¡Ğ¤ì(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”I•Ñ…¹±”•ÑQ½½±‰…É	ÕÑÑ½¹	½Õ¹‘Ì¡¥¹Ğ¥¹‘•à¤(€€€€€€€ì(€€€€€€€€€€€I•Ñ…¹±”Ñ½½±‰…È€ô•ÑQ½½±‰…É	½Õ¹‘Ì¡}Í•±•Ñ¥½¸¤ì(€€€€€€€€€€€¥¹Ñmtİ¥‘Ñ¡Ì€ôì€ÄÀÀ°€àÀ°€ØÀôì(€€€€€€€€€€€¥¹Ğà€ôÑ½½±‰…È¹1•™Ğ€¬€Èì(€€€€€€€€€€€™½È€¡¥¹Ğ¤€ô€Àì¤€ğ¥¹‘•àì¤¬¬¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€à€¬ôİ¥‘Ñ¡Ím¥tì(€€€€€€€€€€€ô(€€€€€€€€€€€É•ÑÕÉ¸¹•ÜI•Ñ…¹±”¡à°Ñ½½±‰…È¹Q½À€¬€È°İ¥‘Ñ¡Ím¥¹‘•át°Ñ½½±‰…È¹!•¥¡Ğ€´€Ğ¤ì(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”Q½½±‰…ÉÑ¥½¸!¥ÑQ•ÍÑQ½½±‰…È¡A½¥¹Ğ±½…Ñ¥½¸¤(€€€€€€€ì(€€€€€€€€€€€¥˜€ …}¡…ÍM•±•Ñ¥½¸ñğ€…•ÑQ½½±‰…É	½Õ¹‘Ì¡}Í•±•Ñ¥½¸¤¹½¹Ñ…¥¹Ì¡±½…Ñ¥½¸¤¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€É•ÑÕÉ¸Q½½±‰…ÉÑ¥½¸¹9½¹”ì(€€€€€€€€€€€ô((€€€€€€€€€€€¥˜€¡•ÑQ½½±‰…É	ÕÑÑ½¹	½Õ¹‘Ì À¤¹½¹Ñ…¥¹Ì¡±½…Ñ¥½¸¤¤É•ÑÕÉ¸Q½½±‰…ÉÑ¥½¸¹½Áäì(€€€€€€€€€€€¥˜€¡•ÑQ½½±‰…É	ÕÑÑ½¹	½Õ¹‘Ì Ä¤¹½¹Ñ…¥¹Ì¡±½…Ñ¥½¸¤¤É•ÑÕÉ¸Q½½±‰…ÉÑ¥½¸¹M…Ù”ì(€€€€€€€€€€€¥˜€¡•ÑQ½½±‰…É	ÕÑÑ½¹	½Õ¹‘Ì È¤¹½¹Ñ…¥¹Ì¡±½…Ñ¥½¸¤¤É•ÑÕÉ¸Q½½±‰…ÉÑ¥½¸¹…¹•°ì(€€€€€€€€€€€É•ÑÕÉ¸Q½½±‰…ÉÑ¥½¸¹9½¹”ì(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”Q½½±‰…ÉÑ¥½¸•ÑM•±•Ñ¥½¹±¥­Ñ¥½¸¡5½ÕÍ•	ÕÑÑ½¹Ì‰ÕÑÑ½¸°A½¥¹Ğ±½…Ñ¥½¸¤(€€€€€€€ì(€€€€€€€€€€€¥˜€ …}¡…ÍM•±•Ñ¥½¸¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€É•ÑÕÉ¸Q½½±‰…ÉÑ¥½¸¹9½¹”ì(€€€€€€€€€€€ô((€€€€€€€€€€€¥˜€¡‰ÕÑÑ½¸€ôô5½ÕÍ•	ÕÑÑ½¹Ì¹I¥¡Ğ¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€É•ÑÕÉ¸Q½½±‰…ÉÑ¥½¸¹M…Ù”ì(€€€€€€€€€€€ô((€€€€€€€€€€€¥˜€¡‰ÕÑÑ½¸€„ô5½ÕÍ•	ÕÑÑ½¹Ì¹1•™Ğ¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€É•ÑÕÉ¸Q½½±‰…ÉÑ¥½¸¹9½¹”ì(€€€€€€€€€€€ô((€€€€€€€€€€€Q½½±‰…ÉÑ¥½¸Ñ½½±‰…ÉÑ¥½¸€ô!¥ÑQ•ÍÑQ½½±‰…È¡±½…Ñ¥½¸¤ì(€€€€€€€€€€€É•ÑÕÉ¸Ñ½½±‰…ÉÑ¥½¸€ôôQ½½±‰…ÉÑ¥½¸¹9½¹”(€€€€€€€€€€€€€€€€üQ½½±‰…ÉÑ¥½¸¹½Áä(€€€€€€€€€€€€€€€€èÑ½½±‰…ÉÑ¥½¸ì(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”Ù½¥A•É™½ÉµQ½½±‰…ÉÑ¥½¸¡Q½½±‰…ÉÑ¥½¸…Ñ¥½¸¤(€€€€€€€ì(€€€€€€€€€€€¥˜€¡…Ñ¥½¸€ôôQ½½±‰…ÉÑ¥½¸¹½Áä¤½ÁåM•±•Ñ¥½¸ ¤ì(€€€€€€€€€€€•±Í”¥˜€¡…Ñ¥½¸€ôôQ½½±‰…ÉÑ¥½¸¹M…Ù”¤M…Ù•M•±•Ñ¥½¸ ¤ì(€€€€€€€€€€€•±Í”¥˜€¡…Ñ¥½¸€ôôQ½½±‰…ÉÑ¥½¸¹…¹•°¤¥¹¥Í ¡™…±Í”°€‹–ŞË–>[šÚ ˆ¤ì(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”Ù½¥½ÁåM•±•Ñ¥½¸ ¤(€€€€€€€ì(€€€€€€€€€€€¥˜€ …}¡…ÍM•±•Ñ¥½¸ñğ}ÍÉ••¸€ôô¹Õ±°¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€É•ÑÕÉ¸ì(€€€€€€€€€€€ô((€€€€€€€€€€€ÑÉä(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€ÕÍ¥¹œ€¡	¥Ñµ…ÀÉ½ÁÁ•€ôMÉ••¹…ÁÑÕÉ”¹É½À¡}ÍÉ••¸°}Í•±•Ñ¥½¸¤¤(€€€€€€€€€€€€€€€ì(€€€€€€€€€€€€€€€€€€€±¥Á‰½…É¹M•Ñ…Ñ…=‰©•Ğ¡É½ÁÁ•°ÑÉÕ”°€Ô°€ĞÀ¤ì(€€€€€€€€€€€€€€€ô(€€€€€€€€€€€€€€€¥¹¥Í ¡ÑÉÕ”°€‹–ŞË–’7–"Û–"Ã–&«¢ÒÓšvüˆ¤ì(€€€€€€€€€€€ô(€€€€€€€€€€€…Ñ €¡áÑ•É¹…±á•ÁÑ¥½¸¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€MåÍÑ•´¹5•‘¥„¹MåÍÑ•µM½Õ¹‘Ì¹á±…µ…Ñ¥½¸¹A±…ä ¤ì(€€€€€€€€€€€ô(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”Ù½¥M…Ù•M•±•Ñ¥½¸ ¤(€€€€€€€ì(€€€€€€€€€€€¥˜€ …}¡…ÍM•±•Ñ¥½¸ñğ}ÍÉ••¸€ôô¹Õ±°¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€É•ÑÕÉ¸ì(€€€€€€€€€€€ô((€€€€€€€€€€€ÑÉä(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€ÕÍ¥¹œ€¡M…Ù•¥±•¥…±½œ‘¥…±½œ€ô¹•ÜM…Ù•¥±•¥…±½œ ¤¤(€€€€€€€€€€€€€€€ì(€€€€€€€€€€€€€€€€€€€‘¥…±½œ¹Q¥Ñ±”€ô€‹’şw–¶cš"«–nøˆì(€€€€€€€€€€€€€€€€€€€‘¥…±½œ¹¥±Ñ•È€ô€‰A9ƒ–nû–<€ ¨¹Á¹œ¥ğ¨¹Á¹ñ)Aƒ–nû–<€ ¨¹©Áœ¥ğ¨¹©Áœˆì(€€€€€€€€€€€€€€€€€€€‘¥…±½œ¹•™…Õ±ÑáĞ€ô€‰Á¹œˆì(€€€€€€€€€€€€€€€€€€€‘¥…±½œ¹‘‘áÑ•¹Í¥½¸€ôÑÉÕ”ì(€€€€€€€€€€€€€€€€€€€‘¥…±½œ¹¥±•9…µ”€ô€‹š"«–nù|ˆ€¬…Ñ•Q¥µ”¹9½Ü¹Q½MÑÉ¥¹œ ‰åååå55‘‘}!!µµÍÌˆ¤€¬€ˆ¹Á¹œˆì((€€€€€€€€€€€€€€€€€€€¥˜€¡‘¥…±½œ¹M¡½İ¥…±½œ¡Ñ¡¥Ì¤€„ô¥…±½I•ÍÕ±Ğ¹=,¤(€€€€€€€€€€€€€€€€€€€ì(€€€€€€€€€€€€€€€€€€€€€€€É•ÑÕÉ¸ì(€€€€€€€€€€€€€€€€€€€ô((€€€€€€€€€€€€€€€€€€€ÕÍ¥¹œ€¡	¥Ñµ…ÀÉ½ÁÁ•€ôMÉ••¹…ÁÑÕÉ”¹É½À¡}ÍÉ••¸°}Í•±•Ñ¥½¸¤¤(€€€€€€€€€€€€€€€€€€€ì(€€€€€€€€€€€€€€€€€€€€€€€M…Ù•%µ…”¡É½ÁÁ•°‘¥…±½œ¹¥±•9…µ”¤ì(€€€€€€€€€€€€€€€€€€€ô(€€€€€€€€€€€€€€€ô((€€€€€€€€€€€€€€€¥¹¥Í ¡ÑÉÕ”°€‹š"«–nû–ŞË’şw–¶`ˆ¤ì(€€€€€€€€€€€ô(€€€€€€€€€€€…Ñ €¡á•ÁÑ¥½¸•á•ÁÑ¥½¸¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€5•ÍÍ…•	½à¹M¡½Ü¡Ñ¡¥Ì°•á•ÁÑ¥½¸¹5•ÍÍ…”°€‹’şw–¶c–’Ç¢Ò”ˆ°5•ÍÍ…•	½á	ÕÑÑ½¹Ì¹=,°5•ÍÍ…•	½á%½¸¹ÉÉ½È¤ì(€€€€€€€€€€€ô(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥ŒÙ½¥M…Ù•%µ…”¡	¥Ñµ…À¥µ…”°ÍÑÉ¥¹œÁ…Ñ ¤(€€€€€€€ì(€€€€€€€€€€€‰½½°¥Í)Á•œ€ôÁ…Ñ ¹¹‘Í]¥Ñ  ˆ¹©Áœˆ°MÑÉ¥¹½µÁ…É¥Í½¸¹=É‘¥¹…±%¹½É•…Í”¤ñğ(€€€€€€€€€€€€€€€Á…Ñ ¹¹‘Í]¥Ñ  ˆ¹©Á•œˆ°MÑÉ¥¹½µÁ…É¥Í½¸¹=É‘¥¹…±%¹½É•…Í”¤ì(€€€€€€€€€€€¥˜€ …¥Í)Á•œ¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€¥µ…”¹M…Ù”¡Á…Ñ °%µ…•½Éµ…Ğ¹A¹œ¤ì(€€€€€€€€€€€€€€€É•ÑÕÉ¸ì(€€€€€€€€€€€ô((€€€€€€€€€€€%µ…•½‘•%¹™¼©Á•¹½‘•È€ô¹Õ±°ì(€€€€€€€€€€€%µ…•½‘•%¹™½mt•¹½‘•ÉÌ€ô%µ…•½‘•%¹™¼¹•Ñ%µ…•¹½‘•ÉÌ ¤ì(€€€€€€€€€€€™½È€¡¥¹Ğ¤€ô€Àì¤€ğ•¹½‘•ÉÌ¹1•¹Ñ ì¤¬¬¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€¥˜€¡•¹½‘•ÉÍm¥t¹½Éµ…Ñ%€ôô%µ…•½Éµ…Ğ¹)Á•œ¹Õ¥¤(€€€€€€€€€€€€€€€ì(€€€€€€€€€€€€€€€€€€€©Á•¹½‘•È€ô•¹½‘•ÉÍm¥tì(€€€€€€€€€€€€€€€€€€€‰É•…¬ì(€€€€€€€€€€€€€€€ô(€€€€€€€€€€€ô((€€€€€€€€€€€¥˜€¡©Á•¹½‘•È€ôô¹Õ±°¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€¥µ…”¹M…Ù”¡Á…Ñ °%µ…•½Éµ…Ğ¹)Á•œ¤ì(€€€€€€€€€€€€€€€É•ÑÕÉ¸ì(€€€€€€€€€€€ô((€€€€€€€€€€€ÕÍ¥¹œ€¡¹½‘•ÉA…É…µ•Ñ•ÉÌÁ…É…µ•Ñ•ÉÌ€ô¹•Ü¹½‘•ÉA…É…µ•Ñ•ÉÌ Ä¤¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€Á…É…µ•Ñ•ÉÌ¹A…É…µlÁt€ô¹•Ü¹½‘•ÉA…É…µ•Ñ•È (€€€€€€€€€€€€€€€€€€€MåÍÑ•´¹É…İ¥¹œ¹%µ…¥¹œ¹¹½‘•È¹EÕ…±¥Ñä°(€€€€€€€€€€€€€€€€€€€)Á•EÕ…±¥Ñä¤ì(€€€€€€€€€€€€€€€¥µ…”¹M…Ù”¡Á…Ñ °©Á•¹½‘•È°Á…É…µ•Ñ•ÉÌ¤ì(€€€€€€€€€€€ô(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”I•Ñ…¹±”¥¹‘]¥¹‘½İĞ¡A½¥¹ĞÁ½¥¹Ğ¤(€€€€€€€ì(€€€€€€€€€€€™½È€¡¥¹Ğ¤€ô€Àì¤€ğ}İ¥¹‘½İI•Ñ…¹±•Ì¹½Õ¹Ğì¤¬¬¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€¥˜€¡}İ¥¹‘½İI•Ñ…¹±•Ím¥t¹½¹Ñ…¥¹Ì¡Á½¥¹Ğ¤¤(€€€€€€€€€€€€€€€ì(€€€€€€€€€€€€€€€€€€€É•ÑÕÉ¸}İ¥¹‘½İI•Ñ…¹±•Ím¥tì(€€€€€€€€€€€€€€€ô(€€€€€€€€€€€ô((€€€€€€€€€€€€¼¼-••Àİ¥¹‘½ÜÍ¹…ÁÁ¥¹œÉ•ÍÁ½¹Í¥Ù”…É½Õ¹Ñ¡¥¸‰½É‘•ÉÌ…¹Í¡…‘½İÌ¸á…Ğ¡¥ÑÌ…É”(€€€€€€€€€€€€¼¼…±İ…åÌÁÉ•™•ÉÉ•°Ñ¡•¸Ñ¡”Ñ½Áµ½ÍĞİ¥¹‘½Üİ¥Ñ¡¥¸„Íµ…±°µ…¹•Ñ¥Œ•‘”É…‘¥ÕÌ¸(€€€€€€€€€€€™½È€¡¥¹Ğ¤€ô€Àì¤€ğ}İ¥¹‘½İI•Ñ…¹±•Ì¹½Õ¹Ğì¤¬¬¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€I•Ñ…¹±”µ…¹•Ñ¥	½Õ¹‘Ì€ô}İ¥¹‘½İI•Ñ…¹±•Ím¥tì(€€€€€€€€€€€€€€€µ…¹•Ñ¥	½Õ¹‘Ì¹%¹™±…Ñ”¡]¥¹‘½İ5…¹•ÑI…‘¥ÕÌ°]¥¹‘½İ5…¹•ÑI…‘¥ÕÌ¤ì(€€€€€€€€€€€€€€€¥˜€¡µ…¹•Ñ¥	½Õ¹‘Ì¹½¹Ñ…¥¹Ì¡Á½¥¹Ğ¤¤(€€€€€€€€€€€€€€€ì(€€€€€€€€€€€€€€€€€€€É•ÑÕÉ¸}İ¥¹‘½İI•Ñ…¹±•Ím¥tì(€€€€€€€€€€€€€€€ô(€€€€€€€€€€€ô((€€€€€€€€€€€MÉ••¸µ½¹¥Ñ½È€ôMÉ••¸¹É½µA½¥¹Ğ¡A½¥¹ÑQ½MÉ••¸¡Á½¥¹Ğ¤¤ì(€€€€€€€€€€€I•Ñ…¹±”‰½Õ¹‘Ì€ôµ½¹¥Ñ½È¹	½Õ¹‘Ìì(€€€€€€€€€€€É•ÑÕÉ¸¹•ÜI•Ñ…¹±” (€€€€€€€€€€€€€€€‰½Õ¹‘Ì¹1•™Ğ€´}Ù¥ÉÑÕ…±MÉ••¸¹1•™Ğ°(€€€€€€€€€€€€€€€‰½Õ¹‘Ì¹Q½À€´}Ù¥ÉÑÕ…±MÉ••¸¹Q½À°(€€€€€€€€€€€€€€€‰½Õ¹‘Ì¹]¥‘Ñ °(€€€€€€€€€€€€€€€‰½Õ¹‘Ì¹!•¥¡Ğ¤ì(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”Ù½¥¥¹¥Í ¡‰½½°ÍÕ••‘•°ÍÑÉ¥¹œµ•ÍÍ…”¤(€€€€€€€ì(€€€€€€€€€€€¥˜€ …}…ÁÑÕÉ•Ñ¥Ù”¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€É•ÑÕÉ¸ì(€€€€€€€€€€€ô((€€€€€€€€€€€}…ÁÑÕÉ•Ñ¥Ù”€ô™…±Í”ì(€€€€€€€€€€€}İ¥¹‘½İQÉ…­¥¹Q¥µ•È¹MÑ½À ¤ì(€€€€€€€€€€€…ÁÑÕÉ”€ô™…±Í”ì(€€€€€€€€€€€!¥‘” ¤ì(€€€€€€€€€€€¥ÍÁ½Í•…ÁÑÕÉ•‘MÉ••¸ ¤ì(€€€€€€€€€€€I•Í•ÑM•±•Ñ¥½¸ ¤ì((€€€€€€€€€€€Ù•¹Ñ!…¹‘±•Èñ…ÁÑÕÉ•MÑ…ÑÕÍÙ•¹ÑÉÌø¡…¹‘±•È€ô…ÁÑÕÉ•¥¹¥Í¡•ì(€€€€€€€€€€€¥˜€¡¡…¹‘±•È€„ô¹Õ±°¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€¡…¹‘±•È¡Ñ¡¥Ì°¹•Ü…ÁÑÕÉ•MÑ…ÑÕÍÙ•¹ÑÉÌ¡ÍÕ••‘•°µ•ÍÍ…”¤¤ì(€€€€€€€€€€€ô(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”Ù½¥I•Í•ÑM•±•Ñ¥½¸ ¤(€€€€€€€ì(€€€€€€€€€€€}¡½Ù•ÉI•Ñ…¹±”€ôI•Ñ…¹±”¹µÁÑäì(€€€€€€€€€€€}Í•±•Ñ¥½¸€ôI•Ñ…¹±”¹µÁÑäì(€€€€€€€€€€€}µ½ÕÍ•½İ¸€ô™…±Í”ì(€€€€€€€€€€€}‘É…¥¹œ€ô™…±Í”ì(€€€€€€€€€€€}¡…ÍM•±•Ñ¥½¸€ô™…±Í”ì(€€€€€€€€€€€}¡½Ù•ÉÑ¥½¸€ôQ½½±‰…ÉÑ¥½¸¹9½¹”ì(€€€€€€€€€€€}¡…ÍQÉ…­•‘ÕÉÍ½È€ô™…±Í”ì(€€€€€€€€€€€}¡…Í5…¹¥™¥•ÉA½¥¹Ğ€ô™…±Í”ì(€€€€€€€€€€€ÕÉÍ½È€ôÕÉÍ½ÉÌ¹É½ÍÌì(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”Ù½¥¥ÍÁ½Í•…ÁÑÕÉ•‘MÉ••¸ ¤(€€€€€€€ì(€€€€€€€€€€€¥˜€¡}ÍÉ••¸€„ô¹Õ±°¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€}ÍÉ••¸¹¥ÍÁ½Í” ¤ì(€€€€€€€€€€€€€€€}ÍÉ••¸€ô¹Õ±°ì(€€€€€€€€€€€ô(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”A½¥¹Ğ±…µÁQ½±¥•¹Ğ¡A½¥¹ĞÁ½¥¹Ğ¤(€€€€€€€ì(€€€€€€€€€€€É•ÑÕÉ¸¹•ÜA½¥¹Ğ (€€€€€€€€€€€€€€€5…Ñ ¹5…à À°5…Ñ ¹5¥¸¡±¥•¹ÑM¥é”¹]¥‘Ñ °Á½¥¹Ğ¹`¤¤°(€€€€€€€€€€€€€€€5…Ñ ¹5…à À°5…Ñ ¹5¥¸¡±¥•¹ÑM¥é”¹!•¥¡Ğ°Á½¥¹Ğ¹d¤¤¤ì(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥ŒI•Ñ…¹±”I•Ñ…¹±•É½µA½¥¹ÑÌ¡A½¥¹Ğ™¥ÉÍĞ°A½¥¹ĞÍ•½¹¤(€€€€€€€ì(€€€€€€€€€€€É•ÑÕÉ¸I•Ñ…¹±”¹É½µ1QI (€€€€€€€€€€€€€€€5…Ñ ¹5¥¸¡™¥ÉÍĞ¹`°Í•½¹¹`¤°(€€€€€€€€€€€€€€€5…Ñ ¹5¥¸¡™¥ÉÍĞ¹d°Í•½¹¹d¤°(€€€€€€€€€€€€€€€5…Ñ ¹5…à¡™¥ÉÍĞ¹`°Í•½¹¹`¤°(€€€€€€€€€€€€€€€5…Ñ ¹5…à¡™¥ÉÍĞ¹d°Í•½¹¹d¤¤ì(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”Ù½¥%¹Ù…±¥‘…Ñ•M•±•Ñ¥½¹QÉ…¹Í¥Ñ¥½¸¡I•Ñ…¹±”½±‘I•Ñ…¹±”°I•Ñ…¹±”¹•İI•Ñ…¹±”°‰½½°¥¹±Õ‘•Q½½±‰…È¤(€€€€€€€ì(€€€€€€€€€€€¥˜€¡½±‘I•Ñ…¹±”¹%ÍµÁÑä€˜˜¹•İI•Ñ…¹±”¹%ÍµÁÑä¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€É•ÑÕÉ¸ì(€€€€€€€€€€€ô((€€€€€€€€€€€I•¥½¸¡…¹•€ô½±‘I•Ñ…¹±”¹%ÍµÁÑä(€€€€€€€€€€€€€€€€ü¹•ÜI•¥½¸¡¹•İI•Ñ…¹±”¤(€€€€€€€€€€€€€€€€è¹•ÜI•¥½¸¡½±‘I•Ñ…¹±”¤ì(€€€€€€€€€€€ÑÉä(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€¥˜€ …¹•İI•Ñ…¹±”¹%ÍµÁÑä€˜˜€…½±‘I•Ñ…¹±”¹%ÍµÁÑä¤(€€€€€€€€€€€€€€€ì(€€€€€€€€€€€€€€€€€€€¡…¹•¹a½È¡¹•İI•Ñ…¹±”¤ì(€€€€€€€€€€€€€€€ô((€€€€€€€€€€€€€€€‘‘M•±•Ñ¥½¹¡É½µ”¡¡…¹•°½±‘I•Ñ…¹±”°¥¹±Õ‘•Q½½±‰…È¤ì(€€€€€€€€€€€€€€€‘‘M•±•Ñ¥½¹¡É½µ”¡¡…¹•°¹•İI•Ñ…¹±”°¥¹±Õ‘•Q½½±‰…È¤ì(€€€€€€€€€€€€€€€%¹Ù…±¥‘…Ñ”¡¡…¹•¤ì(€€€€€€€€€€€ô(€€€€€€€€€€€™¥¹…±±ä(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€¡…¹•¹¥ÍÁ½Í” ¤ì(€€€€€€€€€€€ô(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”Ù½¥%¹Ù…±¥‘…Ñ•M•±•Ñ¥½¹¡É½µ”¡I•Ñ…¹±”É•Ñ…¹±”°‰½½°¥¹±Õ‘•Q½½±‰…È¤(€€€€€€€ì(€€€€€€€€€€€¥˜€¡É•Ñ…¹±”¹%ÍµÁÑä¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€É•ÑÕÉ¸ì(€€€€€€€€€€€ô((€€€€€€€€€€€I•¥½¸¡É½µ”€ô¹•ÜI•¥½¸¡I•Ñ…¹±”¹µÁÑä¤ì(€€€€€€€€€€€ÑÉä(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€‘‘M•±•Ñ¥½¹¡É½µ”¡¡É½µ”°É•Ñ…¹±”°¥¹±Õ‘•Q½½±‰…È¤ì(€€€€€€€€€€€€€€€%¹Ù…±¥‘…Ñ”¡¡É½µ”¤ì(€€€€€€€€€€€ô(€€€€€€€€€€€™¥¹…±±ä(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€¡É½µ”¹¥ÍÁ½Í” ¤ì(€€€€€€€€€€€ô(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”Ù½¥‘‘M•±•Ñ¥½¹¡É½µ”¡I•¥½¸É•¥½¸°I•Ñ…¹±”É•Ñ…¹±”°‰½½°¥¹±Õ‘•Q½½±‰…È¤(€€€€€€€ì(€€€€€€€€€€€¥˜€¡É•Ñ…¹±”¹%ÍµÁÑä¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€É•ÑÕÉ¸ì(€€€€€€€€€€€ô((€€€€€€€€€€€½¹ÍĞ¥¹Ğ•‘”€ô€Ôì(€€€€€€€€€€€É•¥½¸¹U¹¥½¸¡¹•ÜI•Ñ…¹±”¡É•Ñ…¹±”¹1•™Ğ€´•‘”°É•Ñ…¹±”¹Q½À€´•‘”°É•Ñ…¹±”¹]¥‘Ñ €¬•‘”€¨€È°•‘”€¨€È¤¤ì(€€€€€€€€€€€É•¥½¸¹U¹¥½¸¡¹•ÜI•Ñ…¹±”¡É•Ñ…¹±”¹1•™Ğ€´•‘”°É•Ñ…¹±”¹	½ÑÑ½´€´•‘”°É•Ñ…¹±”¹]¥‘Ñ €¬•‘”€¨€È°•‘”€¨€È¤¤ì(€€€€€€€€€€€É•¥½¸¹U¹¥½¸¡¹•ÜI•Ñ…¹±”¡É•Ñ…¹±”¹1•™Ğ€´•‘”°É•Ñ…¹±”¹Q½À°•‘”€¨€È°É•Ñ…¹±”¹!•¥¡Ğ¤¤ì(€€€€€€€€€€€É•¥½¸¹U¹¥½¸¡¹•ÜI•Ñ…¹±”¡É•Ñ…¹±”¹I¥¡Ğ€´•‘”°É•Ñ…¹±”¹Q½À°•‘”€¨€È°É•Ñ…¹±”¹!•¥¡Ğ¤¤ì(€€€€€€€€€€€É•¥½¸¹U¹¥½¸¡•Ñ¥µ•¹Í¥½¹1…‰•±	½Õ¹‘Ì¡É•Ñ…¹±”¤¤ì(€€€€€€€€€€€¥˜€¡¥¹±Õ‘•Q½½±‰…È¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€É•¥½¸¹U¹¥½¸¡•ÑQ½½±‰…É	½Õ¹‘Ì¡É•Ñ…¹±”¤¤ì(€€€€€€€€€€€ô(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”I•Ñ…¹±”•Ñ¥µ•¹Í¥½¹1…‰•±	½Õ¹‘Ì¡I•Ñ…¹±”É•Ñ…¹±”¤(€€€€€€€ì(€€€€€€€€€€€ÍÑÉ¥¹œ‘¥µ•¹Í¥½¹Ì€ôÉ•Ñ…¹±”¹]¥‘Ñ €¬€ˆƒ\€ˆ€¬É•Ñ…¹±”¹!•¥¡Ğì(€€€€€€€€€€€M¥é”Í¥é”€ôQ•áÑI•¹‘•É•È¹5•…ÍÕÉ•Q•áĞ (€€€€€€€€€€€€€€€‘¥µ•¹Í¥½¹Ì°(€€€€€€€€€€€€€€€}ÕÑ¥±¥Ñå½¹Ğ°(€€€€€€€€€€€€€€€M¥é”¹µÁÑä°(€€€€€€€€€€€€€€€Q•áÑ½Éµ…Ñ±…Ì¹9½A…‘‘¥¹œğQ•áÑ½Éµ…Ñ±…Ì¹M¥¹±•1¥¹”¤ì((€€€€€€€€€€€I•Ñ…¹±”±…‰•°€ô¹•ÜI•Ñ…¹±” (€€€€€€€€€€€€€€€É•Ñ…¹±”¹1•™Ğ°(€€€€€€€€€€€€€€€É•Ñ…¹±”¹Q½À€´Í¥é”¹!•¥¡Ğ€´€ÄÀ°(€€€€€€€€€€€€€€€Í¥é”¹]¥‘Ñ €¬€ÄĞ°(€€€€€€€€€€€€€€€Í¥é”¹!•¥¡Ğ€¬€Ø¤ì(€€€€€€€€€€€¥˜€¡±…‰•°¹Q½À€ğ€Ğ¤(€€€€€€€€€€€ì(€€€€€€€€€€€€€€€±…‰•°¹d€ôÉ•Ñ…¹±”¹Q½À€¬€Øì(€€€€€€€€€€€ô(€€€€€€€€€€€É•ÑÕÉ¸±…‰•°ì(€€€€€€€ô((€€€€€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥ŒÉ…Á¡¥ÍA…Ñ I½Õ¹‘•‘I•Ñ…¹±”¡I•Ñ…¹±”É•Ñ…¹±”°¥¹ĞÉ…‘¥ÕÌ¤(€€€€€€€ì(€€€€€€€€€€€¥¹Ğ‘¥…µ•Ñ•È€ôÉ…‘¥ÕÌ€¨€Èì(€€€€€€€€€€€É…Á¡¥ÍA…Ñ Á…Ñ €ô¹•ÜÉ…Á¡¥ÍA…Ñ  ¤ì(€€€€€€€€€€€Á…Ñ ¹‘‘ÉŒ¡É•Ñ…¹±”¹1•™Ğ°É•Ñ…¹±”¹Q½À°‘¥…µ•Ñ•È°‘¥…µ•Ñ•È°€ÄàÀ°€äÀ¤ì(€€€€€€€€€€€Á…Ñ ¹‘‘ÉŒ¡É•Ñ…¹±”¹I¥¡Ğ€´‘¥…µ•Ñ•È°É•Ñ…¹±”¹Q½À°‘¥…µ•Ñ•È°‘¥…µ•Ñ•È°€ÈÜÀ°€äÀ¤ì(€€€€€€€€€€€Á…Ñ ¹‘‘ÉŒ¡É•Ñ…¹±”¹I¥¡Ğ€´‘¥…µ•Ñ•È°É•Ñ…¹±”¹	½ÑÑ½´€´‘¥…µ•Ñ•È°‘¥…µ•Ñ•È°‘¥…µ•Ñ•È°€À°€äÀ¤ì(€€€€€€€€€€€Á…Ñ ¹‘‘ÉŒ¡É•Ñ…¹±”¹1•™Ğ°É•Ñ…¹±”¹	½ÑÑ½´€´‘¥…µ•Ñ•È°‘¥…µ•Ñ•È°‘¥…µ•Ñ•È°€äÀ°€äÀ¤ì(€€€€€€€€€€€Á…Ñ ¹±½Í•¥ÕÉ” ¤ì(€€€€€€€€€€€É•ÑÕÉ¸Á…Ñ ì(€€€€€€€ô(€€€ô((€€€¥¹Ñ•É¹…°Í•…±•±…ÍÌ…ÁÑÕÉ•MÑ…ÑÕÍÙ•¹ÑÉÌ€èÙ•¹ÑÉÌ(€€€ì(€€€€€€€¥¹Ñ•É¹…°…ÁÑÕÉ•MÑ…ÑÕÍÙ•¹ÑÉÌ¡‰½½°ÍÕ••‘•°ÍÑÉ¥¹œµ•ÍÍ…”¤(€€€€€€€ì(€€€€€€€€€€€MÕ••‘•€ôÍÕ••‘•ì(€€€€€€€€€€€5•ÍÍ…”€ôµ•ÍÍ…”ì(€€€€€€€ô((€€€€€€€¥¹Ñ•É¹…°‰½½°MÕ••‘•ì•ĞìÁÉ¥Ù…Ñ”Í•Ğìô(€€€€€€€¥¹Ñ•É¹…°ÍÑÉ¥¹œ5•ÍÍ…”ì•ĞìÁÉ¥Ù…Ñ”Í•Ğìô(€€€ô)ô(