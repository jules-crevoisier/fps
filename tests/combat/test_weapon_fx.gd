## test_weapon_fx.gd
## Spec (contract-r2.md, R-A2) : logique PURE ajoutée pour le ViewModel (recul
## ressort, sway souris, bob, dip de rechargement, montée d'équipement, flash
## au canon) et pour Weapon.gd (résolution du chemin du modèle 3D). Toute la
## physique/animation vit dans ViewModel.AnimState (RefCounted, sans arbre de
## scène) pour être testable ici sans instancier de Node3D.
extends GdUnitTestSuite

const DT := 1.0 / 60.0


# ---------------------------------------------------------------- Recul (spring)
func test_recoil_kicks_away_from_rest_then_returns() -> void:
	var s := ViewModel.AnimState.new()
	s.kick_recoil(Vector3(0, 1.0, 0))
	for i in 3:
		s.tick_recoil(DT)
	var after_kick := s.recoil_offset.y
	assert_bool(after_kick > 0.0).is_true()
	for i in 120:  # ~2 s : le ressort doit être quasi revenu au repos
		s.tick_recoil(DT)
	assert_float(s.recoil_offset.y).is_less(0.01)


func test_recoil_accumulates_on_repeated_kicks() -> void:
	var s := ViewModel.AnimState.new()
	s.kick_recoil(Vector3(0, 1.0, 0))
	s.tick_recoil(DT)
	var one_kick := s.recoil_offset.y
	s.kick_recoil(Vector3(0, 1.0, 0))
	s.tick_recoil(DT)
	assert_float(s.recoil_offset.y).is_greater(one_kick)


# ---------------------------------------------------------------- Sway (mouse-lag)
func test_sway_moves_toward_target_then_decays_to_zero_when_still() -> void:
	var s := ViewModel.AnimState.new()
	for i in 10:
		s.tick_sway(Vector2(200, 0), DT)
	assert_float(absf(s.sway_offset.x)).is_greater(0.0)
	for i in 120:
		s.tick_sway(Vector2.ZERO, DT)
	assert_float(absf(s.sway_offset.x)).is_less(0.001)


func test_sway_is_clamped() -> void:
	var s := ViewModel.AnimState.new()
	for i in 200:
		s.tick_sway(Vector2(100000, 100000), DT)
	assert_float(absf(s.sway_offset.x)).is_less_equal(ViewModel.AnimState.SWAY_MAX + 0.0001)
	assert_float(absf(s.sway_offset.y)).is_less_equal(ViewModel.AnimState.SWAY_MAX + 0.0001)


# ---------------------------------------------------------------- Bob (walk/sprint)
func test_bob_is_flat_when_not_moving() -> void:
	var s := ViewModel.AnimState.new()
	var off := Vector3.ZERO
	for i in 30:
		off = s.tick_bob(0.0, 8.0, DT)
	assert_vector(off).is_equal(Vector3.ZERO)


func test_bob_oscillates_when_moving() -> void:
	var s := ViewModel.AnimState.new()
	var seen_positive := false
	var seen_negative := false
	for i in 120:
		var off := s.tick_bob(8.0, 8.0, DT)
		if off.y > 0.001:
			seen_positive = true
		if off.y < -0.001:
			seen_negative = true
	assert_bool(seen_positive).is_true()
	assert_bool(seen_negative).is_true()


# ---------------------------------------------------------------- Reload dip
func test_reload_dip_returns_to_zero_after_duration() -> void:
	var s := ViewModel.AnimState.new()
	s.start_reload(0.5)
	var mid := s.tick_reload(0.25)
	assert_float(mid.y).is_less(0.0)  # arme qui descend pendant le rechargement
	var last := Vector3.ZERO
	for i in 20:  # dépasse largement les 0.5 s restantes
		last = s.tick_reload(DT)
	assert_vector(last).is_equal(Vector3.ZERO)


func test_reload_dip_is_zero_when_not_reloading() -> void:
	var s := ViewModel.AnimState.new()
	assert_vector(s.tick_reload(DT)).is_equal(Vector3.ZERO)


# ---------------------------------------------------------------- Equip rise
func test_equip_rise_starts_low_and_settles_to_zero() -> void:
	var s := ViewModel.AnimState.new()
	s.start_equip()
	var early := s.tick_equip(0.01)
	assert_float(early.y).is_less(0.0)  # commence sous sa position finale
	var last := Vector3.ZERO
	for i in 60:
		last = s.tick_equip(DT)
	assert_vector(last).is_equal(Vector3.ZERO)


# ---------------------------------------------------------------- Muzzle flash (~50 ms)
func test_muzzle_flash_visible_then_expires() -> void:
	var s := ViewModel.AnimState.new()
	assert_bool(s.is_muzzle_visible()).is_false()
	s.trigger_muzzle_flash()
	assert_bool(s.is_muzzle_visible()).is_true()
	s.tick_muzzle(0.03)
	assert_bool(s.is_muzzle_visible()).is_true()
	s.tick_muzzle(0.03)  # total 0.06 s > MUZZLE_DUR (~0.05 s)
	assert_bool(s.is_muzzle_visible()).is_false()


# ---------------------------------------------------------------- Blends (ADS / sprint / slide)
func test_ads_blend_moves_toward_zero_when_aiming() -> void:
	var s := ViewModel.AnimState.new()
	var v := s.ads_blend(true, 1.0, DT)
	assert_float(v).is_less(1.0)
	assert_float(v).is_greater_equal(0.0)


func test_ads_blend_moves_toward_one_when_not_aiming() -> void:
	var s := ViewModel.AnimState.new()
	var v := s.ads_blend(false, 0.0, DT)
	assert_float(v).is_greater(0.0)


func test_sprint_pose_blend_reaches_target_over_time() -> void:
	var s := ViewModel.AnimState.new()
	var v := 0.0
	for i in 60:
		v = s.sprint_pose_blend(true, v, DT)
	assert_float(v).is_equal_approx(1.0, 0.01)


# ---------------------------------------------------------------- Weapon.model_path_for
func test_model_path_for_matches_weapon_database_stem() -> void:
	var id := WeaponDatabase.id_of(WeaponDatabase.get_by_name("Ravage"))
	assert_str(Weapon.model_path_for(id)).is_equal("res://assets/models/weapons/ravage.glb")


func test_model_path_for_out_of_range_is_empty() -> void:
	assert_str(Weapon.model_path_for(-1)).is_equal("")
	assert_str(Weapon.model_path_for(9999)).is_equal("")
