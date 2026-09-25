## test_telemetry.gd
## Spec FUN-05 (docs/research/05_fun_retention.md §5) : événements JSONL
## versionnés {v, t, match_id, event, ...}, validation de schéma, un `kill`
## qui porte positions/arme/distance/état de mouvement/capacité active/
## headshot/temps depuis spawn, écriture "jeu" réservée au serveur, aucune
## donnée personnelle hors pseudo, coût ≤ 0,1 ms/événement.
extends GdUnitTestSuite


var _saved_match_id: String
var _saved_log_open: bool


func before_test() -> void:
	# `Telemetry` est statique (comme MatchConfig) : sauvegarder/restaurer
	# évite qu'un test pollue le suivant (fichier ouvert, match_id courant).
	_saved_match_id = Telemetry.current_match_id
	_saved_log_open = Telemetry.is_log_open()
	Telemetry.close_log()
	Telemetry.current_match_id = ""


func after_test() -> void:
	Telemetry.close_log()
	Telemetry.current_match_id = _saved_match_id
	if _saved_log_open:
		Telemetry.open_log()


func _temp_path() -> String:
	return "user://telemetry_test_%d.jsonl" % Time.get_ticks_usec()


func _valid_kill_fields() -> Dictionary:
	return {
		"killer_id": 2, "victim_id": 3,
		"killer_pos": [1.0, 0.0, 2.0], "victim_pos": [4.0, 0.0, 5.0],
		"weapon": "Ravage", "distance": 5.0,
		"movement_state": "SLIDE", "active_ability": "Fumée",
		"headshot": true, "time_since_spawn": 4.2,
	}


# =========================================================== build_event / socle

func test_build_event_has_the_common_envelope() -> void:
	var e := Telemetry.build_event(Telemetry.EVENT_SPAWN, {"player_id": 1, "team": 0, "pos": [0.0, 0.0, 0.0]}, "m1")
	assert_int(e["v"]).is_equal(Telemetry.SCHEMA_VERSION)
	assert_bool(e["t"] is float or e["t"] is int).is_true()
	assert_str(e["match_id"]).is_equal("m1")
	assert_str(e["event"]).is_equal(Telemetry.EVENT_SPAWN)
	assert_int(e["player_id"]).is_equal(1)


func test_build_event_falls_back_to_current_match_id_when_omitted() -> void:
	Telemetry.current_match_id = "m_current"
	var e := Telemetry.build_event(Telemetry.EVENT_ABANDON, {"player_id": 1, "team": 0})
	assert_str(e["match_id"]).is_equal("m_current")


# =========================================================== validate — schéma

func test_validate_accepts_a_well_formed_kill_event() -> void:
	var e := Telemetry.build_event(Telemetry.EVENT_KILL, _valid_kill_fields(), "m1")
	assert_bool(Telemetry.validate(e)).is_true()


func test_validate_rejects_a_kill_missing_headshot() -> void:
	var fields := _valid_kill_fields()
	fields.erase("headshot")
	var e := Telemetry.build_event(Telemetry.EVENT_KILL, fields, "m1")
	assert_bool(Telemetry.validate(e)).is_false()


func test_validate_rejects_a_kill_missing_distance() -> void:
	var fields := _valid_kill_fields()
	fields.erase("distance")
	var e := Telemetry.build_event(Telemetry.EVENT_KILL, fields, "m1")
	assert_bool(Telemetry.validate(e)).is_false()


func test_validate_rejects_a_kill_missing_active_ability() -> void:
	var fields := _valid_kill_fields()
	fields.erase("active_ability")
	var e := Telemetry.build_event(Telemetry.EVENT_KILL, fields, "m1")
	assert_bool(Telemetry.validate(e)).is_false()


func test_validate_rejects_an_unknown_event_type() -> void:
	var e := Telemetry.build_event("does_not_exist", {}, "m1")
	assert_bool(Telemetry.validate(e)).is_false()


func test_validate_rejects_a_missing_base_field() -> void:
	var e := Telemetry.build_event(Telemetry.EVENT_SPAWN, {"player_id": 1, "team": 0, "pos": [0.0, 0.0, 0.0]}, "m1")
	e.erase("v")
	assert_bool(Telemetry.validate(e)).is_false()


func test_validate_accepts_every_documented_event_type_with_its_required_fields() -> void:
	var samples := {
		Telemetry.EVENT_SESSION_START: {"session_id": "s1"},
		Telemetry.EVENT_SESSION_END: {"session_id": "s1", "duration_s": 12.0},
		Telemetry.EVENT_MATCH_START: {"mode_id": "tdm", "map_id": "cargo_ship", "team_size": 4},
		Telemetry.EVENT_MATCH_END: {"winner_team": 0, "duration_s": 480.0},
		Telemetry.EVENT_SPAWN: {"player_id": 1, "team": 0, "pos": [0.0, 0.0, 0.0]},
		Telemetry.EVENT_KILL: _valid_kill_fields(),
		Telemetry.EVENT_ROUND_START: {"round_index": 1},
		Telemetry.EVENT_ROUND_END: {"round_index": 1, "winner_team": 1},
		Telemetry.EVENT_PURCHASE: {"player_id": 1, "item_id": 4, "cost": 2900},
		Telemetry.EVENT_ABILITY_USED: {"player_id": 1, "ability_id": "smoke"},
		Telemetry.EVENT_AGENT_SELECTED: {"player_id": 1, "agent_id": "korrigan"},
		Telemetry.EVENT_SETTINGS_CHANGED: {"player_id": 1, "key": "fov", "value": 100},
		Telemetry.EVENT_TUTORIAL_STEP: {"player_id": 1, "step_id": "move"},
		Telemetry.EVENT_TUTORIAL_COMPLETE: {"player_id": 1},
		Telemetry.EVENT_ABANDON: {"player_id": 1, "team": 0},
		Telemetry.EVENT_MATCH_PERF: {"avg_fps": 60.0, "p99_ms": 16.0, "avg_ping_ms": 30.0},
		Telemetry.EVENT_SURVEY: {"player_id": 1, "fun_score": 4},
	}
	for event in samples:
		var e := Telemetry.build_event(event, samples[event], "m1")
		assert_bool(Telemetry.validate(e)).override_failure_message(
			"event %s devrait être valide" % event).is_true()


# =========================================================== RGPD

func test_has_no_personal_data_accepts_game_pseudos_and_ids() -> void:
	var e := Telemetry.build_event(Telemetry.EVENT_SPAWN, {"player_id": 1, "team": 0, "pos": [0.0, 0.0, 0.0], "name": "BOT Mistral"}, "m1")
	assert_bool(Telemetry.has_no_personal_data(e)).is_true()


func test_has_no_personal_data_rejects_an_email_like_value() -> void:
	var e := Telemetry.build_event(Telemetry.EVENT_SPAWN, {"player_id": 1, "team": 0, "pos": [0.0, 0.0, 0.0], "name": "joueur@example.com"}, "m1")
	assert_bool(Telemetry.has_no_personal_data(e)).is_false()


func test_has_no_personal_data_rejects_an_ipv4_like_value() -> void:
	var e := Telemetry.build_event(Telemetry.EVENT_SPAWN, {"player_id": 1, "team": 0, "pos": [0.0, 0.0, 0.0], "note": "192.168.1.42"}, "m1")
	assert_bool(Telemetry.has_no_personal_data(e)).is_false()


# =========================================================== écriture JSONL

func test_record_writes_one_valid_jsonl_line() -> void:
	var path := _temp_path()
	Telemetry.open_log(path)
	Telemetry.record(Telemetry.EVENT_SPAWN, {"player_id": 1, "team": 0, "pos": [0.0, 0.0, 0.0]}, "m1", true)
	Telemetry.close_log()
	var f := FileAccess.open(path, FileAccess.READ)
	var line := f.get_line()
	f.close()
	DirAccess.remove_absolute(path)
	var parsed = JSON.parse_string(line)
	assert_bool(parsed is Dictionary).is_true()
	assert_str(parsed["event"]).is_equal(Telemetry.EVENT_SPAWN)
	assert_str(parsed["match_id"]).is_equal("m1")
	# JSON n'a qu'un type numérique : `parsed["player_id"]` revient en float.
	assert_int(int(parsed["player_id"])).is_equal(1)


func test_record_skips_an_invalid_event_without_writing() -> void:
	var path := _temp_path()
	Telemetry.open_log(path)
	Telemetry.record(Telemetry.EVENT_KILL, {"killer_id": 1}, "m1", true)  # champs requis manquants
	Telemetry.close_log()
	var f := FileAccess.open(path, FileAccess.READ)
	var content := f.get_as_text()
	f.close()
	DirAccess.remove_absolute(path)
	assert_str(content).is_equal("")


## Critère d'acceptation : "écriture côté serveur seulement pour les
## événements de jeu" — un `kill` (dans GAME_EVENTS) rapporté par un CLIENT
## (`is_server = false`) ne doit rien écrire.
func test_game_event_is_not_written_when_reported_by_a_client() -> void:
	var path := _temp_path()
	Telemetry.open_log(path)
	Telemetry.record(Telemetry.EVENT_KILL, _valid_kill_fields(), "m1", false)
	Telemetry.close_log()
	var f := FileAccess.open(path, FileAccess.READ)
	var content := f.get_as_text()
	f.close()
	DirAccess.remove_absolute(path)
	assert_str(content).is_equal("")


## Un événement HORS `GAME_EVENTS` (ex. sélection d'agent) s'écrit même si
## `is_server` est faux : c'est une action propre à un pair, pas un état de
## match autoritaire.
func test_non_game_event_is_written_even_when_reported_by_a_client() -> void:
	var path := _temp_path()
	Telemetry.open_log(path)
	Telemetry.record(Telemetry.EVENT_AGENT_SELECTED, {"player_id": 5, "agent_id": "iris"}, "m1", false)
	Telemetry.close_log()
	var f := FileAccess.open(path, FileAccess.READ)
	var content := f.get_as_text()
	f.close()
	DirAccess.remove_absolute(path)
	assert_bool(content.is_empty()).is_false()


func test_start_session_then_end_session_round_trips_two_lines() -> void:
	Telemetry.start_session()
	var path := Telemetry.log_path()
	Telemetry.end_session()
	var f := FileAccess.open(path, FileAccess.READ)
	var first: Dictionary = JSON.parse_string(f.get_line())
	var second: Dictionary = JSON.parse_string(f.get_line())
	f.close()
	DirAccess.remove_absolute(path)
	assert_str(first["event"]).is_equal(Telemetry.EVENT_SESSION_START)
	assert_str(second["event"]).is_equal(Telemetry.EVENT_SESSION_END)
	assert_bool(Telemetry.is_log_open()).is_false()


func test_start_session_is_idempotent() -> void:
	Telemetry.start_session()
	var path := Telemetry.log_path()
	Telemetry.start_session()  # ne doit pas réouvrir ni ré-émettre session_start
	assert_str(Telemetry.log_path()).is_equal(path)
	Telemetry.end_session()
	DirAccess.remove_absolute(path)


# =========================================================== coût par événement

func test_record_costs_at_most_0_1_ms_per_event_on_average() -> void:
	var path := _temp_path()
	Telemetry.open_log(path)
	var samples := 2000
	var start_usec := Time.get_ticks_usec()
	for i in samples:
		Telemetry.record(Telemetry.EVENT_KILL, _valid_kill_fields(), "m1", true)
	var elapsed_ms := (Time.get_ticks_usec() - start_usec) / 1000.0
	Telemetry.close_log()
	DirAccess.remove_absolute(path)
	var avg_ms := elapsed_ms / samples
	assert_float(avg_ms).override_failure_message(
		"coût moyen %.4f ms/événement > 0.1 ms" % avg_ms).is_less(0.1)
