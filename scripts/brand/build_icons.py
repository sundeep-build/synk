#!/usr/bin/env python3
"""Builds every app icon and in-app logo from the master logo artwork.

Source: assets/brand/source/synk_logo.png — the Synk "S" with a play button,
over the "Synk" wordmark, on black. This cuts the S out (its black background
becomes transparent; faint noise in it is dropped), then places it on a clean
solid tile in the app's background colour, at every size each platform needs.

Outputs (repo-relative):
  assets/brand/logo_mark.png, logo_tile.png, logo_full.png   in-app (Flutter)
  android/.../mipmap-*/ic_launcher{,_foreground,_monochrome}.png, launch_image.png
  ios/Runner/Assets.xcassets/AppIcon.appiconset/*, LaunchImage.imageset/*

Usage:  python3 -m pip install pillow && python3 scripts/brand/build_icons.py
For the sharpest store icons, replace the source with a 2048 px+ export.
"""

import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/brand/source/synk_logo.png"

TILE = (0x05, 0x05, 0x0B)  # SynkPalette.ink950 — the logo's own background

# Regions in the 1254 px source (with padding round the artwork).
MARK_BOX = (380, 205, 852, 735)
FULL_BOX = (290, 205, 965, 1022)

# Anything darker than LO is background; brighter than HI is fully the logo.
LO, HI = 24, 84
MASTER = 2048


def cut_out(box):
    """(premultiplied RGB over black, alpha) for a region of the source."""
    src = Image.open(SOURCE).convert("RGB").crop(box)
    r, g, b = src.split()
    brightest = ImageChops.lighter(ImageChops.lighter(r, g), b)
    alpha = brightest.point(lambda v: 0 if v <= LO else 255 if v >= HI else round((v - LO) * 255 / (HI - LO)))
    # Drop pixels the ramp let through but which are just background noise.
    rgb = Image.composite(src, Image.new("RGB", src.size), alpha)
    return rgb, alpha


def straight_rgba(rgb, alpha):
    """Un-premultiply (the source was drawn over black) for transparent PNGs."""
    c, a = rgb.tobytes(), alpha.tobytes()
    out = bytearray(len(a) * 4)
    for i, av in enumerate(a):
        if av:
            j = i * 3
            out[i * 4 : i * 4 + 4] = bytes((min(255, c[j] * 255 // av), min(255, c[j + 1] * 255 // av),
                                            min(255, c[j + 2] * 255 // av), av))
    return Image.frombytes("RGBA", rgb.size, bytes(out)).crop(alpha.getbbox())


def on_colour(rgb, alpha, colour):
    """Exact composite over a solid colour: src + colour·(1 − α)."""
    inv = ImageChops.invert(alpha)
    bg = ImageChops.multiply(Image.new("RGB", rgb.size, colour), Image.merge("RGB", (inv, inv, inv)))
    return ImageChops.add(rgb, bg).crop(alpha.getbbox())


def place(img, n, box_frac, fill=None):
    """[img] scaled to fit box_frac·n, centred on an n×n canvas."""
    box = n * box_frac
    s = min(box / img.width, box / img.height)
    m = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    canvas = Image.new("RGBA", (n, n), (*fill, 255) if fill else (0, 0, 0, 0))
    m = m.convert("RGBA")
    canvas.alpha_composite(m, ((n - m.width) // 2, (n - m.height) // 2))
    return canvas


def squircle(n, exponent=5.0):
    mask = Image.new("L", (n, n), 0)
    half = n / 2 - n * 0.01
    pts = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        c, s = math.cos(t), math.sin(t)
        pts.append((n / 2 + half * math.copysign(abs(c) ** (2 / exponent), c),
                    n / 2 + half * math.copysign(abs(s) ** (2 / exponent), s)))
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    return mask


def rounded(img):
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), squircle(img.width))
    return out


def save(img, path, px, opaque=False):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    out = img.resize((px, px), Image.LANCZOS) if img.size != (px, px) else img
    if opaque:
        flat = Image.new("RGB", out.size, TILE)
        flat.paste(out, (0, 0), out.convert("RGBA"))
        out = flat
    out.save(path, optimize=True)


def main():
    rgb, alpha = cut_out(MARK_BOX)
    mark = straight_rgba(rgb, alpha)
    mark_on_tile = on_colour(rgb, alpha, TILE)
    white = Image.new("RGBA", alpha.size, (255, 255, 255, 255))
    white.putalpha(alpha)
    mono = white.crop(alpha.getbbox())

    square = place(mark_on_tile, MASTER, 0.64, fill=TILE)
    tile = rounded(square)
    # Adaptive icon foreground (108 dp): the mark stays inside the 66 dp safe
    # circle, so no launcher mask shape clips it.
    fg = place(mark, MASTER, 0.5)
    mono_fg = place(mono, MASTER, 0.46)

    frgb, falpha = cut_out(FULL_BOX)
    straight_rgba(frgb, falpha).save(ROOT / "assets/brand/logo_full.png", optimize=True)

    save(tile, ROOT / "assets/brand/logo_tile.png", 512)
    save(place(mark, MASTER, 1.0), ROOT / "assets/brand/logo_mark.png", 512)

    res = ROOT / "android/app/src/main/res"
    for dpi, k in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
        save(tile, res / f"mipmap-{dpi}/ic_launcher.png", round(48 * k))
        save(fg, res / f"mipmap-{dpi}/ic_launcher_foreground.png", round(108 * k))
        save(mono_fg, res / f"mipmap-{dpi}/ic_launcher_monochrome.png", round(108 * k))
        save(tile, res / f"mipmap-{dpi}/launch_image.png", round(112 * k))

    icons = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for img in json.loads((icons / "Contents.json").read_text())["images"]:
        px = round(float(img["size"].split("x")[0]) * int(img["scale"][0]))
        save(square, icons / img["filename"], px, opaque=True)  # iOS rounds; store icon must be opaque

    launch = ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
    for suffix, k in {"": 1, "@2x": 2, "@3x": 3}.items():
        save(tile, launch / f"LaunchImage{suffix}.png", 112 * k)

    print("✓ icons built from", SOURCE.relative_to(ROOT))


if __name__ == "__main__":
    main()
