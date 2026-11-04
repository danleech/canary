#!/usr/bin/env python3
"""Turn CI simulator screenshots into captioned App Store screenshots.

    python3 make_screenshots.py <shots dir> <out dir> --fonts <dir with Inter TTFs>

<shots dir> holds the PNGs from ios/ci/shoot.sh (every shots-N artifact
unpacked into one folder). Each output keeps its source's exact pixel size,
which is one of the sizes App Store Connect accepts, and is saved as an RGB
PNG with no alpha channel, as Apple requires.

Captions describe what the app shows. They never call a level a forecast or
advice (Canary's editorial rule 1), and they use no Apple badge phrases.
Inter is used under the SIL Open Font Licence.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# (output folder, source prefix, App Store display name)
SETS = [
    ("iphone-6.9", "iphone-18-pro-max-", "iPhone 6.9-inch (1320 × 2868)"),
    ("iphone-6.3", "iphone-17-", "iPhone 6.3-inch (1206 × 2622)"),
    ("duo-outer", "iphone-duo-closed-", "iPhone Duo outer display (1398 × 2034)"),
    ("duo-inner", "iphone-duo-flat-portrait-", "iPhone Duo inner display (2007 × 2853)"),
    ("duo-inner-landscape", "iphone-duo-flat-", "iPhone Duo inner display, landscape (2853 × 2007)"),
]

# (source screen, headline, subline, background tint)
IPHONE = [
    ("summary", "Where the world\nneeds attention", "Nearly 90 global risk signals at a glance", "teal"),
    ("signal", "Every level,\nexplained", "The reasons, the rubric and the sources", "blue"),
    ("world", "One number for\nthe whole board", "The World State, and how it has moved", "mint"),
    ("browse", "Eleven areas,\none calm view", "From markets to natural hazards", "indigo"),
    ("changes", "See what changed,\nand when", "Every move up or down, with the reason", "orange"),
    ("showcase", "Glance from your\nHome Screen", "Widgets for the Home and Lock Screen", "pink"),
    ("summary-dark", "At home in\nDark Mode", "With Dynamic Type and VoiceOver too", "dark"),
]

DUO = [
    ("summary", "More room when\nyou unfold", "A sidebar on the inner display", "teal"),
    ("signal", "Every level,\nexplained", "The reasons, the rubric and the sources", "blue"),
    ("world", "One number for\nthe whole board", "The World State, and how it has moved", "mint"),
    ("domain", "Eleven areas,\none calm view", "From markets to natural hazards", "indigo"),
]

DUO_OUTER = [
    ("summary", "Where the world\nneeds attention", "Nearly 90 global risk signals at a glance", "teal"),
    ("signal", "Every level,\nexplained", "The reasons, the rubric and the sources", "blue"),
    ("world", "One number for\nthe whole board", "The World State, and how it has moved", "mint"),
    ("browse", "Eleven areas,\none calm view", "From markets to natural hazards", "indigo"),
]

# Soft pastel washes from Apple's palette (top colour, bottom colour).
TINTS = {
    "teal": ((222, 245, 247), (250, 252, 253)),
    "blue": ((224, 236, 255), (250, 251, 255)),
    "mint": ((220, 247, 238), (250, 253, 251)),
    "indigo": ((233, 232, 252), (251, 251, 255)),
    "orange": ((255, 238, 220), (255, 252, 248)),
    "pink": ((252, 230, 242), (255, 251, 253)),
    "dark": ((30, 34, 44), (8, 9, 12)),
}


def font(dirpath: Path, name: str, size: int) -> ImageFont.FreeTypeFont:
    for candidate in (dirpath / name, *dirpath.rglob(name)):
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    sys.exit(f"font {name} not found under {dirpath}")


def background(size: tuple[int, int], tint: str) -> Image.Image:
    w, h = size
    top, bottom = TINTS[tint]
    grad = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        grad.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return grad.resize((w, h), Image.BICUBIC)


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def compose(src: Path, dst: Path, headline: str, subline: str, tint: str, fonts: Path) -> None:
    shot = Image.open(src).convert("RGB")
    w, h = shot.size
    landscape = w > h
    canvas = background((w, h), tint)
    dark = tint == "dark"
    ink = (245, 245, 247) if dark else (29, 29, 31)
    soft = (174, 174, 178) if dark else (99, 99, 102)

    # Type scales with the short side, so every size reads the same.
    short = min(w, h)
    head_size = round(short * (0.066 if landscape else 0.072))
    sub_size = round(short * (0.033 if landscape else 0.036))
    head_font = font(fonts, "InterDisplay-Bold.ttf", head_size)
    sub_font = font(fonts, "Inter-Medium.ttf", sub_size)
    draw = ImageDraw.Draw(canvas)

    if landscape:
        headline = headline.replace("\n", " ")
    top = round(h * (0.07 if landscape else 0.065))
    spacing = round(head_size * 0.16)
    draw.multiline_text((w / 2, top), headline, font=head_font, fill=ink, anchor="ma",
                        align="center", spacing=spacing)
    box = draw.multiline_textbbox((w / 2, top), headline, font=head_font, anchor="ma",
                                  align="center", spacing=spacing)
    sub_top = box[3] + round(sub_size * 0.75)
    draw.text((w / 2, sub_top), subline, font=sub_font, fill=soft, anchor="ma")
    text_bottom = sub_top + round(sub_size * 1.3)

    # The screen, scaled down under the caption and running off the bottom edge.
    gap = round(short * 0.05)
    scale = 0.78 if landscape else 0.84
    sw, sh = round(w * scale), round(h * scale)
    screen = shot.resize((sw, sh), Image.LANCZOS)
    radius = round(min(sw, sh) * 0.085)
    screen = rounded(screen, radius)
    x = (w - sw) // 2
    y = text_bottom + gap

    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + gap // 4, x + sw, y + sh), radius,
                                             fill=(0, 0, 0, 110 if dark else 46))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=round(short * 0.03)))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow)
    # A hairline so a white screen doesn't melt into a pale background.
    edge = Image.new("RGBA", (sw + 4, sh + 4), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle((0, 0, sw + 3, sh + 3), radius + 2,
                                           fill=(255, 255, 255, 40) if dark else (0, 0, 0, 22))
    canvas.alpha_composite(edge, (x - 2, y - 2))
    canvas.alpha_composite(screen, (x, y))

    dst.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(dst, "PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("shots", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--fonts", type=Path, required=True)
    args = parser.parse_args()

    made, missing = [], []
    for folder, prefix, label in SETS:
        plan = DUO_OUTER if folder == "duo-outer" else DUO if folder.startswith("duo-inner") else IPHONE
        n = 0
        for screen, headline, subline, tint in plan:
            src = args.shots / f"{prefix}{screen}.png"
            if not src.exists():
                missing.append(src.name)
                continue
            n += 1
            dst = args.out / folder / f"{n:02d}-{screen}.png"
            compose(src, dst, headline, subline, tint, args.fonts)
            made.append(f"{dst.relative_to(args.out)}  {Image.open(dst).size}")
        print(f"{label}: {n}")
    print("\n".join(made))
    if missing:
        print("missing:", ", ".join(missing))


if __name__ == "__main__":
    main()
