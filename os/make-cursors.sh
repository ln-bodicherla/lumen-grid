#!/bin/bash
# Build the "Lumen" hyprcursor theme in the current Omarchy theme's accent color and apply it.
# Thin light-line cursors: hollow arrow at rest, lit (filled) arrow over links, an
# light-disc spinner while busy, orange "no entry". Scalable SVG, so it is crisp at any scale.
# Run by the Omarchy theme-set hook, so Program/Overload switching recolors the cursor too.
set -euo pipefail

# LUMEN_COLORS=<colors.toml> LUMEN_CURSOR_PREBUILD=1 builds into the cache only (no apply)
COLORS="${LUMEN_COLORS:-$HOME/.local/state/omarchy/current/theme/colors.toml}"
color() { grep -E "^$1[[:space:]]*=" "$COLORS" 2>/dev/null | head -1 | sed -E 's/.*"(#[0-9A-Fa-f]{6})".*/\1/'; }
C=$(color accent); C=${C:-#8ED7E6}          # light lines
O=$(color orange); O=${O:-#d19a66}          # warnings
D="#05080c"                                  # dark body

SIZE=${1:-24}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
src="$work/src"; mkdir -p "$src/hyprcursors"
dest="$HOME/.local/share/icons/Lumen"

apply_cursor() {
  # apply now (live); HYPRCURSOR_THEME in hyprland.lua keeps it across restarts
  hyprctl setcursor Lumen "$SIZE" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface cursor-theme Lumen 2>/dev/null || true
}

# Built sets are cached per color (and per version of this script), so a theme switch
# only copies a ready set instead of rebuilding it (~2 s).
cache="$HOME/.cache/lumen-cursors/${C#\#}-${O#\#}-$SIZE-$(md5sum "$0" | cut -c1-8)"
if [[ ${LUMEN_CURSOR_PREBUILD:-0} == 1 ]]; then
  [[ -d $cache ]] && exit 0
  dest="$(mktemp -d)/Lumen"
elif [[ -d $cache ]]; then
  rm -rf "$dest"; mkdir -p "$(dirname "$dest")"; cp -r "$cache" "$dest"
  apply_cursor
  echo "Lumen cursors in $C (cached) -> $dest"
  exit 0
fi

cat > "$src/manifest.hl" <<EOF
name = Lumen
description = Lumen light-line cursors in the Omarchy theme accent
version = 1
cursors_directory = hyprcursors
EOF

glow='<filter id="g" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="0.9"/></filter>'
svg() { echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"32\" height=\"32\" viewBox=\"0 0 32 32\"><defs>$glow</defs>$1</svg>"; }

# shape <name> <hotspot_x 0..1> <hotspot_y 0..1> <overrides;...> <svg-body> [more frames: <svg-body>...]
shape() {
  local name=$1 hx=$2 hy=$3 overrides=$4; shift 4
  local dir="$src/hyprcursors/$name"; mkdir -p "$dir"
  {
    echo "resize_algorithm = bilinear"
    echo "hotspot_x = $hx"
    echo "hotspot_y = $hy"
    IFS=';' read -ra names <<<"$overrides"
    for n in "${names[@]}"; do [[ -n $n ]] && echo "define_override = $n"; done
  } > "$dir/meta.hl"
  local i=0
  for body in "$@"; do
    svg "$body" > "$dir/$name-$i.svg"
    if (( $# > 1 )); then echo "define_size = 0, $name-$i.svg, 90" >> "$dir/meta.hl"
    else echo "define_size = 0, $name-$i.svg" >> "$dir/meta.hl"; fi
    i=$((i + 1))
  done
}

arrow_path="M4 3 L4 24.5 L9.6 19.4 L13.4 27.6 L16.8 26.1 L13.1 18 L20.6 18 Z"
arrow() {  # $1 = fill, $2 = fill opacity
  echo "<path d=\"$arrow_path\" fill=\"none\" stroke=\"$C\" stroke-width=\"2.2\" opacity=\"0.55\" filter=\"url(#g)\"/>
<path d=\"$arrow_path\" fill=\"$1\" fill-opacity=\"$2\" stroke=\"$C\" stroke-width=\"1.3\" stroke-linejoin=\"round\"/>"
}
line() { echo "<g stroke=\"$C\" stroke-linecap=\"round\" fill=\"none\"><g opacity=\"0.5\" stroke-width=\"2.4\" filter=\"url(#g)\">$1</g><g stroke-width=\"1.4\">$1</g></g>"; }
calc() { awk "BEGIN { print $1 }"; }
disc() {  # light disc spinner frame; $1 = rotation, $2 = cx, $3 = cy, $4 = radius
  echo "<g transform=\"rotate($1 $2 $3)\"><circle cx=\"$2\" cy=\"$3\" r=\"$4\" fill=\"$D\" fill-opacity=\"0.7\" stroke=\"$C\" stroke-opacity=\"0.3\" stroke-width=\"1.4\"/>
<path d=\"M$2 $(calc "$3 - $4") A$4 $4 0 0 1 $(calc "$2 + $4") $3\" fill=\"none\" stroke=\"$C\" stroke-width=\"1.8\" stroke-linecap=\"round\"/>
<circle cx=\"$2\" cy=\"$3\" r=\"$(calc "$4 * 0.3")\" fill=\"$C\"/></g>"
}

shape left_ptr 0.12 0.09 "default;arrow;top_left_arrow;left_arrow;context-menu;help;question_arrow;whats_this;copy;alias;dnd-move;dnd-copy;dnd-link;dnd-none;zoom-in;zoom-out" \
  "$(arrow "$D" 0.82)"
shape pointer 0.12 0.09 "hand1;hand2;pointing_hand;grab;openhand;link" \
  "$(arrow "$C" 0.9)"
shape text 0.5 0.5 "xterm;ibeam;vertical-text" \
  "$(line '<path d="M12 6 Q16 6 16 9 L16 23 Q16 26 12 26 M20 6 Q16 6 16 9 M16 23 Q16 26 20 26"/>')"
spin=(); for r in 0 45 90 135 180 225 270 315; do spin+=("$(disc $r 16 16 9)"); done
shape wait 0.5 0.5 "watch" "${spin[@]}"
busy=(); for r in 0 45 90 135 180 225 270 315; do busy+=("$(arrow "$D" 0.82)$(disc $r 23 24 5.5)"); done
shape progress 0.12 0.09 "left_ptr_watch;half-busy" "${busy[@]}"
shape crosshair 0.5 0.5 "cross;tcross;cell;plus;color-picker" \
  "$(line '<path d="M16 4 L16 12 M16 20 L16 28 M4 16 L12 16 M20 16 L28 16"/><circle cx="16" cy="16" r="1.4"/>')"
shape move 0.5 0.5 "fleur;all-scroll;size_all;grabbing;closedhand;dnd-ask" \
  "$(line '<path d="M16 4 L16 28 M4 16 L28 16 M16 4 L13 7 M16 4 L19 7 M16 28 L13 25 M16 28 L19 25 M4 16 L7 13 M4 16 L7 19 M28 16 L25 13 M28 16 L25 19"/>')"
shape ew-resize 0.5 0.5 "col-resize;sb_h_double_arrow;size_hor;h_double_arrow;e-resize;w-resize;left_side;right_side;split_h" \
  "$(line '<path d="M5 16 L27 16 M5 16 L9 12 M5 16 L9 20 M27 16 L23 12 M27 16 L23 20"/>')"
shape ns-resize 0.5 0.5 "row-resize;sb_v_double_arrow;size_ver;v_double_arrow;n-resize;s-resize;top_side;bottom_side;split_v" \
  "$(line '<path d="M16 5 L16 27 M16 5 L12 9 M16 5 L20 9 M16 27 L12 23 M16 27 L20 23"/>')"
shape nwse-resize 0.5 0.5 "size_fdiag;nw-resize;se-resize;top_left_corner;bottom_right_corner" \
  "$(line '<path d="M8 8 L24 24 M8 8 L8 14 M8 8 L14 8 M24 24 L24 18 M24 24 L18 24"/>')"
shape nesw-resize 0.5 0.5 "size_bdiag;ne-resize;sw-resize;top_right_corner;bottom_left_corner" \
  "$(line '<path d="M24 8 L8 24 M24 8 L18 8 M24 8 L24 14 M8 24 L14 24 M8 24 L8 18"/>')"
shape not-allowed 0.5 0.5 "no-drop;forbidden;crossed_circle;circle" \
  "<g fill=\"none\" stroke=\"$O\" stroke-linecap=\"round\"><circle cx=\"16\" cy=\"16\" r=\"9\" stroke-width=\"2.4\" opacity=\"0.5\" filter=\"url(#g)\"/><circle cx=\"16\" cy=\"16\" r=\"9\" stroke-width=\"1.5\"/><path d=\"M9.6 22.4 L22.4 9.6\" stroke-width=\"1.5\"/></g>"

rm -rf "$work/out"; mkdir -p "$work/out"
hyprcursor-util --create "$src" --output "$work/out" >/dev/null
built=$(find "$work/out" -mindepth 1 -maxdepth 1 -type d | head -1)
rm -rf "$dest"; mkdir -p "$(dirname "$dest")"
cp -r "$built" "$dest"
# XCursor copy of the same shapes, for apps that draw their own cursor (foot, GTK, Chromium...)
python3 "$(dirname "$(readlink -f "$0")")/xcursor.py" "$src/hyprcursors" "$dest"

mkdir -p "$(dirname "$cache")"; rm -rf "$cache"; cp -r "$dest" "$cache"
[[ ${LUMEN_CURSOR_PREBUILD:-0} == 1 ]] && { rm -rf "$(dirname "$dest")"; exit 0; }
apply_cursor
echo "Lumen cursors built in $C -> $dest"
