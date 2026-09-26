using System;

namespace BoltSnip
{
    internal enum ReplayCaptureBackend
    {
        GdiGrab,
        DdaGrab
    }

    internal static class ReplayCaptureBackendSelection
    {
        internal const string EnvironmentVariable = "BOLTSNIP_REPLAY_CAPTURE_BACKEND";

        internal static ReplayCaptureBackend FromEnvironment(string value)
        {
            return string.Equals(value, "ddagrab", StringComparison.OrdinalIgnoreCase)
                ? ReplayCaptureBackend.DdaGrab
                : ReplayCaptureBackend.GdiGrab;
        }
    }

    internal sealed class ReplaySettings
    {
        internal readonly TimeSpan buffer_duration;
        internal readonly int target_fps;
        internal readonly int segment_duration_seconds;
        internal readonly bool capture_system_audio;
        internal readonly ReplayCaptureBackend capture_backend;

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
            : this(
                TimeSpan.FromSeconds(300),
                60,
                2,
                true,
                ReplayCaptureBackendSelection.FromEnvironment(
                    Environment.GetEnvironmentVariable(ReplayCaptureBackendSelection.EnvironmentVariable)))
        {
        }

        internal ReplaySettings(TimeSpan bufferDuration, int targetFps, int segmentDurationSeconds)
            : this(bufferDuration, targetFps, segmentDurationSeconds, true, ReplayCaptureBackend.GdiGrab)
        {
        }

        internal ReplaySettings(TimeSpan bufferDuration, int targetFps, int segmentDurationSeconds, bool captureSystemAudio)
            : this(bufferDuration, targetFps, segmentDurationSeconds, captureSystemAudio, ReplayCaptureBackend.GdiGrab)
        {
        }

        internal ReplaySettings(
            TimeSpan bufferDuration,
            int targetFps,
            int segmentDurationSeconds,
            bool captureSystemAudio,
            ReplayCaptureBackend captureBackend)
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
            capture_system_audio = captureSystemAudio;
            capture_backend = captureBackend;
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
