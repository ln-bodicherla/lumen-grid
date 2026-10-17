#!/usr/bin/env python3
"""Build "MartianMono Lumen": Martian Mono Nerd Font with the bar's icons redrawn as Lumen
light-line glyphs (thin strokes, rings, segmented bars, light-disc motifs).

Text glyphs are untouched; only the icon code points the Omarchy bar uses (battery,
Wi-Fi, Bluetooth, volume, mic, indicators, weather, agents, media, and the Lumen bar
modules) are replaced, keeping each icon's original box so layouts don't shift.

    make-lumen-icons.py [out_dir]    (default ~/.local/share/fonts/lumen)

Needs fontTools (installed in ~/.local/share/lumen-grid/venv by install.sh).
"""
import math
import os
import sys

from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

SRC_DIR = "/usr/share/fonts/TTF"
STYLES = ["Regular", "Medium", "Bold"]
FAMILY = "MartianMono Lumen"
W = 0.075      # stroke width (unit box)
THIN = 0.035


# ---------------------------------------------------------------- geometry (unit box, y up)
class Icon:
    def __init__(self):
        self.contours = []          # (points, is_hole)

    def poly(self, pts, hole=False):
        self.contours.append((pts, hole))

    def rect(self, x0, y0, x1, y1):
        self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])

    def line(self, x1, y1, x2, y2, w=W):
        dx, dy = x2 - x1, y2 - y1
        L = math.hypot(dx, dy) or 1e-6
        nx, ny = -dy / L * w / 2, dx / L * w / 2
        ex, ey = dx / L * w / 2, dy / L * w / 2      # square caps
        self.poly([(x1 - ex + nx, y1 - ey + ny), (x2 + ex + nx, y2 + ey + ny),
                   (x2 + ex - nx, y2 + ey - ny), (x1 - ex - nx, y1 - ey - ny)])

    def polyline(self, pts, w=W, closed=False):
        seq = pts + ([pts[0]] if closed else [])
        for a, b in zip(seq, seq[1:]):
            self.line(a[0], a[1], b[0], b[1], w)

    def circle(self, cx, cy, r, n=36):
        self.poly([(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)])

    def ring(self, cx, cy, r, w=W, n=48):
        self.circle(cx, cy, r + w / 2, n)
        self.poly([(cx + (r - w / 2) * math.cos(2 * math.pi * i / n), cy + (r - w / 2) * math.sin(2 * math.pi * i / n)) for i in range(n)], hole=True)

    def arc(self, cx, cy, r, a0, a1, w=W, n=24):
        a0, a1 = math.radians(a0), math.radians(a1)
        outer = [(cx + (r + w / 2) * math.cos(a0 + (a1 - a0) * i / n), cy + (r + w / 2) * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]
        inner = [(cx + (r - w / 2) * math.cos(a1 - (a1 - a0) * i / n), cy + (r - w / 2) * math.sin(a1 - (a1 - a0) * i / n)) for i in range(n + 1)]
        self.poly(outer + inner)

    def sector(self, cx, cy, r, a0, a1, n=24):
        a0, a1 = math.radians(a0), math.radians(a1)
        self.poly([(cx, cy)] + [(cx + r * math.cos(a0 + (a1 - a0) * i / n), cy + r * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)])

    def rrect(self, x0, y0, x1, y1, rad, w=W):
        """rounded-rectangle outline"""
        def path(x0, y0, x1, y1, rad):
            pts = []
            for cx, cy, a in ((x1 - rad, y0 + rad, -90), (x1 - rad, y1 - rad, 0), (x0 + rad, y1 - rad, 90), (x0 + rad, y0 + rad, 180)):
                for i in range(7):
                    t = math.radians(a + 90 * i / 6)
                    pts.append((cx + rad * math.cos(t), cy + rad * math.sin(t)))
            return pts
        h = w / 2
        self.poly(path(x0 - h, y0 - h, x1 + h, y1 + h, rad + h))
        self.poly(path(x0 + h, y0 + h, x1 - h, y1 - h, max(0.001, rad - h)), hole=True)

    def slash(self):
        self.line(0.14, 0.86, 0.86, 0.14, W)


# ---------------------------------------------------------------- icon designs
def battery(level, charging=False):
    i = Icon()
    i.rrect(0.06, 0.28, 0.82, 0.72, 0.07)
    i.rect(0.85, 0.42, 0.92, 0.58)
    if charging:
        i.poly([(0.48, 0.66), (0.32, 0.47), (0.44, 0.47), (0.38, 0.34), (0.56, 0.53), (0.44, 0.53)])
        i.rect(0.14, 0.36, 0.14 + 0.60 * level / 10, 0.39)
    else:
        lit = max(1, round(level / 2))
        seg, gap = (0.60 - 4 * 0.035) / 5, 0.035
        for s in range(lit):
            x = 0.14 + s * (seg + gap)
            i.rect(x, 0.36, x + seg, 0.64)
    return i


def wifi(strength, off=False):
    i = Icon()
    i.circle(0.5, 0.2, 0.06)
    for k, r in enumerate((0.27, 0.45, 0.63)):
        i.arc(0.5, 0.2, r, 45, 135, W if (not off and strength > k + 1) else THIN)
    if off:
        i.slash()
    return i


def ethernet():
    i = Icon()
    i.rrect(0.38, 0.66, 0.62, 0.88, 0.03)
    i.rrect(0.10, 0.12, 0.34, 0.34, 0.03)
    i.rrect(0.66, 0.12, 0.90, 0.34, 0.03)
    i.polyline([(0.5, 0.66), (0.5, 0.5), (0.22, 0.5), (0.22, 0.34)])
    i.line(0.5, 0.5, 0.78, 0.5)
    i.line(0.78, 0.5, 0.78, 0.34)
    return i


def bluetooth(state="on"):
    i = Icon()
    i.line(0.48, 0.12, 0.48, 0.88)
    i.polyline([(0.26, 0.30), (0.70, 0.66), (0.48, 0.88)])
    i.polyline([(0.26, 0.70), (0.70, 0.34), (0.48, 0.12)])
    if state == "connected":
        i.circle(0.12, 0.5, 0.05)
        i.circle(0.86, 0.5, 0.05)
    if state == "off":
        i.slash()
    return i


def speaker(level=0, mute=False):
    i = Icon()
    i.polyline([(0.08, 0.38), (0.24, 0.38), (0.44, 0.20), (0.44, 0.80), (0.24, 0.62), (0.08, 0.62)], closed=True)
    if mute:
        i.line(0.62, 0.36, 0.88, 0.64)
        i.line(0.62, 0.64, 0.88, 0.36)
    for k, r in enumerate((0.16, 0.30, 0.44)):
        if not mute and level > k:
            i.arc(0.48, 0.5, r, -45, 45)
    return i


def headphones():
    i = Icon()
    i.arc(0.5, 0.46, 0.34, 0, 180)
    i.rrect(0.12, 0.16, 0.28, 0.46, 0.05)
    i.rrect(0.72, 0.16, 0.88, 0.46, 0.05)
    return i


def speaker_box():
    i = Icon()
    i.rrect(0.24, 0.08, 0.76, 0.92, 0.06)
    i.ring(0.5, 0.36, 0.13)
    i.circle(0.5, 0.72, 0.05)
    return i


def display():
    i = Icon()
    i.rrect(0.08, 0.32, 0.92, 0.86, 0.05)
    i.line(0.5, 0.32, 0.5, 0.18)
    i.line(0.32, 0.16, 0.68, 0.16)
    return i


def camera():
    i = Icon()
    i.rrect(0.08, 0.24, 0.92, 0.76, 0.06)
    i.ring(0.5, 0.5, 0.14)
    i.circle(0.78, 0.66, 0.035)
    return i


def mic(off=False):
    i = Icon()
    i.rrect(0.38, 0.40, 0.62, 0.88, 0.12)
    i.arc(0.5, 0.52, 0.24, 200, 340)
    i.line(0.5, 0.28, 0.5, 0.14)
    i.line(0.34, 0.12, 0.66, 0.12)
    if off:
        i.slash()
    return i


def bell_off():
    i = Icon()
    i.arc(0.5, 0.56, 0.22, 0, 180)
    i.line(0.28, 0.56, 0.26, 0.32)
    i.line(0.72, 0.56, 0.74, 0.32)
    i.line(0.16, 0.30, 0.84, 0.30)
    i.circle(0.5, 0.18, 0.05)
    i.slash()
    return i


def coffee():
    i = Icon()
    i.polyline([(0.16, 0.62), (0.22, 0.16), (0.62, 0.16), (0.68, 0.62)], closed=True)
    i.arc(0.70, 0.42, 0.13, -80, 80)
    for x in (0.30, 0.42, 0.54):
        i.line(x, 0.72, x, 0.88, THIN * 1.4)
    return i


def nightlight():
    i = Icon()
    i.ring(0.5, 0.5, 0.32)
    i.sector(0.5, 0.5, 0.32, 90, 270)
    return i


def reminder():
    i = Icon()
    i.ring(0.5, 0.46, 0.32)
    i.line(0.5, 0.46, 0.5, 0.66)
    i.line(0.5, 0.46, 0.64, 0.38)
    i.line(0.42, 0.88, 0.58, 0.88)
    return i


def record():
    i = Icon()
    i.ring(0.5, 0.5, 0.34)
    i.circle(0.5, 0.5, 0.14)
    return i


def hourglass():
    i = Icon()
    i.line(0.24, 0.86, 0.76, 0.86)
    i.line(0.24, 0.14, 0.76, 0.14)
    i.polyline([(0.30, 0.86), (0.5, 0.5), (0.70, 0.86)])
    i.polyline([(0.30, 0.14), (0.5, 0.5), (0.70, 0.14)])
    return i


def robot():
    i = Icon()
    i.rrect(0.18, 0.18, 0.82, 0.70, 0.12)
    i.circle(0.38, 0.46, 0.06)
    i.circle(0.62, 0.46, 0.06)
    i.line(0.40, 0.30, 0.60, 0.30, THIN * 1.4)
    i.line(0.5, 0.70, 0.5, 0.84)
    i.ring(0.5, 0.88, 0.04, THIN)
    i.line(0.10, 0.40, 0.10, 0.52)
    i.line(0.90, 0.40, 0.90, 0.52)
    return i


# weather pieces
def sun(i, cx=0.5, cy=0.5, r=0.17, rays=True):
    i.ring(cx, cy, r)
    if rays:
        for k in range(8):
            a = 2 * math.pi * k / 8
            i.line(cx + (r + 0.09) * math.cos(a), cy + (r + 0.09) * math.sin(a), cx + (r + 0.17) * math.cos(a), cy + (r + 0.17) * math.sin(a), THIN * 1.6)


def moon(i, cx=0.5, cy=0.5, r=0.30):
    i.arc(cx, cy, r, 60, 300)
    i.arc(cx + r * 0.62, cy, r * 0.82, 105, 255, THIN * 1.5)


def cloud(i, dx=0.0, dy=0.0, s=1.0):
    f = lambda x, y: (0.5 + (x - 0.5) * s + dx, 0.5 + (y - 0.5) * s + dy)
    (bx0, by), (bx1, _) = f(0.16, 0.34), f(0.84, 0.34)
    i.line(bx0, by, bx1, by)
    c = f(0.30, 0.46); i.arc(c[0], c[1], 0.12 * s, 90, 270)
    c = f(0.52, 0.54); i.arc(c[0], c[1], 0.20 * s, 15, 165)
    c = f(0.72, 0.45); i.arc(c[0], c[1], 0.12 * s, -90, 75)


def weather(kind, night=False):
    i = Icon()
    if kind == "clear":
        (moon if night else sun)(i)
    elif kind == "partly":
        if night: moon(i, 0.34, 0.66, 0.18)
        else: sun(i, 0.32, 0.68, 0.12, rays=True)
        cloud(i, 0.08, -0.08, 0.8)
    elif kind == "cloud":
        cloud(i)
    else:
        if kind in ("showers", "flurries"):
            if night: moon(i, 0.30, 0.74, 0.14)
            else: sun(i, 0.28, 0.76, 0.10, rays=False)
        cloud(i, 0.04, 0.14, 0.85)
        if kind in ("rain", "showers"):
            for x in (0.32, 0.50, 0.68):
                i.line(x, 0.30, x - 0.06, 0.12, THIN * 1.6)
        elif kind in ("snow", "flurries", "heavysnow"):
            xs = (0.30, 0.50, 0.70) if kind != "heavysnow" else (0.24, 0.40, 0.56, 0.72)
            for k, x in enumerate(xs):
                i.circle(x, 0.20 if k % 2 == 0 else 0.12, 0.04)
        elif kind == "sleet":
            i.line(0.36, 0.30, 0.30, 0.12, THIN * 1.6)
            i.circle(0.52, 0.18, 0.04)
            i.line(0.68, 0.30, 0.62, 0.12, THIN * 1.6)
        elif kind == "storm":
            i.poly([(0.56, 0.32), (0.40, 0.16), (0.50, 0.16), (0.42, 0.02), (0.62, 0.20), (0.52, 0.20)])
    return i


def play():
    i = Icon(); i.polyline([(0.30, 0.18), (0.80, 0.5), (0.30, 0.82)], closed=True); return i


def pause():
    i = Icon(); i.rrect(0.24, 0.18, 0.40, 0.82, 0.03); i.rrect(0.60, 0.18, 0.76, 0.82, 0.03); return i


def skip(forward=True):
    i = Icon()
    if forward:
        i.polyline([(0.18, 0.2), (0.62, 0.5), (0.18, 0.8)], closed=True); i.line(0.78, 0.2, 0.78, 0.8)
    else:
        i.polyline([(0.82, 0.2), (0.38, 0.5), (0.82, 0.8)], closed=True); i.line(0.22, 0.2, 0.22, 0.8)
    return i


def music():
    i = Icon()
    i.ring(0.30, 0.24, 0.10); i.ring(0.74, 0.34, 0.10)
    i.line(0.40, 0.24, 0.40, 0.80); i.line(0.84, 0.34, 0.84, 0.88); i.line(0.40, 0.80, 0.84, 0.88)
    return i


def eye(off=False):
    i = Icon()
    i.arc(0.5, 0.10, 0.52, 50, 130)
    i.arc(0.5, 0.90, 0.52, 230, 310)
    i.ring(0.5, 0.5, 0.12)
    if off:
        i.slash()
    return i


def wallpaper():
    i = Icon()
    i.rrect(0.08, 0.16, 0.92, 0.84, 0.05)
    i.polyline([(0.14, 0.26), (0.38, 0.52), (0.54, 0.38), (0.86, 0.66)])
    i.ring(0.30, 0.66, 0.06, THIN)
    return i


def cpu():
    i = Icon()
    i.rrect(0.22, 0.22, 0.78, 0.78, 0.05)
    i.rrect(0.38, 0.38, 0.62, 0.62, 0.02, THIN)
    for t in (0.36, 0.5, 0.64):
        i.line(t, 0.78, t, 0.92, THIN * 1.4); i.line(t, 0.08, t, 0.22, THIN * 1.4)
        i.line(0.08, t, 0.22, t, THIN * 1.4); i.line(0.78, t, 0.92, t, THIN * 1.4)
    return i


def memory():
    i = Icon()
    i.rrect(0.06, 0.32, 0.94, 0.72, 0.04)
    for x in (0.20, 0.42, 0.64):
        i.rect(x, 0.44, x + 0.14, 0.60)
    for x in (0.16, 0.30, 0.44, 0.58, 0.72, 0.86):
        i.line(x, 0.32, x, 0.22, THIN * 1.4)
    return i


def thermometer():
    i = Icon()
    i.rrect(0.42, 0.34, 0.58, 0.90, 0.08)
    i.ring(0.5, 0.22, 0.14)
    i.circle(0.5, 0.22, 0.07)
    i.line(0.5, 0.26, 0.5, 0.62, THIN * 1.6)
    return i


ICONS = {}
for n, cp in enumerate([0xF007A, 0xF007B, 0xF007C, 0xF007D, 0xF007E, 0xF007F, 0xF0080, 0xF0081, 0xF0082, 0xF0079]):
    ICONS[cp] = battery(n + 1)
for n, cp in enumerate([0xF089C, 0xF0086, 0xF0087, 0xF0088, 0xF089D, 0xF0089, 0xF089E, 0xF008A, 0xF008B, 0xF0085]):
    ICONS[cp] = battery(n + 1, charging=True)
ICONS[0xF0084] = battery(5, charging=True)
for n, cp in enumerate([0xF092F, 0xF091F, 0xF0922, 0xF0925, 0xF0928]):
    ICONS[cp] = wifi(n + (1 if n else 0))
ICONS[0xF092E] = wifi(0, off=True)
ICONS[0xF0200] = ethernet()
ICONS[0xF00AF] = bluetooth("on")
ICONS[0xF00B1] = bluetooth("connected")
ICONS[0xF00B2] = bluetooth("off")
ICONS[0xF057F] = speaker(1)
ICONS[0xF0580] = speaker(2)
ICONS[0xF057E] = speaker(3)
ICONS[0xF0581] = speaker(0, mute=True)
ICONS[0xF075F] = speaker(0, mute=True)
ICONS[0xF02CB] = headphones()
ICONS[0xF04C3] = speaker_box()
ICONS[0xF0379] = display()
ICONS[0xF0100] = camera()
ICONS[0xF036C] = mic()
ICONS[0xF036D] = mic(off=True)
ICONS[0xF009B] = bell_off()
ICONS[0xF0176] = coffee()
ICONS[0xF050E] = nightlight()
ICONS[0xF088C] = reminder()
ICONS[0xF0EC2] = record()
ICONS[0xF051F] = hourglass()
ICONS[0xF16A3] = robot()
WEATHER = {0xE30D: ("clear", False), 0xE32B: ("clear", True), 0xE302: ("partly", False), 0xE32E: ("partly", True),
           0xE33D: ("cloud", False), 0xE308: ("showers", False), 0xE333: ("showers", True), 0xE30A: ("flurries", False),
           0xE327: ("flurries", True), 0xE3AD: ("sleet", False), 0xE31D: ("storm", False), 0xE318: ("rain", False),
           0xE31A: ("heavysnow", False)}
for cp, (k, night) in WEATHER.items():
    ICONS[cp] = weather(k, night)
ICONS[0xF040A] = play()
ICONS[0xF03E4] = pause()
ICONS[0xF04AD] = skip(True)
ICONS[0xF04AE] = skip(False)
ICONS[0xF075A] = music()
ICONS[0xF0208] = eye()
ICONS[0xF0209] = eye(off=True)
ICONS[0xF0E09] = wallpaper()
ICONS[0xF0EE0] = cpu()
ICONS[0xF035B] = memory()
ICONS[0xF050F] = thermometer()


# ---------------------------------------------------------------- font patching
def area(pts):
    return sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1])) / 2


def draw(icon, box, glyph_set):
    x0, y0, x1, y1 = box
    s = min(x1 - x0, y1 - y0) * 1.4           # larger, to read clearly next to text
    ox, oy = x0 + (x1 - x0 - s) / 2, y0 + (y1 - y0 - s) / 2
    pen = TTGlyphPen(glyph_set)
    for pts, hole in icon.contours:
        P = [(round(ox + x * s), round(oy + y * s)) for x, y in pts]
        # TrueType: filled contours clockwise, holes counter-clockwise
        cw = area(P) < 0
        if cw == hole:
            P = P[::-1]
        pen.moveTo(P[0])
        for p in P[1:]:
            pen.lineTo(p)
        pen.closePath()
    return pen.glyph()


def patch(src, dst, style):
    f = TTFont(src)
    cmap = f.getBestCmap()
    glyf = f["glyf"]
    # One standard icon box for every icon (taken from a full-size glyph), centered in each
    # glyph's advance width, so all redrawn icons come out the same size.
    hmtx = f["hmtx"]
    ref = glyf[cmap[0xF0EC2]]
    ref.recalcBounds(glyf)
    ref_w = hmtx[cmap[0xF0EC2]][0]
    done = 0
    for cp, icon in ICONS.items():
        name = cmap.get(cp)
        if not name:
            continue
        adv = hmtx[name][0]
        dx = (adv - ref_w) / 2
        box = (ref.xMin + dx, ref.yMin, ref.xMax + dx, ref.yMax)
        new = draw(icon, box, f.getGlyphSet())
        new.recalcBounds(glyf)
        glyf[name] = new
        done += 1
    # rename the family so it installs next to the original
    for rec in f["name"].names:
        if rec.nameID in (1, 4, 6, 16):
            old = rec.toUnicode()
            new = old.replace("MartianMono Nerd Font", FAMILY).replace("MartianMonoNerdFont", FAMILY.replace(" ", "")) \
                     .replace("MartianMono NF", FAMILY)
            rec.string = new
    if "CFF " in f:
        raise SystemExit("unexpected CFF font")
    f.save(dst)
    return done


def main():
    out = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/.local/share/fonts/lumen")
    os.makedirs(out, exist_ok=True)
    for style in STYLES:
        src = os.path.join(SRC_DIR, f"MartianMonoNerdFont-{style}.ttf")
        if not os.path.exists(src):
            continue
        n = patch(src, os.path.join(out, f"MartianMonoLumen-{style}.ttf"), style)
        print(f"{style}: {n} icons redrawn")


if __name__ == "__main__":
    main()
