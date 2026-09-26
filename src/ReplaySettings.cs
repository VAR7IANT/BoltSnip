using System;

namespace BoltSnip
{
    internal enum ReplayCaptureBackend
    {
        GdiGrab,
        DdaGrab
    }

    internal static class ReplayCaptureBackendPolicy
    {
        internal const string EnvironmentVariable = "BOLTSNIP_REPLAY_CAPTURE_BACKEND";

        internal static ReplayCaptureBackend FromEnvironment(string value)
        {
            return FromEnvironment(value, delegate
            {
                return System.Windows.Forms.Screen.AllScreens.Length;
            });
        }

        internal static ReplayCaptureBackend FromEnvironment(string value, Func<int> getActiveScreenCount)
        {
            if (string.Equals(value, "gdigrab", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(value, "ddagrab", StringComparison.OrdinalIgnoreCase))
            {
                return CandidateForScreenCount(value, 0);
            }

            if (getActiveScreenCount == null)
            {
                return ReplayCaptureBackend.GdiGrab;
            }

            try
            {
                return CandidateForScreenCount(value, getActiveScreenCount());
            }
            catch
            {
                return ReplayCaptureBackend.GdiGrab;
            }
        }

        internal static ReplayCaptureBackend CandidateForScreenCount(string value, int activeScreenCount)
        {
            if (string.Equals(value, "gdigrab", StringComparison.OrdinalIgnoreCase))
            {
                return ReplayCaptureBackend.GdiGrab;
            }
            if (string.Equals(value, "ddagrab", StringComparison.OrdinalIgnoreCase))
            {
                return ReplayCaptureBackend.DdaGrab;
            }

            return activeScreenCount == 1
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
                ReplayCaptureBackendPolicy.FromEnvironment(
                    Environment.GetEnvironmentVariable(ReplayCaptureBackendPolicy.EnvironmentVariable)))
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
