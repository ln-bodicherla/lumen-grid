-- Extra transparency for system apps (terminals, Omarchy tools, file manager,
-- system settings) so the wallpaper shows through. Third-party apps (browsers,
-- web apps, Obsidian, LibreOffice, 1Password, ...) keep Omarchy's default.
local system_apps = "^(foot|footclient|Alacritty|kitty|com\\.mitchellh\\.ghostty"
  .. "|org\\.omarchy\\..*|TUI\\.float|Omarchy|omacalc|omawrite|aether|dev\\.tensaku\\.Tensaku"
  .. "|org\\.gnome\\.Nautilus|org\\.gnome\\.DiskUtility|system-config-printer"
  .. "|fcitx5-config-qt|org\\.fcitx\\..*|voxtype)$"
o.window(system_apps, { tag = "-default-opacity" })
o.window(system_apps, { opacity = "0.88 0.80" })
-- Keep the fullscreen screensaver fully opaque.
o.window("org.omarchy.screensaver", { opacity = "1 1" })
