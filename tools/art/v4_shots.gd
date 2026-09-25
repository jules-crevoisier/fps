## v4_shots.gd
## ART-91 (docs/art/WASTELAND_V4_ART_PLAN.md §6 "tâches" : « Captures (JPG
## <= 1600 px) dans reports/checkpoints/<date>_<id>/, vues nommées définies
## par ART-91 (tools/art/data/wasteland_v4_views.json) : V1 Grand-Rue O depuis
## le spawn bleu ... V12 ciel nord depuis la Place. Aucun fichier n'est
## partagé par deux tâches d'une même vague. ») — CE fichier est la source
## unique des 12 poses nommées (position + cible), calculées depuis la
## géométrie RÉELLE de `WastelandLayout.data()` (jamais des coordonnées
## recopiées à la main : si `wasteland.gd` bouge, ces vues suivent), avec un
## raycast anti-caméra-dans-le-mur (même technique que `tools/map_shots.gd`,
## fichier voisin non modifié — dupliquée ici en toute sécurité plutôt que
## composée, `map_shots.gd` étant lui-même un point d'entrée `SceneTree`, pas
## une bibliothèque).
##
## EN FENÊTRÉ (pas headless : il faut un vrai swapchain, comme
## `tools/screenshot.gd`/`tools/map_shots.gd`) :
##
##   godot --path . -s res://tools/art/v4_shots.gd -- \
##       [--out=C:/dossier/] [--views=V11] [--wait=N]
##
## TOUJOURS écrit `tools/art/data/wasteland_v4_views.json` (les 12 poses,
## consommées telles quelles par ART-94..100 pour LEURS propres captures) ;
## capture ensuite un PNG par nom de `--views=` (défaut : `V11` seul — la
## capture imposée par le critère d'acceptation de cette tâche, "ouvertures
## JSON sur V11"). Écrit "<out>/wasteland_<vue>.png" par capture, imprime
## `V4_SHOT <vue> <chemin>` par capture puis `V4_SHOTS_DONE` et quitte (0), ou
## `V4_SHOTS_FAIL <raison>` (1).
extends SceneTree

const _LEVEL_LOOK_SCRIPT := preload("res://scripts/core/LevelLook.gd")
const _INK_POST_SCRIPT := preload("res://scripts/core/InkPost.gd")
const SCENE_PATH := "res://scenes/levels/maps/wasteland.tscn"
const VIEWS_OUT_PATH := "res://tools/art/data/wasteland_v4_views.json"
const DEFAULT_SHOTS_OUT := "res://reports/checkpoints/_v4_shots"
const DEFAULT_WAIT_FRAMES := 50
## Ordre d'affichage dans le JSON (§6 du plan d'art, V1..V12) — purement
## cosmétique (un Dictionary JSON n'a pas d'ordre garanti à la relecture),
## utile seulement pour un `git diff` lisible sur `wasteland_v4_views.json`.
const VIEW_ORDER: PackedStringArray = ["V1", "V2", "V3", "V4", "V5", "V6", "V7", "V8", "V9", "V10", "V11", "V12"]
## `top_ortho`/V11 (même convention que `tools/map_shots.gd`) : sous la quasi-
## totalité des toits à un étage, pour lire les ouvertures au sol.
const ROOFLESS_CUTOFF_Y := 3.0

var _out_dir: String = DEFAULT_SHOTS_OUT
var _wait_frames: int = DEFAULT_WAIT_FRAMES
var _views_filter: PackedStringArray = ["V11"]

var _poses_by_name: Dictionary = {}
var _order: Array[String] = []
var _pose_index: int = 0
var _frame: int = 0
var _started: bool = false
var _failed: bool = false
var _cam: Camera3D
var _scene_inst: Node


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)
		elif a.begins_with("--wait="):
			_wait_frames = int(a.get_slice("=", 1))
		elif a.begins_with("--views="):
			_views_filter = a.get_slice("=", 1).split(",")


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		return _start()
	if _failed:
		return true
	if _cam:
		_cam.current = true
	_ensure_ink_post()
	_frame += 1
	if _frame < _wait_frames:
		return false
	_capture_current()
	return _advance()


func _start() -> bool:
	var look: Node = _LEVEL_LOOK_SCRIPT.new()
	root.add_child(look)
	MatchConfig.map_id = "wasteland"
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		return _fail("scène introuvable : %s" % SCENE_PATH)
	var inst := packed.instantiate()
	if inst.get("agent_select") != null:
		inst.set("agent_select", false)
	if inst.get("allow_bot_fill") != null:
		inst.set("allow_bot_fill", false)
	root.add_child(inst)
	_scene_inst = inst
	current_scene = inst
	_hide_hud(inst)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.current = true

	_poses_by_name = _build_poses()
	_write_views_json()
	for nm in _views_filter:
		if _poses_by_name.has(nm):
			_order.append(nm)
	if _order.is_empty():
		return _fail("aucune vue valide dans --views= (%s) — noms attendus : V1..V12" % [",".join(_views_filter)])
	_pose_index = 0
	_apply_pose(_poses_by_name[_order[0]])
	return false


func _hide_hud(inst: Node) -> void:
	for nm in ["HUD", "PauseMenu", "BuyMenu"]:
		var n := inst.get_node_or_null(nm)
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false


func _ensure_ink_post() -> void:
	if _cam and _cam.get_node_or_null("InkPost") == null:
		var post := _INK_POST_SCRIPT.new()
		post.name = "InkPost"
		_cam.add_child(post)


# ======================================================================
#  Raycast anti-caméra-dans-la-géométrie (même méthode que
#  `tools/map_shots.gd::_raycast_clamp`, dupliquée ici — voir l'en-tête).
# ======================================================================
func _raycast_clamp(anchor: Vector3, target: Vector3, margin: float = 0.4) -> Vector3:
	var world := root.get_world_3d()
	if world == null:
		return anchor
	var space := world.direct_space_state
	if space == null:
		return anchor
	var dir := target - anchor
	var dist := dir.length()
	if dist < 0.05:
		return anchor
	dir /= dist
	var params := PhysicsRayQueryParameters3D.create(anchor, target)
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var result := space.intersect_ray(params)
	if result.is_empty():
		return target
	var hit_pos: Vector3 = result["position"]
	var hit_dist := anchor.distance_to(hit_pos)
	var safe_dist := maxf(hit_dist - margin, 0.1)
	return anchor + dir * safe_dist


func _walk_pose(nm: String, anchor: Vector3, dir_hint: Vector3, eye_h: float, advance: float, look_dist: float, look_y: float = INF) -> Dictionary:
	var d := dir_hint
	d.y = 0
	d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	var eye_anchor := anchor + Vector3(0, eye_h, 0)
	var candidate := eye_anchor + d * advance
	var safe_pos := _raycast_clamp(eye_anchor, candidate)
	var look_at_pt := eye_anchor + d * look_dist
	if look_y != INF:
		look_at_pt.y = look_y
	return {"name": nm, "pos": safe_pos, "look": look_at_pt}


func _piece(data: Dictionary, piece_name: String) -> Dictionary:
	for piece in (data.get("pieces", []) as Array):
		if String((piece as Dictionary).get("name", "")) == piece_name:
			return piece
	return {}


func _piece_pos(data: Dictionary, piece_name: String, fallback: Vector3) -> Vector3:
	var piece := _piece(data, piece_name)
	return piece.get("pos", fallback) if not piece.is_empty() else fallback


func _piece_size(data: Dictionary, piece_name: String, fallback: Vector3) -> Vector3:
	var piece := _piece(data, piece_name)
	return piece.get("size", fallback) if not piece.is_empty() else fallback


# ======================================================================
#  Les 12 vues nommées (docs/art/WASTELAND_V4_ART_PLAN.md §6) — poses
#  calculées depuis `WastelandLayout.data()` réelle, jamais recopiées.
# ======================================================================
func _build_poses() -> Dictionary:
	var data := WastelandLayout.data()
	var bounds: Dictionary = data["bounds"]
	var mn: Vector2 = bounds["min"]
	var mx: Vector2 = bounds["max"]
	var out: Dictionary = {}

	# V1/V2 : Grand-Rue depuis chaque spawn d'équipe, vers le centre (§5 "①
	# Grand-Rue", segment droit x -39..-3 côté ouest).
	var sp0: Dictionary = data["spawns"][0][0]
	var sp1: Dictionary = data["spawns"][1][0]
	var team0: Vector3 = sp0["pos"]
	var team1: Vector3 = sp1["pos"]
	var look0: Vector3 = sp0.get("look", team0)
	var look1: Vector3 = sp1.get("look", team1)
	out["V1"] = _walk_pose("V1", team0, look0 - team0, 1.6, 3.0, 35.0)
	out["V2"] = _walk_pose("V2", team1, look1 - team1, 1.6, 3.0, 35.0)

	# V3 : fenêtre PP1 (Hôtel, façade sud, étage 1, §6 "PP1 Hôtel... fenêtres
	# sud sur la Grand-Rue") — vue de rue qui cadre la façade/la fenêtre.
	var hotel_pos := _piece_pos(data, "Hotel", Vector3(-21, 3.2, -22))
	var hotel_size := _piece_size(data, "Hotel", Vector3(10, 6.4, 6))
	var v3_anchor := Vector3(hotel_pos.x, 0.0, hotel_pos.z - hotel_size.z * 0.5 - 6.0)
	out["V3"] = _walk_pose("V3", v3_anchor, Vector3(0, 0, 1), 1.6, 3.0, 12.0, hotel_pos.y + 1.5)

	# V4 : galerie PP3 (SaloonW, `BalconW`, §6 "Galerie 2x8 m face à la
	# place") — depuis la dalle extérieure de la galerie, vers la place.
	var balcon_pos := _piece_pos(data, "BalconW", Vector3(-7, 3.075, -5))
	var balcon_size := _piece_size(data, "BalconW", Vector3(2, 0.25, 8))
	var v4_anchor := Vector3(balcon_pos.x, balcon_pos.y + balcon_size.y * 0.5, balcon_pos.z)
	out["V4"] = _walk_pose("V4", v4_anchor, Vector3(1, 0, 0.3), 1.6, 2.0, 35.0, 0.0)

	# V5 : la place depuis la Descente (§5 "Descente" (0;0;8)->(0;-2;13),
	# §9) — anchor au sommet de la rampe (bord de la place), vers le nord.
	out["V5"] = _walk_pose("V5", Vector3(0, 0, 9.5), Vector3(0, 0, -1), 1.6, 4.0, 20.0)

	# V6 : intérieur Échoppes (§5 "② Intérieurs... Échoppes 14x14 m, deux
	# salles de 7 m, 5 portes") — entre par la porte nord, regarde le fond.
	var echoppes_pos := _piece_pos(data, "EchoppesW", Vector3(-27, 1.8, -2))
	var echoppes_size := _piece_size(data, "EchoppesW", Vector3(14, 3.6, 14))
	var v6_anchor := Vector3(echoppes_pos.x - 4.0, 0.0, echoppes_pos.z - echoppes_size.z * 0.5 + 1.0)
	out["V6"] = _walk_pose("V6", v6_anchor, Vector3(0, 0, 1), 1.6, 3.0, 10.0)

	# V7 : Ruelle O (§5 "Ruelle : allée nord-sud de 4 m", entre EchoppesW et
	# SaloonW) — même corridor que `map_shots.gd::_wasteland_poses`
	# "interieurs" (repère indépendant, recalculé depuis les mêmes pièces).
	var saloon_pos := _piece_pos(data, "SaloonW", Vector3(-12, 3.2, -3))
	var saloon_size := _piece_size(data, "SaloonW", Vector3(8, 6.4, 16))
	var ruelle_x := ((echoppes_pos.x + echoppes_size.x * 0.5) + (saloon_pos.x - saloon_size.x * 0.5)) * 0.5
	var v7_anchor := Vector3(ruelle_x, 0.0, echoppes_pos.z - echoppes_size.z * 0.5 + 1.0)
	out["V7"] = _walk_pose("V7", v7_anchor, Vector3(0, 0, 1), 1.6, 5.0, 18.0)

	# V8 : canyon depuis RampeCanyonW1 (§5 "③ Canyon", rampe le long de la
	# paroi nord) — au pied de la rampe, regarde vers l'est (le Gué central).
	var ramp_end := Vector3(-34, -2, 13)
	out["V8"] = _walk_pose("V8", ramp_end, Vector3(1, 0, 0), 1.6, 2.0, 22.0)

	# V9 : arrière-cours et rails (§3 "Rails"/§9 "CaissesQuaiW... ChariotMineW",
	# transition ②->③, z 5..12) — vue depuis le quai vers l'ouest (Remise,
	# Cuve, Chariot de mine).
	var quai_pos := _piece_pos(data, "CaissesQuaiW", Vector3(-19, 1, 10))
	out["V9"] = _walk_pose("V9", Vector3(quai_pos.x + 4.0, 0.0, quai_pos.z), Vector3(-1, 0, 0), 1.6, 3.0, 20.0)

	# V10 : aérienne SO (coin sud-ouest, hors géométrie — pas de raycast
	# nécessaire, même formule que `tools/map_shots.gd::_aerial_poses`).
	var center := Vector3((mn.x + mx.x) * 0.5, 0, (mn.y + mx.y) * 0.5)
	var span: float = maxf(mx.x - mn.x, mx.y - mn.y)
	var aerial_pos := center + Vector3(-1, 0, 1).normalized() * (span * 0.7) + Vector3(0, span * 0.5, 0)
	out["V10"] = {"name": "V10", "pos": aerial_pos, "look": center}

	# V11 : ortho (plan du dessus, sans toits — critère d'acceptation "capture :
	# ouvertures JSON sur V11", même formule que
	# `tools/map_shots.gd::_ortho_top_poses`, dupliquée ici).
	var span_z: float = mx.y - mn.y
	var cam_y := 60.0
	out["V11"] = {
		"name": "V11", "pos": Vector3(center.x, cam_y, center.z), "look": Vector3(center.x, 0.0, center.z),
		"up": Vector3(0, 0, -1), "ortho_size": span_z / 0.80, "near": cam_y - ROOFLESS_CUTOFF_Y,
	}

	# V12 : ciel nord depuis la Place (§8 "deux repères de rang 1 visibles
	# au-dessus des toits : la grue... et le derrick") — au sud-est du Wagon
	# (hors de son empreinte, x -6..6/z -2.5..0.5, §9), regard au nord (le
	# ciel/la ligne des toits, pas le sol).
	out["V12"] = _walk_pose("V12", Vector3(9.0, 0, 4.0), Vector3(0, 0, -1), 1.6, 2.0, 30.0, 10.0)

	return out


func _apply_pose(pose: Dictionary) -> void:
	_cam.global_position = pose["pos"]
	_cam.look_at(pose["look"], pose.get("up", Vector3.UP))
	if pose.has("ortho_size"):
		_cam.keep_aspect = Camera3D.KEEP_HEIGHT
		_cam.set_orthogonal(float(pose["ortho_size"]), float(pose.get("near", 0.05)), 4000.0)
	else:
		_cam.set_perspective(75.0, 0.05, 4000.0)
	_cam.current = true


func _write_views_json() -> void:
	var doc: Dictionary = {
		"generated_by": "tools/art/v4_shots.gd",
		"source": "scripts/levels/maps/layouts/wasteland.gd (WastelandLayout.data())",
		"views": {},
	}
	var views: Dictionary = doc["views"]
	for nm in VIEW_ORDER:
		if not _poses_by_name.has(nm):
			continue
		var p: Dictionary = _poses_by_name[nm]
		var entry := {"pos": [p["pos"].x, p["pos"].y, p["pos"].z], "look": [p["look"].x, p["look"].y, p["look"].z]}
		if p.has("ortho_size"):
			entry["ortho_size"] = p["ortho_size"]
			entry["near"] = p["near"]
			entry["up"] = [p["up"].x, p["up"].y, p["up"].z]
		views[nm] = entry
	var abs_dir := ProjectSettings.globalize_path(VIEWS_OUT_PATH).get_base_dir()
	if abs_dir != "" and not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var f := FileAccess.open(VIEWS_OUT_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "  "))
	f.close()


func _capture_current() -> void:
	if _cam:
		_cam.current = true
	_ensure_ink_post()
	var nm := _order[_pose_index]
	var out_path := "%s/wasteland_%s.png" % [_out_dir, nm]
	var img := root.get_texture().get_image()
	var dir := out_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := img.save_png(out_path)
	if err != OK:
		_fail("échec écriture PNG (%d) : %s" % [err, out_path])
		return
	print("V4_SHOT ", nm, " ", out_path)


func _advance() -> bool:
	_pose_index += 1
	_frame = 0
	if _pose_index >= _order.size():
		print("V4_SHOTS_DONE")
		quit(0)
		return true
	_apply_pose(_poses_by_name[_order[_pose_index]])
	return false


func _fail(reason: String) -> bool:
	print("V4_SHOTS_FAIL ", reason)
	_failed = true
	quit(1)
	return true
