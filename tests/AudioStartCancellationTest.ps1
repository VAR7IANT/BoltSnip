param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
if (-not [IO.File]::Exists($Executable)) { throw "Required file was not found: $Executable" }

$workRoot = Join-Path (Split-Path $PSScriptRoot -Parent) '.tools\test-work'
[IO.Directory]::CreateDirectory($workRoot) | Out-Null
$tempRoot = Join-Path $workRoot ([Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tempRoot) | Out-Null
$sourcePath = Join-Path $tempRoot 'ConnectRunner.cs'
$assemblyPath = Join-Path $tempRoot 'ConnectRunner.dll'
$resultPath = Join-Path (Split-Path $PSScriptRoot -Parent) '.tools\instant-replay-audio-evidence\AudioStartCancellationTest.json'
[IO.File]::WriteAllText($sourcePath, @'
using System;
using System.Reflection;
using System.Threading;

public sealed class ConnectRunner
{
    private readonly object _session;
    private readonly MethodInfo _connect;
    private readonly int _timeoutMilliseconds;
    public string FailureType { get; private set; }
    public Thread Worker { get; private set; }

    public ConnectRunner(object session, MethodInfo connect, int timeoutMilliseconds)
    {
        _session = session;
        _connect = connect;
        _timeoutMilliseconds = timeoutMilliseconds;
    }

    public void Start()
    {
        Worker = new Thread(Run) { IsBackground = true, Name = "Audio Startup Cancellation Test" };
        Worker.Start();
    }

    private void Run()
    {
        try { _connect.Invoke(_session, new object[] { _timeoutMilliseconds }); }
        catch (Exception exception) { FailureType = exception.GetBaseException().GetType().FullName; }
    }
}

public sealed class StartupSignalRunner
{
    private readonly object _session;
    private readonly MethodInfo _wait;
    private readonly WaitHandle _signal;
    private readonly int _timeoutMilliseconds;
    public string FailureType { get; private set; }
    public Thread Worker { get; private set; }

    public StartupSignalRunner(object session, MethodInfo wait, WaitHandle signal, int timeoutMilliseconds)
    {
        _session = session;
        _wait = wait;
        _signal = signal;
        _timeoutMilliseconds = timeoutMilliseconds;
    }

    public void Start()
    {
        Worker = new Thread(Run) { IsBackground = true, Name = "Audio Startup Signal Timeout Test" };
        Worker.Start();
    }

    private void Run()
    {
        try { _wait.Invoke(_session, new object[] { _signal, _timeoutMilliseconds, "capture-start timeout test" }); }
        catch (Exception exception) { FailureType = exception.GetBaseException().GetType().FullName; }
    }
}
'@, [Text.UTF8Encoding]::new($false))

try {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $resultPath)) | Out-Null
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not [IO.File]::Exists($compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
    & $compiler /nologo /target:library ("/out:" + $assemblyPath) $sourcePath
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile the connection wait test helper.' }

    $assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
    $sessionType = $assembly.GetType('BoltSnip.ReplayAudioCaptureSession', $true)
    $flags = [Reflection.BindingFlags]'Instance,Static,NonPublic'
    $constructor = $sessionType.GetConstructor([Reflection.BindingFlags]'Instance,NonPublic', $null, [Type[]]@(), $null)
    $prepare = $sessionType.GetMethod('WaitUntilPrepared', $flags)
    $connect = $sessionType.GetMethod('ConnectAndStart', $flags)
    $waitForSignal = $sessionType.GetMethod('WaitForStartupSignal', $flags)
    $stop = $sessionType.GetMethod('Stop', $flags)
    $dispose = $sessionType.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
    $testAssembly = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($assemblyPath))
    $helperType = $testAssembly.GetType('ConnectRunner', $true)
    $signalRunnerType = $testAssembly.GetType('StartupSignalRunner', $true)

    $timeoutSession = $constructor.Invoke(@())
    $timeoutRunner = $null
    $timeoutException = $null
    $timeoutJoined = $false
    $captureStartedTimeout = $false
    $captureTimeoutRunner = $null
    $captureTimeoutSignal = [Threading.ManualResetEvent]::new($false)
    try {
        [void]$prepare.Invoke($timeoutSession, [object[]]@(5000))
        $captureTimeoutRunner = [Activator]::CreateInstance($signalRunnerType, [object[]]@($timeoutSession, $waitForSignal, $captureTimeoutSignal, 1000))
        [void]$captureTimeoutRunner.GetType().GetMethod('Start').Invoke($captureTimeoutRunner, $null)
        $captureTimeoutWorker = $captureTimeoutRunner.GetType().GetProperty('Worker').GetValue($captureTimeoutRunner, $null)
        $captureTimeoutJoined = [bool]$captureTimeoutWorker.Join(2000)
        $captureStartedTimeout = $captureTimeoutJoined -and
            $captureTimeoutRunner.GetType().GetProperty('FailureType').GetValue($captureTimeoutRunner, $null) -eq [TimeoutException].FullName
        $timeoutRunner = [Activator]::CreateInstance($helperType, [object[]]@($timeoutSession, $connect, 1000))
        [void]$timeoutRunner.GetType().GetMethod('Start').Invoke($timeoutRunner, $null)
        $worker = $timeoutRunner.GetType().GetProperty('Worker').GetValue($timeoutRunner, $null)
        $timeoutJoined = [bool]$worker.Join(2500)
        if (-not $timeoutJoined) {
            [void]$stop.Invoke($timeoutSession, $null)
            $timeoutJoined = [bool]$worker.Join(2000)
        }
        $timeoutException = $timeoutRunner.GetType().GetProperty('FailureType').GetValue($timeoutRunner, $null)
    }
    finally {
        $captureTimeoutSignal.Dispose()
        try { [void]$dispose.Invoke($timeoutSession, $null) } catch { }
    }
    $pipeWaitTimedOut = $timeoutJoined -and $timeoutException -eq [TimeoutException].FullName

    $session = $constructor.Invoke(@())
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $runner = $null
    try {
        [void]$prepare.Invoke($session, [object[]]@(5000))
        $runner = [Activator]::CreateInstance($helperType, [object[]]@($session, $connect, 30000))
        $runnerType = $runner.GetType()
        [void]$runnerType.GetMethod('Start').Invoke($runner, $null)
        Start-Sleep -Milliseconds 250
        [void]$stop.Invoke($session, $null)
        $worker = $runnerType.GetProperty('Worker').GetValue($runner, $null)
        $joined = [bool]$worker.Join(4000)
        $failure = $runnerType.GetProperty('FailureType').GetValue($runner, $null)
        $watch.Stop()
        $elapsedMs = [Math]::Round($watch.Elapsed.TotalMilliseconds)
    }
    finally {
        try { [void]$dispose.Invoke($session, $null) } catch { }
        if ($watch.IsRunning) { $watch.Stop() }
    }

    $canceledQuickly = $joined -and $elapsedMs -lt 5000 -and $failure -eq [OperationCanceledException].FullName
    $result = [pscustomobject]@{
        NoPipeClientConnected = $true
        PipeConnectionTimeoutFired = $pipeWaitTimedOut
        PipeTimeoutType = $timeoutException
        CaptureStartWaitTimedOut = $captureStartedTimeout
        ConnectThreadExitedAfterStop = $joined
        StopElapsedMs = $elapsedMs
        StopFailureType = $failure
        StopReportedAsCancellation = $failure -eq [OperationCanceledException].FullName
        Passed = ($captureStartedTimeout -and $pipeWaitTimedOut -and $canceledQuickly)
    }
    $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    $result | Format-List
    if (-not ($captureStartedTimeout -and $pipeWaitTimedOut -and $canceledQuickly)) { exit 1 }
}
finally {
    if ([IO.Directory]::Exists($tempRoot)) {
        try { [IO.Directory]::Delete($tempRoot, $true) } catch { }
    }
}
