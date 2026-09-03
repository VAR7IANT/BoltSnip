using System;
using System.Windows.Forms;

namespace BoltSnip
{
    internal sealed class HotkeyWindow : NativeWindow, IDisposable
    {
        private const int HotkeyId = 0x5A71;
        private readonly Action _pressed;
        private bool _registered;

        private HotkeyGesture? _currentGesture;

        internal HotkeyWindow(Action pressed, HotkeyGesture preferredGesture)
        {
            _pressed = pressed;
            CreateParams parameters = new CreateParams();
            parameters.Caption = "BoltSnip.Hotkey";
            CreateHandle(parameters);

            if (Register(preferredGesture))
            {
                return;
            }

            HotkeyGesture fallback = new HotkeyGesture(
                NativeMethods.MOD_CONTROL | NativeMethods.MOD_SHIFT,
                Keys.A);
            if (!fallback.Equals(preferredGesture))
            {
                Register(fallback);
            }
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

        internal void Suspend()
        {
            if (_registered)
            {
                NativeMethods.UnregisterHotKey(Handle, HotkeyId);
                _registered = false;
            }
        }

        internal bool Resume(out string error)
        {
            if (_registered)
            {
                error = null;
                return true;
            }

            if (_currentGesture.HasValue && Register(_currentGesture.Value))
            {
                error = null;
                return true;
            }

            error = "原快捷键已被其他程序占用，请重新设置。";
            return false;
        }

        internal bool TryChange(HotkeyGesture newGesture, out string error)
        {
            HotkeyGesture? previous = _currentGesture;
            Suspend();

            if (Register(newGesture))
            {
                error = null;
                return true;
            }

            if (previous.HasValue)
            {
                Register(previous.Value);
            }

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

            base.WndProc(ref message);
        }

        public void Dispose()
        {
            if (_registered)
            {
                NativeMethods.UnregisterHotKey(Handle, HotkeyId);
                _registered = false;
            }

            DestroyHandle();
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
