## HitMarker.gd
## Hitmarker au viseur (design.md v2 §12 : zone centrale, crosshair/hitmarkers
## uniquement) : tick blanc à liseré `bg` (lisible sur n'importe quel fond de
## jeu, ciel clair ou décor sombre), variante headshot alourdie, croix sur
## kill — confirmé SERVEUR via `Weapon.hit_confirmed` du joueur local (voir
## GameHUD._on_hit_confirmed).
class_name HitMarker
extends Control

## Liseré sombre + trait blanc plein (au lieu d'une seule couleur) : reste
## lisible que le fond de jeu soit clair (ciel) ou sombre (intérieur).
const _OUTLINE_W := 9.0
const _STROKE_W := 6.0
const _STROKE_W_HEAVY := 8.0

var _variant: String = HitFeedback.MARKER_NORMAL
var _tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0

## `variant` : HitFeedback.MARKER_NORMAL / MARKER_HEADSHOT / MARKER_KILL.
func show_hit(variant: String) -> void:
	_variant = variant
	modulate.a = 1.0
	queue_redraw()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(HitFeedback.MARKER_DURATION * 0.35)
	_tween.tween_property(self, "modulate:a", 0.0, HitFeedback.MARKER_DURATION * 0.65)

func _draw() -> void:
	var c := Vector2.ZERO
	match _variant:
		HitFeedback.MARKER_KILL:
			_draw_cross(c, 16.0, _STROKE_W_HEAVY)
		HitFeedback.MARKER_HEADSHOT:
			_draw_tick(c, 15.0, _STROKE_W_HEAVY)
		_:
			_draw_tick(c, 12.0, _STROKE_W)

## Croix (variante kill) : deux traits diagonaux, liseré sombre + blanc.
func _draw_cross(c: Vector2, r: float, w: float) -> void:
	for d: Vector2 in [Vector2(1, 1), Vector2(1, -1)]:
		var a := c - d * r
		var b := c + d * r
		draw_line(a, b, Comic.BG, w + 4.0)
		draw_line(a, b, Comic.TEXT_ON_BRUSH, w)

## Tick (chevron « ✓ ») : variante normale/headshot (`w` pilote l'épaisseur).
func _draw_tick(c: Vector2, r: float, w: float) -> void:
	var p1 := c + Vector2(-r, 0.0)
	var p2 := c + Vector2(-r * 0.25, r * 0.7)
	var p3 := c + Vector2(r, -r * 0.9)
	var pts := PackedVector2Array([p1, p2, p3])
	draw_polyline(pts, Comic.BG, w + 4.0, false)
	draw_polyline(pts, Comic.TEXT_ON_BRUSH, w, false)
