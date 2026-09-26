using System;
using System.Runtime.InteropServices;

namespace BoltSnip
{
    internal enum AudioDataFlow
    {
        Render = 0,
        Capture = 1,
        All = 2
    }

    internal enum AudioRole
    {
        Console = 0,
        Multimedia = 1,
        Communications = 2
    }

    internal enum AudioShareMode
    {
        Shared = 0,
        Exclusive = 1
    }

    [Flags]
    internal enum AudioClientStreamFlags : uint
    {
        Loopback = 0x00020000
    }

    [ComImport]
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator
    {
        [PreserveSig]
        int EnumAudioEndpoints(AudioDataFlow dataFlow, uint stateMask, out IMMDeviceCollection devices);

        [PreserveSig]
        int GetDefaultAudioEndpoint(AudioDataFlow dataFlow, AudioRole role, out IMMDevice device);

        [PreserveSig]
        int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string deviceId, out IMMDevice device);

        [PreserveSig]
        int RegisterEndpointNotificationCallback(IntPtr client);

        [PreserveSig]
        int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport]
    [Guid("0BD7A1BE-7A1A-44DB-8397-C0A6B1B43E0B")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceCollection
    {
        [PreserveSig]
        int GetCount(out uint count);

        [PreserveSig]
        int Item(uint index, out IMMDevice device);
    }

    [ComImport]
    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice
    {
        [PreserveSig]
        int Activate(ref Guid interfaceId, uint classContext, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object activatedInterface);

        [PreserveSig]
        int OpenPropertyStore(uint access, out IntPtr properties);

        [PreserveSig]
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string deviceId);

        [PreserveSig]
        int GetState(out uint state);
    }

    [ComImport]
    [Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioClient
    {
        [PreserveSig]
        int Initialize(AudioShareMode shareMode, AudioClientStreamFlags streamFlags, long bufferDuration, long periodicity, IntPtr format, IntPtr audioSessionGuid);

        [PreserveSig]
        int GetBufferSize(out uint bufferSize);

        [PreserveSig]
        int GetStreamLatency(out long latency);

        [PreserveSig]
        int GetCurrentPadding(out uint currentPadding);

        [PreserveSig]
        int IsFormatSupported(AudioShareMode shareMode, IntPtr format, out IntPtr closestMatch);

        [PreserveSig]
        int GetMixFormat(out IntPtr format);

        [PreserveSig]
        int GetDevicePeriod(out long defaultPeriod, out long minimumPeriod);

        [PreserveSig]
        int Start();

        [PreserveSig]
        int Stop();

        [PreserveSig]
        int Reset();

        [PreserveSig]
        int SetEventHandle(IntPtr eventHandle);

        [PreserveSig]
        int GetService(ref Guid interfaceId, [MarshalAs(UnmanagedType.IUnknown)] out object service);
    }

    [ComImport]
    [Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioCaptureClient
    {
        [PreserveSig]
        int GetBuffer(out IntPtr data, out uint framesToRead, out uint flags, out ulong devicePosition, out ulong qpcPosition);

        [PreserveSig]
        int ReleaseBuffer(uint framesRead);

        [PreserveSig]
        int GetNextPacketSize(out uint framesInNextPacket);
    }

    internal static class WasapiInterop
    {
        internal static readonly Guid AudioClientClassId = new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E");
        internal static readonly Guid AudioClientInterfaceId = new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2");
        internal static readonly Guid AudioCaptureClientInterfaceId = new Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317");

        [DllImport("ole32.dll", ExactSpelling = true)]
        internal static extern int CoInitializeEx(IntPtr reserved, uint coInit);

        [DllImport("ole32.dll", ExactSpelling = true)]
        internal static extern void CoUninitialize();
    }
}
