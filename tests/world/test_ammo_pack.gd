## test_ammo_pack.gd
## Spec GF-22 (docs/research/10_ammo_kits_input.md §2.4, « Cartouchière lâchée
## à la mort ») — critères d'acceptation du contrat :
##   1. Apparaît à la mort, reste 20 s, 16 au plus (la plus ancienne disparaît).
##   2. Ramassage serveur à <= 1,2 m.
##   3. +1 chargeur par arme (`mag_size`), plafonné à la réserve de la règle
##      courante.
##   4. Absente en Litige et en Duel (modes à manches).
## (Le 5e critère, « vérifiée en image », est une vérification visuelle
## manuelle — hors périmètre d'un test gdUnit4.)
##
## Trois groupes de tests :
##   A. AmmoPack.gd en isolation (construction directe/`spawn_local`, comme
##      tests/agents/test_roseau_kit.gd::_heal_zone) — détection de portée,
##      plafond de réserve, joueur mort ignoré, registre statique, durée de vie.
##   B. Weapon.server_add_reserve_mags appelé directement sur un joueur réel
##      (bot, autorité SERVEUR sans réseau réel — même style que
##      tests/networking/test_respawn_refill.gd).
##   C. Intégration GameWorld._on_player_died (apparition à la mort, absence en
##      mode à manches, plafond de 16, ramassage qui diffuse la disparition via
##      `GameWorld.server_despawn_ammo_pack`) — double `_TestGameWorld`, même
##      patron que tests/networking/test_respawn_refill.gd (fichier distinct :
##      ses classes internes ne sont pas exposées hors de ce fichier, donc
##      reconstruites ici à l'identique).
##
## Chaque groupe qui a besoin d'une réserve FINIE (règle "arena") ajoute un
## double minimal au groupe "game_mode" (`_ArenaModeDouble`, `respawns_
## immediately() -> true`) : sans lui, `Weapon._ammo_rule()` retombe sur
## `Inventory.RULE_INFINITE` (aucun mode dans l'arbre, cf. sa docstring), et le
## plafond de réserve ne serait alors jamais atteignable dans ce test.
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _next_offset_index := 0
var _next_uid_index := 1
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


func _next_uid() -> int:
	var u := _next_uid_index
	_next_uid_index += 1
	return u


## Scène factice (Node3D) pour recevoir les cartouchières posées par
## `AmmoPack.spawn_local`/`GameWorld._server_spawn_ammo_pack`
## (`get_tree().current_scene`) — même motif que
## tests/agents/test_roseau_kit.gd::_dummy_scene.
func _dummy_scene() -> Node3D:
	var s := Node3D.new()
	get_tree().root.add_child(s)
	auto_free(s)
	get_tree().current_scene = s
	return s


## Double minimal d'un mode d'arène (TDM/Hardpoint) : `respawns_immediately`
## renvoie vrai — force `Weapon._ammo_rule()` sur `Inventory.RULE_ARENA` (voir
## docstring de tête) et fait passer `GameWorld._on_player_died` par la
## branche « cartouchière » (groupes B/C).
class _ArenaModeDouble extends Node:
	func respawns_immediately() -> bool:
		return true


## Double minimal d'un mode à manches (Litige/Duel) : `respawns_immediately`
## renvoie faux — `GameWorld._on_player_died` doit alors rendre la main AVANT
## la cartouchière (groupe C).
class _RoundBasedModeDouble extends Node:
	func respawns_immediately() -> bool:
		return false


## Ajoute un `_ArenaModeDouble` au groupe "game_mode" de CETTE suite (Node) —
## réserve FINIE pour tout joueur créé ensuite via `_standalone_bot`.
func _use_arena_mode() -> void:
	var mode := _ArenaModeDouble.new()
	mode.add_to_group("game_mode")
	add_child(mode)
	auto_free(mode)


## Joueur RÉEL (autorité SERVEUR sans réseau réel), ajouté DIRECTEMENT à la
## suite — pour les groupes A/B, qui n'ont pas besoin d'un GameWorld. Même
## style que tests/agents/test_roseau_kit.gd::_bot_player.
func _standalone_bot(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	_next_offset_index += 1
	player.set("is_bot", true)
	player.position = pos
	player.set("spawn_point", pos)
	player.team = 0
	add_child(player)
	auto_free(player)
	return player


func _weapon_of(player: PlayerController) -> Weapon:
	return player.get_node("Weapon") as Weapon


func _health(player: PlayerController) -> Health:
	return player.get_node("Health") as Health


## Construit une cartouchière via le vrai chemin réseau (`spawn_local`,
## registre statique tenu à jour) plutôt que `AmmoPack.new()` nu — pour que
## les tests de portée/plafond exercent le MÊME chemin que la production.
func _pack(pos: Vector3) -> AmmoPack:
	var pack := AmmoPack.spawn_local(_next_uid(), pos, self)
	auto_free(pack)
	return pack


# ======================================================================
#  A. AmmoPack.gd en isolation.
# ======================================================================

func test_ammo_pack_grants_one_magazine_to_each_owned_weapon_within_range() -> void:
	_use_arena_mode()
	var o := _offset()
	var player := _standalone_bot(o)
	var weapon := _weapon_of(player)
	# Vide la réserve de chaque arme possédée (sinon déjà au plafond -> rien à accorder).
	for i in weapon._server_inv.slots.size():
		if weapon._server_inv.slots[i] != Inventory.EMPTY:
			weapon._server_inv.reserve[i] = 0
	var expected: Array = []
	for i in weapon._server_inv.slots.size():
		var id: int = weapon._server_inv.slots[i]
		if id == Inventory.EMPTY:
			expected.append(0)
			continue
		var c := WeaponDatabase.get_by_id(id)
		expected.append(mini(c.mag_size, c.arena_reserve_ammo))
	var pack := _pack(o)
	await get_tree().physics_frame
	await get_tree().physics_frame  # laisse l'Area3D détecter le recouvrement.

	pack._physics_process(0.0)

	assert_array(weapon._server_inv.reserve).append_failure_message(
		"la cartouchière doit ajouter un chargeur à la réserve de CHAQUE arme possédée (contrat GF-22)"
	).is_equal(expected)


func test_ammo_pack_does_not_grant_beyond_the_pickup_range() -> void:
	_use_arena_mode()
	var o := _offset()
	# 1.3 m > PICKUP_RANGE (1.2 m), mais < rayon de détection de l'Area3D :
	# le joueur doit être VU par la zone puis REFUSÉ par le contrôle de distance.
	var player := _standalone_bot(o + Vector3(1.3, 0, 0))
	var weapon := _weapon_of(player)
	for i in weapon._server_inv.slots.size():
		if weapon._server_inv.slots[i] != Inventory.EMPTY:
			weapon._server_inv.reserve[i] = 0
	var before: Array = weapon._server_inv.reserve.duplicate()
	var pack := _pack(o)
	await get_tree().physics_frame
	await get_tree().physics_frame

	pack._physics_process(0.0)

	assert_array(weapon._server_inv.reserve).append_failure_message(
		"au-delà de 1,2 m (contrat GF-22 : « ramassage serveur à <= 1,2 m »), rien ne doit être accordé"
	).is_equal(before)


func test_ammo_pack_caps_the_grant_at_the_current_rule_reserve() -> void:
	_use_arena_mode()
	var o := _offset()
	var player := _standalone_bot(o)
	var weapon := _weapon_of(player)
	# Une munition sous le plafond arène : un chargeur ENTIER dépasserait
	# largement le plafond, qui doit rester une limite dure.
	for i in weapon._server_inv.slots.size():
		var id: int = weapon._server_inv.slots[i]
		if id == Inventory.EMPTY:
			continue
		var c := WeaponDatabase.get_by_id(id)
		weapon._server_inv.reserve[i] = c.arena_reserve_ammo - 1
	var pack := _pack(o)
	await get_tree().physics_frame
	await get_tree().physics_frame

	pack._physics_process(0.0)

	for i in weapon._server_inv.slots.size():
		var id: int = weapon._server_inv.slots[i]
		if id == Inventory.EMPTY:
			continue
		var c := WeaponDatabase.get_by_id(id)
		assert_int(weapon._server_inv.reserve[i]).append_failure_message(
			"la réserve ne doit JAMAIS dépasser le plafond de la règle courante (contrat GF-22 : « plafonné »)"
		).is_equal(c.arena_reserve_ammo)


func test_ammo_pack_ignores_a_dead_player() -> void:
	_use_arena_mode()
	var o := _offset()
	var player := _standalone_bot(o)
	var weapon := _weapon_of(player)
	for i in weapon._server_inv.slots.size():
		if weapon._server_inv.slots[i] != Inventory.EMPTY:
			weapon._server_inv.reserve[i] = 0
	_health(player).is_dead = true
	var before: Array = weapon._server_inv.reserve.duplicate()
	var pack := _pack(o)
	await get_tree().physics_frame
	await get_tree().physics_frame

	pack._physics_process(0.0)

	assert_array(weapon._server_inv.reserve).append_failure_message(
		"un joueur mort ne doit jamais ramasser la cartouchière"
	).is_equal(before)


func test_ammo_pack_default_lifetime_is_twenty_seconds() -> void:
	var pack := AmmoPack.new()
	assert_float(pack.lifetime).append_failure_message(
		"contrat GF-22 : « reste 20 s »"
	).is_equal_approx(20.0, 0.001)
	pack.free()


func test_ammo_pack_default_mags_per_pickup_is_one() -> void:
	var pack := AmmoPack.new()
	assert_int(pack.mags_per_pickup).append_failure_message(
		"contrat GF-22 : « +1 chargeur par arme »"
	).is_equal(1)
	pack.free()


func test_ammo_pack_pickup_range_constant_matches_the_contract() -> void:
	assert_float(AmmoPack.PICKUP_RANGE).append_failure_message(
		"contrat GF-22 : « ramassage serveur à <= 1,2 m »"
	).is_equal_approx(1.2, 0.001)


func test_ammo_pack_active_count_and_oldest_uid_track_the_registry() -> void:
	var before := AmmoPack.active_count()
	var o := _offset()
	var first := _pack(o)
	var second := _pack(o + Vector3(5, 0, 0))

	assert_int(AmmoPack.active_count() - before).append_failure_message(
		"deux cartouchières supplémentaires doivent apparaître dans le registre statique"
	).is_equal(2)
	assert_int(AmmoPack.oldest_uid()).append_failure_message(
		"oldest_uid doit renvoyer la PREMIÈRE cartouchière encore vivante (ordre d'insertion, GF-22 : éviction de la plus ancienne)"
	).is_equal(first.uid)

	AmmoPack.despawn_local(first.uid)
	await get_tree().process_frame  # laisse le queue_free() différé s'exécuter.
	await get_tree().process_frame

	assert_int(AmmoPack.oldest_uid()).append_failure_message(
		"une fois la plus ancienne retirée, la suivante doit prendre sa place"
	).is_equal(second.uid)


func test_ammo_pack_frees_itself_after_its_lifetime_elapses() -> void:
	var o := _offset()
	var pack := AmmoPack.new()
	pack.uid = _next_uid()
	pack.lifetime = 0.05
	add_child(pack)
	pack.global_position = o
	auto_free(pack)  # filet de sécurité si la minuterie n'a pas encore agi.

	await await_millis(150)

	assert_bool(is_instance_valid(pack)).append_failure_message(
		"contrat GF-22 : la cartouchière doit disparaître après sa durée de vie (« reste 20 s »)"
	).is_false()


# ======================================================================
#  B. Weapon.server_add_reserve_mags — appel direct (sans AmmoPack).
# ======================================================================

func test_server_add_reserve_mags_adds_one_magazine_to_each_owned_weapon() -> void:
	_use_arena_mode()
	var o := _offset()
	var player := _standalone_bot(o)
	var weapon := _weapon_of(player)
	for i in weapon._server_inv.slots.size():
		if weapon._server_inv.slots[i] != Inventory.EMPTY:
			weapon._server_inv.reserve[i] = 0

	var changed := weapon.server_add_reserve_mags(1)

	assert_bool(changed).append_failure_message(
		"au moins une réserve était vide : le ramassage doit être signalé comme EFFECTIF"
	).is_true()
	for i in weapon._server_inv.slots.size():
		var id: int = weapon._server_inv.slots[i]
		if id == Inventory.EMPTY:
			continue
		var c := WeaponDatabase.get_by_id(id)
		assert_int(weapon._server_inv.reserve[i]).append_failure_message(
			"+1 chargeur (mag_size) attendu sur chaque arme possédée (contrat GF-22)"
		).is_equal(mini(c.mag_size, c.arena_reserve_ammo))


func test_server_add_reserve_mags_caps_at_the_current_rule_reserve() -> void:
	_use_arena_mode()
	var o := _offset()
	var player := _standalone_bot(o)
	var weapon := _weapon_of(player)
	for i in weapon._server_inv.slots.size():
		var id: int = weapon._server_inv.slots[i]
		if id == Inventory.EMPTY:
			continue
		var c := WeaponDatabase.get_by_id(id)
		weapon._server_inv.reserve[i] = c.arena_reserve_ammo - 1

	weapon.server_add_reserve_mags(1)

	for i in weapon._server_inv.slots.size():
		var id: int = weapon._server_inv.slots[i]
		if id == Inventory.EMPTY:
			continue
		var c := WeaponDatabase.get_by_id(id)
		assert_int(weapon._server_inv.reserve[i]).append_failure_message(
			"la réserve ne doit jamais dépasser le plafond de la règle courante (contrat GF-22)"
		).is_equal(c.arena_reserve_ammo)


func test_server_add_reserve_mags_returns_false_when_every_reserve_is_already_full() -> void:
	_use_arena_mode()
	var o := _offset()
	var player := _standalone_bot(o)
	var weapon := _weapon_of(player)
	# Le loadout par défaut spawn déjà à pleine réserve (règle arène, voir
	# Weapon._ready -> set_loadout) : rien à ajouter.

	var changed := weapon.server_add_reserve_mags(1)

	assert_bool(changed).append_failure_message(
		"toutes les réserves déjà pleines : aucun changement, donc AUCUN ramassage effectif (§2.4 : « si l'une de ses réserves n'est pas pleine »)"
	).is_false()


# ======================================================================
#  C. Intégration GameWorld._on_player_died (apparition à la mort, absence en
#     mode à manches, plafond de 16, ramassage diffusé).
# ======================================================================

## Court-circuite le `_ready()` réel de GameWorld (réseau/écran de sélection
## d'agent...) pour ne garder QUE ce dont `_on_player_died`/`_server_spawn_
## ammo_pack` ont besoin : l'autorité serveur sur ce nœud et le groupe "match"
## (lu par AmmoPack._notify_picked_up). Même motif que la classe privée
## homonyme de tests/networking/test_respawn_refill.gd (fichier distinct,
## reconstruite ici à l'identique — ses classes internes ne sont pas exposées
## hors de ce fichier).
class _TestGameWorld extends GameWorld:
	func _ready() -> void:
		set_multiplayer_authority(1)
		add_to_group("match")


func _new_world() -> GameWorld:
	var world := _TestGameWorld.new()
	add_child(world)
	auto_free(world)
	var players := Node3D.new()
	players.name = "Players"
	world.add_child(players)
	world.respawn_delay = 0.05  # court : boucle de test rapide.
	return world


## Joueur RÉEL, spawné en BOT dans les rangs du monde de test — même autorité
## serveur que l'hôte (PlayerController._enter_tree), même style que
## tests/networking/test_respawn_refill.gd::_bot_player.
func _world_bot(world: GameWorld, id: int, pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.set("is_bot", true)
	player.set("team", 0)
	player.position = pos
	player.set("spawn_point", pos)
	world.get_node(world.players_root).add_child(player)
	auto_free(player)
	return player


func _add_mode(world: GameWorld, mode: Node) -> void:
	mode.add_to_group("game_mode")
	world.add_child(mode)
	auto_free(mode)


func test_death_in_an_arena_mode_spawns_an_ammo_pack_at_the_death_position() -> void:
	_dummy_scene()
	var world := _new_world()
	_add_mode(world, _ArenaModeDouble.new())
	var o := _offset()
	var player := _world_bot(world, 9301, o)
	var before := AmmoPack.active_count()

	world._on_player_died(0, player)

	assert_int(AmmoPack.active_count() - before).append_failure_message(
		"un mode d'arène (TDM/Hardpoint) doit faire apparaître une cartouchière à la mort (contrat GF-22)"
	).is_equal(1)
	var pack := AmmoPack.find(AmmoPack.oldest_uid())
	assert_object(pack).is_not_null()
	assert_float(pack.global_position.distance_to(o + Vector3(0, 0.3, 0))).append_failure_message(
		"la cartouchière doit apparaître à la position DE LA MORT, +0,3 m (§2.4), pas à la position de respawn"
	).is_less(0.05)

	await await_millis(int(world.respawn_delay * 1000.0) + 150)  # draine le respawn différé restant.


func test_death_with_no_game_mode_at_all_spawns_an_ammo_pack_too() -> void:
	# Aucun nœud "game_mode" (ex. entraînement) : `_on_player_died` ne doit PAS
	# retomber dans la branche « mode à manches » (elle exige `mode != null`).
	_dummy_scene()
	var world := _new_world()
	var o := _offset()
	var player := _world_bot(world, 9302, o)
	var before := AmmoPack.active_count()

	world._on_player_died(0, player)

	assert_int(AmmoPack.active_count() - before).append_failure_message(
		"sans mode de jeu (entraînement), la cartouchière doit quand même apparaître"
	).is_equal(1)

	await await_millis(int(world.respawn_delay * 1000.0) + 150)


func test_death_in_a_round_based_mode_never_spawns_an_ammo_pack() -> void:
	_dummy_scene()
	var world := _new_world()
	_add_mode(world, _RoundBasedModeDouble.new())
	var o := _offset()
	var player := _world_bot(world, 9303, o)
	var before := AmmoPack.active_count()

	world._on_player_died(0, player)

	assert_int(AmmoPack.active_count()).append_failure_message(
		"contrat GF-22 : « absente en Litige et en Duel » (modes à manches, respawns_immediately() == false)"
	).is_equal(before)

	await await_millis(int(world.respawn_delay * 1000.0) + 150)


func test_ammo_pack_count_is_capped_at_sixteen_and_evicts_the_oldest() -> void:
	_dummy_scene()
	var world := _new_world()
	var before := AmmoPack.active_count()
	var o := _offset()
	var first_uid := -1

	for i in (GameWorld.AMMO_PACK_MAX + 1):
		world._server_spawn_ammo_pack(o + Vector3(float(i) * 4.0, 0, 0))
		if i == 0:
			first_uid = AmmoPack.oldest_uid()
	await get_tree().process_frame  # laisse le despawn différé (éviction) s'exécuter.
	await get_tree().process_frame

	assert_int(AmmoPack.active_count() - before).append_failure_message(
		"contrat GF-22 : « 16 au plus »"
	).is_equal(GameWorld.AMMO_PACK_MAX)
	assert_object(AmmoPack.find(first_uid)).append_failure_message(
		"« la plus ancienne disparaît » : la toute première posée doit avoir été évincée"
	).is_null()


func test_ammo_pack_pickup_despawns_it_for_everyone_via_the_game_world() -> void:
	_dummy_scene()
	var world := _new_world()
	_add_mode(world, _ArenaModeDouble.new())
	var o := _offset()
	var victim := _world_bot(world, 9304, o)
	_health(victim).is_dead = true  # simule la mort déjà actée par Health.gd.

	world._on_player_died(0, victim)
	var uid := AmmoPack.oldest_uid()
	var pack := AmmoPack.find(uid)
	assert_object(pack).is_not_null()

	var picker := _world_bot(world, 9305, o)
	var weapon := _weapon_of(picker)
	for i in weapon._server_inv.slots.size():
		if weapon._server_inv.slots[i] != Inventory.EMPTY:
			weapon._server_inv.reserve[i] = 0
	await get_tree().physics_frame
	await get_tree().physics_frame  # laisse l'Area3D détecter le recouvrement.

	pack._physics_process(0.0)
	await get_tree().process_frame  # laisse le despawn diffusé (queue_free différé) s'exécuter.
	await get_tree().process_frame

	assert_object(AmmoPack.find(uid)).append_failure_message(
		"un ramassage effectif doit faire disparaître la cartouchière POUR TOUT LE MONDE, via GameWorld.server_despawn_ammo_pack"
	).is_null()

	await await_millis(int(world.respawn_delay * 1000.0) + 150)
