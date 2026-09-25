## AgentMenu.gd
## UX-33 -- UI v4 « Encre, jaune, italique » (docs/UI_DIRECTION_BL3.md, UX-30
## VALIDÉE par l'utilisateur le 2026-09-25) : liste des agents depuis le menu
## principal, chacun avec son kit complet -- réutilise désormais
## `KitCard.ability_row_v4` (la même ligne "kit" que la colonne de droite de
## AgentSelectScreen.gd) au lieu de la méthode `_ability_row` locale (v3,
## icône seule + texte) dupliquée entre ces deux écrans avant cette tranche.
## Permet d'en choisir un (stocké dans AgentDatabase.selected_index) --
## l'agent choisi gagne SEUL la couleur `signal` (jamais sa propre
## couleur-clé, même parade qu'AgentSelectScreen.gd contre le "conflit de
## jaune" avec Vanne, §9).
extends Control

signal closed

var _cards: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Comic.plate_color()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, Comic.SAFE_MARGIN)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Comic.SP_3)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Comic.SP_3)
	root.add_child(header)
	var title := Comic.title_label_v4("Agents", Comic.SIZE_50, Comic.paper_color())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := _build_action_button(Vector2(160.0, 54.0), Comic.SIZE_28)
	(back.label as Label).text = "Retour"
	(back.button as Button).pressed.connect(func(): closed.emit())
	header.add_child(back.button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", Comic.SP_4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var agents := AgentDatabase.all()
	for i in agents.size():
		list.add_child(_agent_card(agents[i], i))
	_refresh_selection()
	(back.button as Button).grab_focus()


## Plaque de bouton v4 (§4.3 : coins coupés, aucun trait) -- contenu manuel
## (Label centré dans un HBoxContainer plein-rect) car le texte change
## dynamiquement (Choisir/Sélectionné) : voir `_refresh_selection`.
func _build_action_button(min_size: Vector2, font_size: int) -> Dictionary:
	var b := Button.new()
	b.text = ""
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_stylebox_override("normal", Comic.plate_style(Comic.plate_hi_color()))
	b.add_theme_stylebox_override("hover", Comic.plate_style(Comic.plate_hi_color().lightened(0.08)))
	b.add_theme_stylebox_override("pressed", Comic.plate_style(Comic.plate_hi_color().darkened(0.08)))
	b.add_theme_stylebox_override("disabled", Comic.plate_style(Comic.SIGNAL))
	b.add_theme_stylebox_override("focus", Comic.focus_style())

	var row := HBoxContainer.new()
	Comic.anchor(row, Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Comic.button_label_v4("", font_size, Comic.paper_color())
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	b.add_child(row)
	return {"button": b, "label": lbl}


func _agent_card(agent: AgentConfig, index: int) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Comic.plate_style(Comic.plate_color()))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Comic.SP_2)
	panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", Comic.SP_3)
	box.add_child(head)

	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 0)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Comic.title_label_v4(agent.agent_name, Comic.SIZE_37, Comic.paper_color())
	name_box.add_child(name_lbl)
	name_box.add_child(Comic.meta_label_v4(agent.role, Comic.SIZE_21, Comic.paper_dim_color()))
	head.add_child(name_box)

	var choose := _build_action_button(Vector2(170.0, 50.0), Comic.SIZE_21)
	(choose.button as Button).pressed.connect(_choose.bind(index))
	head.add_child(choose.button)

	box.add_child(Comic.body_label_v4(agent.description, Comic.SIZE_28, Comic.paper_color()))

	# UX-21 -- une ligne de kit par passif/capacité (`KitCard.ability_row_v4`,
	# partagée avec AgentSelectScreen.gd) : passif d'abord, puis C/Q/E/X dans
	# l'ordre (voir AgentDatabase._agent).
	if agent.passive:
		box.add_child(KitCard.ability_row_v4(
			AgentDatabase.passive_icon(agent), "", agent.passive.display_name, "PASSIF",
			agent.passive.description))
	for ab in agent.abilities:
		# UX-13 : jamais `ab.slot` brut ("C"/"Q"/"E"/"X") -- le libellé de la
		# VRAIE touche (AZERTY/QWERTY).
		var key_label := KeyLabel.for_action(PlayerInput.action_for_slot(ab.slot))
		var tag := ("ULTIME · %d POINTS" % ab.ult_cost) if ab.is_ultimate else ""
		box.add_child(KitCard.ability_row_v4(
			AgentDatabase.ability_icon(agent, ab.slot), key_label, ab.display_name, tag,
			ab.description, ab.is_ultimate))

	_cards.append({
		"panel": panel, "button": choose.button, "label": choose.label,
		"name_lbl": name_lbl, "index": index, "color": agent.color,
	})
	return panel


func _choose(index: int) -> void:
	AgentDatabase.selected_index = index
	_refresh_selection()


func _refresh_selection() -> void:
	for c in _cards:
		var selected: bool = c.index == AgentDatabase.selected_index
		(c.button as Button).disabled = selected
		var lbl: Label = c.label
		lbl.text = "SÉLECTIONNÉ" if selected else "Choisir"
		# §9 « conflit de jaune » (Vanne #F2B51D) : l'agent choisi gagne
		# TOUJOURS `signal`, jamais sa propre couleur-clé (même parade que
		# AgentSelectScreen.gd) -- le bouton disabled (fond `signal`) veut du
		# texte encre pour rester lisible (§4.2 règle 4).
		lbl.add_theme_color_override("font_color", Comic.ink_color() if selected else Comic.paper_color())
		c.name_lbl.add_theme_color_override("font_color", Comic.SIGNAL if selected else Comic.paper_color())
