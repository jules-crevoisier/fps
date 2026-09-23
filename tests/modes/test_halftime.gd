## test_halftime.gd
## Spec (.orchestrator/maps-spec-v2.md §7.5/§8.18) : HalfTime.should_swap est
## PUR (aucune scène) — "the mode sets sides_swapped once, at 50% of the time
## limit or when the leader reaches half the score limit, whichever comes
## first". SpawnPick.safest (§7.6/§8.18) maximise la distance à l'ennemi
## vivant le plus proche, égalité départagée par le curseur (round-robin).
extends GdUnitTestSuite


func test_no_swap_before_half_time_or_half_score() -> void:
	assert_bool(HalfTime.should_swap(299.0, 600.0, 10, 10, 50)).is_false()


func test_swap_at_exactly_half_time_limit() -> void:
	assert_bool(HalfTime.should_swap(300.0, 600.0, 0, 0, 50)).is_true()
	assert_bool(HalfTime.should_swap(300.01, 600.0, 0, 0, 50)).is_true()


func test_swap_when_leader_reaches_half_score_limit() -> void:
	# Meneur (25) atteint la moitié de 50 bien avant la moitié du temps.
	assert_bool(HalfTime.should_swap(10.0, 600.0, 25, 3, 50)).is_true()
	assert_bool(HalfTime.should_swap(10.0, 600.0, 3, 25, 50)).is_true()


func test_no_swap_when_neither_condition_met() -> void:
	assert_bool(HalfTime.should_swap(10.0, 600.0, 3, 4, 50)).is_false()


func test_disabled_limits_never_trigger_that_branch() -> void:
	# limit_s <= 0 désactive la branche temps ; score_limit <= 0 désactive la
	# branche score (modes qui n'utilisent qu'un seul type de limite).
	assert_bool(HalfTime.should_swap(999999.0, 0.0, 0, 0, 50)).is_false()
	assert_bool(HalfTime.should_swap(0.0, 600.0, 999, 999, 0)).is_false()


func test_whichever_comes_first_time_then_score() -> void:
	# Le temps est déjà à moitié écoulé mais le score ne l'est pas -> vrai
	# quand même (l'un OU l'autre suffit, "whichever comes first").
	assert_bool(HalfTime.should_swap(300.0, 600.0, 1, 0, 50)).is_true()


# ----------------------------------------------------------------------
#  SpawnPick.safest (§7.6) — utilisé par GameWorld._get_spawn_position.
# ----------------------------------------------------------------------
func test_safest_picks_point_farthest_from_nearest_enemy() -> void:
	var points := [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(20, 0, 0)]
	var enemies := [Vector3(20, 0, 0)]
	# Point 0 est à 20 m du seul ennemi, point 1 à 10 m, point 2 à 0 m ->
	# le plus sûr est le point 0.
	assert_int(SpawnPick.safest(points, enemies, 0)).is_equal(0)


func test_safest_falls_back_to_cursor_with_no_enemies() -> void:
	var points := [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(20, 0, 0)]
	assert_int(SpawnPick.safest(points, [], 2)).is_equal(2)
	assert_int(SpawnPick.safest(points, [], 5)).is_equal(2)  # 5 % 3 == 2


func test_safest_falls_back_to_cursor_on_empty_points() -> void:
	assert_int(SpawnPick.safest([], [Vector3.ZERO], 3)).is_equal(0)


func test_safest_ties_break_to_cursor() -> void:
	# Deux points équidistants du seul ennemi (10 m chacun) -> égalité,
	# départagée par le curseur (round-robin stable), pas un choix arbitraire.
	var points := [Vector3(-10, 0, 0), Vector3(10, 0, 0)]
	var enemies := [Vector3(0, 0, 0)]
	assert_int(SpawnPick.safest(points, enemies, 0)).is_equal(0)
	assert_int(SpawnPick.safest(points, enemies, 1)).is_equal(1)


func test_safest_maximises_distance_to_nearest_of_several_enemies() -> void:
	var points := [Vector3(-20, 0, 0), Vector3(0, 0, 0), Vector3(20, 0, 0)]
	var enemies := [Vector3(-20, 0, 0), Vector3(20, 0, 0)]
	# Le point central (0) est à 20 m du plus proche ennemi de chaque côté ;
	# les points -20/20 sont à 0 m de LEUR propre côté -> le centre gagne.
	assert_int(SpawnPick.safest(points, enemies, 0)).is_equal(1)


# ----------------------------------------------------------------------
#  Wiring des modes (§7.5) : sides_swapped/asymmetric_map par défaut false
#  (comportement inchangé tant que MapSetup ne les positionne pas), et la
#  RPC de synchro met bien à jour l'état + la cartouche HUD séparée.
# ----------------------------------------------------------------------
func test_tdm_mode_defaults_to_not_asymmetric_not_swapped() -> void:
	var mode := TDMMode.new()
	auto_free(mode)
	assert_bool(mode.asymmetric_map).is_false()
	assert_bool(mode.sides_swapped).is_false()
	assert_str(mode.side_swap_notice).is_equal("")


func test_tdm_mode_sync_sides_swapped_updates_state() -> void:
	var mode := TDMMode.new()
	auto_free(mode)
	mode.sync_sides_swapped(true, "CHANGEMENT DE CÔTÉ")
	assert_bool(mode.sides_swapped).is_true()
	assert_str(mode.side_swap_notice).is_equal("CHANGEMENT DE CÔTÉ")


func test_hardpoint_mode_defaults_to_not_asymmetric_not_swapped() -> void:
	var mode := HardpointMode.new()
	auto_free(mode)
	assert_bool(mode.asymmetric_map).is_false()
	assert_bool(mode.sides_swapped).is_false()
	assert_str(mode.side_swap_notice).is_equal("")


func test_hardpoint_mode_sync_sides_swapped_updates_state() -> void:
	var mode := HardpointMode.new()
	auto_free(mode)
	mode.sync_sides_swapped(true, "CHANGEMENT DE CÔTÉ")
	assert_bool(mode.sides_swapped).is_true()
	assert_str(mode.side_swap_notice).is_equal("CHANGEMENT DE CÔTÉ")
