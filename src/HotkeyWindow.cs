using System;
using System.Windows.Forms;

namespace BoltSnip
{
    internal sealed class HotkeyWindow : NativeWindow, IDisposable
    {
        private const int HotkeyId = 0x5A71;
        private const int ReplayHotkeyId = 0x5A72;
        private readonly Action _pressed;
        private readonly Action _replayPressed;
        private readonly HotkeyGesture _replayGesture;
        private bool _registered;
        private bool _replayRegistered;

        private HotkeyGesture? _currentGesture;

        internal HotkeyWindow(Action pressed, Action replayPressed, HotkeyGesture preferredGesture)
            : this(
                pressed,
                replayPressed,
                preferredGesture,
                new HotkeyGesture(NativeMethods.MOD_ALT | NativeMethods.MOD_SHIFT, Keys.S))
        {
        }

        internal HotkeyWindow(
            Action pressed,
            Action replayPressed,
            HotkeyGesture preferredGesture,
            HotkeyGesture replayGesture)
        {
            _pressed = pressed;
            _replayPressed = replayPressed;
            _replayGesture = replayGesture;
            CreateParams parameters = new CreateParams();
            parameters.Caption = "BoltSnip.Hotkey";
            CreateHandle(parameters);

            if (!Register(preferredGesture))
            {
                HotkeyGesture fallback = new HotkeyGesture(
                    NativeMethods.MOD_CONTROL | NativeMethods.MOD_SHIFT,
                    Keys.A);
                if (!fallback.Equals(preferredGesture))
                {
                    Register(fallback);
                }
            }

            RegisterReplayHotkey();
        }

        internal string ShortcutText
        {
            get { return _registered && _currentGesture.HasValue ? _currentGesture.Value.DisplayText : "托盘菜单"; }
        }

        internal HotkeyGesture CurrentGesture
        {
            get { return _currentGesture.HasValue ? _currentGesture.Value : HotkeyGesture.Default; }
        }

        internal bool IsRegistered
        {
            get { return _registered; }
        }

        internal bool IsReplayHotkeyRegistered
        {
            get { return _replayRegistered; }
        }

        internal string ReplayShortcutText
        {
            get { return _replayGesture.DisplayText; }
        }

        internal void Suspend()
        {
            if (_registered)
            {
                NativeMethods.UnregisterHotKey(Handle, HotkeyId);
                _registered = false;
            }
            if (_replayRegistered)
            {
                NativeMethods.UnregisterHotKey(Handle, ReplayHotkeyId);
                _replayRegistered = false;
            }
        }

        internal bool Resume(out string error)
        {
            if (!_registered && _currentGesture.HasValue)
            {
                Register(_currentGesture.Value);
            }

            if (!_replayRegistered)
            {
                RegisterReplayHotkey();
            }

            if (!_registered)
            {
                error = "原快捷键已被其他程序占用，请重新设置。";
                return false;
            }

            error = _replayRegistered ? null : "即时回放快捷键 Alt+Shift+S 已被占用。";
            return true;
        }

        internal bool TryChange(HotkeyGesture newGesture, out string error)
        {
            if (newGesture.Equals(_replayGesture))
            {
                error = "“" + newGesture.DisplayText + "” 已保留给即时回放，请换一个组合键。";
                return false;
            }

            HotkeyGesture? previous = _currentGesture;
            Suspend();

            if (Register(newGesture))
            {
                RegisterReplayHotkey();
                error = null;
                return true;
            }

            if (previous.HasValue)
            {
                Register(previous.Value);
            }
            RegisterReplayHotkey();

            error = "“" + newGesture.DisplayText + "” 已被其他程序占用，请换一个组合键。";
            return false;
        }

        protected override void WndProc(ref Message message)
        {
            if (message.Msg == NativeMethods.WM_HOTKEY && message.WParam.ToInt32() == HotkeyId)
            {
                _pressed();
                return;
            }
            if (message.Msg == NativeMethods.WM_HOTKEY && message.WParam.ToInt32() == ReplayHotkeyId)
            {
                if (_replayPressed != null)
                {
                    _replayPressed();
                }
                return;
            }

            base.WndProc(ref message);
        }

        public void Dispose()
        {
            if (_registered)
            {
                NativeMethods.UnregisterHotKey(Handle, HotkeyId);
                _registered = false;
            }
            if (_replayRegistered)
            {
                NativeMethods.UnregisterHotKey(Handle, ReplayHotkeyId);
                _replayRegistered = false;
            }

            DestroyHandle();
        }

        private bool RegisterReplayHotkey()
        {
            _replayRegistered = NativeMethods.RegisterHotKey(
                Handle,
                ReplayHotkeyId,
                _replayGesture.Modifiers | NativeMethods.MOD_NOREPEAT,
                (uint)_replayGesture.Key);
            return _replayRegistered;
        }

        private bool Register(HotkeyGesture gesture)
        {
            _registered = NativeMethods.RegisterHotKey(
                Handle,
                HotkeyId,
                gesture.Modifiers | NativeMethods.MOD_NOREPEAT,
                (uint)gesture.Key);

            if (_registered)
            {
                _currentGesture = gesture;
            }

            return _registered;
        }
    }
}
