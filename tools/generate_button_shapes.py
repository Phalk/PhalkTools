"""Generate antialiased rounded masks and thin/thick button border rings."""
import math
from pathlib import Path
import struct

SIZE = 128
OUTPUT = Path(__file__).resolve().parents[1] / "Media" / "Buttons" / "Shapes"


def distance(x, y, radius, inset=0):
    half = SIZE / 2 - inset
    radius = min(radius, half)
    qx = abs(x - SIZE / 2) - (half - radius)
    qy = abs(y - SIZE / 2) - (half - radius)
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - radius


def coverage(value):
    t = max(0, min(1, 0.5 - value / 2.0))
    return t * t * (3 - 2 * t)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    for percent in range(51):
        radius = SIZE * percent / 100
        pixels = {"Mask": bytearray(), "Thin": bytearray(), "Thick": bytearray(), "Sheen": bytearray(), "Hover": bytearray()}
        for name in ("ContentThin", "ContentThick", "SheenThin", "SheenThick"):
            pixels[name] = bytearray()
        for y in range(SIZE):
            for x in range(SIZE):
                outer = coverage(distance(x+.5, y+.5, radius))
                pixels["Mask"].extend((255, 255, 255, round(outer * 255)))
                depth = max(0, -distance(x+.5, y+.5, radius))
                hover = outer * (0.055 + 0.62 * math.exp(-((depth-2.0)/4.0)**2))
                pixels["Hover"].extend((255, 255, 255, round(hover * 255)))
                sheen = coverage(distance(x+.5, y+.5, max(0, radius-3), 3))
                pixels["Sheen"].extend((255, 255, 255, round(sheen * 255)))
                for name, thickness in (("Thin", 3.2), ("Thick", 6.4)):
                    inner = coverage(distance(x+.5, y+.5, max(0, radius-thickness), thickness))
                    # Overlap the content with the opaque portion of the ring.
                    # An inward gap exposes the world as a second inner outline.
                    inset = thickness - 1.0
                    content = coverage(distance(x+.5, y+.5, max(0, radius-inset), inset))
                    pixels["Content"+name].extend((255, 255, 255, round(content*255)))
                    inset += 2
                    inside_light = coverage(distance(x+.5, y+.5, max(0, radius-inset), inset))
                    pixels["Sheen"+name].extend((255, 255, 255, round(inside_light*255)))
                    pixels[name].extend((255, 255, 255, round(max(0, outer-inner)*255)))
        for name, data in pixels.items():
            (OUTPUT / f"{name}-{percent}.tga").write_bytes(header + data)


if __name__ == "__main__":
    main()
