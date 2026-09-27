## test_inventory_server_authority.gd
## Spec (contrat lead 2026-09-27, "inventaire CS-style", point 8) : "the
## server REJECTS weapon shots while a utility is equipped, and rejects a
## throw whose kind is not the equipped one" — vérifié directement sur les
## méthodes serveur (`Weapon._server_fire`/`UtilityThrower._server_throw`),
## même méthode organique qu'un joueur BOT serveur-autoritaire (nom >=
## PlayerController.BOT_ID_START) que tests/combat/test_fire_while_sprinting.gd.
## `_server_select_utility` est appelée directement pour PRÉPARER l'état
## (équiper une grenade) : ce n'est pas le comportement sous test ici (voir
## tests/combat/utility/test_utility_equip.gd et
## tests/combat/test_inventory_selection.gd pour la logique pure d'équipement),
## seulement une étape d'arrangement.
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


## Même méthode que test_fire_while_sprinting.gd::_bot_player -- nom >=
## BOT_ID_START => autorité SERVEUR (PlayerController._enter_tree), donc
## Weapon/UtilityThrower._physics_process tournent réellement en test headless.
func _bot_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	player.set("is_bot", true)
	auto_free(player)
	return player


func _sender_id(player: PlayerController) -> int:
	return str(player.name).to_int()


func _weapon(player: PlayerController) -> Weapon:
	return player.get_node("Weapon") as Weapon


func _utility(player: PlayerController) -> UtilityThrower:
	return player.get_node("UtilityThrower") as UtilityThrower


func _wait_physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _spawn_ready_player() -> PlayerController:
	var o := _offset()
	_floor(o)
	var player := _bot_player(o)
	await _wait_physics(2)
	return player


# ======================================================================
#  "the server REJECTS weapon shots while a utility is equipped"
# ======================================================================

## Contrôle positif : prouve que le test suivant rejette bien À CAUSE de la
## grenade équipée, pas pour une autre raison (préalable de scène invalide).
## `_server_fire` est appelée DIRECTEMENT (comme le test suivant, voir sa
## docstring de classe) : `weapon.mag`/`weapon.current` lisent la copie
## PRÉDITE (`_inv`), jamais mise à jour par cet appel direct qui ne passe pas
## par `_fire_local` (seul `_server_inv`, l'autoritaire, bouge ici) — la seule
## assertion fiable dans ce contournement est donc `rejected_shots`, pas le
## chargeur (voir aussi `_server_inv` non exposé publiquement pour vérifier
## la consommation autoritaire directement).
func test_weapon_shot_is_accepted_when_no_utility_is_equipped() -> void:
	var player := await _spawn_ready_player()
	var weapon := _weapon(player)
	var sender_id := _sender_id(player)
	var rejected_before := weapon.rejected_shots

	weapon._server_fire(sender_id, player.head.global_position, [Vector3(0, 0, -1)], WeaponDatabase.id_of(weapon.cfg()))

	assert_int(weapon.rejected_shots).append_failure_message(
		"préalable du test : un tir sans grenade équipée ne doit PAS être refusé"
	).is_equal(rejected_before)


func test_weapon_shot_is_rejected_while_a_utility_is_equipped() -> void:
	var player := await _spawn_ready_player()
	var weapon := _weapon(player)
	var utility := _utility(player)
	var sender_id := _sender_id(player)

	utility._server_select_utility(sender_id, UtilityDatabase.FRAG)
	assert_bool(utility.is_server_utility_equipped()).append_failure_message(
		"préalable du test : la grenade doit être équipée côté serveur"
	).is_true()

	var mag_before: int = weapon.mag[weapon.current]
	var rejected_before := weapon.rejected_shots

	weapon._server_fire(sender_id, player.head.global_position, [Vector3(0, 0, -1)], WeaponDatabase.id_of(weapon.cfg()))

	assert_int(weapon.rejected_shots).append_failure_message(
		"un tir d'arme doit être refusé tant qu'une grenade est équipée côté serveur"
	).is_equal(rejected_before + 1)
	assert_int(weapon.mag[weapon.current]).append_failure_message(
		"aucune munition ne doit être consommée sur un tir refusé"
	).is_equal(mag_before)


# ======================================================================
#  "rejects a throw whose kind is not the equipped one"
# ======================================================================

func test_throw_of_the_equipped_kind_is_accepted() -> void:
	# Contrôle positif : même raison que le test symétrique ci-dessus.
	var player := await _spawn_ready_player()
	var utility := _utility(player)
	var sender_id := _sender_id(player)
	utility._server_select_utility(sender_id, UtilityDatabase.FRAG)
	_wait_deploy_delay(utility)

	var head_pos: Vector3 = player.head.global_position
	utility._server_throw(sender_id, UtilityDatabase.FRAG, head_pos, Vector3(0, 0, -1), 0.0, false, false)

	assert_int(utility.snapshot_charges()[UtilityDatabase.FRAG]).append_failure_message(
		"préalable du test : un lancer du type ÉQUIPÉ doit consommer sa charge (donc être accepté)"
	).is_equal(0)


func test_throw_of_a_kind_other_than_the_equipped_one_is_rejected() -> void:
	var player := await _spawn_ready_player()
	var utility := _utility(player)
	var sender_id := _sender_id(player)
	utility._server_select_utility(sender_id, UtilityDatabase.FRAG)
	_wait_deploy_delay(utility)

	var head_pos: Vector3 = player.head.global_position
	# Le client annonce FLASH alors que seule la frag est équipée.
	utility._server_throw(sender_id, UtilityDatabase.FLASH, head_pos, Vector3(0, 0, -1), 0.0, false, false)

	assert_int(utility.snapshot_charges()[UtilityDatabase.FLASH]).append_failure_message(
		"un lancer d'un type NON équipé ne doit jamais consommer sa charge (requête rejetée)"
	).is_equal(1)
	assert_int(utility.snapshot_charges()[UtilityDatabase.FRAG]).append_failure_message(
		"la charge du type réellement équipé (frag) ne doit pas non plus bouger sur une requête rejetée"
	).is_equal(1)


## Écoule le délai de déploiement (contrat point 4, UtilityEquip.DEPLOY_DELAY_S)
## directement sur la copie SERVEUR, pour isoler le test de rejet de type de
## celui du délai de déploiement (couvert séparément par
## tests/combat/utility/test_utility_equip.gd).
func _wait_deploy_delay(utility: UtilityThrower) -> void:
	utility._server_equip.tick(UtilityEquip.DEPLOY_DELAY_S)


## Retour utilisateur 2026-09-27 : le LANCEUR voit les dégâts de sa frag (chiffre de
## dégâts, dessiné sans test de profondeur -> visible même derrière un mur), comme
## pour une balle ; jamais de chiffre pour les dégâts qu'il s'inflige à lui-même.
func test_frag_damage_shows_a_damage_number_to_the_thrower() -> void:
	var o := _offset()
	_floor(o)
	var thrower := _bot_player(o + Vector3(0, 1, 0))
	var target := _bot_player(o + Vector3(0, 1, -4))
	thrower.team = 0
	target.team = 1
	await _wait_physics(3)
	var hp := target.get_node("Health") as Health
	var hp_before := hp.current_health
	var cfg := UtilityDatabase.get_by_id(UtilityDatabase.FRAG)
	var before := _damage_numbers().size()
	# Explosion à 1 m devant la poitrine RÉELLE de la cible (lue après l'attente).
	var blast: Vector3 = target.head.global_position + Vector3(0, -0.3, 1.0)
	_utility(thrower)._apply_frag_effects_to([target], blast, cfg, _sender_id(thrower), 0)
	assert_float(hp.current_health).is_less(hp_before)
	assert_int(_damage_numbers().size()).append_failure_message(
		"la frag qui touche doit afficher un chiffre de dégâts chez le lanceur"
	).is_greater(before)


func test_frag_self_damage_shows_no_damage_number() -> void:
	var o := _offset()
	_floor(o)
	var thrower := _bot_player(o + Vector3(0, 1, 0))
	thrower.team = 0
	await _wait_physics(3)
	var cfg := UtilityDatabase.get_by_id(UtilityDatabase.FRAG)
	var before := _damage_numbers().size()
	var blast: Vector3 = thrower.head.global_position + Vector3(0, -0.3, 1.0)
	_utility(thrower)._apply_frag_effects_to([thrower], blast, cfg, _sender_id(thrower), 0)
	assert_int(_damage_numbers().size()).is_equal(before)


func _damage_numbers() -> Array:
	var out: Array = []
	for c in get_children():
		if c is DamageNumber3D:
			out.append(c)
	return out

