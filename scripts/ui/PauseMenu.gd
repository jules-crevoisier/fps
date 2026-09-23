## PauseMenu.gd
## Menu pause : ouvert par l'action "pause" (Échap clavier / bouton Start manette).
## Navigable au clavier ET à la manette (focus + actions ui_*). Ne met pas l'arbre
## en pause (sûr en multijoueur) ; libère la souris et gèle les entrées du joueur.
## Restylé v2 (design.md §11) : bandeau pinceau + case charcoal centrale.
extends CanvasLayer

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const OPTIONS_SCRIPT := preload("res://scripts/ui/OptionsMenu.gd")

var _bg: ColorRect
var _header: BrushHeader
var _panel: ComicPanel
var _options: Control
var _first_button: Button
var _open: bool = false

func _ready() -> void:
	layer = 10
	_build()
	_bg.visible = false
	_header.visible = false
	_panel.visible = false

func _build() -> void:
	_bg = ColorRect.new()
	_bg.color = Color(Comic.BG.r, Comic.BG.g, Comic.BG.b, 0.65)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	wrap.custom_minimum_size = Vector2(360, 0)
	center.add_child(wrap)

	_header = BrushHeader.new()
	_header.title = "Pause"
	wrap.add_child(_header)

	_panel = ComicPanel.new()
	_panel.bg_color = Comic.PANEL
	_panel.border_width = Comic.RULE_W
	_panel.content_margin = Comic.SP_5
	wrap.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Comic.SP_3)
	_panel.body.add_child(box)

	_first_button = _add_button(box, "Reprendre", _close)
	_add_button(box, "Options", _open_options)
	_add_button(box, "Quitter au menu", _quit_to_menu)

func _add_button(box: VBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
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
		if _options and is_instance_valid(_options):
			_close_options()
		else:
			_close()
		get_viewport().set_input_as_handled()

func _pause() -> void:
	_open = true
	_bg.visible = true
	_header.visible = true
	_header.replay()
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _first_button:
		_first_button.grab_focus()

func _close() -> void:
	_open = false
	_bg.visible = false
	_header.visible = false
	_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _open_options() -> void:
	_header.visible = false
	_panel.visible = false
	_options = OPTIONS_SCRIPT.new()
	_options.closed.connect(_close_options)
	add_child(_options)

func _close_options() -> void:
	if _options and is_instance_valid(_options):
		_options.queue_free()
	_options = null
	_header.visible = true
	_panel.visible = true
	if _first_button:
		_first_button.grab_focus()

func _quit_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU)
