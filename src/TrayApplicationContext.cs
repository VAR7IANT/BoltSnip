using System;
using System.Collections.Generic;
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
        private readonly TrayPopupForm _trayPopup;
        private readonly AppSettings _settings;
        private readonly ReplayManager _replayManager;
        private readonly Timer _replayUiTimer;
        private readonly Icon _applicationIcon;
        private bool _exiting;

        internal TrayApplicationContext()
        {
            _settings = AppSettings.Load();
            _overlay = new CaptureOverlay(delegate { return _settings.SaveDirectory; });
            _overlay.CaptureFinished += OverlayCaptureFinished;
            _replayManager = new ReplayManager();
            _hotkey = new HotkeyWindow(
                BeginCapture,
                SaveReplayFromHotkey,
                _settings.CaptureHotkey,
                _settings.ReplaySaveHotkey);

            _trayPopup = new TrayPopupForm(
                BeginCapture,
                ToggleInstantReplay,
                delegate { _replayManager.SaveReplay(); },
                OpenHotkeySettings,
                OpenSaveDirectorySettings,
                ToggleStartup,
                OpenLicenseSettings,
                ExitApplication);
            _trayPopup.UpdatePresentation(
                ReleaseIdentity.Version,
                _hotkey.CaptureShortcutText,
                _hotkey.ReplaySaveShortcutText,
                StartupRegistration.IsEnabledForCurrentExecutable(),
                LicenseManager.Enabled);

            _trayIcon = new NotifyIcon();
            _applicationIcon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            _trayIcon.Icon = _applicationIcon ?? SystemIcons.Application;
            _trayIcon.MouseUp += TrayIconMouseUp;
            _trayIcon.DoubleClick += delegate { BeginCapture(); };

            UpdateShortcutLabels();
            _trayIcon.Visible = true;
            _replayUiTimer = new Timer();
            _replayUiTimer.Interval = 350;
            _replayUiTimer.Tick += ReplayUiTimerTick;
            _replayUiTimer.Start();

            List<string> unavailableHotkeys = new List<string>();
            if (!_hotkey.CaptureIsRegistered)
            {
                unavailableHotkeys.Add("截图：" + _settings.CaptureHotkey.DisplayText);
            }
            if (!_hotkey.ReplaySaveIsRegistered)
            {
                unavailableHotkeys.Add("保存即时回放：" + _settings.ReplaySaveHotkey.DisplayText);
            }
            if (unavailableHotkeys.Count > 0)
            {
                _trayIcon.ShowBalloonTip(
                    4000,
                    "部分快捷键不可用",
                    string.Join("；", unavailableHotkeys.ToArray()) + " 被其他程序占用，可在快捷键设置中更换。",
                    ToolTipIcon.Warning);
            }
        }

        private void OpenHotkeySettings()
        {
            if (_overlay.IsCapturing)
            {
                return;
            }

            _hotkey.SetCallbacksSuppressed(true);
            try
            {
                using (HotkeySettingsDialog dialog = new HotkeySettingsDialog(_settings, _hotkey))
                {
                    dialog.ShowDialog();
                }
            }
            finally
            {
                _hotkey.SetCallbacksSuppressed(false);
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

        private void OpenLicenseSettings()
        {
            using (ActivationDialog dialog = new ActivationDialog())
            {
                dialog.ShowDialog();
            }
        }

        private void ToggleStartup()
        {
            bool enable = !StartupRegistration.IsEnabledForCurrentExecutable();
            try
            {
                StartupRegistration.SetEnabledForCurrentExecutable(enable);
            }
            catch (Exception exception)
            {
                MessageBox.Show(
                    "无法修改开机启动设置：" + exception.Message,
                    "设置失败",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
            }
            UpdatePopupPresentation();
        }

        private void UpdateShortcutLabels()
        {
            string tooltip = "BoltSnip v" + ReleaseIdentity.Version + " · 截图 " +
                _hotkey.CaptureShortcutText + " · 回放 " + _hotkey.ReplaySaveShortcutText;
            _trayIcon.Text = tooltip.Length > 63 ? tooltip.Substring(0, 60) + "..." : tooltip;
            UpdatePopupPresentation();
        }

        private void UpdatePopupPresentation()
        {
            _trayPopup.UpdatePresentation(
                ReleaseIdentity.Version,
                _hotkey.CaptureShortcutText,
                _hotkey.ReplaySaveShortcutText,
                StartupRegistration.IsEnabledForCurrentExecutable(),
                LicenseManager.Enabled);
        }

        private void ToggleInstantReplay()
        {
            ReplayState state = _replayManager.State;
            if (state == ReplayState.Recording || state == ReplayState.Starting)
            {
                _replayManager.Stop();
            }
            else if (state != ReplayState.Stopping)
            {
                _replayManager.Start();
            }
            UpdateReplayUi();
        }

        private void SaveReplayFromHotkey()
        {
            if (!_exiting)
            {
                _replayManager.SaveReplay();
            }
        }

        private void ReplayUiTimerTick(object sender, EventArgs e)
        {
            UpdateReplayUi();
            ReplayNotification notification;
            while (_replayManager.TryDequeueNotification(out notification))
            {
                if (notification.Title == "即时回放已保存")
                {
                    _trayPopup.ShowSavedFeedback();
                }
                _trayIcon.ShowBalloonTip(
                    notification.IsError ? 4500 : 3000,
                    notification.Title,
                    notification.Message,
                    notification.IsError ? ToolTipIcon.Warning : ToolTipIcon.Info);
            }
        }

        private void UpdateReplayUi()
        {
            if (_exiting)
            {
                return;
            }

            ReplayState state = _replayManager.State;
            bool saving = _replayManager.IsSaving;
            _trayPopup.UpdateReplayState(state, saving, _replayManager.AudioState);
        }

        private void TrayIconMouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right && !_exiting)
            {
                UpdateReplayUi();
                _trayPopup.ShowNear(Cursor.Position);
            }
        }

        private void BeginCapture()
        {
            if (_exiting || _overlay.IsCapturing)
            {
                return;
            }
            if (!LicenseManager.IsAuthorized)
            {
                _trayIcon.ShowBalloonTip(3500, "授权需要验证", "请检查网络，或在托盘菜单中更换授权。", ToolTipIcon.Warning);
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
            _replayUiTimer.Stop();
            _replayUiTimer.Dispose();
            _replayManager.Dispose();
            _hotkey.Dispose();
            _overlay.Dispose();
            _trayIcon.ContextMenuStrip = null;
            _trayIcon.Dispose();
            _trayPopup.Dispose();
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
