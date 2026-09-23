## test_bot_target_select.gd
## Spec (contract-r3.md, R3-IN#2) : choix de cible pure parmi des candidats
## déjà filtrés (ligne de vue/portée/audition) par l'appelant — la cible
## visible la plus proche gagne.
extends GdUnitTestSuite


func test_no_candidates_returns_minus_one() -> void:
	assert_int(BotTargetSelect.choose([])).is_equal(-1)


func test_picks_closest_candidate() -> void:
	var candidates := [
		{"id": 1, "distance": 20.0},
		{"id": 2, "distance": 5.0},
		{"id": 3, "distance": 12.0},
	]
	assert_int(BotTargetSelect.choose(candidates)).is_equal(2)


func test_single_candidate() -> void:
	assert_int(BotTargetSelect.choose([{"id": 42, "distance": 8.0}])).is_equal(42)


func test_ties_pick_first_seen() -> void:
	var candidates := [
		{"id": 7, "distance": 10.0},
		{"id": 8, "distance": 10.0},
	]
	assert_int(BotTargetSelect.choose(candidates)).is_equal(7)
