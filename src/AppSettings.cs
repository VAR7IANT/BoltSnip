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

        private readonly string _settingsPath;

        private AppSettings()
            : this(SettingsPath)
        {
        }

        private AppSettings(string settingsPath)
        {
            _settingsPath = settingsPath;
            CaptureHotkey = HotkeyGesture.Default;
            ReplaySaveHotkey = HotkeyGesture.ReplaySaveDefault;
            SaveDirectory = DefaultSaveDirectory;
        }

        internal HotkeyGesture CaptureHotkey { get; set; }

        internal HotkeyGesture ReplaySaveHotkey { get; set; }

        internal string SaveDirectory { get; set; }

        internal static string DefaultSaveDirectory
        {
            get
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.MyPictures),
                    "BoltSnip");
            }
        }

        internal static AppSettings Load()
        {
            return Load(SettingsPath, LegacySettingsPath);
        }

        internal static AppSettings Load(string settingsPath, string legacySettingsPath)
        {
            AppSettings settings = new AppSettings(settingsPath);
            try
            {
                string path = File.Exists(settingsPath)
                    ? settingsPath
                    : legacySettingsPath;
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

                HotkeyGesture captureHotkey;
                bool hasCaptureHotkey = TryReadGesture(values, "CaptureModifiers", "CaptureKey", out captureHotkey);
                HotkeyGesture legacyCaptureHotkey;
                bool hasLegacyCaptureHotkey = TryReadGesture(values, "Modifiers", "Key", out legacyCaptureHotkey);
                if (hasCaptureHotkey)
                {
                    settings.CaptureHotkey = captureHotkey;
                }
                else if (hasLegacyCaptureHotkey)
                {
                    settings.CaptureHotkey = legacyCaptureHotkey;
                }

                HotkeyGesture replaySaveHotkey;
                if (TryReadGesture(values, "ReplaySaveModifiers", "ReplaySaveKey", out replaySaveHotkey))
                {
                    settings.ReplaySaveHotkey = replaySaveHotkey;
                }

                string saveDirectory;
                if (values.TryGetValue("SaveDirectory", out saveDirectory) &&
                    IsUsableSaveDirectory(saveDirectory))
                {
                    settings.SaveDirectory = saveDirectory;
                }

                bool loadedLegacyPath = string.Equals(path, legacySettingsPath, StringComparison.OrdinalIgnoreCase);
                bool loadedLegacyFormat = !hasCaptureHotkey && hasLegacyCaptureHotkey;
                if (loadedLegacyPath || loadedLegacyFormat)
                {
                    settings.Save(settingsPath);
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
            Save(_settingsPath);
        }

        internal void Save(string path)
        {
            if (!CaptureHotkey.IsValid || !ReplaySaveHotkey.IsValid)
            {
                throw new InvalidOperationException("快捷键设置无效，无法保存。");
            }

            string fullPath = Path.GetFullPath(path);
            string directory = Path.GetDirectoryName(fullPath);
            Directory.CreateDirectory(directory);
            string saveDirectory = IsUsableSaveDirectory(SaveDirectory)
                ? SaveDirectory
                : DefaultSaveDirectory;
            string contents =
                "CaptureModifiers=" + CaptureHotkey.Modifiers.ToString(CultureInfo.InvariantCulture) + Environment.NewLine +
                "CaptureKey=" + ((int)CaptureHotkey.Key).ToString(CultureInfo.InvariantCulture) + Environment.NewLine +
                "ReplaySaveModifiers=" + ReplaySaveHotkey.Modifiers.ToString(CultureInfo.InvariantCulture) + Environment.NewLine +
                "ReplaySaveKey=" + ((int)ReplaySaveHotkey.Key).ToString(CultureInfo.InvariantCulture) + Environment.NewLine +
                "SaveDirectory=" + saveDirectory + Environment.NewLine;

            string temporaryPath = fullPath + ".tmp." + Guid.NewGuid().ToString("N");
            try
            {
                File.WriteAllText(temporaryPath, contents, new System.Text.UTF8Encoding(false));
                if (File.Exists(fullPath))
                {
                    File.Replace(temporaryPath, fullPath, null);
                }
                else
                {
                    try
                    {
                        File.Move(temporaryPath, fullPath);
                    }
                    catch (IOException)
                    {
                        if (!File.Exists(fullPath))
                        {
                            throw;
                        }
                        File.Replace(temporaryPath, fullPath, null);
                    }
                }
            }
            finally
            {
                if (File.Exists(temporaryPath))
                {
                    File.Delete(temporaryPath);
                }
            }
        }

        private static bool TryReadGesture(
            Dictionary<string, string> values,
            string modifiersName,
            string keyName,
            out HotkeyGesture gesture)
        {
            gesture = default(HotkeyGesture);
            string modifiersText;
            string keyText;
            uint modifiers;
            int key;
            if (!values.TryGetValue(modifiersName, out modifiersText) ||
                !values.TryGetValue(keyName, out keyText) ||
                !uint.TryParse(modifiersText, NumberStyles.Integer, CultureInfo.InvariantCulture, out modifiers) ||
                !int.TryParse(keyText, NumberStyles.Integer, CultureInfo.InvariantCulture, out key))
            {
                return false;
            }

            gesture = new HotkeyGesture(modifiers, (Keys)key);
            return gesture.IsValid;
        }

        private static bool IsUsableSaveDirectory(string path)
        {
            return !string.IsNullOrWhiteSpace(path) &&
                Path.IsPathRooted(path) &&
                path.IndexOfAny(Path.GetInvalidPathChars()) < 0 &&
                path.IndexOf('\r') < 0 &&
                path.IndexOf('\n') < 0;
        }
    }
}
