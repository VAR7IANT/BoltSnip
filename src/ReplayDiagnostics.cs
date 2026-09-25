namespace BoltSnip
{
    internal static class ReplayDiagnostics
    {
        internal static void Write(string message)
        {
            CaptureDiagnostics.WriteReplay(message);
        }
    }
}
