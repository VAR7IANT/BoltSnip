using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;

namespace BoltSnip
{
    internal static class CaptureDiagnostics
    {
        private const long MaximumLogBytes = 1024L * 1024L;
        private static readonly object SyncRoot = new object();
        private static readonly bool EnabledValue = IsEnabledByEnvironment();
        private static readonly string LogPathValue = GetLogPath();

        internal static bool IsEnabled
        {
            get { return EnabledValue; }
        }

        internal static string LogPath
        {
            get { return LogPathValue; }
        }

        internal static void Write(string eventName, string details)
        {
            Write(eventName, details, false);
        }

        internal static void WriteReplay(string details)
        {
            Write("Replay", details, true);
        }

        private static void Write(string eventName, string details, bool alwaysWrite)
        {
            if (!EnabledValue && !alwaysWrite)
            {
                return;
            }

            try
            {
                string line = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture) +
                    " | " + eventName +
                    (string.IsNullOrEmpty(details) ? string.Empty : " | " + details) +
                    Environment.NewLine;
                lock (SyncRoot)
                {
                    string directory = Path.GetDirectoryName(LogPathValue);
                    if (!string.IsNullOrEmpty(directory))
                    {
                        Directory.CreateDirectory(directory);
                    }

                    if (File.Exists(LogPathValue) && new FileInfo(LogPathValue).Length >= MaximumLogBytes)
                    {
                        File.WriteAllText(LogPathValue, line, Encoding.UTF8);
                    }
                    else
                    {
                        File.AppendAllText(LogPathValue, line, Encoding.UTF8);
                    }
                }
            }
            catch
            {
                // Diagnostics must never affect capture or tray availability.
            }
        }

        internal static string ExceptionDetails(string stage, Exception exception)
        {
            return "stage=" + stage +
                "; type=" + exception.GetType().FullName +
                "; message=" + exception.Message.Replace('\r', ' ').Replace('\n', ' ');
        }

        internal static double ElapsedMilliseconds(long startedTimestamp)
        {
            if (startedTimestamp == 0)
            {
                return 0;
            }
            return (Stopwatch.GetTimestamp() - startedTimestamp) * 1000.0 / Stopwatch.Frequency;
        }

        private static bool IsEnabledByEnvironment()
        {
            string value = Environment.GetEnvironmentVariable("BOLTSNIP_DIAGNOSTIC_LOG");
            return string.Equals(value, "1", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(value, "true", StringComparison.OrdinalIgnoreCase);
        }

        private static string GetLogPath()
        {
            string configured = Environment.GetEnvironmentVariable("BOLTSNIP_DIAGNOSTIC_LOG_PATH");
            if (!string.IsNullOrWhiteSpace(configured) && Path.IsPathRooted(configured))
            {
                return configured;
            }
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "BoltSnip",
                "diagnostic.log");
        }
    }
}
