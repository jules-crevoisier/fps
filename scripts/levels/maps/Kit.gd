## Kit.gd
## Kit modulaire de pièces procédurales pour les maps graphic-novel
## (.orchestrator/maps-spec.md §4) : murs, sols, rampes, escaliers (UNE
## collision en rampe + marches visuelles — les joueurs n'ont pas de step-up),
## conteneurs (nervurés, `axis`/`ends_open`), coques de bâtiment à 1-2 étages
## (`building2` : portes, fenêtres/meurtrières perçantes, dalles à trémie,
## toit praticable + parapet), murs invisibles (collision seule, garde-fou de
## bord de carte), passerelles avec rambardes, clôtures, silhouettes
## décoratives (grue, château d'eau, antenne). Chaque pièce pose sa collision
## (StaticBody3D + CollisionShape3D) individuellement — la physique et le
## bake de navmesh en ont besoin par pièce, sauf `visual_only` (aucune
## collision : nervures, marches, l'eau...) — mais les visuels de MÊME
## couleur sont fusionnés par `GeoBatcher` en UN SEUL MeshInstance3D par
## matériau, pour garder un nombre de draw calls raisonnable (contrat :
## ≤ 120 draw calls, ≤ 6 matériaux).
##
## Les fonctions ici ne connaissent PAS les maps : `Layouts.gd` compose les
## six maps à partir de ces pièces + de données de layout pures (dictionnaires
## de positions), que `MapSetup.gd` consomme via `build_piece()`.
class_name Kit
extends RefCounted

## Hauteur "œil" utilisée pour juger si une pièce casse une ligne de vue —
## voir `piece_blocks_sight()` (tests/maps : "no direct line between spawns
## through open space").
const SIGHT_MIN_TOP := 1.4

## ======================================================================
##  GeoBatcher : fusionne les visuels de même couleur en un seul mesh
##  (un draw call par matériau) ; la collision reste individuelle par pièce.
## ======================================================================
class GeoBatcher:
	var _tools: Dictionary = {}   # clé "couleur(html)|kind" -> SurfaceTool
	var _colors: Dictionary = {}  # clé -> Color
	var _kinds: Dictionary = {}   # clé -> kind peint ("" = plat, Cartoon.world)

	## `kind` (maps-spec-v2.md §7 "apply painted kinds to Kit surfaces", via
	## MapDressing.surface_kinds()) : nom d'un matériau peint Cartoon.painted
	## (ex. "sand_dirt", "cracked_concrete"). Vide = comportement d'origine
	## (couleur plate Cartoon.world) — groupé séparément des boîtes plates de
	## même couleur pour ne jamais les fusionner par erreur dans un seul mesh.
	func add_box(xform: Transform3D, size: Vector3, color: Color, kind: String = "") -> void:
		var key := "%s|%s" % [color.to_html(), kind]
		if not _tools.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_tools[key] = st
			_colors[key] = color
			_kinds[key] = kind
		var bm := BoxMesh.new()
		bm.size = size
		(_tools[key] as SurfaceTool).append_from(bm, 0, xform)

	## Fusionne tout dans `parent` (un MeshInstance3D par couleur+kind) et
	## renvoie le nombre de matériaux créés (~= draw calls de géométrie statique).
	func flush(parent: Node3D) -> int:
		var n := 0
		for key in _tools.keys():
			var st: SurfaceTool = _tools[key]
			st.index()
			st.generate_normals()
			var mesh := st.commit()
			var mi := MeshInstance3D.new()
			mi.name = "Merged%d" % n
			mi.mesh = mesh
			var kind: String = _kinds.get(key, "")
			var col: Color = _colors[key] as Color
			mi.material_override = Cartoon.painted(kind, col) if kind != "" else Cartoon.world(col)
			parent.add_child(mi)
			n += 1
		return n

# ======================================================================
#  Primitives bas niveau
# ======================================================================
static func _collision_box(parent: Node3D, xform: Transform3D, size: Vector3, nm: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = nm
	body.transform = xform
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	return body

static func _xform_box(center: Vector3, rot_y: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rot_y), center)

## Pièce boîte générique (sol, mur, plateforme, caisse, muret, pilier...).
## `visual_only` (§4.4) : aucune collision (ex. l'eau, un canal) — juste du
## rendu fusionné par le batcher.
static func box(parent: Node3D, batcher: GeoBatcher, center: Vector3, size: Vector3, color: Color, nm: String = "Piece", rot_y: float = 0.0, visual_only: bool = false, kind: String = "") -> void:
	var xf := _xform_box(center, rot_y)
	if not visual_only:
		_collision_box(parent, xf, size, nm)
	batcher.add_box(xf, size, color, kind)

## Géométrie pure d'une rampe (repère + forme), partagée par `ramp()`,
## `stairs()` et les rampes internes de `building2()`.
static func _ramp_shape(start: Vector3, end: Vector3, width: float, thickness: float) -> Dictionary:
	var dir := end - start
	var length := dir.length()
	var fwd := dir.normalized()
	# ATTENTION à l'ordre du produit vectoriel : Basis(x, y, z) attend des
	# colonnes DROITES (x cross y == z). `UP.cross(fwd)` donnerait -side (base
	# gauche = normale de la face "dessus" INVERSÉE, donc une pente > 90° pour
	# Recast : le bake du navmesh ignore alors la rampe — vérifié en isolant
	# le bake). `fwd.cross(UP)` puis `side.cross(fwd)` donne la base DROITE.
	var side := fwd.cross(Vector3.UP)
	if side.length() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(fwd).normalized()
	var b := Basis(fwd, up, side)
	var center := (start + end) * 0.5 - up * (thickness * 0.5)
	return {
		"xform": Transform3D(b, center),
		"size": Vector3(length, thickness, width),
		"fwd": fwd, "side": side, "up": up,
	}

## Rampe définie par deux points DE SURFACE (début, fin) + largeur — assez
## longues/peu pentues pour rester praticables en glissade (design "slide").
## Visuel ET collision suivent la pente lisse.
static func ramp(parent: Node3D, batcher: GeoBatcher, start: Vector3, end: Vector3, width: float, color: Color, thickness: float = 1.0, nm: String = "Ramp", kind: String = "") -> void:
	var r := _ramp_shape(start, end, width, thickness)
	_collision_box(parent, r["xform"], r["size"], nm)
	batcher.add_box(r["xform"], r["size"], color, kind)

## UNE collision en rampe (les joueurs n'ont pas de step-up : des marches
## individuelles bloqueraient la montée) + marches VISUELLES seules (aucune
## collision propre), le long de start->end.
static func _ramp_with_treads(parent: Node3D, batcher: GeoBatcher, start: Vector3, end: Vector3, width: float, color: Color, nm: String, steps: int, thickness: float, kind: String = "") -> void:
	steps = maxi(steps, 2)
	var r := _ramp_shape(start, end, width, thickness)
	_collision_box(parent, r["xform"], r["size"], nm)
	var fwd: Vector3 = r["fwd"]
	var side: Vector3 = r["side"]
	var flat_len := Vector3(end.x - start.x, 0.0, end.z - start.z).length()
	var rise := end.y - start.y
	var step_run := flat_len / float(steps)
	var step_rise := rise / float(steps)
	var tb := Basis(fwd, Vector3.UP, side)
	for i in steps:
		var t := float(i) + 1.0
		var tc := start + fwd * (step_run * t - step_run * 0.5) + Vector3.UP * (step_rise * t - 0.05)
		batcher.add_box(Transform3D(tb, tc), Vector3(step_run * 0.92, 0.08, width * 0.94), color, kind)

## Escalier (marches visuelles réelles) — UNE seule collision en rampe (§4.2 :
## "players have no step-up").
static func stairs(parent: Node3D, batcher: GeoBatcher, start: Vector3, end: Vector3, width: float, steps: int, color: Color, nm: String = "Stairs", kind: String = "") -> void:
	_ramp_with_treads(parent, batcher, start, end, width, color, nm, steps, 0.2, kind)

## Passerelle élevée avec rambardes des deux côtés (contour bas de garde-corps).
static func catwalk(parent: Node3D, batcher: GeoBatcher, start: Vector3, end: Vector3, width: float, color: Color, nm: String = "Catwalk", kind: String = "") -> void:
	var dir := end - start
	var flat := Vector3(dir.x, 0.0, dir.z)
	var length := flat.length()
	var fwd := flat.normalized() if length > 0.001 else Vector3.FORWARD
	var side := Vector3.UP.cross(fwd).normalized()
	var center := (start + end) * 0.5
	var deck_t := 0.25
	var b := Basis(fwd, Vector3.UP, side)
	var deck_xf := Transform3D(b, center)
	var deck_size := Vector3(length, deck_t, width)
	_collision_box(parent, deck_xf, deck_size, nm + "Deck")
	batcher.add_box(deck_xf, deck_size, color, kind)
	var rail_h := 1.0
	for s in [-1.0, 1.0]:
		var sf: float = s
		var rc: Vector3 = center + side * (sf * width * 0.5) + Vector3.UP * (deck_t * 0.5 + rail_h * 0.5)
		var rxf := Transform3D(b, rc)
		var rsize := Vector3(length, rail_h, 0.1)
		_collision_box(parent, rxf, rsize, "%sRail%d" % [nm, int(sf)])
		batcher.add_box(rxf, rsize, color, kind)

## Clôture / muret linéaire fin (start -> end), hauteur donnée.
static func fence(parent: Node3D, batcher: GeoBatcher, start: Vector3, end: Vector3, height: float, color: Color, nm: String = "Fence", kind: String = "") -> void:
	var dir := end - start
	var length := dir.length()
	var fwd := dir.normalized() if length > 0.001 else Vector3.RIGHT
	var side := Vector3.UP.cross(fwd).normalized()
	var center := (start + end) * 0.5 + Vector3.UP * (height * 0.5)
	var xf := Transform3D(Basis(fwd, Vector3.UP, side), center)
	var size := Vector3(length, height, 0.12)
	_collision_box(parent, xf, size, nm)
	batcher.add_box(xf, size, color, kind)

## Mur invisible (§4.4) : collision SEULE, 0.2 m d'épaisseur — garde-fou de
## bord de carte (quai, toit...), jamais rendu.
static func invisible_wall(parent: Node3D, start: Vector3, end: Vector3, height: float, nm: String = "InvWall") -> void:
	var dir := end - start
	var length := dir.length()
	var fwd := dir.normalized() if length > 0.001 else Vector3.RIGHT
	var side := Vector3.UP.cross(fwd).normalized()
	var center := (start + end) * 0.5 + Vector3.UP * (height * 0.5)
	var xf := Transform3D(Basis(fwd, Vector3.UP, side), center)
	_collision_box(parent, xf, Vector3(length, height, 0.2), nm)

## Conteneur nervuré (§4.3) : coque creuse (sol/toit + 2 côtés pleins le long
## de `axis`) + 0/1/2 extrémités ouvertes (`ends_open`, pleine ouverture
## 2.2x2.36 m) + nervures horizontales VISUAL_ONLY (aucune collision propre).
## `axis "x"` place la longueur le long de X (pas de rotation : `size` est
## déjà orienté par l'appelant, comme les autres pièces boîte).
static func container(parent: Node3D, batcher: GeoBatcher, center: Vector3, size: Vector3, color: Color, axis: String = "z", ends_open: int = 0, nm: String = "Container") -> void:
	var wall_t := 0.12
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var shell: Array = []
	shell.append([Vector3(0, -hy + wall_t * 0.5, 0), Vector3(size.x, wall_t, size.z)])
	shell.append([Vector3(0, hy - wall_t * 0.5, 0), Vector3(size.x, wall_t, size.z)])
	var ribs: Array = []
	if axis == "x":
		shell.append([Vector3(0, 0, -hz + wall_t * 0.5), Vector3(size.x, size.y, wall_t)])
		shell.append([Vector3(0, 0, hz - wall_t * 0.5), Vector3(size.x, size.y, wall_t)])
		if ends_open < 2:
			shell.append([Vector3(-hx + wall_t * 0.5, 0, 0), Vector3(wall_t, size.y, size.z)])
		if ends_open < 1:
			shell.append([Vector3(hx - wall_t * 0.5, 0, 0), Vector3(wall_t, size.y, size.z)])
		for i in 3:
			var rx: float = -hx + size.x * float(i + 1) / 4.0
			ribs.append([Vector3(rx, 0, -hz + wall_t), Vector3(0.08, 0.04, size.z - wall_t * 2.0)])
			ribs.append([Vector3(rx, 0, hz - wall_t), Vector3(0.08, 0.04, size.z - wall_t * 2.0)])
	else:
		shell.append([Vector3(-hx + wall_t * 0.5, 0, 0), Vector3(wall_t, size.y, size.z)])
		shell.append([Vector3(hx - wall_t * 0.5, 0, 0), Vector3(wall_t, size.y, size.z)])
		if ends_open < 2:
			shell.append([Vector3(0, 0, -hz + wall_t * 0.5), Vector3(size.x, size.y, wall_t)])
		if ends_open < 1:
			shell.append([Vector3(0, 0, hz - wall_t * 0.5), Vector3(size.x, size.y, wall_t)])
		for i in 3:
			var rz: float = -hz + size.z * float(i + 1) / 4.0
			ribs.append([Vector3(-hx + wall_t, 0, rz), Vector3(0.04, 0.08, size.x - wall_t * 2.0)])
			ribs.append([Vector3(hx - wall_t, 0, rz), Vector3(0.04, 0.08, size.x - wall_t * 2.0)])
	_emit_local_parts(parent, batcher, center, Basis.IDENTITY, shell, color, nm)
	_emit_visual_only(batcher, center, Basis.IDENTITY, ribs, color)

static func _emit_local_parts(parent: Node3D, batcher: GeoBatcher, center: Vector3, basis: Basis, parts: Array, color: Color, nm: String) -> void:
	var i := 0
	for p in parts:
		var local_center: Vector3 = p[0]
		var size: Vector3 = p[1]
		var world_center := center + basis * local_center
		var xf := Transform3D(basis, world_center)
		_collision_box(parent, xf, size, "%s%d" % [nm, i])
		batcher.add_box(xf, size, color)
		i += 1

static func _emit_visual_only(batcher: GeoBatcher, center: Vector3, basis: Basis, parts: Array, color: Color) -> void:
	for p in parts:
		var local_center: Vector3 = p[0]
		var size: Vector3 = p[1]
		var world_center := center + basis * local_center
		batcher.add_box(Transform3D(basis, world_center), size, color)

# ======================================================================
#  building2 (§4.1) : coque à 1-2 étages, portes, fenêtres/meurtrières,
#  dalles à trémie (trou d'escalier 2x6 m), UNE rampe (+ marches visuelles)
#  par étage, toit praticable + parapet optionnel.
# ======================================================================
const _BLD_WALL_T := 0.25
const _BLD_HOLE_W := 2.0
const _BLD_HOLE_D := 6.0   # -> rampe 28° pour un étage de 3.2 m (atan(3.2/6)=28.07°)
const _BLD_RAMP_W := 1.6
const _BLD_PARAPET_T := 0.2

## `doors`: Array de {side:"N|S|E|W", floor:int, y:=-1.0 (remplace floor si
## >=0), offset:=0.0, w:=1.6, h:=2.4}. `windows`: Array de côtés ("N".."W") —
## s'applique à CHAQUE étage de ce côté qui n'a pas déjà de porte. `slit` :
## meurtrières (allège 1.2, hauteur 0.3) au lieu de fenêtres (allège 1.0,
## hauteur 1.0). `stair_side` (défaut "N") : le mur contre lequel la trémie
## d'escalier est collée — À CHOISIR sur un côté SANS porte au rez-de-chaussée
## (sinon la cage d'escalier bloque la porte : constaté en isolant le bake).
## Toit toujours praticable ; `roof_access` perce aussi le toit et ajoute une
## rampe du dernier étage vers le toit.
## `kind` (§-polish, ADDITIF) : matériau peint (Cartoon.painted) pour le sol
## RDC + les dalles d'étage + les murs — "" (défaut) = couleur plate
## d'origine, comportement inchangé. `roof_kind` : matériau du toit/parapet
## SÉPARÉMENT du reste (un toit en tôle sur des murs en planche, par ex.) —
## retombe sur `kind` si vide, jamais sur "" tant que `kind` est renseigné.
static func building2(parent: Node3D, batcher: GeoBatcher, center: Vector3, size: Vector3, color: Color, floors: int, doors: Array, windows: Array, roof_access: bool, parapet: float, slit: bool = false, stair_side: String = "N", nm: String = "Bld", kind: String = "", roof_kind: String = "") -> void:
	floors = maxi(floors, 1)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var bottom := center.y - size.y * 0.5
	var floor_h := size.y / float(floors)
	var wall_t := _BLD_WALL_T
	var hole := _bld_stair_hole_rect(center, size, stair_side)
	var rkind := roof_kind if roof_kind != "" else kind

	# ---- Sol (RDC), pleine dalle — AFFLEURANTE avec le sol extérieur (son
	# dessus est exactement `bottom`, pas `bottom + wall_t/2`) : un rebord de
	# 0.25 m à chaque porte coupait la connexion du navmesh intérieur/extérieur
	# (constaté en isolant le bake — un pas > l'agent_max_climb effectif au
	# seuil, même sous agent_max_climb=0.5, à cause de l'arrondi en voxels).
	box(parent, batcher, Vector3(center.x, bottom - wall_t * 0.5, center.z), Vector3(size.x, wall_t, size.z), color, "%sFloor0" % nm, 0.0, false, kind)

	# ---- Dalles d'étage (une par transition, avec trémie 2x6) ----
	for f in range(1, floors):
		var slab_y := bottom + floor_h * float(f)
		_bld_slab_with_hole(parent, batcher, center, size, slab_y, wall_t, hole, color, "%sSlab%d" % [nm, f], kind)

	# ---- Toit : praticable toujours ; trémie + parapet si roof_access ----
	var roof_y := bottom + size.y
	if roof_access:
		_bld_slab_with_hole(parent, batcher, center, size, roof_y, wall_t, hole, color, "%sRoof" % nm, rkind)
	else:
		box(parent, batcher, Vector3(center.x, roof_y - wall_t * 0.5, center.z), Vector3(size.x, wall_t, size.z), color, "%sRoof" % nm, 0.0, false, rkind)
	if parapet > 0.0:
		var pt := _BLD_PARAPET_T
		var py := roof_y + parapet * 0.5
		box(parent, batcher, Vector3(center.x, py, center.z - hz + pt * 0.5), Vector3(size.x, parapet, pt), color, "%sParN" % nm, 0.0, false, rkind)
		box(parent, batcher, Vector3(center.x, py, center.z + hz - pt * 0.5), Vector3(size.x, parapet, pt), color, "%sParS" % nm, 0.0, false, rkind)
		box(parent, batcher, Vector3(center.x - hx + pt * 0.5, py, center.z), Vector3(pt, parapet, size.z), color, "%sParW" % nm, 0.0, false, rkind)
		box(parent, batcher, Vector3(center.x + hx - pt * 0.5, py, center.z), Vector3(pt, parapet, size.z), color, "%sParE" % nm, 0.0, false, rkind)

	# ---- Murs par étage/côté : portes en priorité, sinon fenêtres, sinon plein ----
	for f in floors:
		var y0 := bottom + floor_h * float(f)
		var y1 := y0 + floor_h
		for side in ["N", "S", "E", "W"]:
			_bld_wall_side(parent, batcher, center, size, f, y0, y1, side, wall_t, doors, windows, slit, color, nm, kind)

	# ---- Rampes internes (une par transition d'étage) + rampe de toit ----
	var ep := _bld_ramp_endpoints(hole, stair_side)
	var ep_lo: Vector3 = ep["lo"]
	var ep_hi: Vector3 = ep["hi"]
	for f in range(1, floors):
		var y_from: float = bottom + floor_h * float(f - 1)
		var y_to: float = bottom + floor_h * float(f)
		_ramp_with_treads(parent, batcher, Vector3(ep_lo.x, y_from, ep_lo.z), Vector3(ep_hi.x, y_to, ep_hi.z), _BLD_RAMP_W, color, "%sRamp%d" % [nm, f], 8, 0.2)
	if roof_access:
		var y_from2: float = bottom + floor_h * float(floors - 1)
		_ramp_with_treads(parent, batcher, Vector3(ep_lo.x, y_from2, ep_lo.z), Vector3(ep_hi.x, roof_y, ep_hi.z), _BLD_RAMP_W, color, "%sRampRoof" % nm, 8, 0.2)

## Rectangle de la trémie d'escalier (2 m x `_BLD_HOLE_D`) collée au mur
## `stair_side`, en coordonnées MONDE.
static func _bld_stair_hole_rect(center: Vector3, size: Vector3, stair_side: String) -> Dictionary:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	match stair_side:
		"S":
			return {"x_lo": center.x - 1.0, "x_hi": center.x + 1.0, "z_lo": maxf(center.z + hz - _BLD_HOLE_D, center.z - hz + 0.1), "z_hi": center.z + hz}
		"E":
			return {"x_lo": maxf(center.x + hx - _BLD_HOLE_D, center.x - hx + 0.1), "x_hi": center.x + hx, "z_lo": center.z - 1.0, "z_hi": center.z + 1.0}
		"W":
			return {"x_lo": center.x - hx, "x_hi": minf(center.x - hx + _BLD_HOLE_D, center.x + hx - 0.1), "z_lo": center.z - 1.0, "z_hi": center.z + 1.0}
		_:
			return {"x_lo": center.x - 1.0, "x_hi": center.x + 1.0, "z_lo": center.z - hz, "z_hi": minf(center.z - hz + _BLD_HOLE_D, center.z + hz - 0.1)}

## Point bas (au mur, y rempli par l'appelant) et point haut (6 m à
## l'intérieur) de la rampe, selon le côté de la trémie.
static func _bld_ramp_endpoints(hole: Dictionary, stair_side: String) -> Dictionary:
	var x_lo: float = hole["x_lo"]
	var x_hi: float = hole["x_hi"]
	var z_lo: float = hole["z_lo"]
	var z_hi: float = hole["z_hi"]
	match stair_side:
		"S":
			var cx: float = (x_lo + x_hi) * 0.5
			return {"lo": Vector3(cx, 0, z_hi), "hi": Vector3(cx, 0, z_lo)}
		"E":
			var cz: float = (z_lo + z_hi) * 0.5
			return {"lo": Vector3(x_hi, 0, cz), "hi": Vector3(x_lo, 0, cz)}
		"W":
			var cz2: float = (z_lo + z_hi) * 0.5
			return {"lo": Vector3(x_lo, 0, cz2), "hi": Vector3(x_hi, 0, cz2)}
		_:
			var cx2: float = (x_lo + x_hi) * 0.5
			return {"lo": Vector3(cx2, 0, z_lo), "hi": Vector3(cx2, 0, z_hi)}

## Dalle pleine sauf la trémie rectangulaire `hole` (collée à UN bord du
## bâtiment, quel qu'il soit) — décomposée en <= 3 boîtes (bande au-delà du
## trou + 2 bandes encadrant le trou).
static func _bld_slab_with_hole(parent: Node3D, batcher: GeoBatcher, center: Vector3, size: Vector3, y: float, wall_t: float, hole: Dictionary, color: Color, nm: String, kind: String = "") -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var x_lo: float = hole["x_lo"]
	var x_hi: float = hole["x_hi"]
	var z_lo: float = hole["z_lo"]
	var z_hi: float = hole["z_hi"]
	if is_equal_approx(z_lo, center.z - hz) or is_equal_approx(z_hi, center.z + hz):
		var far_lo: float
		var far_hi: float
		if is_equal_approx(z_lo, center.z - hz):
			far_lo = z_hi
			far_hi = center.z + hz
		else:
			far_lo = center.z - hz
			far_hi = z_lo
		if far_hi - far_lo > 0.05:
			var fd := far_hi - far_lo
			box(parent, batcher, Vector3(center.x, y, far_lo + fd * 0.5), Vector3(size.x, wall_t, fd), color, nm + "F", 0.0, false, kind)
		var side_w := hx - (x_hi - x_lo) * 0.5
		if side_w > 0.05:
			var hd := z_hi - z_lo
			var hcz := (z_lo + z_hi) * 0.5
			box(parent, batcher, Vector3(center.x - hx + side_w * 0.5, y, hcz), Vector3(side_w, wall_t, hd), color, nm + "L", 0.0, false, kind)
			box(parent, batcher, Vector3(center.x + hx - side_w * 0.5, y, hcz), Vector3(side_w, wall_t, hd), color, nm + "R", 0.0, false, kind)
	else:
		var far_lo2: float
		var far_hi2: float
		if is_equal_approx(x_lo, center.x - hx):
			far_lo2 = x_hi
			far_hi2 = center.x + hx
		else:
			far_lo2 = center.x - hx
			far_hi2 = x_lo
		if far_hi2 - far_lo2 > 0.05:
			var fd2 := far_hi2 - far_lo2
			box(parent, batcher, Vector3(far_lo2 + fd2 * 0.5, y, center.z), Vector3(fd2, wall_t, size.z), color, nm + "F", 0.0, false, kind)
		var side_d := hz - (z_hi - z_lo) * 0.5
		if side_d > 0.05:
			var hd2 := x_hi - x_lo
			var hcx := (x_lo + x_hi) * 0.5
			box(parent, batcher, Vector3(hcx, y, center.z - hz + side_d * 0.5), Vector3(hd2, wall_t, side_d), color, nm + "L", 0.0, false, kind)
			box(parent, batcher, Vector3(hcx, y, center.z + hz - side_d * 0.5), Vector3(hd2, wall_t, side_d), color, nm + "R", 0.0, false, kind)

## Doors matching this (side, floor) — offset "y" overrides the floor's own
## ground level.
static func _bld_doors_for(doors: Array, side: String, floor_idx: int) -> Array:
	var out: Array = []
	for entry in doors:
		var d: Dictionary = entry
		if String(d.get("side", "")) != side:
			continue
		if d.has("y") or int(d.get("floor", 0)) == floor_idx:
			out.append(d)
	return out

## Construit UN pan de mur (un côté, un étage) en perçant portes (priorité)
## ou fenêtres/meurtrières répétées tous les 3 m (si le côté est listé dans
## `windows` et n'a pas de porte à cet étage), sinon plein.
static func _bld_wall_side(parent: Node3D, batcher: GeoBatcher, center: Vector3, size: Vector3, floor_idx: int, y0: float, y1: float, side: String, wall_t: float, doors: Array, windows: Array, slit: bool, color: Color, nm: String, kind: String = "") -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var axis: String
	var fixed: float
	var c_lo: float
	var c_hi: float
	var mid: float
	match side:
		"N":
			axis = "x"; fixed = center.z - hz; c_lo = center.x - hx; c_hi = center.x + hx; mid = center.x
		"S":
			axis = "x"; fixed = center.z + hz; c_lo = center.x - hx; c_hi = center.x + hx; mid = center.x
		"E":
			axis = "z"; fixed = center.x + hx; c_lo = center.z - hz; c_hi = center.z + hz; mid = center.z
		_:
			axis = "z"; fixed = center.x - hx; c_lo = center.z - hz; c_hi = center.z + hz; mid = center.z

	var gaps: Array = []
	var side_doors := _bld_doors_for(doors, side, floor_idx)
	for entry in side_doors:
		var d: Dictionary = entry
		var dw: float = float(d.get("w", 1.6))
		var dh: float = float(d.get("h", 2.4))
		var doff: float = float(d.get("offset", 0.0))
		var dy0: float = float(d["y"]) if d.has("y") else y0
		gaps.append({"c0": mid + doff - dw * 0.5, "c1": mid + doff + dw * 0.5, "y0": dy0, "y1": dy0 + dh})
	if gaps.is_empty() and windows.has(side):
		var wall_len := c_hi - c_lo
		var n := maxi(1, int(floor(wall_len / 3.0)))
		var win_w := 1.2
		var sill: float = 1.2 if slit else 1.0
		var win_h: float = 0.3 if slit else 1.0
		for i in n:
			var t := (float(i) + 0.5) / float(n)
			var cc: float = c_lo + t * wall_len
			gaps.append({"c0": cc - win_w * 0.5, "c1": cc + win_w * 0.5, "y0": y0 + sill, "y1": y0 + sill + win_h})

	_wall_side(parent, batcher, color, "%sW%d%s" % [nm, floor_idx, side], axis, fixed, c_lo, c_hi, y0, y1, wall_t, gaps, kind)

## Construit un pan de mur rectangulaire en perçant une liste d'ouvertures
## ({c0,c1,y0,y1}, coordonnée `c` le long du mur, `y` en absolu). Porte ET
## fenêtres utilisent ce même chemin générique.
static func _wall_side(parent: Node3D, batcher: GeoBatcher, color: Color, nm: String, axis: String, fixed: float, c_lo: float, c_hi: float, y0: float, y1: float, wall_t: float, gaps: Array, kind: String = "") -> void:
	var sorted_gaps: Array = gaps.duplicate()
	sorted_gaps.sort_custom(func(a, b): return float(a["c0"]) < float(b["c0"]))
	var cursor := c_lo
	var idx := 0
	for entry in sorted_gaps:
		var g: Dictionary = entry
		var gc0: float = clampf(float(g["c0"]), c_lo, c_hi)
		var gc1: float = clampf(float(g["c1"]), c_lo, c_hi)
		if gc0 > cursor:
			_wall_span(parent, batcher, color, "%sA%d" % [nm, idx], axis, fixed, cursor, gc0, y0, y1, wall_t, kind)
		var gy0: float = maxf(float(g["y0"]), y0)
		var gy1: float = minf(float(g["y1"]), y1)
		if gc1 > gc0:
			if gy0 > y0:
				_wall_span(parent, batcher, color, "%sB%d" % [nm, idx], axis, fixed, gc0, gc1, y0, gy0, wall_t, kind)
			if gy1 < y1:
				_wall_span(parent, batcher, color, "%sC%d" % [nm, idx], axis, fixed, gc0, gc1, gy1, y1, wall_t, kind)
		cursor = maxf(cursor, gc1)
		idx += 1
	if cursor < c_hi:
		_wall_span(parent, batcher, color, "%sD%d" % [nm, idx], axis, fixed, cursor, c_hi, y0, y1, wall_t, kind)

static func _wall_span(parent: Node3D, batcher: GeoBatcher, color: Color, nm: String, axis: String, fixed: float, c0: float, c1: float, y0: float, y1: float, wall_t: float, kind: String = "") -> void:
	if c1 - c0 < 0.02 or y1 - y0 < 0.02:
		return
	var length := c1 - c0
	var cc := (c0 + c1) * 0.5
	var yy := (y0 + y1) * 0.5
	var hh := y1 - y0
	var center: Vector3
	var size: Vector3
	if axis == "x":
		center = Vector3(cc, yy, fixed)
		size = Vector3(length, hh, wall_t)
	else:
		center = Vector3(fixed, yy, cc)
		size = Vector3(wall_t, hh, length)
	box(parent, batcher, center, size, color, nm, 0.0, false, kind)

# ---- Silhouettes décoratives (mât fin + quelques traverses = peu de collision) ----
static func crane(parent: Node3D, batcher: GeoBatcher, base: Vector3, color: Color, rot_y: float = 0.0, nm: String = "Crane") -> void:
	var pole_h := 10.0
	var b := Basis(Vector3.UP, rot_y)
	box(parent, batcher, base + b * Vector3(0, pole_h * 0.5, 0), Vector3(0.6, pole_h, 0.6), color, nm + "Pole", rot_y)
	box(parent, batcher, base + b * Vector3(3.0, pole_h - 0.3, 0), Vector3(6.5, 0.4, 0.4), color, nm + "Jib", rot_y)
	box(parent, batcher, base + b * Vector3(-1.2, pole_h - 0.3, 0), Vector3(2.0, 0.4, 0.4), color, nm + "Counter", rot_y)

static func water_tower(parent: Node3D, batcher: GeoBatcher, base: Vector3, color: Color, rot_y: float = 0.0, nm: String = "WaterTower") -> void:
	var leg_h := 6.0
	var b := Basis(Vector3.UP, rot_y)
	for dx in [-1.2, 1.2]:
		for dz in [-1.2, 1.2]:
			box(parent, batcher, base + b * Vector3(dx, leg_h * 0.5, dz), Vector3(0.25, leg_h, 0.25), color, nm + "Leg", rot_y)
	box(parent, batcher, base + b * Vector3(0, leg_h + 1.5, 0), Vector3(3.2, 3.0, 3.2), color, nm + "Tank", rot_y)

static func antenna(parent: Node3D, batcher: GeoBatcher, base: Vector3, color: Color, rot_y: float = 0.0, nm: String = "Antenna") -> void:
	var b := Basis(Vector3.UP, rot_y)
	box(parent, batcher, base + b * Vector3(0, 4.0, 0), Vector3(0.2, 8.0, 0.2), color, nm + "Mast", rot_y)
	for i in 3:
		var y: float = 2.0 + float(i) * 2.0
		box(parent, batcher, base + b * Vector3(0, y, 0), Vector3(1.2, 0.08, 0.08), color, "%sBar%d" % [nm, i], rot_y)

# ======================================================================
#  Dispatch données -> géométrie (consommé par MapSetup.gd)
# ======================================================================
## `mat` (maps-spec-v2.md §2/§7.2) : une clé de palette peinte qui l'emporte
## sur `color_key` ("read palette[mat] before color_key") — les deux
## vocabulaires cohabitent : les vieilles pièces n'ont que `color_key`, les
## nouvelles (Cargo/Wasteland) peuvent donner `mat` pour un ton hors des 5
## rôles standards (slate/ochre/teal/bone/sea/rock/adobe, design.md §7).
static func build_piece(parent: Node3D, batcher: GeoBatcher, piece: Dictionary, palette: Dictionary) -> void:
	var color_key := String(piece.get("mat", piece.get("color_key", "wall")))
	var color: Color = palette.get(color_key, Color.GRAY)
	var nm: String = String(piece.get("name", "Piece"))
	var type := String(piece.get("type", "box"))
	# Matériau peint (§7 "apply painted kinds to Kit surfaces") : MapSetup
	# fusionne MapDressing.surface_kinds(map_id) (role -> kind) dans la
	# palette sous la clé "<role>_kind" avant d'appeler build_piece — absent
	# (aucun MapDressing, ou rôle non couvert) => "" => couleur plate d'origine,
	# comportement inchangé pour toute map sans dressing.
	var kind := String(piece.get("kind", palette.get(color_key + "_kind", "")))

	# `prop` (§7.2 nouveau type) : un prop autonome, sans forme Kit derrière —
	# les entrées `dress:` des tables (paysage pur, ex. la coque du navire) et
	# tout prop de collision "cover" qui n'a pas besoin d'être un `box`/
	# `container` Kit. `cover` (déf. vrai) pose la collision du manifeste ;
	# faux = purement visuel (jamais entre y+0.1 et y+2.2 sauf `thin`, §7.1).
	if type == "prop":
		var p_pos: Vector3 = piece["pos"]
		var p_rot_deg := rad_to_deg(float(piece.get("rot_y", 0.0)))
		var p_tint: Color = piece.get("tint", color)
		var p_tints: Dictionary = piece.get("tints", {})
		PropCatalog.place(parent, String(piece["prop"]), p_pos, p_rot_deg, p_tint, bool(piece.get("cover", true)), Vector3.ZERO, p_tints)
		return

	# `skin` (§7.2) : remplace le VISUEL d'une pièce `box` (ou d'un `container`
	# `solid`, visuel §-polish : même collision box() qu'avant, juste le
	# "skin" en plus) par un prop peint, à l'échelle de la boîte — la
	# collision Kit normale reste EXACTEMENT la même (le prop est posé
	# `collide=false`, jamais deux collisions superposées, jamais un pos/size
	# différent de ce que build_piece aurait posé sans skin).
	var skin := String(piece.get("skin", ""))
	var skin_applies := skin != "" and (type == "box" or type == "" or (type == "container" and bool(piece.get("solid", false))))
	if skin_applies:
		var b_pos: Vector3 = piece["pos"]
		var b_size: Vector3 = piece["size"]
		var b_rot: float = float(piece.get("rot_y", 0.0))
		if not bool(piece.get("visual_only", false)):
			_collision_box(parent, _xform_box(b_pos, b_rot), b_size, nm)
		var s_tint: Color = piece.get("tint", color)
		var s_tints: Dictionary = piece.get("tints", {})
		# `skin_rot_y` (§-polish, ADDITIF à `rot_y`, VISUEL SEULEMENT) : un
		# modèle réel n'a pas forcément son axe long orienté comme la boîte
		# Kit (ex. un conteneur .glb a sa longueur sur son Z local — une
		# boîte "axis":"x" a besoin d'un quart de tour pour que le skin
		# s'aligne). Piège vérifié en jeu : réutiliser `rot_y` pour ça
		# tournait AUSSI la collision (`_xform_box` la partage), déplaçant le
		# volume physique réel de 90° — une vraie régression de gameplay, pas
		# qu'un artefact de mesure (attrapée par le test de ligne de vue,
		# qui a vu une brèche de 50 m s'ouvrir là où l'échine centrale du
		# navire est censée bloquer). `skin_rot_y` ne touche jamais `b_rot`/
		# la collision, seulement l'angle passé à PropCatalog.place.
		var skin_extra_rot: float = float(piece.get("skin_rot_y", 0.0))
		PropCatalog.place(parent, skin, b_pos, rad_to_deg(b_rot + skin_extra_rot), s_tint, false, b_size, s_tints)
		return

	match type:
		"ramp":
			ramp(parent, batcher, piece["start"], piece["end"], float(piece["width"]), color, float(piece.get("thickness", 1.0)), nm, kind)
		"stairs":
			stairs(parent, batcher, piece["start"], piece["end"], float(piece["width"]), int(piece.get("steps", 10)), color, nm, kind)
		"catwalk":
			catwalk(parent, batcher, piece["start"], piece["end"], float(piece["width"]), color, nm, kind)
		"fence":
			fence(parent, batcher, piece["start"], piece["end"], float(piece.get("height", 1.6)), color, nm, kind)
		"invisible_wall":
			invisible_wall(parent, piece["start"], piece["end"], float(piece.get("height", 8.0)), nm)
		"container":
			# `solid` (§2 "one collision box instead of the 4-6-body shell") :
			# une simple boîte pleine — utilisé pour les conteneurs "tops"/piliers
			# qui n'ont pas besoin d'un intérieur creux.
			if bool(piece.get("solid", false)):
				box(parent, batcher, piece["pos"], piece["size"], color, nm, float(piece.get("rot_y", 0.0)), false, kind)
			else:
				container(parent, batcher, piece["pos"], piece["size"], color, String(piece.get("axis", "z")), int(piece.get("ends_open", 0)), nm)
		"building2":
			# `roof_kind` (piece dict, ADDITIF) : matériau du toit/parapet
			# séparé de celui des murs/dalles (ex. tôle rouillée sur planches) —
			# retombe sur `kind` (le rôle "wall") si absent.
			var roof_kind := String(piece.get("roof_kind", palette.get(color_key + "_roof_kind", "")))
			building2(parent, batcher, piece["pos"], piece["size"], color, int(piece.get("floors", 1)), (piece.get("doors", []) as Array), (piece.get("windows", []) as Array), bool(piece.get("roof_access", false)), float(piece.get("parapet", 0.0)), bool(piece.get("slit", false)), String(piece.get("stair_side", "N")), nm, kind, roof_kind)
		"crane":
			crane(parent, batcher, piece["pos"], color, float(piece.get("rot_y", 0.0)), nm)
		"water_tower":
			water_tower(parent, batcher, piece["pos"], color, float(piece.get("rot_y", 0.0)), nm)
		"antenna":
			antenna(parent, batcher, piece["pos"], color, float(piece.get("rot_y", 0.0)), nm)
		_:
			box(parent, batcher, piece["pos"], piece["size"], color, nm, float(piece.get("rot_y", 0.0)), bool(piece.get("visual_only", false)), kind)

# ======================================================================
#  Géométrie PURE (aucun nœud) pour les tests de validation de layout.
# ======================================================================

## Empreinte XZ EXACTE (pas conservatrice : formule d'AABB d'un rectangle
## tourné) + intervalle vertical d'une pièce de données, sans construire de
## nœud (tests/maps : bornes, lignes de vue).
static func piece_footprint(piece: Dictionary) -> Dictionary:
	## `prop` (§7.2 "piece_footprint: covers prop") : la taille vient du
	## catalogue (aucun champ `size` sur ces pièces), au rot_y donné.
	if piece.has("prop") and piece.has("pos"):
		var pp: Vector3 = piece["pos"]
		var psize: Vector3 = PropCatalog.footprint(String(piece["prop"]))
		var prot: float = float(piece.get("rot_y", 0.0))
		var pc := absf(cos(prot))
		var ps := absf(sin(prot))
		var phx: float = psize.x * 0.5 * pc + psize.z * 0.5 * ps
		var phz: float = psize.x * 0.5 * ps + psize.z * 0.5 * pc
		return {
			"min": Vector2(pp.x - phx, pp.z - phz),
			"max": Vector2(pp.x + phx, pp.z + phz),
			"bottom": pp.y,
			"top": pp.y + psize.y,
		}
	if piece.has("pos") and piece.has("size"):
		var pos: Vector3 = piece["pos"]
		var size: Vector3 = piece["size"]
		var rot: float = float(piece.get("rot_y", 0.0))
		var c := absf(cos(rot))
		var s := absf(sin(rot))
		var hx: float = size.x * 0.5 * c + size.z * 0.5 * s
		var hz: float = size.x * 0.5 * s + size.z * 0.5 * c
		return {
			"min": Vector2(pos.x - hx, pos.z - hz),
			"max": Vector2(pos.x + hx, pos.z + hz),
			"bottom": pos.y - size.y * 0.5,
			"top": pos.y + size.y * 0.5,
		}
	if piece.has("start") and piece.has("end"):
		var a: Vector3 = piece["start"]
		var b: Vector3 = piece["end"]
		var t := String(piece.get("type", ""))
		if t == "fence" or t == "invisible_wall":
			var h: float = float(piece.get("height", 1.6))
			var pad: float = 0.1
			return {
				"min": Vector2(minf(a.x, b.x) - pad, minf(a.z, b.z) - pad),
				"max": Vector2(maxf(a.x, b.x) + pad, maxf(a.z, b.z) + pad),
				"bottom": minf(a.y, b.y),
				"top": maxf(a.y, b.y) + h,
			}
		var w: float = float(piece.get("width", 1.0))
		var pad2: float = w * 0.5 + 0.5
		var top_y: float = maxf(a.y, b.y) + 0.3
		if t == "catwalk":
			top_y += 1.0
		return {
			"min": Vector2(minf(a.x, b.x) - pad2, minf(a.z, b.z) - pad2),
			"max": Vector2(maxf(a.x, b.x) + pad2, maxf(a.z, b.z) + pad2),
			"bottom": minf(a.y, b.y),
			"top": top_y,
		}
	# Silhouettes décoratives ("pos" seul) : empreinte approximative fixe.
	if piece.has("pos"):
		var p: Vector3 = piece["pos"]
		var reach := 1.5
		var top := 4.0
		match String(piece.get("type", "")):
			"crane":
				reach = 5.0
				top = 10.5
			"water_tower":
				reach = 1.8
				top = 9.0
			"antenna":
				reach = 0.8
				top = 10.0
		return {"min": Vector2(p.x - reach, p.z - reach), "max": Vector2(p.x + reach, p.z + reach), "bottom": p.y, "top": p.y + top}
	return {"min": Vector2.ZERO, "max": Vector2.ZERO, "bottom": 0.0, "top": 0.0}

## Une pièce casse-t-elle une ligne de vue à hauteur d'œil ? Les murs
## invisibles et les pièces `visual_only` ne comptent jamais (aucune
## collision réelle -> aucun blocage physique).
static func piece_blocks_sight(piece: Dictionary) -> bool:
	if String(piece.get("type", "")) == "invisible_wall":
		return false
	if bool(piece.get("visual_only", false)):
		return false
	var fp := piece_footprint(piece)
	return float(fp["top"]) >= SIGHT_MIN_TOP

## Intersection segment 2D / rectangle 2D (slab method), pure — utilisée par
## tests/maps pour vérifier qu'aucune ligne spawn->spawn ne reste dégagée.
static func segment_intersects_rect2(p0: Vector2, p1: Vector2, rmin: Vector2, rmax: Vector2) -> bool:
	var d := p1 - p0
	var tmin := 0.0
	var tmax := 1.0
	for axis in 2:
		var p0a: float = p0[axis]
		var da: float = d[axis]
		var mn: float = rmin[axis]
		var mx: float = rmax[axis]
		if absf(da) < 1e-9:
			if p0a < mn or p0a > mx:
				return false
		else:
			var t1 := (mn - p0a) / da
			var t2 := (mx - p0a) / da
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return false
	return true
