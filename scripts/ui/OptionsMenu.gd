## OptionsMenu.gd
## Menu d'options v2 (design.md §11) à quatre pages : "Clavier / Souris",
## "Manette", "Affichage & Son" et "Accessibilité".
## - Navigable au clavier ET à la manette (focus + ui_*).
## - Page clavier : sensibilité souris, FOV, switch AZERTY/QWERTY, remap touches.
## - Page manette : sensibilité, inversion Y, remap des boutons.
## - Page affichage & son : contours d'arête (ink edges), volumes maître/
##   effets/musique.
## - Page accessibilité : couleur ennemi (Magenta/Citron, design.md §9 —
##   recommandation daltonisme), échelle d'interface (Steam Deck), mouvement
##   réduit. Voir Settings.gd / Cartoon.gd (R-A).
## Émet `closed` quand on revient en arrière.
extends Control

signal closed

var _kb_page: VBoxContainer
var _pad_page: VBoxContainer
var _render_page: VBoxContainer
var _access_page: VBoxContainer
var _kb_buttons: Dictionary = {}
var _pad_buttons: Dictionary = {}
var _tab_kb: Button
var _tab_pad: Button
var _tab_render: Button
var _tab_access: Button
var _layout_label: Label
var _enemy_color_label: Label
var _enemy_color_buttons: Array = []
var _ui_scale_label: Label
var _reduced_motion_check: CheckButton

var _listening_action: String = ""
var _listening_kind: String = ""  # "kb" ou "pad"
var _scroll: ScrollContainer
var _hold_time: float = 0.0       # durée de maintien d'une direction
var _repeat_cd: float = 0.0       # cooldown de répétition de navigation

## Ordre 0 Magenta / 1 Citron (design.md v2 §9 : Settings.enemy_color).
const _ENEMY_COLOR_NAMES := ["Magenta", "Citron"]
const _ENEMY_COLOR_SWATCH := [Comic.ENEMY_MAGENTA, Comic.ENEMY_CITRON]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_show_page("kb")

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
	header.title = "Options"
	root.add_child(header)

	# En-tête : onglets + retour.
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", Comic.SP_2)
	header_row.add_theme_constant_override("margin_top", Comic.SP_2)
	_tab_kb = _tab("Clavier / Souris", func(): _show_page("kb"))
	_tab_pad = _tab("Manette", func(): _show_page("pad"))
	_tab_render = _tab("Affichage & Son", func(): _show_page("render"))
	_tab_access = _tab("Accessibilité", func(): _show_page("access"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back := Button.new()
	back.text = "Retour"
	back.custom_minimum_size = Vector2(120, 38)
	back.pressed.connect(func(): closed.emit())
	header_row.add_child(_tab_kb)
	header_row.add_child(_tab_pad)
	header_row.add_child(_tab_render)
	header_row.add_child(_tab_access)
	header_row.add_child(spacer)
	header_row.add_child(back)
	root.add_child(header_row)

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
	_render_page = _build_render()
	_access_page = _build_access()
	pages.add_child(_kb_page)
	pages.add_child(_pad_page)
	pages.add_child(_render_page)
	pages.add_child(_access_page)

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
	_render_page.visible = page == "render"
	_access_page.visible = page == "access"
	_tab_kb.button_pressed = page == "kb"
	_tab_pad.button_pressed = page == "pad"
	_tab_render.button_pressed = page == "render"
	_tab_access.button_pressed = page == "access"
	var target := _tab_kb
	match page:
		"pad": target = _tab_pad
		"render": target = _tab_render
		"access": target = _tab_access
	target.grab_focus()

# ----------------------------------------------------- PAGE CLAVIER / SOURIS
func _build_kb() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Comic.SP_2)

	v.add_child(Comic.bullet_row("Sensibilité souris"))
	var sens := HSlider.new()
	sens.min_value = 0.0005; sens.max_value = 0.01; sens.step = 0.0001
	sens.value = Settings.mouse_sensitivity
	var sens_lbl := Comic.number_label("%.4f" % Settings.mouse_sensitivity, Comic.SIZE_FLOOR, Comic.TEXT)
	sens.value_changed.connect(func(x):
		Settings.mouse_sensitivity = x; sens_lbl.text = "%.4f" % x; Settings.save_all())
	v.add_child(_row(sens, sens_lbl))

	v.add_child(Comic.bullet_row("Champ de vision (FOV)"))
	var fov := HSlider.new()
	fov.min_value = 70; fov.max_value = 120; fov.step = 1
	fov.value = Settings.fov
	var fov_lbl := Comic.number_label("%d" % int(Settings.fov), Comic.SIZE_FLOOR, Comic.TEXT)
	fov.value_changed.connect(func(x):
		Settings.fov = x; fov_lbl.text = "%d" % int(x); Settings.save_all())
	v.add_child(_row(fov, fov_lbl))

	v.add_child(Comic.bullet_row("Disposition clavier"))
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", Comic.SP_3)
	var az := _btn("AZERTY", func(): _set_layout("azerty"))
	var qw := _btn("QWERTY", func(): _set_layout("qwerty"))
	_layout_label = Comic.label("Actuel : %s" % Settings.layout.to_upper(), Comic.SIZE_BODY, Comic.TEXT_DIM, Comic.FONT_LABEL)
	lrow.add_child(az); lrow.add_child(qw); lrow.add_child(_layout_label)
	v.add_child(lrow)

	v.add_child(Comic.bullet_row("Touches — clique puis appuie sur la nouvelle touche"))
	for action in Settings.ACTIONS:
		var btn := _btn(Settings.binding_text(action), _rebind.bind(action, "kb"))
		_kb_buttons[action] = btn
		v.add_child(_row(Comic.label(Settings.ACTIONS[action], Comic.SIZE_BODY, Comic.TEXT, Comic.FONT_BODY), btn))
	return v

# ----------------------------------------------------------- PAGE MANETTE
func _build_pad() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Comic.SP_2)

	v.add_child(Comic.bullet_row("Sensibilité manette (stick droit)"))
	var sens := HSlider.new()
	sens.min_value = 0.5; sens.max_value = 8.0; sens.step = 0.1
	sens.value = Settings.gamepad_sensitivity
	var sens_lbl := Comic.number_label("%.1f" % Settings.gamepad_sensitivity, Comic.SIZE_FLOOR, Comic.TEXT)
	sens.value_changed.connect(func(x):
		Settings.gamepad_sensitivity = x; sens_lbl.text = "%.1f" % x; Settings.save_all())
	v.add_child(_row(sens, sens_lbl))

	v.add_child(Comic.bullet_row("Visée"))
	var inv := CheckButton.new()
	inv.text = "Inverser l'axe vertical (Y)"
	inv.button_pressed = Settings.invert_y
	inv.toggled.connect(func(on):
		Settings.invert_y = on; Settings.save_all())
	v.add_child(inv)

	v.add_child(Comic.bullet_row("Boutons — clique puis appuie sur un bouton manette"))
	for action in Settings.ACTIONS:
		var btn := _btn(Settings.gamepad_text(action), _rebind.bind(action, "pad"))
		_pad_buttons[action] = btn
		v.add_child(_row(Comic.label(Settings.ACTIONS[action], Comic.SIZE_BODY, Comic.TEXT, Comic.FONT_BODY), btn))

	var note := Comic.label("Sticks (déplacement/visée) et gâchettes (tir/visée) sont fixes.", Comic.SIZE_FLOOR, Comic.DISABLED, Comic.FONT_BODY)
	v.add_child(note)
	return v

# ------------------------------------------------------------ PAGE AFFICHAGE & SON
func _build_render() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Comic.SP_2)

	v.add_child(Comic.bullet_row("Affichage"))
	var edges := CheckButton.new()
	edges.text = "Contours d'arête (ink edges)"
	edges.button_pressed = Settings.ink_edges
	edges.toggled.connect(func(on):
		Settings.ink_edges = on; Settings.save_all())
	v.add_child(edges)

	v.add_child(Comic.bullet_row("Volume général"))
	v.add_child(_volume_row(func(): return Settings.volume_master, func(x):
		Settings.volume_master = x; Settings.save_all()))

	v.add_child(Comic.bullet_row("Volume effets (SFX)"))
	v.add_child(_volume_row(func(): return Settings.volume_sfx, func(x):
		Settings.volume_sfx = x; Settings.save_all()))

	v.add_child(Comic.bullet_row("Volume musique"))
	v.add_child(_volume_row(func(): return Settings.volume_music, func(x):
		Settings.volume_music = x; Settings.save_all()))

	return v

# ------------------------------------------------------------ PAGE ACCESSIBILITÉ
func _build_access() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Comic.SP_2)

	v.add_child(Comic.bullet_row("Couleur ennemi"))
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", Comic.SP_3)
	_enemy_color_buttons.clear()
	for i in _ENEMY_COLOR_NAMES.size():
		var b := _btn(_ENEMY_COLOR_NAMES[i], _set_enemy_color.bind(i))
		var swatch := ColorRect.new()
		swatch.color = _ENEMY_COLOR_SWATCH[i]
		swatch.custom_minimum_size = Vector2(18, 18)
		var bh := HBoxContainer.new()
		bh.add_theme_constant_override("separation", Comic.SP_1)
		bh.add_child(swatch)
		bh.add_child(b)
		_enemy_color_buttons.append(b)
		crow.add_child(bh)
	v.add_child(crow)
	_enemy_color_label = Comic.label("", Comic.SIZE_FLOOR, Comic.TEXT_DIM, Comic.FONT_BODY)
	_enemy_color_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_enemy_color_label)
	# design.md v2 §9 : recommandation daltonisme.
	v.add_child(Comic.label("Citron est recommandé pour les joueurs protanopes/deutéranopes.", Comic.SIZE_FLOOR, Comic.DISABLED, Comic.FONT_BODY))
	_refresh_enemy_color_ui()

	v.add_child(HSeparator.new())
	v.add_child(Comic.bullet_row("Échelle d'interface"))
	var scale_slider := HSlider.new()
	scale_slider.min_value = 0.8; scale_slider.max_value = 1.5; scale_slider.step = 0.05
	scale_slider.value = Settings.ui_scale
	_ui_scale_label = Comic.number_label("%.2f×" % Settings.ui_scale, Comic.SIZE_FLOOR, Comic.TEXT)
	scale_slider.value_changed.connect(func(x):
		Settings.ui_scale = Settings.clamp_ui_scale(x)
		_ui_scale_label.text = "%.2f×" % Settings.ui_scale
		Settings.save_all())
	v.add_child(_row(scale_slider, _ui_scale_label))
	v.add_child(Comic.label("1.15× recommandé sur Steam Deck.", Comic.SIZE_FLOOR, Comic.DISABLED, Comic.FONT_BODY))

	v.add_child(HSeparator.new())
	v.add_child(Comic.bullet_row("Mouvement"))
	_reduced_motion_check = CheckButton.new()
	_reduced_motion_check.text = "Mouvement réduit (fondus uniquement, plus de balayage/pop)"
	_reduced_motion_check.button_pressed = Settings.reduced_motion
	_reduced_motion_check.toggled.connect(func(on):
		Settings.reduced_motion = on; Settings.save_all())
	v.add_child(_reduced_motion_check)

	return v

func _volume_row(getter: Callable, setter: Callable) -> HBoxContainer:
	var sl := HSlider.new()
	sl.min_value = 0.0; sl.max_value = 1.0; sl.step = 0.01
	sl.value = getter.call()
	var lbl := Comic.number_label("%d %%" % int(round(float(sl.value) * 100.0)), Comic.SIZE_FLOOR, Comic.TEXT)
	sl.value_changed.connect(func(x):
		setter.call(x)
		lbl.text = "%d %%" % int(round(x * 100.0)))
	return _row(sl, lbl)

func _set_enemy_color(i: int) -> void:
	Settings.enemy_color = Settings.clamp_enemy_color(i)
	Settings.save_all()
	_refresh_enemy_color_ui()

func _refresh_enemy_color_ui() -> void:
	if _enemy_color_label:
		_enemy_color_label.text = "Actuel : %s" % _ENEMY_COLOR_NAMES[Settings.enemy_color]
	for i in _enemy_color_buttons.size():
		_enemy_color_buttons[i].disabled = i == Settings.enemy_color

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
func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 34)
	b.pressed.connect(cb)
	return b

func _row(a: Control, b: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", Comic.SP_3)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if a is Label:
		a.custom_minimum_size = Vector2(260, 0)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	h.add_child(b)
	return h
