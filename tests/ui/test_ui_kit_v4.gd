## test_ui_kit_v4.gd
## Spec UX-30 (contrat, docs/UI_DIRECTION_BL3.md) : les deux nouveaux
## composants du kit v4 « Encre, jaune, italique » — KitSlantTile (tuile
## penchée 12°, exactement 6 états) et KitSwash (pinceau jaune derrière UN
## titre choisi, règle « 1 par écran »).
extends GdUnitTestSuite


# ===========================================================================
# KitSlantTile — 6 états (normal/hover/focus/pressed/disabled/selected)
# ===========================================================================

func _make_tile() -> KitSlantTile:
	var t := KitSlantTile.new()
	add_child(t)
	auto_free(t)
	return t


func test_tile_states_are_exactly_the_six_states_of_the_contract() -> void:
	var expected: Array[int] = [
		KitStates.State.DEFAULT, KitStates.State.HOVER, KitStates.State.FOCUS,
		KitStates.State.PRESSED, KitStates.State.DISABLED, KitStates.State.SELECTED,
	]
	assert_int(KitSlantTile.TILE_STATES.size()).is_equal(6)
	for i in expected.size():
		assert_int(KitSlantTile.TILE_STATES[i]).is_equal(expected[i])


func test_tile_defaults_to_the_default_state() -> void:
	var t := _make_tile()
	assert_int(t.current_state()).is_equal(KitStates.State.DEFAULT)


func test_tile_state_override_forces_each_of_the_six_states() -> void:
	var t := _make_tile()
	for state in KitSlantTile.TILE_STATES:
		t.state_override = state
		assert_int(t.current_state()).is_equal(state)


func test_tile_state_override_outside_the_six_states_is_ignored() -> void:
	# LOADING/EMPTY/ERROR ne s'appliquent pas à une tuile de capacité (voir
	# la docstring de KitSlantTile.gd) : `state_override` hors de
	# `TILE_STATES` retombe sur l'état RÉEL, jamais un état hors périmètre.
	var t := _make_tile()
	t.state_override = KitStates.State.LOADING
	assert_int(t.current_state()).is_equal(KitStates.State.DEFAULT)
	t.disabled = true
	t.state_override = KitStates.State.EMPTY
	assert_int(t.current_state()).is_equal(KitStates.State.DISABLED)


func test_tile_disabled_takes_priority_over_selected() -> void:
	var t := _make_tile()
	t.selected = true
	t.disabled = true
	assert_int(t.current_state()).is_equal(KitStates.State.DISABLED)


func test_tile_set_disabled_with_reason_sets_both_fields() -> void:
	# CHK-37 "disabled_reason_required" : jamais un contrôle désactivé sans
	# raison exposée.
	var t := _make_tile()
	t.set_disabled_with_reason("Rôle pris par BOT Alizé")
	assert_bool(t.disabled).is_true()
	assert_str(t.disabled_reason).is_equal("Rôle pris par BOT Alizé")
	assert_int(t.current_state()).is_equal(KitStates.State.DISABLED)


func test_tile_slant_shear_matches_a_single_12_degree_incline() -> void:
	# Même géométrie que KitSlantBar (CHK-38 : une seule inclinaison, 12° —
	# `Comic.SLANT_DEG`, tokens.json shape.slant_deg).
	var t := _make_tile()
	t.size = Vector2(88.0, 88.0)
	var pts := t._slant_points(Vector2.ZERO)
	var expected_shear := 88.0 * tan(deg_to_rad(Comic.SLANT_DEG))
	assert_int(pts.size()).is_equal(4)
	assert_float(pts[0].x).is_equal_approx(expected_shear, 0.01)
	assert_float(pts[0].y).is_equal_approx(0.0, 0.01)
	assert_float(pts[1].x).is_equal_approx(88.0 + expected_shear, 0.01)
	assert_float(pts[2].x).is_equal_approx(88.0, 0.01)
	assert_float(pts[2].y).is_equal_approx(88.0, 0.01)
	assert_float(pts[3].x).is_equal_approx(0.0, 0.01)
	assert_float(pts[3].y).is_equal_approx(88.0, 0.01)


func test_tile_selected_gets_the_large_hard_shadow_like_any_plate() -> void:
	# UI_DIRECTION_BL3.md §4.6 « choisi : ombre (6,6) » — la tuile choisie
	# porte la grande ombre dure de plaque, pas la petite ombre par défaut.
	# `reduced_motion` force le saut direct à la cible (sans tween ni attente
	# de frame, même parti que test_reduced_motion_reflects_settings dans
	# test_comic_tokens.gd) : le test vérifie la CIBLE, pas l'animation.
	var before := Settings.reduced_motion
	Settings.reduced_motion = true
	var t := _make_tile()
	t.size = Vector2(88.0, 88.0)
	t.state_override = KitStates.State.SELECTED
	assert_that(t._shadow_off).is_equal(Comic.SHADOW_HARD_OFFSET)
	Settings.reduced_motion = before


func test_tile_key_label_and_title_are_stored() -> void:
	var t := _make_tile()
	t.key_label = "E"
	t.tile_title = "Voile"
	assert_str(t.key_label).is_equal("E")
	assert_str(t.tile_title).is_equal("Voile")


# ===========================================================================
# KitSwash — pinceau jaune derrière UN titre choisi, « 1 par écran »
# ===========================================================================

func test_swash_wrap_places_the_swash_behind_the_label_it_wraps() -> void:
	# « Derrière » vient UNIQUEMENT de l'ordre dans l'arbre (voir la
	# docstring de KitSwash.gd) — PAS d'un z_index négatif, qui ordonnerait
	# tout le canvas et repasserait le swash derrière un fond opaque sans
	# rapport (piège vérifié en capture, UX-30).
	var lbl := Comic.title_label_v4("VIF")
	var host := KitSwash.wrap(lbl)
	add_child(host)
	auto_free(host)

	assert_int(host.get_child_count()).is_equal(2)
	assert_object(host.get_child(0)).is_instanceof(KitSwash)
	assert_object(host.get_child(1)).is_same(lbl)
	assert_int((host.get_child(0) as KitSwash).z_index).is_equal(0)


func test_swash_ragged_rect_wraps_the_full_size_with_a_jagged_outline() -> void:
	var s := KitSwash.new()
	add_child(s)
	auto_free(s)
	s.size = Vector2(200.0, 60.0)
	var pts := s._ragged_rect()
	assert_int(pts.size()).is_equal(18)  # 9 points aller (haut) + 9 points retour (bas)
	for p in pts:
		assert_float(p.x).is_between(-1.0, 201.0)


func test_swash_counts_simultaneously_visible_instances_and_decrements_on_removal() -> void:
	# Règle « 1 par écran » (tokens.json shape.swash.max_per_screen,
	# UI_DIRECTION_BL3.md §4.5) : le compteur avertit sans jamais bloquer —
	# ce test vérifie le comptage lui-même (incrément/décrément), pas
	# l'avertissement (push_warning n'est pas observable depuis gdUnit4 sans
	# capturer stderr).
	var baseline := KitSwash._visible_count
	var a := KitSwash.new()
	var b := KitSwash.new()
	add_child(a)
	add_child(b)
	assert_int(KitSwash._visible_count).is_equal(baseline + 2)

	remove_child(a)
	a.free()
	assert_int(KitSwash._visible_count).is_equal(baseline + 1)

	remove_child(b)
	b.free()
	assert_int(KitSwash._visible_count).is_equal(baseline)
