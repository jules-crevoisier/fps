## viewmodel_shots.gd (R-A2 — capture ad hoc, tools/screenshot.gd de R-A ne
## permet pas de choisir l'arme équipée). Capture EN FENÊTRÉ (swapchain requis)
## le ViewModel pour 3 armes différentes dans terrain d'entraînement : force le
## loadout local via Weapon.server_set_loadout (même pair = serveur ET
## propriétaire en solo, donc appel direct, pas de RPC) puis attend quelques
## frames que le modèle 3D se charge avant de capturer.
##   godot --path . -s <ce fichier> -- --out=<dossier>
extends SceneTree

const LEVEL := "res://scenes/levels/test_arena.tscn"
# (nom_fichier, id_arme) — pistolet (poing), ravage (fusil d'assaut), faucheur (sniper à lunette).
const SHOTS := [
	["viewmodel_pistolet", 0],
	["viewmodel_ravage", 4],
	["viewmodel_faucheur", 6],
]

var _out_dir: String = ""
var _started: bool = false
var _frame: int = 0
var _shot_index: int = 0
var _player: Node = null
var _weapon: Node = null
var _phase: String = "wait_spawn"  # wait_spawn -> equip -> settle -> capture
var _settle_frames: int = 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		return _start()
	_frame += 1

	match _phase:
		"wait_spawn":
			_player = get_first_node_in_group("local_player")
			if _player == null:
				if _frame > 600:
					print("VIEWMODEL_SHOTS_FAIL timeout waiting for local player")
					quit(1)
					return true
				return false
			_weapon = _player.get_node_or_null("Weapon")
			if _weapon == null:
				print("VIEWMODEL_SHOTS_FAIL no Weapon node on local player")
				quit(1)
				return true
			_phase = "equip"
			return false
		"equip":
			if _shot_index >= SHOTS.size():
				print("VIEWMODEL_SHOTS_DONE")
				quit(0)
				return true
			var id: int = SHOTS[_shot_index][1]
			var ids: Array[int] = [id, id]
			_weapon.server_set_loadout(ids)
			_settle_frames = 0
			_phase = "settle"
			return false
		"settle":
			_settle_frames += 1
			if _settle_frames < 150:
				return false
			_phase = "capture"
			return false
		"capture":
			_capture(SHOTS[_shot_index][0] as String)
			_shot_index += 1
			_phase = "equip"
			return false
	return false

func _start() -> bool:
	if _out_dir.is_empty():
		print("VIEWMODEL_SHOTS_FAIL --out requis")
		quit(1)
		return true
	var look: Node = load("res://scripts/core/LevelLook.gd").new()
	root.add_child(look)
	var packed := load(LEVEL) as PackedScene
	var inst := packed.instantiate()
	if inst.get("agent_select") != null:
		inst.set("agent_select", false)
	root.add_child(inst)
	current_scene = inst
	return false

func _capture(name: String) -> void:
	var img := root.get_texture().get_image()
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	var path := "%s/%s.png" % [_out_dir, name]
	var err := img.save_png(path)
	print("VIEWMODEL_SHOT %s -> %s (err=%d)" % [name, path, err])
