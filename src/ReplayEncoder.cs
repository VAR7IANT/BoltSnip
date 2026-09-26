using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;

namespace BoltSnip
{
    internal sealed class ReplayEncoder : IDisposable
    {
        private readonly object _syncRoot = new object();
        private readonly Queue<string> _recentErrors = new Queue<string>();
        private Process _process;
        private string _ffmpegPath;
        private string _segmentListPath;
        private bool _disposed;

        internal string FfmpegPath
        {
            get { lock (_syncRoot) { return _ffmpegPath; } }
        }

        internal string SegmentListPath
        {
            get { lock (_syncRoot) { return _segmentListPath; } }
        }

        internal bool HasExited
        {
            get
            {
                lock (_syncRoot)
                {
                    return _process == null || SafeHasExited(_process);
                }
            }
        }

        internal string RecentError
        {
            get
            {
                lock (_syncRoot)
                {
                    return string.Join(Environment.NewLine, _recentErrors.ToArray());
                }
            }
        }

        internal void Start(
            string cacheDirectory,
            ReplaySettings settings,
            ReplayCaptureSession captureSession,
            ReplayAudioCaptureSession audioSession)
        {
            if (settings == null)
            {
                throw new ArgumentNullException("settings");
            }
            if (captureSession == null)
            {
                throw new ArgumentNullException("captureSession");
            }

            lock (_syncRoot)
            {
                if (_disposed)
                {
                    throw new ObjectDisposedException("ReplayEncoder");
                }
                if (_process != null)
                {
                    throw new InvalidOperationException("The replay encoder has already been started.");
                }
            }

            string ffmpegPath = ReplayProcessSupport.FindFfmpeg();
            ReplayProcessSupport.EnsureNvencAvailable(ffmpegPath);

            string videoInputArguments = captureSession.BuildInputArguments(settings);
            string audioInputArguments = audioSession == null
                ? null
                : ReplayAudioCaptureSession.BuildInputArguments(audioSession.Format, audioSession.PipeArgument);
            Directory.CreateDirectory(cacheDirectory);
            string listPath = Path.Combine(cacheDirectory, "segments.csv");
            string outputPattern = Path.Combine(cacheDirectory, "segment_%08d.mp4");
            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = ffmpegPath;
            startInfo.Arguments = BuildArguments(
                listPath,
                outputPattern,
                videoInputArguments,
                audioInputArguments,
                audioSession == null ? null : audioSession.Format,
                settings);
            ReplayDiagnostics.Write("FFmpeg encoder command: " + startInfo.Arguments);
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            startInfo.RedirectStandardError = true;

            Process process = new Process();
            process.StartInfo = startInfo;
            process.ErrorDataReceived += ProcessErrorDataReceived;

            try
            {
                if (!process.Start())
                {
                    throw new InvalidOperationException("FFmpeg did not start.");
                }
                process.BeginErrorReadLine();
            }
            catch
            {
                process.Dispose();
                throw;
            }

            lock (_syncRoot)
            {
                if (_disposed)
                {
                    try { process.Kill(); } catch { }
                    process.Dispose();
                    throw new ObjectDisposedException("ReplayEncoder");
                }
                _ffmpegPath = ffmpegPath;
                _segmentListPath = listPath;
                _process = process;
            }

            ReplayDiagnostics.Write(
                "Encoder started: NVENC H.264; resolution=" + captureSession.Bounds.Width + "x" + captureSession.Bounds.Height +
                "; fps=" + settings.target_fps.ToString(CultureInfo.InvariantCulture));
            if (audioSession != null)
            {
                ReplayDiagnostics.Write("AAC output enabled");
            }
        }

        internal IList<ReplaySegment> ReadCompletedSegments(int defaultSegmentSeconds)
        {
            string path = SegmentListPath;
            if (string.IsNullOrEmpty(path) || !File.Exists(path))
            {
                return new List<ReplaySegment>();
            }

            string[] lines;
            try
            {
                lines = File.ReadAllLines(path, Encoding.UTF8);
            }
            catch (IOException)
            {
                return new List<ReplaySegment>();
            }
            catch (UnauthorizedAccessException)
            {
                return new List<ReplaySegment>();
            }

            List<ReplaySegment> segments = new List<ReplaySegment>();
            string directory = Path.GetDirectoryName(path);
            for (int index = 0; index < lines.Length; index++)
            {
                string[] fields = ParseCsvLine(lines[index]);
                if (fields.Length < 3 || string.IsNullOrWhiteSpace(fields[0]))
                {
                    continue;
                }

                string segmentPath = Path.IsPathRooted(fields[0])
                    ? fields[0]
                    : Path.Combine(directory, fields[0]);
                int segmentIndex;
                if (!ReplaySegment.TryParseIndex(segmentPath, out segmentIndex))
                {
                    continue;
                }

                double start;
                double end;
                double duration = defaultSegmentSeconds;
                if (double.TryParse(fields[1], NumberStyles.Float, CultureInfo.InvariantCulture, out start) &&
                    double.TryParse(fields[2], NumberStyles.Float, CultureInfo.InvariantCulture, out end) &&
                    end > start)
                {
                    duration = end - start;
                }

                try
                {
                    segments.Add(new ReplaySegment(segmentIndex, segmentPath, duration));
                }
                catch (ArgumentException)
                {
                    // Ignore an incomplete or malformed line and retry on the next poll.
                }
            }

            segments.Sort(delegate(ReplaySegment left, ReplaySegment right)
            {
                return left.Index.CompareTo(right.Index);
            });
            return segments;
        }

        internal void Stop()
        {
            Process process;
            lock (_syncRoot)
            {
                process = _process;
                _process = null;
            }

            if (process == null)
            {
                return;
            }

            try
            {
                if (!SafeHasExited(process))
                {
                    process.Kill();
                    process.WaitForExit(3000);
                }
            }
            catch (Exception exception)
            {
                ReplayDiagnostics.Write("Encoder stop failed: " + exception.Message);
            }
            finally
            {
                process.Dispose();
            }

            ReplayDiagnostics.Write("Encoder stopped");
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
            }
            Stop();
        }

        internal static string BuildArguments(
            string listPath,
            string outputPattern,
            string videoInputArguments,
            string audioInputArguments,
            ReplayAudioFormat audioFormat,
            ReplaySettings settings)
        {
            int gop = settings.target_fps * settings.segment_duration_seconds;
            StringBuilder arguments = new StringBuilder();
            arguments.Append("-hide_banner -loglevel warning -nostats -y ");
            bool includeAudio = audioFormat != null && !string.IsNullOrWhiteSpace(audioInputArguments);
            arguments.Append(videoInputArguments);
            if (includeAudio)
            {
                arguments.Append(audioInputArguments);
                arguments.Append("-map 0:v:0 -map 1:a:0 ");
            }
            else
            {
                arguments.Append("-an ");
            }
            arguments.Append("-c:v h264_nvenc -preset p4 -tune ll -rc vbr -cq 23 -b:v 0 ");
            if (includeAudio)
            {
                arguments.Append("-c:a aac -b:a 192k -ar 48000 -ac 2 ");
            }
            arguments.Append("-g ").Append(gop).Append(" -forced-idr 1 ");
            arguments.Append("-force_key_frames ").Append(ReplayProcessSupport.QuoteArgument(
                "expr:gte(t,n_forced*" + settings.segment_duration_seconds.ToString(CultureInfo.InvariantCulture) + ")")).Append(' ');
            arguments.Append("-f segment -segment_time ").Append(settings.segment_duration_seconds).Append(' ');
            arguments.Append("-segment_time_delta 0.05 -reset_timestamps 1 ");
            arguments.Append("-segment_list ").Append(ReplayProcessSupport.QuoteArgument(listPath)).Append(' ');
            arguments.Append("-segment_list_type csv -segment_list_size ")
                .Append(settings.segment_list_size)
                .Append(" -segment_list_flags +live ");
            arguments.Append("-segment_format mp4 -segment_format_options movflags=+faststart ");
            arguments.Append(ReplayProcessSupport.QuoteArgument(outputPattern));
            return arguments.ToString();
        }

        private void ProcessErrorDataReceived(object sender, DataReceivedEventArgs args)
        {
            if (string.IsNullOrWhiteSpace(args.Data))
            {
                return;
            }

            lock (_syncRoot)
            {
                if (_recentErrors.Count >= 32)
                {
                    _recentErrors.Dequeue();
                }
                _recentErrors.Enqueue(args.Data);
            }
        }

        private static string[] ParseCsvLine(string line)
        {
            List<string> fields = new List<string>();
            StringBuilder field = new StringBuilder();
            bool quoted = false;
            for (int index = 0; index < line.Length; index++)
            {
                char character = line[index];
                if (character == '"')
                {
                    if (quoted && index + 1 < line.Length && line[index + 1] == '"')
                    {
                        field.Append('"');
                        index++;
                    }
                    else
                    {
                        quoted = !quoted;
                    }
                }
                else if (character == ',' && !quoted)
                {
                    fields.Add(field.ToString());
                    field.Length = 0;
                }
                else
                {
                    field.Append(character);
                }
            }
            fields.Add(field.ToString());
            return fields.ToArray();
        }

        private static bool SafeHasExited(Process process)
        {
            try
            {
                return process.HasExited;
            }
            catch
            {
                return true;
            }
        }
    }
}
