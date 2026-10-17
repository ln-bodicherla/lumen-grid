#!/bin/bash
# Rebuild Papirus-Lumen-Cyan / Papirus-Lumen-Gold: Papirus-Dark with translucent
# Lumen-colored folders, installed to ~/.local/share/icons (no sudo needed).
# Usage: build-lumen-icons.sh [front-opacity] [back-opacity] [paper-opacity]   (default 0.60 0.45 0.30)
set -e
FRONT_OPACITY=${1:-0.60}
BACK_OPACITY=${2:-0.45}
PAPER_OPACITY=${3:-0.30}
P=/usr/share/icons/Papirus

make_variant() {  # name front back glyph
  local name=$1 front=$2 back=$3 glyph=$4 out=~/.local/share/icons/$1
  rm -rf "$out"; mkdir -p "$out"
  for dir in $P/*/places; do
    size=$(basename "$(dirname "$dir")"); [[ -L $P/$size ]] && continue
    mkdir -p "$out/$size/places"
    for f in "$dir"/*.svg; do
      n=$(basename "$f"); t=$(basename "$(readlink -f "$f")")
      [[ $t =~ ^(folder|user)-blue[-.] ]] || continue
      sed -e "s/fill:#5294e2/fill:$front;fill-opacity:$FRONT_OPACITY/Ig" \
          -e "s/fill:#4877b1/fill:$back;fill-opacity:$BACK_OPACITY/Ig" \
          -e "s/fill:#e4e4e4/fill:#e4e4e4;fill-opacity:$PAPER_OPACITY/Ig" \
          -e "s/#5294e2/$front/Ig" -e "s/#4877b1/$back/Ig" -e "s/#1d344f/$glyph/Ig" \
          "$(readlink -f "$f")" > "$out/$size/places/$n"
    done
  done
  for l in $P/*@2x; do
    [[ -L $l && -d $out/$(readlink "$l") ]] && ln -s "$(readlink "$l")" "$out/$(basename "$l")"
  done
  dirs=$(cd "$out" && find . -mindepth 2 -maxdepth 2 -type d | sed 's|^\./||' | sort | paste -sd,)
  {
    echo "[Icon Theme]"; echo "Name=$name"; echo "Comment=Papirus-Dark with Lumen-colored folders"
    echo "Inherits=Papirus-Dark,breeze-dark,hicolor"; echo "Directories=$dirs"; echo
    for d in ${dirs//,/ }; do
      s=${d%%x*}; sc=1; [[ $d == *@2x* ]] && sc=2
      printf '[%s]\nContext=Places\nSize=%s\nScale=%s\nType=Fixed\n\n' "$d" "$s" "$sc"
    done
  } > "$out/index.theme"
  gtk-update-icon-cache -f -q "$out" 2>/dev/null || true
  echo "$name: $(find "$out" -name '*.svg' | wc -l) icons"
}

make_variant Papirus-Lumen-Cyan "#8ED7E6" "#597A81" "#1c3a40"
make_variant Papirus-Lumen-Gold "#F2C13C" "#927834" "#3d2f0e"
