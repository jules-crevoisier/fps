## AgentMenu.gd
## Sélection d'agent (classe) depuis le menu principal : liste les agents, leurs
## capacités, et permet d'en choisir un (stocké dans AgentDatabase.selected_index).
extends Control

signal closed

var _cards: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.10, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 40)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "AGENTS"
	title.add_theme_font_size_override("font_size", 40)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back := Button.new()
	back.text = "Retour"
	back.custom_minimum_size = Vector2(140, 40)
	back.pressed.connect(func(): closed.emit())
	header.add_child(title)
	header.add_child(back)
	root.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var agents := AgentDatabase.all()
	for i in agents.size():
		list.add_child(_agent_card(agents[i], i))
	_refresh_selection()

func _agent_card(agent: AgentConfig, index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.18, 1.0)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	style.border_color = agent.color
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	panel.add_child(box)

	var head := HBoxContainer.new()
	var name_lbl := _lbl(agent.agent_name, 26, agent.color)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var choose := Button.new()
	choose.custom_minimum_size = Vector2(150, 36)
	choose.pressed.connect(_choose.bind(index))
	_cards.append({"panel": panel, "button": choose, "index": index})
	head.add_child(name_lbl)
	head.add_child(choose)
	box.add_child(head)

	box.add_child(_lbl(agent.description, 15, Color(0.8, 0.82, 0.86)))

	var abil := ""
	for ab in agent.abilities:
		abil += "%s:%s   " % [ab.slot, ab.display_name]
	box.add_child(_lbl(abil, 16, Color(0.6, 0.8, 1.0)))
	return panel

func _choose(index: int) -> void:
	AgentDatabase.selected_index = index
	_refresh_selection()

func _refresh_selection() -> void:
	for c in _cards:
		var selected: bool = c.index == AgentDatabase.selected_index
		c.button.text = "SÉLECTIONNÉ" if selected else "Choisir"
		c.button.disabled = selected

func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
