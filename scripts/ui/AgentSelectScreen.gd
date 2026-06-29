## AgentSelectScreen.gd
## Écran de sélection d'agent au lancement du match (façon Valorant) : grille
## d'agents, aperçu des capacités, bouton VERROUILLER + compte à rebours.
## Émet `locked` quand le joueur valide (ou à la fin du timer) -> le spawn suit.
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
	bg.color = Color(0.04, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 40)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	# En-tête : titre + compte à rebours.
	var header := HBoxContainer.new()
	var title := _lbl("SÉLECTION D'AGENT", 40, Color(1, 1, 1))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timer_label = _lbl("", 32, Color(1.0, 0.85, 0.3))
	header.add_child(title)
	header.add_child(_timer_label)
	root.add_child(header)

	# Grille d'agents.
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 14)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(grid)

	var agents := AgentDatabase.all()
	for i in agents.size():
		grid.add_child(_agent_card(agents[i], i))

	# Description de l'agent sélectionné.
	_desc_label = _lbl("", 18, Color(0.8, 0.85, 0.95))
	root.add_child(_desc_label)

	# Bouton verrouiller.
	var lock := Button.new()
	lock.text = "VERROUILLER"
	lock.custom_minimum_size = Vector2(0, 54)
	lock.pressed.connect(_lock_in)
	root.add_child(lock)
	lock.grab_focus()

func _agent_card(agent: AgentConfig, index: int) -> Button:
	# La carte entière est un bouton (sélectionne l'agent).
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(220, 0)
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var abil := ""
	for ab in agent.abilities:
		abil += "%s:%s\n" % [ab.slot, ab.display_name]
	b.text = "%s\n\n%s" % [agent.agent_name, abil]
	b.add_theme_color_override("font_color", agent.color)
	b.pressed.connect(_select.bind(index))
	_cards.append(b)
	return b

func _select(index: int) -> void:
	AgentDatabase.selected_index = index
	_refresh()

func _refresh() -> void:
	var agents := AgentDatabase.all()
	for i in _cards.size():
		_cards[i].button_pressed = i == AgentDatabase.selected_index
	if _desc_label:
		_desc_label.text = agents[AgentDatabase.selected_index].description

func _process(delta: float) -> void:
	_time_left -= delta
	if _timer_label:
		_timer_label.text = "%d" % maxi(0, int(ceil(_time_left)))
	if _time_left <= 0.0:
		_lock_in()

func _lock_in() -> void:
	set_process(false)
	locked.emit()

func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
