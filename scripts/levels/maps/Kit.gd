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
## §ART-71 (STYLE_BIBLE l.36/1468, anti-patron « marches décollées de leurs
## limons » / « murs [...] sans trim, sans rupture de silhouette ») : tous
## les escaliers/rampes internes (`stairs()` et les rampes de `building2()`)
## ferment désormais leurs marches d'un limon plein + une contremarche par
## marche (`stair_support_boxes`) ; `building2()` ajoute des trims crème de
## 6 cm sur ses arêtes verticales et en haut des murs (`building_trim_boxes`)
## et un débord de toit de 0,3 m hors de l'espace praticable
## (`roof_overhang_boxes`) — le tout purement visuel (batcher seul, jamais
## `_collision_box` : la collision de chaque pièce ne change pas).
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

## LD-44 (Wasteland v4, §12.3 RÉVISÉ le 2026-09-25 — remplace la version
## LD-40 ci-dessous) : les toits à 60° (l'ancienne valeur, encore visible
## dans l'historique) faisaient monter le faîtage jusqu'à 20,3 m sur les
## Saloons (docs/art/WASTELAND_V4_ART_PLAN.md §1 « B0 ») — assez pour cacher
## le château d'eau (12 m) et casser la silhouette de la ville derrière les
## Échoppes/Saloons. Décision utilisateur : toits BAS (25-30°), méthode des
## maps CoD — plus un volume invisible « anti-joueur » posé AU-DESSUS
## (`roof_clip_boxes`/`roof_clip_volumes` ci-dessous, calque `PhysicsLayers.
## PLAYER_CLIP`, voir docs/COLLISION_LAYERS.md), jamais un minuteur « Retour
## au combat ». Conséquence directe : à 25-30°, la pente est maintenant SOUS
## le plafond de `MapSetup.AGENT_MAX_SLOPE` (46°) — Recast PEUT désormais
## inclure le pan dans le bake (contrairement à LD-40) — c'est précisément
## pourquoi le volume `player_clip` existe : il bloque PHYSIQUEMENT tout
## corps de joueur (saut, grappin, planeur — un déplacement, jamais une
## téléportation, donc toujours arrêté par une collision — vérifié par un
## VRAI `CharacterBody3D.move_and_collide`, `tests/maps/test_wasteland.gd::
## test_no_roof_point_is_physically_reachable_by_a_moving_player_body`).
##
## Décision lead 2026-09-25 (résout le blocage initial de LD-44, voir
## l'historique de docs/COLLISION_LAYERS.md §« Limite connue ») : la décision
## demande AUSSI que ce volume laisse passer les tirs/grenades/capacités de
## lancer (`PhysicsLayers.SHOT_MASK`). Godot (`CharacterBody3D.
## move_and_collide` COMME `PhysicsDirectSpaceState3D.intersect_ray`) ne
## regarde QUE `requête.collision_mask & cible.collision_layer` — JAMAIS le
## masque de la cible — donc un seul calque ne peut pas être à la fois
## « heurté par le masque PAR DÉFAUT du joueur » et « exclu de SHOT_MASK »
## sans calque dédié. `PhysicsLayers.PLAYER_CLIP` (`scripts/core/
## PhysicsLayers.gd`) est ce calque : exclu de `SHOT_MASK`, et inclus dans le
## `collision_mask` par défaut du corps joueur/bot (`scenes/player/
## player.tscn`, WORLD | PLAYER_CLIP). `roof_clip_volumes` pose donc ce
## volume sur `layer=mask=PhysicsLayers.PLAYER_CLIP` (jamais WORLD) : heurté
## par le joueur ET traversé par les tirs/grenades/grappin, prouvé par un
## rayon `SHOT_MASK` réel (`tests/maps/test_wasteland.gd::
## test_a_shot_ray_passes_through_the_roof_clip_volume`) et par un
## `CharacterBody3D.move_and_collide` réel (`test_no_roof_point_is_
## physically_reachable_by_a_moving_player_body`).
const ROOF_PITCH_DEG := 27.0

## LD-44 : le faîtage ne dépasse JAMAIS la corniche (`roof_y`) de plus de
## cette hauteur, quelle que soit la profondeur du bâtiment — décision
## utilisateur « faîte <= 3 m au-dessus de la corniche ». Un bâtiment profond
## (Échoppes 14 m, Saloons 16 m, §1 du plan d'art) dépasserait 3 m à un angle
## nominal de 25-30° (ex. Saloon, demi-profondeur 8 m : 8×tan(27°) = 3,73 m) —
## `roof_ridge_rise` PLAFONNE alors la MONTÉE (angle effectif réduit sous
## 25°), jamais l'inverse : le plafond de hauteur prime toujours sur l'angle
## nominal, jamais assoupli pour le garder.
const ROOF_MAX_RISE := 3.0

## LD-44 : hauteur du volume `player_clip` au-dessus de la surface du toit
## (décision utilisateur « il couvre le toit jusqu'à +12 m pour que grappin
## et planeur ne s'y posent jamais ») — mesurée PERPENDICULAIREMENT à la
## pente (même convention que `pitched_roof_boxes`/`_ramp_shape`, jamais
## verticale pure) : à 20-27° d'angle effectif, cela couvre en réalité
## davantage que 12 m de hauteur VERTICALE (12 / cos(27°) ≈ 13,5 m), jamais
## moins — marge délibérée, jamais un raccourci plus court que demandé.
const ROOF_CLIP_HEIGHT := 12.0

## ======================================================================
##  GeoBatcher : fusionne les visuels de même couleur en un seul mesh
##  (un draw call par matériau) ; la collision reste individuelle par pièce.
## ======================================================================
class GeoBatcher:
	var _tools: Dictionary = {}   # clé "couleur(html)|kind" -> SurfaceTool
	var _colors: Dictionary = {}  # clé -> Color
	var _kinds: Dictionary = {}   # clé -> kind peint ("" = plat, Cartoon.world)
	## Nombre total de boîtes ajoutées (toutes couleurs confondues) — sert aux
	## tests d'intégration (ART-71 : vérifier qu'une pièce a bien VERSÉ sa
	## géométrie de support dans le batcher, sans inspecter `_tools`).
	var box_count: int = 0

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
		box_count += 1

	## Une couleur (+ kind peint) a-t-elle déjà de la géométrie dans ce
	## batcher ? Sert aux tests d'intégration (ART-71 : confirmer qu'un trim
	## crème a bien été versé, sans dépendre de l'ordre des clés de `flush`).
	func has_color(color: Color, kind: String = "") -> bool:
		return _tools.has("%s|%s" % [color.to_html(), kind])

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
## `layer`/`mask` (LD-44, ADDITIF) : par défaut 1/1 — EXACTEMENT les valeurs
## implicites que Godot posait déjà sur un `StaticBody3D.new()` jamais
## touché ; tout appelant existant (aucun ne passe ces deux arguments) garde
## donc une collision bit-à-bit inchangée. Seul `roof_clip_volumes` (LD-44,
## volume `player_clip`) les redéfinit (`layer=mask=PhysicsLayers.PLAYER_CLIP`
## — calque DÉDIÉ, jamais WORLD : voir son commentaire, et celui de
## `ROOF_PITCH_DEG` ci-dessus pour la raison — un calque WORLD serait inclus
## dans `PhysicsLayers.SHOT_MASK` et bloquerait les tirs, ce que la décision
## lead 2026-09-25 exclut explicitement).
static func _collision_box(parent: Node3D, xform: Transform3D, size: Vector3, nm: String, layer: int = 1, mask: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = nm
	body.transform = xform
	body.collision_layer = layer
	body.collision_mask = mask
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
## `stairs()` et les rampes internes de `building2()`. `above` (LD-44,
## ADDITIF, défaut `false` = comportement d'origine INCHANGÉ pour tous les
## appelants existants) : `false` pose l'épaisseur SOUS la ligne
## `start`->`end` (la ligne EST la surface du dessus — c'est ce que
## `pitched_roof_boxes` veut, « deux points DE SURFACE ») ; `true` la pose
## AU-DESSUS (la ligne devient le dessous de la boîte) — c'est ce que veut
## `roof_clip_boxes` : un volume qui colle exactement au-dessus de cette même
## surface, sans le moindre jeu (même ligne `start`/`end`, jamais recalculée).
static func _ramp_shape(start: Vector3, end: Vector3, width: float, thickness: float, above: bool = false) -> Dictionary:
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
	var side_sign := 1.0 if above else -1.0
	var center := (start + end) * 0.5 + up * (thickness * 0.5 * side_sign)
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

## Épaisseur visuelle d'une contremarche (§ART-71) : une planche fine qui
## ferme le devant d'une marche — jamais de collision propre.
const _STAIR_RISER_T := 0.06

## Boîtes VISUELLES qui ferment un escalier (§ART-71, STYLE_BIBLE l.36/1468 :
## anti-patron visé, « les marches d'escalier sont décollées de leurs
## limons ») : `[0]` le limon plein — la MÊME géométrie que la rampe de
## collision de `_ramp_shape`, rendue visible cette fois (elle n'était posée
## qu'en collision par `_ramp_with_treads`) — puis une contremarche par
## marche, du dessous de la marche PRÉCÉDENTE (ou du pied de la volée pour la
## première, y=0 local) jusqu'au dessous de la marche COURANTE, sans écart :
## la contremarche i touche exactement le dessous de la marche i (même
## formule -0.09 que la marche visuelle posée par `_ramp_with_treads` —
## marche centrée sur `step_rise*(i+1) - 0.05`, haute de 0.08, donc son
## dessous est à `step_rise*(i+1) - 0.09`), tolérance ≤ 1 cm de
## STYLE_BIBLE l.1468 (ici : 0 cm, contact exact). AUCUNE collision propre
## n'est posée ici : ni ce helper ni son appelant n'appellent jamais
## `_collision_box` pour ces boîtes — seulement des entrées batcher. La
## collision de l'escalier reste l'unique boîte de rampe (test d'invariance
## Kit : `test_stairs_pose_a_single_ramp_collision_not_one_per_step`). Pure
## (aucun nœud) et volontairement SANS underscore : testable directement,
## comme les autres géométries pures de ce fichier.
static func stair_support_boxes(start: Vector3, end: Vector3, width: float, steps: int, thickness: float) -> Array:
	steps = maxi(steps, 2)
	var r := _ramp_shape(start, end, width, thickness)
	var out: Array = [{"xform": r["xform"], "size": r["size"]}]
	var side: Vector3 = r["side"]
	# `fwd_flat` (PAS `r["fwd"]`, qui est incliné le long de la pente 3D) :
	# les marches ET les contremarches sont des plans VERTICAUX/horizontaux
	# (jamais inclinés comme le limon) — voir le même choix dans
	# `_ramp_with_treads`, dont ceci doit rester le miroir exact pour que la
	# contremarche touche le dessous de sa marche sans écart.
	var flat_dir := Vector3(end.x - start.x, 0.0, end.z - start.z)
	var flat_len := flat_dir.length()
	var fwd_flat: Vector3 = flat_dir.normalized() if flat_len > 0.001 else r["fwd"]
	var rise := end.y - start.y
	var step_run := flat_len / float(steps)
	var step_rise := rise / float(steps)
	var rb := Basis(fwd_flat, Vector3.UP, side)
	for i in steps:
		var riser_top: float = step_rise * float(i + 1) - 0.09
		var riser_bottom: float = 0.0 if i == 0 else step_rise * float(i) - 0.01
		var rc := start + fwd_flat * (step_run * float(i)) + Vector3.UP * ((riser_top + riser_bottom) * 0.5)
		out.append({"xform": Transform3D(rb, rc), "size": Vector3(_STAIR_RISER_T, absf(riser_top - riser_bottom), width * 0.94)})
	return out

## UNE collision en rampe (les joueurs n'ont pas de step-up : des marches
## individuelles bloqueraient la montée) + marches VISUELLES seules (aucune
## collision propre), le long de start->end, + limon plein et contremarches
## fermées (§ART-71 : `stair_support_boxes`, purement visuels eux aussi —
## `steps` grandit le nombre de boîtes versées au batcher mais ne pose
## jamais de second corps de collision).
static func _ramp_with_treads(parent: Node3D, batcher: GeoBatcher, start: Vector3, end: Vector3, width: float, color: Color, nm: String, steps: int, thickness: float, kind: String = "") -> void:
	steps = maxi(steps, 2)
	var r := _ramp_shape(start, end, width, thickness)
	_collision_box(parent, r["xform"], r["size"], nm)
	var side: Vector3 = r["side"]
	# `fwd_flat` (§ART-71, PAS `r["fwd"]`) : `r["fwd"]` est le vecteur 3D
	# incliné le long de la pente (voulu pour la boîte de collision/le limon,
	# qui doivent suivre la pente) — mais l'utiliser pour avancer les marches
	# pas à pas ajoutait sa composante Y en trop en plus du `Vector3.UP *
	# (step_rise * t)` déjà présent (double-compte la montée : ANCIEN bug
	# constaté en écrivant le test de contact contremarche/marche — chaque
	# marche montait alors `fwd.y * step_run` de trop de plus que la
	# précédente). `fwd_flat` (projection horizontale, Y=0) donne des marches
	# ET des contremarches PLATES/VERTICALES, comme une vraie volée d'escalier
	# (seul le limon reste incliné, via `r["xform"]` inchangé).
	var flat_dir := Vector3(end.x - start.x, 0.0, end.z - start.z)
	var flat_len := flat_dir.length()
	var fwd_flat: Vector3 = flat_dir.normalized() if flat_len > 0.001 else r["fwd"]
	var rise := end.y - start.y
	var step_run := flat_len / float(steps)
	var step_rise := rise / float(steps)
	var tb := Basis(fwd_flat, Vector3.UP, side)
	for i in steps:
		var t := float(i) + 1.0
		var tc := start + fwd_flat * (step_run * t - step_run * 0.5) + Vector3.UP * (step_rise * t - 0.05)
		batcher.add_box(Transform3D(tb, tc), Vector3(step_run * 0.92, 0.08, width * 0.94), color, kind)
	for support in stair_support_boxes(start, end, width, steps, thickness):
		batcher.add_box(support["xform"], support["size"], color, kind)

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

## LD-44 (remplace le commentaire LD-40) : montée du faîtage au-dessus de
## `roof_y`, pour une demi-profondeur `hz` (= `size.z * 0.5`) et un angle
## `pitch_deg` — PLAFONNÉE à `ROOF_MAX_RISE` (décision utilisateur « faîte
## <= 3 m au-dessus de la corniche », voir son commentaire) : un bâtiment peu
## profond (`hz * tan(pitch_deg) <= ROOF_MAX_RISE`) garde l'angle nominal
## tel quel ; un bâtiment profond (Échoppes, Saloons) voit sa montée
## RÉDUITE, jamais son plafond assoupli. Pure, publique et testable
## directement (comme `pitched_roof_boxes`), partagée par lui ET par
## `roof_clip_boxes` ci-dessous — UNE SEULE formule de faîtage, jamais deux
## copies qui pourraient diverger.
static func roof_ridge_rise(hz: float, pitch_deg: float = ROOF_PITCH_DEG) -> float:
	return minf(hz * tan(deg_to_rad(pitch_deg)), ROOF_MAX_RISE)

## LD-44 (remplace le commentaire LD-40, même géométrie) : géométrie PURE
## (aucun nœud) des deux pans d'un toit à versants — faîtage au centre de
## `center` (le long de X), pans qui redescendent vers les bords nord/sud de
## `size.z`, à `pitch_deg` (voir `ROOF_PITCH_DEG`), faîtage plafonné par
## `roof_ridge_rise`. Même forme qu'un `ramp()` (`_ramp_shape`, `width` =
## `size.x`, la pleine longueur du faîtage) : c'est littéralement une rampe —
## à 25-30° elle est maintenant SOUS `MapSetup.AGENT_MAX_SLOPE` (46°), Recast
## PEUT donc l'inclure au bake (contrairement à LD-40/60°) ; c'est
## `roof_clip_volumes` (posé par `building2()`, voir son commentaire) qui
## empêche désormais qu'on s'y tienne, pas la pente. Pure et testable
## directement, comme `stair_support_boxes`/`building_trim_boxes`.
static func pitched_roof_boxes(center: Vector3, size: Vector3, roof_y: float, pitch_deg: float = ROOF_PITCH_DEG) -> Array:
	var hz := size.z * 0.5
	var rise := roof_ridge_rise(hz, pitch_deg)
	var ridge := Vector3(center.x, roof_y + rise, center.z)
	var south := _ramp_shape(Vector3(center.x, roof_y, center.z + hz), ridge, size.x, 0.15)
	var north := _ramp_shape(Vector3(center.x, roof_y, center.z - hz), ridge, size.x, 0.15)
	return [south, north]

## Pose les deux pans de `pitched_roof_boxes` (collision + visuel batché) —
## remplace le toit plat de `building2()` quand `roof_pitch_deg > 0.0` (voir
## son commentaire). Ne pose JAMAIS le volume `player_clip` (§`roof_clip_
## volumes`) : ce dernier est posé séparément, une seule fois, par
## `building2()` — `pitched_roof()` reste appelable seule (tests, prototypes)
## sans jamais entraîner de collision `player_clip` fantôme.
static func pitched_roof(parent: Node3D, batcher: GeoBatcher, center: Vector3, size: Vector3, roof_y: float, color: Color, nm: String = "Roof", kind: String = "", pitch_deg: float = ROOF_PITCH_DEG) -> void:
	var i := 0
	for panel in pitched_roof_boxes(center, size, roof_y, pitch_deg):
		var xform: Transform3D = panel["xform"]
		var sz: Vector3 = panel["size"]
		_collision_box(parent, xform, sz, "%s%d" % [nm, i])
		batcher.add_box(xform, sz, color, kind)
		i += 1

## LD-44 (décision utilisateur §12.3 révisée) : géométrie PURE des deux
## volumes `player_clip` posés directement AU-DESSUS de chaque pan de
## `pitched_roof_boxes` — MÊMES points de surface `start`/`ridge` (jamais
## recalculés : aucun jeu possible entre le toit et son volume), étendus de
## `clip_height` vers le haut via `_ramp_shape(..., above=true)`. Pure et
## testable directement (même discipline que `pitched_roof_boxes`).
static func roof_clip_boxes(center: Vector3, size: Vector3, roof_y: float, pitch_deg: float = ROOF_PITCH_DEG, clip_height: float = ROOF_CLIP_HEIGHT) -> Array:
	var hz := size.z * 0.5
	var rise := roof_ridge_rise(hz, pitch_deg)
	var ridge := Vector3(center.x, roof_y + rise, center.z)
	var south := _ramp_shape(Vector3(center.x, roof_y, center.z + hz), ridge, size.x, clip_height, true)
	var north := _ramp_shape(Vector3(center.x, roof_y, center.z - hz), ridge, size.x, clip_height, true)
	return [south, north]

## Pose les deux volumes `player_clip` de `roof_clip_boxes` — COLLISION
## SEULE, jamais de visuel (invisible, comme `invisible_wall`). `layer=mask=
## PhysicsLayers.PLAYER_CLIP` (calque DÉDIÉ, jamais WORLD) : le corps du
## joueur/bot le heurte réellement, vérifié par un `CharacterBody3D.
## move_and_collide` réel (`tests/maps/test_wasteland.gd::test_no_roof_
## point_is_physically_reachable_by_a_moving_player_body`), PARCE QUE
## `scenes/player/player.tscn` inclut désormais ce bit dans son
## `collision_mask` par défaut (WORLD | PLAYER_CLIP). `PLAYER_CLIP` est
## exclu de `PhysicsLayers.SHOT_MASK` (scripts/core/PhysicsLayers.gd) : un
## tir, une grenade ou un grappin (tous en `SHOT_MASK`) traverse donc ce
## volume, vérifié par un rayon réel (`test_a_shot_ray_passes_through_the_
## roof_clip_volume`). Voir docs/COLLISION_LAYERS.md §3.
static func roof_clip_volumes(parent: Node3D, center: Vector3, size: Vector3, roof_y: float, pitch_deg: float = ROOF_PITCH_DEG, clip_height: float = ROOF_CLIP_HEIGHT, nm: String = "Clip") -> void:
	var i := 0
	for panel in roof_clip_boxes(center, size, roof_y, pitch_deg, clip_height):
		var xform: Transform3D = panel["xform"]
		var sz: Vector3 = panel["size"]
		_collision_box(parent, xform, sz, "%s%d" % [nm, i], PhysicsLayers.PLAYER_CLIP, PhysicsLayers.PLAYER_CLIP)
		i += 1

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
## LD-24 (contrat, toit de FuelHouse inatteignable) : la trémie ne doit
## JAMAIS s'approcher du mur opposé à moins de cette marge — l'ancienne
## marge (0,1 m, `_bld_stair_hole_rect`) ne laissait quasiment AUCUNE dalle
## "en face" de la rampe sur un petit bâtiment (ex. FuelHouse, 6 m de
## profondeur : trémie de 6 m => 0,1 m de dalle restante). Cette dalle est
## le seul palier d'ARRIVÉE en ligne droite de la rampe (au-delà de la
## trémie, dans le sens de la montée) — sans lui, Recast (bake :
## `agent_radius` 0,5 m, `scripts/levels/maps/MapSetup.gd`) n'a AUCUN
## polygone assez large pour connecter la rampe à l'étage suivant, même si
## la géométrie "touche" en apparence : un palier de 0,1 m disparaît
## entièrement une fois érodé par le rayon de l'agent (il faut >= 2x
## `agent_radius` de large, cf. le même budget que `_BLD_HOLE_W`/
## `_BLD_RAMP_W`). Vérifié en bake réel (`tests/maps/test_wasteland.gd`,
## chemin sol -> toit FuelHouse) : la rampe de toit restait un îlot de
## navmesh déconnecté tant que la marge valait 0,1 m ; connectée dès qu'elle
## atteint 1,5 m. Sur un GRAND bâtiment (Hotel/Store/Refuge, `Layouts.gd`,
## profondeur >= 10 m), `_BLD_HOLE_D` reste le facteur limitant et cette
## marge ne change rien (aucune régression) : elle ne mord que sur les
## petits bâtiments où `_BLD_HOLE_D` dépasserait sinon la marge disponible.
const _BLD_HOLE_LANDING_MARGIN := 1.5
const _BLD_RAMP_W := 1.6
const _BLD_PARAPET_T := 0.2
## Trim crème (§ART-71, STYLE_BIBLE l.36 : « murs [...] sans trim, sans
## rupture de silhouette ») : 6 cm, la valeur de biseau architecture de
## STYLE_BIBLE §6.6. Débord de toit (§ART-71, contrat) : 0,3 m.
const _BLD_TRIM_T := 0.06
const _BLD_ROOF_OVERHANG := 0.3

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
## `roof_pitch_deg` (LD-40, ADDITIF, défaut 0.0 = comportement d'origine
## inchangé ; valeurs/rationale mises à jour par LD-44, §12.3 révisé) : > 0.0
## remplace le toit plat (praticable si `roof_access`, sinon un simple lid
## plat toujours ATTEIGNABLE par un autre moyen que la rampe — le problème
## visé, §12.3) par `pitched_roof()`, deux pans à cette pente (25-30°,
## `ROOF_PITCH_DEG`, faîte plafonnée par `ROOF_MAX_RISE`), PLUS (LD-44,
## inconditionnel dès que `pitched`) le volume `player_clip` de `roof_clip_
## volumes` juste au-dessus — depuis LD-44 la pente seule (25-30° < 46°,
## `MapSetup.AGENT_MAX_SLOPE`) ne suffit plus à exclure le toit du bake
## (contrairement à LD-40/60°), c'est ce volume qui empêche qu'on s'y tienne
## (voir son commentaire, `roof_clip_volumes`). Dans ce cas, `roof_access`/
## `parapet` sont ignorés pour le TOIT lui-même (aucune rampe ni garde-corps
## posés sur un pan incliné — un vrai escalier de toit n'a de toute façon
## pas sa place là) ; les étages intermédiaires (dalles + rampes internes,
## `floors >= 2`) restent construits normalement, inchangés.
static func building2(parent: Node3D, batcher: GeoBatcher, center: Vector3, size: Vector3, color: Color, floors: int, doors: Array, windows: Array, roof_access: bool, parapet: float, slit: bool = false, stair_side: String = "N", nm: String = "Bld", kind: String = "", roof_kind: String = "", roof_pitch_deg: float = 0.0) -> void:
	floors = maxi(floors, 1)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var bottom := center.y - size.y * 0.5
	var floor_h := size.y / float(floors)
	var wall_t := _BLD_WALL_T
	var hole := _bld_stair_hole_rect(center, size, stair_side, doors)
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

	# ---- Toit : à versants (LD-40, jamais praticable) si roof_pitch_deg > 0 ;
	# sinon comportement d'origine — praticable toujours ; trémie + parapet
	# si roof_access.
	var roof_y := bottom + size.y
	var pitched := roof_pitch_deg > 0.0
	if pitched:
		pitched_roof(parent, batcher, center, size, roof_y, color, "%sRoof" % nm, rkind, roof_pitch_deg)
		# LD-44 : le volume "player_clip" (voir son commentaire) accompagne
		# TOUJOURS un toit à versants, sans exception ni piece dict séparé —
		# un pan à 25-30° ne suffit plus seul (contrairement à LD-40/60°) à
		# empêcher qu'on s'y tienne. Nom "%sClip%d" (jamais "%sRoof...") :
		# ne doit JAMAIS matcher un filtre `begins_with("%sRoof" % nm)`
		# existant (tests/maps/test_kit.gd compte les pans du toit par ce
		# préfixe précis).
		roof_clip_volumes(parent, center, size, roof_y, roof_pitch_deg, ROOF_CLIP_HEIGHT, "%sClip" % nm)
	elif roof_access:
		_bld_slab_with_hole(parent, batcher, center, size, roof_y, wall_t, hole, color, "%sRoof" % nm, rkind)
	else:
		box(parent, batcher, Vector3(center.x, roof_y - wall_t * 0.5, center.z), Vector3(size.x, wall_t, size.z), color, "%sRoof" % nm, 0.0, false, rkind)
	# LD-24 (contrat) : quand la rampe de toit ATTERRIT contre `stair_side`
	# (voir plus bas, `_bld_ramp_span` — vrai dès que `floors` est PAIR), le
	# parapet de CE côté siégerait juste au-dessus de son palier d'arrivée et
	# lui couperait le dégagement vertical (`agent_height`, `MapSetup.gd`) —
	# vérifié en bake : le toit restait inatteignable tant que ce segment de
	# parapet couvrait l'arrivée de la rampe. Un vrai escalier de toit n'a de
	# toute façon pas de garde-corps PILE là où il débouche.
	var skip_parapet_side := roof_access and not pitched and floors % 2 == 0
	if parapet > 0.0 and not pitched:
		var pt := _BLD_PARAPET_T
		var py := roof_y + parapet * 0.5
		if not (skip_parapet_side and stair_side == "N"):
			box(parent, batcher, Vector3(center.x, py, center.z - hz + pt * 0.5), Vector3(size.x, parapet, pt), color, "%sParN" % nm, 0.0, false, rkind)
		if not (skip_parapet_side and stair_side == "S"):
			box(parent, batcher, Vector3(center.x, py, center.z + hz - pt * 0.5), Vector3(size.x, parapet, pt), color, "%sParS" % nm, 0.0, false, rkind)
		if not (skip_parapet_side and stair_side == "W"):
			box(parent, batcher, Vector3(center.x - hx + pt * 0.5, py, center.z), Vector3(pt, parapet, size.z), color, "%sParW" % nm, 0.0, false, rkind)
		if not (skip_parapet_side and stair_side == "E"):
			box(parent, batcher, Vector3(center.x + hx - pt * 0.5, py, center.z), Vector3(pt, parapet, size.z), color, "%sParE" % nm, 0.0, false, rkind)

	# ---- Trims crème + débord de toit (§ART-71) : cassent la silhouette
	# « mur plan » (STYLE_BIBLE l.36) — purement visuels (jamais de collision
	# propre : la collision du bâtiment ne change pas, test d'invariance Kit).
	for trim_box in building_trim_boxes(center, size):
		batcher.add_box(_xform_box(trim_box["pos"], 0.0), trim_box["size"], Cartoon.PAPER)
	for overhang_box in roof_overhang_boxes(center, size, roof_y):
		batcher.add_box(_xform_box(overhang_box["pos"], 0.0), overhang_box["size"], color, rkind)

	# ---- Murs par étage/côté : portes en priorité, sinon fenêtres, sinon plein ----
	for f in floors:
		var y0 := bottom + floor_h * float(f)
		var y1 := y0 + floor_h
		for side in ["N", "S", "E", "W"]:
			_bld_wall_side(parent, batcher, center, size, f, y0, y1, side, wall_t, doors, windows, slit, color, nm, kind)

	# ---- Rampes internes (une par transition d'étage) + rampe de toit ----
	# LD-24 (contrat, îlot de navmesh du toit de FuelHouse) : chaque volée
	# ALTERNE son sens (`_bld_ramp_span`, escalier en switchback réel) au lieu
	# de repartir du mur à chaque étage. Une rampe qui repart TOUJOURS du mur
	# `stair_side` ne touche la dalle de l'étage suivant que par sa jonction
	# LATÉRALE (rampe `_BLD_RAMP_W` posée À CÔTÉ des bandes de la trémie,
	# `_bld_slab_with_hole` — les deux ne coïncident qu'au pied même de la
	# rampe, la pente s'en écarte aussitôt) : ce type de raccord ne tient PAS
	# au bake Recast (`agent_radius` 0,5 m, `MapSetup.gd`), vérifié en isolant
	# le bake (élargir la trémie, ajouter un palier latéral plein : aucun n'a
	# rétabli le chemin). Seule la jonction FRONTALE (perpendiculaire au sens
	# de la montée, toute la largeur de la volée à la MÊME hauteur — comme la
	# dalle pleine du RDC sous la 1ère volée, ou le palier `_bld_stair_hole_
	# rect`/`_BLD_HOLE_LANDING_MARGIN` en face de la trémie) tient. En
	# alternant, chaque volée (sauf la 1ère, sur la dalle RDC déjà pleine)
	# démarre exactement où la PRÉCÉDENTE arrive — ce palier frontal, déjà
	# vérifié fonctionnel. `skip_parapet_side` (ci-dessus) dégage l'arrivée de
	# la DERNIÈRE volée quand elle atterrit contre le mur.
	var ep := _bld_ramp_endpoints(hole, stair_side)
	for f in range(1, floors):
		var y_from: float = bottom + floor_h * float(f - 1)
		var y_to: float = bottom + floor_h * float(f)
		var span := _bld_ramp_span(ep, f)
		_ramp_with_treads(parent, batcher, Vector3(span["from"].x, y_from, span["from"].z), Vector3(span["to"].x, y_to, span["to"].z), _BLD_RAMP_W, color, "%sRamp%d" % [nm, f], 8, 0.2)
	if roof_access and not pitched:
		var y_from2: float = bottom + floor_h * float(floors - 1)
		var span2 := _bld_ramp_span(ep, floors)
		_ramp_with_treads(parent, batcher, Vector3(span2["from"].x, y_from2, span2["from"].z), Vector3(span2["to"].x, roof_y, span2["to"].z), _BLD_RAMP_W, color, "%sRampRoof" % nm, 8, 0.2)

## LD-20 (contrat, « building2 ... casse le chemin extérieur si ce côté
## porte une porte ») : position "en travers" (perpendiculaire au sens de la
## montée) de la trémie — `center.x` (N/S) ou `center.z` (E/W) par défaut,
## comme avant, SAUF si une porte est posée sur `stair_side` AU REZ-DE-
## CHAUSSÉE (floor 0 — la contrainte déjà documentée plus haut, « à choisir
## sur un côté SANS porte au rez-de-chaussée », précisément parce que c'est
## LÀ que le conflit est un vrai blocage physique : la rampe démarre pile à
## ce mur, posée dans le même axe qu'une porte RDC par défaut (voir
## `_bld_ramp_endpoints`), et la bloquerait — constaté en isolant le bake).
## Portée délibérément limitée au RDC (pas les étages) : une porte d'étage
## sur `stair_side` (ex. GasOffice, `wasteland.gd`, E/étage 1) est un défaut
## différent (vide de trémie derrière la porte, pas un blocage), déjà
## documenté et accepté comme écart pour CE bâtiment précis (son accès réel
## passe par une AUTRE porte) — le décaler ici romprait le calage fin déjà
## fait autour de lui (`test_snd_path_ratio_is_within_range`, et les tests de
## parité/rotation de `tests/maps/test_wasteland_markers.gd`, hors de ma
## liste de fichiers). Décale vers l'extrémité du mur qui libère la porte
## RDC (essaie `0`, puis le décalage MAX positif, puis MAX négatif) ;
## retombe sur le centre (comportement d'origine, inchangé) si aucune porte
## RDC n'y est posée.
static func _bld_hole_across_center(center: Vector3, size: Vector3, stair_side: String, doors: Array) -> float:
	var axis_is_x := stair_side == "N" or stair_side == "S"
	var half_span: float = (size.x if axis_is_x else size.z) * 0.5
	var mid: float = center.x if axis_is_x else center.z
	var hw := _BLD_HOLE_W * 0.5
	var max_shift: float = maxf(half_span - hw - 0.3, 0.0)
	var candidates: Array[float] = [0.0, max_shift, -max_shift]
	for shift in candidates:
		var lo: float = mid + shift - hw
		var hi: float = mid + shift + hw
		var blocked := false
		for entry in doors:
			var d: Dictionary = entry
			if String(d.get("side", "")) != stair_side or int(d.get("floor", 0)) != 0:
				continue
			var dw: float = float(d.get("w", 1.6))
			var doff: float = float(d.get("offset", 0.0))
			var dc: float = mid + doff
			if lo < dc + dw * 0.5 and hi > dc - dw * 0.5:
				blocked = true
				break
		if not blocked:
			return mid + shift
	return mid

## Rectangle de la trémie d'escalier (`_BLD_HOLE_W` x `_BLD_HOLE_D`, jamais
## plus près du mur opposé que `_BLD_HOLE_LANDING_MARGIN` — LD-24, voir son
## commentaire) collée au mur `stair_side`, en coordonnées MONDE. Largeur
## dérivée de `_BLD_HOLE_W` (pas un 1.0 en dur) ; position en travers décalée
## via `_bld_hole_across_center` (LD-20) pour ne jamais chevaucher une porte
## de ce côté.
static func _bld_stair_hole_rect(center: Vector3, size: Vector3, stair_side: String, doors: Array) -> Dictionary:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var hw := _BLD_HOLE_W * 0.5
	var m := _BLD_HOLE_LANDING_MARGIN
	var ac := _bld_hole_across_center(center, size, stair_side, doors)
	match stair_side:
		"S":
			return {"x_lo": ac - hw, "x_hi": ac + hw, "z_lo": maxf(center.z + hz - _BLD_HOLE_D, center.z - hz + m), "z_hi": center.z + hz}
		"E":
			return {"x_lo": maxf(center.x + hx - _BLD_HOLE_D, center.x - hx + m), "x_hi": center.x + hx, "z_lo": ac - hw, "z_hi": ac + hw}
		"W":
			return {"x_lo": center.x - hx, "x_hi": minf(center.x - hx + _BLD_HOLE_D, center.x + hx - m), "z_lo": ac - hw, "z_hi": ac + hw}
		_:
			return {"x_lo": ac - hw, "x_hi": ac + hw, "z_lo": center.z - hz, "z_hi": minf(center.z - hz + _BLD_HOLE_D, center.z + hz - m)}

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

## Escalier en switchback réel (LD-24, voir le commentaire d'appel dans
## `building2`) : la volée `transition` (1 = RDC->étage 1, 2 = étage 1->2,
## etc., `floors` désigne la DERNIÈRE trémie traversée, celle qui mène au
## toit) part de `lo` (le mur) quand `transition` est IMPAIRE — la 1ère volée
## part bien du mur, posée sur la dalle RDC PLEINE (aucune trémie à y
## raccorder, donc aucun problème de jonction là) — et de `hi` quand elle est
## PAIRE : elle repart alors du point où la volée précédente arrive, déjà
## raccordé à la dalle par la jonction FRONTALE du palier
## `_BLD_HOLE_LANDING_MARGIN` (perpendiculaire au sens de la montée, toute la
## largeur de la volée à la même hauteur — la seule qui tienne au bake, voir
## le commentaire d'appel), plutôt que de retraverser la trémie pour revenir
## au mur par sa jonction LATÉRALE, celle qui ne relie pas au bake. Chaque
## volée impaire ensuite repart du mur (`lo`) à nouveau, comme une vraie cage
## d'escalier en zigzag.
static func _bld_ramp_span(ep: Dictionary, transition: int) -> Dictionary:
	var lo: Vector3 = ep["lo"]
	var hi: Vector3 = ep["hi"]
	if transition % 2 == 0:
		return {"from": hi, "to": lo}
	return {"from": lo, "to": hi}

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

## Boîtes VISUELLES de trim crème (§ART-71, STYLE_BIBLE l.36 : « les murs
## sont des plans géants sans biseau, sans trim, sans rupture de silhouette »
## — l'anti-patron visé) : 4 arêtes verticales (les coins du bâtiment, pleine
## hauteur) + un bandeau horizontal en haut des 4 pans de mur, juste sous le
## bord du toit. `center`/`size` sont le volume TOTAL du bâtiment (comme
## `building2` les reçoit), donc les arêtes courent sur toute la hauteur,
## portes/étages compris. AUCUNE collision propre : ni ce helper ni son
## appelant ne posent `_collision_box` pour ces boîtes, seulement des
## entrées batcher (la collision du bâtiment ne change pas — test
## d'invariance Kit). Pure (aucun nœud) et volontairement SANS underscore :
## testable directement, comme les autres géométries pures de ce fichier.
static func building_trim_boxes(center: Vector3, size: Vector3) -> Array:
	var t := _BLD_TRIM_T
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var top := center.y + size.y * 0.5
	var out: Array = []
	for corner in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
		var cx: float = center.x + corner.x * (hx - t * 0.5)
		var cz: float = center.z + corner.y * (hz - t * 0.5)
		out.append({"pos": Vector3(cx, center.y, cz), "size": Vector3(t, size.y, t)})
	out.append({"pos": Vector3(center.x, top - t * 0.5, center.z - hz + t * 0.5), "size": Vector3(size.x, t, t)})
	out.append({"pos": Vector3(center.x, top - t * 0.5, center.z + hz - t * 0.5), "size": Vector3(size.x, t, t)})
	out.append({"pos": Vector3(center.x - hx + t * 0.5, top - t * 0.5, center.z), "size": Vector3(t, t, size.z)})
	out.append({"pos": Vector3(center.x + hx - t * 0.5, top - t * 0.5, center.z), "size": Vector3(t, t, size.z)})
	return out

## Boîtes VISUELLES de débord de toit (§ART-71, contrat : « débords de toit
## de 0,3 m hors espace praticable ») : un avant-toit qui dépasse de 0,3 m
## au-delà des murs sur les 4 côtés (coins couverts par le chevauchement des
## côtés adjacents), posé SOUS `roof_y` (le dessus du toit, praticable) —
## jamais au niveau ni au-dessus de ce dessus, donc jamais dans l'espace
## praticable. AUCUNE collision propre : ni ce helper ni son appelant ne
## posent `_collision_box` pour ces boîtes, seulement des entrées batcher —
## un débord ne peut donc jamais devenir praticable, ni à la collision ni au
## navmesh. Pure (aucun nœud) et volontairement SANS underscore : testable
## directement.
static func roof_overhang_boxes(center: Vector3, size: Vector3, roof_y: float) -> Array:
	var d := _BLD_ROOF_OVERHANG
	var t := 0.15
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y := roof_y - t * 0.5 - 0.02
	return [
		{"pos": Vector3(center.x, y, center.z - hz - d * 0.5), "size": Vector3(size.x + d * 2.0, t, d)},
		{"pos": Vector3(center.x, y, center.z + hz + d * 0.5), "size": Vector3(size.x + d * 2.0, t, d)},
		{"pos": Vector3(center.x - hx - d * 0.5, y, center.z), "size": Vector3(d, t, size.z + d * 2.0)},
		{"pos": Vector3(center.x + hx + d * 0.5, y, center.z), "size": Vector3(d, t, size.z + d * 2.0)},
	]

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

	# `visual` (ART-91, ADDITIF, défaut `true` = comportement 100% inchangé) :
	# "pièce entièrement remplacée" par la couche d'art (docs/art/
	# WASTELAND_V4_ART_PLAN.md §1 R9) — `visual:false` bascule TOUT le rendu
	# de CETTE pièce (murs/dalles/toit/trims d'un `building2`, boîte, rampe,
	# escalier, clôture...) vers un `GeoBatcher` JETABLE, jamais fusionné dans
	# la scène : la COLLISION reste, à l'identique, injectée dans la VRAIE
	# scène (chaque géométrie ci-dessous pose sa collision via
	# `_collision_box(parent, ...)`, directement sur `parent`, jamais via ce
	# batcher — voir `WastelandArt.gd` R9 "aucun CollisionObject3D ajouté").
	# `prop`/`skin` (ci-dessus/ci-dessous) ne consomment jamais `batcher` :
	# cette bascule ne les concerne pas, ils gèrent leur propre visuel via
	# `PropCatalog` (déjà "sans collision propre" pour `skin`, cf. son
	# commentaire).
	var art_batcher := batcher if bool(piece.get("visual", true)) else GeoBatcher.new()

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
			ramp(parent, art_batcher, piece["start"], piece["end"], float(piece["width"]), color, float(piece.get("thickness", 1.0)), nm, kind)
		"stairs":
			stairs(parent, art_batcher, piece["start"], piece["end"], float(piece["width"]), int(piece.get("steps", 10)), color, nm, kind)
		"catwalk":
			catwalk(parent, art_batcher, piece["start"], piece["end"], float(piece["width"]), color, nm, kind)
		"fence":
			fence(parent, art_batcher, piece["start"], piece["end"], float(piece.get("height", 1.6)), color, nm, kind)
		"invisible_wall":
			invisible_wall(parent, piece["start"], piece["end"], float(piece.get("height", 8.0)), nm)
		"container":
			# `solid` (§2 "one collision box instead of the 4-6-body shell") :
			# une simple boîte pleine — utilisé pour les conteneurs "tops"/piliers
			# qui n'ont pas besoin d'un intérieur creux.
			if bool(piece.get("solid", false)):
				box(parent, art_batcher, piece["pos"], piece["size"], color, nm, float(piece.get("rot_y", 0.0)), false, kind)
			else:
				container(parent, art_batcher, piece["pos"], piece["size"], color, String(piece.get("axis", "z")), int(piece.get("ends_open", 0)), nm)
		"building2":
			# `roof_kind` (piece dict, ADDITIF) : matériau du toit/parapet
			# séparé de celui des murs/dalles (ex. tôle rouillée sur planches) —
			# retombe sur `kind` (le rôle "wall") si absent.
			var roof_kind := String(piece.get("roof_kind", palette.get(color_key + "_roof_kind", "")))
			building2(parent, art_batcher, piece["pos"], piece["size"], color, int(piece.get("floors", 1)), (piece.get("doors", []) as Array), (piece.get("windows", []) as Array), bool(piece.get("roof_access", false)), float(piece.get("parapet", 0.0)), bool(piece.get("slit", false)), String(piece.get("stair_side", "N")), nm, kind, roof_kind, float(piece.get("roof_pitch_deg", 0.0)))
		"crane":
			crane(parent, art_batcher, piece["pos"], color, float(piece.get("rot_y", 0.0)), nm)
		"water_tower":
			water_tower(parent, art_batcher, piece["pos"], color, float(piece.get("rot_y", 0.0)), nm)
		"antenna":
			antenna(parent, art_batcher, piece["pos"], color, float(piece.get("rot_y", 0.0)), nm)
		_:
			box(parent, art_batcher, piece["pos"], piece["size"], color, nm, float(piece.get("rot_y", 0.0)), bool(piece.get("visual_only", false)), kind)

# ======================================================================
#  Géométrie PURE (aucun nœud) pour les tests de validation de layout.
# ======================================================================

## Repère (axe le long du mur, coordonnée FIXE perpendiculaire, bornes
## c_lo/c_hi) d'un côté de `building2` — EXACTEMENT le `match side:` inline en
## tête de `_bld_wall_side` (recopié ici à l'identique, jamais divergé : voir
## `door_world_rect`/`window_world_rects` ci-dessous, qui en dépendent toutes
## les deux). Pure, publique (ART-91 : consommée hors de Kit par
## `tools/art/export_v4_openings.gd` et par la sonde de parité de
## `tests/maps/test_wasteland_art_parity.gd`).
static func wall_axis_info(center: Vector3, size: Vector3, side: String) -> Dictionary:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	match side:
		"N":
			return {"axis": "x", "fixed": center.z - hz, "mid": center.x, "c_lo": center.x - hx, "c_hi": center.x + hx}
		"S":
			return {"axis": "x", "fixed": center.z + hz, "mid": center.x, "c_lo": center.x - hx, "c_hi": center.x + hx}
		"E":
			return {"axis": "z", "fixed": center.x + hx, "mid": center.z, "c_lo": center.z - hz, "c_hi": center.z + hz}
		_:
			return {"axis": "z", "fixed": center.x - hx, "mid": center.z, "c_lo": center.z - hz, "c_hi": center.z + hz}

## Convertit un intervalle (axis, fixed, c0..c1, y0..y1) — le vocabulaire
## interne de `_bld_wall_side`/`wall_axis_info` — en rectangle MONDE
## x_lo/x_hi/z_lo/z_hi/y0/y1 (une ouverture est infiniment fine dans l'axe
## perpendiculaire au mur : `x_lo == x_hi` sur un côté N/S, `z_lo == z_hi` sur
## un côté E/O — le cadre kit v2 d'ART-92 donne l'épaisseur réelle).
static func opening_world_rect(axis: String, fixed: float, c0: float, c1: float, y0: float, y1: float) -> Dictionary:
	var c_lo := minf(c0, c1)
	var c_hi := maxf(c0, c1)
	if axis == "x":
		return {"x_lo": c_lo, "x_hi": c_hi, "z_lo": fixed, "z_hi": fixed, "y0": y0, "y1": y1}
	return {"x_lo": fixed, "x_hi": fixed, "z_lo": c_lo, "z_hi": c_hi, "y0": y0, "y1": y1}

## Rectangle MONDE d'UNE porte de `building2` (une entrée de `piece["doors"]"`)
## — même arithmétique EXACTE que la boucle `side_doors` de `_bld_wall_side`
## (`_bld_doors_for` pour le filtre côté/étage, recopié ici à l'identique).
## Pure (aucun nœud) : ART-91 R3 "la source de vérité est la collision
## construite... jamais recopiée à la main" — `tools/art/export_v4_openings.gd`
## et la sonde de parité l'appellent directement plutôt que de retranscrire
## les coordonnées de `wasteland.gd` à la main. `build_piece`/`building2` ne
## l'appellent PAS (ils gardent leur propre boucle, inchangée : aucun risque
## de régression sur du code déjà calé — LD-20/LD-24/LD-43) ; la concordance
## entre les deux est vérifiée par un raycast RÉEL dans
## `tests/maps/test_wasteland_art_parity.gd`.
static func door_world_rect(piece: Dictionary, door: Dictionary) -> Dictionary:
	var center: Vector3 = piece["pos"]
	var size: Vector3 = piece["size"]
	var floors := maxi(int(piece.get("floors", 1)), 1)
	var floor_h := size.y / float(floors)
	var bottom := center.y - size.y * 0.5
	var side := String(door.get("side", "N"))
	var floor_idx := int(door.get("floor", 0))
	var y0: float = float(door["y"]) if door.has("y") else bottom + floor_h * float(floor_idx)
	var h: float = float(door.get("h", 2.4))
	var w: float = float(door.get("w", 1.6))
	var off: float = float(door.get("offset", 0.0))
	var ax := wall_axis_info(center, size, side)
	var mid: float = ax["mid"]
	var rect := opening_world_rect(String(ax["axis"]), float(ax["fixed"]), mid + off - w * 0.5, mid + off + w * 0.5, y0, y0 + h)
	rect["side"] = side
	rect["floor"] = floor_idx
	return rect

## Rectangles MONDE des fenêtres d'UN côté/étage d'un `building2` — même
## arithmétique EXACTE que la boucle "windows" de `_bld_wall_side` (recopiée
## ici à l'identique). RAPPEL (comme dans `_bld_wall_side`) : Kit ne pose une
## fenêtre que sur un côté/étage SANS porte — cette fonction ne vérifie pas
## elle-même cette condition, à l'appelant de ne l'invoquer que pour un
## `(side, floor_idx)` sans porte (voir `door_world_rect`/`piece["doors"]`).
static func window_world_rects(piece: Dictionary, side: String, floor_idx: int, slit: bool = false) -> Array:
	var center: Vector3 = piece["pos"]
	var size: Vector3 = piece["size"]
	var floors := maxi(int(piece.get("floors", 1)), 1)
	var floor_h := size.y / float(floors)
	var bottom := center.y - size.y * 0.5
	var y0 := bottom + floor_h * float(floor_idx)
	var ax := wall_axis_info(center, size, side)
	var axis := String(ax["axis"])
	var fixed: float = ax["fixed"]
	var c_lo: float = ax["c_lo"]
	var c_hi: float = ax["c_hi"]
	var wall_len := c_hi - c_lo
	var n := maxi(1, int(floor(wall_len / 3.0)))
	var win_w := 1.2
	var sill: float = 1.2 if slit else 1.0
	var win_h: float = 0.3 if slit else 1.0
	var out: Array = []
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var cc: float = c_lo + t * wall_len
		var rect := opening_world_rect(axis, fixed, cc - win_w * 0.5, cc + win_w * 0.5, y0 + sill, y0 + sill + win_h)
		rect["side"] = side
		rect["floor"] = floor_idx
		out.append(rect)
	return out

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
