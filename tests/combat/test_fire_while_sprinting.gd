## test_fire_while_sprinting.gd
## Régression BUG-26 (revue 20260924-164342) : « fire_in_state:Sprint ok=false
## — munitions 25->24, refusés 0->1 (TIR NON ACCEPTÉ ALORS QU'IL DEVRAIT
## L'ÊTRE) ». tests/review/test_fire_every_state.gd::test_fire_ok_in_sprint
## vérifie déjà qu'UN tir passe en Sprint, mais sa fenêtre de tir (4 ticks
## tenus) ne déclenche jamais un DEUXIÈME tir à la cadence de l'arme — c'est
## justement ce deuxième tir d'une même rafale que le serveur refusait à tort.
##
## Cause racine (voir le commentaire BUG-26 dans Weapon._server_fire) : le
## limiteur de cadence serveur (RateLimiter, scripts/combat/RateLimiter.gd)
## consommait `Time.get_ticks_msec()` (horloge MURALE réelle) alors que le
## client prédit sa cadence via FireClock sur le delta physique SIMULÉ (60 Hz
## fixe, scripts/combat/FireClock.gd) — à une cadence pile (aucune marge de
## burst), un écart réel plus court que l'écart simulé entre deux tics
## physiques (rattrapage moteur sous charge machine — plusieurs process Godot
## en parallèle, cf. la revue d'origine) faisait manquer au jeton le temps de
## se reconstituer et le serveur refusait un tir pourtant cadencé correctement
## côté client. Le Sprint est le SEUL état de la table `fire_in_state` où la
## gâchette reste tenue assez longtemps ET où le joueur se déplace pour que ce
## deuxième tir tombe dans la fenêtre du test — d'où une régression qui
## semblait spécifique au Sprint alors qu'elle touchait la cadence en général.
##
## Ce test tient la gâchette assez longtemps pour couvrir DEUX intervalles de
## cadence de l'arme équipée (calculé depuis `WeaponConfig.fire_rate`, jamais
## une constante en dur) tout en sprintant, et vérifie que les DEUX tirs sont
## acceptés (aucun refus, munitions -2) — même méthode organique
## (`player.input`, joueur BOT serveur-autoritaire) que
## tests/review/test_fire_every_state.gd, dont il partage les helpers de scène.
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _next_offset_index := 0


## Voir tests/review/test_fire_every_state.gd::before_test — même besoin
## cosmétique (`Weapon._spawn_tracer`/`_spawn_impact` posent leurs effets sur
## `get_tree().current_scene`, jamais nul en vrai match).
func before_test() -> void:
	get_tree().current_scene = self


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


## Sol large — même construction que
## tests/review/test_fire_every_state.gd::_floor (Sprint doit pouvoir
## accélérer plusieurs mètres avant le tir).
func _floor(top: Vector3, size: Vector3 = Vector3(60, 1, 60)) -> StaticBody3D:
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


## Instance réelle du joueur, nom >= BOT_ID_START => autorité SERVEUR (voir
## PlayerController._enter_tree) pour que Weapon._physics_process (_server_tick
## ET _owner_tick) tourne réellement en test headless — même méthode que
## tests/review/test_fire_every_state.gd::_bot_player.
func _bot_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	player.set("is_bot", true)  # APRÈS add_child : voir _bot_player d'origine (BotBrain._ready).
	auto_free(player)
	return player


## Spawne au sommet du sol, force le contact réel — même méthode que
## tests/review/test_fire_every_state.gd::_grounded_bot.
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


## Deux tirs consécutifs à la cadence de l'arme, en sprint : les DEUX doivent
## être acceptés par le serveur (BUG-26 — avant le correctif, le second était
## parfois refusé par le limiteur de cadence).
func test_fire_twice_at_fire_rate_while_sprinting_both_accepted() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	player.input.move = Vector2(0, -1)  # sans Shift => sprint auto (docs/MOVEMENT.md)
	await _wait_physics(20)  # laisse ground_accel amener la vitesse à sprint_speed
	assert_str(player.state_machine.current_name).append_failure_message(
		"préalable du test : l'état Sprint n'est jamais devenu actif (actuel=%s)"
			% player.state_machine.current_name
	).is_equal("Sprint")

	var weapon := _weapon(player)
	var cfg := weapon.cfg()
	assert_object(cfg).append_failure_message(
		"préalable du test : aucune arme équipée"
	).is_not_null()
	assert_bool(cfg.automatic).append_failure_message(
		"préalable du test : ce test tient la gâchette pour couvrir DEUX intervalles de "
			+ "cadence — il faut une arme automatique équipée par défaut (loadout, "
			+ "WeaponDatabase.default_loadout_ids)"
	).is_true()
	# Nombre de tics physiques d'UN intervalle de cadence (60 Hz fixe, comme
	# FireClock.gd) — marge de +2 tics pour absorber l'arrondi et garantir que
	# le DEUXIÈME tir tombe bien dans la fenêtre tenue.
	var interval_ticks: int = int(ceil(60.0 / cfg.fire_rate)) + 2

	var ammo_before: int = weapon.mag[weapon.current]
	var rejected_before: int = weapon.rejected_shots
	player.input.fire_pressed = true
	player.input.fire_held = true
	await _wait_physics(1)
	player.input.fire_pressed = false
	await _wait_physics(interval_ticks)
	player.input.fire_held = false
	await _wait_physics(2)
	var ammo_after: int = weapon.mag[weapon.current]
	var rejected_after: int = weapon.rejected_shots

	assert_str(player.state_machine.current_name).append_failure_message(
		"le joueur est sorti de Sprint pendant le test (actuel=%s) — invalide le scénario"
			% player.state_machine.current_name
	).is_equal("Sprint")
	assert_int(ammo_before - ammo_after).append_failure_message(
		("deux tirs attendus en sprint (cadence=%.1f/s, %d tics tenus) — munitions %d->%d : "
			+ "le second tir de la rafale n'a pas eu lieu")
			% [cfg.fire_rate, interval_ticks, ammo_before, ammo_after]
	).is_equal(2)
	assert_int(rejected_after).append_failure_message(
		"BUG-26 : tir refusé par le serveur en sprint (limiteur de cadence) — "
			+ ("munitions %d->%d, refusés %d->%d" % [ammo_before, ammo_after, rejected_before, rejected_after])
	).is_equal(rejected_before)
