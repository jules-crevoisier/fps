## fp_shots.gd
## Capture EN FENÊTRÉ (swapchain requis, comme tools/blender/viewmodel_shots.gd
## et tools/char_ingame_shots.gd) la vue première personne (ViewModel : bras +
## arme) pour plusieurs armes dans test_arena, plus un sprint et un ADS —
## vérification visuelle de la pose FP_Hold + `solve_grip_transform` (fix
## "arme tenue de travers"/"gant quasi noir"). Force le loadout local via
## Weapon.server_set_loadout (même pair = serveur ET propriétaire en solo,
## donc appel direct, pas de RPC — même stratagème que viewmodel_shots.gd).
##
##   godot --path . -s res://tools/fp_shots.gd -- --out=<dossier>
##
## Écrit "<out>/fp_<arme>.png" par arme, "<out>/fp_sprint.png" et
## "<out>/fp_ads.png", imprime `FP_SHOT <nom> -> <chemin>` par capture puis
## `FP_SHOTS_DONE` (0) ou `FP_SHOTS_FAIL <raison>` (1).
extends SceneTree

const LEVEL := "res://scenes/levels/test_arena.tscn"
## (nom_fichier, id_arme) — voir scripts/combat/WeaponDatabase.gd PATHS pour
## les ids : 0 pistolet, 2 rafale, 4 ravage, 5 fracas, 6 faucheur.
const WEAPON_SHOTS := [
	["fp_pistolet", 0],
	["fp_ravage", 4],
	["fp_faucheur", 6],
	["fp_fracas", 5],
	["fp_rafale", 2],
]
## Arme utilisée pour les vues "sprint"/"ads" (n'importe laquelle des 5 ci-
## dessus convient ; ravage = fusil d'assaut, la plus représentative).
const POSE_SHOT_WEAPON_ID := 4
const SETTLE_FRAMES := 150
const POSE_SETTLE_FRAMES := 30

var _out_dir: String = ""
var _started: bool = false
var _player: Node = null
var _weapon: Node = null
var _shot_index: int = 0
var _phase: String = "wait_spawn"  # wait_spawn -> equip -> settle -> capture -> pose_sprint -> pose_ads -> done
var _settle_frames: int = 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		return _start()

	match _phase:
		"wait_spawn":
			_player = get_first_node_in_group("local_player")
			if _player == null:
				_settle_frames += 1
				if _settle_frames > 600:
					return _fail("timeout en attente du joueur local")
				return false
			_weapon = _player.get_node_or_null("Weapon")
			if _weapon == null:
				return _fail("pas de node Weapon sur le joueur local")
			_phase = "equip"
			return false
		"equip":
			if _shot_index >= WEAPON_SHOTS.size():
				_phase = "pose_sprint_equip"
				return false
			var id: int = WEAPON_SHOTS[_shot_index][1]
			var ids: Array[int] = [id, id]
			_weapon.server_set_loadout(ids)
			_settle_frames = 0
			_phase = "settle"
			return false
		"settle":
			_settle_frames += 1
			if _settle_frames < SETTLE_FRAMES:
				return false
			_phase = "capture"
			return false
		"capture":
			_capture(WEAPON_SHOTS[_shot_index][0] as String)
			_shot_index += 1
			_phase = "equip"
			return false
		"pose_sprint_equip":
			var ids: Array[int] = [POSE_SHOT_WEAPON_ID, POSE_SHOT_WEAPON_ID]
			_weapon.server_set_loadout(ids)
			_settle_frames = 0
			_phase = "pose_sprint_settle"
			return false
		"pose_sprint_settle":
			_settle_frames += 1
			if _settle_frames < SETTLE_FRAMES:
				return false
			var sm = _player.get("state_machine")
			if sm:
				sm.transition_to("Sprint")
			_settle_frames = 0
			_phase = "pose_sprint_capture"
			return false
		"pose_sprint_capture":
			_settle_frames += 1
			if _settle_frames < POSE_SETTLE_FRAMES:
				return false
			_capture("fp_sprint")
			var sm2 = _player.get("state_machine")
			if sm2:
				sm2.transition_to("Idle")
			_phase = "pose_ads_settle"
			_settle_frames = 0
			return false
		"pose_ads_settle":
			var input_node = _player.get_node_or_null("Input")
			if input_node:
				input_node.aim_held = true
			_settle_frames += 1
			if _settle_frames < SETTLE_FRAMES:
				return false
			_phase = "pose_ads_capture"
			return false
		"pose_ads_capture":
			_capture("fp_ads")
			_finish()
			return false
	return false


func _start() -> bool:
	if _out_dir.is_empty():
		print("FP_SHOTS_FAIL --out requis")
		quit(1)
		return true
	var look: Node = load("res://scripts/core/LevelLook.gd").new()
	root.add_child(look)
	if not ResourceLoader.exists(LEVEL):
		return _fail("carte introuvable : %s" % LEVEL)
	var packed := load(LEVEL) as PackedScene
	var inst := packed.instantiate()
	if inst.get("agent_select") != null:
		inst.set("agent_select", false)
	root.add_child(inst)
	current_scene = inst
	print("FP_SHOTS_START level=%s" % LEVEL)
	return false


func _capture(name: String) -> void:
	var img := root.get_texture().get_image()
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	var path := "%s/%s.png" % [_out_dir, name]
	var err := img.save_png(path)
	print("FP_SHOT %s -> %s (err=%d)" % [name, path, err])


func _finish() -> void:
	print("FP_SHOTS_DONE")
	quit(0)


func _fail(reason: String) -> bool:
	print("FP_SHOTS_FAIL ", reason)
	quit(1)
	return true
