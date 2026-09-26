using System;
using System.Collections.Generic;
using System.IO;

public static class ReplayAudioSignalAnalyzer
{
    public static double[] FindToneOnsets(
        string rawPcmPath,
        int sampleRate,
        int frequency,
        int windowMilliseconds,
        double threshold)
    {
        if (string.IsNullOrWhiteSpace(rawPcmPath)) throw new ArgumentException("A PCM path is required.", "rawPcmPath");
        if (sampleRate <= 0 || frequency <= 0 || frequency >= sampleRate / 2) throw new ArgumentOutOfRangeException("frequency");
        if (windowMilliseconds <= 0 || 1000 % windowMilliseconds != 0) throw new ArgumentOutOfRangeException("windowMilliseconds");

        int samplesPerWindow = sampleRate * windowMilliseconds / 1000;
        double coefficient = 2.0 * Math.Cos(2.0 * Math.PI * frequency / sampleRate);
        double releaseThreshold = threshold * 0.5;
        List<double> onsets = new List<double>();
        using (BinaryReader reader = new BinaryReader(File.OpenRead(rawPcmPath)))
        {
            long frame = 0;
            bool active = false;
            while (reader.BaseStream.Position + samplesPerWindow * 2 <= reader.BaseStream.Length)
            {
                double previous = 0;
                double previousPrevious = 0;
                for (int sample = 0; sample < samplesPerWindow; sample++)
                {
                    double value = reader.ReadInt16();
                    double current = value + coefficient * previous - previousPrevious;
                    previousPrevious = previous;
                    previous = current;
                }

                double power = previous * previous + previousPrevious * previousPrevious - coefficient * previous * previousPrevious;
                double amplitude = 2.0 * Math.Sqrt(Math.Max(0, power)) / samplesPerWindow;
                if (!active && amplitude >= threshold)
                {
                    active = true;
                    onsets.Add(frame * windowMilliseconds / 1000.0);
                }
                else if (active && amplitude < releaseThreshold)
                {
                    active = false;
                }
                frame++;
            }
        }
        return onsets.ToArray();
    }
}
