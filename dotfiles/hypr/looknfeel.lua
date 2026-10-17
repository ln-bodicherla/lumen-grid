
-- Lumen: closing windows stay on screen while lumen-fx derezzes them. They hold near-solid,
-- then fade fast at the end, in step with the cells burning out (0.32 s, same as the derez).
hl.curve("derez", { type = "bezier", points = { { 0.7, 0 }, { 0.95, 0.45 } } })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3.2, bezier = "derez", style = "popin 100%" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 3.2, bezier = "derez" })
