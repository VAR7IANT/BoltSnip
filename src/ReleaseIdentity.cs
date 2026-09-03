using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Windows.Forms;

namespace BoltSnip
{
    internal static class ReleaseIdentity
    {
        private static readonly Version MinimumSupported =
            new Version(BuildIdentityValues.MinimumSupportedVersion);

        internal static string ProductName
        {
            get { return BuildIdentityValues.ProductName; }
        }

        internal static string Version
        {
            get { return BuildIdentityValues.Version; }
        }

        internal static string BuildTimeUtc
        {
            get { return BuildIdentityValues.BuildTimeUtc; }
        }

        internal static string BuildId
        {
            get { return BuildIdentityValues.BuildId; }
        }

        internal static bool IsCurrentVersionSupported
        {
            get { return IsSupportedVersion(typeof(ReleaseIdentity).Assembly.GetName().Version); }
        }

        internal static bool IsSupportedVersion(Version version)
        {
            return version != null && version.CompareTo(MinimumSupported) >= 0;
        }

        internal static void LogStartup(DateTime startupTimeUtc)
        {
            using (Process process = Process.GetCurrentProcess())
            {
                CaptureDiagnostics.Write(
                    "Startup",
                    CreateStartupDetails(
                        Application.ExecutablePath,
                        process.Id,
                        startupTimeUtc));
            }
        }

        internal static string CreateStartupDetails(
            string executablePath,
            int processId,
            DateTime startupTimeUtc)
        {
            string fullPath = string.IsNullOrWhiteSpace(executablePath)
                ? string.Empty
                : Path.GetFullPath(executablePath);
            fullPath = fullPath.Replace('\r', ' ').Replace('\n', ' ');
            return "Version=" + Version +
                "; Path=" + fullPath +
                "; PID=" + processId.ToString(CultureInfo.InvariantCulture) +
                "; StartedAtUtc=" + startupTimeUtc.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture) +
                "; BuildTimeUtc=" + BuildTimeUtc +
                "; BuildId=" + BuildId;
        }
    }
}
