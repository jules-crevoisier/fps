## test_round_props_cleanup.gd
## Spec BUG-03 (docs/audit/bugs.md) : « Murs, fumées, tremplins, pièges et
## marqueurs d'une manche survivent dans la suivante » — rien ne nettoyait les
## objets posés par AbilityController (AbilityController.gd:227-477, avant ce
## correctif) entre deux manches. Couvre les quatre volets du critère
## d'acceptation :
##   1. mur/fumée/tremplin/piège/marqueur rejoignent le groupe "round_props"
##      dès leur pose (AbilityController._spawn_*/net_show_markers), et un
##      nettoyage par ce groupe les fait bien disparaître ;
##   2. RoundMode._enter_buy_phase() (passage en phase d'achat, à CHAQUE
##      nouvelle manche) et reset_match() (revanche) déclenchent ce nettoyage
##      via GameWorld ;
##   3. AbilityState.refill() (BUG-04) est bien appelée en délégant à
##      AbilityController.server_refill(), qui pousse la correction au
##      propriétaire ;
##   4. _server_activate resynchronise le propriétaire (_push_state) sur
##      CHAQUE refus (BUG-05 : 5 retours anticipés en étaient dépourvus), et le
##      tick d'ultime/charges est gelé mort ou hors phase LIVE (BUG-04/BUG-03).
##
## Technique : instance RÉELLE de scenes/player/player.tscn en BOT (autorité
## SERVEUR sans réseau réel, même méthode que tests/player/test_respawn_state_
## reset.gd et tests/agents/test_ability_rays.gd) pour AbilityController ;
## instance RÉELLE de RoundMode (comme tests/modes/test_game_mode_tiebreak.gd
## instancie GameMode) pilotée par appel DIRECT de ses méthodes (jamais
## `_ready()`/l'engin livré à lui-même) pour éviter tout aléa de `call_deferred`.
## GameWorld n'est PAS instancié ici : son `_ready()` appelle `NetworkManager.
## host()` (liaison RÉELLE d'un port ENet), risque de flakiness/concurrence
## qu'aucun test gdUnit4 du dépôt ne prend (GameWorld n'est testé qu'au travers
## de fonctions pures, ex. tests/networking/test_spawn_role.gd) ; on le
## remplace donc par un double minimal (`_FakeWorld`) exposant juste les
## méthodes que RoundMode appelle par `has_method(...)`.
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _next_offset_index := 0
var _had_prev_scene := false
var _prev_current_scene: Node


## Double minimal du nœud "game_mode" : abilities_enabled/round_phase lus par
## AbilityController via `Object.get()` (mêmes noms de propriété que GameMode/
## RoundMode réels).
class _FakeMode extends Node:
	var abilities_enabled: bool = true
	var round_phase: int = -1  # -1 = "cette clé n'existe pas côté RoundMode réel" par défaut


## Double minimal du nœud "match" (GameWorld) : ne fait que compter les appels
## que RoundMode._clear_round_props()/_respawn_all_for_round() lui adressent.
class _FakeWorld extends Node:
	var clear_round_props_calls := 0
	func clear_round_props() -> void:
		clear_round_props_calls += 1


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


## Scène factice (Node3D) pour recevoir les objets posés par AbilityController
## (`get_tree().current_scene`, voir AbilityController._spawn_barrier etc.).
## SceneTree.set_current_scene refuse tout nœud dont le parent n'est pas la
## racine (`scene/main/scene_tree.cpp`) : on l'ajoute donc directement sous
## `get_tree().root`, pas sous la suite de test elle-même.
func _dummy_scene() -> Node3D:
	var s := Node3D.new()
	get_tree().root.add_child(s)
	auto_free(s)
	get_tree().current_scene = s
	return s


## Instance réelle du joueur, spawnée comme un BOT (autorité SERVEUR, voir
## PlayerController._enter_tree) : _server_state ET _owner_state sont tous les
## deux construits (un process de test headless est déjà "le serveur",
## unique_id 1 -- is_multiplayer_authority() est donc vrai partout, comme pour
## un vrai bot/hôte).
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


func _owner_id(player: PlayerController) -> int:
	return str(player.name).to_int()


## Simule une prédiction optimiste erronée côté propriétaire (charge déjà
## décomptée localement) : sert à vérifier qu'un refus la corrige bien.
func _desync_owner(ctrl: AbilityController) -> void:
	ctrl._owner_state.try_activate(0)


# ============================================================ round_props : pose

func test_spawn_barrier_joins_round_props() -> void:
	var scene := _dummy_scene()
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)

	ctrl._spawn_barrier(player.position, Vector3.FORWARD, Vector3(2, 2, 0.2), 20.0, Color.WHITE)

	var wall := scene.get_child(scene.get_child_count() - 1)
	assert_bool(wall.is_in_group("round_props")).append_failure_message(
		"un mur posé (WallAbility) doit rejoindre round_props, sinon il survit à la manche suivante"
	).is_true()


func test_spawn_smoke_joins_round_props() -> void:
	var scene := _dummy_scene()
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)

	ctrl._spawn_smoke(player.position + Vector3(5, 0, 0), 2.5, 20.0, Color.WHITE)

	var smoke := scene.get_child(scene.get_child_count() - 1)
	assert_bool(smoke.is_in_group("round_props")).append_failure_message(
		"une fumée posée (SmokeAbility) doit rejoindre round_props"
	).is_true()


func test_spawn_jump_pad_joins_round_props() -> void:
	var scene := _dummy_scene()
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)

	ctrl._spawn_jump_pad(player.position + Vector3(10, 0, 0), 20.0, 12.0)

	var pad := scene.get_child(scene.get_child_count() - 1)
	assert_bool(pad.is_in_group("round_props")).append_failure_message(
		"un tremplin posé (JumpPadAbility) doit rejoindre round_props"
	).is_true()


func test_spawn_stun_trap_joins_round_props() -> void:
	var scene := _dummy_scene()
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)

	ctrl._spawn_stun_trap(player.position + Vector3(15, 0, 0), 0, 20.0, 2.0)

	var trap := scene.get_child(scene.get_child_count() - 1)
	assert_bool(trap.is_in_group("round_props")).append_failure_message(
		"un piège posé (StunTrapAbility) doit rejoindre round_props"
	).is_true()


func test_net_show_markers_joins_round_props() -> void:
	var scene := _dummy_scene()
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)

	ctrl.net_show_markers([player.position + Vector3(20, 0, 0)], 20.0)

	var marker := scene.get_child(scene.get_child_count() - 1)
	assert_bool(marker.is_in_group("round_props")).append_failure_message(
		"un marqueur de reveal doit rejoindre round_props"
	).is_true()


## Reproduit EXACTEMENT le nettoyage de GameWorld._clear_round_props (BUG-03) :
## prouve que les cinq types d'objets, une fois posés, disparaissent tous d'un
## seul passage par le groupe -- avant/après en DIFFÉRENTIEL pour rester
## indépendant de tout objet round_props laissé par un autre test du fichier.
func test_all_round_prop_types_are_found_and_removed_via_the_group() -> void:
	var scene := _dummy_scene()
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	var before := get_tree().get_nodes_in_group("round_props").size()

	ctrl._spawn_barrier(player.position, Vector3.FORWARD, Vector3(2, 2, 0.2), 20.0, Color.WHITE)
	ctrl._spawn_smoke(player.position + Vector3(5, 0, 0), 2.5, 20.0, Color.WHITE)
	ctrl._spawn_jump_pad(player.position + Vector3(10, 0, 0), 20.0, 12.0)
	ctrl._spawn_stun_trap(player.position + Vector3(15, 0, 0), 0, 20.0, 2.0)
	ctrl.net_show_markers([player.position + Vector3(20, 0, 0)], 20.0)

	var during := get_tree().get_nodes_in_group("round_props")
	assert_int(during.size() - before).append_failure_message(
		"les 5 types d'objets de capacités doivent tous être comptés dans round_props"
	).is_equal(5)

	for prop in during:
		if is_instance_valid(prop):
			prop.queue_free()
	await get_tree().process_frame

	assert_int(get_tree().get_nodes_in_group("round_props").size()).append_failure_message(
		"vider round_props doit faire disparaître les 5 objets posés"
	).is_equal(before)


# ================================================== RoundMode : quand nettoyer

func test_enter_buy_phase_clears_round_props_via_the_world() -> void:
	var world := _FakeWorld.new()
	world.add_to_group("match")
	add_child(world)
	auto_free(world)
	var mode := RoundMode.new()
	add_child(mode)
	auto_free(mode)

	var before := world.clear_round_props_calls
	mode._enter_buy_phase()

	assert_int(world.clear_round_props_calls).append_failure_message(
		"BUG-03 : RoundMode._enter_buy_phase() (chaque nouvelle manche, passage en achat) doit vider round_props via GameWorld"
	).is_greater(before)


func test_reset_match_clears_round_props_via_the_world() -> void:
	var world := _FakeWorld.new()
	world.add_to_group("match")
	add_child(world)
	auto_free(world)
	var mode := RoundMode.new()
	add_child(mode)
	auto_free(mode)

	var before := world.clear_round_props_calls
	mode.reset_match()

	assert_int(world.clear_round_props_calls).append_failure_message(
		"BUG-03 : reset_match() (revanche) doit aussi vider round_props"
	).is_greater(before)


# ======================================================== AbilityState.refill()

func test_server_refill_restores_charges_without_touching_ultimate() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame

	# Consomme une charge de la capacité C (index 0, toujours non-ultime — voir
	# AgentDatabase.SLOTS) et crédite des points d'ultime, comme une manche en
	# cours l'aurait fait, côté état AUTORITAIRE.
	ctrl._server_state.try_activate(0)
	ctrl._server_state.add_ult(3.0)
	var max_charges: int = ctrl.agent.abilities[0].charges
	assert_int(ctrl._server_state.charges(0)).append_failure_message(
		"préalable du test : une charge doit avoir été consommée"
	).is_less(max_charges)

	ctrl.server_refill()

	assert_int(ctrl._server_state.charges(0)).append_failure_message(
		"BUG-03/BUG-04 : server_refill() doit remettre les charges de base à fond au début de manche"
	).is_equal(max_charges)
	assert_float(ctrl._server_state.ult_points()).append_failure_message(
		"server_refill() ne doit PAS toucher aux points d'ultime accumulés"
	).is_equal_approx(3.0, 0.001)
	assert_int(ctrl._owner_state.charges(0)).append_failure_message(
		"server_refill() doit pousser la correction au propriétaire (copie prédictive), pas seulement à l'état autoritaire"
	).is_equal(max_charges)


# =============================================== _server_activate : resync sur refus

func test_server_activate_resyncs_owner_when_sender_is_not_the_owner() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	_desync_owner(ctrl)
	assert_int(ctrl._owner_state.charges(0)).append_failure_message(
		"préalable du test : la prédiction doit être désynchronisée avant le refus"
	).is_not_equal(ctrl._server_state.charges(0))

	ctrl._server_activate(999999, 0, Vector3.FORWARD)

	assert_int(ctrl._owner_state.charges(0)).append_failure_message(
		"BUG-05 : un refus (expéditeur usurpé) doit resynchroniser le vrai propriétaire, pas laisser sa prédiction fausse"
	).is_equal(ctrl._server_state.charges(0))


func test_server_activate_resyncs_owner_when_abilities_are_disabled() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	var mode := _FakeMode.new()
	mode.abilities_enabled = false
	mode.add_to_group("game_mode")
	add_child(mode)
	auto_free(mode)
	_desync_owner(ctrl)

	ctrl._server_activate(_owner_id(player), 0, Vector3.FORWARD)

	assert_int(ctrl._owner_state.charges(0)).append_failure_message(
		"BUG-05 : capacités désactivées (Duel/Duo) -> refus, mais resync quand même"
	).is_equal(ctrl._server_state.charges(0))


func test_server_activate_resyncs_owner_when_player_is_dead() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	var hp := player.get_node("Health") as Health
	hp.is_dead = true
	_desync_owner(ctrl)

	ctrl._server_activate(_owner_id(player), 0, Vector3.FORWARD)

	assert_int(ctrl._owner_state.charges(0)).append_failure_message(
		"BUG-05 : mort pendant l'appui -> sans ce resync la capacité restait \"en recharge\" jusqu'à 22 s"
	).is_equal(ctrl._server_state.charges(0))


func test_server_activate_resyncs_owner_on_invalid_aim_dir() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	_desync_owner(ctrl)

	ctrl._server_activate(_owner_id(player), 0, Vector3.ZERO)

	assert_int(ctrl._owner_state.charges(0)).append_failure_message(
		"BUG-05 : direction de visée invalide -> refus, mais resync quand même"
	).is_equal(ctrl._server_state.charges(0))


func test_server_activate_resyncs_owner_on_out_of_range_index() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	_desync_owner(ctrl)

	ctrl._server_activate(_owner_id(player), 99, Vector3.FORWARD)

	assert_int(ctrl._owner_state.charges(0)).append_failure_message(
		"BUG-05 : index de capacité hors bornes -> refus, mais resync quand même"
	).is_equal(ctrl._server_state.charges(0))


func test_server_activate_still_consumes_a_charge_and_syncs_owner_on_success() -> void:
	# Non-régression : les 5 refus corrigés ci-dessus ne doivent pas casser le
	# chemin d'activation RÉUSSIE (déjà resynchronisé avant ce correctif).
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	var max_charges: int = ctrl.agent.abilities[0].charges

	ctrl._server_activate(_owner_id(player), 0, Vector3.FORWARD)

	assert_int(ctrl._server_state.charges(0)).is_equal(max_charges - 1)
	assert_int(ctrl._owner_state.charges(0)).append_failure_message(
		"une activation réussie doit aussi synchroniser le propriétaire"
	).is_equal(max_charges - 1)


# ==================================================== tick d'ultime : gating (BUG-03/04)

func test_tick_active_true_by_default_when_alive_and_no_mode() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame

	assert_bool(ctrl._tick_active()).append_failure_message(
		"sans mode à manches (arène/training), l'ultime/les charges doivent continuer à avancer"
	).is_true()


func test_tick_active_false_when_player_is_dead() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	var hp := player.get_node("Health") as Health
	hp.is_dead = true

	assert_bool(ctrl._tick_active()).append_failure_message(
		"BUG-04 : un joueur mort ne doit plus charger son ultime ni régénérer ses charges"
	).is_false()


func test_tick_active_true_during_live_phase_of_a_round_mode() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	var mode := _FakeMode.new()
	mode.round_phase = RoundState.Phase.LIVE
	mode.add_to_group("game_mode")
	add_child(mode)
	auto_free(mode)

	assert_bool(ctrl._tick_active()).is_true()


func test_tick_active_false_outside_live_phase_of_a_round_mode() -> void:
	var player := _bot_player(_offset())
	var ctrl := _abilities(player)
	await get_tree().physics_frame
	var mode := _FakeMode.new()
	mode.add_to_group("game_mode")
	add_child(mode)
	auto_free(mode)

	mode.round_phase = RoundState.Phase.BUY
	assert_bool(ctrl._tick_active()).append_failure_message(
		"BUG-03 : phase d'ACHAT d'un mode à manches -> pas de charge d'ultime/de régénération"
	).is_false()

	mode.round_phase = RoundState.Phase.POST
	assert_bool(ctrl._tick_active()).append_failure_message(
		"BUG-03 : phase de RÉSULTAT (POST) d'un mode à manches -> pas de charge d'ultime/de régénération"
	).is_false()
