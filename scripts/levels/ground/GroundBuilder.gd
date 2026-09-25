## GroundBuilder.gd
## Sol procédural de Wasteland (docs/art/WASTELAND_ART_RESET.md "Coin
## beauté d'abord", tâche ART-85) -- module RÉUTILISABLE (« la map
## l'utilisera ensuite », contrat) : `build(spec) -> Node3D` construit un
## maillage en grille avec relief (bruit doux + piste creusée à deux
## ornières + jupes de terre au pied des bâtiments/props), peint par poids
## de mélange (sable / terre battue / piste / roche, `ink_ground.gdshader`),
## une collision `HeightMapShape3D` calée sur EXACTEMENT la même fonction de
## hauteur (donc sur le même maillage, à la résolution de grille près), et
## reste compatible navmesh (`bake_navmesh()`, même API que
## `scripts/ai/BotNavMesh.gd::ensure_baked` -- séparée de `build()` car la
## baking synchrone de Godot 4.7 (NavigationServer3D.parse_source_geometry_
## data) a besoin que le nœud soit déjà DANS l'arbre de scène active, ce que
## `build()` seul ne peut pas garantir : l'appelant `add_child()` le résultat
## PUIS appelle `bake_navmesh()`, comme tests/ai/test_bot_spots.gd le fait
## déjà pour `BotNavMesh.ensure_baked`).
##
## Spec consommée par `build(spec)` (contrat) :
##   size: Vector2(largeur_x, profondeur_z) -- empreinte en mètres.
##   center: Vector2 (optionnel, défaut ZERO) -- centre XZ monde de l'empreinte.
##   cell: float (défaut 0,5 m) -- résolution de grille du maillage ET de la
##     collision (la même, pour que la collision colle au maillage à la cote
##     de grille près -- voir critère d'acceptation "collision = maillage à
##     +/-2 cm").
##   roads: Array[{points: Array[Vector2], width, depth, ruts: {offset,
##     width, depth}}] -- une piste par entrée, tracée le long de la
##     polyligne `points` (segments successifs).
##   mounds: Array[{pos: Vector2, radius, height}] -- une jupe de terre par
##     entrée (pied de bâtiment/prop).
##   noise_amp: float (défaut 0,05 m) -- amplitude du bruit doux basse
##     fréquence (relief hors piste/jupe).
##   seed: int (défaut 0) -- graine du bruit (déterministe, testable).
##   splat_rules: Dictionary (optionnel) -- réglages fins du matériau peint
##     (aujourd'hui : "triplanar_scale").
##   visual_only: bool (défaut faux, ART-97) -- sol SANS collision propre
##     (`build()` omet `HeightMapShape3D`/`GroundCollision`, pour un sol posé
##     par-dessus une boîte de collision déjà existante, ex. le greybox de
##     Wasteland v4 -- voir `wasteland_art/ArtGround.gd`) : la profondeur des
##     pistes/ornières/jupes peut alors descendre à 3 cm, et le relief TOTAL
##     (bruit+piste+jupe combinés) est plafonné à +/-8 cm, le budget du
##     critère d'acceptation ART-97 ("sol visuel à +/-8 cm des boîtes de
##     sol") -- voir `VISUAL_ONLY_MIN/MAX_ROAD_DEPTH`/`VISUAL_ONLY_HEIGHT_CAP`.
##   roads[].paint: String (défaut "sand"|"dirt"|"track"|"rock", ART-97) --
##     réutilise le même creusement piste/ornière pour peindre en terre
##     battue ou en ballast plutôt qu'en piste (ex. les Ruelles, le lit de
##     ballast le long des rails) sans dupliquer la logique de piste. Ne
##     change jamais le relief, seulement `weights_at`.
##   zones: Array[{rect: Rect2 | poly: Array[Vector2], paint: String, feather:
##     float}] (défaut vide, ART-97) -- peint une zone en dur (fondue sur
##     `feather` mètres à sa bordure, 1 m par défaut), appliquée par-dessus
##     les poids issus des pistes/jupes, dans l'ORDRE du tableau. Purement une
##     affaire de poids : ne touche jamais `height_at`.
##
## MÉTHODE (important pour toute retouche future) : `height_at(spec, x, z)`
## et `weights_at(spec, x, z)` sont des fonctions PURES (aucun état, aucun
## nœud requis) -- le maillage visuel ET la collision les appellent aux
## MÊMES points de grille, donc restent EXACTEMENT synchronisés par
## construction (jamais une dérive entre "ce qu'on voit" et "ce qu'on
## touche"). Testables sans moteur de rendu ni arbre de scène.
class_name GroundBuilder
extends RefCounted

const _SHADER := preload("res://assets/shaders/ink_ground.gdshader")

## Bibliothèque peinte actuelle (assets/textures/painted/, voir Cartoon.gd
## `_PAINTED`) : AUCUNE des 11 matières n'est dédiée au terrain à 4 rôles
## (sable/terre battue/piste/roche) -- seule `sand_dirt` (#C79359) est
## réellement sablonneuse ; `cracked_concrete` (#B8AFA0, clair et craquelé)
## est le moins mauvais repreneur pour "roche" (contrat : "textures actuelles
## de assets/textures/painted/, remplacées plus tard par ART-79B sous les
## mêmes noms" -- ART-79B repeindra CES MÊMES fichiers, ce module n'aura rien
## à changer). "Terre battue" ET "piste" réutilisent TOUTES DEUX le fichier
## `sand_dirt` avec une teinte différente (comme "terre battue" le faisait
## déjà) plutôt qu'un 4e fichier hors-palette (`asphalt`, #302F33 quasi
## noir) : un aplat presque noir dans une rue ensoleillée violerait
## STYLE_BIBLE §6.2/CHK-04 (sol jouable, chroma <= 0,10, L OKLab 0,60-0,78)
## et lirait comme une "zone morte" (§6.2) en plein milieu du coin beauté --
## precisément ce que ce contrat corrige, pas ce qu'il doit réintroduire.
##
## RETOUR VÉRIFICATEUR (ART-85, capture reports/beauty/beauty_corner.png
## datée 09:19) : `rust` (#B5562A) servait de base à "piste" -- mais son
## ratio R:B (~4,5, bien plus extrême que celui de `sand_dirt`, ~2,3) rend
## IMPOSSIBLE d'atteindre la cible §6.2/CHK-04 (L 0,60-0,78, chroma <= 0,10)
## par simple multiplication de teinte SANS lui faire perdre son identité
## (calculé : il faudrait un canal bleu x2,6 pour y arriver, ce qui repeint
## en fait `rust` en un beige neutre) -- résultat mesuré sur la capture :
## L OKLab ~0,15-0,20 sur toute la largeur de piste visible, en plein dans
## la bande "boue" CHK-02 (0,25-0,33) voire dessous, donc « un brun quasi
## uniforme » (retour vérificateur) au lieu de la piste/ornières/jupes
## attendues. `sand_dirt` (ratio R:B bien moins extrême) atteint la cible en
## restant crédible ; "piste" en garde une teinte nettement plus rouge/sombre
## que "terre battue" (frontière la plus basse du gabarit, L~0,605) pour
## rester lisible comme un chemin tassé, jamais confondue avec elle.
## Textures peintes à la main (ART-79/79B, 2026-09-25) : une par rôle, déjà dans
## la palette cible — sable ridé, terre battue à ornières, mélange sable/terre
## pour la piste, béton fissuré pour la roche.
const _TEX_SAND := preload("res://assets/textures/painted/terrain_sable_albedo.png")
const _TEX_DIRT := preload("res://assets/textures/painted/terrain_terre_battue_albedo.png")
const _TEX_TRACK := preload("res://assets/textures/painted/material_sand_dirt_albedo.png")
const _TEX_ROCK := preload("res://assets/textures/painted/material_cracked_concrete_albedo.png")

## Les 3 teintes de rôle ci-dessous sont calibrées en OKLab (mêmes matrices
## que tools/review/style_check.py::rgb01_to_oklab, CHK-04 "Sol calme") pour
## que `texture_moyenne x tint_role` -- L'ALBÉDO AVANT la rampe lumière/ombre
## partagée avec ink_toon.gdshader, voir test_ground_builder.gd section
## "calibration (OKLab)" -- tombe dans la cible §6.2 : L 0,60-0,78,
## chroma <= 0,10.
##
## CETTE cible (albédo pré-éclairage) NE PRÉDIT PAS directement le pixel
## RENDU (mesuré sur de vraies captures, tools/review/beauty_shot.gd) : la
## rampe 2 tons + ombre teintée (ink_toon.gdshader::light(), hors périmètre
## de cette tâche, jamais modifiée ici) déplace la teinte perçue -- mesuré
## deux fois de suite sur ce module :
##  1. Un premier calibrage (piste : L 0,625 H 40°, "terre battue" : L 0,650
##     H 56°) rendait la piste en ROSE VIF (capture réelle : L~0,60 mais
##     H~25° et chroma~0,14 -- la rampe a fait GLISSER la teinte vers le
##     rouge ET gonflé la chroma, pas l'inverse d'une intuition "l'ombre
##     désature"). "Brun"/terracotta n'existe perceptuellement qu'à faible
##     clarté ; à L>=0,60 (imposé par §6.2), la même teinte lit comme un
##     pastel/rose, pas un brun -- confirmé contre des bruns de référence à
##     clarté comparable (chocolate #D2691E : L 0,634 H 50,3 ; sienna
##     #A0522D : L 0,526 H 44,6, tous deux à un H nettement PLUS HAUT que 25-
##     30°).
##  2. Recalibré à partir du DÉPLACEMENT mesuré (ΔL~-0,03, chroma x~1,5,
##     ΔH~-15° entre albédo et pixel rendu) : teintes d'albédo remontées en
##     H et réduites en chroma pour compenser -- piste (H=61, chroma=0,057)
##     rend, mesuré sur la capture finale, à L~0,59-0,62, chroma~0,07-0,08,
##     H~31-33° : dans la cible §6.2, plus dans le rose. "Terre battue" (les
##     ornières, H=67, chroma=0,05, plus clair que la piste, L=0,739) reste
##     nettement plus claire que la piste dans le rendu final -- l'ornière se
##     détache comme une bande plus pâle au lieu de se fondre dedans (les
##     deux calibrages précédents avaient une terre battue et une piste trop
##     proches en clarté ET en teinte pour rester lisibles une fois rendues).
## "terre battue" : L OKLab (albédo) ~0,739, H~66,5°.
const _TINT_DIRT := Color(1.0, 1.0, 1.0)  # textures peintes déjà colorées (ART-79B) : plus de recoloration par rôle
## "piste" : chemin tassé nettement plus sombre/saturé que la terre battue --
## L OKLab (albédo) ~0,644, H~60,9° (voir la note de calibration ci-dessus :
## jamais en dessous de ~40° d'albédo, sous peine de rendre rose).
const _TINT_TRACK := Color(1.0, 1.0, 1.0)  # textures peintes déjà colorées (ART-79B) : plus de recoloration par rôle
## "roche" : `cracked_concrete` désaturé (gravats pâles) -- L OKLab ~0,72,
## chroma ~0,03 (nettement moins saturé que sable/terre/piste : la roche se
## détache par son ABSENCE de couleur, pas par sa clarté ; chroma déjà si
## faible que le déplacement de la rampe lumière/ombre ne le fait pas
## basculer de teinte comme piste/terre battue).
const _TINT_ROCK := Color(1.0, 1.0, 1.0)  # textures peintes déjà colorées (ART-79B) : plus de recoloration par rôle

const DEFAULT_SIZE := Vector2(20.0, 20.0)
const DEFAULT_CELL := 0.5
const DEFAULT_NOISE_AMP := 0.05
const DEFAULT_ROAD_WIDTH := 6.0
const DEFAULT_ROAD_DEPTH := 0.15
const MIN_ROAD_DEPTH := 0.10
const MAX_ROAD_DEPTH := 0.20
const DEFAULT_RUT_OFFSET := 1.4
const DEFAULT_RUT_WIDTH := 0.9
const DEFAULT_RUT_DEPTH := 0.05
const DEFAULT_MOUND_RADIUS := 1.5
const DEFAULT_MOUND_HEIGHT := 0.12

## `visual_only` (ART-97, docs/art/WASTELAND_V4_ART_PLAN.md §3) : bornes
## PROPRES au sol sans collision, plus permissives en bas (une piste peut se
## réduire à un simple frottement de 3 cm, purement peint) mais bien plus
## strictes en haut -- 8 cm est le PLAFOND DU CONTRAT (critère d'acceptation
## ART-97 "sol visuel à +/-8 cm des boîtes de sol") : un sol visuel n'a pas de
## collision propre, il DOIT donc rester sous ce budget pour ne jamais
## décoller de la boîte de sol du greybox qui le porte. Distinctes de
## MIN/MAX_ROAD_DEPTH (10-20 cm) : celles-ci restent le contrat du sol AVEC
## collision (ART-85, BeautyCorner), inchangé.
const VISUAL_ONLY_MIN_ROAD_DEPTH := 0.03
const VISUAL_ONLY_MAX_ROAD_DEPTH := 0.08
## Plafond de SÉCURITÉ appliqué au relief TOTAL (bruit + piste + ornière +
## jupe combinés, voir `height_at`) quand `visual_only` est vrai -- pas
## seulement à `depth` pris isolément : une jupe haute superposée à une
## ornière profonde au même point ne doit jamais dépasser ce budget, même si
## l'appelant (`ArtGround.gd`) n'a plafonné aucun des deux séparément.
const VISUAL_ONLY_HEIGHT_CAP := 0.08
## Largeur de la zone de transition douce entre le fond de piste et le
## terrain environnant ("relief doux", pas de mur vertical).
const _TRENCH_SOFTEN := 0.4
## Bourrelet de bord (terre repoussée par le passage des véhicules).
const _EDGE_WIDTH := 0.6
const _EDGE_HEIGHT := 0.04

## Mêmes paramètres d'agent que `scripts/ai/BotNavMesh.gd::ensure_baked`
## (même capsule joueur/bot, §4.1 STYLE_BIBLE) -- un sol qui accepterait un
## agent de gabarit différent romprait la navmesh partagée du reste du jeu.
const _NAV_AGENT_RADIUS := 0.4
const _NAV_AGENT_HEIGHT := 1.8
const _NAV_AGENT_MAX_CLIMB := 0.6
const _NAV_AGENT_MAX_SLOPE := 52.0
const _NAV_CELL_SIZE := 0.2
const _NAV_CELL_HEIGHT := 0.2


## Construit le sol (maillage peint + collision HeightMapShape3D) pour
## `spec` -- voir l'en-tête pour le format de `spec`. Ne bake PAS la navmesh
## (voir `bake_navmesh`, à appeler par l'appelant une fois le résultat
## `add_child()`-é dans l'arbre de scène active).
static func build(spec: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Ground"

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "GroundMesh"
	mesh_inst.mesh = _build_geometry(spec)
	mesh_inst.material_override = _material(spec)
	root.add_child(mesh_inst)

	# `visual_only` (ART-97) : sol posé par-dessus une boîte de collision déjà
	# existante (WastelandArt.gd §1 R9 "aucun CollisionObject3D ajouté") --
	# jamais de corps de collision propre dans ce cas.
	if not bool(spec.get("visual_only", false)):
		root.add_child(_build_collision(spec))
	return root


## Bake la navmesh sur `ground` (résultat de `build()`, déjà `add_child()`-é
## dans un arbre de scène actif -- voir l'en-tête pour pourquoi ceci est un
## appel séparé). Même pattern synchrone que `BotNavMesh.ensure_baked` :
## `NavigationServer3D.parse_source_geometry_data` (thread principal) puis
## `bake_from_source_geometry_data`, reployé sur `NavigationMeshGenerator.
## bake` si l'une des deux méthodes venait à manquer.
static func bake_navmesh(ground: Node3D) -> NavigationRegion3D:
	var navmesh := NavigationMesh.new()
	# STATIC_COLLIDERS (comme BotNavMesh.ensure_baked), pas MESH_INSTANCES :
	# parse la collision `HeightMapShape3D` déjà posée par `build()`, sans
	# retour CPU<-GPU du maillage visuel (Godot avertit sinon -- "Source
	# geometry parsing ... had to parse RenderingServer meshes at runtime").
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.agent_radius = _NAV_AGENT_RADIUS
	navmesh.agent_height = _NAV_AGENT_HEIGHT
	navmesh.agent_max_climb = _NAV_AGENT_MAX_CLIMB
	navmesh.agent_max_slope = _NAV_AGENT_MAX_SLOPE
	navmesh.cell_size = _NAV_CELL_SIZE
	navmesh.cell_height = _NAV_CELL_HEIGHT

	if NavigationServer3D.has_method("parse_source_geometry_data") \
			and NavigationServer3D.has_method("bake_from_source_geometry_data"):
		var source := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(navmesh, source, ground)
		NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	elif NavigationMeshGenerator.has_method("bake"):
		NavigationMeshGenerator.bake(navmesh, ground)  # repli déprécié mais synchrone.
	else:
		push_warning("GroundBuilder: aucune API de baking de navmesh disponible.")

	var region := NavigationRegion3D.new()
	region.name = "GroundNavRegion"
	region.navigation_mesh = navmesh
	region.add_to_group("nav_region")
	ground.add_child(region)
	return region


# ============================================================== géométrie

## Dimensions de grille (cases, pas sommets) dérivées de `size`/`cell` --
## partagées par le maillage visuel ET la collision (voir l'en-tête, MÉTHODE).
static func _grid_dims(spec: Dictionary) -> Vector2i:
	var size: Vector2 = spec.get("size", DEFAULT_SIZE)
	var cell: float = _cell_of(spec)
	var cols: int = maxi(1, int(round(size.x / cell)))
	var rows: int = maxi(1, int(round(size.y / cell)))
	return Vector2i(cols, rows)


static func _cell_of(spec: Dictionary) -> float:
	return maxf(float(spec.get("cell", DEFAULT_CELL)), 0.05)


## Coin MIN (x, z) de l'empreinte -- `center` +/- `size`/2.
static func _grid_origin(spec: Dictionary) -> Vector2:
	var size: Vector2 = spec.get("size", DEFAULT_SIZE)
	var center: Vector2 = spec.get("center", Vector2.ZERO)
	return center - size * 0.5


static func _build_geometry(spec: Dictionary) -> ArrayMesh:
	var cell := _cell_of(spec)
	var dims := _grid_dims(spec)
	var cols: int = dims.x
	var rows: int = dims.y
	var origin := _grid_origin(spec)

	# Grille de sommets pré-calculée (position + poids de mélange), réutilisée
	# par les deux triangles de chaque case.
	var positions: Array[Vector3] = []
	var weights: Array[PackedFloat32Array] = []
	for row in range(rows + 1):
		for col in range(cols + 1):
			var wx: float = origin.x + float(col) * cell
			var wz: float = origin.y + float(row) * cell
			positions.append(Vector3(wx, height_at(spec, wx, wz), wz))
			weights.append(weights_at(spec, wx, wz))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stride := cols + 1
	for row in range(rows):
		for col in range(cols):
			var i00: int = row * stride + col
			var i10: int = row * stride + col + 1
			var i01: int = (row + 1) * stride + col
			var i11: int = (row + 1) * stride + col + 1
			# Sens de bobinage : ce sens précis (et pas l'inverse) donne des
			# normales +Y avec `SurfaceTool.generate_normals()` -- vérifié
			# empiriquement (`test_flat_ground_mesh_normals_point_upward`,
			# godot --headless) : la convention de face-avant de Godot
			# s'est révélée inverse de la règle de la main droite
			# manuelle ; sans ce test, un maillage tourné à l'envers
			# aurait été invisible depuis une caméra normale (`cull_back`).
			_emit_tri(st, positions, weights, i00, i11, i01)
			_emit_tri(st, positions, weights, i00, i10, i11)
	st.generate_normals()
	return st.commit()


static func _emit_tri(st: SurfaceTool, positions: Array[Vector3], weights: Array[PackedFloat32Array], a: int, b: int, c: int) -> void:
	for idx in [a, b, c]:
		var w: PackedFloat32Array = weights[idx]
		st.set_color(Color(w[0], w[1], w[2], w[3]))
		st.add_vertex(positions[idx])


static func _material(spec: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _SHADER
	m.set_shader_parameter("tex_sand", _TEX_SAND)
	m.set_shader_parameter("tex_dirt", _TEX_DIRT)
	m.set_shader_parameter("tex_track", _TEX_TRACK)
	m.set_shader_parameter("tex_rock", _TEX_ROCK)

	# Teinte par rôle = même palette/carte que le reste du jeu
	# (Cartoon.map_palette(MatchConfig.map_id)["ground"], STYLE_BIBLE §7.7 --
	# jusqu'ici seulement STOCKÉE, jamais consommée, voir le commentaire de
	# Cartoon.gd "ART-06/tâches suivantes" : ce module en est le premier
	# consommateur), diluée comme `Cartoon.painted()` le fait déjà pour ne
	# pas assombrir deux fois une texture déjà colorée (`effective_tint`),
	# puis recolorée par rôle (_TINT_DIRT/_TINT_TRACK/_TINT_ROCK) pour que
	# les 4 canaux restent visuellement distincts.
	var palette: Dictionary = Cartoon.map_palette(MatchConfig.map_id)
	var map_ground: Color = palette.get("ground", Color.WHITE)
	var sand_tint: Color = Cartoon.effective_tint(&"sand_dirt", map_ground)
	m.set_shader_parameter("tint_sand", sand_tint)
	m.set_shader_parameter("tint_dirt", sand_tint * _TINT_DIRT)
	m.set_shader_parameter("tint_track", Cartoon.effective_tint(&"rust", map_ground) * _TINT_TRACK)
	m.set_shader_parameter("tint_rock", Cartoon.effective_tint(&"cracked_concrete", map_ground) * _TINT_ROCK)

	var rules: Dictionary = spec.get("splat_rules", {})
	m.set_shader_parameter("triplanar_scale", float(rules.get("triplanar_scale", 0.25)))
	m.set_shader_parameter("shadow_tint", palette.get("shadow_tint", Cartoon.SHADOW_TINT))
	return m


# =========================================================== collision

## `HeightMapShape3D` échantillonnée à la MÊME résolution de grille (`cell`)
## et par la MÊME fonction `height_at` que le maillage visuel -- donc
## identique à celui-ci aux sommets de grille (0 cm d'écart), et à quelques
## millimètres près entre deux sommets pour un relief aussi doux que celui
## de ce module (interpolation bilinéaire du HeightMapShape3D vs.
## interpolation linéaire des triangles du maillage). Voir la note Godot
## 4.7 (HeightMapShape3D) : la grille est espacée d'1 unité PRE-échelle et
## centrée sur l'origine du CollisionShape3D -- une échelle UNIFORME
## (GodotPhysics3D ne supporte pas l'échelle non uniforme) de `cell` donne
## l'espacement `cell` voulu en X/Z, à condition de PRÉ-DIVISER les hauteurs
## stockées par ce même facteur (`map_data[i] = hauteur / cell`), pour que
## l'échelle Y (= cell, forcée égale à X/Z) rende la bonne hauteur RÉELLE.
static func _build_collision(spec: Dictionary) -> StaticBody3D:
	var cell := _cell_of(spec)
	var dims := _grid_dims(spec)
	var cols: int = dims.x
	var rows: int = dims.y
	var origin := _grid_origin(spec)
	var stride := cols + 1

	var shape := HeightMapShape3D.new()
	shape.map_width = stride
	shape.map_depth = rows + 1
	var data := PackedFloat32Array()
	data.resize(stride * (rows + 1))
	for row in range(rows + 1):
		for col in range(cols + 1):
			var wx: float = origin.x + float(col) * cell
			var wz: float = origin.y + float(row) * cell
			data[row * stride + col] = height_at(spec, wx, wz) / cell
	shape.map_data = data

	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	var col_shape := CollisionShape3D.new()
	col_shape.shape = shape
	col_shape.scale = Vector3(cell, cell, cell)
	var half_span := Vector2(float(cols) * cell, float(rows) * cell) * 0.5
	col_shape.position = Vector3(origin.x + half_span.x, 0.0, origin.y + half_span.y)
	body.add_child(col_shape)
	return body


# ================================================================= relief
# Fonctions PURES (voir en-tête, MÉTHODE) -- aucun état, testables sans arbre
# de scène ni moteur de rendu.

## Hauteur du sol en (x, z) monde : bruit doux + piste(s) creusée(s)
## (ornières + bourrelets de bord) + jupe(s) de terre. Plusieurs pistes qui
## se recouvrent : la contribution DOMINANTE (plus grande amplitude absolue)
## l'emporte plutôt que de s'additionner (évite un double-creusement
## irréaliste à un croisement). Plusieurs jupes qui se recouvrent : la plus
## haute l'emporte (un tas de terre ne s'additionne pas à un autre).
static func height_at(spec: Dictionary, x: float, z: float) -> float:
	var visual_only: bool = bool(spec.get("visual_only", false))
	var h := 0.0
	var noise_amp: float = float(spec.get("noise_amp", DEFAULT_NOISE_AMP))
	if noise_amp > 0.0:
		var seed: int = int(spec.get("seed", 0))
		h += (_value_noise2(x * 0.2, z * 0.2, seed) * 2.0 - 1.0) * noise_amp

	var road_deltas: Array = []
	for road in (spec.get("roads", []) as Array):
		road_deltas.append(_road_delta(x, z, road as Dictionary, visual_only))
	h += _dominant(road_deltas)

	var mound_deltas: Array = []
	for mound in (spec.get("mounds", []) as Array):
		mound_deltas.append(_mound_delta(x, z, mound as Dictionary))
	h += _max_of(mound_deltas)

	if visual_only:
		# Filet de sécurité sur le CUMUL (voir `VISUAL_ONLY_HEIGHT_CAP`) --
		# jamais seulement sur `depth` pris isolément.
		h = clampf(h, -VISUAL_ONLY_HEIGHT_CAP, VISUAL_ONLY_HEIGHT_CAP)
	return h


## Poids de mélange NORMALISÉS (somme = 1) en (x, z) monde : [sable, terre
## battue, piste, roche] -- même ordre que `COLOR` (R/G/B/A) dans
## `ink_ground.gdshader`. Loin de toute piste/jupe/zone : sable pur (1,0,0,0).
static func weights_at(spec: Dictionary, x: float, z: float) -> PackedFloat32Array:
	# `paint` (ART-97, défaut "track" -- comportement d'avant inchangé) :
	# chaque route accumule son influence "inside" dans SON propre canal de
	# rôle plutôt que toujours "piste", pour réutiliser le même creusement
	# piste/ornière sur une route peinte en terre battue (Ruelles) ou en
	# ballast (le long des rails).
	var w_track := 0.0
	var w_dirt := 0.0
	var w_rock := 0.0
	var rut_infl := 0.0
	for road_v in (spec.get("roads", []) as Array):
		var road: Dictionary = road_v as Dictionary
		var points: Array = road.get("points", [])
		if points.size() < 2:
			continue
		var prof := _road_profile(Vector2(x, z), points)
		var half_width: float = float(road.get("width", DEFAULT_ROAD_WIDTH)) * 0.5
		var inside: float = 1.0 - smoothstep(half_width - _TRENCH_SOFTEN, half_width, prof["dist"])
		match String(road.get("paint", "track")):
			"dirt":
				w_dirt = maxf(w_dirt, inside)
			"rock":
				w_rock = maxf(w_rock, inside)
			"sand":
				pass  # une route peinte "sand" ne fait que creuser (relief), sans peindre.
			_:
				w_track = maxf(w_track, inside)

		if road.has("ruts"):
			var ruts: Dictionary = road["ruts"]
			var rut_offset: float = float(ruts.get("offset", DEFAULT_RUT_OFFSET))
			var rut_width: float = float(ruts.get("width", DEFAULT_RUT_WIDTH))
			var rf: float = 1.0 - smoothstep(rut_width * 0.3, rut_width * 0.5, absf(absf(prof["lateral"]) - rut_offset))
			rut_infl = maxf(rut_infl, rf * inside)

	var mound_infl := 0.0
	for mound_v in (spec.get("mounds", []) as Array):
		var mound: Dictionary = mound_v as Dictionary
		var pos: Vector2 = mound.get("pos", Vector2.ZERO)
		var radius: float = maxf(float(mound.get("radius", DEFAULT_MOUND_RADIUS)), 0.01)
		var dist: float = Vector2(x, z).distance_to(pos)
		var falloff: float = (1.0 - smoothstep(0.0, radius, dist)) if dist < radius else 0.0
		mound_infl = maxf(mound_infl, falloff)

	# Piste : pleine "voie" hors ornière, un peu de terre battue DANS
	# l'ornière (les pneus tassent/exposent la terre sous le sable) -- ne
	# s'applique qu'au canal "piste" lui-même (une route peinte en terre
	# battue ou en ballast n'a pas cette réduction : rien à exposer de plus).
	w_track = w_track * (1.0 - rut_infl * 0.5)
	w_dirt = w_dirt + rut_infl * 0.6 + mound_infl * 0.5
	# Jupe de terre : moitié terre tassée, moitié gravats/roche.
	w_rock = w_rock + mound_infl * 0.5
	var w_sand: float = maxf(0.0, 1.0 - w_track - w_dirt - w_rock)

	var total: float = w_sand + w_dirt + w_track + w_rock
	var w: PackedFloat32Array
	if total <= 0.0001:
		w = PackedFloat32Array([1.0, 0.0, 0.0, 0.0])
	else:
		w = PackedFloat32Array([w_sand / total, w_dirt / total, w_track / total, w_rock / total])

	# `zones` (ART-97) : peinture en dur par-dessus les poids ci-dessus, dans
	# l'ORDRE du tableau -- un simple lerp vers le rôle visé garde la somme à
	# 1 par construction (lerp de deux vecteurs de somme 1 reste de somme 1).
	for zone_v in (spec.get("zones", []) as Array):
		var zone: Dictionary = zone_v as Dictionary
		var amt := _zone_amount(Vector2(x, z), zone)
		if amt <= 0.0:
			continue
		var role_idx := _paint_role_index(String(zone.get("paint", "sand")))
		for i in range(4):
			var target: float = 1.0 if i == role_idx else 0.0
			w[i] = lerpf(w[i], target, amt)
	return w


## Index de canal (même ordre que `weights_at`) pour un rôle de peinture --
## rôle absent/inconnu = "sand" (canal 0), jamais un crash sur une faute de
## frappe dans `ArtGround.gd`.
static func _paint_role_index(role: String) -> int:
	match role:
		"dirt":
			return 1
		"track":
			return 2
		"rock":
			return 3
		_:
			return 0


## Force de peinture (0 = aucun effet, 1 = peinture pure) d'UNE `zone` en
## (x, z) monde -- fondue sur `feather` mètres depuis sa bordure VERS
## L'INTÉRIEUR (même famille que `_road_delta`/`_mound_delta` : un
## `smoothstep` qui atteint 0 pile à la bordure, jamais une marche brute).
static func _zone_amount(p: Vector2, zone: Dictionary) -> float:
	var feather: float = maxf(float(zone.get("feather", 1.0)), 0.001)
	if zone.has("rect"):
		return _rect_zone_amount(p, zone["rect"] as Rect2, feather)
	if zone.has("poly"):
		var poly: Array = zone["poly"]
		return _poly_zone_amount(p, PackedVector2Array(poly), feather)
	return 0.0


static func _rect_zone_amount(p: Vector2, rect: Rect2, feather: float) -> float:
	var x0 := rect.position.x
	var z0 := rect.position.y
	var x1 := x0 + rect.size.x
	var z1 := z0 + rect.size.y
	if p.x < x0 or p.x > x1 or p.y < z0 or p.y > z1:
		return 0.0
	var edge_dist: float = minf(minf(p.x - x0, x1 - p.x), minf(p.y - z0, z1 - p.y))
	return smoothstep(0.0, feather, edge_dist)


static func _poly_zone_amount(p: Vector2, poly: PackedVector2Array, feather: float) -> float:
	if poly.size() < 3 or not Geometry2D.is_point_in_polygon(p, poly):
		return 0.0
	var edge_dist := INF
	var n := poly.size()
	for i in range(n):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
		edge_dist = minf(edge_dist, p.distance_to(closest))
	return smoothstep(0.0, feather, edge_dist)


## Distance perpendiculaire ET décalage latéral SIGNÉ (repère local du
## segment le plus proche -- gauche/droite de la piste) au point le plus
## proche de la polyligne `points`.
static func _road_profile(p: Vector2, points: Array) -> Dictionary:
	var best_dist := INF
	var best_lateral := 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var seg := b - a
		var seg_len_sq := seg.length_squared()
		var t := 0.0
		if seg_len_sq > 0.0001:
			t = clampf((p - a).dot(seg) / seg_len_sq, 0.0, 1.0)
		var closest := a + seg * t
		var dist := p.distance_to(closest)
		if dist < best_dist:
			best_dist = dist
			var dir: Vector2 = seg.normalized() if seg_len_sq > 0.0001 else Vector2.RIGHT
			var normal := Vector2(-dir.y, dir.x)
			best_lateral = (p - closest).dot(normal)
	return {"dist": best_dist, "lateral": best_lateral}


## Delta de hauteur d'UNE piste en (x, z) : creux "doux" (bords adoucis sur
## `_TRENCH_SOFTEN`) de `depth` (bornée 10-20 cm, contrat), deux ornières
## (`ruts.offset/width/depth`) qui creusent un peu plus, un bourrelet de bord
## (terre repoussée) juste après le bord de piste.
static func _road_delta(x: float, z: float, road: Dictionary, visual_only: bool = false) -> float:
	var points: Array = road.get("points", [])
	if points.size() < 2:
		return 0.0
	var prof := _road_profile(Vector2(x, z), points)
	var dist: float = prof["dist"]
	var lateral: float = prof["lateral"]
	var half_width: float = float(road.get("width", DEFAULT_ROAD_WIDTH)) * 0.5
	var depth: float = float(road.get("depth", DEFAULT_ROAD_DEPTH))
	if visual_only:
		depth = clampf(depth, VISUAL_ONLY_MIN_ROAD_DEPTH, VISUAL_ONLY_MAX_ROAD_DEPTH)
	else:
		depth = clampf(depth, MIN_ROAD_DEPTH, MAX_ROAD_DEPTH)

	var inside: float = 1.0 - smoothstep(half_width - _TRENCH_SOFTEN, half_width, dist)
	var trench: float = -depth * inside

	var edge_bump: float = smoothstep(half_width - _TRENCH_SOFTEN, half_width, dist) \
		* (1.0 - smoothstep(half_width, half_width + _EDGE_WIDTH, dist))
	var edge: float = _EDGE_HEIGHT * edge_bump

	var ruts: Dictionary = road.get("ruts", {})
	var rut_offset: float = float(ruts.get("offset", DEFAULT_RUT_OFFSET))
	var rut_width: float = float(ruts.get("width", DEFAULT_RUT_WIDTH))
	var rut_depth: float = float(ruts.get("depth", DEFAULT_RUT_DEPTH))
	var rut_factor: float = 1.0 - smoothstep(rut_width * 0.3, rut_width * 0.5, absf(absf(lateral) - rut_offset))
	var rut: float = -rut_depth * rut_factor * inside

	return trench + edge + rut


## Delta de hauteur d'UNE jupe de terre en (x, z) : dôme doux (falloff
## `smoothstep`) de `height` au centre, nul au-delà de `radius`.
static func _mound_delta(x: float, z: float, mound: Dictionary) -> float:
	var pos: Vector2 = mound.get("pos", Vector2.ZERO)
	var radius: float = maxf(float(mound.get("radius", DEFAULT_MOUND_RADIUS)), 0.01)
	var height: float = float(mound.get("height", DEFAULT_MOUND_HEIGHT))
	var dist: float = Vector2(x, z).distance_to(pos)
	if dist >= radius:
		return 0.0
	return height * (1.0 - smoothstep(0.0, radius, dist))


## Élément de plus grande amplitude ABSOLUE (0.0 si `values` est vide) --
## évite qu'un croisement de pistes double-creuse (voir `height_at`).
static func _dominant(values: Array) -> float:
	var best := 0.0
	var best_abs := -1.0
	for v in values:
		var a: float = absf(float(v))
		if a > best_abs:
			best_abs = a
			best = float(v)
	return best


## Plus grande valeur (0.0 si `values` est vide) -- jupes qui se recouvrent.
static func _max_of(values: Array) -> float:
	var best := 0.0
	for v in values:
		best = maxf(best, float(v))
	return best


## Hash déterministe 2D (mêmes (x, z, seed) -> même valeur, testable, pas de
## dépendance au moteur/à une graine globale). Godot GDScript utilise des
## entiers 64 bits en complément à deux : ce mélange XOR/mul déborde SANS
## comportement indéfini (contrairement au C), donc reste reproductible.
static func _hash2(x: int, z: int, seed: int) -> float:
	var n: int = x * 374761393 + z * 668265263 + seed * 2246822519
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0x7fffffff) / float(0x7fffffff)


## Bruit de valeur lissé (interpolation trilinéaire d'un lattice de hash,
## fondu Hermite) -- jamais un `floor()` à facettes, pour un relief "doux"
## (contrat). Retourne [0, 1].
static func _value_noise2(x: float, z: float, seed: int) -> float:
	var xi := floori(x)
	var zi := floori(z)
	var xf := x - float(xi)
	var zf := z - float(zi)
	var v00 := _hash2(xi, zi, seed)
	var v10 := _hash2(xi + 1, zi, seed)
	var v01 := _hash2(xi, zi + 1, seed)
	var v11 := _hash2(xi + 1, zi + 1, seed)
	var u := xf * xf * (3.0 - 2.0 * xf)
	var w := zf * zf * (3.0 - 2.0 * zf)
	var nx0 := lerpf(v00, v10, u)
	var nx1 := lerpf(v01, v11, u)
	return lerpf(nx0, nx1, w)
