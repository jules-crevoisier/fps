## Comic.gd
## Boîte à outils direction artistique COMIC / Spider-Verse :
## couleurs ultra-saturées, gros contours noirs, panneaux anguleux, texte à liseré.
class_name Comic
extends RefCounted

const INK := Color(0.05, 0.05, 0.07)
const PAPER := Color(0.97, 0.95, 0.88)
const YELLOW := Color(1.0, 0.82, 0.1)
const ORANGE := Color(1.0, 0.5, 0.08)
const MAGENTA := Color(1.0, 0.13, 0.5)
const PINK := Color(1.0, 0.35, 0.55)
const PURPLE := Color(0.55, 0.2, 0.95)
const CYAN := Color(0.12, 0.78, 0.95)
const GREEN := Color(0.42, 0.85, 0.2)
const RED := Color(0.95, 0.18, 0.24)
const BLUE := Color(0.2, 0.45, 1.0)

const FONT := preload("res://resources/fonts/Lato-Black.ttf")

const SLOT_COLORS := [MAGENTA, YELLOW, CYAN, RED, GREEN, PURPLE]

## Panneau anguleux à gros contour encre.
static func panel(bg: Color, border: Color = INK, w: int = 5, radius: int = 5) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(w)
	s.border_color = border
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s

## Label « comic » : police Black + gros liseré encre (lisible sur n'importe quel fond).
static func label(text: String, size: int, fill: Color = Color(1, 1, 1), ink_size: int = -1) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", fill)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", ink_size if ink_size >= 0 else maxi(4, int(size / 7.0)))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
