#!/usr/bin/env python3
"""Build the website's sound sprites from the app's bundled switch sets.

For each profile, the letter keys, space, return and backspace are converted to
24 kHz mono 16-bit, laid end to end with a short gap in one WAV file, and their
offsets are written to site/sounds/sprites.json. The site then plays exactly
what the app plays.

Usage: python3 Tools/make_web_sounds.py
"""
import json
import pathlib
import subprocess
import tempfile
import wave

ROOT = pathlib.Path(__file__).resolve().parent.parent
# Keep this aligned with SoundLibrary.bundledSetNames and the product UI.
SETS = {
    "kat": "KAT",
    "cherry": "Cherry",
    "mt3": "MT3",
    "xda": "XDA",
    "oem": "OEM",
    "sa": "SA",
    "dsa": "DSA",
}
RATE = 24_000
GAP = int(RATE * 0.02)

# PC scan codes (set 1) for the keys the demo plays, keyed by KeyboardEvent.key.
CODES = {
    **{c: code for c, code in zip("qwertyuiop", range(16, 26))},
    **{c: code for c, code in zip("asdfghjkl", range(30, 39))},
    **{c: code for c, code in zip("zxcvbnm", range(44, 51))},
    " ": 57, "Enter": 28, "Backspace": 14,
}


def pcm(path):
    """Decodes a bundled sample to 24 kHz mono 16-bit frames with afconvert."""
    with tempfile.TemporaryDirectory() as tmp:
        out = pathlib.Path(tmp) / "sample.wav"
        subprocess.run(["afconvert", "-f", "WAVE", "-d", f"LEI16@{RATE}", "-c", "1", str(path), str(out)], check=True)
        # afconvert writes WAVE_FORMAT_EXTENSIBLE, which the wave module can't read,
        # so take the samples straight from the data chunk.
        data = out.read_bytes()
        at = data.index(b"data")
        size = int.from_bytes(data[at + 4:at + 8], "little")
        return data[at + 8:at + 8 + size]


def resolved_code(directory, code):
    """Matches the app's nearest-key fallback when a profile lacks a down sample."""
    available = sorted(
        int(path.name.removesuffix("-down.wav"))
        for path in directory.glob("*-down.wav")
        if path.name.removesuffix("-down.wav").isdigit()
    )
    if not available:
        return None
    if code in available:
        return code
    main = [candidate for candidate in available if candidate < 100]
    return min(main or available, key=lambda candidate: (abs(candidate - code), candidate))


def main():
    out_dir = ROOT / "site" / "sounds"
    out_dir.mkdir(parents=True, exist_ok=True)
    sprites = {}
    for slug, folder in SETS.items():
        directory = ROOT / "Resources" / "Sounds" / folder
        audio, offsets = bytearray(), {}
        for key, code in CODES.items():
            resolved = resolved_code(directory, code)
            if resolved is None:
                continue
            for stroke in ("down", "up"):
                src = directory / f"{resolved}-{stroke}.wav"
                if not src.exists():
                    continue
                frames = pcm(src)
                start = len(audio) // 2
                audio += frames
                offsets.setdefault(key, {})[stroke] = [round(start / RATE, 5), round(len(frames) / 2 / RATE, 5)]
                audio += b"\0\0" * GAP
        with wave.open(str(out_dir / f"{slug}.wav"), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(bytes(audio))
        sprites[slug] = offsets
        print(f"{slug}: {len(offsets)} keys, {len(audio) // 1024} KB")
    (out_dir / "sprites.json").write_text(json.dumps(sprites, separators=(",", ":")))


if __name__ == "__main__":
    main()
