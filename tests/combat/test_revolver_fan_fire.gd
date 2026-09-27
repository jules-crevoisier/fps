## test_revolver_fan_fire.gd
## Spec (design verrouillé utilisateur, tâche "revolver" — RÉVISÉ 2026-09-27
## après playtest, pivot "Valorant Classic" ; remplace la version précédente
## de ce fichier, qui figeait l'ancien mapping "LMB tap puis hold=fan") :
## - LMB = tir précis UNIQUEMENT, au plus 3.0 tirs/s. Le maintenir ne fanne
##   JAMAIS ("Holding LMB does NOT fan anymore; it fires nothing more until
##   release").
## - RMB TENU = "fan the hammer" à 7.5 tirs/s (premier tir immédiat), JAMAIS
##   de visée/zoom pour le Revolver ("RMB must never zoom, never blend
##   FPP_ADS_In and never slow movement").
## - Le Ravage garde RMB = ADS, inchangé.
## - "le clic gauche vise" (bug rapporté) : LMB ne doit JAMAIS déclencher
##   aim_held, sur AUCUNE arme.
## - Le serveur valide la cadence fan SEULEMENT si le tir est marqué alt-fire
##   ET que l'arme a le mode fan (`WeaponConfig.has_fan_fire()`).
## Même méthode organique (joueur BOT réel, autorité SERVEUR, `player.input`)
## que tests/combat/test_fire_while_sprinting.gd, dont ce fichier reprend les
## helpers de scène (dupliqués ici, convention du dépôt).
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _next_offset_index := 0


func before_test() -> void:
	get_tree().current_scene = self


func after_test() -> void:
	# Défensif : quelques tests pilotent le singleton Input directement
	# (gather_from_devices) -- ne jamais laisser "fire"/"aim" pressés pour la
	# suite suivante du même run.
	Input.action_release("fire")
	Input.action_release("aim")


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


func _floor(top: Vector3, size: Vector3 = Vector3(20, 1, 20)) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = top - Vector3(0, size.y * 0.5, 0)
	add_child(body)
	auto_free(body)
	return body


func _bot_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	player.set("is_bot", true)
	auto_free(player)
	return player


func _grounded_bot(o: Vector3) -> PlayerController:
	var player := _bot_player(o)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.velocity = Vector3(0, -1, 0)
	player.move_and_slide()
	assert_bool(player.is_on_floor()).append_failure_message(
		"préalable du test : le joueur doit être détecté au sol"
	).is_true()
	var t := 0
	while t < 30 and not (player.is_on_floor() and player.state_machine.current_name == "Idle"):
		if player.state_machine.current_name != "Idle" and player.is_on_floor():
			player.state_machine.transition_to("Idle")
		await get_tree().physics_frame
		t += 1
	return player


func _weapon(player: PlayerController) -> Weapon:
	return player.get_node("Weapon") as Weapon


func _wait_physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Bascule sur le slot 2 (revolver) via la même entrée qu'un humain (touche 2,
## `weapon_slot_pressed`) et attend la fin du délai de changement d'arme
## (`Weapon.SWITCH_DELAY`, 0.25 s = 15 tics à 60 Hz) avant de rendre la main.
## IMPORTANT : ce test pilote directement `player.input` (jamais le singleton
## Input, indisponible en tête sans fenêtre) -- même méthode que
## tests/combat/test_fire_while_sprinting.gd.
func _equip_revolver(player: PlayerController) -> Weapon:
	var weapon := _weapon(player)
	player.input.weapon_slot_pressed = 1
	await _wait_physics(1)
	player.input.weapon_slot_pressed = -1
	await _wait_physics(20)
	assert_str(weapon.cfg().weapon_name).append_failure_message(
		"préalable du test : le changement vers le slot 2 (revolver) n'a pas abouti"
	).is_equal("Revolver")
	return weapon


# ======================================================================
#  "Slot 2 = revolver, for every player at spawn, alongside the Ravage"
# ======================================================================

func test_revolver_is_in_slot_2_at_spawn_alongside_ravage() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	var weapon := _weapon(player)
	var configs: Array = weapon.weapons

	assert_int(configs.size()).append_failure_message(
		"préalable du test : l'inventaire doit avoir au moins 2 emplacements"
	).is_greater_equal(2)
	assert_str(configs[0].weapon_name).is_equal("Ravage")
	assert_object(configs[1]).append_failure_message(
		"le slot 2 doit être occupé par le Revolver au spawn (jamais vide)"
	).is_not_null()
	assert_str(configs[1].weapon_name).is_equal("Revolver")
	assert_str(weapon.cfg().weapon_name).is_equal("Ravage")


# ======================================================================
#  LMB = tap ONLY, never fans, even held.
# ======================================================================

func test_holding_lmb_on_the_revolver_never_exceeds_the_tap_rate() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	var weapon := await _equip_revolver(player)

	var mag_before: int = weapon.mag[weapon.current]
	var rejected_before := weapon.rejected_shots

	player.input.fire_pressed = true
	player.input.fire_held = true
	await _wait_physics(1)
	player.input.fire_pressed = false
	await _wait_physics(59)  # 1 s pleine tenue.
	player.input.fire_held = false
	await _wait_physics(2)

	# `automatic = false` -> le déclencheur LMB reste `fire_pressed` (front
	# UNIQUE), jamais `fire_held` : tenir la touche physiquement (fire_held
	# reste vrai) ne redéclenche donc RIEN de plus après le premier coup --
	# EXACTEMENT le contrat "Holding LMB does NOT fan anymore; it fires
	# nothing more until release" (pas "encore au rythme tap", VRAIMENT plus
	# rien tant que le bouton n'est pas relâché puis repressé).
	var consumed: int = mag_before - int(weapon.mag[weapon.current])
	assert_int(consumed).append_failure_message(
		"tenir LMB sur le revolver ne doit produire qu'UN SEUL coup (celui du premier appui) -- "
			+ "contrat : \"Holding LMB does NOT fan anymore; it fires nothing more until release\" "
			+ "-- chargeur %d->%d en 1 s" % [mag_before, weapon.mag[weapon.current]]
	).is_equal(1)
	assert_int(weapon.rejected_shots).is_equal(rejected_before)


func test_releasing_and_pressing_lmb_again_stays_capped_at_the_tap_rate() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	var weapon := await _equip_revolver(player)

	var mag_before: int = weapon.mag[weapon.current]
	var rejected_before := weapon.rejected_shots

	for i in 30:
		player.input.fire_pressed = true
		player.input.fire_held = true
		await get_tree().physics_frame
		player.input.fire_pressed = false
		player.input.fire_held = false
		await get_tree().physics_frame

	var consumed: int = mag_before - int(weapon.mag[weapon.current])
	assert_int(consumed).append_failure_message(
		"tapoter le revolver ne doit jamais dépasser ~3 tirs/s (cadence tap), obtenu %d en 1 s"
			% consumed
	).is_less_equal(4)
	assert_int(weapon.rejected_shots).is_equal(rejected_before)


# ======================================================================
#  RMB (alt_fire_held) = fan the hammer, 7.5/s, never aims.
# ======================================================================

func test_holding_rmb_on_the_revolver_fans_faster_than_the_tap_rate() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	var weapon := await _equip_revolver(player)

	var mag_before: int = weapon.mag[weapon.current]
	var rejected_before := weapon.rejected_shots

	player.input.alt_fire_held = true
	var ticks := 0
	while ticks < 60 and (mag_before - int(weapon.mag[weapon.current])) < 5:
		await get_tree().physics_frame
		ticks += 1
	player.input.alt_fire_held = false
	await _wait_physics(2)

	var consumed: int = mag_before - int(weapon.mag[weapon.current])
	assert_int(consumed).append_failure_message(
		"tenir RMB sur le revolver doit fanner (7.5 tirs/s) -- chargeur %d->%d en %d tics"
			% [mag_before, weapon.mag[weapon.current], ticks]
	).is_greater(1)
	assert_int(weapon.rejected_shots).append_failure_message(
		"le serveur ne doit jamais rejeter un tir fan légitime -- refusés %d->%d"
			% [rejected_before, weapon.rejected_shots]
	).is_equal(rejected_before)


## Ces 4 tests exercent DIRECTEMENT `PlayerInput.gather_from_devices()` (voir
## sa docstring : "Public ... pour rester directement testable") sur le nœud
## RÉEL `player.input` (déjà câblé à CE `player` par PlayerInput._ready()),
## piloté via le singleton `Input` -- JAMAIS en manipulant `player.input.
## aim_held`/`alt_fire_held` à la main sur un BOT : un bot ne passe JAMAIS par
## `gather_from_devices()` (voir `PlayerInput._physics_process`, `if is_bot:
## return`) et SA PROPRE IA (BotBrain._tick_combat) écrit `aim_held`
## directement à chaque tick -- une assignation manuelle serait donc soit
## sans effet, soit un faux positif écrasé par l'IA, sans jamais exercer le
## filtre `weapon_aims_on_right_click` réellement sous test ici.
func _release_mouse_actions() -> void:
	Input.action_release("fire")
	Input.action_release("aim")


func test_rmb_never_aims_while_the_revolver_is_equipped() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	await _equip_revolver(player)
	_release_mouse_actions()

	Input.action_press("aim")
	player.input.gather_from_devices()
	Input.action_release("aim")

	assert_bool(player.input.aim_held).append_failure_message(
		"RMB ne doit JAMAIS viser/zoomer pendant que le revolver est équipé "
			+ "(design : \"RMB must never zoom, never blend FPP_ADS_In\")"
	).is_false()
	assert_bool(player.input.alt_fire_held).append_failure_message(
		"le maintien BRUT de RMB (alt_fire_held) doit rester vrai -- c'est lui qui pilote le fan"
	).is_true()


func test_ravage_rmb_still_aims_unchanged() -> void:
	# Contrôle négatif : le Ravage (alt_fire_mode = NONE) garde RMB = ADS.
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	var weapon := _weapon(player)
	assert_str(weapon.cfg().weapon_name).is_equal("Ravage")
	_release_mouse_actions()

	Input.action_press("aim")
	player.input.gather_from_devices()
	Input.action_release("aim")

	assert_bool(player.input.aim_held).append_failure_message(
		"le Ravage doit garder RMB = ADS (alt_fire_mode NONE, comportement inchangé)"
	).is_true()


# ======================================================================
#  "le clic gauche vise" — LMB ne doit JAMAIS déclencher aim_held.
# ======================================================================

func test_lmb_never_triggers_aiming_on_the_revolver() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	await _equip_revolver(player)
	_release_mouse_actions()

	Input.action_press("fire")
	player.input.gather_from_devices()
	Input.action_release("fire")

	assert_bool(player.input.aim_held).append_failure_message(
		"LMB ne doit jamais déclencher la visée (bug rapporté \"le clic gauche vise\")"
	).is_false()


func test_lmb_never_triggers_aiming_on_the_ravage() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	var weapon := _weapon(player)
	assert_str(weapon.cfg().weapon_name).is_equal("Ravage")
	_release_mouse_actions()

	Input.action_press("fire")
	player.input.gather_from_devices()
	Input.action_release("fire")

	assert_bool(player.input.aim_held).append_failure_message(
		"LMB ne doit jamais déclencher la visée, même sur le Ravage (contrôle de régression)"
	).is_false()


# ======================================================================
#  Validation serveur : cadence fan acceptée SEULEMENT si (alt-fire ET arme fan).
# ======================================================================

func test_revolver_server_rate_cap_matches_fan_fire_rate_when_flagged_alt_fire() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	var weapon := await _equip_revolver(player)
	var sender_id := str(player.name).to_int()
	var cfg := weapon.cfg()
	var revolver_id := WeaponDatabase.id_of(cfg)
	var origin: Vector3 = player.head.global_position
	var dirs := [Vector3(0, 0, -1)]

	# Draine le burst (2.0 jetons) du limiteur FAN -- base connue pour la suite.
	weapon._server_fire(sender_id, origin, dirs, revolver_id, true)
	weapon._server_fire(sender_id, origin, dirs, revolver_id, true)
	var rejected_after_burst := weapon.rejected_shots

	weapon._server_tick(1.0 / cfg.fan_fire_rate + 0.01)
	weapon._server_fire(sender_id, origin, dirs, revolver_id, true)
	assert_int(weapon.rejected_shots).append_failure_message(
		"un tir marqué alt-fire, espacé d'un intervalle FAN complet, doit être accepté"
	).is_equal(rejected_after_burst)

	weapon._server_fire(sender_id, origin, dirs, revolver_id, true)  # immédiat, pas de tick.
	assert_int(weapon.rejected_shots).append_failure_message(
		"un tir alt-fire immédiat (bien plus rapide que la cadence fan) doit rester rejeté"
	).is_equal(rejected_after_burst + 1)


func test_revolver_shot_not_flagged_alt_fire_uses_the_tap_rate_cap() -> void:
	# "fan-rate shots are accepted only when the request is flagged alt-fire" :
	# un tir NON marqué alt-fire reste plafonné à `fire_rate` (3.0), même sur
	# le revolver -- il ne doit JAMAIS profiter du limiteur fan (7.5).
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	var weapon := await _equip_revolver(player)
	var sender_id := str(player.name).to_int()
	var cfg := weapon.cfg()
	var revolver_id := WeaponDatabase.id_of(cfg)
	var origin: Vector3 = player.head.global_position
	var dirs := [Vector3(0, 0, -1)]

	weapon._server_fire(sender_id, origin, dirs, revolver_id, false)
	weapon._server_fire(sender_id, origin, dirs, revolver_id, false)  # draine le burst tap.
	var rejected_after_burst := weapon.rejected_shots

	# Intervalle FAN (1/7.5 s) : suffisant pour le limiteur FAN, PAS pour le
	# limiteur TAP (1/3 s) -- doit rester rejeté puisque is_alt_fire=false.
	weapon._server_tick(1.0 / cfg.fan_fire_rate + 0.01)
	weapon._server_fire(sender_id, origin, dirs, revolver_id, false)
	assert_int(weapon.rejected_shots).append_failure_message(
		"un tir NON marqué alt-fire doit rester plafonné à fire_rate (3/s), jamais fan_fire_rate (7.5/s)"
	).is_equal(rejected_after_burst + 1)


func test_ravage_alt_fire_flag_never_grants_the_fan_rate() -> void:
	# "the fan rate must be accepted only for weapons that have it" : même si
	# un client (modifié) marque un tir Ravage comme alt-fire, le serveur ne
	# doit JAMAIS lui accorder une cadence supérieure à fire_rate (le Ravage
	# n'a pas `has_fan_fire()`).
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	var weapon := _weapon(player)
	var cfg := weapon.cfg()
	assert_str(cfg.weapon_name).is_equal("Ravage")
	assert_bool(cfg.has_fan_fire()).append_failure_message(
		"préalable du test : le Ravage ne doit avoir aucun mode fan"
	).is_false()

	var sender_id := str(player.name).to_int()
	var ravage_id := WeaponDatabase.id_of(cfg)
	var origin: Vector3 = player.head.global_position
	var dirs := [Vector3(0, 0, -1)]

	weapon._server_fire(sender_id, origin, dirs, ravage_id, true)
	weapon._server_fire(sender_id, origin, dirs, ravage_id, true)  # draine le burst.
	var rejected_after_burst := weapon.rejected_shots

	weapon._server_tick(1.0 / cfg.fire_rate + 0.01)  # intervalle tap complet : accepté.
	weapon._server_fire(sender_id, origin, dirs, ravage_id, true)
	assert_int(weapon.rejected_shots).is_equal(rejected_after_burst)

	weapon._server_fire(sender_id, origin, dirs, ravage_id, true)  # immédiat : doit rester rejeté.
	assert_int(weapon.rejected_shots).append_failure_message(
		"le Ravage marqué alt-fire (client modifié) ne doit jamais obtenir une cadence > fire_rate"
	).is_equal(rejected_after_burst + 1)
