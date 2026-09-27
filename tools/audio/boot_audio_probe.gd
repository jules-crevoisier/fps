## boot_audio_probe.gd
## Démarre le jeu EXACTEMENT comme au lancement (scenes/boot.tscn -> salon), enregistre le bus
## Master ~24 s sans aucune action, journalise chaque son joué (Audio.debug_log) et sauve le WAV :
## sert à identifier un bruit qui revient « toutes les secondes au lancement ». Puis lance une
## partie et fait de même 20 s.
##   "%GODOT%" --screen 1 --path . -s res://tools/audio/boot_audio_probe.gd
## Sortie : lignes BOOT_AUDIO + reports/checkpoints/2026-09-27_audio/boot_{menu,game}.wav
extends SceneTree

const OUT := "res://reports/checkpoints/2026-09-27_audio/"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_run.call_deferred()


func _run() -> void:
	var audio := get_root().get_node_or_null("Sfx")
	audio.set("debug_log_enabled", true)
	var rec := AudioEffectRecord.new()
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), rec)
	change_scene_to_file("res://scenes/boot.tscn")
	await _segment("menu", rec, audio, 24.0)
	var ml := load("res://scripts/core/MatchLauncher.gd")
	ml.start_local(self, "tdm", 4, true, MatchConfig.Difficulty.VETERAN)
	for i in 120:
		await process_frame
	for pc in get_root().find_children("*", "PlayerController", true, false):
		(pc as Node).set_process_input(false)
		(pc as Node).set_process_unhandled_input(false)
	await _segment("game", rec, audio, 20.0)
	quit()


func _segment(tag: String, rec: AudioEffectRecord, audio: Node, seconds: float) -> void:
	(audio.get("debug_log") as Array).clear()
	rec.set_recording_active(true)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await process_frame
	rec.set_recording_active(false)
	var wav := rec.get_recording()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if wav:
		wav.save_to_wav(ProjectSettings.globalize_path(OUT + "boot_%s.wav" % tag))
	var log: Array = audio.get("debug_log")
	var counts := {}
	for e in log:
		counts[e["sound"]] = counts.get(e["sound"], 0) + 1
	print("BOOT_AUDIO ", tag, " events=", log.size(), " counts=", counts)
	for e in log.slice(0, 40):
		print("BOOT_AUDIO ", tag, " t=%.2f %s %.1fdB" % [(e["t"] * 1000.0 - t0) / 1000.0, e["sound"], e["volume_db"]])
	for p in get_root().find_children("*", "AudioStreamPlayer", true, false):
		var ap := p as AudioStreamPlayer
		if ap.playing and ap.stream:
			print("BOOT_AUDIO ", tag, " PLAYING ", ap.stream.resource_path, " bus=", ap.bus, " vol=", ap.volume_db)
