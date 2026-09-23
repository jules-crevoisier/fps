## PropCatalog.gd
## Catalogue de props (.orchestrator/maps-spec-v2.md §3.1/§7.1) : charge
## `assets/models/props/manifest.json` (texte brut + JSON.parse — le fichier
## n'est pas forcément importé comme ressource Godot), résout les noms de la
## TABLE DU SPEC vers les fichiers RÉELS du manifeste (`ALIASES` — "Prop names
## may drift from the builder's files. PropCatalog aliases absorb this"),
## instancie le `.glb`, peint chaque surface via `Cartoon.painted_for_slot`
## (un slot du manifeste par surface, dans l'ordre — convention du pipeline
## d'export), et pose la collision (boîtes du manifeste, ou une boîte unique
## de repli). Un nom SANS fichier .glb (spec sans équivalent construit, ou
## test headless sans assets) retombe sur une boîte peinte plate dans la
## teinte demandée : aucun test n'a besoin d'un `.glb` pour passer.
class_name PropCatalog
extends RefCounted

const MANIFEST_PATH := "res://assets/models/props/manifest.json"

## Table du spec (§3.1) -> nom réel du manifeste (assets/models/props/**).
## Un nom absent d'ici est cherché TEL QUEL dans le manifeste ensuite (les
## deux vocabulaires marchent : `info("sedan_wreck")` et
## `info("car_sedan_wreck")` renvoient la même entrée).
const ALIASES: Dictionary = {
	"container_20": "container_20ft",
	"container_40": "container_40ft",
	"container_20_open": "container_20ft",
	"container_40_open": "container_40ft",
	"crate_2": "wooden_crate",
	"crate_low": "wooden_crate",
	"crate_stack": "wooden_crate",
	"barrel_cluster": "oil_drum",
	"barrel": "oil_drum",
	"pallet_stack": "pallet",
	"sandbag_wall": "sandbags",
	"hatch_cover": "hatch_cover",
	"deck_crane": "cargo_crane",
	"ship_hull": "hull_mid",
	"ship_bridge_dress": "bridge_superstructure",
	"ship_mast": "mast_antennas",
	"ship_railing": "deck_railing",
	"lifeboat": "lifeboat_davits",
	"fuel_pump": "fuel_pump",
	"sign_fuel": "fuel_billboard",
	"sign_gas": "gas_billboard",
	"shack_awning": "wooden_shack",
	"shack_roof_peak": "wooden_shack",
	"pipe_run": "pipe_straight",
	"pipe_manifold": "pipe_valve",
	"crane_lattice": "gantry_crane",
	"car_sedan_wreck": "sedan_wreck",
	"car_pickup_wreck": "truck_wreck",
	"tanker_wreck": "truck_wreck",
	"rock_cluster": "rock_medium",
	# Sans équivalent construit (§9 "Prop names... unknown names fail §8.15" —
	# ici on choisit sciemment de retomber sur la boîte de repli plutôt que
	# d'échouer un test, la pièce Kit garde alors sa peinture normale) :
	# windlass, canopy_station, tank_horizontal, tank_skid, bus_wreck,
	# freight_wagon, stagecoach.
}

static var _manifest: Dictionary = {}   # nom manifeste -> entrée brute (dict JSON)
static var _loaded := false
static var _scene_cache: Dictionary = {}  # chemin -> PackedScene (ou null si absent)
static var _mesh_cache: Dictionary = {}    # nom manifeste -> Mesh (extrait une fois, pour le MultiMesh)

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	for p in (parsed.get("props", []) as Array):
		if p is Dictionary and p.has("name"):
			_manifest[String(p["name"])] = p

## Toutes les entrées connues : les alias du spec (§3.1) et les noms bruts du
## manifeste (les deux vocabulaires sont valides pour `info()`/`place()`).
static func names() -> PackedStringArray:
	_ensure_loaded()
	var out := PackedStringArray()
	for k in ALIASES.keys():
		out.append(k)
	for k in _manifest.keys():
		if not out.has(k):
			out.append(k)
	return out

## {name, manifest_name, path, size (w,h,d), cover, thin, collision, slots}.
## `manifest_name`/`path` vides si aucun `.glb` n'existe pour ce nom (repli
## boîte peinte — `place()` reste sans erreur, `size` vaut alors 1x1x1).
static func info(prop: String) -> Dictionary:
	_ensure_loaded()
	var manifest_name := String(ALIASES.get(prop, prop))
	var entry: Dictionary = _manifest.get(manifest_name, {})
	if entry.is_empty():
		return {"name": prop, "manifest_name": "", "path": "", "size": Vector3.ONE, "cover": true, "thin": false, "collision": [], "slots": []}
	var fp: Dictionary = entry.get("footprint", {})
	var size := Vector3(float(fp.get("w", 1.0)), float(fp.get("h", 1.0)), float(fp.get("d", 1.0)))
	return {
		"name": prop, "manifest_name": manifest_name, "path": String(entry.get("path", "")),
		"size": size, "cover": true, "thin": bool(entry.get("thin", false)),
		"collision": (entry.get("collision", []) as Array), "slots": (entry.get("slots", []) as Array),
	}

## Empreinte w×h×d (mètres) d'un prop, pour dimensionner une collision Kit
## (`skin`) ou vérifier une échelle (§8.15 : "skin scale is 0.8-1.25 per axis").
static func footprint(prop: String) -> Vector3:
	return (info(prop) as Dictionary)["size"]

static func _load_scene(path: String) -> PackedScene:
	if path == "":
		return null
	if _scene_cache.has(path):
		return _scene_cache[path]
	var packed: PackedScene = null
	if ResourceLoader.exists(path):
		packed = load(path) as PackedScene
	_scene_cache[path] = packed
	return packed

static func _find_mesh_instances(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		_find_mesh_instances(child, out)

## Peint chaque SURFACE via le nom de matériau glTF d'ORIGINE, survécu à
## l'import comme `Material.resource_name` (scripts/dev/PropKit.gd l'a
## vérifié empiriquement sur plusieurs .glb réels : ce nom correspond TOUJOURS
## à un slot du manifeste, ex. "painted_metal"/"rust"/"sign"). Remplace
## l'ancien appariement PAR ORDRE (fragile : suppose que l'ordre de parcours
## des surfaces == l'ordre de la liste `slots` du manifeste, aucune garantie
## réelle) par un appariement PAR NOM, robuste à l'ordre. `tints` (facultatif) :
## une teinte PAR SLOT (ex. {"container": CONTAINER_RED, "accent": WHITE}) —
## un slot absent de `tints` retombe sur `tint` (le réglage uniforme
## existant). Une surface dont le matériau n'a pas de `resource_name` garde
## son matériau importé tel quel (sûr, jamais un crash).
static func _paint_slots(inst: Node, tint: Color, tints: Dictionary = {}) -> void:
	if inst is MeshInstance3D and (inst as MeshInstance3D).mesh:
		var mi := inst as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src_mat := mi.mesh.surface_get_material(s)
			var slot := String(src_mat.resource_name) if src_mat else ""
			if slot.is_empty():
				continue
			var slot_tint: Color = tints.get(slot, tint)
			mi.set_surface_override_material(s, Cartoon.painted_for_slot(slot, slot_tint))
	for c in inst.get_children():
		_paint_slots(c, tint, tints)

static func _add_box_collision(parent: Node3D, size: Vector3, center: Vector3, nm: String = "Col") -> void:
	var body := StaticBody3D.new()
	body.name = nm
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = center
	body.add_child(col)
	parent.add_child(body)

## Instancie `prop` (nom du spec OU du manifeste) sous `parent`, à `pos`
## (contact au sol — voir maps-spec-v2.md §2 "pos (floor contact)"), tourné
## de `rot_y_deg`, peint en `tint`. `collide=false` (props `visual`/`dress`) ne
## pose aucune collision. Renvoie la racine (Node3D) créée.
##
## `fallback_size` (7e paramètre, ADDITIF — la signature à 6 args ci-dessus
## reste le contrat figé consommé par l'autre chantier) : taille à utiliser
## pour la boîte de repli SI ET SEULEMENT SI `prop` n'a pas de `.glb` (§7.1).
## Sans elle, le repli valait toujours Vector3.ONE (1x1x1) quel que soit
## l'appelant — correct pour un `prop` autonome, mais un `skin` (Kit.gd,
## `build_piece`) pose sa PROPRE collision à la taille de sa boîte Kit tout
## en appelant `place()` juste pour l'aspect visuel (`collide=false`) : sans
## ce paramètre, un skin non catalogué (windlass, tank_horizontal…) rendait
## un cube minuscule flottant dans/à côté de sa vraie collision.
##
## `tints` (8e paramètre, ADDITIF) : teintes PAR SLOT (voir `_paint_slots`) —
## {} (défaut) reproduit l'ancien comportement (tout au `tint` uniforme).
static func place(parent: Node3D, prop: String, pos: Vector3, rot_y_deg: float = 0.0, tint: Color = Color.WHITE, collide: bool = true, fallback_size: Vector3 = Vector3.ZERO, tints: Dictionary = {}) -> Node3D:
	var data := info(prop)
	var size: Vector3 = data["size"]
	var root := Node3D.new()
	root.name = "Prop_%s" % prop
	root.position = pos
	root.rotation.y = deg_to_rad(rot_y_deg)
	parent.add_child(root)

	var packed := _load_scene(String(data["path"]))
	if packed != null:
		var inst := packed.instantiate()
		root.add_child(inst)
		_paint_slots(inst, tint, tints)
		if collide:
			# ATTENTION à l'ordre : "size" du manifeste est [w,d,h] (même ordre
			# que "footprint" — voir tools/blender/make_props.py::_bbox_collision),
			# PAS le [x,y,z]=[w,h,d] de Godot ; "center", lui, EST déjà [x,y,z].
			# Vérifié contre le générateur : mélanger les deux inverse hauteur et
			# profondeur de la collision.
			var cols: Array = data["collision"]
			if cols.is_empty():
				_add_box_collision(root, size, Vector3(0, size.y * 0.5, 0))
			else:
				var i := 0
				for c in cols:
					var cd: Dictionary = c
					var csize: Array = cd["size"]
					var ccenter: Array = cd["center"]
					_add_box_collision(root, Vector3(csize[0], csize[2], csize[1]), Vector3(ccenter[0], ccenter[1], ccenter[2]), "Col%d" % i)
					i += 1
	else:
		# Repli : boîte peinte plate — aucun `.glb`, les tests headless n'en ont
		# jamais besoin (§7.1). `fallback_size` (appelant `skin`) prime sur la
		# taille générique du catalogue pour cette boîte de repli.
		var use_size: Vector3 = fallback_size if fallback_size != Vector3.ZERO else size
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = use_size
		mesh.mesh = bm
		mesh.position = Vector3(0, use_size.y * 0.5, 0)
		mesh.material_override = Cartoon.world(tint)
		root.add_child(mesh)
		if collide:
			_add_box_collision(root, use_size, Vector3(0, use_size.y * 0.5, 0))
	return root

## Extrait (et met en cache) le PREMIER Mesh trouvé dans le `.glb` de `prop`,
## pour `place_many()` (MultiMeshInstance3D — un seul maillage/matériau
## partagé par instance). `null` si le prop n'a pas de `.glb` (repli boîte).
static func _mesh_for(prop: String) -> Mesh:
	var data := info(prop)
	var manifest_name: String = data["manifest_name"]
	if manifest_name == "":
		return null
	if _mesh_cache.has(manifest_name):
		return _mesh_cache[manifest_name]
	var packed := _load_scene(String(data["path"]))
	var mesh: Mesh = null
	if packed != null:
		var inst := packed.instantiate()
		var meshes: Array = []
		_find_mesh_instances(inst, meshes)
		if not meshes.is_empty():
			mesh = (meshes[0] as MeshInstance3D).mesh
		inst.free()
	_mesh_cache[manifest_name] = mesh
	return mesh

## Pose PLUSIEURS instances de `prop` (§7.3/§8.17 : "every prop used 3 or more
## times is a MultiMesh") : >= 3 transforms ET un `.glb` réel -> UN
## MultiMeshInstance3D (un draw call) pour le VISUEL, + une collision
## individuelle par transform si `collide`. En dessous de 3, ou sans `.glb`,
## retombe sur `place()` par transform (comportement identique, juste pas
## fusionné).
static func place_many(parent: Node3D, prop: String, transforms: Array, tint: Color = Color.WHITE, collide: bool = true) -> void:
	var mesh := _mesh_for(prop)
	if mesh == null or transforms.size() < 3:
		for t in transforms:
			var xf: Transform3D = t
			place(parent, prop, xf.origin, rad_to_deg(xf.basis.get_euler().y), tint, collide)
		return
	var data := info(prop)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Batch_%s" % prop
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	mmi.multimesh = mm
	var slots: Array = data["slots"]
	if not slots.is_empty():
		mmi.material_override = Cartoon.painted_for_slot(String(slots[0]), tint)
	parent.add_child(mmi)
	if collide:
		var size: Vector3 = data["size"]
		var cols: Array = data["collision"]
		var i2 := 0
		for t in transforms:
			var xf: Transform3D = t
			var body := StaticBody3D.new()
			body.name = "%sCol%d" % [prop, i2]
			body.transform = xf
			if cols.is_empty():
				var col := CollisionShape3D.new()
				var shape := BoxShape3D.new()
				shape.size = size
				col.position = Vector3(0, size.y * 0.5, 0)
				col.shape = shape
				body.add_child(col)
			else:
				for c in cols:
					var cd: Dictionary = c
					var csize: Array = cd["size"]
					var ccenter: Array = cd["center"]
					var col2 := CollisionShape3D.new()
					var shape2 := BoxShape3D.new()
					shape2.size = Vector3(csize[0], csize[2], csize[1])
					col2.position = Vector3(ccenter[0], ccenter[1], ccenter[2])
					col2.shape = shape2
					body.add_child(col2)
			parent.add_child(body)
			i2 += 1
