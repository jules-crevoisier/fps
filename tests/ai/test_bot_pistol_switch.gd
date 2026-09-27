## test_bot_pistol_switch.gd
## Spec (contrat lead, tâche "revolver" 2026-09-27) : "Bots already have
## 'pistol_slot' logic in BotBrain/BotCombatStyle; make sure they can use it
## (they switch when the rifle is empty, etc.) without crashing." Avant cette
## tâche, `BotCombatStyle.PISTOL_WEAPON_NAME` valait "Pistolet", un nom hérité
## d'un roster d'armes supprimé -- `BotBrain._pistol_slot` ne trouvait donc
## JAMAIS de correspondance (0 crash, mais totalement inerte). Ce fichier
## prouve le chemin RÉEL, bout en bout (joueur BOT réel, autorité SERVEUR,
## même méthode organique que tests/combat/test_fire_while_sprinting.gd) :
## Ravage à sec (chargeur ET réserve) -> BotBrain demande le slot 2 (revolver)
## -> Weapon._owner_tick traite la demande comme pour un humain -> l'arme
## équipée devient bien le Revolver.
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _next_offset_index := 0


func before_test() -> void:
	get_tree().current_scene = self


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


func _wait_physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_pistol_slot_resolves_to_the_revolver_slot() -> void:
	var player := await _ready_bot()
	var weapon := player.get_node("Weapon") as Weapon
	var brain := player.get_node("BotBrain") as BotBrain
	# Emplacement 0 (Ravage) exclu -> doit trouver le Revolver au slot 1.
	assert_int(brain._pistol_slot(weapon, 0)).append_failure_message(
		"BotBrain._pistol_slot doit désormais trouver le Revolver (slot 1) -- "
			+ "PISTOL_WEAPON_NAME doit correspondre à une arme RÉELLE du catalogue"
	).is_equal(1)


func test_bot_requests_the_revolver_slot_when_the_ravage_runs_dry() -> void:
	var player := await _ready_bot()
	var weapon := player.get_node("Weapon") as Weapon
	var brain := player.get_node("BotBrain") as BotBrain
	assert_str(weapon.cfg().weapon_name).append_failure_message(
		"préalable du test : le Ravage doit être l'arme courante au spawn"
	).is_equal("Ravage")

	# Vide le Ravage : chargeur ET réserve à zéro (§2.7 "il passe au pistolet").
	weapon._inv.mag[0] = 0
	weapon._inv.reserve[0] = 0

	player.input.weapon_slot_pressed = -1
	brain._tick_ammo(false)  # hors combat.

	assert_int(player.input.weapon_slot_pressed).append_failure_message(
		"un bot à sec sur le Ravage (chargeur ET réserve) doit demander le slot 2 (revolver)"
	).is_equal(1)


func test_bot_actually_switches_to_the_revolver_after_the_request() -> void:
	var player := await _ready_bot()
	var weapon := player.get_node("Weapon") as Weapon
	var brain := player.get_node("BotBrain") as BotBrain

	weapon._inv.mag[0] = 0
	weapon._inv.reserve[0] = 0
	brain._tick_ammo(false)
	# Laisse Weapon._owner_tick traiter la demande (comme pour un humain, voir
	# Weapon._handle_switch_input) et le délai de changement d'arme s'écouler
	# (Weapon.SWITCH_DELAY = 0.25 s = 15 tics à 60 Hz, marge prise).
	await _wait_physics(20)

	assert_str(weapon.cfg().weapon_name).append_failure_message(
		"le bot doit réellement équiper le Revolver une fois la demande traitée par Weapon.gd -- "
			+ "sans crash (contrat : \"make sure they can use it ... without crashing\")"
	).is_equal("Revolver")


func test_bot_does_not_request_a_switch_while_the_ravage_still_has_ammo() -> void:
	var player := await _ready_bot()
	var weapon := player.get_node("Weapon") as Weapon
	var brain := player.get_node("BotBrain") as BotBrain

	player.input.weapon_slot_pressed = -1
	brain._tick_ammo(false)  # chargeur/réserve intacts au spawn.

	assert_int(player.input.weapon_slot_pressed).append_failure_message(
		"un bot avec un chargeur/une réserve non vides ne doit jamais demander le pistolet"
	).is_equal(-1)


## Spawne au sommet du sol, force le contact réel jusqu'à l'état Idle — même
## méthode que tests/combat/test_slide_fire.gd::_grounded_bot (un bot qui
## tombe encore/n'est jamais passé par Idle a laissé des orphelins constatés
## avec une attente plus courte).
func _ready_bot() -> PlayerController:
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
	var t := 0
	while t < 30 and not (player.is_on_floor() and player.state_machine.current_name == "Idle"):
		if player.state_machine.current_name != "Idle" and player.is_on_floor():
			player.state_machine.transition_to("Idle")
		await get_tree().physics_frame
		t += 1
	return player
