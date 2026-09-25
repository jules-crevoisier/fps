## DressingKit.gd (ART-87)
## Kit d'habillage procédural réutilisable — « ce qui manque autour des
## modèles 3D déjà posés » : poteaux + câbles qui pendent, clôtures en
## rangée, grappes de props au pied d'un mur (caisses/fûts/pneus/fouillis)
## et un semis fin (cailloux, planches, touffes d'herbe sèche, virevoltants)
## en MultiMesh. API pure et sans état — aucun autoload, aucune dépendance à
## une carte précise — pour que `Layouts.gd`/les dressings de carte ET le
## coin beauté (`scripts/dev/BeautyCorner.gd`) l'appellent tous les deux.
##
## Convention "contact au sol" (identique à PropCatalog.place : maps-spec-v2
## §2 "pos (floor contact)") : chaque position passée en entrée (points,
## anchor, plan du semis) EST la hauteur de sol -- la racine visuelle posée
## là reste à cette hauteur, jamais recentrée. Pour les meshes procéduraux du
## semis (`scatter`, pas de .glb), la géométrie elle-même est décalée d'une
## demi-hauteur vers le haut (voir `_scatter_mesh_for`) : l'ORIGINE DE LA
## TRANSFORME MultiMesh reste donc le point de contact, comme pour tout le
## reste du kit -- un test peut lire `instance_transform.origin.y` sans
## connaître la géométrie interne du mesh.
##
## Props : priorité aux modèles déjà catalogués (`PropCatalog`, résolus
## depuis `assets/models/props/manifest.json`) pour tout ce qui a un
## équivalent construit -- poteaux (`power_pole`), clôtures (`fence_wood`/
## `fence_chainlink`/`fence_broken`), caisses/fûts/pneus/fouillis
## (`wooden_crate`/`oil_drum`/`tyre_stack`/`tyre_ground`/`junk_pile`/
## `scrap_sheets`/`cable_spool`). Formes procédurales SEULEMENT pour les
## petits éléments sans .glb (contrat ART-87) : câbles (caténaire
## approximée), cailloux, planches, touffes d'herbe sèche, virevoltants --
## voir `cable_points`/`_scatter_mesh_for`.
##
## Déterminisme : `cluster_against_wall`/`scatter` prennent un `seed`
## entier -- un `RandomNumberGenerator` local y est semé UNE FOIS en tête de
## fonction, jamais de générateur global (`randi()`/`randf()`), pour que le
## MÊME seed reproduise EXACTEMENT les mêmes transformes d'un appel à
## l'autre (aucun état résiduel entre deux appels).
##
## `exclude` (boîtes interdites, `Array[AABB]`) : un candidat dont la
## position tombe dans UNE de ces boîtes (`AABB.has_point`, qui teste aussi
## Y -- la boîte doit donc couvrir le sol, `position.y <= 0 <= position.y +
## size.y`, pour bloquer un semis au sol) est rejeté et une nouvelle position
## est tirée (jusqu'à `_MAX_PLACEMENT_TRIES` essais, puis l'item est
## simplement sauté -- densité effective plus basse près d'une zone
## interdite, jamais une erreur).
class_name DressingKit
extends RefCounted

const _MAX_PLACEMENT_TRIES := 24

## kind (fence_run) -> nom catalogué (assets/models/props/manifest.json).
const _FENCE_KIND_PROP: Dictionary = {
	"wood": "fence_wood",
	"chainlink": "fence_chainlink",
	"broken": "fence_broken",
}

## kind (cluster_against_wall) -> noms catalogués tirés au hasard (variété).
const _CLUSTER_KIND_PROPS: Dictionary = {
	"crates": ["wooden_crate"],
	"barrels": ["oil_drum"],
	"tires": ["tyre_stack", "tyre_ground"],
	"junk": ["junk_pile", "scrap_sheets", "cable_spool"],
}

## Empreinte d'une grappe (mètres) -- centrée sur `anchor`, étalée le long de
## la tangente au mur (largeur) et poussée vers l'avant du mur (profondeur).
## `density` (props par m²) se lit contre CETTE surface : voir
## `cluster_against_wall`.
const _CLUSTER_WIDTH := 2.4
const _CLUSTER_DEPTH := 1.1
const _CLUSTER_DEPTH_MIN := 0.1

## Mesh procédural (kind -> Mesh) mis en cache, même esprit que
## `PropCatalog._mesh_cache` : un semis dense réutilise la même ressource
## Mesh pour toutes ses instances (c'est tout le principe du MultiMesh).
static var _scatter_mesh_cache: Dictionary = {}


# =====================================================================
#  1. Poteaux + câbles
# =====================================================================

## Points de la courbe d'un câble tendu entre `a` et `b` (mêmes unités,
## mètres), qui pend de `sag` mètres SOUS la corde tendue en son milieu --
## caténaire approximée par une parabole (`4*t*(1-t)`, qui vaut exactement 1
## à t=0.5 : le point médian descend donc d'EXACTEMENT `sag` sous le milieu
## du segment a-b, invariant vérifié par les tests). Fonction PURE (aucun
## nœud, aucun état) : réutilisée par `poles_and_cables` pour bâtir le mesh
## visuel, et directement testable pour la flèche.
static func cable_points(a: Vector3, b: Vector3, sag: float, segments: int = 10) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var n: int = maxi(segments, 1)
	for i in range(n + 1):
		var t: float = float(i) / float(n)
		var p: Vector3 = a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		pts.append(p)
	return pts

## Bâtit le ruban visuel (fin, ≤ 0,05 m d'épaisseur -- "décor fin" §6.5 de la
## bible de style) d'un câble entre `a` et `b`, sous la forme d'une chaîne de
## petites boîtes suivant `cable_points` (même technique que
## `Kit.GeoBatcher` : `SurfaceTool.append_from` par segment, fusionné en UN
## SEUL mesh -- un seul MeshInstance3D par câble).
static func _build_cable_mesh(a: Vector3, b: Vector3, sag: float, tint: Color, radius: float = 0.02, segments: int = 10) -> MeshInstance3D:
	var pts := cable_points(a, b, sag, segments)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(pts.size() - 1):
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var seg: Vector3 = p1 - p0
		var length: float = seg.length()
		if length < 0.0001:
			continue
		var mid: Vector3 = (p0 + p1) * 0.5
		var x_axis: Vector3 = seg / length
		var up_ref: Vector3 = Vector3.UP if absf(x_axis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		var z_axis: Vector3 = x_axis.cross(up_ref).normalized()
		var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
		var bm := BoxMesh.new()
		bm.size = Vector3(length, radius * 2.0, radius * 2.0)
		st.append_from(bm, 0, Transform3D(Basis(x_axis, y_axis, z_axis), mid))
	var mi := MeshInstance3D.new()
	mi.name = "Cable"
	mi.mesh = st.commit()
	mi.material_override = Cartoon.world(tint)
	return mi

## Place un `power_pole` (PropCatalog, contact au sol) à chaque point de
## `points` (Array[Vector3]), puis relie chaque paire de poteaux consécutifs
## par un câble qui pend de `sag` mètres, attaché à `height` mètres du sol
## sur chaque poteau (`points[i] + Vector3(0, height, 0)`). >= 3 poteaux ->
## un seul MultiMesh (PropCatalog.place_many, "≥ 3 usages -> MultiMesh").
## `collision` (ADDITIF, ART-99, vrai par défaut -- comportement historique
## inchangé) : transmis tel quel au `collide` de `PropCatalog.place`/
## `place_many` -- `false` pose les poteaux SANS collision, pour un appelant
## purement visuel (ex. `wasteland_art/ArtDressing.gd`, §1 R9 "aucun
## CollisionObject3D ajouté" : la couche d'art de Wasteland ne doit JAMAIS
## poser de collision, même pour un décor hors des bornes jouables). Le câble
## lui-même (`_build_cable_mesh`) n'a jamais eu de collision, quel que soit ce
## paramètre. Renvoie la racine (Node3D) ajoutée à `parent`.
static func poles_and_cables(parent: Node3D, points: Array, sag: float, height: float, tint: Color = Color.WHITE, collision: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "DressingPoles"
	parent.add_child(root)
	if points.is_empty():
		return root
	var pole_xforms: Array = []
	for p in points:
		pole_xforms.append(Transform3D(Basis(), p))
	if pole_xforms.size() >= 3:
		PropCatalog.place_many(root, "power_pole", pole_xforms, tint, collision)
	else:
		for xf in pole_xforms:
			var t3: Transform3D = xf
			PropCatalog.place(root, "power_pole", t3.origin, 0.0, tint, collision)
	for i in range(points.size() - 1):
		var a: Vector3 = (points[i] as Vector3) + Vector3(0.0, height, 0.0)
		var b: Vector3 = (points[i + 1] as Vector3) + Vector3(0.0, height, 0.0)
		root.add_child(_build_cable_mesh(a, b, sag, tint))
	return root


# =====================================================================
#  2. Clôtures en rangée
# =====================================================================

## Repère (x=local X = axe du panneau) une base orthonormée dont l'axe X
## pointe vers `dir` (norme quelconque, composante Y ignorée) et l'axe Y
## reste vertical -- `dir` est toujours dans le plan XZ ici (clôtures et
## grappes restent au sol), donc `x_axis` est déjà perpendiculaire à
## `Vector3.UP` et la base obtenue est orthonormée sans correction
## supplémentaire.
static func _yaw_basis_from_dir(dir: Vector3) -> Basis:
	var x_axis: Vector3 = Vector3(dir.x, 0.0, dir.z).normalized()
	var y_axis: Vector3 = Vector3.UP
	var z_axis: Vector3 = x_axis.cross(y_axis)
	return Basis(x_axis, y_axis, z_axis)

## Résout `kind` ({"wood","chainlink","broken"}, repli "wood" si inconnu) en
## nom catalogué -- extrait de `fence_run` pour que les tests puissent
## vérifier le repli sans construire de nœuds.
static func _fence_prop_for_kind(kind: String) -> String:
	return String(_FENCE_KIND_PROP.get(kind, _FENCE_KIND_PROP["wood"]))

## Transformes (Array[Transform3D], contact au sol -- `origin.y` = l'altitude
## DU POINT DE DÉPART DU TRONÇON) des panneaux de clôture posés bout à bout
## le long de la polyligne `points` (Array[Vector3]), `kind` in {"wood",
## "chainlink", "broken"}. L'espacement entre panneaux est la largeur RÉELLE
## du panneau catalogué (`PropCatalog.footprint(prop).x`, axe "w" du
## manifeste) : un tronçon plus long que ce pas répète le panneau, aucun
## panneau ne chevauche le suivant. Fonction PURE (aucun nœud) -- la seule
## façon fiable de vérifier le contact au sol/l'espacement en gdUnit4
## headless : `MultiMesh.get_instance_transform()` ne relit PAS les
## transformes posées sous le driver de rendu factice headless (vérifié
## empiriquement, probe autonome hors dépôt -- seul `instance_count` reste
## lisible), donc `fence_run` (qui passe par `PropCatalog.place_many` dès 3
## panneaux) ne peut pas être vérifié transforme par transforme une fois
## posé en scène ; cette fonction, elle, peut l'être directement.
static func fence_transforms(points: Array, kind: String = "wood") -> Array:
	var prop_name: String = _fence_prop_for_kind(kind)
	var panel_width: float = PropCatalog.footprint(prop_name).x
	if panel_width <= 0.01:
		panel_width = 2.2
	var xforms: Array = []
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var seg: Vector3 = b - a
		var dist: float = Vector2(seg.x, seg.z).length()
		if dist < 0.001:
			continue
		var basis := _yaw_basis_from_dir(seg)
		var count: int = maxi(1, int(round(dist / panel_width)))
		var step: float = dist / float(count)
		for s in count:
			var t: float = ((float(s) + 0.5) * step) / dist
			var pos: Vector3 = a.lerp(b, t)
			pos.y = a.y
			xforms.append(Transform3D(basis, pos))
	return xforms

## Pose des panneaux de clôture bout à bout le long de la polyligne
## `points` (Array[Vector3], contact au sol), `kind` in {"wood",
## "chainlink", "broken"} (`_FENCE_KIND_PROP`, repli "wood" si inconnu) --
## voir `fence_transforms` pour le calcul. >= 3 panneaux au total -> un seul
## MultiMesh. `collision` (ADDITIF, ART-99, vrai par défaut -- comportement
## historique inchangé) : transmis tel quel au `collide` de `PropCatalog.
## place`/`place_many`, même contrat que `poles_and_cables` ci-dessus.
## Renvoie la racine (Node3D).
static func fence_run(parent: Node3D, points: Array, kind: String = "wood", tint: Color = Color.WHITE, collision: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "DressingFence_%s" % kind
	parent.add_child(root)
	var prop_name: String = _fence_prop_for_kind(kind)
	var xforms: Array = fence_transforms(points, kind)
	if xforms.size() >= 3:
		PropCatalog.place_many(root, prop_name, xforms, tint, collision)
	else:
		for xf in xforms:
			var t3: Transform3D = xf
			PropCatalog.place(root, prop_name, t3.origin, rad_to_deg(t3.basis.get_euler().y), tint, collision)
	return root


# =====================================================================
#  3. Grappe de props au pied d'un mur
# =====================================================================

static func _overlaps_any(pos: Vector3, exclude: Array) -> bool:
	for entry in exclude:
		var box: AABB = entry
		if box.has_point(pos):
			return true
	return false

## Transformes (Dictionary, nom catalogué -> Array[Transform3D], contact au
## sol -- `origin.y` = `anchor.y`) d'une grappe de props (`kind` in
## {"crates","barrels","tires","junk"} -> `_CLUSTER_KIND_PROPS`) contre un
## mur : `anchor` est un point du pied du mur, `facing` la normale HORS du
## mur (composante Y ignorée, repli `Vector3.FORWARD` si nulle). Les props
## sont dispersés dans une empreinte `_CLUSTER_WIDTH` (le long du mur) x
## `_CLUSTER_DEPTH` (poussés depuis le mur), avec un `RandomNumberGenerator`
## semé par `seed_value` (déterminisme : même seed -> mêmes transformes).
## `density` = props par m² de cette empreinte -> `count = clamp(round(
## density * largeur * profondeur), 1, 16)`. `exclude` : boîtes interdites
## (voir l'en-tête du fichier) -- un candidat qui tombe dedans est retiré,
## jusqu'à `_MAX_PLACEMENT_TRIES` essais avant d'abandonner cet item (densité
## localement plus basse, jamais d'erreur). Fonction PURE (aucun nœud) --
## voir `fence_transforms` pour pourquoi c'est la seule façon fiable de
## vérifier déterminisme/contact au sol/exclusion en gdUnit4 headless
## (`MultiMesh.get_instance_transform()` ne relit pas les transformes posées
## sous le driver de rendu factice headless).
static func cluster_transforms(anchor: Vector3, facing: Vector3, kind: String, density: float, seed_value: int, exclude: Array = []) -> Dictionary:
	var props: Array = _CLUSTER_KIND_PROPS.get(kind, _CLUSTER_KIND_PROPS["crates"])
	var normal: Vector3 = Vector3(facing.x, 0.0, facing.z)
	if normal.length_squared() < 0.0001:
		normal = Vector3.FORWARD
	normal = normal.normalized()
	var tangent: Vector3 = Vector3(-normal.z, 0.0, normal.x)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count: int = clampi(int(round(density * _CLUSTER_WIDTH * _CLUSTER_DEPTH)), 1, 16)
	var by_name: Dictionary = {}
	for i in count:
		var prop_name: String = String(props[rng.randi_range(0, props.size() - 1)])
		for attempt in _MAX_PLACEMENT_TRIES:
			var lateral: float = rng.randf_range(-_CLUSTER_WIDTH * 0.5, _CLUSTER_WIDTH * 0.5)
			var depth: float = rng.randf_range(_CLUSTER_DEPTH_MIN, _CLUSTER_DEPTH)
			var pos: Vector3 = anchor + tangent * lateral + normal * depth
			pos.y = anchor.y
			if _overlaps_any(pos, exclude):
				continue
			var yaw: float = rng.randf_range(0.0, TAU)
			if not by_name.has(prop_name):
				by_name[prop_name] = []
			(by_name[prop_name] as Array).append(Transform3D(Basis(Vector3.UP, yaw), pos))
			break
	return by_name

## Empile une grappe de props contre un mur -- voir `cluster_transforms`
## pour le calcul (mêmes paramètres, `seed_value` renommé `seed` ici pour
## coller au contrat, `>= 3` instances du même prop -> un seul MultiMesh).
## `collision` (ADDITIF, ART-99, vrai par défaut -- comportement historique
## inchangé) : transmis tel quel au `collide` de `PropCatalog.place`/
## `place_many`, même contrat que `poles_and_cables`/`fence_run` ci-dessus.
## Renvoie la racine (Node3D) ajoutée à `parent`.
static func cluster_against_wall(parent: Node3D, anchor: Vector3, facing: Vector3, kind: String, density: float, seed: int, tint: Color = Color.WHITE, exclude: Array = [], collision: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "DressingCluster_%s" % kind
	parent.add_child(root)
	var by_name: Dictionary = cluster_transforms(anchor, facing, kind, density, seed, exclude)
	for prop_name in by_name.keys():
		var xforms: Array = by_name[prop_name]
		if xforms.size() >= 3:
			PropCatalog.place_many(root, String(prop_name), xforms, tint, collision)
		else:
			for xf in xforms:
				var t3: Transform3D = xf
				PropCatalog.place(root, String(prop_name), t3.origin, rad_to_deg(t3.basis.get_euler().y), tint, collision)
	return root


# =====================================================================
#  4. Semis fin (cailloux, planches, touffes, virevoltants) en MultiMesh
# =====================================================================

## Teinte par défaut d'un kind de semis (hors des bandes réservées 300-355°
## et 105-145° -- STYLE_BIBLE §1.1.4/§4.4 : la teinte "herbe sèche" reste un
## tan-brun désaturé, jamais un vert franc).
static func _scatter_default_tint(kind: String) -> Color:
	match kind:
		"rock":
			return Color("8c7f72")
		"plank":
			return Color("9c6a42")
		"tuft":
			return Color("b8945c")
		"tumbleweed":
			return Color("a9834f")
	return Color.WHITE

## Mesh procédural d'un kind de semis, mis en cache -- géométrie décalée
## d'une demi-hauteur vers le haut (voir l'en-tête du fichier, "contact au
## sol") pour que l'origine de la transforme MultiMesh reste le point de
## contact. Aucun kind reconnu -> petit cube générique (jamais une erreur).
static func _scatter_mesh_for(kind: String) -> Mesh:
	if _scatter_mesh_cache.has(kind):
		return _scatter_mesh_cache[kind]
	var prim: Mesh
	var half_h: float
	if kind == "rock":
		var bm := BoxMesh.new()
		bm.size = Vector3(0.32, 0.22, 0.28)
		prim = bm
		half_h = bm.size.y * 0.5
	elif kind == "plank":
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(0.9, 0.03, 0.14)
		prim = bm2
		half_h = bm2.size.y * 0.5
	elif kind == "tuft":
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.15
		cm.height = 0.22
		cm.radial_segments = 6
		prim = cm
		half_h = cm.height * 0.5
	elif kind == "tumbleweed":
		var sm := SphereMesh.new()
		sm.radius = 0.24
		sm.height = 0.48
		sm.radial_segments = 8
		sm.rings = 6
		prim = sm
		half_h = sm.height * 0.5
	else:
		var bm3 := BoxMesh.new()
		bm3.size = Vector3(0.3, 0.3, 0.3)
		prim = bm3
		half_h = 0.15
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(prim, 0, Transform3D(Basis(), Vector3(0.0, half_h, 0.0)))
	var mesh := st.commit()
	_scatter_mesh_cache[kind] = mesh
	return mesh

## Transformes (Dictionary, kind -> Array[Transform3D], contact au sol --
## `origin.y` = `y`) d'un semis dense d'éléments procéduraux (`kinds`:
## sous-ensemble de "rock", "plank", "tuft", "tumbleweed") sur `area` (Rect2,
## plan XZ -- `position`/`size` en X et Z), un `RandomNumberGenerator` semé
## par `seed_value` (déterminisme). `density` = éléments par m² de `area` ->
## `total = round(density * area.size.x * area.size.y)`, réparti au hasard
## entre les `kinds` fournis. Chaque instance reçoit une rotation Y et une
## échelle uniforme aléatoires (variation §"variations d'échelle/rotation/
## teinte" du contrat). `exclude` : boîtes interdites, mêmes règles que
## `cluster_transforms`. Fonction PURE (aucun nœud) -- voir `fence_transforms`
## pour pourquoi c'est la seule façon fiable de vérifier déterminisme/contact
## au sol/exclusion en gdUnit4 headless (`MultiMesh.get_instance_transform()`
## ne relit pas les transformes posées sous le driver de rendu factice
## headless).
static func scatter_transforms(area: Rect2, kinds: Array, density: float, seed_value: int, exclude: Array = [], y: float = 0.0) -> Dictionary:
	var by_kind: Dictionary = {}
	for k in kinds:
		by_kind[k] = []
	if kinds.is_empty() or density <= 0.0 or area.size.x <= 0.0 or area.size.y <= 0.0:
		return by_kind
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var total_count: int = int(round(density * area.size.x * area.size.y))
	for i in total_count:
		var kind: String = String(kinds[rng.randi_range(0, kinds.size() - 1)])
		for attempt in _MAX_PLACEMENT_TRIES:
			var x: float = area.position.x + rng.randf() * area.size.x
			var z: float = area.position.y + rng.randf() * area.size.y
			var pos := Vector3(x, y, z)
			if _overlaps_any(pos, exclude):
				continue
			var yaw: float = rng.randf_range(0.0, TAU)
			var scale_mul: float = rng.randf_range(0.8, 1.25)
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_mul)
			(by_kind[kind] as Array).append(Transform3D(basis, pos))
			break
	return by_kind

## Semis dense d'éléments procéduraux en MultiMesh -- voir `scatter_transforms`
## pour le calcul (mêmes paramètres, `seed_value` renommé `seed` ici pour
## coller au contrat ; `tints`, facultatif, kind -> Color, remplace la teinte
## par défaut `_scatter_default_tint`). Un seul MultiMeshInstance3D par kind
## PRÉSENT dans le résultat (0 si aucun candidat n'a survécu à `exclude` pour
## ce kind) -> au plus un draw call par type, jamais plus, quelle que soit la
## densité. Renvoie la racine (Node3D) ajoutée à `parent`.
static func scatter(parent: Node3D, area: Rect2, kinds: Array, density: float, seed: int, exclude: Array = [], tints: Dictionary = {}, y: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "DressingScatter"
	parent.add_child(root)
	var by_kind: Dictionary = scatter_transforms(area, kinds, density, seed, exclude, y)
	for kind in by_kind.keys():
		var xforms: Array = by_kind[kind]
		if xforms.is_empty():
			continue
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Scatter_%s" % kind
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _scatter_mesh_for(String(kind))
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		mmi.multimesh = mm
		mmi.material_override = Cartoon.world(tints.get(kind, _scatter_default_tint(String(kind))))
		root.add_child(mmi)
	return root


# =====================================================================
#  5. Grappes de décor peint Tripo (ART-89) — assets HORS PropCatalog
# =====================================================================
## Les 4 grosses pièces peintes installées par ce contrat (épave, clôture cassée, étal de
## marché, bric-à-brac — tools/ai3d/manifests/painted_env.yaml) ne sont PAS cataloguées
## comme le reste du kit (assets/models/props/manifest.json) : chaque instance charge et
## repeint directement sa PROPRE scène (assets/models/props/wasteland/tripo/*.glb), même
## flux que BeautyCorner._load_painted_tripo/_repaint_painted — dupliqué ici À DESSEIN (ce
## kit reste autonome, sans dépendance à une scène de dev précise ; même convention que
## `ai_import_painted.py`/`ai_restyle.py`, voir leurs en-têtes respectifs), jamais
## `Cartoon.painted()` partagé. Contrat : « variation par rotation, miroir et légère teinte
## (jamais deux voisins identiques au même angle) » — seule façon de distinguer plusieurs
## instances du MÊME fichier .glb (contrairement au reste du kit, `_CLUSTER_KIND_PROPS` tire
## parmi PLUSIEURS noms catalogués ; ces 4 sortes n'en ont chacune qu'UN).

## Sorte (ART-89) -> fichier peint Tripo (assets/models/props/wasteland/tripo/<fichier>.glb).
const TRIPO_KIND_FILE: Dictionary = {
	"car_wreck": "wl_car_wreck",
	"fence_broken": "wl_fence_broken",
	"market_stall": "wl_market_stall",
	"junk_pile": "wl_junk_pile",
}
const _TRIPO_DIR := "res://assets/models/props/wasteland/tripo/"

## Teinte par défaut (légère, hors des bandes réservées 300-355°/105-145° — STYLE_BIBLE
## §1.1.4/§4.4, même contrainte que `_scatter_default_tint`) par sorte Tripo — point de
## départ de la variation par instance, voir `tripo_variants`.
static func _tripo_default_tint(kind: String) -> Color:
	match kind:
		"car_wreck":
			return Color("8a7f74")
		"fence_broken":
			return Color("8c6a4a")
		"market_stall":
			return Color("b8945c")
		"junk_pile":
			return Color("7d7166")
	return Color.WHITE

## Variantes pures (Array[Dictionary] {yaw_deg, mirror, tint}, une par instance parmi
## `count`) pour `count` instances CONSÉCUTIVES de la sorte peinte Tripo `kind`. Un
## `RandomNumberGenerator` local semé UNE FOIS par `seed_value` (déterminisme, même contrat
## que le reste du fichier — voir l'en-tête). `base_yaw_deg` : orientation "neutre" (fournie
## par l'appelant, ex. alignée sur une rue ou une façade — ces 4 sortes vivent HORS
## PropCatalog, donc aucune polyligne à déduire ici, contrairement à `fence_transforms`) ;
## chaque instance reçoit un écart aléatoire dans [-yaw_jitter_deg, yaw_jitter_deg] autour de
## cette base, un miroir latéral 50/50 (`mirror`, voir `tripo_row` pour son application —
## Godot retourne automatiquement l'ordre des faces d'une transforme à déterminant négatif,
## donc `cull_back` du shader ink_toon reste correct), et une teinte dérivée de
## `_tripo_default_tint(kind)` (± une petite variation de luminosité par canal, jamais assez
## pour sortir des bandes réservées). Contrat « jamais deux voisins identiques au même
## angle » : si l'instance i reçoit EXACTEMENT le même (yaw arrondi au degré, miroir) que
## l'instance i-1, un décalage fixe (la moitié du jitter, signe opposé au miroir tiré) est
## appliqué — garantit qu'aucune paire CONSÉCUTIVE ne partage la même silhouette, quel que
## soit le seed ou `yaw_jitter_deg` (> 0).
static func tripo_variants(kind: String, count: int, seed_value: int, base_yaw_deg: float = 0.0, yaw_jitter_deg: float = 20.0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var base_tint: Color = _tripo_default_tint(kind)
	var out: Array = []
	var prev_yaw: float = INF
	var prev_mirror: bool = false
	for i in count:
		var yaw: float = base_yaw_deg + rng.randf_range(-yaw_jitter_deg, yaw_jitter_deg)
		var mirror: bool = rng.randf() < 0.5
		if i > 0 and is_equal_approx(round(yaw), round(prev_yaw)) and mirror == prev_mirror:
			yaw += (yaw_jitter_deg * 0.5) * (-1.0 if mirror else 1.0)
		var shade: float = rng.randf_range(-0.06, 0.06)
		var tint := Color(
			clampf(base_tint.r + shade, 0.0, 1.0),
			clampf(base_tint.g + shade, 0.0, 1.0),
			clampf(base_tint.b + shade, 0.0, 1.0))
		out.append({"yaw_deg": yaw, "mirror": mirror, "tint": tint})
		prev_yaw = yaw
		prev_mirror = mirror
	return out

## Positions (Array[Vector3], contact au sol — `origin.y` = l'altitude DU POINT DE DÉPART du
## tronçon, même convention que `fence_transforms`) de props posés bout à bout le long de la
## polyligne `points`, espacés de `spacing` mètres. Ces 4 sortes vivent HORS PropCatalog (voir
## l'en-tête de cette section) : pas de `PropCatalog.footprint()` à interroger, `spacing` est
## fourni explicitement par l'appelant (largeur réelle de l'asset posé, mesurée au
## turntable). Fonction PURE (aucun nœud, aucune charge de ressource) — même raison que
## `fence_transforms`/`cluster_transforms` : la seule façon fiable de vérifier
## déterminisme/contact au sol en gdUnit4 headless (voir l'en-tête du fichier de test).
static func tripo_row_positions(points: Array, spacing: float) -> Array:
	var out: Array = []
	var step: float = maxf(spacing, 0.01)
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var seg: Vector3 = b - a
		var dist: float = Vector2(seg.x, seg.z).length()
		if dist < 0.001:
			continue
		var count: int = maxi(1, int(round(dist / step)))
		var seg_step: float = dist / float(count)
		for s in count:
			var t: float = ((float(s) + 0.5) * seg_step) / dist
			var pos: Vector3 = a.lerp(b, t)
			pos.y = a.y
			out.append(pos)
	return out

## Charge et repeint (teinte incluse) une instance de la sorte Tripo `kind` (voir
## `TRIPO_KIND_FILE`) — même flux que BeautyCorner._load_painted_tripo/_repaint_painted
## (dupliqué ici, voir l'en-tête de cette section), ou `null` si `kind` est inconnue ou le
## fichier introuvable (jamais un crash — même contrat qu'un nom PropCatalog inconnu, voir
## `PropCatalog.place`). Fonction PUBLIQUE : BeautyCorner (et tout futur dressing de carte)
## l'appelle directement pour les instances placées à la main (position/rotation choisies à
## l'image, ex. les épaves), sans passer par `tripo_row`.
static func load_tripo(kind: String, tint: Color = Color.WHITE) -> Node3D:
	var file: String = String(TRIPO_KIND_FILE.get(kind, ""))
	if file.is_empty():
		push_warning("DressingKit: sorte Tripo inconnue « %s »" % kind)
		return null
	var packed := load(_TRIPO_DIR + file + ".glb") as PackedScene
	if packed == null:
		push_warning("DressingKit: fichier Tripo introuvable pour la sorte « %s »" % kind)
		return null
	var inst := packed.instantiate() as Node3D
	_repaint_tripo(inst, tint)
	return inst

static func _repaint_tripo(node: Node, tint: Color) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mi := node as MeshInstance3D
		for i in range(mi.mesh.get_surface_count()):
			var src: Material = mi.get_surface_override_material(i)
			if src == null:
				src = mi.mesh.surface_get_material(i)
			var tex := Cartoon.texture_from_imported_material(src)
			mi.set_surface_override_material(i, Cartoon.painted_texture_prop(tex, tint))
	for c in node.get_children():
		_repaint_tripo(c, tint)

static func _collect_tripo_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_tripo_meshes(c, out)

## Boîte de collision simple sur l'AABB RÉELLE du maillage importé (contrat : « collisions
## boîtes, jamais le maillage IA ») — même calcul que
## BeautyCorner._add_box_collision_from_aabb (dupliqué ici, ce kit reste autonome). Sans effet
## si `inst` ne porte aucun MeshInstance3D (jamais une erreur).
static func _box_collision_from_aabb(parent: Node3D, inst: Node3D, nm: String) -> void:
	var meshes: Array = []
	_collect_tripo_meshes(inst, meshes)
	if meshes.is_empty():
		return
	var box := AABB()
	var first := true
	for entry in meshes:
		var mi: MeshInstance3D = entry
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var body := StaticBody3D.new()
	body.name = "Collision_%s" % nm
	body.position = box.get_center()
	parent.add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	body.add_child(col)

## Place une rangée de props peints Tripo de la sorte `kind` le long de la polyligne
## `points` (contact au sol — voir `tripo_row_positions`), espacés de `spacing` mètres.
## Variation par instance (rotation/miroir/teinte, voir `tripo_variants`) autour de
## `base_yaw_deg`, collision boîte par instance (contrat) SI `collision` est vrai (ADDITIF,
## ART-99, vrai par défaut — comportement historique inchangé pour tout appelant existant,
## dont `test_tripo_row_places_one_instance_per_position_with_a_box_collision_each`).
## `collision = false` saute entièrement `_box_collision_from_aabb` : c'est le mode qu'un
## dressing PUREMENT VISUEL doit utiliser (`wasteland_art/ArtLandmarks.gd`/`ArtDressing.gd`,
## §1 R9 du plan d'art « aucun CollisionObject3D ajouté » — la couche d'art de Wasteland ne
## pose jamais de collision, même pour une rangée posée hors des bornes jouables). Une
## polyligne trop courte (< 2 points, ou un seul tronçon de longueur nulle) -> racine vide,
## jamais une erreur. Renvoie la racine (Node3D) ajoutée à `parent`.
static func tripo_row(parent: Node3D, points: Array, kind: String, spacing: float, seed_value: int, base_yaw_deg: float = 0.0, yaw_jitter_deg: float = 20.0, collision: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "DressingTripo_%s" % kind
	parent.add_child(root)
	var positions: Array = tripo_row_positions(points, spacing)
	if positions.is_empty():
		return root
	var variants: Array = tripo_variants(kind, positions.size(), seed_value, base_yaw_deg, yaw_jitter_deg)
	for i in positions.size():
		var pos: Vector3 = positions[i]
		var variant: Dictionary = variants[i]
		var tint: Color = variant["tint"]
		var inst := load_tripo(kind, tint)
		if inst == null:
			continue
		inst.position = pos
		inst.rotation_degrees.y = variant["yaw_deg"]
		if variant["mirror"]:
			inst.scale.x = -1.0
		root.add_child(inst)
		if collision:
			_box_collision_from_aabb(root, inst, "%s_%d" % [kind, i])
	return root
