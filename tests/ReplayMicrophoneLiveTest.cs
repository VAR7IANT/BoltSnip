using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading;
namespace BoltSnip {
 internal static class ReplayMicrophoneLiveTest {
  private static void Check(bool success,string message){if(!success)throw new Exception(message);}
  private static void Configure(ReplaySettings settings,string name,object value){typeof(ReplaySettings).GetField(name,BindingFlags.Instance|BindingFlags.NonPublic).SetValue(settings,value);}
  [STAThread] private static int Main(string[] args){
   NativeMethods.EnableBestDpiAwareness(); string root=args[0];Directory.CreateDirectory(root);
   Environment.SetEnvironmentVariable("TEMP",root);Environment.SetEnvironmentVariable("TMP",root);
   Environment.SetEnvironmentVariable("BOLTSNIP_FFMPEG_PATH",args[1]);
   Environment.SetEnvironmentVariable("BOLTSNIP_REPLAY_OUTPUT_DIRECTORY",Path.Combine(root,"output"));
   Environment.SetEnvironmentVariable("BOLTSNIP_DIAGNOSTIC_LOG","1");Environment.SetEnvironmentVariable("BOLTSNIP_DIAGNOSTIC_LOG_PATH",Path.Combine(root,"diagnostic.log"));
   try {
    var settings=new ReplaySettings(TimeSpan.FromSeconds(12),60,2,true,ReplayCaptureBackend.DdaGrab);
    Configure(settings,"capture_microphone",true);Configure(settings,"microphone_device_id",args.Length>2?args[2]:string.Empty);
    using(var manager=new ReplayManager(settings)){
     manager.Start();var ready=Stopwatch.StartNew();while(manager.State==ReplayState.Starting && ready.Elapsed.TotalSeconds<20)Thread.Sleep(50);
     Check(manager.State==ReplayState.Recording,"Not recording: "+manager.LastError);
     Check(manager.AudioState==ReplayAudioState.Active,"System audio inactive");Check(manager.MicrophoneState==ReplayAudioState.Active,"Microphone unavailable");
     var session=(ReplayAudioCaptureSession)typeof(ReplayManager).GetField("_audioSession",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(manager);
     Console.WriteLine("LIVE: system + microphone active");Thread.Sleep(8000);
     Check(session.Microphone.WrittenDurationSeconds>6,"Mic input did not advance");
     Console.WriteLine("LIVE: microphone seconds="+session.Microphone.WrittenDurationSeconds.ToString("F3")+", system seconds="+session.WrittenDurationSeconds.ToString("F3"));
     var buffer=(ReplayBuffer)typeof(ReplayManager).GetField("_buffer",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(manager);int before=buffer.LatestIndex;
     session.Microphone.Stop();Thread.Sleep(4500);
     Check(manager.State==ReplayState.Recording && manager.AudioState==ReplayAudioState.Active && buffer.LatestIndex>before,"Mic stop stalled game recording");
     Console.WriteLine("PASS: game recording continues after microphone stream stops");
     Check(manager.SaveReplay(),"Could not request test save");var saved=Stopwatch.StartNew();while(manager.IsSaving && saved.Elapsed.TotalSeconds<15)Thread.Sleep(50);
     Check(!manager.IsSaving,"Save did not finish");ReplayNotification notification;bool succeeded=false;while(manager.TryDequeueNotification(out notification)){if(notification.Kind==ReplayNotificationKind.SaveSucceeded)succeeded=true;}
     Check(succeeded,"Mixed replay save did not succeed");manager.Stop();
     Console.WriteLine("PASS: real mixed replay saved; recording stopped cleanly");
    }
    return 0;
   }catch(Exception error){Console.Error.WriteLine(error);return 1;}
  }
 }
}