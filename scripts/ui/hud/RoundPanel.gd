## RoundPanel.gd
## Éléments des modes à manches (SnD/Duel, voir RoundMode) : vivants ALLIÉS
## puis ENNEMIS (RELATIF au joueur local, docs/research/04_ui_ux.md §2.3 —
## jamais « équipe 0 — équipe 1 » brut) + crédits (suffixe de la même ligne),
## et une barre de pose/désamorçage (bas-centre, discrète, visible seulement
## si active).
## v4 « Encre, jaune, italique » (UX-31) : remplace les deux chips ComicPanel
## v3 par du texte encré direct (§5 #1 « zéro fond derrière le texte du
## HUD ») — la barre de pose/désamorçage GARDE un fond (`ComicBar`, une piste
## de progression, pas « du texte en boîte »). Le format EXACT de
## `_extra_label.text` (« VIVANTS  ● 2 — 4 ▼ », espaces compris) est
## VERROUILLÉ par tests/ui/test_team_relative.gd (hors de ma liste de
## fichiers) : conservé caractère pour caractère, seul l'habillage visuel
## change.
class_name RoundPanel
extends Control

var _extra_label: Label
var _bomb_wrap: Control
var _bomb_label: Label
var _bomb_bar: ComicBar

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_extra_label = Comic.ink_label("", Comic.SIZE_28, Comic.paper_dim_color(), Comic.meta_font_v4(Comic.SIZE_28))
	Comic.anchor(_extra_label, Control.PRESET_CENTER_TOP)
	_extra_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_extra_label.offset_top = 96.0
	_extra_label.visible = false
	add_child(_extra_label)

	_bomb_wrap = Control.new()
	_bomb_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Comic.anchor(_bomb_wrap, Control.PRESET_CENTER_BOTTOM)
	_bomb_wrap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bomb_wrap.offset_bottom = -160.0
	_bomb_wrap.custom_minimum_size = Vector2(280.0, 60.0)
	_bomb_wrap.visible = false
	add_child(_bomb_wrap)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Comic.SP_1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bomb_wrap.add_child(v)
	_bomb_label = Comic.ink_label("", Comic.SIZE_21, Comic.ALLY, Comic.meta_font_v4(Comic.SIZE_21))
	_bomb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_bomb_label)
	_bomb_bar = ComicBar.new()
	_bomb_bar.custom_minimum_size = Vector2(260.0, Comic.SP_2)
	_bomb_bar.ticks = 1
	v.add_child(_bomb_bar)

## `local_team` : équipe du joueur local — décide quel décompte de vivants va
## à gauche (allié, ●) et à droite (ennemi, ▼), voir `Comic.is_ally`.
func update_round(mode: Node, local_team: int) -> void:
	var is_round_mode: bool = mode != null and is_instance_valid(mode) and mode.has_method("alive_count")
	_extra_label.visible = is_round_mode
	if is_round_mode:
		var my_index := local_team if local_team in [0, 1] else 0
		var other_index := 1 - my_index
		var txt := "VIVANTS  %s %d — %d %s" % [Comic.team_glyph(true), mode.alive_count(my_index), mode.alive_count(other_index), Comic.team_glyph(false)]
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
