## VitalsHUD.gd
## Panneau de vitalité (contrat lead 2026-09-27, HUD en jeu, point 1) —
## bas-gauche : portrait carré NON incliné (Verrou), gros chiffre de PV
## (UiTokens.display T_3XL) + "/100" (T_M), 4 segments inclinés de 25 PV
## chacun (VERT plein / remplissage partiel / PAPIER vide, voir
## `segments_for`, fonction PURE testée directement), nom du personnage sous
## la barre. PV bas (<= 30, `is_low_hp`) : le chiffre ET les segments passent
## au ROUGE, avec une pulsation douce (alpha, `UiTokens.POP_S`-ish, jamais de
## mouvement — juste une respiration).
## Alimenté par GameHUD.gd depuis `Health.health_changed`/`died`/`respawned`.
class_name VitalsHUD
extends Control

const SEG_W := 74.0
const SEG_H := 22.0
const PORTRAIT_SIZE := 128.0
const _PULSE_PERIOD_S := 1.1
const _PULSE_MIN_ALPHA := 0.62

## Un segment de 25 PV : parallélogramme incliné (même pente que
## `UiTokens.SKEW_DEG`), fond PAPIER vide, remplissage `fraction` (0..1) de
## `full_color` (VERT normalement, ROUGE en PV bas) par-dessus — dessiné à la
## main (`_draw`) plutôt qu'une StyleBox : une StyleBox ne sait pas remplir
## une FRACTION de sa largeur, seulement pleine ou vide.
class _Segment extends Control:
	var fraction: float = 0.0
	var full_color: Color = UiTokens.GREEN

	func _draw() -> void:
		var sb := StyleBoxComic.new()
		sb.skew_deg = UiTokens.SKEW_DEG
		var full_rect := Rect2(Vector2.ZERO, size)
		var outer := sb.corners(full_rect)
		var shadow := PackedVector2Array()
		for p in outer:
			shadow.append(p + UiTokens.DROP_SMALL)
		draw_colored_polygon(shadow, UiTokens.INK)
		draw_colored_polygon(outer, UiTokens.INK)
		var inner_rect := full_rect.grow(-UiTokens.STROKE)
		if inner_rect.size.x <= 0.0 or inner_rect.size.y <= 0.0:
			return
		draw_colored_polygon(sb.corners(inner_rect), UiTokens.PAPER_2)
		if fraction > 0.001:
			var fill_w: float = inner_rect.size.x * clampf(fraction, 0.0, 1.0)
			var fill_rect := Rect2(inner_rect.position, Vector2(fill_w, inner_rect.size.y))
			draw_colored_polygon(sb.corners(fill_rect), full_color)


var _portrait: PanelContainer
var _hp_label: Label
var _max_label: Label
var _name_label: Label
var _segments: Array = []
var _low: bool = false
var _pulse_t: float = 0.0


func _ready() -> void:
	Comic.anchor(self, Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _process(delta: float) -> void:
	if not _low:
		return
	# Pulsation douce (alpha seul, jamais d'échelle/position — PV bas n'est
	# pas un moment de mouvement réduit à respecter, mais autant rester sobre).
	_pulse_t += delta
	var a := lerpf(1.0, _PULSE_MIN_ALPHA, (sin(_pulse_t * TAU / _PULSE_PERIOD_S) + 1.0) * 0.5)
	if _hp_label:
		_hp_label.modulate.a = a
	for seg in _segments:
		(seg as Control).modulate.a = a


## 4 fractions (0..1), une par segment de `max_hp / 4` PV — segment `i` est
## plein tant que `hp` couvre tout son intervalle `[i*step, (i+1)*step]`,
## partiellement rempli s'il couvre juste le début, vide sinon. Fonction PURE
## (aucun nœud), testée directement (tests/ui/test_vitals_hud.gd).
static func segments_for(hp: float, max_hp: float) -> Array:
	var step: float = max_hp / 4.0
	var out: Array = []
	for i in 4:
		var f: float = 0.0
		if step > 0.0:
			f = clampf((hp - float(i) * step) / step, 0.0, 1.0)
		out.append(f)
	return out


## PV bas (contrat : "<= 30") — seuil ABSOLU (pas relatif à `max_hp`, cette
## vie n'a jamais qu'une seule valeur max = 100 dans ce prototype).
static func is_low_hp(hp: float) -> bool:
	return hp <= 30.0


func _build() -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTokens.S3)
	row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	row.offset_left = UiTokens.EDGE_MARGIN
	row.offset_bottom = -UiTokens.EDGE_MARGIN
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(row)

	row.add_child(_build_portrait())

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UiTokens.S1)
	row.add_child(col)

	col.add_child(_build_hp_row())
	col.add_child(_build_segments_row())

	_name_label = UiTokens.make_label("", UiTokens.label(UiTokens.T_S, UiTokens.PAPER, 3, true), true)
	col.add_child(_name_label)


func _build_portrait() -> PanelContainer:
	var portrait := TextureRect.new()
	portrait.texture = UiTokens.icon("portrait_verrou")
	portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait = PanelContainer.new()
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiTokens.plate(UiTokens.YELLOW, 0.0, UiTokens.DROP)
	sb.pad = Vector2.ZERO
	_portrait.add_theme_stylebox_override("panel", sb)
	_portrait.add_child(portrait)
	return _portrait


func _build_hp_row() -> HBoxContainer:
	var hp_row := HBoxContainer.new()
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_theme_constant_override("separation", UiTokens.S1)
	hp_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_hp_label = UiTokens.make_label("100", UiTokens.display(UiTokens.T_3XL, UiTokens.PAPER))
	hp_row.add_child(_hp_label)
	_max_label = UiTokens.make_label("/100", UiTokens.display(UiTokens.T_M, UiTokens.PAPER, 6, Vector2(4, 4)))
	_max_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hp_row.add_child(_max_label)
	return hp_row


func _build_segments_row() -> HBoxContainer:
	var seg_row := HBoxContainer.new()
	seg_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seg_row.add_theme_constant_override("separation", UiTokens.S1)
	for i in 4:
		var seg := _Segment.new()
		seg.custom_minimum_size = Vector2(SEG_W, SEG_H)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seg.fraction = 1.0
		_segments.append(seg)
		seg_row.add_child(seg)
	return seg_row


## GameHUD.gd -> Health.health_changed(current, maximum).
func update_hp(current: float, maximum: float) -> void:
	_hp_label.text = str(int(round(current)))
	_max_label.text = "/%d" % int(round(maximum))
	_low = is_low_hp(current)
	var color := UiTokens.RED if _low else UiTokens.PAPER
	_hp_label.label_settings = UiTokens.display(UiTokens.T_3XL, color)
	if not _low:
		_hp_label.modulate.a = 1.0
		_pulse_t = 0.0
	var segs := segments_for(current, maximum)
	for i in _segments.size():
		var seg: _Segment = _segments[i]
		seg.fraction = segs[i]
		seg.full_color = UiTokens.RED if _low else UiTokens.GREEN
		seg.modulate.a = 1.0 if not _low else seg.modulate.a
		seg.queue_redraw()


func set_character_name(display_name: String) -> void:
	_name_label.text = display_name.to_upper()
