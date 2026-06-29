## OptionsMenu.gd
## Menu d'options à deux pages : "Clavier / Souris" et "Manette".
## - Navigable au clavier ET à la manette (focus + ui_*).
## - Page clavier : sensibilité souris, FOV, switch AZERTY/QWERTY, remap touches.
## - Page manette : sensibilité, inversion Y, remap des boutons.
## Émet `closed` quand on revient en arrière.
extends Control

signal closed

var _kb_page: VBoxContainer
var _pad_page: VBoxContainer
var _kb_buttons: Dictionary = {}
var _pad_buttons: Dictionary = {}
var _tab_kb: Button
var _tab_pad: Button
var _layout_label: Label

var _listening_action: String = ""
var _listening_kind: String = ""  # "kb" ou "pad"
var _scroll: ScrollContainer
var _hold_time: float = 0.0       # durée de maintien d'une direction
var _repeat_cd: float = 0.0       # cooldown de répétition de navigation

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_show_page("kb")

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

	# En-tête : onglets + retour.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_tab_kb = _tab("Clavier / Souris", func(): _show_page("kb"))
	_tab_pad = _tab("Manette", func(): _show_page("pad"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back := Button.new()
	back.text = "Retour"
	back.custom_minimum_size = Vector2(120, 38)
	back.pressed.connect(func(): closed.emit())
	header.add_child(_tab_kb)
	header.add_child(_tab_pad)
	header.add_child(spacer)
	header.add_child(back)
	root.add_child(header)

	# Zone de contenu défilable (le scroll suit l'élément focalisé).
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	root.add_child(_scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pages)

	_kb_page = _build_kb()
	_pad_page = _build_pad()
	pages.add_child(_kb_page)
	pages.add_child(_pad_page)

func _tab(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(180, 40)
	b.pressed.connect(cb)
	return b

func _show_page(page: String) -> void:
	_kb_page.visible = page == "kb"
	_pad_page.visible = page == "pad"
	_tab_kb.button_pressed = page == "kb"
	_tab_pad.button_pressed = page == "pad"
	(_tab_kb if page == "kb" else _tab_pad).grab_focus()

# ----------------------------------------------------- PAGE CLAVIER / SOURIS
func _build_kb() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)

	v.add_child(_section("Sensibilité souris"))
	var sens := HSlider.new()
	sens.min_value = 0.0005; sens.max_value = 0.01; sens.step = 0.0001
	sens.value = Settings.mouse_sensitivity
	var sens_lbl := _label("%.4f" % Settings.mouse_sensitivity, 20, Color.WHITE)
	sens.value_changed.connect(func(x):
		Settings.mouse_sensitivity = x; sens_lbl.text = "%.4f" % x; Settings.save_all())
	v.add_child(_row(sens, sens_lbl))

	v.add_child(_section("Champ de vision (FOV)"))
	var fov := HSlider.new()
	fov.min_value = 70; fov.max_value = 120; fov.step = 1
	fov.value = Settings.fov
	var fov_lbl := _label("%d" % int(Settings.fov), 20, Color.WHITE)
	fov.value_changed.connect(func(x):
		Settings.fov = x; fov_lbl.text = "%d" % int(x); Settings.save_all())
	v.add_child(_row(fov, fov_lbl))

	v.add_child(_section("Disposition clavier"))
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 14)
	var az := _btn("AZERTY", func(): _set_layout("azerty"))
	var qw := _btn("QWERTY", func(): _set_layout("qwerty"))
	_layout_label = _label("Actuel : %s" % Settings.layout.to_upper(), 18, Color(0.9, 0.92, 1.0))
	lrow.add_child(az); lrow.add_child(qw); lrow.add_child(_layout_label)
	v.add_child(lrow)

	v.add_child(_section("Touches — clique puis appuie sur la nouvelle touche"))
	for action in Settings.ACTIONS:
		var btn := _btn(Settings.binding_text(action), _rebind.bind(action, "kb"))
		_kb_buttons[action] = btn
		v.add_child(_row(_label(Settings.ACTIONS[action], 18, Color(0.9, 0.92, 1.0)), btn))
	return v

# ----------------------------------------------------------- PAGE MANETTE
func _build_pad() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)

	v.add_child(_section("Sensibilité manette (stick droit)"))
	var sens := HSlider.new()
	sens.min_value = 0.5; sens.max_value = 8.0; sens.step = 0.1
	sens.value = Settings.gamepad_sensitivity
	var sens_lbl := _label("%.1f" % Settings.gamepad_sensitivity, 20, Color.WHITE)
	sens.value_changed.connect(func(x):
		Settings.gamepad_sensitivity = x; sens_lbl.text = "%.1f" % x; Settings.save_all())
	v.add_child(_row(sens, sens_lbl))

	v.add_child(_section("Visée"))
	var inv := CheckButton.new()
	inv.text = "Inverser l'axe vertical (Y)"
	inv.button_pressed = Settings.invert_y
	inv.toggled.connect(func(on):
		Settings.invert_y = on; Settings.save_all())
	v.add_child(inv)

	v.add_child(_section("Boutons — clique puis appuie sur un bouton manette"))
	for action in Settings.ACTIONS:
		var btn := _btn(Settings.gamepad_text(action), _rebind.bind(action, "pad"))
		_pad_buttons[action] = btn
		v.add_child(_row(_label(Settings.ACTIONS[action], 18, Color(0.9, 0.92, 1.0)), btn))

	var note := _label("Sticks (déplacement/visée) et gâchettes (tir/visée) sont fixes.", 14, Color(0.7, 0.7, 0.75))
	v.add_child(note)
	return v

# ----------------------------------------------------------- REBIND
func _rebind(action: String, kind: String) -> void:
	_listening_action = action
	_listening_kind = kind
	var dict: Dictionary = _kb_buttons if kind == "kb" else _pad_buttons
	dict[action].text = "Appuyez…"

## Maintenir haut/bas (stick ou D-pad) fait défiler en continu : le 1er pas est
## géré par le système, puis on répète après un court délai (le scroll suit grâce
## à follow_focus).
func _process(delta: float) -> void:
	if _listening_action != "":
		return
	var dir := 0
	if Input.is_action_pressed("ui_down"):
		dir = 1
	elif Input.is_action_pressed("ui_up"):
		dir = -1
	if dir == 0:
		_hold_time = 0.0
		_repeat_cd = 0.0
		return
	_hold_time += delta
	if _hold_time < 0.4:
		return  # laisse le premier déplacement au système
	_repeat_cd -= delta
	if _repeat_cd <= 0.0:
		_move_focus(dir)
		_repeat_cd = 0.12

func _move_focus(dir: int) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null:
		return
	var nxt := focused.find_next_valid_focus() if dir > 0 else focused.find_prev_valid_focus()
	if nxt:
		nxt.grab_focus()

func _input(event: InputEvent) -> void:
	if _listening_action == "":
		return
	var ok := false
	if _listening_kind == "kb":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
				_end_listen()
				accept_event()
				return
			Settings.set_binding(_listening_action, event); ok = true
		elif event is InputEventMouseButton and event.pressed:
			Settings.set_binding(_listening_action, event); ok = true
	else:  # manette
		if event is InputEventJoypadButton and event.pressed:
			Settings.set_binding(_listening_action, event); ok = true
	if ok:
		_end_listen()
		accept_event()

func _end_listen() -> void:
	var a := _listening_action
	var kind := _listening_kind
	_listening_action = ""
	_listening_kind = ""
	if a == "":
		return
	if kind == "kb" and _kb_buttons.has(a):
		_kb_buttons[a].text = Settings.binding_text(a)
	elif kind == "pad" and _pad_buttons.has(a):
		_pad_buttons[a].text = Settings.gamepad_text(a)

func _set_layout(name: String) -> void:
	Settings.apply_layout(name)
	_layout_label.text = "Actuel : %s" % name.to_upper()
	for action in _kb_buttons:
		_kb_buttons[action].text = Settings.binding_text(action)

# ----------------------------------------------------------- UI HELPERS
func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _section(text: String) -> Label:
	return _label(text, 22, Color(0.55, 0.8, 1.0))

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 34)
	b.pressed.connect(cb)
	return b

func _row(a: Control, b: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if a is Label:
		a.custom_minimum_size = Vector2(260, 0)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	h.add_child(b)
	return h
