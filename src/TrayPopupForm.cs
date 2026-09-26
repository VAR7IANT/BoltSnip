using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;

namespace BoltSnip
{
    internal enum TrayPopupAction
    {
        None,
        Capture,
        ReplayToggle,
        ReplaySave,
        Hotkeys,
        SaveLocation,
        Startup,
        License,
        Exit
    }

    internal sealed class TrayPopupForm : Form
    {
        internal const int LogicalWidth = 336;
        internal const int LogicalHeight = 430;
        internal const int LogicalHeightWithLicense = 464;
        internal const int ReplayTitleLogicalWidth = 158;

        internal static readonly Color BackgroundColor = Color.FromArgb(250, 251, 252);
        internal static readonly Color CardColor = Color.FromArgb(243, 247, 248);
        internal static readonly Color TextColor = Color.FromArgb(34, 45, 51);
        internal static readonly Color SecondaryTextColor = Color.FromArgb(111, 126, 133);
        internal static readonly Color MutedTextColor = Color.FromArgb(151, 163, 168);
        internal static readonly Color BorderColor = Color.FromArgb(226, 233, 235);
        internal static readonly Color AccentColor = Color.FromArgb(75, 145, 158);
        internal static readonly Color AccentSoftColor = Color.FromArgb(232, 243, 245);
        internal static readonly Color HoverColor = Color.FromArgb(241, 245, 246);
        internal static readonly Color PressedColor = Color.FromArgb(233, 239, 241);
        internal static readonly Color ErrorColor = Color.FromArgb(160, 97, 97);

        private const int ShadowClassStyle = 0x00020000;
        private const int ToolWindowExtendedStyle = 0x00000080;

        private readonly Action _beginCapture;
        private readonly Action _toggleReplay;
        private readonly Action _saveReplay;
        private readonly Action _openHotkeys;
        private readonly Action _openSaveLocation;
        private readonly Action _toggleStartup;
        private readonly Action _openLicense;
        private readonly Action _exitApplication;
        private readonly Font _brandFont;
        private readonly Font _bodyFont;
        private readonly Font _mediumFont;
        private readonly Font _smallFont;
        private readonly Font _shortcutFont;

        private string _version;
        private string _captureShortcut;
        private string _replayShortcut;
        private ReplayState _replayState;
        private ReplayAudioState _replayAudioState;
        private bool _isSaving;
        private bool _startupEnabled;
        private bool _licenseEnabled;
        private bool _savedFeedback;
        private DateTime _savedFeedbackUntil;
        private TrayPopupAction _hoverAction;
        private TrayPopupAction _pressedAction;
        private int _dpi = 96;

        internal TrayPopupForm(
            Action beginCapture,
            Action toggleReplay,
            Action saveReplay,
            Action openHotkeys,
            Action openSaveLocation,
            Action toggleStartup,
            Action openLicense,
            Action exitApplication)
        {
            _beginCapture = beginCapture;
            _toggleReplay = toggleReplay;
            _saveReplay = saveReplay;
            _openHotkeys = openHotkeys;
            _openSaveLocation = openSaveLocation;
            _toggleStartup = toggleStartup;
            _openLicense = openLicense;
            _exitApplication = exitApplication;
            _version = ReleaseIdentity.Version;
            _captureShortcut = string.Empty;
            _replayShortcut = string.Empty;
            _replayState = ReplayState.Disabled;
            _replayAudioState = ReplayAudioState.Disabled;

            _brandFont = new Font("Microsoft YaHei UI", 12f, FontStyle.Bold, GraphicsUnit.Point);
            _bodyFont = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Regular, GraphicsUnit.Point);
            _mediumFont = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Bold, GraphicsUnit.Point);
            _smallFont = new Font("Microsoft YaHei UI", 8.25f, FontStyle.Regular, GraphicsUnit.Point);
            _shortcutFont = new Font("Microsoft YaHei UI", 8f, FontStyle.Regular, GraphicsUnit.Point);

            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            ShowInTaskbar = false;
            TopMost = true;
            KeyPreview = true;
            AutoScaleMode = AutoScaleMode.None;
            BackColor = BackgroundColor;
            DoubleBuffered = true;
            SetStyle(
                ControlStyles.UserPaint |
                ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.ResizeRedraw,
                true);
            ClientSize = GetLogicalSize(false);
            ApplyDpi(DeviceDpi);
        }

        internal bool IsReplaySaving
        {
            get { return _isSaving; }
        }

        internal void UpdatePresentation(
            string version,
            string captureShortcut,
            string replayShortcut,
            bool startupEnabled,
            bool licenseEnabled)
        {
            string formattedCaptureShortcut = FormatShortcut(captureShortcut);
            string formattedReplayShortcut = FormatShortcut(replayShortcut);
            bool changed = _version != version ||
                _captureShortcut != formattedCaptureShortcut ||
                _replayShortcut != formattedReplayShortcut ||
                _startupEnabled != startupEnabled ||
                _licenseEnabled != licenseEnabled;
            if (!changed)
            {
                return;
            }

            _version = version ?? string.Empty;
            _captureShortcut = formattedCaptureShortcut;
            _replayShortcut = formattedReplayShortcut;
            _startupEnabled = startupEnabled;
            _licenseEnabled = licenseEnabled;
            ApplyDpi(_dpi);
            Invalidate();
        }

        internal void UpdateReplayState(ReplayState state, bool isSaving)
        {
            UpdateReplayState(
                state,
                isSaving,
                state == ReplayState.Recording ? ReplayAudioState.Active : ReplayAudioState.Disabled);
        }

        internal void UpdateReplayState(ReplayState state, bool isSaving, ReplayAudioState audioState)
        {
            ExpireSavedFeedback();
            if (_replayState == state && _isSaving == isSaving && _replayAudioState == audioState)
            {
                return;
            }

            _replayState = state;
            _isSaving = isSaving;
            _replayAudioState = audioState;
            Invalidate(ScaleRectangle(GetLogicalBounds(TrayPopupAction.ReplayToggle, _licenseEnabled)));
        }

        internal void ShowSavedFeedback()
        {
            _savedFeedback = true;
            _savedFeedbackUntil = DateTime.UtcNow.AddSeconds(2.2);
            Invalidate(ScaleRectangle(GetLogicalBounds(TrayPopupAction.ReplaySave, _licenseEnabled)));
        }

        internal void ShowNear(Point screenPoint)
        {
            if (IsDisposed)
            {
                return;
            }
            if (Visible)
            {
                Hide();
                return;
            }

            int monitorDpi = DeviceDpi;
            ApplyDpi(monitorDpi);
            Rectangle workingArea = Screen.FromPoint(screenPoint).WorkingArea;
            Bounds = FitToWorkingArea(screenPoint, workingArea, Size);
            _hoverAction = TrayPopupAction.None;
            _pressedAction = TrayPopupAction.None;
            Show();
            Activate();
        }

        internal static Size GetLogicalSize(bool licenseEnabled)
        {
            return new Size(LogicalWidth, licenseEnabled ? LogicalHeightWithLicense : LogicalHeight);
        }

        internal static int ScaleLogicalValue(int value, int dpi)
        {
            int safeDpi = dpi > 0 ? dpi : 96;
            return (int)Math.Round(value * safeDpi / 96.0, MidpointRounding.AwayFromZero);
        }

        internal static Rectangle GetLogicalBounds(TrayPopupAction action, bool licenseEnabled)
        {
            switch (action)
            {
                case TrayPopupAction.Capture:
                    return new Rectangle(14, 58, 308, 48);
                case TrayPopupAction.ReplayToggle:
                    return new Rectangle(14, 118, 308, 118);
                case TrayPopupAction.ReplaySave:
                    return new Rectangle(26, 196, 284, 30);
                case TrayPopupAction.Hotkeys:
                    return new Rectangle(14, 268, 308, 32);
                case TrayPopupAction.SaveLocation:
                    return new Rectangle(14, 302, 308, 32);
                case TrayPopupAction.Startup:
                    return new Rectangle(14, 336, 308, 32);
                case TrayPopupAction.License:
                    return licenseEnabled ? new Rectangle(14, 370, 308, 32) : Rectangle.Empty;
                case TrayPopupAction.Exit:
                    return licenseEnabled
                        ? new Rectangle(14, 418, 308, 32)
                        : new Rectangle(14, 384, 308, 32);
                default:
                    return Rectangle.Empty;
            }
        }

        internal static Rectangle FitToWorkingArea(Point anchor, Rectangle workingArea, Size popupSize)
        {
            int x = anchor.X - popupSize.Width;
            int y = anchor.Y - popupSize.Height;
            if (x < workingArea.Left)
            {
                x = anchor.X;
            }
            if (y < workingArea.Top)
            {
                y = anchor.Y;
            }

            int maximumX = Math.Max(workingArea.Left, workingArea.Right - popupSize.Width);
            int maximumY = Math.Max(workingArea.Top, workingArea.Bottom - popupSize.Height);
            x = Math.Max(workingArea.Left, Math.Min(x, maximumX));
            y = Math.Max(workingArea.Top, Math.Min(y, maximumY));
            return new Rectangle(new Point(x, y), popupSize);
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams parameters = base.CreateParams;
                parameters.ClassStyle |= ShadowClassStyle;
                parameters.ExStyle |= ToolWindowExtendedStyle;
                return parameters;
            }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            ApplyDpi(DeviceDpi);
        }

        protected override void OnDpiChanged(DpiChangedEventArgs e)
        {
            base.OnDpiChanged(e);
            ApplyDpi(e.DeviceDpiNew);
            if (Visible)
            {
                Rectangle workingArea = Screen.FromRectangle(Bounds).WorkingArea;
                Bounds = FitToWorkingArea(Location, workingArea, Size);
            }
        }

        protected override void OnSizeChanged(EventArgs e)
        {
            base.OnSizeChanged(e);
            UpdateRoundedRegion();
        }

        protected override void OnDeactivate(EventArgs e)
        {
            base.OnDeactivate(e);
            if (Visible && !IsDisposed)
            {
                try
                {
                    BeginInvoke((MethodInvoker)delegate
                    {
                        if (Visible && !IsDisposed)
                        {
                            Hide();
                        }
                    });
                }
                catch (InvalidOperationException)
                {
                    // The owner may be disposing the tray context during shutdown.
                }
            }
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (keyData == Keys.Escape)
            {
                Hide();
                return true;
            }
            return base.ProcessCmdKey(ref msg, keyData);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Graphics graphics = e.Graphics;
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            graphics.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            graphics.Clear(BackgroundColor);

            DrawPanelBorder(graphics);
            DrawHeader(graphics);
            DrawCaptureAction(graphics);
            DrawReplayCard(graphics);
            DrawSettings(graphics);
            DrawExitAction(graphics);
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            TrayPopupAction next = ActionAt(e.Location);
            if (next != _hoverAction)
            {
                _hoverAction = next;
                Invalidate();
            }
            Cursor = next == TrayPopupAction.None ? Cursors.Default : Cursors.Hand;
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            base.OnMouseLeave(e);
            if (_hoverAction != TrayPopupAction.None)
            {
                _hoverAction = TrayPopupAction.None;
                Invalidate();
            }
            Cursor = Cursors.Default;
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button != MouseButtons.Left)
            {
                return;
            }
            _pressedAction = ActionAt(e.Location);
            if (_pressedAction != TrayPopupAction.None)
            {
                Invalidate();
            }
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            TrayPopupAction releasedAction = e.Button == MouseButtons.Left
                ? ActionAt(e.Location)
                : TrayPopupAction.None;
            TrayPopupAction pressedAction = _pressedAction;
            _pressedAction = TrayPopupAction.None;
            Invalidate();
            if (releasedAction == TrayPopupAction.None || releasedAction != pressedAction)
            {
                return;
            }
            InvokeAction(releasedAction);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _brandFont.Dispose();
                _bodyFont.Dispose();
                _mediumFont.Dispose();
                _smallFont.Dispose();
                _shortcutFont.Dispose();
                if (Region != null)
                {
                    Region current = Region;
                    Region = null;
                    current.Dispose();
                }
            }
            base.Dispose(disposing);
        }

        private int Scale(int value)
        {
            return ScaleLogicalValue(value, _dpi);
        }

        private new float Scale(float value)
        {
            return value * _dpi / 96f;
        }

        private Rectangle ScaleRectangle(Rectangle rectangle)
        {
            return new Rectangle(Scale(rectangle.X), Scale(rectangle.Y), Scale(rectangle.Width), Scale(rectangle.Height));
        }

        private void ApplyDpi(int dpi)
        {
            _dpi = dpi > 0 ? dpi : 96;
            Size logicalSize = GetLogicalSize(_licenseEnabled);
            ClientSize = new Size(Scale(logicalSize.Width), Scale(logicalSize.Height));
            UpdateRoundedRegion();
            Invalidate();
        }

        private void UpdateRoundedRegion()
        {
            if (Width <= 0 || Height <= 0)
            {
                return;
            }
            Rectangle bounds = new Rectangle(0, 0, Width, Height);
            using (GraphicsPath path = RoundedRectangle(bounds, Scale(13)))
            {
                Region previous = Region;
                Region = new Region(path);
                if (previous != null)
                {
                    previous.Dispose();
                }
            }
        }

        private void DrawPanelBorder(Graphics graphics)
        {
            Rectangle border = new Rectangle(0, 0, Math.Max(0, Width - 1), Math.Max(0, Height - 1));
            using (GraphicsPath path = RoundedRectangle(border, Scale(13)))
            using (Pen pen = new Pen(BorderColor))
            {
                graphics.DrawPath(pen, path);
            }
        }

        private void DrawHeader(Graphics graphics)
        {
            Rectangle brand = ScaleRectangle(new Rectangle(14, 9, 178, 23));
            Rectangle version = ScaleRectangle(new Rectangle(218, 11, 104, 18));
            Rectangle subtitle = ScaleRectangle(new Rectangle(15, 32, 250, 17));
            DrawText(graphics, "BoltSnip", _brandFont, TextColor, brand, StringAlignment.Near);
            DrawText(graphics, "v" + _version, _shortcutFont, MutedTextColor, version, StringAlignment.Far);
            DrawText(graphics, "Screen Capture & Replay", _smallFont, SecondaryTextColor, subtitle, StringAlignment.Near);
        }

        private void DrawCaptureAction(Graphics graphics)
        {
            Rectangle logicalBounds = GetLogicalBounds(TrayPopupAction.Capture, _licenseEnabled);
            Rectangle bounds = ScaleRectangle(logicalBounds);
            DrawActionSurface(graphics, bounds, TrayPopupAction.Capture, true);
            DrawCaptureIcon(graphics, Scale(25), bounds.Top + (bounds.Height - Scale(18)) / 2, Scale(18));
            Rectangle label = new Rectangle(Scale(54), bounds.Top, Scale(136), bounds.Height);
            Rectangle shortcut = new Rectangle(Scale(184), bounds.Top, Scale(124), bounds.Height);
            DrawText(graphics, "开始截图", _mediumFont, TextColor, label, StringAlignment.Near);
            DrawText(graphics, _captureShortcut, _shortcutFont, SecondaryTextColor, shortcut, StringAlignment.Far);
        }

        private void DrawReplayCard(Graphics graphics)
        {
            Rectangle card = ScaleRectangle(GetLogicalBounds(TrayPopupAction.ReplayToggle, _licenseEnabled));
            using (GraphicsPath path = RoundedRectangle(card, Scale(11)))
            using (Brush fill = new SolidBrush(CardColor))
            using (Pen border = new Pen(BorderColor))
            {
                graphics.FillPath(fill, path);
                graphics.DrawPath(border, path);
            }

            Rectangle title = new Rectangle(card.Left + Scale(12), card.Top + Scale(8), Scale(ReplayTitleLogicalWidth), Scale(26));
            DrawText(graphics, "Instant Replay", _mediumFont, TextColor, title, StringAlignment.Near);
            DrawReplayState(graphics, card);

            string description = ReplayDescription();
            Rectangle subtitle = new Rectangle(card.Left + Scale(12), card.Top + Scale(38), card.Width - Scale(24), Scale(23));
            DrawText(graphics, description, _smallFont, SecondaryTextColor, subtitle, StringAlignment.Near);

            Rectangle saveButton = ScaleRectangle(GetLogicalBounds(TrayPopupAction.ReplaySave, _licenseEnabled));
            bool saveEnabled = _replayState == ReplayState.Recording && !_isSaving;
            bool showSaved = IsSavedFeedbackVisible();
            bool buttonHovered = _hoverAction == TrayPopupAction.ReplaySave;
            bool buttonPressed = _pressedAction == TrayPopupAction.ReplaySave;
            Color buttonFill = buttonPressed ? PressedColor : (buttonHovered && saveEnabled ? HoverColor : Color.White);
            using (GraphicsPath buttonPath = RoundedRectangle(saveButton, Scale(8)))
            using (Brush fill = new SolidBrush(buttonFill))
            using (Pen border = new Pen(BorderColor))
            {
                graphics.FillPath(fill, buttonPath);
                graphics.DrawPath(border, buttonPath);
            }

            string saveText = _isSaving ? "正在保存…" : (showSaved ? "已保存" : "保存回放");
            Color saveColor = showSaved ? AccentColor : (saveEnabled ? TextColor : MutedTextColor);
            Rectangle saveLabel = new Rectangle(saveButton.Left + Scale(10), saveButton.Top, Scale(148), saveButton.Height);
            DrawText(graphics, saveText, _mediumFont, saveColor, saveLabel, StringAlignment.Near);
            if (!_isSaving && !showSaved && !string.IsNullOrEmpty(_replayShortcut))
            {
                Rectangle saveShortcut = new Rectangle(saveButton.Left + Scale(138), saveButton.Top, saveButton.Width - Scale(148), saveButton.Height);
                DrawText(graphics, _replayShortcut, _shortcutFont, saveEnabled ? SecondaryTextColor : MutedTextColor, saveShortcut, StringAlignment.Far);
            }
        }

        private void DrawReplayState(Graphics graphics, Rectangle card)
        {
            string text;
            Color color;
            bool enabled = _replayState == ReplayState.Starting || _replayState == ReplayState.Recording;
            if (_isSaving)
            {
                text = "Saving…";
                color = AccentColor;
            }
            else if (_replayState == ReplayState.Starting)
            {
                text = "Starting…";
                color = AccentColor;
            }
            else if (_replayState == ReplayState.Recording)
            {
                text = "ON";
                color = AccentColor;
            }
            else if (_replayState == ReplayState.Stopping)
            {
                text = "Stopping…";
                color = SecondaryTextColor;
            }
            else if (_replayState == ReplayState.Error)
            {
                text = "Error";
                color = ErrorColor;
            }
            else
            {
                text = "OFF";
                color = SecondaryTextColor;
            }

            Rectangle state = new Rectangle(card.Left + Scale(174), card.Top + Scale(8), Scale(82), Scale(26));
            DrawText(graphics, text, _shortcutFont, color, state, StringAlignment.Far);
            Rectangle toggle = ScaleRectangle(new Rectangle(274, 123, 34, 20));
            DrawToggle(graphics, toggle, enabled, _replayState == ReplayState.Stopping, _hoverAction == TrayPopupAction.ReplayToggle, _pressedAction == TrayPopupAction.ReplayToggle);
        }

        private string ReplayDescription()
        {
            if (_isSaving)
            {
                return "正在保存最近 5 分钟";
            }
            if (_replayState == ReplayState.Starting)
            {
                return "正在启动录制…";
            }
            if (_replayState == ReplayState.Recording)
            {
                if (_replayAudioState == ReplayAudioState.Active)
                {
                    return "正在缓存最近 5 分钟 · 系统声音";
                }
                if (_replayAudioState == ReplayAudioState.Unavailable)
                {
                    return "正在缓存最近 5 分钟 · 音频不可用";
                }
                return "正在缓存最近 5 分钟";
            }
            if (_replayState == ReplayState.Stopping)
            {
                return "正在停止录制…";
            }
            if (_replayState == ReplayState.Error)
            {
                return "启动失败，点击开关重试";
            }
            return "保存最近 5 分钟";
        }

        private void DrawSettings(Graphics graphics)
        {
            Rectangle heading = ScaleRectangle(new Rectangle(16, 246, 280, 18));
            DrawText(graphics, "设置", _smallFont, SecondaryTextColor, heading, StringAlignment.Near);
            DrawSettingRow(graphics, TrayPopupAction.Hotkeys, "快捷键", DrawKeyboardIcon);
            DrawSettingRow(graphics, TrayPopupAction.SaveLocation, "保存位置", DrawFolderIcon);
            DrawSettingRow(graphics, TrayPopupAction.Startup, "开机启动", DrawPowerIcon);
            if (_licenseEnabled)
            {
                DrawSettingRow(graphics, TrayPopupAction.License, "授权管理", DrawKeyIcon);
            }
        }

        private void DrawSettingRow(Graphics graphics, TrayPopupAction action, string text, Action<Graphics, int, int, int> drawIcon)
        {
            Rectangle bounds = ScaleRectangle(GetLogicalBounds(action, _licenseEnabled));
            DrawActionSurface(graphics, bounds, action, false);
            drawIcon(graphics, Scale(24), bounds.Top + (bounds.Height - Scale(16)) / 2, Scale(16));
            Rectangle label = new Rectangle(Scale(51), bounds.Top, Scale(206), bounds.Height);
            DrawText(graphics, text, _bodyFont, TextColor, label, StringAlignment.Near);
            if (action == TrayPopupAction.Startup)
            {
                Rectangle toggle = ScaleRectangle(new Rectangle(276, GetLogicalBounds(action, _licenseEnabled).Top + 8, 32, 16));
                DrawToggle(graphics, toggle, _startupEnabled, false, _hoverAction == action, _pressedAction == action);
            }
        }

        private void DrawExitAction(Graphics graphics)
        {
            Rectangle bounds = ScaleRectangle(GetLogicalBounds(TrayPopupAction.Exit, _licenseEnabled));
            DrawActionSurface(graphics, bounds, TrayPopupAction.Exit, false);
            DrawExitIcon(graphics, Scale(24), bounds.Top + (bounds.Height - Scale(16)) / 2, Scale(16));
            Rectangle label = new Rectangle(Scale(51), bounds.Top, Scale(250), bounds.Height);
            DrawText(graphics, "退出 BoltSnip", _bodyFont, TextColor, label, StringAlignment.Near);
        }

        private void DrawActionSurface(Graphics graphics, Rectangle bounds, TrayPopupAction action, bool bordered)
        {
            bool hovered = _hoverAction == action;
            bool pressed = _pressedAction == action;
            if (!hovered && !pressed && !bordered)
            {
                return;
            }

            Color fillColor = pressed ? PressedColor : HoverColor;
            if (bordered && !hovered && !pressed)
            {
                fillColor = Color.White;
            }
            using (GraphicsPath path = RoundedRectangle(bounds, Scale(bordered ? 9 : 8)))
            using (Brush fill = new SolidBrush(fillColor))
            {
                graphics.FillPath(fill, path);
                if (bordered)
                {
                    using (Pen border = new Pen(BorderColor))
                    {
                        graphics.DrawPath(border, path);
                    }
                }
            }
        }

        private void DrawToggle(Graphics graphics, Rectangle bounds, bool enabled, bool disabled, bool hovered, bool pressed)
        {
            Color trackColor = enabled ? AccentColor : Color.FromArgb(214, 222, 225);
            if (disabled)
            {
                trackColor = Color.FromArgb(222, 228, 230);
            }
            else if (pressed)
            {
                trackColor = enabled ? Color.FromArgb(62, 129, 142) : Color.FromArgb(197, 208, 211);
            }
            else if (hovered)
            {
                trackColor = enabled ? Color.FromArgb(91, 158, 169) : Color.FromArgb(203, 214, 217);
            }

            using (GraphicsPath path = RoundedRectangle(bounds, bounds.Height / 2))
            using (Brush track = new SolidBrush(trackColor))
            using (Brush knob = new SolidBrush(Color.White))
            using (Pen knobBorder = new Pen(Color.FromArgb(215, 223, 226)))
            {
                graphics.FillPath(track, path);
                int diameter = Math.Max(Scale(10), bounds.Height - Scale(4));
                int x = enabled ? bounds.Right - diameter - Scale(2) : bounds.Left + Scale(2);
                int y = bounds.Top + (bounds.Height - diameter) / 2;
                Rectangle knobBounds = new Rectangle(x, y, diameter, diameter);
                graphics.FillEllipse(knob, knobBounds);
                graphics.DrawEllipse(knobBorder, knobBounds);
            }
        }

        private void DrawCaptureIcon(Graphics graphics, int x, int y, int size)
        {
            using (Pen pen = new Pen(AccentColor, Math.Max(1.2f, Scale(1.5f))))
            {
                pen.StartCap = LineCap.Round;
                pen.EndCap = LineCap.Round;
                float left = x + size * 0.12f;
                float top = y + size * 0.12f;
                float right = x + size * 0.88f;
                float bottom = y + size * 0.88f;
                float corner = size * 0.28f;
                graphics.DrawLine(pen, left, top + corner, left, top);
                graphics.DrawLine(pen, left, top, left + corner, top);
                graphics.DrawLine(pen, right - corner, top, right, top);
                graphics.DrawLine(pen, right, top, right, top + corner);
                graphics.DrawLine(pen, left, bottom - corner, left, bottom);
                graphics.DrawLine(pen, left, bottom, left + corner, bottom);
                graphics.DrawLine(pen, right - corner, bottom, right, bottom);
                graphics.DrawLine(pen, right, bottom - corner, right, bottom);
                float center = size * 0.5f;
                float radius = size * 0.16f;
                graphics.DrawEllipse(pen, x + center - radius, y + center - radius, radius * 2, radius * 2);
            }
        }

        private void DrawKeyboardIcon(Graphics graphics, int x, int y, int size)
        {
            Rectangle bounds = new Rectangle(x, y + size / 5, size, size * 3 / 5);
            using (GraphicsPath path = RoundedRectangle(bounds, Scale(3)))
            using (Pen pen = new Pen(SecondaryTextColor, Math.Max(1f, Scale(1.25f))))
            using (Brush key = new SolidBrush(SecondaryTextColor))
            {
                graphics.DrawPath(pen, path);
                int keySize = Math.Max(1, (int)Math.Round(Scale(1.5f)));
                for (int row = 0; row < 2; row++)
                {
                    for (int column = 0; column < 3; column++)
                    {
                        graphics.FillEllipse(key, x + Scale(3) + column * Scale(4), y + Scale(5) + row * Scale(4), keySize, keySize);
                    }
                }
                graphics.DrawLine(pen, x + Scale(4), y + Scale(12), x + Scale(12), y + Scale(12));
            }
        }

        private void DrawFolderIcon(Graphics graphics, int x, int y, int size)
        {
            using (GraphicsPath path = new GraphicsPath())
            using (Pen pen = new Pen(SecondaryTextColor, Math.Max(1f, Scale(1.25f))))
            {
                path.AddLine(x + Scale(2), y + Scale(4), x + Scale(7), y + Scale(4));
                path.AddLine(x + Scale(7), y + Scale(4), x + Scale(9), y + Scale(6));
                path.AddLine(x + Scale(9), y + Scale(6), x + size - Scale(2), y + Scale(6));
                path.AddLine(x + size - Scale(2), y + Scale(6), x + size - Scale(3), y + size - Scale(3));
                path.AddLine(x + size - Scale(3), y + size - Scale(3), x + Scale(2), y + size - Scale(3));
                path.CloseFigure();
                graphics.DrawPath(pen, path);
            }
        }

        private void DrawPowerIcon(Graphics graphics, int x, int y, int size)
        {
            using (Pen pen = new Pen(SecondaryTextColor, Math.Max(1f, Scale(1.35f))))
            {
                pen.StartCap = LineCap.Round;
                pen.EndCap = LineCap.Round;
                graphics.DrawArc(pen, x + Scale(2), y + Scale(3), size - Scale(4), size - Scale(4), 42, 276);
                graphics.DrawLine(pen, x + size / 2, y + Scale(1), x + size / 2, y + Scale(8));
            }
        }

        private void DrawKeyIcon(Graphics graphics, int x, int y, int size)
        {
            using (Pen pen = new Pen(SecondaryTextColor, Math.Max(1f, Scale(1.3f))))
            {
                pen.StartCap = LineCap.Round;
                pen.EndCap = LineCap.Round;
                graphics.DrawEllipse(pen, x + Scale(1), y + Scale(2), Scale(7), Scale(7));
                graphics.DrawLine(pen, x + Scale(8), y + Scale(9), x + size - Scale(1), y + size - Scale(2));
                graphics.DrawLine(pen, x + size - Scale(5), y + size - Scale(6), x + size - Scale(2), y + size - Scale(9));
                graphics.DrawLine(pen, x + size - Scale(8), y + size - Scale(3), x + size - Scale(5), y + size - Scale(6));
            }
        }

        private void DrawExitIcon(Graphics graphics, int x, int y, int size)
        {
            using (Pen pen = new Pen(SecondaryTextColor, Math.Max(1f, Scale(1.3f))))
            {
                pen.StartCap = LineCap.Round;
                pen.EndCap = LineCap.Round;
                graphics.DrawLine(pen, x + Scale(3), y + Scale(2), x + Scale(3), y + size - Scale(2));
                graphics.DrawLine(pen, x + Scale(3), y + Scale(2), x + Scale(9), y + Scale(2));
                graphics.DrawLine(pen, x + Scale(9), y + Scale(2), x + Scale(9), y + Scale(6));
                graphics.DrawLine(pen, x + Scale(7), y + size / 2, x + size - Scale(2), y + size / 2);
                graphics.DrawLine(pen, x + size - Scale(5), y + size / 2 - Scale(3), x + size - Scale(2), y + size / 2);
                graphics.DrawLine(pen, x + size - Scale(5), y + size / 2 + Scale(3), x + size - Scale(2), y + size / 2);
            }
        }

        private void DrawText(Graphics graphics, string text, Font font, Color color, Rectangle bounds, StringAlignment alignment)
        {
            if (string.IsNullOrEmpty(text) || bounds.Width <= 0 || bounds.Height <= 0)
            {
                return;
            }
            using (Brush brush = new SolidBrush(color))
            using (StringFormat format = new StringFormat())
            {
                format.Alignment = alignment;
                format.LineAlignment = StringAlignment.Center;
                format.Trimming = StringTrimming.EllipsisCharacter;
                format.FormatFlags = StringFormatFlags.NoWrap;
                graphics.DrawString(text, font, brush, bounds, format);
            }
        }

        private bool IsSavedFeedbackVisible()
        {
            ExpireSavedFeedback();
            return _savedFeedback;
        }

        private void ExpireSavedFeedback()
        {
            if (_savedFeedback && DateTime.UtcNow >= _savedFeedbackUntil)
            {
                _savedFeedback = false;
                Invalidate(ScaleRectangle(GetLogicalBounds(TrayPopupAction.ReplaySave, _licenseEnabled)));
            }
        }

        private TrayPopupAction ActionAt(Point point)
        {
            Point logicalPoint = new Point(
                (int)Math.Floor(point.X * 96.0 / _dpi),
                (int)Math.Floor(point.Y * 96.0 / _dpi));
            if (GetLogicalBounds(TrayPopupAction.Capture, _licenseEnabled).Contains(logicalPoint))
            {
                return TrayPopupAction.Capture;
            }
            if (GetLogicalBounds(TrayPopupAction.ReplayToggle, _licenseEnabled).Contains(logicalPoint))
            {
                return GetLogicalBounds(TrayPopupAction.ReplaySave, _licenseEnabled).Contains(logicalPoint)
                    ? TrayPopupAction.ReplaySave
                    : TrayPopupAction.ReplayToggle;
            }
            if (GetLogicalBounds(TrayPopupAction.Hotkeys, _licenseEnabled).Contains(logicalPoint))
            {
                return TrayPopupAction.Hotkeys;
            }
            if (GetLogicalBounds(TrayPopupAction.SaveLocation, _licenseEnabled).Contains(logicalPoint))
            {
                return TrayPopupAction.SaveLocation;
            }
            if (GetLogicalBounds(TrayPopupAction.Startup, _licenseEnabled).Contains(logicalPoint))
            {
                return TrayPopupAction.Startup;
            }
            if (GetLogicalBounds(TrayPopupAction.License, _licenseEnabled).Contains(logicalPoint))
            {
                return TrayPopupAction.License;
            }
            if (GetLogicalBounds(TrayPopupAction.Exit, _licenseEnabled).Contains(logicalPoint))
            {
                return TrayPopupAction.Exit;
            }
            return TrayPopupAction.None;
        }

        private void InvokeAction(TrayPopupAction action)
        {
            switch (action)
            {
                case TrayPopupAction.Capture:
                    Hide();
                    if (_beginCapture != null) _beginCapture();
                    break;
                case TrayPopupAction.ReplayToggle:
                    if (_replayState != ReplayState.Stopping && _toggleReplay != null) _toggleReplay();
                    break;
                case TrayPopupAction.ReplaySave:
                    if (_replayState == ReplayState.Recording && !_isSaving && _saveReplay != null) _saveReplay();
                    break;
                case TrayPopupAction.Hotkeys:
                    Hide();
                    if (_openHotkeys != null) _openHotkeys();
                    break;
                case TrayPopupAction.SaveLocation:
                    Hide();
                    if (_openSaveLocation != null) _openSaveLocation();
                    break;
                case TrayPopupAction.Startup:
                    if (_toggleStartup != null) _toggleStartup();
                    break;
                case TrayPopupAction.License:
                    Hide();
                    if (_openLicense != null) _openLicense();
                    break;
                case TrayPopupAction.Exit:
                    Hide();
                    if (_exitApplication != null) _exitApplication();
                    break;
            }
        }

        private static GraphicsPath RoundedRectangle(Rectangle rectangle, int radius)
        {
            int diameter = Math.Min(radius * 2, Math.Min(rectangle.Width, rectangle.Height));
            GraphicsPath path = new GraphicsPath();
            if (diameter <= 0)
            {
                path.AddRectangle(rectangle);
                return path;
            }
            path.AddArc(rectangle.Left, rectangle.Top, diameter, diameter, 180, 90);
            path.AddArc(rectangle.Right - diameter, rectangle.Top, diameter, diameter, 270, 90);
            path.AddArc(rectangle.Right - diameter, rectangle.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(rectangle.Left, rectangle.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }

        private static string FormatShortcut(string shortcut)
        {
            return string.IsNullOrEmpty(shortcut) ? string.Empty : shortcut.Replace("+", " + ");
        }
    }
}
