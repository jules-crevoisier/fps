## BrushHeader.gd
## Bandeau pinceau sec réutilisable (STYLE_BIBLE v3 §8.2 jeton `brush`,
## §8.1 règle 10) : barre rouge aux bords déchiquetés avec une queue sèche de
## 64 px qui déborde du panneau, titre blanc en capitales italiques
## (Comic.title_label). Se dévoile de gauche à droite en 250 ms
## (Comic.DUR_REVEAL) ; mouvement réduit -> fondu seul, pas de balayage
## (STYLE_BIBLE v3 §8.2 "Mouvement").
##
## La queue (`_draw_tail`) est peinte depuis `assets/ui/brush/dry_tail.png` —
## plusieurs mèches de pinceau sec DISJOINTES, de largeur/opacité décroissantes
## et de bords irréguliers (générées procéduralement, graine fixe) — jamais une
## seule forme continue qui se referme en pointe symétrique : c'est
## exactement ce dernier profil (un aileron lisible comme une nageoire) que
## STYLE_BIBLE v3 nomme « la queue en poisson actuelle » et fait supprimer
## (§8.2 jeton `brush`, §8.1 règle 10 « a l'air d'un bug », §10 anti-patterns
## Interface, ART-31/CHK-38).
## Usage : `var h := BrushHeader.new(); h.title = "07. WASTELAND"; add_child(h)`.
class_name BrushHeader
extends Control

## Texture blanche à alpha (mèches de pinceau sec) teintée à `Comic.BRUSH` au
## dessin — voir la note de classe ci-dessus.
const DRY_TAIL_TEXTURE := preload("res://assets/ui/brush/dry_tail.png")

@export var title: String = "":
	set(v):
		title = v
		if _label:
			_label.text = title.to_upper()
			queue_redraw()

@export var bar_height: float = 56.0
@export var tail_px: float = 64.0

var _label: Label
var _wipe_ratio: float = 1.0
var _shape_seed: int = 0
var _tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, bar_height)
	clip_contents = false
	resized.connect(queue_redraw)
	_shape_seed = hash(title)

	_label = Comic.title_label(title, _title_size(), Comic.TEXT_ON_BRUSH)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.offset_left = Comic.SP_3
	_label.offset_right = -Comic.SP_3
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.clip_text = true
	add_child(_label)

	_play_wipe()

func _title_size() -> int:
	return int(clampf(bar_height * 0.62, Comic.SIZE_LABEL, Comic.SIZE_DISPLAY_MD))

## Rejoue le balayage (ex. un bandeau réutilisé pour une nouvelle carte de
## partie) sans reconstruire le contrôle.
func replay() -> void:
	if _label:
		_play_wipe()

func _play_wipe() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if Comic.reduced_motion():
		_wipe_ratio = 1.0
		modulate.a = 0.0
		queue_redraw()
		_tween = create_tween()
		_tween.tween_property(self, "modulate:a", 1.0, Comic.DUR_REVEAL)
		return
	modulate.a = 1.0
	_wipe_ratio = 0.0
	_label.modulate.a = 0.0
	queue_redraw()
	_tween = create_tween()
	_tween.tween_method(_set_wipe, 0.0, 1.0, Comic.DUR_REVEAL).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(func(): _label.modulate.a = 1.0)

func _set_wipe(r: float) -> void:
	_wipe_ratio = r
	_label.modulate.a = r
	queue_redraw()

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var w := size.x * _wipe_ratio
	if w <= 0.5:
		return
	draw_colored_polygon(_ragged_bar(w), Comic.BRUSH)
	_draw_tail(w)

## Barre principale aux bords déchiquetés (haut/bas légèrement irréguliers —
## "dry-brush" ; design.md §11 "brush header bars").
func _ragged_bar(w: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var jag := maxf(size.y * 0.1, 2.5)
	var steps := 10
	for i in steps + 1:
		var x := w * float(i) / float(steps)
		var n := sin(float(i) * 1.7 + float(_shape_seed % 7)) * jag
		pts.append(Vector2(x, n * 0.5))
	for i in range(steps, -1, -1):
		var x := w * float(i) / float(steps)
		var n := cos(float(i) * 2.1 + float(_shape_seed % 5)) * jag
		pts.append(Vector2(x, size.y + n * 0.5))
	return pts

## Queue sèche (STYLE_BIBLE v3 §8.2 jeton `brush` : "fin sèche à droite,
## 64 px") : déborde à droite de la barre pleine. Texture (mèches disjointes,
## voir note de classe) étirée sur le rectangle de la queue et teintée
## `Comic.BRUSH` — plus de polygone unique qui se referme en pointe
## symétrique (l'ancienne "queue en poisson", supprimée).
func _draw_tail(w: float) -> void:
	var tail_w := minf(tail_px, maxf(size.y * 1.4, 24.0))
	if tail_w <= 1.0:
		return
	var rect := Rect2(Vector2(w, 0.0), Vector2(tail_w, size.y))
	draw_texture_rect(DRY_TAIL_TEXTURE, rect, false, Comic.BRUSH)
