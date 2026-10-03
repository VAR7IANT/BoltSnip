using System;
using System.Windows.Forms;

namespace BoltSnip
{
    internal enum HotkeySlot
    {
        Capture,
        ReplaySave
    }

    internal sealed class HotkeyWindow : NativeWindow, IDisposable
    {
        private const int CaptureHotkeyId = 0x5A71;
        private const int ReplaySaveHotkeyId = 0x5A72;
        private const int ProbeHotkeyId = 0x5A73;

        private readonly Action _capturePressed;
        private readonly Action _replaySavePressed;
        private HotkeyGesture _captureGesture;
        private HotkeyGesture _replaySaveGesture;
        private bool _captureRegistered;
        private bool _replaySaveRegistered;
        private bool _callbacksSuppressed;

        internal HotkeyWindow(
            Action capturePressed,
            Action replaySavePressed,
            HotkeyGesture captureGesture,
            HotkeyGesture replaySaveGesture)
        {
            if (capturePressed == null)
            {
                throw new ArgumentNullException("capturePressed");
            }
            if (replaySavePressed == null)
            {
                throw new ArgumentNullException("replaySavePressed");
            }

            _capturePressed = capturePressed;
            _replaySavePressed = replaySavePressed;
            _captureGesture = captureGesture;
            _replaySaveGesture = replaySaveGesture;

            CreateParams parameters = new CreateParams();
            parameters.Caption = "BoltSnip.Hotkey";
            CreateHandle(parameters);

            if (_captureGesture.IsValid)
            {
                if (!TryRegisterCapture(_captureGesture))
                {
                    HotkeyGesture fallback = new HotkeyGesture(
                        NativeMethods.MOD_CONTROL | NativeMethods.MOD_SHIFT, Keys.A);
                    if (!fallback.Equals(_captureGesture) && !fallback.Equals(_replaySaveGesture) &&
                        TryRegisterCapture(fallback))
                        _captureGesture = fallback;
                }
            }
            if (_replaySaveGesture.IsValid)
            {
                TryRegisterReplaySave(_replaySaveGesture);
            }
        }

        internal string ShortcutText
        {
            get { return CaptureShortcutText; }
        }

        internal string CaptureShortcutText
        {
            get { return _captureGesture.DisplayText + (_captureRegistered ? string.Empty : "（不可用）"); }
        }

        internal string ReplaySaveShortcutText
        {
            get { return _replaySaveGesture.DisplayText + (_replaySaveRegistered ? string.Empty : "（不可用）"); }
        }

        internal HotkeyGesture CurrentGesture
        {
            get { return _captureGesture; }
        }

        internal HotkeyGesture CaptureGesture
        {
            get { return _captureGesture; }
        }

        internal HotkeyGesture ReplaySaveGesture
        {
            get { return _replaySaveGesture; }
        }

        internal bool IsRegistered
        {
            get { return _captureRegistered; }
        }

        internal bool IsReplayHotkeyRegistered
        {
            get { return _replaySaveRegistered; }
        }

        internal bool CaptureIsRegistered
        {
            get { return _captureRegistered; }
        }

        internal bool ReplaySaveIsRegistered
        {
            get { return _replaySaveRegistered; }
        }

        internal bool CheckAvailability(
            HotkeyGesture captureGesture,
            HotkeyGesture replaySaveGesture,
            HotkeySlot slot,
            HotkeyGesture candidate,
            out string error)
        {
            error = null;
            if (!candidate.IsValid)
            {
                error = "请先按下有效的组合键。";
                return false;
            }

            if (captureGesture.Equals(replaySaveGesture))
            {
                error = slot == HotkeySlot.Capture
                    ? "与“保存即时回放”快捷键冲突。"
                    : "与“截图”快捷键冲突。";
                return false;
            }

            HotkeyGesture currentGesture = slot == HotkeySlot.Capture
                ? _captureGesture
                : _replaySaveGesture;
            bool currentRegistered = slot == HotkeySlot.Capture
                ? _captureRegistered
                : _replaySaveRegistered;
            if (currentRegistered && candidate.Equals(currentGesture))
            {
                return true;
            }

            if (CanRegister(candidate))
            {
                return true;
            }

            error = "该快捷键已被其他程序占用。";
            return false;
        }

        internal bool TryApply(
            HotkeyGesture captureGesture,
            HotkeyGesture replaySaveGesture,
            bool retryUnavailableCapture,
            bool retryUnavailableReplaySave,
            out HotkeySlot failedSlot,
            out string error)
        {
            failedSlot = HotkeySlot.Capture;
            error = null;
            if (!captureGesture.IsValid)
            {
                error = "截图快捷键无效，请重新录入。";
                return false;
            }
            if (!replaySaveGesture.IsValid)
            {
                failedSlot = HotkeySlot.ReplaySave;
                error = "保存即时回放快捷键无效，请重新录入。";
                return false;
            }
            if (captureGesture.Equals(replaySaveGesture))
            {
                failedSlot = !captureGesture.Equals(_captureGesture)
                    ? HotkeySlot.Capture
                    : HotkeySlot.ReplaySave;
                error = failedSlot == HotkeySlot.Capture
                    ? "与“保存即时回放”快捷键冲突。"
                    : "与“截图”快捷键冲突。";
                return false;
            }

            HotkeyGesture previousCapture = _captureGesture;
            HotkeyGesture previousReplaySave = _replaySaveGesture;
            bool previousCaptureRegistered = _captureRegistered;
            bool previousReplaySaveRegistered = _replaySaveRegistered;
            bool captureChanged = !captureGesture.Equals(previousCapture);
            bool replaySaveChanged = !replaySaveGesture.Equals(previousReplaySave);
            bool captureTouched = false;
            bool replaySaveTouched = false;

            if (captureChanged && _captureRegistered)
            {
                if (!UnregisterCapture())
                {
                    error = "无法暂时停用原截图快捷键，设置未更改。";
                    return false;
                }
                captureTouched = true;
            }

            if (replaySaveChanged && _replaySaveRegistered)
            {
                if (!UnregisterReplaySave())
                {
                    bool restored = RestorePreviousState(
                        captureTouched,
                        replaySaveTouched,
                        previousCapture,
                        previousReplaySave,
                        previousCaptureRegistered,
                        previousReplaySaveRegistered);
                    error = restored
                        ? "无法暂时停用原保存即时回放快捷键，设置未更改。"
                        : "无法停用或恢复原快捷键，请重新打开设置检查状态。";
                    failedSlot = HotkeySlot.ReplaySave;
                    return false;
                }
                replaySaveTouched = true;
            }

            bool needsCaptureRegistration = captureChanged || (retryUnavailableCapture && !_captureRegistered);
            bool needsReplaySaveRegistration = replaySaveChanged || (retryUnavailableReplaySave && !_replaySaveRegistered);
            if (needsCaptureRegistration)
            {
                if (!TryRegisterCapture(captureGesture))
                {
                    bool restored = RestorePreviousState(
                        captureTouched,
                        replaySaveTouched,
                        previousCapture,
                        previousReplaySave,
                        previousCaptureRegistered,
                        previousReplaySaveRegistered);
                    failedSlot = HotkeySlot.Capture;
                    error = BuildRegistrationFailure(captureGesture, restored);
                    return false;
                }
                captureTouched = true;
            }

            if (needsReplaySaveRegistration)
            {
                if (!TryRegisterReplaySave(replaySaveGesture))
                {
                    bool restored = RestorePreviousState(
                        captureTouched,
                        replaySaveTouched,
                        previousCapture,
                        previousReplaySave,
                        previousCaptureRegistered,
                        previousReplaySaveRegistered);
                    failedSlot = HotkeySlot.ReplaySave;
                    error = BuildRegistrationFailure(replaySaveGesture, restored);
                    return false;
                }
                replaySaveTouched = true;
            }

            _captureGesture = captureGesture;
            _replaySaveGesture = replaySaveGesture;
            return true;
        }

        internal HotkeyWindowState CaptureState()
        {
            return new HotkeyWindowState(
                _captureGesture,
                _replaySaveGesture,
                _captureRegistered,
                _replaySaveRegistered);
        }

        internal bool RestoreState(HotkeyWindowState state, out string error)
        {
            if (state == null)
            {
                throw new ArgumentNullException("state");
            }

            HotkeyWindowState current = CaptureState();
            if (TrySetState(state, out error))
            {
                return true;
            }

            string transitionError = error;
            string rollbackError;
            bool rolledBack = TrySetState(current, out rollbackError);
            error = transitionError + (rolledBack
                ? ""
                : " 回滚失败：" + rollbackError);
            return false;
        }

        internal void SetCallbacksSuppressed(bool suppressed)
        {
            _callbacksSuppressed = suppressed;
        }

        protected override void WndProc(ref Message message)
        {
            if (message.Msg == NativeMethods.WM_HOTKEY && !_callbacksSuppressed)
            {
                int id = message.WParam.ToInt32();
                if (id == CaptureHotkeyId)
                {
                    _capturePressed();
                    return;
                }
                if (id == ReplaySaveHotkeyId)
                {
                    _replaySavePressed();
                    return;
                }
            }

            base.WndProc(ref message);
        }

        public void Dispose()
        {
            if (_captureRegistered)
            {
                NativeMethods.UnregisterHotKey(Handle, CaptureHotkeyId);
                _captureRegistered = false;
            }
            if (_replaySaveRegistered)
            {
                NativeMethods.UnregisterHotKey(Handle, ReplaySaveHotkeyId);
                _replaySaveRegistered = false;
            }

            DestroyHandle();
        }

        private bool CanRegister(HotkeyGesture gesture)
        {
            using (HotkeyProbe probe = new HotkeyProbe())
            {
                return probe.CanRegister(gesture);
            }
        }

        private bool TryRegisterCapture(HotkeyGesture gesture)
        {
            _captureRegistered = NativeMethods.RegisterHotKey(
                Handle,
                CaptureHotkeyId,
                gesture.Modifiers | NativeMethods.MOD_NOREPEAT,
                (uint)gesture.Key);
            return _captureRegistered;
        }

        private bool TryRegisterReplaySave(HotkeyGesture gesture)
        {
            _replaySaveRegistered = NativeMethods.RegisterHotKey(
                Handle,
                ReplaySaveHotkeyId,
                gesture.Modifiers | NativeMethods.MOD_NOREPEAT,
                (uint)gesture.Key);
            return _replaySaveRegistered;
        }

        private bool UnregisterCapture()
        {
            if (!_captureRegistered)
            {
                return true;
            }

            if (!NativeMethods.UnregisterHotKey(Handle, CaptureHotkeyId))
            {
                return false;
            }

            _captureRegistered = false;
            return true;
        }

        private bool UnregisterReplaySave()
        {
            if (!_replaySaveRegistered)
            {
                return true;
            }

            if (!NativeMethods.UnregisterHotKey(Handle, ReplaySaveHotkeyId))
            {
                return false;
            }

            _replaySaveRegistered = false;
            return true;
        }

        private bool RestorePreviousState(
            bool captureTouched,
            bool replaySaveTouched,
            HotkeyGesture previousCapture,
            HotkeyGesture previousReplaySave,
            bool previousCaptureRegistered,
            bool previousReplaySaveRegistered)
        {
            bool captureRestored = RestoreCapture(
                captureTouched,
                previousCapture,
                previousCaptureRegistered);
            bool replaySaveRestored = RestoreReplaySave(
                replaySaveTouched,
                previousReplaySave,
                previousReplaySaveRegistered);
            return captureRestored && replaySaveRestored;
        }

        private bool RestoreCapture(bool touched, HotkeyGesture previous, bool wasRegistered)
        {
            if (!touched)
            {
                return true;
            }
            if (wasRegistered)
            {
                if (_captureRegistered && !UnregisterCapture())
                {
                    return false;
                }
                return TryRegisterCapture(previous);
            }
            return !_captureRegistered || UnregisterCapture();
        }

        private bool RestoreReplaySave(bool touched, HotkeyGesture previous, bool wasRegistered)
        {
            if (!touched)
            {
                return true;
            }
            if (wasRegistered)
            {
                if (_replaySaveRegistered && !UnregisterReplaySave())
                {
                    return false;
                }
                return TryRegisterReplaySave(previous);
            }
            return !_replaySaveRegistered || UnregisterReplaySave();
        }

        private bool TrySetState(HotkeyWindowState state, out string error)
        {
            error = null;
            bool captureNeedsTransition = _captureRegistered != state.CaptureRegistered ||
                (state.CaptureRegistered && !_captureGesture.Equals(state.CaptureGesture));
            bool replaySaveNeedsTransition = _replaySaveRegistered != state.ReplaySaveRegistered ||
                (state.ReplaySaveRegistered && !_replaySaveGesture.Equals(state.ReplaySaveGesture));

            if (captureNeedsTransition && _captureRegistered && !UnregisterCapture())
            {
                error = "无法释放当前截图快捷键。";
                return false;
            }
            if (replaySaveNeedsTransition && _replaySaveRegistered && !UnregisterReplaySave())
            {
                error = "无法释放当前保存即时回放快捷键。";
                return false;
            }

            if (state.CaptureRegistered && !_captureRegistered)
            {
                if (!TryRegisterCapture(state.CaptureGesture))
                {
                    error = BuildRegistrationFailure(state.CaptureGesture, false);
                    return false;
                }
                _captureGesture = state.CaptureGesture;
            }
            if (state.ReplaySaveRegistered && !_replaySaveRegistered)
            {
                if (!TryRegisterReplaySave(state.ReplaySaveGesture))
                {
                    error = BuildRegistrationFailure(state.ReplaySaveGesture, false);
                    return false;
                }
                _replaySaveGesture = state.ReplaySaveGesture;
            }

            _captureGesture = state.CaptureGesture;
            _replaySaveGesture = state.ReplaySaveGesture;
            return true;
        }

        private static string BuildRegistrationFailure(HotkeyGesture gesture, bool restored)
        {
            return "“" + gesture.DisplayText + "” 已被其他程序占用。" +
                (restored ? "原快捷键已恢复。" : "原快捷键未能完全恢复，请重新打开设置检查状态。");
        }
    }

    internal sealed class HotkeyWindowState
    {
        internal HotkeyWindowState(
            HotkeyGesture captureGesture,
            HotkeyGesture replaySaveGesture,
            bool captureRegistered,
            bool replaySaveRegistered)
        {
            CaptureGesture = captureGesture;
            ReplaySaveGesture = replaySaveGesture;
            CaptureRegistered = captureRegistered;
            ReplaySaveRegistered = replaySaveRegistered;
        }

        internal HotkeyGesture CaptureGesture { get; private set; }
        internal HotkeyGesture ReplaySaveGesture { get; private set; }
        internal bool CaptureRegistered { get; private set; }
        internal bool ReplaySaveRegistered { get; private set; }
    }

    internal sealed class HotkeyProbe : NativeWindow, IDisposable
    {
        private const int ProbeId = 0x5A73;
        private bool _registered;

        internal HotkeyProbe()
        {
            CreateParams parameters = new CreateParams();
            parameters.Caption = "BoltSnip.HotkeyProbe";
            CreateHandle(parameters);
        }

        internal bool CanRegister(HotkeyGesture gesture)
        {
            if (_registered)
            {
                NativeMethods.UnregisterHotKey(Handle, ProbeId);
                _registered = false;
            }

            _registered = NativeMethods.RegisterHotKey(
                Handle,
                ProbeId,
                gesture.Modifiers | NativeMethods.MOD_NOREPEAT,
                (uint)gesture.Key);
            if (!_registered)
            {
                return false;
            }

            bool unregistered = NativeMethods.UnregisterHotKey(Handle, ProbeId);
            _registered = !unregistered;
            return unregistered;
        }

        public void Dispose()
        {
            if (_registered)
            {
                NativeMethods.UnregisterHotKey(Handle, ProbeId);
                _registered = false;
            }
            DestroyHandle();
        }
    }
}
