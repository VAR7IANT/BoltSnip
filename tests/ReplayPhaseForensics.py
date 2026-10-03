"""Read retained evidence only; emit reproducible JSON to stdout, create no files."""
import argparse
import csv
import json
from pathlib import Path
import numpy as np


def read_tsv(path):
    with open(path, encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe-tsv", type=Path, required=True)
    parser.add_argument("--decoded-tsv", type=Path, required=True)
    parser.add_argument("--v3-evidence-directory", type=Path)
    parser.add_argument("--source-presentations-tsv", type=Path)
    parser.add_argument("--epoch-qpc", type=int, default=166311311852)
    args = parser.parse_args()
    rows = read_tsv(args.probe_tsv)
    decoded = read_tsv(args.decoded_tsv)
    x = np.array([float(row["VideoPTS"]) for row in rows])
    y = np.array([float(row["VideoClockErrorMs"]) for row in rows])
    n = len(x)
    if n < 1202:
        raise ValueError("Need at least 1202 unique probe states for fixed 600-state split guard")
    cumulative = [np.r_[0, np.cumsum(z)] for z in [x, y, x*x, x*y, y*y]]

    def fit(a, b):
        sx, sy, sxx, sxy, syy = [z[b]-z[a] for z in cumulative]
        count = b-a
        denominator = sxx-sx*sx/count
        slope = (sxy-sx*sy/count)/denominator
        intercept = (sy-slope*sx)/count
        sse = syy-sy*sy/count-(sxy-sx*sy/count)**2/denominator
        return float(sse), float(slope), float(intercept)

    candidates = np.arange(600, n-600)
    constant_cost = cumulative[4][candidates]-cumulative[1][candidates]**2/candidates + (cumulative[4][n]-cumulative[4][candidates])-(cumulative[1][n]-cumulative[1][candidates])**2/(n-candidates)
    constant_split = int(candidates[np.argmin(constant_cost)])
    linear_cost = np.array([fit(0, int(k))[0]+fit(int(k), n)[0] for k in candidates])
    split = int(candidates[np.argmin(linear_cost)])
    cusum_split = int(np.argmax(np.abs(np.cumsum(y-y.mean())))+1)

    def location(index):
        return dict(uniqueProbeIndex=index, replayFrameIndex=int(rows[index]["ReplayFrameIndex"]),
                    actualPTS=float(x[index]), sequence=int(rows[index]["Sequence"]),
                    embeddedElapsedQpc=int(rows[index]["EncodedQpc"]),
                    embeddedAbsoluteQpc=args.epoch_qpc+int(rows[index]["EncodedQpc"]))

    def metrics(mask):
        xx, yy = x[mask], y[mask]
        count = len(xx)
        span = float(xx[-1]-xx[0])
        # Exact original deterministic policy, including reset per piece.
        rng = np.random.default_rng(20261003)
        i = rng.integers(0, count, 500000)
        j = rng.integers(0, count, 500000)
        selected = j > i
        ts = np.median((yy[j[selected]]-yy[i[selected]])/(xx[j[selected]]-xx[i[selected]]))*60
        delta = float(np.median(yy[xx >= xx[-1]-.1*span])-np.median(yy[xx <= xx[0]+.1*span]))
        return dict(count=count, startPTS=float(xx[0]), endPTS=float(xx[-1]), durationSeconds=span,
                    lsMsPerMin=float(np.polyfit(xx, yy, 1)[0]*60), theilSenMsPerMin=float(ts),
                    theilSenOrderedPairs=int(selected.sum()), firstLast10pctMedianChangeMs=delta,
                    firstLast10pctApproxRateMsPerMin=delta/(span*.9)*60,
                    literalEndpointRateMsPerMin=float((yy[-1]-yy[0])/span*60), medianMs=float(np.median(yy)))

    # Local rolling time medians are a separate detector from the global SSE/CUSUM.
    # Search is declared in advance around the previously observed 40-60 s event.
    rolling = []
    for window in [1, 2, 5, 10]:
        best = (-float("inf"), None)
        for frame in range(2700, 3150):
            t = frame/60
            left = y[(x >= t-window) & (x < t)]
            right = y[(x >= t) & (x < t+window)]
            if not len(left) or not len(right):
                continue
            score = float(np.median(right)-np.median(left))
            if score > best[0]:
                best = (score, frame)
        rolling.append(dict(windowEachSideSeconds=window, medianDifferenceMs=best[0],
                            replayFrameSplit=best[1], splitGridSeconds=best[1]/60))
    all_pts = np.array([float(row["VideoPTS"]) for row in decoded])
    sequences = np.array([int(row["Sequence"]) for row in decoded])
    intervals = np.diff(all_pts)
    interval_values, interval_counts = np.unique(np.round(intervals, 9), return_counts=True)
    duplicate_indices = np.flatnonzero(np.diff(sequences) == 0)+1
    cuts = np.r_[0, np.flatnonzero(np.diff(sequences) != 0)+1, len(sequences)]
    runs = sorted([(int(cuts[k+1]-cuts[k]), int(cuts[k]), int(sequences[cuts[k]])) for k in range(len(cuts)-1)], reverse=True)
    pre_line, post_line = fit(0, split), fit(split, n)
    result = dict(inputs=dict(probeTSV=str(args.probe_tsv), decodedTSV=str(args.decoded_tsv)),
                  modelPolicy="Probe TSV has first unique content states; regression axis actual PTS, not reconstructed frame/60. Rolling scan grid alone uses frame/60 for candidate split times. No outliers removed.",
                  theilSenPolicy="numpy default_rng seed 20261003 reset per piece, 500000 i pairs then 500000 j pairs; retain j>i",
                  constantSSE=dict(location=location(constant_split), sse=float(constant_cost.min())),
                  linearSSE=dict(location=location(split), sse=float(linear_cost.min()),
                                 stepAtSplitMs=(post_line[1]*x[split]+post_line[2])-(pre_line[1]*x[split]+pre_line[2])),
                  cusum=dict(location=location(cusum_split)), rollingMedians=rolling,
                  pieces=dict(pre=metrics(x < x[split]), post=metrics(x >= x[split]),
                              preBefore45sSupplemental=metrics(x < 45), postFrom60sSupplemental=metrics(x >= 60)),
                  plateauMedianDifferenceMs=float(np.median(y[x >= x[split]])-np.median(y[x < x[split]])),
                  pts=dict(frames=len(decoded), validPayloadFrames=sum(int(z["DecodeValid"]) == 1 for z in decoded),
                           nonpositiveIntervals=int(np.sum(intervals <= 0)),
                           intervalSecondsAndCounts=list(zip(interval_values.tolist(), interval_counts.tolist())),
                           maxDeviationFrom60fpsMs=float(np.max(np.abs(intervals-1/60))*1000)),
                  duplicates=dict(count=len(duplicate_indices), uniqueStates=len(set(sequences.tolist())),
                                  nearTransitionFrames=[int(k) for k in duplicate_indices if abs(all_pts[k]-x[split]) <= 1],
                                  transitionRows=decoded[2909:2915],
                                  longestRuns=[dict(frames=a, firstFrame=b, lastFrame=b+a-1, sequence=c,
                                                    firstPTS=float(all_pts[b]), lastPTS=float(all_pts[b+a-1])) for a,b,c in runs[:5]]),
                  classification="Single bounded content sampling phase slip; no measurable continuous video-clock drift after step in this run. Internal acquisition cause and human-visible effect unmeasured.")
    paired = {}
    for field in ["ObserverClockErrorMs", "DifferentialErrorMs"]:
        selected = [z for z in rows if z[field]]
        xx = np.array([float(z["VideoPTS"]) for z in selected])
        yy = np.array([float(z[field]) for z in selected])
        post = xx >= x[split]
        paired[field] = dict(postCount=int(post.sum()),
            postDurationSeconds=float(xx[post][-1]-xx[post][0]),
            postLSMsPerMin=float(np.polyfit(xx[post], yy[post], 1)[0]*60))
    result["sparseMatchedDiagnostics"] = paired
    if args.source_presentations_tsv:
        presentations = {int(z["Sequence"]): z for z in read_tsv(args.source_presentations_tsv)}
        delay = np.array([(int(presentations[int(z["Sequence"])]["DwmFlushQpc"])-(args.epoch_qpc+int(z["EncodedQpc"])))/10000 for z in rows])
        result["sourcePresentation"] = dict(flushDelayMedianPreMs=float(np.median(delay[x<x[split]])),
            flushDelayMedianPostMs=float(np.median(delay[x>=x[split]])),
            flushDelayLSMsPerMin=float(np.polyfit(x,delay,1)[0]*60),
            longestRepeatSourceRows=[presentations[runs[0][2]],presentations[runs[0][2]+1]])
    if args.v3_evidence_directory:
        path=args.v3_evidence_directory
        summaries={label:json.loads((path/f"save-{label}-summary.json").read_text(encoding="utf-8-sig")) for label in ["a","b"]}
        pairs={label:{int(z["id"]):z for z in read_tsv(path/f"save-{label}-event-pairs.tsv")} for label in ["a","b"]}
        shared=sorted(pairs["a"].keys() & pairs["b"].keys())
        differences=np.array([float(pairs["b"][k]["rawMs"])-float(pairs["a"][k]["rawMs"]) for k in shared])
        old_piecewise={}
        for label in ["a","b"]:
            values=list(pairs[label].values());xx=np.array([float(z["videoPts"]) for z in values]);yy=np.array([float(z["rawMs"]) for z in values]); options=[]
            for k in range(8,len(xx)-8):
                a=np.polyfit(xx[:k],yy[:k],1);b=np.polyfit(xx[k:],yy[k:],1)
                cost=float(np.sum((yy[:k]-np.polyval(a,xx[:k]))**2)+np.sum((yy[k:]-np.polyval(b,xx[k:]))**2))
                options.append((cost,k,float(a[0]*60),float(b[0]*60)))
            cost,k,a,b=min(options)
            old_piecewise[label]=dict(splitID=int(values[k]["id"]),splitVideoPTS=float(xx[k]),sse=cost,preLSMsPerMin=a,postLSMsPerMin=b)
        result["separateV3Run"]=dict(caveat="Different recording from continuous clock run. Stable later video-clock data cannot erase unresolved earlier progressive A/V trend.",
            rawAV={label:summaries[label]["rawAV"] for label in ["a","b"]}, piecewise=old_piecewise,
            sharedIDs=len(shared),bMinusAMedianMs=float(np.median(differences)),
            bMinusAP95AbsMs=float(np.quantile(np.abs(differences),.95)),bMinusAMaxAbsMs=float(np.max(np.abs(differences))))
    print(json.dumps(result, indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
