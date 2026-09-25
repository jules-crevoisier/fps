## HitMarker.gd
## Hitmarker au viseur (docs/STYLE_BIBLE.md §9.4 "Retour de tir (HUD)",
## verrouillé — zone centrale, CHK-35 : réticule/hitmarker/arcs/lunette
## uniquement) : 4 traits diagonaux papier + contour encre, variante headshot
## orange avec petit anneau, confirmation de kill en traits pinceau (rouge)
## avec punch d'échelle — confirmé SERVEUR via `Weapon.hit_confirmed` du
## joueur local (voir GameHUD._on_hit_confirmed). Toutes les tailles/couleurs/
## durées viennent de HitFeedback (jetons docs/style/tokens.json
## "vfx.hitmarker") : ce fichier ne fait que dessiner et animer.
class_name HitMarker
extends Control

## Épaisseur du cœur "papier" d'un trait/anneau (le contour encre
## `HitFeedback.MARKER_INK_PX` s'ajoute de chaque côté, voir `_draw_ticks`).
const _CORE_W := 4.0
## Rayon du petit anneau de headshot : à l'intérieur de l'écart des traits
## (`HitFeedback.MARKER_TICK_GAP_PX`), jamais au contact.
const _RING_RADIUS_RATIO := 0.75
const _RING_W := 2.0

var _variant: String = HitFeedback.MARKER_NORMAL
var _tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	# CHK-35 "Zone centrale" : le hitmarker est un des SEULS nœuds autorisés
	# dans le carré central 40 % × 40 % (avec réticule/arcs/lunette, hors de
	# mon périmètre d'écriture) — s'enregistrer ici permet à la revue de le
	# reconnaître dès que ces autres nœuds rejoignent le même groupe.
	add_to_group("hud_center")

## `variant` : HitFeedback.MARKER_NORMAL / MARKER_HEADSHOT / MARKER_KILL.
func show_hit(variant: String) -> void:
	_variant = variant
	modulate.a = 1.0
	queue_redraw()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	var reduced := Comic.reduced_motion()
	if variant == HitFeedback.MARKER_KILL and not reduced:
		# Punch d'échelle 1,3 -> 1, "slap" raccourci à 150 ms (STYLE_BIBLE
		# §9.4, tokens.json vfx.hitmarker.kill_punch/kill_punch_ms) — SEULE
		# variante animée en échelle, jamais en mouvement réduit (tokens.json
		# reduced_motion.forbid : scale).
		scale = Vector2.ONE * HitFeedback.MARKER_KILL_PUNCH_FROM
		_tween.tween_property(self, "scale", Vector2.ONE * HitFeedback.MARKER_KILL_PUNCH_TO, HitFeedback.MARKER_KILL_PUNCH_DURATION) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "modulate:a", 0.0, HitFeedback.MARKER_KILL_HOLD)
		return
	# Normal/headshot (STYLE_BIBLE §9.4 : "sans animation d'échelle") ET kill
	# en mouvement réduit (fondu seul, jamais le punch d'échelle) : fondu pur.
	scale = Vector2.ONE
	if reduced:
		_tween.tween_property(self, "modulate:a", 0.0, Comic.DUR_REDUCED_FADE)
		return
	var duration := HitFeedback.marker_duration(variant)
	_tween.tween_interval(duration * 0.35)
	_tween.tween_property(self, "modulate:a", 0.0, duration * 0.65)

func _draw() -> void:
	var c := Vector2.ZERO
	var color := _stroke_color()
	_draw_ticks(c, color)
	if _variant == HitFeedback.MARKER_HEADSHOT:
		_draw_ring(c, HitFeedback.HEADSHOT_COLOR)

## Couleur des traits par variante (STYLE_BIBLE §9.4) : papier blanc (normal),
## orange headshot (`HitFeedback.HEADSHOT_COLOR`), pinceau rouge sur kill
## (« les traits passent en pinceau » — `Comic.BRUSH`, la marque/action
## principale de la charte, réservée à ce moment fort).
func _stroke_color() -> Color:
	match _variant:
		HitFeedback.MARKER_KILL:
			return Comic.BRUSH
		HitFeedback.MARKER_HEADSHOT:
			return HitFeedback.HEADSHOT_COLOR
		_:
			return Comic.TEXT_ON_BRUSH

## 4 traits diagonaux (STYLE_BIBLE §9.4 : "4 traits diagonaux papier, contour
## encre 2 px, 10 px de long, écart de 8 px") : chaque trait part à
## `MARKER_TICK_GAP_PX` du centre et s'étire de `MARKER_TICK_LEN_PX` vers
## l'extérieur, sur les 4 diagonales — deux passes (encre plus large en
## dessous, couleur au-dessus) pour le contour, comme `Comic.hard_shadow_style`
## fait le relief par décalage plutôt que par flou (CHK-38).
func _draw_ticks(c: Vector2, color: Color) -> void:
	for d: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var dir := d.normalized()
		var a := c + dir * HitFeedback.MARKER_TICK_GAP_PX
		var b := a + dir * HitFeedback.MARKER_TICK_LEN_PX
		draw_line(a, b, Comic.HARD_SHADOW_COLOR, _CORE_W + HitFeedback.MARKER_INK_PX * 2.0)
		draw_line(a, b, color, _CORE_W)

## Petit anneau de headshot (STYLE_BIBLE §9.4 : "traits orange + petit
## anneau"), même traitement à deux passes que les traits.
func _draw_ring(c: Vector2, color: Color) -> void:
	var r := HitFeedback.MARKER_TICK_GAP_PX * _RING_RADIUS_RATIO
	draw_arc(c, r, 0.0, TAU, 24, Comic.HARD_SHADOW_COLOR, _RING_W + HitFeedback.MARKER_INK_PX, true)
	draw_arc(c, r, 0.0, TAU, 24, color, _RING_W, true)
