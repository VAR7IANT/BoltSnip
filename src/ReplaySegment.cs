using System;
using System.Globalization;
using System.IO;

namespace BoltSnip
{
    internal sealed class ReplaySegment
    {
        internal ReplaySegment(int index, string path, double durationSeconds)
        {
            if (index < 0)
            {
                throw new ArgumentOutOfRangeException("index");
            }
            if (string.IsNullOrWhiteSpace(path))
            {
                throw new ArgumentException("A segment path is required.", "path");
            }
            if (durationSeconds <= 0 || double.IsNaN(durationSeconds) || double.IsInfinity(durationSeconds))
            {
                throw new ArgumentOutOfRangeException("durationSeconds");
            }

            Index = index;
            Path = System.IO.Path.GetFullPath(path);
            DurationSeconds = durationSeconds;
        }

        internal int Index { get; private set; }
        internal string Path { get; private set; }
        internal double DurationSeconds { get; private set; }

        internal static bool TryParseIndex(string path, out int index)
        {
            index = -1;
            string name = System.IO.Path.GetFileNameWithoutExtension(path);
            const string prefix = "segment_";
            if (name == null || !name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            return int.TryParse(
                name.Substring(prefix.Length),
                NumberStyles.None,
                CultureInfo.InvariantCulture,
                out index);
        }
    }
}
