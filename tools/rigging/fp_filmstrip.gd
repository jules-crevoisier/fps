## fp_filmstrip.gd
## Pellicule de la vue FPS en jeu : joue une séquence d'entrées scriptée (visée, tir en visée,
## déplacement en visée, tir à la hanche, rechargement, visée pendant le rechargement,
## inspection interrompue par un tir) et enregistre une image toutes les STEP frames.
##   "%GODOT%" --screen 1 --path . -s res://tools/rigging/fp_filmstrip.gd
## Puis : python tools/rigging/filmstrip_sheet.py (planches annotées).
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const _SETTLE := 120
const STEP := 5
const OUT_DIR := "res://reports/checkpoints/fp_filmstrip"
## frame (depuis la fin de l'installation) -> [action, pressée ?]
const TIMELINE := [
	[20, "aim", true], [50, "fire", true], [85, "fire", false],
	[95, "move_forward", true], [140, "move_forward", false], [150, "aim", false],
	[160, "fire", true], [180, "fire", false],
	[190, "reload", true], [194, "reload", false],
	[260, "aim", true], [300, "aim", false],
	[360, "inspect", true], [364, "inspect", false],
	[450, "fire", true], [470, "fire", false],
]
const END := 520

var _frame := 0
var _player: PlayerController
var _step := STEP
var _from := 10
var _to := END

func _initialize() -> void:
	# Options : --step=N --from=F --to=T (ex. image par image autour du clic de visée).
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=")
		if kv.size() == 2 and kv[0] in ["step", "from", "to"]:
			set("_" + kv[0], int(kv[1]))

func _process(_delta: float) -> bool:
	if _frame == 0:
		Engine.max_fps = 60  # 1 frame = 1/60 s : la chronologie ci-dessus est en temps réel
		MatchConfig.mode_id = "tdm"
		MatchConfig.map_id = "shipment"
		MatchConfig.bots_enabled = true
		MatchConfig.team_size = 1
		get_root().add_child((load(_SHIPMENT) as PackedScene).instantiate())
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_frame += 1
	if _frame == _SETTLE:
		_player = _find_human(get_root())
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _player == null:
		return false
	var t := _frame - _SETTLE
	for ev in TIMELINE:
		if ev[0] == t:
			if ev[2]:
				Input.action_press(ev[1])
			else:
				Input.action_release(ev[1])
	if t >= _from and t <= _to and (t - _from) % _step == 0:
		var img := get_root().get_texture().get_image()
		if img:
			img.resize(384, 216)
			img.save_png(ProjectSettings.globalize_path(OUT_DIR.path_join("f_%04d.png" % t)))
	if t >= END:
		quit()
	return false

func _find_human(n: Node) -> PlayerController:
	var pc := n as PlayerController
	if pc and pc.is_local_human():
		return pc
	for c in n.get_children():
		var r := _find_human(c)
		if r:
			return r
	return null
