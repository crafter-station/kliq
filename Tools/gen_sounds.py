#!/usr/bin/env python3
"""Generate Kliq's built-in synthetic switch sound sets.

Each set is a folder of <code>-down.caf / <code>-up.caf files where <code> is a
PC scan code (set 1), as mapped by Kliq's KeyMapper:

    2-11 number row     16-25 qwertyuiop     30-38 asdfghjkl     44-50 zxcvbnm
    14 backspace  15 tab  28 return  41 backtick  42/54 shifts  57 space  58 caps
    29 ctrl  56/3640 option  3675/3676 command  57416/57419/57421/57424 arrows
    1 esc  59-68 F1-F10  87/88 F11-F12

Sound design by Cris. Every sound is synthesized from scratch. Nothing here is
a recording.

Model: a key stroke is a few impact events a few milliseconds apart, and each
event is a sum of band-passed white-noise bursts, each with its own gain,
attack and exponential decay (a noise-band impact model).

    key down   stem/leaf tick    very short, 3-10 kHz
               bottom-out        keycap on plate, broadband around 1-4 kHz, 2-10 ms
               case / plate      low band 150-700 Hz, 15-40 ms, the "thock"
    key up     top-out           shorter, lighter and higher than bottom-out

No sine oscillators and no high-Q resonators are used for key sounds, so
nothing rings at a pitch. Per-key variation comes from deterministic seeds:
small jitter in band gains, centre frequencies, decays and event timing, plus
a gentle trend across the board. Stabilized keys are bigger and lower, with a
second hit from the far end of the bar and a faint wire rattle.

Files are mono Apple Lossless (48 kHz, 16-bit) in a CAF container. The app
duplicates mono to both channels and pans each key itself, so stereo files would
only double the size. Encoding uses macOS's afconvert. Requires numpy and scipy.

Usage: python3 gen_sounds.py [output-dir] [--wav]    (default: Resources/Sounds)
       --wav writes plain 16-bit WAV files instead, for quick analysis runs.
"""
import functools
import hashlib
import pathlib
import subprocess
import sys
import wave

import numpy as np
from scipy.signal import butter, sosfilt

RATE = 48_000
AUDIO_SUFFIXES = {".wav", ".caf", ".aiff", ".aif", ".m4a", ".mp3"}

# Physical layout by scan code, mirrors KeyMapper.rows.
ROWS = [
    [1, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 87, 88],
    [41, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14],
    [15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 43],
    [58, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 28],
    [42, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54],
    [29, 56, 3675, 57, 3676, 3640, 57419, 57416, 57424, 57421],
]
EXTRA = [3613, 3612, 3637, 3655, 3657, 3663, 3665, 3666, 3667,
         55, 69, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 91, 92, 93]

# Stabilized keys: size multiplier (lower, longer, second hit and wire rattle).
BIG = {14: 1.22, 28: 1.28, 42: 1.25, 54: 1.28, 57: 1.5, 3612: 1.18}
MEDIUM = {15, 58, 29, 56, 3640, 3675, 3676, 3613}  # 1.25-1.75u keys, slightly larger
ROW_TONE = [1.06, 1.03, 1.0, 0.98, 0.97, 0.95]     # far rows a touch brighter

# A band is (centre Hz, width in octaves, gain, attack ms, decay tau ms).
# Gains are amplitudes of unit-RMS noise bands. Events start at "at" ms.
# The 0.3-octave bands are the keycap and plate modes: narrow enough to give each
# set its colour, damped within a few ms so they never ring as a pitch.
KINDS = {
    "Synth Thock": dict(
        down=dict(
            leaf=dict(at=0.0, bands=[(5200, 1.2, 0.10, 0.08, 0.45)]),
            bottom=dict(at=2.4, bands=[(1150, 1.3, 1.00, 0.35, 2.4),
                                       (2200, 1.0, 0.45, 0.20, 1.3),
                                       (3900, 1.0, 0.14, 0.10, 0.7),
                                       (620, 0.3, 0.35, 0.30, 4.5),
                                       (1380, 0.3, 0.30, 0.25, 3.0),
                                       (2350, 0.3, 0.15, 0.15, 2.0)]),
            case=dict(at=2.7, bands=[(720, 0.9, 0.30, 0.6, 5.0),
                                     (430, 1.0, 0.28, 0.9, 7.5),
                                     (240, 0.9, 0.16, 1.4, 11.0)]),
        ),
        up=dict(
            top=dict(at=0.0, bands=[(1700, 1.2, 1.00, 0.25, 1.8),
                                    (3200, 1.0, 0.38, 0.12, 0.9),
                                    (1450, 0.3, 0.30, 0.20, 2.5),
                                    (2600, 0.3, 0.15, 0.10, 1.6)]),
            case=dict(at=0.4, bands=[(580, 1.0, 0.24, 0.6, 4.5),
                                     (310, 0.9, 0.11, 1.0, 7.0)]),
        ),
        tail=(1000, 2.0, 0.035, 1.0, 15.0), lowpass=5200, bounce=0.35, drive=1.3,
    ),
    "Synth Clack": dict(
        down=dict(
            leaf=dict(at=0.0, bands=[(6200, 1.4, 0.75, 0.05, 0.45),
                                     (3600, 0.9, 0.35, 0.06, 0.6)]),
            bottom=dict(at=3.8, bands=[(2800, 1.2, 1.00, 0.15, 1.7),
                                       (4500, 1.0, 0.50, 0.10, 1.0),
                                       (1500, 1.0, 0.36, 0.25, 2.2),
                                       (7600, 1.0, 0.22, 0.05, 0.5),
                                       (1900, 0.3, 0.35, 0.15, 2.8),
                                       (3150, 0.3, 0.30, 0.10, 2.0),
                                       (4800, 0.3, 0.15, 0.08, 1.4)]),
            case=dict(at=4.0, bands=[(650, 1.0, 0.14, 0.6, 4.5),
                                     (340, 1.0, 0.06, 1.0, 7.0)]),
        ),
        up=dict(
            top=dict(at=0.0, bands=[(3300, 1.2, 1.00, 0.10, 1.2),
                                    (5600, 1.0, 0.45, 0.05, 0.6),
                                    (1900, 1.0, 0.28, 0.20, 1.8),
                                    (2300, 0.3, 0.30, 0.10, 2.0),
                                    (3700, 0.3, 0.15, 0.08, 1.4)]),
            leaf=dict(at=2.2, bands=[(5200, 1.2, 0.35, 0.05, 0.45)]),
            case=dict(at=0.3, bands=[(720, 1.0, 0.10, 0.5, 4.0)]),
        ),
        tail=(2600, 2.0, 0.05, 0.8, 11.0), lowpass=14000, bounce=0.5, drive=1.4,
    ),
    "Synth Linear": dict(
        down=dict(
            leaf=dict(at=0.0, bands=[(5000, 1.2, 0.06, 0.10, 0.5)]),
            bottom=dict(at=1.6, bands=[(1900, 1.3, 1.00, 0.60, 2.5),
                                       (3200, 1.0, 0.30, 0.35, 1.3),
                                       (1000, 1.0, 0.30, 0.70, 3.0),
                                       (1250, 0.3, 0.35, 0.40, 3.5),
                                       (2150, 0.3, 0.28, 0.30, 2.5),
                                       (3400, 0.3, 0.12, 0.20, 1.8)]),
            case=dict(at=2.0, bands=[(440, 1.0, 0.16, 0.9, 6.5),
                                     (230, 0.9, 0.07, 1.4, 9.0)]),
        ),
        up=dict(
            top=dict(at=0.0, bands=[(2300, 1.2, 1.00, 0.40, 1.8),
                                    (3800, 1.0, 0.28, 0.25, 1.0),
                                    (1650, 0.3, 0.30, 0.30, 2.5),
                                    (2800, 0.3, 0.15, 0.20, 1.6)]),
            case=dict(at=0.4, bands=[(640, 1.0, 0.16, 0.6, 4.0)]),
        ),
        tail=(1700, 2.0, 0.035, 1.0, 12.0), lowpass=7000, bounce=0.2, drive=1.2,
    ),
}

README = """Kliq sound sets
================

Each sub-folder in this directory is one switch set. A set is a folder of
audio files named <code>-down.<ext> and <code>-up.<ext>, where <code> is a PC
scan code (set 1). Supported extensions:
wav, caf, aiff, aif, m4a, mp3. Any sample rate or channel count works; files
are converted at load time. Missing codes fall back to a neighbouring key.

    2-11 number row     16-25 qwertyuiop     30-38 asdfghjkl     44-50 zxcvbnm
    14 backspace  15 tab  28 return  41 backtick  42/54 shifts  57 space  58 caps
    29 ctrl  56/3640 option  3675/3676 command  57416/57419/57421/57424 arrows

Top-level effect files (any of the extensions above):
    ding                    played on Return when "Play ding on Return" is on
    left-down / left-up     mouse button sounds (right-down / right-up too)
    click                   fallback mouse click

The bundled sets (Thock, Clack, Linear) and effects are by Cris, generated by
Tools/gen_sounds.py in the Kliq repository.
"""


def rng_for(*parts):
    seed = int(hashlib.md5("/".join(map(str, parts)).encode()).hexdigest()[:8], 16)
    return np.random.default_rng(seed)


@functools.lru_cache(maxsize=None)
def _bandpass(lo, hi):
    if hi >= RATE * 0.45:
        return butter(2, lo, "highpass", fs=RATE, output="sos")
    return butter(2, [lo, hi], "bandpass", fs=RATE, output="sos")


@functools.lru_cache(maxsize=None)
def _lowpass(cutoff):
    return butter(2, cutoff, "lowpass", fs=RATE, output="sos")


def band_noise(rng, n, fc, octaves):
    """Unit-RMS white noise band-passed to `octaves` wide around `fc` Hz."""
    lo = int(fc * 2 ** (-octaves / 2))
    hi = int(fc * 2 ** (octaves / 2))
    pad = 1024  # let the filter settle before the part we keep
    y = sosfilt(_bandpass(max(lo, 30), hi), rng.standard_normal(n + pad))[pad:]
    return y / (np.sqrt(np.mean(y ** 2)) + 1e-12)


def burst(n, start, attack, tau):
    """Raised-cosine rise over `attack` s from `start` s, then exponential decay."""
    t = np.arange(n) / RATE - start
    env = np.zeros(n)
    rise = (t >= 0) & (t < attack)
    env[rise] = 0.5 - 0.5 * np.cos(np.pi * t[rise] / attack)
    fall = t >= attack
    env[fall] = np.exp(-(t[fall] - attack) / tau)
    return env


def place(code):
    """(horizontal 0..1, row index or None) of a key on the board."""
    for r, row in enumerate(ROWS):
        if code in row:
            return row.index(code) / max(1, len(row) - 1), r
    return 0.9, None


def add_bands(sig, rng, bands, at, fscale, tscale, gscale=1.0, jitter=1.0):
    """Adds one event: every band gets its own small gain, pitch and decay jitter."""
    n = len(sig)
    for fc, octv, gain, attack, tau in bands:
        f = fc * fscale * rng.uniform(1 - 0.05 * jitter, 1 + 0.05 * jitter)
        g = gain * gscale * 10 ** (rng.normal(0, 0.8 * jitter) / 20)
        a = attack / 1000 * rng.uniform(0.85, 1.15)
        d = tau / 1000 * tscale * rng.uniform(1 - 0.1 * jitter, 1 + 0.1 * jitter)
        sig += g * band_noise(rng, n, min(f, RATE * 0.42), octv) * burst(n, at, a, d)


def synth_key(kind, code, down):
    p = KINDS[kind]
    rng = rng_for(kind, code, down)
    size = BIG.get(code, 1.1 if code in MEDIUM else 1.0)
    u, row = place(code)
    centre = 1 - abs(u - 0.5) * 2      # 1 in the middle of a row, 0 at its ends

    # Bigger keys sound lower and longer; keys in the middle of the board a bit hollower.
    fscale = size ** -0.55 * (ROW_TONE[row] if row is not None else 1.0)
    fscale *= (1 + 0.05 * (u - 0.5)) * rng.uniform(0.96, 1.04)
    tscale = size ** 0.9 * rng.uniform(0.92, 1.08)
    n = int(RATE * (0.095 if down else 0.07) * size ** 0.7)
    sig = np.zeros(n)

    events = p["down" if down else "up"]
    spread = rng.uniform(0.85, 1.2)    # how hard the key was hit: leaf-to-bottom gap
    for name, ev in events.items():
        at = ev["at"] * (spread if name != "leaf" or not down else 1.0)
        at = max(0.0, at + rng.uniform(-0.3, 0.3)) / 1000
        gs = 1.0
        if name == "case":
            gs = (1 + 0.25 * centre) * size ** 0.6
        add_bands(sig, rng, ev["bands"], at, fscale, tscale * (1 + 0.15 * centre if name == "case" else 1), gs)

    hit = events.get("bottom" if down else "top")
    hit_at = (hit["at"] * spread if down else hit["at"]) / 1000
    # Keycap wobble: sometimes a second, weaker micro-impact right after the first.
    if rng.random() < p["bounce"]:
        add_bands(sig, rng, hit["bands"], hit_at + rng.uniform(0.0007, 0.0016), fscale * 1.04, tscale * 0.8,
                  rng.uniform(0.2, 0.4))

    if code in BIG:
        # The far end of the stabilized bar lands a moment later, a little lower.
        add_bands(sig, rng, hit["bands"], hit_at + rng.uniform(0.0025, 0.006), fscale * 0.9, tscale,
                  rng.uniform(0.4, 0.6) if down else rng.uniform(0.25, 0.4))
        # Wire rattle: a few faint, very short ticks and a brief buzz.
        for i in range(int(rng.integers(2, 5))):
            t0 = hit_at + rng.uniform(0.004, 0.024)
            add_bands(sig, rng, [(rng.uniform(2500, 5500), 0.8, 0.10 * 0.7 ** i, 0.05, 0.35)], t0, 1.0, 1.0,
                      0.8 if down else 0.5)
        add_bands(sig, rng, [(2200, 1.0, 0.04, 1.0, 6.0)], hit_at + 0.003, 1.0, 1.0)

    if p.get("tail"):
        add_bands(sig, rng, [p["tail"]], hit_at, fscale, tscale, 1.0 if down else 0.6)

    sig = sosfilt(_lowpass(p["lowpass"] * (1.0 if down else 1.15)), sig)
    sig = np.tanh(sig / np.abs(sig).max() * p["drive"])
    peak = (0.85 if down else 0.50) * (1.1 if code in BIG else 1.0)
    return finish(sig, peak)


def finish(sig, peak):
    fade = min(len(sig), int(RATE * 0.006))
    sig[-fade:] *= np.linspace(1, 0, fade)
    return sig / max(1e-9, np.abs(sig).max()) * peak


def synth_mouse(button, down):
    """Micro-switch: a sharp metal snap (with contact bounce) and a short plastic shell tick."""
    rng = rng_for("mouse", button, down)
    k = 1.0 if button == "left" else 1.06
    n = int(RATE * (0.045 if down else 0.035))
    sig = np.zeros(n)
    if down:
        snap = [(7500 * k, 1.6, 1.00, 0.03, 0.7), (11000 * k, 1.0, 0.50, 0.02, 0.5),
                (4000 * k, 1.0, 0.35, 0.05, 0.6)]
        ring = [(6800 * k, 0.5, 0.12, 0.10, 4.0)]
        shell = [(2000 * k, 1.0, 0.18, 0.15, 1.2), (1000 * k, 1.0, 0.06, 0.3, 2.5)]
    else:
        snap = [(8500 * k, 1.5, 1.00, 0.03, 0.55), (12000 * k, 1.0, 0.40, 0.02, 0.4),
                (4500 * k, 1.0, 0.30, 0.05, 0.5)]
        ring = [(7600 * k, 0.5, 0.10, 0.10, 3.0)]
        shell = [(2400 * k, 1.0, 0.12, 0.10, 0.9)]
    add_bands(sig, rng, snap, 0.0005, 1.0, 1.0, jitter=0.5)
    add_bands(sig, rng, snap, 0.0005 + rng.uniform(0.0003, 0.0007), 1.03, 0.8, 0.4, jitter=0.5)
    add_bands(sig, rng, shell, 0.0008, 1.0, 1.0, jitter=0.5)
    add_bands(sig, rng, ring, 0.0006, 1.0, 1.0, jitter=0.5)
    sig = np.tanh(sig / np.abs(sig).max() * 1.3)
    return finish(sig, 0.7 if down else 0.45)


def synth_ding():
    """A small struck bell: bright inharmonic partials, each a slightly detuned pair
    so it shimmers, over a short metallic strike. Meant to ring, unlike the keys."""
    n = int(RATE * 0.9)
    rng = rng_for("ding")
    t = np.arange(n) / RATE
    f0 = 2100.0
    partials = [(1.00, 1.00, 0.20), (2.03, 0.42, 0.13), (2.63, 0.30, 0.10),
                (3.91, 0.16, 0.07), (5.34, 0.08, 0.05), (6.96, 0.04, 0.035)]
    attack = np.minimum(1.0, t / 0.0015)
    sig = np.zeros(n)
    for ratio, amp, tau in partials:
        for detune, share in ((-0.0012, 0.55), (0.0012, 0.45)):
            ph = rng.uniform(0, 2 * np.pi)
            sig += share * amp * np.sin(2 * np.pi * f0 * ratio * (1 + detune) * t + ph) * np.exp(-t / tau)
    sig *= attack
    strike = np.zeros(n)
    add_bands(strike, rng, [(5500, 1.4, 0.5, 0.05, 0.8), (2500, 1.0, 0.25, 0.1, 1.5)], 0.0, 1.0, 1.0, jitter=0)
    sig += strike
    return finish(np.tanh(sig * 1.1), 0.7)


def write_sample(stem, mono, as_wav=False):
    """Writes <stem>.caf as mono Apple Lossless, going through a temporary WAV."""
    wav = stem.with_name(stem.name + ".wav")
    pcm = (np.clip(mono, -1, 1) * 32767).astype("<i2")
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    if as_wav:
        return
    caf = stem.with_name(stem.name + ".caf")
    subprocess.run(["afconvert", "-d", "alac", "-f", "caff", str(wav), str(caf)], check=True)
    wav.unlink()


def remove_audio(folder, stem=None):
    for path in folder.iterdir():
        if path.suffix.lower() in AUDIO_SUFFIXES and (stem is None or path.stem == stem):
            path.unlink()


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    as_wav = "--wav" in sys.argv[1:]
    out = pathlib.Path(args[0] if args else "Resources/Sounds")
    out.mkdir(parents=True, exist_ok=True)
    codes = sorted({c for row in ROWS for c in row} | set(EXTRA))
    count = 0
    for kind in KINDS:
        folder = out / kind
        folder.mkdir(exist_ok=True)
        remove_audio(folder)
        for code in codes:
            for down in (True, False):
                write_sample(folder / f"{code}-{'down' if down else 'up'}", synth_key(kind, code, down), as_wav)
                count += 1
    effects = {"ding": synth_ding, "click": lambda: synth_mouse("left", True),
               "left-down": lambda: synth_mouse("left", True), "left-up": lambda: synth_mouse("left", False),
               "right-down": lambda: synth_mouse("right", True), "right-up": lambda: synth_mouse("right", False)}
    for name, make in effects.items():
        remove_audio(out, name)
        write_sample(out / name, make(), as_wav)
    (out / "README.txt").write_text(README)
    print(f"wrote {count} key sounds ({len(codes)} codes x down/up) in {len(KINDS)} sets plus {len(effects)} effects -> {out}")


if __name__ == "__main__":
    main()
