using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;

namespace BoltSnip
{
    internal sealed class ReplayBuffer : IDisposable
    {
        private readonly object _syncRoot = new object();
        private readonly string _directory;
        private readonly TimeSpan _bufferDuration;
        private readonly List<ReplaySegment> _segments = new List<ReplaySegment>();
        private readonly Dictionary<int, int> _leaseCounts = new Dictionary<int, int>();
        private readonly Dictionary<int, ReplaySegment> _retiredSegments = new Dictionary<int, ReplaySegment>();
        private double _currentDurationSeconds;
        private int _droppedSegmentCount;
        private int _highestSeenSegmentIndex = -1;
        private bool _disposed;

        internal ReplayBuffer(string directory, TimeSpan bufferDuration)
        {
            if (string.IsNullOrWhiteSpace(directory))
            {
                throw new ArgumentException("A cache directory is required.", "directory");
            }
            if (bufferDuration <= TimeSpan.Zero)
            {
                throw new ArgumentOutOfRangeException("bufferDuration");
            }

            _directory = Path.GetFullPath(directory).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            _bufferDuration = bufferDuration;
            Directory.CreateDirectory(_directory);
        }

        internal string DirectoryPath
        {
            get { return _directory.TrimEnd(Path.DirectorySeparatorChar); }
        }

        internal int SegmentCount
        {
            get { lock (_syncRoot) { return _segments.Count; } }
        }

        internal double CurrentDurationSeconds
        {
            get { lock (_syncRoot) { return _currentDurationSeconds; } }
        }

        internal int LatestIndex
        {
            get
            {
                lock (_syncRoot)
                {
                    return _segments.Count == 0 ? -1 : _segments[_segments.Count - 1].Index;
                }
            }
        }

        internal bool AddSegment(ReplaySegment segment)
        {
            if (segment == null)
            {
                throw new ArgumentNullException("segment");
            }

            string fullPath = Path.GetFullPath(segment.Path);
            if (!fullPath.StartsWith(_directory, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("A replay segment was outside the active cache directory.");
            }
            if (!File.Exists(fullPath) || new FileInfo(fullPath).Length == 0)
            {
                return false;
            }

            lock (_syncRoot)
            {
                if (_disposed || segment.Index <= _highestSeenSegmentIndex)
                {
                    return false;
                }

                _highestSeenSegmentIndex = segment.Index;
                ReplaySegment stored = new ReplaySegment(segment.Index, fullPath, segment.DurationSeconds);
                _segments.Add(stored);
                _currentDurationSeconds += stored.DurationSeconds;
                TrimOldestSegments();
                Monitor.PulseAll(_syncRoot);
                return true;
            }
        }

        internal bool WaitForSegmentAfter(int index, int timeoutMilliseconds, WaitHandle stopSignal)
        {
            DateTime deadline = DateTime.UtcNow.AddMilliseconds(Math.Max(0, timeoutMilliseconds));
            lock (_syncRoot)
            {
                while (!_disposed && LatestIndexUnsafe() <= index && !IsSignaled(stopSignal))
                {
                    int remaining = (int)Math.Max(0, (deadline - DateTime.UtcNow).TotalMilliseconds);
                    if (remaining == 0)
                    {
                        return false;
                    }
                    Monitor.Wait(_syncRoot, remaining);
                }

                return !_disposed && LatestIndexUnsafe() > index;
            }
        }

        internal void WakeWaiters()
        {
            lock (_syncRoot)
            {
                Monitor.PulseAll(_syncRoot);
            }
        }

        internal ReplayBufferSnapshot AcquireSnapshot()
        {
            lock (_syncRoot)
            {
                if (_disposed)
                {
                    throw new ObjectDisposedException("ReplayBuffer");
                }
                if (_segments.Count == 0)
                {
                    throw new InvalidOperationException("等待第一个完整录像片段后再保存即时回放。");
                }

                List<ReplaySegment> selected = new List<ReplaySegment>();
                double selectedDuration = 0;
                for (int index = _segments.Count - 1; index >= 0; index--)
                {
                    ReplaySegment segment = _segments[index];
                    if (selectedDuration + segment.DurationSeconds > _bufferDuration.TotalSeconds + 0.05)
                    {
                        break;
                    }
                    selected.Add(segment);
                    selectedDuration += segment.DurationSeconds;
                }

                selected.Reverse();
                for (int index = 0; index < selected.Count; index++)
                {
                    int segmentIndex = selected[index].Index;
                    int count;
                    _leaseCounts.TryGetValue(segmentIndex, out count);
                    _leaseCounts[segmentIndex] = count + 1;
                }

                return new ReplayBufferSnapshot(this, selected.ToArray(), selectedDuration);
            }
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
                for (int index = 0; index < _segments.Count; index++)
                {
                    RetireSegment(_segments[index]);
                }
                _segments.Clear();
                _currentDurationSeconds = 0;
                Monitor.PulseAll(_syncRoot);
                DeleteDirectoryIfReleased();
            }
        }

        internal void ReleaseSnapshot(ReplaySegment[] segments)
        {
            lock (_syncRoot)
            {
                for (int index = 0; index < segments.Length; index++)
                {
                    ReplaySegment segment = segments[index];
                    int count;
                    if (!_leaseCounts.TryGetValue(segment.Index, out count))
                    {
                        continue;
                    }

                    if (count > 1)
                    {
                        _leaseCounts[segment.Index] = count - 1;
                        continue;
                    }

                    _leaseCounts.Remove(segment.Index);
                    ReplaySegment retired;
                    if (_retiredSegments.TryGetValue(segment.Index, out retired))
                    {
                        _retiredSegments.Remove(segment.Index);
                        TryDeleteFile(retired.Path);
                    }
                }

                DeleteDirectoryIfReleased();
            }
        }

        private int LatestIndexUnsafe()
        {
            return _segments.Count == 0 ? -1 : _segments[_segments.Count - 1].Index;
        }

        private static bool IsSignaled(WaitHandle signal)
        {
            return signal != null && signal.WaitOne(0);
        }

        private void TrimOldestSegments()
        {
            while (_segments.Count > 0 && _currentDurationSeconds > _bufferDuration.TotalSeconds + 0.05)
            {
                ReplaySegment oldest = _segments[0];
                _segments.RemoveAt(0);
                _currentDurationSeconds -= oldest.DurationSeconds;
                RetireSegment(oldest);
                _droppedSegmentCount++;
                if (_droppedSegmentCount == 1 || _droppedSegmentCount % 30 == 0)
                {
                    ReplayDiagnostics.Write(
                        "Dropped oldest segment; total=" + _droppedSegmentCount +
                        "; latest=" + oldest.Index);
                }
            }
        }

        private void RetireSegment(ReplaySegment segment)
        {
            int leaseCount;
            if (_leaseCounts.TryGetValue(segment.Index, out leaseCount) && leaseCount > 0)
            {
                _retiredSegments[segment.Index] = segment;
            }
            else
            {
                TryDeleteFile(segment.Path);
            }
        }

        private void DeleteDirectoryIfReleased()
        {
            if (!_disposed || _retiredSegments.Count != 0)
            {
                return;
            }

            try
            {
                string directory = _directory.TrimEnd(Path.DirectorySeparatorChar);
                if (Directory.Exists(directory))
                {
                    Directory.Delete(directory, true);
                }
            }
            catch (Exception exception)
            {
                ReplayDiagnostics.Write("Cache cleanup failed: " + exception.Message);
            }
        }

        private static void TryDeleteFile(string path)
        {
            try
            {
                if (File.Exists(path))
                {
                    File.Delete(path);
                }
            }
            catch (Exception exception)
            {
                ReplayDiagnostics.Write("Segment cleanup failed: " + exception.Message);
            }
        }
    }

    internal sealed class ReplayBufferSnapshot : IDisposable
    {
        private ReplayBuffer _owner;
        private readonly ReplaySegment[] _segments;

        internal ReplayBufferSnapshot(ReplayBuffer owner, ReplaySegment[] segments, double durationSeconds)
        {
            _owner = owner;
            _segments = segments;
            DurationSeconds = durationSeconds;
        }

        internal ReplaySegment[] Segments
        {
            get { return (ReplaySegment[])_segments.Clone(); }
        }

        internal double DurationSeconds { get; private set; }

        public void Dispose()
        {
            ReplayBuffer owner = Interlocked.Exchange(ref _owner, null);
            if (owner != null)
            {
                owner.ReleaseSnapshot(_segments);
            }
        }
    }
}
