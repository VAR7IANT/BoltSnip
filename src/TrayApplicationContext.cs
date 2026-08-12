using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace BoltSnip
{
    internal sealed class TrayApplicationContext : ApplicationContext
    {
        private readonly CaptureOverlay _overlay;
        private readonly HotkeyWindow _hotkey;
        private readonly NotifyIcon _trayIcon;
        private readonly ToolStripMenuItem _captureMenuItem;
        private readonly ToolStripMenuItem _startupMenuItem;
        private readonly AppSettings _settings;
        private readonly Icon _applicationIcon;
        private bool _exiting;

        internal TrayApplicationContext()
        {
            _settings = AppSettings.Load();
            _overlay = new CaptureOverlay(delegate { return _settings.SaveDirectory; });
            _overlay.CaptureFinished += OverlayCaptureFinished;
            _hotkey = new HotkeyWindow(BeginCapture, _settings.Hotkey);

            ContextMenuStrip menu = new ContextMenuStrip();
            _captureMenuItem = new ToolStripMenuItem();
            _captureMenuItem.Font = new Font(_captureMenuItem.Font, FontStyle.Bold);
            _captureMenuItem.Click += delegate { BeginCapture(); };
            menu.Items.Add(_captureMenuItem);
            ToolStripMenuItem hotkeySettings = new ToolStripMenuItem("设置快捷键…");
            hotkeySettings.Click += delegate { OpenHotkeySettings(); };
            menu.Items.Add(hotkeySettings);
            ToolStripMenuItem saveDirectorySettings = new ToolStripMenuItem("设置保存目录…");
            saveDirectorySettings.Click += delegate { OpenSaveDirectorySettings(); };
            menu.Items.Add(saveDirectorySettings);
            _startupMenuItem = new ToolStripMenuItem("开机启动");
            _startupMenuItem.Checked = StartupRegistration.IsEnabledForCurrentExecutable();
            _startupMenuItem.Click += delegate { ToggleStartup(); };
            menu.Items.Add(_startupMenuItem);
            menu.Items.Add(new ToolStripSeparator());
            ToolStripMenuItem exit = new ToolStripMenuItem("退出 BoltSnip");
            exit.Click += delegate { ExitApplication(); };
            menu.Items.Add(exit);

            _trayIcon = new NotifyIcon();
            _applicationIcon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            _trayIcon.Icon = _applicationIcon ?? SystemIcons.Application;
            _trayIcon.Text = "BoltSnip · " + _hotkey.ShortcutText;
            _trayIcon.ContextMenuStrip = menu;
            _trayIcon.Visible = true;
            _trayIcon.DoubleClick += delegate { BeginCapture(); };

            UpdateShortcutLabels();

            if (_hotkey.ShortcutText == "托盘菜单")
            {
                _trayIcon.ShowBalloonTip(3000, "BoltSnip", "快捷键被其他程序占用，请双击托盘图标截图。", ToolTipIcon.Warning);
            }
        }

        private void OpenHotkeySettings()
        {
            if (_overlay.IsCapturing)
            {
                return;
            }

            _hotkey.Suspend();
            bool changed = false;
            try
            {
                HotkeyGesture displayedGesture = _hotkey.CurrentGesture;
                while (true)
                {
                    using (HotkeySettingsDialog dialog = new HotkeySettingsDialog(displayedGesture))
                    {
                        if (dialog.ShowDialog() != DialogResult.OK)
                        {
                            return;
                        }

                        string error;
                        if (!_hotkey.TryChange(dialog.SelectedGesture, out error))
                        {
                            displayedGesture = dialog.SelectedGesture;
                            MessageBox.Show(error, "无法使用这个快捷键", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                            _hotkey.Suspend();
                            continue;
                        }

                        changed = true;
                        _settings.Hotkey = dialog.SelectedGesture;
                        try
                        {
                            _settings.Save();
                        }
                        catch (Exception exception)
                        {
                            MessageBox.Show(
                                "快捷键已经生效，但无法保存设置：" + exception.Message,
                                "无法保存设置",
                                MessageBoxButtons.OK,
                                MessageBoxIcon.Warning);
                        }
                        break;
                    }
                }
            }
            finally
            {
                if (!changed && !_hotkey.IsRegistered)
                {
                    string resumeError;
                    if (!_hotkey.Resume(out resumeError))
                    {
                        _trayIcon.ShowBalloonTip(3000, "快捷键不可用", resumeError, ToolTipIcon.Warning);
                    }
                }
                UpdateShortcutLabels();
            }
        }

        private void OpenSaveDirectorySettings()
        {
            if (_overlay.IsCapturing)
            {
                return;
            }

            using (FolderBrowserDialog dialog = new FolderBrowserDialog())
            {
                dialog.Description = "选择右键快速保存截图的目录";
                dialog.ShowNewFolderButton = true;
                dialog.SelectedPath = Directory.Exists(_settings.SaveDirectory)
                    ? _settings.SaveDirectory
                    : Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);

                if (dialog.ShowDialog() != DialogResult.OK)
                {
                    return;
                }

                string previousDirectory = _settings.SaveDirectory;
                _settings.SaveDirectory = dialog.SelectedPath;
                try
                {
                    _settings.Save();
                }
                catch (Exception exception)
                {
                    _settings.SaveDirectory = previousDirectory;
                    MessageBox.Show(
                        "无法保存目录设置：" + exception.Message,
                        "设置失败",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Warning);
                }
            }
        }

        private void ToggleStartup()
        {
            bool enable = !_startupMenuItem.Checked;
            try
            {
                StartupRegistration.SetEnabledForCurrentExecutable(enable);
                _startupMenuItem.Checked = StartupRegistration.IsEnabledForCurrentExecutable();
            }
            catch (Exception exception)
            {
                _startupMenuItem.Checked = StartupRegistration.IsEnabledForCurrentExecutable();
                MessageBox.Show(
                    "无法修改开机启动设置：" + exception.Message,
                    "设置失败",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
            }
        }

        private void UpdateShortcutLabels()
        {
            _captureMenuItem.Text = "截图    " + _hotkey.ShortcutText;
            _trayIcon.Text = "BoltSnip · " + _hotkey.ShortcutText;
        }

        private void BeginCapture()
        {
            if (_exiting || _overlay.IsCapturing)
            {
                return;
            }

            try
            {
                _overlay.BeginCapture();
            }
            catch (Exception exception)
            {
                _trayIcon.ShowBalloonTip(3500, "无法截图", exception.Message, ToolTipIcon.Error);
            }
        }

        private void OverlayCaptureFinished(object sender, CaptureStatusEventArgs e)
        {
            // A successful capture stays intentionally silent so the workflow is not interrupted.
        }

        private void ExitApplication()
        {
            _exiting = true;
            _trayIcon.Visible = false;
            _hotkey.Dispose();
            _overlay.Dispose();
            _trayIcon.Dispose();
            if (_applicationIcon != null)
            {
                _applicationIcon.Dispose();
            }
            ExitThread();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && !_exiting)
            {
                ExitApplication();
            }
            base.Dispose(disposing);
        }
    }
}
