#!/usr/bin/env python3
"""Frames raw phone captures as 1080×1920 (9:16) Play Store screenshots.

Input:  fastlane/raw_screenshots/<n>_<name>.png   (adb exec-out screencap -p)
Output: fastlane/metadata/android/en-US/images/phoneScreenshots/<n>.png

Each gets a caption (heavy first word, light rest, beside an accent bar) over
the screen, which bleeds off the bottom. The status bar is cropped away.

Usage:  python3 scripts/brand/build_play_screenshots.py
"""

from PIL import Image, ImageDraw

from build_icons import ROOT
from build_play_assets import BRAND, INK50, INK950, K as FONT_SCALE, font

RAW = ROOT / "fastlane/raw_screenshots"
OUT = ROOT / "fastlane/metadata/android/en-US/images/phoneScreenshots"
FRAME = (0x22, 0x26, 0x4B)  # SynkPalette.ink800

# file stem → (heavy word, rest of line 1, line 2)
CAPTIONS = {
    "1_room": ("Listen", "together,", "in sync."),
    "2_home": ("Start", "a room,", "invite your crew."),
    "3_queue": ("Everyone", "adds", "to the queue."),
    "4_trending": ("Trending", "music", "for your country."),
    "5_radio": ("Live", "radio from", "around the world."),
    "6_vibes": ("Every", "vibe,", "one tap away."),
}

W, H = 1080, 1920  # Play: 9:16
STATUS_BAR = 110  # px cropped off the top of a 1080×2400 capture
SCREEN_W, SCREEN_TOP, BEZEL, RADIUS = 800, 420, 14, 64


def frame(raw, caption):
    img = Image.new("RGB", (W, H), INK950)
    d = ImageDraw.Draw(img)

    heavy_word, rest, line2 = caption
    heavy, light = font("ExtraBold", 72 / FONT_SCALE), font("Light", 72 / FONT_SCALE)
    x, top, line_h = 110, 120, 92
    d.rounded_rectangle((x - 34, top + 14, x - 26, top + 2 * line_h - 8), radius=4, fill=BRAND)
    d.text((x, top), heavy_word, font=heavy, fill=INK50)
    d.text((x + d.textlength(heavy_word + " ", font=heavy), top), rest, font=light, fill=INK50)
    d.text((x, top + line_h), line2, font=light, fill=INK50)

    shot = Image.open(raw).convert("RGB")
    shot = shot.crop((0, STATUS_BAR, shot.width, shot.height))
    shot = shot.resize((SCREEN_W, round(shot.height * SCREEN_W / shot.width)), Image.LANCZOS)
    left = (W - SCREEN_W) // 2
    d.rounded_rectangle((left - BEZEL, SCREEN_TOP - BEZEL, left + SCREEN_W + BEZEL, H + RADIUS),
                        radius=RADIUS + BEZEL, fill=FRAME)
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, shot.width, shot.height + RADIUS), radius=RADIUS, fill=255)
    img.paste(shot, (left, SCREEN_TOP), mask)
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for raw in sorted(RAW.glob("*.png")):
        n = raw.stem.split("_")[0]
        frame(raw, CAPTIONS[raw.stem]).save(OUT / f"{n}.png", optimize=True)
    print("✓", len(list(OUT.glob("*.png"))), "screenshots in", OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
