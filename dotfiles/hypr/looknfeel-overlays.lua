
-- Lumen: a very light blur behind the computer bar only. Blur is switched on with a tiny
-- radius, windows opt out, and only the lumen-computer layer uses it. Lumen overlays skip
-- Hyprland's fade so their own animations play cleanly.
hl.config({ decoration = { blur = { enabled = true, size = 3, passes = 1, noise = 0, contrast = 1.0, brightness = 1.0, vibrancy = 0 } } })
hl.window_rule({ match = { class = ".*" }, no_blur = true })
hl.layer_rule({ match = { namespace = "^lumen-computer$" }, blur = true })
hl.layer_rule({ match = { namespace = "^lumen-" }, no_anim = true })

-- Lumen: workspaces slide (the current one moves out to the side, the next slides in from
-- the other side, by workspace order) over the live Grid wallpaper, which stays put.
hl.animation({ leaf = "workspaces", enabled = true, speed = 4.5, bezier = "easeOutQuint", style = "slide" })
