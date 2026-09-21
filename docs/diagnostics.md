# BoltSnip diagnostics

Lifecycle diagnostics are disabled by default and add only a boolean check to capture paths.

Set `BOLTSNIP_DIAGNOSTIC_LOG=1` before starting BoltSnip to record capture lifecycle events. Logs are written to `%LOCALAPPDATA%\BoltSnip\diagnostic.log` and are truncated when they reach 1 MB. `BOLTSNIP_DIAGNOSTIC_LOG_PATH` may override the destination with an absolute path.

Recorded events: `Startup`, `Capture Start`, `Overlay Show`, `Capture End`, `Capture Failed`, `Overlay Hide`, and `Resource Cleanup`.

`Startup` includes the release version, full executable path, process ID, UTC startup time, build time, and build ID. Use it to distinguish stale binaries and shortcuts without enabling verbose capture tracing.
