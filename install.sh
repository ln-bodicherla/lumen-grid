#!/bin/bash
# Lumen Grid for Omarchy: install / update. Safe to re-run.
#
#   ./install.sh             install and apply (sets the theme, reloads Hyprland, restarts the shell)
#   ./install.sh --yes       accept every optional step without asking
#   ./install.sh --no-apply  install files only, don't apply
#
# Everything it changes is backed up to ~/.local/state/lumen-grid/backup-<time>/,
# and ./uninstall.sh puts your desktop back.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
D="$REPO/dotfiles"
CFG="$HOME/.config"
STATE="$HOME/.local/state/lumen-grid"
APPLY=1
YES=0
for arg in "$@"; do
  case $arg in
    --no-apply) APPLY=0 ;;
    --yes|-y)   YES=1 ;;
    -h|--help)  sed -n '2,10p' "$0"; exit 0 ;;
  esac
done

step() { printf '\e[36m◆\e[0m %s\n' "$*"; }
note() { printf '  %s\n' "$*" >&2; }
need() { command -v "$1" >/dev/null || { echo "Missing dependency: $1" >&2; exit 1; }; }
# ask "question" default(y|n): yes / no, honoring --yes and non-interactive runs
ask() {
  local q=$1 def=${2:-n} ans
  (( YES )) && return 0
  [[ -t 0 ]] || { [[ $def == y ]]; return; }
  read -r -p "  $q [$([[ $def == y ]] && echo Y/n || echo y/N)] " ans
  ans=${ans:-$def}
  [[ $ans =~ ^[Yy] ]]
}
# block <file> <name> <snippet> [comment-prefix]: put a snippet in a config file between
# markers; re-running replaces it, uninstall.sh removes it.
block() {
  local file=$1 name=$2 src=$3 c=${4:---} tmp
  mkdir -p "$(dirname "$file")"; touch "$file"
  tmp=$(mktemp)
  awk -v s="$c >>> lumen-grid:$name" -v e="$c <<< lumen-grid:$name" '
    $0 == s { skip = 1; next } $0 == e { skip = 0; next } !skip' "$file" > "$tmp"
  { cat "$tmp"; echo; echo "$c >>> lumen-grid:$name"; cat "$src"; echo "$c <<< lumen-grid:$name"; } > "$file"
  rm -f "$tmp"
}
backup() {   # backup <file>...: copy into this run's backup folder, keeping the path under $HOME
  for f in "$@"; do
    [[ -e $f ]] || continue
    local rel=${f#"$HOME"/}
    mkdir -p "$BACKUP/$(dirname "$rel")"
    cp -a "$f" "$BACKUP/$rel"
  done
}

cat <<'EOF'
Lumen Grid will restyle your Omarchy desktop. It:
  • adds three themes (Lumen Program, Overload, Redline) and switches to Lumen Program
  • replaces the wallpaper with a live 3D grid, and adds window, workspace and lock-screen effects
  • clones and patches Omarchy's notifications, launcher, clock and lock screen (re-run after Omarchy updates)
  • rearranges the bar, adds keybindings (SUPER+SPACE, SUPER+D, SUPER+TAB, SUPER+ALT+T/V)
  • sets a patched copy of Martian Mono as the system font, and Lumen cursors and folder icons
  • adds small background services (keyboard light, grid alert, root-shell theme)
Your current files are backed up, and ./uninstall.sh reverts all of it.

EOF
ask "Continue?" y || exit 0

mkdir -p "$STATE"
BACKUP="$STATE/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
echo "$REPO" > "$STATE/repo"
if [[ ! -f $STATE/install.env ]]; then   # remember what to go back to (first install only)
  {
    echo "PREV_FONT=\"$(omarchy font current 2>/dev/null || true)\""
    echo "PREV_THEME=\"$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)\""
    echo "FIRST_BACKUP=\"$BACKUP\""
  } > "$STATE/install.env"
fi
backup "$CFG/omarchy/shell.json" "$CFG/hypr/hyprland.lua" "$CFG/hypr/looknfeel.lua" "$CFG/hypr/bindings.lua" \
       "$CFG/ghostty/config" "$HOME/.bashrc" "$CFG/starship.toml" "$HOME/.claude/settings.json" \
       "$CFG/fastfetch/config.jsonc" "$CFG/omarchy/branding/about.txt" "$CFG/omarchy/branding/screensaver.txt"

step "Packages (installs only the missing ones; asks for your password)"
PKGS=(ghostty ttf-martian-mono-nerd fd brightnessctl librsvg hyprcursor qt6-shadertools papirus-icon-theme
      python-pillow starship socat zstd grim)
missing=$(pacman -T "${PKGS[@]}" 2>/dev/null || true)
[[ -n $missing ]] && omarchy pkg add $missing
for cmd in omarchy hyprctl python3 rsvg-convert hyprcursor-util brightnessctl; do need "$cmd"; done
QSB=/usr/lib/qt6/bin/qsb
[[ -x $QSB ]] || { echo "Missing dependency: qsb (qt6-shadertools)" >&2; exit 1; }
python3 -c "import PIL" 2>/dev/null || { echo "Missing dependency: python-pillow" >&2; exit 1; }
[[ -f $CFG/omarchy/shell.json ]] || { echo "No ~/.config/omarchy/shell.json yet: log in to Omarchy once, then re-run." >&2; exit 1; }

step "Themes: Lumen Program, Lumen Overload, Lumen Redline (with generated wallpapers)"
mkdir -p "$CFG/omarchy/themes"
cp -r "$D/themes/." "$CFG/omarchy/themes/"
python3 "$REPO/os/make-backgrounds.py" "$CFG/omarchy/themes" >/dev/null

step "Workspaces: light discs with a gooey core"
ws="$USER.workspaces"
mkdir -p "$CFG/omarchy/plugins/$ws" "$CFG/omarchy/bar/modules"
cp "$D/plugins/workspaces/Workspaces.qml" "$CFG/omarchy/plugins/$ws/"
sed "s/\"id\": \"[^\"]*\.workspaces\"/\"id\": \"$ws\"/" "$D/plugins/workspaces/manifest.json" > "$CFG/omarchy/plugins/$ws/manifest.json"
cp "$D/bar-modules/"*.qml "$CFG/omarchy/bar/modules/"

# Clone one of Omarchy's shell plugins fresh and apply our patch; if the patch no longer
# fits this Omarchy version, fall back to the stock plugin.
patched_plugin() {  # <name> <patch> [extra files to copy in, as "src:dest-subdir"]...
  local name=$1 patchf=$2 dir="$CFG/omarchy/plugins/$USER.$1"; shift 2
  rm -rf "$dir"
  omarchy plugin clone "omarchy.$name" >/dev/null
  for extra in "$@"; do mkdir -p "$dir/${extra#*:}"; cp "${extra%%:*}" "$dir/${extra#*:}"; done
  if ! patch -s -p1 -d "$dir" < "$patchf"; then
    note "the $name patch doesn't fit this Omarchy version; keeping Omarchy's own $name"
    omarchy plugin remove "$USER.$name" --yes >/dev/null 2>&1 || rm -rf "$dir"
    omarchy plugin enable "omarchy.$name" >/dev/null 2>&1 || true
  fi
}
step "Notifications, launcher, clock and lock screen (Omarchy's, cloned and patched)"
patched_plugin notifications "$D/plugins/notifications/border-beam.patch" \
  "$D/plugins/BorderBeam.qml:components" "$D/plugins/lumen-fx/Decrypt.qml:components"
patched_plugin menu "$D/plugins/menu/border-beam.patch" "$D/plugins/BorderBeam.qml:." "$D/plugins/lumen-fx/Decrypt.qml:."
patched_plugin clock "$D/plugins/clock/decrypt.patch"
lockdir="$CFG/omarchy/plugins/$USER.lock"
patched_plugin lock "$D/plugins/lock/checkpoint.patch" "$D/plugins/lumen-fx/Decrypt.qml:."
if [[ -d $lockdir ]]; then
  mkdir -p "$lockdir/shaders"
  "$QSB" --glsl "100 es,120,150" --hlsl 50 --msl 12 -o "$lockdir/shaders/world.frag.qsb" "$D/plugins/lumen-fx/shaders/world.frag"
fi

step "Grid effects: wallpaper, window effects, computer bar, app disc, card switcher, duel, screensaver"
fx="$CFG/omarchy/plugins/$USER.lumen-fx"
rm -rf "$fx"; mkdir -p "$fx/shaders"
cp "$D/plugins/lumen-fx/"*.qml "$fx/"
sed "s/\"id\": \"[^\"]*\.lumen-fx\"/\"id\": \"$USER.lumen-fx\"/" "$D/plugins/lumen-fx/manifest.json" > "$fx/manifest.json"
for frag in "$D/plugins/lumen-fx/shaders/"*.frag; do
  "$QSB" --glsl "100 es,120,150" --hlsl 50 --msl 12 -o "$fx/shaders/$(basename "$frag").qsb" "$frag"
done
mkdir -p "$HOME/.local/bin"
for b in lumen-computer lumen-gridvision lumen-switch lumen-agent-state; do install -m 755 "$D/bin/$b" "$HOME/.local/bin/$b"; done
[[ -f $CFG/omarchy/lumen-vision.json ]] || echo '{ "auto": true, "apps": [] }' > "$CFG/omarchy/lumen-vision.json"
[[ -f $CFG/omarchy/lumen-wallpaper.json ]] || echo '{ "live": true }' > "$CFG/omarchy/lumen-wallpaper.json"
omarchy-shell -q shell rescanPlugins || true
omarchy plugin enable "$USER.lumen-fx" >/dev/null 2>&1 || true
command -v claude >/dev/null || note "the computer bar answers questions ending in ? with the Claude Code CLI (claude), which isn't installed"

step "Hyprland: animations, blur for the computer bar, keybindings, cursors, see-through system apps"
block "$CFG/hypr/looknfeel.lua" derez "$D/hypr/looknfeel.lua"
block "$CFG/hypr/looknfeel.lua" overlays "$D/hypr/looknfeel-overlays.lua"
block "$CFG/hypr/bindings.lua" switch "$D/hypr/bindings.lua"
block "$CFG/hypr/bindings.lua" disc "$D/hypr/bindings-disc.lua"
block "$CFG/hypr/bindings.lua" card "$D/hypr/bindings-card.lua"
block "$CFG/hypr/bindings.lua" computer "$D/hypr/bindings-computer.lua"
block "$CFG/hypr/hyprland.lua" cursors "$D/hypr/hyprland.lua"
block "$CFG/hypr/hyprland.lua" opacity "$D/hypr/system-app-opacity.lua"

step "Bar layout: stats and clock in the middle (around the notch on a MacBook), the rest grouped"
notch=0
grep -qi macbook /proc/device-tree/model /sys/class/dmi/id/product_name 2>/dev/null && notch=1
python3 - "$CFG/omarchy/shell.json" "$notch" <<'EOF'
import json, sys
path, notch = sys.argv[1], sys.argv[2] == "1"
d = json.load(open(path))
old = {e["id"]: e for sec in d.get("bar", {}).get("layout", {}).values() for e in sec}
def e(i, **kw):
    x = dict(old.get(i, {"id": i})); x.update(kw); return x
sp = lambda: {"id": "omarchy.spacer"}
pick = lambda suffix, default: next((i for i in old if i.endswith(suffix)), default)
clock, menu, ws = pick(".clock", "omarchy.clock"), pick(".menu", "omarchy.menu"), pick(".workspaces", "omarchy.workspaces")
placed = {"omarchy.weather", "omarchy.tray", "omarchy.monitor", "omarchy.agents", "omarchy.system-update", "omarchy.indicators",
          "omarchy.keyboard-layout", "omarchy.bluetooth", "omarchy.network", "omarchy.audio", "omarchy.power", "omarchy.spacer",
          clock, menu, ws, "lumen-orb", "lumen-voice", "lumen-vision", "lumen-wall", "lumen-stats", "lumen-notch", "lumen-status"}
right = [e("lumen-orb", type="qml"), e("lumen-voice", type="qml"), e("lumen-status", type="qml"), e("omarchy.system-update"), sp(),
         e("omarchy.weather"), e("omarchy.tray")] + [e(i) for i in old if i not in placed]
right += [e("omarchy.agents"), sp(), e("lumen-vision", type="qml"), e("lumen-wall", type="qml"), sp(),
          e("omarchy.keyboard-layout"), e("omarchy.bluetooth"), e("omarchy.network"), e("omarchy.audio"), e("omarchy.power", showPercentage=True)]
center = [e("lumen-stats", type="qml")] + ([e("lumen-notch", type="qml")] if notch else []) + [e(clock)]
d.setdefault("bar", {})["layout"] = {"left": [e(menu), e(ws)], "center": center, "right": right}
d["bar"]["centerAnchor"] = "lumen-notch" if notch else clock
json.dump(d, open(path, "w"), indent=2)
EOF

step "Background services: keyboard light, grid alert, root-shell theme"
mkdir -p "$CFG/systemd/user"
for svc in lumen-keys lumen-alert lumen-sudo-watch; do
  install -m 755 "$D/bin/$svc" "$HOME/.local/bin/$svc"
  cp "$D/systemd/$svc.service" "$CFG/systemd/user/"
done
systemctl --user daemon-reload
systemctl --user enable --now lumen-keys.service lumen-alert.service lumen-sudo-watch.service >/dev/null 2>&1 || true

if command -v claude >/dev/null && ask "Show Claude Code activity in the bar (adds hooks to ~/.claude/settings.json)?" y; then
  python3 - "$HOME/.claude/settings.json" <<'EOF'
import json, os, sys
path = sys.argv[1]
os.makedirs(os.path.dirname(path), exist_ok=True)
c = json.load(open(path)) if os.path.exists(path) else {}
hooks = c.setdefault("hooks", {})
for event, state in [("UserPromptSubmit", "busy"), ("PostToolUse", "busy"), ("Notification", "wait"), ("Stop", "idle"), ("SessionEnd", "idle")]:
    cmd = f"$HOME/.local/bin/lumen-agent-state {state}"
    entries = hooks.setdefault(event, [])
    if not any(h.get("command") == cmd for e in entries for h in e.get("hooks", [])):
        entries.append({"hooks": [{"type": "command", "command": cmd}]})
json.dump(c, open(path, "w"), indent=2)
EOF
  echo 'CLAUDE_HOOKS=1' >> "$STATE/install.env"
fi

step "Theme hooks: recolor the extras when the theme changes"
mkdir -p "$STATE/hooks"
sed "s|@REPO@|$REPO|g" "$D/hooks/lumen-cursors" > "$STATE/hooks/lumen-cursors"; chmod +x "$STATE/hooks/lumen-cursors"
omarchy hook install theme-set "$STATE/hooks/lumen-cursors" >/dev/null
omarchy hook install theme-set "$REPO/omarchy-sync.sh" >/dev/null

step "Cursors and folder icons"
"$REPO/os/make-cursors.sh" >/dev/null
for t in lumen-overload lumen-redline; do   # pre-build, so the first switch to these is instant
  LUMEN_COLORS="$CFG/omarchy/themes/$t/colors.toml" LUMEN_CURSOR_PREBUILD=1 "$REPO/os/make-cursors.sh" >/dev/null 2>&1 || true
done
"$REPO/os/build-lumen-icons.sh" >/dev/null

step "GTK apps (Files and others) in the theme colors"
"$REPO/os/make-gtk.sh" >/dev/null

step "Icon font: MartianMono Lumen (Martian Mono with the bar's icons redrawn)"
VENV="$STATE/venv"
[[ -x $VENV/bin/python ]] || python3 -m venv "$VENV"
"$VENV/bin/python" -c "import fontTools" 2>/dev/null || "$VENV/bin/pip" install -q fonttools
"$VENV/bin/python" "$REPO/os/make-lumen-icons.py" >/dev/null
fc-cache -f "$HOME/.local/share/fonts" >/dev/null
if ask "Use MartianMono Lumen as the system font (needed for the Lumen bar icons)?" y; then
  omarchy font set "MartianMono Lumen" >/dev/null 2>&1 || note "set it later with: omarchy font set \"MartianMono Lumen\""
fi

step "Terminal: Ghostty shaders (cursor trail, glow, one color) and the HUD prompt"
block "$CFG/ghostty/config" shaders "$D/ghostty/lumen.conf" "#"
"$REPO/os/make-ghostty-trail.sh" >/dev/null
"$REPO/os/make-ghostty-glow.sh" >/dev/null
mkdir -p "$HOME/.local/share/applications"
cp "$D/applications/com.mitchellh.ghostty.desktop" "$HOME/.local/share/applications/"
cp "$D/starship.toml" "$CFG/starship.toml"
if ! grep -q 'default/bash/rc' "$HOME/.bashrc" 2>/dev/null; then
  if ask "Your ~/.bashrc doesn't load Omarchy's shell setup (needed for the prompt). Replace it with Omarchy's (yours is backed up)?" y; then
    cp /usr/share/omarchy/default/bashrc "$HOME/.bashrc"
    echo 'BASHRC_REPLACED=1' >> "$STATE/install.env"
  fi
fi
python3 "$REPO/os/make-obsidian.py" || true

step "Screensaver and system-info art"
B="$CFG/omarchy/branding"; mkdir -p "$B"
python3 "$REPO/os/make-branding.py" "$B"
if [[ -f /etc/fastfetch/config.jsonc ]]; then
  mkdir -p "$CFG/fastfetch"
  sed -e 's/"green"/"cyan"/g' -e 's/"magenta"/"yellow"/g' /etc/fastfetch/config.jsonc > "$CFG/fastfetch/config.jsonc"
fi
"$REPO/omarchy-sync.sh" >/dev/null

if ask "Give root shells the same prompt (writes /root/.bashrc with sudo)?" n; then
  sudo sh -c "cp /usr/share/omarchy/default/bashrc /root/.bashrc && echo 'export STARSHIP_CONFIG=$CFG/starship.toml' >> /root/.bashrc" || true
fi
if [[ ! -d $CFG/omarchy/plugins/netmojo.omdrop ]] && ask "Add OmDrop (AirDrop-style sharing, a separate project) to the bar?" n; then
  omarchy plugin add https://github.com/brentkearney/omdrop-plugin.git --enable --yes >/dev/null 2>&1 || note "couldn't add OmDrop"
fi

if (( APPLY )); then
  step "Applying"
  current=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)
  [[ $current == lumen-overload ]] || current=lumen-program
  omarchy theme set "$current" >/dev/null
  hyprctl reload >/dev/null
  omarchy restart shell >/dev/null 2>&1 || true
fi

cat <<EOF

Done. Backups of what changed: $BACKUP
Optional, by hand:
  • Browser extension: chrome://extensions → Developer mode → Load unpacked → $REPO
  • Ghostty as the default terminal: omarchy install terminal ghostty
  • Boot splash (asks for your password): omarchy plymouth set-by-theme lumen-program
To remove everything: $REPO/uninstall.sh
EOF
