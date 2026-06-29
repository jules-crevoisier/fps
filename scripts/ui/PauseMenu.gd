## PauseMenu.gd
## Menu pause : ouvert par l'action "pause" (Échap clavier / bouton Start manette).
## Navigable au clavier ET à la manette (focus + actions ui_*). Ne met pas l'arbre
## en pause (sûr en multijoueur) ; libère la souris et gèle les entrées du joueur.
extends CanvasLayer

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const OPTIONS_SCRIPT := preload("res://scripts/ui/OptionsMenu.gd")

var _panel: Control
var _options: Control
var _first_button: Button
var _open: bool = false

func _ready() -> void:
	layer = 10
	_build()
	_panel.visible = false

func _build() -> void:
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09, 0.7)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(320, 0)
	center.add_child(box)

	var title := Label.new()
	title.text = "PAUSE"
	title.add_theme_font_size_override("font_size", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_first_button = _add_button(box, "Reprendre", _close)
	_add_button(box, "Options", _open_options)
	_add_button(box, "Quitter au menu", _quit_to_menu)

func _add_button(box: VBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.pressed.connect(cb)
	box.add_child(b)
	return b

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _options and is_instance_valid(_options):
			_close_options()
		elif _open:
			_close()
		else:
			_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and (_open or _options):
		# B / Échap = retour quand un menu est ouvert.
		if _options and is_instance_valid(_options):
			_close_options()
		else:
			_close()
		get_viewport().set_input_as_handled()

func _pause() -> void:
	_open = true
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _first_button:
		_first_button.grab_focus()  # pour la navigation manette/clavier

func _close() -> void:
	_open = false
	_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _open_options() -> void:
	_panel.visible = false
	_options = OPTIONS_SCRIPT.new()
	_options.closed.connect(_close_options)
	add_child(_options)

func _close_options() -> void:
	if _options and is_instance_valid(_options):
		_options.queue_free()
	_options = null
	_panel.visible = true
	if _first_button:
		_first_button.grab_focus()

func _quit_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU)
