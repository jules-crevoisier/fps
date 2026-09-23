## prop_shots.gd
## Capture EN FENÊTRÉ (swapchain requis, comme tools/blender/viewmodel_shots.gd)
## tous les props de assets/models/props/manifest.json : pose chacun sur un
## plan de sol (sable pour le set "wasteland", pont métallique pour
## "cargo_ship"), applique Cartoon.painted(kind, tint) sur chaque slot si la
## méthode existe déjà (ajoutée en parallèle par un autre builder sur
## scripts/core/Cartoon.gd), sinon Cartoon.prop(couleur du slot) en repli.
## Sauve des vues d'ensemble (une par set) + des gros plans sur une sélection
## de props représentatifs, pour comparer au visuel aux références
## .orchestrator/refs/wasteland_*.png et cargo_ship_*.png.
##   godot --path . -s tools/prop_shots.gd -- --out=<dossier>
extends SceneTree

const MANIFEST_PATH := "res://assets/models/props/manifest.json"

# Teintes par kind — utilisées comme paramètre `tint` de Cartoon.painted() ET
# comme couleur de repli directe pour Cartoon.prop() si painted() n'existe pas
# encore.
const KIND_TINTS := {
	"painted_metal": Color("5c6b78"),
	"rust": Color("6b3821"),
	"corrugated": Color("8c8e91"),
	"container": Color("8c4d33"),
	"wood": Color("735230"),
	"sand": Color("c2a670"),
	"concrete": Color("9e9a8f"),
	"asphalt": Color("262628"),
	"ship_deck": Color("4d5761"),
	"rubber": Color("1a1a1c"),
	"glass": Color("8cb8c4"),
	"accent": Color("c73d24"),
	"sign": Color("dcd0a8"),
}

# Teintes de démonstration pour les 4 conteneurs bonus (montre le slot
# `container` tint-able en une seule fois, comme demandé par le brief).
const CONTAINER_TINTS := [Color("b0392b"), Color("2e5fa3"), Color("d68a1f"), Color("6f7880")]

# ATTENTION contrat : Cartoon.painted() (tel qu'atterri par le builder
# shaders/textures en parallèle) utilise des clés DIFFÉRENTES de celles du
# brief de cette tâche ("corrugated_metal" pas "corrugated", "container_paint"
# pas "container", "wood_planks" pas "wood", "sand_dirt" pas "sand",
# "cracked_concrete" pas "concrete", "rubber_tire" pas "rubber", "dirty_glass"
# pas "glass" — voir scripts/core/Cartoon.gd `_PAINTED`). Les noms de SLOT
# MATÉRIAU exportés par make_props.py restent ceux du brief verrouillé (pas
# à moi de retoucher unilatéralement le contrat ni Cartoon.gd) ; cette table
# ne sert qu'à faire un aperçu fidèle dans CE script de capture. Signalé
# comme blocker dans le rapport de tâche.
const PAINTED_KIND_ALIAS := {
	"corrugated": "corrugated_metal",
	"container": "container_paint",
	"wood": "wood_planks",
	"sand": "sand_dirt",
	"concrete": "cracked_concrete",
	"rubber": "rubber_tire",
	"glass": "dirty_glass",
}
# "accent"/"sign" ne sont pas des kinds texturés (couleur plate / panneau à
# lettrage) — jamais routés vers Cartoon.painted(), toujours Cartoon.prop().
const FLAT_KINDS := ["accent", "sign"]

# "accent" est VOLONTAIREMENT teinté par le placeur de props (le cactus n'a
# pas de kind "feuillage" dédié dans le contrat — voir make_props.py). Ici,
# juste pour que l'aperçu ressemble à quelque chose plutôt que "rouge partout" :
# override par nom de prop -> {kind: tint}.
const PROP_TINT_OVERRIDE := {
	"cactus": {"accent": Color("4f7942")},
	# Convention chantier naval : liséré de sécurité toujours jaune (pas
	# tintable par le placeur comme les autres usages d'"accent").
	"deck_hatch": {"accent": Color("e6c229")},
}

const CLOSEUP_WASTELAND := ["truck_wreck", "wooden_shack", "oil_derrick", "fuel_billboard", "water_tower", "gantry_crane",
	"shopfront_2_saloon", "shopfront_2_motel", "shopfront_corner_garage", "shopfront_1_store"]
const CLOSEUP_CARGO := ["container_20ft", "bridge_superstructure", "cargo_crane", "hull_mid", "lifeboat_davits",
	"container_stack3", "container_open20", "pipe_manifold"]

const MARGIN := 3.2
const GAP_BETWEEN_SETS := 14.0
const SETTLE_FRAMES_BUILD := 40
const SETTLE_FRAMES_SHOT := 20

var _out_dir: String = ""
var _started: bool = false
var _phase: String = "settle"
var _settle_frames: int = 0
var _shots: Array = []
var _shot_index: int = 0
var _cam: Camera3D = null
var _has_painted: bool = false
var _manifest_by_name: Dictionary = {}
var _cartoon_probe: Object = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		return _start()

	match _phase:
		"settle":
			_settle_frames += 1
			if _settle_frames < SETTLE_FRAMES_BUILD:
				return false
			_phase = "aim"
			return false
		"aim":
			if _shot_index >= _shots.size():
				print("PROP_SHOTS_DONE %d shots" % _shots.size())
				quit(0)
				return true
			var shot: Dictionary = _shots[_shot_index]
			_cam.global_position = shot["cam_pos"]
			_cam.look_at(shot["target"], Vector3.UP)
			_settle_frames = 0
			_phase = "wait"
			return false
		"wait":
			_settle_frames += 1
			if _settle_frames < SETTLE_FRAMES_SHOT:
				return false
			_phase = "capture"
			return false
		"capture":
			_capture(_shots[_shot_index]["name"] as String)
			_shot_index += 1
			_phase = "aim"
			return false
	return false


func _start() -> bool:
	if _out_dir.is_empty():
		print("PROP_SHOTS_FAIL --out requis")
		quit(1)
		return true

	# LevelLook DOIT être ajouté avant le WorldEnvironment/la lumière pour
	# capter leur `node_added` (voir tools/blender/viewmodel_shots.gd, même
	# ordre) — il stylise ciel/ambiance/lumière clé "encre et papier".
	var look: Node = load("res://scripts/core/LevelLook.gd").new()
	root.add_child(look)
	root.add_child(WorldEnvironment.new())
	root.add_child(DirectionalLight3D.new())

	_cartoon_probe = Cartoon.new()
	_has_painted = _cartoon_probe.has_method("painted")
	print("PROP_SHOTS_PAINTED_AVAILABLE %s" % _has_painted)

	var props: Array = _load_manifest()
	if props.is_empty():
		print("PROP_SHOTS_FAIL manifest vide ou introuvable")
		quit(1)
		return true
	for entry in props:
		_manifest_by_name[entry["name"]] = entry

	var by_set: Dictionary = {}
	for entry in props:
		var s: String = entry["set"]
		if not by_set.has(s):
			by_set[s] = []
		by_set[s].append(entry)

	var wasteland_layout := _layout(by_set.get("wasteland", []), 30.0, 0.0)
	var cargo_origin_x: float = (wasteland_layout["total_width"] as float) + GAP_BETWEEN_SETS
	var cargo_layout := _layout(by_set.get("cargo_ship", []), 34.0, cargo_origin_x)

	_add_ground(0.0, wasteland_layout["total_width"], wasteland_layout["total_depth"], "sand")
	_add_ground(cargo_origin_x, cargo_layout["total_width"], cargo_layout["total_depth"], "ship_deck")

	var wpos: Dictionary = wasteland_layout["positions"]
	for name in wpos:
		_spawn_prop(_manifest_by_name[name], wpos[name])
	var cpos: Dictionary = cargo_layout["positions"]
	for name in cpos:
		_spawn_prop(_manifest_by_name[name], cpos[name])

	_spawn_tinted_containers(cargo_origin_x, (cargo_layout["total_depth"] as float) + 3.0)

	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = 55.0
	root.add_child(_cam)

	_shots = _build_shot_list(wasteland_layout, cargo_layout, cargo_origin_x)
	_phase = "settle"
	_settle_frames = 0
	return false


func _load_manifest() -> Array:
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		return []
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if data == null or typeof(data) != TYPE_DICTIONARY or not data.has("props"):
		return []
	return data["props"]


## Rangement en étagères ("shelf packing") : place les props les uns après
## les autres sur une ligne, passe à la ligne suivante quand `max_row_width`
## est dépassée. Simple, déterministe, et n'écrase pas les petits props avec
## une cellule dimensionnée pour le plus grand (contrairement à une grille à
## cellule fixe — le conteneur 40 ft à lui seul ferait exploser une cellule
## uniforme).
func _layout(entries: Array, max_row_width: float, origin_x: float) -> Dictionary:
	var positions: Dictionary = {}
	var cursor_x := 0.0
	var cursor_z := 0.0
	var row_depth := 0.0
	for entry in entries:
		var fp: Dictionary = entry["footprint"]
		var w: float = float(fp["w"]) + MARGIN
		var d: float = float(fp["d"]) + MARGIN
		if cursor_x > 0.0 and cursor_x + w > max_row_width:
			cursor_x = 0.0
			cursor_z += row_depth
			row_depth = 0.0
		positions[entry["name"]] = Vector3(origin_x + cursor_x + w * 0.5, 0.0, cursor_z + d * 0.5)
		cursor_x += w
		row_depth = max(row_depth, d)
	return {"positions": positions, "total_width": max_row_width, "total_depth": cursor_z + row_depth}


func _material_for(kind: String, overrides: Dictionary = {}) -> Material:
	var tint: Color = overrides.get(kind, KIND_TINTS.get(kind, Color(0.6, 0.6, 0.6)))
	if _has_painted and not FLAT_KINDS.has(kind):
		# Appel dynamique (Object.call) : Cartoon.painted() est ajoutée en
		# parallèle par un autre builder — un appel statique `Cartoon.painted(...)`
		# ferait échouer l'analyse du script tant qu'elle n'existe pas encore.
		var mapped: String = PAINTED_KIND_ALIAS.get(kind, kind)
		return _cartoon_probe.call("painted", mapped, tint) as Material
	return Cartoon.prop(tint)


func _add_ground(origin_x: float, width: float, depth: float, kind: String) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width + 4.0, 0.2, depth + 4.0)
	mesh_inst.mesh = box
	root.add_child(mesh_inst)
	mesh_inst.position = Vector3(origin_x + width * 0.5, -0.1, depth * 0.5)
	mesh_inst.set_surface_override_material(0, _material_for(kind))


func _apply_materials(node: Node, slots: Array, overrides: Dictionary = {}) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		if mesh != null:
			for i in range(mesh.get_surface_count()):
				var kind: String = (slots[i] as String) if i < slots.size() else "accent"
				node.set_surface_override_material(i, _material_for(kind, overrides))
	for child in node.get_children():
		_apply_materials(child, slots, overrides)


func _apply_materials_tinted(node: Node, slots: Array, tint: Color) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		if mesh != null:
			for i in range(mesh.get_surface_count()):
				var kind: String = (slots[i] as String) if i < slots.size() else "accent"
				var use_tint: Color = tint if kind == "container" else KIND_TINTS.get(kind, Color(0.3, 0.3, 0.3))
				if _has_painted and not FLAT_KINDS.has(kind):
					var mapped: String = PAINTED_KIND_ALIAS.get(kind, kind)
					node.set_surface_override_material(i, _cartoon_probe.call("painted", mapped, use_tint) as Material)
				else:
					node.set_surface_override_material(i, Cartoon.prop(use_tint))
	for child in node.get_children():
		_apply_materials_tinted(child, slots, tint)


func _spawn_prop(entry: Dictionary, pos: Vector3) -> void:
	var packed: PackedScene = load(entry["path"])
	if packed == null:
		print("PROP_SHOTS_WARN cannot load %s" % str(entry["path"]))
		return
	var inst := packed.instantiate()
	root.add_child(inst)
	inst.position = pos
	var overrides: Dictionary = PROP_TINT_OVERRIDE.get(entry["name"], {})
	_apply_materials(inst, entry["slots"], overrides)


## Démonstration du slot `container` tint-able : 4 exemplaires de
## container_20ft (2x2, empilés) avec 4 teintes différentes — montre que le
## même .glb sert à toute la variété de couleurs vues dans la référence
## cargo_ship_sheet.png sans ré-exporter de géométrie.
func _spawn_tinted_containers(origin_x: float, origin_z: float) -> void:
	var entry: Dictionary = _manifest_by_name.get("container_20ft", {})
	if entry.is_empty():
		return
	for i in range(CONTAINER_TINTS.size()):
		var packed: PackedScene = load(entry["path"])
		if packed == null:
			continue
		var inst := packed.instantiate()
		root.add_child(inst)
		var col := i % 2
		var row := int(i / 2)
		inst.position = Vector3(origin_x + col * 2.9, row * 2.59, origin_z)
		_apply_materials_tinted(inst, entry["slots"], CONTAINER_TINTS[i])


func _overview_shot(name: String, center: Vector3, span: float) -> Dictionary:
	# Toute façade/panneau de la bibliothèque a sa face "avant" détaillée
	# tournée vers -Z (convention établie dans make_props.py : textes/portes/
	# fenêtres posés à `wall_face_z` négatif). Une caméra qui approche par +Z
	# ne voit que des dos plats — on approche donc par -X/-Z.
	var dist: float = span * 0.9 + 6.0
	var cam_pos := center + Vector3(-dist * 0.55, dist * 0.6, -dist * 0.55)
	return {"name": name, "cam_pos": cam_pos, "target": center + Vector3(0.0, 1.0, 0.0)}


func _closeup_shot(name: String, pos: Vector3) -> Dictionary:
	var entry: Dictionary = _manifest_by_name.get(name, {})
	var fp: Dictionary = entry.get("footprint", {"w": 1.0, "d": 1.0, "h": 1.0})
	var w: float = float(fp["w"])
	var d: float = float(fp["d"])
	var h: float = float(fp["h"])
	var span: float = max(w, max(d, h))
	var dist: float = span * 1.15 + 1.5
	var target := pos + Vector3(0.0, h * 0.5, 0.0)
	# Approche par -X/-Z (face avant), voir remarque ci-dessus sur _overview_shot.
	var cam_pos := target + Vector3(-dist * 0.6, dist * 0.45, -dist * 0.6)
	return {"name": "closeup_%s" % name, "cam_pos": cam_pos, "target": target}


func _build_shot_list(wasteland_layout: Dictionary, cargo_layout: Dictionary, cargo_origin_x: float) -> Array:
	var shots: Array = []
	var ww: float = wasteland_layout["total_width"]
	var wd: float = wasteland_layout["total_depth"]
	shots.append(_overview_shot("overview_wasteland", Vector3(ww * 0.5, 0.0, wd * 0.5), max(ww, wd)))
	var cw: float = cargo_layout["total_width"]
	var cd: float = cargo_layout["total_depth"]
	shots.append(_overview_shot("overview_cargo", Vector3(cargo_origin_x + cw * 0.5, 0.0, cd * 0.5), max(cw, cd)))

	var wpos: Dictionary = wasteland_layout["positions"]
	for prop_name in CLOSEUP_WASTELAND:
		if wpos.has(prop_name):
			shots.append(_closeup_shot(prop_name, wpos[prop_name]))
	var cpos: Dictionary = cargo_layout["positions"]
	for prop_name in CLOSEUP_CARGO:
		if cpos.has(prop_name):
			shots.append(_closeup_shot(prop_name, cpos[prop_name]))
	return shots


func _capture(name: String) -> void:
	var img := root.get_texture().get_image()
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	var path := "%s/%s.png" % [_out_dir, name]
	var err := img.save_png(path)
	print("PROP_SHOT %s -> %s (err=%d)" % [name, path, err])
