using System;
using System.Reflection;
using System.Threading;

public sealed class ReplayAudioConnectRunner
{
    private readonly object _session;
    private readonly MethodInfo _connect;
    private readonly int _timeoutMilliseconds;

    public string FailureType { get; private set; }
    public string FailureMessage { get; private set; }
    public Thread Worker { get; private set; }

    public ReplayAudioConnectRunner(object session, MethodInfo connect, int timeoutMilliseconds)
    {
        _session = session;
        _connect = connect;
        _timeoutMilliseconds = timeoutMilliseconds;
    }

    public void Start()
    {
        Worker = new Thread(Run) { IsBackground = true, Name = "Replay Audio Pipeline Startup Test" };
        Worker.Start();
    }

    private void Run()
    {
        try
        {
            _connect.Invoke(_session, new object[] { _timeoutMilliseconds });
        }
        catch (Exception exception)
        {
            Exception failure = exception.GetBaseException();
            FailureType = failure.GetType().FullName;
            FailureMessage = failure.Message;
        }
    }
}
