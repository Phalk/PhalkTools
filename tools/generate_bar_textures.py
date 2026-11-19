"""Generate original grayscale bar fills, tinted by WoW's status bar colors."""

import math
from pathlib import Path
import struct


WIDTH, HEIGHT = 128, 32
OUTPUT = Path(__file__).resolve().parents[1] / "Media"


def shade(style, x, y):
    v = y / (HEIGHT - 1)
    if style == "Gradient":
        return 1.0 - 0.48 * v
    if style == "Gloss":
        return 0.96 - 0.25 * v if v < 0.48 else 0.56 + 0.20 * (1 - v)
    if style == "Soft":
        return 0.60 + 0.38 * math.sin(math.pi * v)
    if style == "Metal":
        return 0.60 + 0.37 * math.exp(-((v - 0.32) / 0.13) ** 2) + 0.14 * v
    if style == "Striped":
        stripe = 0.13 if (x + y) % 16 < 7 else 0
        return 0.94 - 0.25 * v - stripe
    if style == "Beveled":
        if y < 3:
            return 1.0 - 0.04 * y
        if y >= HEIGHT - 3:
            return 0.48 - 0.05 * (y - HEIGHT + 3)
        return 0.78 - 0.09 * v
    raise ValueError(style)


def main():
    OUTPUT.mkdir(exist_ok=True)
    for style in ("Gradient", "Gloss", "Soft", "Metal", "Striped", "Beveled"):
        # Uncompressed 32-bit BGRA TGA, top-left origin and eight alpha bits.
        header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, WIDTH, HEIGHT, 32, 0x28)
        pixels = bytearray()
        for y in range(HEIGHT):
            for x in range(WIDTH):
                value = round(max(0, min(1, shade(style, x, y))) * 255)
                pixels.extend((value, value, value, 255))
        (OUTPUT / f"{style}.tga").write_bytes(header + pixels)


if __name__ == "__main__":
    main()
