#!/bin/bash
# Draw the Lumen boot-splash emblem (light disc + light trail) for an Omarchy theme.
# Omarchy's boot splash shows a theme's unlock.png above the disk-password field.
# Usage: make-unlock.sh <accent-hex> <output.png>
set -euo pipefail
c="$1"; out="$2"
W=800; H=240; cx=400; cy=120
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# light disc: outer ring, inner ring, solid core
magick -size ${W}x${H} xc:none -fill none -stroke "$c" \
  -strokewidth 5 -draw "circle $cx,$cy $cx,$((cy - 92))" \
  -strokewidth 2 -draw "circle $cx,$cy $cx,$((cy - 62))" \
  -stroke none -fill "$c" -draw "circle $cx,$cy $cx,$((cy - 14))" \
  "$tmp/disc.png"

# light trail: a solid line, faded out toward both ends by an alpha mask
magick -size ${W}x${H} xc:none -stroke none -fill "$c" \
  -draw "rectangle 10,$((cy - 1)) 300,$((cy + 1))" \
  -draw "rectangle 500,$((cy - 1)) 790,$((cy + 1))" "$tmp/line.png"
magick -size ${H}x${W} gradient:black-white -rotate 90 \
  \( -size ${H}x${W} gradient:white-black -rotate 90 \) -compose darken -composite \
  -level 0,50% "$tmp/mask.png"
magick "$tmp/line.png" \( "$tmp/line.png" -alpha extract "$tmp/mask.png" -compose multiply -composite \) \
  -compose copy_opacity -composite "$tmp/trail.png"

magick "$tmp/trail.png" "$tmp/disc.png" -compose over -composite "$tmp/shape.png"

# soft glow underneath, crisp shape on top
magick "$tmp/shape.png" -blur 0x10 "$tmp/glow.png"
magick "$tmp/glow.png" "$tmp/shape.png" -compose over -composite "$out"
