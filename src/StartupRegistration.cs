using System;
using System.IO;
using System.Windows.Forms;
using Microsoft.Win32;

namespace BoltSnip
{
    internal static class StartupRegistration
    {
        private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string ValueName = "BoltSnip";

        internal static bool IsEnabledForCurrentExecutable()
        {
            return IsEnabled(Application.ExecutablePath);
        }

        internal static void SetEnabledForCurrentExecutable(bool enabled)
        {
            SetEnabled(Application.ExecutablePath, enabled);
        }

        internal static string BuildCommand(string executablePath)
        {
            if (string.IsNullOrWhiteSpace(executablePath) || !Path.IsPathRooted(executablePath))
            {
                throw new ArgumentException("应用路径必须是完整路径。", "executablePath");
            }

            return "\"" + Path.GetFullPath(executablePath) + "\" --startup";
        }

        internal static bool IsEnabled(string executablePath)
        {
            string expected = BuildCommand(executablePath);
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RunKeyPath, false))
            {
                if (key == null)
                {
                    return false;
                }

                string configured = key.GetValue(ValueName, null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
                return string.Equals(configured, expected, StringComparison.OrdinalIgnoreCase);
            }
        }

        internal static void SetEnabled(string executablePath, bool enabled)
        {
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(RunKeyPath))
            {
                if (key == null)
                {
                    throw new InvalidOperationException("无法打开 Windows 启动项设置。");
                }

                if (enabled)
                {
                    key.SetValue(ValueName, BuildCommand(executablePath), RegistryValueKind.String);
                }
                else
                {
                    key.DeleteValue(ValueName, false);
                }
            }
        }
    }
}
