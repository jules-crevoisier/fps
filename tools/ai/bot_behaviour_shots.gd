## bot_behaviour_shots.gd
## Captures in-game (tâche "bots humains", 2026-09-27, vérification obligatoire
## du contrat) — même boot que bot_behaviour_probe.gd (TDM 4v4 BOTS SEULS,
## `ServerBoot.active = true`, carte ajoutée EN DIFFÉRÉ), mais ici pour prendre
## 4 captures 1920x1080 depuis une caméra libre placée DERRIÈRE/près d'un bot
## à la suite, à des instants différents (laisse une chance de capturer un
## strafe/une pré-visée de coin où le corps ne fait pas face au déplacement) :
##  - montre l'arme 3P en main (correctif ThirdPersonWeapon.is_local_human()) ;
##  - montre le corps tourné vers un angle plutôt que vers le cap de
##    déplacement (correctif BotLook L7 + BotCombatStyle.movement_pace).
## FENÊTRÉ (swapchain réel nécessaire, voir capture_shipment.gd), `--screen 1
## --resolution 1920x1080` (convention de session).
##
## Usage :
##   "%GODOT%" --path . --screen 1 --resolution 1920x1080 \
##       -s res://tools/ai/bot_behaviour_shots.gd -- \
##       --map=shipment --out=reports/checkpoints/2026-09-27_bots
extends SceneTree

const EXPECTED_BOTS := 8
const SPAWN_WAIT_TIMEOUT_S := 30.0
const SETTLE_EXTRA_FRAMES := 90       ## ~1.5 s : laisse les bots s'engager avant la 1ère capture.
const SHOT_INTERVAL_FRAMES := 150     ## ~2.5 s entre deux captures (change de bot ET laisse la scène évoluer).
const SHOT_COUNT := 4
const CAM_BACK_M := 3.0
const CAM_UP_M := 1.6

var _map_id := "shipment"
var _out_dir := "reports/checkpoints/2026-09-27_bots"

var _phase := 0
var _wait_elapsed_s := 0.0
var _settle_frames_left := SETTLE_EXTRA_FRAMES
var _shot_frame_counter := 0
var _shots_taken := 0
var _bots: Array = []
var _cam: Camera3D = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			_map_id = a.get_slice("=", 1)
		elif a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)


func _process(delta: float) -> bool:
	match _phase:
		0:
			_boot()
			_phase = 1
			return false
		1:
			return _wait_for_bots(delta)
		2:
			_settle_frames_left -= 1
			if _settle_frames_left <= 0:
				_setup_camera()
				_phase = 3
			return false
		3:
			return _shoot_loop()
		4:
			_settle_frames_left -= 1
			if _settle_frames_left <= 0:
				_phase = 3
			return false
	return true


func _boot() -> void:
	ServerBoot.active = true
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = _map_id
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = EXPECTED_BOTS / 2
	MatchConfig.bot_difficulty = MatchConfig.Difficulty.VETERAN
	var packed := load("res://scenes/levels/maps/%s.tscn" % _map_id) as PackedScene
	if packed == null:
		printerr("BOT_SHOTS_FAIL scene_not_found map=%s" % _map_id)
		call_deferred("quit", 1)
		return
	# DIFFÉRÉ : voir bot_behaviour_probe.gd, même raison (autoload Look).
	get_root().add_child.call_deferred(packed.instantiate())


func _wait_for_bots(delta: float) -> bool:
	_wait_elapsed_s += delta
	var world := get_root().get_tree().get_first_node_in_group("match")
	if world != null:
		var players_root := world.get_node_or_null(world.get("players_root"))
		if players_root != null and players_root.get_child_count() >= EXPECTED_BOTS:
			_bots.clear()
			for child in players_root.get_children():
				if bool(child.get("is_bot")):
					_bots.append(child)
			if _bots.size() >= EXPECTED_BOTS:
				_phase = 2
				return false
	if _wait_elapsed_s >= SPAWN_WAIT_TIMEOUT_S:
		printerr("BOT_SHOTS_FAIL bots_not_spawned")
		call_deferred("quit", 1)
		return true
	return false


func _setup_camera() -> void:
	_cam = Camera3D.new()
	get_root().add_child(_cam)
	_cam.current = true


## Place la caméra à `CAM_BACK_M` derrière le bot choisi (dans SA direction de
## regard, pour le voir de dos/3-4 avec l'arme en main) et un peu au-dessus.
func _follow_bot(bot: Node3D) -> void:
	var yaw: float = bot.rotation.y
	var back_dir := Vector3(sin(yaw), 0.0, cos(yaw))  # inverse de BotLook.yaw_forward_dir.
	_cam.global_position = bot.global_position + back_dir * CAM_BACK_M + Vector3.UP * CAM_UP_M
	_cam.look_at(bot.global_position + Vector3.UP * 1.2, Vector3.UP)


func _shoot_loop() -> bool:
	var bot: Node3D = _bots[_shots_taken % _bots.size()]
	_follow_bot(bot)
	_shot_frame_counter += 1
	if _shot_frame_counter < 3:
		return false  # laisse le swapchain présenter la nouvelle vue avant de capturer.
	_shot_frame_counter = 0
	_capture(bot)
	_shots_taken += 1
	if _shots_taken >= SHOT_COUNT:
		call_deferred("quit", 0)
		return true
	# Attend SHOT_INTERVAL_FRAMES avant la prochaine capture (laisse la scène
	# évoluer — un autre bot, un autre instant de comportement).
	_settle_frames_left = SHOT_INTERVAL_FRAMES
	_phase = 4
	return false


func _capture(bot: Node3D) -> void:
	var img := get_root().get_texture().get_image()
	if img == null:
		push_error("bot_behaviour_shots: pas d'image (lancé --headless ?)")
		return
	var abs_dir := ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var name := "bot_%02d_%s.png" % [_shots_taken, str(bot.name)]
	var path := _out_dir.path_join(name)
	var err := img.save_png(path)
	print("BOT_SHOTS: ", name, " -> ", path, " (err=", err, ")")
