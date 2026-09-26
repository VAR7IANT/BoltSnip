using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using System.Threading;
using System.Diagnostics;

namespace BoltSnip
{
    internal sealed class ReplayAudioCaptureSession : IDisposable
    {
        private sealed class PipeWaitCompletion
        {
            private readonly object _syncRoot = new object();
            private readonly ManualResetEvent _completedEvent = new ManualResetEvent(false);
            private readonly List<Action> _completionActions = new List<Action>();
            private Exception _failure;
            private bool _completed;
            private bool _completionActionsFinished;
            private bool _waitingFinished;
            private bool _eventDisposed;

            internal WaitHandle Signal
            {
                get { return _completedEvent; }
            }

            internal Exception Failure
            {
                get { lock (_syncRoot) { return _failure; } }
            }

            internal void Complete(Exception failure)
            {
                lock (_syncRoot)
                {
                    if (_completed)
                    {
                        return;
                    }
                    _failure = failure;
                    _completed = true;
                }

                while (true)
                {
                    Action[] actions;
                    lock (_syncRoot)
                    {
                        if (_completionActions.Count == 0)
                        {
                            _completionActionsFinished = true;
                            _completedEvent.Set();
                            DisposeEventIfFinished();
                            return;
                        }

                        actions = _completionActions.ToArray();
                        _completionActions.Clear();
                    }

                    foreach (Action action in actions)
                    {
                        try { action(); }
                        catch (Exception exception)
                        {
                            ReplayDiagnostics.Write("Deferred audio pipe cleanup failed: " + exception.Message);
                        }
                    }
                }
            }

            internal void RunAfterCompletion(Action action)
            {
                if (action == null)
                {
                    throw new ArgumentNullException("action");
                }

                bool runNow;
                lock (_syncRoot)
                {
                    runNow = _completionActionsFinished;
                    if (!runNow)
                    {
                        _completionActions.Add(action);
                    }
                }

                if (runNow)
                {
                    action();
                }
            }

            internal void FinishWaiting()
            {
                lock (_syncRoot)
                {
                    _waitingFinished = true;
                    DisposeEventIfFinished();
                }
            }

            private void DisposeEventIfFinished()
            {
                if (_completionActionsFinished && _waitingFinished && !_eventDisposed)
                {
                    _eventDisposed = true;
                    _completedEvent.Dispose();
                }
            }
        }

        private const uint ClsctxAll = 23;
        private const uint AudioClientBufferFlagSilent = 0x00000002;
        private const long AudioBufferDurationHns = 1000000;
        private const int PipeConnectTimeoutMilliseconds = 5000;
        private const int CaptureStartTimeoutMilliseconds = 3000;
        private const int WorkerStopTimeoutMilliseconds = 1500;

        private readonly object _syncRoot = new object();
        private readonly object _pipeSyncRoot = new object();
        private readonly ManualResetEvent _stopEvent = new ManualResetEvent(false);
        private readonly ManualResetEvent _startEvent = new ManualResetEvent(false);
        private readonly ManualResetEvent _preparedEvent = new ManualResetEvent(false);
        private readonly ManualResetEvent _captureStartedEvent = new ManualResetEvent(false);
        private readonly NamedPipeServerStream _pipe;
        private readonly string _pipeName;
        private readonly string _pipeArgument;
        private readonly Thread _worker;
        private ReplayAudioFormat _format;
        private ReplayAudioState _state = ReplayAudioState.Starting;
        private Exception _preparationFailure;
        private bool _disposed;
        private bool _workerStopped;
        private bool _sessionEventsDisposed;
        private bool _pipeDisposed;
        private int _activeConnectCalls;
        private int _pipeEndWaitPending;
        private int _pipeDisposeQueued;
        private PipeWaitCompletion _activePipeWaitCompletion;
        private int _workerNativeThreadId;
        private long _bytesWritten;
        private ulong _firstAudioDevicePosition;
        private ulong _firstAudioQpcPosition;
        private ulong _lastAudioDevicePosition;
        private ulong _lastAudioQpcPosition;
        private long _lastAudioClockLogTimestamp;
        private bool _hasAudioClockPosition;

        internal ReplayAudioCaptureSession()
        {
            _pipeName = "BoltSnipReplayAudio-" + Guid.NewGuid().ToString("N");
            _pipeArgument = @"\\.\pipe\" + _pipeName;
            _pipe = new NamedPipeServerStream(_pipeName, PipeDirection.Out, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
            ReplayDiagnostics.Write("Audio pipe created");

            _worker = new Thread(WorkerLoop);
            _worker.IsBackground = true;
            _worker.Name = "BoltSnip Replay Audio";
            _worker.Start();
        }

        internal ReplayAudioFormat Format
        {
            get { lock (_syncRoot) { return _format; } }
        }

        internal ReplayAudioState State
        {
            get { lock (_syncRoot) { return _state; } }
        }

        internal string PipeArgument
        {
            get { return _pipeArgument; }
        }

        internal double WorkerCpuSeconds
        {
            get
            {
                int threadId = Volatile.Read(ref _workerNativeThreadId);
                if (threadId == 0)
                {
                    return 0;
                }

                try
                {
                    using (Process process = Process.GetCurrentProcess())
                    {
                        ProcessThreadCollection threads = process.Threads;
                        for (int index = 0; index < threads.Count; index++)
                        {
                            using (ProcessThread thread = threads[index])
                            {
                                if (thread.Id == threadId)
                                {
                                    return thread.TotalProcessorTime.TotalSeconds;
                                }
                            }
                        }
                    }
                }
                catch
                {
                    // The measurement is diagnostic only; it must not affect capture.
                }

                return 0;
            }
        }

        internal double WrittenDurationSeconds
        {
            get
            {
                ReplayAudioFormat format = Format;
                if (format == null || format.OutputBytesPerFrame <= 0 || format.SampleRate <= 0)
                {
                    return 0;
                }

                return (double)Interlocked.Read(ref _bytesWritten) /
                    format.OutputBytesPerFrame / format.SampleRate;
            }
        }

        internal void WaitUntilPrepared(int timeoutMilliseconds)
        {
            WaitForStartupSignal(_preparedEvent, timeoutMilliseconds, "Timed out preparing WASAPI loopback capture.");

            Exception failure;
            lock (_syncRoot)
            {
                failure = _preparationFailure;
            }
            if (failure != null)
            {
                throw new InvalidOperationException("WASAPI loopback capture is unavailable: " + failure.Message, failure);
            }
        }

        internal void ConnectAndStart(int timeoutMilliseconds)
        {
            lock (_syncRoot)
            {
                if (_disposed)
                {
                    throw new OperationCanceledException("System audio startup was stopped.");
                }
                _activeConnectCalls++;
            }

            try
            {
                ConnectAndStartCore(timeoutMilliseconds);
            }
            finally
            {
                lock (_syncRoot)
                {
                    _activeConnectCalls--;
                    TryDisposeSessionEventsUnsafe();
                }
            }
        }

        private void ConnectAndStartCore(int timeoutMilliseconds)
        {
            WaitUntilPrepared(timeoutMilliseconds);
            bool pipeConnected;
            lock (_pipeSyncRoot)
            {
                if (_pipeDisposed || _pipeDisposeQueued != 0 || _stopEvent.WaitOne(0))
                {
                    throw new OperationCanceledException("System audio startup was stopped.");
                }
                pipeConnected = _pipe.IsConnected;
            }

            if (!pipeConnected)
            {
                PipeWaitCompletion completion = new PipeWaitCompletion();
                IAsyncResult connection = null;
                Thread endWaitThread = null;
                DateTime connectionDeadline = DateTime.UtcNow.AddMilliseconds(timeoutMilliseconds);
                try
                {
                    lock (_pipeSyncRoot)
                    {
                        if (_pipeDisposed || _pipeDisposeQueued != 0 || _stopEvent.WaitOne(0))
                        {
                            throw new OperationCanceledException("System audio startup was stopped.");
                        }

                        _activePipeWaitCompletion = completion;
                        _pipeEndWaitPending = 1;
                        try
                        {
                            connection = _pipe.BeginWaitForConnection(null, null);
                        }
                        catch
                        {
                            _pipeEndWaitPending = 0;
                            _activePipeWaitCompletion = null;
                            Monitor.PulseAll(_pipeSyncRoot);
                            completion.Complete(null);
                            throw;
                        }
                    }

                    Action endWait = delegate
                    {
                        Exception failure = null;
                        try { _pipe.EndWaitForConnection(connection); }
                        catch (Exception exception) { failure = exception; }
                        CompletePendingPipeWait(completion, failure);
                    };

                    endWaitThread = new Thread(new ThreadStart(endWait));
                    endWaitThread.IsBackground = true;
                    endWaitThread.Name = "BoltSnip Replay Audio Pipe Wait";
                    try
                    {
                        endWaitThread.Start();
                    }
                    catch
                    {
                        CancelPendingPipeConnection();
                        endWait();
                        throw;
                    }

                    WaitForStartupSignal(
                        completion.Signal,
                        RemainingTimeoutMilliseconds(connectionDeadline),
                        "Timed out waiting for FFmpeg to connect to the audio pipe.");

                    Exception connectionFailure = completion.Failure;
                    if (connectionFailure != null)
                    {
                        throw new InvalidOperationException(
                            "FFmpeg audio pipe connection failed: " + connectionFailure.Message,
                            connectionFailure);
                    }
                }
                catch
                {
                    if (connection != null)
                    {
                        CancelPendingPipeConnection();
                        bool endWaitCompleted = false;
                        try { endWaitCompleted = completion.Signal.WaitOne(WorkerStopTimeoutMilliseconds); } catch { }
                        if (endWaitCompleted)
                        {
                            DisposePipeSafely();
                        }
                        else
                        {
                            ReplayDiagnostics.Write("Audio pipe wait did not settle after cancellation; deferring pipe disposal until EndWait completes");
                            QueuePipeDisposal(completion);
                        }
                    }
                    else
                    {
                        CancelPendingPipeConnection();
                        DisposePipeSafely();
                        completion.Complete(null);
                    }
                    throw;
                }
                finally
                {
                    completion.FinishWaiting();
                }
            }

            ReplayDiagnostics.Write("Audio pipe connected");
            _startEvent.Set();
            WaitForStartupSignal(
                _captureStartedEvent,
                CaptureStartTimeoutMilliseconds,
                "Timed out starting WASAPI loopback capture.");

            ReplayAudioState state = State;
            if (state != ReplayAudioState.Active)
            {
                Exception failure;
                lock (_syncRoot) { failure = _preparationFailure; }
                throw new InvalidOperationException(
                    failure == null ? "WASAPI loopback capture did not become active." : failure.Message,
                    failure);
            }
        }

        internal void Stop()
        {
            lock (_syncRoot)
            {
                if (!_sessionEventsDisposed)
                {
                    _stopEvent.Set();
                    _startEvent.Set();
                }
            }
            if (_worker != null && _worker != Thread.CurrentThread && _worker.IsAlive)
            {
                if (!_worker.Join(WorkerStopTimeoutMilliseconds))
                {
                    DisposePipeSafely();
                    if (!_worker.Join(WorkerStopTimeoutMilliseconds))
                    {
                        ReplayDiagnostics.Write("Audio worker did not stop within the bounded wait");
                    }
                }
            }
        }

        private void WaitForStartupSignal(WaitHandle signal, int timeoutMilliseconds, string timeoutMessage)
        {
            int signaled = WaitHandle.WaitAny(new WaitHandle[] { _stopEvent, signal }, timeoutMilliseconds);
            if (signaled == 0 || _stopEvent.WaitOne(0))
            {
                throw new OperationCanceledException("System audio startup was stopped.");
            }
            if (signaled == WaitHandle.WaitTimeout)
            {
                throw new TimeoutException(timeoutMessage);
            }
        }

        private static int RemainingTimeoutMilliseconds(DateTime deadline)
        {
            double remaining = (deadline - DateTime.UtcNow).TotalMilliseconds;
            if (remaining <= 0)
            {
                return 0;
            }
            return (int)Math.Min(int.MaxValue, Math.Ceiling(remaining));
        }

        private void CancelPendingPipeConnection()
        {
            lock (_pipeSyncRoot)
            {
                CancelPendingPipeConnectionUnsafe();
            }
        }

        private void CancelPendingPipeConnectionUnsafe()
        {
            if (_pipeDisposed || _pipeEndWaitPending == 0)
            {
                return;
            }

            try
            {
                if (!CancelIoEx(_pipe.SafePipeHandle, IntPtr.Zero))
                {
                    int error = Marshal.GetLastWin32Error();
                    if (error != 1168 && error != 6)
                    {
                        ReplayDiagnostics.Write("Could not cancel pending audio pipe wait: " + error.ToString(CultureInfo.InvariantCulture));
                    }
                }
            }
            catch (Exception exception)
            {
                ReplayDiagnostics.Write("Could not cancel pending audio pipe wait: " + exception.Message);
            }
        }

        private void DisposePipeSafely()
        {
            PipeWaitCompletion completion = null;
            bool disposeNow = false;
            lock (_pipeSyncRoot)
            {
                if (_pipeDisposed || Interlocked.CompareExchange(ref _pipeDisposeQueued, 0, 0) != 0)
                {
                    return;
                }

                if (_pipeEndWaitPending != 0)
                {
                    completion = _activePipeWaitCompletion;
                    if (completion == null)
                    {
                        ReplayDiagnostics.Write("Audio pipe disposal deferred without an EndWait completion signal");
                        return;
                    }
                    CancelPendingPipeConnectionUnsafe();
                }
                else
                {
                    _pipeDisposed = true;
                    disposeNow = true;
                }
            }

            if (completion != null)
            {
                QueuePipeDisposal(completion);
                return;
            }

            if (disposeNow)
            {
                DisposePipeHandle();
            }
        }

        private void QueuePipeDisposal(PipeWaitCompletion completion)
        {
            if (completion == null || Interlocked.CompareExchange(ref _pipeDisposeQueued, 1, 0) != 0)
            {
                return;
            }

            try
            {
                completion.RunAfterCompletion(DisposePipeAfterEndWait);
            }
            catch (Exception exception)
            {
                Interlocked.Exchange(ref _pipeDisposeQueued, 0);
                ReplayDiagnostics.Write("Could not defer audio pipe cleanup: " + exception.Message);
            }
        }

        private void DisposePipeAfterEndWait()
        {
            bool disposeNow = false;
            lock (_pipeSyncRoot)
            {
                if (!_pipeDisposed && _pipeEndWaitPending == 0)
                {
                    _pipeDisposed = true;
                    disposeNow = true;
                }
                else if (_pipeEndWaitPending != 0)
                {
                    ReplayDiagnostics.Write("Audio pipe cleanup callback ran before EndWait settled; keeping the pipe open");
                    Interlocked.Exchange(ref _pipeDisposeQueued, 0);
                }
            }

            if (disposeNow)
            {
                DisposePipeHandle();
            }
        }

        private void DisposePipeHandle()
        {
            try { _pipe.Dispose(); }
            catch (Exception exception) { ReplayDiagnostics.Write("Audio pipe disposal failed: " + exception.Message); }
        }

        private void CompletePendingPipeWait(PipeWaitCompletion completion, Exception failure)
        {
            lock (_pipeSyncRoot)
            {
                if (ReferenceEquals(_activePipeWaitCompletion, completion))
                {
                    _pipeEndWaitPending = 0;
                    _activePipeWaitCompletion = null;
                    Monitor.PulseAll(_pipeSyncRoot);
                }
            }

            completion.Complete(failure);
        }

        private void TryDisposeSessionEventsUnsafe()
        {
            if (!_disposed || !_workerStopped || _activeConnectCalls != 0 || _sessionEventsDisposed)
            {
                return;
            }

            _sessionEventsDisposed = true;
            _stopEvent.Dispose();
            _startEvent.Dispose();
            _preparedEvent.Dispose();
            _captureStartedEvent.Dispose();
        }

        public void Dispose()
        {
            lock (_syncRoot)
            {
                if (_disposed)
                {
                    return;
                }
                _disposed = true;
            }

            Stop();
            DisposePipeSafely();
            lock (_syncRoot)
            {
                TryDisposeSessionEventsUnsafe();
            }
        }

        internal static string BuildInputArguments(ReplayAudioFormat format, string pipeArgument)
        {
            if (format == null)
            {
                throw new ArgumentNullException("format");
            }
            if (string.IsNullOrWhiteSpace(pipeArgument))
            {
                throw new ArgumentException("An audio pipe path is required.", "pipeArgument");
            }

            return "-thread_queue_size 512 -f " + format.FfmpegSampleFormat +
                " -ar " + format.SampleRate.ToString(CultureInfo.InvariantCulture) +
                " -ac " + format.Channels.ToString(CultureInfo.InvariantCulture) +
                " -i " + ReplayProcessSupport.QuoteArgument(pipeArgument) + " ";
        }

        private void WorkerLoop()
        {
            Volatile.Write(ref _workerNativeThreadId, unchecked((int)GetCurrentThreadId()));
            IMMDeviceEnumerator enumerator = null;
            IMMDevice device = null;
            IAudioClient audioClient = null;
            IAudioCaptureClient captureClient = null;
            bool initializedCom = false;
            bool audioStarted = false;

            try
            {
                int coResult = WasapiInterop.CoInitializeEx(IntPtr.Zero, 0);
                if (coResult < 0)
                {
                    Marshal.ThrowExceptionForHR(coResult);
                }
                initializedCom = coResult == 0 || coResult == 1;

                Type enumeratorType = Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"), true);
                enumerator = (IMMDeviceEnumerator)Activator.CreateInstance(enumeratorType);
                CheckHResult(enumerator.GetDefaultAudioEndpoint(AudioDataFlow.Render, AudioRole.Console, out device), "GetDefaultAudioEndpoint");

                string endpointId;
                CheckHResult(device.GetId(out endpointId), "IMMDevice.GetId");
                ReplayDiagnostics.Write("Audio endpoint: " + endpointId);

                object audioClientObject;
                Guid audioClientId = WasapiInterop.AudioClientInterfaceId;
                CheckHResult(device.Activate(ref audioClientId, ClsctxAll, IntPtr.Zero, out audioClientObject), "IMMDevice.Activate(IAudioClient)");
                audioClient = (IAudioClient)audioClientObject;

                IntPtr mixFormatPointer = IntPtr.Zero;
                try
                {
                    CheckHResult(audioClient.GetMixFormat(out mixFormatPointer), "IAudioClient.GetMixFormat");
                    _format = ParseMixFormat(mixFormatPointer);
                    ReplayDiagnostics.Write(
                        "Audio mix format: " + _format.SampleRate.ToString(CultureInfo.InvariantCulture) + " Hz, " +
                        _format.Channels.ToString(CultureInfo.InvariantCulture) + " channels, " +
                        _format.BitsPerSample.ToString(CultureInfo.InvariantCulture) + "-bit " + _format.FfmpegSampleFormat);

                    int initializeResult = audioClient.Initialize(
                        AudioShareMode.Shared,
                        AudioClientStreamFlags.Loopback,
                        AudioBufferDurationHns,
                        0,
                        mixFormatPointer,
                        IntPtr.Zero);
                    CheckHResult(initializeResult, "IAudioClient.Initialize(loopback)");
                }
                finally
                {
                    if (mixFormatPointer != IntPtr.Zero)
                    {
                        Marshal.FreeCoTaskMem(mixFormatPointer);
                    }
                }

                object captureClientObject;
                Guid captureClientId = WasapiInterop.AudioCaptureClientInterfaceId;
                CheckHResult(audioClient.GetService(ref captureClientId, out captureClientObject), "IAudioClient.GetService(IAudioCaptureClient)");
                captureClient = (IAudioCaptureClient)captureClientObject;

                lock (_syncRoot)
                {
                    _state = ReplayAudioState.Starting;
                }
                _preparedEvent.Set();

                int signaled = WaitHandle.WaitAny(new WaitHandle[] { _startEvent, _stopEvent });
                if (signaled == 1 || _stopEvent.WaitOne(0))
                {
                    return;
                }

                CheckHResult(audioClient.Start(), "IAudioClient.Start");
                audioStarted = true;
                lock (_syncRoot)
                {
                    _state = ReplayAudioState.Active;
                }
                ReplayDiagnostics.Write("WASAPI loopback started");
                _captureStartedEvent.Set();

                try
                {
                    CaptureLoop(captureClient, enumerator, endpointId, _format);
                }
                catch (ReplayAudioPipeException exception)
                {
                    SetUnavailable(exception.Message, false);
                }
                catch (Exception exception)
                {
                    if (!_stopEvent.WaitOne(0))
                    {
                        SetUnavailable(exception.Message, true);
                        SilenceUntilStopped(_format);
                    }
                }
            }
            catch (Exception exception)
            {
                bool prepared;
                lock (_syncRoot)
                {
                    prepared = _format != null;
                    if (_preparationFailure == null)
                    {
                        _preparationFailure = exception;
                    }
                    _state = ReplayAudioState.Unavailable;
                }

                if (!_stopEvent.WaitOne(0))
                {
                    ReplayDiagnostics.Write("Audio endpoint unavailable: " + exception.Message);
                    if (prepared && _pipe.IsConnected)
                    {
                        _captureStartedEvent.Set();
                        ReplayDiagnostics.Write("Audio capture failed; continuing with silence/video");
                        try { SilenceUntilStopped(_format); }
                        catch (ReplayAudioPipeException pipeException) { ReplayDiagnostics.Write(pipeException.Message); }
                    }
                }
            }
            finally
            {
                if (!_preparedEvent.WaitOne(0))
                {
                    _preparedEvent.Set();
                }
                _captureStartedEvent.Set();

                if (audioStarted && audioClient != null)
                {
                    try { CheckHResult(audioClient.Stop(), "IAudioClient.Stop"); }
                    catch (Exception exception) { ReplayDiagnostics.Write("WASAPI stop failed: " + exception.Message); }
                }

                ReleaseComObject(captureClient);
                ReleaseComObject(audioClient);
                ReleaseComObject(device);
                ReleaseComObject(enumerator);
                if (initializedCom)
                {
                    WasapiInterop.CoUninitialize();
                }
                ReplayDiagnostics.Write("Audio resources released");
                lock (_syncRoot)
                {
                    _workerStopped = true;
                    TryDisposeSessionEventsUnsafe();
                }
            }
        }

        private void CaptureLoop(IAudioCaptureClient captureClient, IMMDeviceEnumerator enumerator, string endpointId, ReplayAudioFormat format)
        {
            long intervalTicks = Math.Max(1, System.Diagnostics.Stopwatch.Frequency / 100);
            long nextEndpointCheckTicks = System.Diagnostics.Stopwatch.GetTimestamp() + System.Diagnostics.Stopwatch.Frequency;
            long silenceDeadline = System.Diagnostics.Stopwatch.GetTimestamp() + intervalTicks * 2;
            int silenceRemainder = 0;
            byte[] source = new byte[Math.Max(4096, format.SampleRate * format.Channels * (format.BitsPerSample / 8) / 10)];
            byte[] packed24 = format.RequiresPacked24Conversion
                ? new byte[Math.Max(3072, format.SampleRate * format.Channels * 3 / 10)]
                : null;
            byte[] silence = new byte[Math.Max(format.OutputBytesPerFrame * Math.Max(1, format.SampleRate / 10), 4096)];

            while (!_stopEvent.WaitOne(0))
            {
                long now = System.Diagnostics.Stopwatch.GetTimestamp();
                if (now >= nextEndpointCheckTicks)
                {
                    string currentEndpointId = GetDefaultRenderEndpointId(enumerator);
                    if (!string.Equals(endpointId, currentEndpointId, StringComparison.OrdinalIgnoreCase))
                    {
                        string reason = "The default render endpoint changed; restart Instant Replay to capture system audio from the new endpoint.";
                        SetUnavailable(reason, true);
                        SilenceUntilStopped(format);
                        return;
                    }
                    nextEndpointCheckTicks = now + System.Diagnostics.Stopwatch.Frequency;
                }

                uint nextFrames;
                CheckHResult(captureClient.GetNextPacketSize(out nextFrames), "IAudioCaptureClient.GetNextPacketSize");
                if (nextFrames > 0)
                {
                    while (nextFrames > 0 && !_stopEvent.WaitOne(0))
                    {
                        IntPtr data;
                        uint frames;
                        uint flags;
                        ulong devicePosition;
                        ulong qpcPosition;
                        CheckHResult(captureClient.GetBuffer(out data, out frames, out flags, out devicePosition, out qpcPosition), "IAudioCaptureClient.GetBuffer");
                        LogAudioClockPosition(devicePosition, qpcPosition);
                        try
                        {
                            if ((flags & AudioClientBufferFlagSilent) != 0)
                            {
                                WriteSilence(format, frames, silence);
                            }
                            else
                            {
                                WriteAudioPacket(format, data, frames, source, packed24);
                            }
                        }
                        finally
                        {
                            CheckHResult(captureClient.ReleaseBuffer(frames), "IAudioCaptureClient.ReleaseBuffer");
                        }

                        silenceDeadline = System.Diagnostics.Stopwatch.GetTimestamp() + intervalTicks * 2;
                        CheckHResult(captureClient.GetNextPacketSize(out nextFrames), "IAudioCaptureClient.GetNextPacketSize");
                    }
                }
                else
                {
                    long silenceNow = System.Diagnostics.Stopwatch.GetTimestamp();
                    int frames = GetDueSilenceFrameCount(
                        silenceNow,
                        intervalTicks,
                        ref silenceDeadline,
                        format.SampleRate,
                        ref silenceRemainder);
                    if (frames > 0)
                    {
                        WriteSilence(format, (uint)frames, silence);
                    }
                    _stopEvent.WaitOne(5);
                }
            }
        }

        private static string GetDefaultRenderEndpointId(IMMDeviceEnumerator enumerator)
        {
            IMMDevice defaultDevice = null;
            try
            {
                CheckHResult(
                    enumerator.GetDefaultAudioEndpoint(AudioDataFlow.Render, AudioRole.Console, out defaultDevice),
                    "GetDefaultAudioEndpoint(check)");
                string endpointId;
                CheckHResult(defaultDevice.GetId(out endpointId), "IMMDevice.GetId(check)");
                return endpointId;
            }
            finally
            {
                ReleaseComObject(defaultDevice);
            }
        }

        private void SilenceUntilStopped(ReplayAudioFormat format)
        {
            if (format == null || !_pipe.IsConnected)
            {
                return;
            }

            byte[] silence = new byte[Math.Max(format.OutputBytesPerFrame * Math.Max(1, format.SampleRate / 100), 4096)];
            int remainder = 0;
            long intervalTicks = Math.Max(1, System.Diagnostics.Stopwatch.Frequency / 100);
            long silenceDeadline = System.Diagnostics.Stopwatch.GetTimestamp() + intervalTicks;
            while (!_stopEvent.WaitOne(10))
            {
                int frames = GetDueSilenceFrameCount(
                    System.Diagnostics.Stopwatch.GetTimestamp(),
                    intervalTicks,
                    ref silenceDeadline,
                    format.SampleRate,
                    ref remainder);
                if (frames > 0)
                {
                    WriteSilence(format, (uint)frames, silence);
                }
            }
        }

        private void LogAudioClockPosition(ulong devicePosition, ulong qpcPosition)
        {
            if (qpcPosition == 0)
            {
                return;
            }

            if (!_hasAudioClockPosition)
            {
                _firstAudioDevicePosition = devicePosition;
                _firstAudioQpcPosition = qpcPosition;
                _lastAudioClockLogTimestamp = Stopwatch.GetTimestamp();
                _hasAudioClockPosition = true;
            }

            _lastAudioDevicePosition = devicePosition;
            _lastAudioQpcPosition = qpcPosition;
            long now = Stopwatch.GetTimestamp();
            if (now - _lastAudioClockLogTimestamp < Stopwatch.Frequency * 5)
            {
                return;
            }

            WriteAudioClockMeasurement();
            _lastAudioClockLogTimestamp = now;
        }

        private void WriteAudioClockMeasurement()
        {
            if (!_hasAudioClockPosition || _lastAudioQpcPosition <= _firstAudioQpcPosition ||
                _lastAudioDevicePosition <= _firstAudioDevicePosition)
            {
                return;
            }

            ulong frames = _lastAudioDevicePosition - _firstAudioDevicePosition;
            double seconds = (_lastAudioQpcPosition - _firstAudioQpcPosition) / 10000000.0;
            double rate = frames / seconds;
            ReplayDiagnostics.Write(
                "WASAPI device clock: frames=" + frames.ToString(CultureInfo.InvariantCulture) +
                ", qpcDuration=" + seconds.ToString("F3", CultureInfo.InvariantCulture) + "s, observedRate=" +
                rate.ToString("F2", CultureInfo.InvariantCulture) + " Hz");
        }

        private void WriteAudioPacket(ReplayAudioFormat format, IntPtr sourcePointer, uint frames, byte[] source, byte[] packed24)
        {
            int sampleBytes = format.BitsPerSample / 8;
            long sourceLengthLong = (long)frames * format.Channels * sampleBytes;
            if (sourceLengthLong > int.MaxValue)
            {
                throw new InvalidOperationException("WASAPI returned an audio packet that is too large.");
            }
            int sourceLength = (int)sourceLengthLong;
            if (sourceLength > source.Length)
            {
                source = new byte[sourceLength];
            }
            Marshal.Copy(sourcePointer, source, 0, sourceLength);

            if (format.RequiresPacked24Conversion)
            {
                int sampleCount = checked((int)frames * format.Channels);
                int outputLength = checked(sampleCount * 3);
                if (packed24 == null || outputLength > packed24.Length)
                {
                    packed24 = new byte[outputLength];
                }
                for (int sample = 0; sample < sampleCount; sample++)
                {
                    int value = BitConverter.ToInt32(source, sample * 4) >> 8;
                    int outputOffset = sample * 3;
                    packed24[outputOffset] = (byte)value;
                    packed24[outputOffset + 1] = (byte)(value >> 8);
                    packed24[outputOffset + 2] = (byte)(value >> 16);
                }
                WritePipe(packed24, outputLength);
                return;
            }

            WritePipe(source, sourceLength);
        }

        private void WriteSilence(ReplayAudioFormat format, uint frames, byte[] silence)
        {
            long lengthLong = (long)frames * format.OutputBytesPerFrame;
            if (lengthLong > int.MaxValue)
            {
                throw new InvalidOperationException("WASAPI silence packet is too large.");
            }
            int length = (int)lengthLong;
            if (length > silence.Length)
            {
                silence = new byte[length];
            }
            WritePipe(silence, length);
        }

        private void WritePipe(byte[] data, int length)
        {
            try
            {
                _pipe.Write(data, 0, length);
                Interlocked.Add(ref _bytesWritten, length);
            }
            catch (Exception exception)
            {
                throw new ReplayAudioPipeException("Audio pipe write failed: " + exception.Message, exception);
            }
        }

        private void SetUnavailable(string reason, bool continueWithSilence)
        {
            lock (_syncRoot)
            {
                _state = ReplayAudioState.Unavailable;
                if (_preparationFailure == null)
                {
                    _preparationFailure = new InvalidOperationException(reason);
                }
            }

            ReplayDiagnostics.Write("Audio endpoint unavailable: " + reason);
            if (continueWithSilence)
            {
                ReplayDiagnostics.Write("Audio capture failed; continuing with silence/video");
            }
        }

        private static ReplayAudioFormat ParseMixFormat(IntPtr formatPointer)
        {
            int formatTag = unchecked((ushort)Marshal.ReadInt16(formatPointer, 0));
            int channels = unchecked((ushort)Marshal.ReadInt16(formatPointer, 2));
            int sampleRate = Marshal.ReadInt32(formatPointer, 4);
            int blockAlign = unchecked((ushort)Marshal.ReadInt16(formatPointer, 12));
            int bitsPerSample = unchecked((ushort)Marshal.ReadInt16(formatPointer, 14));
            int extraSize = unchecked((ushort)Marshal.ReadInt16(formatPointer, 16));
            int validBits = bitsPerSample;
            Guid subFormat = Guid.Empty;

            if (formatTag == 0xfffe)
            {
                if (extraSize >= 22)
                {
                    validBits = unchecked((ushort)Marshal.ReadInt16(formatPointer, 18));
                    byte[] guidBytes = new byte[16];
                    Marshal.Copy(IntPtr.Add(formatPointer, 24), guidBytes, 0, guidBytes.Length);
                    subFormat = new Guid(guidBytes);
                }
            }

            return ReplayAudioFormat.Parse(formatTag, channels, sampleRate, bitsPerSample, blockAlign, extraSize, validBits, subFormat);
        }

        internal static int GetDueSilenceFrameCount(
            long nowTicks,
            long intervalTicks,
            ref long nextDeadlineTicks,
            int sampleRate,
            ref int remainder)
        {
            if (intervalTicks <= 0)
            {
                throw new ArgumentOutOfRangeException("intervalTicks");
            }
            if (sampleRate <= 0)
            {
                throw new ArgumentOutOfRangeException("sampleRate");
            }

            if (nowTicks < nextDeadlineTicks)
            {
                return 0;
            }

            long dueIntervals = ((nowTicks - nextDeadlineTicks) / intervalTicks) + 1;
            long frameNumerator = checked((long)sampleRate * dueIntervals + remainder);
            long frames = frameNumerator / 100;
            remainder = (int)(frameNumerator % 100);
            nextDeadlineTicks = checked(nextDeadlineTicks + dueIntervals * intervalTicks);
            if (frames > int.MaxValue)
            {
                throw new InvalidOperationException("The WASAPI silence packet is too large.");
            }

            return (int)frames;
        }

        private static void CheckHResult(int result, string operation)
        {
            if (result < 0)
            {
                Marshal.ThrowExceptionForHR(result);
                throw new InvalidOperationException(operation + " failed with HRESULT 0x" + result.ToString("X8", CultureInfo.InvariantCulture) + ".");
            }
        }

        private static void ReleaseComObject(object value)
        {
            if (value != null && Marshal.IsComObject(value))
            {
                try { Marshal.ReleaseComObject(value); } catch { }
            }
        }

        private sealed class ReplayAudioPipeException : IOException
        {
            internal ReplayAudioPipeException(string message, Exception innerException)
                : base(message, innerException)
            {
            }
        }

        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CancelIoEx(SafePipeHandle handle, IntPtr overlapped);
    }
}
