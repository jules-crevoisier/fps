## test_roster_padding.gd
## Spec (brief lead 2026-09-27, HeroesScreen) : la grille reste 2×2 (4 cartes)
## même avec un seul agent réel (AgentDatabase, prototype) — le reste verrouillé
## "Bientôt".
extends GdUnitTestSuite

const RosterPadding := preload("res://scripts/ui/menu/RosterPadding.gd")


func test_pads_a_single_real_agent_to_four() -> void:
	var out := RosterPadding.pad(["Verrou"], 4)
	assert_int(out.size()).is_equal(4)
	assert_str(out[0]["name"]).is_equal("Verrou")
	assert_bool(out[0]["locked"]).is_false()
	for i in range(1, 4):
		assert_bool(out[i]["locked"]).is_true()
		assert_str(out[i]["name"]).is_equal("")


func test_noop_when_already_at_count() -> void:
	var out := RosterPadding.pad(["A", "B", "C", "D"], 4)
	assert_int(out.size()).is_equal(4)
	for e in out:
		assert_bool(e["locked"]).is_false()


func test_never_shrinks_below_count() -> void:
	var out := RosterPadding.pad(["A", "B", "C", "D", "E"], 4)
	assert_int(out.size()).is_equal(5)


func test_empty_roster_is_all_locked() -> void:
	var out := RosterPadding.pad([], 4)
	assert_int(out.size()).is_equal(4)
	for e in out:
		assert_bool(e["locked"]).is_true()
