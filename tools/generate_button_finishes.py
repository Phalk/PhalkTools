"""Original alpha overlays for action buttons; no Masque assets are copied.

Each finish has separate BLEND shade and specular layers. Keeping them
separate preserves the icon's saturation rather than covering it in gray.
"""
import math
from pathlib import Path
import struct

SIZE = 128
OUTPUT = Path(__file__).resolve().parents[1] / "Media" / "Buttons"
STYLES = ("Gloss", "Glass", "Crystal", "Lacquer", "Chrome", "Obsidian", "Soft")


def clamp(v):
    return max(0.0, min(1.0, v))


def gaussian(x, center, width):
    return math.exp(-((x - center) / width) ** 2)


def smoothstep(low, high, value):
    t = clamp((value - low) / (high - low))
    return t * t * (3 - 2 * t)


def layers(style, u, v):
    # Reflections fade BEFORE the silhouette. No luminous perimeter or
    # one-pixel lines: these became white halos when downsampled in-game.
    edge = min(u, 1-u, v, 1-v)
    fade = smoothstep(0.018, 0.105, edge)
    lateral = 0.55 + 0.45 * gaussian(u, 0.38, 0.55)
    glint = gaussian(u, 0.28, 0.21) * gaussian(v, 0.16, 0.095)
    shade = 0.10 * smoothstep(0.28, 0.95, v)
    tint = (1.0, 1.0, 1.0)
    if style == "Gloss":
        horizon = 0.43 + 0.10 * (2*u-1)**2
        cap = 1-smoothstep(horizon-0.045, horizon+0.045, v)
        light = (0.28 + 0.14 * (1-v)) * cap * lateral + 0.17 * glint
        shade += 0.10 * gaussian(v, 0.66, 0.22)
    elif style == "Glass":
        horizon = 0.43 + 0.15 * (2*u-1)**2
        cap = 1-smoothstep(horizon-0.035, horizon+0.045, v)
        light = (0.19+0.20*gaussian(v, 0.19, 0.20))*cap*lateral
        light += 0.12*gaussian(v, horizon, 0.037)*gaussian(u, 0.5, 0.5) + 0.16*glint
        shade += 0.12*gaussian(v, 0.7, 0.28)
        tint = (0.94, 0.98, 1.0)
    elif style == "Crystal":
        diagonal = u + 0.66*v
        light = 0.39*gaussian(diagonal, 0.53, 0.13)
        light += 0.12*gaussian(diagonal, 0.83, 0.052) + 0.07*gaussian(v, 0.18, 0.18)
        shade += 0.10*gaussian(v-u, 0.40, 0.40)
        tint = (0.94, 0.98, 1.0)
    elif style == "Lacquer":
        horizon = 0.36 + 0.10*(2*u-1)**2
        cap = 1-smoothstep(horizon-0.023, horizon+0.038, v)
        light = (0.34+0.11*gaussian(v, 0.17, 0.13))*cap*lateral + 0.20*glint
        light += 0.055*gaussian(v, 0.85, 0.07)*gaussian(u, 0.55, 0.4)
        shade += 0.16*gaussian(v, 0.59, 0.23)
    elif style == "Chrome":
        light = (0.37*gaussian(v, 0.22, 0.10)+0.17*gaussian(v, 0.74, 0.095))*lateral
        light += 0.07*glint
        shade += 0.15*gaussian(v, 0.47, 0.16)
        tint = (0.96, 0.98, 1.0)
    elif style == "Obsidian":
        horizon = 0.36+0.12*(2*u-1)**2
        cap = 1-smoothstep(horizon-0.035, horizon+0.05, v)
        light = 0.24*cap*lateral + 0.17*gaussian(u+v*0.4, 0.34, 0.085)
        shade += 0.20*gaussian(v, 0.63, 0.38)
        tint = (0.92, 0.94, 1.0)
    elif style == "Soft":
        light = 0.19*gaussian(v, 0.29, 0.29)*lateral
        shade *= 0.7
    else:
        raise ValueError(style)
    return clamp(shade)*smoothstep(0, 0.04, edge), min(0.62, light)*fade, tint


def write_tga(path, pixels):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    path.write_bytes(header + pixels)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for style in STYLES:
        dark, bright = bytearray(), bytearray()
        for y in range(SIZE):
            for x in range(SIZE):
                shade, light, tint = layers(style, (x + .5) / SIZE, (y + .5) / SIZE)
                dark.extend((0, 0, 0, round(255 * shade)))
                bright.extend((*[round(255 * c) for c in reversed(tint)], round(255 * light)))
        write_tga(OUTPUT / f"{style}-Shade.tga", dark)
        write_tga(OUTPUT / f"{style}-Light.tga", bright)


if __name__ == "__main__":
    main()
