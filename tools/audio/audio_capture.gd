## audio_capture.gd
## Vérification du mix (tâche "son", 2026-09-27) : héberge Shipment SANS bot,
## pilote le joueur directement via `player.input.*` (comme
## tools/review/gameplay_probe.gd -- `Input.mouse_mode` n'est pas fiable en
## tête sans fenêtre réelle, voir sa docstring de tête ; ici on tourne EN
## FENÊTRE mais on ne veut toujours pas voler le focus, voir NO_FOCUS
## ci-dessous), enregistre le bus Master (AudioEffectRecord) pendant une
## séquence scriptée qui couvre chaque famille de son de cette tâche, écrit
## le WAV + un journal texte horodaté des sons RÉELLEMENT joués
## (Audio.debug_log, activé UNIQUEMENT par cet outil).
##
## PAS headless : un vrai swapchain audio est nécessaire pour que
## AudioEffectRecord capture des échantillons réels (le pipeline audio de
## Godot tourne même fenêtre invisible/NO_FOCUS, contrairement au rendu).
##
## Usage :
##   "%GODOT%" --path . -s res://tools/audio/audio_capture.gd --screen 1 -- --out=reports/checkpoints/2026-09-27_audio
extends SceneTree

const SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const OUT_DEFAULT := "res://reports/checkpoints/2026-09-27_audio"

var _out_dir: String = OUT_DEFAULT
var _world: Node = null
var _player: PlayerController = null
## Godot 4.7 (vérifié empiriquement sur ce projet -- la doc en ligne encore
## indexée pour 4.3 décrit `AudioEffectRecordInstance.set_recording_active`,
## qui N'EXISTE PLUS ici, `ClassDB.class_get_method_list` le confirme vide) :
## `set_recording_active`/`get_recording` vivent sur la RESSOURCE
## `AudioEffectRecord` elle-même (celle posée sur le bus), jamais sur son
## "instance" d'exécution -- on garde donc directement la ressource.
var _recorder: AudioEffectRecord
var _record_start_t: float = 0.0
var _started: bool = false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)
	# Fenêtre NO_FOCUS (consigne) : ne vole jamais le focus de l'utilisateur
	# pendant que la séquence tourne toute seule.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true, DisplayServer.MAIN_WINDOW_ID)

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false  # `_run()` appelle `quit()` lui-même à la fin.

func _sfx() -> Audio:
	# Jamais l'identifiant nu "Sfx" : ne se résout pas de façon fiable depuis
	# un script `-s` qui remplace la boucle principale (voir
	# ThrownUtility._play_sfx, même mise en garde) -- résolution par chemin ABSOLU.
	return root.get_node_or_null("Sfx") as Audio

# ==========================================================================
#  ORCHESTRATION
# ==========================================================================
func _run() -> void:
	await _boot()
	if _player == null:
		push_error("audio_capture: le joueur hôte n'a jamais spawné sur Shipment")
		quit(1)
		return
	_start_recording()
	var sfx := _sfx()
	if sfx:
		sfx.debug_log_enabled = true
	await _sequence()
	await _wait_physics(60)  # laisse les derniers sons (réverbération, fondu du fumigène...) finir.
	_stop_and_save()
	quit(0)

func _boot() -> void:
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = "shipment"
	MatchConfig.bots_enabled = false  # consigne : bots OFF.
	MatchConfig.team_size = 1
	var packed := load(SHIPMENT) as PackedScene
	if packed == null:
		push_error("audio_capture: scène introuvable : %s" % SHIPMENT)
		return
	_world = packed.instantiate()
	# "map ajoutée DEFERRED" (consigne) : jamais un add_child() direct pendant
	# que _initialize()/le tout premier _process() tourne encore.
	root.call_deferred("add_child", _world)
	await process_frame
	await process_frame
	current_scene = _world
	_player = await _wait_for_local_player(10.0)
	if _player:
		# Pilotage direct de `input.*` (voir docstring de tête,
		# tools/review/gameplay_probe.gd) : jamais Input.action_press ici.
		_player.is_bot = true
		_player.input.reads_devices = false

func _wait_for_local_player(timeout: float) -> PlayerController:
	var t := 0.0
	while t < timeout:
		for n in get_nodes_in_group("local_player"):
			if is_instance_valid(n) and not (n as Node).is_queued_for_deletion():
				return n as PlayerController
		await physics_frame
		t += 1.0 / 60.0
	return null

func _weapon() -> Weapon:
	return _player.get_node_or_null("Weapon") as Weapon

func _utility() -> UtilityThrower:
	return _player.get_node_or_null("UtilityThrower") as UtilityThrower

func _wait_physics(n: int) -> void:
	for i in n:
		await physics_frame

func _wait_sim(seconds: float) -> void:
	await create_timer(seconds).timeout

# ==========================================================================
#  ENREGISTREMENT (AudioEffectRecord sur Master)
# ==========================================================================
func _start_recording() -> void:
	var idx := AudioServer.get_bus_index("Master")
	if idx < 0:
		push_error("audio_capture: bus Master introuvable")
		return
	_recorder = AudioEffectRecord.new()
	AudioServer.add_bus_effect(idx, _recorder)
	_recorder.set_recording_active(true)
	# `Audio._debug_log` horodate en `Time.get_ticks_msec()` ABSOLU (depuis le
	# lancement du PROCESSUS, voir sa docstring) -- le WAV, lui, commence à
	# l'échantillon 0 pile ICI. Sans cette référence, chaque horodatage du
	# journal serait décalé du temps de boot/chargement de carte par rapport
	# au fichier audio -- retenue pour rendre `events.txt` DÉJÀ relatif au
	# début de l'enregistrement (voir `_write_event_log`).
	_record_start_t = Time.get_ticks_msec() / 1000.0

func _stop_and_save() -> void:
	var abs_dir := ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	if _recorder:
		_recorder.set_recording_active(false)
		var stream: AudioStreamWAV = _recorder.get_recording()
		if stream:
			var wav_path := _out_dir.path_join("mix.wav")
			var err: Error = stream.save_to_wav(wav_path)
			print("audio_capture: mix.wav -> ", wav_path, " (err=", err, ")")
		else:
			push_error("audio_capture: get_recording() a renvoyé null (rien capturé)")
	_write_event_log(_out_dir.path_join("events.txt"))
	var sfx := _sfx()
	if sfx:
		sfx.debug_log_enabled = false
		sfx.debug_log.clear()

func _write_event_log(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("audio_capture: impossible d'écrire %s" % path)
		return
	var sfx := _sfx()
	var log_entries: Array = sfx.debug_log if sfx else []
	for e in log_entries:
		# Relatif au début de l'enregistrement (voir `_start_recording`), PAS
		# l'horodatage absolu brut -- s'aligne directement sur mix.wav (échantillon 0 = t=0).
		var t_rel: float = float(e["t"]) - _record_start_t
		f.store_line("%.3f\t%s\t%.2f" % [t_rel, String(e["sound"]), float(e["volume_db"])])
	f.close()
	print("audio_capture: events.txt -> ", path, " (", log_entries.size(), " sons)")

# ==========================================================================
#  SÉQUENCE SCRIPTÉE (consigne : revolver+fan+reload+inspect, Ravage, grenades, déplacement)
# ==========================================================================
func _sequence() -> void:
	await _use_revolver()
	await _use_ravage()
	await _use_grenades()
	await _walk_and_sprint()

func _use_revolver() -> void:
	var w := _weapon()
	_player.input.weapon_slot_pressed = 1  # id 1 = Revolver (WeaponDatabase.PATHS).
	await _wait_physics(3)
	_player.input.weapon_slot_pressed = -1
	await _wait_sim(0.5)  # Weapon.SWITCH_DELAY + marge.

	# 3 tirs LMB (semi-auto, fire_rate=3.0/s -> >= 1/3 s entre deux appuis pour
	# que chacun soit réellement accepté par FireClock, jamais absorbé).
	for i in 3:
		_player.input.fire_pressed = true
		await _wait_physics(1)
		_player.input.fire_pressed = false
		await _wait_sim(0.45)

	# 1 s de fan (RMB tenu, `alt_fire_held` -- voir Weapon._owner_tick).
	_player.input.alt_fire_held = true
	await _wait_sim(1.0)
	_player.input.alt_fire_held = false
	await _wait_sim(0.4)

	# Rechargement (foley dédié, WeaponFoley.revolver_reload_events).
	_player.input.reload_pressed = true
	await _wait_physics(2)
	_player.input.reload_pressed = false
	var c := w.cfg() if w else null
	await _wait_sim((c.reload_time if c else 2.4) + 0.6)

	# Inspection (touche E -- WeaponFoley.revolver_inspect_events).
	_player.input.inspect_pressed = true
	await _wait_physics(2)
	_player.input.inspect_pressed = false
	await _wait_sim(3.0)

func _use_ravage() -> void:
	var w := _weapon()
	_player.input.weapon_slot_pressed = 0  # id 0 = Ravage.
	await _wait_physics(3)
	_player.input.weapon_slot_pressed = -1
	await _wait_sim(0.5)

	_player.input.fire_held = true
	await _wait_sim(1.0)
	_player.input.fire_held = false
	await _wait_sim(0.4)

	_player.input.reload_pressed = true
	await _wait_physics(2)
	_player.input.reload_pressed = false
	var c := w.cfg() if w else null
	await _wait_sim((c.reload_time if c else 1.8) + 0.6)

func _use_grenades() -> void:
	await _throw_grenade(UtilityDatabase.FRAG)
	await _wait_sim(4.0)  # amorce + vol + détonation (fuse_time ~2.5s + marge).
	await _throw_grenade(UtilityDatabase.FLASH)
	await _wait_sim(4.0)  # + laisse l'éblouissement/l'assourdissement se dérouler.
	await _throw_grenade(UtilityDatabase.SMOKE)
	await _wait_sim(4.0)

## Vise devant soi et lance en tap rapide -- appelle DIRECTEMENT les méthodes
## internes de UtilityThrower (`_handle_equip_input`/`_handle_throw_input`)
## plutôt que de passer par `player.input.*` + `_owner_tick` : ce dernier est
## gardé par `player.is_local_human()` (voir UtilityThrower._physics_process),
## qui est FAUX pour `is_bot = true` -- exactement le déguisement utilisé
## ci-dessus pour piloter l'arme sans que PlayerInput ne réécrase les champs
## chaque tick (voir tools/review/gameplay_probe.gd, même mise en garde) --
## par conception, "les bots ne lancent jamais de grenade" (docstring de
## UtilityThrower.gd, point 9 du contrat lead), donc CE chemin normal reste
## bloqué quel que soit `player.input.*`. Appeler les fonctions internes
## directement (GDScript n'impose aucune restriction d'accès sur `_préfixé`)
## reproduit EXACTEMENT le même code -- foley "grenade_pin" PUIS
## "grenade_throw" compris (un appui sans `fire_held` arme le lancer et le
## relâche sur le MÊME appel : `held_now` lit `fire_held`, resté faux).
func _throw_grenade(kind: int) -> void:
	var ut := _utility()
	if ut == null:
		push_error("audio_capture: UtilityThrower introuvable")
		return
	if ut.camera == null:
		ut.camera = _player.camera
	var dt := 1.0 / Engine.physics_ticks_per_second
	_player.input.grenade_slot_pressed = kind
	ut._handle_equip_input()
	_player.input.grenade_slot_pressed = -1
	if not ut.is_utility_equipped():
		push_error("audio_capture: grenade %d refusée à l'équipement (charges=%s)" % [kind, ut.snapshot_charges()])
		return
	# `UtilityEquip.deploy_left` (délai de déploiement, 0.25 s) n'est décompté
	# côté PROPRIÉTAIRE que par `_equip.tick(delta)`, appelé depuis
	# `_owner_tick` -- jamais exécuté ici (voir docstring de fonction) : on
	# saute directement ce délai plutôt que de rappeler `tick()` nous-mêmes à
	# chaque frame pour un simple raccourci de vérification. Côté SERVEUR
	# (`_server_equip`, copie AUTORITAIRE séparée -- voir `_server_throw`, qui
	# rejette silencieusement tant qu'elle n'est pas écoulée), le décompte
	# tourne réellement à chaque tick physique (gardé par
	# `multiplayer.is_server()` SEUL, jamais `is_local_human()`) : une vraie
	# attente suffit, jamais besoin de la forcer.
	ut._equip.deploy_left = 0.0
	await _wait_sim(0.3)
	_player.input.fire_pressed = true
	ut._handle_throw_input(dt)
	_player.input.fire_pressed = false
	await _wait_physics(5)

## Marche puis sprint sur le sol en béton (spawn), puis -- si un collider dont
## le nom contient "container"/"conteneur" existe sur CETTE carte -- sur son
## toit (métal). Shipment ne nomme pas encore ses conteneurs ainsi au moment
## de cette tâche (aucune méta "surface" non plus) : ce second passage est
## alors sauté proprement (voir le rapport pour cette lacune de contenu, pas
## de code).
func _walk_and_sprint() -> void:
	_player.input.walk_held = true
	_player.input.move = Vector2(0, -1)
	await _wait_sim(2.0)
	_player.input.walk_held = false  # sprint automatique dès qu'on avance sans marche forcée.
	await _wait_sim(2.0)
	_player.input.move = Vector2.ZERO
	_player.input.walk_held = false
	await _wait_sim(0.3)

	var top = _find_container_top()
	if top == null:
		print("audio_capture: aucun collider \"container\"/\"conteneur\" trouvé sur Shipment -- pas au métal sauté")
		return
	_player.global_position = (top as Vector3) + Vector3.UP * 1.0
	_player.velocity = Vector3.ZERO
	await _wait_physics(15)
	_player.input.walk_held = true
	_player.input.move = Vector2(0, -1)
	await _wait_sim(1.0)
	_player.input.walk_held = false
	await _wait_sim(1.0)
	_player.input.move = Vector2.ZERO

func _find_container_top() -> Variant:
	var found := _search_by_name(_world, ["container", "conteneur"])
	if found == null:
		return null
	var mesh := _first_mesh_instance(found)
	if mesh == null:
		return null
	var aabb := mesh.get_aabb()
	var top_local := Vector3(aabb.position.x + aabb.size.x * 0.5, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z * 0.5)
	return mesh.to_global(top_local)

func _search_by_name(node: Node, keywords: Array) -> Node:
	var n := String(node.name).to_lower()
	for k in keywords:
		if n.contains(k):
			return node
	for c in node.get_children():
		var r := _search_by_name(c, keywords)
		if r:
			return r
	return null

func _first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var r := _first_mesh_instance(c)
		if r:
			return r
	return null
