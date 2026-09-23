## test_server_config.gd
## Spec (mission serveur dédié, ServerBoot) : la config lit PORT, HEALTH_PORT,
## MODE, MAP, MAX_PLAYERS, BOTS, BOT_DIFFICULTY, MATCH_TOKEN_SECRET, MATCH_ID,
## RESTART_ON_END depuis un environnement déjà résolu (voir docs/SERVER.md
## pour la liste complète) avec des valeurs par défaut sûres quand une clé est
## absente ou invalide. `ServerConfig.parse` est pur (dictionnaire injecté),
## jamais `OS` directement — voir ServerConfig.from_os pour le seul point de
## contact réel avec l'environnement.
extends GdUnitTestSuite


func test_defaults_when_env_is_empty() -> void:
	var c := ServerConfig.parse({})
	assert_int(c.port).is_equal(7777)
	assert_int(c.health_port).is_equal(8080)
	assert_str(c.mode_id).is_equal("tdm")
	assert_str(c.map_id).is_equal("")
	assert_int(c.max_players).is_equal(16)
	assert_bool(c.bots_enabled).is_true()
	assert_str(c.bot_difficulty).is_equal("veteran")
	assert_str(c.match_token_secret).is_equal("")
	assert_bool(c.restart_on_end).is_true()


func test_reads_every_key_from_env() -> void:
	var c := ServerConfig.parse({
		"PORT": "9999",
		"HEALTH_PORT": "9090",
		"MODE": "hardpoint",
		"MAP": "col_du_vautour",
		"MAX_PLAYERS": "8",
		"BOTS": "false",
		"BOT_DIFFICULTY": "elite",
		"MATCH_TOKEN_SECRET": "top-secret",
		"MATCH_ID": "match-abc",
		"RESTART_ON_END": "false",
	})
	assert_int(c.port).is_equal(9999)
	assert_int(c.health_port).is_equal(9090)
	assert_str(c.mode_id).is_equal("hardpoint")
	assert_str(c.map_id).is_equal("col_du_vautour")
	assert_int(c.max_players).is_equal(8)
	assert_bool(c.bots_enabled).is_false()
	assert_str(c.bot_difficulty).is_equal("elite")
	assert_str(c.match_token_secret).is_equal("top-secret")
	assert_str(c.match_id).is_equal("match-abc")
	assert_bool(c.restart_on_end).is_false()


func test_invalid_int_falls_back_to_default() -> void:
	var c := ServerConfig.parse({"PORT": "not-a-number"})
	assert_int(c.port).is_equal(7777)


func test_bool_accepts_common_truthy_and_falsy_spellings() -> void:
	for v in ["1", "true", "TRUE", "yes", "on"]:
		assert_bool(ServerConfig.parse({"BOTS": v}).bots_enabled) \
			.append_failure_message("BOTS=%s devrait être vrai" % v).is_true()
	for v in ["0", "false", "FALSE", "no", "off"]:
		assert_bool(ServerConfig.parse({"BOTS": v}).bots_enabled) \
			.append_failure_message("BOTS=%s devrait être faux" % v).is_false()


func test_unrecognized_bool_spelling_falls_back_to_default() -> void:
	assert_bool(ServerConfig.parse({"BOTS": "maybe"}).bots_enabled).is_true()


func test_match_id_falls_back_to_random_seed_when_absent() -> void:
	var c := ServerConfig.parse({}, "generated-id")
	assert_str(c.match_id).is_equal("generated-id")


func test_wants_dedicated_true_on_feature_tag() -> void:
	assert_bool(ServerConfig.wants_dedicated(true, PackedStringArray())).is_true()


func test_wants_dedicated_true_on_server_arg() -> void:
	assert_bool(ServerConfig.wants_dedicated(false, PackedStringArray(["--server"]))).is_true()


func test_wants_dedicated_false_otherwise() -> void:
	assert_bool(ServerConfig.wants_dedicated(false, PackedStringArray())).is_false()
	assert_bool(ServerConfig.wants_dedicated(false, PackedStringArray(["--fullscreen"]))).is_false()


func test_difficulty_id_maps_known_names() -> void:
	assert_int(ServerConfig.difficulty_id("recrue")).is_equal(0)
	assert_int(ServerConfig.difficulty_id("veteran")).is_equal(1)
	assert_int(ServerConfig.difficulty_id("elite")).is_equal(2)
	assert_int(ServerConfig.difficulty_id("ELITE")).is_equal(2)


func test_difficulty_id_falls_back_to_veteran() -> void:
	assert_int(ServerConfig.difficulty_id("n'importe quoi")).is_equal(1)
