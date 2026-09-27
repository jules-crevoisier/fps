## MainMenu.gd
## Salon principal (reports/ui/mockups/*.html) : barre du haut (chip joueur,
## onglets, indice Échap) + écran actif (HomeScreen/HeroesScreen/ArmoryScreen/
## SettingsPanel). boot.tscn change vers scenes/ui/main_menu.tscn (sauf
## --quickstart, voir QuickStart.gd) — remplace l'ancien lancement direct.
## Échap : ferme d'abord un sous-panneau ouvert de l'écran courant (ex. le
## panneau IP de l'accueil, voir HomeScreen.has_open_subpanel/close_subpanel),
## sinon ouvre la confirmation « Quitter le jeu ? ».
class_name MainMenu
extends Control

const TABS := ["accueil", "persos", "armurerie", "parametres"]
const _TAB_LABELS := {"accueil": "Accueil", "persos": "Persos", "armurerie": "Armurerie", "parametres": "Paramètres"}
const _TAB_SIZE := Vector2(230, 60)

var _current_tab: String = "accueil"
var _tab_buttons: Dictionary = {}
var _screens: Dictionary = {}
var _content_host: Control
var _confirm_backdrop: ColorRect
var _confirm_dialog: PanelContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	# retour de partie : la souris y était capturée (visée) -- le salon doit toujours la rendre
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	MatchConfig.load_last()
	_build()


func _build() -> void:
	_content_host = Control.new()
	_content_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_content_host)

	_screens["accueil"] = HomeScreen.new()
	_screens["persos"] = HeroesScreen.new()
	_screens["armurerie"] = ArmoryScreen.new()
	_screens["parametres"] = _build_settings_wrapper()
	for id in TABS:
		var s: Control = _screens[id]
		s.set_anchors_preset(Control.PRESET_FULL_RECT)
		s.visible = id == _current_tab
		_content_host.add_child(s)

	_build_topbar()
	_build_confirm_dialog()


func _build_settings_wrapper() -> Control:
	var wrap := Control.new()
	wrap.add_child(MenuWidgets.sunburst_background(Color("3C9BFF"), Color("2E8BFF"), Color("1D5FD6")))
	var panel := SettingsPanel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(panel)
	return wrap


# ------------------------------------------------------------ barre du haut

## PAS un Container : trois groupes (chip/onglets/Échap) positionnés à la main
## (mêmes coordonnées que la maquette) — un PanelContainer réarrangerait ses
## enfants dans le MÊME rect de contenu et effacerait ces positions (même
## piège que HomeScreen._build_modes, voir sa doc).
func _build_topbar() -> void:
	var bar := Control.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, 104)
	bar.size.y = 104
	bar.mouse_filter = Control.MOUSE_FILTER_PASS

	var chip := HBoxContainer.new()
	chip.position = Vector2(48, 16)
	chip.add_theme_constant_override("separation", UiTokens.S2)
	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(72, 72)
	avatar.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.YELLOW, 0.0, Vector2(5, 5)))
	var portrait := TextureRect.new()
	portrait.texture = UiTokens.icon("portrait_verrou")
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	avatar.add_child(portrait)
	chip.add_child(avatar)
	var name_block := VBoxContainer.new()
	name_block.add_theme_constant_override("separation", 0)
	name_block.add_child(UiTokens.make_label("Joueur", UiTokens.label(UiTokens.T_M, UiTokens.PAPER), true))
	name_block.add_child(UiTokens.make_label("Niveau 1 · Hors ligne", UiTokens.body(20, UiTokens.PAPER)))
	chip.add_child(name_block)
	bar.add_child(chip)

	var tabs_root := Control.new()
	tabs_root.position = Vector2(48 + 72 + 16 + 220 + 24, 22)
	var x := 0.0
	for id in TABS:
		var b := MenuWidgets.tab_button(_TAB_LABELS[id], id == _current_tab)
		b.size = _TAB_SIZE
		b.custom_minimum_size = _TAB_SIZE
		b.position = Vector2(x, 0)
		b.pressed.connect(_show_tab.bind(id))
		tabs_root.add_child(b)
		_tab_buttons[id] = b
		x += _TAB_SIZE.x + 6.0
	bar.add_child(tabs_root)

	# « Échap Quitter » CLIQUABLE (retour utilisateur 2026-09-27) : même effet que la touche Échap
	# (confirmation « Quitter le jeu ? »), texte jaune au survol / focus clavier.
	var quit_btn := Button.new()
	quit_btn.flat = true
	quit_btn.focus_mode = Control.FOCUS_ALL
	quit_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	quit_btn.tooltip_text = "Quitter le jeu"
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		quit_btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	quit_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	quit_btn.position = Vector2(-48 - 170, 26)
	quit_btn.custom_minimum_size = Vector2(170, 52)
	var right := HBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_FULL_RECT)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override("separation", UiTokens.S2)
	var esc_chip := MenuWidgets.key_chip("Échap")
	esc_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(esc_chip)
	var quit_label := UiTokens.make_label("Quitter", UiTokens.label(UiTokens.T_S, UiTokens.PAPER))
	right.add_child(quit_label)
	quit_btn.add_child(right)
	var set_hot := func(hot: bool) -> void:
		quit_label.label_settings.font_color = UiTokens.YELLOW if hot else UiTokens.PAPER
	quit_btn.mouse_entered.connect(set_hot.bind(true))
	quit_btn.mouse_exited.connect(set_hot.bind(false))
	quit_btn.focus_entered.connect(set_hot.bind(true))
	quit_btn.focus_exited.connect(set_hot.bind(false))
	quit_btn.pressed.connect(_handle_escape)
	bar.add_child(quit_btn)

	add_child(bar)


func _show_tab(id: String) -> void:
	if not TABS.has(id):
		return
	_current_tab = id
	for tab_id in _tab_buttons:
		var b: Button = _tab_buttons[tab_id]
		var selected: bool = tab_id == id
		MenuWidgets.apply_plate_states(b, UiTokens.YELLOW if selected else UiTokens.PAPER)
		if selected:
			var sb := b.get_theme_stylebox("normal") as StyleBoxComic
			sb.drop = Vector2(6, 6)
		b.position.y = -4.0 if selected else 0.0
	for tab_id in _screens:
		(_screens[tab_id] as Control).visible = tab_id == id
	var current: Control = _screens[id]
	MenuWidgets.slide_in(current, current.position.x + 40.0)


# ------------------------------------------------------------ Échap

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_handle_escape()
		get_viewport().set_input_as_handled()


func _handle_escape() -> void:
	if _confirm_dialog.visible:
		_hide_confirm()
		return
	var screen: Control = _screens.get(_current_tab)
	if screen != null and screen.has_method("has_open_subpanel") and screen.call("has_open_subpanel"):
		screen.call("close_subpanel")
		return
	_show_confirm()


func _build_confirm_dialog() -> void:
	_confirm_backdrop = ColorRect.new()
	_confirm_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_backdrop.color = Color(UiTokens.INK.r, UiTokens.INK.g, UiTokens.INK.b, 0.6)
	_confirm_backdrop.visible = false
	_confirm_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_confirm_backdrop)

	_confirm_dialog = PanelContainer.new()
	_confirm_dialog.visible = false
	_confirm_dialog.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.PAPER, 0.0, Vector2(12, 12), UiTokens.STROKE, Vector2(UiTokens.S4, UiTokens.S3)))
	_confirm_dialog.position = Vector2(960 - 240, 540 - 120)
	_confirm_dialog.custom_minimum_size = Vector2(480, 240)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTokens.S3)
	col.add_child(UiTokens.make_label("Quitter le jeu ?", UiTokens.display(UiTokens.T_L, UiTokens.INK, 0)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTokens.S2)
	var yes := MenuWidgets.comic_button("Quitter", UiTokens.YELLOW)
	yes.pressed.connect(func() -> void: get_tree().quit())
	var no := MenuWidgets.comic_button("Annuler", UiTokens.PAPER)
	no.pressed.connect(_hide_confirm)
	row.add_child(yes)
	row.add_child(no)
	col.add_child(row)
	_confirm_dialog.add_child(col)
	add_child(_confirm_dialog)


func _show_confirm() -> void:
	_confirm_backdrop.visible = true
	_confirm_dialog.visible = true
	MenuWidgets.pop_in(_confirm_dialog)


func _hide_confirm() -> void:
	_confirm_backdrop.visible = false
	_confirm_dialog.visible = false
