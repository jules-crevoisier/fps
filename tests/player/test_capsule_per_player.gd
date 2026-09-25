## test_capsule_per_player.gd
## Spec (BUG-22, docs/audit/bugs.md) : le CapsuleShape3D du sous-resource de
## scenes/player/player.tscn est PARTAGÉ par défaut entre toutes les instances
## de la scène. Or `PlayerController._apply_body_height()` MUTE `shape.height`
## directement (appelée par `_update_crouch_height`, autorité SERVEUR, ET par
## la branche non-autorité de `_physics_process`, pour les corps distants
## répliqués) — sans capsule propre à chaque instance, UN SEUL joueur
## accroupi rétrécissait donc la hitbox de TOUS les autres joueurs, aussi
## bien côté serveur (bots/hôte, qui possèdent l'autorité) que côté client
## (un pair qui applique la hauteur répliquée d'un AUTRE joueur). Le
## correctif duplique `collision.shape` au `_ready()` de chaque instance.
##
## Voir aussi (même notes de contrat) : hauteur de capsule parfois NÉGATIVE au
## respawn de la manche 2 en Duel/Duo (« CapsuleShape3D height cannot be
## negative ») — `_update_crouch_height` doit borner `current_height` à
## [crouch_height ; stand_height] même si un delta anormalement grand (hitch)
## fait extrapoler le lerp au-delà de sa cible.
##
## Instances réelles de scenes/player/player.tscn (même méthode que
## tests/player/test_respawn_state_reset.gd et tests/player/test_state_exits.gd),
## SANS sol de décor : ces tests exercent `_update_crouch_height`/
## `_apply_body_height` directement (comme `player._do_respawn` dans
## test_respawn_state_reset.gd) pour isoler le mécanisme visé par BUG-22, sans
## dépendre du timing organique gravité/sol de la state machine.
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _next_offset_index := 0
var _next_peer_id := 101  # pairs "distants" simulés (jamais 1, jamais >= BOT_ID_START)


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


## Instance réelle du joueur, spawnée comme un BOT (autorité SERVEUR — voir
## PlayerController._enter_tree) : `_physics_process` tourne alors sur la
## branche AUTORITÉ (celle qu'emprunte aussi l'hôte-joueur et le serveur pour
## chaque bot), qui recalcule `current_height` via `_update_crouch_height`.
## Même méthode que tests/player/test_respawn_state_reset.gd::_bot_player.
func _bot_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	player.set("is_bot", true)
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	auto_free(player)
	return player


## Instance réelle du joueur nommée comme un pair RÉEL distant (id < BOT_ID_START,
## jamais 1) : `_enter_tree` lui donne alors l'autorité DE CE PAIR, jamais la
## nôtre (id local par défaut = 1 en headless sans MultiplayerPeer). Sa
## `_physics_process` emprunte donc la branche NON-AUTORITÉ — exactement ce que
## fait un CLIENT (ou le serveur) qui observe un AUTRE joueur humain distant :
## il ne fait qu'APPLIQUER `current_height` (déjà répliqué) via
## `_apply_body_height()`, sans jamais rappeler `_update_crouch_height`.
func _remote_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(_next_peer_id)
	_next_peer_id += 1
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	auto_free(player)
	return player


# --------------------------------------------------- capsule indépendante (serveur)

func test_crouching_bot_does_not_shrink_another_bots_capsule() -> void:
	# Deux instances AUTORITÉ (comme le ferait le serveur pour l'hôte et pour
	# chaque bot) : l'une s'accroupit, l'autre reste debout. `_update_crouch_
	# height` est appelée directement (comme `player._do_respawn`/`player.
	# _check_fall_stun` dans tests/player/test_respawn_state_reset.gd) plutôt
	# que de faire tourner tout `_physics_process`/la state machine : ceci
	# isole EXACTEMENT le mécanisme visé par BUG-22 (la capsule mutée par
	# `_apply_body_height`) sans dépendre du timing organique gravité/sol
	# (Idle/Air remettent `is_crouching` à false sur `enter()` — hors sujet ici).
	var o := _offset()
	var crouching := _bot_player(o)
	var standing := _bot_player(o + Vector3(3, 0, 0))
	await get_tree().physics_frame

	assert_float(standing.collision.shape.height).append_failure_message(
		"préalable du test : les deux capsules doivent démarrer debout (1,80 m)"
	).is_equal_approx(1.8, 0.01)

	crouching.is_crouching = true
	# Assez de ticks pour que le lerp (crouch_lerp_speed) converge nettement.
	var dt := 1.0 / 60.0
	for i in range(60):
		crouching._update_crouch_height(dt)

	assert_float(crouching.collision.shape.height).append_failure_message(
		"le joueur accroupi devrait avoir une capsule nettement rétrécie (cible %.2f m), obtenu %.2f m"
			% [crouching.config.crouch_height, crouching.collision.shape.height]
	).is_less(1.2)
	assert_float(standing.collision.shape.height).append_failure_message(
		"BUG-22 : la capsule d'UN AUTRE joueur (qui ne s'est jamais accroupi) a rétréci alors qu'un joueur voisin s'accroupissait — capsule partagée entre instances"
	).is_equal_approx(1.8, 0.01)
	assert_bool(standing.is_crouching).append_failure_message(
		"préalable du test : le joueur debout ne doit jamais être passé en état accroupi"
	).is_false()


# ---------------------------------------------------- capsule indépendante (client)

func test_replicated_crouch_on_one_remote_player_does_not_shrink_another_remote_players_capsule() -> void:
	# Simule un CLIENT (ou le serveur) qui observe DEUX AUTRES joueurs humains
	# distants : aucun n'a l'autorité localement, donc `_physics_process`
	# n'emprunte QUE la branche `_apply_body_height()` (jamais
	# `_update_crouch_height`) — reproduit fidèlement l'application d'une
	# valeur `current_height` reçue par réplication (SceneReplicationConfig,
	# player.tscn).
	var o := _offset()
	var crouched_remote := _remote_player(o)
	var standing_remote := _remote_player(o + Vector3(3, 0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_bool(crouched_remote.is_multiplayer_authority()).append_failure_message(
		"préalable du test : ce pair distant simulé ne doit PAS avoir l'autorité localement"
	).is_false()

	# Valeurs "reçues par réplication" : l'un accroupi, l'autre debout.
	crouched_remote.current_height = crouched_remote.config.crouch_height
	standing_remote.current_height = standing_remote.config.stand_height
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_float(crouched_remote.collision.shape.height).append_failure_message(
		"le corps distant répliqué comme accroupi doit appliquer sa propre hauteur"
	).is_equal_approx(crouched_remote.config.crouch_height, 0.01)
	assert_float(standing_remote.collision.shape.height).append_failure_message(
		"BUG-22 côté client : la capsule d'un AUTRE corps distant debout a rétréci quand un pair voisin appliquait une hauteur accroupie répliquée"
	).is_equal_approx(standing_remote.config.stand_height, 0.01)


# ----------------------------------------------- garde de régression (identité)

func test_two_player_instances_never_share_the_same_capsule_shape_resource() -> void:
	# Garde directe contre une régression future : même sans faire bouger la
	# hauteur, les deux instances ne doivent JAMAIS pointer vers le même objet
	# CapsuleShape3D (le sous-resource du .tscn est partagé par défaut tant
	# qu'il n'est pas dupliqué par instance).
	var o := _offset()
	var a := _bot_player(o)
	var b := _bot_player(o + Vector3(3, 0, 0))
	await get_tree().physics_frame

	assert_object(a.collision.shape).append_failure_message(
		"les deux instances de joueur partagent la MÊME ressource CapsuleShape3D — muter l'une mute l'autre (BUG-22)"
	).is_not_same(b.collision.shape)


# --------------------------------------- hauteur bornée (respawn manche 2, Duel/Duo)

func test_update_crouch_height_never_goes_negative_even_with_a_large_delta_spike() -> void:
	# Repro du bug noté dans les notes du contrat BUG-22 : un delta anormalement
	# grand (hitch au respawn de la manche 2 en Duel/Duo) combiné à
	# `crouch_lerp_speed` (poids de lerp très supérieur à 1) EXTRAPOLE au-delà
	# de la cible sans clamp, jusqu'à une hauteur négative — que CapsuleShape3D
	# refuse ("height cannot be negative").
	var o := _offset()
	var player := _bot_player(o)
	await get_tree().physics_frame

	player.current_height = player.config.stand_height
	player.is_crouching = true  # cible = crouch_height, à l'opposé de la valeur actuelle

	player._update_crouch_height(2.0)  # delta énorme (hitch de manche)

	assert_float(player.current_height).append_failure_message(
		"current_height = %.3f : doit rester borné à [%.2f ; %.2f], jamais négatif ni au-delà de la cible"
			% [player.current_height, player.config.crouch_height, player.config.stand_height]
	).is_between(player.config.crouch_height, player.config.stand_height)
	assert_float(player.collision.shape.height).append_failure_message(
		"CapsuleShape3D.height négatif ferait planter le moteur (\"height cannot be negative\")"
	).is_not_negative()
