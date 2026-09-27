## test_match_mode_catalog.gd
## Spec (brief lead 2026-09-27, MainMenu/HomeScreen) : les 4 cartes de mode de
## l'accueil sont des PRÉRÉGLAGES sur l'unique mode MatchConfig ("tdm") — jamais
## de mode_id inventé. "Rejoindre / héberger" n'a pas de config locale.
extends GdUnitTestSuite

const MatchModeCatalog := preload("res://scripts/ui/menu/MatchModeCatalog.gd")


func test_four_presets_in_mockup_order() -> void:
	assert_int(MatchModeCatalog.PRESETS.size()).is_equal(4)
	assert_str(MatchModeCatalog.PRESETS[0]["id"]).is_equal(MatchModeCatalog.TDM)
	assert_str(MatchModeCatalog.PRESETS[1]["id"]).is_equal(MatchModeCatalog.DUEL)
	assert_str(MatchModeCatalog.PRESETS[2]["id"]).is_equal(MatchModeCatalog.TRAINING)
	assert_str(MatchModeCatalog.PRESETS[3]["id"]).is_equal(MatchModeCatalog.JOIN_HOST)


func test_tdm_preset_is_4v4_veteran() -> void:
	var p := MatchModeCatalog.params_for(MatchModeCatalog.TDM)
	assert_str(p["mode_id"]).is_equal("tdm")
	assert_int(p["team_size"]).is_equal(4)
	assert_int(p["bot_difficulty"]).is_equal(MatchConfig.Difficulty.VETERAN)


func test_duel_preset_is_1v1() -> void:
	var p := MatchModeCatalog.params_for(MatchModeCatalog.DUEL)
	assert_int(p["team_size"]).is_equal(1)


func test_training_preset_uses_easiest_difficulty() -> void:
	var p := MatchModeCatalog.params_for(MatchModeCatalog.TRAINING)
	assert_int(p["bot_difficulty"]).is_equal(MatchConfig.Difficulty.RECRUE)
	assert_int(p["team_size"]).is_equal(4)


func test_join_host_has_no_local_params() -> void:
	assert_bool(MatchModeCatalog.params_for(MatchModeCatalog.JOIN_HOST).is_empty()).is_true()
	assert_bool(MatchModeCatalog.is_join_host(MatchModeCatalog.JOIN_HOST)).is_true()
	assert_bool(MatchModeCatalog.is_join_host(MatchModeCatalog.TDM)).is_false()


func test_unknown_preset_has_no_params() -> void:
	assert_bool(MatchModeCatalog.params_for("nope").is_empty()).is_true()


func test_index_of() -> void:
	assert_int(MatchModeCatalog.index_of(MatchModeCatalog.DUEL)).is_equal(1)
	assert_int(MatchModeCatalog.index_of("nope")).is_equal(-1)
