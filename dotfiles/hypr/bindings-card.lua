-- Lumen: SUPER+TAB is a held card switcher (current workspace squeezes back right, the next
-- comes to the center; release SUPER to zoom in); SUPER+number keeps the slide.
hl.unbind("SUPER + TAB")
hl.unbind("SUPER + SHIFT + TAB")
o.bind("SUPER + TAB", "Next workspace (card swap)", "omarchy-shell lumenCard next")
o.bind("SUPER + SHIFT + TAB", "Previous workspace (card swap)", "omarchy-shell lumenCard prev")
