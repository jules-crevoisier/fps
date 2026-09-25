## test_state_exits.gd
## Spec (BUG-08, docs/audit/bugs.md) :
##  - Slide / Roll / Stun ne doivent JAMAIS se relever (is_crouching -> false)
##    quand `PlayerController.is_blocked_above()` est vrai (plafond bas) : le
##    joueur se relèverait dans le décor. Ils passent en Crouch à la place ;
##    Crouch relèvera de lui-même dès que le plafond sera dégagé
##    (Crouch.gd:21, déjà couvert).
##  - Dive ne doit jamais rester bloqué à vie : si l'élan vertical est annulé
##    dès la première frame (obstacle juste au-dessus), `is_on_floor()` reste
##    vrai en continu, `_airborne` ne passe jamais à vrai et l'atterrissage
##    naturel (`elif _airborne: transition_to("Roll")`) ne se déclenche
##    jamais. Une minuterie de sécurité de 1 s force la sortie (vers Roll)
##    quoi qu'il arrive.
##
## Scène physique minimale et réelle (StaticBody3D pour le sol/plafond +
## instance réelle de scenes/player/player.tscn, synchronisée via
## `await get_tree().physics_frame`), même méthode que
## tests/player/test_respawn_state_reset.gd et tests/agents/test_ability_rays.gd.
## Les states sont pilotés directement via `state_machine.transition_to()` /
## `state_machine.physics_update()` (comme `player._check_fall_stun()` dans
## test_respawn_state_reset.gd) pour un timing déterministe, sans dépendre de
## la fenêtre exacte d'un vrai déclenchement (sprint+Ctrl pour Slide, etc.).
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _next_offset_index := 0


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


## Sol de décor (StaticBody3D, calque WORLD) dont la surface haute est
## exactement à `top.y` — même construction que
## tests/player/test_respawn_state_reset.gd::_floor.
func _floor(top: Vector3, size: Vector3 = Vector3(10, 1, 10)) -> StaticBody3D:
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


## Plafond bas (StaticBody3D, calque WORLD) qui recouvre la bande verticale
## scrutée par CeilingCheck : RayCast3D FIXE à l'origine du joueur, local y
## dans [1.4, 2.0] (scenes/player/player.tscn:101-104 — ne bouge PAS avec
## `is_crouching`/`current_height`, donc inutile de simuler un vrai crouch).
## Bas du bloc à `player_origin.y + 1.6`, bien dans cette bande.
func _low_ceiling(player_origin: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 1, 4)
	col.shape = shape
	body.add_child(col)
	body.position = player_origin + Vector3(0, 1.6 + 0.5, 0)
	add_child(body)
	auto_free(body)
	return body


## Instance réelle du joueur, spawnée comme un BOT (autorité SERVEUR — voir
## PlayerController._enter_tree) pour que `_physics_process` tourne bien en
## test headless, sans capture souris/caméra (branche humain local). Même
## méthode que tests/player/test_respawn_state_reset.gd::_bot_player.
func _bot_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	player.set("is_bot", true)
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	auto_free(player)
	return player


## Spawne un bot exactement au sommet du sol et force le contact réel
## (`is_on_floor()` vrai) avant de piloter un state directement — même
## méthode que test_respawn_state_reset.gd
## (test_slide_jumped_cleared_when_check_fall_stun_transitions_to_*).
func _grounded_bot(o: Vector3) -> PlayerController:
	var player := _bot_player(o)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.velocity = Vector3(0, -1, 0)
	player.move_and_slide()
	assert_bool(player.is_on_floor()).append_failure_message(
		"préalable du test : le joueur doit être détecté au sol"
	).is_true()
	return player


# ----------------------------------------------------------- Slide -> Crouch

func test_slide_exit_stays_crouched_under_a_low_ceiling() -> void:
	var o := _offset()
	_floor(o)
	_low_ceiling(o)
	var player := await _grounded_bot(o)

	player.state_machine.transition_to("Slide", {})
	assert_str(player.state_machine.current_name).append_failure_message(
		"préalable du test : le slide doit bien être actif"
	).is_equal("Slide")

	# CANCEL : relâcher Ctrl déclenche _exit_to_ground() dès le tick suivant
	# (scripts/player/states/Slide.gd, branche "not player.input.crouch_held").
	player.input.crouch_held = false
	player.state_machine.physics_update(1.0 / 60.0)

	assert_str(player.state_machine.current_name).append_failure_message(
		"sous un plafond bas, la fin de glissade doit rester accroupie (Crouch), jamais se relever dans le décor — état obtenu : %s"
			% player.state_machine.current_name
	).is_equal("Crouch")
	assert_bool(player.is_crouching).append_failure_message(
		"le state Crouch doit garder la capsule accroupie"
	).is_true()


func test_slide_exit_stands_up_normally_when_ceiling_is_clear() -> void:
	# Régression : sans obstacle, le comportement existant (se relever) reste
	# inchangé.
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)

	player.state_machine.transition_to("Slide", {})
	player.input.crouch_held = false
	player.state_machine.physics_update(1.0 / 60.0)

	assert_str(player.state_machine.current_name).append_failure_message(
		"sans plafond bas, la fin de glissade doit se relever normalement — état obtenu : %s"
			% player.state_machine.current_name
	).is_not_equal("Crouch")
	assert_bool(player.is_crouching).is_false()


# ------------------------------------------------------------ Roll -> Crouch

func test_roll_exit_stays_crouched_under_a_low_ceiling() -> void:
	var o := _offset()
	_floor(o)
	_low_ceiling(o)
	var player := await _grounded_bot(o)

	player.state_machine.transition_to("Roll", {})
	assert_str(player.state_machine.current_name).is_equal("Roll")

	# Fait s'écouler toute la durée de la roulade en un seul appel (déterministe).
	player.state_machine.physics_update(player.config.roll_duration + 0.01)

	assert_str(player.state_machine.current_name).append_failure_message(
		"sous un plafond bas, la fin de roulade doit rester accroupie (Crouch), jamais se relever dans le décor — état obtenu : %s"
			% player.state_machine.current_name
	).is_equal("Crouch")
	assert_bool(player.is_crouching).is_true()


func test_roll_exit_stands_up_normally_when_ceiling_is_clear() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)

	player.state_machine.transition_to("Roll", {})
	player.state_machine.physics_update(player.config.roll_duration + 0.01)

	assert_str(player.state_machine.current_name).append_failure_message(
		"sans plafond bas, la fin de roulade doit se relever normalement — état obtenu : %s"
			% player.state_machine.current_name
	).is_not_equal("Crouch")
	assert_bool(player.is_crouching).is_false()


# ------------------------------------------------------------ Stun -> Crouch

func test_stun_recovery_crouches_under_a_low_ceiling() -> void:
	var o := _offset()
	_floor(o)
	_low_ceiling(o)
	var player := await _grounded_bot(o)

	player.state_machine.transition_to("Stun", {"duration": 0.4})
	assert_str(player.state_machine.current_name).is_equal("Stun")

	player.state_machine.physics_update(0.4 + 0.01)

	assert_str(player.state_machine.current_name).append_failure_message(
		"sous un plafond bas, la récupération du stun doit s'accroupir (Crouch), jamais se relever dans le décor — état obtenu : %s"
			% player.state_machine.current_name
	).is_equal("Crouch")
	assert_bool(player.is_crouching).is_true()


func test_stun_recovery_stands_up_normally_when_ceiling_is_clear() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)

	player.state_machine.transition_to("Stun", {"duration": 0.4})
	player.state_machine.physics_update(0.4 + 0.01)

	assert_str(player.state_machine.current_name).append_failure_message(
		"sans plafond bas, la récupération du stun doit se relever normalement — état obtenu : %s"
			% player.state_machine.current_name
	).is_not_equal("Crouch")
	assert_bool(player.is_crouching).is_false()


# --------------------------------------------------- Dive : délai de sécurité

func test_dive_never_stays_stuck_more_than_one_second_when_blocked_from_taking_off() -> void:
	# Reproduit EXACTEMENT le scénario du bug (docs/audit/bugs.md BUG-08) :
	# un obstacle annule l'élan vertical dès la première frame, donc
	# `is_on_floor()` reste vrai en continu et `_airborne` ne passe jamais à
	# vrai — sans minuterie de sécurité, `elif _airborne: transition_to
	# ("Roll")` ne se déclenche JAMAIS et le joueur reste bloqué à vie dans
	# Dive. On simule ça fidèlement en pilotant `state_machine.physics_update`
	# directement SANS jamais rappeler `move_and_slide()` après le contact au
	# sol initial : `is_on_floor()` reste alors figé à "vrai" tick après tick,
	# exactement comme le ferait un vrai obstacle qui empêche tout décollage.
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)

	player.state_machine.transition_to("Dive", {})
	assert_str(player.state_machine.current_name).is_equal("Dive")

	var dt := 1.0 / 60.0
	var elapsed := 0.0
	var ticks := 0
	var max_ticks := 90  # marge large (1.5 s à 60 Hz) : le test échoue si jamais atteint.
	while player.state_machine.current_name == "Dive" and ticks < max_ticks:
		player.state_machine.physics_update(dt)
		elapsed += dt
		ticks += 1

	assert_str(player.state_machine.current_name).append_failure_message(
		"le plongeon est resté bloqué plus de %d ticks (%.2f s) sans jamais sortir — délai de sécurité manquant ou cassé"
			% [max_ticks, elapsed]
	).is_equal("Roll")
	assert_float(elapsed).append_failure_message(
		"le plongeon a mis %.3f s à sortir, plus que le délai de sécurité annoncé (1 s max, docs/audit/bugs.md BUG-08)"
			% elapsed
	).is_less_equal(1.0 + dt)


func test_dive_lands_normally_and_transitions_to_roll_well_before_the_safety_timeout() -> void:
	# Régression : un plongeon normal (rien au-dessus) doit toujours retomber
	# et enchaîner sur Roll via l'atterrissage réel, largement avant le délai
	# de sécurité de 1 s — la minuterie ne doit jamais "voler" la transition
	# normale.
	# Sol large : le plongeon parcourt ~11 m à l'horizontale (dive_speed = 13
	# m/s sur ~0.85 s de vol) — un sol trop petit le ferait sortir du bord
	# avant d'atterrir et fausserait le test (c'est d'ailleurs un AUTRE cas
	# réel que la minuterie de sécurité couvre : plongeon au-dessus du vide).
	var o := _offset()
	_floor(o, Vector3(60, 1, 60))
	var player := await _grounded_bot(o)

	player.state_machine.transition_to("Dive", {})
	assert_str(player.state_machine.current_name).is_equal("Dive")

	var ticks := 0
	var max_ticks := 80  # ~1.33 s à 60 Hz : largement suffisant pour un atterrissage normal.
	while player.state_machine.current_name == "Dive" and ticks < max_ticks:
		await get_tree().physics_frame
		ticks += 1

	assert_str(player.state_machine.current_name).append_failure_message(
		"un plongeon normal (aucun obstacle) doit atterrir et passer en Roll — état obtenu après %d ticks : %s"
			% [ticks, player.state_machine.current_name]
	).is_equal("Roll")
	assert_int(ticks).append_failure_message(
		"l'atterrissage normal a pris %d ticks physiques : trop proche du délai de sécurité (60 ticks = 1 s), suspect"
			% ticks
	).is_less(55)
