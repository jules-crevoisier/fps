## test_vanne_kit.gd
## Spec AGT-05 (docs/research/10_ammo_kits_input.md §3.3, fiche Vanne) :
## "Relevé" (passif) et "Piquet d'arpenteur" (E signature, grappin,
## GrappleAbility). Couvre les critères d'acceptation du contrat :
##   1. Ancrage <= 18 m validé CÔTÉ SERVEUR (rayon depuis la vue serveur,
##      décor uniquement, jamais un joueur, + 1 m de marge de tolérance).
##   2. Marque de 1,5 s, au plus 1 marque PAR ENNEMI toutes les 4 s.
##   3. Branchement sur l'impact de mur dans Weapon.gd (hook GF-21) : NON
##      câblé ici (AbilityController.gd/Weapon.gd sont hors des fichiers
##      possédés par ce contrat — voir `on_wall_shot`, appelée directement ici
##      exactement comme un futur hook le ferait, même motif que
##      tests/agents/test_passives.gd qui appelle net_apply_stun/net_show_markers
##      DIRECTEMENT sans transport RPC réel).
##
## Style des doubles : bot réel (`scenes/player/player.tscn`, autorité SERVEUR
## sans réseau réel), comme tests/agents/test_passives.gd et
## tests/agents/test_roseau_kit.gd. Les rayons purs (`GrappleAbility.anchor_hit`)
## utilisent des corps physiques minimaux, comme tests/agents/test_ability_rays.gd
## (_decor_body/_player_body). Chaque test reçoit un offset XZ dédié pour ne
## jamais partager d'espace physique avec un autre test.
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
## Aucune de ces deux classes n'a de `class_name` global (comme DashAbility.gd,
## BaumeAuRepos.gd déjà dans le dépôt -- voir tests/agents/test_ability_rays.gd
## et tests/agents/test_roseau_kit.gd) -> preload explicite.
const GrappleAbilityScript := preload("res://scripts/agents/abilities/GrappleAbility.gd")
const ReleveScript := preload("res://scripts/agents/passives/Releve.gd")

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


## Scène factice (Node3D) pour recevoir les marqueurs posés par
## AbilityController.net_show_markers (via Releve.on_wall_shot -> cast_reveal)
## -- même motif que tests/agents/test_round_props_cleanup.gd::_dummy_scene.
func _dummy_scene() -> Node3D:
	var s := Node3D.new()
	get_tree().root.add_child(s)
	auto_free(s)
	get_tree().current_scene = s
	return s


## Joueur RÉEL, spawné en BOT (autorité SERVEUR sans réseau réel, même
## méthode que tests/agents/test_passives.gd::_bot_player), avec une équipe
## assignée. Fait AUSSI avancer `_next_offset_index` (comme `_offset()`) --
## plusieurs tests ci-dessous créent DEUX bots dans la même position de base
## (`origin + aim_dir * ...`) sans rappeler `_offset()` entre les deux : sans
## cela, ils partageraient le même nom de nœud (id BOT_ID_START + index).
## `parent` (par défaut la suite elle-même) sert aux tests Releve.on_wall_shot :
## `AbilityController.cast_reveal` lit `child.get("team")` sur CHAQUE enfant de
## `players_root` -- un décor/joueur factice (`_decor_body`/`_player_body`,
## sans cette propriété) laissé par un AUTRE test dans le même parent y ferait
## planter `int(null)` ; ces tests passent donc une racine dédiée (`_players_root`).
func _bot_player(pos: Vector3, team: int = 0, parent: Node = null) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	_next_offset_index += 1
	player.set("is_bot", true)
	player.position = pos
	player.set("spawn_point", pos)
	player.team = team
	(parent if parent else self).add_child(player)
	auto_free(player)
	return player


## Joueur RÉEL non-bot, avec l'id de pair 1 -- « l'hôte » (PlayerController.
## _enter_tree : `authority_id := 1 if owner_id >= BOT_ID_START else owner_id`,
## donc id 1 = authority 1 = le même pair que le process de test headless,
## comme documenté par tests/networking/test_respawn_refill.gd::_bot_player :
## "même autorité serveur que l'hôte... donc le même chemin que _teleport_player
## emprunte pour l'hôte ET les bots"). Seul cas où AbilityController.cast_reveal
## appelle réellement net_show_markers en test headless : elle SAUTE tout
## coéquipier `is_bot` (marqueur purement cosmétique, voir sa docstring) --
## au plus UN par test (les noms de nœuds doivent rester uniques). Voir
## `_bot_player` ci-dessus pour `parent`.
func _human_player(pos: Vector3, team: int = 0, parent: Node = null) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = "1"
	player.position = pos
	player.set("spawn_point", pos)
	player.team = team
	(parent if parent else self).add_child(player)
	auto_free(player)
	return player


## Racine dédiée pour les tests Releve.on_wall_shot (voir docstring de
## `_bot_player`) : AbilityController.cast_reveal suppose que TOUS les enfants
## de `players_root` sont des joueurs (`get("team")`) -- jamais un décor/corps
## de test laissé par un AUTRE test de ce fichier dans le même parent.
func _players_root() -> Node:
	var root := Node.new()
	add_child(root)
	auto_free(root)
	return root


## Corps de DÉCOR opaque (mur/sol) : calque PhysicsLayers.WORLD, inclus dans
## SHOT_MASK -- doit toujours bloquer un rayon physique (même corps que
## tests/agents/test_ability_rays.gd::_decor_body).
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


## Reproduit EXACTEMENT le corps de collision posé par
## AbilityController.cast_smoke (StaticBody3D, calque VISION, masque 0) --
## bloque la vue, jamais les balles ni les capacités (SHOT_MASK l'exclut).
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


## Corps de JOUEUR minimal (calque par défaut Godot = PhysicsLayers.WORLD) --
## pour les tests PURS d'anchor_hit, comme tests/agents/test_ability_rays.gd::_player_body.
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


# ======================================================================
#  GrappleAbility -- métadonnées
# ======================================================================

func test_grapple_ability_metadata_matches_the_contract() -> void:
	var ab := GrappleAbilityScript.new()
	assert_str(ab.slot).is_equal("E")
	assert_str(ab.display_name).is_equal("Piquet d'arpenteur")
	assert_float(ab.cooldown).append_failure_message(
		"Piquet d'arpenteur : recharge 10 s (contrat AGT-05)"
	).is_equal_approx(10.0, 0.001)
	assert_int(ab.charges).is_equal(1)
	assert_float(ab.max_range).append_failure_message(
		"ancrage <= 18 m (contrat AGT-05)"
	).is_equal_approx(18.0, 0.001)
	assert_float(ab.server_margin).append_failure_message(
		"+ 1 m de marge de tolérance serveur (contrat AGT-05)"
	).is_equal_approx(1.0, 0.001)
	assert_float(ab.pull_speed).append_failure_message(
		"traction à 22 m/s (docs/research/10_ammo_kits_input.md §3.3)"
	).is_equal_approx(22.0, 0.001)
	assert_float(ab.pull_duration).is_equal_approx(0.8, 0.001)


# ======================================================================
#  GrappleAbility.anchor_hit -- rayon pur (statique, testable isolément)
# ======================================================================

func test_anchor_hit_finds_decor_within_range() -> void:
	var o := _offset()
	var origin := o + Vector3(0, 1.6, 0)
	var dir := Vector3(0, 0, -1)
	_decor_body(origin + dir * 10.0, Vector3(4, 4, 0.5))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state
	var result := GrappleAbilityScript.anchor_hit(space, origin, dir, 19.0, [])
	assert_bool(result.is_empty()).append_failure_message(
		"un ancrage sur du décor à 10 m (<= 18 m + 1 m) doit être trouvé"
	).is_false()
	assert_float(result.position.distance_to(origin)).is_less(10.1)


func test_anchor_hit_ignores_smoke_and_reaches_decor_beyond() -> void:
	# BUG-06 : la fumée bloque la vue, jamais les capacités -- un grappin lancé
	# à travers une fumée continue sa course.
	var o := _offset()
	var origin := o + Vector3(0, 1.6, 0)
	var dir := Vector3(0, 0, -1)
	_smoke_body(origin + dir * 4.0, 2.5)
	_decor_body(origin + dir * 10.0, Vector3(4, 4, 0.5))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state
	var result := GrappleAbilityScript.anchor_hit(space, origin, dir, 19.0, [])
	assert_bool(result.is_empty()).append_failure_message(
		"le rayon d'ancrage s'est arrêté sur la fumée au lieu du décor : %s" % result
	).is_false()
	# Le décor (boîte 4x4x0.5 centrée à 10 m) présente sa face avant à
	# 10 - 0,25 = 9,75 m -- c'est CETTE surface que le rayon touche, pas le centre.
	assert_float(result.position.distance_to(origin)).is_between(9.6, 9.9)


func test_anchor_hit_rejects_a_target_beyond_the_capped_range() -> void:
	var o := _offset()
	var origin := o + Vector3(0, 1.6, 0)
	var dir := Vector3(0, 0, -1)
	_decor_body(origin + dir * 25.0, Vector3(4, 4, 0.5))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state
	var result := GrappleAbilityScript.anchor_hit(space, origin, dir, 19.0, [])
	assert_bool(result.is_empty()).append_failure_message(
		"un décor à 25 m dépasse 18 m + 1 m de marge : aucun ancrage ne doit être trouvé"
	).is_true()


func test_anchor_hit_never_anchors_on_a_player() -> void:
	var o := _offset()
	var origin := o + Vector3(0, 1.6, 0)
	var dir := Vector3(0, 0, -1)
	_decor_body(origin + dir * 15.0, Vector3(4, 4, 0.5))  # décor réel, plus loin
	var victim := _player_body(origin + dir * 5.0)         # joueur entre origin et le décor
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state

	# Sans exclusion : preuve que le test est significatif (le rayon touche
	# bien le joueur, un faux positif serait possible si la géométrie le ratait).
	var hit_unfiltered := GrappleAbilityScript.anchor_hit(space, origin, dir, 19.0, [])
	assert_object(hit_unfiltered.get("collider")).append_failure_message(
		"le rayon aurait dû toucher le joueur"
	).is_same(victim)

	# Comportement réel (tous les joueurs exclus) : le rayon traverse le
	# joueur et atteint le décor derrière lui.
	var hit := GrappleAbilityScript.anchor_hit(space, origin, dir, 19.0, [victim.get_rid()])
	assert_bool(hit.is_empty()).append_failure_message("l'ancrage ne touche plus rien derrière le joueur").is_false()
	assert_object(hit.collider).append_failure_message("le grappin s'est ancré sur la tête du joueur").is_not_same(victim)
	# Face avant du décor (boîte 4x4x0.5 centrée à 15 m) : 15 - 0,25 = 14,75 m.
	assert_float(hit.position.distance_to(origin)).is_between(14.6, 14.9)


# ======================================================================
#  GrappleAbility.activate_server -- validation + traction, bout en bout
# ======================================================================

func test_activate_server_pulls_the_owner_toward_a_validated_anchor() -> void:
	var o := _offset()
	var caster := _bot_player(o)
	var ab := GrappleAbilityScript.new()
	await get_tree().physics_frame
	var origin: Vector3 = caster.head.global_position
	var aim_dir := Vector3(0, 0, -1)
	_decor_body(origin + aim_dir * 10.0, Vector3(4, 4, 0.5))
	# Le décor a besoin de 2 passages physiques pour être enregistré par le
	# serveur physique (même motif que tests/agents/test_ability_rays.gd) --
	# la remise à zéro de la vélocité vient APRÈS ces `await` (jamais avant),
	# sinon la gravité accumulée pendant ces frames (le joueur est en chute
	# libre, aucun sol dans cette scène factice) fausserait la mesure.
	await get_tree().physics_frame
	await get_tree().physics_frame
	caster.velocity = Vector3.ZERO

	ab.activate_server(caster, aim_dir)

	assert_vector(caster.velocity).append_failure_message(
		"un ancrage validé (décor à 10 m) doit haler le lanceur à 22 m/s vers l'ancrage"
	).is_equal_approx(aim_dir * ab.pull_speed, Vector3.ONE * 0.05)


func test_activate_server_does_nothing_without_a_valid_anchor_in_range() -> void:
	var o := _offset()
	var caster := _bot_player(o)
	var ab := GrappleAbilityScript.new()
	await get_tree().physics_frame
	var origin: Vector3 = caster.head.global_position
	var aim_dir := Vector3(0, 0, -1)
	_decor_body(origin + aim_dir * 25.0, Vector3(4, 4, 0.5))  # 25 m > 18 + 1 m
	await get_tree().physics_frame
	await get_tree().physics_frame
	caster.velocity = Vector3.ZERO

	ab.activate_server(caster, aim_dir)

	assert_vector(caster.velocity).append_failure_message(
		"un décor hors de portée (25 m) ne doit produire AUCUNE traction"
	).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)


func test_activate_server_accepts_an_anchor_within_the_one_meter_margin() -> void:
	var o := _offset()
	var caster := _bot_player(o)
	var ab := GrappleAbilityScript.new()
	await get_tree().physics_frame
	var origin: Vector3 = caster.head.global_position
	var aim_dir := Vector3(0, 0, -1)
	_decor_body(origin + aim_dir * 18.7, Vector3(4, 4, 0.5))  # au-delà de 18 m, dans la marge de 1 m
	await get_tree().physics_frame
	await get_tree().physics_frame
	caster.velocity = Vector3.ZERO

	ab.activate_server(caster, aim_dir)

	assert_vector(caster.velocity).append_failure_message(
		"18,7 m est au-delà de 18 m mais dans la marge de tolérance serveur (+1 m) : la traction doit s'appliquer"
	).is_equal_approx(aim_dir * ab.pull_speed, Vector3.ONE * 0.05)


func test_activate_server_never_pulls_the_owner_onto_a_blocking_player() -> void:
	var o := _offset()
	var caster := _bot_player(o)
	var ab := GrappleAbilityScript.new()
	await get_tree().physics_frame
	var origin: Vector3 = caster.head.global_position
	var aim_dir := Vector3(0, 0, -1)
	var blocker := _bot_player(origin + aim_dir * 5.0, 1)  # un autre joueur entre le lanceur et le décor
	_decor_body(origin + aim_dir * 12.0, Vector3(4, 4, 0.5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	caster.velocity = Vector3.ZERO

	ab.activate_server(caster, aim_dir)

	assert_vector(caster.velocity).append_failure_message(
		"le grappin doit traverser le joueur bloquant et s'ancrer sur le décor derrière lui, jamais sur la tête du joueur"
	).is_equal_approx(aim_dir * ab.pull_speed, Vector3.ONE * 0.05)
	assert_object(blocker).is_not_null()  # sanity : le bloqueur existe bien dans la scène


# ======================================================================
#  Releve.should_mark -- limitation PURE (au plus 1 marque par couple / 4 s)
# ======================================================================

func test_should_mark_grants_the_first_mark_for_a_new_key() -> void:
	var marks := {}
	assert_bool(ReleveScript.should_mark(marks, "1:2", 10.0, 4.0)).is_true()


func test_should_mark_rejects_a_second_mark_within_the_cooldown_window() -> void:
	var marks := {}
	ReleveScript.should_mark(marks, "1:2", 10.0, 4.0)
	assert_bool(ReleveScript.should_mark(marks, "1:2", 13.9, 4.0)).append_failure_message(
		"une deuxième marque à 3,9 s de la première (< 4 s) doit être refusée"
	).is_false()


func test_should_mark_allows_a_mark_again_once_the_cooldown_has_elapsed() -> void:
	var marks := {}
	ReleveScript.should_mark(marks, "1:2", 10.0, 4.0)
	assert_bool(ReleveScript.should_mark(marks, "1:2", 14.0, 4.0)).append_failure_message(
		"exactement 4 s plus tard, une nouvelle marque doit être acceptée"
	).is_true()


func test_should_mark_tracks_different_keys_independently() -> void:
	var marks := {}
	ReleveScript.should_mark(marks, "1:2", 10.0, 4.0)
	assert_bool(ReleveScript.should_mark(marks, "1:3", 10.1, 4.0)).append_failure_message(
		"un ennemi différent (clé différente) ne doit jamais être bloqué par le cooldown d'un autre"
	).is_true()


# ======================================================================
#  Releve.on_wall_shot -- intégration (filtre d'équipe + cast_reveal)
# ======================================================================

func test_releve_metadata_matches_the_contract() -> void:
	var passive := ReleveScript.new()
	assert_str(passive.display_name).is_equal("Relevé")
	assert_float(passive.mark_duration).append_failure_message(
		"marqueur de 1,5 s (contrat AGT-05)"
	).is_equal_approx(1.5, 0.001)
	assert_float(passive.mark_cooldown).append_failure_message(
		"1 marque par ennemi toutes les 4 s (contrat AGT-05)"
	).is_equal_approx(4.0, 0.001)


func test_on_wall_shot_never_marks_a_teammate() -> void:
	var root := _players_root()
	var o := _offset()
	var owner := _bot_player(o, 0, root)
	var teammate := _bot_player(o + Vector3(3, 0, 0), 0, root)  # même équipe que le mur
	var passive := ReleveScript.new()
	await get_tree().physics_frame

	var marked := passive.on_wall_shot(owner, teammate, 10.0)

	assert_bool(marked).append_failure_message(
		"un coéquipier qui tire dans son propre mur (ou celui d'un allié) ne doit jamais être marqué"
	).is_false()


func test_on_wall_shot_marks_an_enemy_and_broadcasts_a_marker_to_the_owners_team() -> void:
	var scene := _dummy_scene()
	var root := _players_root()
	var o := _offset()
	var owner := _human_player(o, 0, root)             # non-bot : seul cas où le marqueur est réellement posé.
	var enemy := _bot_player(o + Vector3(6, 0, 0), 1, root)
	var passive := ReleveScript.new()
	await get_tree().physics_frame
	var before := get_tree().get_nodes_in_group("round_props").size()

	var marked := passive.on_wall_shot(owner, enemy, 10.0)

	assert_bool(marked).append_failure_message("un ennemi qui tire dans le mur doit être marqué").is_true()
	var after := get_tree().get_nodes_in_group("round_props")
	assert_int(after.size() - before).append_failure_message(
		"la marque doit poser un marqueur \"!\" (net_show_markers) dans round_props"
	).is_equal(1)
	var marker := scene.get_child(scene.get_child_count() - 1) as Label3D
	assert_object(marker).is_not_null()
	assert_str(marker.text).is_equal("!")


func test_on_wall_shot_rate_limits_the_same_enemy_within_four_seconds() -> void:
	var scene := _dummy_scene()
	var root := _players_root()
	var o := _offset()
	var owner := _human_player(o, 0, root)
	var enemy := _bot_player(o + Vector3(6, 0, 0), 1, root)
	var passive := ReleveScript.new()
	await get_tree().physics_frame
	passive.on_wall_shot(owner, enemy, 10.0)
	var after_first := get_tree().get_nodes_in_group("round_props").size()

	var marked_again := passive.on_wall_shot(owner, enemy, 12.0)  # 2 s plus tard (< 4 s)

	assert_bool(marked_again).append_failure_message(
		"le même ennemi ne doit pas être remarqué avant 4 s"
	).is_false()
	assert_int(get_tree().get_nodes_in_group("round_props").size()).append_failure_message(
		"un refus de marque ne doit poser aucun marqueur supplémentaire"
	).is_equal(after_first)


func test_on_wall_shot_allows_marking_the_same_enemy_again_after_the_cooldown() -> void:
	var root := _players_root()
	var owner := _human_player(_offset(), 0, root)
	var enemy := _bot_player(owner.global_position + Vector3(6, 0, 0), 1, root)
	var passive := ReleveScript.new()
	await get_tree().physics_frame
	passive.on_wall_shot(owner, enemy, 10.0)

	var marked_again := passive.on_wall_shot(owner, enemy, 14.1)  # 4,1 s plus tard

	assert_bool(marked_again).append_failure_message(
		"passé 4 s, le même ennemi doit pouvoir être remarqué"
	).is_true()


func test_on_wall_shot_tracks_different_enemies_independently() -> void:
	var root := _players_root()
	var o := _offset()
	var owner := _human_player(o, 0, root)
	var enemy_a := _bot_player(o + Vector3(6, 0, 0), 1, root)
	var enemy_b := _bot_player(o + Vector3(-6, 0, 0), 1, root)
	var passive := ReleveScript.new()
	await get_tree().physics_frame
	passive.on_wall_shot(owner, enemy_a, 10.0)

	var marked_b := passive.on_wall_shot(owner, enemy_b, 10.1)

	assert_bool(marked_b).append_failure_message(
		"le cooldown d'un ennemi ne doit jamais bloquer la marque d'un ennemi différent"
	).is_true()


func test_on_wall_shot_is_a_safe_no_op_without_a_player_or_attacker() -> void:
	var owner := _bot_player(_offset(), 0)
	var passive := ReleveScript.new()
	await get_tree().physics_frame

	assert_bool(passive.on_wall_shot(null, owner, 10.0)).is_false()
	assert_bool(passive.on_wall_shot(owner, null, 10.0)).is_false()
