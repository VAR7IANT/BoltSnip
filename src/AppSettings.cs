using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Windows.Forms;

namespace BoltSnip
{
    internal sealed class AppSettings
    {
        private static readonly string SettingsDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "BoltSnip");

        private static readonly string SettingsPath = Path.Combine(SettingsDirectory, "settings.ini");
        private static readonly string LegacySettingsPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "InstantShot",
            "settings.ini");

        private AppSettings()
        {
            Hotkey = HotkeyGesture.Default;
        }

        internal HotkeyGesture Hotkey { get; set; }

        internal static AppSettings Load()
        {
            AppSettings settings = new AppSettings();
            try
            {
                string path = File.Exists(SettingsPath)
                    ? SettingsPath
                    : LegacySettingsPath;
                if (!File.Exists(path))
                {
                    return settings;
                }

                Dictionary<string, string> values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                string[] lines = File.ReadAllLines(path);
                for (int index = 0; index < lines.Length; index++)
                {
                    int separator = lines[index].IndexOf('=');
                    if (separator <= 0)
                    {
                        continue;
                    }

                    values[lines[index].Substring(0, separator).Trim()] = lines[index].Substring(separator + 1).Trim();
                }

                string modifiersText;
                string keyText;
                uint modifiers;
                int key;
                if (values.TryGetValue("Modifiers", out modifiersText) &&
                    values.TryGetValue("Key", out keyText) &&
                    uint.TryParse(modifiersText, NumberStyles.Integer, CultureInfo.InvariantCulture, out modifiers) &&
                    int.TryParse(keyText, NumberStyles.Integer, CultureInfo.InvariantCulture, out key))
                {
                    HotkeyGesture saved = new HotkeyGesture(modifiers, (Keys)key);
                    if (saved.IsValid)
                    {
                        settings.Hotkey = saved;
                    }
                }

                if (string.Equals(path, LegacySettingsPath, StringComparison.OrdinalIgnoreCase))
                {
                    settings.Save();
                }
            }
            catch
            {
                // An unreadable settings file should never prevent screenshots.
            }

            return settings;
        }

        internal void Save()
        {
            Directory.CreateDirectory(SettingsDirectory);
            string contents =
                "Modifiers=" + Hotkey.Modifiers.ToString(CultureInfo.InvariantCulture) + Environment.NewLine +
                "Key=" + ((int)Hotkey.Key).ToString(CultureInfo.InvariantCulture) + Environment.NewLine;
            File.WriteAllText(SettingsPath, contents);
        }
    }
}
