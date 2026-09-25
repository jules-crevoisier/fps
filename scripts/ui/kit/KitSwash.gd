## KitSwash.gd
## Kit v4 « Encre, jaune, italique » (UX-30, docs/UI_DIRECTION_BL3.md §4.5/§6,
## docs/style/tokens.json v4.0.0 shape.swash) — coup de pinceau JAUNE
## (`Comic.SIGNAL`) posé DERRIÈRE un titre CHOISI, jamais une couleur
## d'accent différente : « toi, choisi, agis maintenant » (§1). Règle
## bloquante : au plus 1 par écran (tokens.json shape.swash.max_per_screen),
## réservé à l'élément PRINCIPAL choisi (nom du menu sélectionné, nom
## d'agent) — jamais un fond générique de section (voir `KitTrame`/
## `BrushHeader` pour les autres traitements de titre, INCHANGÉS, v3).
##
## `_visible_count` avertit (`push_warning`) si un second swash devient
## visible en même temps ; ne bloque JAMAIS le rendu — une règle éditoriale
## ne doit pas faire planter un export de jeu, seulement se signaler en
## revue (voir `docs/REVIEW.md`).
##
## Usage : `add_child(KitSwash.wrap(mon_label))` — `wrap()` construit le
## montage (swash DERRIÈRE, label DEVANT) pour l'appelant ; `mon_label`
## garde son texte/sa couleur, inchangés.
class_name KitSwash
extends Control

## Marge autour du texte enveloppé par `wrap()`, en px 1080p.
const PAD_X := 24.0
const PAD_Y := 10.0

static var _visible_count := 0

@export var seed_text: String = "":
	set(v):
		seed_text = v
		_shape_seed = hash(v)
		queue_redraw()

var _shape_seed: int = 0
var _was_visible := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# PAS de `z_index` négatif ici (voir remarque plus bas) : `z_index` en Godot 4 ordonne TOUT le
	# canvas (pas seulement les frères du même parent) — un swash à -1
	# repasserait derrière n'importe quel fond opaque dessiné plus tôt dans
	# l'écran (ex. le ColorRect plein cadre de la galerie), donc invisible
	# (piège vérifié en capture, UX-30). « Derrière son label » vient
	# uniquement de l'ORDRE dans l'arbre : `wrap()` ajoute ce nœud AVANT le
	# label, ce qui suffit — deux frères de même z_index se dessinent dans
	# l'ordre de la liste d'enfants.
	resized.connect(queue_redraw)
	visibility_changed.connect(_track_visibility)
	_track_visibility()


func _exit_tree() -> void:
	if _was_visible:
		_visible_count = maxi(0, _visible_count - 1)
		_was_visible = false


func _track_visibility() -> void:
	var vis := is_visible_in_tree()
	if vis and not _was_visible:
		_visible_count += 1
		if _visible_count > 1:
			push_warning(
				"KitSwash : %d pinceaux jaunes visibles en même temps — règle « 1 par écran »"
				% _visible_count + " (tokens.json shape.swash.max_per_screen, UI_DIRECTION_BL3.md §4.5)."
			)
	elif not vis and _was_visible:
		_visible_count = maxi(0, _visible_count - 1)
	_was_visible = vis


## Construit `label` (déjà créé par l'appelant, ex. `Comic.title_label_v4`)
## enveloppé d'un `KitSwash` DERRIÈRE lui, dimensionné sur sa taille minimale
## — un seul appel pour tout écran qui veut « le titre choisi sur un coup de
## pinceau jaune » (menu, sélection d'agent). Retourne le conteneur à ajouter
## à l'arbre ; `label` reste accessible tel quel par l'appelant (texte/
## couleur/police restent à sa charge).
static func wrap(label: Label) -> Control:
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.custom_minimum_size = label.get_minimum_size()

	var swash := KitSwash.new()
	swash.seed_text = label.text
	swash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	swash.offset_left = -PAD_X
	swash.offset_right = PAD_X
	swash.offset_top = -PAD_Y
	swash.offset_bottom = PAD_Y
	host.add_child(swash)

	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(label)
	return host


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	draw_colored_polygon(_ragged_rect(), Comic.SIGNAL)


## Rectangle jaune aux bords légèrement déchiquetés — un coup de pinceau sec
## n'a jamais un bord parfaitement droit (même esprit que `BrushHeader.
## _ragged_bar`, v3, INCHANGÉ) ; graine dérivée du texte souligné pour rester
## stable d'une frame à l'autre (pas de scintillement au redraw).
func _ragged_rect() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var jag := maxf(size.y * 0.06, 2.0)
	var steps := 8
	for i in steps + 1:
		var x := size.x * float(i) / float(steps)
		var n := sin(float(i) * 1.9 + float(_shape_seed % 7)) * jag
		pts.append(Vector2(x, n))
	for i in range(steps, -1, -1):
		var x := size.x * float(i) / float(steps)
		var n := cos(float(i) * 2.3 + float(_shape_seed % 5)) * jag
		pts.append(Vector2(x, size.y + n))
	return pts
