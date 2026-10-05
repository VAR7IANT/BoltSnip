using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace BoltSnip
{
    internal sealed class ActivationDialog : Form
    {
        private readonly List<Font> _fonts = new List<Font>();
        private readonly Label _title, _subtitle, _infoTitle, _infoHint, _methodCaption, _methodValue, _detailCaption, _onlineTitle, _onlineHint, _bindingHint, _offlineTitle, _offlineHint, _status;
        private readonly TextBox _key, _detail;
        private readonly HotkeySettingsCard _infoCard, _onlineCard, _offlineCard;
        private readonly AudioDeviceSurface _keyFrame;
        private readonly AudioSettingsButton _close, _cancel, _change, _revoke, _activate, _import;
        private readonly LicenseStatusMark _mark;
        private readonly bool _hasAuthorization;
        private bool _editing;
        private int _dpi = 96;
        private const float InterfaceScale = 1.30F;
        private static readonly string Typeface = ChooseTypeface();
        [DllImport("user32.dll")] private static extern bool ReleaseCapture();
        [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr hwnd, uint message, IntPtr wp, IntPtr lp);
        [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);

        internal ActivationDialog() : this(null, null, true) { }
        internal ActivationDialog(string method, string detail) : this(method, detail, false) { }
        private ActivationDialog(string method, string detail, bool loadCurrent)
        {
            if (loadCurrent) LicenseManager.TryGetAuthorizationInfo(out method, out detail);
            _hasAuthorization = !string.IsNullOrEmpty(method);
            _editing = !_hasAuthorization;
            Text = "BoltSnip · 授权管理";
            BackColor = HotkeySettingsDialogColor.Background;
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.CenterScreen;
            ShowInTaskbar = false;
            TopMost = true;
            AutoScaleMode = AutoScaleMode.None;
            DoubleBuffered = true;
            _title = Label("授权管理", false);
            _subtitle = Label("管理此设备的使用授权", true);
            _title.MouseDown += DragHeader; _subtitle.MouseDown += DragHeader;
            _close = Button("×", SettingsButtonStyle.Tertiary);
            _close.AccessibleName = "关闭授权管理";
            _close.DialogResult = DialogResult.Cancel;
            _cancel = Button("关闭", SettingsButtonStyle.Secondary);
            _cancel.DialogResult = DialogResult.Cancel;
            CancelButton = _cancel;

            _infoCard = new HotkeySettingsCard();
            _mark = new LicenseStatusMark();
            _infoTitle = Label("此设备已授权", false);
            _infoHint = Label("可以使用 BoltSnip 的全部功能", true);
            _methodCaption = Label("授权方式", true);
            _methodValue = Label(method ?? string.Empty, false);
            _detailCaption = Label(method == "离线授权文件" ? "授权文件" : "激活码", true);
            _detail = new TextBox { Text = detail ?? string.Empty, ReadOnly = true, BorderStyle = BorderStyle.None, BackColor = Color.White, ForeColor = HotkeySettingsDialogColor.Text, TabStop = false, AccessibleName = _detailCaption.Text };
            _infoCard.Controls.AddRange(new Control[] { _mark, _infoTitle, _infoHint, _methodCaption, _methodValue, _detailCaption, _detail });
            _change = Button("更换授权", SettingsButtonStyle.Primary);
            _change.Click += delegate { EnterEditor(); };
            _revoke = Button("取消授权", SettingsButtonStyle.Secondary);
            _revoke.Destructive = true;
            _revoke.Click += Revoke;

            _onlineCard = new HotkeySettingsCard();
            _onlineTitle = Label("输入激活码", false);
            _onlineHint = Label("联网验证后，授权将绑定此设备", true);
            _keyFrame = new AudioDeviceSurface();
            _key = new TextBox { BorderStyle = BorderStyle.None, BackColor = Color.White, ForeColor = HotkeySettingsDialogColor.Text, AccessibleName = "激活码", MaxLength = 128 };
            _keyFrame.Controls.Add(_key);
            _key.GotFocus += delegate { _keyFrame.Invalidate(); };
            _key.LostFocus += delegate { _keyFrame.Invalidate(); };
            _key.TextChanged += delegate { ShowStatus("换机时使用原码，旧电脑会自动失效。", false); };
            _bindingHint = Label("同一时间仅限一台电脑使用", true);
            _activate = Button("联网激活", SettingsButtonStyle.Primary);
            _activate.Click += ActivateLicense;
            _onlineCard.Controls.AddRange(new Control[] { _onlineTitle, _onlineHint, _keyFrame, _bindingHint, _activate });
            _offlineCard = new HotkeySettingsCard();
            _offlineTitle = Label("离线授权文件", false);
            _offlineHint = Label("已有授权文件时，直接导入即可", true);
            _import = Button("选择文件", SettingsButtonStyle.Secondary);
            _import.Click += Import;
            _offlineCard.Controls.AddRange(new Control[] { _offlineTitle, _offlineHint, _import });
            _status = Label(string.Empty, true);
            Controls.AddRange(new Control[] { _title, _subtitle, _close, _infoCard, _change, _revoke, _onlineCard, _offlineCard, _status, _cancel });
            ApplyDpi(96);
            UpdateMode();
        }
        private static Label Label(string text, bool muted)
        {
            return new Label { Text = text, ForeColor = muted ? HotkeySettingsDialogColor.Muted : HotkeySettingsDialogColor.Text, BackColor = Color.Transparent, TextAlign = ContentAlignment.MiddleLeft, UseMnemonic = false };
        }
        private static AudioSettingsButton Button(string text, SettingsButtonStyle style) { return new AudioSettingsButton(style) { Text = text }; }
        private static string ChooseTypeface()
        {
            try { using (FontFamily family = new FontFamily("YouYuan")) return family.Name; }
            catch (ArgumentException) { return "Microsoft YaHei UI"; }
        }
        private int Scale(int value) { return (int)Math.Round(value * _dpi * InterfaceScale / 96F); }
        private Font FontFor(float pixels, FontStyle style) { return FontFor(pixels, style, Typeface); }
        private Font FontFor(float pixels, FontStyle style, string typeface)
        {
            float size = pixels * _dpi * InterfaceScale / 96F;
            foreach (Font font in _fonts) if (font.Size == size && font.Style == style && font.FontFamily.Name == typeface) return font;
            Font created = new Font(typeface, size, style, GraphicsUnit.Pixel); _fonts.Add(created); return created;
        }
        private void Place(Control control, int x, int y, int width, int height) { control.SetBounds(Scale(x), Scale(y), Scale(width), Scale(height)); }
        private void ApplyDpi(int dpi)
        {
            _dpi = dpi > 0 ? dpi : 96;
            SuspendLayout();
            Font body = FontFor(14F, FontStyle.Regular), small = FontFor(13F, FontStyle.Regular), bold = FontFor(14.5F, FontStyle.Regular);
            Font = body;
            _title.Font = FontFor(21F, FontStyle.Regular);
            _subtitle.Font = _infoHint.Font = _onlineHint.Font = _offlineHint.Font = _bindingHint.Font = _status.Font = small;
            _infoTitle.Font = FontFor(16F, FontStyle.Regular);
            _methodCaption.Font = _detailCaption.Font = _methodValue.Font = body;
            _detail.Font = _key.Font = FontFor(14F, FontStyle.Regular, "Arial Rounded MT Bold");
            _onlineTitle.Font = _offlineTitle.Font = bold;
            _change.Font = _revoke.Font = _activate.Font = _import.Font = _cancel.Font = body;
            _close.Font = FontFor(18F, FontStyle.Regular);
            ClientSize = new Size(Scale(424), Scale(_editing ? 440 : 344));
            Place(_title, 24, 18, 310, 28); Place(_subtitle, 25, 50, 360, 22); Place(_close, 368, 18, 30, 30);
            Place(_infoCard, 24, 86, 376, 152);
            Place(_mark, 18, 16, 32, 32); Place(_infoTitle, 62, 12, 294, 25); Place(_infoHint, 62, 38, 294, 20);
            Place(_methodCaption, 18, 77, 86, 24); Place(_methodValue, 112, 77, 244, 24);
            Place(_detailCaption, 18, 111, 86, 24); Place(_detail, 112, 115, 244, 24);
            Place(_change, 24, 292, 104, 32); Place(_revoke, 140, 292, 104, 32);
            Place(_onlineCard, 24, 86, 376, 176);
            Place(_onlineTitle, 18, 12, 340, 24); Place(_onlineHint, 18, 38, 340, 21);
            Place(_keyFrame, 18, 66, 340, 38); Place(_key, 12, 10, 316, 24);
            Place(_bindingHint, 18, 116, 225, 38); Place(_activate, 250, 118, 90, 32);
            Place(_offlineCard, 24, 274, 376, 86); Place(_offlineTitle, 18, 12, 222, 24); Place(_offlineHint, 18, 38, 222, 32); Place(_import, 250, 26, 90, 32);
            Place(_status, 25, _editing ? 369 : 247, _editing ? 266 : 374, _editing ? 50 : 27);
            Place(_cancel, 310, _editing ? 392 : 292, 90, 32);
            Region old = Region;
            using (GraphicsPath shape = HotkeySettingsDialog.RoundedRectangle(new Rectangle(0, 0, Width, Height), Scale(14))) Region = new Region(shape);
            if (old != null) old.Dispose();
            ResumeLayout(false); Invalidate(true);
        }
        private void UpdateMode()
        {
            _infoCard.Visible = _change.Visible = _revoke.Visible = !_editing;
            _onlineCard.Visible = _offlineCard.Visible = _editing;
            _title.Text = _editing ? (_hasAuthorization ? "更换授权" : "激活 BoltSnip") : "授权管理";
            _subtitle.Text = _editing ? "输入激活码，或导入已有授权文件" : "管理此设备的使用授权";
            AcceptButton = _editing ? _activate : _change;
            ShowStatus(_editing ? "换机时使用原码，旧电脑会自动失效。" : "更换授权后，将使用新凭据验证此设备。", false);
        }
        private void EnterEditor()
        {
            Point center = new Point(Left + Width / 2, Top + Height / 2);
            _editing = true; ApplyDpi(_dpi); UpdateMode();
            if (Visible) { Location = new Point(center.X - Width / 2, center.Y - Height / 2); _key.Focus(); }
        }
        protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); ApplyDpi(DeviceDpi); }
        protected override void OnDpiChanged(DpiChangedEventArgs e) { base.OnDpiChanged(e); ApplyDpi(e.DeviceDpiNew); }
        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            SetWindowPos(Handle, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);
            if ((NativeMethods.GetWindowLong(Handle, NativeMethods.GWL_EXSTYLE) & 0x08000000) == 0)
                NativeMethods.SetForegroundWindow(Handle);
            Activate();
            if (_editing) _key.Focus(); else _change.Focus();
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e); e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath shape = HotkeySettingsDialog.RoundedRectangle(new Rectangle(0, 0, Width - 1, Height - 1), Scale(14)))
            using (Pen border = new Pen(HotkeySettingsDialogColor.Border)) e.Graphics.DrawPath(border, shape);
        }
        protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); if (e.Y < Scale(78)) DragHeader(this, e); }
        private void DragHeader(object sender, MouseEventArgs e) { if (e.Button != MouseButtons.Left) return; ReleaseCapture(); SendMessage(Handle, 0x00A1, new IntPtr(2), IntPtr.Zero); }
        private void ShowStatus(string message, bool error) { _status.Text = message; _status.ForeColor = error ? Color.FromArgb(175, 60, 60) : HotkeySettingsDialogColor.Muted; }
        private void ActivateLicense(object sender, EventArgs e)
        {
            try { if (LicenseManager.ActivateCustomer(_key.Text) == "OK") { DialogResult = DialogResult.OK; Close(); } else ShowStatus("激活码无效，请检查后重试。", true); }
            catch (Exception) { ShowStatus("无法连接激活服务，请检查网络后重试。", true); }
        }
        private void Import(object sender, EventArgs e)
        {
            using (OpenFileDialog picker = new OpenFileDialog())
            {
                picker.Filter = "BoltSnip 授权文件 (*.license)|*.license|所有文件 (*.*)|*.*";
                if (picker.ShowDialog(this) != DialogResult.OK) return;
                try { if (LicenseManager.ImportOwnerFile(picker.FileName)) { DialogResult = DialogResult.OK; Close(); } else ShowStatus("授权文件无效，请重新选择。", true); }
                catch (Exception) { ShowStatus("无法读取或保存授权文件，请重试。", true); }
            }
        }
        private void Revoke(object sender, EventArgs e)
        {
            using (AuthorizationCancellationDialog confirmation = new AuthorizationCancellationDialog()) if (confirmation.ShowDialog(this) != DialogResult.Yes) return;
            try { LicenseManager.CancelAuthorization(); EnterEditor(); ShowStatus("已取消本机授权。凭据已备份，可重新激活。", false); }
            catch (Exception) { ShowStatus("无法取消授权，请检查授权文件的访问权限。", true); }
        }
        protected override void Dispose(bool disposing) { base.Dispose(disposing); if (disposing) { foreach (Font font in _fonts) font.Dispose(); _fonts.Clear(); } }
    }

    internal sealed class LicenseStatusMark : Control
    {
        internal LicenseStatusMark() { SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true); BackColor = Color.White; }
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(BackColor); e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            float s = Width / 32F;
            using (GraphicsPath shape = HotkeySettingsDialog.RoundedRectangle(new Rectangle(0, 0, Width - 1, Height - 1), Math.Max(5, Width / 4)))
            using (Brush background = new SolidBrush(HotkeySettingsDialogColor.AccentSoft))
            using (Pen line = new Pen(HotkeySettingsDialogColor.Accent, 1.8F * s))
            {
                line.StartCap = line.EndCap = LineCap.Round;
                e.Graphics.FillPath(background, shape);
                e.Graphics.DrawLines(line, new PointF[] { new PointF(16*s,7*s),new PointF(24*s,10*s),new PointF(23*s,20*s),new PointF(16*s,25*s),new PointF(9*s,20*s),new PointF(8*s,10*s),new PointF(16*s,7*s) });
                e.Graphics.DrawLines(line, new PointF[] { new PointF(12*s,16*s),new PointF(15*s,19*s),new PointF(20*s,13*s) });
            }
        }
    }
}