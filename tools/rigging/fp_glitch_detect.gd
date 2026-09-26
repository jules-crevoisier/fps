## fp_glitch_detect.gd
## Détecteur d'images aberrantes de la vue FPS : enchaîne des cycles visée / relâche (et un tir
## en visée), et à CHAQUE image mesure l'angle entre le canon (−Z du modèle d'arme) et le regard
## de la caméra. Signale toute image au-delà de SEUIL degrés (+ l'état de l'arbre d'animation).
##   "%GODOT%" --screen 1 --path . -s res://tools/rigging/fp_glitch_detect.gd
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const _SETTLE := 120
const CYCLES := 10
const PERIOD := 40      ## frames par cycle : visée pressée à 0, tir de 16 à 22, relâchée à 26
const SEUIL := 25.0

var _frame := 0
var _player: PlayerController
var _vm
var _worst := 0.0
var _flagged := 0

func _process(_delta: float) -> bool:
	if _frame == 0:
		Engine.max_fps = 60
		MatchConfig.mode_id = "tdm"
		MatchConfig.map_id = "shipment"
		MatchConfig.bots_enabled = true
		MatchConfig.team_size = 1
		get_root().add_child((load(_SHIPMENT) as PackedScene).instantiate())
	_frame += 1
	if _frame == _SETTLE:
		_player = _find_human(get_root())
		_vm = _player.find_child("ViewModel", true, false) if _player else null
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _vm == null:
		return false
	var t := _frame - _SETTLE
	var c := t % PERIOD
	if c == 0:
		Input.action_press("aim")
	elif c == 16:
		Input.action_press("fire")
	elif c == 22:
		Input.action_release("fire")
	elif c == 26:
		Input.action_release("aim")
	_check(t)
	if t >= CYCLES * PERIOD:
		print("GLITCH_SUMMARY frames_flagged=%d worst_deg=%.1f" % [_flagged, _worst])
		quit()
	return false

func _check(t: int) -> void:
	var model: Node3D = _vm._model
	if model == null or not model.is_inside_tree():
		return
	var cam: Camera3D = _player.camera
	var gun_fwd := -model.global_transform.basis.z.normalized()
	var cam_fwd := -cam.global_transform.basis.z.normalized()
	var ang := rad_to_deg(gun_fwd.angle_to(cam_fwd))
	_worst = maxf(_worst, ang)
	if ang > SEUIL:
		_flagged += 1
		var tree: AnimationTree = _vm._arms._tree
		var eye: Transform3D = _vm._arms.fp_camera_global_pose()
		var rig_vs_cam := rad_to_deg((-eye.basis.z.normalized()).angle_to(cam_fwd))
		var gun_vs_rig := rad_to_deg(gun_fwd.angle_to(-eye.basis.z.normalized()))
		print("GLITCH_SPLIT rig_vs_cam=%.1f gun_vs_rig=%.1f cam_fov=%.1f" % [rig_vs_cam, gun_vs_rig, cam.fov])
		print("GLITCH t=%d cycle_frame=%d angle=%.1f ads_t=%.2f amt=%.2f draw=%s reload=%s insp=%s" % [t, t % PERIOD, ang,
			_vm._ads_t, tree.get("parameters/IdleAds/blend_amount"), tree.get("parameters/DrawShot/active"),
			tree.get("parameters/ReloadShot/active"), tree.get("parameters/InspectShot/active")])

func _find_human(n: Node) -> PlayerController:
	var pc := n as PlayerController
	if pc and pc.is_local_human():
		return pc
	for ch in n.get_children():
		var r := _find_human(ch)
		if r:
			return r
	return null
