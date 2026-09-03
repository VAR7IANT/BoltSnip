# Performance baseline

Recorded on 2026-09-03 with the Release Hardening build. The machine had one
active 1707 x 1067 display. Values are point-in-time engineering baselines, not
release limits.

| Metric | Result |
| --- | ---: |
| Tray-ready startup | 198 ms |
| Capture initialization | 60 ms |
| `Overlay.Show()` | 55.40 ms |
| End-to-end overlay visibility smoke test | 125 ms |
| Alignment guide draw | 136.21 microseconds/call |
| Color analyzer call | 32.91 microseconds/call |
| Capture working set | 83.8 MB |
| Capture private memory | 54.5 MB |
| Capture GDI objects | 30 |
| Capture USER objects | 30 |

Run `tests/PerformanceBaseline.ps1` for the component baseline and
`tests/SmokeTest.ps1` for the end-to-end capture baseline. Compare multiple
runs on the same machine; screenshot capture time and memory vary with display
resolution, DPI, and desktop contents.

## v0.12.0 release-hardening checkpoint

- End-to-end screenshot startup: 125 ms
- Alignment guide draw: 136 microseconds/call
- Color analyzer call: 33 microseconds/call
- Capture working set: approximately 84 MB
- Regression suite: 23/23 passed
