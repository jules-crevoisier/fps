## capture_shots.gd
## Capture d'écran EN FENÊTRÉ (comme tests/ui/capture_shots.gd et
## tools/screenshot.gd, lus non modifiés — il faut un vrai swapchain pour
## lire le rendu) de chaque zone du terrain d'entraînement (contract-r4a.md,
## R4-TRAIN : "screenshots of each area"). Charge
## `scenes/levels/training/training_ground.tscn` UNE fois, puis téléporte le
## joueur local (sa propre caméra, pas une caméra externe : ainsi le HUD/les
## panneaux contextuels de zone — gated sur la position RÉELLE du joueur,
## voir MovementTutorial/TimeTrialCourse/ShootingRange/AbilitiesCorner —
## s'affichent comme en jeu) d'une zone à l'autre, capturant une image par
## zone dans le même run (plus rapide qu'un process par cible).
##
##   godot --path . -s res://tests/training/capture_shots.gd -- \
##       --out_dir=C:/tmp/shots/r4 [--wait=60]
##
## Écrit `SCREENSHOT_OK <chemin>` par image, puis `CAPTURE_DONE <n>` et
## quitte (0), ou `SCREENSHOT_FAIL <raison>` et quitte (1).
extends SceneTree

const LEVEL := "res://scenes/levels/training/training_ground.tscn"
const INK_POST_SCRIPT := preload("res://scripts/core/InkPost.gd")

## name, pos, yaw_deg (corps), pitch_deg (tête), extra ("buymenu" ouvre le
## menu d'achat gratuit avant de capturer — râtelier "10 armes"). `pos.y`
## suit le sol RÉEL de chaque section (+1.7 m d'œil debout) — voir
## TrainingLayout.gd pour les hauteurs de plateforme (constaté en capture :
## une hauteur approximative plaçait la caméra à ras du sol ou dans le décor).
## Convention de yaw (Godot, `rotation.y`) : 0 = -Z, 90 = -X, -90 = +X, 180 = +Z.
const TARGETS := [
	{"name": "01_hub", "pos": Vector3(0, 1.7, 9), "yaw": 0.0, "pitch": -6.0},
	{"name": "02_tutorial_slide", "pos": Vector3(0, 1.7, -24), "yaw": 8.0, "pitch": -8.0},
	{"name": "03_tutorial_air_strafe", "pos": Vector3(0, -1.3, -66), "yaw": 0.0, "pitch": -6.0},
	{"name": "04_tutorial_dive_gap", "pos": Vector3(0, -1.3, -80), "yaw": 0.0, "pitch": -6.0},
	{"name": "05_tutorial_tower", "pos": Vector3(0, 6.7, -114), "yaw": 0.0, "pitch": -20.0},
	{"name": "06_timetrial_checkpoint", "pos": Vector3(0, -1.3, -58), "yaw": -15.0, "pitch": -4.0},
	{"name": "07_shooting_range", "pos": Vector3(-10, 1.7, 4), "yaw": 90.0, "pitch": -3.0},
	{"name": "08_abilities_corner", "pos": Vector3(12, 1.7, 0), "yaw": -90.0, "pitch": -5.0},
	{"name": "09_buy_menu", "pos": Vector3(-10, 1.7, 4), "yaw": 90.0, "pitch": -3.0, "extra": "buymenu"},
]

var _out_dir: String = ""
var _wait_frames: int = 60
var _settle_frames: int = 30

var _world: Node
var _player: PlayerController
var _frame: int = 0
var _target_i: int = -1
var _phase_frame: int = 0
var _saved: int = 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out_dir="):
			_out_dir = a.get_slice("=", 1)
		elif a.begins_with("--wait="):
			_wait_frames = int(a.get_slice("=", 1))

func _process(_delta: float) -> bool:
	if _out_dir.is_empty():
		return _fail("--out_dir est requis")
	_frame += 1
	if _world == null:
		return _boot()
	if _player == null or not is_instance_valid(_player):
		_find_player()
		return false
	if _target_i < 0:
		_target_i = 0
		_phase_frame = 0
		_apply_target(TARGETS[_target_i])
		return false
	_phase_frame += 1
	if _phase_frame < _settle_frames:
		return false
	_capture_current()
	_target_i += 1
	if _target_i >= TARGETS.size():
		print("CAPTURE_DONE ", _saved)
		quit(0 if _saved == TARGETS.size() else 1)
		return true
	_phase_frame = 0
	_apply_target(TARGETS[_target_i])
	return false

func _boot() -> bool:
	var packed := load(LEVEL) as PackedScene
	if packed == null:
		return _fail("scène introuvable : %s" % LEVEL)
	_world = packed.instantiate()
	if _world.get("agent_select") != null:
		_world.set("agent_select", false)
	root.add_child(_world)
	current_scene = _world
	return false

func _find_player() -> void:
	if _frame > 600:
		_fail("joueur local introuvable après 600 frames")
		return
	var arr := get_nodes_in_group("local_player")
	if arr.is_empty():
		return
	_player = arr[0] as PlayerController

func _apply_target(t: Dictionary) -> void:
	_player.velocity = Vector3.ZERO
	_player.global_position = t["pos"]
	_player.rotation = Vector3(0, deg_to_rad(float(t["yaw"])), 0)
	_player.head.rotation = Vector3(deg_to_rad(float(t["pitch"])), 0, 0)
	if _player.camera:
		_player.camera.current = true
		if _player.camera.get_node_or_null("InkPost") == null:
			var post := INK_POST_SCRIPT.new()
			post.name = "InkPost"
			_player.camera.add_child(post)
	var extra := String(t.get("extra", ""))
	if extra == "buymenu":
		var buy := _world.get_node_or_null("BuyMenu")
		if buy and buy.has_method("debug_force_open"):
			buy.call("debug_force_open")

func _capture_current() -> void:
	var img := root.get_texture().get_image()
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	var t: Dictionary = TARGETS[_target_i]
	var out_path := "%s/%s.png" % [_out_dir, String(t["name"])]
	var err := img.save_png(out_path)
	if err != OK:
		print("SCREENSHOT_FAIL écriture PNG (%d) pour %s" % [err, out_path])
		return
	print("SCREENSHOT_OK ", out_path)
	_saved += 1

func _fail(reason: String) -> bool:
	print("SCREENSHOT_FAIL ", reason)
	quit(1)
	return true
