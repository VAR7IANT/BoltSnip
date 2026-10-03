param(
    [Parameter(Mandatory=$true)][string]$Executable,
    [Parameter(Mandatory=$true)][string]$FfmpegPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [ValidateSet('ddagrab','gdigrab')][string]$Backend = 'ddagrab',
    [ValidateRange(60,3600)][int]$DurationSeconds = 60,
    [string]$ExpectedBuildId = '',
    [ValidatePattern('^$|^[0-9a-fA-F]{40}$')][string]$ExpectedGitSha = ''
)
# Run in a fresh Windows PowerShell process. This observes cursor state without moving
# or forcing visibility. DrawMouse is taken from the product command, never overridden.
$ErrorActionPreference = 'Stop'
$Executable = (Resolve-Path -LiteralPath $Executable).Path
$FfmpegPath = (Resolve-Path -LiteralPath $FfmpegPath).Path
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Use a NEW output directory to preserve evidence.' }
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
public sealed class CursorSessionObserver : IDisposable {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; }
    [StructLayout(LayoutKind.Sequential)] public struct CURSORINFO { public int cbSize,flags; public IntPtr hCursor; public POINT position; }
    [DllImport("user32.dll",SetLastError=true)] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern IntPtr GetThreadDpiAwarenessContext();
    [DllImport("user32.dll")] static extern int GetAwarenessFromDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr OpenInputDesktop(uint flags,bool inherit,uint access);
    [DllImport("user32.dll",SetLastError=true)] static extern bool SetThreadDesktop(IntPtr desktop);
    [DllImport("user32.dll",SetLastError=true)] static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll",SetLastError=true)] static extern bool GetCursorInfo(ref CURSORINFO info);
    public static int EnableBestDpiAwareness() {
        SetProcessDpiAwarenessContext(new IntPtr(-4));
        if(SetThreadDpiAwarenessContext(new IntPtr(-4))==IntPtr.Zero)
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(),"Cannot set per-monitor DPI awareness");
        int awareness=GetAwarenessFromDpiAwarenessContext(GetThreadDpiAwarenessContext());
        if(awareness!=2) throw new InvalidOperationException("Per-monitor DPI awareness was not established");
        return awareness;
    }
    readonly string path; Thread worker; volatile bool stopping;
    public long Samples,Errors,Transitions; public Exception Failure;
    public CursorSessionObserver(string output) { path=output; }
    public void Start() { worker=new Thread(Run); worker.IsBackground=true; worker.Start(); }
    void Run() {
        IntPtr desktop=IntPtr.Zero;
        try {
            desktop=OpenInputDesktop(0,false,0x0101);
            if(desktop==IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(),"OpenInputDesktop");
            if(!SetThreadDesktop(desktop)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(),"SetThreadDesktop");
            EnableBestDpiAwareness();
            using(var output=new StreamWriter(path,false)) {
                output.WriteLine("Qpc\tUtc\tSuccess\tError\tFlags\tShowing\tCursorHandle\tX\tY");
                int last=-1;
                while(!stopping) {
                    var cursor=new CURSORINFO(); cursor.cbSize=Marshal.SizeOf(typeof(CURSORINFO));
                    long qpc=Stopwatch.GetTimestamp();
                    bool ok=GetCursorInfo(ref cursor); int error=ok?0:Marshal.GetLastWin32Error();
                    int showing=(cursor.flags&1)!=0?1:0;
                    if(ok) { if(last!=-1 && last!=showing) Interlocked.Increment(ref Transitions); last=showing; }
                    else Interlocked.Increment(ref Errors);
                    output.WriteLine(String.Format(CultureInfo.InvariantCulture,"{0}\t{1}\t{2}\t{3}\t{4}\t{5}\t{6}\t{7}\t{8}",qpc,DateTime.UtcNow.ToString("O"),ok,error,cursor.flags,showing,cursor.hCursor.ToInt64(),cursor.position.X,cursor.position.Y));
                    output.Flush(); Interlocked.Increment(ref Samples); Thread.Sleep(5);
                }
            }
        } catch(Exception error) { Failure=error; }
        finally { if(desktop!=IntPtr.Zero) CloseDesktop(desktop); }
    }
    public void Dispose() { stopping=true; if(worker!=null && !worker.Join(5000)) throw new TimeoutException("Cursor observer did not stop"); }
}
'@
$awareness = [CursorSessionObserver]::EnableBestDpiAwareness()
# Load Forms only AFTER setting DPI awareness. Application manifest is not inherited
# when loading an EXE by reflection into PowerShell.
Add-Type -AssemblyName System.Windows.Forms
$bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds
$nativeWidth = [CursorSessionObserver]::GetSystemMetrics(0)
$nativeHeight = [CursorSessionObserver]::GetSystemMetrics(1)
if ($bounds.Width -ne $nativeWidth -or $bounds.Height -ne $nativeHeight) { throw 'Physical primary screen dimensions disagree.' }
$assembly = [Reflection.Assembly]::LoadFile($Executable)
$metadata = @{}
foreach ($item in $assembly.GetCustomAttributes($false)) {
    if ($item.GetType().FullName -eq 'System.Reflection.AssemblyMetadataAttribute') { $metadata[$item.Key] = $item.Value }
}
if ($ExpectedBuildId -and $metadata.BuildId -ne $ExpectedBuildId) { throw 'Executable BuildId does not match ExpectedBuildId.' }
if ($ExpectedGitSha -and (-not $metadata.BuildId -or -not $ExpectedGitSha.StartsWith([string]$metadata.BuildId,[StringComparison]::OrdinalIgnoreCase))) { throw 'Executable BuildId does not match the supplied Git SHA prefix.' }
$identity = [ordered]@{ Executable=$Executable; ExecutableSHA256=(Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash; BuildId=$metadata.BuildId; BuildTimeUtc=$metadata.BuildTimeUtc; FfmpegPath=$FfmpegPath; FfmpegSHA256=(Get-FileHash -LiteralPath $FfmpegPath -Algorithm SHA256).Hash; RequestedBackend=$Backend; DurationSeconds=$DurationSeconds; QpcFrequency=[Diagnostics.Stopwatch]::Frequency; DpiAwareness=$awareness; PrimaryBounds=@{X=$bounds.X;Y=$bounds.Y;Width=$bounds.Width;Height=$bounds.Height}; NativePrimaryWidth=$nativeWidth; NativePrimaryHeight=$nativeHeight; HostPID=$PID; CursorSamplingPeriodRequestedMs=5; PhysicalVisualFlickerVerdict='NOT_OBSERVED_BY_HARNESS'; BuildCommitNote='BuildId is embedded metadata; full Git SHA is not inferred.' }
$identity['ExpectedGitShaSuppliedByRunner']=$ExpectedGitSha
$identity | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'identity.json') -Encoding UTF8
$oldEnvironment = @{}
foreach ($name in @('BOLTSNIP_REPLAY_CAPTURE_BACKEND','BOLTSNIP_FFMPEG_PATH','BOLTSNIP_REPLAY_OUTPUT_DIRECTORY','BOLTSNIP_DIAGNOSTIC_LOG_PATH','BOLTSNIP_DIAGNOSTIC_LOG','TEMP','TMP')) { $oldEnvironment[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
$manager=$null; $observer=$null; $events=$null; $failure=$null; $observedPids=New-Object 'System.Collections.Generic.HashSet[int]'
$flags=[Reflection.BindingFlags]'Instance,NonPublic'
try {
    $probeTempDirectory=Join-Path $OutputDirectory 'temp'
    New-Item -ItemType Directory -Path $probeTempDirectory | Out-Null
    $env:TEMP=$probeTempDirectory
    $env:TMP=$probeTempDirectory
    $env:BOLTSNIP_REPLAY_CAPTURE_BACKEND=$Backend
    $env:BOLTSNIP_FFMPEG_PATH=$FfmpegPath
    $env:BOLTSNIP_REPLAY_OUTPUT_DIRECTORY=$OutputDirectory
    $env:BOLTSNIP_DIAGNOSTIC_LOG_PATH=Join-Path $OutputDirectory 'diagnostic.log'
    $env:BOLTSNIP_DIAGNOSTIC_LOG='1'
    $type=$assembly.GetType('BoltSnip.ReplayManager',$true)
    $manager=[Activator]::CreateInstance($type,$true)
    $events=New-Object IO.StreamWriter((Join-Path $OutputDirectory 'lifecycle.jsonl'),$false)
    function Write-ProbeEvent([string]$Event) {
        $state=[string]$type.GetProperty('State',$flags).GetValue($manager)
        $audio=[string]$type.GetProperty('AudioState',$flags).GetValue($manager)
        $buffer=[double]$type.GetProperty('BufferedDurationSeconds',$flags).GetValue($manager)
        $encoder=$type.GetField('_encoder',$flags).GetValue($manager)
        $encoderPid=$null; $processStart=$null; $processExited=$null
        if ($null -ne $encoder) {
            $process=$encoder.GetType().GetField('_process',$flags).GetValue($encoder)
            if ($null -ne $process) { try { $encoderPid=$process.Id; $processStart=$process.StartTime.ToUniversalTime().ToString('O'); $processExited=$process.HasExited; [void]$observedPids.Add($encoderPid) } catch {} }
        }
        $record=[ordered]@{Qpc=[Diagnostics.Stopwatch]::GetTimestamp();Utc=[DateTime]::UtcNow.ToString('O');Event=$Event;State=$state;AudioState=$audio;BufferedSeconds=$buffer;EncoderPID=$encoderPid;EncoderStartUtc=$processStart;EncoderExited=$processExited}
        $events.WriteLine(($record | ConvertTo-Json -Compress)); $events.Flush()
    }
    $observer=New-Object CursorSessionObserver((Join-Path $OutputDirectory 'cursor-samples.tsv'))
    $observer.Start()
    Start-Sleep -Seconds 2
    if ($observer.Failure -or $observer.Samples -lt 10) { throw 'Cursor observer failed before capture startup.' }
    Write-ProbeEvent 'BeforeStart'
    $type.GetMethod('Start',$flags).Invoke($manager,@())
    Write-ProbeEvent 'StartReturned'
    $readyDeadline=[DateTime]::UtcNow.AddSeconds(30)
    do {
        Write-ProbeEvent 'StartupPoll'
        $state=[string]$type.GetProperty('State',$flags).GetValue($manager)
        if ($state -eq 'Error') { throw ('Replay startup failed: '+$type.GetProperty('LastError',$flags).GetValue($manager)) }
        if ($state -eq 'Recording') { break }
        Start-Sleep -Milliseconds 50
    } while ([DateTime]::UtcNow -lt $readyDeadline)
    if ($state -ne 'Recording') { throw 'Replay did not reach Recording.' }
    Write-ProbeEvent 'RecordingDurationStarted'
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt $DurationSeconds) {
        Write-ProbeEvent 'RecordingPoll'
        if ([string]$type.GetProperty('State',$flags).GetValue($manager) -ne 'Recording') { throw 'Recording stopped unexpectedly.' }
        if ($observer.Failure) { throw $observer.Failure }
        Start-Sleep -Milliseconds 50
    }
    Write-ProbeEvent 'RecordingDurationCompleted'
} catch { $failure=$_.Exception.ToString() }
finally {
    if ($null -ne $manager) {
        try {
            Write-ProbeEvent 'BeforeStop'
            $type.GetMethod('Stop',$flags).Invoke($manager,@()) | Out-Null
            $stopDeadline=[DateTime]::UtcNow.AddSeconds(20)
            do { Write-ProbeEvent 'StopPoll'; if ([string]$type.GetProperty('State',$flags).GetValue($manager) -eq 'Disabled') { break }; Start-Sleep -Milliseconds 50 } while ([DateTime]::UtcNow -lt $stopDeadline)
            Write-ProbeEvent 'AfterStop'
        } catch { $failure=([string]$failure+'; Cleanup: '+$_.Exception.ToString()) }
        try { $type.GetMethod('Dispose',[Reflection.BindingFlags]'Instance,Public,NonPublic').Invoke($manager,@()) | Out-Null } catch { $failure=([string]$failure+'; Dispose: '+$_.Exception.ToString()) }
    }
    if ($null -ne $observer) { Start-Sleep -Seconds 2; try { $observer.Dispose() } catch { $failure=([string]$failure+'; Observer: '+$_.Exception.ToString()) } }
    if ($null -ne $events) { $events.Dispose() }
    foreach ($name in $oldEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name,$oldEnvironment[$name],'Process') }
}
$remaining=@()
foreach ($encoderPid in $observedPids) { if (Get-Process -Id $encoderPid -ErrorAction SilentlyContinue) { $remaining += $encoderPid } }
$logPath=Join-Path $OutputDirectory 'diagnostic.log'
$commands=@(); if (Test-Path -LiteralPath $logPath) { $commands=@(Select-String -LiteralPath $logPath -Pattern 'FFmpeg encoder command:|Encoder started:') | ForEach-Object { $_.Line } }
$recordingInterval=$null
$lifecyclePath=Join-Path $OutputDirectory 'lifecycle.jsonl'
$samplesPath=Join-Path $OutputDirectory 'cursor-samples.tsv'
if ((Test-Path -LiteralPath $lifecyclePath) -and (Test-Path -LiteralPath $samplesPath)) {
    $lifecycle=@(Get-Content -LiteralPath $lifecyclePath | ForEach-Object { $_ | ConvertFrom-Json })
    $recordingStart=$lifecycle | Where-Object Event -eq 'RecordingDurationStarted' | Select-Object -First 1
    $recordingEnd=$lifecycle | Where-Object Event -eq 'RecordingDurationCompleted' | Select-Object -First 1
    if ($recordingStart -and $recordingEnd) {
        $recordingSamples=@(Import-Csv -LiteralPath $samplesPath -Delimiter "`t" | Where-Object { [long]$_.Qpc -ge [long]$recordingStart.Qpc -and [long]$_.Qpc -le [long]$recordingEnd.Qpc })
        $recordingTransitions=0; $recordingErrors=0; $recordingVisible=0; $previousShowing=$null
        foreach ($sample in $recordingSamples) {
            if ($sample.Success -ne 'True') { $recordingErrors++; continue }
            $showing=[int]$sample.Showing
            if ($null -ne $previousShowing -and $previousShowing -ne $showing) { $recordingTransitions++ }
            $previousShowing=$showing
            if ($showing -eq 1) { $recordingVisible++ }
        }
        $recordingStates=@($lifecycle | Where-Object { [long]$_.Qpc -ge [long]$recordingStart.Qpc -and [long]$_.Qpc -le [long]$recordingEnd.Qpc })
        $recordingInterval=[ordered]@{StartQpc=$recordingStart.Qpc;EndQpc=$recordingEnd.Qpc;DurationSeconds=([long]$recordingEnd.Qpc-[long]$recordingStart.Qpc)/[double][Diagnostics.Stopwatch]::Frequency;Samples=$recordingSamples.Count;VisibleSamples=$recordingVisible;CursorApiErrors=$recordingErrors;VisibilityTransitions=$recordingTransitions;RecordingAtAllSnapshots=(@($recordingStates | Where-Object State -ne 'Recording').Count -eq 0);AudioActiveAtAllSnapshots=(@($recordingStates | Where-Object AudioState -ne 'Active').Count -eq 0)}
    }
}
$summary=[ordered]@{Failure=$failure; Samples=if($observer){$observer.Samples}else{0}; CursorApiErrors=if($observer){$observer.Errors}else{0}; VisibilityTransitions=if($observer){$observer.Transitions}else{0}; ObserverFailure=if($observer -and $observer.Failure){$observer.Failure.ToString()}else{$null}; OwnedEncoderPIDs=@($observedPids); RemainingObservedPIDs=$remaining; ActualEncoderCommands=$commands; HumanVisibleFlicker='UNVERIFIED'; ReplayCursorQuality='UNVERIFIED'; MediaAndAVAcceptance='NOT_RUN'; Note='Transition count spans baseline, startup, recording and stop; use QPC lifecycle data to classify windows.'}
$summary['RecordingInterval']=$recordingInterval
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'summary.json') -Encoding UTF8
$summary | ConvertTo-Json -Depth 6
if ($failure -or ($observer -and ($observer.Failure -or $observer.Errors)) -or $remaining.Count) { exit 1 }
