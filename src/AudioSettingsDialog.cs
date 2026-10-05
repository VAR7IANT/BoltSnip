using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace BoltSnip
{
    internal sealed class AudioSettingsDialog : Form
    {
        private readonly AppSettings _settings;
        private readonly List<Font> _ownedFonts = new List<Font>();
        private readonly Label _title, _subtitle, _gameTitle, _gameDescription, _gameState, _micTitle, _micDescription;
        private readonly HotkeySettingsCard _gameCard, _micCard;
        private readonly AudioDeviceSurface _deviceFrame;
        private readonly CheckBox _enabled;
        private readonly ComboBox _devices;
        private readonly AudioVolumeSlider _volume;
        private readonly Label _volumeLabel, _volumeText, _status;
        private readonly AudioSettingsButton _close, _cancel, _save;
        private int _dpi = 96;
        [DllImport("user32.dll")] private static extern bool ReleaseCapture();
        [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wparam, IntPtr lparam);

        internal AudioSettingsDialog(AppSettings settings)
        {
            _settings = settings;
            Text = "录制声音";
            BackColor = HotkeySettingsDialogColor.Background;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.CenterScreen;
            TopMost = true;
            AutoScaleMode = AutoScaleMode.None;
            DoubleBuffered = true;
            _title = Label("录制声音", HotkeySettingsDialogColor.Text);
            _subtitle = Label("让回放保留游戏声与自己的声音", HotkeySettingsDialogColor.Muted);
            _title.MouseDown += DragHeader;
            _subtitle.MouseDown += DragHeader;
            _close = Button("×", SettingsButtonStyle.Tertiary);
            _close.AccessibleName = "关闭录制声音设置";
            _close.DialogResult = DialogResult.Cancel;
            _gameCard = new HotkeySettingsCard();
            _gameTitle = Label("游戏与系统声音", HotkeySettingsDialogColor.Text);
            _gameDescription = Label("沿用当前的回放录制设置", HotkeySettingsDialogColor.Muted);
            _gameState = Label("跟随回放", HotkeySettingsDialogColor.Accent);
            _gameState.TextAlign = ContentAlignment.MiddleRight;
            _gameCard.Controls.AddRange(new Control[] { _gameTitle, _gameDescription, _gameState });
            _micCard = new HotkeySettingsCard();
            _micTitle = Label("麦克风", HotkeySettingsDialogColor.Text);
            _micDescription = Label(string.Empty, HotkeySettingsDialogColor.Muted);
            _enabled = new AudioToggle { Checked = settings.RecordMicrophone, AccessibleName = "同时录制麦克风", TabIndex = 0 };
            _devices = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, FlatStyle = FlatStyle.Flat, DrawMode = DrawMode.OwnerDrawFixed, BackColor = Color.White, AccessibleName = "录制麦克风设备", TabIndex = 1, DropDownWidth = 340, MaxDropDownItems = 8 };
            _deviceFrame = new AudioDeviceSurface();
            _deviceFrame.Controls.Add(_devices);
            _devices.GotFocus += delegate { _deviceFrame.Invalidate(); };
            _devices.LostFocus += delegate { _deviceFrame.Invalidate(); };
            _devices.DrawItem += DrawDevice;
            foreach (MicrophoneDevice device in MicrophoneDevices.List()) _devices.Items.Add(device);
            _devices.SelectedIndex = 0;
            for (int index = 0; index < _devices.Items.Count; index++) if (((MicrophoneDevice)_devices.Items[index]).Id == settings.MicrophoneDeviceId) _devices.SelectedIndex = index;
            if (!string.IsNullOrEmpty(settings.MicrophoneDeviceId) && ((MicrophoneDevice)_devices.SelectedItem).Id != settings.MicrophoneDeviceId)
            {
                _devices.Items.Add(new MicrophoneDevice(settings.MicrophoneDeviceId, "先前选择的麦克风（当前不可用）"));
                _devices.SelectedIndex = _devices.Items.Count - 1;
            }
            _volumeLabel = Label("麦克风音量", HotkeySettingsDialogColor.Text);
            _volumeText = Label(string.Empty, HotkeySettingsDialogColor.Accent);
            _volumeText.TextAlign = ContentAlignment.MiddleRight;
            _volume = new AudioVolumeSlider { Value = Math.Max(0, Math.Min(200, settings.MicrophoneVolume)), AccessibleName = "麦克风音量", TabIndex = 2 };
            _micCard.Controls.AddRange(new Control[] { _micTitle, _micDescription, _enabled, _deviceFrame, _volumeLabel, _volumeText, _volume });
            _status = Label("保存后，下次开启回放时生效。", HotkeySettingsDialogColor.Muted);
            _cancel = Button("取消", SettingsButtonStyle.Secondary);
            _cancel.DialogResult = DialogResult.Cancel;
            _save = Button("保存设置", SettingsButtonStyle.Primary);
            _save.Click += SaveClicked;
            _enabled.CheckedChanged += delegate { UpdateEnabled(); };
            _volume.ValueChanged += delegate { UpdateEnabled(); };
            Controls.AddRange(new Control[] { _title, _subtitle, _close, _gameCard, _micCard, _status, _cancel, _save });
            AcceptButton = _save;
            CancelButton = _cancel;
            ApplyDpi(96);
            UpdateEnabled();
        }

        private static Label Label(string text, Color color)
        {
            return new Label { Text = text, ForeColor = color, BackColor = Color.Transparent, AutoSize = false, TextAlign = ContentAlignment.MiddleLeft, UseMnemonic = false };
        }
        private static AudioSettingsButton Button(string text, SettingsButtonStyle style)
        {
            return new AudioSettingsButton(style) { Text = text };
        }
        private Font OwnFont(float pixels, FontStyle style)
        {
            float size = pixels * _dpi / 96F;
            foreach (Font cached in _ownedFonts) { if (cached.Size == size && cached.Style == style) return cached; }
            Font font = new Font("Microsoft YaHei UI", size, style, GraphicsUnit.Pixel);
            _ownedFonts.Add(font);
            return font;
        }
        private void BoundsFor(Control control, int x, int y, int width, int height)
        {
            control.SetBounds(Scale(x), Scale(y), Scale(width), Scale(height));
        }
        private int Scale(int value) { return (value * _dpi + 48) / 96; }
        private void ApplyDpi(int dpi)
        {
            _dpi = dpi > 0 ? dpi : 96;
            SuspendLayout();
            Font body = OwnFont(12.5F, FontStyle.Regular);
            Font small = OwnFont(11.5F, FontStyle.Regular);
            Font medium = OwnFont(13F, FontStyle.Bold);
            Font heading = OwnFont(18F, FontStyle.Bold);
            Font closeFont = OwnFont(18F, FontStyle.Regular);
            Font = body;
            _title.Font = heading;
            _subtitle.Font = _gameDescription.Font = _micDescription.Font = _status.Font = small;
            _gameTitle.Font = _micTitle.Font = medium;
            _gameState.Font = _devices.Font = _volumeLabel.Font = _volumeText.Font = _cancel.Font = _save.Font = body;
            _close.Font = closeFont;
            ClientSize = new Size(Scale(424), Scale(400));
            BoundsFor(_title, 24, 18, 310, 28);
            BoundsFor(_subtitle, 25, 50, 360, 22);
            BoundsFor(_close, 368, 18, 30, 30);
            BoundsFor(_gameCard, 24, 86, 376, 50);
            BoundsFor(_gameTitle, 18, 8, 230, 21);
            BoundsFor(_gameDescription, 18, 27, 246, 17);
            BoundsFor(_gameState, 272, 13, 86, 22);
            BoundsFor(_micCard, 24, 148, 376, 164);
            BoundsFor(_micTitle, 18, 10, 240, 23);
            BoundsFor(_micDescription, 18, 34, 276, 18);
            BoundsFor(_enabled, 314, 14, 44, 24);
            BoundsFor(_deviceFrame, 18, 62, 340, 44);
            BoundsFor(_devices, 6, 3, 328, 24);
            _devices.ItemHeight = Scale(30);
            _devices.Top = Math.Max(Scale(2), (_deviceFrame.Height - _devices.Height) / 2);
            _devices.DropDownWidth = _deviceFrame.Width;
            BoundsFor(_volumeLabel, 18, 111, 248, 22);
            BoundsFor(_volumeText, 274, 111, 84, 22);
            BoundsFor(_volume, 18, 135, 340, 22);
            BoundsFor(_status, 25, 324, 374, 24);
            BoundsFor(_cancel, 216, 352, 82, 32);
            BoundsFor(_save, 310, 352, 90, 32);
            Region previous = Region;
            using (GraphicsPath shape = HotkeySettingsDialog.RoundedRectangle(new Rectangle(0, 0, Width, Height), Scale(14))) Region = new Region(shape);
            if (previous != null) previous.Dispose();
            ResumeLayout(false);
            Invalidate(true);
        }
        protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); ApplyDpi(DeviceDpi); }
        protected override void OnDpiChanged(DpiChangedEventArgs e) { base.OnDpiChanged(e); ApplyDpi(e.DeviceDpiNew); }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath shape = HotkeySettingsDialog.RoundedRectangle(new Rectangle(0, 0, Width - 1, Height - 1), Scale(14)))
            using (Pen border = new Pen(HotkeySettingsDialogColor.Border)) e.Graphics.DrawPath(border, shape);
        }
        protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); if (e.Y < Scale(78)) DragHeader(this, e); }
        private void DragHeader(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) return;
            ReleaseCapture();
            SendMessage(Handle, 0x00A1, new IntPtr(2), IntPtr.Zero);
        }
        private void DrawDevice(object sender, DrawItemEventArgs e)
        {
            if (e.Index < 0 || e.Index >= _devices.Items.Count) return;
            bool collapsed = (e.State & DrawItemState.ComboBoxEdit) != 0;
            bool highlighted = !collapsed && (e.State & DrawItemState.Selected) != 0;
            bool selected = e.Index == _devices.SelectedIndex;
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (Brush background = new SolidBrush(Color.White)) e.Graphics.FillRectangle(background, e.Bounds);
            if (highlighted)
            {
                Rectangle row = new Rectangle(e.Bounds.Left + Scale(4), e.Bounds.Top + Scale(2), e.Bounds.Width - Scale(8), e.Bounds.Height - Scale(4));
                using (GraphicsPath shape = HotkeySettingsDialog.RoundedRectangle(row, Scale(6)))
                using (Brush fill = new SolidBrush(HotkeySettingsDialogColor.AccentSoft)) e.Graphics.FillPath(fill, shape);
            }
            Color color = !_devices.Enabled ? Color.FromArgb(145, 156, 166) : highlighted ? HotkeySettingsDialogColor.Accent : HotkeySettingsDialogColor.Text;
            Rectangle text = new Rectangle(e.Bounds.Left + Scale(12), e.Bounds.Top, e.Bounds.Width - Scale(collapsed ? 24 : 46), e.Bounds.Height);
            TextRenderer.DrawText(e.Graphics, _devices.Items[e.Index].ToString(), _devices.Font, text, color, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            if (!collapsed && selected)
            {
                float x = e.Bounds.Right - Scale(25), y = e.Bounds.Top + e.Bounds.Height / 2F;
                using (Pen check = new Pen(HotkeySettingsDialogColor.Accent, Math.Max(1.5F, _dpi / 48F)))
                {
                    check.StartCap = check.EndCap = LineCap.Round;
                    e.Graphics.DrawLines(check, new PointF[] { new PointF(x, y), new PointF(x + Scale(3), y + Scale(3)), new PointF(x + Scale(9), y - Scale(4)) });
                }
            }
        }
        private void UpdateEnabled()
        {
            _devices.Enabled = _volume.Enabled = _enabled.Checked;
            _volumeText.Text = _volume.Value + "%";
            _volumeText.ForeColor = _enabled.Checked ? HotkeySettingsDialogColor.Accent : HotkeySettingsDialogColor.Muted;
            _micDescription.Text = _enabled.Checked ? "开启后，回放会持续收录你的声音" : "关闭时仅保存游戏与系统声音";
        }
        private void SaveClicked(object sender, EventArgs e)
        {
            bool previousEnabled = _settings.RecordMicrophone;
            string previousDevice = _settings.MicrophoneDeviceId;
            int previousVolume = _settings.MicrophoneVolume;
            try
            {
                _settings.RecordMicrophone = _enabled.Checked;
                _settings.MicrophoneDeviceId = ((MicrophoneDevice)_devices.SelectedItem).Id;
                _settings.MicrophoneVolume = _volume.Value;
                _settings.Save();
                DialogResult = DialogResult.OK;
                Close();
            }
            catch (Exception error)
            {
                _settings.RecordMicrophone = previousEnabled;
                _settings.MicrophoneDeviceId = previousDevice;
                _settings.MicrophoneVolume = previousVolume;
                _status.Text = "保存失败：" + error.Message;
                _status.ForeColor = Color.FromArgb(175, 60, 60);
            }
        }
        protected override void Dispose(bool disposing)
        {
            base.Dispose(disposing);
            if (disposing) { foreach (Font font in _ownedFonts) font.Dispose(); _ownedFonts.Clear(); }
        }
    }

    internal sealed class AudioDeviceSurface : Panel
    {
        internal AudioDeviceSurface()
        {
            BackColor = Color.White;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath shape = HotkeySettingsDialog.RoundedRectangle(new Rectangle(0, 0, Width - 1, Height - 1), Math.Max(5, Height / 4)))
            using (Pen border = new Pen(ContainsFocus ? HotkeySettingsDialogColor.Accent : HotkeySettingsDialogColor.Border)) e.Graphics.DrawPath(border, shape);
        }
    }

    internal sealed class AudioSettingsButton : Button
    {
        private readonly SettingsButtonStyle _style;
        private bool _hovered, _pressed;
        internal bool Destructive { get; set; }
        internal AudioSettingsButton(SettingsButtonStyle style)
        {
            _style = style;
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            UseVisualStyleBackColor = false;
            Cursor = Cursors.Hand;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        }
        protected override void OnMouseEnter(EventArgs e) { _hovered = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hovered = _pressed = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left) _pressed = true; Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { _pressed = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(Parent == null ? HotkeySettingsDialogColor.Background : Parent.BackColor);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Color fill = _style == SettingsButtonStyle.Primary ? (_pressed ? Color.FromArgb(30, 64, 175) : _hovered ? Color.FromArgb(29, 78, 216) : HotkeySettingsDialogColor.Accent)
                : _hovered ? (Destructive ? Color.FromArgb(253, 240, 239) : HotkeySettingsDialogColor.AccentSoft) : HotkeySettingsDialogColor.Background;
            Color text = _style == SettingsButtonStyle.Primary ? Color.White : _style == SettingsButtonStyle.Tertiary ? HotkeySettingsDialogColor.Accent : Destructive ? Color.FromArgb(175, 60, 60) : HotkeySettingsDialogColor.Text;
            Rectangle bounds = new Rectangle(0, 0, Width - 1, Height - 1);
            using (GraphicsPath shape = HotkeySettingsDialog.RoundedRectangle(bounds, Math.Max(5, Height / 4)))
            using (Brush brush = new SolidBrush(fill))
            using (Pen border = new Pen(_style == SettingsButtonStyle.Secondary ? HotkeySettingsDialogColor.Border : fill))
            {
                e.Graphics.FillPath(brush, shape);
                e.Graphics.DrawPath(border, shape);
            }
            TextRenderer.DrawText(e.Graphics, Text, Font, bounds, text, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
            if (Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(bounds, -5, -5), text, fill);
        }
    }

    internal sealed class AudioToggle : CheckBox
    {
        internal AudioToggle()
        {
            AutoSize = false;
            Text = string.Empty;
            BackColor = Color.White;
            Cursor = Cursors.Hand;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        }
        protected override void OnCheckedChanged(EventArgs e) { base.OnCheckedChanged(e); Invalidate(); }
        protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
        protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(BackColor);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            float scale = Height / 24F;
            Rectangle track = new Rectangle(1, 1, Width - 2, Height - 2);
            using (GraphicsPath shape = HotkeySettingsDialog.RoundedRectangle(track, (Height - 2) / 2))
            using (Brush fill = new SolidBrush(Checked ? HotkeySettingsDialogColor.Accent : Color.FromArgb(219, 227, 235))) e.Graphics.FillPath(fill, shape);
            float diameter = 16 * scale;
            float left = Checked ? Width - diameter - 4 * scale : 4 * scale;
            using (Brush thumb = new SolidBrush(Color.White)) e.Graphics.FillEllipse(thumb, left, (Height - diameter) / 2, diameter, diameter);
            if (Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle, -1, -1));
        }
    }

    internal sealed class AudioVolumeSlider : Control
    {
        private int _value;
        private bool _dragging;
        internal event EventHandler ValueChanged;
        internal int Value
        {
            get { return _value; }
            set { int next = Math.Max(0, Math.Min(200, value)); if (next == _value) return; _value = next; Invalidate(); if (ValueChanged != null) ValueChanged(this, EventArgs.Empty); }
        }
        internal AudioVolumeSlider()
        {
            BackColor = Color.White;
            TabStop = true;
            Cursor = Cursors.Hand;
            AccessibleRole = AccessibleRole.Slider;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
        }
        protected override bool IsInputKey(Keys keyData) { Keys key = keyData & Keys.KeyCode; return key == Keys.Left || key == Keys.Right || key == Keys.Home || key == Keys.End || base.IsInputKey(keyData); }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Left) Value -= e.Shift ? 1 : 5;
            else if (e.KeyCode == Keys.Right) Value += e.Shift ? 1 : 5;
            else if (e.KeyCode == Keys.Home) Value = 0;
            else if (e.KeyCode == Keys.End) Value = 200;
            else { base.OnKeyDown(e); return; }
            e.Handled = true;
        }
        private void UpdateValue(int x) { float padding = Height * 0.32F; Value = (int)Math.Round((x - padding) * 200 / Math.Max(1, Width - padding * 2)); }
        protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); if (e.Button == MouseButtons.Left) { Focus(); _dragging = true; Capture = true; UpdateValue(e.X); } }
        protected override void OnMouseMove(MouseEventArgs e) { base.OnMouseMove(e); if (_dragging) UpdateValue(e.X); }
        protected override void OnMouseUp(MouseEventArgs e) { base.OnMouseUp(e); _dragging = false; Capture = false; }
        protected override void OnMouseCaptureChanged(EventArgs e) { base.OnMouseCaptureChanged(e); if (!Capture) _dragging = false; }
        protected override void OnMouseWheel(MouseEventArgs e) { base.OnMouseWheel(e); Value += Math.Sign(e.Delta) * 5; }
        protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
        protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(BackColor);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            float scale = Height / 22F, padding = 7 * scale, y = Height / 2F;
            float x = padding + (Width - padding * 2) * Value / 200F;
            Color accent = Enabled ? HotkeySettingsDialogColor.Accent : Color.FromArgb(178, 190, 202);
            using (Pen track = new Pen(Color.FromArgb(227, 233, 240), 4 * scale))
            using (Pen progress = new Pen(accent, 4 * scale))
            using (Brush thumb = new SolidBrush(Color.White))
            using (Pen outline = new Pen(accent, 2 * scale))
            {
                track.StartCap = track.EndCap = progress.StartCap = progress.EndCap = LineCap.Round;
                e.Graphics.DrawLine(track, padding, y, Width - padding, y);
                if (Value > 0) e.Graphics.DrawLine(progress, padding, y, x, y);
                e.Graphics.FillEllipse(thumb, x - 6 * scale, y - 6 * scale, 12 * scale, 12 * scale);
                e.Graphics.DrawEllipse(outline, x - 6 * scale, y - 6 * scale, 12 * scale, 12 * scale);
            }
            if (Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle, -1, -1));
        }
    }
}