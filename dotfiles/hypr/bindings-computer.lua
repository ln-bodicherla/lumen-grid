-- Lumen: the ship's computer on SUPER+SPACE: search apps, Omarchy commands and files;
-- end with "?" to ask Claude. Omarchy's own menu moves to SUPER+ALT+C.
hl.unbind("SUPER + SPACE")
o.bind("SUPER + SPACE", "Lumen: computer (search, or ask with ?)", "omarchy-shell lumenComputer toggle")
o.bind("SUPER + ALT + C", "Omarchy menu", "omarchy-menu toggle")
