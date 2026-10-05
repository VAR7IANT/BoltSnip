using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
namespace BoltSnip {
    internal static class ReplaySavedToastTest {
        [STAThread] private static int Main(string[] args) {
            BindingFlags flags = BindingFlags.Instance | BindingFlags.NonPublic;
            using (ReplaySavedToast toast = new ReplaySavedToast()) {
                Type type = typeof(ReplaySavedToast);
                CreateParams style = (CreateParams)type.GetProperty("CreateParams", flags).GetValue(toast, null);
                int required = 0x08000000 | 0x00000080 | 0x00000020 | 0x00080000;
                if ((style.ExStyle & required) != required || toast.ShowInTaskbar || !toast.TopMost) throw new Exception("Overlay window style failed");
                if (!(bool)type.GetProperty("ShowWithoutActivation", flags).GetValue(toast, null)) throw new Exception("Overlay can activate");
                foreach (int dpi in new int[] { 96, 144, 192 }) {
                    float scale = dpi / 96F;
                    type.GetField("_scale", flags).SetValue(toast, scale);
                    type.GetField("_message", flags).SetValue(toast, "BoltSnip-Replay-20261006-001500.mp4 · 300 秒");
                    toast.ClientSize = new Size((int)(344 * scale), (int)(76 * scale));
                    using (Bitmap preview = new Bitmap(toast.Width, toast.Height)) {
                        toast.DrawToBitmap(preview, new Rectangle(Point.Empty, preview.Size));
                        preview.Save(Path.Combine(args[0], "saved-toast-" + dpi + ".png"), ImageFormat.Png);
                    }
                    if (toast.Visible) throw new Exception("Preview must not show a window");
                }
                MethodInfo wndProc = type.GetMethod("WndProc", flags);
                object[] hitTest = new object[] { Message.Create(IntPtr.Zero, 0x0084, IntPtr.Zero, IntPtr.Zero) };
                wndProc.Invoke(toast, hitTest);
                if (((Message)hitTest[0]).Result != new IntPtr(-1)) throw new Exception("Mouse hit-test not transparent");
                object[] activate = new object[] { Message.Create(IntPtr.Zero, 0x0021, IntPtr.Zero, IntPtr.Zero) };
                wndProc.Invoke(toast, activate);
                if (((Message)activate[0]).Result != new IntPtr(3)) throw new Exception("Mouse activation not blocked");
                Console.WriteLine("PASS: no activation, mouse-through, no taskbar entry, topmost; hidden previews at 96/144/192 DPI");
            }
            return 0;
        }
    }
}