## KitSlantTile.gd
## Kit v4 « Encre, jaune, italique » (UX-30, docs/UI_DIRECTION_BL3.md §4.3/§5/
## §6, docs/style/tokens.json v4.0.0 shape.slant_deg/stroke/shadow) — tuile
## penchée à 12° (même cisaillement que l'italique et que KitSlantBar,
## `Comic.SLANT_DEG`) : capacités du HUD (C·A·E·X, bas-centre), portraits
## d'agent en sélection (6 tuiles). Porte un icône/lettre (`key_label`, coin
## haut-gauche) et un titre optionnel (`tile_title`, sous la tuile) — jamais
## un fond flottant SEUL sur la 3D (règle « zéro fond » du HUD, §5) : ici la
## tuile EST le contenant, avec son ombre dure portée comme toute plaque v4.
##
## Exactement 6 états (contrat UX-30 — ni loading, ni empty, ni error, qui ne
## s'appliquent pas à une tuile de capacité) : normal, survol, focus, pressé,
## désactivé (avec raison), sélectionné. Réutilise `KitStates.State` (kit
## partagé, ART-31) pour les 6 valeurs communes plutôt que d'inventer une
## seconde énumération, mais restreint `current_state()`/`state_override` à
## `TILE_STATES` : un `state_override` hors de cette liste (LOADING/EMPTY/
## ERROR) est ignoré, jamais un état hors contrat.
class_name KitSlantTile
extends BaseButton

const DEFAULT_SIZE := Vector2(88.0, 88.0)

## Les 6 états du contrat, dans l'ordre d'affichage de la galerie.
const TILE_STATES: Array[int] = [
	KitStates.State.DEFAULT, KitStates.State.HOVER, KitStates.State.FOCUS,
	KitStates.State.PRESSED, KitStates.State.DISABLED, KitStates.State.SELECTED,
]

@export var key_label: String = "":
	set(v):
		key_label = v
		queue_redraw()
@export var tile_title: String = "":
	set(v):
		tile_title = v
		if _title_label:
			_title_label.text = tile_title.to_upper()
## Couleur de la tuile CHOISIE (§4.6 « choisi : fond signal ») — jamais une
## couleur d'équipe/d'agent dans le HUD (`hud.agent_colours_in_hud` = false) ;
## `Comic.SIGNAL` par défaut, mais un écran hors-HUD (sélection d'agent) peut
## passer la couleur-clé de l'agent pour sa propre tuile choisie.
@export var accent_color: Color = Comic.SIGNAL:
	set(v):
		accent_color = v
		queue_redraw()
@export var disabled_reason: String = "":
	set(v):
		disabled_reason = v
		_refresh()
@export var selected: bool = false:
	set(v):
		selected = v
		_refresh()
@export var state_override: int = -1:
	set(v):
		state_override = v
		_refresh()

var _held := false
var _shadow_off := Comic.SHADOW_HARD_SMALL_OFFSET
var _translate := Vector2.ZERO
var _shadow_tween: Tween
var _title_label: Label
var _reason_label: Label
var _hatch: TextureRect
var _last_state := -1


func _ready() -> void:
	custom_minimum_size = DEFAULT_SIZE
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	mouse_entered.connect(_refresh)
	mouse_exited.connect(_refresh)
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	resized.connect(_refresh)

	_title_label = Comic.meta_label_v4(tile_title, Comic.SIZE_21, Comic.TEXT_DIM)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title_label)

	_reason_label = Comic.label("", Comic.SIZE_FLOOR, Comic.DISABLED)
	_reason_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_reason_label.visible = false
	add_child(_reason_label)

	# Hachures 45° (§4.6 « désactivé : paper_off + hachures + raison ») —
	# `Comic.hatch_rect()` existant (v3, INCHANGÉ), réutilisé tel quel.
	_hatch = Comic.hatch_rect(10, Comic.DISABLED, 0.5)
	_hatch.visible = false
	add_child(_hatch)

	_refresh()


func _on_button_down() -> void:
	_held = true
	_refresh()


func _on_button_up() -> void:
	_held = false
	_refresh()


func set_disabled_with_reason(reason: String) -> void:
	disabled_reason = reason
	disabled = true
	_refresh()


## État courant, restreint aux 6 valeurs de `TILE_STATES` (contrat UX-30) —
## un `state_override` hors de cette liste retombe sur l'état RÉEL, jamais
## sur un LOADING/EMPTY/ERROR hors périmètre de ce composant.
func current_state() -> int:
	if state_override in TILE_STATES:
		return state_override
	if disabled:
		return KitStates.State.DISABLED
	if selected:
		return KitStates.State.SELECTED
	if _held:
		return KitStates.State.PRESSED
	if has_focus():
		return KitStates.State.FOCUS
	if is_hovered():
		return KitStates.State.HOVER
	return KitStates.State.DEFAULT


func _refresh() -> void:
	if _title_label == null or not is_inside_tree():
		return
	var s := current_state()
	tooltip_text = disabled_reason if (s == KitStates.State.DISABLED and disabled_reason != "") else ""

	_title_label.text = tile_title.to_upper()
	_title_label.visible = tile_title != ""
	_title_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_title_label.offset_top = -Comic.SIZE_21 - Comic.SP_1
	_title_label.offset_bottom = -Comic.SP_1
	# Jaune = texte encre (§4.2 règle 4) : jamais `paper` sur `signal`, illisible.
	var title_color := Comic.TEXT_DIM
	if s == KitStates.State.DISABLED:
		title_color = Comic.DISABLED
	elif s == KitStates.State.SELECTED:
		title_color = Comic.HARD_SHADOW_COLOR
	_title_label.add_theme_color_override("font_color", title_color)

	_reason_label.visible = s == KitStates.State.DISABLED
	if _reason_label.visible:
		_reason_label.text = disabled_reason if disabled_reason != "" else KitStates.DEFAULT_DISABLED_REASON
		_reason_label.position = Vector2(-Comic.SP_2, size.y + Comic.SP_1)
		_reason_label.size = Vector2(size.x + Comic.SP_2 * 2.0, Comic.SIZE_FLOOR * 2.0)

	_hatch.visible = s == KitStates.State.DISABLED
	if _hatch.visible:
		_hatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var target_shadow := Comic.SHADOW_HARD_SMALL_OFFSET
	var target_translate := Vector2.ZERO
	var anim_dur := Comic.DUR_FOCUS
	match s:
		KitStates.State.HOVER:
			target_shadow = Comic.SHADOW_HOVER_OFFSET
			target_translate = Comic.SHADOW_HOVER_TRANSLATE
		KitStates.State.PRESSED:
			target_shadow = Comic.SHADOW_PRESSED_OFFSET
			target_translate = Comic.SHADOW_PRESSED_TRANSLATE
			anim_dur = Comic.DUR_PRESS
		KitStates.State.SELECTED:
			# §4.6 « choisi : ombre (6,6) » — la seule tuile à porter la
			# grande ombre dure de plaque, jamais la petite ombre par défaut.
			target_shadow = Comic.SHADOW_HARD_OFFSET
		KitStates.State.DISABLED:
			target_shadow = Vector2(2.0, 2.0)
	_animate_shadow(target_shadow, target_translate, anim_dur, s)
	_last_state = s
	queue_redraw()


func _animate_shadow(target_shadow: Vector2, target_translate: Vector2, dur: float, s: int) -> void:
	if Comic.reduced_motion() or s == _last_state:
		_shadow_off = target_shadow
		_translate = target_translate
		queue_redraw()
		return
	if _shadow_tween and _shadow_tween.is_valid():
		_shadow_tween.kill()
	_shadow_tween = create_tween()
	_shadow_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_shadow_tween.set_parallel(true)
	_shadow_tween.tween_method(_set_shadow_off, _shadow_off, target_shadow, dur)
	_shadow_tween.tween_method(_set_translate, _translate, target_translate, dur)


func _set_shadow_off(v: Vector2) -> void:
	_shadow_off = v
	queue_redraw()


func _set_translate(v: Vector2) -> void:
	_translate = v
	queue_redraw()


## Parallélogramme cisaillé de `tan(Comic.SLANT_DEG)` sur X, ancré à `origin`
## — même géométrie que KitSlantBar (une seule inclinaison, CHK-38).
func _slant_points(origin: Vector2) -> PackedVector2Array:
	var shear := size.y * tan(deg_to_rad(Comic.SLANT_DEG))
	return PackedVector2Array([
		origin + Vector2(shear, 0.0),
		origin + Vector2(size.x + shear, 0.0),
		origin + Vector2(size.x, size.y),
		origin + Vector2(0.0, size.y),
	])


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var s := current_state()

	if _shadow_off != Vector2.ZERO:
		draw_colored_polygon(_slant_points(_translate + _shadow_off), Comic.HARD_SHADOW_COLOR)

	var fill := Comic.PANEL
	if s == KitStates.State.SELECTED:
		fill = accent_color
	elif s == KitStates.State.DISABLED:
		fill = Comic.PANEL_HI

	var body := _slant_points(_translate)
	draw_colored_polygon(body, fill)
	var closed := PackedVector2Array()
	for p in body:
		closed.append(p)
	closed.append(body[0])
	draw_polyline(closed, Comic.HARD_SHADOW_COLOR, Comic.STROKE_INK)

	# Focus (§4.6 « survol + contour paper 3 px décalé de 4 px, lisible même
	# sur un élément choisi ») : anneau `paper`, jamais `signal` (réservé au
	# remplissage sélectionné) — dessiné en plus de la sélection le cas échéant.
	if s == KitStates.State.FOCUS:
		_draw_ring(body, Comic.TEXT, Comic.STROKE_FOCUS, Comic.FOCUS_RING_OFFSET_PX)

	var text_color := Comic.HARD_SHADOW_COLOR if s == KitStates.State.SELECTED else Comic.TEXT
	if key_label != "":
		# Le haut du parallélogramme est décalé du cisaillement : la touche suit le bord.
		var kc := _translate + Vector2(size.y * tan(deg_to_rad(Comic.SLANT_DEG)) + Comic.SP_3, Comic.SP_3)
		KitStates.draw_centered_string(self, Comic.title_font(), kc, key_label, Comic.SIZE_21, text_color)

	if s == KitStates.State.SELECTED:
		var check_c := _translate + Vector2(size.x - Comic.SP_3, Comic.SP_3)
		KitStates.draw_centered_string(self, Comic.FONT_NUMBER, check_c, "✓", Comic.SIZE_FLOOR, Comic.HARD_SHADOW_COLOR)


## Anneau agrandi de `offset_px` autour du polygone `body` (STYLE_BIBLE v4
## §4.6 « anneau de focus décalé ») — même construction que `KitSlantBar.
## _draw_diecut_outline`, généralisée à un offset/une couleur/une épaisseur
## paramétrables plutôt que les constantes v3 figées.
func _draw_ring(body: PackedVector2Array, color: Color, width: float, offset_px: float) -> void:
	var bounds := Rect2(body[0], Vector2.ZERO)
	for p in body:
		bounds = bounds.expand(p)
	var c := bounds.get_center()
	var grown := PackedVector2Array()
	for p in body:
		grown.append(p + (p - c).normalized() * offset_px)
	grown.append(grown[0])
	draw_polyline(grown, color, width)
