"""Deterministic synthetic photo fixture, not sample content in the product."""
from pathlib import Path
import math
import struct
import sys
import zlib

width, height = 1170, 2532
pixels = bytearray()
for y in range(height):
    pixels.append(0)
    for x in range(width):
        # Distinct top/bottom tests orientation; fine detail makes blur visible.
        wave = math.sin(x / 50 + y / 130) * 12
        grid = 10 if (x // 24 + y // 24) % 2 else -10
        pixels.extend((
            max(0, min(255, int(50 + 105 * x / width + wave + grid))),
            max(0, min(255, int(60 + 85 * y / height + wave + grid))),
            max(0, min(255, int(100 + 60 * (1 - y / height) + grid))),
        ))

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

png = b'\x89PNG\r\n\x1a\n'
png += chunk(b'IHDR', struct.pack('>2I5B', width, height, 8, 2, 0, 0, 0))
png += chunk(b'sRGB', b'\0')
png += chunk(b'IDAT', zlib.compress(pixels, 6))
png += chunk(b'IEND', b'')
Path(sys.argv[1]).write_bytes(png)
