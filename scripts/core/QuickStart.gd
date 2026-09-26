## QuickStart.gd
## Prototype minimal (décision 2026-09-26, "strip to minimal prototype", puis
## "clean absolument tout, repart sur de bonnes bases") : le jeu n'a plus de
## menu principal — cette scène de boot (scenes/boot.tscn, run/main_scene dans
## project.godot) reproduit directement l'ancienne logique
## MainMenu._on_host()/_start_game() pour une partie locale TDM sur Shipment,
## bots activés (4v4 : le joueur + 3 bots alliés contre 4 bots ennemis,
## difficulté Vétéran) — sans écran à traverser. Settings.gd reste lu
## normalement (sensibilité/AZERTY depuis user://settings.cfg), juste sans
## interface pour les modifier.
extends Node

func _ready() -> void:
	Settings.load_all()
	MatchConfig.set_mode("tdm")
	MatchConfig.map_id = "shipment"
	MatchConfig.bots_enabled = true
	MatchConfig.bot_difficulty = MatchConfig.Difficulty.VETERAN

	# `_ready()` s'exécute pendant que l'arbre ajoute encore la scène
	# principale (même course que ServerBoot._ready, voir sa doc) : toucher le
	# pair multijoueur ou changer de scène ICI lève "Parent node is busy
	# adding/removing children". On attend deux frames complètes avant d'agir.
	await get_tree().process_frame
	await get_tree().process_frame

	var net := NetworkManager.get_net(get_tree())
	net.disconnect_from_game()  # jamais de connexion résiduelle sur un boot frais.
	if net.host() == OK:
		get_tree().change_scene_to_file(MatchConfig.resolve_scene(MatchConfig.mode_id, MatchConfig.map_id))
	else:
		push_error("QuickStart : échec de l'hébergement local.")
