param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$flags = [Reflection.BindingFlags]'Instance,NonPublic'
$bufferType = $assembly.GetType('BoltSnip.ReplayBuffer', $true)
$managerType = $assembly.GetType('BoltSnip.ReplayManager', $true)
$bufferConstructor = $bufferType.GetConstructor($flags, $null, [Type[]]@([string],[TimeSpan]), $null)
$waitMethod = $bufferType.GetMethod('WaitForSegmentAfter', $flags)
$disposeMethod = $bufferType.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
$managerDisposeMethod = $managerType.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
$helperName = 'ReplayWaitThread_' + [Guid]::NewGuid().ToString('N')
$helperSource = @"
using System;
using System.Reflection;
using System.Threading;

public sealed class ${helperName}Result
{
    public readonly ManualResetEvent Finished = new ManualResetEvent(false);
    public Thread WaitThread;
    public bool Value;
    public Exception Error;
}

public static class $helperName
{
    public static ${helperName}Result Start(object buffer, MethodInfo waitMethod, WaitHandle stopSignal)
    {
        ${helperName}Result result = new ${helperName}Result();
        Thread thread = new Thread(delegate()
        {
            try { result.Value = (bool)waitMethod.Invoke(buffer, new object[] { -1, 10000, stopSignal }); }
            catch (Exception exception) { result.Error = exception; }
            finally { result.Finished.Set(); }
        });
        thread.IsBackground = true;
        result.WaitThread = thread;
        thread.Start();
        return result;
    }
}
"@
Add-Type -TypeDefinition $helperSource
$helperType = [Type]::GetType($helperName + ', ' + [Reflection.Assembly]::GetExecutingAssembly().GetName().Name, $false)
if ($null -eq $helperType) { $helperType = ([AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object { $_.GetType($helperName, $false) } | Where-Object { $null -ne $_ } | Select-Object -First 1) }
$startWait = $helperType.GetMethod('Start')

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('BoltSnip-ReplayWait-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$stopBuffer = $null
$disposeBuffer = $null
$stopManager = $null
$disposeManager = $null
try {
    $stopDirectory = [string](Join-Path $testRoot 'stop')
    $stopBuffer = $bufferConstructor.Invoke([object[]]@($stopDirectory, [TimeSpan]::FromSeconds(5)))
    $stopManager = [Activator]::CreateInstance($managerType, $true)
    $managerBufferField = $managerType.GetField('_buffer', $flags)
    $managerStateField = $managerType.GetField('_state', $flags)
    $stopEventField = $managerType.GetField('_stopEvent', $flags)
    $managerStop = $managerType.GetMethod('Stop', $flags)
    $managerBufferField.SetValue($stopManager, $stopBuffer)
    $managerStateField.SetValue($stopManager, [Enum]::Parse($managerStateField.FieldType, 'Recording'))
    $stopSignal = $stopEventField.GetValue($stopManager)
    $stopWait = $startWait.Invoke($null, [object[]]@($stopBuffer, $waitMethod, $stopSignal.PSObject.BaseObject))
    Start-Sleep -Milliseconds 100
    [void]$managerStop.Invoke($stopManager, $null)
    $stopCompleted = $stopWait.Finished.WaitOne(3000) -and $null -eq $stopWait.Error -and -not $stopWait.Value

    $disposeDirectory = [string](Join-Path $testRoot 'dispose')
    $disposeBuffer = $bufferConstructor.Invoke([object[]]@($disposeDirectory, [TimeSpan]::FromSeconds(5)))
    $disposeManager = [Activator]::CreateInstance($managerType, $true)
    $managerBufferField.SetValue($disposeManager, $disposeBuffer)
    $managerStateField.SetValue($disposeManager, [Enum]::Parse($managerStateField.FieldType, 'Recording'))
    $disposeSignal = $stopEventField.GetValue($disposeManager)
    $disposeWait = $startWait.Invoke($null, [object[]]@($disposeBuffer, $waitMethod, $disposeSignal.PSObject.BaseObject))
    $managerSavingThreadField = $managerType.GetField('_savingThread', $flags)
    $managerSavingThreadField.SetValue($disposeManager, $disposeWait.WaitThread)
    Start-Sleep -Milliseconds 100
    [void]$managerDisposeMethod.Invoke($disposeManager, $null)
    $disposeCompleted = $disposeWait.Finished.WaitOne(3000) -and $null -eq $disposeWait.Error -and -not $disposeWait.Value
    $waitHandleDisposedAfterWaiter = $disposeSignal.SafeWaitHandle.IsClosed
    $repeatedDisposeCompleted = $true
    try {
        [void]$managerDisposeMethod.Invoke($disposeManager, $null)
    }
    catch {
        $repeatedDisposeCompleted = $false
    }

    $passed = $stopCompleted -and $disposeCompleted -and $waitHandleDisposedAfterWaiter -and $repeatedDisposeCompleted
    [pscustomobject]@{
        ManagerStopWokeWaiter = $stopCompleted
        ManagerDisposeWokeWaiter = $disposeCompleted
        StopWaitHandleDisposedAfterWaiter = $waitHandleDisposedAfterWaiter
        RepeatedManagerDisposeDoesNotThrow = $repeatedDisposeCompleted
        NoTimeoutOrDeadlock = $passed
        Passed = $passed
    } | Format-List
    if (-not $passed) { exit 1 }
}
finally {
    if ($null -ne $stopManager) { [void]$managerDisposeMethod.Invoke($stopManager, $null) }
    if ($null -ne $disposeManager) { [void]$managerDisposeMethod.Invoke($disposeManager, $null) }
    if ($null -ne $stopBuffer) { [void]$disposeMethod.Invoke($stopBuffer, $null) }
    if ($null -ne $disposeBuffer) { [void]$disposeMethod.Invoke($disposeBuffer, $null) }
    if ([IO.Directory]::Exists($testRoot)) { [IO.Directory]::Delete($testRoot, $true) }
}
