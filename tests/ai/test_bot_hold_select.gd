## test_bot_hold_select.gd
## Spec (tâche "bots humains", 2026-09-27, écart « ils courent partout dans la
## map ») : `BotHoldSelect.pick_hold_spot` choisit un point de TENUE parmi des
## spots `BotSpots` (Dictionary synthétiques ici, même schéma que
## `BotSpots.spots` — voir sa docstring) :
##  - seuls les spots À COUVERT (`BotSpots.is_covered`) qualifient ;
##  - seuls ceux dans la bande [MIN_RANGE_M, MAX_RANGE_M] de la position du
##    bot qualifient (ni collé, ni une traversée de carte) ;
##  - le spot tenu PRÉCÉDEMMENT (`exclude_pos`) est écarté, pour ne pas
##    reprendre aussitôt le même après une tenue ;
##  - `{"found": false}` si aucun spot ne qualifie.
## PUR (RefCounted, aucun accès scène) — testable avec des Dictionary à la
## main, sans bake réel ni NavigationRegion3D.
extends GdUnitTestSuite


## Un spot minimal, à couvert ou non — 8 entrées (BotSpots.DIRECTIONS.size())
## par tableau de couverture, une seule à `true` si `covered`.
func _spot(pos: Vector3, covered: bool) -> Dictionary:
	var crouch: Array = [false, false, false, false, false, false, false, false]
	var stand: Array = crouch.duplicate()
	if covered:
		crouch[0] = true
	return {
		"position": pos,
		"coverage_crouch": crouch,
		"coverage_stand": stand,
		"sniping": false,
		"approach_points": PackedVector3Array(),
	}


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_no_spots_returns_not_found() -> void:
	var result := BotHoldSelect.pick_hold_spot([], Vector3.ZERO, Vector3.INF, _rng(1))
	assert_bool(result.found).is_false()


func test_picks_the_only_qualifying_covered_spot_in_range() -> void:
	var spots := [_spot(Vector3(10, 0, 0), true)]
	var result := BotHoldSelect.pick_hold_spot(spots, Vector3.ZERO, Vector3.INF, _rng(1))
	assert_bool(result.found).is_true()
	assert_vector(result.pos).is_equal_approx(Vector3(10, 0, 0), Vector3(0.01, 0.01, 0.01))


func test_uncovered_spots_never_qualify() -> void:
	var spots := [_spot(Vector3(10, 0, 0), false)]
	var result := BotHoldSelect.pick_hold_spot(spots, Vector3.ZERO, Vector3.INF, _rng(1))
	assert_bool(result.found).is_false()


func test_spot_too_close_does_not_qualify() -> void:
	var spots := [_spot(Vector3(1, 0, 0), true)]  # sous MIN_RANGE_M (4 m).
	var result := BotHoldSelect.pick_hold_spot(spots, Vector3.ZERO, Vector3.INF, _rng(1))
	assert_bool(result.found).is_false()


func test_spot_too_far_does_not_qualify() -> void:
	var spots := [_spot(Vector3(100, 0, 0), true)]  # au-delà de MAX_RANGE_M (22 m).
	var result := BotHoldSelect.pick_hold_spot(spots, Vector3.ZERO, Vector3.INF, _rng(1))
	assert_bool(result.found).is_false()


func test_excludes_the_previously_held_spot() -> void:
	var spots := [_spot(Vector3(10, 0, 0), true)]
	var result := BotHoldSelect.pick_hold_spot(spots, Vector3.ZERO, Vector3(10, 0, 0), _rng(1))
	assert_bool(result.found).is_false()


func test_exclude_pos_infinite_excludes_nothing() -> void:
	var spots := [_spot(Vector3(10, 0, 0), true)]
	var result := BotHoldSelect.pick_hold_spot(spots, Vector3.ZERO, Vector3.INF, _rng(1))
	assert_bool(result.found).is_true()


func test_picks_among_several_qualifying_spots() -> void:
	var spots := [
		_spot(Vector3(10, 0, 0), true),
		_spot(Vector3(0, 0, 10), true),
		_spot(Vector3(-10, 0, 0), true),
	]
	var result := BotHoldSelect.pick_hold_spot(spots, Vector3.ZERO, Vector3.INF, _rng(7))
	assert_bool(result.found).is_true()
	var matches_one := false
	for s in spots:
		if (result.pos as Vector3).is_equal_approx(s.position):
			matches_one = true
	assert_bool(matches_one).append_failure_message(
		"le spot choisi doit être l'un des candidats qualifiants").is_true()


func test_ignores_covered_spots_outside_range_even_if_others_qualify() -> void:
	var spots := [
		_spot(Vector3(10, 0, 0), true),   # qualifie.
		_spot(Vector3(500, 0, 0), true),  # trop loin.
	]
	for _i in range(10):
		var result := BotHoldSelect.pick_hold_spot(spots, Vector3.ZERO, Vector3.INF, _rng(_i))
		assert_vector(result.pos).is_equal_approx(Vector3(10, 0, 0), Vector3(0.01, 0.01, 0.01))
