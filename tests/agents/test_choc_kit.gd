## test_choc_kit.gd
## Spec AGT-04 (docs/research/10_ammo_kits_input.md §3.3, fiche Choc) : Tête de
## cloche (passif), Tape-la-cloche (E, BellChargeAbility) et l'armement de la
## Déferlante (X, StunBurstAbility). Critère d'acceptation : "Contact serveur ;
## 15 PV, 3 m, 0,5 s ; auto-étourdissement contre un mur ; -40% sur les
## contrôles subis (test)".
##
## Style des doubles : bot réel (scenes/player/player.tscn, autorité SERVEUR
## sans réseau réel), même méthode que tests/agents/test_passives.gd et
## tests/agents/test_round_props_cleanup.gd::_bot_player. Les rayons de
## contact (wall_hit) suivent le même patron physique réel que
## tests/agents/test_ability_rays.gd (StaticBody3D synchronisés via
## `await get_tree().physics_frame`).
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
## Aucune de ces classes n'a de `class_name` global (comme StunTrapAbility.gd
## etc., sauf TeteDeCloche/BaumeAuRepos qui héritent de `Passive`, elle-même
## globale) -> preload explicite, comme tests/agents/test_ability_rays.gd.
const BellChargeAbilityScript := preload("res://scripts/agents/abilities/BellChargeAbility.gd")
const StunBurstAbilityScript := preload("res://scripts/agents/abilities/StunBurstAbility.gd")
const TeteDeClocheScript := preload("res://scripts/agents/passives/TeteDeCloche.gd")

var _next_offset_index := 0


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


## Incrémente son PROPRE compteur de nom (indépendant de `_offset()`) : un test
## qui spawne plusieurs bots à des offsets relatifs à un même point d'ancrage
## (attaquant + victime/coéquipier) doit obtenir des noms UNIQUES à chaque
## appel, sinon Godot renomme le second nœud en collision et `str(name).to_int()`
## (id réseau utilisé par PlayerController._enter_tree/les capacités) ne
## correspond plus à ce qu'on attend.
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


## Corps de DÉCOR opaque (mur/sol) : calque PhysicsLayers.WORLD, inclus dans
## SHOT_MASK -- doit toujours bloquer le rayon de contact de la charge (même
## construction que tests/agents/test_ability_rays.gd::_decor_body).
func _decor_body(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = pos
	add_child(body)
	auto_free(body)
	return body


## Reproduit le corps de collision posé par AbilityController.cast_smoke :
## calque VISION, jamais dans SHOT_MASK -- une charge ne doit pas s'y arrêter.
func _smoke_body(pos: Vector3, radius: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.VISION
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	col.shape = shape
	body.add_child(col)
	body.position = pos
	add_child(body)
	auto_free(body)
	return body


## Corps de JOUEUR minimal (calque par défaut, comme test_ability_rays.gd::
## _player_body) -- sert uniquement à prouver que wall_hit exclut bien tous
## les joueurs qu'on lui passe, sans dépendre du rig complet du bot.
func _player_body(pos: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	col.shape = shape
	body.add_child(col)
	body.position = pos
	add_child(body)
	auto_free(body)
	return body


# ============================================== BellChargeAbility : métadonnées

func test_bell_charge_metadata_matches_the_fiche_choc() -> void:
	var ab := BellChargeAbilityScript.new()
	assert_str(ab.slot).is_equal("E")
	assert_str(ab.display_name).is_equal("Tape-la-cloche")
	assert_float(ab.cooldown).append_failure_message("recharge 14 s (docs §3.3)").is_equal_approx(14.0, 0.001)
	assert_int(ab.charges).is_equal(1)
	assert_bool(ab.is_ultimate).is_false()
	assert_float(ab.hit_damage).append_failure_message("15 PV au premier ennemi touché").is_equal_approx(15.0, 0.001)
	assert_float(ab.knockback_distance).append_failure_message("repoussée de 3 m").is_equal_approx(3.0, 0.001)
	assert_float(ab.victim_stun_duration).append_failure_message("étourdissement de la victime : 0,5 s").is_equal_approx(0.5, 0.001)
	assert_float(ab.self_stun_duration).append_failure_message("auto-étourdissement contre un mur : 0,5 s").is_equal_approx(0.5, 0.001)


# ==================================================== first_hit_along_path (pur)

func test_first_hit_along_path_finds_a_candidate_on_the_segment() -> void:
	var hit := BellChargeAbilityScript.first_hit_along_path(
		Vector3.ZERO, Vector3(0, 0, -1), 10.0, [{"id": 1, "pos": Vector3(0, 0, -4), "team": 1}], 1.2)
	assert_bool(hit.is_empty()).is_false()
	assert_int(hit.id).is_equal(1)


func test_first_hit_along_path_prefers_the_one_hit_first_not_the_closest_to_the_axis() -> void:
	var candidates := [
		{"id": 2, "pos": Vector3(0, 0, -6), "team": 1},
		{"id": 1, "pos": Vector3(0, 0, -3), "team": 1},
	]
	var hit := BellChargeAbilityScript.first_hit_along_path(Vector3.ZERO, Vector3(0, 0, -1), 10.0, candidates, 1.2)
	assert_int(hit.id).append_failure_message(
		"le PREMIER ennemi capté (t=3) doit gagner, pas celui listé en premier (t=6)"
	).is_equal(1)


func test_first_hit_along_path_ignores_a_candidate_behind_the_origin() -> void:
	var hit := BellChargeAbilityScript.first_hit_along_path(
		Vector3.ZERO, Vector3(0, 0, -1), 10.0, [{"id": 1, "pos": Vector3(0, 0, 2), "team": 1}], 1.2)
	assert_bool(hit.is_empty()).append_failure_message("un ennemi derrière Choc ne doit jamais être touché").is_true()


func test_first_hit_along_path_ignores_a_candidate_beyond_the_length() -> void:
	var hit := BellChargeAbilityScript.first_hit_along_path(
		Vector3.ZERO, Vector3(0, 0, -1), 10.0, [{"id": 1, "pos": Vector3(0, 0, -12), "team": 1}], 1.2)
	assert_bool(hit.is_empty()).append_failure_message("un ennemi au-delà de la portée (mur ou fin de charge) ne doit pas être touché").is_true()


func test_first_hit_along_path_ignores_a_candidate_outside_the_capture_radius() -> void:
	var hit := BellChargeAbilityScript.first_hit_along_path(
		Vector3.ZERO, Vector3(0, 0, -1), 10.0, [{"id": 1, "pos": Vector3(3.0, 0, -4), "team": 1}], 1.2)
	assert_bool(hit.is_empty()).append_failure_message("3 m d'écart latéral est hors du couloir de charge").is_true()


func test_first_hit_along_path_includes_a_candidate_just_inside_the_capture_radius() -> void:
	# 1.19 < 1.2 sans dépendre d'une égalité flottante exacte à la frontière
	# (sqrt(1.2^2) n'est pas garanti bit-à-bit égal à 1.2 en float32).
	var hit := BellChargeAbilityScript.first_hit_along_path(
		Vector3.ZERO, Vector3(0, 0, -1), 10.0, [{"id": 1, "pos": Vector3(1.19, 0, -4), "team": 1}], 1.2)
	assert_bool(hit.is_empty()).is_false()


func test_first_hit_along_path_excludes_a_candidate_just_outside_the_capture_radius() -> void:
	var hit := BellChargeAbilityScript.first_hit_along_path(
		Vector3.ZERO, Vector3(0, 0, -1), 10.0, [{"id": 1, "pos": Vector3(1.21, 0, -4), "team": 1}], 1.2)
	assert_bool(hit.is_empty()).is_true()


func test_first_hit_along_path_empty_candidates_returns_empty() -> void:
	var hit := BellChargeAbilityScript.first_hit_along_path(Vector3.ZERO, Vector3(0, 0, -1), 10.0, [], 1.2)
	assert_bool(hit.is_empty()).is_true()


# ============================================================== wall_hit (rayon)

func test_wall_hit_detects_real_decor_along_the_charge_axis() -> void:
	var o := _offset()
	var origin := o + Vector3(0, 1.0, 0)
	var dir := Vector3(0, 0, -1)
	_decor_body(o + dir * 5.0, Vector3(4, 4, 0.5))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state
	var hit := BellChargeAbilityScript.wall_hit(space, origin, dir, 10.0, [])
	assert_bool(hit.is_empty()).append_failure_message(
		"le rayon de contact serveur de la charge aurait dû toucher le mur de décor"
	).is_false()


func test_wall_hit_passes_through_smoke() -> void:
	var o := _offset()
	var origin := o + Vector3(0, 1.0, 0)
	var dir := Vector3(0, 0, -1)
	_smoke_body(o + dir * 4.0, 2.5)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state
	var hit := BellChargeAbilityScript.wall_hit(space, origin, dir, 10.0, [])
	assert_bool(hit.is_empty()).append_failure_message(
		"une charge d'épaule ne doit pas s'arrêter sur une fumée (VISION, hors SHOT_MASK)"
	).is_true()


func test_wall_hit_excludes_all_players() -> void:
	var o := _offset()
	var origin := o + Vector3(0, 1.0, 0)
	var dir := Vector3(0, 0, -1)
	_decor_body(o + dir * 5.0, Vector3(4, 4, 0.5))
	var bystander := _player_body(o + dir * 2.0 + Vector3(0, 1.0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state
	var hit_unfiltered := BellChargeAbilityScript.wall_hit(space, origin, dir, 10.0, [])
	assert_object(hit_unfiltered.get("collider")).append_failure_message(
		"préalable du test : sans exclusion, le rayon doit toucher le joueur"
	).is_same(bystander)

	var hit := BellChargeAbilityScript.wall_hit(space, origin, dir, 10.0, [bystander.get_rid()])
	assert_bool(hit.is_empty()).append_failure_message("le rayon aurait dû traverser le joueur pour atteindre le mur").is_false()
	assert_object(hit.collider).append_failure_message("le contact ne doit jamais désigner un joueur comme un mur").is_not_same(bystander)


# ============================================= BellChargeAbility : mouvement local

func test_activate_local_charges_along_the_flat_forward_axis() -> void:
	var player := _bot_player(_offset())
	await get_tree().physics_frame
	var ab := BellChargeAbilityScript.new()
	player.velocity = Vector3.ZERO

	ab.activate_local(player)

	# Le corps par défaut regarde -Z (basis identité) -> direction (0, 0, -1).
	assert_float(player.velocity.z).append_failure_message("vitesse imprimée = force (20 m/s par défaut)").is_equal_approx(-ab.force, 0.05)
	assert_float(player.velocity.x).is_equal_approx(0.0, 0.05)
	assert_float(player.velocity.y).append_failure_message("hop minimal imposé").is_greater_equal(ab.hop - 0.001)


# ==================================================== BellChargeAbility : contact

func test_activate_server_hits_the_first_enemy_deals_damage_knockback_and_stun() -> void:
	var o := _offset()
	var attacker := _bot_player(o)
	var victim := _bot_player(o + Vector3(0, 0, -4))
	victim.set("team", 1)  # ennemi de l'attaquant (équipe 0 par défaut)
	victim.velocity = Vector3.ZERO
	await get_tree().physics_frame

	var ab := BellChargeAbilityScript.new()
	ab.activate_server(attacker, Vector3(0, 0, -1))

	var vhp := victim.get_node("Health") as Health
	assert_float(vhp.current_health).append_failure_message("15 PV au premier ennemi touché (100 - 15 = 85)").is_equal_approx(85.0, 0.01)
	assert_float(victim.velocity.z).append_failure_message("repoussée de 3 m dans l'axe de la charge").is_equal_approx(-ab.knockback_distance, 0.05)
	assert_str(victim.state_machine.current_name).append_failure_message("la victime touchée doit être étourdie").is_equal("Stun")
	assert_float(victim.state_machine._states["Stun"]._duration).is_equal_approx(0.5, 0.001)
	assert_str(attacker.state_machine.current_name).append_failure_message(
		"un ennemi touché absorbe le choc : Choc ne doit PAS s'auto-étourdir en plus"
	).is_not_equal("Stun")


func test_activate_server_self_stuns_against_a_wall_when_no_enemy_is_hit() -> void:
	var o := _offset()
	var attacker := _bot_player(o)
	var dir := Vector3(0, 0, -1)
	_decor_body(o + dir * 5.0, Vector3(4, 4, 0.5))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var ab := BellChargeAbilityScript.new()
	ab.activate_server(attacker, dir)

	assert_str(attacker.state_machine.current_name).append_failure_message(
		"contre un mur, sans ennemi touché, Choc doit s'étourdir lui-même"
	).is_equal("Stun")
	assert_float(attacker.state_machine._states["Stun"]._duration).is_equal_approx(0.5, 0.001)


func test_activate_server_does_nothing_in_open_ground() -> void:
	var o := _offset()
	var attacker := _bot_player(o)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var ab := BellChargeAbilityScript.new()
	ab.activate_server(attacker, Vector3(0, 0, -1))

	assert_str(attacker.state_machine.current_name).append_failure_message(
		"sans mur ni ennemi dans le couloir de charge, rien ne doit se déclencher"
	).is_not_equal("Stun")


func test_activate_server_ignores_a_teammate_and_still_self_stuns_on_the_wall_behind_them() -> void:
	var o := _offset()
	var attacker := _bot_player(o)
	var teammate := _bot_player(o + Vector3(0, 0, -3))  # équipe 0, comme l'attaquant
	var dir := Vector3(0, 0, -1)
	_decor_body(o + dir * 5.0, Vector3(4, 4, 0.5))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var ab := BellChargeAbilityScript.new()
	ab.activate_server(attacker, dir)

	var tm_hp := teammate.get_node("Health") as Health
	assert_float(tm_hp.current_health).append_failure_message("un coéquipier dans le couloir ne doit jamais être touché").is_equal_approx(100.0, 0.01)
	assert_str(teammate.state_machine.current_name).append_failure_message("un coéquipier ne doit jamais être étourdi par cette capacité").is_not_equal("Stun")
	assert_str(attacker.state_machine.current_name).append_failure_message(
		"le coéquipier ignoré, le mur au-delà doit quand même déclencher l'auto-étourdissement"
	).is_equal("Stun")


# ============================================================= TeteDeCloche

func test_tete_de_cloche_reduces_a_received_control_duration_by_40_percent() -> void:
	var p := TeteDeClocheScript.new()
	assert_float(p.modify_cc_duration(2.0)).append_failure_message(
		"-40% sur les contrôles subis : 2.0 * 0.6 = 1.2"
	).is_equal_approx(1.2, 0.001)


func test_tete_de_cloche_is_neutral_at_zero() -> void:
	var p := TeteDeClocheScript.new()
	assert_float(p.modify_cc_duration(0.0)).is_equal_approx(0.0, 0.001)


## Intégration avec la VRAIE classe (pas le double générique de
## tests/agents/test_passives.gd) : AbilityController.net_apply_stun doit
## réduire la durée reçue par Choc de 40%, via son passif réel.
func test_tete_de_cloche_reduces_the_stun_duration_choc_actually_receives() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	var cfg := AgentConfig.new()
	cfg.agent_name = "Choc"
	cfg.abilities = [StunBurstAbilityScript.new()]
	cfg.passive = TeteDeClocheScript.new()
	ctrl.agent = cfg

	ctrl.net_apply_stun(2.2)

	var stun_state = ctrl.player.state_machine._states["Stun"]
	assert_float(stun_state._duration).append_failure_message(
		"Tête de cloche (classe réelle) : 2.2 s * 0.6 = 1.32 s"
	).is_equal_approx(1.32, 0.001)


# ==================================================== StunBurstAbility : armement

func test_stun_burst_defaults_match_the_fiche_choc() -> void:
	var ab := StunBurstAbilityScript.new()
	assert_float(ab.arm_delay).append_failure_message("armement de la Déferlante : 0,4 s (docs §3.3)").is_equal_approx(0.4, 0.001)
	assert_float(ab.stun_duration).append_failure_message("étourdissement réduit de 1,8 à 1,5 s (docs §3.3)").is_equal_approx(1.5, 0.001)


func test_stun_burst_does_not_stun_immediately_after_activation() -> void:
	var o := _offset()
	var attacker := _bot_player(o)
	var victim := _bot_player(o + Vector3(0.8, 0, -6))
	victim.set("team", 1)
	await get_tree().physics_frame

	var ab := StunBurstAbilityScript.new()
	ab.arm_delay = 0.1
	ab.throw_range = 6.0
	ab.burst_radius = 3.0

	ab.activate_server(attacker, Vector3(0, 0, -1))

	assert_str(victim.state_machine.current_name).append_failure_message(
		"la Déferlante ne doit étourdir qu'APRÈS l'armement (0,1 s), jamais instantanément"
	).is_not_equal("Stun")


func test_stun_burst_stuns_once_the_arm_delay_has_elapsed() -> void:
	var o := _offset()
	var attacker := _bot_player(o)
	var victim := _bot_player(o + Vector3(0.8, 0, -6))
	victim.set("team", 1)
	await get_tree().physics_frame

	var ab := StunBurstAbilityScript.new()
	ab.arm_delay = 0.05
	ab.throw_range = 6.0
	ab.burst_radius = 3.0

	ab.activate_server(attacker, Vector3(0, 0, -1))
	await get_tree().create_timer(0.2).timeout

	assert_str(victim.state_machine.current_name).append_failure_message(
		"une fois l'armement écoulé, la victime toujours dans le rayon doit être étourdie"
	).is_equal("Stun")


func test_stun_burst_misses_a_victim_who_fled_during_the_arm_window() -> void:
	# Contre-jeu explicite (docs §3.3) : "se disperser au son" -- la résolution
	# (recherche des cibles) doit lire la position CORRENTE au moment où
	# l'armement se termine, pas celle du moment de l'activation.
	var o := _offset()
	var attacker := _bot_player(o)
	var victim := _bot_player(o + Vector3(0.8, 0, -6))
	victim.set("team", 1)
	await get_tree().physics_frame

	var ab := StunBurstAbilityScript.new()
	ab.arm_delay = 0.05
	ab.throw_range = 6.0
	ab.burst_radius = 3.0

	ab.activate_server(attacker, Vector3(0, 0, -1))
	victim.global_position += Vector3(0, 0, -20.0)  # fuit pendant l'armement
	await get_tree().create_timer(0.2).timeout

	assert_str(victim.state_machine.current_name).append_failure_message(
		"une victime qui a fui pendant l'armement ne doit pas être étourdie a posteriori"
	).is_not_equal("Stun")
