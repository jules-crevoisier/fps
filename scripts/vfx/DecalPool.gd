## DecalPool.gd
## Pool PARTAGÉ de décalques plats (STYLE_BIBLE.md §9.1 #6 : "décalques en
## pool de 64 (FIFO), durée de vie 8 s, fondu de 1 s" ; docs/style/tokens.json
## "vfx.decals") — généralise le pool round-robin qu'ImpactFx.gd (GF-06)
## posait déjà pour SA seule tache d'encre plate : ici, un pool UNIQUE
## partagé par tout décalque texturé (étoile d'impact, brûlure, fissure, ...),
## quel qu'en soit le type, réutilisant l'atlas déjà encré livré par ART-04
## (assets/textures/decals/decal_atlas.png{,.json} — "rgb = fill(shape,
## hexc(INK))", tools/textures/gen_textures.py : ces décalques SONT de
## l'encre, pas une texture à teinter/contourer nous-mêmes).
##
## FIFO comme `ImpactFx._acquire` (GF-06) : les MAX_POOL premiers appels
## créent une instance, les suivants réutilisent la plus ancienne (round-
## robin sur `_next_slot`) plutôt que d'empiler des nœuds sans limite pendant
## une rafale.
class_name DecalPool
extends RefCounted

const MAX_POOL := 64
const LIFETIME_S := 8.0
const FADE_S := 1.0

const _ATLAS_TEX := preload("res://assets/textures/decals/decal_atlas.png")
const _ATLAS_JSON_PATH := "res://assets/textures/decals/decal_atlas.json"

## nom -> Rect2 en pixels de l'atlas ; chargé une seule fois (voir
## `_ensure_regions_loaded`), depuis le même decal_atlas.json qu'ART-04.
static var _regions: Dictionary = {}
static var _pool: Array[MeshInstance3D] = []
static var _next_slot: int = 0

static func _ensure_regions_loaded() -> void:
	if not _regions.is_empty():
		return
	var f := FileAccess.open(_ATLAS_JSON_PATH, FileAccess.READ)
	if f == null:
		push_warning("DecalPool: decal_atlas.json introuvable (%s)" % _ATLAS_JSON_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("DecalPool: decal_atlas.json illisible")
		return
	var decals: Dictionary = parsed.get("decals", {})
	for key in decals:
		var d: Dictionary = decals[key]
		_regions[String(key)] = Rect2(float(d["x"]), float(d["y"]), float(d["w"]), float(d["h"]))

## Noms valides (clés de decal_atlas.json) — utile aux appelants pour vérifier
## `decal_name` avant `spawn()`, et aux tests sans dépendre du disque.
static func known_decal_names() -> Array[String]:
	_ensure_regions_loaded()
	var names: Array[String] = []
	for key in _regions:
		names.append(key)
	return names

## Pose le décalque `decal_name` (ex. "impact_star_large", "crack_branch",
## "burn_small" — voir `known_decal_names()`) à plat contre la surface
## touchée (`pos`/`normal`), `size_m` de côté, teinté par `tint`
## (multiplicatif — Color.WHITE rend la texture telle quelle ; ces décalques
## sont DÉJÀ encrés, voir l'en-tête de fichier). Réutilise l'instance la plus
## ancienne du pool une fois MAX_POOL atteint. Sans effet si `parent` est nul
## ou hors de l'arbre (ex. fin de partie), ou si `decal_name` est inconnu.
static func spawn(parent: Node, pos: Vector3, normal: Vector3, decal_name: String, size_m: float, tint: Color = Color.WHITE) -> MeshInstance3D:
	if parent == null or not parent.is_inside_tree():
		return null
	_ensure_regions_loaded()
	if not _regions.has(decal_name):
		push_warning("DecalPool: décalque inconnu \"%s\"" % decal_name)
		return null
	var inst := _acquire(parent)
	if inst == null:
		return null
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	inst.global_transform = Transform3D(_basis_for_normal(n), pos + n * 0.01)
	_trigger(inst, decal_name, size_m, tint)
	return inst

static func _acquire(parent: Node) -> MeshInstance3D:
	if _pool.size() < MAX_POOL:
		var inst := _build_instance()
		parent.add_child(inst)
		_pool.append(inst)
		return inst
	var idx := _next_slot % _pool.size()
	_next_slot = (_next_slot + 1) % _pool.size()
	var inst: MeshInstance3D = _pool[idx]
	if not is_instance_valid(inst):
		inst = _build_instance()
		parent.add_child(inst)
		_pool[idx] = inst
	elif inst.get_parent() != parent:
		if inst.get_parent():
			inst.get_parent().remove_child(inst)
		parent.add_child(inst)
	var existing_tween: Object = inst.get_meta("_fade_tween", null)
	if existing_tween is Tween:
		(existing_tween as Tween).kill()
	return inst

static func _build_instance() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	mi.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mi.material_override = mat
	return mi

static func _trigger(inst: MeshInstance3D, decal_name: String, size_m: float, tint: Color) -> void:
	var mat := inst.material_override as StandardMaterial3D
	var rect: Rect2 = _regions[decal_name]
	var atlas := AtlasTexture.new()
	atlas.atlas = _ATLAS_TEX
	atlas.region = rect
	mat.albedo_texture = atlas
	mat.albedo_color = tint
	(inst.mesh as QuadMesh).size = Vector2.ONE * size_m
	inst.visible = true
	var tw := inst.create_tween()
	inst.set_meta("_fade_tween", tw)
	tw.tween_interval(maxf(LIFETIME_S - FADE_S, 0.0))
	tw.tween_property(mat, "albedo_color:a", 0.0, FADE_S)
	tw.tween_callback(inst.hide)

static func _basis_for_normal(n: Vector3) -> Basis:
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.999 else Vector3.RIGHT
	var x := up.cross(n)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT.cross(n)
	x = x.normalized()
	var y := n.cross(x).normalized()
	return Basis(x, y, n)
