## EndPanel.gd
## Page de fin v2 (design.md §13 "400 ms end page") : fond charcoal, bandeau
## pinceau "ÉQUIPE X GAGNE", tableau des scores, Rejouer / Retour au menu.
class_name EndPanel
extends Control

signal replay_pressed
signal menu_pressed

var _header: BrushHeader
var _score_label: Label
var _list: VBoxContainer

func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Comic.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	wrap.custom_minimum_size = Vector2(520, 0)
	center.add_child(wrap)

	_header = BrushHeader.new()
	_header.title = "Victoire"
	wrap.add_child(_header)

	var panel := ComicPanel.new()
	panel.bg_color = Comic.PANEL
	panel.border_width = Comic.RULE_W
	panel.content_margin = Comic.SP_6
	wrap.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Comic.SP_3)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.body.add_child(box)

	_score_label = Comic.number_label("", Comic.SIZE_DISPLAY_MD, Comic.ALLY)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_score_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", Comic.SP_1)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var replay := Button.new()
	replay.text = "Rejouer"
	replay.custom_minimum_size = Vector2(0, 56)
	replay.pressed.connect(func(): replay_pressed.emit())
	box.add_child(replay)
	var menu := Button.new()
	menu.text = "Retour au menu"
	menu.custom_minimum_size = Vector2(0, 56)
	menu.pressed.connect(func(): menu_pressed.emit())
	box.add_child(menu)

func show_result(winner_team: int, team0: int, team1: int, match_node: Node) -> void:
	visible = true
	_header.title = "Équipe %d gagne" % (winner_team + 1)
	_header.replay()
	_score_label.text = "%d — %d" % [team0, team1]
	for c in _list.get_children():
		c.queue_free()
	if match_node == null or not is_instance_valid(match_node):
		return
	var info: Dictionary = match_node.player_info
	for team in [0, 1]:
		var team_color := Comic.ALLY if team == 0 else Comic.enemy_color()
		_list.add_child(Comic.label("%s ÉQUIPE %d" % [Comic.team_glyph(team == 0), team + 1], Comic.SIZE_BODY, team_color, Comic.FONT_NUMBER))
		for id in info:
			if int(info[id].team) != team:
				continue
			var row := "   %-18s  %d / %d" % [str(info[id].name), int(info[id].kills), int(info[id].deaths)]
			_list.add_child(Comic.label(row, Comic.SIZE_BODY, Comic.TEXT, Comic.FONT_BODY))

func hide_result() -> void:
	visible = false
