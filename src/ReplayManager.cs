using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;

namespace BoltSnip
{
    internal sealed class ReplayManager : IDisposable
    {
        private static readonly TimeSpan StaleReplayCacheAge = TimeSpan.FromHours(24);
        private static int _staleReplayCacheCleanupAttempted;

        private readonly object _syncRoot = new object();
        private readonly ManualResetEvent _stopEvent = new ManualResetEvent(false);
        private readonly ReplaySettings _settings;
        private readonly Queue<ReplayNotification> _notifications = new Queue<ReplayNotification>();
        private ReplayState _state = ReplayState.Disabled;
        private ReplayEncoder _encoder;
        private ReplayBuffer _buffer;
        private ReplaySaver _saver;
        private Thread _recordingThread;
        private Thread _savingThread;
        private bool _stopRequested;
        private bool _disposed;
        private bool _stopEventDisposed;
        private bool _isSaving;
        private string _lastError;
        private ReplayAudioState _audioState = ReplayAudioState.Disabled;
        private double _audioWorkerCpuSeconds;
        private double _audioInputDurationSeconds;

        internal ReplayManager()
            : this(new ReplaySettings())
        {
        }

        internal ReplayManager(ReplaySettings settings)
        {
            if (settings == null)
            {
                throw new ArgumentNullException("settings");
            }
            _settings = settings;
        }

        internal ReplayState State
        {
            get { lock (_syncRoot) { return _state; } }
        }

        internal bool IsSaving
        {
            get { lock (_syncRoot) { return _isSaving; } }
        }

        internal string LastError
        {
            get { lock (_syncRoot) { return _lastError; } }
        }

        internal ReplayAudioState AudioState
        {
            get { lock (_syncRoot) { return _audioState; } }
        }

        internal double AudioWorkerCpuSeconds
        {
            get { lock (_syncRoot) { return _audioWorkerCpuSeconds; } }
        }

        internal double AudioInputDurationSeconds
        {
            get { lock (_syncRoot) { return _audioInputDurationSeconds; } }
        }

        internal int BufferedSegmentCount
        {
            get
            {
                ReplayBuffer buffer;
                lock (_syncRoot) { buffer = _buffer; }
                return buffer == null ? 0 : buffer.SegmentCount;
            }
        }

        internal double BufferedDurationSeconds
        {
            get
            {
                ReplayBuffer buffer;
                lock (_syncRoot) { buffer = _buffer; }
                return buffer == null ? 0 : buffer.CurrentDurationSeconds;
            }
        }

        internal void Start()
        {
            lock (_syncRoot)
            {
                if (_disposed)
                {
                    return;
                }
                if (_isSaving)
                {
                    EnqueueNotification("即时回放", "上一段即时回放仍在保存，请等待保存完成后再重新开启。", true);
                    return;
                }
                if (_state == ReplayState.Starting || _state == ReplayState.Recording || _state == ReplayState.Stopping)
                {
                    return;
                }

                _stopEvent.Reset();
                _stopRequested = false;
                _lastError = null;
                _audioWorkerCpuSeconds = 0;
                _audioInputDurationSeconds = 0;
                _audioState = _settings.capture_system_audio ? ReplayAudioState.Starting : ReplayAudioState.Disabled;
                _state = ReplayState.Starting;
                _recordingThread = new Thread(RecordLoop);
                _recordingThread.IsBackground = true;
                _recordingThread.Name = "BoltSnip Instant Replay";
                _recordingThread.Start();
                EnqueueNotification("即时回放", "正在开启即时回放…", false);
            }

            ReplayDiagnostics.Write("Starting capture");
        }

        internal void Stop()
        {
            bool changeState = false;
            ReplayBuffer buffer;
            lock (_syncRoot)
            {
                if (_disposed || _state == ReplayState.Disabled || _state == ReplayState.Stopping)
                {
                    return;
                }

                _stopRequested = true;
                _stopEvent.Set();
                buffer = _buffer;
                if (_recordingThread == null || !_recordingThread.IsAlive)
                {
                    _state = ReplayState.Disabled;
                    _lastError = null;
                }
                else
                {
                    _state = ReplayState.Stopping;
                }
                changeState = true;
                EnqueueNotification("即时回放", "正在关闭即时回放…", false);
            }

            if (buffer != null)
            {
                buffer.WakeWaiters();
            }

            if (changeState)
            {
                ReplayDiagnostics.Write("Stopping capture");
            }
        }

        internal bool SaveReplay()
        {
            ReplayBuffer buffer;
            ReplayEncoder encoder;
            lock (_syncRoot)
            {
                if (_disposed || _state != ReplayState.Recording || _buffer == null || _encoder == null)
                {
                    EnqueueNotification("即时回放未开启", "请先在托盘菜单中开启即时回放。", true);
                    return false;
                }
                if (_isSaving)
                {
                    EnqueueNotification("即时回放", "上一段回放仍在保存，请稍后再试。", true);
                    return false;
                }

                buffer = _buffer;
                encoder = _encoder;
                if (buffer.LatestIndex < 0)
                {
                    EnqueueNotification("即时回放正在预热", "请等待约 2 秒后再保存。", false);
                    return false;
                }

                _isSaving = true;
                ReplaySaver saver = new ReplaySaver();
                _saver = saver;
                int latestIndex = buffer.LatestIndex;
                string ffmpegPath = encoder.FfmpegPath;
                _savingThread = new Thread(delegate()
                {
                    SaveLoop(buffer, saver, ffmpegPath, latestIndex);
                });
                _savingThread.IsBackground = true;
                _savingThread.Name = "BoltSnip Replay Saver";
                _savingThread.Start();
                EnqueueNotification("即时回放", "正在保存最近可用的回放…", false);
            }

            ReplayDiagnostics.Write("Replay save requested");
            return true;
        }

        internal bool TryDequeueNotification(out ReplayNotification notification)
        {
            lock (_syncRoot)
            {
                if (_notifications.Count == 0)
                {
                    notification = null;
                    return false;
                }
                notification = _notifications.Dequeue();
                return true;
            }
        }

        public void Dispose()
        {
            Thread recordingThread;
            Thread savingThread;
            ReplayEncoder encoder;
            ReplaySaver saver;
            ReplayBuffer buffer;
            lock (_syncRoot)
            {
                if (_disposed)
                {
                    return;
                }

                _disposed = true;
                _stopRequested = true;
                _stopEvent.Set();
                buffer = _buffer;
                encoder = _encoder;
                if (_state != ReplayState.Disabled)
                {
                    _state = ReplayState.Stopping;
                }
                recordingThread = _recordingThread;
                savingThread = _savingThread;
                saver = _saver;
            }

            if (buffer != null)
            {
                buffer.WakeWaiters();
            }

            if (saver != null)
            {
                saver.Cancel();
            }
            JoinQuietly(recordingThread, 12000);
            RunEncoderShutdownFailSafe(
                recordingThread != null && recordingThread.IsAlive,
                delegate { if (encoder != null) encoder.Stop(); },
                delegate { ReplayDiagnostics.Write("Forced encoder shutdown after recording worker timeout"); },
                delegate { JoinQuietly(recordingThread, 1000); });
            JoinQuietly(savingThread, 7000);

            lock (_syncRoot)
            {
                _state = ReplayState.Disabled;
                _audioState = ReplayAudioState.Disabled;
                _encoder = null;
                _buffer = null;
                _saver = null;
                if (recordingThread == null || !recordingThread.IsAlive)
                {
                    _recordingThread = null;
                }
                if (savingThread == null || !savingThread.IsAlive)
                {
                    _savingThread = null;
                    _isSaving = false;
                }
                TryDisposeStopEventUnsafe();
            }

            ReplayDiagnostics.Write("Manager disposed");
        }

        private void RecordLoop()
        {
            ReplayEncoder encoder = new ReplayEncoder();
            ReplayCaptureSession captureSession = new ReplayCaptureSession(_settings.capture_backend);
            ReplayAudioCaptureSession audioSession = null;
            ReplayBuffer buffer = null;
            bool failed = false;
            bool runtimeFallbackUsed = false;
            string failureMessage = null;

            try
            {
                string cacheDirectory = CreateCacheDirectory();
                buffer = new ReplayBuffer(cacheDirectory, _settings.buffer_duration);
                lock (_syncRoot)
                {
                    if (_stopRequested || _disposed)
                    {
                        return;
                    }
                    _encoder = encoder;
                    _buffer = buffer;
                }

                if (_settings.capture_system_audio)
                {
                    try
                    {
                        audioSession = new ReplayAudioCaptureSession();
                        audioSession.WaitUntilPrepared(5000);
                    }
                    catch (Exception exception)
                    {
                        if (IsStopRequested())
                        {
                            throw new OperationCanceledException("Audio startup was stopped.", exception);
                        }
                        ReplayDiagnostics.Write("Audio endpoint unavailable: " + exception.Message);
                        SetAudioState(ReplayAudioState.Unavailable);
                        if (audioSession != null)
                        {
                            audioSession.Dispose();
                            audioSession = null;
                        }
                    }
                }

                Action startWithCaptureBackendFallback = delegate
                {
                    ReplayCaptureBackend requestedBackend = captureSession.Backend;
                    Exception backendFailure;
                    TryStartWithCaptureBackendFallback(
                        requestedBackend,
                        delegate
                        {
                            encoder.Start(cacheDirectory, _settings, captureSession, audioSession);
                            if (audioSession != null)
                            {
                                audioSession.ConnectAndStart(5000);
                            }
                            StabilizeEncoderStartup(encoder);
                        },
                        delegate { return encoder.HasExited; },
                        IsStopRequested,
                        delegate
                        {
                            if (IsStopRequested())
                            {
                                throw new OperationCanceledException("Replay startup was stopped.");
                            }

                            string backendError = encoder.RecentError;
                            if (!string.IsNullOrWhiteSpace(backendError))
                            {
                                ReplayDiagnostics.Write(
                                    "DdaGrab FFmpeg startup error: " + backendError.Replace('\r', ' ').Replace('\n', ' '));
                            }
                            if (audioSession != null)
                            {
                                audioSession.Stop();
                                audioSession.Dispose();
                                audioSession = new ReplayAudioCaptureSession();
                                audioSession.WaitUntilPrepared(5000);
                            }

                            encoder.Dispose();
                            buffer.Dispose();
                            buffer = new ReplayBuffer(cacheDirectory, _settings.buffer_duration);
                            encoder = new ReplayEncoder();
                            captureSession.UseBackend(ReplayCaptureBackend.GdiGrab);
                            lock (_syncRoot)
                            {
                                _encoder = encoder;
                                _buffer = buffer;
                                if (_disposed || _stopRequested)
                                {
                                    throw new OperationCanceledException("Replay startup was stopped.");
                                }
                            }

                            encoder.Start(cacheDirectory, _settings, captureSession, audioSession);
                            if (audioSession != null)
                            {
                                audioSession.ConnectAndStart(5000);
                            }
                            StabilizeEncoderStartup(encoder);
                        },
                        out backendFailure);
                };

                if (audioSession == null)
                {
                    startWithCaptureBackendFallback();
                }
                else
                {
                    Exception audioStartFailure;
                    bool audioStarted = TryStartWithAudioAndFallback(
                        startWithCaptureBackendFallback,
                        IsStopRequested,
                        delegate
                        {
                            if (IsStopRequested())
                            {
                                throw new OperationCanceledException("Audio startup was stopped.");
                            }

                            ReplayDiagnostics.Write("Audio startup failed; retrying with video-only capture");
                            SetAudioState(ReplayAudioState.Unavailable);
                            audioSession.Dispose();
                            audioSession = null;
                            encoder.Dispose();
                            buffer.Dispose();
                            buffer = new ReplayBuffer(cacheDirectory, _settings.buffer_duration);
                            encoder = new ReplayEncoder();
                            lock (_syncRoot)
                            {
                                _encoder = encoder;
                                _buffer = buffer;
                                if (_disposed || _stopRequested)
                                {
                                    throw new OperationCanceledException("Replay startup was stopped.");
                                }
                            }
                            startWithCaptureBackendFallback();
                        },
                        out audioStartFailure);

                    if (audioStarted)
                    {
                        SetAudioState(ReplayAudioState.Active);
                    }
                    else
                    {
                        ReplayDiagnostics.Write("Audio endpoint unavailable: " + audioStartFailure.Message);
                    }
                }

                lock (_syncRoot)
                {
                    if (!_stopRequested && !_disposed)
                    {
                        _state = ReplayState.Recording;
                        string audioNotice = _audioState == ReplayAudioState.Active
                            ? " · 正在缓存系统声音。"
                            : (_audioState == ReplayAudioState.Unavailable ? " · 系统音频不可用。" : string.Empty);
                        EnqueueNotification("即时回放已开启", "按 Alt+Shift+S 保存最近录像" + audioNotice, false);
                    }
                }

                ReplayDiagnostics.Write("Capture started; buffer initialized");
                DateTime lastSegmentReceivedUtc = DateTime.UtcNow;
                DateTime? ddaDisplayChangeObservedUtc = null;
                while (!IsStopRequested())
                {
                    IList<ReplaySegment> completed = encoder.ReadCompletedSegments(_settings.segment_duration_seconds);
                    for (int index = 0; index < completed.Count; index++)
                    {
                        ReplaySegment segment = completed[index];
                        if (buffer.AddSegment(segment))
                        {
                            lastSegmentReceivedUtc = DateTime.UtcNow;
                            if (buffer.SegmentCount == 1)
                            {
                                ReplayDiagnostics.Write("First encoded segment buffered");
                            }
                        }
                    }

                    bool encoderExitedUnexpectedly = encoder.HasExited;
                    string currentEncoderError = encoder.RecentError;
                    bool ddaAccessLostAfterDisplayChange =
                        !encoderExitedUnexpectedly &&
                        captureSession.Backend == ReplayCaptureBackend.DdaGrab &&
                        captureSession.HasDisplayChanged() &&
                        ClassifyDdaRuntimeFailure(currentEncoderError) == "DXGI_ERROR_ACCESS_LOST";
                    if (encoderExitedUnexpectedly || ddaAccessLostAfterDisplayChange)
                    {
                        bool runtimeRecovered = TryRunDdaRuntimeFallback(
                            captureSession.Backend,
                            true,
                            IsStopRequested(),
                            runtimeFallbackUsed,
                            delegate
                            {
                                string failedEncoderError = encoder.RecentError;
                                ReplayDiagnostics.Write(
                                    "DdaGrab runtime capture failure; process-exited=" + encoderExitedUnexpectedly +
                                    "; classification=" +
                                    ClassifyDdaRuntimeFailure(failedEncoderError) +
                                    "; full FFmpeg error follows:" + Environment.NewLine +
                                    (string.IsNullOrWhiteSpace(failedEncoderError)
                                        ? "(FFmpeg produced no stderr output)"
                                        : failedEncoderError));

                                lock (_syncRoot)
                                {
                                    if (_disposed || _stopRequested)
                                    {
                                        throw new OperationCanceledException("Replay recovery was stopped.");
                                    }
                                    _state = ReplayState.Starting;
                                    _audioState = _settings.capture_system_audio
                                        ? ReplayAudioState.Starting
                                        : ReplayAudioState.Disabled;
                                }

                                if (audioSession != null)
                                {
                                    audioSession.Stop();
                                    audioSession.Dispose();
                                    audioSession = null;
                                }

                                encoder.Dispose();
                                buffer.Dispose();

                                cacheDirectory = CreateCacheDirectory();
                                buffer = new ReplayBuffer(cacheDirectory, _settings.buffer_duration);
                                encoder = new ReplayEncoder();
                                captureSession.UseBackend(ReplayCaptureBackend.GdiGrab);

                                lock (_syncRoot)
                                {
                                    if (_disposed || _stopRequested)
                                    {
                                        throw new OperationCanceledException("Replay recovery was stopped.");
                                    }
                                    _encoder = encoder;
                                    _buffer = buffer;
                                }

                                if (_settings.capture_system_audio)
                                {
                                    try
                                    {
                                        audioSession = new ReplayAudioCaptureSession();
                                        audioSession.WaitUntilPrepared(5000);
                                    }
                                    catch (OperationCanceledException)
                                    {
                                        throw;
                                    }
                                    catch (Exception exception)
                                    {
                                        ReplayDiagnostics.Write(
                                            "WASAPI restart failed during DdaGrab recovery: " + exception.Message);
                                        SetAudioState(ReplayAudioState.Unavailable);
                                        if (audioSession != null)
                                        {
                                            audioSession.Stop();
                                            audioSession.Dispose();
                                            audioSession = null;
                                        }
                                    }
                                }

                                if (audioSession == null)
                                {
                                    encoder.Start(cacheDirectory, _settings, captureSession, null);
                                    StabilizeEncoderStartup(encoder);
                                    if (_settings.capture_system_audio)
                                    {
                                        SetAudioState(ReplayAudioState.Unavailable);
                                    }
                                }
                                else
                                {
                                    Exception audioStartFailure;
                                    bool audioStarted = TryStartWithAudioAndFallback(
                                        delegate
                                        {
                                            encoder.Start(cacheDirectory, _settings, captureSession, audioSession);
                                            audioSession.ConnectAndStart(5000);
                                            StabilizeEncoderStartup(encoder);
                                        },
                                        IsStopRequested,
                                        delegate
                                        {
                                            if (IsStopRequested())
                                            {
                                                throw new OperationCanceledException("Replay recovery was stopped.");
                                            }
                                            ReplayDiagnostics.Write(
                                                "WASAPI restart failed; continuing recovered GDI capture without audio");
                                            audioSession.Stop();
                                            audioSession.Dispose();
                                            audioSession = null;
                                            SetAudioState(ReplayAudioState.Unavailable);
                                            encoder.Dispose();
                                            buffer.Dispose();
                                            buffer = new ReplayBuffer(cacheDirectory, _settings.buffer_duration);
                                            encoder = new ReplayEncoder();
                                            lock (_syncRoot)
                                            {
                                                if (_disposed || _stopRequested)
                                                {
                                                    throw new OperationCanceledException("Replay recovery was stopped.");
                                                }
                                                _encoder = encoder;
                                                _buffer = buffer;
                                            }
                                            encoder.Start(cacheDirectory, _settings, captureSession, null);
                                            StabilizeEncoderStartup(encoder);
                                        },
                                        out audioStartFailure);

                                    if (audioStarted)
                                    {
                                        SetAudioState(ReplayAudioState.Active);
                                    }
                                    else
                                    {
                                        ReplayDiagnostics.Write(
                                            "WASAPI unavailable after DdaGrab recovery: " + audioStartFailure.Message);
                                    }
                                }

                                lock (_syncRoot)
                                {
                                    if (_disposed || _stopRequested)
                                    {
                                        throw new OperationCanceledException("Replay recovery was stopped.");
                                    }
                                    _state = ReplayState.Recording;
                                    _lastError = null;
                                    EnqueueNotification(
                                        "即时回放捕获已自动恢复",
                                        "即时回放捕获已自动恢复，最近录像缓存已重新开始。",
                                        false);
                                }

                                ReplayDiagnostics.Write(
                                    "DdaGrab runtime recovery completed; backend=GdiGrab; replay ring reset");
                            });
                        if (runtimeRecovered)
                        {
                            runtimeFallbackUsed = true;
                            lastSegmentReceivedUtc = DateTime.UtcNow;
                            continue;
                        }
                        throw BuildEncoderFailure(encoder, "即时回放捕获进程意外退出");
                    }
                    if (audioSession != null)
                    {
                        UpdateAudioStateFromSession(audioSession);
                    }
                    if (captureSession.HasDisplayChanged())
                    {
                        if (captureSession.Backend == ReplayCaptureBackend.DdaGrab)
                        {
                            if (!ddaDisplayChangeObservedUtc.HasValue)
                            {
                                ddaDisplayChangeObservedUtc = DateTime.UtcNow;
                                ReplayDiagnostics.Write(
                                    "Display change detected during DdaGrab; waiting briefly for DXGI encoder exit before graceful failure");
                            }
                            if (DateTime.UtcNow - ddaDisplayChangeObservedUtc.Value < TimeSpan.FromSeconds(4))
                            {
                                Thread.Sleep(100);
                                continue;
                            }
                        }
                        throw new InvalidOperationException("主显示器分辨率或连接状态已改变，请关闭后重新开启即时回放。");
                    }
                    ddaDisplayChangeObservedUtc = null;
                    if (DateTime.UtcNow - lastSegmentReceivedUtc > TimeSpan.FromSeconds(15))
                    {
                        throw new InvalidOperationException("超过 15 秒没有生成新录像片段，已停止即时回放以保护临时磁盘空间。");
                    }
                    Thread.Sleep(250);
                }
            }
            catch (OperationCanceledException)
            {
                // A user or application stop is an expected end to the capture loop.
            }
            catch (Exception exception)
            {
                if (!IsStopRequested())
                {
                    failed = true;
                    failureMessage = exception.Message;
                    ReplayDiagnostics.Write("Capture error: " + exception.Message);
                    if (!string.IsNullOrWhiteSpace(encoder.RecentError))
                    {
                        ReplayDiagnostics.Write("Encoder error: " + encoder.RecentError.Replace('\r', ' ').Replace('\n', ' '));
                    }
                }
            }
            finally
            {
                if (audioSession != null)
                {
                    double audioWorkerCpuSeconds = audioSession.WorkerCpuSeconds;
                    double audioInputDurationSeconds = audioSession.WrittenDurationSeconds;
                    lock (_syncRoot)
                    {
                        _audioWorkerCpuSeconds = audioWorkerCpuSeconds;
                        _audioInputDurationSeconds = audioInputDurationSeconds;
                    }
                    if (audioInputDurationSeconds > 0)
                    {
                        ReplayDiagnostics.Write(
                            "Audio input samples written: duration=" +
                            audioInputDurationSeconds.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture) + "s");
                    }
                    audioSession.Stop();
                    audioSession.Dispose();
                }
                encoder.Stop();
                encoder.Dispose();
                if (buffer != null)
                {
                    buffer.Dispose();
                }

                lock (_syncRoot)
                {
                    if (ReferenceEquals(_encoder, encoder))
                    {
                        _encoder = null;
                    }
                    if (ReferenceEquals(_buffer, buffer))
                    {
                        _buffer = null;
                    }

                    if (_disposed || _stopRequested)
                    {
                        _state = ReplayState.Disabled;
                        _audioState = ReplayAudioState.Disabled;
                        _lastError = null;
                    }
                    else if (failed)
                    {
                        _state = ReplayState.Error;
                        if (_settings.capture_system_audio)
                        {
                            _audioState = ReplayAudioState.Unavailable;
                        }
                        _lastError = failureMessage;
                        EnqueueNotification("即时回放启动或录制失败", failureMessage, true);
                    }
                    else
                    {
                        _state = ReplayState.Disabled;
                        _audioState = ReplayAudioState.Disabled;
                    }
                    _recordingThread = null;
                    TryDisposeStopEventUnsafe();
                }

                ReplayDiagnostics.Write("Capture resources released");
            }
        }

        private void SaveLoop(ReplayBuffer buffer, ReplaySaver saver, string ffmpegPath, int latestIndex)
        {
            ReplayBufferSnapshot snapshot = null;
            try
            {
                if (!buffer.WaitForSegmentAfter(latestIndex, 5000, _stopEvent))
                {
                    throw new InvalidOperationException("等待当前录像片段完成超时，请稍后重试。");
                }

                snapshot = buffer.AcquireSnapshot();
                ReplaySaveResult result = saver.Save(ffmpegPath, snapshot);
                ReplayDiagnostics.Write(
                    "Replay saved: " + result.Path + "; duration=" +
                    result.DurationSeconds.ToString("F1", System.Globalization.CultureInfo.InvariantCulture) +
                    "s; saveMs=" + result.Elapsed.TotalMilliseconds.ToString("F0", System.Globalization.CultureInfo.InvariantCulture));
                lock (_syncRoot)
                {
                    if (!_disposed)
                    {
                        EnqueueNotification(
                            "即时回放已保存",
                            Path.GetFileName(result.Path) + " · " + result.DurationSeconds.ToString("F0") + " 秒",
                            false);
                    }
                }
            }
            catch (OperationCanceledException)
            {
                ReplayDiagnostics.Write("Replay save cancelled during application shutdown");
            }
            catch (Exception exception)
            {
                ReplayDiagnostics.Write("Replay save failed: " + exception.Message);
                lock (_syncRoot)
                {
                    if (!_disposed)
                    {
                        EnqueueNotification("即时回放保存失败", exception.Message, true);
                    }
                }
            }
            finally
            {
                if (snapshot != null)
                {
                    snapshot.Dispose();
                }
                saver.Dispose();
                lock (_syncRoot)
                {
                    if (ReferenceEquals(_saver, saver))
                    {
                        _saver = null;
                    }
                    _savingThread = null;
                    _isSaving = false;
                    TryDisposeStopEventUnsafe();
                }
            }
        }

        private bool IsStopRequested()
        {
            lock (_syncRoot)
            {
                return _stopRequested || _disposed;
            }
        }

        private void SetAudioState(ReplayAudioState state)
        {
            lock (_syncRoot)
            {
                _audioState = state;
            }
        }

        internal static bool TryStartWithAudio(Action startWithAudio, out Exception failure)
        {
            if (startWithAudio == null)
            {
                throw new ArgumentNullException("startWithAudio");
            }
            try
            {
                startWithAudio();
                failure = null;
                return true;
            }
            catch (Exception exception)
            {
                failure = exception;
                return false;
            }
        }

        internal static ReplayCaptureBackend TryStartWithCaptureBackendFallback(
            ReplayCaptureBackend requestedBackend,
            Action startRequestedBackend,
            Func<bool> isRequestedBackendUnavailable,
            Func<bool> isStopRequested,
            Action cleanAndStartGdiGrab,
            out Exception backendFailure)
        {
            if (startRequestedBackend == null)
            {
                throw new ArgumentNullException("startRequestedBackend");
            }
            if (isRequestedBackendUnavailable == null)
            {
                throw new ArgumentNullException("isRequestedBackendUnavailable");
            }
            if (isStopRequested == null)
            {
                throw new ArgumentNullException("isStopRequested");
            }
            if (cleanAndStartGdiGrab == null)
            {
                throw new ArgumentNullException("cleanAndStartGdiGrab");
            }

            if (requestedBackend != ReplayCaptureBackend.DdaGrab)
            {
                startRequestedBackend();
                backendFailure = null;
                return ReplayCaptureBackend.GdiGrab;
            }

            try
            {
                startRequestedBackend();
                backendFailure = null;
                return ReplayCaptureBackend.DdaGrab;
            }
            catch (Exception exception)
            {
                if (isStopRequested())
                {
                    throw new OperationCanceledException("Replay startup was stopped.", exception);
                }
                if (!isRequestedBackendUnavailable())
                {
                    throw;
                }

                backendFailure = exception;
                ReplayDiagnostics.Write("DdaGrab startup failed; retrying with GdiGrab: " + exception.Message);
                cleanAndStartGdiGrab();
                return ReplayCaptureBackend.GdiGrab;
            }
        }

        internal static bool TryStartWithAudioAndFallback(
            Action startAndStabilizeWithAudio,
            Func<bool> isStopRequested,
            Action cleanAndStartVideoOnly,
            out Exception audioFailure)
        {
            if (startAndStabilizeWithAudio == null)
            {
                throw new ArgumentNullException("startAndStabilizeWithAudio");
            }
            if (isStopRequested == null)
            {
                throw new ArgumentNullException("isStopRequested");
            }
            if (cleanAndStartVideoOnly == null)
            {
                throw new ArgumentNullException("cleanAndStartVideoOnly");
            }

            try
            {
                startAndStabilizeWithAudio();
                audioFailure = null;
                return true;
            }
            catch (Exception exception)
            {
                if (isStopRequested())
                {
                    throw new OperationCanceledException("Audio startup was stopped.", exception);
                }

                audioFailure = exception;
                cleanAndStartVideoOnly();
                return false;
            }
        }

        internal static void RunEncoderShutdownFailSafe(
            bool recordingWorkerTimedOut,
            Action stopEncoder,
            Action logForcedShutdown,
            Action joinAfterStop)
        {
            if (!recordingWorkerTimedOut)
            {
                return;
            }
            if (stopEncoder == null) throw new ArgumentNullException("stopEncoder");
            if (logForcedShutdown == null) throw new ArgumentNullException("logForcedShutdown");
            if (joinAfterStop == null) throw new ArgumentNullException("joinAfterStop");

            stopEncoder();
            joinAfterStop();
            logForcedShutdown();
        }

        internal static bool TryRunDdaRuntimeFallback(
            ReplayCaptureBackend currentBackend,
            bool encoderExitedUnexpectedly,
            bool stopRequested,
            bool fallbackAlreadyUsed,
            Action recoverWithGdi)
        {
            if (currentBackend != ReplayCaptureBackend.DdaGrab ||
                !encoderExitedUnexpectedly ||
                stopRequested ||
                fallbackAlreadyUsed)
            {
                return false;
            }
            if (recoverWithGdi == null)
            {
                throw new ArgumentNullException("recoverWithGdi");
            }

            recoverWithGdi();
            return true;
        }

        internal static string ClassifyDdaRuntimeFailure(string error)
        {
            string value = error ?? string.Empty;
            if (value.IndexOf("AcquireNextFrame failed", StringComparison.OrdinalIgnoreCase) >= 0 ||
                value.IndexOf("887a0026", StringComparison.OrdinalIgnoreCase) >= 0 ||
                value.IndexOf("DXGI_ERROR_ACCESS_LOST", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return "DXGI_ERROR_ACCESS_LOST";
            }

            return "unclassified DDA runtime failure";
        }

        private void StabilizeEncoderStartup(ReplayEncoder encoder)
        {
            DateTime startupDeadline = DateTime.UtcNow.AddSeconds(3);
            while (true)
            {
                if (IsStopRequested())
                {
                    throw new OperationCanceledException("Replay startup was stopped.");
                }
                if (encoder.HasExited)
                {
                    throw BuildEncoderFailure(encoder, "桌面捕获或 NVENC 初始化失败");
                }
                if (DateTime.UtcNow >= startupDeadline)
                {
                    return;
                }
                Thread.Sleep(100);
            }
        }

        private void UpdateAudioStateFromSession(ReplayAudioCaptureSession audioSession)
        {
            ReplayAudioState state = audioSession.State;
            lock (_syncRoot)
            {
                ReplayAudioState previous = _audioState;
                _audioState = state;
                if (previous == ReplayAudioState.Active && state == ReplayAudioState.Unavailable && !_disposed)
                {
                    EnqueueNotification(
                        "系统音频不可用",
                        "即时回放仍在录制视频；系统声音将保持静音，重新开启回放后可重试。",
                        true);
                }
            }
        }

        private string CreateCacheDirectory()
        {
            string root = Path.Combine(Path.GetTempPath(), "BoltSnip", "replay-cache");
            Directory.CreateDirectory(root);
            CleanupStaleReplayCacheOnce(root);

            // ReplayBuffer owns its session directory; snapshot leases can outlive capture.
            string session = Path.Combine(root, Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(session);
            return session;
        }

        private static void CleanupStaleReplayCacheOnce(string root)
        {
            // This runs before the first session is created in this process, never on every
            // Replay start. A stale session owned by this process therefore cannot be swept.
            if (Interlocked.CompareExchange(ref _staleReplayCacheCleanupAttempted, 1, 0) != 0)
            {
                return;
            }

            CleanupStaleReplayCacheDirectories(root, DateTime.UtcNow, null, null);
        }

        internal static void CleanupStaleReplayCacheDirectories(
            string root,
            DateTime utcNow,
            string activeSessionDirectory,
            Action<string> deleteDirectory)
        {
            if (string.IsNullOrWhiteSpace(root))
            {
                return;
            }

            DateTime cutoffUtc = utcNow.ToUniversalTime() - StaleReplayCacheAge;
            string activeSessionPath = null;
            try
            {
                if (!string.IsNullOrWhiteSpace(activeSessionDirectory))
                {
                    activeSessionPath = NormalizeDirectoryPath(activeSessionDirectory);
                }

                string[] sessions = Directory.GetDirectories(root);
                for (int index = 0; index < sessions.Length; index++)
                {
                    string session = sessions[index];
                    try
                    {
                        if (activeSessionPath != null && string.Equals(
                            NormalizeDirectoryPath(session), activeSessionPath, StringComparison.OrdinalIgnoreCase))
                        {
                            continue;
                        }

                        DirectoryInfo info = new DirectoryInfo(session);
                        if (info.LastWriteTimeUtc >= cutoffUtc)
                        {
                            continue;
                        }

                        if (deleteDirectory == null)
                        {
                            Directory.Delete(session, true);
                        }
                        else
                        {
                            deleteDirectory(session);
                        }
                        ReplayDiagnostics.Write("Deleted stale replay cache session: " + session);
                    }
                    catch (Exception exception)
                    {
                        ReplayDiagnostics.Write("Stale replay cache cleanup skipped " + session + ": " +
                            CaptureDiagnostics.ExceptionDetails("cache cleanup", exception));
                    }
                }
            }
            catch (Exception exception)
            {
                // Cache cleanup is best-effort and must never prevent Replay initialization.
                ReplayDiagnostics.Write("Stale replay cache cleanup failed: " +
                    CaptureDiagnostics.ExceptionDetails("cache cleanup", exception));
            }
        }

        private static string NormalizeDirectoryPath(string path)
        {
            string fullPath = Path.GetFullPath(path);
            string root = Path.GetPathRoot(fullPath);
            return fullPath.Length > root.Length
                ? fullPath.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                : fullPath;
        }

        private void TryDisposeStopEventUnsafe()
        {
            if (!_disposed || _stopEventDisposed || _recordingThread != null || _savingThread != null)
            {
                return;
            }

            _stopEvent.Dispose();
            _stopEventDisposed = true;
        }

        private static Exception BuildEncoderFailure(ReplayEncoder encoder, string message)
        {
            string details = encoder.RecentError;
            return new InvalidOperationException(
                string.IsNullOrWhiteSpace(details) ? message : message + Environment.NewLine + details);
        }

        private void EnqueueNotification(string title, string message, bool isError)
        {
            if (message != null && message.Length > 220)
            {
                message = message.Substring(0, 217) + "…";
            }
            _notifications.Enqueue(new ReplayNotification(title, message, isError));
            while (_notifications.Count > 12)
            {
                _notifications.Dequeue();
            }
        }

        private static void JoinQuietly(Thread thread, int timeoutMilliseconds)
        {
            if (thread == null || Thread.CurrentThread == thread)
            {
                return;
            }

            try
            {
                thread.Join(timeoutMilliseconds);
            }
            catch
            {
                // Shutdown cleanup must not escape through the tray application context.
            }
        }
    }

    internal sealed class ReplayNotification
    {
        internal ReplayNotification(string title, string message, bool isError)
        {
            Title = title;
            Message = message;
            IsError = isError;
        }

        internal string Title { get; private set; }
        internal string Message { get; private set; }
        internal bool IsError { get; private set; }
    }
}
