using System;
using System.Collections.Generic;
using System.Windows.Forms;

namespace BoltSnip
{
    internal struct HotkeyGesture : IEquatable<HotkeyGesture>
    {
        internal HotkeyGesture(uint modifiers, Keys key)
            : this()
        {
            Modifiers = modifiers;
            Key = key & Keys.KeyCode;
        }

        internal uint Modifiers { get; private set; }
        internal Keys Key { get; private set; }

        internal static HotkeyGesture Default
        {
            get { return new HotkeyGesture(NativeMethods.MOD_ALT, Keys.A); }
        }

        internal string DisplayText
        {
            get
            {
                List<string> parts = new List<string>();
                if ((Modifiers & NativeMethods.MOD_CONTROL) != 0) parts.Add("Ctrl");
                if ((Modifiers & NativeMethods.MOD_ALT) != 0) parts.Add("Alt");
                if ((Modifiers & NativeMethods.MOD_SHIFT) != 0) parts.Add("Shift");
                parts.Add(KeyText(Key));
                return string.Join("+", parts.ToArray());
            }
        }

        internal static bool TryFromKeyEvent(KeyEventArgs eventArgs, out HotkeyGesture gesture, out string error)
        {
            gesture = default(HotkeyGesture);
            error = null;

            Keys key = eventArgs.KeyCode & Keys.KeyCode;
            if (IsModifierKey(key))
            {
                error = "请再按一个字母、数字或功能键";
                return false;
            }

            uint modifiers = 0;
            if (eventArgs.Control) modifiers |= NativeMethods.MOD_CONTROL;
            if (eventArgs.Alt) modifiers |= NativeMethods.MOD_ALT;
            if (eventArgs.Shift) modifiers |= NativeMethods.MOD_SHIFT;

            gesture = new HotkeyGesture(modifiers, key);
            if (!gesture.IsValid)
            {
                error = "快捷键至少要包含 Ctrl、Alt 或 Shift 中的一个";
                return false;
            }

            return true;
        }

        internal bool IsValid
        {
            get
            {
                uint allowedModifiers = NativeMethods.MOD_CONTROL | NativeMethods.MOD_ALT | NativeMethods.MOD_SHIFT;
                return Modifiers != 0 &&
                       (Modifiers & ~allowedModifiers) == 0 &&
                       Key != Keys.None &&
                       !IsModifierKey(Key);
            }
        }

        public bool Equals(HotkeyGesture other)
        {
            return Modifiers == other.Modifiers && Key == other.Key;
        }

        public override bool Equals(object value)
        {
            return value is HotkeyGesture && Equals((HotkeyGesture)value);
        }

        public override int GetHashCode()
        {
            return ((int)Modifiers * 397) ^ (int)Key;
        }

        private static bool IsModifierKey(Keys key)
        {
            return key == Keys.ControlKey ||
                   key == Keys.LControlKey ||
                   key == Keys.RControlKey ||
                   key == Keys.Menu ||
                   key == Keys.LMenu ||
                   key == Keys.RMenu ||
                   key == Keys.ShiftKey ||
                   key == Keys.LShiftKey ||
                   key == Keys.RShiftKey ||
                   key == Keys.LWin ||
                   key == Keys.RWin;
        }

        private static string KeyText(Keys key)
        {
            if (key >= Keys.A && key <= Keys.Z)
            {
                return ((char)('A' + (key - Keys.A))).ToString();
            }

            if (key >= Keys.D0 && key <= Keys.D9)
            {
                return ((char)('0' + (key - Keys.D0))).ToString();
            }

            if (key >= Keys.NumPad0 && key <= Keys.NumPad9)
            {
                return "Num" + (key - Keys.NumPad0);
            }

            return key.ToString();
        }
    }
}
