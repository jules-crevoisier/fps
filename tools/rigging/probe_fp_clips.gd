## probe_fp_clips.gd
## Banc d'essai isolé des bras FPS : caméra du viewmodel (54° vertical), FPArmsRig aligné,
## Ravage attaché, chaque clip FP_* posé à des instants fixes (AnimationPlayer direct, sans
## AnimationTree ni gameplay). Sort une planche par clip dans reports/checkpoints/.
##   "%GODOT%" --screen 1 --path . -s res://tools/rigging/probe_fp_clips.gd
extends SceneTree

const OUT_DIR := "res://reports/checkpoints/2026-09-26_frog_fp_probe"
const SHOTS := {
	"FP_Idle": [0.0], "FP_ADS_In": [0.25, 0.5, 0.75], "FP_ADS": [0.0], "FP_Fire": [0.03],
	"FP_Reload": [0.15, 0.35, 0.55, 0.78, 0.84, 0.89, 0.94], "FP_Draw": [0.0, 0.5, 1.0],
	"FP_Sprint": [0.0, 0.5], "FP_Inspect": [0.2, 0.45, 0.7],
}

var _cam: Camera3D
var _rig: FPArmsRig
var _jobs: Array = []
var _frame := 0

func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.43, 0.71, 1.0)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.7)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 135, 0)
	world.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 54.0
	_cam.near = 0.01
	world.add_child(_cam)
	_cam.make_current()
	_rig = FPArmsRig.new()
	world.add_child(_rig)
	if not _rig.load():
		push_error("probe_fp_clips: FPArmsRig.load() a échoué")
		quit(1)
		return
	var gun := (load("res://assets/models/weapons/ravage.glb") as PackedScene).instantiate() as Node3D
	_rig.align_to_camera(_cam, Transform3D.IDENTITY, 1.0)
	_rig.attach_weapon(gun)
	var tree := _rig.find_child("AnimationTree", true, false) as AnimationTree
	if tree == null:
		for c in _rig.get_children():
			if c is AnimationTree:
				tree = c
	if tree:
		tree.active = false
	for clip in SHOTS:
		for u in SHOTS[clip]:
			_jobs.append([clip, u])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

func _process(_delta: float) -> bool:
	_frame += 1
	_rig.align_to_camera(_cam, Transform3D.IDENTITY, 1.0)
	if _frame < 5:
		return false
	var step := (_frame - 5) % 3
	var idx := (_frame - 5) / 3
	if idx >= _jobs.size():
		quit()
		return true
	var clip: String = _jobs[idx][0]
	var u: float = _jobs[idx][1]
	var ap := _rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if step == 0:
		ap.play(clip)
		ap.seek(ap.current_animation_length * u, true)
		ap.pause()
	elif step == 2:
		var img := root.get_texture().get_image()
		var name := "%s_%02d.png" % [clip, int(round(u * 100.0))]
		img.save_png(ProjectSettings.globalize_path(OUT_DIR.path_join(name)))
		print("PROBE_SHOT ", name)
	return false
