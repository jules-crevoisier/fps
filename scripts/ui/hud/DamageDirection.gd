## DamageDirection.gd
## Flèche(s) de direction des dégâts : ink wedge(s) sur l'anneau du viseur
## (design.md §8 « damage arcs on its rim (in the enemy colour) » ;
## contract-r4a.md "R4-FX" #2), un par coup reçu, chacun s'effaçant sur 1 s
## (HitFeedback.wedge_alpha/WEDGE_DURATION). Plusieurs impacts rapprochés
## peuvent se superposer (liste, pas un seul état).
class_name DamageDirection
extends Control

## Ancré PRESET_CENTER (offsets à 0, voir GameHUD._build) : rect de taille
## NULLE positionné au centre écran, même convention que
## `GameHUD._crosshair`/HitMarker — tout se dessine en coordonnées LOCALES
## autour de l'origine (0,0).
const RING_RADIUS := 200.0
const HALF_WIDTH_DEG := 16.0
const WEDGE_THICKNESS := 34.0
const SUBDIVS := 5

var _wedges: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

## `angle_deg` : voir HitFeedback.wedge_angle_deg (0 = devant, 90 = droite).
func show_damage(angle_deg: float) -> void:
	_wedges.append({"angle": angle_deg, "elapsed": 0.0})
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	var i := _wedges.size() - 1
	while i >= 0:
		_wedges[i].elapsed += delta
		if _wedges[i].elapsed >= HitFeedback.WEDGE_DURATION:
			_wedges.remove_at(i)
		i -= 1
	queue_redraw()
	if _wedges.is_empty():
		set_process(false)

func _draw() -> void:
	var c := Vector2.ZERO
	for w in _wedges:
		var alpha: float = HitFeedback.wedge_alpha(w.elapsed)
		if alpha <= 0.0:
			continue
		_draw_wedge(c, float(w.angle), alpha)

func _draw_wedge(c: Vector2, angle_deg: float, alpha: float) -> void:
	var half := deg_to_rad(HALF_WIDTH_DEG)
	var base := deg_to_rad(angle_deg)
	var r0 := RING_RADIUS
	var r1 := RING_RADIUS + WEDGE_THICKNESS
	var pts := PackedVector2Array()
	for i in range(SUBDIVS + 1):
		var t := base - half + (2.0 * half) * float(i) / float(SUBDIVS)
		pts.append(c + Vector2(sin(t), -cos(t)) * r0)
	for i in range(SUBDIVS, -1, -1):
		var t := base - half + (2.0 * half) * float(i) / float(SUBDIVS)
		pts.append(c + Vector2(sin(t), -cos(t)) * r1)
	# Couleur ennemi (Settings.enemy_color, design.md §9) : même langage que
	# le contour des ennemis en jeu 3D — pas le rouge `brush` (réservé
	# marque/vie basse).
	var fill := Comic.enemy_color()
	fill.a = alpha
	draw_colored_polygon(pts, fill)
	var outline := pts
	outline.append(pts[0])
	var rim := Comic.BG
	rim.a = alpha
	draw_polyline(outline, rim, Comic.RULE_W_STRONG)
