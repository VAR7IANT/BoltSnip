using System;using System.Drawing;using System.IO;using System.Reflection;using System.Windows.Forms;
namespace BoltSnip {internal static class LicenseUiTest {
static BindingFlags Flags=BindingFlags.Instance|BindingFlags.NonPublic;
static Control Field(ActivationDialog form,string name){return (Control)typeof(ActivationDialog).GetField(name,Flags).GetValue(form);}
static void Check(bool value,string message){if(!value)throw new Exception(message);}
static void CheckBounds(Control c){foreach(Control child in c.Controls){Check(child.Left>=0&&child.Top>=0&&child.Right<=c.ClientSize.Width&&child.Bottom<=c.ClientSize.Height,"Clipped "+child.GetType().Name);CheckBounds(child);}}
static void Paint(Control c,Graphics graphics,Point p){using(var bitmap=new Bitmap(c.Width,c.Height)){c.DrawToBitmap(bitmap,new Rectangle(Point.Empty,bitmap.Size));graphics.DrawImageUnscaled(bitmap,p);}foreach(Control child in c.Controls)Paint(child,graphics,new Point(p.X+child.Left,p.Y+child.Top));}
static void Render(ActivationDialog form,string path,bool editing){using(var bitmap=new Bitmap(form.Width,form.Height))using(var graphics=Graphics.FromImage(bitmap)){form.DrawToBitmap(bitmap,new Rectangle(Point.Empty,bitmap.Size));string[] names=editing?new[]{"_title","_subtitle","_close","_onlineCard","_offlineCard","_status","_cancel"}:new[]{"_title","_subtitle","_close","_infoCard","_change","_revoke","_status","_cancel"};foreach(string name in names){var c=Field(form,name);Check(c.Right<=form.ClientSize.Width&&c.Bottom<=form.ClientSize.Height,"Root clipped "+name);CheckBounds(c);Paint(c,graphics,new Point(c.Left,c.Top));}bitmap.Save(path);}}
[STAThread]static int Main(string[] args){try{
Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);Application.ThreadException+=delegate(object sender,System.Threading.ThreadExceptionEventArgs e){Console.Error.WriteLine(e.Exception);Environment.Exit(1);};NativeMethods.EnableBestDpiAwareness();Application.EnableVisualStyles();Directory.CreateDirectory(args[0]);
foreach(int dpi in new[]{96,120,144,192})using(var form=new ActivationDialog("联网激活码","DEMO-KEY")){
IntPtr handle=form.Handle;var apply=typeof(ActivationDialog).GetMethod("ApplyDpi",Flags);apply.Invoke(form,new object[]{dpi});apply.Invoke(form,new object[]{dpi});Render(form,Path.Combine(args[0],"license-info-"+dpi+".png"),false);
Check(form.AcceptButton==Field(form,"_change"),"Wrong info default action");((Button)Field(form,"_change")).PerformClick();typeof(ActivationDialog).GetMethod("EnterEditor",Flags).Invoke(form,new object[0]);Render(form,Path.Combine(args[0],"license-editor-"+dpi+".png"),true);
Check(form.AcceptButton==Field(form,"_activate"),"Wrong editor default action");Check(form.CancelButton==Field(form,"_cancel"),"Wrong close action");Check(Field(form,"_key").Text=="","Changing authorization leaked current credential into input");Check(!form.Visible,"Preview opened a visible window");Console.WriteLine("PASS: info and editor at DPI "+dpi);
}
using(var form=new ActivationDialog(null,null)){Check(form.AcceptButton==Field(form,"_activate"),"Initial activation not ready");}
using(var confirm=new AuthorizationCancellationDialog()){Check(confirm.AcceptButton==confirm.CancelButton,"Confirmation must default to keeping authorization");}
Console.WriteLine("PASS: initial activation, editor transition and cancellation default");return 0;
}catch(Exception error){Console.Error.WriteLine(error);return 1;}}
}}