#!/usr/bin/env python3
"""Pack the Lumen cursor SVGs into XCursor files (for apps that draw their own cursor).

Usage: xcursor.py <hyprcursor working dir>/hyprcursors <theme dir>
Reads each shape's meta.hl (hotspot, frames, overrides), renders every frame with
rsvg-convert at several sizes, writes <theme dir>/cursors/<shape>, and symlinks
every override name to it. XCursor format: little-endian header + TOC + ARGB images.
"""
import io, os, struct, subprocess, sys
from PIL import Image

SIZES = [24, 32, 48, 64, 96]
IMAGE_TYPE = 0xFFFD0002


def render(svg_path, size):
    png = subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), svg_path],
                         check=True, capture_output=True).stdout
    return Image.open(io.BytesIO(png)).convert("RGBA")


def argb_premultiplied(img):
    raw, out = img.tobytes(), bytearray()
    for i in range(0, len(raw), 4):
        r, g, b, a = raw[i:i + 4]
        out += struct.pack("<I", (a << 24) | ((r * a // 255) << 16) | ((g * a // 255) << 8) | (b * a // 255))
    return bytes(out)


def read_meta(path):
    meta = {"hotspot_x": 0.0, "hotspot_y": 0.0, "frames": [], "overrides": []}
    for line in open(path):
        key, _, value = (part.strip() for part in line.partition("="))
        if key in ("hotspot_x", "hotspot_y"):
            meta[key] = float(value)
        elif key == "define_override":
            meta["overrides"].append(value)
        elif key == "define_size":
            parts = [p.strip() for p in value.split(",")]
            meta["frames"].append((parts[1], int(parts[2]) if len(parts) > 2 else 0))
    return meta


def write_cursor(shape_dir, meta, out_path):
    images = []
    for size in SIZES:
        for svg, delay in meta["frames"]:
            img = render(os.path.join(shape_dir, svg), size)
            xhot = min(size - 1, round(meta["hotspot_x"] * size))
            yhot = min(size - 1, round(meta["hotspot_y"] * size))
            header = struct.pack("<9I", 36, IMAGE_TYPE, size, 1, size, size, xhot, yhot, delay)
            images.append((size, header + argb_premultiplied(img)))
    ntoc = len(images)
    pos = 16 + ntoc * 12
    toc, body = b"", b""
    for size, chunk in images:
        toc += struct.pack("<3I", IMAGE_TYPE, size, pos + len(body))
        body += chunk
    with open(out_path, "wb") as f:
        f.write(b"Xcur" + struct.pack("<3I", 16, 0x10000, ntoc) + toc + body)


def main(src, theme):
    cursors = os.path.join(theme, "cursors")
    os.makedirs(cursors, exist_ok=True)
    for name in sorted(os.listdir(src)):
        shape_dir = os.path.join(src, name)
        meta = read_meta(os.path.join(shape_dir, "meta.hl"))
        write_cursor(shape_dir, meta, os.path.join(cursors, name))
        for alias in meta["overrides"]:
            link = os.path.join(cursors, alias)
            if os.path.lexists(link):
                os.remove(link)
            os.symlink(name, link)
    with open(os.path.join(theme, "index.theme"), "w") as f:
        f.write("[Icon Theme]\nName=Lumen\nComment=Lumen light-line cursors\nInherits=Adwaita\n")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
