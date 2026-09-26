## test_fall_stun.gd
## Spec (MV-03, tasks/backlog.yaml/docs/research/01_game_feel.md #16) : le
## stun de chute est ADOUCI — plus une "perte de contrôle totale en plein
## combat, frustrante en compétitif" (jusqu'à 2,5 s figé), mais une coupure
## COURTE (0,6 s max) qui ne se déclenche qu'à partir d'une chute franche.
## Critères d'acceptation exacts :
##  - fall_min_height 6 m, stun_max_time 0.6 s (MovementConfig) ;
##  - chute de 5 m -> aucun stun ; chute de 14 m -> stun de 0.6 s ;
##  - dispersion de tir additionnelle pendant le stun : +3° (config seule —
##    la dispersion elle-même et le déblocage du tir vivent dans Weapon.gd/
##    WeaponFeel.gd, hors de ma liste de fichiers pour cette tâche, voir la
##    docstring de Stun.gd).
##
## Deux niveaux de test, même convention que tests/player/test_stair_step.gd
## et tests/player/test_respawn_state_reset.gd :
##  - unitaire, direct sur les valeurs par défaut de `MovementConfig` ;
##  - intégration, sur une instance RÉELLE de scenes/player/player.tscn,
##    en pilotant directement `PlayerController._check_fall_stun()` (fonction
##    contractuelle déjà exercée telle quelle par test_respawn_state_reset.gd
##    ::test_slide_jumped_cleared_when_check_fall_stun_transitions_to_stun —
##    PlayerController.gd n'est PAS dans ma liste de fichiers, mais sa logique
##    de déclenchement n'est pas modifiée par cette tâche : seules les valeurs
##    de MovementConfig qu'elle consomme changent).
##
## Étendu par GF-29 (docs/research/01_game_feel.md, câblage GF-08/MV-03 en
## jeu) : PlayerController._maybe_stun() est désormais DANS ma liste de
## fichiers et lit `GameMode.fall_stun_enabled` (groupe "game_mode") avant de
## déclencher le stun — Duel/Duo/Litige (manches, RoundMode.
## respawns_immediately() == false) le désactivent déjà ; TDM/Hardpoint
## (arène, respawn immédiat) le gardent activé. La dispersion de tir
## additionnelle pendant le stun (+3°) et le déblocage de Weapon._can_act()
## restent testés dans tests/player/test_camera_shake_wiring.gd (même tâche,
## autre fichier possédé).
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _next_offset_index := 0


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


## Sol de décor (StaticBody3D, calque WORLD), même construction que
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


## Instance réelle du joueur, spawnée comme un BOT (autorité SERVEUR), même
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


## Joueur posé au sol (is_on_floor() vrai) prêt pour un appel direct à
## `_check_fall_stun()`, avec le flanc d'atterrissage simulé — même recette
## que test_respawn_state_reset.gd::test_slide_jumped_cleared_when_check_
## fall_stun_transitions_to_stun.
func _landed_bot(o: Vector3, fall_height: float) -> PlayerController:
	var player := _bot_player(o)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.velocity = Vector3(0, -1, 0)
	player.move_and_slide()
	assert_bool(player.is_on_floor()).append_failure_message(
		"préalable du test : le joueur doit être détecté au sol"
	).is_true()
	player._was_on_floor = false  # flanc d'atterrissage
	player._air_peak_y = o.y + fall_height
	return player


# ============================================================ MovementConfig

func test_default_fall_min_height_is_6_meters() -> void:
	var config := MovementConfig.new()
	assert_float(config.fall_min_height).append_failure_message(
		"fall_min_height par défaut doit être 6 m (critère d'acceptation MV-03)"
	).is_equal_approx(6.0, 0.001)


func test_default_stun_max_time_is_0_6_seconds() -> void:
	var config := MovementConfig.new()
	assert_float(config.stun_max_time).append_failure_message(
		"stun_max_time par défaut doit être 0.6 s (critère d'acceptation MV-03 : stun adouci)"
	).is_equal_approx(0.6, 0.001)


func test_default_stun_min_time_stays_below_the_new_max() -> void:
	var config := MovementConfig.new()
	assert_float(config.stun_min_time).append_failure_message(
		"stun_min_time (%.2f) doit rester strictement inférieur au nouveau stun_max_time (%.2f), sinon le remap de _maybe_stun n'a plus de sens"
			% [config.stun_min_time, config.stun_max_time]
	).is_less(config.stun_max_time)


func test_default_stun_fire_spread_add_is_3_degrees() -> void:
	var config := MovementConfig.new()
	assert_float(config.stun_fire_spread_add).append_failure_message(
		"stun_fire_spread_add par défaut doit être 3° (critère d'acceptation MV-03 : dispersion additionnelle pendant le stun)"
	).is_equal_approx(3.0, 0.001)


func test_default_movement_resource_inherits_the_softened_stun_values() -> void:
	# resources/movement/default_movement.tres ne surcharge aucune propriété
	# (voir son contenu .tres) : il doit donc hériter tel quel des nouvelles
	# valeurs par défaut du script — pas besoin d'override explicite.
	var config: MovementConfig = load("res://resources/movement/default_movement.tres")
	assert_float(config.fall_min_height).is_equal_approx(6.0, 0.001)
	assert_float(config.stun_max_time).is_equal_approx(0.6, 0.001)
	assert_float(config.stun_fire_spread_add).is_equal_approx(3.0, 0.001)


# ================================================== Intégration : hauteur de chute

func test_falling_5_meters_never_triggers_stun() -> void:
	var o := _offset()
	_floor(o)
	var player := await _landed_bot(o, 5.0)  # < fall_min_height (6 m)

	player._check_fall_stun()

	assert_str(player.state_machine.current_name).append_failure_message(
		"une chute de 5 m (sous fall_min_height = 6 m) ne doit déclencher AUCUN stun — état obtenu : %s"
			% player.state_machine.current_name
	).is_not_equal("Stun")


func test_falling_14_meters_triggers_a_0_6_second_stun() -> void:
	var o := _offset()
	_floor(o)
	var player := await _landed_bot(o, 14.0)  # == fall_max_height : stun maximal

	player._check_fall_stun()

	assert_str(player.state_machine.current_name).append_failure_message(
		"une chute de 14 m (>= fall_max_height) doit déclencher le stun — état obtenu : %s"
			% player.state_machine.current_name
	).is_equal("Stun")
	assert_float(player.state_machine.current._duration).append_failure_message(
		"une chute de 14 m doit produire la durée de stun MAXIMALE, soit stun_max_time = 0.6 s (critère d'acceptation MV-03)"
	).is_equal_approx(0.6, 0.005)


func test_falling_well_beyond_14_meters_stays_clamped_to_0_6_seconds() -> void:
	# Garde de non-régression : le clamp de `_maybe_stun` ne doit jamais
	# produire un stun plus long que stun_max_time, même très au-delà de
	# fall_max_height (chute depuis toute la hauteur d'une carte verticale).
	var o := _offset()
	_floor(o)
	var player := await _landed_bot(o, 40.0)

	player._check_fall_stun()

	assert_str(player.state_machine.current_name).is_equal("Stun")
	assert_float(player.state_machine.current._duration).append_failure_message(
		"une chute bien au-delà de fall_max_height ne doit jamais dépasser stun_max_time (0.6 s)"
	).is_equal_approx(0.6, 0.005)


# ============================================== Intégration : GameMode.fall_stun_enabled (GF-29)
# Même méthode d'instanciation qu'ailleurs dans la suite de tests (voir par ex.
# tests/player/test_ping.gd::test_server_ping_defend_reports_an_enemy_sighting_to_the_game_mode) :
# `mode.add_to_group("game_mode")` AVANT `add_child` (la classe GameMode le
# refait de toute façon dans son propre `_ready()`, mais l'appel explicite
# évite toute dépendance à l'ordre d'exécution de `_ready()` dans ce test).

func test_fall_stun_still_triggers_in_tdm_mode_for_a_14_meter_fall() -> void:
	var mode := TDMMode.new()
	mode.add_to_group("game_mode")
	add_child(mode)
	auto_free(mode)
	var o := _offset()
	_floor(o)
	var player := await _landed_bot(o, 14.0)

	player._check_fall_stun()

	assert_str(player.state_machine.current_name).append_failure_message(
		"le TDM (arène, respawn immédiat, GameMode.fall_stun_enabled == true) doit garder le stun de chute -- état obtenu : %s"
			% player.state_machine.current_name
	).is_equal("Stun")
	assert_float(player.state_machine.current._duration).append_failure_message(
		"le stun en TDM sur une chute de 14 m doit rester à stun_max_time = 0.6 s (critère d'acceptation GF-29)"
	).is_equal_approx(0.6, 0.005)
