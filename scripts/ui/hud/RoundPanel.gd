## RoundPanel.gd
## Éléments des modes à manches (SnD/Duel, voir RoundMode) : vivants par
## équipe + crédits (cartouche sous le score), et une ComicBar de
## pose/désamorçage (bas-centre, discrète, visible seulement si active).
class_name RoundPanel
extends Control

var _extra: ComicPanel
var _extra_label: Label
var _bomb_wrap: ComicPanel
var _bomb_label: Label
var _bomb_bar: ComicBar

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_extra = ComicPanel.new()
	_extra.bg_color = Comic.PANEL
	_extra.border_width = Comic.RULE_W
	_extra.content_margin = Comic.SP_2
	Comic.anchor(_extra, Control.PRESET_CENTER_TOP)
	_extra.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_extra.offset_top = 96
	_extra.visible = false
	add_child(_extra)
	_extra_label = Comic.label("", Comic.SIZE_BODY, Comic.TEXT_DIM, Comic.FONT_LABEL)
	_extra.body.add_child(_extra_label)

	_bomb_wrap = ComicPanel.new()
	_bomb_wrap.bg_color = Comic.PANEL
	_bomb_wrap.border_width = Comic.RULE_W
	_bomb_wrap.content_margin = Comic.SP_2
	Comic.anchor(_bomb_wrap, Control.PRESET_CENTER_BOTTOM)
	_bomb_wrap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bomb_wrap.offset_bottom = -160
	_bomb_wrap.custom_minimum_size = Vector2(280, 0)
	_bomb_wrap.visible = false
	add_child(_bomb_wrap)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Comic.SP_1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bomb_wrap.body.add_child(v)
	_bomb_label = Comic.label("", Comic.SIZE_FLOOR, Comic.ALLY, Comic.FONT_NUMBER)
	_bomb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_bomb_label)
	_bomb_bar = ComicBar.new()
	_bomb_bar.custom_minimum_size = Vector2(260, Comic.SP_2)
	_bomb_bar.ticks = 1
	v.add_child(_bomb_bar)

func update_round(mode: Node) -> void:
	var is_round_mode: bool = mode != null and is_instance_valid(mode) and mode.has_method("alive_count")
	_extra.visible = is_round_mode
	if is_round_mode:
		var txt := "VIVANTS  %s %d — %d %s" % [Comic.team_glyph(true), mode.alive_count(0), mode.alive_count(1), Comic.team_glyph(false)]
		if "my_credits" in mode:
			txt += "    ·    %s" % HudFormat.format_credits(int(mode.my_credits))
		_extra_label.text = txt
	_update_bomb(mode, is_round_mode)

func _update_bomb(mode: Node, round_mode_active: bool) -> void:
	var plant_ratio := 0.0
	var defuse_ratio := 0.0
	var label := ""
	if round_mode_active and "bomb_plant_ratio" in mode:
		plant_ratio = float(mode.bomb_plant_ratio)
		defuse_ratio = float(mode.bomb_defuse_ratio)
		if plant_ratio > 0.0 and plant_ratio < 1.0:
			label = "POSE DE LA BOMBE"
		elif defuse_ratio > 0.0 and defuse_ratio < 1.0:
			label = "DÉSAMORÇAGE"
	var active := label != ""
	_bomb_wrap.visible = active
	if active:
		_bomb_bar.value = maxf(plant_ratio, defuse_ratio)
		_bomb_label.text = label
