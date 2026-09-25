using System;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace BoltSnip
{
    internal static class ReplayProcessSupport
    {
        internal static string FindFfmpeg()
        {
            string configured = Environment.GetEnvironmentVariable("BOLTSNIP_FFMPEG_PATH");
            if (!string.IsNullOrWhiteSpace(configured))
            {
                string configuredPath = Path.GetFullPath(configured.Trim().Trim('"'));
                if (File.Exists(configuredPath))
                {
                    return configuredPath;
                }
                throw new ReplayNotSupportedException(
                    "找不到 BOLTSNIP_FFMPEG_PATH 指定的 ffmpeg.exe：" + configuredPath);
            }

            string applicationPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ffmpeg.exe");
            if (File.Exists(applicationPath))
            {
                return applicationPath;
            }

            string pathValue = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
            string[] pathEntries = pathValue.Split(Path.PathSeparator);
            for (int index = 0; index < pathEntries.Length; index++)
            {
                string entry = pathEntries[index].Trim().Trim('"');
                if (entry.Length == 0)
                {
                    continue;
                }

                try
                {
                    string candidate = Path.Combine(entry, "ffmpeg.exe");
                    if (File.Exists(candidate))
                    {
                        return candidate;
                    }
                }
                catch
                {
                    // Ignore malformed PATH entries and continue searching.
                }
            }

            throw new ReplayNotSupportedException(
                "即时回放需要带 NVIDIA NVENC 支持的 FFmpeg。请将 ffmpeg.exe 放到 BoltSnip.exe 同目录、加入 PATH，或设置 BOLTSNIP_FFMPEG_PATH。");
        }

        internal static void EnsureNvencAvailable(string ffmpegPath)
        {
            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = ffmpegPath;
            startInfo.Arguments = "-hide_banner -encoders";
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            startInfo.RedirectStandardOutput = true;
            startInfo.RedirectStandardError = true;

            StringBuilder standardError = new StringBuilder();
            object encoderFoundLock = new object();
            bool encoderFound = false;
            using (Process process = new Process())
            {
                process.StartInfo = startInfo;
                process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs args)
                {
                    if (!string.IsNullOrEmpty(args.Data) &&
                        args.Data.IndexOf("h264_nvenc", StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        lock (encoderFoundLock)
                        {
                            encoderFound = true;
                        }
                    }
                };
                process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs args)
                {
                    if (string.IsNullOrEmpty(args.Data))
                    {
                        return;
                    }
                    lock (standardError)
                    {
                        if (standardError.Length < 4096)
                        {
                            standardError.AppendLine(args.Data);
                        }
                    }
                };

                try
                {
                    if (!process.Start())
                    {
                        throw new InvalidOperationException("FFmpeg did not start.");
                    }
                    process.BeginOutputReadLine();
                    process.BeginErrorReadLine();
                    if (!process.WaitForExit(7000))
                    {
                        try { process.Kill(); } catch { }
                        throw new ReplayNotSupportedException("检查 FFmpeg 编码器超时，请稍后重试。");
                    }
                    process.WaitForExit();
                }
                catch (ReplayNotSupportedException)
                {
                    throw;
                }
                catch (Exception exception)
                {
                    throw new ReplayNotSupportedException("无法运行 FFmpeg：" + exception.Message);
                }

                if (process.ExitCode != 0)
                {
                    throw new ReplayNotSupportedException(
                        "FFmpeg 无法检查编码器：" + ReadError(standardError));
                }
            }

            lock (encoderFoundLock)
            {
                if (!encoderFound)
                {
                    throw new ReplayNotSupportedException(
                        "当前 FFmpeg 没有 h264_nvenc 编码器。即时回放实验版暂不提供软件编码回退。");
                }
            }
        }

        internal static string QuoteArgument(string value)
        {
            if (value == null)
            {
                return "\"\"";
            }

            bool needsQuotes = value.Length == 0;
            for (int index = 0; index < value.Length && !needsQuotes; index++)
            {
                needsQuotes = char.IsWhiteSpace(value[index]) || value[index] == '"';
            }
            if (!needsQuotes)
            {
                return value;
            }

            StringBuilder quoted = new StringBuilder();
            quoted.Append('"');
            int backslashes = 0;
            for (int index = 0; index < value.Length; index++)
            {
                char character = value[index];
                if (character == '\\')
                {
                    backslashes++;
                    continue;
                }

                if (character == '"')
                {
                    quoted.Append('\\', backslashes * 2 + 1);
                    quoted.Append('"');
                    backslashes = 0;
                    continue;
                }

                if (backslashes > 0)
                {
                    quoted.Append('\\', backslashes);
                    backslashes = 0;
                }
                quoted.Append(character);
            }

            if (backslashes > 0)
            {
                quoted.Append('\\', backslashes * 2);
            }
            quoted.Append('"');
            return quoted.ToString();
        }

        internal static string ReadError(StringBuilder error)
        {
            lock (error)
            {
                string value = error.ToString().Trim();
                return value.Length == 0 ? "未知错误" : value;
            }
        }
    }

    internal sealed class ReplayNotSupportedException : Exception
    {
        internal ReplayNotSupportedException(string message)
            : base(message)
        {
        }
    }
}
