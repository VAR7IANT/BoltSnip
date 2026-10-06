using System;using System.Drawing;using System.Reflection;using System.Runtime.InteropServices;using System.Windows.Forms;
class LicenseTrayClickTest {
[DllImport("user32.dll")]static extern int SetWindowLong(IntPtr hwnd,int index,int value);
[DllImport("user32.dll")]static extern int GetWindowLong(IntPtr hwnd,int index);
[DllImport("user32.dll")]static extern IntPtr SendMessage(IntPtr hwnd,uint msg,IntPtr wp,IntPtr lp);
[DllImport("user32.dll")]static extern IntPtr GetForegroundWindow();
static void Offscreen(Form form){form.StartPosition=FormStartPosition.Manual;form.Location=new Point(-6000,-6000);SetWindowLong(form.Handle,-20,GetWindowLong(form.Handle,-20)|0x08000000);}
[STAThread]static int Main(string[] args){try{
Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);Application.ThreadException+=delegate(object s,System.Threading.ThreadExceptionEventArgs e){Console.Error.WriteLine(e.Exception);Environment.Exit(2);};Application.EnableVisualStyles();var assembly=Assembly.LoadFile(args[0]);var flags=BindingFlags.Instance|BindingFlags.NonPublic;var type=assembly.GetType("BoltSnip.TrayPopupForm",true);var dialogType=assembly.GetType("BoltSnip.ActivationDialog",true);int count=0;bool success=true;IntPtr foreground=GetForegroundWindow();Action noop=delegate{};
Action open=delegate{count++;using(var dialog=(Form)Activator.CreateInstance(dialogType,flags,null,new object[0],null)){Offscreen(dialog);var timer=new Timer{Interval=80};timer.Tick+=delegate{timer.Stop();bool topmost=(GetWindowLong(dialog.Handle,-20)&8)!=0;success=success&&dialog.Visible&&topmost;Console.WriteLine("click "+count+": visible="+dialog.Visible+", native topmost="+topmost);dialog.Close();};timer.Start();dialog.ShowDialog();timer.Dispose();}};
using(var tray=(Form)Activator.CreateInstance(type,flags,null,new object[]{noop,noop,noop,noop,noop,noop,open,noop},null)){
type.GetMethod("UpdatePresentation",flags).Invoke(tray,new object[]{"2.0.0","Ctrl+Alt+A","Ctrl+Alt+R",false,true});Offscreen(tray);
for(int i=0;i<3;i++){tray.Show();Application.DoEvents();var actionType=assembly.GetType("BoltSnip.TrayPopupAction",true);var licenseBounds=(Rectangle)type.GetMethod("GetLogicalBounds",BindingFlags.Static|BindingFlags.NonPublic).Invoke(null,new object[]{Enum.Parse(actionType,"License"),true});int x=tray.Width/2,y=(int)Math.Round((licenseBounds.Top+licenseBounds.Height/2.0)*tray.Width/336.0);IntPtr pos=new IntPtr((y<<16)|x);SendMessage(tray.Handle,0x201,new IntPtr(1),pos);SendMessage(tray.Handle,0x202,IntPtr.Zero,pos);if(count!=i+1)throw new Exception("Click did not open exactly one dialog");}
}
if(GetForegroundWindow()!=foreground)throw new Exception("Test changed foreground");Console.WriteLine(success?"PASS: first and repeated tray clicks create visible topmost dialogs":"FAIL: tray click creates an unprotected dialog");return success?0:1;
}catch(Exception error){Console.Error.WriteLine(error);return 2;}}
}