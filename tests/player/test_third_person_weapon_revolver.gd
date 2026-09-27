## test_third_person_weapon_revolver.gd
## Spec (design verrouillé utilisateur, tâche "revolver" 2026-09-27) : "the 3P
## gun model is the revolver on PistolGrip" — ThirdPersonWeapon.gd attache le
## Revolver sous un os DÉDIÉ "PistolGrip" (contrat lead, frog_cowboy.glb) au
## lieu du nœud générique "WeaponSocket" utilisé par toute autre arme, avec
## repli silencieux si l'os n'existe pas encore. Même méthode organique
## (joueur "distant" simulé, voir tests/player/test_frog_cowboy_character.gd::
## _remote_player/test_weapon_keeps_its_real_world_scale_on_a_scaled_character,
## dont ce fichier reprend les helpers de scène) : ThirdPersonWeapon.gd est
## inerte pour le joueur LOCAL (voir sa docstring de classe), donc seul un
## pair DISTANT simulé l'active réellement en test headless.
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _next_offset_index := 0
var _next_peer_id := 301  # pairs "distants" simulés (jamais 1, jamais >= BOT_ID_START).


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


func _remote_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(_next_peer_id)
	_next_peer_id += 1
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	auto_free(player)
	return player


func _ready_remote() -> Dictionary:
	var player := _remote_player(_offset())
	await get_tree().physics_frame
	await get_tree().physics_frame
	var character_body := player.get_node("%CharacterModel") as CharacterBody
	assert_bool(character_body.is_model_ready()).append_failure_message(
		"préalable du test : le modèle du corps doit être chargé"
	).is_true()
	return {
		"player": player,
		"weapon": player.get_node("Weapon") as Weapon,
		"tp": player.get_node("ThirdPersonWeapon") as ThirdPersonWeapon,
		"body": character_body,
	}


func test_revolver_attaches_under_the_pistol_grip_bone() -> void:
	var ctx := await _ready_remote()
	var w: Weapon = ctx["weapon"]
	w._inv.equip(1)  # slot 2 = Revolver (WeaponDatabase.default_loadout_ids).
	w._broadcast_current_id(WeaponDatabase.id_of(w.cfg()))
	await get_tree().physics_frame

	var tp: ThirdPersonWeapon = ctx["tp"]
	var weapon_model: Node3D = tp.get("_model")
	assert_object(weapon_model).append_failure_message(
		"préalable du test : le modèle revolver doit être chargé et attaché"
	).is_not_null()
	var parent := weapon_model.get_parent() as BoneAttachment3D
	assert_object(parent).append_failure_message(
		"l'arme doit être rattachée à une BoneAttachment3D dédiée"
	).is_not_null()
	assert_str(parent.bone_name).append_failure_message(
		"le Revolver en 3P doit s'attacher sous l'os \"PistolGrip\", pas \"WeaponSocket\"/la main droite"
	).is_equal("PistolGrip")


func test_ravage_still_attaches_under_weapon_socket_unchanged() -> void:
	var ctx := await _ready_remote()
	var w: Weapon = ctx["weapon"]
	w._broadcast_current_id(w._inv.current_id())  # Ravage, arme de spawn (current=0).
	await get_tree().physics_frame

	var tp: ThirdPersonWeapon = ctx["tp"]
	var weapon_model: Node3D = tp.get("_model")
	assert_object(weapon_model).is_not_null()
	var body: CharacterBody = ctx["body"]
	var socket := body.find_child("WeaponSocket", true, false)
	assert_object(weapon_model.get_parent()).append_failure_message(
		"le Ravage doit rester attaché sous \"WeaponSocket\" (comportement inchangé par cette tâche)"
	).is_same(socket)


func test_switching_from_revolver_back_to_ravage_reattaches_under_weapon_socket() -> void:
	var ctx := await _ready_remote()
	var w: Weapon = ctx["weapon"]
	w._inv.equip(1)
	w._broadcast_current_id(WeaponDatabase.id_of(w.cfg()))
	await get_tree().physics_frame

	w._inv.equip(0)
	w._broadcast_current_id(WeaponDatabase.id_of(w.cfg()))
	await get_tree().physics_frame

	var tp: ThirdPersonWeapon = ctx["tp"]
	var weapon_model: Node3D = tp.get("_model")
	assert_object(weapon_model).is_not_null()
	var body: CharacterBody = ctx["body"]
	var socket := body.find_child("WeaponSocket", true, false)
	assert_object(weapon_model.get_parent()).append_failure_message(
		"reprendre le Ravage doit détacher le Revolver de \"PistolGrip\" et revenir sur \"WeaponSocket\""
	).is_same(socket)
