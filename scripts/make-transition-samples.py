#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10", "numpy>=1.26"]
# ///
"""Draw the two sample stills the Transitions panel previews run between (BashCut/Core/Engine/TransitionSamples).

    uv run scripts/make-transition-samples.py

Flat illustrations made here, so they carry no licence: a warm sunset over hills (the outgoing picture) and a cool
lake under snowy peaks (the incoming one). Different colours and shapes, so a fade, a wipe or a turn reads at tile
size. 320x180 JPEG, about 10 KB each.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 320, 180
OUT = Path(__file__).resolve().parent.parent / "BashCut/Core/Engine/TransitionSamples"


def gradient(top, bottom):
    t = np.linspace(0, 1, H, dtype=np.float32)[:, None, None]
    rows = np.array(top, np.float32) * (1 - t) + np.array(bottom, np.float32) * t
    return Image.fromarray(np.repeat(rows, W, 1).astype(np.uint8))


def ridge(draw, base, amplitude, period, phase, colour):
    xs = np.arange(0, W + 1, 4)
    ys = base - amplitude * (0.6 * np.sin(xs / period + phase) + 0.4 * np.sin(xs / (period * 0.43) + phase * 2.1))
    draw.polygon([(0, H)] + list(zip(xs.tolist(), ys.tolist())) + [(W, H)], fill=colour)


def sunset():
    image = gradient((252, 196, 92), (232, 86, 96))
    draw = ImageDraw.Draw(image)
    draw.ellipse((196, 46, 268, 118), fill=(255, 238, 170))
    ridge(draw, 120, 14, 40, 0.3, (176, 64, 92))
    ridge(draw, 140, 12, 30, 1.7, (112, 42, 82))
    ridge(draw, 162, 9, 22, 2.9, (58, 26, 58))
    for x, y in ((70, 50), (92, 40), (110, 58)):
        draw.line((x - 7, y - 3, x, y, x + 7, y - 3), fill=(90, 40, 60), width=2)
    return image


def lake():
    image = gradient((92, 170, 232), (196, 230, 246))
    draw = ImageDraw.Draw(image)
    for cx, cy, r in ((60, 36, 14), (78, 32, 18), (98, 38, 12), (228, 24, 10), (244, 20, 14)):
        draw.ellipse((cx - r, cy - r * 0.7, cx + r, cy + r * 0.7), fill=(250, 252, 255))
    peaks = [(10, 118, 70), (120, 118, 150), (200, 118, 95), (300, 118, 140)]
    for x, base, top in peaks:
        draw.polygon([(x - 70, base), (x, base - top + 40), (x + 70, base)], fill=(44, 102, 120))
        draw.polygon([(x - 16, base - top + 56), (x, base - top + 40), (x + 16, base - top + 56)], fill=(240, 248, 252))
    draw.rectangle((0, 118, W, H), fill=(28, 128, 150))
    for y in range(126, H, 9):
        draw.line((20 + y % 40, y, 120 + y % 40, y), fill=(120, 196, 210), width=1)
    draw.polygon([(150, 150), (176, 150), (170, 158), (156, 158)], fill=(250, 250, 250))
    draw.polygon([(163, 128), (163, 149), (176, 149)], fill=(255, 255, 255))
    return image


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, image in (("outgoing", sunset()), ("incoming", lake())):
        path = OUT / f"{name}.jpg"
        image.filter(ImageFilter.SMOOTH).save(path, quality=82, optimize=True, progressive=False)
        print(path.name, path.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
