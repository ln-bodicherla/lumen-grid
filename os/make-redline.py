#!/usr/bin/env python3
"""Build the red Lumen Redline theme from Lumen Overload by rotating every color's hue
from Overload's amber/orange to Redline red. Used by lumen-alert for grid alerts.

    make-redline.py <themes dir>     reads <dir>/lumen-overload, writes <dir>/lumen-redline
"""
import colorsys
import re
import shutil
import sys
from pathlib import Path

from PIL import Image

HUE_SHIFT = -40 / 360     # amber (44°) -> red (4°), orange (26°) -> crimson (346°)
SAT_BOOST = 1.1


def shift(r, g, b):
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    if s < 0.08:              # leave greys and near-blacks alone
        return r, g, b
    r, g, b = colorsys.hsv_to_rgb((h + HUE_SHIFT) % 1, min(1, s * SAT_BOOST), v)
    return round(r * 255), round(g * 255), round(b * 255)


def shift_hex(m):
    hx = m.group(1)
    r, g, b = (int(hx[i:i + 2], 16) for i in (0, 2, 4))
    out = "%02x%02x%02x" % shift(r, g, b)
    return m.group(0).replace(hx, out.upper() if hx.isupper() else out)


def shift_text(text):
    # #RRGGBB and rgba(RRGGBBAA): only the first six hex digits are color
    text = re.sub(r"#([0-9a-fA-F]{6})(?![0-9a-fA-F])", shift_hex, text)
    return re.sub(r"rgba\(([0-9a-fA-F]{6})[0-9a-fA-F]{2}\)", shift_hex, text)


def shift_image(src, dst):
    im = Image.open(src)
    if im.mode == "P" or "transparency" in im.info:
        im = im.convert("RGBA")
    alpha = im.getchannel("A") if im.mode in ("RGBA", "LA") else None
    h, s, v = im.convert("RGB").convert("HSV").split()
    h = h.point(lambda x: int(x + HUE_SHIFT * 256) % 256)
    s = s.point(lambda x: min(255, int(x * SAT_BOOST)))
    out = Image.merge("HSV", (h, s, v)).convert("RGB")
    if alpha is not None:
        out.putalpha(alpha)
    out.save(dst)


def main():
    themes = Path(sys.argv[1]).expanduser()
    src, dst = themes / "lumen-overload", themes / "lumen-redline"
    shutil.rmtree(dst, ignore_errors=True)
    for path in src.rglob("*"):
        out = dst / path.relative_to(src)
        if path.is_dir():
            out.mkdir(parents=True, exist_ok=True)
            continue
        out.parent.mkdir(parents=True, exist_ok=True)
        if path.suffix.lower() in (".png", ".jpg", ".jpeg"):
            out = out.with_name(out.name.replace("orange", "red"))
            shift_image(path, out)
        elif path.suffix in (".toml", ".css", ".conf", ".lua", ".ini"):
            out.write_text(shift_text(path.read_text()).replace("Overload", "Redline").replace("Overload", "Redline"))
        else:
            shutil.copy2(path, out)


if __name__ == "__main__":
    main()
