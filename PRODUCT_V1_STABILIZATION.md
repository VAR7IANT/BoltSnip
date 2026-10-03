# BoltSnip Product V1 Final Stabilization

Date: 2026-10-03 (Asia/Shanghai)
Repository: VAR7IANT/BoltSnip-Source
Branch: fix/product-v1-final-stabilization
HEAD: FINAL_HEAD_AFTER_REPORT_COMMIT (see delivered git-state.json)
Base: 9e94f2f513f929e52e14de72759fedeb690d1370
Production source changed: YES

**Final verdict: BLOCKED BY UNRESOLVED ROOT CAUSE**

Production fixes are reviewable; this is not a final acceptance PASS. Screenshot dark-pixel corruption is reproduced and corrected in the actual provided source-image fixture. Hotkey V2 is ported, transactional, recording-safe, and verified at the current real DPI. Cursor root cause and the separate retained A/V trend are unresolved. Final integration regression was not started because A/B/C acceptance is incomplete.

## Screenshot White Spot

User symptom reproduced: YES, using the authoritative Downloads source image displayed on the actual desktop at native 1:1. The anomalous Downloads crops were also inspected visually. This is a real image fixture; it does not reproduce every original application's rendering state.

Currently installed/running EXE inspected: C:\Users\VAR7IANT\Documents\ChatGPT\BoltSnip\bin\BoltSnip.exe; embedded BuildId=23a590fe3abd, BuildTimeUtc=2026-09-26T09:51:20.1135085Z, version1.0.0. This existing running binary is the System Audio baseline, not a screenshot-fixed Product V1 executable. It was preserved (PID38844, original start time).

Tested delivered EXE: D:\Codex\Outputs\BoltSnip-ProductV1-Stabilization-20261003\BoltSnip.exe
Tested EXE Git SHA: 1042006187a528a1c40cbbba45916d233ea65a3c; clean source.
EXE SHA256: 19F394CD9239B0923919420C72432F3C9D47AC5625CE3D38F3E52AC085E4871B
Build timestamp: 2026-10-03T06:16:38.0538568Z.
Backend: NativeTopDownDibBitBlt. Startup diagnostics now contain full commit, dirty state, timestamp and backend; diagnostic logging must be enabled.

First corruption stage: StageA ScreenCapture.Capture. Native reference RGB(13,11,12,255) became stored RGBA(0,0,0,0). In the selected 900x950 ROI, 242 pixels/151 connected components were damaged. Real _screen, crop and PNG retained damage; Clipboard readback produced RGB(211,211,211), #D3D3D3. Actual selected overlay painted damaged positions dark instead of the original image. The evidence distinguishes stored bytes from displayed pixels.

Root cause: BitBlt into a Graphics.FromImage(PArgb bitmap).GetHdc destination loses this dark-pixel pattern. Independent native DIB capture preserves the visible source. This is not fixed by changing only downstream alpha.

Fix: Reimplemented top-down 32-bit BI_RGB DIB capture in the private Product V1 source; materialize an owned opaque RGB Bitmap via FromHbitmap. Preserve bounds.Left/Top, CAPTUREBLT and the crop interface. Validate row/total arithmetic before GDI allocation; restore selected bitmap and free DIB/DC/source handles on every exception path. No public commit was cherry-picked.

| Check | Result |
|---|---|
| Native visible source vs supplied source ROI | 0 differences |
| StageA/B/C, Clipboard, PNG, actual selected Overlay | 0 anomalies and 0 RGBA differences |
| 100 repeated actual desktop captures | PASS; 0 mismatches, 0 anomalies |
| GDI resources | 24 before /24 after; delta0 |
| Zero/negative/row-overflow/total-overflow bounds | PASS |
| Capture latency median /P95 /max | 38.754650 /44.665700 /48.794700 ms |
| Single monitor at2560x1600, DPI150% | PASS for source fixture |
| Multiple monitors /negativeX /negativeY | UNAVAILABLE: current desktop has one monitor at0,0 |
| Real100/125/200% desktop screenshot matrix | NOT RUN; only current150% measured |
| Browser scrolling/moving/hover/video/WebGL | NOT RUN |
| Overlay temporal magnifier/toolbar/guide transitions | NOT RUN |

Real browser/layered acceptance: **BLOCKED /NOT PASS**. First Chromium trial was occluded by the live Antigravity window:100 browser iterations plus10 layered iterations yielded7,137,420 mismatches and116,278 anomaly candidates. Saved images show the wrong foreground scene, so these are invalid browser acceptance data and cannot be attributed to capture corruption. Revised visibility checks stopped the second trial before comparison with `INFRASTRUCTURE INVALID: intended browser ROI occluded at66,201; actualRootHwnd=1574178; ownedBrowser=332846`, even after requesting owned-window topmost. Original failed evidence is retained; no threshold was relaxed. Actual hardware acceleration and intended browser exposure remain unverified.

Strict verdict: **SCREENSHOT WHITE-SPOT STILL NOT FIXED** (full requested acceptance incomplete). The proven242-pixel source-fixture defect is fixed; the verdict does not imply recurrence in that passing fixture.

Next smallest experiment: expose the owned Chromium fixture on an unobscured interactive desktop and pass the visibility+native-reference bracketing checks, then100 exact captures and dynamic scenarios. Complete the unavailable monitor/real-DPI matrix separately.

## Physical Cursor Flicker

Existing private branch fb4bdc8 reviewed, not merged. It defaults all displays to GDI and disables DDA cursor recording, without a root-cause fix. Its old captures were1707x1067 and lacked raw startup/segment cursor traces; an argument test still expected draw_mouse1.

Old observed transitions: DDA mouse1=2/~26s; DDA mouse0=4/~26s; GDI=0/~26s. Those historical observations are not invalidated by the new trials.

| New actual2560x1600 trial | Recording duration | Samples | Visibility changes | Hidden/API errors |
|---|---:|---:|---:|---:|
| DDA draw_mouse1, private diagnostic ProductV1 | 60.0589254s | 3927 | 0 | 0 |
| DDA draw_mouse0, reviewed ProductV1-derived fb4bdc8 binary | 60.0266474s | 3890 | 0 | 0 |
| GDI draw_mouse1, private diagnostic ProductV1 | 60.0170827s | 3901 | 0 | 0 |

All sampled Recording intervals retained Active audio and one encoder PID. Raw QPC/flags/handle/position and lifecycle traces remain under D:\Codex\Work\BoltSnip-FinalStabilization. Compact provenance/results and a detailed audit are committed.

First trial exited1 because the tests-only reflection harness looked for public Dispose with NonPublic flags. Stop still reached Disabled+Audio Disabled and no observed encoder remained. This failed harness teardown is preserved; the corrected harness passed subsequent trials. Its first cache used normal C-drive system temp; corrected later trials use D-drive TEMP/TMP.

Limitations: observed sampling approximately65Hz; transient physical compositor flicker can escape visibility sampling. Mouse stimuli were unmatched, especially stationary mouse0. No independent physical-screen recording, continuous5-minute visual acceptance, video-cursor inspection or GDI5-minute performance/A/V proof.

Final backend policy: **unchanged ProductV1 DDA selection/GDI fallback; draw_mouse1 unchanged**. No ShowCursor, mouse_event, teleport or visibility forcing.

60sec measurement:0 events. 5min:NOT RUN. Replay cursor:UNVERIFIED. Root cause:UNRESOLVED. Strict verdict: **CURSOR FLICKER STILL PRESENT** (reported symptom unresolved, not reproduced during these measurements).

Next smallest experiment: reproduce the physical symptom with matched movement/shape/focus workload and independent physical-screen observation, while keeping the raw observer. Identify startup/acquisition/segment/NVENC triggers before changing backend policy.

## Replay Timing

No new5-minute run before existing-data forensics; no production timestamp/capture/encoder/audio resampling changes.

Exact duplicate: zero-based frame2910, PTS48.500000s, embedded sequence10359, elapsedQPC1141630649, frequency10000000. Frame2909 carries the same payload. Statistical change neighborhood: rolling2smedian frame2911/48.516667; piecewiseSSE frame2912/48.533333; independentCUSUM frame2913/48.550000. Fitted phase step16.659252ms; plateau median shift16.792850ms. At segment59 ~0.5s after start, not a concat boundary.

PTS anomalies:0;18000 valid decoded frames,17999 positive16.666/16.667ms intervals. Duplicate frames375, unique states17625. One27-frame payload repeat is independently accompanied by a468.4249ms source-stimulus pause and is not evidence of a capture freeze.

| Piece | Duration | LS ms/min | Theil-Sen ms/min | First-last10% median change |
|---|---:|---:|---:|---:|
| PRE | 48.516667s | +0.224518 | +0.136373 | +1.117250ms |
| POST | 251.450000s | +0.007349 | -0.000431 | -0.014300ms |

Clock-run classification: **BOUNDED CONTENT SAMPLING PHASE SLIP; NO MEASURABLE CONTINUOUS VIDEO CLOCK DRIFT AFTER THE STEP**. Whole-run+2.740475ms/min is dominated by the step. User-visible effect is unmeasured; do not label every duplicate a product defect.

The separate retained V3 SaveA/B run remains a limitation:

| Metric | SaveA | SaveB |
|---|---:|---:|
| Raw A/V P95 abs | 55.645667ms | 55.333333ms |
| Raw A/V max abs | 61.646667ms | 62.333333ms |
| Whole-run LS | +5.145265ms/min | +5.316298ms/min |
| Whole-run Theil-Sen | +4.977188ms/min | +4.977354ms/min |
| First-last median change | +20.489667ms | +20.656667ms |
| Post best-piece A/V LS | +4.934364ms/min | +4.837345ms/min |

55 shared IDs differ median0.312333ms, P95/max0.687667ms. All retained events are<100ms and saves agree, but progressive A/V absence is **UNPROVEN**. A stable later video-only clock run cannot erase a different run's A/V trend. The historical continuous runner also retained Source observer failed/RunnerStateReady=false; offline analysis does not upgrade that runtime gate.

Next smallest experiment: same-run continuous pixel-QPC plus frozen V3 visual/audio signals, independently model saved audioPTS-source audioQPC and videoPTS-embeddedQPC, then SaveA/B. Do not blindly alter timestamp parameters.

Reproducible script and detailed report: tests/ReplayPhaseForensics.py and tests/evidence/product-v1-final-stabilization-20261003/ReplayPhaseForensics.md.

## Hotkey Settings V2

Migrated from old base: YES, from local uncommitted codex/hotkey-settings-v2 work at070b610, ported by differences onto9e94f2f. Audio, backend, encoder, ReplaySaver and ReplayManager production files remain unchanged.

Defaults preserved: screenshotAlt+A; replayAlt+Shift+S. Ctrl+Shift+F13/F14 are isolated test configurations, not defaults. Product startup screenshot fallbackCtrl+Shift+A is retained. Existing normal availability is muted; window dimensions/fonts are90%; blue/white/gray buttons and explicit capture mode/Esc cancellation retained.

Screenshot and Replay change/persistence/cancel/conflict/config-write rollback: **PASS**. Live registration tests and actual shown-dialog tests passed. Rollback reports failure if a competing process claims a temporarily released previous gesture; no unconditional OS ownership guarantee is claimed.

Recording-safe live change: **PASS**. After60.021354s/30segments with Recording+AudioActive, edited Replay gesture and saved settings. Old gesture synthetic OS keyboard input caused0 callbacks; new gesture caused1 accepted save. Before/after/save used the same encoderPID30148, same start time, audio pipe GUID and buffer object. StopRequested=false; buffer advanced to62.021354s/31segments. Settings call chain calls no Stop. No physical-human keypress or audio-object identity instrumentation is claimed.

Saved media: H2642560x1600,60/1,3720frames,62.000000s; AAC48000Hz stereo,62.026688s; full decode exit0. This62s validation is not the final5-minute regression.

Real DPI: current150% **PASS**, native/layoutDPI144 and594x446client size; actual text/control bounds and saved desktop image inspected. Synthetic100/125/150/200%layout tests **PASS**. Real100/125/200%system DPI not changed. Actual150%smoke found and fixed a constructor96DPI clipping defect using native GetDpiForWindow at handle creation; final delivered EXE retested.

## Final 60 FPS Product Regression

Build: PASS, clean tested commit1042006187a528a1c40cbbba45916d233ea65a3c.
Targeted automated tests: PASS (HotkeyRollback, StartupFallback, Persistence, DialogInteraction, fourDPI layouts, startup provenance, VersionInformation, SelectionPrecision, PixelFidelity; current realDPI smoke).
All existing automated tests /full screenshotUX /JPEG /10xlifecycle /5:40continuous /finalSaveA/B /V3same-run A/V /300sringbounded: **NOT RUN**. User's prerequisite requires A/B/C/D completion before E; unresolved roots and incomplete A acceptance prevent this final gate. The earlier5-minute media metrics are historical evidence, not this branch's final regression.
120 FPS touched: NO. No120FPS source/UI/acceptance change. No threshold reduction.

## Git

Core production commits:5af7cf3 HotkeyV2;04ef1e9 screenshot/provenance. Evidence commits:3902286 cursor; e40e53e replayforensics. Later tests-only fixture guard1042006 and final report/evidence commit are separate; final HEAD and remote HEAD are recorded in delivered git-state.json.
Remote branch: VAR7IANT/BoltSnip-Source/fix/product-v1-final-stabilization.
Public BoltSnip source modified by this task: NO.
Main modified: NO.
No main merge; no public-source commit; no release.

## Final Verdict

**BLOCKED BY UNRESOLVED ROOT CAUSE**

Stop for independent review. Do not treat the delivered diagnostic executable or passing source-fixture/Hotkey checks as PRODUCT V1 FINAL STABILIZATION READY.