## test_crosshair_code.gd
## Spec (UX-03, docs/research/04_ui_ux.md tâche UX-03) : l'éditeur de viseur
## dessine `Crosshair._draw()` à partir d'un dictionnaire de réglages
## (`Crosshair.settings`, complété/borné par `Crosshair.normalize_settings`) ;
## `Crosshair.encode()`/`decode()` font l'aller-retour SANS PERTE ; 4
## préréglages (Défaut, Point, Croix fine, Croix épaisse — `Crosshair.PRESETS`/
## `PRESET_IDS`) ; les fonctions pures qui alimentent `_draw()`
## (`line_gap_px`, `element_color`) restent compatibles avec l'écart dynamique
## verrouillé par GF-09 (tests/ui/test_crosshair.gd, hors de ce fichier —
## jamais réécrit ici).
extends GdUnitTestSuite

const OPTIONS_MENU_SCRIPT := preload("res://scripts/ui/OptionsMenu.gd")


# ------------------------------------------------------------ normalize_settings : défauts + bornes
func test_normalize_settings_of_empty_dict_returns_full_defaults() -> void:
	assert_dict(Crosshair.normalize_settings({})).is_equal(Crosshair.DEFAULT_SETTINGS)


func test_normalize_settings_fills_only_missing_keys() -> void:
	var partial := {"inner_gap": 12.0, "dot_enabled": false}
	var out := Crosshair.normalize_settings(partial)
	assert_float(out.inner_gap).is_equal_approx(12.0, 0.001)
	assert_bool(out.dot_enabled).is_false()
	# Le reste retombe sur DEFAULT_SETTINGS, jamais une valeur inventée.
	assert_float(out.inner_length).is_equal_approx(Crosshair.DEFAULT_SETTINGS.inner_length, 0.001)
	assert_bool(out.outline_enabled).is_equal(Crosshair.DEFAULT_SETTINGS.outline_enabled)


func test_normalize_settings_clamps_opacity_above_one() -> void:
	var out := Crosshair.normalize_settings({"inner_opacity": 5.0})
	assert_float(out.inner_opacity).is_equal_approx(1.0, 0.001)


func test_normalize_settings_clamps_opacity_below_zero() -> void:
	var out := Crosshair.normalize_settings({"outer_opacity": -2.0})
	assert_float(out.outer_opacity).is_equal_approx(0.0, 0.001)


func test_normalize_settings_clamps_thickness_to_minimum() -> void:
	var out := Crosshair.normalize_settings({"inner_thickness": -10.0})
	assert_float(out.inner_thickness).is_equal_approx(0.5, 0.001)


func test_normalize_settings_forces_color_alpha_to_one() -> void:
	# UX-03 : la couleur de base n'a JAMAIS d'alpha propre (seules les
	# opacités par élément contrôlent la transparence, voir doc de classe).
	var out := Crosshair.normalize_settings({"color": Color(0.2, 0.4, 0.6, 0.1)})
	assert_float(out.color.a).is_equal_approx(1.0, 0.001)
	assert_float(out.color.r).is_equal_approx(0.2, 0.001)
	assert_float(out.color.g).is_equal_approx(0.4, 0.001)
	assert_float(out.color.b).is_equal_approx(0.6, 0.001)


func test_normalize_settings_ignores_wrong_typed_numeric_field() -> void:
	# Un code importé à la main peut porter un type inattendu : jamais un
	# plantage, la clé retombe sur son défaut (voir doc de `normalize_settings`).
	var out := Crosshair.normalize_settings({"inner_gap": "pas un nombre"})
	assert_float(out.inner_gap).is_equal_approx(Crosshair.DEFAULT_SETTINGS.inner_gap, 0.001)


func test_normalize_settings_ignores_non_color_value_for_color_key() -> void:
	var out := Crosshair.normalize_settings({"color": "rouge"})
	assert_that(out.color).is_equal(Crosshair.DEFAULT_SETTINGS.color)


func test_normalize_settings_never_mutates_its_argument() -> void:
	var raw := {"inner_gap": 99.0}
	var raw_copy := raw.duplicate(true)
	Crosshair.normalize_settings(raw)
	assert_dict(raw).is_equal(raw_copy)


# ------------------------------------------------------------ encode()/decode() : aller-retour sans perte
func test_encode_decode_round_trip_preserves_default_settings() -> void:
	var code := Crosshair.encode(Crosshair.DEFAULT_SETTINGS)
	assert_dict(Crosshair.decode(code)).is_equal(Crosshair.DEFAULT_SETTINGS)


func test_encode_decode_round_trip_is_lossless_for_a_fully_customized_dictionary() -> void:
	var custom := {
		"color": Color(0.125, 0.875, 0.333, 1.0),
		"outline_enabled": false, "outline_opacity": 0.42, "outline_thickness": 3.5,
		"dot_enabled": false, "dot_size": 11.5, "dot_opacity": 0.61,
		"inner_enabled": true, "inner_length": 13.25, "inner_thickness": 3.75, "inner_gap": 8.5, "inner_opacity": 0.88,
		"outer_enabled": true, "outer_length": 4.5, "outer_thickness": 1.5, "outer_gap": 21.0, "outer_opacity": 0.15,
	}
	var expected := Crosshair.normalize_settings(custom)
	var round_tripped := Crosshair.decode(Crosshair.encode(custom))
	assert_dict(round_tripped).is_equal(expected)


func test_encode_decode_round_trip_preserves_fractional_float_precision() -> void:
	# `full_precision` (JSON.stringify) doit survivre à l'aller-retour, pas
	# seulement les valeurs "rondes" testées ci-dessus.
	var custom := Crosshair.normalize_settings({"inner_gap": 7.0000001, "outer_opacity": 0.3333333})
	var round_tripped := Crosshair.decode(Crosshair.encode(custom))
	assert_float(round_tripped.inner_gap).is_equal_approx(7.0000001, 0.00001)
	assert_float(round_tripped.outer_opacity).is_equal_approx(0.3333333, 0.00001)


func test_decode_empty_code_returns_defaults() -> void:
	assert_dict(Crosshair.decode("")).is_equal(Crosshair.DEFAULT_SETTINGS)


func test_decode_garbage_base64_returns_defaults() -> void:
	assert_dict(Crosshair.decode("¤¤¤ pas du base64 ¤¤¤")).is_equal(Crosshair.DEFAULT_SETTINGS)


func test_decode_base64_of_non_dictionary_json_returns_defaults() -> void:
	# Base64 valide, JSON valide, mais la racine est un Array : jamais un
	# plantage (voir doc de `decode`).
	var code := Marshalls.utf8_to_base64(JSON.stringify([1, 2, 3]))
	assert_dict(Crosshair.decode(code)).is_equal(Crosshair.DEFAULT_SETTINGS)


func test_decode_partial_json_fills_missing_keys_with_defaults() -> void:
	var code := Marshalls.utf8_to_base64(JSON.stringify({"inner_gap": 20.0}))
	var out := Crosshair.decode(code)
	assert_float(out.inner_gap).is_equal_approx(20.0, 0.001)
	assert_float(out.outer_length).is_equal_approx(Crosshair.DEFAULT_SETTINGS.outer_length, 0.001)


# ------------------------------------------------------------ 4 préréglages requis
func test_preset_ids_are_the_four_required_ones_in_order() -> void:
	assert_array(Crosshair.PRESET_IDS).is_equal(["default", "dot", "thin_cross", "thick_cross"])


func test_every_preset_is_already_normalized() -> void:
	for id in Crosshair.PRESET_IDS:
		assert_dict(Crosshair.normalize_settings(Crosshair.PRESETS[id])).append_failure_message(
			"le préréglage '%s' devrait déjà être normalisé" % id).is_equal(Crosshair.PRESETS[id])


func test_preset_default_matches_default_settings() -> void:
	assert_dict(Crosshair.PRESETS.default).is_equal(Crosshair.DEFAULT_SETTINGS)


func test_preset_dot_shows_only_the_center_dot() -> void:
	var p: Dictionary = Crosshair.PRESETS.dot
	assert_bool(p.dot_enabled).is_true()
	assert_bool(p.inner_enabled).is_false()
	assert_bool(p.outer_enabled).is_false()


func test_preset_thin_cross_has_no_dot_and_a_thinner_inner_line_than_thick_cross() -> void:
	var thin: Dictionary = Crosshair.PRESETS.thin_cross
	var thick: Dictionary = Crosshair.PRESETS.thick_cross
	assert_bool(thin.dot_enabled).is_false()
	assert_bool(thin.inner_enabled).is_true()
	assert_bool(thick.inner_enabled).is_true()
	assert_bool(float(thin.inner_thickness) < float(thick.inner_thickness)).is_true()


func test_every_preset_round_trips_losslessly_through_encode_decode() -> void:
	for id in Crosshair.PRESET_IDS:
		var p: Dictionary = Crosshair.PRESETS[id]
		assert_dict(Crosshair.decode(Crosshair.encode(p))).append_failure_message(
			"le préréglage '%s' ne survit pas à encode()/decode()" % id).is_equal(p)


# ------------------------------------------------------------ line_gap_px (écart dessiné, pur)
func test_line_gap_px_in_static_case_matches_the_chosen_setting_exactly() -> void:
	# Aucun delta dynamique (dynamic_gap == DEFAULT_GAP_PX, cas de l'aperçu de
	## CrosshairEditor.gd, qui n'appelle jamais update_spread) : l'écart
	# dessiné doit être EXACTEMENT celui choisi par le joueur.
	var gap := Crosshair.line_gap_px(Crosshair.DEFAULT_GAP_PX, 10.0)
	assert_float(gap).is_equal_approx(10.0, 0.001)


func test_line_gap_px_adds_the_dynamic_spread_delta_on_top_of_the_custom_base() -> void:
	# Dispersion dynamique +3 px (spray/mouvement) par-dessus un écart de base
	# de 10 px choisi par le joueur -> 13 px, jamais l'un des deux seul.
	var gap := Crosshair.line_gap_px(Crosshair.DEFAULT_GAP_PX + 3.0, 10.0)
	assert_float(gap).is_equal_approx(13.0, 0.001)


func test_line_gap_px_with_default_dynamic_and_default_setting_matches_legacy_gap() -> void:
	var gap := Crosshair.line_gap_px(Crosshair.DEFAULT_GAP_PX, Crosshair.DEFAULT_SETTINGS.inner_gap)
	assert_float(gap).is_equal_approx(Crosshair.DEFAULT_GAP_PX, 0.001)


# ------------------------------------------------------------ element_color (opacité par élément, pur)
func test_element_color_multiplies_base_alpha_by_opacity() -> void:
	var c := Crosshair.element_color(Color(1.0, 1.0, 1.0, 1.0), 0.5)
	assert_float(c.a).is_equal_approx(0.5, 0.001)
	assert_float(c.r).is_equal_approx(1.0, 0.001)


func test_element_color_clamps_opacity_above_one() -> void:
	var c := Crosshair.element_color(Color(1.0, 1.0, 1.0, 1.0), 4.0)
	assert_float(c.a).is_equal_approx(1.0, 0.001)


func test_element_color_clamps_opacity_below_zero() -> void:
	var c := Crosshair.element_color(Color(1.0, 1.0, 1.0, 1.0), -4.0)
	assert_float(c.a).is_equal_approx(0.0, 0.001)


# ------------------------------------------------------------ Crosshair (nœud) — apply_settings depuis un dictionnaire
func _crosshair() -> Crosshair:
	return auto_free(Crosshair.new())


func test_apply_settings_normalizes_and_stores_the_dictionary() -> void:
	var cross := _crosshair()
	cross.apply_settings({"inner_gap": 9.0, "dot_enabled": false})
	assert_float(cross.settings.inner_gap).is_equal_approx(9.0, 0.001)
	assert_bool(cross.settings.dot_enabled).is_false()
	# Le reste retombe sur les défauts, jamais une valeur héritée d'un appel précédent.
	assert_float(cross.settings.outer_gap).is_equal_approx(Crosshair.DEFAULT_SETTINGS.outer_gap, 0.001)


func test_apply_settings_with_a_preset_matches_that_preset_exactly() -> void:
	var cross := _crosshair()
	cross.apply_settings(Crosshair.PRESETS.thick_cross)
	assert_dict(cross.settings).is_equal(Crosshair.PRESETS.thick_cross)


func test_apply_settings_never_changes_the_dynamic_gap_pipeline() -> void:
	# GF-09, verrouillé par tests/ui/test_crosshair.gd : `current_gap_px()` ne
	# doit JAMAIS dépendre de `settings` — seul `_draw()` (via `line_gap_px`)
	# ajoute l'écart choisi par le joueur PAR-DESSUS, sans jamais toucher la
	# valeur "réelle" exposée par `current_gap_px()`.
	var cross := _crosshair()
	cross.update_spread(deg_to_rad(2.0), 90.0, 1080.0)
	var gap_before := cross.current_gap_px()
	cross.apply_settings({"inner_gap": 37.0, "outer_gap": 5.0})
	assert_float(cross.current_gap_px()).is_equal_approx(gap_before, 0.001)


func test_apply_settings_default_dictionary_matches_the_legacy_fixed_crosshair() -> void:
	# DEFAULT_SETTINGS doit reproduire l'ancien réticule fixe de GF-09.
	assert_float(Crosshair.DEFAULT_SETTINGS.inner_gap).is_equal_approx(Crosshair.DEFAULT_GAP_PX, 0.001)
	assert_float(Crosshair.DEFAULT_SETTINGS.inner_length).is_equal_approx(Crosshair.LINE_LENGTH_PX, 0.001)
	assert_float(Crosshair.DEFAULT_SETTINGS.inner_thickness).is_equal_approx(Crosshair.LINE_THICKNESS_PX, 0.001)
	assert_float(Crosshair.DEFAULT_SETTINGS.dot_size).is_equal_approx(Crosshair.CENTER_DOT_PX, 0.001)


# ------------------------------------------------------------ Intégration : OptionsMenu -> CrosshairEditor
## Instance RÉELLE d'OptionsMenu.gd, montée dans l'arbre (même patron que
## tests/ui/test_main_menu.gd `_menu()`) : `_ready()` construit les 5 pages
## sans appel réseau. Les méthodes préfixées `_` (`_open_crosshair_editor`,
## `_apply_preset`, …) sont appelées directement, comme d'autres suites du
## dépôt le font déjà (voir tests/ui/test_main_menu.gd, tête de fichier).
func _options_menu() -> Control:
	var m: Control = OPTIONS_MENU_SCRIPT.new()
	add_child(m)
	auto_free(m)
	return m


func test_options_menu_opens_the_crosshair_editor_from_its_viseur_page() -> void:
	var menu := _options_menu()
	await get_tree().process_frame
	menu._open_crosshair_editor()
	await get_tree().process_frame
	assert_object(menu._crosshair_editor).append_failure_message(
		"la page 'Viseur' d'OptionsMenu doit ouvrir CrosshairEditor.gd").is_not_null()


func test_crosshair_editor_builds_two_live_previews_matching_the_current_draft() -> void:
	# Acceptance UX-03 : "l'aperçu change en temps réel sur un fond ciel + un
	# fond sable" -- les DEUX nœuds Crosshair de l'aperçu doivent exister et
	# refléter EXACTEMENT le brouillon courant dès la construction.
	var menu := _options_menu()
	await get_tree().process_frame
	menu._open_crosshair_editor()
	await get_tree().process_frame
	var editor: Control = menu._crosshair_editor
	assert_object(editor._sky_crosshair).is_not_null()
	assert_object(editor._sand_crosshair).is_not_null()
	assert_dict(editor._sky_crosshair.settings).is_equal(editor._draft)
	assert_dict(editor._sand_crosshair.settings).is_equal(editor._draft)


func test_crosshair_editor_preset_button_updates_both_previews_in_real_time() -> void:
	var menu := _options_menu()
	await get_tree().process_frame
	menu._open_crosshair_editor()
	await get_tree().process_frame
	var editor: Control = menu._crosshair_editor
	editor._apply_preset("thick_cross")
	assert_dict(editor._draft).is_equal(Crosshair.PRESETS.thick_cross)
	assert_dict(editor._sky_crosshair.settings).append_failure_message(
		"l'aperçu 'ciel' doit suivre le préréglage en temps réel").is_equal(Crosshair.PRESETS.thick_cross)
	assert_dict(editor._sand_crosshair.settings).append_failure_message(
		"l'aperçu 'sable' doit suivre le préréglage en temps réel").is_equal(Crosshair.PRESETS.thick_cross)


func test_crosshair_editor_import_code_updates_both_previews() -> void:
	var menu := _options_menu()
	await get_tree().process_frame
	menu._open_crosshair_editor()
	await get_tree().process_frame
	var editor: Control = menu._crosshair_editor
	var imported := Crosshair.normalize_settings({"inner_gap": 22.0, "color": Color(0.1, 0.9, 0.4)})
	editor._code_field.text = Crosshair.encode(imported)
	editor._import_code()
	assert_dict(editor._draft).is_equal(imported)
	assert_dict(editor._sky_crosshair.settings).is_equal(imported)


func test_crosshair_editor_persists_the_draft_into_settings() -> void:
	var menu := _options_menu()
	await get_tree().process_frame
	menu._open_crosshair_editor()
	await get_tree().process_frame
	var editor: Control = menu._crosshair_editor
	editor._apply_preset("dot")
	assert_dict(Settings.crosshair_settings).append_failure_message(
		"CrosshairEditor doit écrire le brouillon dans Settings.crosshair_settings à chaque changement"
	).is_equal(Crosshair.PRESETS.dot)


func test_closing_the_crosshair_editor_clears_the_menu_reference() -> void:
	var menu := _options_menu()
	await get_tree().process_frame
	menu._open_crosshair_editor()
	await get_tree().process_frame
	menu._close_crosshair_editor()
	assert_object(menu._crosshair_editor).is_null()
