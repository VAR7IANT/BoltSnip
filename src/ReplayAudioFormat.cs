using System;

namespace BoltSnip
{
    internal sealed class ReplayAudioFormat
    {
        private static readonly Guid PcmSubFormat = new Guid("00000001-0000-0010-8000-00aa00389b71");
        private static readonly Guid IeeeFloatSubFormat = new Guid("00000003-0000-0010-8000-00aa00389b71");

        private ReplayAudioFormat(int channels, int sampleRate, int bitsPerSample, string ffmpegSampleFormat, bool requiresPacked24Conversion)
        {
            Channels = channels;
            SampleRate = sampleRate;
            BitsPerSample = bitsPerSample;
            FfmpegSampleFormat = ffmpegSampleFormat;
            RequiresPacked24Conversion = requiresPacked24Conversion;
        }

        internal int Channels { get; private set; }
        internal int SampleRate { get; private set; }
        internal int BitsPerSample { get; private set; }
        internal string FfmpegSampleFormat { get; private set; }
        internal bool RequiresPacked24Conversion { get; private set; }

        internal int OutputBytesPerFrame
        {
            get { return Channels * (RequiresPacked24Conversion ? 3 : BitsPerSample / 8); }
        }

        internal static ReplayAudioFormat Parse(
            int formatTag,
            int channels,
            int sampleRate,
            int bitsPerSample,
            int blockAlign,
            int extraSize,
            int validBitsPerSample,
            Guid subFormat)
        {
            if (channels <= 0 || channels > 32)
            {
                throw Unsupported("channel count " + channels);
            }
            if (sampleRate <= 0)
            {
                throw Unsupported("sample rate " + sampleRate);
            }
            if (bitsPerSample <= 0 || bitsPerSample % 8 != 0)
            {
                throw Unsupported("container size " + bitsPerSample);
            }

            bool extensible = formatTag == 0xfffe;
            if (extensible)
            {
                if (extraSize < 22)
                {
                    throw Unsupported("incomplete WAVEFORMATEXTENSIBLE descriptor");
                }
                if (subFormat == PcmSubFormat)
                {
                    formatTag = 1;
                }
                else if (subFormat == IeeeFloatSubFormat)
                {
                    formatTag = 3;
                }
                else
                {
                    throw Unsupported("subformat " + subFormat);
                }
            }

            int validBits = validBitsPerSample <= 0 ? bitsPerSample : validBitsPerSample;
            if (validBits > bitsPerSample)
            {
                throw Unsupported("valid bit count " + validBits);
            }

            if (formatTag == 3)
            {
                if (bitsPerSample != 32 || validBits != 32)
                {
                    throw Unsupported("IEEE float " + validBits + "-bit samples");
                }
                ValidateBlockAlign(channels, bitsPerSample, blockAlign);
                return new ReplayAudioFormat(channels, sampleRate, bitsPerSample, "f32le", false);
            }

            if (formatTag != 1)
            {
                throw Unsupported("format tag 0x" + formatTag.ToString("X4"));
            }

            if (bitsPerSample == 16 && validBits == 16)
            {
                ValidateBlockAlign(channels, bitsPerSample, blockAlign);
                return new ReplayAudioFormat(channels, sampleRate, bitsPerSample, "s16le", false);
            }
            if (bitsPerSample == 24 && validBits == 24)
            {
                ValidateBlockAlign(channels, bitsPerSample, blockAlign);
                return new ReplayAudioFormat(channels, sampleRate, bitsPerSample, "s24le", false);
            }
            if (bitsPerSample == 32 && validBits == 32)
            {
                ValidateBlockAlign(channels, bitsPerSample, blockAlign);
                return new ReplayAudioFormat(channels, sampleRate, bitsPerSample, "s32le", false);
            }
            if (bitsPerSample == 32 && validBits == 24)
            {
                ValidateBlockAlign(channels, bitsPerSample, blockAlign);
                return new ReplayAudioFormat(channels, sampleRate, bitsPerSample, "s24le", true);
            }

            throw Unsupported("PCM " + validBits + "-bit samples in a " + bitsPerSample + "-bit container");
        }

        private static void ValidateBlockAlign(int channels, int bitsPerSample, int blockAlign)
        {
            int expected = channels * (bitsPerSample / 8);
            if (blockAlign != expected)
            {
                throw Unsupported("block alignment " + blockAlign + " (expected " + expected + ")");
            }
        }

        private static InvalidOperationException Unsupported(string detail)
        {
            return new InvalidOperationException("Audio format unsupported: " + detail + ".");
        }
    }

    internal enum ReplayAudioState
    {
        Disabled,
        Starting,
        Active,
        Unavailable
    }
}
