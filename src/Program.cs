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
            bool createdNew;
            _singleInstance = new Mutex(true, "Local\\BoltSnip.SingleInstance", out createdNew);
            if (!createdNew)
            {
                return;
            }

            NativeMethods.EnableBestDpiAwareness();
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            try
            {
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
