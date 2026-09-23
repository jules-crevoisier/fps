## ComicBurst.gd
## Halo derrière une onomatopée (design.md §11 : Protest Revolution "for
## onomatopoeia only") — étoile pinceau rouge/charcoal UNIQUEMENT ce contexte
## (mot-bruit de kill, KillWordBurst.gd). Jamais ailleurs dans le HUD/menus.
class_name ComicBurst
extends Control

@export var color: Color = Comic.BRUSH
@export var outline_color: Color = Comic.PANEL
@export var spikes: int = 14
@export var inner: float = 0.72
@export var outline_w: float = 3.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _star(c: Vector2, ro: float, ri: float, n: int, phase: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var count := n * 2
	for i in count:
		var ang := TAU * float(i) / float(count) - PI / 2.0 + phase
		var r := ro if i % 2 == 0 else ri
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	return pts

func _draw() -> void:
	var c := size * 0.5
	var ro: float = min(size.x, size.y) * 0.5 - outline_w
	if ro <= 0.0:
		return
	var ri := ro * inner
	var p := _star(c, ro, ri, spikes, 0.0)
	draw_colored_polygon(p, color)
	var po := p
	po.append(p[0])
	draw_polyline(po, outline_color, outline_w)
