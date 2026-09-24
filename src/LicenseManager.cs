using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace BoltSnip
{
    internal static class LicenseManager
    {
        private static readonly string DirectoryPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BoltSnip");
        private static readonly string OwnerPath = Path.Combine(DirectoryPath, "owner.license");
        private static readonly string CustomerPath = Path.Combine(DirectoryPath, "customer.key");
        private static System.Threading.Timer _checkTimer;
        private static int _authorized;
        private static volatile bool _owner;

        internal static bool Enabled { get { return LicensingValues.Enabled; } }
        internal static bool IsAuthorized { get { return !Enabled || _owner || Interlocked.CompareExchange(ref _authorized, 0, 0) == 1; } }

        internal static bool EnsureAuthorized()
        {
            if (!Enabled) return true;
            bool validOwner = false;
            try { validOwner = File.Exists(OwnerPath) && IsValidOwnerFile(File.ReadAllText(OwnerPath)); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            if (validOwner)
            {
                _owner = true;
                Interlocked.Exchange(ref _authorized, 1);
                return true;
            }
            if (File.Exists(CustomerPath))
            {
                try
                {
                    if (Request("check", File.ReadAllText(CustomerPath).Trim()) == "OK")
                    {
                        StartCustomerChecks();
                        return true;
                    }
                }
                catch (Exception) { }
            }
            using (ActivationDialog dialog = new ActivationDialog())
                return dialog.ShowDialog() == DialogResult.OK;
        }

        internal static bool IsValidOwnerFile(string contents)
        {
            try
            {
                string[] parts = contents.Trim().Split('.');
                if (parts.Length != 3 || parts[0] != "BS1") return false;
                byte[] payload = Convert.FromBase64String(parts[1]);
                byte[] signature = Convert.FromBase64String(parts[2]);
                if (Encoding.UTF8.GetString(payload) != "BoltSnip|owner|1") return false;
                using (RSA rsa = RSA.Create())
                {
                    rsa.FromXmlString(LicensingValues.OwnerPublicKeyXml);
                    return rsa.VerifyData(payload, signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
                }
            }
            catch (Exception) { return false; }
        }

        internal static bool ImportOwnerFile(string path)
        {
            string contents = File.ReadAllText(path);
            if (!IsValidOwnerFile(contents)) return false;
            Directory.CreateDirectory(DirectoryPath);
            File.WriteAllText(OwnerPath, contents);
            _owner = true;
            Interlocked.Exchange(ref _authorized, 1);
            return true;
        }

        internal static string ActivateCustomer(string key)
        {
            key = key.Trim();
            string result = Request("activate", key);
            if (result == "OK")
            {
                Directory.CreateDirectory(DirectoryPath);
                File.WriteAllText(CustomerPath, key);
                StartCustomerChecks();
            }
            return result;
        }

        private static void StartCustomerChecks()
        {
            _owner = false;
            Interlocked.Exchange(ref _authorized, 1);
            if (_checkTimer == null)
                _checkTimer = new System.Threading.Timer(CheckCustomer, null, TimeSpan.FromMinutes(1), TimeSpan.FromMinutes(1));
        }

        private static void CheckCustomer(object state)
        {
            if (_owner) return;
            bool valid = false;
            try
            {
                valid = File.Exists(CustomerPath) &&
                    Request("check", File.ReadAllText(CustomerPath).Trim()) == "OK";
            }
            catch (Exception) { }
            Interlocked.Exchange(ref _authorized, valid ? 1 : 0);
        }

        private static string Request(string operation, string key)
        {
            if (string.IsNullOrWhiteSpace(key) || key.Length > 128) return "INVALID";
            string body = "key=" + Uri.EscapeDataString(key) +
                "&device=" + Uri.EscapeDataString(GetDeviceId());
            byte[] bytes = Encoding.ASCII.GetBytes(body);
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(LicensingValues.ServerUrl.TrimEnd('/') + "/" + operation);
            request.Method = "POST";
            request.ContentType = "application/x-www-form-urlencoded";
            request.ContentLength = bytes.Length;
            request.Timeout = 4000;
            request.ReadWriteTimeout = 4000;
            request.AllowAutoRedirect = false;
            using (Stream stream = request.GetRequestStream()) stream.Write(bytes, 0, bytes.Length);
            using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
            using (StreamReader reader = new StreamReader(response.GetResponseStream()))
                return reader.ReadToEnd().Trim();
        }

        private static string GetDeviceId()
        {
            using (RegistryKey key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Cryptography"))
            {
                string machineGuid = key == null ? null : key.GetValue("MachineGuid") as string;
                if (string.IsNullOrWhiteSpace(machineGuid))
                    throw new InvalidOperationException("无法读取此电脑的设备标识。");
                using (SHA256 sha = SHA256.Create())
                {
                    byte[] hash = sha.ComputeHash(Encoding.UTF8.GetBytes("BoltSnip|1|" + machineGuid));
                    return BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
                }
            }
        }
    }

    internal sealed class ActivationDialog : Form
    {
        private readonly TextBox _key;
        private readonly Label _status;
        private static readonly Color Surface = BoltSnipMenuStyle.SurfaceColor;
        private static readonly Color Ink = BoltSnipMenuStyle.TextColor;
        private static readonly Color Muted = BoltSnipMenuStyle.MutedTextColor;
        private static readonly Color Accent = BoltSnipMenuStyle.AccentColor;

        internal ActivationDialog()
        {
            Text = "BoltSnip · 激活";
            ClientSize = new Size(500, 388);
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            BackColor = Surface;
            ForeColor = Ink;
            Font = new Font("Microsoft YaHei UI", 9f, FontStyle.Regular, GraphicsUnit.Point);
            AutoScaleMode = AutoScaleMode.Font;

            ActivationMark mark = new ActivationMark { Location = new Point(26, 24), Size = new Size(44, 44) };
            Label title = new Label
            {
                Location = new Point(82, 22), Size = new Size(390, 31),
                Text = "开始使用 BoltSnip",
                Font = new Font(Font.FontFamily, 15f, FontStyle.Bold, GraphicsUnit.Point),
                ForeColor = Ink
            };
            Label subtitle = new Label
            {
                Location = new Point(83, 55), Size = new Size(390, 21),
                Text = "完成激活后，即可截图、复制与保存。",
                ForeColor = Muted
            };
            Panel headerRule = new Panel
            {
                Location = new Point(26, 91), Size = new Size(448, 1),
                BackColor = BoltSnipMenuStyle.DividerColor
            };

            Label onlineTitle = new Label
            {
                Location = new Point(28, 110), Size = new Size(170, 24),
                Text = "输入激活码",
                Font = new Font(Font.FontFamily, 10f, FontStyle.Bold, GraphicsUnit.Point),
                ForeColor = Ink
            };
            Label onlineHint = new Label
            {
                Location = new Point(350, 113), Size = new Size(122, 20),
                Text = "客户使用 · 需联网",
                TextAlign = ContentAlignment.MiddleRight,
                ForeColor = Muted
            };
            RoundedSurface keySurface = new RoundedSurface
            {
                Location = new Point(28, 143), Size = new Size(444, 40),
                BackColor = Color.White, CornerRadius = 10,
                BorderColor = Color.FromArgb(197, 212, 218)
            };
            _key = new TextBox
            {
                Location = new Point(14, 9), Size = new Size(416, 23),
                BorderStyle = BorderStyle.None,
                BackColor = Color.White, ForeColor = Ink,
                Font = new Font("Segoe UI", 11f, FontStyle.Regular, GraphicsUnit.Point)
            };
            keySurface.Controls.Add(_key);
            _key.GotFocus += delegate { keySurface.BorderColor = Accent; };
            _key.LostFocus += delegate { keySurface.BorderColor = Color.FromArgb(197, 212, 218); };
            _key.TextChanged += delegate { ShowStatus("换机后在新电脑输入原码，旧电脑会自动失效。", false); };
            Label bindingHint = new Label
            {
                Location = new Point(28, 196), Size = new Size(288, 21),
                Text = "同一时间仅限一台电脑使用",
                ForeColor = Muted
            };
            RoundedActionButton activate = new RoundedActionButton
            {
                Location = new Point(332, 186), Size = new Size(140, 38),
                Text = "联网激活", CornerRadius = 11,
                BackColor = Accent, HoverColor = Color.FromArgb(31, 165, 184),
                ForeColor = Color.White,
                Font = new Font(Font.FontFamily, 9.5f, FontStyle.Bold, GraphicsUnit.Point)
            };

            Panel leftRule = new Panel
            {
                Location = new Point(28, 250), Size = new Size(198, 1),
                BackColor = BoltSnipMenuStyle.DividerColor
            };
            Label alternative = new Label
            {
                Location = new Point(235, 239), Size = new Size(30, 24),
                Text = "或", TextAlign = ContentAlignment.MiddleCenter,
                ForeColor = Muted
            };
            Panel rightRule = new Panel
            {
                Location = new Point(274, 250), Size = new Size(198, 1),
                BackColor = BoltSnipMenuStyle.DividerColor
            };

            RoundedSurface offlineCard = new RoundedSurface
            {
                Location = new Point(28, 272), Size = new Size(444, 66),
                BackColor = Color.White, CornerRadius = 12,
                BorderColor = BoltSnipMenuStyle.DividerColor,
                AccentRail = true
            };
            Label offlineTitle = new Label
            {
                Location = new Point(16, 10), Size = new Size(218, 22),
                Text = "使用离线授权文件",
                Font = new Font(Font.FontFamily, 9.5f, FontStyle.Bold, GraphicsUnit.Point),
                ForeColor = Ink
            };
            Label offlineHint = new Label
            {
                Location = new Point(16, 35), Size = new Size(260, 20),
                Text = "已有授权文件时，直接导入即可",
                ForeColor = Muted
            };
            RoundedActionButton import = new RoundedActionButton
            {
                Location = new Point(307, 15), Size = new Size(122, 36),
                Text = "选择文件…", CornerRadius = 9,
                BackColor = Color.White, HoverColor = BoltSnipMenuStyle.HoverColor,
                BorderColor = Color.FromArgb(174, 216, 222),
                ForeColor = Color.FromArgb(20, 118, 132)
            };
            offlineCard.Controls.AddRange(new Control[] { offlineTitle, offlineHint, import });

            _status = new Label
            {
                Location = new Point(28, 352), Size = new Size(355, 22),
                ForeColor = Muted
            };
            RoundedActionButton cancel = new RoundedActionButton
            {
                Location = new Point(399, 347), Size = new Size(73, 31),
                Text = "稍后", DialogResult = DialogResult.Cancel,
                CornerRadius = 8, BackColor = Surface,
                HoverColor = BoltSnipMenuStyle.HoverColor, ForeColor = Muted
            };
            activate.Click += Activate;
            import.Click += Import;
            Controls.AddRange(new Control[]
            {
                mark, title, subtitle, headerRule, onlineTitle, onlineHint, keySurface,
                bindingHint, activate, leftRule, alternative, rightRule, offlineCard,
                _status, cancel
            });
            ShowStatus("换机后在新电脑输入原码，旧电脑会自动失效。", false);
            AcceptButton = activate;
            CancelButton = cancel;
            Shown += delegate { _key.Focus(); };
        }

        private void ShowStatus(string message, bool error)
        {
            _status.ForeColor = error ? Color.FromArgb(185, 65, 60) : Muted;
            _status.Text = message;
        }

        private void Activate(object sender, EventArgs e)
        {
            try
            {
                string result = LicenseManager.ActivateCustomer(_key.Text);
                if (result == "OK") { DialogResult = DialogResult.OK; Close(); return; }
                ShowStatus("激活码无效，请检查后重试。", true);
            }
            catch (Exception)
            {
                ShowStatus("无法连接激活服务，请检查网络后重试。", true);
            }
        }

        private void Import(object sender, EventArgs e)
        {
            using (OpenFileDialog picker = new OpenFileDialog())
            {
                picker.Filter = "BoltSnip 授权文件 (*.license)|*.license|所有文件 (*.*)|*.*";
                if (picker.ShowDialog(this) != DialogResult.OK) return;
                try
                {
                    if (LicenseManager.ImportOwnerFile(picker.FileName))
                    {
                        DialogResult = DialogResult.OK;
                        Close();
                    }
                    else ShowStatus("授权文件无效，请重新选择。", true);
                }
                catch (Exception) { ShowStatus("无法读取或保存授权文件，请重试。", true); }
            }
        }
    }

    internal sealed class ActivationMark : Control
    {
        internal ActivationMark()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.UserPaint, true);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath tile = BoltSnipMenuStyle.RoundedRectangle(
                new Rectangle(0, 0, Width - 1, Height - 1), 10))
            using (Brush background = new SolidBrush(BoltSnipMenuStyle.HoverColor))
            using (Pen crop = new Pen(BoltSnipMenuStyle.AccentColor, 2.5f))
            {
                crop.StartCap = LineCap.Round;
                crop.EndCap = LineCap.Round;
                e.Graphics.FillPath(background, tile);
                e.Graphics.DrawLines(crop, new[]
                {
                    new Point(12, 19), new Point(12, 12), new Point(19, 12)
                });
                e.Graphics.DrawLines(crop, new[]
                {
                    new Point(25, 12), new Point(32, 12), new Point(32, 19)
                });
                e.Graphics.DrawLines(crop, new[]
                {
                    new Point(12, 25), new Point(12, 32), new Point(19, 32)
                });
                e.Graphics.DrawLines(crop, new[]
                {
                    new Point(25, 32), new Point(32, 32), new Point(32, 25)
                });
            }
        }
    }

    internal sealed class RoundedSurface : Panel
    {
        private Color _borderColor = BoltSnipMenuStyle.DividerColor;
        private int _cornerRadius = 10;

        internal RoundedSurface()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.UserPaint, true);
        }

        internal int CornerRadius
        {
            get { return _cornerRadius; }
            set { _cornerRadius = value; UpdateRegion(); Invalidate(); }
        }

        internal Color BorderColor
        {
            get { return _borderColor; }
            set { _borderColor = value; Invalidate(); }
        }

        internal bool AccentRail { get; set; }

        protected override void OnSizeChanged(EventArgs e)
        {
            base.OnSizeChanged(e);
            UpdateRegion();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath outline = BoltSnipMenuStyle.RoundedRectangle(
                new Rectangle(0, 0, Width - 1, Height - 1), CornerRadius))
            using (Pen border = new Pen(BorderColor))
            {
                e.Graphics.DrawPath(border, outline);
            }
            if (AccentRail)
            {
                using (GraphicsPath rail = BoltSnipMenuStyle.RoundedRectangle(
                    new Rectangle(3, 13, 3, Height - 26), 2))
                using (Brush accent = new SolidBrush(BoltSnipMenuStyle.AccentColor))
                    e.Graphics.FillPath(accent, rail);
            }
        }

        private void UpdateRegion()
        {
            if (Width <= 0 || Height <= 0) return;
            using (GraphicsPath shape = BoltSnipMenuStyle.RoundedRectangle(
                new Rectangle(0, 0, Width, Height), CornerRadius))
            {
                Region previous = Region;
                Region = new Region(shape);
                if (previous != null) previous.Dispose();
            }
        }
    }

    internal sealed class RoundedActionButton : Button
    {
        private bool _hover;
        private bool _pressed;
        internal int CornerRadius { get; set; }
        internal Color HoverColor { get; set; }
        internal Color BorderColor { get; set; }

        internal RoundedActionButton()
        {
            CornerRadius = 10;
            HoverColor = BoltSnipMenuStyle.HoverColor;
            BorderColor = Color.Transparent;
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            UseVisualStyleBackColor = false;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.UserPaint, true);
        }

        protected override void OnMouseEnter(EventArgs e)
        {
            _hover = true;
            Invalidate();
            base.OnMouseEnter(e);
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            _hover = false;
            _pressed = false;
            Invalidate();
            base.OnMouseLeave(e);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            _pressed = true;
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
            base.OnGotFocus(e);
            Invalidate();
        }

        protected override void OnLostFocus(EventArgs e)
        {
            base.OnLostFocus(e);
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Color parent = Parent == null ? BoltSnipMenuStyle.SurfaceColor : Parent.BackColor;
            e.Graphics.Clear(parent);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (GraphicsPath shape = BoltSnipMenuStyle.RoundedRectangle(
                new Rectangle(0, 0, Width - 1, Height - 1), CornerRadius))
            using (Brush fill = new SolidBrush(_hover || _pressed ? HoverColor : BackColor))
            {
                e.Graphics.FillPath(fill, shape);
                if (BorderColor != Color.Transparent)
                {
                    using (Pen border = new Pen(BorderColor))
                        e.Graphics.DrawPath(border, shape);
                }
            }
            TextRenderer.DrawText(e.Graphics, Text, Font, ClientRectangle, ForeColor,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
                TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix);
            if (Focused && ShowFocusCues)
            {
                Rectangle focus = new Rectangle(4, 4, Width - 9, Height - 9);
                ControlPaint.DrawFocusRectangle(e.Graphics, focus, ForeColor, BackColor);
            }
        }
    }
}
