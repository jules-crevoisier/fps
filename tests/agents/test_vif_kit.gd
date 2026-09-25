## test_vif_kit.gd
## Spec AGT-03 (docs/research/10_ammo_kits_input.md §3.3, fiche Vif) : "Mèche
## courte" (passif, MecheCourte), "Faux départ" (E signature, remplace
## Tremplin, FauxDepartAbility) et la mèche de 0,3 s de l'Éblouissement (Q,
## FlashAbility). Critère d'acceptation du contrat : "Chiffres du §3.3. Retour
## refusé côté serveur au-delà de 30 m ou 5 s. Braise destructible."
##
## Style des doubles : bot réel (`scenes/player/player.tscn`, autorité SERVEUR
## sans réseau réel), même méthode que tests/agents/test_passives.gd,
## tests/agents/test_round_props_cleanup.gd et tests/agents/test_roseau_kit.gd.
## Chaque test reçoit un offset XZ dédié (`_offset()`) pour ne jamais partager
## d'espace physique avec un autre test, comme tests/agents/test_ability_rays.gd.
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
## Aucune de ces trois classes n'a de `class_name` global (comme
## StunTrapAbility.gd/BaumeAuRepos.gd déjà dans le dépôt) -> preload explicite,
## même motif que tests/agents/test_roseau_kit.gd et tests/agents/test_choc_kit.gd.
const FauxDepartAbilityScript := preload("res://scripts/agents/abilities/FauxDepartAbility.gd")
const FlashAbilityScript := preload("res://scripts/agents/abilities/FlashAbility.gd")
const MecheCourteScript := preload("res://scripts/agents/passives/MecheCourte.gd")

var _next_offset_index := 0
var _had_prev_scene := false
var _prev_current_scene: Node


func before_test() -> void:
	_had_prev_scene = true
	_prev_current_scene = get_tree().current_scene


func after_test() -> void:
	if _had_prev_scene:
		get_tree().current_scene = _prev_current_scene


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


## Scène factice (Node3D) pour recevoir la braise posée par FauxDepartAbility
## (`get_tree().current_scene`) -- même motif que
## tests/agents/test_round_props_cleanup.gd::_dummy_scene.
func _dummy_scene() -> Node3D:
	var s := Node3D.new()
	get_tree().root.add_child(s)
	auto_free(s)
	get_tree().current_scene = s
	return s


## Joueur RÉEL, spawné en BOT (autorité SERVEUR sans réseau réel -- même
## méthode que tests/agents/test_passives.gd::_bot_player). Incrémente
## `_next_offset_index` à CHAQUE appel (contrairement à `_offset()` seule) :
## un test qui spawn deux bots (attaquant + victime) sur le MÊME `_offset()`
## doit quand même leur donner des NOMS distincts -- un nom dupliqué force
## Godot à renommer le second nœud à l'ajout, ce qui casse
## `PlayerController._enter_tree()` (owner_id := str(name).to_int() ne
## retombe plus sur l'id attendu) et donc `is_multiplayer_authority()`.
func _bot_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	_next_offset_index += 1
	player.set("is_bot", true)
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	auto_free(player)
	return player


func _abilities(player: PlayerController) -> AbilityController:
	return player.get_node("Abilities") as AbilityController


func _health(player: PlayerController) -> Health:
	return player.get_node("Health") as Health


## Copie de l'état de munitions (Weapon.mag, une valeur par emplacement) --
## lecture dynamique (`Object.get`), Weapon.gd n'a pas de `class_name` global.
func _weapon_mag(player: PlayerController) -> Array:
	var weapon: Node = player.get_node("Weapon")
	return (weapon.get("mag") as Array).duplicate()


func _generic_ability(cooldown: float, charges: int) -> Ability:
	var a := Ability.new()
	a.cooldown = cooldown
	a.charges = charges
	return a


## Agent de test dont le passif et les capacités sont contrôlés par l'appelant
## (AgentDatabase n'est jamais muté -- même motif que
## tests/agents/test_passives.gd::_bot_with_passive).
func _bot_with_passive(passive: Passive, abilities: Array) -> AbilityController:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	var cfg := AgentConfig.new()
	cfg.agent_name = "TestVif"
	cfg.abilities = abilities
	cfg.passive = passive
	ctrl.agent = cfg
	# `_ready()` a déjà construit `_server_state`/`_owner_state` à partir de
	# l'agent PAR DÉFAUT (avant qu'on remplace `ctrl.agent` ci-dessus) -- on
	# les reconstruit ICI pour qu'ils reflètent les capacités DE TEST passées
	# à `abilities`, jamais l'agent par défaut résolu par `_ready()`.
	ctrl._server_state = AbilityState.new(abilities)
	ctrl._owner_state = AbilityState.new(abilities)
	return ctrl


# ======================================================================
#  FauxDepartAbility (E, "Faux départ") -- chiffres, pose, retour, refus,
#  destructibilité (contrat AGT-03).
# ======================================================================

func test_faux_depart_defaults_match_the_fiche_vif() -> void:
	var ab := FauxDepartAbilityScript.new()
	assert_str(ab.slot).is_equal("E")
	assert_float(ab.cooldown).append_failure_message(
		"Faux départ : recharge 16 s, lancée à la pose (contrat AGT-03/§3.3)"
	).is_equal_approx(16.0, 0.001)
	assert_int(ab.charges).append_failure_message(
		"2 charges : seule façon pour que le second appui (retour) atteigne le serveur -- "
		+ "AbilityController._activate() (fermé) refuse toute activation tant que can_activate() est faux"
	).is_equal(2)
	assert_float(FauxDepartAbilityScript.RETURN_WINDOW).append_failure_message(
		"fenêtre de 5 s (contrat AGT-03/§3.3)"
	).is_equal_approx(5.0, 0.001)
	assert_float(FauxDepartAbilityScript.MAX_RETURN_RANGE).append_failure_message(
		"portée max 30 m (contrat AGT-03/§3.3)"
	).is_equal_approx(30.0, 0.001)
	assert_float(FauxDepartAbilityScript.EMBER_HEALTH).append_failure_message(
		"braise détruite à 30 dégâts (contrat AGT-03/§3.3)"
	).is_equal_approx(30.0, 0.001)


func test_faux_depart_pose_spawns_a_destructible_ember_at_the_players_feet() -> void:
	var scene := _dummy_scene()
	var o := _offset()
	var player := _bot_player(o)
	var ab := FauxDepartAbilityScript.new()
	await get_tree().physics_frame

	ab.activate_server(player, Vector3.FORWARD)

	var ember := scene.get_child(scene.get_child_count() - 1) as Node3D
	assert_object(ember).append_failure_message("la pose doit ajouter la braise à la scène courante").is_not_null()
	assert_bool(ember.is_in_group("round_props")).append_failure_message(
		"la braise doit rejoindre round_props (BUG-03 : nettoyage de manche)"
	).is_true()
	assert_float(ember.global_position.distance_to(o)).append_failure_message(
		"la braise doit se poser À SES PIEDS (§3.3), jamais visée au loin"
	).is_less(0.05)
	var ember_hp := ember.get_node_or_null("Health") as Health
	assert_object(ember_hp).append_failure_message(
		"la braise doit porter un enfant Health générique (destructibilité, résolu par Weapon._resolve_ray)"
	).is_not_null()
	assert_float(ember_hp.max_health).append_failure_message(
		"détruite à 30 dégâts (contrat AGT-03/§3.3)"
	).is_equal_approx(30.0, 0.001)


func test_faux_depart_second_press_within_window_teleports_back_and_preserves_health_and_ammo() -> void:
	var scene := _dummy_scene()
	var o := _offset()
	var player := _bot_player(o)
	var ab := FauxDepartAbilityScript.new()
	await get_tree().physics_frame
	var hp := _health(player)
	hp.current_health = 63.0
	var mag_before := _weapon_mag(player)

	ab.activate_server(player, Vector3.FORWARD)  # pose
	# Position RÉELLEMENT posée (pas `o` : un tick de gravité peut déjà avoir
	# fait tomber le bot avant la pose, la scène de test n'a pas de sol).
	var pending: Dictionary = player.get_meta(FauxDepartAbilityScript.META_KEY)
	var pose_pos: Vector3 = pending["pos"]
	var ember: Node = pending["ember"]
	player.global_position = pose_pos + Vector3(10, 0, 0)  # s'éloigne, mais reste < 30 m

	ab.activate_server(player, Vector3.FORWARD)  # second appui : retour

	# Vérifié AVANT tout nouveau tick physique (le bot, encore en chute libre
	# sans sol dans cette scène de test, continuerait de dériver sous l'effet
	# de la gravité si on laissait tourner davantage de frames ici).
	assert_float(player.global_position.distance_to(pose_pos)).append_failure_message(
		"le retour doit ramener EXACTEMENT sur la braise (§3.3 : retour instantané)"
	).is_less(0.05)
	assert_float(hp.current_health).append_failure_message(
		"PV conservés (contrat AGT-03/§3.3)"
	).is_equal_approx(63.0, 0.001)
	assert_array(_weapon_mag(player)).append_failure_message(
		"munitions conservées (contrat AGT-03/§3.3)"
	).is_equal(mag_before)

	await get_tree().process_frame  # laisse `queue_free()` retirer la braise.
	assert_bool(is_instance_valid(ember)).append_failure_message(
		"un retour réussi doit consommer/retirer la braise"
	).is_false()


func test_faux_depart_refuses_return_beyond_30_meters() -> void:
	var scene := _dummy_scene()
	var o := _offset()
	var player := _bot_player(o)
	var ab := FauxDepartAbilityScript.new()
	await get_tree().physics_frame

	ab.activate_server(player, Vector3.FORWARD)  # pose
	var far_pos := o + Vector3(35, 0, 0)  # > 30 m
	player.global_position = far_pos

	ab.activate_server(player, Vector3.FORWARD)  # tentative de retour

	assert_float(player.global_position.distance_to(far_pos)).append_failure_message(
		"au-delà de 30 m, le retour doit être refusé côté serveur (acceptance AGT-03)"
	).is_less(0.05)


func test_faux_depart_refuses_return_after_5_seconds() -> void:
	var scene := _dummy_scene()
	var o := _offset()
	var player := _bot_player(o)
	var ab := FauxDepartAbilityScript.new()
	await get_tree().physics_frame

	ab.activate_server(player, Vector3.FORWARD)  # pose
	var pending: Dictionary = player.get_meta(FauxDepartAbilityScript.META_KEY)
	pending["posed_at"] -= 6.0  # simule 6 s écoulées (> fenêtre de 5 s), sans attendre en temps réel
	var near_pos := o + Vector3(2, 0, 0)  # reste largement à portée (< 30 m)
	player.global_position = near_pos

	ab.activate_server(player, Vector3.FORWARD)  # tentative de retour, trop tardive

	assert_float(player.global_position.distance_to(near_pos)).append_failure_message(
		"au-delà de 5 s, le retour doit être refusé côté serveur même à portée (acceptance AGT-03)"
	).is_less(0.05)


func test_faux_depart_ember_is_destructible_and_cancels_the_return() -> void:
	var scene := _dummy_scene()
	var o := _offset()
	var player := _bot_player(o)
	var ab := FauxDepartAbilityScript.new()
	await get_tree().physics_frame

	ab.activate_server(player, Vector3.FORWARD)  # pose
	var pending: Dictionary = player.get_meta(FauxDepartAbilityScript.META_KEY)
	var ember: Node = pending["ember"]
	var ember_hp := ember.get_node("Health") as Health
	ember_hp.apply_damage(30.0, 0)  # "détruite à 30 dégâts" (contrat AGT-03/§3.3)
	var near_pos := o + Vector3(5, 0, 0)
	player.global_position = near_pos

	ab.activate_server(player, Vector3.FORWARD)  # tentative de retour

	assert_float(player.global_position.distance_to(near_pos)).append_failure_message(
		"une braise détruite doit REFUSER le retour (contre-jeu §3.3 : \"la détruire pour annuler le retour\")"
	).is_less(0.05)


func test_faux_depart_ember_survives_damage_below_the_destruction_threshold() -> void:
	var scene := _dummy_scene()
	var o := _offset()
	var player := _bot_player(o)
	var ab := FauxDepartAbilityScript.new()
	await get_tree().physics_frame

	ab.activate_server(player, Vector3.FORWARD)  # pose
	var pending: Dictionary = player.get_meta(FauxDepartAbilityScript.META_KEY)
	var ember: Node = pending["ember"]
	(ember.get_node("Health") as Health).apply_damage(29.0, 0)  # sous le seuil de destruction (30)
	player.global_position = o + Vector3(5, 0, 0)

	ab.activate_server(player, Vector3.FORWARD)  # tentative de retour

	assert_float(player.global_position.distance_to(o)).append_failure_message(
		"29 dégâts (< 30) ne doivent PAS détruire la braise : le retour doit réussir"
	).is_less(0.05)


func test_faux_depart_next_press_after_a_refused_return_poses_a_fresh_ember() -> void:
	var scene := _dummy_scene()
	var o := _offset()
	var player := _bot_player(o)
	var ab := FauxDepartAbilityScript.new()
	await get_tree().physics_frame

	ab.activate_server(player, Vector3.FORWARD)  # pose #1
	var pending: Dictionary = player.get_meta(FauxDepartAbilityScript.META_KEY)
	pending["posed_at"] -= 6.0  # fenêtre close
	var new_pos := o + Vector3(3, 0, 0)
	player.global_position = new_pos
	ab.activate_server(player, Vector3.FORWARD)  # tentative refusée -- consomme l'état en attente

	ab.activate_server(player, Vector3.FORWARD)  # 3e appui : nouvelle pose, PAS un retour

	var new_pending = player.get_meta(FauxDepartAbilityScript.META_KEY)
	assert_object(new_pending).append_failure_message(
		"un appui après un retour refusé doit reposer une NOUVELLE braise, pas rester bloqué"
	).is_not_null()
	assert_float((new_pending["pos"] as Vector3).distance_to(new_pos)).append_failure_message(
		"la nouvelle braise doit être posée à la position ACTUELLE du joueur"
	).is_less(0.05)


# ======================================================================
#  MecheCourte (passif, "Mèche courte") -- charge de Ruée + vitesse sur
#  élimination/assistance (contrat AGT-03).
# ======================================================================

func test_meche_courte_default_values_match_the_contract() -> void:
	var passive := MecheCourteScript.new()
	assert_float(MecheCourteScript.SPEED_MULT).append_failure_message(
		"+10% de vitesse au sol (contrat AGT-03/§3.3)"
	).is_equal_approx(1.1, 0.001)
	assert_float(MecheCourteScript.SPEED_DURATION).append_failure_message(
		"pendant 2 s (contrat AGT-03/§3.3)"
	).is_equal_approx(2.0, 0.001)


func test_meche_courte_on_kill_grants_a_dash_charge_and_a_speed_boost() -> void:
	var passive := MecheCourteScript.new()
	var dash := _generic_ability(6.0, 2)  # slot par défaut de Ability.gd = "C"
	var ctrl := _bot_with_passive(passive, [dash])
	await get_tree().physics_frame
	ctrl._server_state.try_activate(0)  # 2 -> 1 charge, cooldown démarré

	passive.on_kill(ctrl.player, 42)

	assert_int(ctrl._server_state.charges(0)).append_failure_message(
		"chaque élimination doit rendre une charge de Ruée (plafond 2, contrat AGT-03/§3.3)"
	).is_equal(2)
	assert_float(ctrl._server_status.speed_mult()).append_failure_message(
		"+10% de vitesse au sol pendant 2 s (contrat AGT-03/§3.3)"
	).is_equal_approx(1.1, 0.001)


func test_meche_courte_on_assist_grants_a_dash_charge_and_a_speed_boost() -> void:
	var passive := MecheCourteScript.new()
	var dash := _generic_ability(6.0, 2)
	var ctrl := _bot_with_passive(passive, [dash])
	await get_tree().physics_frame
	ctrl._server_state.try_activate(0)

	passive.on_assist(ctrl.player, 7)

	assert_int(ctrl._server_state.charges(0)).append_failure_message(
		"une ASSISTANCE doit rendre la charge exactement comme une élimination (§3.3 : \"élimination ou assistance\")"
	).is_equal(2)
	assert_float(ctrl._server_status.speed_mult()).is_equal_approx(1.1, 0.001)


func test_meche_courte_charge_grant_is_capped_at_the_ability_maximum() -> void:
	var passive := MecheCourteScript.new()
	var dash := _generic_ability(6.0, 2)
	var ctrl := _bot_with_passive(passive, [dash])
	await get_tree().physics_frame

	passive.on_kill(ctrl.player, 1)  # déjà à charges pleines (2/2)

	assert_int(ctrl._server_state.charges(0)).append_failure_message(
		"plafond 2 (contrat AGT-03/§3.3) : un kill à charges déjà pleines ne doit rien casser"
	).is_equal(2)


func test_meche_courte_still_applies_the_speed_boost_without_a_slot_c_ability() -> void:
	var passive := MecheCourteScript.new()
	var q_ability := _generic_ability(6.0, 1)
	q_ability.slot = "Q"
	var ctrl := _bot_with_passive(passive, [q_ability])
	await get_tree().physics_frame
	ctrl._server_state.try_activate(0)

	passive.on_kill(ctrl.player, 1)

	assert_int(ctrl._server_state.charges(0)).append_failure_message(
		"aucune capacité en slot \"C\" : le passif ne doit rien accorder à une autre capacité"
	).is_equal(0)
	assert_float(ctrl._server_status.speed_mult()).append_failure_message(
		"le bonus de vitesse doit s'appliquer même sans capacité \"C\" à créditer"
	).is_equal_approx(1.1, 0.001)


func test_meche_courte_is_a_safe_no_op_without_a_player() -> void:
	var passive := MecheCourteScript.new()
	passive.on_kill(null, 1)   # ne doit pas planter
	passive.on_assist(null, 1)  # ne doit pas planter


# ======================================================================
#  FlashAbility (Q, "Éblouissement") -- mèche de 0,3 s + recharge 18 s
#  (contrat AGT-03).
# ======================================================================

func test_flash_ability_defaults_match_the_fiche_vif() -> void:
	var ab := FlashAbilityScript.new()
	assert_float(ab.cooldown).append_failure_message(
		"recharge 22 -> 18 s (contrat AGT-03/§3.3)"
	).is_equal_approx(18.0, 0.001)
	assert_float(ab.fuse_delay).append_failure_message(
		"mèche de 0,3 s (contrat AGT-03/§3.3)"
	).is_equal_approx(0.3, 0.001)
	assert_float(ab.blind_duration).append_failure_message(
		"durée d'aveuglement inchangée (1,3 s)"
	).is_equal_approx(1.3, 0.001)


## Décalage latéral (X) de la victime, HORS de l'axe de tir (Z pur) : sinon le
## rayon de trajectoire (trajectory_hit, masque SHOT_MASK, n'exclut QUE le
## lanceur) toucherait le corps même de la victime en premier -- la grenade
## détonerait alors littéralement à son contact (distance ~0, comportement
## RÉALISTE et correct, mais qui rend ce test non significatif : la victime
## serait "dans le rayon" par construction, jamais en fonction de `radius`).
const _FLASH_VICTIM_OFFSET := Vector3(2, 0, -8)


func test_flash_ability_does_not_blind_immediately_after_activation() -> void:
	var o := _offset()
	var attacker := _bot_player(o)
	var victim := _bot_player(o + _FLASH_VICTIM_OFFSET)  # dans le rayon (9 m), face à l'éclat
	await get_tree().physics_frame
	await get_tree().physics_frame

	var ab := FlashAbilityScript.new()
	ab.fuse_delay = 0.2

	ab.activate_server(attacker, Vector3(0, 0, -1))

	assert_bool(victim.has_meta("blinded_until")).append_failure_message(
		"la mèche de 0,3 s doit retarder l'aveuglement, jamais l'appliquer instantanément"
	).is_false()


func test_flash_ability_blinds_the_facing_victim_once_the_fuse_elapses() -> void:
	var o := _offset()
	var attacker := _bot_player(o)
	var victim := _bot_player(o + _FLASH_VICTIM_OFFSET)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var ab := FlashAbilityScript.new()
	ab.fuse_delay = 0.05

	ab.activate_server(attacker, Vector3(0, 0, -1))
	await get_tree().create_timer(0.2).timeout

	assert_bool(victim.has_meta("blinded_until")).append_failure_message(
		"une fois la mèche écoulée, une victime dans le rayon et faisant face doit être aveuglée"
	).is_true()


func test_flash_ability_misses_a_victim_who_fled_during_the_fuse() -> void:
	# Contre-jeu (même esprit que la Déferlante de Choc, AGT-04) : la
	# résolution lit la position COURANTE au moment où la mèche finit de
	# brûler, pas celle du lancer.
	var o := _offset()
	var attacker := _bot_player(o)
	var victim := _bot_player(o + _FLASH_VICTIM_OFFSET)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var ab := FlashAbilityScript.new()
	ab.fuse_delay = 0.05

	ab.activate_server(attacker, Vector3(0, 0, -1))
	victim.global_position += Vector3(30, 0, 0)  # fuit pendant la mèche
	await get_tree().create_timer(0.2).timeout

	assert_bool(victim.has_meta("blinded_until")).append_failure_message(
		"une victime qui a fui pendant la mèche ne doit pas être aveuglée a posteriori"
	).is_false()
