#!/usr/bin/env python3
"""Render each Lumen theme's wallpaper and preview: a still of the Grid (perspective
floor, horizon glow, a mountain ridge with glowing crests) in the theme's accent.
Everything here is generated, so the repo ships no third-party images.

    make-backgrounds.py <themes dir>     writes <theme>/backgrounds/1-grid.png and <theme>/preview.png
"""
import math
import os
import random
import re
import sys

from PIL import Image, ImageDraw, ImageFilter

W, H = 2560, 1600


def accent(theme_dir):
    try:
        m = re.search(r'^accent\s*=\s*"#([0-9A-Fa-f]{6})"', open(os.path.join(theme_dir, "colors.toml")).read(), re.M)
        hx = m.group(1) if m else "8ED7E6"
    except OSError:
        hx = "8ED7E6"
    return tuple(int(hx[i:i + 2], 16) for i in (0, 2, 4))


def render(color):
    random.seed(7)
    base = Image.new("RGB", (W, H), (9, 11, 13))
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    g = ImageDraw.Draw(glow)
    horizon = int(H * 0.58)
    dim = lambda k: tuple(int(c * k) for c in color)

    # floor grid: lines converging on the vanishing point, rows packing toward the horizon
    vx = W // 2
    for i in range(-40, 41):
        x = vx + i * 220
        g.line([(vx + (x - vx) * 0.02, horizon), (x * 1.0 + (x - vx) * 4, H + 400)], fill=dim(0.55), width=3)
    for k in range(1, 40):
        z = k ** 1.9
        y = horizon + (H - horizon) * (z / 39 ** 1.9)
        g.line([(0, y), (W, y)], fill=dim(0.55 * (0.3 + 0.7 * k / 39)), width=3)

    # mountain ridge just above the horizon
    pts, x = [], 0
    while x <= W:
        h = 60 + 70 * abs(math.sin(x / 310.0)) + 40 * abs(math.sin(x / 97.0 + 1.3)) + random.uniform(0, 18)
        pts.append((x, horizon - h))
        x += 24
    ridge = [(0, horizon)] + pts + [(W, horizon)]
    g.polygon(ridge, fill=(6, 8, 10))
    g.line(pts, fill=dim(0.9), width=4)

    # a light wall racing in from the left
    for t in range(0, 600, 6):
        k = t / 600
        x0, y0 = 300 + t * 1.2, horizon + 210 + t * 0.32
        g.line([(x0, y0), (x0, y0 - 70 - 40 * k)], fill=dim(0.25 + 0.75 * k), width=7)

    # crisp lines plus a soft bloom of the same lines
    bloom = glow.filter(ImageFilter.GaussianBlur(14))
    out = Image.blend(base, glow, 0.85)
    out = Image.blend(out, bloom, 0.35)

    # horizon haze
    haze = Image.new("RGB", (W, H), color)
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    for dy in range(-120, 121):
        md.line([(0, horizon + dy), (W, horizon + dy)], fill=int(70 * math.exp(-abs(dy) / 40)))
    out = Image.composite(haze, out, mask)
    return out


def main():
    themes = sys.argv[1]
    for name in sorted(os.listdir(themes)):
        d = os.path.join(themes, name)
        if not name.startswith("lumen-") or not os.path.isdir(d):
            continue
        img = render(accent(d))
        os.makedirs(os.path.join(d, "backgrounds"), exist_ok=True)
        img.save(os.path.join(d, "backgrounds", "1-grid.png"), optimize=True)
        img.resize((W // 2, H // 2)).save(os.path.join(d, "preview.png"), optimize=True)
        print(f"{name}: wallpaper and preview")


if __name__ == "__main__":
    main()
