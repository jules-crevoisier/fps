## MainMenu.gd
## Menu principal construit par code : Héberger / Rejoindre (IP) / Quitter.
## - Héberger : démarre un serveur et charge la map.
## - Rejoindre : se connecte à l'IP puis charge la map à la connexion.
extends Control

const MODES := [
	{"name": "Team Deathmatch", "scene": "res://scenes/levels/tdm_map.tscn"},
	{"name": "Hardpoint", "scene": "res://scenes/levels/comp_map.tscn"},
]
var _mode_index: int = 0
var _mode_btn: Button
const OPTIONS_SCRIPT := preload("res://scripts/ui/OptionsMenu.gd")
const ARSENAL_SCRIPT := preload("res://scripts/ui/ArsenalMenu.gd")
const AGENT_SCRIPT := preload("res://scripts/ui/AgentMenu.gd")

var _ip_field: LineEdit
var _status: Label
var _net: NetworkManager
var _options: Control
var _menu_box: Control
var _first_button: Button

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Settings.load_all()
	_net = NetworkManager.get_net(get_tree())
	# Focus initial pour la navigation clavier/manette (différé : après le build).
	call_deferred("_focus_first")
	# Si on revient au menu après une partie, on coupe l'ancienne connexion.
	_net.disconnect_from_game()
	_net.connection_succeeded.connect(_on_connected)
	_net.connection_failed.connect(_on_failed)
	_build()

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_menu_box = center

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(360, 0)
	center.add_child(box)

	var title := Label.new()
	title.text = "FPS CARTOON"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_mode_btn = Button.new()
	_mode_btn.custom_minimum_size = Vector2(0, 38)
	_mode_btn.pressed.connect(_cycle_mode)
	box.add_child(_mode_btn)
	_update_mode_btn()

	var host_btn := Button.new()
	host_btn.text = "Héberger"
	host_btn.custom_minimum_size = Vector2(0, 48)
	host_btn.pressed.connect(_on_host)
	box.add_child(host_btn)
	_first_button = host_btn

	_ip_field = LineEdit.new()
	_ip_field.text = "127.0.0.1"
	_ip_field.placeholder_text = "IP du serveur"
	box.add_child(_ip_field)

	var join_btn := Button.new()
	join_btn.text = "Rejoindre"
	join_btn.custom_minimum_size = Vector2(0, 48)
	join_btn.pressed.connect(_on_join)
	box.add_child(join_btn)

	var train_btn := Button.new()
	train_btn.text = "Terrain d'entraînement (solo)"
	train_btn.pressed.connect(_on_training)
	box.add_child(train_btn)

	var agent_btn := Button.new()
	agent_btn.text = "Agents"
	agent_btn.pressed.connect(_open_agents)
	box.add_child(agent_btn)

	var arsenal_btn := Button.new()
	arsenal_btn.text = "Arsenal"
	arsenal_btn.pressed.connect(_open_arsenal)
	box.add_child(arsenal_btn)

	var options_btn := Button.new()
	options_btn.text = "Options"
	options_btn.pressed.connect(_open_options)
	box.add_child(options_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quitter"
	quit_btn.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_btn)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

func _on_host() -> void:
	if _net.host() == OK:
		_start_game()
	else:
		_status.text = "Échec de l'hébergement."

func _on_join() -> void:
	_status.text = "Connexion à %s…" % _ip_field.text
	_net.join(_ip_field.text)

func _on_connected() -> void:
	_start_game()

func _on_failed() -> void:
	_status.text = "Connexion échouée."

func _open_options() -> void:
	_menu_box.visible = false
	_options = OPTIONS_SCRIPT.new()
	_options.closed.connect(_close_options)
	add_child(_options)

func _open_arsenal() -> void:
	_menu_box.visible = false
	_options = ARSENAL_SCRIPT.new()
	_options.closed.connect(_close_options)
	add_child(_options)

func _open_agents() -> void:
	_menu_box.visible = false
	_options = AGENT_SCRIPT.new()
	_options.closed.connect(_close_options)
	add_child(_options)

func _close_options() -> void:
	if _options and is_instance_valid(_options):
		_options.queue_free()
	_options = null
	_menu_box.visible = true
	_focus_first()

func _focus_first() -> void:
	if _first_button and is_instance_valid(_first_button):
		_first_button.grab_focus()

func _on_training() -> void:
	# Solo : l'arène de mouvement héberge automatiquement une partie locale.
	get_tree().change_scene_to_file("res://scenes/levels/test_arena.tscn")

func _cycle_mode() -> void:
	_mode_index = (_mode_index + 1) % MODES.size()
	_update_mode_btn()

func _update_mode_btn() -> void:
	if _mode_btn:
		_mode_btn.text = "Mode : %s  ▸" % MODES[_mode_index].name

func _start_game() -> void:
	get_tree().change_scene_to_file(MODES[_mode_index].scene)
