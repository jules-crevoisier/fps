## ArtRocksBackdrop.gd
## ART-98 (docs/art/WASTELAND_V4_ART_PLAN.md §2 "Roches et falaises" + §4
## "Canyon, falaises et fond") — module de la passe d'art v4 de Wasteland,
## chargé par `WastelandArt.load_modules` (contrat : `apply(parent: Node3D,
## data: Dictionary) -> void`, PUREMENT VISUEL — jamais de
## `CollisionObject3D`, §1 R9). Habille :
##  1. les 8 aiguilles du canyon (RocherS1W/N1W/S2W/GueW + leurs miroirs est,
##     §2 "8 aiguilles UNIQUES, générées aux cotes exactes de leur boîte : 8
##     graines, pas de copie miroir") ;
##  2. les 4 falaises de bordure (CliffN/S/W/E), en segments dont la face
##     côté jeu reste EXACTEMENT sur le plan de collision — garanti par
##     construction (`build_wall_segment`, tools/blender/make_stylized_rocks.py,
##     coupe plane au plan de collision, jamais une tolérance mesurée après
##     coup — voir sa docstring) ;
##  3. la "ville haute" (terrasse nord, +6 m, hors-jeu, docs/research/img/
##     wasteland_v4_art_zones.png) : 7 coques Tripo réutilisées en LOD
##     lointain (`tools/ai3d/manifests/painted_env_far.yaml`) ;
##  4. l'horizon (v4_mesa_01/02, "strates x2" §4 — obtenu par une échelle
##     GODOT x2 sur l'instance, jamais en repassant le tuilage Python : les
##     pièces sont construites à taille normale, voir `_MESA_V4_SCALE`).
##
## "0 pixel de vide sous l'horizon dans les 12 vues" (critère d'acceptation
## ART-98) est déjà GARANTI par `Backdrop.gd` (ART-06/76 : anneau 150-600 m +
## jupe 40-150 m, posé par `LevelLook._style()` sur LES 8 CARTES, wasteland
## comprise, indépendamment de ce module). Ce module ne refait pas cette
## garantie, il ne doit juste pas la régresser (silhouettes fermées côté jeu,
## voir 2. ci-dessus).
##
## Bilan objets/source, à répéter EXACTEMENT ainsi dans tout rendu de tâche
## (aucune formule globale du type "tout vient de data()") : sur les 37
## objets posés par `apply()`, 28 (les 8 aiguilles de 1. + les 20 segments de
## falaise de 2.) ont leur position/taille lues dans
## `WastelandLayout.data()["pieces"]` via `_piece_by_name` — jamais recopiées
## à la main. Les 9 restants (les 7 coques Tripo de 3., `_FAR_TOWN_ENTRIES`,
## + les 2 mesas de 4., `_MESA_V4_ENTRIES`) sont des CONSTANTES tapées à la
## main, lues sur le plan annoté `docs/research/img/wasteland_v4_art_zones.png`
## : purement décoratifs, hors-jeu, jamais dans `data()["pieces"]` (R9), et
## `wasteland.gd` (hors de mon périmètre ART-98) ne leur fournit aucune boîte
## correspondante — recopier ces cotes à la main est ici la seule option
## disponible pour ce module, pas un raccourci pris par défaut.
##
## BLOQUANT connu, signalé au lead (voir le rendu de tâche, `blocked_on`) :
## CliffN/S/W/E et RocherS1W/N1W/S2W/GueW (+ est) sont des pièces `box` de
## `scripts/levels/maps/layouts/wasteland.gd` SANS `"visual": false` — ce
## fichier est HORS de mon périmètre ART-98 (`plan.py prompt ART-98` ne le
## liste pas). `Kit.build_piece` lit déjà ce champ (ART-91, défaut `true`,
## voir son commentaire "pièce entièrement remplacée") : tant qu'il n'est pas
## posé à `false` sur ces 6 pièces, LEUR BOÎTE GRISE KIT RESTE RENDUE EN PLUS
## des maillages posés ci-dessous (double géométrie visible — la collision,
## elle, reste identique dans les deux cas, aucune régression de gameplay).
class_name ArtRocksBackdrop
extends RefCounted

const _ROCKS_DIR := "res://assets/models/props/wasteland/rocks/"
const _FAR_DIR := "res://assets/models/props/wasteland/tripo_far/"

static var _mesh_cache: Dictionary = {}  # chemin res:// -> Mesh (jamais invalidé, comme Backdrop._mesh_cache)

# ======================================================================
#  1. Aiguilles (make_stylized_rocks.py::V4_ROCHER_SPECS, ART-98).
# ======================================================================
const _SPIRE_ASSET_BY_PIECE: Dictionary = {
	"RocherS1W": "v4_rocher_s1w", "RocherN1W": "v4_rocher_n1w",
	"RocherS2W": "v4_rocher_s2w", "RocherGueW": "v4_rocher_guew",
	"RocherS1E": "v4_rocher_s1e", "RocherN1E": "v4_rocher_n1e",
	"RocherS2E": "v4_rocher_s2e", "RocherGueE": "v4_rocher_guee",
}

static func _apply_spires(parent: Node3D, data: Dictionary) -> void:
	for piece_name in _SPIRE_ASSET_BY_PIECE.keys():
		var piece := _piece_by_name(data, String(piece_name))
		if piece.is_empty():
			continue
		var pos: Vector3 = piece["pos"]
		var size: Vector3 = piece["size"]
		var mesh := _mesh_for("%s%s.glb" % [_ROCKS_DIR, _SPIRE_ASSET_BY_PIECE[piece_name]])
		if mesh == null:
			continue
		# Origine de la pièce = centre-bas (convention check_asset, voir
		# `_fit_to_dims`) : pose au sol de la boîte (`pos.y - size.y * 0.5`),
		# centrée en x/z sur la boîte — aucune rotation, la pièce remplit déjà
		# exactement sa boîte (générée à ses cotes, §2).
		var world_pos := Vector3(pos.x, pos.y - size.y * 0.5, pos.z)
		_add_mesh_instance(parent, piece_name, mesh, Transform3D(Basis.IDENTITY, world_pos))

# ======================================================================
#  2. Falaises de bordure (make_stylized_rocks.py::build_wall_segment).
#     Convention d'export glTF observée (vérifiée par lecture de l'AABB d'un
#     .glb réel, voir le rendu de tâche) : l'axe Y BLENDER (0 = plan flush
#     côté jeu, négatif = relief hors-jeu) devient l'axe Z GODOT (0 = plan
#     flush, POSITIF = relief hors-jeu) — donc l'axe local +Z de chaque
#     segment importé pointe TOUJOURS vers le hors-jeu ("outward" ci-dessous).
# ======================================================================
const _WALL_SEGMENTS_W := 6
const _WALL_SEGMENTS_E := 6
const _WALL_SEGMENTS_N := 4
const _WALL_SEGMENTS_S := 4

static func _apply_walls(parent: Node3D, data: Dictionary) -> void:
	# Chaque appel : (nom de la pièce `box`, préfixe des .glb, nb de segments,
	# la pièce court le long de x (vrai, CliffN/S) ou de z (faux, CliffW/E),
	# signe du bord côté jeu sur l'axe FIXE (+1 = bord haut de la boîte, -1 =
	# bord bas — voir `_apply_wall_side`), et la `Basis` qui envoie l'axe
	# local +x sur la direction "le long du mur" et l'axe local +z ("outward",
	# voir ci-dessus) sur la direction "vers le hors-jeu" en repère MONDE.
	_apply_wall_side(parent, data, "CliffW", "v4_cliff_w", _WALL_SEGMENTS_W, false, 1.0,
		Basis(Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0), Vector3(-1.0, 0.0, 0.0)))
	_apply_wall_side(parent, data, "CliffE", "v4_cliff_e", _WALL_SEGMENTS_E, false, -1.0,
		Basis(Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0)))
	_apply_wall_side(parent, data, "CliffN", "v4_cliff_n", _WALL_SEGMENTS_N, true, 1.0,
		Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0)))
	_apply_wall_side(parent, data, "CliffS", "v4_cliff_s", _WALL_SEGMENTS_S, true, -1.0,
		Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0)))

static func _apply_wall_side(parent: Node3D, data: Dictionary, box_name: String, prefix: String,
		segment_count: int, run_along_x: bool, flush_sign: float, basis: Basis) -> void:
	var piece := _piece_by_name(data, box_name)
	if piece.is_empty():
		return
	var pos: Vector3 = piece["pos"]
	var size: Vector3 = piece["size"]
	var bottom_y := pos.y - size.y * 0.5
	var run_lo: float
	var run_hi: float
	var fixed: float
	if run_along_x:
		run_lo = pos.x - size.x * 0.5
		run_hi = pos.x + size.x * 0.5
		fixed = pos.z + flush_sign * size.z * 0.5
	else:
		run_lo = pos.z - size.z * 0.5
		run_hi = pos.z + size.z * 0.5
		fixed = pos.x + flush_sign * size.x * 0.5
	var seg_len := (run_hi - run_lo) / float(segment_count)
	for i in segment_count:
		var center := run_lo + (float(i) + 0.5) * seg_len
		var mesh := _mesh_for("%s%s_%02d.glb" % [_ROCKS_DIR, prefix, i])
		if mesh == null:
			continue
		var world_pos := Vector3(center, bottom_y, fixed) if run_along_x else Vector3(fixed, bottom_y, center)
		_add_mesh_instance(parent, "%s_%02d" % [prefix, i], mesh, Transform3D(basis, world_pos))

# ======================================================================
#  3. "Ville haute" (terrasse nord, +6 m, hors-jeu) — painted_env_far.yaml.
#     Positions/rotations lues sur docs/research/img/wasteland_v4_art_zones.png
#     (bandeau du haut, de l'ouest vers l'est) : garage, saloon, fuel_store,
#     shack, garage, shack, shack. Purement décoratif, jamais dans
#     data()["pieces"] (R9 "aucun CollisionObject3D ajouté").
# ======================================================================
const _FAR_TOWN_Z := -34.0
const _FAR_TOWN_Y := 6.0
## (id du .glb LOD lointain, x monde, rotation Y deg) — x croissant = ouest
## vers est, cohérent avec le bandeau du plan annoté.
const _FAR_TOWN_ENTRIES: Array = [
	["wl_garage_far_a", -36.0, -20.0],
	["wl_saloon_far", -14.0, 8.0],
	["wl_fuel_store_far", 2.0, -6.0],
	["wl_shack_far_a", 12.0, 24.0],
	["wl_garage_far_b", 22.0, 14.0],
	["wl_shack_far_b", 34.0, -18.0],
	["wl_shack_far_c", 46.0, 30.0],
]

static func _apply_far_town(parent: Node3D) -> void:
	for entry in _FAR_TOWN_ENTRIES:
		var asset_id := String(entry[0])
		var x := float(entry[1])
		var rot_deg := float(entry[2])
		var mesh := _mesh_for("%s%s.glb" % [_FAR_DIR, asset_id])
		if mesh == null:
			continue
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(rot_deg)), Vector3(x, _FAR_TOWN_Y, _FAR_TOWN_Z))
		_add_mesh_instance(parent, asset_id, mesh, xf)

# ======================================================================
#  4. Horizon (v4_mesa_01/02, §4 "strates x2, entre 60 et 150 m").
# ======================================================================
## Échelle Godot appliquée à l'instance ("strates x2", §4) : la pièce est
## construite par `make_stylized_rocks.py --v4` à taille NORMALE (même
## tuilage `STRATA_TILE_M` que le reste du pipeline peint) — la doubler ici
## fait lire chaque tuile de la texture de strates sur 4 m au sol au lieu de
## 2 m, lisible à la distance de pose (60-150 m) sans retoucher le pipeline
## Python (voir la docstring de V4_MESA_SPECS).
const _MESA_V4_SCALE := 2.0
## (id, x monde, z monde, rotation Y deg) — rayons mesurés depuis le centre
## de la carte : mesa_01 ~103 m (nord-ouest), mesa_02 ~113 m (sud-est),
## toutes deux dans la bande 60-150 m du critère.
const _MESA_V4_ENTRIES: Array = [
	["v4_mesa_01", -95.0, 40.0, -55.0],
	["v4_mesa_02", 110.0, -25.0, -30.0],
]

static func _apply_horizon_mesas(parent: Node3D) -> void:
	for entry in _MESA_V4_ENTRIES:
		var asset_id := String(entry[0])
		var x := float(entry[1])
		var z := float(entry[2])
		var rot_deg := float(entry[3])
		var mesh := _mesh_for("%s%s.glb" % [_ROCKS_DIR, asset_id])
		if mesh == null:
			continue
		var basis := Basis(Vector3.UP, deg_to_rad(rot_deg)).scaled(Vector3.ONE * _MESA_V4_SCALE)
		_add_mesh_instance(parent, asset_id, mesh, Transform3D(basis, Vector3(x, 0.0, z)))

# ======================================================================
#  Utilitaires (même idiome que Backdrop._load_glb_mesh/PropCatalog._mesh_for :
#  charger la scène, extraire le premier MeshInstance3D, mettre en cache le
#  Mesh seul — jamais la scène entière, jamais de collision).
# ======================================================================
static func _piece_by_name(data: Dictionary, piece_name: String) -> Dictionary:
	for entry in (data.get("pieces", []) as Array):
		var p: Dictionary = entry
		if String(p.get("name", "")) == piece_name:
			return p
	return {}

static func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null

## `null` si l'asset n'existe pas encore (dégrade proprement — même contrat
## que `Backdrop._load_glb_mesh` : "aucun test n'a besoin d'un .glb pour
## passer"), jamais une erreur qui ferait échouer toute la passe d'art pour
## une seule pièce absente.
static func _mesh_for(path: String) -> Mesh:
	if _mesh_cache.has(path):
		return _mesh_cache[path]
	var mesh: Mesh = null
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			var inst := packed.instantiate()
			var mi := _find_mesh_instance(inst)
			if mi != null:
				mesh = mi.mesh
			inst.free()
	_mesh_cache[path] = mesh
	return mesh

## `transform` LOCAL (jamais `global_transform`) : même convention que
## `Kit._collision_box`/`GeoBatcher.add_box` — `parent` (le `NavigationRegion3D`
## de `MapSetup`) porte déjà le décalage éventuel de la carte (ex. `_OFFSET`
## des tests), un enfant direct n'a donc besoin que de sa position DANS le
## repère de la carte.
static func _add_mesh_instance(parent: Node3D, node_name: String, mesh: Mesh, xform: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.transform = xform
	parent.add_child(mi)

## Contrat WastelandArt.gd (§ en-tête) : appelée une fois par `load_modules`,
## dans l'ordre de `MODULE_PATHS`, avec `parent` = le `NavigationRegion3D`
## réel et `data` = `WastelandLayout.data()`. Ordre interne sans importance
## (les 4 groupes ne se recouvrent jamais).
static func apply(parent: Node3D, data: Dictionary) -> void:
	_apply_spires(parent, data)
	_apply_walls(parent, data)
	_apply_far_town(parent)
	_apply_horizon_mesas(parent)
