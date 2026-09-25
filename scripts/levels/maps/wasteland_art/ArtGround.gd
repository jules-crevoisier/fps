## ArtGround.gd
## ART-97 (docs/art/WASTELAND_V4_ART_PLAN.md §3 "Sol (GroundBuilder, visuel
## seul)") — module du registre `WastelandArt.gd` (contrat `apply(parent,
## data) -> void`, §1 R9) : pose, PAR-DESSUS les boîtes de sol du greybox déjà
## construites par `Kit.build_piece` (`G_PlateauW/C/E`, `G_Canyon` —
## `wasteland.gd`, HORS de mon périmètre), un sol peint en relief (bruit +
## piste de la Grand-Rue en "Z" + zones de terre battue + ballast des rails)
## via `GroundBuilder.build(spec)` avec `visual_only: true` (ART-97, additif
## sur `GroundBuilder.gd`) : AUCUNE collision propre — la collision qui compte
## reste celle des boîtes `floor` du greybox, inchangée (§1 R9 "aucun
## CollisionObject3D ajouté dans les bornes"), jamais retouchée ici.
##
## Empreinte de chaque instance = EXACTEMENT celle de sa boîte de sol
## (`pos`/`size` XZ lus dans `data["pieces"]`, jamais recopiés à la main —
## même esprit que R3 "jamais recopiée à la main"), positionnée par
## transformation de nœud sur le DESSUS RÉEL de cette boîte
## (`pos.y + size.y * 0.5`, §3 "trois instances, placées par transformation de
## nœud") : c'est ce qui rend le critère d'acceptation ("sol visuel à +/-8 cm
## des boîtes de sol") vrai par construction, pas par coïncidence — et ce que
## `GroundBuilder.VISUAL_ONLY_HEIGHT_CAP` (8 cm) garde vrai même si une
## combinaison bruit/piste/ornière venait à dépasser ce budget.
##
## Les routes/zones ci-dessous utilisent des coordonnées ABSOLUES (mêmes
## repère et chiffres que `docs/art/WASTELAND_V4_ART_PLAN.md` §3 et
## `docs/research/11_wasteland_v4_layout.md` §5/§9) — partagées TELLES
## QUELLES entre toutes les instances : `height_at`/`weights_at` de
## `GroundBuilder` sont évalués en coordonnées MONDE (`center`/`size` ne
## servent qu'à poser la grille), donc une route qui déborde de l'empreinte
## d'une instance n'y a simplement aucun effet — jamais besoin de découper la
## piste de la Grand-Rue par boîte.
##
## Rails (§3 "maillage d'ArtGround, sans collision, <= 12 cm") : générés ici
## même, en procédural (deux rails + traverses), PAS de dépendance aux
## modules kit v2 de ART-92 (`plank_rail_solid` etc., hors de mon périmètre
## et pas forcément déjà livrés dans la même vague) — seulement
## `Cartoon.painted()`, déjà utilisé par tout le reste du rendu peint.
class_name ArtGround
extends RefCounted

const GroundBuilderScript := preload("res://scripts/levels/ground/GroundBuilder.gd")

## Résolution de grille des instances de sol — assez fine pour lire la piste
## et ses ornières (largeur mini 4 m, ornières à +/-1,5 m), assez grosse pour
## rester bon marché sur ~3 300 m² de plateau (§7 budget perf du plan : "aucune
## ombre sur le semis", ce module n'ajoute qu'un maillage statique de plus).
const _CELL := 1.0

## Noms des boîtes de sol du greybox (`wasteland.gd::_center/_west`, jamais
## retouchés ici) — la mirroir `_mirror_piece` produit "G_PlateauE" depuis
## "G_PlateauW" (suffixe W -> E), donc les 4 sont bien présentes dans
## `data["pieces"]` sans que ce module ait besoin de connaître le miroir.
const _GROUND_BOX_NAMES: PackedStringArray = ["G_PlateauW", "G_PlateauC", "G_PlateauE", "G_Canyon"]
const _CANYON_BOX_NAME := "G_Canyon"

## Bruit doux hors piste/zone — même ordre de grandeur que le défaut de
## GroundBuilder (5 cm), largement sous le plafond visual_only (8 cm) une
## fois combiné à la piste/aux ornières (vérifié par
## `tests/levels/test_ground_builder.gd::
## test_2000_sample_points_stay_within_8cm_of_the_ground_box_top_in_visual_only`,
## qui rejoue exactement cette configuration).
const _PLATEAU_NOISE_AMP := 0.05
const _CANYON_NOISE_AMP := 0.06
const _PLATEAU_SEED := 4
const _CANYON_SEED := 12

## Piste de la Grand-Rue en "Z" (doc §3, coordonnées MONDE) : deux segments
## droits à z=-14,5 (6,2 m de large) reliés par le coude autour du bloc
## Poste/Diligence (4 m de large, x -6,5..-4,6 et 4,6..6,5) — mêmes points que
## `docs/art/WASTELAND_V4_ART_PLAN.md` §3. Ornières à +/-1,5 m (z -16/-13 sur
## le segment ouest), 0,04 m, cohérentes sur tout le tracé (une seule paire
## d'ornières, pas une par segment).
const _GRAND_RUE_RUTS := {"offset": 1.5, "width": 0.9, "depth": 0.04}

static func _grand_rue_roads() -> Array:
	return [
		{
			"points": [Vector2(-44.0, -14.5), Vector2(-6.5, -14.5)],
			"width": 6.2, "depth": 0.06, "ruts": _GRAND_RUE_RUTS,
		},
		{
			"points": [Vector2(-6.5, -14.5), Vector2(-4.6, -9.9), Vector2(4.6, -9.9), Vector2(6.5, -14.5)],
			"width": 4.0, "depth": 0.06, "ruts": _GRAND_RUE_RUTS,
		},
		{
			"points": [Vector2(6.5, -14.5), Vector2(44.0, -14.5)],
			"width": 6.2, "depth": 0.06, "ruts": _GRAND_RUE_RUTS,
		},
	]

## Terre battue claire (doc §3) : cours de spawn (|x| >= 36), Ruelles (|x|
## 16-20, z -11..12), Place (x +/-8, z -11..5), Descente (x +/-4, z 5..13).
## Rectangles en coordonnées MONDE (`Rect2(position=coin MIN, size)`),
## fondus sur 2 m à leur bordure — jamais de relief (paint seulement, §3).
static func _dirt_zones() -> Array:
	return [
		{"rect": Rect2(Vector2(-44.0, -25.0), Vector2(8.0, 37.0)), "paint": "dirt", "feather": 2.0},   # cour FUEL
		{"rect": Rect2(Vector2(36.0, -25.0), Vector2(8.0, 37.0)), "paint": "dirt", "feather": 2.0},    # cour GAS
		{"rect": Rect2(Vector2(-20.0, -11.0), Vector2(4.0, 23.0)), "paint": "dirt", "feather": 1.5},   # Ruelle O
		{"rect": Rect2(Vector2(16.0, -11.0), Vector2(4.0, 23.0)), "paint": "dirt", "feather": 1.5},    # Ruelle E
		{"rect": Rect2(Vector2(-8.0, -11.0), Vector2(16.0, 16.0)), "paint": "dirt", "feather": 2.0},   # Place
		{"rect": Rect2(Vector2(-4.0, 5.0), Vector2(8.0, 8.0)), "paint": "dirt", "feather": 1.5},       # Descente
	]

## Ballast (roche) le long des rails (doc §3) — un ruban peint autour de
## chaque ligne (voir `_ribbon_polygon`), jamais un `road` creusé : un lit de
## ballast se bombe légèrement, il ne se creuse pas (§3 "paint" ne porte
## aucun relief propre, la piste/le bruit suffisent au relief doux existant).
const _BALLAST_HALF_WIDTH := 1.1
const _BALLAST_FEATHER := 0.6

static func _ballast_zones() -> Array:
	var out: Array = []
	for line in _rail_lines():
		out.append({"poly": _ribbon_polygon(line, _BALLAST_HALF_WIDTH), "paint": "rock", "feather": _BALLAST_FEATHER})
	return out


static func apply(parent: Node3D, data: Dictionary) -> void:
	var boxes := _ground_boxes(data)
	if boxes.is_empty():
		return  # carte sans boîtes de sol nommées (ne devrait pas arriver sur wasteland) : no-op sûr.

	var root := Node3D.new()
	root.name = "ArtGround"

	var plateau_roads := _grand_rue_roads()
	var plateau_zones: Array = []
	plateau_zones.append_array(_dirt_zones())
	plateau_zones.append_array(_ballast_zones())

	for box_name in _GROUND_BOX_NAMES:
		if not boxes.has(box_name):
			continue
		var is_canyon := box_name == _CANYON_BOX_NAME
		var ground := _build_ground_instance(
			boxes[box_name] as Dictionary,
			[] if is_canyon else plateau_roads,
			_canyon_zones() if is_canyon else plateau_zones,
			_CANYON_NOISE_AMP if is_canyon else _PLATEAU_NOISE_AMP,
			_CANYON_SEED if is_canyon else _PLATEAU_SEED,
		)
		root.add_child(ground)

	root.add_child(_build_rails())
	parent.add_child(root)


## Gravier du canyon (doc §3 "plus sombre que le plateau") : peint
## majoritairement en roche sur toute l'empreinte, fondu à ses bords pour ne
## pas trancher net contre le plateau voisin.
static func _canyon_zones() -> Array:
	return [
		{"rect": Rect2(Vector2(-44.0, 12.0), Vector2(88.0, 8.0)), "paint": "rock", "feather": 3.0},
	]


## Boîtes de sol nommées (`_GROUND_BOX_NAMES`) trouvées dans `data["pieces"]`
## — jamais recopiées à la main (R3), lues telles que `wasteland.gd` (hors de
## mon périmètre) les construit.
static func _ground_boxes(data: Dictionary) -> Dictionary:
	var out := {}
	for entry in (data.get("pieces", []) as Array):
		var p: Dictionary = entry
		var n := String(p.get("name", ""))
		if n in _GROUND_BOX_NAMES:
			out[n] = p
	return out


## Une instance de sol visuel calée EXACTEMENT sur l'empreinte XZ de `box`
## (une boîte de sol du greybox, `pos`/`size` Kit) et posée sur son dessus
## réel — voir l'en-tête du fichier.
static func _build_ground_instance(box: Dictionary, roads: Array, zones: Array, noise_amp: float, seed: int) -> Node3D:
	var pos: Vector3 = box["pos"]
	var size: Vector3 = box["size"]
	var top: float = pos.y + size.y * 0.5
	var spec := {
		"size": Vector2(size.x, size.z),
		"center": Vector2(pos.x, pos.z),
		"cell": _CELL,
		"visual_only": true,
		"noise_amp": noise_amp,
		"seed": seed,
		"roads": roads,
		"zones": zones,
	}
	var ground := GroundBuilderScript.build(spec)
	ground.name = "ArtGround_%s" % String(box.get("name", "Ground"))
	ground.position.y = top
	return ground


# ================================================================== rails
## Voie de garage (z 9,5, x +/-44 jusqu'aux heurtoirs à +/-3,2) + embranchement
## vers le Wagon (doc §3, coordonnées MONDE, est = miroir strict de l'ouest en
## x) — quatre polylignes, toutes au niveau du plateau (y=0, voir l'en-tête :
## chaque point retombe dans l'empreinte de G_PlateauW/C/E, jamais dans le
## creux du canyon).
static func _rail_lines() -> Array:
	return [
		[Vector2(-44.0, 9.5), Vector2(-3.2, 9.5)],
		[Vector2(44.0, 9.5), Vector2(3.2, 9.5)],
		[Vector2(-11.0, 9.5), Vector2(-9.2, 6.5), Vector2(-8.6, 2.5), Vector2(-6.6, -0.6)],
		[Vector2(11.0, 9.5), Vector2(9.2, 6.5), Vector2(8.6, 2.5), Vector2(6.6, -0.6)],
	]

const _RAIL_GAUGE := 1.0
const _RAIL_WIDTH := 0.08
const _RAIL_HEIGHT := 0.07
const _TIE_SPACING := 0.6
const _TIE_LENGTH := 1.6
const _TIE_WIDTH := 0.22
const _TIE_HEIGHT := 0.05

## Maillage procédural (deux rails + traverses), SANS collision — un
## `MeshInstance3D` de plus sous `ArtGround`, jamais un `CollisionObject3D`
## (§1 R9). Hauteur totale <= 12 cm (contrat §3) : traverses 5 cm + rails
## posés dessus jusqu'à 7 cm de plus, 12 cm au total pile sur le plafond.
static func _build_rails() -> Node3D:
	var root := Node3D.new()
	root.name = "ArtGroundRails"

	var ties_st := SurfaceTool.new()
	ties_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rails_st := SurfaceTool.new()
	rails_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for line_v in _rail_lines():
		var line: Array = line_v
		_emit_ties(ties_st, line)
		_emit_rail_pair(rails_st, line)

	var ties_inst := MeshInstance3D.new()
	ties_inst.name = "Ties"
	ties_st.generate_normals()
	ties_inst.mesh = ties_st.commit()
	ties_inst.material_override = Cartoon.painted(&"wood_planks")
	root.add_child(ties_inst)

	var rails_inst := MeshInstance3D.new()
	rails_inst.name = "Rails"
	rails_st.generate_normals()
	rails_inst.mesh = rails_st.commit()
	rails_inst.material_override = Cartoon.painted(&"rust")
	root.add_child(rails_inst)

	return root


static func _emit_rail_pair(st: SurfaceTool, line: Array) -> void:
	var offset := _RAIL_GAUGE * 0.5
	_emit_offset_beam(st, line, offset, _RAIL_WIDTH, _TIE_HEIGHT, _TIE_HEIGHT + _RAIL_HEIGHT)
	_emit_offset_beam(st, line, -offset, _RAIL_WIDTH, _TIE_HEIGHT, _TIE_HEIGHT + _RAIL_HEIGHT)


## Un des deux rails : un ruban continu, décalé de `lateral_offset` par
## rapport à l'axe de la voie, extrudé segment par segment (voir
## `_add_beam_segment`) sur toute la polyligne.
static func _emit_offset_beam(st: SurfaceTool, line: Array, lateral_offset: float, width: float, y0: float, y1: float) -> void:
	var offset_points := _offset_polyline(line, lateral_offset)
	for i in range(offset_points.size() - 1):
		_add_beam_segment(st, offset_points[i], offset_points[i + 1], width, y0, y1)


## Traverses (perpendiculaires à la voie) réparties tous les `_TIE_SPACING`
## mètres le long de la polyligne.
static func _emit_ties(st: SurfaceTool, line: Array) -> void:
	var total_len := 0.0
	for i in range(line.size() - 1):
		total_len += (line[i + 1] as Vector2).distance_to(line[i] as Vector2)
	if total_len <= 0.001:
		return
	var travelled := 0.0
	var next_tie := 0.0
	for i in range(line.size() - 1):
		var a: Vector2 = line[i]
		var b: Vector2 = line[i + 1]
		var seg_len := a.distance_to(b)
		if seg_len <= 0.001:
			continue
		var dir := (b - a) / seg_len
		while next_tie <= travelled + seg_len:
			var t := next_tie - travelled
			var center := a + dir * t
			_add_tie(st, center, dir)
			next_tie += _TIE_SPACING
		travelled += seg_len


static func _add_tie(st: SurfaceTool, center: Vector2, dir: Vector2) -> void:
	var half_dir := dir * (_TIE_LENGTH * 0.5)
	var a := center - half_dir
	var b := center + half_dir
	_add_beam_segment(st, a, b, _TIE_WIDTH, 0.0, _TIE_HEIGHT)


## Boîte extrudée le long du segment `a`->`b` (repère XZ), de `y0` à `y1`,
## large de `width` perpendiculairement au segment — la brique de base de
## tout le maillage des rails.
static func _add_beam_segment(st: SurfaceTool, a: Vector2, b: Vector2, width: float, y0: float, y1: float) -> void:
	var dir := b - a
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	var normal := Vector2(-dir.y, dir.x) * (width * 0.5)
	var p0 := a + normal
	var p1 := a - normal
	var p2 := b - normal
	var p3 := b + normal
	var v0 := Vector3(p0.x, y0, p0.y)
	var v1 := Vector3(p1.x, y0, p1.y)
	var v2 := Vector3(p2.x, y0, p2.y)
	var v3 := Vector3(p3.x, y0, p3.y)
	var v4 := Vector3(p0.x, y1, p0.y)
	var v5 := Vector3(p1.x, y1, p1.y)
	var v6 := Vector3(p2.x, y1, p2.y)
	var v7 := Vector3(p3.x, y1, p3.y)
	_quad(st, v4, v7, v6, v5)  # dessus
	_quad(st, v1, v2, v3, v0)  # dessous
	_quad(st, v0, v3, v7, v4)  # côté +normal
	_quad(st, v2, v1, v5, v6)  # côté -normal
	_quad(st, v3, v2, v6, v7)  # bout b
	_quad(st, v1, v0, v4, v5)  # bout a


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


## Polyligne décalée de `offset` mètres perpendiculairement à sa direction
## locale (moyenne des segments adjacents à chaque sommet intérieur — un
## "miroitage" simple, largement suffisant vu les angles doux de
## l'embranchement, jamais un vrai offset topologique avec anti-collision).
static func _offset_polyline(points: Array, offset: float) -> Array:
	var out: Array = []
	var n := points.size()
	for i in range(n):
		var p: Vector2 = points[i]
		var dir: Vector2
		if i == 0:
			dir = ((points[1] as Vector2) - p).normalized()
		elif i == n - 1:
			dir = (p - (points[i - 1] as Vector2)).normalized()
		else:
			dir = (((points[i + 1] as Vector2) - (points[i - 1] as Vector2))).normalized()
		var normal := Vector2(-dir.y, dir.x)
		out.append(p + normal * offset)
	return out


## Polygone "ruban" autour d'une polyligne (aller sur un côté, retour sur
## l'autre) — sert de zone `poly` (GroundBuilder) pour peindre le ballast
## sans lui donner de relief propre (voir `_ballast_zones`).
static func _ribbon_polygon(points: Array, half_width: float) -> Array:
	var left := _offset_polyline(points, half_width)
	var right := _offset_polyline(points, -half_width)
	right.reverse()
	var out: Array = []
	out.append_array(left)
	out.append_array(right)
	return out
