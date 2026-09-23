## ComicBurst.gd
## Étoile d'explosion (starburst) dessinée : remplissage saturé + gros contour encre.
## Sert de fond derrière un titre ou un badge. Optionnellement un 2e burst décalé
## pour l'effet "double impact" comic.
class_name ComicBurst
extends Control

@export var color: Color = Color(1.0, 0.82, 0.1)
@export var back_color: Color = Color(0.95, 0.18, 0.24)
@export var spikes: int = 16
@export var inner: float = 0.66
@export var outline_w: float = 6.0
@export var double: bool = true

func _ready() -> void:
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
	var ri: float = ro * inner
	if double:
		var b := _star(c, ro, ri * 0.92, spikes, 0.16)
		draw_colored_polygon(b, back_color)
		var bo := b; bo.append(b[0])
		draw_polyline(bo, INK_(), outline_w)
		ro *= 0.86
		ri *= 0.86
	var p := _star(c, ro, ri, spikes, 0.0)
	draw_colored_polygon(p, color)
	var po := p; po.append(p[0])
	draw_polyline(po, INK_(), outline_w)

func INK_() -> Color:
	return Color(0.05, 0.05, 0.07)
