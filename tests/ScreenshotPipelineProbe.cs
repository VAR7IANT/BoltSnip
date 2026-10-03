using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Threading;
using System.Windows.Forms;

// Tests-only reflection harness: never substitutes a simulated overlay for the product.
class ScreenshotPipelineProbe
{
    class SourceScene : Form {
        public Bitmap Image;
        protected override void OnPaint(PaintEventArgs e) { e.Graphics.Clear(Color.FromArgb(13,11,12)); e.Graphics.DrawImageUnscaled(Image,0,0); }
    }
    const BindingFlags Hidden = BindingFlags.NonPublic | BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static;
    [StructLayout(LayoutKind.Sequential)] struct Header {
        public uint Size; public int Width,Height; public ushort Planes,BitCount;
        public uint Compression,SizeImage; public int XPels,YPels; public uint ColorsUsed,ColorsImportant;
    }
    [StructLayout(LayoutKind.Sequential)] struct Info { public Header Header; public uint Color0,Color1; }
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr w);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr w,IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateDIBSection(IntPtr dc,ref Info info,uint usage,out IntPtr bits,IntPtr section,uint offset);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc,IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern bool BitBlt(IntPtr dst,int x,int y,int w,int h,IntPtr src,int sx,int sy,uint rop);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern uint GetGuiResources(IntPtr process,uint flags);
    static StreamWriter log;
    static void Note(string s) { log.WriteLine(DateTime.UtcNow.ToString("O")+"\tQPC="+System.Diagnostics.Stopwatch.GetTimestamp()+"\t"+s); log.Flush(); }
    static Bitmap Native(Rectangle r) {
        IntPtr dc=GetDC(IntPtr.Zero),mem=IntPtr.Zero,dib=IntPtr.Zero,old=IntPtr.Zero;
        try {
            if(dc==IntPtr.Zero) throw new Exception("GetDC failed");
            mem=CreateCompatibleDC(dc); if(mem==IntPtr.Zero) throw new Exception("CreateCompatibleDC failed");
            Info i=new Info(); i.Header.Size=(uint)Marshal.SizeOf(typeof(Header));
            i.Header.Width=r.Width; i.Header.Height=-r.Height; i.Header.Planes=1;i.Header.BitCount=32;
            i.Header.SizeImage=checked((uint)((long)r.Width*r.Height*4));
            IntPtr bits; dib=CreateDIBSection(dc,ref i,0,out bits,IntPtr.Zero,0);
            if(dib==IntPtr.Zero||bits==IntPtr.Zero) throw new Exception("CreateDIBSection failed");
            old=SelectObject(mem,dib); if(old==IntPtr.Zero||old==new IntPtr(-1)) throw new Exception("SelectObject failed");
            if(!BitBlt(mem,0,0,r.Width,r.Height,dc,r.Left,r.Top,0x40CC0020)) throw new Exception("BitBlt failed");
            return Bitmap.FromHbitmap(dib);
        } finally {
            if(old!=IntPtr.Zero&&old!=new IntPtr(-1)) SelectObject(mem,old);
            if(dib!=IntPtr.Zero) DeleteObject(dib); if(mem!=IntPtr.Zero) DeleteDC(mem);
            if(dc!=IntPtr.Zero) ReleaseDC(IntPtr.Zero,dc);
        }
    }
    static byte[] Bytes(Bitmap b) {
        int bpp=Image.GetPixelFormatSize(b.PixelFormat)/8;
        if(bpp!=4&&bpp!=3) throw new Exception("Unexpected pixel format: "+b.PixelFormat);
        byte[] result=new byte[checked(b.Width*b.Height*4)];
        BitmapData d=b.LockBits(new Rectangle(0,0,b.Width,b.Height),ImageLockMode.ReadOnly,b.PixelFormat);
        try { for(int y=0;y<b.Height;y++) {
            if(bpp==4) Marshal.Copy(IntPtr.Add(d.Scan0,y*d.Stride),result,y*b.Width*4,b.Width*4);
            else {byte[] row=new byte[b.Width*3];Marshal.Copy(IntPtr.Add(d.Scan0,y*d.Stride),row,0,row.Length);for(int x=0;x<b.Width;x++){int o=(y*b.Width+x)*4;result[o]=row[x*3];result[o+1]=row[x*3+1];result[o+2]=row[x*3+2];result[o+3]=255;}}
        } }
        finally {b.UnlockBits(d);}
        if(b.PixelFormat==PixelFormat.Format32bppRgb) for(int i=3;i<result.Length;i+=4) result[i]=255;
        return result;
    }
    static string Pixel(byte[] b,int o) {return b[o+2]+","+b[o+1]+","+b[o]+","+b[o+3];}
    static bool Anomaly(byte[] a,int p,byte[] r,int q) {
        bool zero=a[p+3]==0;
        int min=Math.Min(a[p],Math.Min(a[p+1],a[p+2])),max=Math.Max(a[p],Math.Max(a[p+1],a[p+2]));
        int referenceMax=Math.Max(r[q],Math.Max(r[q+1],r[q+2]));
        return zero || (referenceMax<80 && ((min>=180&&max-min<=25)||min>=235));
    }
    static void Analyze(string dir,Rectangle roi,Rectangle desktop,Bitmap[] stages,string[] names) {
        byte[][] bytes=new byte[stages.Length][]; for(int s=0;s<stages.Length;s++) bytes[s]=Bytes(stages[s]);
        int[] mask=new int[roi.Width*roi.Height],component=new int[mask.Length];
        using(StreamWriter m=new StreamWriter(Path.Combine(dir,"metrics.tsv"))) {
            m.WriteLine("stage\tanomalies\tmismatchesAgainstStage0\tformat");
            for(int s=1;s<stages.Length;s++) {
                int anomalies=0,mismatches=0;
                for(int y=0;y<roi.Height;y++) for(int x=0;x<roi.Width;x++) {
                    int q=((roi.Y+y)*stages[0].Width+roi.X+x)*4;
                    int p=s<=2?((roi.Y+y)*stages[s].Width+roi.X+x)*4:(y*roi.Width+x)*4;
                    if(Anomaly(bytes[s],p,bytes[0],q)){mask[y*roi.Width+x]|=1<<s;anomalies++;}
                    if(Pixel(bytes[s],p)!=Pixel(bytes[0],q)) mismatches++;
                }
                m.WriteLine(names[s]+"\t"+anomalies+"\t"+mismatches+"\t"+stages[s].PixelFormat);
            }
        }
        int id=0;
        using(StreamWriter c=new StreamWriter(Path.Combine(dir,"components.tsv"))) {
            c.WriteLine("component\tpixels\tleft\ttop\tright\tbottom");
            for(int n=0;n<mask.Length;n++) if(mask[n]!=0&&component[n]==0) {
                id++;Queue<int> queue=new Queue<int>();queue.Enqueue(n);component[n]=id;
                int count=0,l=roi.Width,t=roi.Height,r=0,b=0;
                while(queue.Count>0){int k=queue.Dequeue(),x=k%roi.Width,y=k/roi.Width;count++;l=Math.Min(l,x);t=Math.Min(t,y);r=Math.Max(r,x);b=Math.Max(b,y);
                    for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){int xx=x+dx,yy=y+dy;if(xx<0||yy<0||xx>=roi.Width||yy>=roi.Height)continue;int j=yy*roi.Width+xx;if(mask[j]!=0&&component[j]==0){component[j]=id;queue.Enqueue(j);}}
                }c.WriteLine(id+"\t"+count+"\t"+(l+roi.X+desktop.X)+"\t"+(t+roi.Y+desktop.Y)+"\t"+(r+roi.X+desktop.X)+"\t"+(b+roi.Y+desktop.Y));
            }
        }
        using(StreamWriter p=new StreamWriter(Path.Combine(dir,"anomaly-pixels.tsv"))) {
            p.Write("component\tphysicalX\tphysicalY\tstageMask");foreach(string name in names)p.Write("\t"+name+"_storedRGBA");p.WriteLine();
            for(int n=0;n<mask.Length;n++) if(mask[n]!=0){int x=n%roi.Width,y=n/roi.Width;p.Write(component[n]+"\t"+(desktop.X+roi.X+x)+"\t"+(desktop.Y+roi.Y+y)+"\t"+mask[n]);
                for(int s=0;s<stages.Length;s++){int o=s<=2?((roi.Y+y)*stages[s].Width+roi.X+x)*4:n*4;p.Write("\t"+Pixel(bytes[s],o));}p.WriteLine();}
        }
        Note("candidateConnectedComponents="+id+"; thresholds are hypotheses, not automatic proof; stored premultiplied bytes preserved");
    }
    static void Field(Type t,object o,string name,object v){t.GetField(name,Hidden).SetValue(o,v);}
    static void Provenance(Assembly assembly) {
        Type identity=assembly.GetType("BoltSnip.BuildIdentityValues");
        if(identity==null){Note("EmbeddedBuildIdentity=UNAVAILABLE");return;}
        foreach(string name in new string[]{"ProductName","Version","BuildTimeUtc","BuildId","BuildCommit","ScreenCaptureBackend"}) {
            FieldInfo f=identity.GetField(name,Hidden);if(f!=null)Note("Embedded."+name+"="+f.GetValue(null));
        }
        FieldInfo build=identity.GetField("BuildId",Hidden);
        if(build!=null){string value=Convert.ToString(build.GetValue(null));string commit=value.Length>=40?value.Substring(0,40):"unknown";
            bool valid=commit.Length==40;foreach(char ch in commit)if(!Uri.IsHexDigit(ch))valid=false;
            Note("EmbeddedCommitFromBuildId="+(valid?commit:"unknown")+"; full BuildId retained above; build id may include dirty marker");
        }
        Type release=assembly.GetType("BoltSnip.ReleaseIdentity");
        if(release!=null){MethodInfo startup=release.GetMethod("CreateStartupDetails",Hidden);if(startup!=null)Note("EmbeddedStartupDetails="+startup.Invoke(null,new object[]{assembly.Location,System.Diagnostics.Process.GetCurrentProcess().Id,DateTime.UtcNow}));}
    }
    static void BoundsChecks(Type capture) {
        MethodInfo method=capture.GetMethod("Capture",Hidden);
        Rectangle[] cases={new Rectangle(0,0,0,1),new Rectangle(0,0,1,0),new Rectangle(0,0,-1,1),new Rectangle(0,0,536870912,1),new Rectangle(0,0,16384,32768)};
        foreach(Rectangle r in cases){Type expected=r.Width<=0||r.Height<=0?typeof(ArgumentOutOfRangeException):typeof(OverflowException);
            try {using(Bitmap unexpected=(Bitmap)method.Invoke(null,new object[]{r})){}throw new Exception("Bounds accepted unexpectedly: "+r);}
            catch(TargetInvocationException ex){Note("BoundsValidation="+r+"; actual="+ex.InnerException.GetType().Name+"; expected="+expected.Name+"; verdict="+(ex.InnerException.GetType()==expected?"PASS":"FAIL"));}
        }
    }
    static void Repeated(Type capture,Rectangle desktop,Rectangle roi,Bitmap reference,string dir) {
        byte[] expected=Bytes(reference);double[] times=new double[100];long allBad=0,allAnomalies=0;uint before,after;
        using(System.Diagnostics.Process process=System.Diagnostics.Process.GetCurrentProcess()) {
            before=GetGuiResources(process.Handle,0);
            using(StreamWriter report=new StreamWriter(Path.Combine(dir,"repeated-captures.tsv"))) {
                report.WriteLine("iteration\tcaptureMilliseconds\tRGBA_mismatches\tanomalies");
                for(int i=0;i<100;i++) {
                    long start=System.Diagnostics.Stopwatch.GetTimestamp();Bitmap bitmap=(Bitmap)capture.GetMethod("Capture",Hidden).Invoke(null,new object[]{desktop});
                    times[i]=(System.Diagnostics.Stopwatch.GetTimestamp()-start)*1000.0/System.Diagnostics.Stopwatch.Frequency;
                    using(bitmap){byte[] pixels=Bytes(bitmap);long bad=0,anomalies=0;
                        for(int y=roi.Top;y<roi.Bottom;y++)for(int x=roi.Left;x<roi.Right;x++){int p=(y*desktop.Width+x)*4;
                            if(pixels[p]!=expected[p]||pixels[p+1]!=expected[p+1]||pixels[p+2]!=expected[p+2]||pixels[p+3]!=expected[p+3])bad++;
                            if(Anomaly(pixels,p,expected,p))anomalies++;
                        }
                        allBad+=bad;allAnomalies+=anomalies;report.WriteLine((i+1)+"\t"+times[i].ToString("F6",System.Globalization.CultureInfo.InvariantCulture)+"\t"+bad+"\t"+anomalies);
                    }
                }
            }
            after=GetGuiResources(process.Handle,0);
        }
        Array.Sort(times);
        Note("RepeatedStaticFixture=100; totalRgbaMismatchPixels="+allBad+"; totalCandidateAnomalies="+allAnomalies+"; captureMillisecondsMedian="+((times[49]+times[50])/2).ToString("F6",System.Globalization.CultureInfo.InvariantCulture)+"; P95NearestRank="+times[94].ToString("F6",System.Globalization.CultureInfo.InvariantCulture)+"; Max="+times[99].ToString("F6",System.Globalization.CultureInfo.InvariantCulture)+"; GdiBefore="+before+"; GdiAfter="+after+"; GdiDelta="+((long)after-before));
        Note("Timing includes reflection invocation and product bitmap materialization, excludes scanning/save/dispose; reference acquired separately in static scene; no browser or dynamic-scene claim");
    }
    [STAThread] static int Main(string[] args) {
        string dir=args[1];Directory.CreateDirectory(dir);log=new StreamWriter(Path.Combine(dir,"capture.log"));
        List<Bitmap> dispose=new List<Bitmap>();Form overlay=null;SourceScene scene=null;IDataObject clipboard=null;
        try {
            try{if(!SetProcessDpiAwarenessContext(new IntPtr(-4)))SetProcessDPIAware();}catch(EntryPointNotFoundException){SetProcessDPIAware();}
            Assembly a=Assembly.LoadFrom(args[0]);Type capture=a.GetType("BoltSnip.ScreenCapture",true),ot=a.GetType("BoltSnip.CaptureOverlay",true);
            using(SHA256 sha=SHA256.Create())using(FileStream f=File.OpenRead(args[0]))Note("CaptureId="+Path.GetFileName(dir)+"; Exe="+args[0]+"; ExeSHA256="+BitConverter.ToString(sha.ComputeHash(f)).Replace("-","")+"; OperatorExpectedCommit="+args[2]+"; QPCFrequency="+System.Diagnostics.Stopwatch.Frequency);
            Note("Identity="+a.FullName+"; backend=invoked Product ScreenCapture.Capture; Stage0 and StageA are sequential acquisitions, NEVER asserted same frame; requires static scene");
            Provenance(a);
            Rectangle desktop=SystemInformation.VirtualScreen,roi=new Rectangle(int.Parse(args[3]),int.Parse(args[4]),int.Parse(args[5]),int.Parse(args[6]));
            if(!new Rectangle(0,0,desktop.Width,desktop.Height).Contains(roi)||roi.Width<20||roi.Height<20)throw new Exception("ROI outside virtual bitmap or too small");
            Note("Desktop="+desktop+"; ROI in virtual-bitmap coordinates="+roi+"; monitors="+Screen.AllScreens.Length);
            if(args.Length>7&&!String.IsNullOrWhiteSpace(args[7])) {
                Bitmap source=new Bitmap(args[7]);dispose.Add(source);
                using(SHA256 sha=SHA256.Create())using(FileStream f=File.OpenRead(args[7]))Note("SourceImage="+args[7]+"; SHA256="+BitConverter.ToString(sha.ComputeHash(f)).Replace("-","")+"; dimensions="+source.Size);
                scene=new SourceScene();scene.Image=source;scene.FormBorderStyle=FormBorderStyle.None;scene.StartPosition=FormStartPosition.Manual;scene.AutoScaleMode=AutoScaleMode.None;scene.Bounds=desktop;scene.TopMost=true;scene.ShowInTaskbar=false;
                scene.Show();scene.Update();Application.DoEvents();Thread.Sleep(120);Application.DoEvents();
                Note("Scene=static source PNG rendered native 1:1 at virtual desktop origin; clipped to physical desktop, no scale; fixture, NOT live browser reproduction");
            }
            clipboard=Clipboard.GetDataObject();
            Note("Stage0 acquisition begin");Bitmap reference=Native(desktop);dispose.Add(reference);reference.Save(Path.Combine(dir,"Stage0-native.png"));Note("Stage0 acquisition end");
            if(scene!=null){
                if(!new Rectangle(0,0,scene.Image.Width,scene.Image.Height).Contains(roi))throw new Exception("Source ROI outside image");
                byte[] visible=Bytes(reference),expectedScene=Bytes(scene.Image);long sceneBad=0;
                for(int y=roi.Top;y<roi.Bottom;y++)for(int x=roi.Left;x<roi.Right;x++){
                    int v=(y*reference.Width+x)*4,s=(y*scene.Image.Width+x)*4;
                    if(visible[v]!=expectedScene[s]||visible[v+1]!=expectedScene[s+1]||visible[v+2]!=expectedScene[s+2]||visible[v+3]!=expectedScene[s+3])sceneBad++;
                }
                Note("SourceSceneReferenceMismatches="+sceneBad+"; verifies native 1:1 visible source ROI before attributing corruption");
                if(sceneBad!=0)throw new Exception("INFRASTRUCTURE INVALID: visible source scene differs from source image");
                BoundsChecks(capture);Repeated(capture,desktop,roi,reference,dir);
            }else Note("100 repeated fixture and allocation checks SKIPPED: SourceImage required");
            Bitmap raw=null;
            Func<Rectangle,Bitmap> provider=delegate(Rectangle bounds){Note("StageA product acquisition begin");Bitmap returned=(Bitmap)capture.GetMethod("Capture",Hidden).Invoke(null,new object[]{bounds});raw=(Bitmap)returned.Clone();dispose.Add(raw);raw.Save(Path.Combine(dir,"StageA-raw.png"));Note("StageA product acquisition end");return returned;};
            overlay=(Form)ot.GetConstructor(Hidden,null,new Type[]{typeof(Func<string>),typeof(Func<Rectangle,Bitmap>),typeof(Func<Rectangle,List<Rectangle>>),typeof(Action),typeof(Action)},null).Invoke(new object[]{new Func<string>(delegate{return dir;}),provider,new Func<Rectangle,List<Rectangle>>(delegate(Rectangle r){return new List<Rectangle>();}),null,null});
            ot.GetMethod("BeginCapture",Hidden).Invoke(overlay,null);
            if(!overlay.Visible)throw new Exception("Actual overlay not visible");
            ((System.Windows.Forms.Timer)ot.GetField("_windowTrackingTimer",Hidden).GetValue(overlay)).Stop();
            Bitmap screen=(Bitmap)ot.GetField("_screen",Hidden).GetValue(overlay);if(screen==null)throw new Exception("Actual _screen missing");
            Bitmap b=(Bitmap)screen.Clone();dispose.Add(b);b.Save(Path.Combine(dir,"StageB-actual-screen.png"));
            Bitmap crop=(Bitmap)capture.GetMethod("Crop",Hidden).Invoke(null,new object[]{screen,roi});dispose.Add(crop);crop.Save(Path.Combine(dir,"StageC-crop.png"));
            Clipboard.SetDataObject(crop,true,5,40);using(Image img=Clipboard.GetImage()) {
                if(img==null)throw new Exception("StageD Clipboard.GetImage returned null");
                Bitmap cb=img is Bitmap?(Bitmap)((Bitmap)img).Clone():new Bitmap(img);dispose.Add(cb);cb.Save(Path.Combine(dir,"StageD-clipboard.png"));
                string png=Path.Combine(dir,"StageE-saved.png");crop.Save(png,ImageFormat.Png);Bitmap saved=new Bitmap(png);dispose.Add(saved);
                // Force a known active selection and suppress chrome sampling hazards. Actual paint still runs.
                Rectangle active=Rectangle.Inflate(roi,4,4);Field(ot,overlay,"_hasSelection",true);Field(ot,overlay,"_selection",active);
                Field(ot,overlay,"_hasMagnifierPoint",false);Field(ot,overlay,"_hasAlignmentGuidePoint",false);
                Note("Overlay diagnostic selection="+active+"; tracking stopped; magnifier/guides disabled; ROI excludes 4px border; toolbar may overlap and needs human review");
                overlay.Invalidate();overlay.Update();Application.DoEvents();Thread.Sleep(80);Application.DoEvents();
                Note("Overlay physical desktop acquisition begin");Bitmap composed=Native(desktop);dispose.Add(composed);composed.Save(Path.Combine(dir,"Overlay-physical-desktop.png"));
                Bitmap region=composed.Clone(roi,PixelFormat.Format32bppArgb);dispose.Add(region);region.Save(Path.Combine(dir,"Overlay-ROI.png"));Note("Overlay physical desktop acquisition end");
                Analyze(dir,roi,desktop,new Bitmap[]{reference,raw,b,crop,cb,saved,region},new string[]{"Stage0","StageA","StageB","StageC","StageD","StageE","Overlay"});
            }
            Note("COLLECTION COMPLETE; not acceptance; browser/dynamic/multi-monitor/DPI/performance must be tested separately");return 0;
        }catch(Exception ex){Note("FAIL "+ex);return 1;}
        finally {
            if(overlay!=null)overlay.Dispose();if(scene!=null)scene.Dispose();foreach(Bitmap bitmap in dispose)bitmap.Dispose();
            try{if(clipboard!=null)Clipboard.SetDataObject(clipboard,true,5,40);else Clipboard.Clear();Note("Clipboard restore attempted; delayed formats cannot be guaranteed preserved");}catch(Exception ex){Note("Clipboard restore FAILED "+ex);}
            log.Dispose();
        }
    }
}
