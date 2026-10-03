# Replay phase-step forensics

Read-only analysis of retained evidence. No production code, timestamp options, desktop capture or recording changed. The continuous clock run identifies a bounded content sampling phase slip; final Product V1 A/V acceptance remains unresolved because the V3 Save A/B evidence is a separate recording.

## Reproduce

Requires Python and NumPy. The companion script reads TSV/JSON files and emits JSON to stdout only. It does not decode a new recording or create output/intermediate files.

```powershell
python ReplayPhaseForensics.py --probe-tsv 'D:\Codex\Projects\BoltSnip-ContinuousClock-20261002\tests\evidence\retained-clock-recomputed-20261002\continuous-video-clock-probe.tsv' --decoded-tsv 'D:\Codex\Projects\BoltSnip-ContinuousClock-20261002\tests\evidence\retained-clock-recomputed-20261002\continuous-video-clock-decoded-frames.tsv' --source-presentations-tsv 'D:\Codex\Work\BoltSnip-ContinuousClock-20261002\product-run-01\continuous-source\source-presentations.tsv' --v3-evidence-directory 'D:\Codex\Projects\BoltSnip-Source-agent-v3-integration-20261001\tests\evidence\product-final-20261001'
```

The primary probe contains first occurrences of unique pixel-decoded content states, not all video frames. PTS checks and duplicates use the separate all-frame decoded TSV. Piecewise regression uses actual retained ffprobe PTS. No outliers are removed. Theil–Sen resets NumPy default_rng seed 20261003 for each piece, draws 500000 i indices then 500000 j indices, and retains j > i. Rolling median uses explicit 45–52.483333 s candidate split grid, after earlier evidence located the event in 40–60 s. Its grid alone uses frame/60; underlying sample times are actual PTS. Global SSE and CUSUM independently scan all retained unique samples with the SSE split leaving at least 600 states on each side.

## Exact transition evidence

All frame numbers are zero-based.

| Method | Frame split | Actual PTS |
|---|---:|---:|
| Rolling median, 1 s each side | 2912 | 48.533333 s |
| Rolling median, 2 s each side | 2911 | 48.516667 s |
| Rolling median, 5 s each side | 2912 | 48.533333 s |
| Two-piece constant SSE | 2912 | 48.533333 s |
| Two-piece linear SSE | 2912 | 48.533333 s |
| Centered CUSUM | 2913 | 48.550000 s |

| Frame | Actual PTS | Sequence | Embedded elapsed QPC |
|---:|---:|---:|---:|
| 2909 | 48.483333 | 10359 | 1141630649 |
| 2910 | 48.500000 | 10359 | 1141630649 |
| 2911 | 48.516667 | 10360 | 1141756448 |
| 2912 | 48.533333 | 10361 | 1141875434 |
| 2913 | 48.550000 | 10362 | 1141996038 |

QPC frequency is 10000000 Hz; source epoch 166311311852. Duplicate frame absolute embedded QPC is 167452942501. SSE split-frame absolute embedded QPC is 167453187286. The exact duplicate adds 16.667 ms of content age. Fitted line discontinuity at the SSE split is 16.659252 ms; plateau median difference is 16.792850 ms. Statistical detectors locate the transition within two frames of each other, adjacent to the exact repeated content. They do not uniquely identify the internal capture/resampling instruction responsible.

All 18000 payload frames are valid. All 17999 PTS intervals are positive: 6000 intervals of 16.666 ms, 11999 of 16.667 ms. Maximum deviation from exact 1/60 s is 0.000667 ms, consistent with the stored six-decimal PTS representation. PTS anomalies: 0. This supports a content sampling/acquisition phase slip rather than PTS generator drift.

Manifest starts with segment 35, whose CSV global media start is 70.021354 s. The event belongs to retained segment 59 about 0.5 s after its start, rather than its two-second boundary. This is concatenation mapping evidence, not exact encoder QPC attribution.

## Piecewise slopes

| Piece | Duration | States | LS ms/min | Theil–Sen ms/min | First/last 10% median change ms | Literal endpoint rate ms/min |
|---|---:|---:|---:|---:|---:|---:|
| PRE before frame 2912 | 48.516667 s | 2865 | +0.224518 | +0.136373 | +1.117250 | +0.628856 |
| POST frame 2912 onward | 251.450000 s | 14760 | +0.007349 | -0.000431 | -0.014300 | +0.112627 |
| Supplemental POST from 60 s | 239.983333 s | 14079 | +0.038220 | +0.054819 | +0.115700 | -0.179462 |

Literal endpoint rates are sensitive to single-sample cadence jitter. First/last median change uses each piece's first and last 10% time windows. Full-run unique video LS +2.740475 ms/min is dominated by the step and should not be reported as continuous drift. Sparse observer POST LS is +0.013135 ms/min and matched differential POST LS +0.056772 ms/min over 2692 matching states. Source DwmFlush-minus-embedded delay median is 12.007400 ms PRE and 12.008750 ms POST; full-run LS +0.003253 ms/min.

## Duplicate/content caveat

There are 375 duplicate frames and 17625 unique states. The phase transition has one adjacent two-frame repeat at frame 2910. There is also a three-frame run at frame 1789 and a 27-frame repeated payload run at frames 4835–4861, PTS 80.583333–81.016667, sequence 13213. Source presentations independently pause 468.4249 ms from sequence 13213 to 13214; DwmFlush interval is 466.3344 ms. The long repeat is therefore a source-stimulus pause, not proof of a product capture freeze. Other duplicates are not automatically persistent phase slips. Human-visible stutter/effect was not assessed.

## Separate V3 Save A/B recording remains unresolved

The files under product-final-20261001 are a different recording from the continuous clock run. Do not combine their observations into a single acceptance result.

| Raw A/V metric | Save A | Save B |
|---|---:|---:|
| P95 absolute ms | 55.645667 | 55.333333 |
| Maximum absolute ms | 61.646667 | 62.333333 |
| Whole-run LS ms/min | +5.145265 | +5.316298 |
| Whole-run Theil–Sen ms/min | +4.977188 | +4.977354 |
| First/last median change ms | +20.489667 | +20.656667 |
| Independent best two-piece POST LS ms/min | +4.934364 | +4.837345 |

The independent two-piece fit splits at shared signal ID 26, video PTS 106.7 s in A and 80.7 s in B. All events are below 100 ms absolute, but that alone does not prove absence of progressive drift. Cross-save shared IDs: 55. B−A median +0.312333 ms, P95 absolute 0.687667 ms, maximum absolute 0.687667 ms. Saves are consistent; the earlier progressive A/V trend remains unexplained.

## Decision and limits

Classification for the continuous video clock run: BOUNDED CONTENT SAMPLING PHASE SLIP; NO MEASURABLE CONTINUOUS VIDEO CLOCK DRIFT AFTER THE STEP. Do not modify Replay timestamp parameters based only on this event. Internal acquisition mechanism, human-visible effect, and same-run audio-clock stability remain unproven. Historical continuous runner result still has Failure=Source observer failed, BaselineExit=null, RunnerStateReady=false; offline consistency does not recover runtime acceptance. Observer sampling is censored and DwmFlush does not measure physical scan-out.

Final Issue C acceptance remains unresolved. The next smallest experiment combines continuous pixel-QPC markers and V3 audio/visual signal-derived IDs in the already-required final Save A/B recording, with separate piecewise video PTS-minus-source QPC and audio PTS-minus-source audio QPC analyses. Do not claim NO PRODUCT CLOCK DRIFT across all evidence until the separate A/V trend is explained or reproduced with a verified stable result.
