-- Lumen: light-disc launcher around the pointer. Hold to show, point, let go to run.
o.bind("SUPER + D", "Lumen: app disc", "omarchy-shell lumenDisc show")
o.bind("SUPER + D", nil, "omarchy-shell lumenDisc release", { release = true })

-- Lumen: grid vision (whole screen in the theme color)
o.bind("SUPER + ALT + V", "Lumen: grid vision", os.getenv("HOME") .. "/.local/bin/lumen-gridvision")
