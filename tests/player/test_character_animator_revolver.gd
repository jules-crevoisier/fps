## test_character_animator_revolver.gd
## Spec (design verrouillé utilisateur, tâche "revolver" 2026-09-27) : "When a
## peer has the revolver equipped..., the upper-body layer uses Pistol_*
## instead of Rifle_*" — CharacterAnimator.upper_body_clip_prefix_for_weapon
## (logique pure) + bascule DYNAMIQUE réelle sur un bot (même méthode
## organique que tests/player/test_frog_cowboy_character.gd::_bot_player).
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _next_offset_index := 0


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


func _bot_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	player.set("is_bot", true)
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	auto_free(player)
	return player


func _wait_physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


# ---------------------------------------------------------------- fonction PURE
func test_pistol_category_switches_to_pistol_prefix_when_clips_exist() -> void:
	assert_str(CharacterAnimator.upper_body_clip_prefix_for_weapon("Rifle_", WeaponConfig.Category.PISTOL, true)) \
		.is_equal("Pistol_")


func test_pistol_category_falls_back_to_primary_prefix_without_pistol_clips() -> void:
	# Contrat "fall back without crashing" tant que Pistol_* n'est pas livré.
	assert_str(CharacterAnimator.upper_body_clip_prefix_for_weapon("Rifle_", WeaponConfig.Category.PISTOL, false)) \
		.is_equal("Rifle_")


func test_rifle_category_keeps_the_primary_prefix_regardless_of_pistol_clips() -> void:
	assert_str(CharacterAnimator.upper_body_clip_prefix_for_weapon("Rifle_", WeaponConfig.Category.RIFLE, true)) \
		.is_equal("Rifle_")


func test_unknown_category_keeps_the_primary_prefix() -> void:
	assert_str(CharacterAnimator.upper_body_clip_prefix_for_weapon("Pistol_", -1, true)).is_equal("Pistol_")


# ---------------------------------------------------------------- bascule réelle (bot)
func _ready_bot() -> Dictionary:
	var player := _bot_player(_offset())
	await _wait_physics(3)
	var character_body := player.get_node("%CharacterModel") as CharacterBody
	var anim := player.get_node("CharacterAnimator") as CharacterAnimator
	assert_bool(character_body.is_model_ready()).append_failure_message(
		"préalable du test : le modèle du corps doit être chargé"
	).is_true()
	assert_bool(anim.get("_built")).append_failure_message(
		"préalable du test : l'arbre de blend de CharacterAnimator doit être construit"
	).is_true()
	return {"player": player, "anim": anim}


func _active_prefix(anim: CharacterAnimator) -> String:
	return anim.get("_active_clip_prefix")


func test_bot_starts_on_the_rifle_prefix_with_the_ravage_equipped() -> void:
	var ctx := await _ready_bot()
	var anim: CharacterAnimator = ctx["anim"]
	assert_str(_active_prefix(anim)).append_failure_message(
		"préalable : le Ravage (RIFLE) doit garder le préfixe Rifle_ pour frog_cowboy"
	).is_equal("Rifle_")


func test_equipping_the_revolver_switches_the_upper_body_layer_to_pistol_clips() -> void:
	var ctx := await _ready_bot()
	var player: PlayerController = ctx["player"]
	var anim: CharacterAnimator = ctx["anim"]
	var weapon := player.get_node("Weapon") as Weapon

	weapon.equip_weapon_slot(1)  # slot 2 = Revolver (WeaponDatabase.default_loadout_ids).
	await _wait_physics(1)

	assert_str(weapon.cfg().weapon_name).append_failure_message(
		"préalable du test : le changement vers le revolver n'a pas abouti"
	).is_equal("Revolver")
	assert_str(_active_prefix(anim)).append_failure_message(
		"le revolver équipé doit basculer le haut du corps sur Pistol_ (jamais Rifle_)"
	).is_equal("Pistol_")

	var bt := anim.tree_root as AnimationNodeBlendTree
	var idle_breath := bt.get_node("IdleBreath") as AnimationNodeAnimation
	assert_str(idle_breath.animation).append_failure_message(
		"le nœud IdleBreath doit être re-pointé sur Pistol_Idle une fois le revolver équipé"
	).is_equal("Pistol_Idle")


func test_re_equipping_the_ravage_reverts_the_upper_body_layer_to_rifle_clips() -> void:
	var ctx := await _ready_bot()
	var player: PlayerController = ctx["player"]
	var anim: CharacterAnimator = ctx["anim"]
	var weapon := player.get_node("Weapon") as Weapon

	weapon.equip_weapon_slot(1)
	await _wait_physics(1)
	weapon.equip_weapon_slot(0)
	await _wait_physics(1)

	assert_str(weapon.cfg().weapon_name).is_equal("Ravage")
	assert_str(_active_prefix(anim)).append_failure_message(
		"reprendre le Ravage doit revenir sur Rifle_ (jamais rester bloqué sur Pistol_)"
	).is_equal("Rifle_")
