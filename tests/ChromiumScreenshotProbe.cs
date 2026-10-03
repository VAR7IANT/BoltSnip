using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows.Forms;

class ChromiumScreenshotProbe
{
    const BindingFlags Hidden=BindingFlags.Static|BindingFlags.Public|BindingFlags.NonPublic;
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left,Top,Right,Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct PointNative {public int X,Y;public PointNative(int x,int y){X=x;Y=y;}}
    delegate bool EnumProc(IntPtr hwnd,IntPtr state);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc fn,IntPtr state);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd,StringBuilder text,int count);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd,out Rect rect);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hwnd,int command);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(PointNative point);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr hwnd,uint flags);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hwnd,uint message,IntPtr w,IntPtr l);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd,IntPtr dc);
    [DllImport("gdi32.dll")] static extern uint GetPixel(IntPtr dc,int x,int y);
    [StructLayout(LayoutKind.Sequential)] struct Header {public uint Size;public int Width,Height;public ushort Planes,BitCount;public uint Compression,SizeImage;public int XPels,YPels;public uint ColorsUsed,ColorsImportant;}
    [StructLayout(LayoutKind.Sequential)] struct Info {public Header Header;public uint Color0,Color1;}
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateDIBSection(IntPtr dc,ref Info info,uint usage,out IntPtr bits,IntPtr section,uint offset);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc,IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern bool BitBlt(IntPtr dst,int x,int y,int w,int h,IntPtr src,int sx,int sy,uint rop);
    static StreamWriter log,metrics,pixels;
    static MethodInfo capture;
    static Rectangle desktop;
    static string output;
    static int sampleSpacing=1;
    static long totalBad,totalAnomalies;
    static long totalTemporalChanges;
    static IntPtr ownedWindow,ownedLayered;
    static void Note(string message){log.WriteLine(DateTime.UtcNow.ToString("O")+"\tQPC="+Stopwatch.GetTimestamp()+"\t"+message);log.Flush();}
    static string Quote(string s){if(s.Contains("\""))throw new ArgumentException("Argument contains quote");return "\""+s+"\"";}
    static IntPtr Find(int pid,string token){IntPtr found=IntPtr.Zero;EnumWindows(delegate(IntPtr hwnd,IntPtr state){uint actual;GetWindowThreadProcessId(hwnd,out actual);if(actual!=(uint)pid)return true;StringBuilder title=new StringBuilder(1024);GetWindowText(hwnd,title,title.Capacity);if(title.ToString().Contains(token)){found=hwnd;return false;}return true;},IntPtr.Zero);return found;}
    static Bitmap Native(Rectangle r){IntPtr dc=GetDC(IntPtr.Zero),mem=IntPtr.Zero,dib=IntPtr.Zero,old=IntPtr.Zero;
        try{if(dc==IntPtr.Zero)throw new Exception("GetDC failed");mem=CreateCompatibleDC(dc);if(mem==IntPtr.Zero)throw new Exception("CreateCompatibleDC failed");
            Info i=new Info();i.Header.Size=(uint)Marshal.SizeOf(typeof(Header));i.Header.Width=r.Width;i.Header.Height=-r.Height;i.Header.Planes=1;i.Header.BitCount=32;i.Header.SizeImage=checked((uint)((long)r.Width*r.Height*4));
            IntPtr bits;dib=CreateDIBSection(dc,ref i,0,out bits,IntPtr.Zero,0);if(dib==IntPtr.Zero||bits==IntPtr.Zero)throw new Exception("CreateDIBSection failed");old=SelectObject(mem,dib);if(old==IntPtr.Zero||old==new IntPtr(-1))throw new Exception("SelectObject failed");
            if(!BitBlt(mem,0,0,r.Width,r.Height,dc,r.Left,r.Top,0x40CC0020))throw new Exception("Native BitBlt failed");return Bitmap.FromHbitmap(dib);
        }finally{if(old!=IntPtr.Zero&&old!=new IntPtr(-1))SelectObject(mem,old);if(dib!=IntPtr.Zero)DeleteObject(dib);if(mem!=IntPtr.Zero)DeleteDC(mem);if(dc!=IntPtr.Zero)ReleaseDC(IntPtr.Zero,dc);}
    }
    static byte[] Bytes(Bitmap bitmap){int bpp=Image.GetPixelFormatSize(bitmap.PixelFormat)/8;if(bpp!=4&&bpp!=3)throw new Exception("Unsupported format "+bitmap.PixelFormat);byte[] all=new byte[checked(bitmap.Width*bitmap.Height*4)];
        BitmapData d=bitmap.LockBits(new Rectangle(0,0,bitmap.Width,bitmap.Height),ImageLockMode.ReadOnly,bitmap.PixelFormat);
        try{byte[] row=new byte[bitmap.Width*bpp];for(int y=0;y<bitmap.Height;y++){Marshal.Copy(IntPtr.Add(d.Scan0,y*d.Stride),row,0,row.Length);for(int x=0;x<bitmap.Width;x++){int p=(y*bitmap.Width+x)*4;all[p]=row[x*bpp];all[p+1]=row[x*bpp+1];all[p+2]=row[x*bpp+2];all[p+3]=bpp==3||bitmap.PixelFormat==PixelFormat.Format32bppRgb?(byte)255:row[x*bpp+3];}}}finally{bitmap.UnlockBits(d);}return all;
    }
    static void VerifyVisible(Rectangle region,Rectangle layered){
        // Physical point ownership verifies exposure rather than assuming SetForegroundWindow worked.
        for(int y=region.Top+1;y<region.Bottom;y+=40)for(int x=region.Left+1;x<region.Right;x+=40){IntPtr root=GetAncestor(WindowFromPoint(new PointNative(x,y)),2);
            if(root!=ownedWindow&&!(layered.Contains(x,y)&&root==ownedLayered))throw new Exception("INFRASTRUCTURE INVALID: intended browser ROI occluded at "+x+","+y+"; actualRootHwnd="+root+"; ownedBrowser="+ownedWindow+"; no product-failure attribution");
        }
    }
    static void Compare(string label,Rectangle region,Rectangle layered,int count){
        Note(label+" region="+region+"; iterations="+count+"; NativeBefore -> Product -> NativeAfter temporal bracket; static scene required; not simultaneous; reference shares underlying BitBlt API, avoids GDI+ HDC target; point ownership grid40px before/after each bracket");
        for(int iteration=1;iteration<=count;iteration++){
            VerifyVisible(region,layered);byte[] before;
            using(Bitmap nativeBefore=Native(desktop)){before=Bytes(nativeBefore);if(iteration==1)nativeBefore.Save(Path.Combine(output,label+"-native-before.png"),ImageFormat.Png);}
            long start=Stopwatch.GetTimestamp();using(Bitmap bitmap=(Bitmap)capture.Invoke(null,new object[]{desktop})){
                double elapsed=(Stopwatch.GetTimestamp()-start)*1000.0/Stopwatch.Frequency;byte[] data=Bytes(bitmap);byte[] reference;
                using(Bitmap native=Native(desktop)){reference=Bytes(native);if(iteration==1)native.Save(Path.Combine(output,label+"-native-reference.png"),ImageFormat.Png);}
                VerifyVisible(region,layered);
                long compared=0,bad=0,anomalies=0,alphaBad=0,layeredCount=0,layeredBad=0,temporal=0;
                for(int y=region.Top;y<region.Bottom;y+=sampleSpacing)for(int x=region.Left;x<region.Right;x+=sampleSpacing){
                    int p=((y-desktop.Top)*bitmap.Width+x-desktop.Left)*4,r=reference[p+2],g=reference[p+1],b=reference[p];
                    bool same=data[p]==b&&data[p+1]==g&&data[p+2]==r&&data[p+3]==255;
                    if(before[p]!=reference[p]||before[p+1]!=reference[p+1]||before[p+2]!=reference[p+2]||before[p+3]!=reference[p+3])temporal++;
                    int min=Math.Min(data[p],Math.Min(data[p+1],data[p+2])),max=Math.Max(data[p],Math.Max(data[p+1],data[p+2]));
                    bool anomaly=data[p+3]==0||(Math.Max(r,Math.Max(g,b))<80&&((min>=180&&max-min<=25)||min>=235));
                    compared++;if(!same)bad++;if(anomaly)anomalies++;if(data[p+3]!=255)alphaBad++;
                    if(layered.Contains(x,y)){layeredCount++;if(!same)layeredBad++;}
                    if(!same||anomaly)pixels.WriteLine(label+"\t"+iteration+"\t"+x+"\t"+y+"\t"+r+","+g+","+b+",255\t"+data[p+2]+","+data[p+1]+","+data[p]+","+data[p+3]+"\t"+anomaly);
                }
                metrics.WriteLine(label+"\t"+iteration+"\t"+bitmap.PixelFormat+"\t"+compared+"\t"+bad+"\t"+anomalies+"\t"+alphaBad+"\t"+layeredCount+"\t"+layeredBad+"\t"+elapsed.ToString("F6",CultureInfo.InvariantCulture)+"\t"+temporal+"\t"+(temporal==0?"STATIC":"TEMPORALLY UNSTABLE"));metrics.Flush();pixels.Flush();
                totalBad+=bad;totalAnomalies+=anomalies;totalTemporalChanges+=temporal;
                if(iteration==1){bitmap.Save(Path.Combine(output,label+"-full.png"),ImageFormat.Png);using(Bitmap roi=bitmap.Clone(new Rectangle(region.X-desktop.X,region.Y-desktop.Y,region.Width,region.Height),bitmap.PixelFormat))roi.Save(Path.Combine(output,label+"-roi.png"),ImageFormat.Png);}
                if(!layered.IsEmpty&&layeredCount==0)throw new Exception("Layered window not sampled");
            }
            Application.DoEvents();
        }
    }
    [STAThread] static int Main(string[] args){
        output=args[1];Directory.CreateDirectory(output);log=new StreamWriter(Path.Combine(output,"browser.log"));metrics=new StreamWriter(Path.Combine(output,"browser-metrics.tsv"));pixels=new StreamWriter(Path.Combine(output,"browser-anomaly-pixels.tsv"));
        metrics.WriteLine("scene\titeration\tformat\tsamples\tRGBA_mismatches\tanomalies\talphaNot255\tlayeredSamples\tlayeredMismatches\tcaptureMilliseconds\tNativeBeforeAfterMismatchPixels\tSceneStability");pixels.WriteLine("scene\titeration\tphysicalX\tphysicalY\tnativeRGBA\tstoredCaptureRGBA\tcandidateAnomaly");
        Process browser=null;IntPtr hwnd=IntPtr.Zero;Form layered=null;
        try{
            try{if(!SetProcessDpiAwarenessContext(new IntPtr(-4)))SetProcessDPIAware();}catch(EntryPointNotFoundException){SetProcessDPIAware();}
            Assembly assembly=Assembly.LoadFrom(args[0]);capture=assembly.GetType("BoltSnip.ScreenCapture",true).GetMethod("Capture",Hidden);
            using(SHA256 sha=SHA256.Create())using(FileStream file=File.OpenRead(args[0]))Note("ProductExe="+args[0]+"; ExeSHA256="+BitConverter.ToString(sha.ComputeHash(file)).Replace("-","")+"; ActualCapture=reflection Product ScreenCapture.Capture");
            Type identity=assembly.GetType("BoltSnip.BuildIdentityValues");if(identity!=null)foreach(string name in new string[]{"BuildId","BuildTimeUtc","BuildCommit"}){FieldInfo f=identity.GetField(name,Hidden);if(f!=null)Note("Embedded."+name+"="+f.GetValue(null));}
            desktop=SystemInformation.VirtualScreen;Rectangle work=Screen.PrimaryScreen.WorkingArea;
            string profile=Path.Combine(output,"owned-edge-profile");Directory.CreateDirectory(profile);
            string arguments="--user-data-dir="+Quote(profile)+" --no-first-run --no-default-browser-check --disable-background-networking --disable-sync --disable-extensions --disable-component-update --host-resolver-rules="+Quote("MAP * ~NOTFOUND")+" --proxy-server=direct:// --new-window "+Quote(args[3]);
            Note("Owned Edge profile="+profile+"; arguments="+arguments+"; default GPU enabled; actual hardware acceleration NOT VERIFIED; fixture CSP blocks network; QPCFrequency="+Stopwatch.Frequency);
            ProcessStartInfo info=new ProcessStartInfo(args[2],arguments);info.UseShellExecute=false;info.WindowStyle=ProcessWindowStyle.Hidden;browser=Process.Start(info);Note("OwnedEdgePid="+browser.Id);
            Stopwatch wait=Stopwatch.StartNew();while(wait.ElapsedMilliseconds<30000){if(browser.HasExited)throw new Exception("Owned Edge launcher exited before identifying its window");hwnd=Find(browser.Id,args[4]);if(hwnd!=IntPtr.Zero)break;Thread.Sleep(100);}
            if(hwnd==IntPtr.Zero)throw new Exception("No owned Edge window with fixture token; unrelated browser windows are never used");
            ownedWindow=hwnd;
            ShowWindow(hwnd,9);if(!SetWindowPos(hwnd,new IntPtr(-1),work.Left+20,work.Top+20,Math.Min(1400,work.Width-40),Math.Min(1200,work.Height-40),0x0040))throw new Exception("Cannot make OWNED browser topmost");SetForegroundWindow(hwnd);Thread.Sleep(1200);
            Note("Owned browser HWND_TOPMOST; historical unbracketed run with unrelated Antigravity window occlusion is invalid browser evidence; existing mismatches retained, no product-failure attribution");
            Rect bounds;if(!GetWindowRect(hwnd,out bounds))throw new Exception("GetWindowRect failed");
            Rectangle region=Rectangle.Intersect(desktop,new Rectangle(bounds.Left+45,bounds.Top+180,Math.Min(1120,bounds.Right-bounds.Left-90),Math.Min(850,bounds.Bottom-bounds.Top-230)));
            if(region.Width<640||region.Height<400)throw new Exception("Owned browser capture region too small: "+region);
            int count=int.Parse(args[5]);if(count<1)throw new Exception("Invalid iterations");
            sampleSpacing=args.Length>6?int.Parse(args[6]):1;if(sampleSpacing<1)throw new Exception("Invalid sample spacing");
            Note("Desktop="+desktop+"; ownedHwnd="+hwnd+"; sampleSpacing="+sampleSpacing+" physical pixels; exact RGB/A comparisons in stated ROI only; spacing1=every ROI pixel; larger spacing=sampled evidence");
            Compare("chromium-static",region,Rectangle.Empty,count);
            Rectangle layeredRegion=new Rectangle(region.Left+90,region.Top+90,230,180);
            layered=new Form();layered.FormBorderStyle=FormBorderStyle.None;layered.StartPosition=FormStartPosition.Manual;layered.AutoScaleMode=AutoScaleMode.None;layered.Bounds=layeredRegion;layered.TopMost=true;layered.ShowInTaskbar=false;layered.BackColor=Color.FromArgb(30,130,210);layered.Opacity=.45;layered.Show();ownedLayered=layered.Handle;layered.Update();Application.DoEvents();Thread.Sleep(300);
            Compare("chromium-layered-opacity45",region,layeredRegion,Math.Min(count,10));
            Note("TotalMismatchSamples="+totalBad+"; TotalCandidateAnomalies="+totalAnomalies+"; NativeBracketChangedPixels="+totalTemporalChanges+"; browserScroll/windowMove/hover/video/WebGL=NOT RUN; actualGpuAcceleration=UNVERIFIED; multi-monitor and DPI matrix separate");
            bool pass=totalBad==0&&totalAnomalies==0&&totalTemporalChanges==0;
            Note(pass?"STATIC BROWSER AND LAYERED ROI CHECK PASS":totalTemporalChanges!=0?"INFRASTRUCTURE TEMPORALLY UNSTABLE; mismatch rows retained; acceptance NOT PASS":"STATIC BROWSER OR LAYERED ROI CHECK FAIL");return pass?0:1;
        }catch(Exception ex){Note("FAIL "+ex);return 1;}
        finally{
            if(layered!=null)layered.Dispose();
            if(browser!=null){try{if(hwnd!=IntPtr.Zero){uint owner;GetWindowThreadProcessId(hwnd,out owner);if(owner==(uint)browser.Id)PostMessage(hwnd,0x0010,IntPtr.Zero,IntPtr.Zero);}if(!browser.WaitForExit(4000)){Note("Owned Edge did not close promptly; terminate ONLY owned PID "+browser.Id);browser.Kill();browser.WaitForExit(4000);}Note("OwnedEdgeExited="+browser.HasExited+"; profile retained as evidence; no unrelated process cleanup");}catch(Exception ex){Note("OwnedEdgeCleanupFailed="+ex.Message);}browser.Dispose();}
            metrics.Dispose();pixels.Dispose();log.Dispose();
        }
    }
}
