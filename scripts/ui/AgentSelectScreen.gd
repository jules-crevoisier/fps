## AgentSelectScreen.gd
## Écran de sélection d'agent au lancement du match (façon Valorant) : grille
## d'agents, aperçu des capacités, bouton VERROUILLER + compte à rebours.
## Émet `locked` quand le joueur valide (ou à la fin du timer) -> le spawn suit.
## Design.md v2 §9/§11 : bandeau pinceau, plaques charcoal (monogramme sur
## plaque `panel_hi` + glyphe de rôle à forme distincte), l'agent sélectionné
## gagne SEUL sa couleur + un soulignement pinceau.
extends CanvasLayer

signal locked

@export var countdown: float = 15.0

var _time_left: float = 0.0
var _timer_label: Label
var _desc_label: Label
var _cards: Array = []

func _ready() -> void:
	layer = 20
	_time_left = countdown
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	_refresh()

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
	root.add_theme_constant_override("separation", Comic.SP_3)
	margin.add_child(root)

	var header_wrap := Control.new()
	header_wrap.custom_minimum_size = Vector2(0, 64)
	root.add_child(header_wrap)
	var header := BrushHeader.new()
	header.title = "Sélection d'agent"
	header.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header_wrap.add_child(header)
	_timer_label = Comic.number_label("", Comic.SIZE_DISPLAY_MD, Comic.TEXT_ON_BRUSH)
	Comic.anchor(_timer_label, Control.PRESET_CENTER_RIGHT)
	_timer_label.offset_left = -140
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_wrap.add_child(_timer_label)

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", Comic.SP_3)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(grid)

	var agents := AgentDatabase.all()
	for i in agents.size():
		grid.add_child(_agent_card(agents[i], i))

	_desc_label = Comic.label("", Comic.SIZE_BODY, Comic.TEXT, Comic.FONT_BODY)
	root.add_child(_desc_label)

	var lock := Button.new()
	lock.text = "VERROUILLER"
	lock.custom_minimum_size = Vector2(0, 58)
	lock.add_theme_font_size_override("font_size", Comic.SIZE_SUBTITLE)
	lock.pressed.connect(_lock_in)
	root.add_child(lock)
	lock.grab_focus()

## Glyphe de rôle À FORME DISTINCTE (jamais la couleur seule, design.md §9) :
## losange = Entrée, carré = Contrôle, cercle = Soutien.
static func _role_glyph(role: String) -> String:
	match role:
		AgentDatabase.ROLE_ENTREE: return "◆"
		AgentDatabase.ROLE_CONTROLE: return "■"
		AgentDatabase.ROLE_SOUTIEN: return "●"
	return "?"

func _agent_card(agent: AgentConfig, index: int) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.text = ""  # le contenu visuel est construit en enfants ci-dessous.
	b.custom_minimum_size = Vector2(260, 0)
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_select.bind(index))

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", Comic.SP_2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)

	# Plaque monogramme : fond panel_hi + initiale en italique Barlow.
	var plate := ComicPanel.new()
	plate.bg_color = Comic.PANEL_HI
	plate.border_width = Comic.RULE_W
	plate.custom_minimum_size = Vector2(0, 132)
	v.add_child(plate)
	var mono := Comic.title_label(agent.agent_name.substr(0, 1), Comic.SIZE_DISPLAY_XL, Comic.TEXT_DIM)
	mono.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mono.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mono.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.body.add_child(mono)

	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", Comic.SP_1)
	v.add_child(name_row)
	var glyph := Comic.label(_role_glyph(agent.role), Comic.SIZE_LABEL, Comic.TEXT_DIM, Comic.FONT_NUMBER)
	name_row.add_child(glyph)
	var name_lbl := Comic.title_label(agent.agent_name, Comic.SIZE_SUBTITLE, Comic.TEXT_DIM)
	name_row.add_child(name_lbl)

	var role_lbl := Comic.label(agent.role, Comic.SIZE_BODY, Comic.TEXT_DIM, Comic.FONT_LABEL)
	role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(role_lbl)

	var abil := ""
	for ab in agent.abilities:
		abil += "%s : %s\n" % [ab.slot, ab.display_name]
	var abil_lbl := Comic.label(abil.strip_edges(), Comic.SIZE_BODY, Comic.TEXT_DIM, Comic.FONT_BODY)
	abil_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(abil_lbl)

	_cards.append({"button": b, "color": agent.color, "mono": mono, "plate": plate, "glyph": glyph, "name_lbl": name_lbl})
	return b

func _select(index: int) -> void:
	AgentDatabase.selected_index = index
	_refresh()

func _refresh() -> void:
	var agents := AgentDatabase.all()
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		var selected: bool = i == AgentDatabase.selected_index
		c.button.button_pressed = selected
		# La couleur de l'agent n'apparaît QUE sur la carte sélectionnée
		# (design.md §9) : le reste garde une teinte neutre (text_dim).
		var col: Color = c.color if selected else Comic.TEXT_DIM
		c.mono.add_theme_color_override("font_color", col)
		c.glyph.add_theme_color_override("font_color", col)
		c.name_lbl.add_theme_color_override("font_color", col)
		c.plate.selected = selected
		c.plate.border_color = c.color if selected else Comic.RULE
		c.plate.bg_color = Comic.PANEL_HI.lerp(c.color, 0.3) if selected else Comic.PANEL_HI
	if _desc_label:
		var a: AgentConfig = agents[AgentDatabase.selected_index]
		var text := "%s — %s\n%s" % [a.role, a.agent_name, a.description]
		for ab in a.abilities:
			text += "\n%s (%s) : %s" % [ab.display_name, ab.slot, ab.description]
		_desc_label.text = text

func _process(delta: float) -> void:
	_time_left -= delta
	if _timer_label:
		_timer_label.text = HudFormat.format_timer(_time_left)
	if _time_left <= 0.0:
		_lock_in()

func _lock_in() -> void:
	set_process(false)
	locked.emit()
