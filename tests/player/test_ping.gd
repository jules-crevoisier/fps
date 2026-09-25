## test_ping.gd
## Spec UX-10 (docs/research/04_ui_ux.md §2.8/§4, tâche UX-10 — « Système de
## ping contextuel (appui = marque au sol / ennemi / objet ; maintien = roue
## « ennemi ici », « j'y vais », « défendez », « besoin d'aide ») avec nom de
## zone »). Acceptance :
##  1. le ping est envoyé au serveur, qui le relaie à l'équipe SEULE (jamais à
##     l'adversaire, testé) ;
##  2. au plus 3 pings par 5 s et par joueur ;
##  3. un marqueur affiche icône + distance + zone pendant 6 s ;
##  4. les bots alliés réagissent aux pings « défendez » et « j'y vais » ;
##  5. utilisable à la manette (roue au stick).
##
## Style des doubles : sous-classe de GameWorld qui court-circuite `_ready()`
## (réseau/télémétrie hors sujet), exactement `_TestGameWorld` de
## tests/networking/test_respawn_refill.gd. Seule la branche 100 % hôte
## (id de pair 1, `OfflineMultiplayerPeer` par défaut en headless — voir
## GameMode.gd, "Godot ne rend is_server() fiable que si un pair est
## assigné... OfflineMultiplayerPeer par défaut") est exercée directement :
## un test mono-process ne peut pas relayer une VRAIE RPC vers un second
## pair (voir tests/networking/server_join_smoke.gd pour ce chemin-là) — le
## relais « équipe seule, jamais l'adversaire » est donc prouvé par la
## fonction PURE `GameWorld.teammates_for_ping` (aucun id d'équipe adverse ne
## peut structurellement en sortir) ET par une émission réelle du signal
## `ping_received` pour un roster mixte (équipe 0 humaine + équipe 1
## adverse), qui ne se déclenche jamais pour l'expéditeur "adverse".
extends GdUnitTestSuite

const PLAYER_KIND_ENEMY := PingController.KIND_ENEMY
const PLAYER_KIND_GROUND := PingController.KIND_GROUND
const PLAYER_KIND_OBJECT := PingController.KIND_OBJECT


class _TestGameWorld extends GameWorld:
	func _ready() -> void:
		set_multiplayer_authority(1)
		add_to_group("match")


## Double minimal d'un mode de jeu (TDM/Hardpoint...) : enregistre chaque
## appel de `report_enemy_sighting` (BOT-01) sans dépendre de GameMode.gd
## réel (hors périmètre de cette tâche).
class _GameModeDouble extends Node:
	var calls: Array = []

	func report_enemy_sighting(team: int, pos: Vector3) -> void:
		calls.append({"team": team, "pos": pos})


## Faux joueur pour `classify_tap` : seul le duck-typing `"team" in collider`
## compte, jamais une vraie scène de joueur.
class _FakePlayer extends Node:
	var team: int = 0


func _new_world() -> GameWorld:
	var world := _TestGameWorld.new()
	add_child(world)
	auto_free(world)
	return world


func _recorder() -> Dictionary:
	# Callable + tableau partagé : `bind` ne convient pas ici (nombre d'args
	# variable selon le signal), un Dictionary mutable capturé par une lambda
	# suffit pour un enregistreur de test local.
	var calls: Array = []
	var cb := func(sender_id: int, sender_name: String, kind: String, pos: Vector3, zone_name: String) -> void:
		calls.append({"sender_id": sender_id, "sender_name": sender_name, "kind": kind, "pos": pos, "zone_name": zone_name})
	return {"calls": calls, "cb": cb}


# ======================================================================
#  PingController — pur
# ======================================================================

func test_is_hold_false_just_under_the_threshold() -> void:
	assert_bool(PingController.is_hold(PingController.HOLD_THRESHOLD_S - 0.01)).is_false()


func test_is_hold_true_at_the_threshold() -> void:
	assert_bool(PingController.is_hold(PingController.HOLD_THRESHOLD_S)).is_true()


func test_is_hold_true_well_above_the_threshold() -> void:
	assert_bool(PingController.is_hold(1.5)).is_true()


func test_classify_tap_defaults_to_ground_when_nothing_is_hit() -> void:
	assert_str(PingController.classify_tap({}, 0)).is_equal(PLAYER_KIND_GROUND)


func test_classify_tap_defaults_to_ground_for_an_unrecognized_collider() -> void:
	var deco := Node.new()
	auto_free(deco)
	assert_str(PingController.classify_tap({"collider": deco}, 0)).is_equal(PLAYER_KIND_GROUND)


func test_classify_tap_returns_enemy_for_a_player_on_another_team() -> void:
	var enemy := _FakePlayer.new()
	enemy.team = 1
	auto_free(enemy)
	assert_str(PingController.classify_tap({"collider": enemy}, 0)).is_equal(PLAYER_KIND_ENEMY)


func test_classify_tap_returns_ground_for_a_teammate_not_enemy() -> void:
	var ally := _FakePlayer.new()
	ally.team = 0
	auto_free(ally)
	assert_str(PingController.classify_tap({"collider": ally}, 0)).is_equal(PLAYER_KIND_GROUND)


func test_classify_tap_returns_object_for_a_world_weapon() -> void:
	var weapon := WorldWeapon.new()
	auto_free(weapon)
	assert_str(PingController.classify_tap({"collider": weapon}, 0)).is_equal(PLAYER_KIND_OBJECT)


func test_classify_tap_returns_object_for_an_ammo_pack() -> void:
	var pack := AmmoPack.new()
	auto_free(pack)
	assert_str(PingController.classify_tap({"collider": pack}, 0)).is_equal(PLAYER_KIND_OBJECT)


# ======================================================================
#  PingWheel — pur (souris ET manette partagent CE calcul, contrat "roue au
#  stick" : un Vector2 suffit à représenter les deux, voir doc de classe)
# ======================================================================

func test_option_for_direction_up_selects_enemy_here() -> void:
	assert_int(PingWheel.option_for_direction(Vector2(0, -1))).is_equal(0)


func test_option_for_direction_right_selects_going() -> void:
	assert_int(PingWheel.option_for_direction(Vector2(1, 0))).is_equal(1)


func test_option_for_direction_down_selects_defend() -> void:
	assert_int(PingWheel.option_for_direction(Vector2(0, 1))).is_equal(2)


func test_option_for_direction_left_selects_need_help() -> void:
	assert_int(PingWheel.option_for_direction(Vector2(-1, 0))).is_equal(3)


func test_option_for_direction_inside_deadzone_selects_nothing() -> void:
	assert_int(PingWheel.option_for_direction(Vector2(0.05, 0.05))).is_equal(-1)


func test_option_for_direction_matches_wheel_kinds_order() -> void:
	# Vérifie la correspondance COMPLÈTE index -> kind (contrat : 4 options).
	var dirs := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
	for i in dirs.size():
		var idx := PingWheel.option_for_direction(dirs[i])
		assert_str(PingController.WHEEL_KINDS[idx]).is_equal(PingController.WHEEL_KINDS[i])


func _new_wheel() -> PingWheel:
	var w := PingWheel.new()
	add_child(w)
	auto_free(w)
	return w


func test_wheel_update_direction_sets_the_hovered_kind() -> void:
	var wheel := _new_wheel()
	wheel.open()
	wheel.update_direction(Vector2(0, -1))
	assert_str(wheel.hovered_kind()).is_equal(PingController.KIND_ENEMY_HERE)


func test_wheel_open_starts_with_no_hovered_option() -> void:
	var wheel := _new_wheel()
	wheel.open()
	assert_str(wheel.hovered_kind()).is_equal("")


func test_wheel_close_and_confirm_returns_the_hovered_kind_and_hides() -> void:
	var wheel := _new_wheel()
	wheel.open()
	wheel.update_direction(Vector2(0, 1))
	var kind := wheel.close_and_confirm()
	assert_str(kind).is_equal(PingController.KIND_DEFEND)
	assert_bool(wheel.visible).is_false()


func test_wheel_close_and_confirm_returns_empty_when_direction_stayed_neutral() -> void:
	var wheel := _new_wheel()
	wheel.open()
	wheel.update_direction(Vector2.ZERO)
	assert_str(wheel.close_and_confirm()).is_equal("")


func test_wheel_close_and_confirm_emits_option_chosen_only_for_a_real_choice() -> void:
	var wheel := _new_wheel()
	var chosen: Array = []
	wheel.option_chosen.connect(func(kind: String) -> void: chosen.append(kind))
	wheel.open()
	wheel.update_direction(Vector2(-1, 0))
	wheel.close_and_confirm()
	assert_array(chosen).is_equal([PingController.KIND_NEED_HELP])

	chosen.clear()
	wheel.open()
	wheel.update_direction(Vector2.ZERO)
	wheel.close_and_confirm()
	assert_array(chosen).append_failure_message(
		"un maintien relâché en zone morte doit être ANNULÉ, jamais émettre un choix par défaut"
	).is_empty()


# ======================================================================
#  PingMarkers — pur
# ======================================================================

func test_format_distance_rounds_to_the_nearest_meter() -> void:
	assert_str(PingMarkers.format_distance(24.4)).is_equal("24 m")
	assert_str(PingMarkers.format_distance(24.6)).is_equal("25 m")


func test_format_distance_is_never_negative() -> void:
	assert_str(PingMarkers.format_distance(-3.0)).is_equal("0 m")


func test_format_label_appends_the_uppercased_zone() -> void:
	assert_str(PingMarkers.format_label(PingController.KIND_ENEMY, "grand-rue")).is_equal("ENNEMI — GRAND-RUE")


func test_format_label_falls_back_to_the_kind_label_without_a_zone() -> void:
	assert_str(PingMarkers.format_label(PingController.KIND_ENEMY, "")).is_equal("ENNEMI")


func test_every_kind_has_a_non_empty_icon_and_label() -> void:
	for kind in PingController.ALL_KINDS:
		assert_str(PingMarkers.icon_for_kind(kind)).append_failure_message(
			"icône manquante pour le kind '%s'" % kind
		).is_not_empty()
		assert_str(PingMarkers.label_for_kind(kind)).append_failure_message(
			"libellé manquant pour le kind '%s'" % kind
		).is_not_empty()


func test_entry_lifetime_is_exactly_six_seconds() -> void:
	# Contrat UX-10 : « pendant 6 s ».
	assert_float(PingMarkers.ENTRY_LIFETIME).is_equal_approx(6.0, 0.001)


func _new_markers() -> PingMarkers:
	var pm := PingMarkers.new()
	add_child(pm)
	auto_free(pm)
	return pm


func test_receive_adds_one_entry_with_the_distance_from_the_viewer() -> void:
	var pm := _new_markers()
	pm.receive(2, "BOT Iris", PingController.KIND_ENEMY, Vector3(10, 0, 0), "Grand-Rue", Vector3.ZERO)
	assert_int(pm.get_child_count()).is_equal(1)
	var panel := pm.get_child(0)
	var dist_label: Label = panel.get_meta("distance_label")
	assert_str(dist_label.text).is_equal("10 m")


func test_update_viewer_position_recomputes_the_distance_of_every_entry() -> void:
	var pm := _new_markers()
	pm.receive(2, "BOT Iris", PingController.KIND_ENEMY, Vector3(10, 0, 0), "", Vector3.ZERO)
	pm.update_viewer_position(Vector3(4, 0, 0))
	var panel := pm.get_child(0)
	var dist_label: Label = panel.get_meta("distance_label")
	assert_str(dist_label.text).is_equal("6 m")


func test_receive_caps_the_stack_at_max_entries_keeping_the_newest_first() -> void:
	var pm := _new_markers()
	for i in PingMarkers.MAX_ENTRIES + 2:
		pm.receive(2, "BOT", PingController.KIND_GROUND, Vector3(float(i), 0, 0), "", Vector3.ZERO)
	assert_int(pm.get_child_count()).is_equal(PingMarkers.MAX_ENTRIES)
	# Le plus récent (dernier `receive`) est inséré en tête (move_child(...,0)).
	var newest_pos: Vector3 = pm.get_child(0).get_meta("ping_pos")
	assert_float(newest_pos.x).is_equal_approx(float(PingMarkers.MAX_ENTRIES + 1), 0.001)


# ======================================================================
#  GameWorld — pur (limite de fréquence + relais équipe seule + bots)
# ======================================================================

func test_prune_ping_timestamps_drops_entries_outside_the_window() -> void:
	# `now - t <= window_s` : une entrée pile à 5,0 s (t=0.0) est encore
	# gardée (limite INCLUSE) ; -1.0 (6,0 s) est strictement hors fenêtre.
	var kept := GameWorld.prune_ping_timestamps([-1.0, 0.0, 4.0, 4.9], 5.0, 5.0)
	assert_array(kept).is_equal([0.0, 4.0, 4.9])


func test_prune_ping_timestamps_keeps_everything_inside_the_window() -> void:
	var kept := GameWorld.prune_ping_timestamps([4.0, 4.5], 5.0, 5.0)
	assert_array(kept).is_equal([4.0, 4.5])


func test_can_send_ping_true_under_the_cap() -> void:
	assert_bool(GameWorld.can_send_ping([1.0, 2.0], 3)).is_true()


func test_can_send_ping_false_at_the_cap() -> void:
	assert_bool(GameWorld.can_send_ping([1.0, 2.0, 3.0], 3)).is_false()


func test_teammates_for_ping_never_includes_the_enemy_team() -> void:
	var info := {
		1: {"name": "Hôte", "team": 0, "is_bot": false},
		2: {"name": "Adversaire", "team": 1, "is_bot": false},
	}
	var out := GameWorld.teammates_for_ping(info, 0)
	assert_array(out).append_failure_message(
		"contrat UX-10 : le ping ne doit JAMAIS être relayé à l'équipe adverse"
	).is_equal([1])


func test_teammates_for_ping_includes_the_sender_itself() -> void:
	var info := {1: {"name": "Hôte", "team": 0, "is_bot": false}}
	assert_array(GameWorld.teammates_for_ping(info, 0)).is_equal([1])


func test_teammates_for_ping_excludes_bots() -> void:
	var info := {
		1: {"name": "Hôte", "team": 0, "is_bot": false},
		9101: {"name": "BOT Iris", "team": 0, "is_bot": true},
	}
	assert_array(GameWorld.teammates_for_ping(info, 0)).is_equal([1])


func test_triggers_bot_rally_is_true_for_defend_going_and_enemy_sightings() -> void:
	assert_bool(GameWorld.triggers_bot_rally(PingController.KIND_DEFEND)).is_true()
	assert_bool(GameWorld.triggers_bot_rally(PingController.KIND_GOING)).is_true()
	assert_bool(GameWorld.triggers_bot_rally(PingController.KIND_ENEMY)).is_true()
	assert_bool(GameWorld.triggers_bot_rally(PingController.KIND_ENEMY_HERE)).is_true()


func test_triggers_bot_rally_is_false_for_need_help_ground_and_object() -> void:
	assert_bool(GameWorld.triggers_bot_rally(PingController.KIND_NEED_HELP)).is_false()
	assert_bool(GameWorld.triggers_bot_rally(PingController.KIND_GROUND)).is_false()
	assert_bool(GameWorld.triggers_bot_rally(PingController.KIND_OBJECT)).is_false()


# ======================================================================
#  GameWorld._server_ping — instance, branche 100 % hôte (voir doc d'en-tête)
# ======================================================================

func test_server_ping_relays_to_the_host_itself_but_never_to_the_enemy() -> void:
	var world := _new_world()
	world.player_info = {
		1: {"name": "Hôte", "team": 0, "kills": 0, "deaths": 0, "is_bot": false},
		2: {"name": "Adversaire", "team": 1, "kills": 0, "deaths": 0, "is_bot": false},
	}
	var rec := _recorder()
	world.ping_received.connect(rec.cb)

	world._server_ping(PingController.KIND_ENEMY, Vector3(5, 0, 0), 1)

	assert_int(rec.calls.size()).append_failure_message(
		"le ping de l'hôte (équipe 0) doit être relayé exactement une fois (à lui-même), jamais à l'adversaire"
	).is_equal(1)
	assert_int(rec.calls[0].sender_id).is_equal(1)
	assert_str(rec.calls[0].kind).is_equal(PingController.KIND_ENEMY)


func test_server_ping_ignores_a_sender_unknown_to_player_info() -> void:
	var world := _new_world()
	world.player_info = {1: {"name": "Hôte", "team": 0, "kills": 0, "deaths": 0, "is_bot": false}}
	var rec := _recorder()
	world.ping_received.connect(rec.cb)

	world._server_ping(PingController.KIND_GROUND, Vector3.ZERO, 42)

	assert_array(rec.calls).is_empty()


func test_server_ping_rejects_an_unknown_kind() -> void:
	var world := _new_world()
	world.player_info = {1: {"name": "Hôte", "team": 0, "kills": 0, "deaths": 0, "is_bot": false}}
	var rec := _recorder()
	world.ping_received.connect(rec.cb)

	world._server_ping("triche", Vector3.ZERO, 1)

	assert_array(rec.calls).is_empty()


func test_server_ping_enforces_at_most_three_pings_per_five_seconds() -> void:
	var world := _new_world()
	world.player_info = {1: {"name": "Hôte", "team": 0, "kills": 0, "deaths": 0, "is_bot": false}}
	var rec := _recorder()
	world.ping_received.connect(rec.cb)

	for i in 4:
		world._server_ping(PingController.KIND_GROUND, Vector3.ZERO, 1)

	assert_int(rec.calls.size()).append_failure_message(
		"contrat UX-10 : au plus 3 pings par 5 s et par joueur"
	).is_equal(3)


func test_request_ping_as_host_relays_directly_without_an_rpc() -> void:
	var world := _new_world()
	world.player_info = {1: {"name": "Hôte", "team": 0, "kills": 0, "deaths": 0, "is_bot": false}}
	var rec := _recorder()
	world.ping_received.connect(rec.cb)

	world.request_ping(PingController.KIND_OBJECT, Vector3(1, 2, 3))

	assert_int(rec.calls.size()).is_equal(1)
	assert_str(rec.calls[0].kind).is_equal(PingController.KIND_OBJECT)


func test_server_ping_defend_reports_an_enemy_sighting_to_the_game_mode() -> void:
	var world := _new_world()
	world.player_info = {1: {"name": "Hôte", "team": 0, "kills": 0, "deaths": 0, "is_bot": false}}
	var mode := _GameModeDouble.new()
	mode.add_to_group("game_mode")
	world.add_child(mode)
	auto_free(mode)

	world._server_ping(PingController.KIND_DEFEND, Vector3(7, 0, 2), 1)

	assert_int(mode.calls.size()).append_failure_message(
		"contrat UX-10 : les bots alliés doivent réagir au ping « défendez »"
	).is_equal(1)
	assert_int(mode.calls[0].team).is_equal(0)
	assert_vector(mode.calls[0].pos).is_equal(Vector3(7, 0, 2))


func test_server_ping_going_reports_an_enemy_sighting_to_the_game_mode() -> void:
	var world := _new_world()
	world.player_info = {1: {"name": "Hôte", "team": 0, "kills": 0, "deaths": 0, "is_bot": false}}
	var mode := _GameModeDouble.new()
	mode.add_to_group("game_mode")
	world.add_child(mode)
	auto_free(mode)

	world._server_ping(PingController.KIND_GOING, Vector3(1, 0, 1), 1)

	assert_int(mode.calls.size()).append_failure_message(
		"contrat UX-10 : les bots alliés doivent réagir au ping « j'y vais »"
	).is_equal(1)


func test_server_ping_need_help_does_not_report_an_enemy_sighting() -> void:
	var world := _new_world()
	world.player_info = {1: {"name": "Hôte", "team": 0, "kills": 0, "deaths": 0, "is_bot": false}}
	var mode := _GameModeDouble.new()
	mode.add_to_group("game_mode")
	world.add_child(mode)
	auto_free(mode)

	world._server_ping(PingController.KIND_NEED_HELP, Vector3.ZERO, 1)

	assert_array(mode.calls).is_empty()
