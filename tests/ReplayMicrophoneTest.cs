using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;
namespace BoltSnip {
 internal static class ReplayMicrophoneTest {
  private static void Require(bool value,string message) { if(!value)throw new Exception(message); }
  private static string RunFfmpeg(string path,string arguments) {
   using(var process=new Process()) {
    process.StartInfo=new ProcessStartInfo(path,arguments){UseShellExecute=false,CreateNoWindow=true,RedirectStandardError=true};
    var errors=new StringBuilder();process.ErrorDataReceived+=delegate(object sender,DataReceivedEventArgs e){if(e.Data!=null)lock(errors)errors.AppendLine(e.Data);};
    process.Start();process.BeginErrorReadLine();if(!process.WaitForExit(20000)){process.Kill();throw new Exception("FFmpeg timeout");}process.WaitForExit();
    Require(process.ExitCode==0,errors.ToString());return errors.ToString();
   }
  }
  private static double ToneAmplitude(float[] values,int frequency) {
   int begin=4800,end=Math.Min(values.Length,48000);double sine=0,cosine=0;for(int i=begin;i<end;i++){double angle=2*Math.PI*frequency*i/48000;sine+=values[i]*Math.Sin(angle);cosine+=values[i]*Math.Cos(angle);}return 2*Math.Sqrt(sine*sine+cosine*cosine)/(end-begin);
  }
  [STAThread] private static int Main(string[] args) {
   try {
    NativeMethods.EnableBestDpiAwareness();Application.EnableVisualStyles();
    string root=args[0],ffmpeg=args[1];Directory.CreateDirectory(root);
    string config=Path.Combine(root,"settings-"+Guid.NewGuid().ToString("N")+".ini");AppSettings settings=AppSettings.Load(config,null);
    Require(!settings.RecordMicrophone && settings.MicrophoneVolume==100,"Microphone must default off at unity gain");
    settings.RecordMicrophone=true;settings.MicrophoneDeviceId="test-endpoint";settings.MicrophoneVolume=75;settings.Save();
    AppSettings restored=AppSettings.Load(config,null);Require(restored.RecordMicrophone && restored.MicrophoneDeviceId=="test-endpoint" && restored.MicrophoneVolume==75,"Audio settings persistence failed");
    using(var dialog=new AudioSettingsDialog(restored)) {
     var flags=BindingFlags.Instance|BindingFlags.NonPublic;
     ((CheckBox)typeof(AudioSettingsDialog).GetField("_enabled",flags).GetValue(dialog)).Checked=false;
     ((AudioVolumeSlider)typeof(AudioSettingsDialog).GetField("_volume",flags).GetValue(dialog)).Value=15;
     using(var image=new Bitmap(dialog.Width,dialog.Height)){dialog.DrawToBitmap(image,new Rectangle(Point.Empty,image.Size));
      using(var canvas=Graphics.FromImage(image)) {
       Point origin=dialog.PointToScreen(Point.Empty); Point outer=dialog.Location;
       foreach(Control control in dialog.Controls) {
        Require(control.Right<=dialog.ClientSize.Width && control.Bottom<=dialog.ClientSize.Height,"Audio setting control clipped");
        using(var child=new Bitmap(control.Width,control.Height)){control.DrawToBitmap(child,new Rectangle(Point.Empty,child.Size));canvas.DrawImageUnscaled(child,control.Left+origin.X-outer.X,control.Top+origin.Y-outer.Y);}
       }
      }
      image.Save(Path.Combine(root,"audio-settings.png"));}
     Require(restored.RecordMicrophone && restored.MicrophoneVolume==75,"Draft dialog changed persisted state before Save");
    }
    Console.WriteLine("PASS: default off, persistence, Cancel/draft isolation");
    foreach(var device in MicrophoneDevices.List())Console.WriteLine("Microphone device: "+device.Name);
    var invalidSettings=new ReplaySettings(TimeSpan.FromSeconds(12),60,2,true,ReplayCaptureBackend.DdaGrab);
    typeof(ReplaySettings).GetField("capture_microphone",BindingFlags.Instance|BindingFlags.NonPublic).SetValue(invalidSettings,true);
    typeof(ReplaySettings).GetField("microphone_device_id",BindingFlags.Instance|BindingFlags.NonPublic).SetValue(invalidSettings,"missing-microphone-endpoint");
    using(var session=ReplayAudioCaptureSession.Create(invalidSettings)){session.WaitUntilPrepared(5000);Require(session.Microphone==null && session.MicrophoneState==ReplayAudioState.Unavailable,"Invalid mic must preserve the system-audio session");}
    Console.WriteLine("PASS: missing microphone preserves system audio");
    var audioFormat=ReplayAudioFormat.Parse(3,1,48000,32,4,0,32,Guid.Empty);
    foreach(double gain in new double[]{1,0}) {
     var encoderSettings=new ReplaySettings(TimeSpan.FromSeconds(12),60,2,true);
     typeof(ReplaySettings).GetField("microphone_gain",BindingFlags.Instance|BindingFlags.NonPublic).SetValue(encoderSettings,gain);
     string mixRoot=Path.Combine(root,gain==0?"gain-zero":"gain-one");Directory.CreateDirectory(mixRoot);
     string arguments=ReplayEncoder.BuildArgumentsCore(Path.Combine(mixRoot,"segments.csv"),Path.Combine(mixRoot,"segment_%08d.mp4"),"-f lavfi -i color=c=black:s=320x180:r=60:d=3 ","-f lavfi -i sine=frequency=700:sample_rate=48000:duration=3 ",audioFormat,encoderSettings,"-f lavfi -i sine=frequency=1100:sample_rate=44100:duration=3 ");
     RunFfmpeg(ffmpeg,arguments);
     string decoded=Path.Combine(mixRoot,"audio.f32");RunFfmpeg(ffmpeg,"-hide_banner -loglevel error -y -i "+ReplayProcessSupport.QuoteArgument(Path.Combine(mixRoot,"segment_00000000.mp4"))+" -vn -ar 48000 -ac 1 -f f32le "+ReplayProcessSupport.QuoteArgument(decoded));
     byte[] bytes=File.ReadAllBytes(decoded);float[] samples=new float[bytes.Length/4];Buffer.BlockCopy(bytes,0,samples,0,bytes.Length);
     double game=ToneAmplitude(samples,700),mic=ToneAmplitude(samples,1100);
     Require(game>0.03,"Game audio disappeared during mix");Require(gain==0?mic<0.001:mic>0.03,"Mic gain/mixing failed");
     Console.WriteLine("PASS: mixed 48k/44.1k inputs; gain="+gain+", game="+game.ToString("F4")+", mic="+mic.ToString("F4"));
    }
    return 0;
   }catch(Exception error){Console.Error.WriteLine(error);return 1;}
  }
 }
}