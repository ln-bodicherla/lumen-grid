#!/usr/bin/env python3
"""Write Omarchy branding text art in the Lumen style.

  about.txt        light disc with a light trail (fastfetch / About logo)
  screensaver.txt  LUMEN wordmark over a light trail (idle screensaver)

Usage: make-branding.py <output dir>
The disc is drawn on a pixel grid and packed two pixels per character with half
blocks, so it stays round in a terminal (cells are about twice as tall as wide).
"""
import math, os, sys

W, H = 54, 46  # pixels -> 54 columns x 23 rows
ASPECT = 1.12  # half-block pixels render ~12% taller than wide in Ghostty / JetBrains Mono


def disc_pixels():
    cx, cy = W / 2 - 0.5, H / 2 - 1
    rings = [(19.5, 2.4), (13.0, 1.1)]  # (radius, half thickness)
    core = 4.2
    px = [[False] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            d = math.hypot(x - cx, (y - cy) * ASPECT)
            on = d <= core or any(abs(d - r) <= t for r, t in rings)
            # light trail: a thin horizontal line on both sides of the disc
            if y == cy and d > rings[0][0] + rings[0][1] + 1:
                on = True
            px[y][x] = on
    return px


def pack(px):
    rows = []
    for y in range(0, H, 2):
        line = ""
        for x in range(W):
            top, bottom = px[y][x], px[y + 1][x] if y + 1 < H else False
            line += "█" if top and bottom else "▀" if top else "▄" if bottom else " "
        rows.append(line.rstrip())
    while rows and not rows[-1]:
        rows.pop()
    while rows and not rows[0]:
        rows.pop(0)
    return "\n".join(rows) + "\n"


LETTERS = {  # 18 columns x 7 rows each, 4-column strokes
    "T": ["██████████████████"] + ["       ████       "] * 6,
    "R": ["████▀▀▀▀▀▀▀▀▀▀███▄", "████          ████", "████          ████", "████▄▄▄▄▄▄▄▄▄▄███▀",
          "████    ▀▀████▄   ", "████         ▀███▄", "████           ███"],
    "O": ["▄███▀▀▀▀▀▀▀▀▀▀███▄"] + ["████          ████"] * 5 + ["▀███▄▄▄▄▄▄▄▄▄▄███▀"],
    "N": ["████▄         ████", "██████▄       ████", "████ ▀██▄     ████", "████   ▀██▄   ████",
          "████     ▀██▄ ████", "████       ▀██████", "████         ▀████"],
}


def wordmark(text="LUMEN", gap=2):
    rows = [(" " * gap).join(LETTERS[c][r] for c in text) for r in range(7)]
    width = len(rows[0])
    return "\n".join(rows + ["", "━" * (width - 1) + "◆"]) + "\n"


def main(out):
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "about.txt"), "w") as f:
        f.write(pack(disc_pixels()))
    with open(os.path.join(out, "screensaver.txt"), "w") as f:
        f.write(wordmark())


if __name__ == "__main__":
    main(sys.argv[1])
