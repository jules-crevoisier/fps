## audio_smoke_test.gd
## Expérience contrôlée : chaque façon de jouer un son est isolée dans sa propre fenêtre de
## temps, le bus Master est enregistré, puis le niveau de chaque fenêtre est mesuré. Sert à
## distinguer un vrai silence du jeu d'un artefact d'outil de capture.
##   "%GODOT%" --screen 1 --path . -s res://tools/audio/audio_smoke_test.gd
## Sortie : lignes « SMOKE <cas> rms_db=… » + reports/checkpoints/2026-09-27_audio/smoke.wav
extends SceneTree

const OUT := "res://reports/checkpoints/2026-09-27_audio/smoke.wav"
const SFX := "res://assets/audio/sfx/"

var _rec: AudioEffectRecord
var _cases: Array = []
var _t := 0.0


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var master := AudioServer.get_bus_index("Master")
	_rec = AudioEffectRecord.new()
	AudioServer.add_bus_effect(master, _rec)
	_rec.set_recording_active(true)
	var t0 := Time.get_ticks_msec()
	var stream := load(SFX + "gunshot_revolver_body_1.wav") as AudioStream
	print("SMOKE stream ", stream, " length=", stream.get_length() if stream else -1)
	# cas 1 : AudioStreamPlayer brut sur Master
	await _case("raw_2d_master", t0, func():
		var p := AudioStreamPlayer.new()
		p.stream = stream
		get_root().add_child(p)
		p.play())
	# cas 2 : AudioStreamPlayer brut sur le bus SFX
	await _case("raw_2d_sfx", t0, func():
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = "SFX"
		get_root().add_child(p)
		p.play())
	# cas 3 : Audio.play_local (pool du jeu)
	var audio := get_root().get_node_or_null("Sfx")
	if audio == null:
		audio = get_root().get_node_or_null("Audio")
	print("SMOKE autoload ", audio)
	await _case("audio_play_local_footstep", t0, func(): audio.call("play_local", "footstep_sprint"))
	await _case("audio_play_local_hitmarker", t0, func(): audio.call("play_local", "kill_confirm"))
	# cas 4 : Audio.play_at sans caméra 3D (pas d'écouteur)
	await _case("audio_play_at_no_camera", t0, func(): audio.call("play_at", "gunshot_revolver", Vector3(0, 0, -3)))
	# cas 5 : avec une caméra 3D courante devant la source
	var world := Node3D.new()
	get_root().add_child(world)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.make_current()
	await process_frame
	await _case("audio_play_at_with_camera", t0, func(): audio.call("play_at", "gunshot_revolver", Vector3(0, 0, -3)))
	await _case("audio_play_at_explosion", t0, func(): audio.call("play_at", "explosion", Vector3(0, 0, -5)))
	# mêmes cas 2D rejoués EN FIN de séquence : un silence ici = vrai problème, un son = amorce de l'enregistreur
	await _case("late_raw_2d_master", t0, func():
		var p := AudioStreamPlayer.new()
		p.stream = stream
		get_root().add_child(p)
		p.play())
	await _case("late_play_local_footstep", t0, func(): audio.call("play_local", "footstep_sprint"))
	await _case("late_play_local_kill", t0, func(): audio.call("play_local", "kill_confirm"))
	_rec.set_recording_active(false)
	var wav := _rec.get_recording()
	if wav:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
		wav.save_to_wav(ProjectSettings.globalize_path(OUT))
		_measure(wav)
	quit()


func _case(name: String, t0: int, fn: Callable) -> void:
	var start := (Time.get_ticks_msec() - t0) / 1000.0
	fn.call()
	for i in 60:   # ~1 s par cas
		await process_frame
	var end := (Time.get_ticks_msec() - t0) / 1000.0
	_cases.append([name, start, end])


func _measure(wav: AudioStreamWAV) -> void:
	var data := wav.data
	var stereo := wav.stereo
	var rate := wav.mix_rate
	var n := data.size() / 2
	for c in _cases:
		var a := int(c[1] * rate) * (2 if stereo else 1)
		var b := mini(int(c[2] * rate) * (2 if stereo else 1), n)
		var acc := 0.0
		var peak := 0.0
		for i in range(a, b):
			var v := float(data.decode_s16(i * 2)) / 32768.0
			acc += v * v
			peak = maxf(peak, absf(v))
		var cnt := maxi(b - a, 1)
		print("SMOKE %-28s rms_db=%6.1f peak_db=%6.1f" % [c[0], 10.0 * log(acc / cnt + 1e-12) / log(10.0), 20.0 * log(peak + 1e-9) / log(10.0)])
