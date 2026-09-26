param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'obj\instant-replay-audio\bin\BoltSnip.exe'),
    [string]$Ffmpeg = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\ffmpeg.exe'),
    [string]$Ffprobe = (Join-Path (Split-Path $PSScriptRoot -Parent) '.tools\ffmpeg\ffprobe.exe'),
    [string]$AlternateEndpointId = '',
    [string]$EvidenceDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) '.tools\instant-replay-audio-evidence')
)

$ErrorActionPreference = 'Stop'
foreach ($path in @($Executable, $Ffmpeg, $Ffprobe)) {
    if (-not [IO.File]::Exists($path)) { throw "Required file was not found: $path" }
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace BoltSnipAudioDeviceTest
{
    public enum DataFlow { Render = 0, Capture = 1, All = 2 }
    public enum Role { Console = 0, Multimedia = 1, Communications = 2 }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(DataFlow flow, uint stateMask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(DataFlow flow, Role role, out IDevice device);
        [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IDevice device);
        [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr callback);
        [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr callback);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IDevice
    {
        [PreserveSig] int Activate(ref Guid iid, uint context, IntPtr parameters, [MarshalAs(UnmanagedType.IUnknown)] out object value);
        [PreserveSig] int OpenPropertyStore(uint access, out IntPtr properties);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetState(out uint state);
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class DeviceEnumeratorClass { }

    [ComImport, Guid("F8679F50-850A-41CF-9C72-430F290290C8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPolicyConfig
    {
        [PreserveSig] int GetMixFormat([MarshalAs(UnmanagedType.LPWStr)] string id, out IntPtr format);
        [PreserveSig] int GetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id, int defaultFormat, out IntPtr format);
        [PreserveSig] int ResetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id);
        [PreserveSig] int SetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr format, IntPtr mixFormat);
        [PreserveSig] int GetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string id, out long defaultPeriod, out long minimumPeriod);
        [PreserveSig] int SetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr period);
        [PreserveSig] int GetShareMode([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr mode);
        [PreserveSig] int SetShareMode([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr mode);
        [PreserveSig] int GetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr key, IntPtr value);
        [PreserveSig] int SetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr key, IntPtr value);
        [PreserveSig] int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string id, Role role);
        [PreserveSig] int SetEndpointVisibility([MarshalAs(UnmanagedType.LPWStr)] string id, int visible);
    }

    [ComImport, Guid("870AF99C-171D-4F9E-AF0D-E63DF40C2BC9")]
    internal class PolicyConfigClient { }

    public static class DevicePolicy
    {
        public static string GetDefaultEndpointId(int role)
        {
            Type enumeratorType = Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"));
            IDeviceEnumerator enumerator = (IDeviceEnumerator)Activator.CreateInstance(enumeratorType);
            IDevice device = null;
            try
            {
                Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(DataFlow.Render, (Role)role, out device));
                string id;
                Marshal.ThrowExceptionForHR(device.GetId(out id));
                return id;
            }
            finally
            {
                if (device != null && Marshal.IsComObject(device)) Marshal.ReleaseComObject(device);
                if (enumerator != null && Marshal.IsComObject(enumerator)) Marshal.ReleaseComObject(enumerator);
            }
        }

        public static void SetDefaultEndpoint(string id, int role)
        {
            Type policyType = Type.GetTypeFromCLSID(new Guid("870AF99C-171D-4F9E-AF0D-E63DF40C2BC9"));
            IPolicyConfig policy = (IPolicyConfig)Activator.CreateInstance(policyType);
            try { Marshal.ThrowExceptionForHR(policy.SetDefaultEndpoint(id, (Role)role)); }
            finally { if (policy != null && Marshal.IsComObject(policy)) Marshal.ReleaseComObject(policy); }
        }
    }
}
'@

if ([string]::IsNullOrWhiteSpace($AlternateEndpointId)) {
    $renderRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
    $friendlyNameKey = '{b3f8fa53-0004-438e-9003-51a46e139bfc},6'
    $alternate = Get-ChildItem -LiteralPath $renderRoot | Where-Object {
        $state = (Get-ItemProperty -LiteralPath $_.PSPath -Name DeviceState -ErrorAction SilentlyContinue).DeviceState
        $state -band 1
    } | ForEach-Object {
        $properties = Get-ItemProperty -LiteralPath (Join-Path $_.PSPath 'Properties') -ErrorAction SilentlyContinue
        $nameProperty = $properties.PSObject.Properties | Where-Object Name -eq $friendlyNameKey | Select-Object -First 1
        if ($null -ne $nameProperty) {
            [pscustomobject]@{ Id = '{0.0.0.00000000}.' + $_.PSChildName; Name = [string]$nameProperty.Value }
        }
    } | Where-Object { $_.Name -match 'Realtek' } | Select-Object -First 1
    if ($null -eq $alternate) { throw 'No active Realtek alternate render endpoint was found.' }
    $AlternateEndpointId = $alternate.Id
    $alternateName = $alternate.Name
}
else { $alternateName = 'Caller-supplied endpoint' }

$originalEndpointIds = @()
for ($role = 0; $role -lt 3; $role++) {
    $originalEndpointIds += [BoltSnipAudioDeviceTest.DevicePolicy]::GetDefaultEndpointId($role)
}
if (@($originalEndpointIds | Where-Object { $_ -eq $AlternateEndpointId }).Count -gt 0) {
    throw 'The alternate endpoint is already the default for one or more roles.'
}

$runId = 'DeviceChange-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$runDirectory = Join-Path $EvidenceDirectory $runId
[IO.Directory]::CreateDirectory($runDirectory) | Out-Null
Set-Content -LiteralPath (Join-Path $runDirectory 'default-endpoints-before.txt') -Value ($originalEndpointIds -join [Environment]::NewLine) -Encoding UTF8
$diagnosticPath = Join-Path $runDirectory 'diagnostic.log'
$oldFfmpegPath = [Environment]::GetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', 'Process')
$oldDiagnosticPath = [Environment]::GetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', 'Process')
$oldReplayOutputDirectory = [Environment]::GetEnvironmentVariable('BOLTSNIP_REPLAY_OUTPUT_DIRECTORY', 'Process')
[Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $Ffmpeg, 'Process')
[Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $diagnosticPath, 'Process')
[Environment]::SetEnvironmentVariable('BOLTSNIP_REPLAY_OUTPUT_DIRECTORY', $runDirectory, 'Process')

$manager = $null
$soundPlayer = $null
$restored = $false
$savePath = $null
$switchTime = $null
$managerStateAtSave = $null
$audioStateAtSave = $null
$dispose = $null
$policyChanged = $false
try {
    $wavePath = Join-Path $runDirectory 'device-change-tone.wav'
    $sampleRate = 48000
    $sampleCount = $sampleRate
    $writer = New-Object IO.BinaryWriter([IO.File]::Create($wavePath))
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
        $writer.Write([int]($sampleCount * 2 + 36))
        $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
        $writer.Write([int]16)
        $writer.Write([int16]1)
        $writer.Write([int16]1)
        $writer.Write([int]$sampleRate)
        $writer.Write([int]($sampleRate * 2))
        $writer.Write([int16]2)
        $writer.Write([int16]16)
        $writer.Write([Text.Encoding]::ASCII.GetBytes('data'))
        $writer.Write([int]($sampleCount * 2))
        for ($sample = 0; $sample -lt $sampleCount; $sample++) {
            $value = [int][Math]::Round(4096 * [Math]::Sin(2 * [Math]::PI * 880 * $sample / $sampleRate))
            $writer.Write([int16]$value)
        }
    }
    finally { $writer.Dispose() }

    $soundPlayer = New-Object System.Media.SoundPlayer($wavePath)
    $soundPlayer.Load()
    $soundPlayer.PlayLooping()

    $assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
    $managerType = $assembly.GetType('BoltSnip.ReplayManager', $true)
    $flags = [Reflection.BindingFlags]'Instance,Static,NonPublic'
    $manager = [Activator]::CreateInstance($managerType, $true)
    $start = $managerType.GetMethod('Start', $flags)
    $dispose = $managerType.GetMethod('Dispose', [Reflection.BindingFlags]'Instance,Public')
    $state = $managerType.GetProperty('State', $flags)
    $audioState = $managerType.GetProperty('AudioState', $flags)
    $save = $managerType.GetMethod('SaveReplay', $flags)
    $isSaving = $managerType.GetProperty('IsSaving', $flags)
    [void]$start.Invoke($manager, $null)
    $startupDeadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $startupDeadline -and $state.GetValue($manager, $null).ToString() -notin @('Recording', 'Error')) {
        Start-Sleep -Milliseconds 50
    }
    if ($state.GetValue($manager, $null).ToString() -ne 'Recording') { throw 'Replay failed to start before the endpoint change test.' }

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $switchRequested = $false
    $saveRequested = $false
    while ($watch.Elapsed.TotalSeconds -lt 26) {
        if (-not $switchRequested -and $watch.Elapsed.TotalSeconds -ge 12) {
            $switchRequested = $true
            $policyChanged = $true
            for ($role = 0; $role -lt 3; $role++) {
                [BoltSnipAudioDeviceTest.DevicePolicy]::SetDefaultEndpoint($AlternateEndpointId, $role)
            }
            $switchTime = [Math]::Round($watch.Elapsed.TotalSeconds, 1)
            $soundPlayer.Stop()
            Start-Sleep -Milliseconds 100
            $soundPlayer.PlayLooping()
            [IO.File]::WriteAllText((Join-Path $runDirectory 'endpoint-change.txt'),
                ('Switched all default render roles at {0}s to {1} ({2})' -f $switchTime, $alternateName, $AlternateEndpointId))
        }

        if (-not $saveRequested -and $watch.Elapsed.TotalSeconds -ge 23 -and -not [bool]$isSaving.GetValue($manager, $null)) {
            if (-not [bool]$save.Invoke($manager, $null)) { throw 'Replay save was rejected after the output-device change.' }
            $saveRequested = $true
        }

        if ($state.GetValue($manager, $null).ToString() -ne 'Recording') {
            throw "Replay stopped after the output-device change: $([string]$managerType.GetProperty('LastError', $flags).GetValue($manager, $null))"
        }
        Start-Sleep -Milliseconds 50
    }

    if (-not $saveRequested) { throw 'The post-change Replay save was not requested.' }
    $saveDeadline = [DateTime]::UtcNow.AddSeconds(45)
    while ([DateTime]::UtcNow -lt $saveDeadline -and [bool]$isSaving.GetValue($manager, $null)) {
        Start-Sleep -Milliseconds 100
    }
    if ([bool]$isSaving.GetValue($manager, $null)) { throw 'Timed out waiting for the post-change Replay save.' }
    $managerStateAtSave = $state.GetValue($manager, $null).ToString()
    $audioStateAtSave = $audioState.GetValue($manager, $null).ToString()
    if ($managerStateAtSave -ne 'Recording') { throw 'Replay was no longer recording after the post-change save.' }
    $diagnosticText = [IO.File]::ReadAllText($diagnosticPath)
    $endpointChangeDetected = $diagnosticText.Contains('The default render endpoint changed')

    foreach ($line in [IO.File]::ReadAllLines($diagnosticPath)) {
        if ($line -match 'Replay saved: (.+); duration=') { $savePath = $Matches[1] }
    }
    if (-not $savePath -or -not [IO.File]::Exists($savePath)) { throw 'The post-change Replay output was not found.' }
    $destination = Join-Path $runDirectory 'DeviceChange-save-01.mp4'
    Move-Item -LiteralPath $savePath -Destination $destination -Force
    $savePath = $destination

    $watch.Stop()
    $soundPlayer.Stop()
    for ($role = 0; $role -lt 3; $role++) {
        [BoltSnipAudioDeviceTest.DevicePolicy]::SetDefaultEndpoint($originalEndpointIds[$role], $role)
    }
    $restoredEndpointIds = @()
    for ($role = 0; $role -lt 3; $role++) {
        $restoredEndpointIds += [BoltSnipAudioDeviceTest.DevicePolicy]::GetDefaultEndpointId($role)
    }
    $restored = $restoredEndpointIds.Count -eq $originalEndpointIds.Count
    for ($role = 0; $role -lt $originalEndpointIds.Count; $role++) {
        if ($restoredEndpointIds[$role] -ne $originalEndpointIds[$role]) { $restored = $false }
    }
    Set-Content -LiteralPath (Join-Path $runDirectory 'default-endpoints-after.txt') -Value ($restoredEndpointIds -join [Environment]::NewLine) -Encoding UTF8
    if (-not $restored) { throw 'The original default render endpoints were not restored.' }
    $policyChanged = $false
    [void]$dispose.Invoke($manager, $null)

    $probeInfo = New-Object Diagnostics.ProcessStartInfo
    $probeInfo.FileName = $Ffprobe
    $probeInfo.Arguments = '-v error -show_entries stream=codec_type,codec_name,sample_rate,channels,duration -show_entries format=duration -of json "' + $savePath + '"'
    $probeInfo.UseShellExecute = $false
    $probeInfo.CreateNoWindow = $true
    $probeInfo.RedirectStandardOutput = $true
    $probeInfo.RedirectStandardError = $true
    $probeProcess = [Diagnostics.Process]::Start($probeInfo)
    $probeOutput = $probeProcess.StandardOutput.ReadToEnd()
    $probeError = $probeProcess.StandardError.ReadToEnd()
    $probeProcess.WaitForExit()
    if ($probeProcess.ExitCode -ne 0) { throw "ffprobe failed: $probeError" }
    $probe = $probeOutput | ConvertFrom-Json
    $video = @($probe.streams | Where-Object codec_type -eq 'video' | Select-Object -First 1)[0]
    $audio = @($probe.streams | Where-Object codec_type -eq 'audio' | Select-Object -First 1)[0]

    $decodeInfo = New-Object Diagnostics.ProcessStartInfo
    $decodeInfo.FileName = $Ffmpeg
    $decodeInfo.Arguments = '-hide_banner -v error -i "' + $savePath + '" -f null NUL'
    $decodeInfo.UseShellExecute = $false
    $decodeInfo.CreateNoWindow = $true
    $decodeInfo.RedirectStandardError = $true
    $decodeProcess = [Diagnostics.Process]::Start($decodeInfo)
    $decodeError = $decodeProcess.StandardError.ReadToEnd()
    $decodeProcess.WaitForExit()
    $decodeExitCode = $decodeProcess.ExitCode

    $report = [pscustomobject]@{
        AlternateEndpointName = $alternateName
        AlternateEndpointId = $AlternateEndpointId
        OriginalEndpointIds = $originalEndpointIds
        SwitchAtSeconds = $switchTime
        RequestedDurationSeconds = 26
        ManagerStateAtSave = $managerStateAtSave
        AudioStateAtSave = $audioStateAtSave
        EndpointChangeDetected = $endpointChangeDetected
        AudioChangeBehavior = if ($endpointChangeDetected -and $audioStateAtSave -eq 'Unavailable') { 'Silence until Replay is restarted after output-device change' } else { 'Unexpected state; inspect diagnostics' }
        DefaultsRestored = $restored
        ReplayPath = $savePath
        VideoCodec = if ($null -ne $video) { $video.codec_name } else { $null }
        AudioCodec = if ($null -ne $audio) { $audio.codec_name } else { $null }
        AudioSampleRate = if ($null -ne $audio) { $audio.sample_rate } else { $null }
        AudioChannels = if ($null -ne $audio) { $audio.channels } else { $null }
        VideoDuration = if ($null -ne $video.duration) { [double]$video.duration } else { $null }
        AudioDuration = if ($null -ne $audio.duration) { [double]$audio.duration } else { $null }
        FormatDuration = [double]$probe.format.duration
        DecodeExitCode = $decodeExitCode
        DecodeError = $decodeError.Trim()
        DiagnosticLog = $diagnosticPath
    }
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDirectory 'result.json') -Encoding UTF8
    $report | Format-List
    if ($null -eq $video -or $video.codec_name -ne 'h264') { throw 'Post-change replay video was not H.264.' }
    if ($null -eq $audio -or $audio.codec_name -ne 'aac') { throw 'Post-change replay AAC stream is missing.' }
    if ($decodeExitCode -ne 0) { throw 'Post-change replay failed full decode.' }
    if (-not $endpointChangeDetected -or $audioStateAtSave -ne 'Unavailable') { throw 'The default endpoint change did not switch audio capture into its silence fallback.' }
    if (-not $restored) { throw 'The original default render endpoints were not restored.' }
}
catch {
    $_ | Format-List * -Force | Out-String | Set-Content -LiteralPath (Join-Path $runDirectory 'failure.txt') -Encoding UTF8
    throw
}
finally {
    if ($null -ne $soundPlayer) { try { $soundPlayer.Stop(); $soundPlayer.Dispose() } catch { } }
    if ($policyChanged) {
        for ($role = 0; $role -lt $originalEndpointIds.Count; $role++) {
            try { [BoltSnipAudioDeviceTest.DevicePolicy]::SetDefaultEndpoint($originalEndpointIds[$role], $role) } catch { }
        }
    }
    if ($originalEndpointIds.Count -eq 3) {
        try {
            $observedEndpointIds = @()
            for ($role = 0; $role -lt 3; $role++) {
                $observedEndpointIds += [BoltSnipAudioDeviceTest.DevicePolicy]::GetDefaultEndpointId($role)
            }
            Set-Content -LiteralPath (Join-Path $runDirectory 'default-endpoints-after.txt') -Value ($observedEndpointIds -join [Environment]::NewLine) -Encoding UTF8
        }
        catch { $_ | Out-String | Set-Content -LiteralPath (Join-Path $runDirectory 'endpoint-restore-error.txt') -Encoding UTF8 }
    }
    if ($null -ne $manager -and $null -ne $dispose) { try { [void]$dispose.Invoke($manager, $null) } catch { } }
    if ($oldFfmpegPath) { [Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $oldFfmpegPath, 'Process') }
    else { [Environment]::SetEnvironmentVariable('BOLTSNIP_FFMPEG_PATH', $null, 'Process') }
    if ($oldDiagnosticPath) { [Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $oldDiagnosticPath, 'Process') }
    else { [Environment]::SetEnvironmentVariable('BOLTSNIP_DIAGNOSTIC_LOG_PATH', $null, 'Process') }
    if ($oldReplayOutputDirectory) { [Environment]::SetEnvironmentVariable('BOLTSNIP_REPLAY_OUTPUT_DIRECTORY', $oldReplayOutputDirectory, 'Process') }
    else { [Environment]::SetEnvironmentVariable('BOLTSNIP_REPLAY_OUTPUT_DIRECTORY', $null, 'Process') }
}
