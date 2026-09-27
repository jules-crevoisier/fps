## test_match_launcher.gd
## Spec (brief lead 2026-09-27, MatchLauncher.gd) : `configure_local` applique
## une config de partie locale à MatchConfig, pure (aucun réseau, aucun
## changement de scène) — c'est la partie testable en isolation de
## `start_local`/`host_lan` (le reste ouvre un vrai port ENet et change de
## scène, voir server_join_smoke.gd pour la vérification réseau de bout en
## bout existante ; ce fichier ne la duplique pas).
extends GdUnitTestSuite

const MatchLauncher := preload("res://scripts/core/MatchLauncher.gd")

var _saved_mode_id: String
var _saved_map_id: String
var _saved_team_size: int
var _saved_bots: bool
var _saved_difficulty: int


func before_test() -> void:
	_saved_mode_id = MatchConfig.mode_id
	_saved_map_id = MatchConfig.map_id
	_saved_team_size = MatchConfig.team_size
	_saved_bots = MatchConfig.bots_enabled
	_saved_difficulty = MatchConfig.bot_difficulty


func after_test() -> void:
	MatchConfig.mode_id = _saved_mode_id
	MatchConfig.map_id = _saved_map_id
	MatchConfig.team_size = _saved_team_size
	MatchConfig.bots_enabled = _saved_bots
	MatchConfig.bot_difficulty = _saved_difficulty


func test_configure_local_applies_all_fields() -> void:
	MatchLauncher.configure_local("tdm", 1, false, MatchConfig.Difficulty.ELITE, "shipment")
	assert_str(MatchConfig.mode_id).is_equal("tdm")
	assert_int(MatchConfig.team_size).is_equal(1)
	assert_bool(MatchConfig.bots_enabled).is_false()
	assert_int(MatchConfig.bot_difficulty).is_equal(MatchConfig.Difficulty.ELITE)
	assert_str(MatchConfig.map_id).is_equal("shipment")


func test_configure_local_falls_back_to_tdm_for_an_unknown_mode() -> void:
	# MatchConfig.set_mode retombe sur "tdm" pour tout id absent de MODES —
	# comportement HÉRITÉ, pas dupliqué ici, juste vérifié après passage par
	# configure_local (voir MatchConfig.MODES).
	MatchLauncher.configure_local("mode-inexistant", 4, true, MatchConfig.Difficulty.VETERAN)
	assert_str(MatchConfig.mode_id).is_equal("tdm")


func test_configure_local_clamps_an_out_of_range_difficulty() -> void:
	MatchLauncher.configure_local("tdm", 4, true, 99)
	assert_int(MatchConfig.bot_difficulty).is_equal(MatchConfig.Difficulty.ELITE)
