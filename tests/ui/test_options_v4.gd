## test_options_v4.gd
## Spec UX-35 (docs/UI_DIRECTION_BL3.md §6 « Options », direction VALIDÉE
## 2026-09-25) : onglets penchés, lignes de 60 px sur 1 100 px max (libellé 28,
## contrôle à 480 px, pas au bord), curseur à piste penchée signal, bascule
## OUI / NON, aide de la ligne focalisée à droite (comme BL3). Toutes les
## options existantes (UX-02/03/06/12/14) doivent rester présentes et
## fonctionnelles sous ce nouvel habillage — voir OptionsMenu.gd, tête de
## fichier "UX-35".
##
## Instance RÉELLE d'OptionsMenu.gd, montée dans l'arbre (même patron que
## tests/ui/test_crosshair_code.gd `_options_menu()`) : `_ready()` construit
## les 5 pages sans appel réseau. Les champs/méthodes préfixés `_` sont
## utilisés directement, comme le reste de la suite `tests/ui/` le fait déjà.
extends GdUnitTestSuite

const OPTIONS_MENU_SCRIPT := preload("res://scripts/ui/OptionsMenu.gd")


func _menu() -> Control:
	var m: Control = OPTIONS_MENU_SCRIPT.new()
	add_child(m)
	auto_free(m)
	return m


## Cherche récursivement un `Label` dont le texte EXACT est `label_text` sous
## `root`, et renvoie le CONTRÔLE de sa ligne (`_row_v4` place systématiquement
## [libellé, contrôle, marge] dans cet ordre — voir OptionsMenu._row_v4).
func _row_control(root: Node, label_text: String) -> Control:
	for child in root.get_children():
		if child is Label and (child as Label).text == label_text:
			var row := child.get_parent()
			if row and row.get_child_count() > 1:
				return row.get_child(1)
		var found := _row_control(child, label_text)
		if found:
			return found
	return null


# ================================================ Lignes v4 (§6 « 60 px sur 1 100 px max, contrôle à 480 px »)

func test_row_dimension_constants_match_the_locked_spec() -> void:
	assert_float(OPTIONS_MENU_SCRIPT.ROW_HEIGHT_V4).append_failure_message(
		"UI_DIRECTION_BL3.md §6 : lignes de 60 px").is_equal_approx(60.0, 0.01)
	assert_float(OPTIONS_MENU_SCRIPT.ROW_MAX_WIDTH_V4).append_failure_message(
		"UI_DIRECTION_BL3.md §6 : 1 100 px max").is_equal_approx(1100.0, 0.01)
	assert_float(OPTIONS_MENU_SCRIPT.ROW_LABEL_WIDTH_V4).append_failure_message(
		"UI_DIRECTION_BL3.md §6 : contrôle à 480 px").is_equal_approx(480.0, 0.01)
	assert_float(OPTIONS_MENU_SCRIPT.ROW_RIGHT_MARGIN_V4).append_failure_message(
		"UI_DIRECTION_BL3.md §6 : « pas au bord » — marge droite non nulle").is_greater(0.0)


func test_a_real_row_is_built_at_the_locked_height() -> void:
	var menu := _menu()
	var control := _row_control(menu._kb_page, "Champ de vision (FOV)")
	assert_object(control).append_failure_message("la ligne FOV doit exister sur la page Clavier / Souris").is_not_null()
	var row: Control = control.get_parent()
	assert_float(row.custom_minimum_size.y).append_failure_message(
		"chaque ligne d'options doit mesurer 60 px de haut (UI_DIRECTION_BL3.md §6)"
	).is_equal_approx(OPTIONS_MENU_SCRIPT.ROW_HEIGHT_V4, 0.01)


func test_the_settings_column_is_capped_at_1100px_and_left_aligned() -> void:
	var menu := _menu()
	assert_float(menu._scroll.custom_minimum_size.x).append_failure_message(
		"la colonne de réglages doit être bornée à 1 100 px max (UI_DIRECTION_BL3.md §6)"
	).is_equal_approx(OPTIONS_MENU_SCRIPT.ROW_MAX_WIDTH_V4, 0.01)
	assert_int(menu._scroll.size_flags_horizontal).append_failure_message(
		"la colonne ne doit pas s'étirer sur toute la largeur — alignée à gauche (§4.4 « rien n'est centré par défaut »)"
	).is_equal(Control.SIZE_SHRINK_BEGIN)


# ================================================ Onglets penchés (§6 « onglets penchés » ; §4.6 « choisi : fond signal »)

func test_tabs_are_slanted_kit_slant_bars() -> void:
	var menu := _menu()
	for tab in [menu._tab_kb, menu._tab_pad, menu._tab_render, menu._tab_access, menu._tab_crosshair]:
		assert_bool(tab is KitSlantBar).append_failure_message(
			"les onglets d'Options doivent être des KitSlantBar penchés (UI_DIRECTION_BL3.md §6, même kit que BuyMenu/ArsenalMenu)"
		).is_true()


func test_the_active_tab_turns_signal_yellow_and_the_others_stay_plate() -> void:
	var menu := _menu()
	# _ready() a déjà affiché "kb" par défaut.
	assert_that(menu._tab_kb.accent_color).append_failure_message(
		"l'onglet ACTIF doit passer en fond `signal` (§4.6 « choisi : fond signal »)"
	).is_equal(Comic.signal_color())
	assert_that(menu._tab_render.accent_color).append_failure_message(
		"un onglet INACTIF doit rester en `plate_hi`, jamais `signal`"
	).is_equal(Comic.plate_hi_color())

	menu._show_page("render")

	assert_that(menu._tab_render.accent_color).is_equal(Comic.signal_color())
	assert_that(menu._tab_kb.accent_color).append_failure_message(
		"changer d'onglet doit repasser l'ANCIEN onglet actif en `plate_hi`"
	).is_equal(Comic.plate_hi_color())
	assert_bool(menu._tab_render.selected).is_true()
	assert_bool(menu._tab_kb.selected).is_false()


# ================================================ Aide de la ligne focalisée à droite (§6 « comme BL3 »)

func test_help_panel_has_a_non_empty_default_before_anything_is_focused() -> void:
	var menu := _menu()
	assert_str(menu._help_label.text).append_failure_message(
		"le panneau d'aide doit avoir un état par défaut non vide (état 'vide' explicite, jamais un panneau blanc)"
	).is_not_empty()


func test_hovering_a_row_control_shows_its_help_text_on_the_right() -> void:
	var menu := _menu()
	var default_text: String = menu._help_label.text

	var probe := Control.new()
	add_child(probe)
	auto_free(probe)
	menu._wire_help(probe, "Aide de test — ligne survolée")

	probe.mouse_entered.emit()

	assert_str(menu._help_label.text).append_failure_message(
		"survoler une ligne doit afficher SON aide à droite (UI_DIRECTION_BL3.md §6 « aide de la ligne focalisée à droite, comme BL3 »)"
	).is_equal("Aide de test — ligne survolée")
	assert_str(menu._help_label.text).is_not_equal(default_text)


func test_focusing_a_row_control_also_shows_its_help_text() -> void:
	var menu := _menu()
	var probe := Control.new()
	add_child(probe)
	auto_free(probe)
	menu._wire_help(probe, "Aide de test — focus manette/clavier")

	probe.focus_entered.emit()

	assert_str(menu._help_label.text).is_equal("Aide de test — focus manette/clavier")


func test_switching_page_resets_the_help_panel_to_its_default() -> void:
	var menu := _menu()
	var default_text: String = menu._help_label.text
	menu._set_help("Un texte quelconque, laissé par la ligne précédente")

	menu._show_page("pad")

	assert_str(menu._help_label.text).append_failure_message(
		"changer d'onglet ne doit jamais laisser affichée l'aide d'une ligne de la page précédente"
	).is_equal(default_text)


# ================================================ Bascule OUI / NON (§6)

func test_boolean_settings_render_as_oui_non_toggles_and_flip_the_underlying_setting() -> void:
	var menu := _menu()
	var before := Settings.fov_effects_enabled

	var toggle: Control = _row_control(menu._kb_page, "Effets de FOV")
	assert_object(toggle).append_failure_message("la ligne « Effets de FOV » doit exister sur la page Clavier / Souris").is_not_null()
	assert_bool(toggle is KitSlantBar).append_failure_message(
		"une bascule v4 doit être un KitSlantBar OUI/NON (UI_DIRECTION_BL3.md §6)").is_true()
	var kit_toggle: KitSlantBar = toggle
	assert_str(kit_toggle.bar_text).is_equal("Oui" if before else "Non")

	kit_toggle.pressed.emit()

	assert_bool(Settings.fov_effects_enabled).append_failure_message(
		"cliquer la bascule doit inverser IMMÉDIATEMENT le réglage Settings correspondant"
	).is_equal(not before)
	assert_str(kit_toggle.bar_text).is_equal("Non" if before else "Oui")
	assert_that(kit_toggle.accent_color).append_failure_message(
		"« OUI » doit être en fond signal (jaune), « NON » en plate_hi (§4.6)"
	).is_equal(Comic.signal_color() if not before else Comic.plate_hi_color())

	Settings.fov_effects_enabled = before  # Settings est un état STATIQUE partagé — restauré pour ne pas polluer les autres suites.
	Settings.save_all()


# ================================================ Curseur à piste penchée signal (§6)

func test_slider_row_drives_a_slanted_signal_track_and_persists_the_setting() -> void:
	var menu := _menu()
	var before := Settings.mouse_sensitivity

	var control := _row_control(menu._kb_page, "Sensibilité souris")
	assert_object(control).is_not_null()
	var wrap: HBoxContainer = control
	# `_V4Slider` (OptionsMenu.gd) est une classe interne SANS `class_name` :
	# accès dynamique (non typé) plutôt qu'une annotation de type impossible
	# à écrire depuis un autre fichier — même limite que documentée pour les
	# classes internes de BuyMenu.gd (WeaponSilhouette/WeaponTurntable).
	var slider = wrap.get_child(0)
	assert_bool(slider.has_signal("value_changed")).append_failure_message(
		"le curseur v4 (_V4Slider) doit exposer `value_changed`, comme un HSlider"
	).is_true()

	slider.min_value = 0.0005
	slider.max_value = 0.01
	slider.step = 0.0001
	slider.value = 0.0075

	assert_float(slider.value).is_equal_approx(0.0075, 0.0001)

	slider.value_changed.emit(slider.value)

	assert_float(Settings.mouse_sensitivity).append_failure_message(
		"déplacer le curseur doit persister IMMÉDIATEMENT dans Settings, comme chaque contrôle du menu"
	).is_equal_approx(0.0075, 0.0001)

	Settings.mouse_sensitivity = before
	Settings.save_all()


func test_slider_clamps_its_value_to_the_min_max_range() -> void:
	var menu := _menu()
	var control := _row_control(menu._kb_page, "Champ de vision (FOV)")
	var wrap: HBoxContainer = control
	var slider = wrap.get_child(0)

	slider.value = 999.0
	assert_float(slider.value).append_failure_message(
		"le curseur ne doit jamais dépasser `max_value`"
	).is_equal_approx(float(slider.max_value), 0.01)

	slider.value = -999.0
	assert_float(slider.value).append_failure_message(
		"le curseur ne doit jamais descendre sous `min_value`"
	).is_equal_approx(float(slider.min_value), 0.01)


# ================================================ Toutes les options existantes restent présentes (UX-02/03/06/12/14)

func test_all_five_pages_and_all_rebindable_actions_are_still_present() -> void:
	var menu := _menu()

	menu._show_page("kb")
	for action in Settings.ACTIONS:
		assert_bool(menu._kb_buttons.has(action)).append_failure_message(
			"l'action « %s » doit rester remappable au clavier (UX-06)" % action
		).is_true()

	menu._show_page("pad")
	for action in Settings.ACTIONS:
		assert_bool(menu._pad_buttons.has(action)).append_failure_message(
			"l'action « %s » doit rester remappable à la manette (UX-06)" % action
		).is_true()

	menu._show_page("crosshair")
	menu._open_crosshair_editor()
	assert_object(menu._crosshair_editor).append_failure_message(
		"la page Viseur doit toujours ouvrir CrosshairEditor.gd (UX-03)"
	).is_not_null()


# ================================================ UX-37 (retour lead 2026-09-25, §4 :
# « bandeau pinceau rouge à supprimer, titre OPTIONS en encre 66 » ;
# « sensibilité en échelle lisible » ; « curseur intensité du tremblement »).

func test_options_no_longer_shows_the_red_brush_banner() -> void:
	var menu := _menu()

	assert_int(menu.find_children("*", "BrushHeader", true, false).size()).append_failure_message(
		"UX-37 §4 : le bandeau pinceau rouge (BrushHeader) doit disparaître de l'écran Options"
	).is_equal(0)


func test_options_title_is_a_v4_label_at_66px() -> void:
	var menu := _menu()

	assert_object(menu._title_label).append_failure_message(
		"le titre OPTIONS doit rester visible, juste sans bandeau pinceau (UX-37 §4)"
	).is_not_null()
	assert_str(menu._title_label.text).is_equal("OPTIONS")
	assert_int(menu._title_label.get_theme_font_size("font_size")).append_failure_message(
		"UX-37 §4 : titre OPTIONS en 66 px (remplace le bandeau pinceau)"
	).is_equal(Comic.SIZE_66)


func test_mouse_sensitivity_slider_uses_a_readable_scale_around_the_settings_default() -> void:
	# Retour utilisateur 2026-09-25 : « la sensibilité de base est beaucoup
	# trop haute » — le curseur et son libellé doivent parler en multiplicateur
	# du défaut (0.1x-5.0x, 1.0x = Settings.MOUSE_SENSITIVITY_DEFAULT), jamais
	# en valeur brute rad/pixel (« 0.0025 »/« 0.0010 »).
	var before := Settings.mouse_sensitivity
	Settings.mouse_sensitivity = Settings.MOUSE_SENSITIVITY_DEFAULT
	var menu := _menu()

	var control := _row_control(menu._kb_page, "Sensibilité souris")
	assert_object(control).is_not_null()
	var wrap: HBoxContainer = control
	var slider = wrap.get_child(0)
	var val_lbl: Label = wrap.get_child(1)

	assert_str(val_lbl.text).append_failure_message(
		"au défaut Settings, la sensibilité affichée doit lire 1.00× (échelle lisible), jamais la valeur brute rad/pixel"
	).is_equal("1.00×")
	assert_float(float(slider.min_value)).append_failure_message(
		"le bas du curseur doit correspondre à 0.1× le défaut (échelle 0.1-5.0)"
	).is_equal_approx(Settings.MOUSE_SENSITIVITY_DEFAULT * 0.1, 0.00001)
	assert_float(float(slider.max_value)).append_failure_message(
		"le haut du curseur doit correspondre à 5.0× le défaut (échelle 0.1-5.0)"
	).is_equal_approx(Settings.MOUSE_SENSITIVITY_DEFAULT * 5.0, 0.00001)

	Settings.mouse_sensitivity = before
	Settings.save_all()


func test_camera_shake_intensity_slider_exists_on_the_accessibility_page_and_persists_the_setting() -> void:
	# GF-08 : curseur "Intensité du tremblement" 0-100 %, séparé du maître
	# ON/OFF "Secousses de caméra" (Settings.camera_shake_intensity).
	var before := Settings.camera_shake_intensity
	var menu := _menu()
	menu._show_page("access")

	var control := _row_control(menu._access_page, "Intensité du tremblement")
	assert_object(control).append_failure_message(
		"la page Accessibilité doit exposer un curseur « Intensité du tremblement » (GF-08, Settings.camera_shake_intensity)"
	).is_not_null()
	var wrap: HBoxContainer = control
	var slider = wrap.get_child(0)

	slider.value = 0.42
	slider.value_changed.emit(slider.value)

	assert_float(Settings.camera_shake_intensity).append_failure_message(
		"déplacer le curseur doit persister IMMÉDIATEMENT dans Settings.camera_shake_intensity"
	).is_equal_approx(0.42, 0.01)

	Settings.camera_shake_intensity = before
	Settings.save_all()
