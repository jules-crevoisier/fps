## test_verrou_kit.gd
## Spec AGT-08 (docs/research/10_ammo_kits_input.md §3.3, fiche Verrou) :
## "Sang-froid" (passif), "Glu" (E signature, GlueAbility, refonte de la
## Chausse-trape) et "Bastion" (X, rebranché sur la Glu). Couvre le critère
## d'acceptation du contrat :
##   1. Sang-froid : -30 % de dispersion et -20 % de recul (vertical) après
##      0.4 s immobile (test PUR — WeaponFeel.is_steady/steady_spread_mult/
##      steady_recoil_mult, sans dépendance à un joueur réel).
##   2. Glu : -50 % de vitesse, ni saut, ni glissade, ni plongeon (verrou de
##      saut — voir note plus bas), effet qui dure encore 1.5 s après la
##      sortie de la zone. Plusieurs victimes simultanées.
##   3. Bastion : mur ET Glu au même endroit (métadonnées + délégation).
##
## 2e passage (vague 28 refusée, contrat AGT-08) : `is_jump_locked()` bloquait
## déjà le SAUT (PlayerController.can_jump(), voir
## tests/agents/test_status_effects.gd::test_can_jump_is_false_while_locked_
## by_a_status), mais Idle/Walk/Sprint/Air (scripts/player/states/*.gd, TOUS
## possédés par ce contrat) entraient encore en Dive/Slide SANS tester ce même
## verrou : un joueur englué pouvait plonger et glisser normalement. Corrigé
## dans ce passage (Dive/Slide gardés derrière `not player.is_jump_locked()`
## dans les 4 fichiers) et couvert par un VRAI test d'intégration ci-dessous
## (section "Intégration RÉELLE des states de mouvement") : joueur RÉEL posé
## au sol, states pilotés directement (`state_machine.transition_to`/
## `physics_update`, même méthode que tests/player/test_state_exits.gd,
## fichier hors périmètre de ce contrat, non importé), effet posé via les
## méthodes PUBLIQUES et déjà testées d'AbilityController
## (server_apply_speed_mult/server_apply_jump_lock, AGT-01).
##
## Style des doubles : bot réel (`scenes/player/player.tscn`, autorité SERVEUR
## sans réseau réel), comme tests/agents/test_passives.gd et
## tests/agents/test_roseau_kit.gd. Les objets RPC-répliqués d'
## AbilityController (cast_barrier...) ne sont JAMAIS appelés via leur wrapper
## `.rpc()` public dans aucun test de ce dépôt (toujours via le `_spawn_*`
## privé — voir tests/agents/test_round_props_cleanup.gd) : le test Bastion
## ci-dessous suit la même prudence et ne vérifie que les métadonnées et la
## délégation vers GlueAbility.spawn_zone, pas le mur RPC lui-même (déjà
## couvert ailleurs, inchangé par ce contrat).
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
## Aucune de ces classes n'a de `class_name` global (extends Ability seul,
## comme StunTrapAbility.gd/BalmZoneAbility.gd) -> preload explicite, même
## motif que tests/agents/test_ability_rays.gd et test_roseau_kit.gd.
const GlueAbilityScript := preload("res://scripts/agents/abilities/GlueAbility.gd")
const BastionAbilityScript := preload("res://scripts/agents/abilities/BastionAbility.gd")
const SangFroidScript := preload("res://scripts/agents/passives/SangFroid.gd")

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


## Scène factice (Node3D) pour recevoir la plaque posée par GlueAbility/
## BastionAbility (`get_tree().current_scene`) -- même motif que
## tests/agents/test_round_props_cleanup.gd::_dummy_scene.
func _dummy_scene() -> Node3D:
	var s := Node3D.new()
	get_tree().root.add_child(s)
	auto_free(s)
	get_tree().current_scene = s
	return s


## Compteur d'id DÉDIÉ, distinct de `_next_offset_index` (positions spatiales) :
## deux joueurs posés dans le MÊME test (ex. "plusieurs victimes") ne doivent
## jamais partager le même nom, sinon Godot désambiguïse le nœud enfant et
## `str(player.name).to_int()` (id réseau — voir AbilityController._push_status)
## cesse de retomber dans la plage BOT_ID_START, provoquant un RPC vers un pair
## inconnu (bruit, bien que sans effet sur les assertions grâce au repli de
## `status()` sur `_server_status`).
var _next_bot_id := 0


## Joueur RÉEL (autorité SERVEUR sans réseau réel, même méthode que
## tests/agents/test_roseau_kit.gd::_bot_player), avec une équipe assignée.
func _bot_player(pos: Vector3, team: int = 0) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_bot_id)
	_next_bot_id += 1
	player.set("is_bot", true)
	player.position = pos
	player.set("spawn_point", pos)
	player.team = team
	add_child(player)
	auto_free(player)
	return player


func _abilities(player: PlayerController) -> AbilityController:
	return player.get_node("Abilities") as AbilityController


func _health(player: PlayerController) -> Health:
	return player.get_node("Health") as Health


# ======================================================================
#  WeaponFeel : Sang-froid, calcul PUR (contrat AGT-08 : "test pur").
# ======================================================================

func test_is_steady_false_before_the_threshold() -> void:
	assert_bool(WeaponFeel.is_steady(0.39, 0.0, false)).append_failure_message(
		"Sang-froid : sous 0.4 s d'immobilité, la condition ne doit pas encore être remplie"
	).is_false()


func test_is_steady_true_at_the_threshold_under_the_speed_limit() -> void:
	assert_bool(WeaponFeel.is_steady(0.4, 0.49, false)).append_failure_message(
		"Sang-froid : 0.4 s immobile sous 0.5 m/s doit activer la condition"
	).is_true()


func test_is_steady_false_when_still_moving_even_past_the_threshold() -> void:
	assert_bool(WeaponFeel.is_steady(1.0, 0.5, false)).append_failure_message(
		"0.5 m/s n'est plus \"sous\" la limite (< 0.5) : Sang-froid ne doit pas s'activer"
	).is_false()


func test_is_steady_true_immediately_when_crouching_regardless_of_timer_or_speed() -> void:
	assert_bool(WeaponFeel.is_steady(0.0, 8.0, true)).append_failure_message(
		"accroupi active Sang-froid IMMÉDIATEMENT, même en mouvement/sans délai (contrat AGT-08)"
	).is_true()


func test_steady_spread_mult_is_neutral_before_the_condition() -> void:
	assert_float(WeaponFeel.steady_spread_mult(0.0, 5.0, false)).is_equal_approx(1.0, 0.001)


func test_steady_spread_mult_is_minus_thirty_percent_once_steady() -> void:
	assert_float(WeaponFeel.steady_spread_mult(0.4, 0.0, false)).append_failure_message(
		"Sang-froid : -30 %% de dispersion (contrat AGT-08)"
	).is_equal_approx(0.7, 0.001)


func test_steady_recoil_mult_is_neutral_before_the_condition() -> void:
	assert_float(WeaponFeel.steady_recoil_mult(0.0, 5.0, false)).is_equal_approx(1.0, 0.001)


func test_steady_recoil_mult_is_minus_twenty_percent_once_steady() -> void:
	assert_float(WeaponFeel.steady_recoil_mult(0.4, 0.0, false)).append_failure_message(
		"Sang-froid : -20 %% de recul vertical (contrat AGT-08)"
	).is_equal_approx(0.8, 0.001)


func test_total_spread_deg_applies_the_passive_multiplier() -> void:
	var s := WeaponFeel.total_spread_deg(2.0, 0.0, 0.0, 0.7)
	assert_float(s).append_failure_message(
		"2.0 deg de base * 0.7 (Sang-froid) doit donner 1.4 deg"
	).is_equal_approx(1.4, 0.001)


func test_total_spread_deg_default_multiplier_is_neutral() -> void:
	# Non-régression : tout appelant existant (Weapon.gd, 3 arguments) ne doit
	# pas voir son résultat changer.
	var s := WeaponFeel.total_spread_deg(2.0, 1.5, 3.0)
	assert_float(s).is_equal_approx(6.5, 0.001)


func test_recoil_for_shot_applies_the_multiplier_only_to_the_vertical_component() -> void:
	var c := WeaponConfig.new()
	c.recoil_pattern = PackedVector2Array([Vector2(0.1, 0.6)])
	c.pattern_shots = 1
	var kick := WeaponFeel.recoil_for_shot(c, 0, null, 0.8)
	assert_float(kick.x).append_failure_message(
		"la déviation HORIZONTALE (yaw) ne doit jamais être réduite par Sang-froid"
	).is_equal_approx(0.1, 0.0001)
	assert_float(kick.y).append_failure_message(
		"Sang-froid : -20 %% doit s'appliquer à la montée VERTICALE (0.6 * 0.8 = 0.48)"
	).is_equal_approx(0.48, 0.0001)


func test_recoil_for_shot_default_multiplier_is_neutral() -> void:
	# Non-régression : comportement pré-existant inchangé pour tout appelant
	# qui n'a jamais entendu parler de Sang-froid.
	var c := WeaponConfig.new()
	c.recoil_pattern = PackedVector2Array([Vector2(0.0, 0.5)])
	c.pattern_shots = 1
	var kick := WeaponFeel.recoil_for_shot(c, 0)
	assert_float(kick.y).is_equal_approx(0.5, 0.0001)


# ======================================================================
#  SangFroid (Passive) : intégration avec un joueur réel.
# ======================================================================

func test_sang_froid_spread_mult_is_neutral_immediately_after_becoming_still() -> void:
	var o := _offset()
	var player := _bot_player(o)
	player.velocity = Vector3.ZERO
	var passive := SangFroidScript.new()

	# Premier appel : vient tout juste de repasser sous le seuil -> 0 s
	# d'immobilité écoulée, encore sous 0.4 s.
	assert_float(passive.spread_mult(player)).append_failure_message(
		"Sang-froid ne doit pas s'activer au tout premier instant de l'arrêt"
	).is_equal_approx(1.0, 0.001)


func test_sang_froid_spread_mult_activates_once_steady_since_at_least_0_4s() -> void:
	var o := _offset()
	var player := _bot_player(o)
	player.velocity = Vector3.ZERO
	var passive := SangFroidScript.new()
	# Simule 1 s déjà écoulée sous le seuil (bien au-delà de 0.4 s), sans
	# attente réelle -- même motif que test_status_effects.gd (tick direct).
	passive._still_since[player.get_instance_id()] = (Time.get_ticks_msec() / 1000.0) - 1.0

	assert_float(passive.spread_mult(player)).append_failure_message(
		"Sang-froid : -30 %% une fois l'immobilité soutenue >= 0.4 s"
	).is_equal_approx(0.7, 0.001)
	assert_float(passive.recoil_mult(player)).append_failure_message(
		"Sang-froid : -20 %% de recul vertical dans les mêmes conditions"
	).is_equal_approx(0.8, 0.001)


func test_sang_froid_is_neutral_while_moving_even_if_previously_steady() -> void:
	var o := _offset()
	var player := _bot_player(o)
	player.velocity = Vector3.ZERO
	var passive := SangFroidScript.new()
	passive._still_since[player.get_instance_id()] = (Time.get_ticks_msec() / 1000.0) - 1.0
	player.velocity = Vector3(10.0, 0.0, 0.0)  # repart en mouvement (> 0.5 m/s)

	assert_float(passive.spread_mult(player)).append_failure_message(
		"un joueur qui se remet à bouger doit immédiatement perdre le bonus de Sang-froid"
	).is_equal_approx(1.0, 0.001)


func test_sang_froid_activates_immediately_when_crouching_even_while_moving() -> void:
	var o := _offset()
	var player := _bot_player(o)
	player.velocity = Vector3(10.0, 0.0, 0.0)
	player.is_crouching = true
	var passive := SangFroidScript.new()

	assert_float(passive.spread_mult(player)).append_failure_message(
		"accroupi active Sang-froid immédiatement, peu importe la vitesse ou le délai"
	).is_equal_approx(0.7, 0.001)


func test_sang_froid_tracks_each_player_independently() -> void:
	# Cette ressource Passive est PARTAGÉE entre tous les joueurs de Verrou
	# (voir docstring de SangFroid.gd) : une seule instance doit donc pouvoir
	# suivre plusieurs joueurs sans que l'un n'écrase l'état de l'autre.
	var o := _offset()
	var steady_player := _bot_player(o)
	var moving_player := _bot_player(o + Vector3(5, 0, 0))
	steady_player.velocity = Vector3.ZERO
	moving_player.velocity = Vector3(10.0, 0.0, 0.0)
	var passive := SangFroidScript.new()
	passive._still_since[steady_player.get_instance_id()] = (Time.get_ticks_msec() / 1000.0) - 1.0

	assert_float(passive.spread_mult(steady_player)).is_equal_approx(0.7, 0.001)
	assert_float(passive.spread_mult(moving_player)).append_failure_message(
		"le joueur en mouvement ne doit pas hériter de l'immobilité de l'autre"
	).is_equal_approx(1.0, 0.001)


func test_sang_froid_default_values_match_the_contract() -> void:
	var passive := SangFroidScript.new()
	assert_str(passive.display_name).is_equal("Sang-froid")


# ======================================================================
#  GlueAbility : pose au sol (rayon).
# ======================================================================

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


func test_glue_ground_ray_ignores_smoke_and_reaches_the_floor() -> void:
	var o := _offset()
	var above := o + Vector3(0, 5.0, 0)
	_decor_body(o + Vector3(0, -0.5, 0), Vector3(10, 1, 10))
	_smoke_body(o + Vector3(0, 2.0, 0), 2.5)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state
	var hit := GlueAbilityScript.ground_hit(space, above, above + Vector3(0, -6.0, 0), [])
	assert_bool(hit.is_empty()).append_failure_message("la Glu ne touche rien : devrait traverser la fumée").is_false()
	assert_float(hit.position.y).append_failure_message(
		"la Glu s'est posée sur la fumée (y=%.2f) au lieu du sol (y=0)" % hit.position.y
	).is_equal_approx(o.y, 0.05)


func test_glue_ground_ray_excludes_all_players() -> void:
	var o := _offset()
	var above := o + Vector3(0, 5.0, 0)
	_decor_body(o + Vector3(0, -0.5, 0), Vector3(10, 1, 10))
	var victim := _bot_player(o + Vector3(0, 1.0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state
	var hit := GlueAbilityScript.ground_hit(space, above, above + Vector3(0, -6.0, 0), [victim.get_rid()])
	assert_bool(hit.is_empty()).append_failure_message("la Glu ne touche plus rien sous le joueur").is_false()
	assert_object(hit.collider).append_failure_message("la Glu a atterri sur la tête du joueur").is_not_same(victim)
	assert_float(hit.position.y).is_equal_approx(o.y, 0.05)


# ======================================================================
#  GlueAbility : métadonnées + pose.
# ======================================================================

func test_glue_ability_metadata_matches_the_contract() -> void:
	var ab := GlueAbilityScript.new()
	assert_str(ab.slot).is_equal("E")
	assert_float(ab.cooldown).is_equal_approx(18.0, 0.001)
	assert_int(ab.charges).is_equal(1)
	assert_float(ab.slow_mult).append_failure_message(
		"Glu : -50 %% de vitesse (contrat AGT-08)"
	).is_equal_approx(0.5, 0.001)
	assert_float(ab.linger).append_failure_message(
		"Glu : effet qui dure encore 1.5 s après la sortie (contrat AGT-08)"
	).is_equal_approx(1.5, 0.001)


func test_glue_ability_spawns_a_team_filtered_persistent_zone_in_round_props() -> void:
	var scene := _dummy_scene()
	var o := _offset()
	var caster := _bot_player(o, 1)
	var ab := GlueAbilityScript.new()
	await get_tree().physics_frame

	ab.activate_server(caster, Vector3.FORWARD)

	var zone := scene.get_child(scene.get_child_count() - 1)
	assert_object(zone).append_failure_message(
		"GlueAbility.activate_server doit poser une zone dans la scène courante"
	).is_not_null()
	assert_int(int(zone.get("owner_team"))).append_failure_message(
		"la plaque doit être filtrée sur l'équipe DU LANCEUR"
	).is_equal(1)
	assert_bool(zone.is_in_group("round_props")).append_failure_message(
		"la plaque doit rejoindre round_props (BUG-03 : nettoyage de manche)"
	).is_true()


# ======================================================================
#  GlueAbility : effet de zone (ralentissement + verrou de saut).
# ======================================================================

func test_glue_zone_slows_and_locks_the_jump_of_an_overlapping_enemy() -> void:
	var scene := _dummy_scene()
	var o := _offset()
	GlueAbilityScript.spawn_zone(scene, o, 0, 2.5, 20.0, 0.5, 1.5, Color(0.25, 0.55, 0.85))
	var enemy := _bot_player(o, 1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var zone := scene.get_child(scene.get_child_count() - 1)

	zone._physics_process(0.016)

	var status := _abilities(enemy).status()
	assert_float(status.speed_mult()).append_failure_message(
		"Glu : -50 %% de vitesse sur un ennemi dans la zone"
	).is_equal_approx(0.5, 0.001)
	assert_bool(status.is_jump_locked()).append_failure_message(
		"Glu : verrou de saut sur un ennemi dans la zone"
	).is_true()


func test_glue_zone_never_slows_its_owners_team() -> void:
	var scene := _dummy_scene()
	var o := _offset()
	GlueAbilityScript.spawn_zone(scene, o, 0, 2.5, 20.0, 0.5, 1.5, Color(0.25, 0.55, 0.85))
	var ally := _bot_player(o, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var zone := scene.get_child(scene.get_child_count() - 1)

	zone._physics_process(0.016)

	var status := _abilities(ally).status()
	assert_float(status.speed_mult()).append_failure_message(
		"la Glu ne doit jamais ralentir le camp de son propriétaire"
	).is_equal_approx(1.0, 0.001)
	assert_bool(status.is_jump_locked()).is_false()


func test_glue_zone_ignores_a_dead_enemy() -> void:
	var scene := _dummy_scene()
	var o := _offset()
	GlueAbilityScript.spawn_zone(scene, o, 0, 2.5, 20.0, 0.5, 1.5, Color(0.25, 0.55, 0.85))
	var enemy := _bot_player(o, 1)
	_health(enemy).is_dead = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	var zone := scene.get_child(scene.get_child_count() - 1)

	zone._physics_process(0.016)

	assert_float(_abilities(enemy).status().speed_mult()).append_failure_message(
		"un ennemi déjà mort ne doit pas être ralenti par la Glu"
	).is_equal_approx(1.0, 0.001)


## "Plusieurs victimes" (critère d'acceptation explicite AGT-08) : la Glu
## n'est plus un piège à déclenchement UNIQUE (StunTrapAbility) -- tous les
## ennemis présents en même temps doivent être affectés.
func test_glue_zone_slows_multiple_simultaneous_victims() -> void:
	var scene := _dummy_scene()
	var o := _offset()
	GlueAbilityScript.spawn_zone(scene, o, 0, 2.5, 20.0, 0.5, 1.5, Color(0.25, 0.55, 0.85))
	var e1 := _bot_player(o + Vector3(0.6, 0, 0), 1)
	var e2 := _bot_player(o + Vector3(-0.6, 0, 0), 1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var zone := scene.get_child(scene.get_child_count() - 1)

	zone._physics_process(0.016)

	assert_float(_abilities(e1).status().speed_mult()).append_failure_message(
		"la première victime doit être ralentie"
	).is_equal_approx(0.5, 0.001)
	assert_float(_abilities(e2).status().speed_mult()).append_failure_message(
		"une SECONDE victime, en même temps que la première, doit AUSSI être ralentie"
	).is_equal_approx(0.5, 0.001)


func test_glue_effect_lingers_1_5s_after_leaving_the_zone_then_expires() -> void:
	var scene := _dummy_scene()
	var o := _offset()
	GlueAbilityScript.spawn_zone(scene, o, 0, 2.5, 20.0, 0.5, 1.5, Color(0.25, 0.55, 0.85))
	var enemy := _bot_player(o, 1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var zone := scene.get_child(scene.get_child_count() - 1)
	zone._physics_process(0.016)  # dernier tick DANS la zone.
	var ctrl := _abilities(enemy)
	assert_bool(ctrl._server_status.is_jump_locked()).append_failure_message(
		"préalable du test : l'effet doit être actif juste après le dernier tick dans la zone"
	).is_true()

	# Sortie de zone simulée (le contact n'est plus réappliqué) : la minuterie
	# décroît NATURELLEMENT, comme test_status_effects.gd (tick direct plutôt
	# qu'une attente réelle).
	ctrl._server_status.tick(1.4)
	assert_bool(ctrl._server_status.is_jump_locked()).append_failure_message(
		"Glu : l'effet doit durer encore ~1.5 s après la sortie de la zone (contrat AGT-08)"
	).is_true()
	assert_float(ctrl._server_status.speed_mult()).is_equal_approx(0.5, 0.001)

	ctrl._server_status.tick(0.2)  # total 1.6 s > 1.5 s.
	assert_bool(ctrl._server_status.is_jump_locked()).append_failure_message(
		"et doit avoir expiré après 1.5 s hors de la zone"
	).is_false()
	assert_float(ctrl._server_status.speed_mult()).is_equal_approx(1.0, 0.001)


# ======================================================================
#  BastionAbility : ultime rebranché sur la Glu.
# ======================================================================

func test_bastion_ability_metadata_matches_the_contract() -> void:
	var ab := BastionAbilityScript.new()
	assert_str(ab.slot).is_equal("X")
	assert_bool(ab.is_ultimate).is_true()
	assert_int(ab.ult_cost).is_equal(8)
	assert_float(ab.wall_duration).append_failure_message(
		"Bastion : mur de 12 s (contrat AGT-08/doc §3.3)"
	).is_equal_approx(12.0, 0.001)
	assert_float(ab.glue_duration).append_failure_message(
		"Bastion : Glu de 16 s (contrat AGT-08/doc §3.3)"
	).is_equal_approx(16.0, 0.001)
	assert_float(ab.slow_mult).is_equal_approx(0.5, 0.001)


func test_bastion_ability_spawns_a_glue_zone_owned_by_the_casters_team() -> void:
	# Note : n'exerce PAS le mur (ctrl.cast_barrier -> RPC), voir docstring du
	# fichier -- seule la délégation vers GlueAbility.spawn_zone est vérifiée
	# ici, comme le reste de ce dépôt le fait pour les objets RPC-répliqués.
	var scene := _dummy_scene()
	var o := _offset()
	var caster := _bot_player(o, 1)
	var ab := BastionAbilityScript.new()
	await get_tree().physics_frame

	ab.activate_server(caster, Vector3.FORWARD)

	var zone := scene.get_child(scene.get_child_count() - 1)
	assert_object(zone).append_failure_message(
		"Bastion doit poser une zone de Glu, en plus du mur"
	).is_not_null()
	assert_int(int(zone.get("owner_team"))).is_equal(1)
	assert_float(float(zone.get("slow_mult"))).is_equal_approx(0.5, 0.001)
	assert_bool(zone.is_in_group("round_props")).is_true()


func test_bastion_glue_zone_still_slows_enemies_like_the_signature_version() -> void:
	# Non-régression : Bastion réutilise EXACTEMENT GlueAbility.spawn_zone,
	# donc son effet de zone est identique (plusieurs victimes comprises).
	# Position de l'ennemi ALIGNÉE sur celle que `activate_server` calcule
	# réellement : `fwd` vient de la ROTATION du joueur (identité par défaut
	# -> -Z), pas de `aim_dir` (comportement PRÉ-EXISTANT de BastionAbility,
	# inchangé par ce contrat), à `distance + 1.2` = 4.2 m le long de `fwd`.
	var scene := _dummy_scene()
	var o := _offset()
	var caster := _bot_player(o, 0)
	var ab := BastionAbilityScript.new()
	var enemy := _bot_player(o + Vector3(0, 0, -(ab.distance + 1.2)), 1)
	await get_tree().physics_frame
	await get_tree().physics_frame

	ab.activate_server(caster, Vector3.FORWARD)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var zone := scene.get_child(scene.get_child_count() - 1)
	zone._physics_process(0.016)

	assert_float(_abilities(enemy).status().speed_mult()).append_failure_message(
		"la Glu de Bastion doit ralentir un ennemi exactement comme la signature"
	).is_equal_approx(0.5, 0.001)


# ======================================================================
#  Intégration RÉELLE des states de mouvement (2e passage, vague 28
#  refusée -- voir NOTE en tête de fichier). Idle/Walk/Sprint/Air doivent
#  refuser Dive/Slide (le saut est, lui, déjà verrouillé par can_jump(),
#  hors périmètre -- voir test_status_effects.gd) tant que
#  `player.is_jump_locked()` est vrai, et la vitesse au sol doit bien
#  retomber à -50 % (StatusEffects.speed_mult(), déjà consommé par
#  PlayerController.ground_move -- voir sa docstring, hors périmètre).
#  Sol réel + `state_machine.transition_to`/`physics_update` pilotés
#  directement SANS jamais rappeler `move_and_slide()` après le contact au
#  sol initial (`is_on_floor()` reste alors figé à "vrai" tick après tick) :
#  même méthode que tests/player/test_state_exits.gd (fichier hors périmètre
#  de ce contrat, non importé -- dupliquée ici). L'effet est posé via les
#  méthodes PUBLIQUES et déjà testées d'AbilityController
#  (server_apply_jump_lock/server_apply_speed_mult, AGT-01), exactement ce
#  que _GlueZone._physics_process applique déjà à chaque victime en zone
#  (voir les tests de zone ci-dessus).
# ======================================================================

## Sol réel (StaticBody3D, calque WORLD) dont la surface haute est
## exactement à `top.y` -- même construction que
## tests/player/test_state_exits.gd::_floor (fichier hors périmètre,
## dupliquée ici).
func _ground_floor(top: Vector3, size: Vector3 = Vector3(10, 1, 10)) -> StaticBody3D:
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


## Joueur RÉEL posé sur un vrai sol, contact `is_on_floor()` confirmé avant de
## piloter ses states directement -- même méthode que
## tests/player/test_state_exits.gd::_grounded_bot, adaptée au `_bot_player`
## (équipe) de ce fichier.
func _grounded_bot(pos: Vector3, team: int = 0) -> PlayerController:
	_ground_floor(pos)
	var player := _bot_player(pos, team)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.velocity = Vector3(0, -1, 0)
	player.move_and_slide()
	assert_bool(player.is_on_floor()).append_failure_message(
		"préalable du test : le joueur doit être détecté au sol avant de piloter ses states"
	).is_true()
	return player


func test_glued_player_cannot_jump_from_idle() -> void:
	var o := _offset()
	var player := await _grounded_bot(o)
	_abilities(player).server_apply_jump_lock(1.5)
	player.state_machine.transition_to("Idle", {})
	player._jump_buffer_timer = 1.0  # saut bufferisé, comme un vrai appui juste avant.

	player.state_machine.physics_update(1.0 / 60.0)

	assert_str(player.state_machine.current_name).append_failure_message(
		"Glu : un joueur englué ne doit pas pouvoir sauter depuis Idle (contrat AGT-08 : \"ni saut\") -- état obtenu : %s"
			% player.state_machine.current_name
	).is_equal("Idle")


func test_glued_player_cannot_dive_from_idle_walk_or_sprint() -> void:
	for state_name in ["Idle", "Walk", "Sprint"]:
		var o := _offset()
		var player := await _grounded_bot(o)
		_abilities(player).server_apply_jump_lock(1.5)
		player.state_machine.transition_to(state_name, {})
		player.input.dive_pressed = true

		player.state_machine.physics_update(1.0 / 60.0)

		assert_str(player.state_machine.current_name).append_failure_message(
			"Glu : un joueur englué ne doit pas pouvoir plonger depuis %s (contrat AGT-08 : \"ni plongeon\") -- état obtenu : %s"
				% [state_name, player.state_machine.current_name]
		).is_not_equal("Dive")


func test_glued_player_cannot_slide_from_walk_or_sprint() -> void:
	for state_name in ["Walk", "Sprint"]:
		var o := _offset()
		var player := await _grounded_bot(o)
		_abilities(player).server_apply_jump_lock(1.5)
		player.state_machine.transition_to(state_name, {})
		player.velocity = -player.global_transform.basis.z * 10.0  # > slide_min_speed (6.5 m/s)
		player.input.crouch_pressed = true

		player.state_machine.physics_update(1.0 / 60.0)

		assert_str(player.state_machine.current_name).append_failure_message(
			"Glu : un joueur englué ne doit pas pouvoir glisser depuis %s (contrat AGT-08 : \"ni glissade\") -- état obtenu : %s"
				% [state_name, player.state_machine.current_name]
		).is_not_equal("Slide")


func test_glued_player_cannot_slide_hop_when_landing_from_air() -> void:
	var o := _offset()
	var player := await _grounded_bot(o)
	_abilities(player).server_apply_jump_lock(1.5)
	player.state_machine.transition_to("Air", {})
	player.velocity = Vector3(0, -1.0, 0) + (-player.global_transform.basis.z * 10.0)
	player.input.crouch_held = true

	player.state_machine.physics_update(1.0 / 60.0)

	assert_str(player.state_machine.current_name).append_failure_message(
		"Glu : un atterrissage englué ne doit pas déclencher de slide-hop (contrat AGT-08 : \"ni glissade\") -- état obtenu : %s"
			% player.state_machine.current_name
	).is_not_equal("Slide")


func test_glued_player_moves_at_half_speed_while_sprinting() -> void:
	var o := _offset()
	var player := await _grounded_bot(o)
	_abilities(player).server_apply_speed_mult(0.5, 1.5)
	player.state_machine.transition_to("Sprint", {})
	player.input_vector = Vector2(0, -1)
	player.wish_dir = -player.global_transform.basis.z

	for i in range(120):  # 2 s à 60 Hz : largement de quoi converger (ground_accel = 85 m/s^2).
		player.state_machine.physics_update(1.0 / 60.0)

	assert_float(player.horizontal_speed()).append_failure_message(
		"Glu : la vitesse doit être divisée par deux en sprint (attendu ~%.2f m/s, obtenu %.2f m/s)"
			% [player.config.sprint_speed * 0.5, player.horizontal_speed()]
	).is_equal_approx(player.config.sprint_speed * 0.5, 0.05)
