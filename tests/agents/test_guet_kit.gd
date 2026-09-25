## test_guet_kit.gd
## Spec AGT-06 (docs/research/10_ammo_kits_input.md §3.3, fiche Guet) :
##  - Planeur (passif, scripts/agents/passives/Planeur.gd + branche générique
##    dans scripts/player/states/Air.gd) : chute plafonnée à 2,5 m/s pendant
##    2 s max (recharge au sol), AUCUN étourdissement de chute
##    (PlayerController._check_fall_stun) tant que le vol plané reste actif
##    jusqu'à l'atterrissage, bonus de contrôle aérien (+30 %) lu par Air.gd
##    via `Planeur.control_mult`.
##  - Coup de dé (RevealAbility, "E" signature de Guet) : délai de vol de
##    0,5 s avant que la révélation ne s'applique, avertissement reçu par les
##    SEULES victimes révélées (jamais le reste de leur équipe, jamais
##    l'équipe du lanceur).
##
## Style des doubles : bot réel (scenes/player/player.tscn, autorité SERVEUR
## sans réseau réel), comme tests/agents/test_passives.gd et
## tests/agents/test_roseau_kit.gd/test_choc_kit.gd (fiches sœurs de la même
## vague AGT). Chaque test reçoit un offset XZ dédié (`_offset()`) pour ne
## jamais partager d'espace physique avec un autre test -- même motif que
## tests/agents/test_ability_rays.gd. `_air_peak_y`/`_check_fall_stun()` sont
## manipulés/appelés DIRECTEMENT, comme tests/player/test_respawn_state_reset.gd
## et tests/player/test_state_exits.gd.
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
## Aucun `class_name` sur ces deux fichiers (comme les capacités concrètes,
## ex. FlashAbility.gd, et comme BaumeAuRepos.gd, le passif sœur de Roseau --
## voir tests/agents/test_roseau_kit.gd) -> preload explicite.
const PlaneurScript := preload("res://scripts/agents/passives/Planeur.gd")
const RevealAbilityScript := preload("res://scripts/agents/abilities/RevealAbility.gd")

var _next_offset_index := 0
var _had_prev_scene := false
var _prev_current_scene: Node
## Conteneur DÉDIÉ aux bots de test, recréé à chaque test (before_test) :
## RevealAbility/AbilityController.cast_reveal itère `players_root.
## get_children()` et lit `int(child.get("team"))` sur CHAQUE enfant en
## supposant (comme en jeu réel, où players_root == le nœud "Players" de
## GameWorld) qu'il ne contient QUE des PlayerController -- jamais un nœud
## interne de la suite. Isoler les bots ICI, plutôt que de les ajouter
## directement à la suite, garantit `players_root.get_children()` propre --
## même motif que tests/agents/test_roseau_kit.gd::_players_root.
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


## Scène factice (Node3D) pour recevoir les marqueurs posés par
## `AbilityController.net_show_markers` (`get_tree().current_scene`) -- même
## motif que tests/agents/test_roseau_kit.gd::_dummy_scene.
func _dummy_scene() -> Node3D:
	var s := Node3D.new()
	get_tree().root.add_child(s)
	auto_free(s)
	get_tree().current_scene = s
	return s


## Sol de décor (StaticBody3D, calque WORLD) dont la surface haute est
## exactement à `top.y` -- même construction que
## tests/player/test_respawn_state_reset.gd::_floor.
func _floor(top: Vector3, size: Vector3 = Vector3(10, 1, 10)) -> StaticBody3D:
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


## Joueur RÉEL, spawné en BOT (autorité SERVEUR sans réseau réel -- voir
## PlayerController._enter_tree), même méthode que tests/agents/test_passives.gd
## et tests/agents/test_roseau_kit.gd. Incrémente le MÊME compteur que
## `_offset()` : garantit un nom unique même pour deux bots créés côte à côte
## sans appel à `_offset()` entre les deux.
func _bot_player(pos: Vector3, team: int = 0) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	_next_offset_index += 1
	player.set("is_bot", true)
	player.position = pos
	player.set("spawn_point", pos)
	player.team = team
	_players_root.add_child(player)
	auto_free(player)
	return player


func _ability(cooldown: float, charges: int) -> Ability:
	var a := Ability.new()
	a.cooldown = cooldown
	a.charges = charges
	return a


## Assigne un AgentConfig FRAIS (l'agent par défaut ne pose jamais de
## Planeur) portant le passif fourni au nœud "Abilities" du bot -- même motif
## que tests/agents/test_passives.gd::_bot_with_passive.
func _bot_with_passive(passive: Passive, pos: Vector3) -> PlayerController:
	var player := _bot_player(pos)
	var ctrl := player.get_node("Abilities") as AbilityController
	var cfg := AgentConfig.new()
	cfg.agent_name = "TestGuet"
	cfg.abilities = [_ability(8.0, 2)]
	cfg.passive = passive
	ctrl.agent = cfg
	return player


# ======================================================================
#  Planeur (passif) : configuration
# ======================================================================

func test_planeur_default_config_matches_the_design_numbers() -> void:
	var p = PlaneurScript.new()
	assert_float(p.max_fall_speed).append_failure_message(
		"Planeur : chute plafonnée à 2,5 m/s (contrat AGT-06)"
	).is_equal_approx(2.5, 0.001)
	assert_float(p.glide_duration).append_failure_message(
		"Planeur : budget de vol plané de 2 s max (contrat AGT-06)"
	).is_equal_approx(2.0, 0.001)
	assert_float(p.air_control_bonus).append_failure_message(
		"Planeur : bonus de contrôle aérien de +30 %"
	).is_equal_approx(0.3, 0.001)


# ======================================================================
#  Planeur : plafond de chute (Air.gd::physics_update -> Passive.on_air)
# ======================================================================

func test_gliding_caps_the_fall_speed() -> void:
	var player := _bot_with_passive(PlaneurScript.new(), _offset())
	await get_tree().physics_frame
	player.state_machine.transition_to("Air", {})
	player.velocity.y = -20.0
	player.input.jump_held = true

	player.state_machine.physics_update(1.0 / 60.0)

	assert_float(player.velocity.y).append_failure_message(
		"le vol plané doit plafonner la chute à -2,5 m/s (obtenu : %.3f)" % player.velocity.y
	).is_greater_equal(-2.5001)


func test_without_holding_jump_the_fall_is_not_capped() -> void:
	var player := _bot_with_passive(PlaneurScript.new(), _offset())
	await get_tree().physics_frame
	player.state_machine.transition_to("Air", {})
	player.velocity.y = -20.0
	player.input.jump_held = false

	player.state_machine.physics_update(1.0 / 60.0)

	assert_float(player.velocity.y).append_failure_message(
		"sans Saut tenu, le vol plané ne doit rien plafonner -- seule la gravité s'applique"
	).is_less(-19.0)


func test_air_state_is_a_safe_no_op_without_any_passive() -> void:
	# Agent par défaut (aucun `cfg.passive =` encore posé ailleurs dans
	# AgentDatabase.gd au moment de ce contrat) : la branche Planeur ne doit
	# rien casser pour un agent sans passif.
	var player := _bot_player(_offset())
	await get_tree().physics_frame
	player.state_machine.transition_to("Air", {})
	player.velocity.y = -20.0
	player.input.jump_held = true

	player.state_machine.physics_update(1.0 / 60.0)  # ne doit pas planter

	assert_float(player.velocity.y).append_failure_message(
		"sans passif, aucun plafond de chute -- seule la gravité s'applique"
	).is_less(-19.0)


func test_glide_budget_is_exhausted_after_two_seconds_of_holding_jump() -> void:
	var player := _bot_with_passive(PlaneurScript.new(), _offset())
	await get_tree().physics_frame
	player.state_machine.transition_to("Air", {})
	player.input.jump_held = true

	var step := 1.0 / 60.0
	var elapsed := 0.0
	while elapsed < 2.05:
		player.velocity.y = -20.0  # une chute qui "voudrait" toujours aller vite.
		player.state_machine.physics_update(step)
		elapsed += step

	assert_float(player.velocity.y).append_failure_message(
		"après 2 s de vol plané tenu, le budget doit être épuisé -- la chute redevient normale (non plafonnée)"
	).is_less(-2.5001)


func test_entering_air_resets_the_glide_budget_even_if_it_was_drained() -> void:
	var passive = PlaneurScript.new()
	var player := _bot_with_passive(passive, _offset())
	await get_tree().physics_frame
	player.set_meta("planeur_glide_time_left", 0.0)  # budget épuisé (vol précédent).

	player.state_machine.transition_to("Air", {})  # "recharge au sol".

	assert_float(PlaneurScript.glide_time_left(player)).append_failure_message(
		"entrer dans \"Air\" doit remettre le budget de vol plané à fond (recharge au sol)"
	).is_equal_approx(passive.glide_duration, 0.001)


# ======================================================================
#  Planeur : bonus de contrôle aérien (+30 %, lu via Planeur.control_mult)
# ======================================================================

func test_control_mult_is_boosted_while_actively_gliding() -> void:
	var player := _bot_with_passive(PlaneurScript.new(), _offset())
	await get_tree().physics_frame
	player.state_machine.transition_to("Air", {})
	player.input.jump_held = true
	player.velocity.y = -1.0

	player.state_machine.physics_update(1.0 / 60.0)

	assert_float(PlaneurScript.control_mult(player)).append_failure_message(
		"le contrôle aérien doit recevoir +30% pendant le vol plané actif"
	).is_equal_approx(1.3, 0.001)


func test_control_mult_is_neutral_without_holding_jump() -> void:
	var player := _bot_with_passive(PlaneurScript.new(), _offset())
	await get_tree().physics_frame
	player.state_machine.transition_to("Air", {})
	player.input.jump_held = false

	player.state_machine.physics_update(1.0 / 60.0)

	assert_float(PlaneurScript.control_mult(player)).append_failure_message(
		"sans Saut tenu, le contrôle aérien ne doit recevoir aucun bonus"
	).is_equal_approx(1.0, 0.001)


# ======================================================================
#  Planeur : AUCUN étourdissement de chute tant qu'il plane
#  (PlayerController._check_fall_stun -- appelé directement, même motif que
#  tests/player/test_respawn_state_reset.gd).
# ======================================================================

func test_gliding_all_the_way_down_prevents_the_landing_stun() -> void:
	var o := _offset()
	_floor(o)
	# 4,8 m de chute : sous le budget du planeur (2,5 m/s * 2 s = 5 m max),
	# mais AU-DESSUS de `fall_min_height` (4 m) -- sans vol plané, cette même
	# chute étourdirait (voir le test de non-régression ci-dessous).
	var player := _bot_with_passive(PlaneurScript.new(), o + Vector3(0, 4.8, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	player.state_machine.transition_to("Air", {})
	player.input.jump_held = true

	var step := 1.0 / 60.0
	var gp := player.global_position
	while gp.y > o.y + 0.05:
		player.state_machine.physics_update(step)
		gp.y += player.velocity.y * step
		player.global_position = gp

	# Contact sol réel (comme test_respawn_state_reset.gd), puis flanc d'atterrissage.
	gp.y = o.y
	player.global_position = gp
	player.velocity.y = -1.0
	player.move_and_slide()
	assert_bool(player.is_on_floor()).append_failure_message(
		"préalable du test : le joueur doit être détecté au sol"
	).is_true()
	player._was_on_floor = false

	player._check_fall_stun()

	assert_str(player.state_machine.current_name).append_failure_message(
		"le vol plané jusqu'au sol ne doit JAMAIS déclencher le stun de chute -- état obtenu : %s (_air_peak_y=%.2f, y=%.2f)"
			% [player.state_machine.current_name, player._air_peak_y, player.global_position.y]
	).is_not_equal("Stun")


func test_the_same_short_fall_without_holding_jump_still_triggers_the_landing_stun() -> void:
	# Non-régression : preuve que le test précédent est significatif -- sans
	# Saut tenu (pas de vol plané), une chute au-dessus du seuil de stun doit
	# étourdir normalement (comportement PlayerController inchangé, hors
	# périmètre de ce contrat). DÉCISION LEAD (GF-29) : 7 m ici, plutôt que les
	# 4,8 m d'origine -- MV-03 a porté MovementConfig.fall_min_height de 4 m à
	# 6 m (tests/player/test_fall_stun.gd), donc 4,8 m ne dépasse plus le
	# seuil et ne prouverait plus rien ; 7 m dépasse à la fois ce nouveau seuil
	# ET le budget du planeur (2,5 m/s * 2 s = 5 m max), mais ce dernier point
	# n'a pas d'importance ICI (jump_held = false, aucun vol plané) -- ce qui
	# garde l'intention du test : une chute franchement au-dessus du seuil de
	# stun (6 m) doit toujours étourdir.
	var o := _offset()
	_floor(o)
	var player := _bot_with_passive(PlaneurScript.new(), o + Vector3(0, 7.0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	player.state_machine.transition_to("Air", {})
	player.input.jump_held = false

	var step := 1.0 / 60.0
	var gp := player.global_position
	while gp.y > o.y + 0.05:
		player.state_machine.physics_update(step)
		gp.y += player.velocity.y * step
		player.global_position = gp

	gp.y = o.y
	player.global_position = gp
	player.velocity.y = -1.0
	player.move_and_slide()
	assert_bool(player.is_on_floor()).is_true()
	player._was_on_floor = false

	player._check_fall_stun()

	assert_str(player.state_machine.current_name).append_failure_message(
		"préalable du test : sans vol plané, une chute de 7 m (> fall_min_height = 6 m) doit étourdir -- état obtenu : %s"
			% player.state_machine.current_name
	).is_equal("Stun")


# ======================================================================
#  Coup de dé (RevealAbility, E signature de Guet) : métadonnées + délai de
#  vol + avertissement réservé aux seules victimes.
# ======================================================================

func test_reveal_ability_defaults_preserve_existing_behaviour() -> void:
	# "Œil"/"Voile"/"Vision totale" ne fixent ni `flight_time` ni
	# `warn_victims` -- ces deux réglages doivent donc rester neutres par
	# défaut (aucune régression sur les fiches existantes).
	var ab := RevealAbilityScript.new()
	assert_float(ab.flight_time).append_failure_message(
		"le délai de vol par défaut doit rester 0 s"
	).is_equal_approx(0.0, 0.001)
	assert_bool(ab.warn_victims).append_failure_message(
		"l'avertissement doit rester désactivé par défaut"
	).is_false()


func test_victims_to_warn_only_returns_entries_that_carry_a_node() -> void:
	var fake_a := Node.new()
	var fake_b := Node.new()
	auto_free(fake_a)
	auto_free(fake_b)
	var revealed := [
		{"pos": Vector3.ZERO, "team": 1, "node": fake_a},
		{"pos": Vector3.ONE, "team": 1, "node": fake_b},
		{"pos": Vector3.ONE, "team": 1},  # entrée défensive sans "node".
	]

	var out := RevealAbilityScript.victims_to_warn(revealed)

	assert_int(out.size()).append_failure_message(
		"une entrée révélée = UNE victime à prévenir, jamais plus, jamais moins"
	).is_equal(2)
	assert_bool(out.has(fake_a)).is_true()
	assert_bool(out.has(fake_b)).is_true()


func test_activate_server_delays_the_reveal_by_flight_time() -> void:
	var scene := _dummy_scene()
	var o := _offset()
	var caster := _bot_player(o, 0)
	var victim := _bot_player(o + Vector3(0, 0, -22), 1)
	# Simule un joueur réel (avec écran) pour observer son marqueur --
	# `is_bot` est un champ SÉPARÉ du nommage par id (>= BOT_ID_START, qui ne
	# fixe que l'AUTORITÉ réseau -- voir PlayerController._enter_tree) : ce
	# joueur reste simulé ICI (appel direct, sans RPC réseau réelle), comme
	# n'importe quel bot de ce fichier de test.
	victim.set("is_bot", false)
	await get_tree().physics_frame

	var ab := RevealAbilityScript.new()
	ab.throw_range = 22.0
	ab.reveal_radius = 9.0
	ab.duration = 2.5
	ab.flight_time = 0.5
	ab.warn_victims = true

	ab.activate_server(caster, Vector3(0, 0, -1))

	assert_int(scene.get_child_count()).append_failure_message(
		"le délai de vol (0,5 s) doit retarder TOUTE la résolution -- rien ne doit apparaître immédiatement"
	).is_equal(0)

	await get_tree().create_timer(0.6).timeout

	assert_int(scene.get_child_count()).append_failure_message(
		"une fois le délai de vol écoulé (0,5 s), la révélation doit s'appliquer"
	).is_greater(0)


func test_activate_server_warns_only_the_revealed_victim() -> void:
	var scene := _dummy_scene()
	var o := _offset()
	var caster := _bot_player(o, 0)
	var ally := _bot_player(o + Vector3(1, 0, 0), 0)
	var victim := _bot_player(o + Vector3(0, 0, -22), 1)          # dans le rayon (9 m) du point d'impact.
	var bystander := _bot_player(o + Vector3(6, 0, 0), 1)         # même équipe que la victime, HORS rayon.
	victim.set("is_bot", false)
	bystander.set("is_bot", false)
	ally.set("is_bot", false)
	await get_tree().physics_frame

	var ab := RevealAbilityScript.new()
	ab.throw_range = 22.0
	ab.reveal_radius = 9.0
	ab.duration = 2.5
	ab.warn_victims = true

	ab.activate_server(caster, Vector3(0, 0, -1))

	var found_over_victim := false
	var found_over_bystander := false
	var found_over_ally := false
	for child in scene.get_children():
		var l := child as Label3D
		if l == null:
			continue
		if l.global_position.distance_to(victim.global_position + Vector3(0, 1.6, 0)) < 0.1:
			found_over_victim = true
		if l.global_position.distance_to(bystander.global_position + Vector3(0, 1.6, 0)) < 0.1:
			found_over_bystander = true
		if l.global_position.distance_to(ally.global_position + Vector3(0, 1.6, 0)) < 0.1:
			found_over_ally = true

	assert_bool(found_over_victim).append_failure_message(
		"la victime révélée (dans le rayon) doit recevoir SON PROPRE marqueur d'avertissement"
	).is_true()
	assert_bool(found_over_bystander).append_failure_message(
		"un ennemi HORS du rayon (jamais révélé) ne doit recevoir AUCUN avertissement"
	).is_false()
	assert_bool(found_over_ally).append_failure_message(
		"un allié du lanceur ne doit jamais recevoir l'avertissement réservé aux victimes"
	).is_false()


func test_activate_server_does_not_warn_anyone_when_warn_victims_is_disabled() -> void:
	# Non-régression : "Voile"/"Vision totale" laissent `warn_victims` à
	# false -- aucun avertissement individuel ne doit apparaître (seul
	# `cast_reveal`, déjà existant et inchangé, s'applique).
	var scene := _dummy_scene()
	var o := _offset()
	var caster := _bot_player(o, 0)
	var victim := _bot_player(o + Vector3(0, 0, -22), 1)
	victim.set("is_bot", false)
	await get_tree().physics_frame

	var ab := RevealAbilityScript.new()
	ab.throw_range = 22.0
	ab.reveal_radius = 9.0
	ab.duration = 2.5
	# `warn_victims` reste à sa valeur par défaut (false).

	ab.activate_server(caster, Vector3(0, 0, -1))

	assert_int(scene.get_child_count()).append_failure_message(
		"warn_victims == false : aucun marqueur individuel ne doit être posé"
	).is_equal(0)
