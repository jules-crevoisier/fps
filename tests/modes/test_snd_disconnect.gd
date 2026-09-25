## test_snd_disconnect.gd
## Spec (BUG-10, docs/audit/bugs.md, tasks/backlog.yaml) : en Recherche &
## Destruction, une déconnexion en cours de manche laissait la bombe dans un
## état incohérent, sur trois volets (`SnDMode.gd:186-204,220-227,252-260,
## 346-357` avant ce correctif) :
##   1. le PORTEUR se déconnecte en LIVE -> son nœud disparaît de `_players()`
##      mais `_bomb_carrier_id`/`_bomb_state` (CARRIED) restaient inchangés :
##      la bombe restait "portée" par un id fantôme, plus jamais ramassable ni
##      posable. Le correctif la fait tomber DROPPED à sa DERNIÈRE position
##      connue (`_bomb_carrier_last_pos`, tenue à jour à chaque tick tant que
##      le porteur existe) ;
##   2. aucun attaquant encore présent au moment de `_assign_carrier` (spawn
##      asynchrone après connexion), OU le porteur choisi se déconnecte
##      PENDANT la phase d'achat (la bombe n'est tickée qu'en LIVE : rien ne
##      l'aurait détecté avant) -> le correctif réattribue le porteur au début
##      du LIVE (`_on_live_start`, nouveau hook de `RoundMode`) si celui en
##      place n'est toujours pas un joueur valide ;
##   3. un défenseur en train de désamorcer se déconnecte -> sa progression
##      restait pour toujours dans `_defuse_progress`, et `_broadcast_bomb`
##      fait le MAX de TOUTES les valeurs du dictionnaire : la barre de
##      désamorçage restait affichée à tous après son départ ("progression
##      fantôme"). Le correctif purge les entrées des ids absents à chaque
##      tick (`_purge_absent_defuse_progress`).
##
## Technique : SnDMode instancié et piloté par appel DIRECT de ses méthodes
## (`_on_new_round`, `_on_live_start`, `_server_tick_bomb`...), jamais son
## `_ready()`/le moteur livrés à eux-mêmes — même choix que tests/modes/
## test_duel_stalemate.gd et tests/ai/test_bot_goals.gd. Joueurs factices
## minimaux (Node3D + `team`, comme le `_FakePlayer` de ces deux fichiers) pour
## peupler `RoundMode._players()` sans scène de joueur réelle. Une
## "déconnexion" est simulée par `free()` IMMÉDIAT (pas `queue_free`, différé
## en fin de frame) du nœud joueur : `_players()` ne doit plus le voir dès le
## tick suivant, comme un vrai `GameWorld._on_player_disconnected`.
extends GdUnitTestSuite


## Double minimal du nœud "match" (GameWorld) : seul `players_root` est lu par
## RoundMode._players()/_player_node (voir leur doc d'en-tête).
class _FakeWorld extends Node3D:
	var players_root: NodePath = ^"Players"


## Joueur factice minimal : un `team` (lu par `int(child.get("team"))`, comme
## un vrai PlayerController) — `global_position` vient de Node3D.
class _FakePlayer extends Node3D:
	var team: int = 0


func _make_world() -> Node3D:
	var world := _FakeWorld.new()
	world.add_to_group("match")
	var players_node := Node3D.new()
	players_node.name = "Players"
	world.add_child(players_node)
	add_child(world)
	auto_free(world)
	return world


## Ajoute un joueur factice de `team`, à `pos`, sous `world`. Renvoie son nœud
## (pour le "déconnecter" plus tard avec `.free()`).
func _add_player(world: Node3D, id: int, team: int, pos: Vector3) -> _FakePlayer:
	var player := _FakePlayer.new()
	player.name = str(id)
	player.team = team
	world.get_node("Players").add_child(player)
	auto_free(player)
	player.global_position = pos
	return player


func _new_mode() -> SnDMode:
	var mode := SnDMode.new()
	add_child(mode)
	auto_free(mode)
	return mode


# ======================================================================
#  Volet 1 : le porteur disparaît en LIVE -> bombe DROPPED à sa DERNIÈRE
#  position connue.
# ======================================================================
func test_carrier_disconnecting_mid_live_drops_the_bomb_at_its_last_known_position() -> void:
	var world := _make_world()
	var carrier := _add_player(world, 201, 0, Vector3(5, 0, 3))
	var mode := _new_mode()
	mode._bomb_carrier_id = 201
	mode._bomb_state = SnDMode.BombState.CARRIED

	# Un tick pendant que le porteur existe encore : la bombe reste portée et
	# sa dernière position connue est bien enregistrée.
	mode._server_tick_bomb(0.016)
	assert_int(mode._bomb_state).append_failure_message(
		"préalable du test : la bombe doit rester CARRIED tant que le porteur existe"
	).is_equal(SnDMode.BombState.CARRIED)

	carrier.free()  # déconnexion : le nœud disparaît immédiatement de _players().
	mode._server_tick_bomb(0.016)

	assert_int(mode._bomb_state).append_failure_message(
		"BUG-10 : le porteur disparu doit faire tomber la bombe (DROPPED)"
	).is_equal(SnDMode.BombState.DROPPED)
	assert_int(mode._bomb_carrier_id).append_failure_message(
		"plus aucun porteur une fois la bombe tombée"
	).is_equal(-1)
	assert_vector(mode._bomb_drop_pos).append_failure_message(
		"la bombe doit tomber à la DERNIÈRE position connue du porteur, pas à l'origine"
	).is_equal_approx(Vector3(5, 0, 3), Vector3.ONE * 0.001)


func test_bomb_dropped_by_a_disconnected_carrier_stays_dropped_and_can_still_be_picked_up() -> void:
	var world := _make_world()
	var carrier := _add_player(world, 202, 0, Vector3(-2, 0, 4))
	var mode := _new_mode()
	mode._bomb_carrier_id = 202
	mode._bomb_state = SnDMode.BombState.CARRIED
	mode._server_tick_bomb(0.016)  # enregistre la position avant la déconnexion.

	carrier.free()
	mode._server_tick_bomb(0.016)

	# Un autre attaquant qui marche dessus la ramasse normalement (non-régression).
	var teammate := _add_player(world, 203, 0, Vector3(-2, 0, 4))
	mode._server_tick_bomb(0.016)

	assert_int(mode._bomb_state).append_failure_message(
		"une bombe DROPPED doit rester ramassable normalement après la déconnexion du porteur précédent"
	).is_equal(SnDMode.BombState.CARRIED)
	assert_int(mode._bomb_carrier_id).is_equal(203)
	assert_object(teammate).is_not_null()  # utilisé plus haut : évite un avertissement "inutilisé".


# ======================================================================
#  Volet 2 : porteur attribué au début du LIVE si absent au début de manche.
# ======================================================================
func test_on_live_start_assigns_a_carrier_when_none_was_found_because_attackers_had_not_finished_spawning() -> void:
	var mode := _new_mode()
	mode._on_new_round()  # aucun attaquant encore spawné : `_assign_carrier` ne trouve personne.

	assert_int(mode._bomb_carrier_id).append_failure_message(
		"préalable du test : aucun porteur tant qu'aucun attaquant n'est présent"
	).is_equal(-1)

	var world := _make_world()
	_add_player(world, 301, mode.attacking_team(), Vector3.ZERO)  # l'attaquant finit par apparaître.

	mode._on_live_start()

	assert_int(mode._bomb_carrier_id).append_failure_message(
		"BUG-10 : le porteur doit être réattribué au début du LIVE si aucun n'a pu l'être en début de manche"
	).is_equal(301)
	assert_int(mode._bomb_state).is_equal(SnDMode.BombState.CARRIED)


func test_on_live_start_reassigns_carrier_when_the_previously_chosen_one_disconnected_during_buy() -> void:
	var world := _make_world()
	_add_player(world, 401, 0, Vector3.ZERO)
	_add_player(world, 402, 0, Vector3.ZERO)
	var mode := _new_mode()
	mode._bomb_carrier_id = 401  # attribution initiale (début de manche, phase d'achat).
	mode._bomb_state = SnDMode.BombState.CARRIED

	world.get_node("Players").get_node("401").free()  # déconnexion PENDANT les achats.

	mode._on_live_start()

	assert_int(mode._bomb_carrier_id).append_failure_message(
		"BUG-10 : un porteur déconnecté pendant les achats doit être réattribué au début du live"
	).is_equal(402)
	assert_int(mode._bomb_state).is_equal(SnDMode.BombState.CARRIED)


func test_on_live_start_does_not_reassign_a_carrier_that_is_still_present() -> void:
	var world := _make_world()
	_add_player(world, 501, 0, Vector3.ZERO)
	_add_player(world, 502, 0, Vector3.ZERO)
	var mode := _new_mode()
	mode._bomb_carrier_id = 501
	mode._bomb_state = SnDMode.BombState.CARRIED

	mode._on_live_start()

	assert_int(mode._bomb_carrier_id).append_failure_message(
		"non-régression : un porteur encore présent ne doit pas être changé au début du live"
	).is_equal(501)


# ======================================================================
#  Volet 3 : entrées de désamorçage des joueurs absents purgées (barre
#  fantôme).
# ======================================================================
func test_defuse_progress_of_a_disconnected_defender_is_purged() -> void:
	var world := _make_world()
	_add_player(world, 601, 1, Vector3.ZERO)  # défenseur (équipe != attaquants = équipe 0).
	var mode := _new_mode()
	mode._bomb_state = SnDMode.BombState.PLANTED
	mode._defuse_progress[601] = SnDMode.DEFUSE_TIME * 0.5  # désamorçage bien engagé.

	world.get_node("Players").get_node("601").free()  # déconnexion en pleine action.
	mode._server_tick_bomb(0.016)

	assert_bool(mode._defuse_progress.has(601)).append_failure_message(
		"BUG-10 : l'entrée de désamorçage d'un défenseur déconnecté doit être purgée (barre fantôme sinon)"
	).is_false()


func test_defuse_progress_of_a_still_connected_defender_is_not_purged() -> void:
	var world := _make_world()
	_add_player(world, 602, 1, Vector3.ZERO)
	var mode := _new_mode()
	mode._bomb_state = SnDMode.BombState.PLANTED
	mode._defuse_progress[602] = SnDMode.DEFUSE_TIME * 0.5

	mode._server_tick_bomb(0.016)

	assert_bool(mode._defuse_progress.has(602)).append_failure_message(
		"non-régression : la progression d'un défenseur toujours présent ne doit pas être purgée"
	).is_true()
