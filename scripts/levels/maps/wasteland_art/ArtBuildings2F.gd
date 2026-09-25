## ArtBuildings2F.gd
## ART-95 — module de la couche d'art v4 de Wasteland (contrat WastelandArt.gd,
## docs/art/WASTELAND_V4_ART_PLAN.md §1 R9 "mise en œuvre" / §2 "traitement
## par volume") : bâtiments à 2 niveaux et Wagon (Hôtel, Banque, SaloonW/E,
## Wagon), plus leurs escaliers et la galerie du Saloon (StairImpasseW/E,
## StairPassageW/E, StairRuelleW/E, StairGalerieW/E, BalconW/E, RampeBalconW/E
## — toutes déjà posées par `wasteland.gd`, jamais un `CollisionObject3D`
## ajouté ici, §1 R9).
##
## Contrat de fichiers (ART-95) : ce script + `assets/models/props/wasteland/
## skins/{hotel,banque,saloon,wagon}_*` (peaux neuves de cette tâche) +
## `tools/art/skins_2f.yaml` (manifeste de fabrication). Les coques Tripo
## d'ART-93 (`.../wasteland/tripo/wl_saloon.glb`, `wl_saloon_long.glb`,
## `wl_wagon.glb`) et les modules kit v2 d'ART-92 (`.../wasteland/shanty/`)
## sont RÉUTILISÉS tels quels, jamais recopiés ni modifiés ici.
##
## Toit (B0) : NON traité — bloquant utilisateur, voir la note du plan §0.6 et
## §1 "B0". Les peaux ci-dessous s'arrêtent à l'égout (hauteur `size.y` de la
## boîte `building2`, jamais au-delà) : « le plan tient quelle que soit la
## décision, les cartes s'arrêtent à l'égout ». Aucune fausse façade, aucune
## tôle de toit posée par ce module.
##
## Peau, jamais collision (§1 R9) : chaque pièce ci-dessous garde la boîte de
## collision que `Kit.build_piece` a DÉJÀ posée pour `wasteland.gd` (aucune
## pièce n'a `"visual":false` — cette bascule touche `wasteland.gd`, hors de
## mon périmètre). Les cartes de façade sont fabriquées (tools/blender/
## shell_to_skin.py, ART-92, mode "card"/"shell") avec leur origine locale
## recentrée au CENTRE de la pièce réelle, au SOL (voir tools/art/
## skins_2f.yaml, "convention de recentrage") : elles s'instancient donc avec
## EXACTEMENT le même geste que `ArtCovers._place_ground` —
## `node.position = Vector3(pos.x, pos.y - size.y * 0.5, pos.z)`,
## `node.rotation.y` TOUJOURS 0 (« le repère Tripo place la façade en +Z à
## rot_y=0 », plan §2 ; `wasteland.gd::_mirror_piece` ne tourne JAMAIS un
## `building2`, seul son `pos.x` est miroité) — le flanc Ouest/Est d'un même
## bâtiment (ou le mur Ouest/Est de l'autre moitié Hotel<->Banque, SaloonW<->
## SaloonE) réutilise alors la MÊME carte, simplement retournée en place par
## une échelle locale `Vector3(-1,1,1)` (seule façon de MIROITER un axe sans
## le confondre avec une rotation, qui échangerait aussi la profondeur —
## Godot restitue correctement l'éclairage d'un maillage à déterminant négatif
## via sa normal-matrix standard, vérifié aux captures V3/V4/V5 de la tâche).
##
## Ouvertures réelles — source de vérité (§1 R3) : `tools/art/data/
## wasteland_v4_boxes.json` (export ART-91), relu ICI à l'exécution (jamais
## recopié à la main) pour poser les volets/cadres exactement là où
## `tools/blender/shell_to_skin.py` a percé la peau hors ligne (même fichier
## des deux côtés — voir `tools/art/skins_2f.yaml`).
##
## Limite connue du gisement Tripo ART-93 (sondée pendant cette tâche, voir
## `tools/art/skins_2f.yaml` "deviations") : `wl_saloon_long`/`wl_wagon` sont
## plus petits que leur brief de modélisation (~55-70 % sur l'axe long) — les
## cartes/coques qui en dérivent dépassent le contrat d'étirement d'ART-92
## (12 %/15 %) une fois mises à la cote RÉELLE de la boîte Wasteland. La
## COUVERTURE reste exacte (une carte est TOUJOURS mise à l'échelle exacte de
## la boîte cible, donc R1 — parité visuel/collision, ±10 cm — n'est PAS en
## jeu : l'étirement déforme la texture, jamais l'emprise). Signalé en
## `blocked_on` : nécessite soit plus de crédit Tripo (ART-93, hors de mon
## périmètre), soit un découpage en travées (R2) qu'une prochaine tâche peut
## reprendre à partir de ce module.
class_name ArtBuildings2F
extends RefCounted

const SKINS_DIR := "res://assets/models/props/wasteland/skins/"
const SHANTY_DIR := "res://assets/models/props/wasteland/shanty/"
const BOXES_JSON_PATH := "res://tools/art/data/wasteland_v4_boxes.json"

## Les 5 "kinds" peints du contrat ART-73/92 (make_wl_shanty_kit.py::KINDS,
## Cartoon.gd::_PAINTED) — voir ArtCovers.gd pour la même convention, réécrite
## ici en local (ce module ne dépend d'aucune fonction privée d'un autre
## chantier, même règle que ArtCovers.gd).
const _PAINTED_KINDS := ["wood_planks", "corrugated_metal", "rust", "painted_metal", "dirty_glass"]

## Hauteur d'étage Kit (doc 11 §9) — sert uniquement de repli quand une
## ouverture du JSON n'a pas de "world" exploitable (ne devrait jamais
## arriver : le JSON en porte toujours un, voir export_v4_openings.gd).
const _FLOOR_HEIGHT_M := 3.2

# ======================================================================
#  Point d'entrée (contrat WastelandArt.gd : `apply(parent, data) -> void`,
#  fonction STATIQUE, purement visuelle).
# ======================================================================

static func apply(parent: Node3D, data: Dictionary) -> void:
	var by_name := _index_by_name(data.get("pieces", []) as Array)
	var boxes := _load_boxes()

	_skin_hotel_banque(parent, by_name, boxes)
	_skin_saloon(parent, by_name, boxes)
	_skin_wagon(parent, by_name, boxes)
	_skin_stairs(parent, by_name)
	_skin_gallery(parent, by_name)


# ======================================================================
#  Primitives (copies locales — même règle d'indépendance qu'ArtCovers.gd).
# ======================================================================

static func _index_by_name(pieces: Array) -> Dictionary:
	var out: Dictionary = {}
	for entry in pieces:
		var p: Dictionary = entry
		var nm := String(p.get("name", ""))
		if nm == "":
			continue
		if not out.has(nm):
			out[nm] = []
		(out[nm] as Array).append(p)
	return out

static func _for_each(by_name: Dictionary, name: String, cb: Callable) -> void:
	if not by_name.has(name):
		return
	for entry in (by_name[name] as Array):
		cb.call(entry as Dictionary)

static func _instance(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D

## Repeint chaque surface par le nom de matériau glTF d'origine — voir
## ArtCovers._paint_tree pour le même mécanisme (slot 0 des coques/cartes
## Tripo, sans nom de kind reconnu, reste intact : R2 "albédo Tripo intact").
static func _paint_tree(node: Node, tint: Color = Color.WHITE) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src_mat := mi.mesh.surface_get_material(s)
			var slot := String(src_mat.resource_name) if src_mat else ""
			if slot.is_empty() or not _PAINTED_KINDS.has(slot):
				continue
			mi.set_surface_override_material(s, Cartoon.painted_for_slot(slot, tint))
	for c in node.get_children():
		_paint_tree(c, tint)

## Place une peau de façade dont l'origine locale est le CENTRE de la pièce
## réelle, au sol (convention de fabrication, voir l'en-tête de fichier et
## tools/art/skins_2f.yaml) : `rotation.y` toujours 0 ; `mirror_x` retourne la
## carte en place (échelle locale -1 sur X) pour réutiliser la même peau sur
## le flanc opposé (Ouest<->Est) sans en fabriquer une seconde.
static func _place_facade(parent: Node3D, pos: Vector3, size: Vector3, asset_path: String, mirror_x: bool = false) -> void:
	var node := _instance(asset_path)
	if node == null:
		return
	node.position = Vector3(pos.x, pos.y - size.y * 0.5, pos.z)
	node.scale = Vector3(-1.0 if mirror_x else 1.0, 1.0, 1.0)
	parent.add_child(node)
	_paint_tree(node)

## Charge `tools/art/data/wasteland_v4_boxes.json` (export ART-91, §1 R3 —
## source de vérité des ouvertures, jamais recopiées à la main) et renvoie
## `{nom_batiment: {"pos", "size", "openings": [...]}}`. Absence/erreur de
## lecture (ne devrait jamais arriver, le fichier est un livrable ART-91
## versionné) : renvoie `{}` — les peaux de façade (structure) restent quand
## même posées par `_place_facade`, seules les décorations d'ouverture
## (volets, cadres) sont alors sautées, jamais un crash.
static func _load_boxes() -> Dictionary:
	var f := FileAccess.open(BOXES_JSON_PATH, FileAccess.READ)
	if f == null:
		push_warning("ArtBuildings2F: wasteland_v4_boxes.json introuvable (%s)" % BOXES_JSON_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("buildings"):
		push_warning("ArtBuildings2F: wasteland_v4_boxes.json illisible")
		return {}
	var out: Dictionary = {}
	for entry in (parsed as Dictionary)["buildings"] as Array:
		var b: Dictionary = entry
		var nm := String(b.get("name", ""))
		if nm != "":
			out[nm] = b
	return out

## Centre monde + cotes d'une ouverture du JSON (son champ "world" est déjà
## en coordonnées ABSOLUES, exactement la même passe que celle qui a servi à
## percer la peau hors ligne — voir tools/art/skins_2f.yaml) :
## `{"center": Vector3, "w": float, "h": float}`.
static func _opening_world(o: Dictionary) -> Dictionary:
	var w: Array = o.get("world", [])
	if w.size() < 6:
		return {}
	var x0: float = w[0]; var x1: float = w[1]
	var z0: float = w[2]; var z1: float = w[3]
	var y0: float = w[4]; var y1: float = w[5]
	return {
		"center": Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5),
		"w": absf(x1 - x0) if o.get("side", "N") in ["N", "S"] else absf(z1 - z0),
		"h": absf(y1 - y0),
	}

## Marge de dégagement (m) appliquée au centre de l'ouverture, vers
## l'EXTÉRIEUR du bâtiment — la carte de façade garde jusqu'à `MAX_RELIEF_M`
## (10 cm, R1) de relief résiduel après écrasement (`flatten_relief`,
## shell_to_skin.py) DANS LES DEUX SENS autour du plan nominal de la boîte :
## un volet posé pile au plan nominal (sans marge) peut donc se retrouver
## partiellement ENFONCÉ dans la carte si son relief local est repoussé vers
## l'intérieur à cet endroit précis. Cette marge (nettement au-dessus du
## standoff des cartes, 3 cm) couvre le pire cas du relief résiduel sans
## décoller visiblement le volet du mur ailleurs.
const _WINDOW_STANDOFF_M := 0.08

## Retour vérificateur (fenêtre centrale S d'Hôtel/Banque, cf. skins_2f.yaml
## "deviations") — cause RÉELLE, diagnostiquée en rendu Godot frais (jamais
## une capture fournie par un agent) : ce n'est PAS le relief de la carte
## ci-dessus (`hotel_window_shutters.glb` rendu SEUL, isolé de toute façade,
## est rigoureusement IDENTIQUE aux 3 offsets — cadre + 2 jambages, aucun
## panneau au centre : « volets ouverts » est bien un TROU par construction,
## jamais un panneau plein). Ce que le joueur voit à travers ce trou dépend
## donc entièrement de ce qu'il y a DERRIÈRE, côté Kit — et c'est LÀ que
## Hôtel/Banque diffèrent des fenêtres voisines : `stair_side="N"` (wasteland.
## gd) centre la trémie d'escalier de `Kit._bld_hole_across_center` EXACTEMENT
## sur l'axe de symétrie du bâtiment (`_bld_hole_across_center` : premier
## candidat testé = `shift=0.0`, aucune porte "N" RdC chez Hôtel/Banque pour
## le bloquer → retenu tel quel) — le MÊME axe que la fenêtre centrale des 3.
## Une trémie d'escalier est un vide de plancher : au-dessus d'elle (jusqu'au
## toit) rien n'arrête un rayon horizontal tiré depuis cette fenêtre, qui
## traverse alors la profondeur ENTIÈRE du bâtiment (~6 m) et ressort sur le
## mur Nord — plein, peint de la MÊME teinte Kit que le mur extérieur (aucune
## porte/fenêtre "N" chez Hôtel/Banque, §2/skins_2f.yaml "no_north_wall_
## hotel_banque" : la face Nord n'a aucune peau). Résultat : un carré plat et
## uni, sans ombre ni relief proche pour le lire comme une cavité — confirmé
## en isolant la variable (rendu hors-axe : identique ; `_WINDOW_STANDOFF_M`
## poussé à 0,6 puis 1,5 m : seuls les jambages s'écartent, l'intérieur reste
## plat, preuve qu'aucun objet proche n'« embouche » le volet). Les fenêtres
## voisines profitent d'un relief intérieur proche (structure de la trémie,
## sous-face de palier) qui n'existe, par construction du Kit, QU'À CÔTÉ de
## son propre axe — une coïncidence de plan, pas un trait du volet lui-même.
## Correction : `_place_window_backing` (ci-dessous) donne à CHAQUE volet
## ouvert (les 22 instances, jamais seulement celui-ci) son propre fond
## d'ombre — la cavité se lit alors par construction, sans dépendre de ce qui
## se trouve par hasard derrière le mur Kit à cet endroit précis.
const _WINDOW_BACKING_DEPTH_M := 0.22    # < Kit._BLD_WALL_T (0.25 m, hors périmètre) : reste dans l'épaisseur du mur, jamais un panneau qui flotte dans la pièce
const _WINDOW_BACKING_MARGIN_M := 0.12   # retrait sous les cotes de l'ouverture : reste caché derrière cadre/jambages, ne déborde jamais visiblement autour d'eux
const _WINDOW_BACKING_COLOR := Color("221a14")   # quasi Cartoon.INK, assombri encore : lu comme un creux, jamais comme un volet de plus

## Volets ouverts (R4 "vraie fenêtre" — module `hotel_window_shutters.glb`,
## réutilisé sur les 5 bâtiments, voir skins_2f.yaml) posés au centre exact de
## l'ouverture (+ `_WINDOW_STANDOFF_M` vers l'extérieur, voir ci-dessus),
## orientés vers l'extérieur (perpendiculaires au mur "N"/"S" ->
## `rotation.y = 0`, "O"/"E" -> `rotation.y = PI*0.5`, mêmes conventions que
## `door_rects_face_local`) — plus un fond d'ombre juste derrière, voir
## `_place_window_backing`.
static func _place_window_shutters(parent: Node3D, o: Dictionary) -> void:
	var info := _opening_world(o)
	if info.is_empty():
		return
	var node := _instance(SKINS_DIR + "hotel_window_shutters.glb")
	if node == null:
		return
	var side := String(o.get("side", "N"))
	var outward := Vector3.ZERO
	match side:
		"S":
			outward = Vector3(0.0, 0.0, 1.0)
		"N":
			outward = Vector3(0.0, 0.0, -1.0)
		"E":
			outward = Vector3(1.0, 0.0, 0.0)
		"W", "O":
			outward = Vector3(-1.0, 0.0, 0.0)
	node.position = (info["center"] as Vector3) + outward * _WINDOW_STANDOFF_M
	node.rotation.y = 0.0 if side in ["N", "S"] else PI * 0.5
	parent.add_child(node)
	_paint_tree(node)
	_place_window_backing(parent, info, side, outward)

## Fond d'ombre plat, en léger retrait derrière le cadre (voir le commentaire
## de `_WINDOW_BACKING_DEPTH_M` ci-dessus pour la cause qu'il corrige) — une
## simple boîte plate générée ici (jamais un nouvel asset : ce module reste
## autosuffisant), peinte via `Cartoon.prop` (même socle encre que le reste du
## décor peint, R2 "toujours le même vocabulaire de matériaux peints"). `info`
## déjà calculé par l'appelant (`_opening_world`), jamais recalculé deux fois.
static func _place_window_backing(parent: Node3D, info: Dictionary, side: String, outward: Vector3) -> void:
	var w: float = maxf((info["w"] as float) - _WINDOW_BACKING_MARGIN_M, 0.1)
	var h: float = maxf((info["h"] as float) - _WINDOW_BACKING_MARGIN_M, 0.1)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, h, 0.02) if side in ["N", "S"] else Vector3(0.02, h, w)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, Cartoon.prop(_WINDOW_BACKING_COLOR))
	mi.position = (info["center"] as Vector3) - outward * _WINDOW_BACKING_DEPTH_M
	parent.add_child(mi)

## Cadre de porte SEUL (R6 "ajoute des modules kit v2 cuits... cadres") posé
## au centre exact de l'ouverture — utilisé UNIQUEMENT là où aucune carte de
## façade ne recouvre déjà l'ouverture (donc pas de tableau peint slot 1
## existant, voir §2 SaloonW/E dans l'en-tête de fichier : les portes de
## balcon floor=1, côté O/E, n'ont pas de carte dessous).
static func _place_door_frame(parent: Node3D, o: Dictionary, asset_path: String) -> void:
	var info := _opening_world(o)
	if info.is_empty():
		return
	var node := _instance(asset_path)
	if node == null:
		return
	var w: Array = o["world"]
	var y0: float = w[4]
	var center: Vector3 = info["center"]
	node.position = Vector3(center.x, y0, center.z)
	var side := String(o.get("side", "N"))
	node.rotation.y = 0.0 if side in ["N", "S"] else PI * 0.5
	parent.add_child(node)
	_paint_tree(node)


# ======================================================================
#  Hôtel / Banque (§2 : « S : face avant de wl_saloon... O et E : flancs du
#  saloon recadrés sur les 6 premiers m, portes d'étage percées »).
# ======================================================================

static func _skin_hotel_banque(parent: Node3D, by_name: Dictionary, boxes: Dictionary) -> void:
	for bname in ["Hotel", "Banque"]:
		_for_each(by_name, bname, func(p: Dictionary) -> void:
			var pos: Vector3 = p["pos"]
			var size: Vector3 = p["size"]
			_place_facade(parent, pos, size, SKINS_DIR + "hotel_facade_s.glb")
			_place_facade(parent, pos, size, SKINS_DIR + "hotel_facade_flank.glb", false)   # flanc Ouest
			_place_facade(parent, pos, size, SKINS_DIR + "hotel_facade_flank.glb", true)    # flanc Est (miroir)
		)
		if not boxes.has(bname):
			continue
		var b: Dictionary = boxes[bname]
		for o in (b.get("openings", []) as Array):
			var od: Dictionary = o
			if String(od.get("kind", "")) == "window":
				_place_window_shutters(parent, od)


# ======================================================================
#  SaloonW / SaloonE (§2 : « wl_saloon_long, 4 faces sans étirement »).
# ======================================================================

static func _skin_saloon(parent: Node3D, by_name: Dictionary, boxes: Dictionary) -> void:
	_skin_saloon_one(parent, by_name, boxes, "SaloonW", false)
	_skin_saloon_one(parent, by_name, boxes, "SaloonE", true)

## `mirror` : SaloonE est le miroir X de SaloonW (`wasteland.gd::_mirror_piece`
## négate `pos.x`, jamais une rotation — voir l'en-tête de fichier). Les
## cartes O/E fabriquées à partir de SaloonW (`saloon_facade_w`/`_e`, chacune
## perçant l'ouverture réelle de CE côté-là) sont donc échangées ET retournées
## (`mirror_x=true`) pour SaloonE : son flanc Ouest reprend `saloon_facade_e`
## (le décalage de porte +4,5 y est identique, vérifié sur le JSON), son flanc
## Est reprend `saloon_facade_w` (décalage -3,0 identique).
static func _skin_saloon_one(parent: Node3D, by_name: Dictionary, boxes: Dictionary, name: String, mirror: bool) -> void:
	_for_each(by_name, name, func(p: Dictionary) -> void:
		var pos: Vector3 = p["pos"]
		var size: Vector3 = p["size"]
		_place_facade(parent, pos, size, SKINS_DIR + "saloon_facade_n.glb")
		_place_facade(parent, pos, size, SKINS_DIR + "saloon_facade_s.glb")
		if mirror:
			_place_facade(parent, pos, size, SKINS_DIR + "saloon_facade_e.glb", true)   # flanc Ouest (retourné)
			_place_facade(parent, pos, size, SKINS_DIR + "saloon_facade_w.glb", true)   # flanc Est (retourné)
		else:
			_place_facade(parent, pos, size, SKINS_DIR + "saloon_facade_w.glb")
			_place_facade(parent, pos, size, SKINS_DIR + "saloon_facade_e.glb")
	)
	if not boxes.has(name):
		return
	var b: Dictionary = boxes[name]
	for o in (b.get("openings", []) as Array):
		var od: Dictionary = o
		var side := String(od.get("side", "N"))
		var floor_idx := int(od.get("floor", 0))
		var kind := String(od.get("kind", ""))
		if kind == "window":
			# N/S : matière pleine a tous les etages (sonde, voir l'en-tete de
			# fichier) -> volets partout. O/E : matiere seulement au rez (le
			# plan n'y met de toute façon que des portes de balcon a l'etage,
			# jamais de fenetre — aucun cas O/E ici en pratique).
			_place_window_shutters(parent, od)
		elif kind == "door" and side in ["W", "E"] and floor_idx == 1:
			# Porte de balcon a l'etage, cote flanc : aucune carte dessous
			# (voir l'en-tete de fichier) -> cadre seul, deja "ouvert".
			_place_door_frame(parent, od, SKINS_DIR + "saloon_door_frame.glb")


# ======================================================================
#  Wagon (§2 : « wl_wagon en mode shell évidé »).
# ======================================================================

static func _skin_wagon(parent: Node3D, by_name: Dictionary, boxes: Dictionary) -> void:
	_for_each(by_name, "Wagon", func(p: Dictionary) -> void:
		var pos: Vector3 = p["pos"]
		var size: Vector3 = p["size"]
		var node := _instance(SKINS_DIR + "wagon_shell.glb")
		if node == null:
			return
		node.position = Vector3(pos.x, pos.y - size.y * 0.5, pos.z)
		parent.add_child(node)
		_paint_tree(node)
	)
	if not boxes.has("Wagon"):
		return
	var b: Dictionary = boxes["Wagon"]
	for o in (b.get("openings", []) as Array):
		var od: Dictionary = o
		if String(od.get("kind", "")) == "window":
			_place_window_shutters(parent, od)


# ======================================================================
#  Escaliers extérieurs (§2 : « Module stairs_fit(largeur, montée, course) aux
#  cotes exactes »). `stairs_fit.glb` existant (ART-92, 1,5/3,2/5,0 m) sert
#  Impasse/Passage TEL QUEL (mêmes cotes, vérifié sur wasteland.gd — aucun
#  nouveau bake) ; `saloon_stairs_6m.glb` (cette tâche, 1,5/3,2/6,0 m) sert
#  Ruelle/Galerie.
# ======================================================================

static func _skin_stairs(parent: Node3D, by_name: Dictionary) -> void:
	for n in ["StairImpasseW", "StairImpasseE", "StairPassageW", "StairPassageE"]:
		_place_stairs(parent, by_name, n, SHANTY_DIR + "stairs_fit.glb")
	for n in ["StairRuelleW", "StairRuelleE", "StairGalerieW", "StairGalerieE"]:
		_place_stairs(parent, by_name, n, SKINS_DIR + "saloon_stairs_6m.glb")

## `stairs_fit` (make_wl_shanty_kit.py) est un module d'auteur Y-haut Z-avant :
## origine au bas de l'escalier (0,0,0), monte en +Y en même temps qu'il
## avance vers -Z (`P_STRUT(..., (x,0,0), (x, rise, -run), ...)`). `start`/
## `end` de la pièce `stairs` (wasteland.gd::_stairs_piece) ne varient qu'en Y
## et sur UN SEUL axe horizontal (jamais de dévers latéral, sondé sur les 8
## pièces de wasteland.gd) : `fwd` = direction horizontale start->end (== la
## direction de montée, donc l'axe local -Z une fois posé), `side` = l'axe
## local X (largeur, perpendiculaire), `Vector3.UP` = l'axe local Y (montée).
static func _place_stairs(parent: Node3D, by_name: Dictionary, name: String, asset_path: String) -> void:
	_for_each(by_name, name, func(p: Dictionary) -> void:
		var start: Vector3 = p["start"]
		var end: Vector3 = p["end"]
		var horiz := Vector3(end.x - start.x, 0.0, end.z - start.z)
		var run := horiz.length()
		if run < 0.05:
			return
		var fwd := horiz / run
		var side := fwd.cross(Vector3.UP).normalized()
		if side.length() < 0.5:
			side = Vector3.RIGHT
		var node := _instance(asset_path)
		if node == null:
			return
		node.transform = Transform3D(Basis(side, Vector3.UP, -fwd), start)
		parent.add_child(node)
		_paint_tree(node)
	)


# ======================================================================
#  Galerie du Saloon (§2 : « porche + balcony_railing sur BalconW et
#  RampeBalconW »). Le platelage BalconW/E (pièce "box", role "slab") reste
#  la dalle Kit déjà peinte par wasteland_look.gd (hors de mon périmètre) ;
#  seul le garde-corps est ajouté ici, sur la pièce "fence" dédiée.
# ======================================================================

static func _skin_gallery(parent: Node3D, by_name: Dictionary) -> void:
	for n in ["RampeBalconW", "RampeBalconE"]:
		_for_each(by_name, n, func(p: Dictionary) -> void:
			_place_fence_run(parent, p["start"], p["end"], SHANTY_DIR + "balcony_railing.glb", 2.0)
		)

## Copie locale de la technique de tuilage d'ArtCovers._place_fence_run (même
## règle d'indépendance qu'ArtCovers.gd : reste autosuffisant, aucune fonction
## privée d'un autre chantier). `balcony_railing.glb` (ART-92) : longueur
## d'auteur 2,0 m le long de son axe X.
static func _place_fence_run(parent: Node3D, start: Vector3, end: Vector3, asset_path: String, asset_len: float) -> void:
	var d := end - start
	var length := d.length()
	if length < 0.05:
		return
	var fwd := d.normalized()
	var side := Vector3.UP.cross(fwd).normalized()
	var n: int = maxi(1, roundi(length / asset_len))
	var seg_len := length / float(n)
	for i in range(n):
		var t := (float(i) + 0.5) / float(n)
		var node := _instance(asset_path)
		if node == null:
			continue
		node.transform = Transform3D(Basis(fwd, Vector3.UP, side), start.lerp(end, t))
		node.scale = Vector3(seg_len / asset_len, 1.0, 1.0)
		parent.add_child(node)
		_paint_tree(node)
