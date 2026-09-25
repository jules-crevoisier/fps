## test_respawn_refill.gd
## Spec GF-20 (docs/research/10_ammo_kits_input.md §2.1, §2.2) : « on tombe vite
## à court de munitions » venait d'un bug, pas d'un manque de réserve —
## `Weapon.server_refill_ammo()` existait déjà mais AUCUN appelant ne le
## déclenchait au respawn. En arène (Mêlée/Borne/entraînement), un joueur mort
## à 0/0 doit réapparaître avec son loadout PLEIN (chargeur ET réserve) —
## en hôte, en client distant et en bot, puisque les trois partagent la même
## logique serveur (`GameWorld._on_player_died`, seul fichier possédé ici avec
## ce test). Le Litige et le Duel (RoundMode.respawns_immediately() == false)
## rechargent DÉJÀ au round via leur propre `_after_round_respawn` (hors
## périmètre GF-20) et ne doivent PAS être touchés par ce correctif : ce
## fichier prouve qu'ils gardent leur inventaire inchangé quand `_on_player_died`
## rend la main avant même de programmer un respawn.
##
## Portée réseau (hôte/bot/client distant) : `Weapon.server_refill_ammo()` ne
## dépend QUE de `multiplayer.is_server()` et de l'inventaire AUTORITAIRE
## `_server_inv`, qui existe côté serveur pour CHAQUE joueur quel que soit son
## type (docstring d'en-tête de Weapon.gd : « une instance par joueur, sur ce
## nœud »). La différence hôte/bot vs client distant se joue uniquement DANS
## `server_refill_ammo()`/`_push_server_sync()` (appel direct vs RPC vers le
## propriétaire) — un fichier qui n'est PAS dans notre liste possédée. On
## prouve donc ici l'appel effectif de `server_refill_ammo()` depuis
## `_on_player_died` avec un joueur qui emprunte le chemin hôte/bot
## (`_teleport_player` : `has_method("server_respawn") and is_multiplayer_
## authority()`, la seule branche qu'un test mono-process headless peut
## exercer sans un second pair réel — voir tests/networking/server_join_smoke.gd
## pour la vérification inter-process) ; le comportement du client distant
## n'est PAS re-testé ici car il ne dépend d'aucune ligne de GameWorld.gd
## (même appel direct à `server_refill_ammo()`, juste une diffusion RPC en
## plus, entièrement interne à Weapon.gd).
##
## Style des doubles : sous-classe légère de GameWorld qui court-circuite son
## `_ready()` réel (réseau/UI de sélection d'agent — hors sujet ici), comme
## `_ClockedTDMMode extends TDMMode` dans tests/ai/test_bot_goals.gd. Joueur
## réel (`scenes/player/player.tscn`, spawné en BOT) comme
## tests/player/test_respawn_state_reset.gd::_bot_player — nécessaire ici
## car `Weapon._ready()` caste son parent en `PlayerController` : un simple
## `Node3D` factice laisserait `Weapon._server_inv` valide mais `player` à
## `null`, ce qui ferait s'effondrer `_push_server_sync()` sur
## `player.is_multiplayer_authority()`.
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _next_offset_index := 0


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


## Court-circuite le `_ready()` réel de GameWorld (réseau/écran de sélection
## d'agent, `Telemetry.start_session`, `Settings.load_all`...) pour ne garder
## QUE ce dont `_on_player_died` a besoin : l'autorité serveur sur ce nœud et
## le groupe "match" (lu par `Weapon._buy_enabled`/`_round_locked`, pas
## exercé ici mais gratuit). Les méthodes exercées par ce fichier
## (`_on_player_died`, `_record_kill`, `_record_recent_death`,
## `_get_spawn_position`, `_teleport_player`, `_mark_spawned`) restent
## CELLES, réelles et non modifiées, de GameWorld.
class _TestGameWorld extends GameWorld:
	func _ready() -> void:
		set_multiplayer_authority(1)
		add_to_group("match")


## Double minimal d'un mode à manches (SnD/Duel) : seule `respawns_immediately`
## est lue par `_on_player_died` (voir RoundMode.gd:185, partagée par
## SnDMode/DuelMode). Ajouté au groupe "game_mode", exactement comme le vrai
## mode l'est dans les scènes de jeu.
class _RoundBasedModeDouble extends Node:
	func respawns_immediately() -> bool:
		return false


## Double minimal d'un mode d'arène (TDM/Hardpoint) : `respawns_immediately`
## renvoie vrai, comme `GameMode.respawns_immediately()` (non surchargée par
## TDMMode/HardpointMode).
class _ArenaModeDouble extends Node:
	func respawns_immediately() -> bool:
		return true


func _new_world() -> GameWorld:
	var world := _TestGameWorld.new()
	add_child(world)
	auto_free(world)
	var players := Node3D.new()
	players.name = "Players"
	world.add_child(players)
	world.respawn_delay = 0.05  # court : boucle de test rapide, voir await_millis ci-dessous.
	return world


## Joueur RÉEL (scène de production), spawné en BOT — même autorité serveur
## que l'hôte (PlayerController._enter_tree : `authority_id := 1 if owner_id
## >= BOT_ID_START else owner_id`), donc le même chemin que `_teleport_player`
## emprunte pour l'hôte ET les bots (appel direct, pas de RPC).
func _bot_player(world: GameWorld, id: int, pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.set("is_bot", true)
	player.set("team", 0)
	player.position = pos
	player.set("spawn_point", pos)
	world.get_node(world.players_root).add_child(player)
	auto_free(player)
	return player


func _weapon_of(player: Node) -> Weapon:
	return player.get_node("Weapon") as Weapon


## Vide chargeur ET réserve de CHAQUE slot possédé (simule "à sec après 2-3
## vies", constat GF-20 §2.1) sur l'inventaire AUTORITAIRE serveur.
func _drain_ammo(weapon: Weapon) -> void:
	for i in weapon._server_inv.slots.size():
		if weapon._server_inv.slots[i] == Inventory.EMPTY:
			continue
		weapon._server_inv.mag[i] = 0
		weapon._server_inv.reserve[i] = 0


func _is_fully_drained(weapon: Weapon) -> bool:
	for i in weapon._server_inv.slots.size():
		if weapon._server_inv.slots[i] == Inventory.EMPTY:
			continue
		if weapon._server_inv.mag[i] != 0 or weapon._server_inv.reserve[i] != 0:
			return false
	return true


# ======================================================================
#  1. Arène (aucun mode explicite = entraînement/scène sans GameMode) :
#     un joueur mort à 0/0 réapparaît avec son loadout plein.
# ======================================================================

func test_respawn_with_no_mode_refills_empty_weapon_to_full_loadout() -> void:
	var world := _new_world()
	var player := _bot_player(world, 9101, _offset())
	var weapon := _weapon_of(player)
	var full_mag: Array = weapon._server_inv.mag.duplicate()
	var full_reserve: Array = weapon._server_inv.reserve.duplicate()

	_drain_ammo(weapon)
	assert_bool(_is_fully_drained(weapon)).append_failure_message(
		"préalable du test : le chargeur ET la réserve doivent être à 0 avant la mort"
	).is_true()

	world._on_player_died(0, player)
	await await_millis(int(world.respawn_delay * 1000.0) + 150)

	assert_array(weapon._server_inv.mag).append_failure_message(
		"le chargeur doit revenir au maximum de chaque arme possédée après le respawn"
	).is_equal(full_mag)
	assert_array(weapon._server_inv.reserve).append_failure_message(
		"la réserve doit revenir au maximum de chaque arme possédée après le respawn (GF-20 : plus de sec après 2-3 vies)"
	).is_equal(full_reserve)


# ======================================================================
#  2. Sonde « 3 vies de suite sans chargeur vide au spawn » (acceptance GF-20).
# ======================================================================

func test_three_consecutive_lives_never_spawn_with_an_empty_magazine() -> void:
	var world := _new_world()
	var player := _bot_player(world, 9102, _offset())
	var weapon := _weapon_of(player)
	var full_mag: Array = weapon._server_inv.mag.duplicate()
	var full_reserve: Array = weapon._server_inv.reserve.duplicate()

	for life in 3:
		_drain_ammo(weapon)
		world._on_player_died(0, player)
		await await_millis(int(world.respawn_delay * 1000.0) + 150)
		assert_array(weapon._server_inv.mag).append_failure_message(
			"vie %d/3 : chargeur vide au spawn (GF-20 non tenu sur une série de morts)" % (life + 1)
		).is_equal(full_mag)
		assert_array(weapon._server_inv.reserve).append_failure_message(
			"vie %d/3 : réserve vide au spawn" % (life + 1)
		).is_equal(full_reserve)


# ======================================================================
#  3. Mode d'arène EXPLICITE (TDM/Hardpoint, respawns_immediately() == true) :
#     même comportement que "sans mode" ci-dessus, nommé pour matcher le
#     contrat ("en Mêlée et en Borne").
# ======================================================================

func test_respawn_in_tdm_like_mode_refills_ammo() -> void:
	var world := _new_world()
	var mode := _ArenaModeDouble.new()
	mode.add_to_group("game_mode")
	world.add_child(mode)
	auto_free(mode)
	var player := _bot_player(world, 9103, _offset())
	var weapon := _weapon_of(player)
	var full_mag: Array = weapon._server_inv.mag.duplicate()
	var full_reserve: Array = weapon._server_inv.reserve.duplicate()

	_drain_ammo(weapon)
	world._on_player_died(0, player)
	await await_millis(int(world.respawn_delay * 1000.0) + 150)

	assert_array(weapon._server_inv.mag).is_equal(full_mag)
	assert_array(weapon._server_inv.reserve).is_equal(full_reserve)


# ======================================================================
#  4. Litige / Duel (RoundMode : respawns_immediately() == false) : INCHANGÉS.
#     `_on_player_died` rend la main avant tout respawn/refill — ces deux
#     modes rechargent DÉJÀ au round via leur propre `_after_round_respawn`
#     (SnDMode.gd/DuelMode.gd, hors fichiers possédés ici).
# ======================================================================

func test_round_based_mode_is_not_refilled_by_on_player_died() -> void:
	var world := _new_world()
	var mode := _RoundBasedModeDouble.new()
	mode.add_to_group("game_mode")
	world.add_child(mode)
	auto_free(mode)
	var player := _bot_player(world, 9104, _offset())
	var weapon := _weapon_of(player)

	_drain_ammo(weapon)
	assert_bool(_is_fully_drained(weapon)).is_true()

	world._on_player_died(0, player)
	# Aucune minuterie de respawn n'est programmée dans ce mode (retour anticipé) :
	# on attend quand même, pour prouver l'absence de tout effet DIFFÉRÉ, pas
	# seulement synchrone.
	await await_millis(int(world.respawn_delay * 1000.0) + 150)

	assert_bool(_is_fully_drained(weapon)).append_failure_message(
		"Litige/Duel : _on_player_died ne doit JAMAIS recharger l'inventaire (RoundMode gère son propre round_respawn)"
	).is_true()
