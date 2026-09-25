## KitSlantBar.gd
## Kit de composants autocollant (ART-31, docs/STYLE_BIBLE.md §8.1/§8.2/§8.4)
## — famille « Autocollant », variante **barre inclinée** (§8.2 jeton
## `radius.slant` = 0, `slant_deg` = 12° : « barres/boutons/onglets inclinés,
## jamais un radius » — contrairement à `KitCard`, qui garde des coins ronds
## SANS inclinaison). CTA principal, onglets, boutons de mode/carte.
##
## Géométrie : parallélogramme cisaillé de `tan(12°)` sur X (même angle que
## l'italique, STYLE_BIBLE v3 §8.1 règle 5 « une seule inclinaison ») —
## CHK-38 vérifie 12 ± 0,5°. Le LABEL reste un `Label` non transformé, en
## police italique réelle (`Comic.button_secondary_font()`), jamais un nœud
## pivoté : le texte reste net et lisible, seule la police porte l'italique
## (même convention que `BrushHeader`/`Comic.title_label`).
##
## Ses 9 états (§8.4, colonne « Autocollant (carte, CTA) ») : voir KitCard.gd
## (même sémantique, table §8.4 partagée) — seule la FORME change.
class_name KitSlantBar
extends BaseButton

const DEFAULT_SIZE := Vector2(220.0, 64.0)
const SKELETON_HZ := 1.0
const SKELETON_MIN_ALPHA := 0.6
const SKELETON_MAX_ALPHA := 1.0

@export var bar_text: String = "":
	set(v):
		bar_text = v
		if _label:
			_label.text = bar_text.to_upper()
@export var accent_color: Color = Comic.BRUSH:
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
@export var loading: bool = false:
	set(v):
		loading = v
		_skeleton_t = 0.0
		_refresh()
@export var empty: bool = false:
	set(v):
		empty = v
		_refresh()
@export var error_text: String = "":
	set(v):
		error_text = v
		_refresh()
@export var state_override: int = -1:
	set(v):
		state_override = v
		_refresh()

var _held := false
var _shadow_off := Comic.SHADOW_HARD_OFFSET
var _translate := Vector2.ZERO
var _shadow_tween: Tween
var _skeleton_t := 0.0
var _label: Label
var _reason_label: Label
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

	_label = Comic.button_secondary_label(bar_text.to_upper(), Comic.SIZE_SUBTITLE, Comic.TEXT_ON_BRUSH)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.clip_text = true
	add_child(_label)

	_reason_label = Comic.label("", Comic.SIZE_FLOOR, Comic.DISABLED)
	_reason_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason_label.visible = false
	add_child(_reason_label)

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


func current_state() -> int:
	if state_override >= 0:
		return state_override
	if error_text != "":
		return KitStates.State.ERROR
	if empty:
		return KitStates.State.EMPTY
	if loading:
		return KitStates.State.LOADING
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


func _process(delta: float) -> void:
	if current_state() != KitStates.State.LOADING:
		set_process(false)
		return
	if Comic.reduced_motion():
		modulate.a = 0.8
		set_process(false)
		return
	_skeleton_t += delta
	var phase := sin(_skeleton_t * TAU * SKELETON_HZ) * 0.5 + 0.5
	modulate.a = lerpf(SKELETON_MIN_ALPHA, SKELETON_MAX_ALPHA, phase)


func _refresh() -> void:
	if _label == null or not is_inside_tree():
		return
	var s := current_state()
	tooltip_text = disabled_reason if (s == KitStates.State.DISABLED and disabled_reason != "") else ""

	modulate.a = 1.0
	_label.visible = s != KitStates.State.EMPTY
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_color_override("font_color", Comic.DISABLED if s == KitStates.State.DISABLED else Comic.TEXT_ON_BRUSH)

	_reason_label.visible = s == KitStates.State.DISABLED
	if _reason_label.visible:
		_reason_label.text = disabled_reason if disabled_reason != "" else KitStates.DEFAULT_DISABLED_REASON
		_reason_label.position = Vector2(-Comic.SP_2, size.y + Comic.SP_1)
		_reason_label.size = Vector2(size.x + Comic.SP_2 * 2.0, Comic.SIZE_FLOOR + Comic.SP_1)

	set_process(s == KitStates.State.LOADING)
	if s != KitStates.State.LOADING:
		modulate.a = 1.0

	var target_shadow := Comic.SHADOW_HARD_OFFSET
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
		KitStates.State.DISABLED:
			target_shadow = Vector2(2.0, 2.0)
		KitStates.State.LOADING, KitStates.State.EMPTY:
			target_shadow = Vector2.ZERO
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
## (STYLE_BIBLE v3 §8.2 `slant_deg` : « décalage horizontal = 0,2126 ×
## hauteur »).
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

	if s == KitStates.State.EMPTY:
		_draw_dashed_slant(_translate, Comic.TEXT_DIM, 2.0)
		_draw_plus_glyph(_translate + size * 0.5, Comic.TEXT_DIM)
		return

	if _shadow_off != Vector2.ZERO:
		draw_colored_polygon(_slant_points(_translate + _shadow_off), Comic.HARD_SHADOW_COLOR)

	var fill := accent_color
	if s == KitStates.State.LOADING:
		fill = Comic.PANEL_HI
	elif s == KitStates.State.DISABLED:
		fill = Color.from_hsv(accent_color.h, accent_color.s * 0.3, accent_color.v, accent_color.a)

	var body := _slant_points(_translate)
	draw_colored_polygon(body, fill)
	var closed := PackedVector2Array()
	for p in body:
		closed.append(p)
	closed.append(body[0])
	draw_polyline(closed, Comic.HARD_SHADOW_COLOR, Comic.STROKE_STICKER)

	if s == KitStates.State.SELECTED or s == KitStates.State.FOCUS:
		_draw_diecut_outline(body)
	if s == KitStates.State.SELECTED:
		var c := _translate + Vector2(size.x - 20.0, size.y * 0.5)
		KitStates.draw_centered_string(self, Comic.FONT_NUMBER, c, "✓", Comic.SIZE_SUBTITLE, Comic.HARD_SHADOW_COLOR)
	if s == KitStates.State.FOCUS:
		var cy := _translate.y + size.y * 0.5
		var x := _translate.x - 22.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, cy - 9.0), Vector2(x + 14.0, cy), Vector2(x, cy + 9.0)]), Comic.BRUSH)
	if s == KitStates.State.DISABLED:
		var lc := _translate + Vector2(size.x - 22.0, size.y - 22.0)
		draw_arc(lc, 7.0, PI, TAU, 14, Comic.HARD_SHADOW_COLOR, 3.0, true)
		draw_rect(Rect2(lc + Vector2(-8.0, 0.0), Vector2(16.0, 12.0)), Comic.HARD_SHADOW_COLOR, true)
	if s == KitStates.State.ERROR:
		var center := _translate + size * 0.5
		draw_set_transform(center, deg_to_rad(-8.0), Vector2.ONE)
		var font := Comic.title_font()
		var text_size := font.get_string_size("RATÉ", HORIZONTAL_ALIGNMENT_LEFT, -1, Comic.SIZE_LABEL)
		draw_rect(Rect2(-text_size * 0.5 - Vector2(Comic.SP_2, Comic.SP_1), text_size + Vector2(Comic.SP_2, Comic.SP_1) * 2.0), Comic.HARD_SHADOW_COLOR, false, 3.0)
		KitStates.draw_centered_string(self, font, Vector2.ZERO, "RATÉ", Comic.SIZE_LABEL, Comic.HARD_SHADOW_COLOR)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_diecut_outline(body: PackedVector2Array) -> void:
	var center := Rect2(body[0], Vector2.ZERO)
	for p in body:
		center = center.expand(p)
	var c := center.get_center()
	var grown := PackedVector2Array()
	for p in body:
		grown.append(p + (p - c).normalized() * (Comic.STROKE_STICKER + Comic.STROKE_DIECUT))
	grown.append(grown[0])
	draw_polyline(grown, Comic.TEXT, Comic.STROKE_DIECUT)


func _draw_plus_glyph(center: Vector2, color: Color) -> void:
	var half := 12.0
	draw_line(center + Vector2(-half, 0.0), center + Vector2(half, 0.0), color, 3.0)
	draw_line(center + Vector2(0.0, -half), center + Vector2(0.0, half), color, 3.0)


func _draw_dashed_slant(origin: Vector2, color: Color, width: float) -> void:
	var pts := _slant_points(origin)
	for i in pts.size():
		draw_dashed_line(pts[i], pts[(i + 1) % pts.size()], color, width, 6.0)
