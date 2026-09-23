## ScoreboardPanel.gd
## Tableau des scores (maintenir Tab) : page encre plein écran, une colonne par
## équipe, glyphes ●/▼ (jamais la couleur seule).
class_name ScoreboardPanel
extends Control

var _panel: ComicPanel
var _list: VBoxContainer

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(Comic.BG.r, Comic.BG.g, Comic.BG.b, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	center.add_child(wrap)

	var header := BrushHeader.new()
	header.title = "Tableau des scores"
	header.custom_minimum_size = Vector2(620, 0)
	wrap.add_child(header)

	_panel = ComicPanel.new()
	_panel.bg_color = Comic.PANEL
	_panel.border_width = Comic.RULE_W
	_panel.content_margin = Comic.SP_5
	wrap.add_child(_panel)

	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(620, 0)
	_list.add_theme_constant_override("separation", Comic.SP_2)
	_panel.body.add_child(_list)

func refresh(match_node: Node) -> void:
	if match_node == null or not is_instance_valid(match_node) or _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	var info: Dictionary = match_node.player_info
	for team in [0, 1]:
		var team_color := Comic.ALLY if team == 0 else Comic.enemy_color()
		_list.add_child(Comic.label("%s ÉQUIPE %d" % [Comic.team_glyph(team == 0), team + 1], Comic.SIZE_LABEL, team_color, Comic.FONT_NUMBER))
		for id in info:
			if int(info[id].team) != team:
				continue
			var row := "   %-18s  %d / %d" % [str(info[id].name), int(info[id].kills), int(info[id].deaths)]
			_list.add_child(Comic.label(row, Comic.SIZE_BODY, Comic.TEXT, Comic.FONT_BODY))
