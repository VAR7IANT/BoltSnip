using System;
using System.Drawing;
using System.Windows.Forms;

namespace BoltSnip
{
    internal sealed class HotkeySettingsDialog : Form
    {
        private readonly TextBox _hotkeyInput;
        private readonly Label _statusLabel;
        private HotkeyGesture _selectedGesture;

        internal HotkeySettingsDialog(HotkeyGesture currentGesture)
        {
            _selectedGesture = currentGesture;

            Text = "设置截图快捷键";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(400, 218);
            BackColor = Color.FromArgb(246, 248, 250);
            Font = new Font("Microsoft YaHei UI", 9f, FontStyle.Regular, GraphicsUnit.Point);

            Label title = new Label();
            title.AutoSize = true;
            title.Location = new Point(24, 21);
            title.Font = new Font(Font.FontFamily, 12f, FontStyle.Bold, GraphicsUnit.Point);
            title.ForeColor = Color.FromArgb(30, 36, 42);
            title.Text = "按下新的组合键";
            Controls.Add(title);

            Label description = new Label();
            description.AutoSize = true;
            description.Location = new Point(25, 52);
            description.ForeColor = Color.FromArgb(96, 104, 112);
            description.Text = "需要包含 Ctrl、Alt 或 Shift，保存后立即生效。";
            Controls.Add(description);

            _hotkeyInput = new TextBox();
            _hotkeyInput.Location = new Point(24, 82);
            _hotkeyInput.Size = new Size(352, 42);
            _hotkeyInput.ReadOnly = true;
            _hotkeyInput.ShortcutsEnabled = false;
            _hotkeyInput.BackColor = Color.White;
            _hotkeyInput.ForeColor = Color.FromArgb(20, 118, 132);
            _hotkeyInput.BorderStyle = BorderStyle.FixedSingle;
            _hotkeyInput.TextAlign = HorizontalAlignment.Center;
            _hotkeyInput.Font = new Font("Segoe UI", 16f, FontStyle.Bold, GraphicsUnit.Point);
            _hotkeyInput.Text = currentGesture.DisplayText;
            _hotkeyInput.KeyDown += HotkeyInputKeyDown;
            Controls.Add(_hotkeyInput);

            _statusLabel = new Label();
            _statusLabel.Location = new Point(25, 130);
            _statusLabel.Size = new Size(350, 22);
            _statusLabel.ForeColor = Color.FromArgb(112, 120, 128);
            _statusLabel.Text = "点击上方输入框，然后按下组合键";
            Controls.Add(_statusLabel);

            Button saveButton = new Button();
            saveButton.Location = new Point(245, 169);
            saveButton.Size = new Size(131, 34);
            saveButton.Text = "保存并启用";
            saveButton.FlatStyle = FlatStyle.Flat;
            saveButton.FlatAppearance.BorderSize = 0;
            saveButton.BackColor = Color.FromArgb(52, 190, 208);
            saveButton.ForeColor = Color.White;
            saveButton.Click += SaveButtonClick;
            Controls.Add(saveButton);

            Button cancelButton = new Button();
            cancelButton.Location = new Point(154, 169);
            cancelButton.Size = new Size(82, 34);
            cancelButton.Text = "取消";
            cancelButton.DialogResult = DialogResult.Cancel;
            cancelButton.FlatStyle = FlatStyle.Flat;
            cancelButton.FlatAppearance.BorderColor = Color.FromArgb(208, 214, 220);
            cancelButton.BackColor = Color.White;
            Controls.Add(cancelButton);

            AcceptButton = saveButton;
            CancelButton = cancelButton;
            Shown += delegate { _hotkeyInput.Focus(); _hotkeyInput.SelectAll(); };
        }

        internal HotkeyGesture SelectedGesture
        {
            get { return _selectedGesture; }
        }

        private void HotkeyInputKeyDown(object sender, KeyEventArgs eventArgs)
        {
            eventArgs.Handled = true;
            eventArgs.SuppressKeyPress = true;

            if (!eventArgs.Control && !eventArgs.Alt && !eventArgs.Shift)
            {
                if (eventArgs.KeyCode == Keys.Escape)
                {
                    DialogResult = DialogResult.Cancel;
                    Close();
                    return;
                }

                if (eventArgs.KeyCode == Keys.Enter)
                {
                    SaveButtonClick(this, EventArgs.Empty);
                    return;
                }
            }

            HotkeyGesture gesture;
            string error;
            if (!HotkeyGesture.TryFromKeyEvent(eventArgs, out gesture, out error))
            {
                _statusLabel.ForeColor = Color.FromArgb(194, 74, 64);
                _statusLabel.Text = error;
                return;
            }

            _selectedGesture = gesture;
            _hotkeyInput.Text = gesture.DisplayText;
            _statusLabel.ForeColor = Color.FromArgb(20, 118, 132);
            _statusLabel.Text = "可以保存这个快捷键";
            _hotkeyInput.SelectAll();
        }

        private void SaveButtonClick(object sender, EventArgs eventArgs)
        {
            if (!_selectedGesture.IsValid)
            {
                _statusLabel.ForeColor = Color.FromArgb(194, 74, 64);
                _statusLabel.Text = "请先按下一个有效的组合键";
                return;
            }

            DialogResult = DialogResult.OK;
            Close();
        }
    }
}
