## test_respawn_state_reset.gd
## Spec (BUG-07, docs/audit/bugs.md) : après une réapparition depuis une chute
## / en l'air, `_do_respawn()` doit remettre à zéro TOUT l'état transitoire de
## chute/saut (`_air_peak_y`, `_was_on_floor`, `_roll_buffer_timer`,
## `_jump_buffer_timer`, `_coyote_timer`) — sinon un `_air_peak_y` resté haut
## déclenche un Stun/Roll fantôme au premier atterrissage post-spawn, et un
## buffer de saut/coyote resté positif déclenche un saut involontaire. De plus
## `slide_jumped` doit être effacé sur les chemins Roll/Stun de
## `_check_fall_stun()` (Air -> Roll/Stun direct, qui ne passe PAS par
## `Air._land()` — seul endroit qui l'effaçait avant ce correctif).
##
## Scène physique minimale et réelle (StaticBody3D pour le sol + instance
## réelle de scenes/player/player.tscn, synchronisée via
## `await get_tree().physics_frame`), même méthode que
## tests/agents/test_ability_rays.gd. Le joueur est spawné en BOT (id >=
## PlayerController.BOT_ID_START, `is_bot = true`) pour obtenir l'autorité
## SERVEUR sans déclencher la branche "humain local" de `_ready()` (capture
## souris/caméra — sans intérêt ici, voir `PlayerController.is_local_human`).
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _next_offset_index := 0


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


## Sol de décor (StaticBody3D, calque WORLD) dont la surface haute est
## exactement à `top.y` — même construction que
## tests/agents/test_ability_rays.gd::_decor_body.
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


## Instance réelle du joueur, spawnée comme un BOT (autorité SERVEUR — voir
## PlayerController._enter_tree) pour que `_physics_process` tourne bien en
## test headless, sans capture souris/caméra (branche humain local).
func _bot_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	player.set("is_bot", true)
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	auto_free(player)
	return player


# ------------------------------------------------- _do_respawn : reset direct

func test_do_respawn_resets_air_peak_y_to_the_respawn_height() -> void:
	var o := _offset()
	_floor(o)
	var player := _bot_player(o + Vector3(0, 5, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Chute en cours au moment du respawn : sommet d'altitude resté haut,
	# comme un joueur mort en l'air ou une manche qui recommence pendant une chute.
	player._air_peak_y = o.y + 40.0

	player._do_respawn(o)

	assert_float(player._air_peak_y).append_failure_message(
		"_air_peak_y doit repartir de la position de spawn, pas rester à l'altitude de la chute précédente"
	).is_equal_approx(o.y, 0.01)


func test_do_respawn_resets_was_on_floor_so_the_next_tick_is_never_read_as_a_landing() -> void:
	var o := _offset()
	_floor(o)
	var player := _bot_player(o + Vector3(0, 5, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	player._was_on_floor = false  # comme un joueur mort en l'air

	player._do_respawn(o)

	assert_bool(player._was_on_floor).append_failure_message(
		"le premier _check_fall_stun() après spawn ne doit jamais être lu comme un atterrissage"
	).is_true()


func test_do_respawn_clears_jump_buffer_roll_buffer_and_coyote_timer() -> void:
	var o := _offset()
	_floor(o)
	var player := _bot_player(o + Vector3(0, 5, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Appuis mémorisés juste avant la téléportation (saut + dive).
	player._jump_buffer_timer = player.config.jump_buffer_time
	player._roll_buffer_timer = player.config.land_roll_window_max
	player._coyote_timer = player.config.coyote_time

	player._do_respawn(o)

	assert_float(player._jump_buffer_timer).append_failure_message(
		"un saut bufferisé avant le respawn ne doit pas déclencher un saut involontaire au spawn"
	).is_equal(0.0)
	assert_float(player._roll_buffer_timer).append_failure_message(
		"une roulade bufferisée avant le respawn ne doit pas déclencher une roulade fantôme au spawn"
	).is_equal(0.0)
	assert_float(player._coyote_timer).is_equal(0.0)


func test_do_respawn_clears_slide_jumped() -> void:
	var o := _offset()
	_floor(o)
	var player := _bot_player(o + Vector3(0, 5, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	player.slide_jumped = true

	player._do_respawn(o)

	assert_bool(player.slide_jumped).is_false()


func test_do_respawn_transitions_to_idle() -> void:
	var o := _offset()
	_floor(o)
	var player := _bot_player(o + Vector3(0, 5, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	player._do_respawn(o)

	assert_str(player.state_machine.current_name).is_equal("Idle")


# --------------------------------------------- premier tick physique réel

func test_first_physics_tick_after_respawn_from_height_triggers_no_stun_no_roll_no_jump() -> void:
	# Reproduit EXACTEMENT le scénario du bug (docs/audit/bugs.md BUG-07) :
	# un joueur qui vient de tomber de haut (ou de mourir en l'air) est
	# respawné au sol, avec un saut/dive encore "bufferisé" au moment du
	# respawn (appui juste avant la téléportation).
	var o := _offset()
	_floor(o)
	var player := _bot_player(o + Vector3(0, 5, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	player._air_peak_y = o.y + 40.0
	player._was_on_floor = false
	player._jump_buffer_timer = player.config.jump_buffer_time
	player._roll_buffer_timer = player.config.land_roll_window_max
	player._coyote_timer = player.config.coyote_time

	player._do_respawn(o)

	# Tick(s) physique(s) réel(s) suivants : c'est là que le bug se manifestait
	# (Stun/Roll fantôme, saut involontaire).
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_str(player.state_machine.current_name).append_failure_message(
		"état après le premier tick post-respawn : %s (attendu Idle/Air, jamais Stun ni Roll)"
			% player.state_machine.current_name
	).is_not_equal("Stun")
	assert_str(player.state_machine.current_name).is_not_equal("Roll")
	assert_float(player.velocity.y).append_failure_message(
		"velocity.y = %.2f : un saut involontaire a été déclenché au respawn (jump_velocity = %.2f)"
			% [player.velocity.y, player.config.jump_velocity]
	).is_less(player.config.jump_velocity * 0.5)


# --------------------------------------- slide_jumped effacé (chemins Roll/Stun)

func test_slide_jumped_cleared_when_check_fall_stun_transitions_to_stun() -> void:
	var o := _offset()
	_floor(o)
	var player := _bot_player(o)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Pose le joueur au sol (is_on_floor() vrai) sans dépendre d'une vraie
	# chute complète — même but que `_land_at` implicite des autres tests :
	# on exerce directement la fonction contractuelle (`_check_fall_stun`).
	player.velocity = Vector3(0, -1, 0)
	player.move_and_slide()
	assert_bool(player.is_on_floor()).append_failure_message(
		"préalable du test : le joueur doit être détecté au sol"
	).is_true()

	player.slide_jumped = true
	player._was_on_floor = false            # flanc d'atterrissage
	player._air_peak_y = o.y + 40.0          # chute largement au-dessus de fall_max_height

	player._check_fall_stun()

	assert_str(player.state_machine.current_name).append_failure_message(
		"préalable du test : le stun aurait dû se déclencher"
	).is_equal("Stun")
	assert_bool(player.slide_jumped).append_failure_message(
		"un slide-jump resté vrai avant ce stun fausse le PROCHAIN slide (plus de boost de vitesse)"
	).is_false()


func test_slide_jumped_cleared_when_check_fall_stun_transitions_to_roll() -> void:
	var o := _offset()
	_floor(o)
	var player := _bot_player(o)
	await get_tree().physics_frame
	await get_tree().physics_frame

	player.velocity = Vector3(0, -1, 0)
	player.move_and_slide()
	assert_bool(player.is_on_floor()).append_failure_message(
		"préalable du test : le joueur doit être détecté au sol"
	).is_true()

	player.slide_jumped = true
	player._was_on_floor = false             # flanc d'atterrissage
	player._roll_buffer_timer = player.config.land_roll_window_max  # dive bufferisé

	player._check_fall_stun()

	assert_str(player.state_machine.current_name).append_failure_message(
		"préalable du test : la roulade d'atterrissage aurait dû se déclencher"
	).is_equal("Roll")
	assert_bool(player.slide_jumped).append_failure_message(
		"un slide-jump resté vrai avant cette roulade fausse le PROCHAIN slide (plus de boost de vitesse)"
	).is_false()
