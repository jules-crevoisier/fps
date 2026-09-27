## idle_sound_probe.gd
## Liste les sons joués SANS aucune action du joueur (menu, puis partie), avec leur horodatage :
## sert à traquer un bruit qui « se répète toutes les secondes ». S'appuie sur le journal de
## débogage d'Audio.gd (`debug_log_enabled`). Joue aussi la boucle de musique/ambiance active.
##   "%GODOT%" --screen 1 --path . -s res://tools/audio/idle_sound_probe.gd
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_run.call_deferred()


func _run() -> void:
	var audio := get_root().get_node_or_null("Sfx")
	audio.set("debug_log_enabled", true)
	change_scene_to_file("res://scenes/ui/main_menu.tscn")   # vrai salon (musique du menu comprise)
	await _wait_s(10.0)
	_dump("MENU", audio)
	_list_players("MENU")
	# VRAI lancement de match (même chemin que le bouton JOUER) : musique/ambiance démarrent comme en jeu
	MatchLauncher.start_local(self, "tdm", 4, true, MatchConfig.Difficulty.VETERAN)
	await _wait_s(15.0)
	for pc in get_root().find_children("*", "PlayerController", true, false):
		(pc as Node).set_process_input(false)
		(pc as Node).set_process_unhandled_input(false)
	_dump("GAME", audio)
	_list_players("GAME")
	quit()


func _wait_s(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000.0):
		await process_frame


func _dump(tag: String, audio: Node) -> void:
	var log: Array = audio.get("debug_log")
	var counts := {}
	for e in log:
		counts[e["sound"]] = counts.get(e["sound"], 0) + 1
	print("IDLE_", tag, " events=", log.size(), " counts=", counts)
	var last := {}
	for e in log:
		var n: String = e["sound"]
		if last.has(n):
			print("IDLE_", tag, "  ", n, " +%.2fs" % (e["t"] - last[n]))
		last[n] = e["t"]
	log.clear()


## Tout lecteur audio EN COURS (musique, ambiance, boucles) -- un bruit périodique peut venir d'une
## boucle, qui n'apparaît pas dans le journal des sons ponctuels.
func _list_players(tag: String) -> void:
	for p in get_root().find_children("*", "AudioStreamPlayer", true, false):
		var ap := p as AudioStreamPlayer
		if ap.playing:
			print("IDLE_", tag, "_PLAYING 2D ", ap.get_path(), " ", ap.stream.resource_path if ap.stream else "?", " bus=", ap.bus, " vol=", ap.volume_db)
	for p in get_root().find_children("*", "AudioStreamPlayer3D", true, false):
		var ap3 := p as AudioStreamPlayer3D
		if ap3.playing:
			print("IDLE_", tag, "_PLAYING 3D ", ap3.get_path(), " ", ap3.stream.resource_path if ap3.stream else "?")
