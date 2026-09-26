param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('BoltSnip-AudioLifecycle-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$clientSource = Join-Path $testRoot 'PipeDrain.cs'
$clientAssemblyPath = Join-Path $testRoot 'PipeDrain.dll'
[IO.File]::WriteAllText($clientSource, @'
using System;
using System.IO.Pipes;
using System.Threading;

public sealed class PipeDrain : IDisposable
{
    private readonly NamedPipeClientStream _client;
    private readonly Thread _thread;
    private volatile bool _stopping;
    public Exception Error { get; private set; }

    public PipeDrain(string pipeName)
    {
        _client = new NamedPipeClientStream(".", pipeName, PipeDirection.In, PipeOptions.None);
        _thread = new Thread(ReadLoop) { IsBackground = true, Name = "Replay Audio Pipe Test Reader" };
        _thread.Start();
    }

    private void ReadLoop()
    {
        try
        {
            _client.Connect(5000);
            byte[] buffer = new byte[65536];
            while (!_stopping)
            {
                int read = _client.Read(buffer, 0, buffer.Length);
                if (read == 0) break;
            }
        }
        catch (Exception exception)
        {
            if (!_stopping) Error = exception;
        }
    }

    public void Dispose()
    {
        _stopping = true;
        _client.Dispose();
        _thread.Join(6000);
    }
}
'@)

try {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not [IO.File]::Exists($compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
    & $compiler /nologo /target:library ("/out:" + $clientAssemblyPath) $clientSource
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile the named-pipe test reader.' }

    $assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
    $type = $assembly.GetType('BoltSnip.ReplayAudioCaptureSession', $true)
    $flags = [Reflection.BindingFlags]'Instance,Static,NonPublic'
    $constructor = $type.GetConstructor([Reflection.BindingFlags]'Instance,NonPublic', $null, [Type[]]@(), $null)
    $prepare = $type.GetMethod('WaitUntilPrepared', $flags)
    $connectAndStart = $type.GetMethod('ConnectAndStart', $flags)
    $stop = $type.GetMethod('Stop', $flags)
    $dispose = $type.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
    $pipeArgument = $type.GetProperty('PipeArgument', $flags)
    $audioState = $type.GetProperty('State', $flags)
    $workerField = $type.GetField('_worker', $flags)
    $drainType = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($clientAssemblyPath)).GetType('PipeDrain', $true)
    $results = @()

    for ($round = 1; $round -le 3; $round++) {
        $session = $null
        $drain = $null
        $worker = $null
        $started = $false
        $prepareError = $null
        $watch = [Diagnostics.Stopwatch]::StartNew()
        try {
            $session = $constructor.Invoke(@())
            try {
                [void]$prepare.Invoke($session, [object[]]@(5000))
                $pipe = [string]$pipeArgument.GetValue($session, $null)
                $pipeName = $pipe.Substring($pipe.LastIndexOf('\') + 1)
                $drain = [Activator]::CreateInstance($drainType, [object[]]@($pipeName))
                [void]$connectAndStart.Invoke($session, [object[]]@(5000))
                $started = [string]$audioState.GetValue($session, $null) -eq 'Active'
            }
            catch {
                $prepareError = $_.Exception.GetBaseException().ToString()
            }
        }
        finally {
            if ($null -ne $session) {
                [void]$stop.Invoke($session, $null)
                [void]$dispose.Invoke($session, $null)
                [void]$dispose.Invoke($session, $null)
                $worker = $workerField.GetValue($session)
            }
            if ($null -ne $drain) { [void]$drainType.GetMethod('Dispose').Invoke($drain, $null) }
            $watch.Stop()
        }

        $workerStopped = $null -eq $worker -or -not $worker.IsAlive
        $passed = $workerStopped -and $watch.Elapsed.TotalSeconds -lt 12 -and
            [string]$prepareError -notmatch 'ObjectDisposedException'
        $results += [pscustomobject]@{
            Round = $round
            WASAPIStarted = $started
            AudioState = if ($null -ne $session) { [string]$audioState.GetValue($session, $null) } else { 'ConstructorFailed' }
            WorkerStopped = $workerStopped
            DisposeMs = [Math]::Round($watch.Elapsed.TotalMilliseconds)
            Failure = $prepareError
            Passed = $passed
        }
    }

    $results | Format-List
    if ($results.Where({ -not $_.Passed }).Count -gt 0) { exit 1 }
}
finally {
    if ([IO.Directory]::Exists($testRoot)) {
        try { [IO.Directory]::Delete($testRoot, $true) } catch { }
    }
}
