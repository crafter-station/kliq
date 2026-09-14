#!/usr/bin/env python3
"""Turn a keyboard recording into a Kliq switch set.

Two ways in:

    typing   one recording of free typing, like a switch sound test. Strokes are
             found, scored for how cleanly they stand apart from their neighbours,
             and sorted into presses, releases and stabilized-key presses by level
             and spectrum. Only the cleanest ones are kept.
    guided   recordings made for this: press a key, hold it about a third of a
             second, let go, wait half a second, and repeat. One file for the normal
             keys (any keys, 20 to 60 presses), and optionally one each for space,
             return, backspace, shift and the modifiers. Presses and releases
             alternate, so nothing has to be guessed and every tail rings out.

Either way each kept stroke starts 0.2 ms before its hit and ends once its tail has
faded 45 dB, with short fades. Strokes are levelled most of the way toward their
group's median, every group of presses is matched to the normal keys' presses, and
releases are lifted to 4 dB under them (--release-level; --natural-balance keeps the
recording's balance instead). One shared gain puts presses where the bundled sets'
presses sit, and the strokes are dealt out over every scan code Kliq knows. Files are
mono Apple Lossless .caf, written by gen_sounds.write_sample.

--match REFERENCE measures the octave-band balance of another typing recording's
presses (seven numbers) and EQs the set toward it. No audio from the reference ends
up in the set.

The set goes to ~/Library/Application Support/Kliq/Sounds/<name>, which Kliq loads
on launch and never bundles. Only sets you recorded yourself, or have permission to
redistribute, may go into Resources/Sounds. Every set gets CREDITS.txt (the source
files, plus --credit) and slices.json (where each file was cut from).

Usage:
    python3 Tools/slice_recording.py typing test.wav --name "My Board" [--credit TEXT]
    python3 Tools/slice_recording.py guided --keys keys.m4a [--space space.m4a]
        [--enter ...] [--backspace ...] [--shift ...] [--mods ...] --name "My Board"
Options: --out DIR instead of the Application Support folder, --match REFERENCE,
--audition WAV to write every kept stroke in a row and check the sorting by ear.
Requires numpy, scipy, and ffmpeg or afconvert to read the input.
"""
import argparse
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, find_peaks, sosfilt, sosfiltfilt

from gen_sounds import EXTRA, RATE, ROWS, key_class, remove_audio, rng_for, write_sample

USER_SETS = pathlib.Path.home() / "Library" / "Application Support" / "Kliq" / "Sounds"
MS = RATE // 1000                   # samples per millisecond
PRESS_RMS = -24.0                   # dBFS over a press's first 30 ms, where the bundled presses sit
CEILING = 10 ** (-1 / 20)           # no sample peaks above -1 dBFS
LEVELING = 0.9                      # share of each stroke's distance from its group's median taken out
BALANCE_LIMIT = 12                  # dB, most a group is moved to match the presses
FADE_BELOW = 45                     # a sample ends once it has faded this many dB under its peak
PREROLL = MS // 5                   # samples kept before the hit (0.2 ms)
# Typing mode keeps the strictest tier that still yields enough strokes. Per tier: how loud
# the previous stroke may still be under this one (dB), how long until the next stroke
# starts (ms), and how far this one must have faded by then (dB).
TIERS = [(-25, 80, -30), (-20, 60, -24), (-15, 50, -20), (-12, 40, -15)]
WANT = {"press": 48, "release": 16, "big": 4}
MARGIN = 0.7                        # a press or release is kept if this much nearer its group than the other
# Kept level range around each group's median (dB below, dB above). The quietest "presses"
# and the loudest "releases" are where the two get mixed up, so those sides are tighter.
BOUNDS = {"press": (4, 6), "release": (6, 4), "big": (6, 6)}
LONGEST = {"press": 250, "release": 150, "big": 300}       # ms
OCTAVES = [125, 250, 500, 1000, 2000, 4000, 8000]          # Hz, for --match
MATCH_LIMIT = 12                                           # dB, most --match may boost or cut a band
GUIDED = ("keys", "mods", "space", "enter", "backspace", "shift")
# Where each stabilized key takes its strokes from: the first of these recordings that exists.
BIG_FROM = {57: ["space"], 28: ["enter", "space"], 3612: ["enter", "space"],
            14: ["backspace", "enter", "space"],
            42: ["shift", "backspace", "enter", "space"], 54: ["shift", "backspace", "enter", "space"]}


def load(path):
    """Any audio file as 48 kHz mono float, rumble below 40 Hz removed."""
    with tempfile.TemporaryDirectory() as tmp:
        wav = pathlib.Path(tmp) / "in.wav"
        if shutil.which("ffmpeg"):
            cmd = ["ffmpeg", "-v", "error", "-y", "-i", str(path), "-ar", str(RATE), "-c:a", "pcm_f32le", str(wav)]
        else:
            cmd = ["afconvert", "-f", "WAVE", "-d", f"LEF32@{RATE}", str(path), str(wav)]
        subprocess.run(cmd, check=True)
        _, y = wavfile.read(wav)
    if np.issubdtype(y.dtype, np.integer):
        y = y / float(np.iinfo(y.dtype).max)
    y = y.astype(np.float64)
    if y.ndim > 1:
        y = y.mean(axis=1)
    return sosfiltfilt(butter(2, 40, "highpass", fs=RATE, output="sos"), y)


def envelope(y):
    """RMS level per millisecond, dB."""
    n = len(y) // MS
    return 20 * np.log10(np.sqrt(np.mean(y[:n * MS].reshape(n, MS) ** 2, axis=1)) + 1e-9)


def head_db(seg):
    """RMS level of a sample's first 30 ms, dB."""
    return 20 * np.log10(np.sqrt(np.mean(seg[:30 * MS] ** 2)) + 1e-12)


def find_strokes(y, min_gap):
    """Start sample of every stroke: a sharp rise of high-passed energy (10 dB within 3 ms,
    ending 15 dB over the quiet parts), pinned to the first sample reaching a tenth of the
    stroke's peak and walked back over any faint lead-in (a fingertip meeting the keycap)
    that stays 6 dB over the level before it, up to 15 ms. Then pinned to the first sample
    standing clear of what came before, within 2 ms, less PREROLL. Rises closer than
    `min_gap` ms count as one stroke."""
    hp = sosfiltfilt(butter(4, 300, "highpass", fs=RATE, output="sos"), y)
    env, full = envelope(hp), envelope(y)
    floor = np.percentile(env, 10)
    rise = env - np.concatenate([np.full(3, env[0]), env[:-3]])
    peaks, _ = find_peaks(rise, height=10, distance=min_gap)
    starts = []
    for p in peaks:
        if env[min(p + 3, len(env) - 1)] < floor + 15:
            continue
        lo = max(0, (p - 5) * MS)
        a = np.abs(y[lo:(p + 6) * MS])
        t10 = lo + int(np.argmax(a >= 0.1 * a.max()))
        k = t10 // MS
        reach = min(15, (k - starts[-1] // MS) // 2) if starts else 15
        bed = full[max(0, k - reach - 10):max(1, k - reach)].min()
        j = k
        while j > max(0, k - reach) and full[j - 1] > bed + 6:
            j -= 1
        s = j * MS if j < k else t10
        before = y[max(0, s - 8 * MS):max(1, s - 3 * MS)]
        clear = max(0.01 * a.max(), 4 * np.sqrt(np.mean(before ** 2)))
        w = np.abs(y[max(0, s - 2 * MS):s + 1]) >= clear
        if w.any():
            s = max(0, s - 2 * MS) + int(np.argmax(w))
        s = max(0, s - PREROLL)
        if not starts or s - starts[-1] >= min_gap * MS // 2:
            starts.append(s)
    return starts


def describe(y, starts):
    """Per stroke: where it can be cut, its level, how cleanly it stands apart from its
    neighbours, and a few spectral features for telling presses from releases."""
    env = envelope(y)
    f = np.fft.rfftfreq(4096, 1 / RATE)
    strokes = []
    for i, s in enumerate(starts):
        last = i + 1 == len(starts)
        end = len(y) if last else starts[i + 1]
        a, b = s // MS, min(end // MS, len(env) - 1)
        # The peak can come up to 15 ms after a lead-in, so look 30 ms ahead (not past the
        # next stroke) and take the spectrum and decay from the peak, not from the start.
        head = env[a:max(a + 1, min(a + 30, b))]
        pk, at = float(head.max()), a + int(head.argmax())
        window = (end - s) / MS
        w0 = max(s, (at - 2) * MS)
        w = y[w0:w0 + int(min(20, max(8, (end - w0) / MS)) * MS)]
        spec = np.abs(np.fft.rfft(w * np.hanning(len(w)), 4096)) ** 2
        total = spec.sum() + 1e-18
        strokes.append(dict(
            start=s, end=end, pk=pk, window=window,
            bleed=float(env[a - 4:a].max()) - pk if a >= 4 else -99.0,
            cut=-99.0 if last else float(env[max(at, b - 1)]) - pk,
            cen=float((f * spec).sum() / total),
            low=float(10 * np.log10(spec[f < 600].sum() / total + 1e-12)),
            high=float(10 * np.log10(spec[f > 3000].sum() / total + 1e-12)),
            slope=float(env[min(at + 8, len(env) - 1)]) - pk if end // MS - at >= 10 else np.nan))
    return strokes


def kmeans(Z, k, tries=8, iters=100):
    """Cluster labels for the rows of Z, best of `tries` seeded starts."""
    best = None
    for seed in range(tries):
        c = Z[np.random.default_rng(seed).choice(len(Z), k, replace=False)]
        for _ in range(iters):
            lab = np.argmin(((Z[:, None] - c[None]) ** 2).sum(-1), axis=1)
            c = np.array([Z[lab == j].mean(0) if np.any(lab == j) else c[j] for j in range(k)])
        inertia = ((Z - c[lab]) ** 2).sum()
        if best is None or inertia < best[0]:
            best = (inertia, lab)
    return best[1]


def sort_typing(strokes):
    """Presses, releases and stabilized-key presses of a free-typing recording: three clusters
    on level, centroid, low and high share and early decay. The loudest cluster is the presses,
    the brighter of the other two the releases. Loud strokes much darker than the median press
    are taken as stabilized keys."""
    X = np.array([[s["pk"], np.log2(max(s["cen"], 100)), s["low"], s["high"], s["slope"]] for s in strokes])
    rows = np.flatnonzero(~np.isnan(X).any(axis=1))
    Z = (X[rows] - X[rows].mean(0)) / (X[rows].std(0) + 1e-9)
    lab = kmeans(Z, 3)
    order = sorted(range(3), key=lambda j: -X[rows[lab == j], 0].mean())
    p = order[0]
    r = max(order[1:], key=lambda j: X[rows[lab == j], 1].mean())
    centres = np.array([Z[lab == j].mean(0) for j in range(3)])
    dist = np.linalg.norm(Z[:, None] - centres[None], axis=2)
    # Only strokes clearly nearer their own group than the other: the in-between ones are
    # where presses and releases get mixed up.
    press = rows[(lab == p) & (dist[:, p] <= MARGIN * dist[:, r])]
    release = rows[(lab == r) & (dist[:, r] <= MARGIN * dist[:, p])]
    level, tone = np.median(X[press, 0]), np.median(X[press, 1])
    big = {int(i) for i in rows if X[i, 0] > level - 4 and X[i, 1] < tone + np.log2(0.7)}
    return {"press": [int(i) for i in press if i not in big], "release": [int(i) for i in release],
            "big": sorted(big)}


def drop_outliers(strokes, idx, below=6, above=6):
    """Leaves out strokes more than `below` dB quieter or `above` dB louder than their group's median."""
    if len(idx) < 4:
        return idx
    med = np.median([strokes[i]["pk"] for i in idx])
    return [i for i in idx if -below <= strokes[i]["pk"] - med <= above]


def pick_clean(strokes, idx, want, below, above):
    """The strokes of a group that stand apart best, at the strictest tier that yields `want`."""
    for tier in TIERS:
        bleed, window, cut = tier
        chosen = [i for i in idx if strokes[i]["bleed"] < bleed and strokes[i]["window"] >= window
                  and strokes[i]["cut"] < cut]
        if len(chosen) >= want:
            break
    return drop_outliers(strokes, chosen, below, above), tier


def fade_out(seg, length):
    """Raised-cosine fade over the last `length` samples."""
    n = min(len(seg), length)
    seg[len(seg) - n:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, n))
    return seg


def cut(y, stroke, longest, floor):
    """A stroke as a sample: up to the next stroke or `longest` ms, ending early once it has
    faded FADE_BELOW dB under its peak or reached the noise floor (then a 4 ms fade; a stroke
    cut short by the next one fades over its last fifth). Fades in over the pre-roll."""
    seg = y[stroke["start"]:min(stroke["end"] - MS // 2, stroke["start"] + longest * MS)].copy()
    env = envelope(seg)
    quiet = np.flatnonzero(env[10:] < max(env[:30].max() - FADE_BELOW, floor + 3))
    fade = max(6 * MS, len(seg) // 5)
    if len(quiet):
        seg = seg[:(quiet[0] + 10) * MS]
        fade = 4 * MS
    seg[:PREROLL] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, PREROLL))
    return fade_out(seg, fade)


def shape_of(segs):
    """Median octave-band balance of strokes over 25 ms from their peak, dB re the loudest band."""
    f = np.fft.rfftfreq(4096, 1 / RATE)
    bands = [(f >= c / 2 ** 0.5) & (f < c * 2 ** 0.5) for c in OCTAVES]
    shapes = []
    for seg in segs:
        w0 = max(0, int(np.argmax(np.abs(seg[:30 * MS]))) - 2 * MS)
        w = seg[w0:w0 + 25 * MS]
        if len(w) < 8 * MS:
            continue
        spec = np.abs(np.fft.rfft(w * np.hanning(len(w)), 4096)) ** 2
        b = 10 * np.log10(np.array([spec[band].sum() for band in bands]) + 1e-18)
        shapes.append(b - b.max())
    return np.median(shapes, axis=0)


def peaking(fc, gain_db, q=2 ** 0.5):
    """Peaking-EQ biquad (one octave wide at the default q) as one sos row."""
    A, w = 10 ** (gain_db / 40), 2 * np.pi * fc / RATE
    alpha = np.sin(w) / (2 * q)
    b = np.array([1 + alpha * A, -2 * np.cos(w), 1 - alpha * A])
    a = np.array([1 + alpha / A, -2 * np.cos(w), 1 - alpha / A])
    return np.concatenate([b, a]) / a[0]


def match_tone(pools, reference):
    """EQs every sample so the presses' median octave balance moves toward the presses of
    `reference`, a typing recording. Only that balance is taken from it, none of its audio."""
    y = load(reference)
    strokes = describe(y, find_strokes(y, min_gap=12))
    target = shape_of([y[strokes[i]["start"]:strokes[i]["end"]] for i in sort_typing(strokes)["press"]
                       if strokes[i]["window"] >= 20])
    segs = [seg for seg, _, _ in pools[("keys", "down")]]
    before, gains = shape_of(segs), np.zeros(len(OCTAVES))
    for _ in range(5):
        sos = np.array([peaking(fc, g) for fc, g in zip(OCTAVES, gains)])
        gains += 0.8 * (target - shape_of([sosfilt(sos, s) for s in segs]))
        gains = np.clip(gains - gains.mean(), -MATCH_LIMIT, MATCH_LIMIT)
    sos = np.array([peaking(fc, g) for fc, g in zip(OCTAVES, gains)])
    after = shape_of([sosfilt(sos, s) for s in segs])
    for key, pool in pools.items():
        pools[key] = [(fade_out(sosfilt(sos, seg), 6 * MS), src, at) for seg, src, at in pool]
    rms = lambda d: float(np.sqrt(np.mean(d ** 2)))
    print("tone match EQ: " + "  ".join(f"{fc}:{g:+.1f}" for fc, g in zip(OCTAVES, gains)) +
          f" dB; distance to {pathlib.Path(reference).name} {rms(before - target):.1f} -> {rms(after - target):.1f} dB")


def source_for(code, direction, pools):
    """The pool a key's sample comes from: its own recording when there is one, else the normal keys."""
    kinds = {"big": BIG_FROM.get(code, []) + ["big"], "mod": ["mods"]}.get(key_class(code), [])
    return next((k for k in kinds if (k, direction) in pools), "keys")


def build(pools, args, sources):
    """Levels the pools, deals them out over every scan code and writes the set."""
    if args.match:
        match_tone(pools, args.match)
    for key, pool in pools.items():
        levels = [head_db(seg) for seg, _, _ in pool]
        med = np.median(levels)
        pools[key] = [(seg * 10 ** (LEVELING * (med - lv) / 20), src, at) for (seg, src, at), lv in zip(pool, levels)]
    press = np.median([head_db(seg) for seg, _, _ in pools[("keys", "down")]])
    if not args.natural_balance:
        # Every group of presses at the normal presses' level; releases lifted (never
        # lowered) to --release-level under them.
        for (kind, direction), pool in pools.items():
            if (kind, direction) == ("keys", "down"):
                continue
            med = np.median([head_db(seg) for seg, _, _ in pool])
            shift = press - med if direction == "down" else max(0.0, press + args.release_level - med)
            shift = float(np.clip(shift, -BALANCE_LIMIT, BALANCE_LIMIT))
            pools[(kind, direction)] = [(seg * 10 ** (shift / 20), src, at) for seg, src, at in pool]
            print(f"balance: {kind} {direction} {shift:+.1f} dB")
    gain = 10 ** ((PRESS_RMS - press) / 20)
    limited = 0
    for key, pool in pools.items():
        leveled = []
        for seg, src, at in pool:
            seg = seg * gain
            peak = np.abs(seg).max()
            if peak > CEILING:
                seg *= CEILING / peak
                limited += 1
            leveled.append((seg, src, at))
        pools[key] = leveled

    codes = sorted({c for row in ROWS for c in row} | set(EXTRA))
    chosen = {}
    for direction in ("down", "up"):
        if ("keys", direction) not in pools:
            print(f"warning: no clean {direction} strokes, so keys will be silent on key {direction}")
            continue
        by_kind = {}
        for code in codes:
            by_kind.setdefault(source_for(code, direction, pools), []).append(code)
        for kind, group in by_kind.items():
            pool = pools[(kind, direction)]
            order = rng_for(args.name, kind, direction).permutation(len(pool))
            for k, code in enumerate(group):
                chosen[f"{code}-{direction}"] = pool[order[k % len(pool)]]

    folder = args.out / args.name
    folder.mkdir(parents=True, exist_ok=True)
    remove_audio(folder)
    for stem, (seg, _, _) in chosen.items():
        write_sample(folder / stem, seg)
    manifest = {stem: {"source": src, "at": round(at / RATE, 4)} for stem, (_, src, at) in sorted(chosen.items())}
    (folder / "slices.json").write_text(json.dumps(manifest, indent=1))
    credits = f"{args.name}\n\nCut from: {', '.join(sources)}\n" + (f"\n{args.credit}\n" if args.credit else "")
    (folder / "CREDITS.txt").write_text(credits)

    if args.audition:
        gap, pause, parts = np.zeros(int(0.25 * RATE)), np.zeros(int(0.8 * RATE)), []
        for (kind, direction), pool in pools.items():
            print(f"audition: {kind} {direction}, {len(pool)} strokes")
            parts.append(pause)
            for seg, _, _ in pool:
                parts += [seg, gap]
        wavfile.write(args.audition, RATE, (np.clip(np.concatenate(parts), -1, 1) * 32767).astype(np.int16))

    lengths = [len(seg) / MS for seg, _, _ in chosen.values()]
    distinct = sum(len(p) for p in pools.values())
    print(f"wrote {len(chosen)} files from {distinct} distinct strokes to {folder}")
    print(f"sample length median {np.median(lengths):.0f} ms (range {min(lengths):.0f}-{max(lengths):.0f});"
          f" shared gain {20 * np.log10(gain):+.1f} dB; {limited} strokes held under -1 dBFS")
    print("Relaunch Kliq to load the set.")


def typing(args):
    y = load(args.recording)
    floor = np.percentile(envelope(y), 10)
    strokes = describe(y, find_strokes(y, min_gap=12))
    groups = sort_typing(strokes)
    print(f"{len(strokes)} strokes in {len(y) / RATE:.1f} s")
    src, pools = args.recording.name, {}
    for group, kind, direction in (("press", "keys", "down"), ("release", "keys", "up"), ("big", "big", "down")):
        chosen, (bleed, window, faded) = pick_clean(strokes, groups[group], WANT[group], *BOUNDS[group])
        print(f"{group}: {len(groups[group])} strokes, {len(chosen)} kept "
              f"(bleed under {bleed} dB, {window} ms clear, faded {faded} dB by the next stroke)")
        if len(chosen) >= (3 if group == "big" else 1):
            pools[(kind, direction)] = [(cut(y, strokes[i], LONGEST[group], floor), src, strokes[i]["start"])
                                        for i in chosen]
    if ("keys", "down") not in pools:
        sys.exit("no clean presses found; try a guided recording")
    build(pools, args, [src])


def guided(args):
    pools, sources = {}, []
    for kind in GUIDED:
        path = getattr(args, kind)
        if not path:
            continue
        y = load(path)
        floor = np.percentile(envelope(y), 10)
        strokes = describe(y, find_strokes(y, min_gap=60))
        downs, ups, i = [], [], 0
        while i + 1 < len(strokes):
            if 40 * MS <= strokes[i + 1]["start"] - strokes[i]["start"] <= 2000 * MS:
                downs.append(i)
                ups.append(i + 1)
                i += 2
            else:
                print(f"  {path.name}: no release after the stroke at {strokes[i]['start'] / RATE:.2f} s, skipped")
                i += 1
        downs, ups = drop_outliers(strokes, downs), drop_outliers(strokes, ups)
        longest = LONGEST["big"] if kind in ("space", "enter", "backspace", "shift") else LONGEST["press"]
        pools[(kind, "down")] = [(cut(y, strokes[i], longest, floor), path.name, strokes[i]["start"]) for i in downs]
        pools[(kind, "up")] = [(cut(y, strokes[i], LONGEST["release"], floor), path.name, strokes[i]["start"]) for i in ups]
        sources.append(path.name)
        print(f"{kind}: {len(downs)} presses, {len(ups)} releases from {path.name}")
    if not pools.get(("keys", "down")):
        sys.exit("no presses found in --keys")
    build(pools, args, sources)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="mode", required=True)
    t = sub.add_parser("typing", help="one recording of free typing, such as a switch sound test")
    t.add_argument("recording", type=pathlib.Path)
    g = sub.add_parser("guided", help="slow press-and-release recordings, one per key group")
    g.add_argument("--keys", type=pathlib.Path, required=True, help="normal keys")
    for kind in GUIDED[1:]:
        g.add_argument(f"--{kind}", type=pathlib.Path)
    for p in (t, g):
        p.add_argument("--name", required=True, help="set name, as shown in Kliq")
        p.add_argument("--credit", help="credit line written to CREDITS.txt")
        p.add_argument("--out", type=pathlib.Path, default=USER_SETS, help="parent folder of the set")
        p.add_argument("--match", type=pathlib.Path,
                       help="typing recording whose tonal balance to EQ toward (none of its audio is used)")
        p.add_argument("--audition", type=pathlib.Path, help="WAV with every kept stroke in a row")
        p.add_argument("--release-level", type=float, default=-4.0,
                       help="dB under the presses that releases are lifted to (default -4)")
        p.add_argument("--natural-balance", action="store_true",
                       help="keep the recording's balance between presses, releases and key groups")
    args = parser.parse_args()
    typing(args) if args.mode == "typing" else guided(args)


if __name__ == "__main__":
    main()
