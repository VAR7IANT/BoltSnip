# BoltSnip Product V1 cursor evidence audit

Prepared 2026-10-03, Asia/Shanghai. Read-only analysis of existing files; this report ran no new captures and changed no production source.

## Conclusion

Root cause remains unlocalized. The three new 60-second trials recorded zero GetCursorInfo visibility transitions, including the DDA configuration previously associated with flicker. These observations do not invalidate the earlier user-visible symptom and do not demonstrate a fix. No external camera/independent physical-screen observation, five-minute cursor acceptance, replay cursor-quality validation, or GDI performance/A/V acceptance is supplied by these trials. Verdict: **CURSOR FLICKER FIX NOT PROVEN**.

## Existing branch

Repository/worktree: `D:\Codex\Projects\BoltSnip-Source-replay-mouse-flicker`.

Reviewed branch commit `fb4bdc8f552391165966b5334db6a938da685fd5` is one commit directly above Product V1 `9e94f2f513f929e52e14de72759fedeb690d1370`. It changes five files: README, ReplayCaptureSession, ReplayManager, ReplaySettings and ReplayCaptureBackendSelectionTest. It defaults all displays to GDI, changes DDA draw_mouse from 1 to 0, and adds diagnostic/user warnings. This is a backend workaround; it does not identify or repair the underlying DDA interaction. It should not be merged as-is.

Earlier evidence under `D:\Codex\Projects\BoltSnip-Source-replay-mouse-flicker\bin\mouse-flicker-evidence`:

| Trial | Configuration | Visibility transitions | Duration |
|---|---|---:|---:|
| A-dda-mouse1-retry | DDA mouse=1 | 2 | approximately 26s |
| B-dda-mouse0 | DDA mouse=0 | 4 | approximately 26s |
| C-gdi-mouse1 | GDI mouse=1 | 0 | approximately 26s |
| RC2-default-60s-verified | GDI mouse=1 | 0 of 3876 samples | 60s sampled |

Deficiencies in that branch/evidence:

- `tests\ReplayCaptureBackendArgumentsTest.ps1:29` still requires draw_mouse=1 despite the branch emitting draw_mouse=0. The branch leaves an existing test inconsistent with production behavior.
- `bin\RunMouseFlickerCapture.ps1` starts sampling after Recording/audio readiness, omitting startup and stop. It records aggregate visibility rather than per-sample QPC, handle, flags and position, preventing trigger correlation.
- Old logs report capture bounds 1707x1067, so these runs cannot establish the required 2560x1600 performance. Reflection-host DPI virtualization is a plausible explanation, not an established cause.
- Old result JSON does not bind an EXE hash to the test. A generated identity source records fb4bdc8f5523, but source text alone is not a tested-binary hash.
- DDA mouse=0 did not eliminate the earlier physical visibility switches and removes the software cursor from the recorded replay. A new default backend requires independent five-minute GDI performance/A/V evidence.

## New trial provenance

Evidence root: `D:\Codex\Work\BoltSnip-FinalStabilization`.

Each trial contains `identity.json`, `cursor-samples.tsv`, `lifecycle.jsonl`, `diagnostic.log`, and `summary.json`. Observer harness: `D:\Codex\Data\visualizations\2026\10\03\01a10047-c8ad-7e71-b7af-039a5c4f2807\CursorSessionProbe.ps1`.

All identity files report per-monitor DPI awareness 2, primary/native dimensions 2560x1600 at (0,0), and QPC frequency 10000000. Encoder logs confirm 2560x1600 and requested 60 FPS. Encoder arguments include H.264 NVENC P4, GOP 120, two-second segments, and AAC 48kHz stereo. Requested FPS and an active encoder are not decoded-output FPS proof.

| Trials | EXE | Embedded BuildId | EXE SHA256 |
|---|---|---|---|
| cursor-dda-60s; cursor-gdi-60s | diagnostic-build\BoltSnip.exe | d16bd21e573befae37e15bcf8983c5325517b51c | A90936C95EF47BADC7F6A74B65449A6027E380A083D66F6A73C5090BF6D7B81A |
| cursor-dda-mouse0-60s | D:\Codex\Projects\BoltSnip-Source-replay-mouse-flicker\bin\BoltSnip.exe | fb4bdc8f5523 | F09C4CF31F69E6600CC1CCA3A82A4E056F9BB996511E4BACA8E4F01C1D2E0595 |

Diagnostic build time: 2026-10-03T05:50:04.0418496Z. Mouse=0 build time: 2026-10-02T17:49:09.4844514Z. Mouse=0 runner supplied expected Git SHA fb4bdc8f552391165966b5334db6a938da685fd5 and checked the embedded prefix. Build metadata and hashes identify the tested files; they do not establish an unchanged source tree beyond that identity.

All three use `D:\Codex\Projects\BoltSnip-Source\bin\ffmpeg.exe`, SHA256 `C7364C2FB2F7ED2E944C1E5B76ACB8C0869BE942C17143756BCAC952C66C07C5`.

## Exact Recording interval measurements

Counts below were recomputed from each raw TSV using inclusive QPC bounds between RecordingDurationStarted and RecordingDurationCompleted. This preserves the first run's original summary, which predates the RecordingInterval field. A transition is a change of CURSOR_SHOWING between consecutive successful samples inside that window. No failed samples occurred.

| Trial | Logged backend/mouse | Start QPC | End QPC | Duration seconds | Raw samples | Visible samples | Transitions | API errors | State snapshots | Encoder PID |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| cursor-dda-60s | DDA / 1 | 15329695428 | 15930284682 | 60.0589254 | 3927 | 3927 | 0 | 0 | 952 | 3272 |
| cursor-dda-mouse0-60s | DDA / 0 | 20858729946 | 21458996420 | 60.0266474 | 3890 | 3890 | 0 | 0 | 952 | 7880 |
| cursor-gdi-60s | GDI / 1 | 21767982789 | 22368153616 | 60.0170827 | 3901 | 3901 | 0 | 0 | 948 | 40404 |

Every state snapshot within each interval reports Recording and Audio Active. Each interval has one encoder PID. Across the broader observer window (baseline/startup/recording/stop), totals were 4567, 4422 and 4400 samples respectively, with zero transitions and zero API errors.

Recording windows in UTC:

- DDA mouse=1: 2026-10-03T05:51:11.2543367Z through 05:52:11.3126711Z.
- DDA mouse=0: 2026-10-03T06:00:24.1579113Z through 06:01:24.1844132Z.
- GDI mouse=1: 2026-10-03T06:01:55.0822215Z through 06:02:55.0995808Z.

Activity differences matter: DDA mouse=1 has 79 distinct sampled positions and three cursor handles; DDA mouse=0 has one position and one handle; GDI has 230 positions and five handles. The mouse=0 trial principally covers a stationary cursor. None documents a matched focus/fullscreen/compositor stimulus script. The configuration comparison is therefore not a controlled reproduction of the earlier flicker.

## Preserved first-run teardown failure

`cursor-dda-60s\summary.json` retains the original error: `Dispose: ... You cannot call a method on a null-valued expression.` The harness queried Dispose with Instance/NonPublic flags, but ReplayManager.Dispose is public. This is a harness lookup defect, not evidence that product Dispose threw.

The first run's lifecycle reached State Disabled and AudioState Disabled after Stop; RemainingObservedPIDs is empty. Recording observations remain usable, but the run's exit 1/failed teardown validation must remain reported. Subsequent harness source includes public Dispose lookup. The later DDA mouse=0 and GDI summaries report Failure=null and no remaining observed PIDs; this does not retroactively turn the first run into a fully passing harness execution.

The first run used the C-drive system replay temp directory. Subsequent source sets/restores process TEMP and TMP to OutputDirectory\temp before manager startup; later commands record D-drive cache paths. No original evidence was rewritten or deleted.

## Measurement limitations and remaining hypotheses

- The worker requests a five-millisecond sleep, but approximately 3900 samples over 60 seconds means about 65 samples/second in these trials. QPC enables exact timing; an unsampled subinterval can still contain a brief visual event. Zero sampled CURSOR_SHOWING transitions does not imply every displayed frame retained its physical cursor.
- No independent external camera or user-confirmed physical visual evidence accompanies these runs. Physical composition can differ from the GetCursorInfo visibility flag.
- No saved/decode-verified replay, software-cursor image comparison, five-minute cursor trial, save-during-recording exercise, resource-range measurement, or signal-derived A/V check was performed by this harness.
- The DDA mouse=0 trial uses a separate branch EXE with other policy/notification differences; it is not a one-variable build comparison.
- Existing results identify a past DDA-associated interaction and failure of draw_mouse=0 to resolve it. They do not isolate startup, initialization, AcquireNextFrame, segment edges, encoder restart, cursor shape, focus or compositor conditions.

## Next smallest controlled reproduction

Use the user's actual flickering desktop/application scene and record physical cursor behavior with an independent camera/manual observation. Keep the same GPU/Windows/display/FFmpeg stack, 2560x1600/60 FPS, NVENC P4 and audio. Use the existing DPI-aware observer from before startup through stop. Add explicit QPC markers for manual stimulus phases without forcing pointer visibility or injecting input.

For each backend trial, repeat the same manual sequence: stationary arrow baseline; ordinary pointer movement over the affected surface; hover transitions between arrow, text and resize cursor shapes; deliberate foreground/focus changes between the same applications; then the affected fullscreen/borderless condition if relevant. Log user-observed flicker times and match them against raw flags/handle/position, encoder lifecycle and segment timing. Compare DDA mouse=1, DDA mouse=0 in an isolated diagnostic build with only that parameter changed, and GDI mouse=1. Keep startup and stop windows separate from the 60-second Recording window.

Do not use ShowCursor loops, periodic visibility forcing, mouse_event tricks or cursor teleportation. Do not change default backend policy from these nonreproducing short trials. If GDI is required by a reliably reproduced symptom, first complete the specified five-minute 2560x1600/60 FPS audio/save/decode/starvation/A/V/resource acceptance, followed by physical visual cursor confirmation.
