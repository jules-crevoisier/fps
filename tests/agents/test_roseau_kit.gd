## test_roseau_kit.gd
## Spec AGT-07 (docs/research/10_ammo_kits_input.md §3.3, fiche Roseau) :
## "Baume au repos" (passif), "Baume du Palud" (E signature, HealZone/
## BalmZoneAbility) et "Sursaut" version d'équipe (RenewalAbility, X). Couvre
## les critères d'acceptation du contrat :
##   1. HealZone : zone filtrée par équipe, 12 PV/s pendant 6 s, soin divisé
##      par 2 sur une cible touchée depuis < 1 s.
##   2. RenewalAbility ("Sursaut") : soigne les alliés à <= 10 m (en plus du
##      soin total pour elle-même, déjà existant).
##   3. BaumeAuRepos : régénération à 2,5 s / 40 PV/s, POUR ELLE SEULE.
##
## Style des doubles : bot réel (`scenes/player/player.tscn`, autorité SERVEUR
## sans réseau réel), comme tests/agents/test_passives.gd et
## tests/agents/test_round_props_cleanup.gd. Chaque test reçoit un offset XZ
## dédié (`_offset()`) pour ne jamais partager d'espace physique avec un autre
## test -- même motif que tests/agents/test_ability_rays.gd.
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
## HealZone a un `class_name` global (déjà présent avant ce contrat) -> pas de
## preload nécessaire pour l'instancier (`HealZone.new()` plus bas).
## Aucune de ces deux classes n'a de `class_name` global (comme HealAbility.gd,
## RenewalAbility.gd déjà dans le dépôt -- voir tests/agents/test_ability_rays.gd)
## -> preload explicite.
const BalmZoneAbilityScript := preload("res://scripts/agents/abilities/BalmZoneAbility.gd")
const RenewalAbilityScript := preload("res://scripts/agents/abilities/RenewalAbility.gd")
const BaumeAuReposScript := preload("res://scripts/agents/passives/BaumeAuRepos.gd")

var _next_offset_index := 0
var _had_prev_scene := false
var _prev_current_scene: Node
## Conteneur DÉDIÉ aux bots de test, recréé à chaque test (before_test) :
## RenewalAbility/AbilityController.cast_reveal itère `players_root.
## get_children()` et lit `int(child.get("team"))` sur CHAQUE enfant en
## supposant (comme en jeu réel, où players_root == le nœud "Players" de
## GameWorld) qu'il ne contient QUE des PlayerController -- jamais une
## HealZone de test encore en attente de libération (`queue_free` différé)
## ou un nœud interne de la suite. Isoler les bots dans ce conteneur, plutôt
## que de les ajouter directement à la suite, garantit `players_root.
## get_children()` propre pour les tests qui déclenchent un reveal.
var _players_root: Node


func before_test() -> void:
	_had_prev_scene = true
	_prev_current_scene = get_tree().current_scene
	_players_root = Node.new()
	add_child(_players_root)
	auto_free(_players_root)


func after_test() -> void:
	if _had_prev_scene:
		get_tree().current_scene = _prev_current_scene


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


## Scène factice (Node3D) pour recevoir la flaque posée par BalmZoneAbility
## (`get_tree().current_scene`) -- même motif que
## tests/agents/test_round_props_cleanup.gd::_dummy_scene.
func _dummy_scene() -> Node3D:
	var s := Node3D.new()
	get_tree().root.add_child(s)
	auto_free(s)
	get_tree().current_scene = s
	return s


## Joueur RÉEL (autorité SERVEUR sans réseau réel, même méthode que
## tests/agents/test_passives.gd::_bot_player), avec une équipe assignée.
func _bot_player(pos: Vector3, team: int = 0) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	# Incrémente le MÊME compteur que `_offset()` -- garantit un nom unique
	# même pour deux bots créés côte à côte sans appel à `_offset()` entre les
	# deux (ex. un allié et un ennemi au même offset XZ).
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	_next_offset_index += 1
	player.set("is_bot", true)
	player.position = pos
	player.set("spawn_point", pos)
	player.team = team
	_players_root.add_child(player)
	auto_free(player)
	return player


func _health(player: PlayerController) -> Health:
	return player.get_node("Health") as Health


# ======================================================================
#  HealZone (scripts/world/HealZone.gd) : filtre d'équipe, 12 PV/s, moitié
#  moins vite sur une cible touchée depuis < 1 s.
# ======================================================================

func _heal_zone(pos: Vector3, radius: float, owner_team: int, heal_per_second: float) -> HealZone:
	var zone := HealZone.new()
	zone.owner_team = owner_team
	zone.heal_per_second = heal_per_second
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	col.shape = shape
	zone.add_child(col)
	zone.position = pos
	add_child(zone)
	auto_free(zone)
	return zone


func test_heal_zone_heals_only_the_matching_team() -> void:
	var o := _offset()
	var zone := _heal_zone(o, 5.0, 0, 12.0)
	var ally := _bot_player(o, 0)
	var enemy := _bot_player(o + Vector3(1, 0, 0), 1)
	# Régénération de base (Health.gd, indépendante de la flaque) désactivée :
	# isole strictement l'effet de HealZone pour cette assertion exacte.
	_health(ally).regen_enabled = false
	_health(enemy).regen_enabled = false
	_health(ally).current_health = 50.0
	_health(enemy).current_health = 50.0
	await get_tree().physics_frame
	await get_tree().physics_frame

	zone._physics_process(1.0)

	assert_float(_health(ally).current_health).append_failure_message(
		"un allié (même équipe que la flaque) doit être soigné"
	).is_greater(50.0)
	assert_float(_health(enemy).current_health).append_failure_message(
		"HealZone doit filtrer par équipe : un ennemi dans la zone ne doit RIEN recevoir"
	).is_equal_approx(50.0, 0.001)


func test_heal_zone_default_team_neutral_heals_everyone() -> void:
	# Comportement d'ORIGINE préservé (owner_team par défaut = -1, utilisé par
	# la zone de test neutre du Gulag, scripts/levels/GulagBuilder.gd) : sans
	# filtre explicite, tout le monde est soigné, quelle que soit l'équipe.
	var o := _offset()
	var zone := _heal_zone(o, 5.0, -1, 12.0)
	var a := _bot_player(o, 0)
	var b := _bot_player(o + Vector3(1, 0, 0), 1)
	_health(a).regen_enabled = false
	_health(b).regen_enabled = false
	_health(a).current_health = 50.0
	_health(b).current_health = 50.0
	await get_tree().physics_frame
	await get_tree().physics_frame

	zone._physics_process(1.0)

	assert_float(_health(a).current_health).is_greater(50.0)
	assert_float(_health(b).current_health).is_greater(50.0)


func test_heal_zone_heals_at_twelve_hp_per_second() -> void:
	var o := _offset()
	var zone := _heal_zone(o, 5.0, 0, 12.0)
	var ally := _bot_player(o, 0)
	var hp := _health(ally)
	hp.regen_enabled = false
	hp.current_health = 50.0
	await get_tree().physics_frame
	await get_tree().physics_frame  # laisse l'Area3D détecter le recouvrement.

	# Mesuré en DELTA depuis juste avant l'appel contrôlé (1 s) : les 2 frames
	# physiques ci-dessus ont déjà pu faire tourner _physics_process une fois
	# automatiquement (l'objet est déjà dans l'arbre) -- seul l'écart imputable
	# à CET appel de 1 s doit valoir 12 PV, quel que soit ce qui a pu se
	# produire avant.
	var before := hp.current_health
	zone._physics_process(1.0)  # 1 s à 12 PV/s -> +12 PV

	assert_float(hp.current_health - before).append_failure_message(
		"Baume du Palud : 12 PV/s (contrat AGT-07)"
	).is_equal_approx(12.0, 0.01)


func test_heal_zone_halves_the_heal_for_a_target_damaged_less_than_1s_ago() -> void:
	var o := _offset()
	var zone := _heal_zone(o, 5.0, 0, 12.0)
	var ally := _bot_player(o, 0)
	var hp := _health(ally)
	hp.regen_enabled = false
	hp.current_health = 50.0
	await get_tree().physics_frame
	await get_tree().physics_frame  # body_entered connecte hp.damaged AVANT le dégât.

	hp.apply_damage(5.0, 0)  # marque "touché maintenant" (peu importe le montant restant).
	var before := hp.current_health
	zone._physics_process(1.0)  # 1 s à 12 PV/s / 2 -> +6 PV depuis `before`.

	assert_float(hp.current_health - before).append_failure_message(
		"une cible touchée il y a < 1 s ne doit recevoir que la MOITIÉ du soin"
	).is_equal_approx(6.0, 0.01)


func test_heal_zone_restores_the_full_rate_once_the_damage_window_has_elapsed() -> void:
	var o := _offset()
	var zone := _heal_zone(o, 5.0, 0, 12.0)
	var ally := _bot_player(o, 0)
	var hp := _health(ally)
	hp.regen_enabled = false
	hp.current_health = 50.0
	await get_tree().physics_frame
	await get_tree().physics_frame

	hp.apply_damage(5.0, 0)
	# Simule l'écoulement de la fenêtre (1 s) sans attendre de temps réel --
	# même motif que test_round_props_cleanup.gd::_desync_owner (manipulation
	# directe de l'état interne pour rendre le test déterministe).
	var id := hp.get_instance_id()
	zone._damage_times[id] = (Time.get_ticks_msec() / 1000.0) - 2.0

	var before := hp.current_health
	zone._physics_process(1.0)  # fenêtre expirée -> plein tarif : +12 PV depuis `before`.

	assert_float(hp.current_health - before).append_failure_message(
		"passé 1 s sans nouveau dégât, le soin doit repasser à plein tarif"
	).is_equal_approx(12.0, 0.01)


func test_heal_zone_stops_tracking_a_target_that_leaves_the_zone() -> void:
	var o := _offset()
	var zone := _heal_zone(o, 3.0, 0, 12.0)
	var ally := _bot_player(o, 0)
	var hp := _health(ally)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_int(zone._connections.size()).is_equal(1)

	ally.global_position = o + Vector3(50, 0, 0)  # sort du rayon de la zone (3 m).
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_int(zone._connections.size()).append_failure_message(
		"une cible qui quitte la zone doit être désabonnée de Health.damaged"
	).is_equal(0)


# ======================================================================
#  BalmZoneAbility (E signature, "Baume du Palud") : métadonnées + pose.
# ======================================================================

func test_balm_zone_ability_metadata_matches_the_contract() -> void:
	var ab := BalmZoneAbilityScript.new()
	assert_str(ab.slot).is_equal("E")
	assert_float(ab.cooldown).is_equal_approx(24.0, 0.001)
	assert_int(ab.charges).is_equal(1)
	assert_float(ab.heal_per_second).append_failure_message(
		"Baume du Palud doit soigner à 12 PV/s (contrat AGT-07)"
	).is_equal_approx(12.0, 0.001)
	assert_float(ab.duration).append_failure_message(
		"Baume du Palud doit durer 6 s (contrat AGT-07)"
	).is_equal_approx(6.0, 0.001)
	assert_float(ab.recent_damage_window).is_equal_approx(1.0, 0.001)


func test_balm_zone_ability_spawns_a_team_filtered_heal_zone() -> void:
	var scene := _dummy_scene()
	var o := _offset()
	var caster := _bot_player(o, 1)
	var ab := BalmZoneAbilityScript.new()
	await get_tree().physics_frame

	ab.activate_server(caster, Vector3.FORWARD)

	var zone := scene.get_child(scene.get_child_count() - 1) as HealZone
	assert_object(zone).append_failure_message(
		"BalmZoneAbility.activate_server doit poser une HealZone dans la scène courante"
	).is_not_null()
	assert_int(zone.owner_team).append_failure_message(
		"la flaque doit être filtrée sur l'équipe DU LANCEUR"
	).is_equal(1)
	assert_float(zone.heal_per_second).is_equal_approx(12.0, 0.001)
	assert_float(zone.duration).is_equal_approx(6.0, 0.001)
	assert_bool(zone.is_in_group("round_props")).append_failure_message(
		"la flaque doit rejoindre round_props (BUG-03 : nettoyage de manche)"
	).is_true()


func test_balm_zone_ability_lands_along_the_aim_direction_up_to_throw_range() -> void:
	var scene := _dummy_scene()
	var o := _offset()
	var caster := _bot_player(o, 0)
	var ab := BalmZoneAbilityScript.new()
	await get_tree().physics_frame

	var aim_dir := Vector3(0, 0, -1)
	ab.activate_server(caster, aim_dir)

	var zone := scene.get_child(scene.get_child_count() - 1) as HealZone
	var origin: Vector3 = caster.head.global_position
	var expected := origin + aim_dir * ab.throw_range
	expected.y = maxf(expected.y, caster.global_position.y)
	assert_float(zone.global_position.distance_to(expected)).append_failure_message(
		"sans obstacle, la flaque doit atterrir à `throw_range` le long de la visée"
	).is_less(0.05)


# ======================================================================
#  RenewalAbility ("Sursaut", X) : soin d'équipe à <= 10 m.
# ======================================================================

func test_renewal_ability_heals_an_ally_within_ten_meters() -> void:
	var o := _offset()
	var caster := _bot_player(o, 0)
	var near_ally := _bot_player(o + Vector3(8, 0, 0), 0)  # 8 m <= 10 m
	_health(near_ally).current_health = 10.0
	var ab := RenewalAbilityScript.new()
	await get_tree().physics_frame

	ab.activate_server(caster, Vector3.FORWARD)

	assert_float(_health(near_ally).current_health).append_failure_message(
		"Sursaut doit soigner intégralement un allié à <= 10 m (contrat AGT-07)"
	).is_equal_approx(100.0, 0.001)


func test_renewal_ability_does_not_heal_an_ally_beyond_ten_meters() -> void:
	var o := _offset()
	var caster := _bot_player(o, 0)
	var far_ally := _bot_player(o + Vector3(15, 0, 0), 0)  # 15 m > 10 m
	# Régénération de base désactivée : isole l'assertion de tout apport
	# indépendant de Sursaut (même précaution que les tests de HealZone).
	_health(far_ally).regen_enabled = false
	_health(far_ally).current_health = 10.0
	var ab := RenewalAbilityScript.new()
	await get_tree().physics_frame

	ab.activate_server(caster, Vector3.FORWARD)

	assert_float(_health(far_ally).current_health).append_failure_message(
		"un allié au-delà de 10 m ne doit pas être soigné par Sursaut"
	).is_equal_approx(10.0, 0.001)


func test_renewal_ability_never_heals_an_enemy() -> void:
	var o := _offset()
	var caster := _bot_player(o, 0)
	var enemy := _bot_player(o + Vector3(2, 0, 0), 1)  # proche, mais ennemi
	_health(enemy).regen_enabled = false
	_health(enemy).current_health = 10.0
	var ab := RenewalAbilityScript.new()
	await get_tree().physics_frame

	ab.activate_server(caster, Vector3.FORWARD)

	assert_float(_health(enemy).current_health).append_failure_message(
		"Sursaut ne doit jamais soigner un ennemi, même à portée"
	).is_equal_approx(10.0, 0.001)


func test_renewal_ability_still_fully_heals_the_caster_regardless_of_distance() -> void:
	# Non-régression : le soin total pour elle-même (comportement déjà existant,
	# hors périmètre du critère AGT-07) doit survivre à l'ajout du soin d'équipe.
	var o := _offset()
	var caster := _bot_player(o, 0)
	_health(caster).current_health = 1.0
	var ab := RenewalAbilityScript.new()
	await get_tree().physics_frame

	ab.activate_server(caster, Vector3.FORWARD)

	assert_float(_health(caster).current_health).is_equal_approx(100.0, 0.001)


func test_renewal_ability_does_not_heal_a_dead_ally() -> void:
	var o := _offset()
	var caster := _bot_player(o, 0)
	var dead_ally := _bot_player(o + Vector3(3, 0, 0), 0)
	var hp := _health(dead_ally)
	hp.current_health = 0.0
	hp.is_dead = true
	var ab := RenewalAbilityScript.new()
	await get_tree().physics_frame

	ab.activate_server(caster, Vector3.FORWARD)

	assert_float(hp.current_health).append_failure_message(
		"un allié mort ne doit pas être ramené à la vie par Sursaut"
	).is_equal_approx(0.0, 0.001)


# ======================================================================
#  BaumeAuRepos (passif de Roseau) : régénération 2,5 s / 40 PV/s, elle seule.
# ======================================================================

func test_baume_au_repos_default_values_match_the_contract() -> void:
	var passive := BaumeAuReposScript.new()
	assert_float(passive.regen_delay).append_failure_message(
		"Baume au repos : régénération après 2,5 s sans dégât (contrat AGT-07)"
	).is_equal_approx(2.5, 0.001)
	assert_float(passive.regen_rate).append_failure_message(
		"Baume au repos : 40 PV/s (contrat AGT-07)"
	).is_equal_approx(40.0, 0.001)


func test_baume_au_repos_sets_the_owners_health_regen_on_spawn() -> void:
	var o := _offset()
	var player := _bot_player(o, 0)
	var hp := _health(player)
	# Valeurs de base (Health.gd) que le passif doit remplacer au spawn.
	hp.regen_delay = 4.0
	hp.regen_rate = 35.0
	var passive := BaumeAuReposScript.new()

	passive.on_spawn(player)

	assert_float(hp.regen_delay).is_equal_approx(2.5, 0.001)
	assert_float(hp.regen_rate).is_equal_approx(40.0, 0.001)


func test_baume_au_repos_only_changes_its_owners_health_never_a_teammates() -> void:
	var o := _offset()
	var owner_player := _bot_player(o, 0)
	var teammate := _bot_player(o + Vector3(3, 0, 0), 0)
	var teammate_hp := _health(teammate)
	teammate_hp.regen_delay = 4.0
	teammate_hp.regen_rate = 35.0
	var passive := BaumeAuReposScript.new()

	passive.on_spawn(owner_player)

	assert_float(teammate_hp.regen_delay).append_failure_message(
		"le passif de Roseau ne doit régler QUE son propre composant Health"
	).is_equal_approx(4.0, 0.001)
	assert_float(teammate_hp.regen_rate).is_equal_approx(35.0, 0.001)


func test_baume_au_repos_on_spawn_is_a_safe_no_op_without_a_player() -> void:
	var passive := BaumeAuReposScript.new()
	passive.on_spawn(null)  # ne doit pas planter.
