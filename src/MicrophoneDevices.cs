using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace BoltSnip
{
    internal sealed class MicrophoneDevice
    {
        internal readonly string Id;
        internal readonly string Name;
        internal MicrophoneDevice(string id, string name) { Id = id; Name = name; }
        public override string ToString() { return Name; }
    }

    internal static class MicrophoneDevices
    {
        [StructLayout(LayoutKind.Sequential)] private struct PropertyKey { internal Guid Format; internal uint Id; }
        [StructLayout(LayoutKind.Explicit, Size = 24)] private struct Variant
        {
            [FieldOffset(0)] internal ushort Type;
            [FieldOffset(8)] internal IntPtr Text;
        }
        [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface PropertyStore
        {
            [PreserveSig] int GetCount(out uint count);
            [PreserveSig] int GetAt(uint index, out PropertyKey key);
            [PreserveSig] int GetValue(ref PropertyKey key, out Variant value);
            [PreserveSig] int SetValue(ref PropertyKey key, ref Variant value);
            [PreserveSig] int Commit();
        }
        [DllImport("ole32.dll")] private static extern int PropVariantClear(ref Variant variant);

        internal static List<MicrophoneDevice> List()
        {
            List<MicrophoneDevice> result = new List<MicrophoneDevice>();
            result.Add(new MicrophoneDevice(string.Empty, "系统默认通信麦克风"));
            IMMDeviceEnumerator enumerator = null;
            IMMDeviceCollection collection = null;
            try
            {
                enumerator = (IMMDeviceEnumerator)Activator.CreateInstance(Type.GetTypeFromCLSID(WasapiInterop.AudioClientClassId, true));
                Marshal.ThrowExceptionForHR(enumerator.EnumAudioEndpoints(AudioDataFlow.Capture, 1, out collection));
                uint count; Marshal.ThrowExceptionForHR(collection.GetCount(out count));
                for (uint index = 0; index < count; index++)
                {
                    IMMDevice device = null;
                    try
                    {
                        Marshal.ThrowExceptionForHR(collection.Item(index, out device));
                        string id; Marshal.ThrowExceptionForHR(device.GetId(out id));
                        result.Add(new MicrophoneDevice(id, FriendlyName(device, "麦克风 " + (index + 1))));
                    }
                    finally { Release(device); }
                }
            }
            catch (Exception error) { ReplayDiagnostics.Write("Microphone enumeration unavailable: " + error.Message); }
            finally { Release(collection); Release(enumerator); }
            return result;
        }

        private static string FriendlyName(IMMDevice device, string fallback)
        {
            IntPtr pointer = IntPtr.Zero;
            PropertyStore store = null;
            Variant value = new Variant();
            try
            {
                Marshal.ThrowExceptionForHR(device.OpenPropertyStore(0, out pointer));
                store = (PropertyStore)Marshal.GetTypedObjectForIUnknown(pointer, typeof(PropertyStore));
                PropertyKey key = new PropertyKey { Format = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), Id = 14 };
                Marshal.ThrowExceptionForHR(store.GetValue(ref key, out value));
                return value.Type == 31 ? (Marshal.PtrToStringUni(value.Text) ?? fallback) : fallback;
            }
            catch { return fallback; }
            finally { PropVariantClear(ref value); Release(store); if (pointer != IntPtr.Zero) Marshal.Release(pointer); }
        }
        private static void Release(object value) { if (value != null && Marshal.IsComObject(value)) Marshal.ReleaseComObject(value); }
    }
}