#!/usr/bin/env python3
"""Builds the Google Play store graphics from the master logo artwork.

Outputs, in fastlane `supply` layout so the folder can be uploaded as-is later:
  fastlane/metadata/android/en-US/images/icon.png            512×512, opaque
  fastlane/metadata/android/en-US/images/featureGraphic.png  1024×500, opaque

The listing text sits beside them (title.txt, short_description.txt,
full_description.txt). The icon is the launcher/iOS icon as a full-bleed square:
Play rounds the corners itself. Montserrat, the app font, is downloaded once
into build/fonts.

Usage:  python3 -m pip install pillow && python3 scripts/brand/build_play_assets.py
"""

import math
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from build_icons import FULL_BOX, MARK_BOX, MASTER, ROOT, TILE, cut_out, on_colour, place, save, straight_rgba

OUT = ROOT / "fastlane/metadata/android/en-US/images"
FONTS = ROOT / "build/fonts"
FONT_URL = "https://raw.githubusercontent.com/JulietaUla/Montserrat/master/fonts/ttf/Montserrat-{}.ttf"

# SynkPalette (lib/core/design_system/tokens.dart)
INK950 = (0x0B, 0x0C, 0x1F)
INK600 = (0x36, 0x3B, 0x66)
INK300 = (0xB4, 0xB6, 0xCF)
INK50 = (0xF5, 0xF5, 0xFC)
BRAND = (0x78, 0x44, 0xF9)
CYAN = (0x33, 0xCF, 0xFB)

W, H, K = 1024, 500, 2  # feature graphic, drawn at 2× then downsampled


def font(weight, px):
    path = FONTS / f"Montserrat-{weight}.ttf"
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(FONT_URL.format(weight), path)
    return ImageFont.truetype(str(path), round(px * K))


def feature_graphic():
    img = Image.new("RGBA", (W * K, H * K), (*INK950, 255))
    d = ImageDraw.Draw(img)

    # Logo (S + wordmark) on the left.
    logo = straight_rgba(*cut_out(FULL_BOX))
    lh = 340 * K
    logo = logo.resize((round(logo.width * lh / logo.height), lh), Image.LANCZOS)
    img.alpha_composite(logo, (round(96 * K), (H * K - lh) // 2))

    # Headline: accent bar, heavy first word, light rest.
    x, gap = 478 * K, 18 * K
    heavy, light, sub = font("ExtraBold", 54), font("Light", 54), font("SemiBold", 21)
    line_h = round(66 * K)
    top = round(126 * K)
    d.rounded_rectangle((x, top + 8 * K, x + 6 * K, top + 2 * line_h - 10 * K), radius=3 * K, fill=BRAND)
    tx = x + gap + 6 * K
    d.text((tx, top), "Listen", font=heavy, fill=INK50)
    d.text((tx + d.textlength("Listen ", font=heavy), top), "together,", font=light, fill=INK50)
    d.text((tx, top + line_h), "in sync.", font=light, fill=INK50)
    d.text((tx, top + 2 * line_h + 18 * K), "Music rooms  ·  Live radio  ·  Huddles", font=sub, fill=INK300)

    # Waveform progress bar, as in the player.
    bars, bw, bgap, wy, played = 44, 4 * K, 5 * K, top + 2 * line_h + 92 * K, 0.42
    for i in range(bars):
        h = (10 + 26 * abs(math.sin(i * 0.55) * math.cos(i * 0.21))) * K
        bx = tx + i * (bw + bgap)
        d.rounded_rectangle((bx, wy - h / 2, bx + bw, wy + h / 2), radius=bw / 2,
                            fill=CYAN if i < bars * played else INK600)

    return img.convert("RGB").resize((W, H), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rgb, alpha = cut_out(MARK_BOX)
    save(place(on_colour(rgb, alpha, TILE), MASTER, 0.64, fill=TILE), OUT / "icon.png", 512, opaque=True)
    feature_graphic().save(OUT / "featureGraphic.png", optimize=True)
    print("✓ Play assets built in", OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
