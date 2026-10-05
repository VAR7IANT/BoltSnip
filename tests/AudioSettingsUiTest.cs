using System;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
namespace BoltSnip {
 internal static class AudioSettingsUiTest {
  private static void Check(bool okay,string message){if(!okay)throw new Exception(message);}
  private static void Paint(Control control,Graphics target,Point origin) {
   using(var bitmap=new Bitmap(control.Width,control.Height)){control.DrawToBitmap(bitmap,new Rectangle(Point.Empty,bitmap.Size));target.DrawImageUnscaled(bitmap,origin);}
   ComboBox combo = control as ComboBox;
   if (combo != null && combo.SelectedIndex >= 0)
   {
    using (Brush background = new SolidBrush(Color.White)) target.FillRectangle(background, origin.X, origin.Y, combo.Width - Math.Max(18, combo.Height), combo.Height);
    DrawItemEventArgs draw = new DrawItemEventArgs(target, combo.Font, new Rectangle(origin.X, origin.Y, combo.Width - Math.Max(18, combo.Height), combo.Height), combo.SelectedIndex, DrawItemState.ComboBoxEdit);
    typeof(ComboBox).GetMethod("OnDrawItem", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(combo, new object[] { draw });
   }
   foreach(Control child in control.Controls) {
    Check(child.Left>=0 && child.Top>=0 && child.Right<=control.ClientSize.Width && child.Bottom<=control.ClientSize.Height,"Control clipped: "+child.GetType().Name);
    Paint(child,target,new Point(origin.X+child.Left,origin.Y+child.Top));
   }
  }
  [STAThread]private static int Main(string[] args){
   try {
    Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
    Application.ThreadException += delegate(object sender, System.Threading.ThreadExceptionEventArgs error) { Console.Error.WriteLine(error.Exception); Environment.Exit(1); };
    NativeMethods.EnableBestDpiAwareness();Application.EnableVisualStyles();string root=args[0];Directory.CreateDirectory(root);
    var settings=AppSettings.Load(Path.Combine(root,"ui-settings-"+Guid.NewGuid().ToString("N")+".ini"),null);
    settings.RecordMicrophone=true;settings.MicrophoneVolume=100;
    foreach(var device in MicrophoneDevices.List())if(device.Name.Contains("AB13X"))settings.MicrophoneDeviceId=device.Id;
    var flags=BindingFlags.Instance|BindingFlags.NonPublic;
    foreach(int dpi in new int[]{96,120,144,192})using(var dialog=new AudioSettingsDialog(settings)) {
     IntPtr nativeHandle=dialog.Handle; typeof(AudioSettingsDialog).GetMethod("ApplyDpi",flags).Invoke(dialog,new object[]{dpi});
     typeof(AudioSettingsDialog).GetMethod("ApplyDpi",flags).Invoke(dialog,new object[]{dpi});
     using(var image=new Bitmap(dialog.Width,dialog.Height))using(var graphics=Graphics.FromImage(image)){graphics.Clear(Color.FromArgb(238,242,247));Paint(dialog,graphics,Point.Empty);image.Save(Path.Combine(root,"audio-ui-"+dpi+".png"));}
     Check(!dialog.Visible,"Hidden preview showed a window");
     Console.WriteLine("PASS: UI bounds at DPI "+dpi);
    }
    using(var dialog=new AudioSettingsDialog(settings)) {
     var slider=(AudioVolumeSlider)typeof(AudioSettingsDialog).GetField("_volume",flags).GetValue(dialog);
     typeof(AudioVolumeSlider).GetMethod("OnKeyDown",flags).Invoke(slider,new object[]{new KeyEventArgs(Keys.Right)});Check(slider.Value==105,"Right key failed");
     typeof(AudioVolumeSlider).GetMethod("OnKeyDown",flags).Invoke(slider,new object[]{new KeyEventArgs(Keys.Left|Keys.Shift)});Check(slider.Value==104,"Fine adjustment failed");
     typeof(AudioVolumeSlider).GetMethod("UpdateValue",flags).Invoke(slider,new object[]{-100});Check(slider.Value==0,"Slider left bound failed");
     typeof(AudioVolumeSlider).GetMethod("UpdateValue",flags).Invoke(slider,new object[]{slider.Width+100});Check(slider.Value==200,"Slider right bound failed");
     Check(settings.MicrophoneVolume==100,"Draft volume changed settings before Save");
     slider.Value=125;
     typeof(AudioSettingsDialog).GetMethod("SaveClicked",flags).Invoke(dialog,new object[]{null,EventArgs.Empty});
     var loaded=AppSettings.Load(settingsPath(settings),null);Check(loaded.RecordMicrophone && loaded.MicrophoneVolume==125 && loaded.MicrophoneDeviceId==settings.MicrophoneDeviceId,"Save failed to persist audio choices");
    }
    using(var canceled=new AudioSettingsDialog(settings)) {
     ((CheckBox)typeof(AudioSettingsDialog).GetField("_enabled",flags).GetValue(canceled)).Checked=false;
     ((AudioVolumeSlider)typeof(AudioSettingsDialog).GetField("_volume",flags).GetValue(canceled)).Value=25;
     canceled.DialogResult=DialogResult.Cancel;canceled.Close();Check(settings.RecordMicrophone && settings.MicrophoneVolume==125,"Cancel changed live settings");
    }
    Console.WriteLine("PASS: keyboard, slider limits, draft isolation, Save and Cancel");return 0;
   }catch(Exception error){Console.Error.WriteLine(error);return 1;}
  }
  private static string settingsPath(AppSettings settings){return (string)typeof(AppSettings).GetField("_settingsPath",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(settings);}
 }
}