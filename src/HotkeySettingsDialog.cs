using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using System.Runtime.InteropServices;

namespace BoltSnip
{
    internal sealed class HotkeySettingsDialog : Form
    {
        private static readonly Color BackgroundColor = HotkeySettingsDialogColor.Background;
        private static readonly Color SurfaceColor = HotkeySettingsDialogColor.Surface;
        private static readonly Color BorderColor = HotkeySettingsDialogColor.Border;
        private static readonly Color TextColor = HotkeySettingsDialogColor.Text;
        private static readonly Color MutedColor = HotkeySettingsDialogColor.Muted;
        private static readonly Color AccentColor = HotkeySettingsDialogColor.Accent;
        private static readonly Color AccentSoftColor = HotkeySettingsDialogColor.AccentSoft;
        private static readonly Color ErrorColor = Color.FromArgb(185, 28, 28);
        private static readonly Color SuccessColor = MutedColor;

        private readonly AppSettings _settings;
        private readonly HotkeyWindow _hotkeyWindow;
        private readonly List<Font> _ownedFonts = new List<Font>();
        private readonly HotkeySettingsCard _captureCard;
        private readonly HotkeySettingsCard _replayCard;
        private readonly ShortcutPill _capturePill;
        private readonly ShortcutPill _replayPill;
        private readonly Label _captureStatus;
        private readonly Label _replayStatus;
        private readonly RoundedSettingsButton _captureModifyButton;
        private readonly RoundedSettingsButton _replayModifyButton;
        private readonly RoundedSettingsButton _saveButton;
        private readonly RoundedSettingsButton _cancelButton;
        private readonly RoundedSettingsButton _defaultsButton;
        private readonly Label _captureDescription;
        private readonly Label _replayDescription;

        private HotkeyGesture _captureDraft;
        private HotkeyGesture _replaySaveDraft;
        private HotkeySlot? _recordingSlot;
        private bool _captureWasEdited;
        private bool _replaySaveWasEdited;
        private int _dpi = 96;

        internal HotkeySettingsDialog(AppSettings settings, HotkeyWindow hotkeyWindow)
        {
            if (settings == null) throw new ArgumentNullException("settings");
            if (hotkeyWindow == null) throw new ArgumentNullException("hotkeyWindow");

            _settings = settings;
            _hotkeyWindow = hotkeyWindow;
            _captureDraft = settings.CaptureHotkey;
            _replaySaveDraft = settings.ReplaySaveHotkey;

            Text = "快捷键";
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.CenterScreen;
            TopMost = true;
            AutoScaleMode = AutoScaleMode.None;
            BackColor = BackgroundColor;
            DoubleBuffered = true;
            SetStyle(
                ControlStyles.UserPaint |
                ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.ResizeRedraw,
                true);

            Label title = new Label();
            title.Text = "快捷键";
            title.ForeColor = TextColor;
            title.Font = OwnFont("Microsoft YaHei UI", 13f, FontStyle.Bold);
            title.BackColor = Color.Transparent;
            title.AutoSize = true;
            Controls.Add(title);

            Label subtitle = new Label();
            subtitle.Text = "自定义 BoltSnip 的全局快捷键";
            subtitle.ForeColor = MutedColor;
            subtitle.Font = OwnFont("Microsoft YaHei UI", 9f, FontStyle.Regular);
            subtitle.BackColor = Color.Transparent;
            subtitle.AutoSize = true;
            Controls.Add(subtitle);

            RoundedSettingsButton closeButton = CreateButton("×", SettingsButtonStyle.Secondary);
            closeButton.AccessibleName = "关闭快捷键设置";
            closeButton.Font = OwnFont("Segoe UI", 12f, FontStyle.Regular);
            closeButton.Click += delegate { CancelChanges(); };
            Controls.Add(closeButton);

            _captureCard = new HotkeySettingsCard();
            _captureCard.AccessibleName = "截图快捷键";
            Controls.Add(_captureCard);

            Label captureTitle = CreateCardTitle("截图");
            _captureDescription = CreateCardDescription("快速打开截图选择器");
            _capturePill = new ShortcutPill();
            _capturePill.AccessibleName = "截图快捷键组合";
            _capturePill.Font = OwnFont("Segoe UI", 9f, FontStyle.Bold);
            _captureStatus = CreateStatusLabel();
            _captureModifyButton = CreateButton("修改", SettingsButtonStyle.Secondary);
            _captureModifyButton.AccessibleName = "修改截图快捷键";
            _captureModifyButton.Click += delegate { BeginRecording(HotkeySlot.Capture); };
            _captureCard.Controls.Add(captureTitle);
            _captureCard.Controls.Add(_captureDescription);
            _captureCard.Controls.Add(_capturePill);
            _captureCard.Controls.Add(_captureStatus);
            _captureCard.Controls.Add(_captureModifyButton);

            _replayCard = new HotkeySettingsCard();
            _replayCard.AccessibleName = "保存即时回放快捷键";
            Controls.Add(_replayCard);

            Label replayTitle = CreateCardTitle("保存即时回放");
            _replayDescription = CreateCardDescription("保存最近最多 5 分钟的回放");
            _replayPill = new ShortcutPill();
            _replayPill.AccessibleName = "保存即时回放快捷键组合";
            _replayPill.Font = OwnFont("Segoe UI", 9f, FontStyle.Bold);
            _replayStatus = CreateStatusLabel();
            _replayModifyButton = CreateButton("修改", SettingsButtonStyle.Secondary);
            _replayModifyButton.AccessibleName = "修改保存即时回放快捷键";
            _replayModifyButton.Click += delegate { BeginRecording(HotkeySlot.ReplaySave); };
            _replayCard.Controls.Add(replayTitle);
            _replayCard.Controls.Add(_replayDescription);
            _replayCard.Controls.Add(_replayPill);
            _replayCard.Controls.Add(_replayStatus);
            _replayCard.Controls.Add(_replayModifyButton);

            _defaultsButton = CreateButton("恢复默认", SettingsButtonStyle.Tertiary);
            _defaultsButton.AccessibleName = "恢复默认快捷键";
            _defaultsButton.Click += delegate { RestoreDefaults(); };
            Controls.Add(_defaultsButton);

            _cancelButton = CreateButton("取消", SettingsButtonStyle.Secondary);
            _cancelButton.Click += delegate { CancelChanges(); };
            Controls.Add(_cancelButton);

            _saveButton = CreateButton("保存", SettingsButtonStyle.Primary);
            _saveButton.AccessibleName = "保存快捷键设置";
            _saveButton.Click += SaveButtonClick;
            Controls.Add(_saveButton);

            AcceptButton = _saveButton;
            CancelButton = _cancelButton;
            FormClosing += delegate
            {
                if (DialogResult != DialogResult.OK)
                {
                    DialogResult = DialogResult.Cancel;
                }
            };

            UpdateShortcutDisplays();
            SetCardAvailability(HotkeySlot.Capture);
            SetCardAvailability(HotkeySlot.ReplaySave);
            ApplyDpi(DeviceDpi);
        }

        internal HotkeyGesture CaptureDraft
        {
            get { return _captureDraft; }
        }

        internal HotkeyGesture ReplaySaveDraft
        {
            get { return _replaySaveDraft; }
        }

        protected override bool ProcessCmdKey(ref Message message, Keys keyData)
        {
            if (keyData == Keys.Escape)
            {
                CancelChanges();
                return true;
            }

            if (_recordingSlot.HasValue)
            {
                HotkeySlot slot = _recordingSlot.Value;
                HotkeyGesture gesture;
                string error;
                KeyEventArgs keyEvent = new KeyEventArgs(keyData);
                if (!HotkeyGesture.TryFromKeyEvent(keyEvent, out gesture, out error))
                {
                    SetCardStatus(slot, error, ErrorColor);
                    return true;
                }

                if (slot == HotkeySlot.Capture)
                {
                    _captureDraft = gesture;
                    _captureWasEdited = true;
                }
                else
                {
                    _replaySaveDraft = gesture;
                    _replaySaveWasEdited = true;
                }

                _recordingSlot = null;
                UpdateShortcutDisplays();
                SetCardAvailability(slot);
                return true;
            }

            return base.ProcessCmdKey(ref message, keyData);
        }

        [DllImport("user32.dll")]
        private static extern uint GetDpiForWindow(IntPtr window);

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            int dpi = DeviceDpi;
            try
            {
                uint actual = GetDpiForWindow(Handle);
                if (actual > 0) dpi = (int)actual;
            }
            catch (EntryPointNotFoundException) { }
            ApplyDpi(dpi);
        }

        protected override void OnDpiChanged(DpiChangedEventArgs e)
        {
            base.OnDpiChanged(e);
            ApplyDpi(e.DeviceDpiNew);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle bounds = new Rectangle(0, 0, ClientSize.Width - 1, ClientSize.Height - 1);
            using (GraphicsPath outline = RoundedRectangle(bounds, Scale(13)))
            using (Pen border = new Pen(BorderColor, Math.Max(1f, Scale(1))))
            {
                e.Graphics.DrawPath(border, outline);
            }
        }

        protected override void WndProc(ref Message message)
        {
            const int WmNcHitTest = 0x0084;
            const int HtCaption = 0x0002;
            if (message.Msg == WmNcHitTest)
            {
                long packedPoint = message.LParam.ToInt64();
                Point point = PointToClient(new Point(
                    unchecked((short)(packedPoint & 0xffff)),
                    unchecked((short)((packedPoint >> 16) & 0xffff))));
                if (point.Y >= 0 && point.Y < Scale(68) && point.X < ClientSize.Width - Scale(52))
                {
                    message.Result = new IntPtr(HtCaption);
                    return;
                }
            }
            base.WndProc(ref message);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                for (int index = 0; index < _ownedFonts.Count; index++)
                {
                    _ownedFonts[index].Dispose();
                }
                _ownedFonts.Clear();
            }
            base.Dispose(disposing);
        }

        private void ApplyDpi(int dpi)
        {
            _dpi = dpi > 0 ? dpi : 96;
            ClientSize = new Size(Scale(440), Scale(330));
            Region previousRegion = Region;
            using (GraphicsPath shape = RoundedRectangle(
                new Rectangle(0, 0, ClientSize.Width, ClientSize.Height),
                Scale(13)))
            {
                Region = new Region(shape);
            }
            if (previousRegion != null)
            {
                previousRegion.Dispose();
            }

            SetBounds(Controls[0], 22, 16, 280, 24);
            SetBounds(Controls[1], 23, 44, 330, 19);
            SetBounds(Controls[2], 396, 13, 29, 29);
            _captureCard.SetBounds(Scale(18), Scale(76), Scale(404), Scale(91));
            _replayCard.SetBounds(Scale(18), Scale(178), Scale(404), Scale(91));

            SetBounds(_captureCard.Controls[0], 16, 9, 230, 20);
            SetBounds(_captureDescription, 16, 32, 260, 18);
            _capturePill.SetBounds(Scale(16), Scale(58), Scale(137), Scale(25));
            SetBounds(_captureStatus, 163, 51, 141, 37);
            SetBounds(_captureModifyButton, 316, 31, 72, 32);

            SetBounds(_replayCard.Controls[0], 16, 9, 230, 20);
            SetBounds(_replayDescription, 16, 32, 280, 18);
            _replayPill.SetBounds(Scale(16), Scale(58), Scale(137), Scale(25));
            SetBounds(_replayStatus, 163, 51, 141, 37);
            SetBounds(_replayModifyButton, 316, 31, 72, 32);

            SetBounds(_defaultsButton, 18, 286, 102, 30);
            SetBounds(_cancelButton, 264, 284, 72, 32);
            SetBounds(_saveButton, 348, 284, 74, 32);
            Invalidate(true);
        }

        private void SetBounds(Control control, int x, int y, int width, int height)
        {
            control.SetBounds(Scale(x), Scale(y), Scale(width), Scale(height));
        }

        private int Scale(int logicalValue)
        {
            return (logicalValue * _dpi * 9 + 480) / 960;
        }

        private Font OwnFont(string family, float size, FontStyle style)
        {
            Font font = new Font(family, size * 0.9f, style, GraphicsUnit.Point);
            _ownedFonts.Add(font);
            return font;
        }

        private Label CreateCardTitle(string text)
        {
            Label label = new Label();
            label.Text = text;
            label.AutoSize = true;
            label.Font = OwnFont("Microsoft YaHei UI", 9.5f, FontStyle.Bold);
            label.ForeColor = TextColor;
            label.BackColor = Color.Transparent;
            return label;
        }

        private Label CreateCardDescription(string text)
        {
            Label label = new Label();
            label.Text = text;
            label.AutoSize = true;
            label.Font = OwnFont("Microsoft YaHei UI", 8.25f, FontStyle.Regular);
            label.ForeColor = MutedColor;
            label.BackColor = Color.Transparent;
            return label;
        }

        private Label CreateStatusLabel()
        {
            Label label = new Label();
            label.AutoSize = false;
            label.TextAlign = ContentAlignment.MiddleLeft;
            label.Font = OwnFont("Microsoft YaHei UI", 8f, FontStyle.Regular);
            label.ForeColor = SuccessColor;
            label.BackColor = Color.Transparent;
            return label;
        }

        private RoundedSettingsButton CreateButton(string text, SettingsButtonStyle style)
        {
            RoundedSettingsButton button = new RoundedSettingsButton(style);
            button.Text = text;
            button.Font = OwnFont("Microsoft YaHei UI", 9f, FontStyle.Regular);
            button.AccessibleRole = AccessibleRole.PushButton;
            return button;
        }

        private void BeginRecording(HotkeySlot slot)
        {
            _recordingSlot = slot;
            if (slot == HotkeySlot.Capture)
            {
                _capturePill.Text = "请按下新的快捷键…";
                _capturePill.Recording = true;
                _captureModifyButton.Text = "按键中";
            }
            else
            {
                _replayPill.Text = "请按下新的快捷键…";
                _replayPill.Recording = true;
                _replayModifyButton.Text = "按键中";
            }
            SetCardStatus(slot, "等待输入", AccentColor);
            Focus();
        }

        private void RestoreDefaults()
        {
            _recordingSlot = null;
            _captureDraft = HotkeyGesture.Default;
            _replaySaveDraft = HotkeyGesture.ReplaySaveDefault;
            _captureWasEdited = true;
            _replaySaveWasEdited = true;
            _capturePill.Recording = false;
            _replayPill.Recording = false;
            _captureModifyButton.Text = "修改";
            _replayModifyButton.Text = "修改";
            UpdateShortcutDisplays();
            SetCardAvailability(HotkeySlot.Capture);
            SetCardAvailability(HotkeySlot.ReplaySave);
        }

        private void UpdateShortcutDisplays()
        {
            _capturePill.Text = _captureDraft.DisplayText;
            _replayPill.Text = _replaySaveDraft.DisplayText;
            _capturePill.Recording = false;
            _replayPill.Recording = false;
            _captureModifyButton.Text = "修改";
            _replayModifyButton.Text = "修改";
        }

        private void SetCardAvailability(HotkeySlot slot)
        {
            HotkeyGesture candidate = slot == HotkeySlot.Capture ? _captureDraft : _replaySaveDraft;
            string error;
            bool available = _hotkeyWindow.CheckAvailability(
                _captureDraft,
                _replaySaveDraft,
                slot,
                candidate,
                out error);
            string visibleStatus = available
                ? "可用"
                : error.IndexOf("占用", StringComparison.Ordinal) >= 0
                    ? "已被占用"
                    : error;
            SetCardStatus(slot, visibleStatus, available ? SuccessColor : ErrorColor, error);
        }

        private void SetCardStatus(HotkeySlot slot, string text, Color color)
        {
            SetCardStatus(slot, text, color, text);
        }

        private void SetCardStatus(HotkeySlot slot, string text, Color color, string detail)
        {
            Label status = slot == HotkeySlot.Capture ? _captureStatus : _replayStatus;
            status.Text = text;
            status.ForeColor = color;
            status.AccessibleDescription = detail;
            status.Tag = detail;
        }

        private void SaveButtonClick(object sender, EventArgs eventArgs)
        {
            if (_recordingSlot.HasValue)
            {
                SetCardStatus(_recordingSlot.Value, "先完成快捷键录入", ErrorColor);
                return;
            }

            if (_captureDraft.Equals(_replaySaveDraft))
            {
                HotkeySlot conflictingSlot = _captureDraft.Equals(_settings.CaptureHotkey)
                    ? HotkeySlot.ReplaySave
                    : HotkeySlot.Capture;
                string message = conflictingSlot == HotkeySlot.Capture
                    ? "与“保存即时回放”快捷键冲突。"
                    : "与“截图”快捷键冲突。";
                SetCardStatus(conflictingSlot, message, ErrorColor);
                return;
            }

            HotkeyWindowState previousHotkeyState = _hotkeyWindow.CaptureState();
            HotkeySlot failedSlot;
            string error;
            if (!_hotkeyWindow.TryApply(
                _captureDraft,
                _replaySaveDraft,
                _captureWasEdited,
                _replaySaveWasEdited,
                out failedSlot,
                out error))
            {
                string visibleError = error.IndexOf("占用", StringComparison.Ordinal) >= 0
                    ? "已被占用"
                    : error;
                SetCardStatus(failedSlot, visibleError, ErrorColor, error);
                return;
            }

            HotkeyGesture previousCapture = _settings.CaptureHotkey;
            HotkeyGesture previousReplaySave = _settings.ReplaySaveHotkey;
            _settings.CaptureHotkey = _captureDraft;
            _settings.ReplaySaveHotkey = _replaySaveDraft;
            try
            {
                _settings.Save();
            }
            catch (Exception exception)
            {
                _settings.CaptureHotkey = previousCapture;
                _settings.ReplaySaveHotkey = previousReplaySave;
                string rollbackError;
                bool restored = _hotkeyWindow.RestoreState(previousHotkeyState, out rollbackError);
                SetCardStatus(
                    HotkeySlot.Capture,
                    restored ? "保存失败，已恢复原快捷键" : "保存失败，请检查快捷键状态",
                    ErrorColor,
                    exception.Message + (restored ? "；已恢复原快捷键。" : "；" + rollbackError));
                return;
            }

            DialogResult = DialogResult.OK;
            Close();
        }

        private void CancelChanges()
        {
            DialogResult = DialogResult.Cancel;
            Close();
        }

        internal static GraphicsPath RoundedRectangle(Rectangle rectangle, int radius)
        {
            GraphicsPath path = new GraphicsPath();
            int diameter = Math.Max(1, radius * 2);
            Rectangle arc = new Rectangle(rectangle.Location, new Size(diameter, diameter));
            path.AddArc(arc, 180, 90);
            arc.X = rectangle.Right - diameter;
            path.AddArc(arc, 270, 90);
            arc.Y = rectangle.Bottom - diameter;
            path.AddArc(arc, 0, 90);
            arc.X = rectangle.Left;
            path.AddArc(arc, 90, 90);
            path.CloseFigure();
            return path;
        }
    }

    internal sealed class HotkeySettingsCard : Panel
    {
        internal HotkeySettingsCard()
        {
            BackColor = HotkeySettingsDialogColor.Background;
            SetStyle(
                ControlStyles.UserPaint |
                ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.ResizeRedraw,
                true);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle bounds = new Rectangle(0, 0, Width - 1, Height - 1);
            using (GraphicsPath shape = HotkeySettingsDialog.RoundedRectangle(bounds, 10))
            using (SolidBrush fill = new SolidBrush(HotkeySettingsDialogColor.Surface))
            using (Pen border = new Pen(HotkeySettingsDialogColor.Border))
            {
                e.Graphics.FillPath(fill, shape);
                e.Graphics.DrawPath(border, shape);
            }
        }
    }

    internal sealed class ShortcutPill : Control
    {
        private string _text = string.Empty;

        internal ShortcutPill()
        {
            ForeColor = Color.FromArgb(30, 41, 59);
            SetStyle(
                ControlStyles.UserPaint |
                ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.ResizeRedraw,
                true);
        }

        internal bool Recording { get; set; }

        public override string Text
        {
            get { return _text; }
            set
            {
                if (_text == value) return;
                _text = value ?? string.Empty;
                Invalidate();
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle bounds = new Rectangle(0, 0, Width - 1, Height - 1);
            Color fillColor = Recording ? HotkeySettingsDialogColor.AccentSoft : Color.FromArgb(243, 246, 249);
            Color borderColor = Recording ? HotkeySettingsDialogColor.Accent : HotkeySettingsDialogColor.Border;
            using (GraphicsPath shape = HotkeySettingsDialog.RoundedRectangle(bounds, Math.Max(5, Height / 2)))
            using (SolidBrush fill = new SolidBrush(fillColor))
            using (Pen border = new Pen(borderColor))
            {
                e.Graphics.FillPath(fill, shape);
                e.Graphics.DrawPath(border, shape);
            }
            TextRenderer.DrawText(
                e.Graphics,
                _text,
                Font,
                new Rectangle(Scale(5), 0, Math.Max(0, Width - Scale(10)), Height),
                ForeColor,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
        }

        private int Scale(int value)
        {
            return (value * DeviceDpi + 48) / 96;
        }
    }

    internal enum SettingsButtonStyle
    {
        Primary,
        Secondary,
        Tertiary
    }

    internal sealed class RoundedSettingsButton : Button
    {
        private readonly SettingsButtonStyle _style;
        private bool _hovered;
        private bool _pressed;

        internal RoundedSettingsButton(SettingsButtonStyle style)
        {
            _style = style;
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            UseVisualStyleBackColor = false;
            TabStop = true;
            SetStyle(
                ControlStyles.UserPaint |
                ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.ResizeRedraw,
                true);
        }

        protected override void OnMouseEnter(EventArgs e)
        {
            _hovered = true;
            Invalidate();
            base.OnMouseEnter(e);
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            _hovered = false;
            _pressed = false;
            Invalidate();
            base.OnMouseLeave(e);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left) _pressed = true;
            Invalidate();
            base.OnMouseDown(e);
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            _pressed = false;
            Invalidate();
            base.OnMouseUp(e);
        }

        protected override void OnGotFocus(EventArgs e)
        {
            Invalidate();
            base.OnGotFocus(e);
        }

        protected override void OnLostFocus(EventArgs e)
        {
            Invalidate();
            base.OnLostFocus(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle bounds = new Rectangle(0, 0, Width - 1, Height - 1);
            Color background = GetBackgroundColor();
            Color foreground = _style == SettingsButtonStyle.Primary
                ? Color.White
                : _style == SettingsButtonStyle.Tertiary
                    ? HotkeySettingsDialogColor.Accent
                    : HotkeySettingsDialogColor.Text;
            using (GraphicsPath shape = HotkeySettingsDialog.RoundedRectangle(bounds, 7))
            using (SolidBrush fill = new SolidBrush(background))
            using (Pen border = new Pen(_style == SettingsButtonStyle.Secondary
                ? HotkeySettingsDialogColor.Border
                : background))
            {
                e.Graphics.FillPath(fill, shape);
                if (_style == SettingsButtonStyle.Secondary)
                {
                    e.Graphics.DrawPath(border, shape);
                }
            }

            TextRenderer.DrawText(
                e.Graphics,
                Text,
                Font,
                bounds,
                foreground,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
            if (Focused && ShowFocusCues)
            {
                Rectangle focus = Rectangle.Inflate(bounds, -4, -4);
                ControlPaint.DrawFocusRectangle(e.Graphics, focus, foreground, background);
            }
        }

        private Color GetBackgroundColor()
        {
            if (_style == SettingsButtonStyle.Primary)
            {
                if (_pressed) return Color.FromArgb(30, 64, 175);
                if (_hovered) return Color.FromArgb(29, 78, 216);
                return HotkeySettingsDialogColor.Accent;
            }

            if (_style == SettingsButtonStyle.Tertiary)
            {
                if (_pressed) return Color.FromArgb(219, 234, 254);
                if (_hovered) return HotkeySettingsDialogColor.AccentSoft;
                return HotkeySettingsDialogColor.Background;
            }

            if (_pressed) return Color.FromArgb(226, 232, 240);
            if (_hovered) return Color.FromArgb(241, 245, 249);
            return Color.FromArgb(248, 250, 252);
        }
    }

    internal static class HotkeySettingsDialogColor
    {
        internal static readonly Color Background = TrayPopupForm.BackgroundColor;
        internal static readonly Color Surface = Color.White;
        internal static readonly Color Border = TrayPopupForm.BorderColor;
        internal static readonly Color Text = TrayPopupForm.TextColor;
        internal static readonly Color Muted = TrayPopupForm.SecondaryTextColor;
        internal static readonly Color Accent = TrayPopupForm.AccentColor;
        internal static readonly Color AccentSoft = TrayPopupForm.AccentSoftColor;
    }
}
