#!/usr/bin/env python3
"""Pack the standard PNG iconset into a modern ICNS container."""

from pathlib import Path
import struct
import sys


ENTRIES = [
    (b"icp4", "icon_16x16.png", 16),
    (b"ic11", "icon_16x16@2x.png", 32),
    (b"icp5", "icon_32x32.png", 32),
    (b"ic12", "icon_32x32@2x.png", 64),
    (b"ic07", "icon_128x128.png", 128),
    (b"ic13", "icon_128x128@2x.png", 256),
    (b"ic08", "icon_256x256.png", 256),
    (b"ic14", "icon_256x256@2x.png", 512),
    (b"ic09", "icon_512x512.png", 512),
    (b"ic10", "icon_512x512@2x.png", 1024),
]


def png_size(data: bytes) -> tuple[int, int]:
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError("not a PNG")
    return struct.unpack(">II", data[16:24])


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: pack_icns.py ICONSET OUTPUT.icns")
    iconset, output = Path(sys.argv[1]), Path(sys.argv[2])
    chunks = []
    for kind, name, expected_size in ENTRIES:
        data = (iconset / name).read_bytes()
        if png_size(data) != (expected_size, expected_size):
            raise SystemExit(f"{name} must be {expected_size}×{expected_size}")
        chunks.append(kind + struct.pack(">I", len(data) + 8) + data)
    body = b"".join(chunks)
    output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


if __name__ == "__main__":
    main()
