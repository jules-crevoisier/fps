## test_wasteland_art_parity.gd
## ART-91 (fondation, docs/art/WASTELAND_V4_ART_PLAN.md §1 "Coexistence de
## l'art et de la collision") — verrouille le CONTRAT que chaque tâche d'art
## suivante (ART-92..100) doit respecter, avant qu'aucune d'elles n'existe :
##
##  1. `test_collision_hash_identical_with_and_without_art` (R9 "aucun
##     CollisionObject3D ajouté... la collision reste celle du greybox") :
##     la collision RÉELLEMENT posée par `MapSetup`/`Kit` (transform + taille
##     de chaque `CollisionShape3D`, sous `nav_region`) est identique AVANT/
##     APRÈS `WastelandArt.load_modules` — aujourd'hui un no-op (aucun module
##     ART-94..100 n'existe encore), donc trivialement vert ; le test reste
##     en place pour que la PREMIÈRE tâche qui ajoute un module casse
##     immédiatement s'il pose la moindre collision.
##  2. `test_all_11_building2_have_openings_matching_real_collision` (R3
##     "toutes les pièces et les ouvertures des 11 building2" + "jamais
##     recopiée à la main") : `Kit.door_world_rect`/`Kit.window_world_rects`
##     (consommées par `tools/art/export_v4_openings.gd`, la source de vérité
##     JSON) sont vérifiées contre un raycast RÉEL — le centre d'une ouverture
##     est dégagé, juste à côté (dans le mur) c'est bloqué.
##  3. `test_parity_probe_3000_samples_and_five_pp` (§0.1/R1 "sonde de parité
##     ... bloque toute livraison" ; critère : "3 000 paires navmesh et les 5
##     PP, raycast collision contre raycast visuel, <= 0,5 % d'écart global et
##     0 sur les PP") : échantillonne les 4 faces × tous les étages des 11
##     `building2`, compare un raycast contre la collision RÉELLE (calque 1)
##     à un raycast contre un maillage trimesh RECONSTRUIT depuis le VISUEL
##     RÉELLEMENT rendu (calque 2, les `MeshInstance3D` fusionnées par
##     `Kit.GeoBatcher.flush`) — aujourd'hui les deux viennent du MÊME code
##     (`Kit.build_piece`, aucune peau posée), donc 0 % d'écart ; une future
##     tâche qui pose une peau (`visual:false` + skin) mal alignée fera
##     remonter cet écart, pas un artefact de mesure.
##  4. `test_parity_probe_flags_a_1m_control_block` (critère : "un bloc témoin
##     de 1 m doit la faire échouer") : exerce la MÊME machinerie de
##     comparaison (§3) sur une géométrie synthétique décalée de 1 m — prouve
##     que la sonde détecte réellement un écart, pas seulement qu'elle passe
##     faute de rien à comparer.
##  5. `test_art_is_skipped_in_headless` (R9 "art sauté en headless") :
##     `WastelandArt.is_enabled()` observé directement — le contrat de tâche
##     impose `--headless` à CHAQUE lancement gdUnit4, donc cette assertion
##     teste la VRAIE condition, pas une simulation.
extends GdUnitTestSuite

const _OFFSET := Vector3(19200, 0, 0)
## Scène synthétique du test 4 — isolée de toute autre géométrie de test
## (aucun autre fichier n'utilise cette zone, voir les `_OFFSET` de
## `test_wasteland.gd`/`test_wasteland_markers.gd`/`test_wasteland_los3d.gd`).
const _CANARY_OFFSET := Vector3(50000, 0, 0)

## Calques physiques du PROBE (indépendants de `scripts/core/PhysicsLayers.gd`
## — jamais posés sur une pièce de gameplay réelle, seulement sur les corps
## JETABLES que CE test ajoute lui-même pour comparer) : 1 = collision réelle
## (défaut de `Kit._collision_box`, inchangé), 2 = "vérité visuelle" (trimesh
## reconstruit depuis les `MeshInstance3D` réellement rendues,
## `collision_mask = 0` : ne bloque jamais rien, sert seulement au raycast).
const _LAYER_COLLISION := 1
const _LAYER_VISUAL := 2

## Échantillonnage (test 3) : chaque face d'un `building2`, tous ses étages,
## avec une marge de `_CORNER_INSET` par bout (évite les trims/coins d'ART-71,
## purement visuels mais qui n'existent que près des arêtes) et 3 hauteurs
## par étage. Rayon de `_WALL_RAY_MARGIN` de chaque côté du plan du mur
## (épaisseur réelle 0,25 m, `Kit._BLD_WALL_T`) : large marge sans jamais
## déborder sur un mur voisin (bâtiments les plus proches à plusieurs mètres).
const _CORNER_INSET := 0.3
const _ALONG_STEP := 0.4
const _HEIGHT_FRACS := [0.25, 0.5, 0.75]
const _WALL_RAY_MARGIN := 0.4
const _MIN_SAMPLE_COUNT := 3000

## Tolérance par paire (R3 "l'outil perce la carte à ±2 cm") et seuils du
## critère d'acceptation ("<= 0,5 % d'écart global et 0 sur les PP").
const _OPENING_TOLERANCE_M := 0.02
const _GLOBAL_MISMATCH_MAX_RATIO := 0.005

## Les 5 positions fortes (docs/art/WASTELAND_V4_ART_PLAN.md §1 R1 "Les
## façades PP sont : Hôtel sud, Banque sud, Saloon ouest côté est, Saloon est
## côté ouest et Wagon nord... sur TOUTE LEUR HAUTEUR") : (bâtiment, côté),
## tous étages confondus.
const _PP_ZONES := [
	["Hotel", "S"], ["Banque", "S"], ["SaloonW", "E"], ["SaloonE", "W"], ["Wagon", "N"],
]


func _setup() -> MapSetup:
	var setup := MapSetup.new()
	setup.map_id = "wasteland"
	setup.position = _OFFSET
	add_child(setup)
	return setup


func _teardown(setup: Node) -> void:
	remove_child(setup)
	setup.free()
	await get_tree().physics_frame


# ======================================================================
#  Test 5 — R9 "art sauté en headless".
# ======================================================================
func test_art_is_skipped_in_headless() -> void:
	# Le contrat de tâche impose `--headless` à CHAQUE lancement gdUnit4 (voir
	# la commande de la tâche) : cette assertion observe la VRAIE condition
	# telle qu'elle tourne ici même, sans la simuler.
	assert_bool(WastelandArt.is_enabled()).append_failure_message("DisplayServer=%s : la couche d'art devrait être désactivée sous gdUnit4 (--headless)" % DisplayServer.get_name()).is_false()


# ======================================================================
#  Test 1 — R9 "collision inchangée avec/sans art".
# ======================================================================
func test_collision_hash_identical_with_and_without_art() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var before := _collision_signature(setup.nav_region)
	# Dispatch NU (voir `WastelandArt.gd`, "pourquoi exposée à part") : exerce
	# le VRAI mécanisme de chargement des modules même sous gdUnit4 (toujours
	# headless, où `apply_all` court-circuiterait tout).
	WastelandArt.load_modules(setup.nav_region, WastelandLayout.data())
	await get_tree().physics_frame
	var after := _collision_signature(setup.nav_region)
	assert_int(after.size()).append_failure_message("load_modules a changé le nombre de corps de collision (%d -> %d)" % [before.size(), after.size()]).is_equal(before.size())
	assert_array(after).append_failure_message("load_modules a changé la collision réellement posée alors qu'aucun module n'existe encore").is_equal(before)
	await _teardown(setup)


## Signature canonique (triée, indépendante de l'ordre des enfants) de TOUTE
## la collision réellement posée sous `root` (transform monde + taille de
## chaque `BoxShape3D` — toutes les collisions de Kit.gd sont des boîtes).
func _collision_signature(root: Node) -> Array:
	var out: Array = []
	for body in _find_static_bodies(root):
		for shape_child in (body as Node).get_children():
			if shape_child is CollisionShape3D:
				var shp := (shape_child as CollisionShape3D).shape
				var sz := (shp as BoxShape3D).size if shp is BoxShape3D else Vector3(-1, -1, -1)
				out.append("%s|%s" % [(body as Node3D).global_transform, sz])
	out.sort()
	return out


func _find_static_bodies(node: Node) -> Array:
	var out: Array = []
	if node is StaticBody3D and node.collision_layer == 1:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_static_bodies(c))
	return out


func _find_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_mesh_instances(c))
	return out


# ======================================================================
#  Test 2 — R3 "jamais recopiée à la main", vérifiée contre un raycast réel.
# ======================================================================
func test_all_11_building2_have_openings_matching_real_collision() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var space_state := setup.get_world_3d().direct_space_state

	var buildings := _building2_pieces()
	assert_int(buildings.size()).append_failure_message("attendu 11 building2 (5 ouest + 5 miroirs est + Wagon), voir §1 R9 du plan d'art").is_equal(11)

	var checked_openings := 0
	for entry in buildings:
		var piece: Dictionary = entry
		var doors: Array = piece.get("doors", [])
		for d in doors:
			var door: Dictionary = d
			var rect := Kit.door_world_rect(piece, door)
			_assert_opening_matches_collision(space_state, piece, rect, "porte")
			checked_openings += 1
		var doors_by_side_floor := {}
		for d2 in doors:
			var dd: Dictionary = d2
			doors_by_side_floor["%s|%d" % [String(dd.get("side", "N")), int(dd.get("floor", 0))]] = true
		var floors := maxi(int(piece.get("floors", 1)), 1)
		for side in (piece.get("windows", []) as Array):
			for f in floors:
				if doors_by_side_floor.has("%s|%d" % [String(side), f]):
					continue
				for rect2 in Kit.window_world_rects(piece, String(side), f, bool(piece.get("slit", false))):
					_assert_opening_matches_collision(space_state, piece, rect2, "fenêtre")
					checked_openings += 1

	assert_int(checked_openings).append_failure_message("aucune ouverture trouvée sur les 11 building2 — la carte a-t-elle changé de forme ?").is_greater(0)
	await _teardown(setup)


## Une ouverture RÉELLE (§R3) : son centre est dégagé (aucun hit sur un court
## rayon qui la traverse), et juste à côté — dans l'épaisseur du mur, du côté
## OPPOSÉ le long de la face (toujours à l'intérieur du mur pour une ouverture
## qui n'est pas collée à un coin) — un rayon identique est BLOQUÉ. Un
## bâtiment de moins de 2 m de large sur ce côté n'a pas de marge : ignoré
## silencieusement plutôt que de fabriquer un faux échec.
func _assert_opening_matches_collision(space_state: PhysicsDirectSpaceState3D, piece: Dictionary, rect: Dictionary, kind: String) -> void:
	var side := String(rect.get("side", "N"))
	var ax := Kit.wall_axis_info(piece["pos"], piece["size"], side)
	var axis := String(ax["axis"])
	var fixed: float = ax["fixed"]
	var dir := _inward_dir(axis, side)
	var y: float = (float(rect["y0"]) + float(rect["y1"])) * 0.5
	var cx: float
	var cz: float
	if axis == "x":
		cx = (float(rect["x_lo"]) + float(rect["x_hi"])) * 0.5
		cz = fixed
	else:
		cx = fixed
		cz = (float(rect["z_lo"]) + float(rect["z_hi"])) * 0.5
	var center := Vector3(cx, y, cz)
	var open_gap: Variant = _pair_hit_distance(space_state, center - dir * _WALL_RAY_MARGIN + _OFFSET, center + dir * _WALL_RAY_MARGIN + _OFFSET, 0xFFFFFFFF)
	assert_bool(open_gap == null).append_failure_message("%s de %s (%s, étage %d) : le centre de l'ouverture est BLOQUÉ (devrait être dégagé)" % [kind, piece.get("name", "?"), side, int(rect.get("floor", 0))]).is_true()

	# Point "à côté" : 0,5 m le long du mur, du côté qui reste DANS la portée
	# du mur (jamais hors des bornes du bâtiment).
	var half: float = (float(rect["x_hi"]) - float(rect["x_lo"])) * 0.5 if axis == "x" else (float(rect["z_hi"]) - float(rect["z_lo"])) * 0.5
	var along := Vector3(1, 0, 0) if axis == "x" else Vector3(0, 0, 1)
	var beside := center + along * (half + 0.5)
	var wall_ax := Kit.wall_axis_info(piece["pos"], piece["size"], side)
	var c_lo: float = wall_ax["c_lo"]
	var c_hi: float = wall_ax["c_hi"]
	var beside_c: float = (beside.x if axis == "x" else beside.z)
	if beside_c > c_hi - 0.1:
		beside = center - along * (half + 0.5)
		beside_c = (beside.x if axis == "x" else beside.z)
	if beside_c < c_lo + 0.1 or beside_c > c_hi - 0.1:
		return  # ouverture trop proche des deux bords à la fois (bâtiment étroit) : rien à comparer
	var solid_gap: Variant = _pair_hit_distance(space_state, beside - dir * _WALL_RAY_MARGIN + _OFFSET, beside + dir * _WALL_RAY_MARGIN + _OFFSET, 0xFFFFFFFF)
	assert_bool(solid_gap != null).append_failure_message("%s de %s (%s, étage %d) : le mur juste à côté de l'ouverture n'est PAS bloqué" % [kind, piece.get("name", "?"), side, int(rect.get("floor", 0))]).is_true()


func _inward_dir(axis: String, side: String) -> Vector3:
	match side:
		"N":
			return Vector3(0, 0, 1)
		"S":
			return Vector3(0, 0, -1)
		"E":
			return Vector3(-1, 0, 0)
		_:
			return Vector3(1, 0, 0)


func _pair_hit_distance(space_state: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int) -> Variant:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	var hit := space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	return from.distance_to(hit["position"])


# ======================================================================
#  Test 3 — la sonde de parité (R1/§0.1).
# ======================================================================
func test_parity_probe_3000_samples_and_five_pp() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var visual_bodies := _add_visual_probe_bodies(setup.nav_region)
	assert_int(visual_bodies.size()).append_failure_message("aucun maillage visuel fusionné trouvé sous nav_region — GeoBatcher.flush a-t-il tourné ?").is_greater(0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space_state := setup.get_world_3d().direct_space_state
	var samples := _all_wall_samples()
	assert_int(samples.size()).append_failure_message("échantillonnage insuffisant (%d < %d) — resserrer _ALONG_STEP/_HEIGHT_FRACS" % [samples.size(), _MIN_SAMPLE_COUNT]).is_greater_equal(_MIN_SAMPLE_COUNT)

	var global_mismatches := 0
	var pp_total := 0
	var pp_mismatches := 0
	var worst_desc := ""
	var worst_gap := 0.0
	for entry in samples:
		var s: Dictionary = entry
		var from: Vector3 = (s["from"] as Vector3) + _OFFSET
		var to: Vector3 = (s["to"] as Vector3) + _OFFSET
		var gap := _visual_parity_gap(space_state, from, to)
		var is_mismatch := gap > _OPENING_TOLERANCE_M
		if is_mismatch:
			global_mismatches += 1
			if gap > worst_gap:
				worst_gap = gap
				worst_desc = "%s %s étage %d" % [s["building"], s["side"], s["floor"]]
		if bool(s["is_pp"]):
			pp_total += 1
			if is_mismatch:
				pp_mismatches += 1

	var global_ratio := float(global_mismatches) / float(samples.size())
	print("ART-91 parity: samples=%d mismatches=%d ratio=%.4f%% pp_samples=%d pp_mismatches=%d worst=%.4f (%s)" % [samples.size(), global_mismatches, global_ratio * 100.0, pp_total, pp_mismatches, worst_gap, worst_desc])

	assert_int(pp_total).append_failure_message("aucun échantillon sur les 5 PP (Hotel/Banque/SaloonW/SaloonE/Wagon) — noms de pièces à jour ?").is_greater(0)
	assert_int(pp_mismatches).append_failure_message("écart visuel/collision détecté sur une façade PP (%d/%d), pire cas %s : les façades PP doivent rester exactes sur toute leur hauteur (§1 R1)" % [pp_mismatches, pp_total, worst_desc]).is_equal(0)
	assert_float(global_ratio).append_failure_message("écart visuel/collision global %.3f%% (%d/%d) > 0,5%%, pire cas %s" % [global_ratio * 100.0, global_mismatches, samples.size(), worst_desc]).is_less_equal(_GLOBAL_MISMATCH_MAX_RATIO)
	await _teardown(setup)


## Écart (m) entre le point de contact "collision réelle" (calque 1) et
## "visuel réel" (calque 2) sur le MÊME segment. Un miss d'un seul côté (une
## ouverture visuelle en face d'un mur de collision, ou l'inverse) renvoie la
## longueur du segment entier — un écart maximal, jamais une valeur qui
## passerait la tolérance par accident. Les deux manquent (ouverture des deux
## côtés, comme au milieu d'une porte) : 0 (aucun écart).
func _visual_parity_gap(space_state: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> float:
	var dc: Variant = _pair_hit_distance(space_state, from, to, _LAYER_COLLISION)
	var dv: Variant = _pair_hit_distance(space_state, from, to, _LAYER_VISUAL)
	if dc == null and dv == null:
		return 0.0
	if dc == null or dv == null:
		return from.distance_to(to)
	return absf(float(dc) - float(dv))


## Ajoute, comme enfants de `root`, un `StaticBody3D` (calque `_LAYER_VISUAL`,
## `collision_mask = 0` : ne bloque jamais rien, JAMAIS ajouté à la navmesh —
## posé APRÈS le bake de `MapSetup._build_geometry`, et de toute façon ignoré
## par `NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS`) par `MeshInstance3D`
## réellement rendue sous `root` — un maillage trimesh construit depuis le
## VRAI mesh visuel (`Mesh.create_trimesh_shape`, jamais depuis les données de
## `wasteland.gd` : ce test ne fait AUCUNE hypothèse sur ce que le visuel
## contient, il regarde ce qui a été RENDU). Renvoie les corps ajoutés (pour
## le compte dans l'appelant ; libérés avec `nav_region`/`setup`, aucun
## nettoyage séparé nécessaire).
func _add_visual_probe_bodies(root: Node) -> Array:
	var added: Array = []
	for mi in _find_mesh_instances(root):
		var mesh_inst: MeshInstance3D = mi
		var mesh: Mesh = mesh_inst.mesh
		if mesh == null:
			continue
		var shape := mesh.create_trimesh_shape()
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.name = "VisualProbe%d" % added.size()
		body.collision_layer = _LAYER_VISUAL
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		# ORDRE IMPORTANT : `add_child` D'ABORD, `global_transform` ENSUITE.
		# `Node3D.global_transform` posé AVANT l'entrée dans l'arbre est
		# silencieusement traité comme un `transform` LOCAL (aucun parent pour
		# le composer) — une fois reparenté sous `root` (lui-même déjà décalé,
		# ex. `_OFFSET` du test), le décalage du parent s'AJOUTE à cette
		# valeur au lieu de la reproduire : chaque corps sonde se retrouvait
		# à deux fois son décalage réel (constaté en isolant le bake — un
		# raycast "visuel" qui ne touchait plus RIEN de la vraie carte,
		# ~88 % d'écart mesuré sur l'échantillonnage complet avant ce
		# correctif). Poser `global_transform` UNE FOIS le nœud dans l'arbre
		# le fait recalculer correctement contre le parent réel.
		root.add_child(body)
		body.global_transform = mesh_inst.global_transform
		added.append(body)
	return added


func _building2_pieces() -> Array:
	var out: Array = []
	for entry in (WastelandLayout.data()["pieces"] as Array):
		var p: Dictionary = entry
		if String(p.get("type", "")) == "building2":
			out.append(p)
	return out


func _is_pp_zone(building_name: String, side: String) -> bool:
	for z in _PP_ZONES:
		if String(z[0]) == building_name and String(z[1]) == side:
			return true
	return false


## Échantillons (from/to en espace LOCAL, l'appelant ajoute `_OFFSET`) sur les
## 4 faces × tous les étages des 11 `building2` — voir les constantes
## `_CORNER_INSET`/`_ALONG_STEP`/`_HEIGHT_FRACS`/`_WALL_RAY_MARGIN` en tête de
## fichier.
func _all_wall_samples() -> Array:
	var out: Array = []
	for entry in _building2_pieces():
		out.append_array(_wall_samples_for_piece(entry))
	return out


## Marge (m) autour du bord d'une ouverture (porte/fenêtre) dans laquelle un
## échantillon est REJETÉ plutôt que compté : à la limite exacte, la
## collision (une `BoxShape3D` par segment de mur) et le maillage visuel
## fusionné (un trimesh RECONSTRUIT par triangulation indépendante,
## `Mesh.create_trimesh_shape`) peuvent légitimement trancher le pixel-limite
## chacun de leur côté (bruit de construction de maillage, pas un écart
## d'art) — constaté en isolant le bake : `Wagon` (portes larges de 1,6 m,
## calées PILE sur le pas d'échantillonnage de 0,4 m) et `Hotel`/`SaloonW`
## (hauteur de porte 2,4 m = exactement 0,75 x la hauteur d'étage de 3,2 m,
## qui tombe PILE sur `_HEIGHT_FRACS[2]`) produisaient ~2 % d'écart, à 100 %
## concentré sur des points à ± quelques dixièmes de millimètre du bord d'une
## ouverture. 0,10 m (§1 R1, l'unité de tolérance du plan d'art) : bien plus
## large que ce bruit, assez petit pour ne retirer qu'une poignée de points
## par ouverture.
const _OPENING_BOUNDARY_MARGIN := 0.10


## Rectangles (c0/c1/y0/y1, dans le repère "le long du mur"/"hauteur") des
## ouvertures d'un côté/étage donné — mêmes fonctions que le test 2
## (`Kit.door_world_rect`/`Kit.window_world_rects`), reconverties depuis leurs
## coordonnées MONDE vers `axis`.
func _openings_c_y(piece: Dictionary, side: String, floor_idx: int, axis: String) -> Array:
	var out: Array = []
	var doors: Array = piece.get("doors", [])
	var has_door := false
	for entry in doors:
		var d: Dictionary = entry
		if String(d.get("side", "N")) != side or int(d.get("floor", 0)) != floor_idx:
			continue
		has_door = true
		var rect := Kit.door_world_rect(piece, d)
		out.append(_rect_to_cy(rect, axis))
	if not has_door and (piece.get("windows", []) as Array).has(side):
		for rect2 in Kit.window_world_rects(piece, side, floor_idx, bool(piece.get("slit", false))):
			out.append(_rect_to_cy(rect2, axis))
	return out


func _rect_to_cy(rect: Dictionary, axis: String) -> Dictionary:
	if axis == "x":
		return {"c0": rect["x_lo"], "c1": rect["x_hi"], "y0": rect["y0"], "y1": rect["y1"]}
	return {"c0": rect["z_lo"], "c1": rect["z_hi"], "y0": rect["y0"], "y1": rect["y1"]}


func _near_opening_boundary(c: float, y: float, openings: Array, margin: float) -> bool:
	for entry in openings:
		var o: Dictionary = entry
		var c0: float = o["c0"]
		var c1: float = o["c1"]
		var y0: float = o["y0"]
		var y1: float = o["y1"]
		var near_c_edge := absf(c - c0) < margin or absf(c - c1) < margin
		var near_y_edge := absf(y - y0) < margin or absf(y - y1) < margin
		var within_y_range := y > y0 - margin and y < y1 + margin
		var within_c_range := c > c0 - margin and c < c1 + margin
		if near_c_edge and within_y_range:
			return true
		if near_y_edge and within_c_range:
			return true
	return false


func _wall_samples_for_piece(piece: Dictionary) -> Array:
	var out: Array = []
	var name := String(piece.get("name", ""))
	var center: Vector3 = piece["pos"]
	var size: Vector3 = piece["size"]
	var floors := maxi(int(piece.get("floors", 1)), 1)
	var floor_h := size.y / float(floors)
	var bottom := center.y - size.y * 0.5
	for side in ["N", "S", "E", "W"]:
		var ax := Kit.wall_axis_info(center, size, side)
		var axis := String(ax["axis"])
		var fixed: float = ax["fixed"]
		var c_lo: float = float(ax["c_lo"]) + _CORNER_INSET
		var c_hi: float = float(ax["c_hi"]) - _CORNER_INSET
		if c_hi <= c_lo:
			continue
		var dir := _inward_dir(axis, side)
		var is_pp := _is_pp_zone(name, side)
		for f in floors:
			var y0 := bottom + floor_h * float(f)
			var openings := _openings_c_y(piece, side, f, axis)
			var c := c_lo
			while c <= c_hi:
				for frac in _HEIGHT_FRACS:
					var y: float = y0 + floor_h * float(frac)
					if _near_opening_boundary(c, y, openings, _OPENING_BOUNDARY_MARGIN):
						continue
					var base: Vector3 = Vector3(c, y, fixed) if axis == "x" else Vector3(fixed, y, c)
					out.append({
						"from": base - dir * _WALL_RAY_MARGIN, "to": base + dir * _WALL_RAY_MARGIN,
						"is_pp": is_pp, "building": name, "side": side, "floor": f,
					})
				c += _ALONG_STEP
	return out


# ======================================================================
#  Test 4 — "un bloc témoin de 1 m doit la faire échouer".
# ======================================================================
func test_parity_probe_flags_a_1m_control_block() -> void:
	var root := Node3D.new()
	add_child(root)

	var body_collision := StaticBody3D.new()
	body_collision.collision_layer = _LAYER_COLLISION
	body_collision.position = _CANARY_OFFSET
	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(1, 1, 1)
	col.shape = box_shape
	body_collision.add_child(col)
	root.add_child(body_collision)

	# Le "bloc témoin" : la même boîte, mais son VISUEL est décalé de 1 m —
	# exactement le défaut visé par le critère d'acceptation.
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	var body_visual := StaticBody3D.new()
	body_visual.collision_layer = _LAYER_VISUAL
	body_visual.collision_mask = 0
	body_visual.position = _CANARY_OFFSET + Vector3(1.0, 0.0, 0.0)
	var col2 := CollisionShape3D.new()
	col2.shape = bm.create_trimesh_shape()
	body_visual.add_child(col2)
	root.add_child(body_visual)

	await get_tree().physics_frame
	await get_tree().physics_frame
	var space_state := root.get_world_3d().direct_space_state
	var gap := _visual_parity_gap(space_state, _CANARY_OFFSET + Vector3(-2, 0, 0), _CANARY_OFFSET + Vector3(3, 0, 0))
	assert_float(gap).append_failure_message("la sonde n'a pas détecté le bloc témoin décalé de 1 m (gap mesuré=%.3f, tolérance=%.3f) — la machinerie de comparaison ne détecte rien" % [gap, _OPENING_TOLERANCE_M]).is_greater(_OPENING_TOLERANCE_M)
	# Le même écart, exprimé en ratio sur un lot d'1 seul échantillon, dépasse
	# bien le seuil global de 0,5 % du critère d'acceptation — cette sonde
	# ferait donc échouer une livraison qui contiendrait un tel bloc.
	assert_bool(gap > _OPENING_TOLERANCE_M).is_true()

	root.queue_free()
	await get_tree().physics_frame
