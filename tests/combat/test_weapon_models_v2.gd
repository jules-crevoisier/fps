## test_weapon_models_v2.gd
## FP-11 -- criteres d'acceptation sur les 7 modeles "arme v2"
## (assets/models/weapons/v2/*.glb, tools/blender/rig_weapon_parts.py) : Grip = l'origine,
## POSE sur la poignee (creux de la main, a la hauteur du pontet, sous le bas de la
## carcasse), Foregrip/Sight/MagWell/Eject sur la vraie surface, Muzzle au bout du canon,
## pieces mobiles nommees (§3.3 de docs/research/12_viewmodel_v2.md), budget <= 8000 tris.
## Charge les GLB v2 DIRECTEMENT par chemin (pas via Weapon.model_path_for, qui pointe
## encore vers le v1 -- la bascule est FP-19, hors perimetre de cette tache).
##
## TEST INDEPENDANT du pipeline (revue du lead du 2026-09-25) : chaque critere geometrique
## est REMESURE ici sur les triangles du .glb exporte et reimporte par Godot -- distance
## point-triangle, rayons, silhouette de profil rasterisee -- sans rien relire du rapport
## JSON de rig_weapon_parts.py, SAUF l'IoU de silhouette v2 contre v1 transforme (cle
## "iou_profile") : la rasterisation IoU est testee en isolation, sur des cas synthetiques
## verifies a la main, par tools/blender/tests/test_rig_weapon_parts.py::TestSilhouetteIoU,
## et le "v1 transforme" n'existe que dans le pipeline (cle absente = echec, jamais un
## defaut silencieux).
##
## Definitions (identiques a l'en-tete de rig_weapon_parts.py, reimplementees ici) :
##   - "sous le bas de la carcasse / a la hauteur du pontet" : entre le bas et le haut de
##     l'ouverture du pontet, jour ferme de la silhouette de profil juste devant la
##     poignee (le haut de ce jour est la ou la queue de detente sort de la carcasse) ;
##   - "a l'interieur du maillage" : un rayon tire du Grip dans chacune des 6 directions
##     X/Y/Z touche un triangle (maillages Tripo non etanches, a coques superposees) ;
##   - "Muzzle au bout du canon" : a <= 1 cm, le long de l'axe, du sommet le plus en avant,
##     et a <= 1 cm de l'axe de l'ame, pris au centre de la face la plus avancee. Remplace
##     l'ancien test "sommet de la bande avant le plus proche de X=0, Y=0" : il supposait
##     l'axe du canon a la hauteur de l'origine, ce que le contrat v2 rend faux (origine =
##     poignee, 4 a 11 cm sous l'axe) -- il ne retenait donc que le bord BAS de la bouche.
extends GdUnitTestSuite

const MAX_TRIS := 8000
const MIN_IOU := 0.98
const V2_DIR := "res://assets/models/weapons/v2/"
# Ordre WeaponDatabase.PATHS (append-only, voir docs/STYLE_BIBLE.md §5.2) : 0 Pistolet,
# 1 Magnum, 2 Rafale, 3 Marqueur, 4 Ravage, 5 Fracas, 6 Faucheur.
const WEAPON_STEMS := ["pistolet", "magnum", "rafale", "marqueur", "ravage", "fracas", "faucheur"]
const EXPECTED_PIECES := {
	"pistolet": ["Slide", "Mag"],
	"magnum": ["Cylinder", "Hammer"],
	"rafale": ["Mag"],
	"marqueur": ["Mag"],
	"ravage": ["Mag"],
	"fracas": ["Pump"],
	"faucheur": ["Bolt", "Mag"],
}
const REQUIRED_ANCHORS := ["Grip", "Foregrip", "Muzzle", "Sight", "MagWell", "Eject"]
const SURFACE_ANCHORS := ["Foregrip", "Sight", "MagWell", "Eject"]

# Tolerances -- memes valeurs que les seuils durs de rig_weapon_parts.py, plus une marge
# epsilon (arrondis de l'aller-retour glTF : jamais plus de quelques dixiemes de mm).
const EPS_M := 0.0015
const GRIP_MAX_SURFACE_DIST_M := 0.010 + EPS_M
const ANCHOR_MAX_SURFACE_DIST_M := 0.015 + EPS_M
const MUZZLE_MAX_AXIAL_M := 0.01 + EPS_M
const MUZZLE_MAX_OFF_AXIS_M := 0.01 + EPS_M
const MUZZLE_FRONT_BAND_M := 0.003
const SIGHT_MIN_ELEVATION_M := 0.03 - EPS_M
const SIGHT_LATERAL_MAX_DEG := 1.5 + 0.2
const ANCHOR_FORWARD_MAX_DEG := 1.5
const ANCHOR_UP_MAX_DEG := 2.0
# Ouverture du pontet (memes valeurs que rig_weapon_parts.py::GUARD_*) : fenetre autour
# du Grip dans la silhouette de profil (u = -z = vers la bouche, v = y = hauteur).
const GUARD_CELL_M := 0.0025
const GUARD_WINDOW_FRONT_M := 0.22
const GUARD_WINDOW_BACK_M := 0.06
const GUARD_WINDOW_HALF_HEIGHT_M := 0.10
const GUARD_MAX_VERTICAL_GAP_M := 0.06
const GUARD_MIN_AREA_M2 := 1.0e-4

const CELL_EMPTY := 0
const CELL_FILLED := 1
const CELL_OUTSIDE := 2
const CELL_HOLE := 3

## Triangles (espace racine de la scene) par arme -- charges une fois par suite.
var _triangles_by_stem: Dictionary = {}


func _model_path(stem: String) -> String:
	return "%s%s.glb" % [V2_DIR, stem]


func _load_model(stem: String) -> Node3D:
	var path := _model_path(stem)
	assert_bool(ResourceLoader.exists(path)).append_failure_message(
		"%s : modele v2 introuvable (%s)" % [stem, path]).is_true()
	var scene: PackedScene = load(path)
	assert_object(scene).append_failure_message("%s : echec de chargement (%s)" % [stem, path]).is_not_null()
	var inst := scene.instantiate() as Node3D
	assert_object(inst).is_not_null()
	return inst


func _find_mesh_instances(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_find_mesh_instances(c))
	return out


func _tri_count(root: Node3D) -> int:
	var total := 0
	for mesh in _find_mesh_instances(root):
		if mesh.mesh:
			total += mesh.mesh.get_faces().size() / 3
	return total


func _find_anchor(root: Node3D, anchor_name: String) -> Node3D:
	return root.find_child(anchor_name, true, false) as Node3D


## Transform LOCAL -> racine de la scene instanciee, en remontant la chaine de parents a la
## main -- l'instance n'est jamais ajoutee a l'arbre de scene, donc
## `Node3D.global_transform` renverrait l'identite ; chaque piece dont l'origine a ete
## deplacee sur son pivot (§3.3) donnerait alors une position fausse.
func _root_transform_of(node: Node3D) -> Transform3D:
	var xform := node.transform
	var parent := node.get_parent()
	while parent is Node3D:
		xform = (parent as Node3D).transform * xform
		parent = parent.get_parent()
	return xform


func _anchor_position(root: Node3D, anchor_name: String) -> Vector3:
	var anchor := _find_anchor(root, anchor_name)
	assert_object(anchor).append_failure_message("repere \"%s\" introuvable" % anchor_name).is_not_null()
	return _root_transform_of(anchor).origin


## Tous les triangles de l'arme (sommets consecutifs par 3), en espace racine.
func _triangles(stem: String) -> PackedVector3Array:
	if _triangles_by_stem.has(stem):
		return _triangles_by_stem[stem]
	var inst := _load_model(stem)
	var tris := PackedVector3Array()
	for mesh in _find_mesh_instances(inst):
		if not mesh.mesh:
			continue
		var xform: Transform3D = _root_transform_of(mesh)
		for p in mesh.mesh.get_faces():
			tris.append(xform * p)
	inst.free()
	assert_int(tris.size()).append_failure_message("%s : aucun triangle" % stem).is_greater(0)
	_triangles_by_stem[stem] = tris
	return tris


## Rapport num / den, ou 0 si den est nul : un triangle degenere (arete de longueur nulle,
## frequent dans ces maillages Tripo) donnerait sinon NaN, et `minf(meilleur, NaN)` renvoie
## NaN -- le minimum courant serait perdu sans bruit.
func _safe_ratio(num: float, den: float) -> float:
	if absf(den) < 1e-18:
		return 0.0
	return num / den


## Point le plus proche de `p` sur le triangle (a, b, c) -- Ericson, "Real-Time Collision
## Detection" §5.1.5 (regions de Voronoi des sommets, aretes et face).
func _closest_point_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * _safe_ratio(d1, d1 - d3)
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * _safe_ratio(d2, d2 - d6)
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * _safe_ratio(d4 - d3, (d4 - d3) + (d5 - d6))
	var denom := va + vb + vc
	return a + ab * _safe_ratio(vb, denom) + ac * _safe_ratio(vc, denom)


func _distance_to_surface(tris: PackedVector3Array, p: Vector3) -> float:
	var best := INF
	for i in range(0, tris.size(), 3):
		var q := _closest_point_on_triangle(p, tris[i], tris[i + 1], tris[i + 2])
		best = minf(best, p.distance_to(q))
	return best


## Moller-Trumbore a deux faces. PAS Geometry3D.ray_intersects_triangle : son test de
## parallelisme compare e1.(d x e2) a un epsilon ABSOLU de 1e-5, soit l'aire d'un triangle
## d'environ 3 mm de cote en metres -- il manque donc les petits triangles de ces armes
## (sondage FP-11 : rayon vertical du Grip du Magnum sans impact).
func _ray_hits_triangle(origin: Vector3, direction: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var e1 := b - a
	var e2 := c - a
	var h := direction.cross(e2)
	var det := e1.dot(h)
	if absf(det) < 1e-14:
		return false
	var inv := 1.0 / det
	var s := origin - a
	var u := inv * s.dot(h)
	if u < 0.0 or u > 1.0:
		return false
	var q := s.cross(e1)
	var v := inv * direction.dot(q)
	if v < 0.0 or u + v > 1.0:
		return false
	return inv * e2.dot(q) > 1e-6


func _ray_hits(tris: PackedVector3Array, origin: Vector3, direction: Vector3) -> bool:
	for i in range(0, tris.size(), 3):
		if _ray_hits_triangle(origin, direction, tris[i], tris[i + 1], tris[i + 2]):
			return true
	return false


## Projection de profil : u = -z (vers la bouche), v = y (hauteur).
func _profile(p: Vector3) -> Vector2:
	return Vector2(-p.z, p.y)


func _in_profile_silhouette(tris: PackedVector3Array, p: Vector3) -> bool:
	var q := _profile(p)
	for i in range(0, tris.size(), 3):
		var a := _profile(tris[i])
		var b := _profile(tris[i + 1])
		var c := _profile(tris[i + 2])
		if q.x < minf(a.x, minf(b.x, c.x)) or q.x > maxf(a.x, maxf(b.x, c.x)):
			continue
		if q.y < minf(a.y, minf(b.y, c.y)) or q.y > maxf(a.y, maxf(b.y, c.y)):
			continue
		if _point_in_triangle_2d(q, a, b, c):
			return true
	return false


func _edge(a: Vector2, b: Vector2, p: Vector2) -> float:
	return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)


func _point_in_triangle_2d(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := _edge(a, b, p)
	var d2 := _edge(b, c, p)
	var d3 := _edge(c, a, p)
	var has_neg := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var has_pos := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (has_neg and has_pos)


## Ouverture du pontet dans la silhouette de profil, fenetre autour du Grip : jour ferme
## (non relie au bord de la fenetre) d'au moins 1 cm2, dont le centroide est DEVANT le Grip
## et dont la hauteur chevauche [Grip - 6 cm, Grip + 6 cm] ; le plus proche du Grip.
## Renvoie {"top", "bottom"} (hauteurs, m) ou {} si aucun.
func _trigger_guard_opening(tris: PackedVector3Array, grip: Vector3) -> Dictionary:
	var g := _profile(grip)
	var u0 := g.x - GUARD_WINDOW_BACK_M
	var v0 := g.y - GUARD_WINDOW_HALF_HEIGHT_M
	var nu := int(ceil((GUARD_WINDOW_FRONT_M + GUARD_WINDOW_BACK_M) / GUARD_CELL_M))
	var nv := int(ceil(2.0 * GUARD_WINDOW_HALF_HEIGHT_M / GUARD_CELL_M))
	var grid := PackedByteArray()
	grid.resize(nu * nv)
	grid.fill(CELL_EMPTY)
	for t in range(0, tris.size(), 3):
		var a := _profile(tris[t])
		var b := _profile(tris[t + 1])
		var c := _profile(tris[t + 2])
		var i0 := maxi(0, int(floor((minf(a.x, minf(b.x, c.x)) - u0) / GUARD_CELL_M)))
		var i1 := mini(nu - 1, int(floor((maxf(a.x, maxf(b.x, c.x)) - u0) / GUARD_CELL_M)))
		var j0 := maxi(0, int(floor((minf(a.y, minf(b.y, c.y)) - v0) / GUARD_CELL_M)))
		var j1 := mini(nv - 1, int(floor((maxf(a.y, maxf(b.y, c.y)) - v0) / GUARD_CELL_M)))
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				if grid[j * nu + i] == CELL_FILLED:
					continue
				var center := Vector2(u0 + (i + 0.5) * GUARD_CELL_M, v0 + (j + 0.5) * GUARD_CELL_M)
				if _point_in_triangle_2d(center, a, b, c):
					grid[j * nu + i] = CELL_FILLED
	# Vide relie au bord de la fenetre = dehors.
	var stack: Array[int] = []
	for i in range(nu):
		stack.append(i)
		stack.append((nv - 1) * nu + i)
	for j in range(nv):
		stack.append(j * nu)
		stack.append(j * nu + nu - 1)
	while not stack.is_empty():
		var idx: int = stack.pop_back()
		if grid[idx] != CELL_EMPTY:
			continue
		grid[idx] = CELL_OUTSIDE
		var ci := idx % nu
		var cj := idx / nu
		if ci > 0:
			stack.append(idx - 1)
		if ci < nu - 1:
			stack.append(idx + 1)
		if cj > 0:
			stack.append(idx - nu)
		if cj < nv - 1:
			stack.append(idx + nu)
	var best: Dictionary = {}
	var best_dist := INF
	for start in range(nu * nv):
		if grid[start] != CELL_EMPTY:
			continue
		var comp: Array[int] = []
		var todo: Array[int] = [start]
		grid[start] = CELL_HOLE
		while not todo.is_empty():
			var idx: int = todo.pop_back()
			comp.append(idx)
			var ci := idx % nu
			var cj := idx / nu
			for n in [idx - 1, idx + 1, idx - nu, idx + nu]:
				if n < 0 or n >= nu * nv:
					continue
				if (n == idx - 1 and ci == 0) or (n == idx + 1 and ci == nu - 1):
					continue
				if grid[n] == CELL_EMPTY:
					grid[n] = CELL_HOLE
					todo.append(n)
		var area := comp.size() * GUARD_CELL_M * GUARD_CELL_M
		if area < GUARD_MIN_AREA_M2:
			continue
		var j_min := nv
		var j_max := -1
		var sum_i := 0.0
		var sum_j := 0.0
		for idx in comp:
			var cj := idx / nu
			j_min = mini(j_min, cj)
			j_max = maxi(j_max, cj)
			sum_i += idx % nu
			sum_j += cj
		var cu := u0 + (sum_i / comp.size() + 0.5) * GUARD_CELL_M
		var cv := v0 + (sum_j / comp.size() + 0.5) * GUARD_CELL_M
		var bottom := v0 + j_min * GUARD_CELL_M
		var top := v0 + (j_max + 1) * GUARD_CELL_M
		if cu <= g.x:
			continue
		if top < g.y - GUARD_MAX_VERTICAL_GAP_M or bottom > g.y + GUARD_MAX_VERTICAL_GAP_M:
			continue
		var dist := Vector2(cu, cv).distance_to(g)
		if dist < best_dist:
			best_dist = dist
			best = {"top": top, "bottom": bottom}
	return best


func _read_report(stem: String) -> Dictionary:
	var path := "%s%s.json" % [V2_DIR, stem]
	assert_bool(FileAccess.file_exists(path)).append_failure_message(
		"%s : rapport JSON introuvable (%s)" % [stem, path]).is_true()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_bool(parsed is Dictionary).append_failure_message(
		"%s : rapport JSON invalide (%s)" % [stem, path]).is_true()
	return parsed as Dictionary


# ======================================================================
#  Chargement + budget de tris (<= 8000 par arme, meme plafond que le v1)
# ======================================================================
func test_every_v2_model_loads_and_stays_within_the_8000_tris_budget() -> void:
	for stem in WEAPON_STEMS:
		var inst := _load_model(stem)
		var tris := _tri_count(inst)
		assert_int(tris).append_failure_message(
			"%s : %d tris (budget FP-11 <= %d)" % [stem, tris, MAX_TRIS]).is_less_equal(MAX_TRIS)
		assert_int(tris).append_failure_message("%s : mesh vide (0 tri)" % stem).is_greater(0)
		inst.free()


# ======================================================================
#  Les 6 reperes sont presents (Grip/Foregrip/Muzzle/Sight/MagWell/Eject)
# ======================================================================
func test_every_v2_model_has_all_six_named_anchors() -> void:
	for stem in WEAPON_STEMS:
		var inst := _load_model(stem)
		for anchor_name in REQUIRED_ANCHORS:
			assert_object(_find_anchor(inst, anchor_name)).append_failure_message(
				"%s : repere \"%s\" introuvable" % [stem, anchor_name]).is_not_null()
		inst.free()


# ======================================================================
#  Reperes orientes : canon -Z (<= 1,5°), haut +Y (<= 2°)
# ======================================================================
func test_every_v2_anchor_is_oriented_bore_forward_and_up() -> void:
	for stem in WEAPON_STEMS:
		var inst := _load_model(stem)
		for anchor_name in REQUIRED_ANCHORS:
			var anchor := _find_anchor(inst, anchor_name)
			assert_object(anchor).is_not_null()
			var basis := _root_transform_of(anchor).basis.orthonormalized()
			var forward_deg := rad_to_deg((-basis.z).angle_to(Vector3.FORWARD))
			var up_deg := rad_to_deg(basis.y.angle_to(Vector3.UP))
			assert_float(forward_deg).append_failure_message(
				"%s.%s : avant local a %.2f° de -Z (attendu <= %.1f°)" %
				[stem, anchor_name, forward_deg, ANCHOR_FORWARD_MAX_DEG]).is_less_equal(ANCHOR_FORWARD_MAX_DEG)
			assert_float(up_deg).append_failure_message(
				"%s.%s : haut local a %.2f° de +Y (attendu <= %.1f°)" %
				[stem, anchor_name, up_deg, ANCHOR_UP_MAX_DEG]).is_less_equal(ANCHOR_UP_MAX_DEG)
		inst.free()


# ======================================================================
#  Grip = l'origine (§3.3 : le MAILLAGE est deplace, jamais le repere)
# ======================================================================
func test_every_v2_model_has_grip_at_the_local_origin() -> void:
	for stem in WEAPON_STEMS:
		var inst := _load_model(stem)
		var grip := _anchor_position(inst, "Grip")
		assert_float(grip.length()).append_failure_message(
			"%s : Grip a %s, attendu (0,0,0)" % [stem, grip]).is_less(EPS_M)
		inst.free()


# ======================================================================
#  Grip POSE sur la poignee : <= 1,0 cm de la surface, enferme par le maillage,
#  dans la silhouette de profil, a la hauteur du pontet sous le bas de la carcasse
# ======================================================================
func test_every_v2_grip_is_within_1_cm_of_the_handle_surface() -> void:
	for stem in WEAPON_STEMS:
		var inst := _load_model(stem)
		var grip := _anchor_position(inst, "Grip")
		inst.free()
		var dist := _distance_to_surface(_triangles(stem), grip)
		assert_float(dist).append_failure_message(
			"%s : Grip a %.2f cm de la surface (attendu <= 1,0 cm)" % [stem, dist * 100.0]
		).is_less_equal(GRIP_MAX_SURFACE_DIST_M)


func test_every_v2_grip_is_enclosed_by_the_mesh() -> void:
	var directions := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
	for stem in WEAPON_STEMS:
		var inst := _load_model(stem)
		var grip := _anchor_position(inst, "Grip")
		inst.free()
		var tris := _triangles(stem)
		for direction in directions:
			assert_bool(_ray_hits(tris, grip, direction)).append_failure_message(
				"%s : le rayon tire du Grip vers %s ne touche rien -- Grip hors de la matiere" %
				[stem, direction]).is_true()


func test_every_v2_grip_is_inside_the_profile_silhouette() -> void:
	for stem in WEAPON_STEMS:
		var inst := _load_model(stem)
		var grip := _anchor_position(inst, "Grip")
		inst.free()
		assert_bool(_in_profile_silhouette(_triangles(stem), grip)).append_failure_message(
			"%s : Grip hors de la silhouette de profil" % stem).is_true()


func test_every_v2_grip_is_at_trigger_guard_height_below_the_frame() -> void:
	for stem in WEAPON_STEMS:
		var inst := _load_model(stem)
		var grip := _anchor_position(inst, "Grip")
		inst.free()
		var guard := _trigger_guard_opening(_triangles(stem), grip)
		assert_bool(guard.is_empty()).append_failure_message(
			"%s : aucune ouverture de pontet devant le Grip" % stem).is_false()
		if guard.is_empty():
			continue
		assert_float(grip.y).append_failure_message(
			"%s : Grip a y=%.2f cm, au-dessus du bas de la carcasse (haut du pontet %.2f cm)" %
			[stem, grip.y * 100.0, guard["top"] * 100.0]).is_less_equal(guard["top"])
		assert_float(grip.y).append_failure_message(
			"%s : Grip a y=%.2f cm, sous le bas du pontet (%.2f cm)" %
			[stem, grip.y * 100.0, guard["bottom"] * 100.0]).is_greater_equal(guard["bottom"])


# ======================================================================
#  Foregrip / Sight / MagWell / Eject : <= 1,5 cm de la surface
# ======================================================================
func test_every_v2_anchor_sits_within_1_5_cm_of_the_surface() -> void:
	for stem in WEAPON_STEMS:
		var inst := _load_model(stem)
		var positions: Dictionary = {}
		for anchor_name in SURFACE_ANCHORS:
			positions[anchor_name] = _anchor_position(inst, anchor_name)
		inst.free()
		var tris := _triangles(stem)
		for anchor_name in SURFACE_ANCHORS:
			var dist := _distance_to_surface(tris, positions[anchor_name])
			assert_float(dist).append_failure_message(
				"%s.%s : %.2f cm de la surface (attendu <= 1,5 cm)" % [stem, anchor_name, dist * 100.0]
			).is_less_equal(ANCHOR_MAX_SURFACE_DIST_M)


# ======================================================================
#  Muzzle : canon vers -Z, au bout du canon (axe de l'ame)
# ======================================================================
func test_every_v2_model_has_a_muzzle_anchor_pointing_forward() -> void:
	for stem in WEAPON_STEMS:
		var inst := _load_model(stem)
		var muzzle := _anchor_position(inst, "Muzzle")
		assert_float(muzzle.z).append_failure_message(
			"%s : Muzzle.z = %.4f (attendu < 0, canon vers -Z)" % [stem, muzzle.z]).is_less(0.0)
		inst.free()


func test_every_v2_model_has_its_muzzle_at_the_bore_tip() -> void:
	for stem in WEAPON_STEMS:
		var inst := _load_model(stem)
		var muzzle := _anchor_position(inst, "Muzzle")
		inst.free()
		var tris := _triangles(stem)
		var min_z := INF
		for p in tris:
			min_z = minf(min_z, p.z)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in tris:
			if p.z <= min_z + MUZZLE_FRONT_BAND_M:
				lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
				hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		var bore := (lo + hi) * 0.5
		var axial := absf(muzzle.z - min_z)
		var off_axis := Vector2(muzzle.x, muzzle.y).distance_to(bore)
		assert_float(axial).append_failure_message(
			"%s : Muzzle a %.2f cm du sommet le plus en avant, le long de l'axe (attendu <= 1 cm)" %
			[stem, axial * 100.0]).is_less_equal(MUZZLE_MAX_AXIAL_M)
		assert_float(off_axis).append_failure_message(
			"%s : Muzzle a %.2f cm de l'axe de l'ame (centre de la face avant) (attendu <= 1 cm)" %
			[stem, off_axis * 100.0]).is_less_equal(MUZZLE_MAX_OFF_AXIS_M)


# ======================================================================
#  Sight : >= 3 cm au-dessus de l'axe du canon (hauteur = +Y export), et
#  son axe vers Muzzle reste sans cant lateral (note de lecture de
#  rig_weapon_parts.py : la tolerance porte sur la deviation LATERALE X).
# ======================================================================
func test_every_v2_model_has_sight_elevated_above_the_bore_axis() -> void:
	for stem in WEAPON_STEMS:
		var inst := _load_model(stem)
		var elevation: float = _anchor_position(inst, "Sight").y - _anchor_position(inst, "Muzzle").y
		assert_float(elevation).append_failure_message(
			"%s : Sight %.2f cm au-dessus du canon (attendu >= 3 cm)" %
			[stem, elevation * 100.0]).is_greater_equal(SIGHT_MIN_ELEVATION_M)
		inst.free()


func test_every_v2_model_has_no_lateral_cant_between_sight_and_muzzle() -> void:
	for stem in WEAPON_STEMS:
		var inst := _load_model(stem)
		var sight := _anchor_position(inst, "Sight")
		var muzzle := _anchor_position(inst, "Muzzle")
		var forward: float = absf(muzzle.z - sight.z)
		var lateral: float = absf(muzzle.x - sight.x)
		var angle_deg := rad_to_deg(atan2(lateral, maxf(forward, 0.0001)))
		assert_float(angle_deg).append_failure_message(
			"%s : deviation laterale Sight->Muzzle = %.2f° (attendu <= %.1f°)" %
			[stem, angle_deg, SIGHT_LATERAL_MAX_DEG]).is_less_equal(SIGHT_LATERAL_MAX_DEG)
		inst.free()


# ======================================================================
#  Pieces mobiles presentes et nommees comme au §3.3
# ======================================================================
func test_every_v2_model_has_its_contract_pieces_present_and_named() -> void:
	for stem in WEAPON_STEMS:
		var inst := _load_model(stem)
		for piece_name in EXPECTED_PIECES[stem]:
			var piece := inst.find_child(piece_name, true, false)
			assert_object(piece).append_failure_message(
				"%s : piece \"%s\" introuvable" % [stem, piece_name]).is_not_null()
			assert_bool(piece is MeshInstance3D).append_failure_message(
				"%s : \"%s\" n'est pas un MeshInstance3D" % [stem, piece_name]).is_true()
		# "Body reste implicite" (weapon_rigs.yaml) : au moins UN maillage en plus des
		# pieces attendues (le corps principal n'est jamais dans EXPECTED_PIECES).
		assert_int(_find_mesh_instances(inst).size()).append_failure_message(
			"%s : aucun maillage \"Body\" au-dela des pieces" % stem).is_greater(
			EXPECTED_PIECES[stem].size())
		inst.free()


# ======================================================================
#  IoU de silhouette de profil (v2 contre v1 transforme) -- lue depuis le
#  rapport JSON du pipeline (voir l'en-tete de ce fichier).
# ======================================================================
func test_every_v2_model_keeps_the_v1_profile_silhouette() -> void:
	for stem in WEAPON_STEMS:
		var report := _read_report(stem)
		assert_bool(report.has("iou_profile")).append_failure_message(
			"%s : cle \"iou_profile\" absente du rapport" % stem).is_true()
		var iou: float = report["iou_profile"]
		assert_float(iou).append_failure_message(
			"%s : IoU de silhouette = %.4f (attendu >= %.2f)" % [stem, iou, MIN_IOU]).is_greater_equal(MIN_IOU)


# ======================================================================
#  Le v1 reste intact (§3.3 : "Ne pas toucher aux GLB v1", bascule en FP-19)
#  et sa copie figee _painted_v1 existe (source de rig_weapon_parts.py).
# ======================================================================
func test_v1_glb_and_its_frozen_copy_both_exist() -> void:
	for stem in WEAPON_STEMS:
		var v1_path := "res://assets/models/weapons/%s.glb" % stem
		var frozen_path := "res://assets/models/weapons/_painted_v1/%s.glb" % stem
		assert_bool(ResourceLoader.exists(v1_path)).append_failure_message(
			"%s : v1 introuvable (%s)" % [stem, v1_path]).is_true()
		assert_bool(ResourceLoader.exists(frozen_path)).append_failure_message(
			"%s : copie _painted_v1 introuvable (%s)" % [stem, frozen_path]).is_true()
