## SettingsPanel.gd
## Panneau PARAMÈTRES réutilisable (reports/ui/mockups/settings.html) — utilisé
## par MainMenu (onglet PARAMÈTRES) ET par PauseMenu.gd (voir sa doc de tête) ;
## ne dessine PAS son propre fond plein écran (l'appelant en fournit un si
## besoin, voir MainMenu._build_settings_tab / PauseMenu voile). Ne lie QUE des
## réglages qui existent réellement dans Settings.gd/Audio.gd — voir
## `_UNAVAILABLE` pour ce qui a été sciemment laissé de côté (rapporté au lead).
class_name SettingsPanel
extends Control

const _TABS := [
	{"id": "mouse", "label": "Souris & visée"},
	{"id": "keys", "label": "Touches"},
	{"id": "video", "label": "Vidéo"},
	{"id": "audio", "label": "Son"},
	{"id": "crosshair", "label": "Réticule"},
	{"id": "access", "label": "Accessibilité"},
]

## Réglages demandés par la maquette mais SANS équivalent réel dans
## Settings.gd (voir sa doc « réinitialiser » : « les touches remappées
## individuellement restent HORS de ce périmètre ») : « Sprint en bascule » n'a
## pas de champ dédié (le maintien/bascule existe pour accroupi/ADS/marche,
## PAS pour le sprint) — jamais inventé ici, remplacé par un réglage réel
## (« Viser en maintien »).
const _UNAVAILABLE := ["Sprint en bascule (pas de champ Settings dédié — hold_to_crouch/aim/walk existent, pas hold_to_sprint)"]

const _PRESET_LABELS := {"default": "Défaut", "dot": "Point", "thin_cross": "Croix fine", "thick_cross": "Croix épaisse"}

var _current_tab: String = "mouse"
var _tab_buttons: Dictionary = {}
var _page_host: Control
var _crosshair_preview: Crosshair
var _enemy_swatches: Dictionary = {}
var _rebinding_action: String = ""
var _rebind_buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	_build_side_tabs()
	_page_host = Control.new()
	_page_host.position = Vector2(450, 170)
	_page_host.custom_minimum_size = Vector2(900, 790)
	add_child(_page_host)
	_build_page_frame()
	_build_crosshair_sidebar()
	_build_bottom_bar()
	_show_tab(_current_tab)


func unavailable_settings() -> Array:
	return _UNAVAILABLE


# ------------------------------------------------------------ colonne d'onglets

func _build_side_tabs() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(64, 170)
	col.custom_minimum_size = Vector2(330, 0)
	col.add_theme_constant_override("separation", UiTokens.S1 + 4)
	for tab in _TABS:
		var b := MenuWidgets.comic_button(tab["label"], UiTokens.PAPER, UiTokens.T_M)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(330, 60)
		b.pressed.connect(_show_tab.bind(tab["id"]))
		col.add_child(b)
		_tab_buttons[tab["id"]] = b
	add_child(col)


func _refresh_side_tabs() -> void:
	for id in _tab_buttons:
		var b: Button = _tab_buttons[id]
		var selected: bool = id == _current_tab
		MenuWidgets.apply_plate_states(b, UiTokens.YELLOW if selected else UiTokens.PAPER)
		b.position.x = 18.0 if selected else 0.0


# ------------------------------------------------------------ cadre de page

var _page_title: Label
var _page_body: VBoxContainer

## Recolore la barre de défilement native (rouge par défaut du thème éditeur —
## détonnait fort dans la direction BD, vu à la capture 2026-09-27 sur la page
## Touches, la seule assez longue pour en avoir besoin).
func _style_scrollbar(scroll: ScrollContainer) -> void:
	var vbar := scroll.get_v_scroll_bar()
	vbar.add_theme_stylebox_override("scroll", StyleBoxEmpty.new())
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = UiTokens.INK_SOFT
	grabber.set_corner_radius_all(6)
	grabber.content_margin_left = 4
	grabber.content_margin_right = 4
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		vbar.add_theme_stylebox_override(state, grabber)


func _build_page_frame() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.PAPER, 0.0, UiTokens.DROP, UiTokens.STROKE, Vector2(UiTokens.S4, UiTokens.S3)))
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_style_scrollbar(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", UiTokens.S2)
	_page_title = UiTokens.make_label("", UiTokens.display(UiTokens.T_XL, UiTokens.INK, 0))
	col.add_child(_page_title)
	_page_body = VBoxContainer.new()
	_page_body.add_theme_constant_override("separation", 4)
	col.add_child(_page_body)
	scroll.add_child(col)
	panel.add_child(scroll)
	_page_host.add_child(panel)


func _show_tab(id: String) -> void:
	_current_tab = id
	_refresh_side_tabs()
	for c in _page_body.get_children():
		c.queue_free()
	match id:
		"mouse": _page_title.text = "Souris & visée"; _build_mouse_page()
		"keys": _page_title.text = "Touches"; _build_keys_page()
		"video": _page_title.text = "Vidéo"; _build_video_page()
		"audio": _page_title.text = "Son"; _build_audio_page()
		"crosshair": _page_title.text = "Réticule"; _build_crosshair_page()
		"access": _page_title.text = "Accessibilité"; _build_access_page()


# ------------------------------------------------------------ lignes génériques

func _row_frame(name: String, desc: String = "") -> Dictionary:
	var grid := HBoxContainer.new()
	grid.custom_minimum_size = Vector2(0, 60)
	grid.add_theme_constant_override("separation", UiTokens.S3)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	left.add_theme_constant_override("separation", 2)
	left.add_child(UiTokens.make_label(name, UiTokens.label(27), true))
	if desc != "":
		var d := UiTokens.make_label(desc, UiTokens.body(19, UiTokens.INK_SOFT))
		d.custom_minimum_size = Vector2(330, 0)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD
		left.add_child(d)
	grid.add_child(left)
	var mid := Control.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.custom_minimum_size = Vector2(0, 40)
	grid.add_child(mid)
	var val := UiTokens.make_label("", UiTokens.display(30, UiTokens.INK, 0))
	val.custom_minimum_size = Vector2(110, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(val)
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", UiTokens.S1)
	wrap.add_child(grid)
	var sep := ColorRect.new()
	sep.color = Color(UiTokens.INK.r, UiTokens.INK.g, UiTokens.INK.b, 0.2)
	sep.custom_minimum_size = Vector2(0, 3)
	wrap.add_child(sep)
	return {"wrap": wrap, "mid": mid, "val": val}


func _add_slider_row(name: String, desc: String, min_v: float, max_v: float, step: float, value: float, fmt: Callable, apply: Callable) -> void:
	var f := _row_frame(name, desc)
	var slider := MenuWidgets.styled_slider(min_v, max_v, step, value)
	slider.custom_minimum_size.x = 300
	f["mid"].add_child(slider)
	var val_label: Label = f["val"]
	val_label.text = fmt.call(value)
	slider.value_changed.connect(func(v: float) -> void:
		val_label.text = fmt.call(v)
		apply.call(v))
	_page_body.add_child(f["wrap"])


func _add_switch_row(name: String, desc: String, value: bool, apply: Callable) -> void:
	var f := _row_frame(name, desc)
	var sw := MenuWidgets.switch_control(value)
	f["mid"].add_child(sw)
	sw.toggled.connect(func(p: bool) -> void:
		apply.call(p)
		_show_tab(_current_tab))
	_page_body.add_child(f["wrap"])


func _add_segmented_row(name: String, desc: String, options: Array, labels: Array, selected, apply: Callable) -> void:
	var f := _row_frame(name, desc)
	f["mid"].add_child(MenuWidgets.segmented(options, labels, selected, func(id) -> void:
		apply.call(id)
		_show_tab(_current_tab)))
	_page_body.add_child(f["wrap"])


# ------------------------------------------------------------ SOURIS & VISÉE

func _build_mouse_page() -> void:
	_add_slider_row("Sensibilité", "Vitesse de la caméra à la souris",
		SettingsFormat.SENSITIVITY_MIN, SettingsFormat.SENSITIVITY_MAX, 0.00005, Settings.mouse_sensitivity,
		func(v: float) -> String: return SettingsFormat.format_ratio(v, Settings.MOUSE_SENSITIVITY_DEFAULT),
		func(v: float) -> void: Settings.mouse_sensitivity = Settings.clamp_mouse_sensitivity(v))
	_add_slider_row("Sensibilité en visée", "Multiplicateur quand tu vises",
		SettingsFormat.ADS_MULT_MIN, SettingsFormat.ADS_MULT_MAX, 0.01, Settings.ads_sensitivity_multiplier,
		func(v: float) -> String: return SettingsFormat.format_multiplier(v),
		func(v: float) -> void: Settings.ads_sensitivity_multiplier = Settings.clamp_ads_sensitivity_multiplier(v))
	_add_slider_row("Champ de vision", "Horizontal, en degrés",
		SettingsFormat.FOV_MIN, SettingsFormat.FOV_MAX, 1.0, Settings.fov,
		func(v: float) -> String: return SettingsFormat.format_degrees(v),
		func(v: float) -> void: Settings.fov = Settings.clamp_fov(v))
	_add_switch_row("Inverser l'axe vertical", "", Settings.invert_y,
		func(p: bool) -> void: Settings.invert_y = p)
	_add_segmented_row("Disposition du clavier", "Change seulement les lettres affichées",
		Settings.LAYOUT_OPTIONS, ["Auto", "AZERTY", "QWERTY"], Settings.layout,
		func(id: String) -> void: Settings.apply_layout(id))
	_add_switch_row("Viser en maintien", "Relâcher la touche arrête la visée", Settings.hold_to_aim,
		func(p: bool) -> void: Settings.hold_to_aim = p)


# ------------------------------------------------------------ TOUCHES

func _build_keys_page() -> void:
	_rebind_buttons.clear()
	for action in Settings.ACTIONS:
		var f := _row_frame(Settings.ACTIONS[action], "")
		var b := MenuWidgets.key_chip(Settings.binding_text(action))
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		var click := Button.new()
		click.flat = true
		click.set_anchors_preset(Control.PRESET_FULL_RECT)
		click.pressed.connect(_start_rebind.bind(action))
		b.add_child(click)
		f["mid"].add_child(b)
		f["val"].visible = false
		_rebind_buttons[action] = b
		_page_body.add_child(f["wrap"])


func _start_rebind(action: String) -> void:
	_rebinding_action = action
	var b: PanelContainer = _rebind_buttons.get(action)
	if b:
		(b.get_child(0) as Label).text = "…"


func _input(event: InputEvent) -> void:
	if _rebinding_action == "" or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_cancel_rebind()
		else:
			Settings.set_binding(_rebinding_action, event)
			_finish_rebind()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		Settings.set_binding(_rebinding_action, event)
		_finish_rebind()
		get_viewport().set_input_as_handled()


func _cancel_rebind() -> void:
	var action := _rebinding_action
	_rebinding_action = ""
	var b: PanelContainer = _rebind_buttons.get(action)
	if b:
		(b.get_child(0) as Label).text = Settings.binding_text(action)


func _finish_rebind() -> void:
	_rebinding_action = ""
	_show_tab("keys")


# ------------------------------------------------------------ VIDÉO

func _build_video_page() -> void:
	_add_segmented_row("Mode d'affichage", "", Settings.WINDOW_MODES,
		["Fenêtré", "Plein écran (fenêtré)", "Plein écran"], Settings.window_mode,
		func(id: String) -> void:
			Settings.window_mode = id
			Settings.apply_window_mode()
			Settings.save_all())
	_add_slider_row("Échelle de rendu", "Baisse la résolution 3D pour gagner en performance",
		0.5, 1.0, 0.05, Settings.render_scale,
		func(v: float) -> String: return "%d %%" % int(round(v * 100.0)),
		func(v: float) -> void:
			Settings.render_scale = Settings.clamp_render_scale(v)
			Settings.apply_render_scale())
	_add_switch_row("Synchronisation verticale (VSync)", "", Settings.vsync_enabled,
		func(p: bool) -> void:
			Settings.vsync_enabled = p
			Settings.apply_vsync())
	_add_segmented_row("Limite d'images", "", Settings.FPS_LIMIT_OPTIONS,
		["Illimitée", "60", "144", "240"], Settings.fps_limit,
		func(v: int) -> void:
			Settings.fps_limit = v
			Settings.apply_fps_limit())
	_add_segmented_row("Préréglage graphique", "", Settings.GRAPHICS_PRESETS.keys(),
		["Steam Deck", "Performance", "Équilibré", "Qualité"], Settings.graphics_preset,
		func(id: String) -> void: Settings.apply_graphics_preset(id))


# ------------------------------------------------------------ SON

func _build_audio_page() -> void:
	_add_slider_row("Volume général", "", 0.0, 1.0, 0.01, Settings.volume_master,
		func(v: float) -> String: return "%d %%" % int(round(v * 100.0)),
		func(v: float) -> void: Settings.volume_master = Settings.clamp_volume(v))
	_add_slider_row("Effets sonores", "", 0.0, 1.0, 0.01, Settings.volume_sfx,
		func(v: float) -> String: return "%d %%" % int(round(v * 100.0)),
		func(v: float) -> void: Settings.volume_sfx = Settings.clamp_volume(v))
	_add_slider_row("Musique", "", 0.0, 1.0, 0.01, Settings.volume_music,
		func(v: float) -> String: return "%d %%" % int(round(v * 100.0)),
		func(v: float) -> void: Settings.volume_music = Settings.clamp_volume(v))
	_add_slider_row("Interface", "", 0.0, 1.0, 0.01, Settings.volume_ui,
		func(v: float) -> String: return "%d %%" % int(round(v * 100.0)),
		func(v: float) -> void: Settings.volume_ui = Settings.clamp_volume(v))
	_add_slider_row("Voix", "", 0.0, 1.0, 0.01, Settings.volume_voice,
		func(v: float) -> String: return "%d %%" % int(round(v * 100.0)),
		func(v: float) -> void: Settings.volume_voice = Settings.clamp_volume(v))
	_add_slider_row("Ambiance", "", 0.0, 1.0, 0.01, Settings.volume_ambience,
		func(v: float) -> String: return "%d %%" % int(round(v * 100.0)),
		func(v: float) -> void: Settings.volume_ambience = Settings.clamp_volume(v))
	_add_switch_row("Audio mono", "Un seul canal (accessibilité)", Settings.audio_mono,
		func(p: bool) -> void: Settings.audio_mono = p)


# ------------------------------------------------------------ RÉTICULE

func _build_crosshair_page() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTokens.S2)
	for id in Crosshair.PRESET_IDS:
		var b := MenuWidgets.comic_button(_PRESET_LABELS.get(id, id), UiTokens.PAPER, UiTokens.T_S)
		b.pressed.connect(func() -> void:
			Settings.crosshair_settings = Crosshair.PRESETS[id].duplicate(true)
			_refresh_crosshair_preview())
		row.add_child(b)
	_page_body.add_child(row)
	_add_switch_row("Réticule statique", "Ignore la dispersion réelle de l'arme", Settings.static_crosshair,
		func(p: bool) -> void:
			Settings.static_crosshair = p
			_refresh_crosshair_preview())


# ------------------------------------------------------------ ACCESSIBILITÉ

func _build_access_page() -> void:
	_add_slider_row("Échelle d'interface", "1.15 recommandée sur Steam Deck",
		0.8, 1.5, 0.05, Settings.ui_scale,
		func(v: float) -> String: return "%s ×" % SettingsFormat.format_number(v, 2),
		func(v: float) -> void:
			Settings.ui_scale = Settings.clamp_ui_scale(v)
			Settings.apply_ui_scale())
	_add_switch_row("Mouvement réduit", "Ne garde que des fondus", Settings.reduced_motion,
		func(p: bool) -> void: Settings.reduced_motion = p)
	_add_switch_row("Secousses de caméra", "", Settings.camera_shake_enabled,
		func(p: bool) -> void: Settings.camera_shake_enabled = p)
	_add_slider_row("Intensité des secousses", "", 0.0, 1.0, 0.05, Settings.camera_shake_intensity,
		func(v: float) -> String: return "%d %%" % int(round(v * 100.0)),
		func(v: float) -> void: Settings.camera_shake_intensity = Settings.clamp_camera_shake_intensity(v))
	_add_switch_row("Balancement de tête", "", Settings.head_bob_enabled,
		func(p: bool) -> void: Settings.head_bob_enabled = p)
	_add_slider_row("Intensité du balancement", "", 0.0, 2.0, 0.05, Settings.head_bob_intensity,
		func(v: float) -> String: return "%s ×" % SettingsFormat.format_number(v, 2),
		func(v: float) -> void: Settings.head_bob_intensity = Settings.clamp_head_bob_intensity(v))


# ------------------------------------------------------------ aperçu réticule + couleur ennemi (persistants)

## `preview` est un Control simple (PAS un PanelContainer) : la légende et le
## réticule vivent à des positions INDÉPENDANTES dans le même cadre — un
## Container les réarrangerait tous les deux dans le même rect de contenu
## (même piège qu'ArmoryScreen._build_stage, voir sa doc). Le fond est un
## `Panel` simple (dessine juste sa StyleBox).
func _build_crosshair_sidebar() -> void:
	var preview := Control.new()
	preview.position = Vector2(1920 - 64 - 470, 170)
	preview.custom_minimum_size = Vector2(470, 470)
	preview.clip_contents = true
	var preview_bg := Panel.new()
	preview_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_bg.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.PAPER_2, 0.0, UiTokens.DROP))
	preview.add_child(preview_bg)
	# vraie scène du jeu derrière le réticule (sur un aplat clair, le réticule blanc se perdait)
	var scene_bg := TextureRect.new()
	scene_bg.texture = load("res://assets/ui/renders/crosshair_preview_bg.png") as Texture2D
	scene_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scene_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	scene_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	scene_bg.offset_left = UiTokens.STROKE
	scene_bg.offset_top = UiTokens.STROKE
	scene_bg.offset_right = -UiTokens.STROKE
	scene_bg.offset_bottom = -UiTokens.STROKE
	preview.add_child(scene_bg)

	var cap := PanelContainer.new()
	cap.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.INK, 0.0, Vector2.ZERO, 0.0, Vector2(UiTokens.S2, UiTokens.S1 * 0.75)))
	cap.add_child(UiTokens.make_label("Aperçu du réticule", UiTokens.label(UiTokens.T_S, UiTokens.PAPER), true))
	preview.add_child(cap)

	_crosshair_preview = Crosshair.new()
	_crosshair_preview.set_anchors_preset(Control.PRESET_CENTER)
	preview.add_child(_crosshair_preview)
	add_child(preview)
	_refresh_crosshair_preview()

	var swatches := PanelContainer.new()
	swatches.position = Vector2(1920 - 64 - 470, 680)
	swatches.custom_minimum_size = Vector2(470, 0)
	swatches.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.PAPER, 0.0, UiTokens.DROP))
	var col := VBoxContainer.new()
	col.add_child(UiTokens.make_label("Couleur des ennemis", UiTokens.label(24), true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTokens.S2)
	row.add_child(_build_enemy_swatch(0, Color("FF2E9A")))
	row.add_child(_build_enemy_swatch(1, Color("C8FF1F")))
	row.add_child(UiTokens.make_label("Magenta ou citron,\nselon ta vue des couleurs", UiTokens.body(19, UiTokens.INK_SOFT)))
	col.add_child(row)
	swatches.add_child(col)
	add_child(swatches)
	_refresh_enemy_swatches()


func _build_enemy_swatch(index: int, color: Color) -> Control:
	var b := PanelContainer.new()
	b.custom_minimum_size = Vector2(64, 64)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_border_width_all(3)
	sb.border_color = UiTokens.INK
	b.add_theme_stylebox_override("panel", sb)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var click := Button.new()
	click.flat = true
	click.set_anchors_preset(Control.PRESET_FULL_RECT)
	click.pressed.connect(func() -> void:
		Settings.enemy_color = Settings.clamp_enemy_color(index)
		_refresh_enemy_swatches())
	b.add_child(click)
	_enemy_swatches[index] = b
	return b


func _refresh_enemy_swatches() -> void:
	for i in _enemy_swatches:
		var b: PanelContainer = _enemy_swatches[i]
		var sb := b.get_theme_stylebox("panel") as StyleBoxFlat
		var selected: bool = i == Settings.enemy_color
		sb.border_width_left = 6 if selected else 3
		sb.border_width_top = 6 if selected else 3
		sb.border_width_right = 6 if selected else 3
		sb.border_width_bottom = 6 if selected else 3
		sb.border_color = UiTokens.YELLOW if selected else UiTokens.INK


func _refresh_crosshair_preview() -> void:
	if _crosshair_preview:
		_crosshair_preview.static_mode = Settings.static_crosshair
		_crosshair_preview.apply_settings(Settings.crosshair_settings)


# ------------------------------------------------------------ PAR DÉFAUT / APPLIQUER

func _build_bottom_bar() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	row.position = Vector2(-64 - 460, -50 - 60)
	row.add_theme_constant_override("separation", UiTokens.S3)
	var reset_btn := MenuWidgets.comic_button("Par défaut", UiTokens.PAPER)
	reset_btn.pressed.connect(_on_reset_pressed)
	var apply_btn := MenuWidgets.comic_button("Appliquer", UiTokens.YELLOW)
	apply_btn.pressed.connect(_on_apply_pressed)
	row.add_child(reset_btn)
	row.add_child(apply_btn)
	add_child(row)


func _on_reset_pressed() -> void:
	match _current_tab:
		"mouse":
			Settings.reset_kb_page()
		"keys":
			Settings.reset_movement_bindings()
			Settings.save_all()
		"video", "audio":
			Settings.reset_render_page()
		"crosshair":
			Settings.crosshair_settings = Crosshair.DEFAULT_SETTINGS.duplicate(true)
			Settings.static_crosshair = false
			Settings.save_all()
		"access":
			Settings.reset_access_page()
	_refresh_crosshair_preview()
	_refresh_enemy_swatches()
	_show_tab(_current_tab)


func _on_apply_pressed() -> void:
	Settings.apply_ui_scale()
	Settings.apply_window_mode()
	Settings.apply_render_scale()
	Settings.apply_vsync()
	Settings.apply_fps_limit()
	Settings.save_all()
