#!/usr/bin/env python3
"""Measure the acoustic character of Kliq switch sets.

Prints one row per set (a folder of <code>-down.* / <code>-up.* files) with
medians over its key sounds, so synthesized sets can be compared with any other
set on the same scale. Nothing is written; the audio is only read.

    python3 Tools/analyze_sounds.py SET_DIR [SET_DIR ...]
    python3 Tools/analyze_sounds.py --effects FILE [FILE ...]

Columns (key-down sounds unless noted):
    flat      spectral flatness, 150 Hz-16 kHz, energy-weighted over frames
              (1 = white noise, near 0 = pure tones; also low for coloured noise)
    wflat     whitened flatness: the same, after dividing each 21 ms frame by its
              1-octave smoothed spectrum, so only fine structure counts
              (noise of any colour ~0.5, steady tones near 0)
    cent      spectral centroid of the whole stroke, Hz
    c.late    centroid 15-50 ms after the onset, Hz
    atk       onset (-30 dB) to peak, ms
    t20/t40   onset to the last point of the 2 ms RMS envelope above -20/-40 dB
              of its maximum, ms (t40 is "-" when the noise floor is above -40 dB)
    lo/mid/hi energy share below 700 Hz / 700 Hz-4 kHz / above 4 kHz, %
    crest     peak-to-RMS over the first 50 ms after the onset, dB
    tonal     strongest narrow spectral peak 20-60 ms after the onset, dB above
              the local (+-1/3 octave) median of the averaged spectrum; tones score
              20+ dB, noise around 6-9 dB. "-" if that tail is below -45 dB.
    ev        distinct sub-events in the stroke, median count
    gap       ms between the first two sub-events (median over keys that have 2+)
    d/u       key-down vs key-up loudness (RMS over 50 ms), dB
    peak      median sample peak of down / up files
"""
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import wave

import numpy as np
from scipy.signal import butter, sosfilt, stft

NAME = re.compile(r"^(\d+)-(down|up)$")
AUDIO = {".wav", ".caf", ".aiff", ".aif", ".m4a", ".mp3"}


def load(path):
    """Returns (mono float samples, sample rate). Non-WAV files go through afconvert."""
    path = pathlib.Path(path)
    if path.suffix.lower() == ".wav":
        try:
            return _read_wav(path)
        except wave.Error:
            pass
    with tempfile.TemporaryDirectory() as tmp:
        wav = pathlib.Path(tmp) / "x.wav"
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16", str(path), str(wav)],
                       check=True, capture_output=True)
        return _read_wav(wav)


def _read_wav(path):
    """Minimal RIFF reader: PCM or WAVE_FORMAT_EXTENSIBLE integer PCM, any channel count."""
    data = pathlib.Path(path).read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise wave.Error("not a RIFF/WAVE file")
    pos, fmt, raw = 12, None, None
    while pos + 8 <= len(data):
        cid, size = data[pos:pos + 4], int.from_bytes(data[pos + 4:pos + 8], "little")
        body = data[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            fmt = body
        elif cid == b"data":
            raw = body
        pos += 8 + size + (size & 1)
    if fmt is None or raw is None:
        raise wave.Error("missing fmt or data chunk")
    ch = int.from_bytes(fmt[2:4], "little")
    rate = int.from_bytes(fmt[4:8], "little")
    width = int.from_bytes(fmt[14:16], "little") // 8
    raw = raw[:len(raw) - len(raw) % (width * ch)]
    if width == 2:
        x = np.frombuffer(raw, "<i2").astype(np.float64) / 32768
    elif width == 3:
        b = np.frombuffer(raw, np.uint8).reshape(-1, 3)
        v = (b[:, 0].astype(np.int32) | (b[:, 1].astype(np.int32) << 8) | (b[:, 2].astype(np.int32) << 16))
        x = np.where(v >= 1 << 23, v - (1 << 24), v).astype(np.float64) / (1 << 23)
    elif width == 4:
        x = np.frombuffer(raw, "<i4").astype(np.float64) / (1 << 31)
    else:
        x = (np.frombuffer(raw, np.uint8).astype(np.float64) - 128) / 128
    return x.reshape(-1, ch).mean(axis=1), rate


def envelope(x, rate, win_ms=2.0, hop_ms=0.25):
    win, hop = max(1, int(rate * win_ms / 1000)), max(1, int(rate * hop_ms / 1000))
    p = np.concatenate([x ** 2, np.zeros(win)])
    c = np.concatenate([[0], np.cumsum(p)])
    starts = np.arange(0, len(x), hop)
    return np.sqrt((c[starts + win] - c[starts]) / win), hop / rate


def metrics(x, rate):
    x = x - np.mean(x)
    peak = float(np.max(np.abs(x)))
    if peak < 1e-5:
        return None
    env, dt = envelope(x, rate)
    emax = env.max()
    db = 20 * np.log10(env / emax + 1e-12)
    onset_i = int(np.argmax(db > -30))
    onset = onset_i * dt
    ipk = int(np.argmax(np.abs(x)))
    attack = max(0.0, ipk / rate - onset)
    tail = db[int(len(db) * 0.85):] if len(db) > 40 else db[-4:]
    floor = float(np.median(tail))
    above20 = np.nonzero(db > -20)[0]
    t20 = above20[-1] * dt - onset
    above40 = np.nonzero(db > -40)[0]
    t40 = above40[-1] * dt - onset if floor < -44 else np.nan

    o = int(onset * rate)
    seg = np.zeros(int(0.05 * rate))
    part = x[o:o + len(seg)]
    seg[:len(part)] = part
    rms50 = float(np.sqrt(np.mean(seg ** 2)))
    crest = 20 * np.log10(peak / max(rms50, 1e-12))

    nper = 256 if rate < 46000 else 256
    stroke = x[max(0, o - int(0.002 * rate)):o + int(0.12 * rate)]
    f, t, Z = stft(stroke, rate, nperseg=nper, noverlap=nper * 3 // 4, boundary=None, padded=True)
    P = np.abs(Z) ** 2 + 1e-20
    band = (f >= 150) & (f <= 16000)
    fe = P[band].sum(axis=0)
    flat_frames = np.exp(np.mean(np.log(P[band]), axis=0)) / np.mean(P[band], axis=0)
    flat = float(np.sum(flat_frames * fe) / np.sum(fe))
    # Whitened flatness: each frame divided by its own 1-octave smoothed spectrum, so
    # spectral tilt and broad coloration do not count, only fine structure. Noise of
    # any colour scores ~0.5 (Hann-windowed periodogram), steady tones score low.
    # 1024-point frames (~21 ms) so low tones are resolved; one frame spans a whole event.
    f2, _, Z2 = stft(stroke, rate, nperseg=1024, noverlap=768, boundary=None, padded=True)
    P2 = np.abs(Z2) ** 2 + 1e-20
    wb = (f2 >= 100) & (f2 <= 8000)
    Pw = P2[wb]
    fw = f2[wb]
    smooth = np.empty_like(Pw)
    for i, fc in enumerate(fw):
        nb = (fw >= fc / np.sqrt(2)) & (fw <= fc * np.sqrt(2))
        smooth[i] = Pw[nb].mean(axis=0)
    W = Pw / smooth
    wf_frames = np.exp(np.mean(np.log(W), axis=0)) / np.mean(W, axis=0)
    we = Pw.sum(axis=0)
    wflat = float(np.sum(wf_frames * we) / np.sum(we))
    S = P.sum(axis=1)
    audible = f >= 40
    cent = float(np.sum(f[audible] * S[audible]) / np.sum(S[audible]))
    tot = S[audible].sum()
    lo = S[(f >= 40) & (f < 700)].sum() / tot
    mid = S[(f >= 700) & (f < 4000)].sum() / tot
    hi = S[f >= 4000].sum() / tot
    tt = t - 0.002
    late = (tt >= 0.015) & (tt <= 0.05)
    Sl = P[:, late].sum(axis=1) if late.any() else S * 0
    c_late = float(np.sum(f[audible] * Sl[audible]) / max(np.sum(Sl[audible]), 1e-20)) if late.any() else np.nan

    tonal = tonal_peak(x, rate, o, emax)
    events, gap = sub_events(x, rate, o)
    return dict(flat=flat, wflat=wflat, cent=cent, c_late=c_late, atk=attack * 1000, t20=t20 * 1000,
                t40=t40 * 1000, lo=lo * 100, mid=mid * 100, hi=hi * 100, crest=crest,
                tonal=tonal, ev=events, gap=gap, rms=rms50, peak=peak)


def tonal_peak(x, rate, o, emax):
    """Prominence (dB) of the strongest narrow peak in the 20-60 ms tail spectrum."""
    a, b = o + int(0.020 * rate), o + int(0.060 * rate)
    tail = x[a:b]
    if len(tail) < int(0.03 * rate):
        return np.nan
    if np.sqrt(np.mean(tail ** 2)) < emax * 10 ** (-45 / 20):
        return np.nan
    nper = 1024 if rate > 46000 else 1024
    f, _, Z = stft(tail, rate, nperseg=nper, noverlap=nper * 7 // 8, boundary=None, padded=True)
    P = (np.abs(Z) ** 2).mean(axis=1) + 1e-20
    L = 10 * np.log10(P)
    best = 0.0
    for i in range(len(f)):
        if f[i] < 120 or f[i] > 12000:
            continue
        lo_f, hi_f = f[i] / 2 ** (1 / 3), f[i] * 2 ** (1 / 3)
        nb = (f >= lo_f) & (f <= hi_f)
        if nb.sum() < 5:
            nb = np.zeros_like(nb)
            nb[max(0, i - 4):i + 5] = True
        best = max(best, L[i] - np.median(L[nb]))
    return best


def sub_events(x, rate, o):
    """Counts distinct attacks in the stroke from the >1 kHz energy in 0.5 ms frames."""
    sos = butter(4, 1000, "highpass", fs=rate, output="sos")
    h = sosfilt(sos, x[max(0, o - int(0.003 * rate)):o + int(0.10 * rate)])
    env, dt = envelope(h, rate, win_ms=0.5, hop_ms=0.25)
    db = 20 * np.log10(env / (env.max() + 1e-12) + 1e-9)
    peaks = []
    back = int(0.0015 / dt)
    for i in range(1, len(db) - 1):
        if db[i] < -22 or db[i] < db[i - 1] or db[i] < db[i + 1]:
            continue
        if db[i] - db[max(0, i - back):i].min(initial=db[i]) < 5:
            continue
        if peaks and (i - peaks[-1]) * dt < 0.002:
            if db[i] > db[peaks[-1]]:
                peaks[-1] = i
            continue
        peaks.append(i)
    gap = (peaks[1] - peaks[0]) * dt * 1000 if len(peaks) > 1 else np.nan
    return len(peaks), gap


def analyze_set(folder):
    folder = pathlib.Path(folder)
    files = {}
    for p in folder.iterdir():
        m = NAME.match(p.stem)
        if m and p.suffix.lower() in AUDIO:
            files[(int(m.group(1)), m.group(2))] = p
    down, up, ratio = [], [], []
    for (code, kind), p in sorted(files.items()):
        if kind != "down":
            continue
        x, r = load(p)
        md = metrics(x, r)
        if md is None:
            continue
        down.append(md)
        if (code, "up") in files:
            y, ry = load(files[(code, "up")])
            mu = metrics(y, ry)
            if mu is not None:
                up.append(mu)
                ratio.append(20 * np.log10(md["rms"] / mu["rms"]))
    return down, up, ratio


def med(rows, key):
    v = np.array([r[key] for r in rows], dtype=float)
    v = v[~np.isnan(v)]
    return float(np.median(v)) if len(v) else np.nan


COLS = [("flat", "{:.3f}"), ("wflat", "{:.3f}"), ("cent", "{:.0f}"), ("c_late", "{:.0f}"), ("atk", "{:.1f}"),
        ("t20", "{:.1f}"), ("t40", "{:.1f}"), ("lo", "{:.0f}"), ("mid", "{:.0f}"),
        ("hi", "{:.0f}"), ("crest", "{:.1f}"), ("tonal", "{:.1f}"), ("ev", "{:.0f}"),
        ("gap", "{:.1f}")]


def fmt(v, f):
    return "-" if v is None or (isinstance(v, float) and np.isnan(v)) else f.format(v)


def header(first="set"):
    names = [c for c, _ in COLS] + ["d/u", "peak"]
    return f"{first:<22}" + "".join(f"{n:>8}" for n in names)


def row(label, down, up, ratio):
    cells = [fmt(med(down, c), f) for c, f in COLS]
    cells.append(fmt(float(np.median(ratio)) if ratio else np.nan, "{:+.1f}"))
    cells.append(f"{med(down, 'peak'):.2f}/{med(up, 'peak'):.2f}" if up else f"{med(down, 'peak'):.2f}")
    return f"{label[:22]:<22}" + "".join(f"{c:>8}" for c in cells)


def up_row(label, up):
    cells = [fmt(med(up, c), f) for c, f in COLS]
    return f"{(label + ' up')[:22]:<22}" + "".join(f"{c:>8}" for c in cells)


def main(argv):
    if not argv:
        print(__doc__)
        return
    if argv[0] == "--effects":
        print(header("file"))
        for p in argv[1:]:
            x, r = load(p)
            m = metrics(x, r)
            print(row(pathlib.Path(p).stem, [m], [], []))
        return
    show_up = "--up" in argv
    argv = [a for a in argv if a != "--up"]
    print(header())
    ups = []
    for d in argv:
        down, up, ratio = analyze_set(d)
        label = os.path.basename(os.path.normpath(d))
        print(row(label, down, up, ratio), flush=True)
        ups.append((label, up))
    if show_up:
        print()
        print(header("key-up"))
        for label, up in ups:
            print(up_row(label, up))


if __name__ == "__main__":
    main(sys.argv[1:])
