using System;
using System.IO;
using System.Text;

public static class ReplayAudioSyncWave
{
    public static void WritePattern(
        string path,
        int sampleRate,
        int durationSeconds,
        int toneFrequencyHz,
        int periodMilliseconds,
        int leadingSilenceMilliseconds,
        int toneMilliseconds,
        short amplitude)
    {
        if (string.IsNullOrWhiteSpace(path)) throw new ArgumentException("A wave output path is required.", "path");
        if (sampleRate <= 0 || durationSeconds <= 0 || toneFrequencyHz <= 0 || periodMilliseconds <= 0 ||
            leadingSilenceMilliseconds < 0 || toneMilliseconds <= 0 || leadingSilenceMilliseconds + toneMilliseconds > periodMilliseconds)
        {
            throw new ArgumentOutOfRangeException("durationSeconds", "The sync wave format or tone timings are invalid.");
        }

        int sampleCount = checked(sampleRate * durationSeconds);
        int dataLength = checked(sampleCount * 2);
        int periodSamples = checked(sampleRate * periodMilliseconds / 1000);
        int toneStart = checked(sampleRate * leadingSilenceMilliseconds / 1000);
        int toneLength = checked(sampleRate * toneMilliseconds / 1000);

        using (FileStream stream = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None))
        using (BinaryWriter writer = new BinaryWriter(stream, Encoding.ASCII))
        {
            writer.Write(Encoding.ASCII.GetBytes("RIFF"));
            writer.Write(dataLength + 36);
            writer.Write(Encoding.ASCII.GetBytes("WAVEfmt "));
            writer.Write(16);
            writer.Write((short)1);
            writer.Write((short)1);
            writer.Write(sampleRate);
            writer.Write(sampleRate * 2);
            writer.Write((short)2);
            writer.Write((short)16);
            writer.Write(Encoding.ASCII.GetBytes("data"));
            writer.Write(dataLength);

            for (int sample = 0; sample < sampleCount; sample++)
            {
                int phase = sample % periodSamples;
                short value = 0;
                if (phase >= toneStart && phase < toneStart + toneLength)
                {
                    double toneSample = phase - toneStart;
                    value = (short)Math.Round(amplitude * Math.Sin(2.0 * Math.PI * toneFrequencyHz * toneSample / sampleRate));
                }
                writer.Write(value);
            }
        }
    }
}
