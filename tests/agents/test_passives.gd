## test_passives.gd
## Spec AGT-01 (docs/research/10_ammo_kits_input.md §3.5, "Socle commun à
## construire") : passifs d'agent, assistances, et les deux primitives de
## relance de AbilityState (grant_charge/arm) + la repoussée (net_apply_impulse).
## Critère d'acceptation "Hooks serveur appelés" : couvert par les tests
## AbilityController ci-dessous (server_on_kill/server_on_assist appellent bien
## Passive.on_kill/on_assist avec le bon joueur/victime, et net_apply_stun/
## net_apply_flash appliquent bien Passive.modify_cc_duration CHEZ LA VICTIME).
## Critère "Repoussée appliquée chez le propriétaire distant" : net_apply_impulse
## est la fonction REÇUE par le propriétaire (RPC "authority" -- voir sa
## docstring dans AbilityController.gd) ; elle est appelée ici DIRECTEMENT,
## exactement comme le reste du dépôt teste déjà net_apply_stun/net_show_markers
## (tests/agents/test_round_props_cleanup.gd) sans transport réseau réel : la
## RPC ne change QUE la manière dont l'appel arrive (direct pour un bot/hôte,
## réseau pour un pair distant), jamais le corps de la fonction qui l'applique.
##
## Style des doubles : bot réel (`scenes/player/player.tscn`, autorité SERVEUR
## sans réseau réel), comme tests/agents/test_round_props_cleanup.gd::_bot_player.
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _next_offset_index := 0


## Double qui ENREGISTRE chaque appel de hook, pour prouver qu'AbilityController
## les déclenche avec les bons arguments (contract-r3.md style : double minimal,
## jamais un mock générique).
class _RecordingPassive extends Passive:
	var spawn_calls: Array = []
	var kill_calls: Array = []
	var assist_calls: Array = []
	## Multiplicateur appliqué par `modify_cc_duration` (1.0 = neutre par défaut).
	var cc_factor: float = 1.0

	func on_spawn(player: PlayerController) -> void:
		spawn_calls.append(player)

	func on_kill(player: PlayerController, victim_id: int) -> void:
		kill_calls.append({"player": player, "victim_id": victim_id})

	func on_assist(player: PlayerController, victim_id: int) -> void:
		assist_calls.append({"player": player, "victim_id": victim_id})

	func modify_cc_duration(duration: float) -> float:
		return duration * cc_factor


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


## Joueur RÉEL, spawné en BOT (autorité SERVEUR sans réseau réel -- même
## méthode que test_round_props_cleanup.gd/test_ability_rays.gd).
func _bot_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	player.set("is_bot", true)
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	auto_free(player)
	return player


func _abilities(player: PlayerController) -> AbilityController:
	return player.get_node("Abilities") as AbilityController


func _ability(cooldown: float, charges: int, is_ultimate: bool = false, ult_cost: int = 7) -> Ability:
	var a := Ability.new()
	a.cooldown = cooldown
	a.charges = charges
	a.is_ultimate = is_ultimate
	a.ult_cost = ult_cost
	return a


# ============================================================ Passive : socle
# (implémentation par défaut, aucune capacité concrète -- juste la classe de base)

func test_passive_default_modify_cc_duration_is_neutral() -> void:
	var p := Passive.new()
	assert_float(p.modify_cc_duration(2.5)).is_equal_approx(2.5, 0.001)


func test_passive_default_spread_mult_is_neutral() -> void:
	var p := Passive.new()
	assert_float(p.spread_mult(null)).is_equal_approx(1.0, 0.001)


func test_passive_default_hooks_do_not_crash_without_a_player() -> void:
	var p := Passive.new()
	p.on_spawn(null)
	p.on_kill(null, 5)
	p.on_assist(null, 5)
	p.on_air(null, 0.016)
	# Aucune assertion : la seule exigence est de ne pas planter (no-op par défaut).


# ================================================ AgentConfig : champ `passive`

func test_agent_config_passive_defaults_to_null() -> void:
	var cfg := AgentConfig.new()
	assert_object(cfg.passive).is_null()


func test_agent_config_passive_can_be_assigned() -> void:
	var cfg := AgentConfig.new()
	var p := _RecordingPassive.new()
	cfg.passive = p
	assert_object(cfg.passive).is_same(p)


# ===================================================== AssistTracker (pur)

func test_damage_below_the_assist_threshold_is_not_an_assist() -> void:
	var t := AssistTracker.new()
	t.record_damage(1, 2, 39.0, 10.0)
	assert_array(t.assists_for_kill(1, 999, 10.5)).is_empty()


func test_damage_at_the_assist_threshold_is_an_assist() -> void:
	var t := AssistTracker.new()
	t.record_damage(1, 2, 40.0, 10.0)
	assert_array(t.assists_for_kill(1, 999, 10.5)).is_equal([2])


func test_damage_outside_the_5s_window_before_death_does_not_count() -> void:
	var t := AssistTracker.new()
	t.record_damage(1, 2, 60.0, 10.0)
	# la mort survient à 15.01 -> le coup de 10.0 a 5.01 s, hors fenêtre.
	assert_array(t.assists_for_kill(1, 999, 15.01)).append_failure_message(
		"un dégât de plus de 5 s avant la mort ne doit plus compter pour l'assistance"
	).is_empty()


func test_damage_at_the_window_edge_still_counts() -> void:
	var t := AssistTracker.new()
	t.record_damage(1, 2, 60.0, 10.0)
	assert_array(t.assists_for_kill(1, 999, 15.0)).is_equal([2])


func test_damage_cumulates_across_multiple_hits_within_the_window() -> void:
	var t := AssistTracker.new()
	t.record_damage(1, 2, 20.0, 10.0)
	t.record_damage(1, 2, 25.0, 12.0)
	assert_array(t.assists_for_kill(1, 999, 13.0)).append_failure_message(
		"20 + 25 = 45 dégâts cumulés du même attaquant doivent dépasser le seuil de 40"
	).is_equal([2])


func test_the_killer_is_never_counted_as_its_own_assist() -> void:
	var t := AssistTracker.new()
	t.record_damage(1, 5, 100.0, 10.0)
	assert_array(t.assists_for_kill(1, 5, 10.5)).append_failure_message(
		"un kill n'est jamais aussi sa propre assistance"
	).is_empty()


func test_self_damage_and_environment_damage_are_ignored() -> void:
	var t := AssistTracker.new()
	t.record_damage(1, 1, 100.0, 10.0)   # dégât à soi-même
	t.record_damage(1, 0, 100.0, 10.0)   # environnement
	t.record_damage(1, -1, 100.0, 10.0)  # id invalide
	assert_array(t.assists_for_kill(1, 999, 10.5)).is_empty()


func test_multiple_attackers_can_each_earn_an_assist() -> void:
	var t := AssistTracker.new()
	t.record_damage(1, 2, 50.0, 10.0)
	t.record_damage(1, 3, 45.0, 10.2)
	var out := t.assists_for_kill(1, 999, 10.5)
	assert_int(out.size()).is_equal(2)
	assert_bool(out.has(2)).is_true()
	assert_bool(out.has(3)).is_true()


func test_assists_for_kill_purges_history_so_the_next_life_starts_clean() -> void:
	var t := AssistTracker.new()
	t.record_damage(1, 2, 100.0, 10.0)
	t.assists_for_kill(1, 999, 10.5)
	assert_array(t.assists_for_kill(1, 999, 10.6)).append_failure_message(
		"une mort ferme la fenêtre : la vie suivante ne doit rien hériter des dégâts d'avant"
	).is_empty()


func test_different_victims_are_tracked_independently() -> void:
	var t := AssistTracker.new()
	t.record_damage(1, 2, 100.0, 10.0)
	t.record_damage(9, 2, 100.0, 10.0)
	t.assists_for_kill(1, 999, 10.5)
	assert_array(t.assists_for_kill(9, 999, 10.5)).append_failure_message(
		"consommer l'historique d'une victime ne doit pas affecter celui d'une autre"
	).is_equal([2])


# ============================================= AbilityState : grant_charge / arm

func test_grant_charge_adds_one_charge_without_touching_cooldown() -> void:
	var a := _ability(5.0, 3)
	var state := AbilityState.new([a])
	state.try_activate(0)  # 3 -> 2, cooldown démarre à 5.0
	state.try_activate(0)  # 2 -> 1, charges n'étaient pas pleines -> cooldown inchangé
	state.tick(2.0, true)  # cooldown -> 3.0

	state.grant_charge(0)  # 1 -> 2, encore SOUS le maximum (3) -> ne doit pas effacer le cooldown

	assert_int(state.charges(0)).is_equal(2)
	assert_float(state.cooldown_left(0)).append_failure_message(
		"grant_charge ne doit pas toucher un cooldown déjà en cours tant que la capacité n'est pas repassée pleine"
	).is_equal_approx(3.0, 0.001)


func test_grant_charge_is_capped_at_the_ability_maximum() -> void:
	var a := _ability(5.0, 2)
	var state := AbilityState.new([a])
	assert_int(state.charges(0)).is_equal(2)

	state.grant_charge(0)

	assert_int(state.charges(0)).append_failure_message(
		"Mèche courte de Vif : la charge octroyée est plafonnée (ex. 2 max)"
	).is_equal(2)


func test_grant_charge_clears_cooldown_once_back_to_full() -> void:
	var a := _ability(5.0, 1)
	var state := AbilityState.new([a])
	state.try_activate(0)  # 1 -> 0, cooldown démarre à 5.0

	state.grant_charge(0)

	assert_int(state.charges(0)).is_equal(1)
	assert_float(state.cooldown_left(0)).append_failure_message(
		"une fois pleine, plus rien à régénérer -- le cooldown doit retomber à 0"
	).is_equal_approx(0.0, 0.001)


func test_grant_charge_has_no_effect_on_an_ultimate() -> void:
	var ult := _ability(0.0, 1, true, 7)
	var state := AbilityState.new([ult])
	state.grant_charge(0)
	assert_float(state.ult_points()).is_equal_approx(0.0, 0.001)


func test_grant_charge_ignores_an_out_of_bounds_index() -> void:
	var a := _ability(5.0, 1)
	var state := AbilityState.new([a])
	state.grant_charge(5)  # ne doit pas planter
	assert_int(state.charges(0)).is_equal(1)


func test_arm_marks_the_ability_as_armed_until_the_window_elapses() -> void:
	var a := _ability(16.0, 1)
	var state := AbilityState.new([a])
	assert_bool(state.is_armed(0)).is_false()

	state.arm(0, 5.0)
	assert_bool(state.is_armed(0)).is_true()

	state.tick(4.9, true)
	assert_bool(state.is_armed(0)).is_true()

	state.tick(0.2, true)
	assert_bool(state.is_armed(0)).append_failure_message(
		"la fenêtre de relance (5 s) doit être expirée après 5.1 s"
	).is_false()


func test_arm_window_does_not_advance_while_inactive() -> void:
	var a := _ability(16.0, 1)
	var state := AbilityState.new([a])
	state.arm(0, 5.0)
	state.tick(10.0)  # active par défaut = false (mort / hors phase LIVE)
	assert_bool(state.is_armed(0)).append_failure_message(
		"la fenêtre de relance doit rester gelée hors phase active, comme charges/cooldown"
	).is_true()


func test_disarm_clears_the_window_immediately() -> void:
	var a := _ability(16.0, 1)
	var state := AbilityState.new([a])
	state.arm(0, 5.0)
	state.disarm(0)
	assert_bool(state.is_armed(0)).is_false()


func test_armed_window_round_trips_through_to_dict_apply_dict() -> void:
	var a := _ability(16.0, 1)
	var state := AbilityState.new([a])
	state.arm(0, 5.0)
	state.tick(1.0, true)

	var d := state.to_dict()
	var restored := AbilityState.new([_ability(16.0, 1)])
	restored.apply_dict(d)

	assert_bool(restored.is_armed(0)).is_true()


# ================================================== AbilityController : hooks

## Prépare un joueur bot dont l'agent porte le passif fourni (agent frais,
## AgentDatabase n'est jamais muté -- l'agent par défaut résolu par `_ready()`
## reste intact pour les autres tests/joueurs).
func _bot_with_passive(passive: Passive) -> AbilityController:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	var cfg := AgentConfig.new()
	cfg.agent_name = "TestAgent"
	cfg.abilities = [_ability(8.0, 2)]
	cfg.passive = passive
	ctrl.agent = cfg
	return ctrl


## `_bot_with_passive` ci-dessus ne peut pas `await` (ce n'est pas un test) :
## chaque appelant attend un tick physique juste après, comme
## test_round_props_cleanup.gd::test_server_refill_restores_charges_...


func test_server_on_kill_calls_the_passive_with_the_player_and_victim() -> void:
	var passive := _RecordingPassive.new()
	var ctrl := _bot_with_passive(passive)
	await get_tree().physics_frame

	ctrl.server_on_kill(42)

	assert_int(passive.kill_calls.size()).is_equal(1)
	assert_object(passive.kill_calls[0]["player"]).is_same(ctrl.player)
	assert_int(passive.kill_calls[0]["victim_id"]).is_equal(42)


func test_server_on_assist_calls_the_passive_with_the_player_and_victim() -> void:
	var passive := _RecordingPassive.new()
	var ctrl := _bot_with_passive(passive)
	await get_tree().physics_frame

	ctrl.server_on_assist(7)

	assert_int(passive.assist_calls.size()).is_equal(1)
	assert_object(passive.assist_calls[0]["player"]).is_same(ctrl.player)
	assert_int(passive.assist_calls[0]["victim_id"]).is_equal(7)


func test_server_on_kill_is_a_safe_no_op_without_a_passive() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	ctrl.server_on_kill(1)  # ne doit pas planter (agent par défaut sans passif)


func test_server_on_assist_is_a_safe_no_op_without_a_passive() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	ctrl.server_on_assist(1)  # ne doit pas planter


func test_net_apply_stun_applies_the_passive_reduction_to_the_victim() -> void:
	# Tête de cloche de Choc (-40%) : ici généralisé via cc_factor pour rester
	# indépendant de la fiche concrète (AGT-03, hors fichiers possédés ici).
	var passive := _RecordingPassive.new()
	passive.cc_factor = 0.6
	var ctrl := _bot_with_passive(passive)
	await get_tree().physics_frame

	ctrl.net_apply_stun(2.0)

	var stun_state = ctrl.player.state_machine._states["Stun"]
	assert_float(stun_state._duration).append_failure_message(
		"le passif doit réduire la durée du contrôle SUBI (2.0 * 0.6 = 1.2)"
	).is_equal_approx(1.2, 0.001)


func test_net_apply_stun_is_neutral_without_a_passive() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame

	ctrl.net_apply_stun(2.0)

	var stun_state = ctrl.player.state_machine._states["Stun"]
	assert_float(stun_state._duration).is_equal_approx(2.0, 0.001)


func test_net_apply_flash_applies_the_passive_reduction_for_a_bot() -> void:
	var passive := _RecordingPassive.new()
	passive.cc_factor = 0.5
	var ctrl := _bot_with_passive(passive)
	await get_tree().physics_frame
	var before := Time.get_ticks_msec() / 1000.0

	ctrl.net_apply_flash(4.0)  # bot -> "blinded_until", pas d'écran (BotBrain le lit)

	var blinded_until: float = ctrl.player.get_meta("blinded_until")
	assert_float(blinded_until - before).append_failure_message(
		"4.0 s * 0.5 (passif) doit donner ~2.0 s d'aveuglement, pas 4.0 s"
	).is_between(1.9, 2.2)


func test_cc_mult_status_and_passive_combine_by_multiplication() -> void:
	# Passif (0.5) ET statut générique (server_apply_cc_mult, 0.5) doivent se
	# combiner (0.5 * 0.5 = 0.25), jamais l'un remplacer l'autre.
	var passive := _RecordingPassive.new()
	passive.cc_factor = 0.5
	var ctrl := _bot_with_passive(passive)
	await get_tree().physics_frame
	ctrl.server_apply_cc_mult(0.5, 10.0)

	ctrl.net_apply_stun(4.0)

	var stun_state = ctrl.player.state_machine._states["Stun"]
	assert_float(stun_state._duration).is_equal_approx(1.0, 0.001)


func test_net_apply_impulse_adds_to_the_owners_velocity() -> void:
	# Reçu CHEZ LE PROPRIÉTAIRE (mouvement client-autoritaire) : cette fonction
	# est appelée directement pour un bot/hôte, ou via RPC pour un pair distant
	# -- même corps de fonction dans les deux cas (voir docstring du fichier).
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	player.velocity = Vector3(1.0, 0.0, 0.0)

	ctrl.net_apply_impulse(Vector3(0.0, 0.0, 5.0))

	assert_bool(player.velocity.is_equal_approx(Vector3(1.0, 0.0, 5.0))).append_failure_message(
		"la repoussée doit s'AJOUTER à la vélocité courante, jamais l'écraser"
	).is_true()


func test_net_apply_impulse_accumulates_across_two_calls() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	player.velocity = Vector3.ZERO

	ctrl.net_apply_impulse(Vector3(0.0, 0.0, 3.0))
	ctrl.net_apply_impulse(Vector3(0.0, 0.0, 3.0))

	assert_bool(player.velocity.is_equal_approx(Vector3(0.0, 0.0, 6.0))).is_true()


func test_server_grant_charge_pushes_the_correction_to_the_owner_immediately() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	ctrl._server_state.try_activate(0)
	var max_charges: int = ctrl.agent.abilities[0].charges

	ctrl.server_grant_charge(0)

	assert_int(ctrl._server_state.charges(0)).is_equal(max_charges)
	assert_int(ctrl._owner_state.charges(0)).append_failure_message(
		"server_grant_charge doit pousser la correction au propriétaire, pas seulement à l'état autoritaire"
	).is_equal(max_charges)


func test_server_arm_pushes_the_correction_to_the_owner_immediately() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame

	ctrl.server_arm(0, 6.0)

	assert_bool(ctrl._server_state.is_armed(0)).is_true()
	assert_bool(ctrl._owner_state.is_armed(0)).append_failure_message(
		"server_arm doit pousser la fenêtre de relance au propriétaire (bot : appel direct, <= 1 tick)"
	).is_true()
