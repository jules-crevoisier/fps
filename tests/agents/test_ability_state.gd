## test_ability_state.gd
## Spec (contract-p0.md, AbilityState): non-ult charges/cooldown state machine
## and ult points-over-time, keyed by ability slot index. Ability instances are
## built explicitly (Ability.new()) so cooldown/charges/is_ultimate/ult_cost are
## exact and independent of any concrete ability resource.
## AGT-02 (§3.4, docs/research/10_ammo_kits_input.md) ajoute l'économie
## d'ultime : ces tests référencent les constantes réelles de GameWorld.gd
## (ULT_DAMAGE_RATE/ULT_KILL_POINTS/ULT_OBJECTIVE_POINTS), accessibles sans
## instancier de scène (class_name statique).
extends GdUnitTestSuite


func _ability(cooldown: float, charges: int, is_ultimate: bool = false, ult_cost: int = 7) -> Ability:
	var a := Ability.new()
	a.cooldown = cooldown
	a.charges = charges
	a.is_ultimate = is_ultimate
	a.ult_cost = ult_cost
	return a


func test_try_activate_consumes_a_charge() -> void:
	var a := _ability(8.0, 2)
	var state := AbilityState.new([a])
	assert_int(state.charges(0)).is_equal(2)
	assert_bool(state.try_activate(0)).is_true()
	assert_int(state.charges(0)).is_equal(1)


func test_cooldown_starts_only_when_charges_were_full() -> void:
	var a := _ability(5.0, 3)
	var state := AbilityState.new([a])
	assert_float(state.cooldown_left(0)).is_equal_approx(0.0, 0.001)

	# charges were full (3) before this consume -> cooldown must start
	state.try_activate(0)
	assert_float(state.cooldown_left(0)).is_equal_approx(5.0, 0.001)


func test_second_activation_while_not_full_does_not_restart_cooldown() -> void:
	var a := _ability(5.0, 3)
	var state := AbilityState.new([a])
	state.try_activate(0)  # 3 -> 2, cooldown starts at 5.0
	state.tick(2.0, true)  # cooldown counts down to 3.0
	state.try_activate(0)  # 2 -> 1, charges were NOT full -> cooldown unaffected
	assert_float(state.cooldown_left(0)).is_equal_approx(3.0, 0.001)


func test_regen_one_charge_per_cooldown() -> void:
	var a := _ability(4.0, 1)
	var state := AbilityState.new([a])
	state.try_activate(0)
	assert_int(state.charges(0)).is_equal(0)

	state.tick(4.0, true)
	assert_int(state.charges(0)).is_equal(1)
	# back to full -> cooldown must not restart
	assert_float(state.cooldown_left(0)).is_equal_approx(0.0, 0.001)


func test_multi_charge_regen_restarts_cooldown_until_full() -> void:
	var a := _ability(2.0, 3)
	var state := AbilityState.new([a])
	state.try_activate(0)  # 3 -> 2, cooldown starts
	state.try_activate(0)  # 2 -> 1, charges were not full, cooldown unaffected

	state.tick(2.0, true)  # first regen: 1 -> 2, still below max -> cooldown restarts
	assert_int(state.charges(0)).is_equal(2)
	assert_float(state.cooldown_left(0)).is_equal_approx(2.0, 0.001)

	state.tick(2.0, true)  # second regen: 2 -> 3 (full) -> cooldown stops
	assert_int(state.charges(0)).is_equal(3)
	assert_float(state.cooldown_left(0)).is_equal_approx(0.0, 0.001)


func test_can_activate_false_and_try_activate_false_when_no_charge() -> void:
	var a := _ability(8.0, 1)
	var state := AbilityState.new([a])
	state.try_activate(0)
	assert_bool(state.can_activate(0)).is_false()
	assert_bool(state.try_activate(0)).is_false()
	assert_int(state.charges(0)).is_equal(0)


## AGT-02 (§3.4, docs/research/10_ammo_kits_input.md) ramène le gain continu
## de 0,1 pt/s (BUG-04) à 0,02 pt/s : à ce rythme, l'ultime dépend surtout des
## dégâts/kills (voir les tests d'économie plus bas), pas du temps passé en
## vie. Remplace test_default_ult_charge_rate_is_0_1 (BUG-04), valeur
## superseded par cette tâche.
func test_default_ult_charge_rate_is_0_02() -> void:
	var ult := _ability(0.0, 1, true, 7)
	var state := AbilityState.new([ult])
	assert_float(state.ult_charge_rate).is_equal_approx(0.02, 0.0001)

	state.tick(10.0, true)
	assert_float(state.ult_points()).is_equal_approx(0.2, 0.001)


func test_tick_inactive_by_default_adds_nothing() -> void:
	var a := _ability(4.0, 1)
	var ult := _ability(0.0, 1, true, 7)
	var state := AbilityState.new([a, ult])
	state.try_activate(0)  # 1 -> 0, cooldown starts at 4.0

	state.tick(10.0)  # active defaults to false -> frozen (dead or hors phase active)
	assert_int(state.charges(0)).is_equal(0)
	assert_float(state.cooldown_left(0)).is_equal_approx(4.0, 0.001)
	assert_float(state.ult_points()).is_equal_approx(0.0, 0.001)


func test_tick_explicit_inactive_adds_nothing() -> void:
	var a := _ability(4.0, 1)
	var ult := _ability(0.0, 1, true, 7)
	var state := AbilityState.new([a, ult])
	state.try_activate(0)  # 1 -> 0, cooldown starts at 4.0

	state.tick(10.0, false)
	assert_int(state.charges(0)).is_equal(0)
	assert_float(state.cooldown_left(0)).is_equal_approx(4.0, 0.001)
	assert_float(state.ult_points()).is_equal_approx(0.0, 0.001)


func test_refill_resets_base_charges_and_cooldowns_without_touching_ult() -> void:
	var a := _ability(5.0, 3)
	var ult := _ability(0.0, 1, true, 7)
	var state := AbilityState.new([a, ult])
	state.try_activate(0)  # 3 -> 2, cooldown starts at 5.0
	state.add_ult(4.0)

	state.refill()

	assert_int(state.charges(0)).is_equal(3)
	assert_float(state.cooldown_left(0)).is_equal_approx(0.0, 0.001)
	assert_float(state.ult_points()).is_equal_approx(4.0, 0.001)


func test_ult_charges_over_time_and_caps_at_cost() -> void:
	var ult := _ability(0.0, 1, true, 7)
	var state := AbilityState.new([ult])
	state.ult_charge_rate = 0.45

	state.tick(10.0, true)
	assert_float(state.ult_points()).is_equal_approx(4.5, 0.001)

	state.tick(10.0, true)  # would be 9.0, capped at ult_cost = 7
	assert_float(state.ult_points()).is_equal_approx(7.0, 0.001)


func test_try_activate_ult_requires_full_points_and_resets_on_use() -> void:
	var ult := _ability(0.0, 1, true, 7)
	var state := AbilityState.new([ult])

	assert_bool(state.can_activate(0)).is_false()
	assert_bool(state.try_activate(0)).is_false()

	state.add_ult(7.0)
	assert_bool(state.can_activate(0)).is_true()
	assert_bool(state.try_activate(0)).is_true()
	assert_float(state.ult_points()).is_equal_approx(0.0, 0.001)


func test_add_ult_caps_at_ult_cost() -> void:
	var ult := _ability(0.0, 1, true, 7)
	var state := AbilityState.new([ult])
	state.add_ult(3.0)
	assert_float(state.ult_points()).is_equal_approx(3.0, 0.001)
	state.add_ult(100.0)
	assert_float(state.ult_points()).is_equal_approx(7.0, 0.001)


func test_can_activate_and_try_activate_false_for_bad_index() -> void:
	var a := _ability(8.0, 1)
	var state := AbilityState.new([a])
	assert_bool(state.can_activate(5)).is_false()
	assert_bool(state.try_activate(-1)).is_false()


func test_to_dict_apply_dict_round_trip() -> void:
	var a := _ability(5.0, 3)
	var ult := _ability(0.0, 1, true, 7)
	var state := AbilityState.new([a, ult])
	state.try_activate(0)  # 3 -> 2, cooldown starts at 5.0
	state.tick(2.0, true)  # cooldown -> 3.0
	state.add_ult(4.0)

	var d := state.to_dict()
	var restored := AbilityState.new([_ability(5.0, 3), _ability(0.0, 1, true, 7)])
	restored.apply_dict(d)

	assert_int(restored.charges(0)).is_equal(state.charges(0))
	assert_float(restored.cooldown_left(0)).is_equal_approx(state.cooldown_left(0), 0.001)
	assert_float(restored.ult_points()).is_equal_approx(state.ult_points(), 0.001)


# ==========================================================================
# Économie d'ultime (§3.4, docs/research/10_ammo_kits_input.md, AGT-02) --
# `add_ult` reste générique (AbilityState est PUR, elle ne connaît ni dégâts
# ni kills) ; ces tests exercent les constantes RÉELLEMENT utilisées par
# GameWorld.gd (`ULT_DAMAGE_RATE`, `ULT_KILL_POINTS`, `ULT_OBJECTIVE_POINTS`)
# pour verrouiller le résultat chiffré de l'acceptance : « 100 dégâts + 1 kill
# = 2 pts. Coût 8 atteint en ≈ 3 à 4 kills. Litige : +1 à la pose ou au
# désamorçage. »
# ==========================================================================

func test_100_damage_plus_one_kill_grants_2_ult_points() -> void:
	var ult := _ability(0.0, 1, true, 8)
	var state := AbilityState.new([ult])
	state.add_ult(100.0 * GameWorld.ULT_DAMAGE_RATE)  # 100 dégâts : 1.0 pt
	state.add_ult(GameWorld.ULT_KILL_POINTS)  # + le kill lui-même : 1.0 pt
	assert_float(state.ult_points()).is_equal_approx(2.0, 0.0001)


func test_ult_cost_8_reached_after_about_3_to_4_kills() -> void:
	var ult := _ability(0.0, 1, true, 8)
	var state := AbilityState.new([ult])
	# 3 kills à 100 dégâts chacun : 3 x 2.0 = 6.0 pts, pas encore assez pour un
	# coût de 8 (voir §3.4 : « un ultime tous les 3 à 4 kills »).
	for i in 3:
		state.add_ult(100.0 * GameWorld.ULT_DAMAGE_RATE)
		state.add_ult(GameWorld.ULT_KILL_POINTS)
	assert_bool(state.can_activate(0)).is_false()

	# Le 4e kill atteint (et plafonne à) le coût de 8.
	state.add_ult(100.0 * GameWorld.ULT_DAMAGE_RATE)
	state.add_ult(GameWorld.ULT_KILL_POINTS)
	assert_bool(state.can_activate(0)).is_true()
	assert_float(state.ult_points()).is_equal_approx(8.0, 0.0001)


func test_litige_plant_or_defuse_grants_one_objective_point() -> void:
	var ult := _ability(0.0, 1, true, 8)
	var state := AbilityState.new([ult])
	state.add_ult(GameWorld.ULT_OBJECTIVE_POINTS)
	assert_float(state.ult_points()).is_equal_approx(1.0, 0.0001)


## §3.4 (AGT-02) : `AbilityController._sync_ult_charge_rate` coupe
## `ult_charge_rate` à ZÉRO en mode à manches (Litige/Duel-Duo). Verrouille ici
## le comportement PUR dont elle dépend : un taux nul, même "actif" (phase
## LIVE, joueur vivant), n'ajoute plus aucun point en continu -- seul le bonus
## fixe pose/désamorçage (tests ci-dessous) fait progresser l'ultime en Litige.
func test_zero_ult_charge_rate_adds_nothing_over_time() -> void:
	var ult := _ability(0.0, 1, true, 8)
	var state := AbilityState.new([ult])
	state.ult_charge_rate = 0.0

	state.tick(20.0, true)

	assert_float(state.ult_points()).is_equal_approx(0.0, 0.0001)


# ==========================================================================
# Câblage RÉEL pose/désamorçage (§3.4, AGT-02, 2e passage -- vague 30
# refusée) : `test_litige_plant_or_defuse_grants_one_objective_point` ci-dessus
# verrouille le CHIFFRE mais appelle `add_ult` directement (tautologique) --
# il ne dit rien sur le CÂBLAGE. Les deux tests suivants exercent
# SnDMode._do_plant/_do_defuse eux-mêmes (les vraies méthodes de production,
## déclenchées par une pose/un désamorçage réel via `_server_tick_bomb`) et
## vérifient qu'ils relaient bien vers GameWorld.charge_ult_for_objective.
## Double minimal du nœud "match" (GameWorld) -- même patron que `_FakeWorld`
## de tests/agents/test_round_props_cleanup.gd et
## tests/modes/test_snd_disconnect.gd : `players_root` pointe vers un enfant
## "Players" VIDE (RoundMode._player_node ne trouve personne, comme un
## GameWorld réel avant tout spawn -- sans lui `_do_plant` planterait sur
## `world.get_node(world.players_root)`), et `charge_ult_for_objective`
## enregistre chaque appel au lieu d'agir pour de vrai sur un AbilityState.
# ==========================================================================

class _FakeUltWorld extends Node3D:
	var players_root: NodePath = ^"Players"
	var objective_calls: Array = []
	func charge_ult_for_objective(player_id: int) -> void:
		objective_calls.append(player_id)


func _make_ult_world() -> _FakeUltWorld:
	var world := _FakeUltWorld.new()
	world.add_to_group("match")
	var players_node := Node3D.new()
	players_node.name = "Players"
	world.add_child(players_node)
	add_child(world)
	auto_free(world)
	return world


func _new_snd_mode() -> SnDMode:
	var mode := SnDMode.new()
	add_child(mode)
	auto_free(mode)
	return mode


func test_do_plant_charges_ult_for_the_bomb_carrier() -> void:
	var world := _make_ult_world()
	var mode := _new_snd_mode()
	var carrier_id := PlayerController.BOT_ID_START
	mode._bomb_carrier_id = carrier_id
	mode._bomb_state = SnDMode.BombState.CARRIED

	mode._do_plant()

	assert_array(world.objective_calls).append_failure_message(
		"_do_plant doit brancher GameWorld.charge_ult_for_objective (§3.4, AGT-02) pour le poseur"
	).is_equal([carrier_id])


func test_do_defuse_charges_ult_for_the_defuser_only() -> void:
	var world := _make_ult_world()
	var mode := _new_snd_mode()
	var defuser_id := PlayerController.BOT_ID_START + 1
	mode._bomb_state = SnDMode.BombState.PLANTED
	# Court-circuite le end_round() de _do_defuse (hors périmètre de ce test :
	# la fin de manche a déjà sa propre couverture ailleurs) sans empêcher
	# _charge_ult_for_objective, appelé AVANT dans _do_defuse.
	mode.winner = 0

	mode._do_defuse(defuser_id)

	assert_array(world.objective_calls).append_failure_message(
		"_do_defuse doit brancher GameWorld.charge_ult_for_objective (§3.4, AGT-02) pour le désamorceur"
	).is_equal([defuser_id])
