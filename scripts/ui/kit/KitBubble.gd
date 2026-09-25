## KitBubble.gd
## Kit de composants autocollant (ART-31, docs/STYLE_BIBLE.md §8.1/§8.2/§8.4,
## §9.6 « Reveal ») — famille « Autocollant », variante **bulle** BD : la
## bulle de ping/révélation (« bulle papier, "!" encre, contour encre, pointe
## vers la cible » — épingle 02, §9.6 Reveal). Corps arrondi `radius.sticker`
## + pointe triangulaire, contour encre 3 px, ombre dure (6, 6), fond PAPIER
## par défaut (pas une couleur d'agent — c'est un indicateur universel).
##
## Ses 9 états suivent la même table §8.4 « Autocollant (carte, CTA) » que
## `KitCard`/`KitSlantBar` — seule la géométrie (corps + pointe) change.
class_name KitBubble
extends BaseButton

const DEFAULT_SIZE := Vector2(96.0, 72.0)
const TAIL_W := 20.0
const TAIL_H := 16.0
const SKELETON_HZ := 1.0
const SKELETON_MIN_ALPHA := 0.6
const SKELETON_MAX_ALPHA := 1.0

## Position horizontale de la pointe (0..1 de la largeur du corps) — « pointe
## vers la cible », configurable selon où se trouve la cible visée.
@export var tail_anchor: float = 0.28
@export var glyph_text: String = "!"
## Fond « papier » par défaut (§9.6 « bulle papier ») — pas une couleur
## d'agent ; reste exposé pour les usages qui en ont vraiment besoin (pings
## d'équipe teintés `Comic.ALLY`, par ex.).
@export var accent_color: Color = Comic.TEXT:
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
var _reason_label: Label
var _last_state := -1


func _ready() -> void:
	custom_minimum_size = DEFAULT_SIZE + Vector2(0.0, TAIL_H)
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


## Rect du corps (hors pointe, qui déborde sous ce rect).
func _body_rect() -> Rect2:
	return Rect2(_translate, Vector2(size.x, size.y - TAIL_H))


func _refresh() -> void:
	if _reason_label == null or not is_inside_tree():
		return
	var s := current_state()
	tooltip_text = disabled_reason if (s == KitStates.State.DISABLED and disabled_reason != "") else ""
	modulate.a = 1.0

	_reason_label.visible = s == KitStates.State.DISABLED
	if _reason_label.visible:
		_reason_label.text = disabled_reason if disabled_reason != "" else KitStates.DEFAULT_DISABLED_REASON
		_reason_label.position = Vector2(0.0, size.y + Comic.SP_1)
		_reason_label.size = Vector2(size.x, Comic.SIZE_FLOOR + Comic.SP_1)

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


func _tail_points(origin: Vector2) -> PackedVector2Array:
	var body := Rect2(origin, Vector2(size.x, size.y - TAIL_H))
	var apex_x := body.position.x + body.size.x * tail_anchor
	return PackedVector2Array([
		Vector2(apex_x - TAIL_W * 0.5, body.position.y + body.size.y),
		Vector2(apex_x + TAIL_W * 0.5, body.position.y + body.size.y),
		Vector2(apex_x - TAIL_W * 0.15, body.position.y + body.size.y + TAIL_H),
	])


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 1.0:
		return
	var s := current_state()
	var body := Rect2(_translate, Vector2(size.x, size.y - TAIL_H))
	var radius := Comic.RADIUS_STICKER

	if s == KitStates.State.EMPTY:
		_draw_dashed_bubble(_translate, Comic.TEXT_DIM, 2.0, radius)
		draw_line(body.get_center() + Vector2(-12.0, 0.0), body.get_center() + Vector2(12.0, 0.0), Comic.TEXT_DIM, 3.0)
		draw_line(body.get_center() + Vector2(0.0, -12.0), body.get_center() + Vector2(0.0, 12.0), Comic.TEXT_DIM, 3.0)
		return

	if _shadow_off != Vector2.ZERO:
		var shadow_body := Rect2(body.position + _shadow_off, body.size)
		draw_style_box(Comic.hard_shadow_style(radius), shadow_body)
		draw_colored_polygon(_tail_points(_translate + _shadow_off), Comic.HARD_SHADOW_COLOR)

	var fill := accent_color
	if s == KitStates.State.LOADING:
		fill = Comic.PANEL_HI
	elif s == KitStates.State.DISABLED:
		fill = Color.from_hsv(accent_color.h, accent_color.s * 0.3, accent_color.v, accent_color.a)

	draw_style_box(Comic.panel_style(fill, Comic.HARD_SHADOW_COLOR, radius, Comic.STROKE_STICKER), body)
	var tail := _tail_points(_translate)
	draw_colored_polygon(tail, fill)
	var tail_closed := PackedVector2Array([tail[0], tail[2], tail[1]])
	draw_polyline(tail_closed, Comic.HARD_SHADOW_COLOR, Comic.STROKE_STICKER)

	var glyph_color := Comic.HARD_SHADOW_COLOR if s != KitStates.State.DISABLED else Comic.DISABLED
	if s != KitStates.State.LOADING:
		KitStates.draw_centered_string(self, Comic.FONT_NUMBER, body.get_center(), glyph_text, Comic.SIZE_SUBTITLE, glyph_color)

	if s == KitStates.State.SELECTED or s == KitStates.State.FOCUS:
		var outline := StyleBoxFlat.new()
		outline.draw_center = false
		outline.set_border_width_all(Comic.STROKE_DIECUT)
		outline.border_color = Comic.TEXT
		outline.set_corner_radius_all(radius + Comic.STROKE_STICKER + Comic.STROKE_DIECUT / 2)
		outline.anti_aliasing = true
		draw_style_box(outline, body.grow(Comic.STROKE_STICKER + Comic.STROKE_DIECUT * 0.5))
	if s == KitStates.State.FOCUS:
		var cy := body.position.y + body.size.y * 0.5
		var x := body.position.x - 22.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, cy - 9.0), Vector2(x + 14.0, cy), Vector2(x, cy + 9.0)]), Comic.BRUSH)
	if s == KitStates.State.DISABLED:
		var lc := body.position + Vector2(body.size.x - 20.0, body.size.y - 20.0)
		draw_arc(lc, 6.0, PI, TAU, 14, Comic.HARD_SHADOW_COLOR, 3.0, true)
		draw_rect(Rect2(lc + Vector2(-7.0, 0.0), Vector2(14.0, 11.0)), Comic.HARD_SHADOW_COLOR, true)
	if s == KitStates.State.ERROR:
		var center := body.get_center()
		draw_set_transform(center, deg_to_rad(-8.0), Vector2.ONE)
		var font := Comic.title_font()
		var text_size := font.get_string_size("RATÉ", HORIZONTAL_ALIGNMENT_LEFT, -1, Comic.SIZE_FLOOR)
		draw_rect(Rect2(-text_size * 0.5 - Vector2(4.0, 2.0), text_size + Vector2(4.0, 2.0) * 2.0), Comic.HARD_SHADOW_COLOR, false, 2.0)
		KitStates.draw_centered_string(self, font, Vector2.ZERO, "RATÉ", Comic.SIZE_FLOOR, Comic.HARD_SHADOW_COLOR)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_dashed_bubble(origin: Vector2, color: Color, width: float, radius: int) -> void:
	var body := Rect2(origin, Vector2(size.x, size.y - TAIL_H))
	var cut := float(radius)
	var p := body.position
	var sz := body.size
	var pts := PackedVector2Array([
		Vector2(p.x + cut, p.y), Vector2(p.x + sz.x - cut, p.y),
		Vector2(p.x + sz.x, p.y + cut), Vector2(p.x + sz.x, p.y + sz.y - cut),
		Vector2(p.x + sz.x - cut, p.y + sz.y), Vector2(p.x + cut, p.y + sz.y),
		Vector2(p.x, p.y + sz.y - cut), Vector2(p.x, p.y + cut),
	])
	for i in pts.size():
		draw_dashed_line(pts[i], pts[(i + 1) % pts.size()], color, width, 6.0)
