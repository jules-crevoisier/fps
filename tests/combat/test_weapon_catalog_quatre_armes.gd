## test_weapon_catalog_quatre_armes.gd
## Spec (tâche "quatre armes", 2026-09-28, contrat lead) : QUATRE nouvelles
## entrées append-only dans WeaponDatabase.PATHS (ids 2-5, dans cet ordre
## EXACT — B en dépend) : Rafale (SMG), Fracas (fusil à pompe), Verdict
## (carabine à levier), Aiguille (sniper à verrou). Noms EXACTS, catégories,
## stats-clés, et la table TTK calculée depuis les VRAIES valeurs .tres (pas
## des configs de test isolées, contrairement à test_weapon_math.gd) —
## fichier DÉDIÉ, ne modifie aucun test existant (test_weapon_database.gd
## reste intact).
extends GdUnitTestSuite

const RAFALE_ID := 2
const FRACAS_ID := 3
const VERDICT_ID := 4
const AIGUILLE_ID := 5

const BODY_HP := 100.0


func test_four_new_weapons_appended_in_order_after_ravage_and_revolver() -> void:
	assert_int(WeaponDatabase.PATHS.size()).is_equal(6)
	assert_str(WeaponDatabase.get_by_id(RAFALE_ID).weapon_name).is_equal("Rafale")
	assert_str(WeaponDatabase.get_by_id(FRACAS_ID).weapon_name).is_equal("Fracas")
	assert_str(WeaponDatabase.get_by_id(VERDICT_ID).weapon_name).is_equal("Verdict")
	assert_str(WeaponDatabase.get_by_id(AIGUILLE_ID).weapon_name).is_equal("Aiguille")


func test_rafale_is_an_smg_with_contract_stats() -> void:
	var c := WeaponDatabase.get_by_name("Rafale")
	assert_object(c).is_not_null()
	assert_int(c.category).is_equal(WeaponConfig.Category.SMG)
	assert_bool(c.automatic).is_true()
	assert_float(c.fire_rate).is_equal_approx(14.0, 0.001)
	assert_float(c.damage).is_equal_approx(18.0, 0.001)
	assert_float(c.damage_min).is_equal_approx(11.0, 0.001)
	assert_float(c.falloff_start).is_equal_approx(10.0, 0.001)
	assert_float(c.falloff_end).is_equal_approx(25.0, 0.001)
	assert_float(c.headshot_mult).is_equal_approx(1.5, 0.001)
	assert_int(c.mag_size).is_equal(32)
	assert_float(c.spread_hip).is_equal_approx(1.6, 0.001)
	assert_float(c.spread_aim).is_equal_approx(0.7, 0.001)
	assert_float(c.ads_time).is_equal_approx(0.15, 0.001)
	assert_float(c.cycle_time).is_equal_approx(0.0, 0.0001)
	assert_bool(c.reload_per_round).is_false()


func test_fracas_is_a_pump_shotgun_with_contract_stats() -> void:
	var c := WeaponDatabase.get_by_name("Fracas")
	assert_object(c).is_not_null()
	assert_int(c.category).is_equal(WeaponConfig.Category.SHOTGUN)
	assert_bool(c.automatic).is_false()
	assert_int(c.pellets).is_equal(9)
	assert_float(c.damage).is_equal_approx(12.0, 0.001)
	assert_float(c.damage_min).is_equal_approx(3.0, 0.001)
	assert_float(c.falloff_start).is_equal_approx(6.0, 0.001)
	assert_float(c.falloff_end).is_equal_approx(16.0, 0.001)
	assert_float(c.headshot_mult).is_equal_approx(1.25, 0.001)
	assert_float(c.pellet_spread).is_equal_approx(5.5, 0.001)
	assert_float(c.pellet_spread_aim).is_equal_approx(4.0, 0.001)
	assert_int(c.mag_size).is_equal(6)
	assert_float(c.cycle_time).is_equal_approx(0.9, 0.001)
	assert_bool(c.reload_per_round).is_true()
	assert_float(c.reload_start_time).is_equal_approx(0.3, 0.001)
	assert_float(c.reload_round_time).is_equal_approx(0.45, 0.001)


func test_verdict_is_a_lever_carbine_with_contract_stats() -> void:
	var c := WeaponDatabase.get_by_name("Verdict")
	assert_object(c).is_not_null()
	assert_int(c.category).is_equal(WeaponConfig.Category.RIFLE)
	assert_bool(c.automatic).is_false()
	assert_float(c.damage).is_equal_approx(50.0, 0.001)
	assert_float(c.damage_min).is_equal_approx(38.0, 0.001)
	assert_float(c.falloff_start).is_equal_approx(30.0, 0.001)
	assert_float(c.falloff_end).is_equal_approx(60.0, 0.001)
	assert_float(c.headshot_mult).is_equal_approx(2.0, 0.001)
	assert_float(c.cycle_time).is_equal_approx(0.45, 0.001)
	assert_int(c.mag_size).is_equal(8)
	assert_bool(c.reload_per_round).is_true()
	assert_float(c.reload_start_time).is_equal_approx(0.3, 0.001)
	assert_float(c.reload_round_time).is_equal_approx(0.4, 0.001)
	assert_float(c.spread_hip).is_equal_approx(1.0, 0.001)
	assert_float(c.spread_aim).is_equal_approx(0.05, 0.001)
	assert_float(c.aim_fov).is_equal_approx(50.0, 0.001)
	assert_float(c.ads_time).is_equal_approx(0.2, 0.001)


func test_aiguille_is_a_bolt_sniper_with_contract_stats() -> void:
	var c := WeaponDatabase.get_by_name("Aiguille")
	assert_object(c).is_not_null()
	assert_int(c.category).is_equal(WeaponConfig.Category.SNIPER)
	assert_bool(c.scoped).is_true()
	assert_float(c.damage).is_equal_approx(80.0, 0.001)
	# "damage 80 flat (no falloff)" -- damage_min == damage, jamais de chute.
	assert_float(c.damage_min).is_equal_approx(80.0, 0.001)
	assert_float(c.headshot_mult).is_equal_approx(2.0, 0.001)
	assert_int(c.mag_size).is_equal(5)
	assert_float(c.reload_time).is_equal_approx(2.6, 0.001)
	assert_bool(c.reload_per_round).append_failure_message(
		"reload 2.6 s (WHOLE MAG) -- pas un rechargement par cartouche"
	).is_false()
	assert_float(c.cycle_time).is_equal_approx(1.2, 0.001)
	assert_float(c.aim_fov).is_equal_approx(25.0, 0.001)
	assert_float(c.ads_time).is_equal_approx(0.28, 0.001)
	assert_float(c.spread_hip).is_equal_approx(6.0, 0.001)
	# "scoped spread 0 once ADS completes" -- spread_aim nul.
	assert_float(c.spread_aim).is_equal_approx(0.0, 0.0001)


func test_no_maker_names_appear_in_any_new_weapon_name() -> void:
	for name in ["Rafale", "Fracas", "Verdict", "Aiguille"]:
		var c := WeaponDatabase.get_by_name(name)
		assert_object(c).is_not_null()
		assert_str(c.weapon_name.to_lower()).not_contains("têtard")
		assert_str(c.weapon_name.to_lower()).not_contains("marécage")


# ---------------------------------------------------------------- TTK (calculée depuis les .tres réels)
# "Body TTK close ≈ 0.36 s (6 hits)".
func test_rafale_body_ttk_close_range_matches_contract() -> void:
	var c := WeaponDatabase.get_by_name("Rafale")
	var shots := WeaponMath.shots_to_kill(c, 5.0, BODY_HP, false)
	assert_int(shots).is_equal(6)
	assert_float(WeaponMath.ttk_ms(c, 5.0, BODY_HP, false)).is_equal_approx(357.14, 1.0)


# "All 9 pellets on body at ≤6 m = kill" -- un seul tir.
func test_fracas_all_pellets_on_body_within_six_meters_is_a_one_shot_kill() -> void:
	var c := WeaponDatabase.get_by_name("Fracas")
	var dmg := WeaponMath.shot_damage(c, 5.0, false)
	assert_float(dmg).is_greater_equal(BODY_HP)
	assert_int(WeaponMath.shots_to_kill(c, 5.0, BODY_HP, false)).is_equal(1)


# "2 body hits kill inside falloff_start" (30 m).
func test_verdict_two_body_hits_kill_inside_falloff_start() -> void:
	var c := WeaponDatabase.get_by_name("Verdict")
	assert_int(WeaponMath.shots_to_kill(c, 20.0, BODY_HP, false)).is_equal(2)


# "head x2.0 (=160, one-shot), body 2 hits".
func test_aiguille_headshot_is_always_a_one_shot_kill_at_any_range() -> void:
	var c := WeaponDatabase.get_by_name("Aiguille")
	for dist in [0.0, 50.0, 150.0, 500.0]:
		assert_float(WeaponMath.shot_damage(c, dist, true)).is_equal_approx(160.0, 0.001)
		assert_int(WeaponMath.shots_to_kill(c, dist, BODY_HP, true)).is_equal(1)


func test_aiguille_body_shot_needs_exactly_two_hits_at_any_range() -> void:
	var c := WeaponDatabase.get_by_name("Aiguille")
	for dist in [0.0, 50.0, 150.0, 500.0]:
		assert_float(WeaponMath.shot_damage(c, dist, false)).is_equal_approx(80.0, 0.001)
		assert_int(WeaponMath.shots_to_kill(c, dist, BODY_HP, false)).is_equal(2)
