#!/usr/bin/env python3
"""Render a short typing demo from a switch set, for listening to a set outside the app.

Types a sentence with human-like timing (varied gaps between keys, 70-120 ms
between each key's down and up, space bar between words, Return at the end),
using the set's <code>-down / <code>-up files. Panning and the +-5 % random pitch
follow the app's defaults. The timing is seeded, so every set gets the same
performance and renders can be compared side by side.

    python3 Tools/audition.py SET_DIR OUT.wav [--text "..."] [--seed N] [--volume 0.7]
"""
import argparse
import pathlib
import sys
import wave

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from analyze_sounds import AUDIO, load  # noqa: E402
from gen_sounds import ROWS  # noqa: E402

RATE = 48_000
LETTERS = {c: code for c, code in zip("qwertyuiop", range(16, 26))}
LETTERS.update({c: code for c, code in zip("asdfghjkl", range(30, 39))})
LETTERS.update({c: code for c, code in zip("zxcvbnm", range(44, 51))})
LETTERS[" "] = 57
LETTERS["\n"] = 28
LEFT_HAND = set("qwertasdfgzxcvb")


def pan_for(code):
    """Same table as KeyMapper.panByScanCode."""
    for row in ROWS:
        if code in row:
            return (row.index(code) / max(1, len(row) - 1) * 2 - 1) * 0.35
    return 0.0


def schedule(text, rng):
    """[(time s, code, down)] for typing `text` followed by Return."""
    events, t, prev = [], 0.25, None
    for ch in text + "\n":
        code = LETTERS[ch]
        gap = float(np.exp(rng.normal(np.log(0.112), 0.28)))
        if prev is not None and ch not in " \n" and prev not in " \n" and (ch in LEFT_HAND) == (prev in LEFT_HAND):
            gap += 0.03                           # same hand: a little slower
        if prev == " ":
            gap += 0.035                          # starting a new word
        if ch == "\n":
            gap += 0.30                           # a pause before Return
        t += gap if prev is not None else 0
        dwell = rng.uniform(0.07, 0.12) if ch not in " \n" else rng.uniform(0.09, 0.13)
        events.append((t, code, True))
        events.append((t + dwell, code, False))
        prev = ch
    return sorted(events)


def find(folder, code, down):
    stem = f"{code}-{'down' if down else 'up'}"
    for p in folder.iterdir():
        if p.stem == stem and p.suffix.lower() in AUDIO:
            return p
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("set_dir")
    ap.add_argument("out")
    ap.add_argument("--text", default="the quick brown fox jumps over the lazy dog")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--volume", type=float, default=0.7, help="the app's default volume")
    a = ap.parse_args()

    folder = pathlib.Path(a.set_dir)
    rng = np.random.default_rng(a.seed)
    events = schedule(a.text, rng)
    cache = {}
    length = events[-1][0] + 0.5
    mix = np.zeros((int(RATE * length) + RATE, 2))
    for t, code, down in events:
        key = (code, down)
        if key not in cache:
            path = find(folder, code, down)
            x, rate = load(path) if path else (np.zeros(1), RATE)
            if rate != RATE:
                x = np.interp(np.arange(0, len(x), rate / RATE), np.arange(len(x)), x)
            cache[key] = x
        x = cache[key]
        pitch = rng.uniform(0.95, 1.05)           # app default: pitch variation on
        x = np.interp(np.arange(0, len(x) - 1, pitch), np.arange(len(x)), x)
        pan = pan_for(code)
        gains = (min(1.0, 1 - pan), min(1.0, 1 + pan))
        i = int(t * RATE)
        mix[i:i + len(x), 0] += x * gains[0] * a.volume
        mix[i:i + len(x), 1] += x * gains[1] * a.volume
    mix = mix[: int(RATE * length)]
    peak = np.abs(mix).max()
    pcm = (np.clip(mix, -1, 1) * 32767).astype("<i2")
    with wave.open(a.out, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    print(f"{a.out}: {length:.2f} s, {len(events) // 2} keys, peak {peak:.2f}{' (clipped)' if peak > 1 else ''}")


if __name__ == "__main__":
    main()
