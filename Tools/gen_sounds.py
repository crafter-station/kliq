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

Sets:
    Butter      smooth and deep
    Glass       bright and glassy
    Obsidian    dark and heavy

Model: a key stroke is a short sequence of impact events: a faint lead-in, the
first contact, the main impact, rebounds and rattle. Each event is a sum of
band-passed white-noise bursts on a fixed grid of third-octave bands (a
noise-band impact model). Every band of every event has its own gain and its
own exponential decay, so an event can be bright at the attack and dark in its
tail. Events have a mean start time and a per-key spread, and some happen on
only part of the keys.

Every set has separate down and up profiles for three key classes: normal
keys, big stabilized keys (space, return, backspace, shifts) and modifiers
(tab, caps, control, option, command). Per key, deterministic seeds choose the
event timing and which optional events happen, plus small jitter in band gains,
centre frequencies and decays. On top of that each set has gentle level, tone
and decay trends across the rows and columns of the board.

Levels are absolute, not normalized per file, so the balance between keys and
between down and up strokes is part of each profile. A gentle soft limiter
keeps the rare loud peak below full scale, so nothing clips. No sine
oscillators are used for key sounds; the narrowest bands are a third of an
octave wide and damped.

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

# Stabilized keys and their width; within the class, wider keys sound a little lower and longer.
BIG = {14: 2.0, 28: 2.25, 42: 2.25, 54: 2.75, 57: 6.25, 3612: 2.0}
MODIFIERS = {15, 58, 29, 56, 3640, 3675, 3676, 3613}

GRID = 1000 * 2.0 ** (np.arange(-10, 13) / 3)     # 23 band centres, 100 Hz - 16 kHz
WIDTH = 1 / 3                                     # band width, octaves
DECAY_AT = np.array([125, 500, 2000, 8000, 16000.0])
START_MS = 1.0                                    # silence before the first event
CENTRE = (0.5, 2.5)                               # trends are relative to mid-board
BAND_JITTER = (1.5, 0.03, 0.1)                    # per band: gain sd dB, pitch, decay
SILENT = -60                                      # bands at or below this gain are left out


def E(at, spread, chance, attack, gains, decays):
    """One event of a stroke.

    at      mean start, ms after the first event of the stroke
    spread  per-key standard deviation of the start, ms
    chance  share of keys on which the event happens
    attack  rise time, ms
    gains   dB per GRID band, relative to the stroke level (-60 or lower: left out)
    decays  decay time constants in ms at DECAY_AT, log-interpolated in between
    """
    return dict(at=at, spread=spread, chance=chance, attack=attack, gains=gains, decays=decays)


# A stroke is dict(level=dBFS of a unit band, length=ms, delay=(chance, mean ms, sd ms),
#                  lead=E or None, events=[E, ...]).
# The lead-in is a faint first tick. On `chance` of the keys everything after it lands
# later by a random delay, as when a key is struck slightly off-centre.
# A set has one stroke per key class and direction, plus per direction:
#   trend   (level dB, tone semitones, decay octaves) per board width and per row,
#           as (level_col, level_row, tone_col, tone_row, decay_col, decay_row)
#   jitter  per-key (level sd dB, tone sd semitones, decay sd octaves)
KINDS = {
    "Synth Butter": dict(
        norm=dict(
            down=dict(level=-10.14, length=91, delay=(0.19, 7.73, 2.35),
                lead=E(0, 0, 1, 0.197,
                       [-99, -99, -99, -99, -99, -99, -99, -57, -50, -48, -40, -32, -33, -38, -32, -37, -52, -49, -48, -99, -99, -99, -99],
                       (19, 30, 39, 40, 55)),
                events=[
                    E(0.21, 0.39, 1, 0.867,
                      [-99, -57, -58, -59, -60, -59, -50, -51, -45, -31, -22, -11, -6, -9, 0, -11, -28, -16, -17, -41, -33, -47, -99],
                      (67, 18, 1.3, 0.92, 0.35)),
                    E(4.06, 1.66, 0.69, 0.203,
                      [-99, -99, -99, -57, -55, -54, -53, -52, -51, -48, -45, -42, -40, -39, -39, -39, -43, -49, -55, -99, -99, -99, -99],
                      (6.1, 4, 2.7, 1.8, 1.1)),
                    E(1.79, 2.03, 0.37, 0.202,
                      [-99, -99, -54, -48, -44, -41, -32, -36, -43, -45, -45, -43, -41, -40, -39, -41, -45, -49, -55, -59, -99, -99, -99],
                      (7.5, 4.3, 2.7, 1.7, 1.1)),
                ]),
            up=dict(level=-25.32, length=50, delay=(0.35, 8.23, 9.9),
                lead=E(0, 0, 1, 4.2,
                       [-99, -99, -99, -99, -99, -54, -34, -34, -30, -36, -31, -23, -33, -38, -29, -40, -99, -99, -99, -99, -99, -99, -49],
                       (1.1, 7.7, 39, 33, 47)),
                events=[
                    E(0.54, 0.49, 1, 2.695,
                      [-99, -99, -99, -99, -99, -99, -58, -51, -36, -25, -12, -7, -9, -10, 0, -18, -37, -30, -16, -42, -57, -99, -99],
                      (32, 20, 3.1, 0.48, 0.31)),
                    E(0.86, 2.77, 0.96, 0.799,
                      [-99, -99, -99, -99, -99, -99, -58, -52, -47, -43, -40, -36, -28, -18, -10, -21, -33, -33, -39, -46, -48, -45, -42],
                      (2.6, 2.1, 1.5, 0.85, 0.66)),
                    E(1.79, 2.96, 0.71, 0.122,
                      [-99, -99, -99, -99, -99, -99, -57, -54, -50, -48, -46, -44, -43, -43, -44, -46, -49, -51, -53, -55, -57, -57, -57],
                      (2.9, 2.7, 2.3, 1.8, 1.4)),
                    E(29.72, 2.17, 0.27, 0.358,
                      [-59, -59, -59, -58, -58, -56, -54, -52, -49, -47, -44, -42, -41, -42, -44, -48, -51, -45, -33, -41, -48, -53, -56],
                      (1.8, 2.1, 2.6, 3.1, 2.7)),
                ]),
        ),
        big=dict(
            down=dict(level=-15.23, length=90, delay=(0, 0, 0),
                lead=E(0, 0, 1, 0.2,
                       [-99, -99, -99, -99, -99, -56, -45, -36, -37, -32, -35, -20, -25, -30, -26, -27, -39, -29, -20, -47, -99, -99, -99],
                       (11, 26, 41, 4.3, 0.88)),
                events=[
                    E(0.08, 0.39, 1, 1.483,
                      [-99, -99, -99, -99, -99, -49, -35, -27, -21, -9, -20, 0, -3, -10, 0, -18, -29, -10, -27, -48, -99, -99, -99],
                      (30, 9.1, 1.6, 0.42, 0.33)),
                    E(7.25, 1.85, 1, 0.246,
                      [-60, -99, -99, -99, -99, -57, -53, -49, -46, -43, -41, -39, -39, -40, -43, -47, -52, -56, -99, -99, -99, -99, -99],
                      (4.7, 3.3, 2.3, 1.5, 0.92)),
                    E(7.93, 0.37, 0.8, 1.582,
                      [-99, -99, -99, -99, -59, -56, -51, -47, -43, -40, -33, -20, -10, -27, -42, -50, -54, -57, -58, -58, -57, -54, -53],
                      (6.4, 5.1, 3.6, 1.9, 1)),
                ]),
            up=dict(level=-28.42, length=48, delay=(1, 4.29, 0.1),
                lead=E(0, 0, 1, 2.595,
                       [-48, -52, -55, -57, -57, -51, -32, -20, -32, -17, -22, -16, -18, -23, -19, -20, -41, -25, -20, -45, -53, -50, -48],
                       (4.5, 13, 22, 8.1, 9.1)),
                events=[
                    E(1.22, 0, 1, 2.984,
                      [-48, -50, -52, -53, -54, -52, -45, -38, -28, -5, -7, 0, -1, -6, -6, -11, -31, -23, -17, -41, -49, -49, -46],
                      (1.5, 7.6, 1.2, 0.58, 0.5)),
                    E(2.04, 0.18, 1, 0.804,
                      [-47, -49, -50, -51, -52, -50, -46, -42, -39, -36, -33, -30, -28, -26, -25, -28, -34, -31, -32, -43, -49, -49, -48],
                      (1.2, 2.7, 2.4, 1.1, 0.69)),
                    E(3.26, 0, 1, 0.187,
                      [-48, -50, -51, -52, -52, -50, -46, -42, -38, -36, -35, -33, -32, -30, -28, -30, -34, -32, -34, -43, -48, -49, -47],
                      (1.6, 3, 2.4, 1.2, 0.73)),
                    E(4.93, 0, 0.6, 0.086,
                      [-47, -48, -49, -50, -50, -48, -45, -41, -37, -35, -33, -32, -31, -30, -31, -32, -34, -32, -33, -41, -45, -46, -45],
                      (1.6, 2.9, 2.4, 1.1, 0.74)),
                    E(11.84, 0, 0.6, 0.196,
                      [-48, -48, -49, -50, -50, -48, -44, -40, -37, -34, -33, -32, -32, -34, -36, -40, -44, -42, -41, -43, -45, -42, -31],
                      (1.7, 3.2, 3.2, 1.7, 1.1)),
                ]),
        ),
        mod=dict(
            down=dict(level=-16.09, length=95, delay=(0, 0, 0),
                lead=E(0, 0, 1, 0.791,
                       [-43, -37, -43, -57, -99, -59, -49, -47, -42, -44, -35, -31, -31, -31, -30, -34, -47, -48, -46, -51, -99, -99, -58],
                       (15, 23, 41, 47, 32)),
                events=[
                    E(0, 0.06, 1, 0.331,
                      [-45, -50, -55, -60, -59, -50, -33, -38, -42, -40, -26, -14, -13, -7, 0, -12, -30, -30, -17, -40, -55, -99, -99],
                      (8.7, 10, 3.2, 1.6, 0.68)),
                    E(3.9, 0, 0.71, 1.488,
                      [-47, -51, -54, -57, -57, -55, -51, -49, -47, -43, -30, -8, -6, -14, -20, -22, -33, -36, -28, -44, -55, -99, -99],
                      (5.3, 4.2, 2.8, 1.6, 0.91)),
                    E(5.4, 0.23, 0.57, 0.279,
                      [-45, -49, -53, -55, -55, -51, -46, -43, -43, -43, -40, -35, -31, -27, -23, -21, -33, -41, -45, -49, -53, -56, -58],
                      (4.8, 4.5, 3.7, 2.1, 1)),
                    E(7.2, 0, 0.43, 0.197,
                      [-44, -48, -52, -54, -55, -52, -49, -46, -45, -44, -41, -37, -34, -32, -31, -32, -37, -40, -43, -47, -51, -53, -56],
                      (4.7, 3.7, 2.7, 1.7, 1)),
                ]),
            up=dict(level=-28.58, length=58, delay=(0.57, 11.6, 10.74),
                lead=E(0, 0, 1, 2.857,
                       [-55, -57, -59, -99, -99, -56, -43, -36, -32, -23, -24, -15, -26, -13, -6, -11, -35, -34, -24, -44, -58, -59, -45],
                       (4.3, 15, 9, 2.2, 5.8)),
                events=[
                    E(2.86, 0.35, 1, 2.988,
                      [-54, -54, -56, -57, -57, -55, -51, -43, -29, -19, -17, 0, -23, -30, -34, -40, -46, -41, -22, -43, -55, -56, -50],
                      (1.3, 4.3, 5.7, 1.5, 0.66)),
                    E(20.23, 6, 1, 0.872,
                      [-52, -52, -53, -54, -54, -54, -52, -48, -44, -40, -37, -37, -38, -30, -25, -24, -45, -49, -44, -50, -54, -50, -31],
                      (1.1, 3.4, 7.5, 3.4, 1.1)),
                    E(10.84, 4.16, 0.57, 0.193,
                      [-51, -52, -52, -53, -53, -52, -49, -45, -41, -39, -37, -36, -35, -33, -33, -37, -43, -46, -46, -48, -51, -48, -37],
                      (1.7, 2.6, 2.7, 1.7, 1.1)),
                ]),
        ),
        trend=dict(down=(0.07, -0.18, -0.15, -0.05, -0.4, 0.083), up=(7.04, 1.56, 1.74, -0.35, -0.4, -0.069)),
        jitter=dict(down=(0.37, 0.5, 0.124), up=(2.98, 0.74, 0.238)),
    ),
    "Synth Glass": dict(
        norm=dict(
            down=dict(level=-22.63, length=65, delay=(0.98, 16.24, 2.53),
                lead=E(0, 0, 1, 2.781,
                       [-44, -32, -29, -43, -52, -45, -22, -22, -23, -27, -24, -25, -29, -32, -24, -19, -22, -26, -24, -18, -17, -52, -99],
                       (34, 32, 17, 21, 38)),
                events=[
                    E(0.67, 0, 1, 2.946,
                      [-21, -25, -34, -43, -47, -43, -31, -16, -9, -11, 0, -1, -6, -11, -3, -5, -9, -9, -7, -3, -7, -39, -99],
                      (4.5, 4.3, 7, 2.3, 1.1)),
                    E(5.25, 4.12, 0.92, 0.415,
                      [-32, -34, -38, -43, -46, -45, -41, -37, -33, -28, -24, -19, -14, -10, -8, -15, -22, -26, -27, -30, -36, -46, -57],
                      (5.3, 4.1, 2.9, 2.2, 1.6)),
                    E(10.72, 2.78, 0.56, 0.286,
                      [-30, -30, -33, -38, -43, -43, -41, -39, -35, -31, -26, -23, -22, -23, -23, -23, -24, -25, -26, -30, -36, -45, -55],
                      (6.2, 4.8, 3.6, 2.4, 1.5)),
                    E(22.2, 4.26, 0.25, 0.221,
                      [-20, -16, -20, -30, -38, -41, -41, -39, -36, -30, -22, -17, -21, -26, -22, -17, -22, -22, -19, -25, -34, -45, -55],
                      (5.2, 6.5, 8.1, 5.4, 2.6)),
                ]),
            up=dict(level=-17.48, length=65, delay=(0.98, 40.12, 5.88),
                lead=E(0, 0, 1, 0.074,
                       [-27, -41, -42, -44, -48, -46, -38, -43, -38, -38, -34, -29, -38, -42, -37, -32, -39, -40, -36, -37, -30, -99, -99],
                       (7.6, 41, 31, 48, 27)),
                events=[
                    E(0.57, 0, 1, 0.796,
                      [-45, -42, -41, -43, -47, -46, -41, -36, -32, -28, -25, -24, -23, -18, -10, -11, -9, -14, -5, 0, -8, -43, -99],
                      (6.7, 3.6, 1.8, 1, 1.2)),
                    E(0.04, 2.73, 0.88, 0.199,
                      [-45, -44, -43, -45, -47, -44, -36, -27, -19, -15, -7, -8, -20, -22, -19, -21, -23, -29, -33, -37, -44, -52, -99],
                      (7.7, 7.2, 4.7, 2.3, 0.99)),
                    E(11.15, 2.59, 0.63, 0.208,
                      [-44, -44, -44, -46, -48, -45, -37, -28, -22, -18, -17, -22, -29, -35, -38, -39, -40, -41, -41, -43, -48, -56, -99],
                      (8.6, 7.9, 5.5, 2.7, 1.1)),
                    E(8.54, 2.87, 0.5, 3.258,
                      [-49, -41, -33, -39, -46, -42, -25, -11, -9, -10, -15, -23, -31, -36, -38, -40, -40, -42, -43, -45, -50, -58, -99],
                      (18, 13, 8.1, 3.2, 1.1)),
                ]),
        ),
        big=dict(
            down=dict(level=-15.48, length=66, delay=(0.8, 14.5, 0.88),
                lead=E(0, 0, 1, 0.787,
                       [-44, -46, -53, -99, -99, -57, -40, -26, -38, -37, -34, -34, -36, -39, -36, -39, -35, -45, -35, -29, -29, -99, -99],
                       (20, 29, 25, 28, 26)),
                events=[
                    E(1.72, 0, 1, 0.811,
                      [-58, -41, -27, -45, -57, -52, -30, -21, -28, -29, -19, -11, -19, -21, -20, -25, -16, -25, -18, 0, -18, -48, -99],
                      (42, 8.8, 8.2, 1.1, 0.73)),
                    E(6.23, 1.34, 0.8, 2.972,
                      [-34, -44, -52, -56, -57, -53, -42, -26, -9, -9, -13, -23, -31, -35, -36, -37, -37, -33, -21, -19, -20, -49, -99],
                      (3.7, 3.3, 5.3, 5.9, 3.4)),
                    E(14.48, 1.11, 0.4, 0.797,
                      [-45, -47, -49, -51, -52, -51, -48, -45, -42, -40, -39, -37, -32, -23, -17, -13, -18, -15, -26, -37, -46, -56, -99],
                      (4.1, 4.2, 4.5, 5.7, 4.8)),
                    E(16.85, 6, 0.4, 0.214,
                      [-46, -47, -49, -51, -52, -51, -48, -44, -40, -36, -33, -33, -35, -35, -33, -27, -19, -20, -19, -20, -17, -44, -99],
                      (4.5, 4.6, 4.9, 3.6, 2)),
                ]),
            up=dict(level=-17.58, length=66, delay=(1, 37.9, 4.95),
                lead=E(0, 0, 1, 0.078,
                       [-29, -29, -36, -39, -36, -50, -49, -34, -31, -31, -33, -29, -30, -40, -34, -33, -34, -32, -30, -32, -25, -56, -99],
                       (7.6, 45, 34, 16, 17)),
                events=[
                    E(0, 0, 1, 0.2,
                      [-44, -40, -36, -37, -39, -36, -23, -16, -6, -7, -4, -3, -5, -15, -19, -9, -11, -20, -19, 0, -9, -44, -99],
                      (9.3, 7.3, 1.7, 1.8, 5.8)),
                    E(1.89, 2.78, 1, 0.205,
                      [-44, -40, -36, -37, -39, -36, -24, -20, -18, -20, -24, -27, -31, -35, -38, -38, -37, -37, -36, -35, -39, -48, -58],
                      (8.6, 7.3, 3.4, 1.7, 0.92)),
                    E(21, 1.3, 0.4, 0.213,
                      [-39, -34, -30, -32, -36, -34, -25, -19, -18, -21, -24, -27, -31, -35, -37, -38, -37, -37, -37, -36, -40, -49, -58],
                      (12, 6.8, 3.5, 1.9, 1)),
                    E(21.1, 1.39, 0.4, 0.2,
                      [-40, -33, -27, -31, -36, -34, -25, -19, -19, -21, -25, -29, -32, -36, -38, -38, -37, -37, -37, -36, -40, -49, -58],
                      (14, 7.1, 3.7, 2, 1.1)),
                    E(22.73, 3.15, 0.4, 0.199,
                      [-40, -32, -24, -29, -36, -34, -25, -19, -19, -22, -27, -30, -33, -36, -38, -38, -38, -38, -37, -37, -41, -50, -58],
                      (14, 7.4, 4, 2.1, 1.1)),
                ]),
        ),
        mod=dict(
            down=dict(level=-19.01, length=66, delay=(1, 14.61, 1.66),
                lead=E(0, 0, 1, 2.476,
                       [-37, -46, -53, -58, -60, -54, -40, -20, -27, -23, -26, -25, -29, -29, -21, -25, -26, -30, -26, -20, -25, -57, -99],
                       (4.7, 12, 10, 24, 40)),
                events=[
                    E(0, 0, 1, 3.049,
                      [-23, -38, -49, -56, -57, -51, -35, -12, -9, -3, 0, -8, -10, -8, -7, -11, -20, -24, -14, -9, -19, -48, -99],
                      (2.9, 4.7, 4.7, 2.2, 1.2)),
                    E(18.17, 1.67, 1, 1.226,
                      [-47, -37, -38, -46, -54, -48, -30, -35, -33, -25, -24, -22, -28, -27, -25, -25, -27, -23, -23, -31, -42, -54, -99],
                      (20, 14, 6.6, 3.1, 1.4)),
                    E(11.43, 6, 0.43, 0.199,
                      [-43, -45, -47, -50, -51, -50, -47, -42, -37, -33, -30, -27, -26, -25, -25, -26, -27, -29, -31, -36, -43, -52, -99],
                      (5.4, 5.2, 4.3, 2.9, 1.8)),
                ]),
            up=dict(level=-20.25, length=66, delay=(1, 36.29, 3.75),
                lead=E(0, 0, 1, 0.722,
                       [-34, -45, -44, -37, -46, -50, -42, -29, -37, -36, -25, -27, -31, -32, -36, -32, -35, -43, -39, -35, -31, -58, -99],
                       (7.6, 27, 57, 77, 71)),
                events=[
                    E(0, 0, 1, 0.8,
                      [-99, -99, -99, -99, -99, -47, -25, -13, -11, -8, 0, -4, -12, -6, -4, -4, -8, -16, -9, -2, -4, -39, -99],
                      (72, 34, 1.8, 0.99, 1.6)),
                    E(0.09, 1.57, 1, 0.212,
                      [-53, -54, -55, -55, -54, -52, -48, -44, -40, -37, -35, -33, -31, -29, -28, -28, -29, -31, -33, -37, -43, -50, -58],
                      (4.3, 3.2, 2.2, 1.4, 0.77)),
                    E(30.72, 1.94, 0.86, 0.652,
                      [-52, -53, -54, -54, -54, -51, -48, -44, -40, -37, -35, -33, -32, -31, -32, -34, -37, -41, -43, -45, -48, -54, -60],
                      (4.7, 3.6, 2.6, 1.7, 1)),
                    E(33.46, 4.26, 0.57, 0.548,
                      [-50, -51, -52, -53, -52, -50, -46, -42, -38, -36, -34, -32, -32, -31, -32, -34, -37, -40, -42, -45, -48, -53, -59],
                      (4.6, 3.7, 2.8, 1.9, 1.2)),
                    E(31.75, 2.69, 0.29, 0.444,
                      [-46, -47, -48, -49, -48, -46, -43, -39, -36, -33, -32, -31, -30, -30, -31, -33, -35, -38, -40, -43, -46, -51, -57],
                      (4, 3.4, 2.7, 1.9, 1.4)),
                ]),
        ),
        trend=dict(down=(-0.26, -0.06, -0.38, 0.65, 0.4, 0.027), up=(-1.03, -0.53, -1.93, -1.5, 0.222, 0.008)),
        jitter=dict(down=(0.28, 1.5, 0.101), up=(1.83, 1.5, 0.051)),
    ),
    "Synth Obsidian": dict(
        norm=dict(
            down=dict(level=-23.28, length=39, delay=(0.35, 8.1, 3.46),
                lead=None,
                events=[
                    E(0.65, 0.51, 1, 2.116,
                      [-44, -44, -40, -31, -36, -52, -99, -99, -52, -28, -11, -11, -8, 0, 0, -1, -6, -13, -10, -6, -9, -33, -57],
                      (13, 14, 4.3, 3.1, 5.1)),
                    E(3.57, 1.66, 0.71, 0.794,
                      [-45, -47, -49, -51, -54, -58, -99, -99, -59, -54, -48, -42, -32, -18, -12, -19, -27, -32, -31, -26, -17, -9, -19],
                      (9.4, 11, 9.7, 2.3, 0.35)),
                    E(1.86, 1.06, 0.27, 0.198,
                      [-44, -45, -46, -47, -49, -52, -54, -55, -53, -49, -45, -40, -37, -34, -32, -31, -31, -32, -33, -34, -34, -33, -29],
                      (4.6, 3.3, 2.4, 1.7, 1.2)),
                ]),
            up=dict(level=-28.68, length=41, delay=(1, 23.94, 6.77),
                lead=E(0, 0, 1, 8.174,
                       [-42, -58, -99, -99, -53, -50, -55, -53, -42, -37, -30, -33, -33, -31, -24, -23, -25, -26, -25, -20, -17, -28, -46],
                       (6.3, 4.4, 5.3, 4.9, 4.1)),
                events=[
                    E(4.95, 0, 1, 2.955,
                      [-52, -55, -58, -59, -58, -56, -51, -41, -25, -9, -6, -9, -18, -7, -4, -1, -5, -8, -5, 0, -3, -16, -36],
                      (2.9, 2.1, 1.2, 1.6, 1.8)),
                    E(7.28, 2.77, 0.63, 2.861,
                      [-52, -54, -57, -58, -58, -55, -51, -45, -38, -33, -31, -32, -34, -33, -30, -22, -9, -7, -6, -6, -9, -14, -36],
                      (2.9, 1.8, 0.72, 0.61, 1.1)),
                ]),
        ),
        big=dict(
            down=dict(level=-19.28, length=39, delay=(0.5, 3.5, 0.25),
                lead=E(0, 0, 1, 0.074,
                       [-99, -48, -37, -36, -51, -99, -99, -99, -99, -53, -41, -30, -27, -26, -26, -28, -40, -47, -48, -42, -34, -47, -99],
                       (24, 22, 12, 4.4, 4.5)),
                events=[
                    E(0.12, 0.3, 1, 1.609,
                      [-99, -58, -54, -52, -52, -58, -99, -99, -50, -24, -13, -16, -14, -1, -13, 0, -10, -8, -18, -12, -16, -23, -34],
                      (40, 30, 1.9, 1.5, 5)),
                    E(10.13, 0.37, 1, 0.129,
                      [-59, -57, -56, -56, -56, -58, -59, -58, -54, -49, -44, -38, -29, -21, -30, -29, -23, -28, -35, -37, -37, -40, -46],
                      (4.7, 5.4, 4.6, 1.9, 0.9)),
                    E(7.93, 0.83, 0.5, 0.05,
                      [-60, -57, -56, -56, -57, -59, -59, -53, -40, -20, -24, -32, -35, -35, -35, -34, -34, -36, -38, -39, -39, -41, -44],
                      (5.2, 4.9, 4.4, 2.7, 1.5)),
                    E(13.65, 0.55, 0.5, 0.088,
                      [-58, -56, -55, -54, -54, -55, -56, -55, -51, -46, -42, -38, -35, -34, -35, -37, -39, -39, -36, -28, -28, -35, -48],
                      (4.4, 4, 3.7, 3.2, 2.7)),
                    E(10.21, 0, 0.25, 0.36,
                      [-55, -52, -50, -49, -49, -50, -52, -51, -49, -44, -40, -38, -36, -35, -35, -35, -34, -35, -35, -35, -36, -40, -47],
                      (4, 3.4, 2.8, 2.2, 1.7)),
                ]),
            up=dict(level=-22.32, length=50, delay=(1, 17.52, 6.23),
                lead=E(0, 0, 1, 0.689,
                       [-99, -60, -58, -57, -58, -59, -58, -52, -43, -31, -27, -39, -45, -33, -30, -21, -23, -23, -22, -25, -27, -24, -44],
                       (8.7, 9.5, 6.3, 7.9, 7.5)),
                events=[
                    E(0, 0, 1, 0.79,
                      [-57, -53, -45, -29, -38, -51, -56, -52, -41, -24, -8, -18, -22, -10, -2, -6, -1, -12, -6, -5, -3, -5, -28],
                      (13, 12, 2, 1.4, 0.62)),
                    E(5.33, 0, 0.25, 0.969,
                      [-50, -49, -47, -47, -47, -48, -47, -43, -36, -30, -26, -25, -28, -29, -27, -20, -10, -1, 0, -13, -24, -34, -44],
                      (4.1, 3.1, 2.2, 1.6, 1.2)),
                    E(7.53, 0, 0.25, 0.198,
                      [-49, -47, -45, -44, -45, -45, -45, -41, -36, -32, -31, -30, -31, -29, -27, -22, -18, -14, -15, -19, -25, -32, -41],
                      (3.7, 2.8, 2.1, 1.6, 1.3)),
                    E(12.84, 0, 0.25, 0.254,
                      [-48, -46, -44, -44, -44, -44, -42, -37, -30, -30, -30, -28, -26, -13, -20, -19, -21, -25, -22, -22, -26, -32, -40],
                      (3.6, 2.9, 2.5, 1.3, 0.92)),
                    E(15.22, 0, 0.25, 1.032,
                      [-48, -46, -44, -43, -43, -44, -43, -40, -37, -36, -35, -33, -33, -30, -30, -33, -35, -34, -23, -13, -11, -9, -28],
                      (3.8, 2.6, 1.6, 1.1, 1.1)),
                ]),
        ),
        mod=dict(
            down=dict(level=-23.94, length=40, delay=(0.71, 4.89, 2.55),
                lead=E(0, 0, 1, 0.078,
                       [-52, -48, -45, -46, -51, -55, -57, -55, -48, -38, -30, -30, -26, -29, -22, -28, -26, -31, -31, -20, -31, -30, -46],
                       (11, 13, 14, 8.5, 7.4)),
                events=[
                    E(1.01, 0, 1, 0.8,
                      [-45, -43, -39, -39, -45, -49, -49, -46, -37, -23, -4, -8, -3, -1, 0, -1, -11, -11, -6, -1, -16, -12, -31],
                      (9.8, 11, 3.6, 1.6, 1.6)),
                    E(4.1, 0.79, 0.86, 0.072,
                      [-54, -42, -24, -22, -40, -47, -47, -39, -23, -10, -16, -19, -23, -27, -29, -32, -34, -31, -24, -15, -23, -33, -43],
                      (13, 11, 4.1, 2.2, 1.1)),
                    E(7.55, 1.11, 0.57, 0.13,
                      [-44, -42, -40, -40, -42, -43, -43, -40, -33, -26, -23, -22, -24, -27, -30, -33, -35, -34, -28, -19, -22, -27, -41],
                      (7.2, 5.5, 3.1, 1.9, 1.5)),
                    E(6.72, 1.39, 0.43, 0.153,
                      [-45, -41, -38, -38, -40, -42, -41, -39, -33, -27, -24, -23, -25, -28, -30, -33, -34, -33, -30, -26, -27, -32, -41],
                      (7.4, 5.5, 3.4, 2.1, 1.3)),
                ]),
            up=dict(level=-30.39, length=44, delay=(1, 24.64, 3.58),
                lead=E(0, 0, 1, 1.704,
                       [-99, -59, -49, -38, -38, -45, -48, -41, -29, -27, -26, -35, -31, -45, -38, -23, -31, -28, -20, -22, -32, -31, -45],
                       (11, 17, 13, 13, 26)),
                events=[
                    E(0.2, 0, 1, 3.015,
                      [-99, -99, -60, -49, -29, -19, -25, -17, -5, -15, 0, -17, -7, -27, -25, -6, -14, -10, -7, -19, -15, -34, -53],
                      (25, 7.2, 1.8, 1.7, 0.85)),
                    E(9.07, 1.29, 0.8, 0.198,
                      [-53, -52, -51, -49, -46, -44, -41, -38, -36, -35, -35, -35, -34, -35, -33, -32, -26, -19, -24, -27, -31, -39, -49],
                      (2.3, 2.6, 2.3, 1.6, 1.1)),
                    E(10.24, 1.94, 0.4, 0.198,
                      [-53, -52, -50, -47, -44, -41, -39, -38, -37, -38, -37, -31, -19, -27, -29, -33, -28, -17, -28, -36, -41, -45, -49],
                      (3.6, 3.9, 3.4, 1.3, 0.74)),
                ]),
        ),
        trend=dict(down=(1.18, 0.22, -0.37, 0.42, -0.204, 0.15), up=(-8, 0.79, -3, 0.98, 0.007, -0.006)),
        jitter=dict(down=(1.08, 0.99, 0.191), up=(2.74, 1.5, 0.069)),
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

The bundled sets (Butter, Glass, Obsidian) and effects are by Cris, generated
by Tools/gen_sounds.py in the Kliq repository.
"""


def rng_for(*parts):
    seed = int(hashlib.md5("/".join(map(str, parts)).encode()).hexdigest()[:8], 16)
    return np.random.default_rng(seed)


@functools.lru_cache(maxsize=None)
def _bandpass(lo, hi):
    if hi >= RATE * 0.45:
        return butter(2, lo, "highpass", fs=RATE, output="sos")
    return butter(2, [lo, hi], "bandpass", fs=RATE, output="sos")


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


def key_class(code):
    return "big" if code in BIG else "mod" if code in MODIFIERS else "norm"


def decay_curve(knots):
    """Decay time constant (ms) for every GRID band from the knots at DECAY_AT."""
    return np.exp(np.interp(np.log(GRID), np.log(DECAY_AT), np.log(np.asarray(knots, float))))


def soft_limit(x, knee=0.7):
    """Leaves everything below `knee` alone and bends larger peaks smoothly toward 1."""
    a = np.abs(x)
    over = a > knee
    y = x.copy()
    y[over] = np.sign(x[over]) * (knee + (1 - knee) * np.tanh((a[over] - knee) / (1 - knee)))
    return y


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
    way = "down" if down else "up"
    cls = key_class(code)
    stroke = p[cls][way]
    rng = rng_for(kind, code, down)
    u, row = place(code)
    dx = u - CENTRE[0]
    dy = (row - CENTRE[1]) if row is not None else 0.0
    lc, lr, tc, trw, dc, dr = p["trend"][way]
    lsd, tsd, dsd = p["jitter"][way]

    level = stroke["level"] + lc * dx + lr * dy + rng.normal(0, lsd)
    tone = tc * dx + trw * dy + rng.normal(0, tsd)
    decay = dc * dx + dr * dy + rng.normal(0, dsd)
    if cls == "big":
        # Wider bars sound a little lower and ring a little longer than the class average.
        size = np.log2(BIG[code] / 2.6)
        tone -= 1.5 * size
        decay += 0.15 * size
    fscale, tscale = 2 ** (tone / 12), 2 ** decay

    n = int(RATE * (stroke["length"] + START_MS) / 1000)
    sig = np.zeros(n)
    gsd, fsd, dsd_band = BAND_JITTER
    chance, mean, sd = stroke["delay"]
    late = rng.random() < chance
    delay = max(0.0, rng.normal(mean, sd)) if late else 0.0
    events = [(stroke["lead"], 0.0)] if stroke["lead"] else []
    events += [(ev, delay) for ev in stroke["events"]]
    for ev, offset in events:
        happens = rng.random() < ev["chance"]
        at = START_MS + offset + max(0.0, ev["at"] + rng.normal(0, ev["spread"]))
        if not happens:
            continue
        taus = decay_curve(ev["decays"])
        for fc, gain, tau in zip(GRID, ev["gains"], taus):
            if gain <= SILENT:
                continue
            g = 10 ** ((level + gain + rng.normal(0, gsd)) / 20)
            f = min(fc * fscale * rng.uniform(1 - fsd, 1 + fsd), RATE * 0.42)
            a = ev["attack"] / 1000 * rng.uniform(0.85, 1.15)
            d = tau / 1000 * tscale * rng.uniform(1 - dsd_band, 1 + dsd_band)
            sig += g * band_noise(rng, n, f, WIDTH) * burst(n, at / 1000, a, d)

    fade = int(RATE * 0.006)
    sig[-fade:] *= np.linspace(1, 0, fade)
    return soft_limit(sig)


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
