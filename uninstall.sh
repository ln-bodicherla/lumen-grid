#!/bin/bash
# Remove Lumen Grid and put the desktop back the way it was before the first install.
#   ./uninstall.sh          asks first
#   ./uninstall.sh --yes    no questions
set -uo pipefail

CFG="$HOME/.config"
STATE="$HOME/.local/state/lumen-grid"
[[ ${1:-} == "--yes" || ${1:-} == "-y" ]] || {
  read -r -p "Remove Lumen Grid and restore your previous desktop? [y/N] " a
  [[ $a =~ ^[Yy] ]] || exit 0
}
step() { printf '\e[36m◆\e[0m %s\n' "$*"; }
[[ -f $STATE/install.env ]] && source "$STATE/install.env"

step "Config blocks (Hyprland, Ghostty)"
unblock() {   # unblock <file> [comment-prefix]: drop every lumen-grid block from a file
  local file=$1 c=${2:---} tmp
  [[ -f $file ]] || return 0
  tmp=$(mktemp)
  awk -v c="$c" 'index($0, c " >>> lumen-grid:") == 1 { skip = 1; next }
                 index($0, c " <<< lumen-grid:") == 1 { skip = 0; next } !skip' "$file" > "$tmp" && cat "$tmp" > "$file"
  rm -f "$tmp"
}
unblock "$CFG/hypr/looknfeel.lua"; unblock "$CFG/hypr/bindings.lua"; unblock "$CFG/hypr/hyprland.lua"
unblock "$CFG/ghostty/config" "#"

step "Background services and commands"
systemctl --user disable --now lumen-keys.service lumen-alert.service lumen-sudo-watch.service >/dev/null 2>&1
rm -f "$CFG/systemd/user/"lumen-{keys,alert,sudo-watch}.service
systemctl --user daemon-reload
rm -f "$HOME/.local/bin/"lumen-{computer,gridvision,switch,agent-state,keys,alert,sudo-watch}

step "Shell plugins (back to Omarchy's own) and bar modules"
for p in notifications menu clock lock; do
  omarchy plugin remove "$USER.$p" --yes >/dev/null 2>&1 || rm -rf "$CFG/omarchy/plugins/$USER.$p"
  omarchy plugin enable "omarchy.$p" >/dev/null 2>&1 || true
done
omarchy plugin remove "$USER.lumen-fx" --yes >/dev/null 2>&1 || rm -rf "$CFG/omarchy/plugins/$USER.lumen-fx"
rm -rf "$CFG/omarchy/plugins/$USER.workspaces"
rm -f "$CFG/omarchy/bar/modules/"lumen-*.qml "$CFG/omarchy/"lumen-{vision,wallpaper,disc}.json

step "Restoring backed-up files (bar layout, shell, prompt, ...)"
if [[ -n ${FIRST_BACKUP:-} && -d $FIRST_BACKUP ]]; then
  for rel in .config/omarchy/shell.json .config/starship.toml .config/fastfetch/config.jsonc \
             .config/omarchy/branding/about.txt .config/omarchy/branding/screensaver.txt; do
    [[ -e $FIRST_BACKUP/$rel ]] && cp -a "$FIRST_BACKUP/$rel" "$HOME/$rel"
  done
  [[ ${BASHRC_REPLACED:-0} == 1 && -e $FIRST_BACKUP/.bashrc ]] && cp -a "$FIRST_BACKUP/.bashrc" "$HOME/.bashrc"
fi
for f in "$CFG/gtk-3.0/gtk.css" "$CFG/gtk-4.0/gtk.css"; do
  if [[ -f $f.orig ]]; then mv -f "$f.orig" "$f"; elif grep -q "lumen-grid" "$f" 2>/dev/null; then rm -f "$f"; fi
done
rm -f "$CFG/ghostty/shaders/"lumen-{trail,glow}.glsl "$HOME/.local/share/applications/com.mitchellh.ghostty.desktop"

if [[ ${CLAUDE_HOOKS:-0} == 1 && -f $HOME/.claude/settings.json ]]; then
  step "Claude Code hooks"
  python3 - "$HOME/.claude/settings.json" <<'EOF'
import json, sys
p = sys.argv[1]; c = json.load(open(p))
for event, entries in list(c.get("hooks", {}).items()):
    entries = [e for e in entries if not any("lumen-agent-state" in h.get("command", "") for h in e.get("hooks", []))]
    if entries: c["hooks"][event] = entries
    else: del c["hooks"][event]
if not c.get("hooks"): c.pop("hooks", None)
json.dump(c, open(p, "w"), indent=2)
EOF
fi

step "Theme hooks, font, cursors, icons, themes"
rm -f "$CFG/omarchy/hooks/theme-set.d/"{lumen-cursors,omarchy-sync.sh}
font=${PREV_FONT:-JetBrainsMono Nerd Font}; [[ $font == "MartianMono Lumen" ]] && font="JetBrainsMono Nerd Font"
omarchy font set "$font" >/dev/null 2>&1 || true
theme=${PREV_THEME:-tokyo-night}; [[ $theme == lumen-* ]] && theme=tokyo-night
omarchy theme set "$theme" >/dev/null 2>&1 || true
rm -rf "$HOME/.local/share/fonts/lumen" "$HOME/.local/share/icons/Lumen" "$HOME/.local/share/icons/"Papirus-Lumen-{Cyan,Gold} \
       "$HOME/.cache/lumen-cursors" "$HOME/.local/state/lumen-alert" "$HOME/.local/state/lumen-agents" "$HOME/.local/state/lumen"
rm -rf "$CFG/omarchy/themes/"lumen-{program,overload,redline}
fc-cache -f >/dev/null 2>&1
hyprctl setcursor Adwaita 24 >/dev/null 2>&1 || true

step "Reloading"
hyprctl reload >/dev/null 2>&1
omarchy restart shell >/dev/null 2>&1 || true
rm -f "$STATE/install.env" "$STATE/repo"
echo
echo "Lumen Grid removed. Backups are still in $STATE (delete it when you're happy)."
echo "Remove the browser extension in chrome://extensions, and /root/.bashrc if you let the installer write it."
