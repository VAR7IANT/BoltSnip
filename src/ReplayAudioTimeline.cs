using System;

namespace BoltSnip
{
    // Maps packet QPC positions to the PCM sample clock shared with generated silence.
    internal sealed class ReplayAudioTimeline
    {
        private readonly int _sampleRate;
        private bool _anchored;
        private long _originQpc;
        private long _originFrame;

        internal ReplayAudioTimeline(int sampleRate)
        {
            if (sampleRate <= 0) throw new ArgumentOutOfRangeException("sampleRate");
            _sampleRate = sampleRate;
        }

        internal bool IsAnchored { get { return _anchored; } }

        internal long GetPacketStartFrame(long qpc, long writtenFrames)
        {
            if (!_anchored)
            {
                _originQpc = qpc;
                _originFrame = writtenFrames;
                _anchored = true;
            }
            return checked(_originFrame + (long)Math.Round(
                (qpc - _originQpc) * (_sampleRate / 10000000.0),
                MidpointRounding.AwayFromZero));
        }

        internal long GetDueSilenceFrames(long qpc, long writtenFrames, int safetyFrames)
        {
            if (!_anchored) return 0;
            return Math.Max(0, GetPacketStartFrame(qpc, writtenFrames) - safetyFrames - writtenFrames);
        }

        internal long GetMissingFrames(long packetStartFrame, long writtenFrames, int deadZoneFrames)
        {
            long gap = packetStartFrame - writtenFrames;
            return gap > deadZoneFrames ? gap : 0;
        }

        internal long GetOverlapFrames(long packetStartFrame, long writtenFrames, int deadZoneFrames)
        {
            long overlap = writtenFrames - packetStartFrame;
            return overlap > deadZoneFrames ? overlap : 0;
        }
    }
}
