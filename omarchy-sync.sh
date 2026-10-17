#!/bin/bash
# Copy the current Omarchy theme (colors + wallpaper) into the Lumen Grid extension.
# Installed as an Omarchy theme-set hook, so switching themes restyles YouTube too.
# Pages pick it up on their next load; no extension reload needed.
set -euo pipefail

EXT_DIR="$(dirname "$(readlink -f "$0")")"
[[ -f $EXT_DIR/manifest.json ]] || EXT_DIR=$(cat "$HOME/.local/state/lumen-grid/repo" 2>/dev/null || echo "$HOME/lumen-grid")   # when run from the hooks dir
OUT="$EXT_DIR/omarchy"
CURRENT="$HOME/.local/state/omarchy/current"
COLORS="$CURRENT/theme/colors.toml"
mkdir -p "$OUT"

color() {  # color <key> <fallback>
  local v
  v=$(grep -E "^$1[[:space:]]*=" "$COLORS" 2>/dev/null | head -1 | sed -E 's/.*"(#[0-9A-Fa-f]{6})".*/\1/')
  [[ $v == \#* ]] && echo "$v" || echo "$2"
}

bg_src=$(readlink -f "$CURRENT/background" 2>/dev/null || true)
bg_name=""
if [[ -n $bg_src && -f $bg_src ]]; then
  ext="${bg_src##*.}"; ext="${ext,,}"
  rm -f "$OUT"/background.*
  bg_name="background.$ext"
  cp "$bg_src" "$OUT/$bg_name"
fi

cat > "$OUT/theme.json" <<JSON
{
  "name": "$(cat "$CURRENT/theme.name" 2>/dev/null || echo unknown)",
  "accent": "$(color accent '#00f0ff')",
  "orange": "$(color orange '#ff9a3c')",
  "background": "$(color background '#05080c')",
  "darkBackground": "$(color darker_background '#030507')",
  "panel": "$(color lighter_background '#0a1118')",
  "foreground": "$(color foreground '#dffcff')",
  "mutedForeground": "$(color dark_foreground '#8aaab3')",
  "wallpaper": "$bg_name",
  "stamp": $(date +%s)
}
JSON
echo "Lumen Grid synced to Omarchy theme: $(cat "$CURRENT/theme.name" 2>/dev/null)"
