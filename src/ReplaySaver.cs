using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;

namespace BoltSnip
{
    internal sealed class ReplaySaver : IDisposable
    {
        private readonly object _syncRoot = new object();
        private Process _process;
        private bool _cancelled;

        internal ReplaySaveResult Save(string ffmpegPath, ReplayBufferSnapshot snapshot)
        {
            if (string.IsNullOrWhiteSpace(ffmpegPath))
            {
                throw new ArgumentException("An FFmpeg path is required.", "ffmpegPath");
            }
            if (snapshot == null)
            {
                throw new ArgumentNullException("snapshot");
            }
            if (snapshot.Segments.Length == 0)
            {
                throw new InvalidOperationException("没有可保存的完整录像片段。");
            }

            Stopwatch stopwatch = Stopwatch.StartNew();
            string outputDirectoryOverride = Environment.GetEnvironmentVariable("BOLTSNIP_REPLAY_OUTPUT_DIRECTORY");
            string videosDirectory = string.IsNullOrWhiteSpace(outputDirectoryOverride)
                ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyVideos), "BoltSnip")
                : Path.GetFullPath(outputDirectoryOverride);
            Directory.CreateDirectory(videosDirectory);

            DateTime timestamp = DateTime.Now;
            string outputPath = BuildUniqueOutputPath(videosDirectory, timestamp);
            string temporaryOutputPath = outputPath + ".partial.mp4";
            string manifestPath = Path.Combine(
                Path.GetTempPath(),
                "BoltSnip-Replay-" + Guid.NewGuid().ToString("N") + ".ffconcat");

            try
            {
                WriteManifest(manifestPath, snapshot.Segments);
                ProcessStartInfo startInfo = new ProcessStartInfo();
                startInfo.FileName = ffmpegPath;
                startInfo.Arguments = BuildArguments(manifestPath, temporaryOutputPath);
                ReplayDiagnostics.Write("FFmpeg replay save command: " + startInfo.Arguments);
                startInfo.UseShellExecute = false;
                startInfo.CreateNoWindow = true;
                startInfo.RedirectStandardError = true;

                StringBuilder standardError = new StringBuilder();
                Process process = new Process();
                process.StartInfo = startInfo;
                process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs args)
                {
                    if (!string.IsNullOrWhiteSpace(args.Data))
                    {
                        lock (standardError)
                        {
                            if (standardError.Length < 8192)
                            {
                                standardError.AppendLine(args.Data);
                            }
                        }
                    }
                };

                lock (_syncRoot)
                {
                    if (_cancelled)
                    {
                        process.Dispose();
                        throw new OperationCanceledException("即时回放保存已取消。");
                    }
                    _process = process;
                }

                try
                {
                    if (!process.Start())
                    {
                        throw new InvalidOperationException("FFmpeg did not start.");
                    }
                    process.BeginErrorReadLine();
                    lock (_syncRoot)
                    {
                        if (_cancelled)
                        {
                            try { process.Kill(); } catch { }
                        }
                    }

                    while (!process.WaitForExit(100))
                    {
                        lock (_syncRoot)
                        {
                            if (_cancelled)
                            {
                                try { process.Kill(); } catch { }
                                throw new OperationCanceledException("即时回放保存已取消。");
                            }
                        }
                    }
                    process.WaitForExit();

                    if (process.ExitCode != 0)
                    {
                        throw new InvalidOperationException(
                            "FFmpeg 合并片段失败：" + ReplayProcessSupport.ReadError(standardError));
                    }
                    if (!File.Exists(temporaryOutputPath) || new FileInfo(temporaryOutputPath).Length == 0)
                    {
                        throw new InvalidOperationException("FFmpeg 没有生成 MP4 文件。");
                    }

                    File.Move(temporaryOutputPath, outputPath);
                }
                finally
                {
                    lock (_syncRoot)
                    {
                        if (ReferenceEquals(_process, process))
                        {
                            _process = null;
                        }
                    }
                    process.Dispose();
                }

                stopwatch.Stop();
                return new ReplaySaveResult(outputPath, snapshot.DurationSeconds, stopwatch.Elapsed);
            }
            finally
            {
                TryDeleteFile(manifestPath);
                TryDeleteFile(temporaryOutputPath);
            }
        }

        internal void Cancel()
        {
            Process process;
            lock (_syncRoot)
            {
                _cancelled = true;
                process = _process;
            }

            if (process != null)
            {
                try
                {
                    if (!process.HasExited)
                    {
                        process.Kill();
                    }
                }
                catch
                {
                    // The process may have exited between HasExited and Kill.
                }
            }
        }

        public void Dispose()
        {
            Cancel();
        }

        internal static string BuildUniqueOutputPath(string directory, DateTime timestamp)
        {
            string baseName = "BoltSnip-Replay-" + timestamp.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);
            string candidate = Path.Combine(directory, baseName + ".mp4");
            int suffix = 2;
            while (File.Exists(candidate) || File.Exists(candidate + ".partial.mp4"))
            {
                candidate = Path.Combine(
                    directory,
                    baseName + "-" + suffix.ToString(CultureInfo.InvariantCulture) + ".mp4");
                suffix++;
            }
            return candidate;
        }

        internal static string BuildArguments(string manifestPath, string outputPath)
        {
            return "-hide_banner -loglevel error -nostats -y -f concat -safe 0 -i " +
                ReplayProcessSupport.QuoteArgument(manifestPath) +
                " -map 0:v:0 -map 0:a:0? -c:v copy -c:a copy -movflags +faststart -f mp4 " +
                ReplayProcessSupport.QuoteArgument(outputPath);
        }

        internal static string BuildManifestText(ReplaySegment[] segments)
        {
            if (segments == null)
            {
                throw new ArgumentNullException("segments");
            }

            StringBuilder contents = new StringBuilder();
            contents.AppendLine("ffconcat version 1.0");
            for (int index = 0; index < segments.Length; index++)
            {
                ReplaySegment segment = segments[index];
                contents.Append("file '")
                    .Append(EscapeConcatPath(segment.Path))
                    .AppendLine("'");
                contents.Append("duration ")
                    .Append(segment.DurationSeconds.ToString("0.#################", CultureInfo.InvariantCulture))
                    .AppendLine();
            }
            return contents.ToString();
        }

        private static void WriteManifest(string path, ReplaySegment[] segments)
        {
            File.WriteAllText(path, BuildManifestText(segments), new UTF8Encoding(false));
        }

        private static string EscapeConcatPath(string path)
        {
            return path.Replace("'", "'\\''");
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
                ReplayDiagnostics.Write("Save temporary cleanup failed: " + exception.Message);
            }
        }
    }

    internal sealed class ReplaySaveResult
    {
        internal ReplaySaveResult(string path, double durationSeconds, TimeSpan elapsed)
        {
            Path = path;
            DurationSeconds = durationSeconds;
            Elapsed = elapsed;
        }

        internal string Path { get; private set; }
        internal double DurationSeconds { get; private set; }
        internal TimeSpan Elapsed { get; private set; }
    }
}
