using System;

namespace BoltSnip
{
    internal sealed class ReplaySettings
    {
        internal readonly TimeSpan buffer_duration;
        internal readonly int target_fps;
        internal readonly int segment_duration_seconds;

        internal int segment_list_size
        {
            get
            {
                double requiredSegments = Math.Ceiling(
                    buffer_duration.TotalSeconds / segment_duration_seconds);
                if (requiredSegments > int.MaxValue - 2)
                {
                    throw new InvalidOperationException("The replay buffer requires too many segments.");
                }
                return (int)requiredSegments + 2;
            }
        }

        internal ReplaySettings()
            : this(TimeSpan.FromSeconds(300), 60, 2)
        {
        }

        internal ReplaySettings(TimeSpan bufferDuration, int targetFps, int segmentDurationSeconds)
        {
            if (bufferDuration <= TimeSpan.Zero)
            {
                throw new ArgumentOutOfRangeException("bufferDuration");
            }
            if (targetFps <= 0)
            {
                throw new ArgumentOutOfRangeException("targetFps");
            }
            if (segmentDurationSeconds <= 0)
            {
                throw new ArgumentOutOfRangeException("segmentDurationSeconds");
            }

            buffer_duration = bufferDuration;
            target_fps = targetFps;
            segment_duration_seconds = segmentDurationSeconds;
        }
    }

    internal enum ReplayState
    {
        Disabled,
        Starting,
        Recording,
        Error,
        Stopping
    }
}
