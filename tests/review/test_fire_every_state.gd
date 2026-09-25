## test_fire_every_state.gd
## Test de régression CI (OPS-02B) : le tir doit rester POSSIBLE dans tous les
## états de mouvement SAUF Dive/Roll (restriction VOULUE — voir
## Weapon._can_act() et WeaponFeel.fire_delay_left()/_since_slide/_since_dive
## dans Weapon._owner_tick). Bug d'origine (retour joueur) : « on ne peut pas
## tirer si on ne saute pas » — l'absence d'un filet de test couvrant "tirer
## dans TOUS les états de mouvement" avait laissé passer cette régression.
##
## Porte la MÊME table de résultats attendus que tools/review/gameplay_probe.gd
## (sonde complète fenêtrée/headless, lancée manuellement par la revue), mais
## tourne ICI en CI à chaque suite gdUnit4 (`res://tests`) : scène physique
## minimale et réelle (StaticBody3D pour le sol + instance réelle de
## scenes/player/player.tscn en BOT serveur-autoritaire) — même méthode que
## tests/player/test_state_exits.gd. Les états sont atteints ORGANIQUEMENT via
## `player.input` (comme le ferait un vrai joueur/bot, PAS via
## `state_machine.transition_to()`) pour Idle/Walk/Sprint/Crouch/Air/Slide/
## Dive : seuls Roll et Stun sont forcés directement (atteindre une roulade
## d'atterrissage ou un étourdissement réel exigerait un vol/une chute
## minutés, hors sujet ici — Weapon._can_act() ne regarde que le NOM de
## l'état, jamais comment on y est entré).
##
## | État    | Tir attendu | Raison                                                |
## |---------|-------------|--------------------------------------------------------|
## | Idle    | OK          | aucune restriction                                      |
## | Walk    | OK          | aucune restriction                                      |
## | Sprint  | OK          | sprint auto (docs/MOVEMENT.md), aucun délai (BUG-K01)   |
## | Crouch  | OK          | aucune restriction                                      |
## | Air     | OK          | saut : aucune restriction                               |
## | Slide   | OK          | GF-30 (playtest 2026-09-25) : tir en glissade, dispersion |
## | Dive    | BLOQUÉ      | Weapon._can_act() exclut "Dive" explicitement           |
## | Roll    | BLOQUÉ      | Weapon._can_act() exclut "Roll" (roulade = pas d'action)|
## | Stun    | OK          | GF-29/MV-03 : stun adouci, tir avec +3° de dispersion   |
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _next_offset_index := 0


## `Weapon._spawn_tracer` (scripts/combat/Weapon.gd, hors de mon périmètre)
## pose son effet cosmétique sur `player.get_tree().current_scene` sans garde
## de nullité — jamais nul dans un vrai match (GameWorld l'EST), mais gdUnit4
## ne désigne aucune `current_scene` pour une suite de test. La suite
## elle-même est déjà un nœud bien réel de l'arbre (voir `add_child` plus
## bas) : la désigner comme scène courante suffit à satisfaire ce besoin
## cosmétique sans toucher à Weapon.gd.
func before_test() -> void:
	get_tree().current_scene = self


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


## Sol large (Sprint doit pouvoir accélérer plusieurs mètres, Dive parcourt
## ~11 m à l'horizontale) — même construction que
## tests/player/test_state_exits.gd::_floor.
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


## Instance réelle du joueur (nom >= BOT_ID_START => autorité SERVEUR, voir
## PlayerController._enter_tree/is_multiplayer_authority) pour que
## `Weapon._physics_process`/`_owner_tick` tournent bien en test headless.
## `is_bot` est posé APRÈS `add_child` (pas avant, contrairement à
## tests/player/test_state_exits.gd, qui ne pilote jamais l'entrée
## organiquement) : BotBrain.gd (enfant du joueur) lit `player.is_bot` UNE
## SEULE fois dans SON `_ready()` et s'auto-désactive à vie s'il est faux à
## cet instant précis (`set_physics_process(false)`) — le poser APRÈS laisse
## donc BotBrain inerte (aucune IA ne vient écraser `player.input.*` posé à la
## main ci-dessous) tout en satisfaisant, chaque tick suivant, le garde de
## PlayerInput._physics_process (`if is_bot: return`, avant toute lecture du
## singleton Input global — nécessaire en headless, voir
## tools/review/gameplay_probe.gd qui bascule l'hôte de la MÊME façon, APRÈS
## son spawn).
func _bot_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	player.set("is_bot", true)
	auto_free(player)
	return player


## Spawne un bot exactement au sommet du sol et force le contact réel
## (`is_on_floor()` vrai) avant de piloter l'entrée d'état — même méthode que
## tests/player/test_state_exits.gd::_grounded_bot.
func _grounded_bot(o: Vector3) -> PlayerController:
	var player := _bot_player(o)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.velocity = Vector3(0, -1, 0)
	player.move_and_slide()
	assert_bool(player.is_on_floor()).append_failure_message(
		"préalable du test : le joueur doit être détecté au sol"
	).is_true()
	# Laisse un éventuel rebond d'atterrissage (Air d'une frame) retomber en
	# Idle avant de piloter l'entrée d'état — même garde que
	# gameplay_probe.gd::_reset_player (le tout premier tick après un
	# repositionnement voit parfois `is_on_floor()` gelé au dernier
	# `move_and_slide()` d'AVANT le téléport).
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


## Vérifie l'état courant puis presse/relâche le tir : `fire_pressed` (une
## frame, semi-auto) ET `fire_held` (maintenu, auto) — couvre les deux
## `WeaponConfig.automatic` sans avoir à l'inspecter ici (même geste que
## gameplay_probe.gd::_check_fire_in_state).
func _assert_fire_in_state(player: PlayerController, expect_blocked: bool, state_name: String) -> void:
	assert_str(player.state_machine.current_name).append_failure_message(
		"préalable du test : l'état %s n'est jamais devenu actif (actuel=%s)"
			% [state_name, player.state_machine.current_name]
	).is_equal(state_name)
	var weapon := _weapon(player)
	var ammo_before: int = weapon.mag[weapon.current]
	player.input.fire_pressed = true
	player.input.fire_held = true
	await _wait_physics(1)
	player.input.fire_pressed = false
	await _wait_physics(3)
	player.input.fire_held = false
	await _wait_physics(2)
	var ammo_after: int = weapon.mag[weapon.current]
	var fired := ammo_after < ammo_before
	if expect_blocked:
		assert_bool(fired).append_failure_message(
			"tir NON bloqué en %s (munitions %d -> %d) — restriction cassée"
				% [state_name, ammo_before, ammo_after]
		).is_false()
	else:
		assert_bool(fired).append_failure_message(
			"tir bloqué à tort en %s (munitions %d -> %d)" % [state_name, ammo_before, ammo_after]
		).is_true()


# ==========================================================================
#  États AUTORISÉS
# ==========================================================================

func test_fire_ok_in_idle() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	await _assert_fire_in_state(player, false, "Idle")


func test_fire_ok_in_walk() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	player.input.walk_held = true
	player.input.move = Vector2(0, -1)  # avant (voir tests/input/test_player_input.gd)
	await _wait_physics(3)
	await _assert_fire_in_state(player, false, "Walk")


func test_fire_ok_in_sprint() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	player.input.move = Vector2(0, -1)  # sans Shift => sprint auto (docs/MOVEMENT.md)
	await _wait_physics(20)  # laisse ground_accel amener la vitesse à sprint_speed
	await _assert_fire_in_state(player, false, "Sprint")


func test_fire_ok_in_crouch() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	player.input.crouch_held = true
	await _wait_physics(3)
	await _assert_fire_in_state(player, false, "Crouch")


func test_fire_ok_in_air() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	player.input.jump_pressed = true
	player.input.jump_held = true
	await _wait_physics(1)
	player.input.jump_pressed = false
	player.input.jump_held = false
	await _wait_physics(1)
	await _assert_fire_in_state(player, false, "Air")


# ==========================================================================
#  États BLOQUÉS (restriction voulue)
# ==========================================================================

func test_fire_ok_in_slide() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	player.input.move = Vector2(0, -1)
	await _wait_physics(20)  # vitesse >= slide_min_speed (prérequis de la glissade)
	# Tap de crouch pendant le sprint => glissade (Sprint.gd) ; garder
	# `crouch_held` vrai APRÈS le tap, sinon Slide.physics_update annule la
	# glissade dès que `crouch_held` repasse à faux (slide-cancel) — même
	# geste que gameplay_probe.gd::_enter_slide_from_sprint.
	player.input.crouch_pressed = true
	player.input.crouch_held = true
	await _wait_physics(1)
	player.input.crouch_pressed = false
	await _wait_physics(2)
	await _assert_fire_in_state(player, false, "Slide")


func test_fire_blocked_in_dive() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	player.input.dive_pressed = true
	await _wait_physics(1)
	player.input.dive_pressed = false
	await _wait_physics(1)
	await _assert_fire_in_state(player, true, "Dive")


## Roulade forcée directement (`transition_to`, comme
## tests/player/test_state_exits.gd) : Weapon._can_act() ne regarde QUE le nom
## de l'état ("Roll" exclu explicitement), jamais comment on y est entré —
## reproduire un vrai plongeon+atterrissage minuté n'apporterait aucune
## couverture supplémentaire pour CE bug précis.
func test_fire_blocked_in_roll() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	player.state_machine.transition_to("Roll", {})
	assert_str(player.state_machine.current_name).append_failure_message(
		"préalable du test : la roulade doit bien être active"
	).is_equal("Roll")
	await _assert_fire_in_state(player, true, "Roll")


## Étourdissement forcé directement (même raison que Roll ci-dessus) — durée
## large (2 s) pour ne jamais expirer pendant la fenêtre de tir du check.
func test_fire_ok_in_stun() -> void:
	var o := _offset()
	_floor(o)
	var player := await _grounded_bot(o)
	player.state_machine.transition_to("Stun", {"duration": 2.0})
	assert_str(player.state_machine.current_name).append_failure_message(
		"préalable du test : l'étourdissement doit bien être actif"
	).is_equal("Stun")
	await _assert_fire_in_state(player, false, "Stun")
