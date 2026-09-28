## test_primary_weapon_choice.gd
## Spec (contrat lead 2026-09-28, "LOADOUT SELECTION" point 5, réseau
## autoritaire serveur) : un client (Armurerie/écran de mort) demande à
## changer sa primaire via `GameWorld.request_primary_weapon` — hôte : appel
## direct (voir `_server_choose_primary`) ; client distant : RPC
## `_server_request_primary` (non testée directement ici, RPC réelle non
## exerçable en mono-process, MÊME limite documentée par tests/player/
## test_ping.gd pour `_server_request_ping`). Le serveur valide l'id
## (`Loadout.is_valid_primary_id`), borne la fréquence (au plus
## `PRIMARY_CHOICE_MAX_PER_WINDOW` par `PRIMARY_CHOICE_WINDOW_S`), et
## n'applique le choix qu'au PROCHAIN spawn/respawn — jamais mi-vie.
##
## Style des doubles : `_TestGameWorld` court-circuite `_ready()` (réseau/UI
## hors sujet), MÊME patron que tests/networking/test_respawn_refill.gd et
## tests/player/test_ping.gd.
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")


class _TestGameWorld extends GameWorld:
	func _ready() -> void:
		set_multiplayer_authority(1)
		add_to_group("match")


func _new_world() -> GameWorld:
	var world := _TestGameWorld.new()
	add_child(world)
	auto_free(world)
	return world


func _ravage_id() -> int:
	return WeaponDatabase.id_of(WeaponDatabase.get_by_name("Ravage"))


func _revolver_id() -> int:
	return WeaponDatabase.id_of(WeaponDatabase.get_by_name("Revolver"))


func _some_other_primary_id() -> int:
	# N'importe quelle primaire DIFFÉRENTE du Ravage, pour prouver un
	# changement réel (pas juste "le repli par défaut a été redemandé").
	var ids := Loadout.available_primary_ids()
	for id in ids:
		if id != _ravage_id():
			return id
	return _ravage_id()  # repli dégénéré (seul le Ravage existerait) : jamais le cas ici.


# ======================================================================
#  _server_choose_primary — validation + mémorisation
# ======================================================================

func test_server_choose_primary_stores_valid_choice_for_known_player() -> void:
	var world := _new_world()
	world.player_info = {1: {"name": "Hôte", "team": 0, "kills": 0, "deaths": 0, "is_bot": false}}
	var other := _some_other_primary_id()

	world._server_choose_primary(other, 1)

	assert_int(world._chosen_primary_id.get(1, -1)).is_equal(other)


func test_server_choose_primary_ignores_unknown_sender() -> void:
	var world := _new_world()
	world.player_info = {1: {"name": "Hôte", "team": 0, "kills": 0, "deaths": 0, "is_bot": false}}

	world._server_choose_primary(_some_other_primary_id(), 42)

	assert_bool(world._chosen_primary_id.has(42)).append_failure_message(
		"un id inconnu de player_info (déconnecté/pas encore spawné) ne doit jamais être mémorisé"
	).is_false()


func test_server_choose_primary_rejects_the_revolver_id() -> void:
	var world := _new_world()
	world.player_info = {1: {"name": "Hôte", "team": 0, "kills": 0, "deaths": 0, "is_bot": false}}

	world._server_choose_primary(_revolver_id(), 1)

	assert_bool(world._chosen_primary_id.has(1)).append_failure_message(
		"le Revolver n'est jamais une primaire valide, même transmis par un client modifié"
	).is_false()


func test_server_choose_primary_rejects_unknown_and_negative_ids() -> void:
	var world := _new_world()
	world.player_info = {1: {"name": "Hôte", "team": 0, "kills": 0, "deaths": 0, "is_bot": false}}

	world._server_choose_primary(9999, 1)
	world._server_choose_primary(-1, 1)

	assert_bool(world._chosen_primary_id.has(1)).is_false()


func test_server_choose_primary_enforces_the_rate_limit() -> void:
	var world := _new_world()
	world.player_info = {1: {"name": "Hôte", "team": 0, "kills": 0, "deaths": 0, "is_bot": false}}
	var ids := Loadout.available_primary_ids()
	assert_int(ids.size()).append_failure_message(
		"préalable du test : il faut au moins 2 primaires chargées pour distinguer la valeur retenue"
	).is_greater_equal(2)

	# PRIMARY_CHOICE_MAX_PER_WINDOW requêtes acceptées, la SUIVANTE ignorée —
	# chacune choisit une primaire DIFFÉRENTE pour repérer sans ambiguïté
	# celle qui a effectivement été retenue.
	var accepted_count: int = world.PRIMARY_CHOICE_MAX_PER_WINDOW
	var last_accepted := -1
	for i in accepted_count:
		var pid: int = ids[i % ids.size()]
		last_accepted = pid
		world._server_choose_primary(pid, 1)
	assert_int(world._chosen_primary_id.get(1, -1)).is_equal(last_accepted)

	var rejected_pid: int = ids[(accepted_count) % ids.size()]
	world._server_choose_primary(rejected_pid, 1)

	assert_int(world._chosen_primary_id.get(1, -1)).append_failure_message(
		"contrat : au plus %d changements de primaire par %.0f s" % [world.PRIMARY_CHOICE_MAX_PER_WINDOW, world.PRIMARY_CHOICE_WINDOW_S]
	).is_equal(last_accepted)


# ======================================================================
#  request_primary_weapon — branche 100 % hôte (MÊME limite que
#  test_ping.gd::test_request_ping_as_host_relays_directly_without_an_rpc :
#  une RPC réelle vers un second pair n'est pas exerçable en mono-process).
# ======================================================================

func test_request_primary_weapon_as_host_applies_directly_without_an_rpc() -> void:
	var world := _new_world()
	world.player_info = {1: {"name": "Hôte", "team": 0, "kills": 0, "deaths": 0, "is_bot": false}}
	var other := _some_other_primary_id()

	world.request_primary_weapon(other)

	assert_int(world._chosen_primary_id.get(1, -1)).is_equal(other)


# ======================================================================
#  Application AU RESPAWN SEULEMENT — jamais mi-vie (contrat point 5).
#  Joueur RÉEL (scène de production), MÊME patron que
#  tests/networking/test_respawn_refill.gd::_bot_player.
# ======================================================================

func _human_player(world: GameWorld, id: int, pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.set("is_bot", false)
	player.set("team", 0)
	player.position = pos
	player.set("spawn_point", pos)
	world.get_node(world.players_root).add_child(player)
	auto_free(player)
	return player


func _weapon_of(player: Node) -> Weapon:
	return player.get_node("Weapon") as Weapon


func test_changing_primary_mid_life_does_not_touch_the_current_loadout() -> void:
	var world := _new_world()
	var players := Node3D.new()
	players.name = "Players"
	world.add_child(players)
	world.respawn_delay = 0.05
	world.player_info = {9201: {"name": "Joueuse", "team": 0, "kills": 0, "deaths": 0, "is_bot": false}}
	var player := _human_player(world, 9201, Vector3.ZERO)
	var weapon := _weapon_of(player)
	var slots_before: Array = weapon._server_inv.slots.duplicate()

	world._server_choose_primary(_some_other_primary_id(), 9201)

	assert_array(weapon._server_inv.slots).append_failure_message(
		"changer de primaire ne doit RIEN changer à l'inventaire en cours -- seulement au PROCHAIN respawn"
	).is_equal(slots_before)


func test_chosen_primary_is_applied_at_the_next_respawn() -> void:
	var world := _new_world()
	var players := Node3D.new()
	players.name = "Players"
	world.add_child(players)
	world.respawn_delay = 0.05
	world.player_info = {9202: {"name": "Joueuse", "team": 0, "kills": 0, "deaths": 0, "is_bot": false}}
	var player := _human_player(world, 9202, Vector3.ZERO)
	var weapon := _weapon_of(player)
	var chosen := _some_other_primary_id()

	world._server_choose_primary(chosen, 9202)
	world._on_player_died(0, player)
	await await_millis(int(world.respawn_delay * 1000.0) + 150)

	assert_int(weapon._server_inv.slots[0]).append_failure_message(
		"le respawn doit appliquer la primaire choisie AVANT la mort"
	).is_equal(chosen)
	assert_int(weapon._server_inv.slots[1]).is_equal(_revolver_id())


func test_bot_respawn_picks_a_valid_random_primary_each_time() -> void:
	var world := _new_world()
	var players := Node3D.new()
	players.name = "Players"
	world.add_child(players)
	world.respawn_delay = 0.05
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = "9203"
	player.set("is_bot", true)
	player.set("team", 0)
	player.set("spawn_point", Vector3.ZERO)
	world.get_node(world.players_root).add_child(player)
	auto_free(player)
	var weapon := _weapon_of(player)

	world._on_player_died(0, player)
	await await_millis(int(world.respawn_delay * 1000.0) + 150)

	var available := Loadout.available_primary_ids()
	assert_bool(available.has(weapon._server_inv.slots[0])).append_failure_message(
		"un bot doit toujours respawn avec une primaire CONNUE, jamais un id forgé"
	).is_true()
	assert_int(weapon._server_inv.slots[1]).is_equal(_revolver_id())
