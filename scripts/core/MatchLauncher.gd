## MatchLauncher.gd
## Extrait de QuickStart.gd (lancement d'une partie locale) en un point d'entrée
## réutilisable par le menu principal — QuickStart.gd continue de fonctionner
## tel quel (voir sa doc « --quickstart ») pour les captures du lead, il
## délègue simplement ICI au lieu de dupliquer la logique.
##
## Les trois fonctions réseau (`start_local`, `host_lan`, `join`) reproduisent
## la MÊME course « Parent node is busy adding/removing children » documentée
## par QuickStart.gd : `_ready()`/le changement de scène ne doivent JAMAIS
## toucher le pair multijoueur pendant que l'arbre ajoute encore la scène
## courante, d'où les deux `await process_frame` avant tout appel réseau.
class_name MatchLauncher
extends RefCounted

## Applique une config de partie LOCALE à MatchConfig (pure, testable sans
## SceneTree) — mode, taille d'équipe, bots, difficulté, carte, puis persiste
## (MatchConfig.save_last, UX-08 : « JOUER lance le dernier mode »).
static func configure_local(mode_id: String, team_size: int, bots_enabled: bool, bot_difficulty: int, map_id: String = "shipment") -> void:
	MatchConfig.set_mode(mode_id)
	MatchConfig.team_size = team_size
	MatchConfig.map_id = map_id
	MatchConfig.bots_enabled = bots_enabled
	MatchConfig.bot_difficulty = MatchConfig.clamp_difficulty(bot_difficulty)
	MatchConfig.save_last()

## Configure puis héberge une partie LOCALE (solo/duel/entraînement, bots
## compris) et change de scène — même soin de course que QuickStart._ready().
static func start_local(tree: SceneTree, mode_id: String, team_size: int, bots_enabled: bool, bot_difficulty: int, map_id: String = "shipment") -> Error:
	configure_local(mode_id, team_size, bots_enabled, bot_difficulty, map_id)
	return await _host_and_change_scene(tree, NetworkManager.DEFAULT_PORT)

## Héberge une partie LAN (bouton HOST du panneau « Rejoindre / héberger ») avec
## la config MatchConfig COURANTE (déjà choisie par le joueur sur l'accueil) —
## ne touche à aucun champ de MatchConfig, juste la persiste puis héberge.
static func host_lan(tree: SceneTree, port: int = NetworkManager.DEFAULT_PORT) -> Error:
	MatchConfig.save_last()
	return await _host_and_change_scene(tree, port)

static func _host_and_change_scene(tree: SceneTree, port: int) -> Error:
	# `_ready()`/le changement de scène pendant que l'arbre ajoute encore CETTE
	# scène-ci lève "Parent node is busy adding/removing children" — voir
	# QuickStart.gd, doc de tête.
	await tree.process_frame
	await tree.process_frame
	var net := NetworkManager.get_net(tree)
	net.disconnect_from_game()  # jamais de connexion résiduelle avant d'héberger.
	var err := net.host(port)
	if err == OK:
		tree.change_scene_to_file(MatchConfig.resolve_scene(MatchConfig.mode_id, MatchConfig.map_id))
	else:
		push_error("MatchLauncher : échec de l'hébergement (%s)." % err)
	return err

## Rejoint un hôte à `ip`. Ne change PAS de scène directement : le CLIENT
## charge toujours la scène résolue par le SERVEUR, reçue pendant
## l'authentification (NetworkManager.match_config_received) — jamais sa
## propre sélection locale (BUG-02, docs/audit/bugs.md, voir NetworkManager.gd
## doc de `received_scene`). L'appelant (HomeScreen) peut écouter
## `net.connection_failed` pour afficher une erreur dans le panneau IP.
static func join(tree: SceneTree, ip: String, port: int = NetworkManager.DEFAULT_PORT) -> Error:
	var net := NetworkManager.get_net(tree)
	net.disconnect_from_game()
	var err := net.join(ip, port)
	if err == OK:
		net.match_config_received.connect(func(_mode_id: String, _map_id: String, scene: String) -> void:
			tree.change_scene_to_file(scene if scene != "" else NetworkManager.MAIN_MENU)
		, CONNECT_ONE_SHOT)
	return err
