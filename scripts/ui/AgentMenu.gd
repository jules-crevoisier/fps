## AgentMenu.gd
## Sélection d'agent (classe) depuis le menu principal : liste les agents, leurs
## capacités, et permet d'en choisir un (stocké dans AgentDatabase.selected_index).
## Design.md v2 §9/§11 : cartes charcoal, l'agent sélectionné gagne sa couleur
## + un soulignement pinceau (ComicPanel.selected).
extends Control

signal closed

var _cards: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Comic.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, Comic.SAFE_MARGIN)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	margin.add_child(root)

	var header := BrushHeader.new()
	header.title = "Agents"
	root.add_child(header)

	var back_row := HBoxContainer.new()
	back_row.add_theme_constant_override("separation", Comic.SP_2)
	back_row.add_theme_constant_override("margin_top", Comic.SP_2)
	root.add_child(back_row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back := Button.new()
	back.text = "Retour"
	back.custom_minimum_size = Vector2(150, 46)
	back.pressed.connect(func(): closed.emit())
	back_row.add_child(spacer)
	back_row.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", Comic.SP_2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var agents := AgentDatabase.all()
	for i in agents.size():
		list.add_child(_agent_card(agents[i], i))
	_refresh_selection()
	back.grab_focus()

func _agent_card(agent: AgentConfig, index: int) -> ComicPanel:
	var panel := ComicPanel.new()
	panel.bg_color = Comic.PANEL
	panel.border_width = Comic.RULE_W

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Comic.SP_1)
	panel.body.add_child(box)

	var head := HBoxContainer.new()
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Comic.title_label(agent.agent_name, Comic.SIZE_LABEL, Comic.TEXT_DIM)
	name_box.add_child(name_lbl)
	name_box.add_child(Comic.label(agent.role, Comic.SIZE_BODY, Comic.TEXT_DIM, Comic.FONT_LABEL))
	var choose := Button.new()
	choose.custom_minimum_size = Vector2(160, 44)
	choose.pressed.connect(_choose.bind(index))
	_cards.append({"panel": panel, "button": choose, "name_lbl": name_lbl, "index": index, "color": agent.color})
	head.add_child(name_box)
	head.add_child(choose)
	box.add_child(head)

	box.add_child(Comic.label(agent.description, Comic.SIZE_BODY, Comic.TEXT, Comic.FONT_BODY))

	for ab in agent.abilities:
		var line := "%s — %s : %s" % [ab.slot, ab.display_name, ab.description]
		var l := Comic.label(line, Comic.SIZE_BODY, Comic.TEXT_DIM, Comic.FONT_BODY)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		box.add_child(l)
	return panel

func _choose(index: int) -> void:
	AgentDatabase.selected_index = index
	_refresh_selection()

func _refresh_selection() -> void:
	for c in _cards:
		var selected: bool = c.index == AgentDatabase.selected_index
		c.button.text = "SÉLECTIONNÉ" if selected else "Choisir"
		c.button.disabled = selected
		var col: Color = c.color if selected else Comic.TEXT_DIM
		c.panel.selected = selected
		c.panel.border_color = c.color if selected else Comic.RULE
		c.panel.border_width = Comic.RULE_W_STRONG if selected else Comic.RULE_W
		c.name_lbl.add_theme_color_override("font_color", col)
