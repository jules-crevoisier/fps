## test_death_screen.gd
## Spec (contrat lead 2026-09-27, "DEATH SCREEN") : affiché à la mort du joueur
## LOCAL (Health.died), masqué au respawn (Health.respawned) -- éclat "K.O. !",
## carte du tueur (nom, arme + tir à la tête si applicable, PV restants du
## tueur SI fiable), anneau de compte à rebours (respawn_delay), astuce
## tournante parmi 6, repli "L'ENVIRONNEMENT" sans ligne d'arme pour un
## suicide/environnement (killer_id <= 0, GameWorld._record_kill : "killer_id
## > 0" -- même convention que Health.apply_damage "0 = environnement").
extends GdUnitTestSuite

const DeathScreen := preload("res://scripts/ui/hud/DeathScreen.gd")


func _screen() -> DeathScreen:
	var d: DeathScreen = auto_free(DeathScreen.new())
	add_child(d)
	return d


# ---- is_environment_death / killer_display_name (pure) ----

func test_is_environment_death_for_zero_or_negative_id() -> void:
	assert_bool(DeathScreen.is_environment_death(0)).is_true()
	assert_bool(DeathScreen.is_environment_death(-1)).is_true()


func test_is_environment_death_false_for_a_real_peer() -> void:
	assert_bool(DeathScreen.is_environment_death(9003)).is_false()


func test_killer_display_name_environment_fallback() -> void:
	assert_str(DeathScreen.killer_display_name(0, "")).is_equal("L'ENVIRONNEMENT")


func test_killer_display_name_uses_the_real_name() -> void:
	assert_str(DeathScreen.killer_display_name(9003, "Crapaud")).is_equal("Crapaud")


# ---- killer_line (pure) ----

func test_killer_line_appends_headshot_suffix() -> void:
	assert_str(DeathScreen.killer_line("REVOLVER", true)).is_equal("REVOLVER · TIR À LA TÊTE")


func test_killer_line_without_headshot() -> void:
	assert_str(DeathScreen.killer_line("RAVAGE", false)).is_equal("RAVAGE")


# ---- killer_hp_line (pure) ----

func test_killer_hp_line_formats_rounded_integer_pv() -> void:
	assert_str(DeathScreen.killer_hp_line(45.4)).is_equal("Il lui restait 45 PV")


# ---- countdown_seconds / ring_fill_ratio (pure) ----

func test_countdown_seconds_starts_at_the_full_delay() -> void:
	assert_int(DeathScreen.countdown_seconds(0.0, 3.0)).is_equal(3)


func test_countdown_seconds_counts_down() -> void:
	assert_int(DeathScreen.countdown_seconds(2.5, 3.0)).is_equal(1)


func test_countdown_seconds_never_negative() -> void:
	assert_int(DeathScreen.countdown_seconds(10.0, 3.0)).is_equal(0)


func test_ring_fill_ratio_starts_full() -> void:
	assert_float(DeathScreen.ring_fill_ratio(0.0, 3.0)).is_equal_approx(1.0, 0.001)


func test_ring_fill_ratio_empties_over_time() -> void:
	assert_float(DeathScreen.ring_fill_ratio(1.5, 3.0)).is_equal_approx(0.5, 0.001)


func test_ring_fill_ratio_never_goes_below_zero() -> void:
	assert_float(DeathScreen.ring_fill_ratio(10.0, 3.0)).is_equal_approx(0.0, 0.001)


func test_ring_fill_ratio_zero_delay_is_defensive() -> void:
	assert_float(DeathScreen.ring_fill_ratio(1.0, 0.0)).is_equal_approx(0.0, 0.001)


# ---- tip_for (pure, 6 astuces vérifiées contre le code) ----

func test_tip_list_has_exactly_six_entries() -> void:
	assert_int(DeathScreen.TIPS.size()).is_equal(6)


func test_tip_for_cycles_round_robin() -> void:
	var first := DeathScreen.tip_for(0)
	assert_str(DeathScreen.tip_for(6)).is_equal(first)


func test_tip_for_is_never_empty() -> void:
	for i in 6:
		assert_str(DeathScreen.tip_for(i)).is_not_empty()


# ---- nœuds ----

func test_hidden_by_default() -> void:
	var d := _screen()
	assert_bool(d.visible).is_false()


func test_show_death_makes_it_visible() -> void:
	var d := _screen()
	d.show_death("Crapaud", false, "REVOLVER", true, 45.0, true, 3.0)
	assert_bool(d.visible).is_true()


func test_show_death_sets_killer_name_and_weapon_line() -> void:
	var d := _screen()
	d.show_death("Crapaud", false, "REVOLVER", true, 45.0, true, 3.0)
	assert_str(d._killer_name_label.text).is_equal("Crapaud")
	assert_str(d._weapon_label.text).is_equal("REVOLVER · TIR À LA TÊTE")
	assert_bool(d._weapon_label.visible).is_true()
	assert_str(d._hp_label.text).is_equal("Il lui restait 45 PV")
	assert_bool(d._hp_label.visible).is_true()


func test_show_death_hides_hp_line_when_not_reliably_known() -> void:
	var d := _screen()
	d.show_death("Crapaud", false, "REVOLVER", false, 0.0, false, 3.0)
	assert_bool(d._hp_label.visible).append_failure_message(
		"la ligne de PV du tueur ne doit s'afficher que si elle est fiable"
	).is_false()


func test_show_death_environment_hides_weapon_line() -> void:
	var d := _screen()
	d.show_death("L'ENVIRONNEMENT", true, "", false, 0.0, false, 3.0)
	assert_str(d._killer_name_label.text).is_equal("L'ENVIRONNEMENT")
	assert_bool(d._weapon_label.visible).append_failure_message(
		"un suicide/environnement ne montre aucune ligne d'arme"
	).is_false()


func test_hide_death_hides_the_screen() -> void:
	var d := _screen()
	d.show_death("Crapaud", false, "REVOLVER", true, 45.0, true, 3.0)
	d.hide_death()
	assert_bool(d.visible).is_false()


func test_show_death_advances_the_tip_round_robin() -> void:
	var d := _screen()
	d.show_death("Crapaud", false, "REVOLVER", true, 45.0, true, 3.0)
	var first_tip := d._tip_label.text
	d.hide_death()
	d.show_death("Crapaud", false, "REVOLVER", true, 45.0, true, 3.0)
	var second_tip := d._tip_label.text
	assert_str(second_tip).is_not_equal(first_tip)


# ======================================================================
#  LOADOUT SELECTION (contrat lead 2026-09-28, "DEATH SCREEN" point 4) —
#  rangée pour changer la primaire du PROCHAIN respawn, choix persisté +
#  surlignage de la primaire ACTUELLEMENT retenue.
# ======================================================================

func _with_saved_selected_primary(callback: Callable) -> void:
	# Settings.selected_primary est un STATIC partagé par toute la suite
	# headless (même précaution que tests/core/test_settings.gd::_snapshot/
	# _restore) -- restauré après le test, jamais laissé fuiter.
	var before := Settings.selected_primary
	callback.call()
	Settings.selected_primary = before


func test_primary_picker_has_one_button_per_primary_in_locked_order() -> void:
	var d := _screen()
	assert_int(d._picker_buttons.size()).is_equal(Loadout.PRIMARY_NAMES.size())
	for i in Loadout.PRIMARY_NAMES.size():
		assert_str(d._picker_buttons[i]["name"]).is_equal(Loadout.PRIMARY_NAMES[i])


func test_primary_picker_highlights_the_currently_persisted_default() -> void:
	_with_saved_selected_primary(func() -> void:
		Settings.selected_primary = "Fracas"
		var d := _screen()
		for entry in d._picker_buttons:
			var btn: Button = entry["button"]
			var sb := btn.get_theme_stylebox("normal") as StyleBoxComic
			var expected_fill := UiTokens.YELLOW if entry["name"] == "Fracas" else UiTokens.PAPER
			assert_bool(sb.fill.is_equal_approx(expected_fill)).append_failure_message(
				"%s : surlignage jaune attendu seulement sur la primaire persistée" % entry["name"]
			).is_true()
	)


func test_picking_a_primary_persists_it_as_the_new_default() -> void:
	_with_saved_selected_primary(func() -> void:
		var d := _screen()
		d._on_primary_picked("Verdict")
		assert_str(Settings.selected_primary).is_equal("Verdict")
	)


func test_show_death_refreshes_the_picker_highlight() -> void:
	_with_saved_selected_primary(func() -> void:
		var d := _screen()
		Settings.selected_primary = "Aiguille"  # changé APRÈS la construction de l'écran.
		d.show_death("Crapaud", false, "REVOLVER", true, 45.0, true, 3.0)
		for entry in d._picker_buttons:
			if entry["name"] == "Aiguille":
				var btn: Button = entry["button"]
				var sb := btn.get_theme_stylebox("normal") as StyleBoxComic
				assert_bool(sb.fill.is_equal_approx(UiTokens.YELLOW)).append_failure_message(
					"show_death doit resurligner la primaire persistée MÊME si elle a changé depuis la construction"
				).is_true()
	)


# ======================================================================
#  Retour de test 2026-09-28 : « on ne peut pas changer d'arme, il n'y a pas
#  la souris » -- souris libérée pendant la mort, touches 1 à 5 en plus.
# ======================================================================

func _key(keycode: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = true
	return e


func test_number_key_picks_the_matching_primary_while_dead() -> void:
	_with_saved_selected_primary(func() -> void:
		Settings.selected_primary = "Ravage"
		var d := _screen()
		d.visible = true
		d._unhandled_input(_key(KEY_4))
		assert_str(Settings.selected_primary).is_equal(Loadout.PRIMARY_NAMES[3])
	)


func test_number_keys_do_nothing_while_the_screen_is_hidden() -> void:
	_with_saved_selected_primary(func() -> void:
		Settings.selected_primary = "Ravage"
		var d := _screen()
		d.visible = false
		d._unhandled_input(_key(KEY_2))
		assert_str(Settings.selected_primary).is_equal("Ravage")
	)


func test_mouse_is_released_only_if_it_was_captured() -> void:
	assert_int(DeathScreen.mouse_mode_for_picker(Input.MOUSE_MODE_CAPTURED)).is_equal(Input.MOUSE_MODE_VISIBLE)
	assert_int(DeathScreen.mouse_mode_for_picker(Input.MOUSE_MODE_VISIBLE)).is_equal(Input.MOUSE_MODE_VISIBLE)
