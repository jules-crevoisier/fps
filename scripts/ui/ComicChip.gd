## ComicChip.gd
## Badge de capacité "comic" : hexagone crantÃ© rempli + gros contour encre,
## avec la touche, le nom et le statut (cooldown / charges / PRÊT).
class_name ComicChip
extends Control

const INK := Color(0.05, 0.05, 0.07)

var fill: Color = Color(1.0, 0.13, 0.5)
var _key := ""
var _title := ""
var _status: Label

func setup(key: String, title: String, color: Color) -> void:
	_key = key
	_title = title
	fill = color

func _ready() -> void:
	custom_minimum_size = Vector2(78, 84)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var kl := Comic.label(_key, 24, Color(1, 1, 1))
	kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(kl)
	var tl := Comic.label(_title, 12, Color(1, 1, 1))
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tl)
	_status = Comic.label("", 13, Color(1, 1, 1))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_status)
	resized.connect(queue_redraw)
	queue_redraw()

func set_status(text: String, dim: bool) -> void:
	if _status:
		_status.text = text
		_status.add_theme_color_override("font_color", Color(1, 1, 1) if not dim else Color(0.8, 0.8, 0.85))

func _draw() -> void:
	var w := size.x
	var h := size.y
	var pad := 5.0
	var pts := PackedVector2Array([
		Vector2(w * 0.5, pad),
		Vector2(w - pad, h * 0.27),
		Vector2(w - pad * 1.4, h * 0.74),
		Vector2(w * 0.5, h - pad),
		Vector2(pad * 1.4, h * 0.74),
		Vector2(pad, h * 0.27),
	])
	draw_colored_polygon(pts, fill)
	var outl := pts
	outl.append(pts[0])
	draw_polyline(outl, INK, 5.0)
