using System;
using System.Threading;
using System.Windows.Forms;

namespace BoltSnip
{
    internal static class Program
    {
        private static Mutex _singleInstance;

        [STAThread]
        private static void Main()
        {
            DateTime startupTimeUtc = DateTime.UtcNow;
            bool createdNew;
            _singleInstance = new Mutex(true, "Local\\BoltSnip.SingleInstance", out createdNew);
            if (!createdNew)
            {
                _singleInstance.Dispose();
                return;
            }

            try
            {
                NativeMethods.EnableBestDpiAwareness();
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                ReleaseIdentity.LogStartup(startupTimeUtc);
                if (!ReleaseIdentity.IsCurrentVersionSupported)
                {
                    MessageBox.Show(
                        "检测到旧版本，请启动最新版 BoltSnip。",
                        ReleaseIdentity.ProductName,
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Warning);
                    return;
                }

                if (!LicenseManager.EnsureAuthorized())
                {
                    return;
                }

                Application.Run(new TrayApplicationContext());
            }
            finally
            {
                _singleInstance.ReleaseMutex();
                _singleInstance.Dispose();
            }
        }
    }
}
