## ArtBuildings1F.gd
## ART-94 — module de la couche d'art v4 de Wasteland (contrat WastelandArt.gd,
## docs/art/WASTELAND_V4_ART_PLAN.md §1 R9 "mise en œuvre" / §2 "traitement
## par volume") : bâtiments jouables à UN NIVEAU — Forge/Maréchal, Magasin/
## Épicerie, Échoppes/Bazar (ForgeW/E, MagasinW/E, EchoppesW/E dans
## `wasteland.gd`, hors de mon périmètre de fichiers, LU seulement).
##
## Contrat de fichiers (ART-94) : ce script + `tools/art/skins_1f.yaml`
## (journal des bakes et des écarts au contrat, voir ce fichier) + les .glb
## neufs sous `assets/models/props/wasteland/skins/{forge,magasin,echoppes}_*`
## (un seul à cette tâche : `forge_facade_s.glb`, voir §"Portée" ci-dessous —
## les modules kit v2 déjà livrés par ART-92 sous `.../wasteland/shanty/` sont
## RÉUTILISÉS tels quels, jamais recopiés ni modifiés ici, même principe
## d'indépendance qu'ArtCovers.gd : "ce module ne dépend d'aucune fonction
## privée d'un autre chantier" — les petites primitives ci-dessous
## (`_index_by_name`/`_for_each`/`_instance`/`_paint_tree`) sont donc
## dupliquées plutôt qu'importées).
##
## Peau, jamais collision (§1 R9) : chaque bâtiment garde la boîte
## `building2` que `Kit.build_piece` a DÉJÀ posée pour `wasteland.gd` (aucune
## pièce de ce module n'a `"visual":false` — cette bascule touche
## `wasteland.gd`, hors de mon périmètre — donc le Kit brut reste dessous,
## TOUJOURS OPAQUE ; la peau doit dépasser cette boîte de quelques cm sur
## chaque face visible pour "gagner" le test de profondeur, cf. le
## correctif documenté dans ArtCovers.gd).
##
## TROIS bugs de pose trouvés et corrigés EN COURS DE TÂCHE (posé une première
## fois pile à la cote nominale de la boîte + une rotation par analogie avec
## ArtCovers.gd — capture en jeu : mur plat beige, aucune peau visible sur
## AUCUNE des 3 faces testées, alors que la MÊME peau rendait impeccablement
## en isolation, hors contexte de bâtiment — voir le rapport de tâche pour la
## démarche de diagnostic complète, raycasts + rendu isolé à l'appui) :
##   1. **Profondeur.** `Kit._bld_wall_side` (Kit.gd, lu seulement) centre
##      CHAQUE mur sur le plan `center ± size*0.5` (la limite "nominale" de
##      la boîte) et l'étend de `±Kit._BLD_WALL_T/2` (0,125 m) — la face
##      RÉELLEMENT peinte/collisionnée du Kit dépasse donc la boîte nominale
##      de 0,125 m vers l'extérieur (confirmé par raycast : la collision de
##      ForgeW touche à z=-14,875, pas z=-15,0, la cote nominale). Une peau
##      posée pile à la cote nominale (comme les modules `_place_ground`
##      d'ArtCovers.gd, qui eux collent des BOÎTES sans cette marge de
##      construction) reste donc 12,5 cm À L'INTÉRIEUR de la face réellement
##      opaque du Kit, TOUJOURS devant elle — invisible, quel que soit son
##      matériau. `_KIT_WALL_OUTER_M` (le plan réel) et `_origin_offset_for`
##      (la demi-épaisseur PROPRE de chaque module, jamais un décalage
##      unique) corrigent ce calcul sur les 3 fonctions de pose ci-dessous.
##   2. **Rotation ouest/est.** Vérifiée EMPIRIQUEMENT (`Basis(Vector3.UP,
##      angle) * Vector3(0,0,-1)`, jamais supposée par analogie) : rot=0 ->
##      local(-Z) = monde -Z (nord), rot=PI -> +Z (sud), rot=+PI/2 -> -X
##      (ouest), rot=-PI/2 -> +X (est) — l'INVERSE de la convention ouest/est
##      utilisée par ArtCovers.gd::_skin_citerne pour `bund_wall.glb`
##      (`rot=-PI*0.5` à l'ouest). Un muret symétrique (aucune face avant/
##      arrière visible) ne révèle jamais cette inversion ; un mur de
##      planches asymétrique (jambages/vis, comme `wall_1_level`/
##      `door_frame`) ou une carte Tripo À DOS SUPPRIMÉ (voir plus bas), si.
##      `_KIT_ROT_Y` ci-dessous porte la valeur VÉRIFIÉE, pas la valeur par
##      analogie.
##   3. **Vides RÉELS du bardage kit v2, jamais un défaut de peinture.**
##      Retour QA sur V1/V2/V7 (une bande de bardage sur deux "totalement
##      BEIGE PLATE, aucun grain de bois, aucun encrage, dégradé lisse
##      typique du matériau par défaut de Godot", + un panneau plein
##      au-dessus du linteau de chaque porte) : diagnostic initial (QA)
##      "`_paint_tree` ne repeint pas certaines surfaces". FAUX, vérifié sur
##      le .glb lui-même (export JSON du glTF, hors moteur : un seul
##      primitive, un seul matériau `wood_planks`, jamais de second slot ni
##      de suffixe `_001`) : `_paint_tree` peint bien TOUJOURS l'intégralité
##      de `wall_1_level.glb`. Le vrai constat (positions de sommets
##      extraites du .glb, axe Y) : `plank_wall_parts` (make_wl_shanty_kit.py,
##      PLANK_H_M=0,21 m/PLANK_GAP_M=0,015 m PAR RANGÉE, lu seulement) NE
##      COUVRE, sur le maillage réellement livré, qu'environ 0,045 m de
##      planche sur un pas de rangée de 0,225 m — ~80 % de VIDE RÉEL
##      (aucune face, aucun triangle) par conception (bardage en relief à
##      poser SUR un fond déjà plein), jamais un artefact de matériau. Sans
##      fond peint, ces vides ET la zone entre le linteau (`door_frame.glb`,
##      qui ne monte qu'à sa hauteur `h`) et le sommet du mur (jamais couvert
##      par `_tile_wall_segment`, qui ne pose de bardage QUE dans les
##      tronçons hors gabarit de porte) laissent voir directement la boîte
##      `building2` du Kit, jamais peinte par construction (voir plus haut :
##      "TOUJOURS OPAQUE"). `_place_wall_backing_quad` (fond peint procédural,
##      `SurfaceTool`, aucun nouvel asset) comble les deux — jamais
##      `wall_1_level.glb`/`door_frame.glb` eux-mêmes retouchés, hors de mon
##      périmètre (ART-92).
##
## Deux familles de peau, chacune sa propre fonction de pose :
##   - **Modules kit v2 peints** (`wall_1_level`/`door_frame`, SHANTY_DIR) :
##     origine à la base (Y=0), CENTRÉE en largeur, plan de façade en Z=0,
##     face peinte visible orientée en LOCAL -Z quand rot_y=0 (mesuré à
##     l'export : la poignée/le vantail de `door.glb` sont posés à
##     `z_out - jt` avec `z_out = -WALL_D_M*0.5`, donc côté -Z). D'où
##     `_KIT_ROT_Y` : 0 au nord, PI au sud, +PI/2 à l'ouest, -PI/2 à l'est
##     (point 2 ci-dessus). Un module BOÎTE (planches empilées, 2 faces par
##     planche) reste visible même mal tourné — seule sa profondeur (point 1)
##     empêchait le rendu avant correctif.
##   - **Carte Tripo découpée** (`forge_facade_s.glb`, `shell_to_skin.py`
##     ART-92, mode "card" : "tranche une face... et supprime le dos" — UN
##     SEUL côté visible, la rotation compte donc EXACTEMENT comme pour un
##     module kit v2, contrairement à ce qu'un premier essai par analogie
##     avec `poste_shell`/`diligence_shell` (ArtCovers.gd, `rotation.y =
##     piece.rot_y`, jamais de PI ajouté) supposait) : rendu invisible tant
##     que la normale de la tranche pointait vers l'intérieur du bâtiment
##     plutôt que vers la rue — corrigé par un +PI explicite dans
##     `_hero_facade_s` (jamais retouché dans `poste_shell.glb`/
##     `diligence_shell.glb` eux-mêmes, hors de mon périmètre : soit leur
##     propre coque Tripo source a, par hasard ou par construction, la
##     normale opposée à `wl_garage`, soit ArtCovers.gd porte la même
##     inversion sans jamais l'avoir vérifiée en jeu d'aussi près — à
##     signaler au lead, hors de mon périmètre de fichiers).
##
## Portée retenue pour cette tâche (à documenter au lead, cf. rendu) : les
## trois volumes du plan (§2, tableau "Bâtiments jouables") demandent chacun
## une composition multi-travées de coques Tripo réutilisées (`wl_garage`/
## `wl_shack`/`wl_fuel_store`) sur CHAQUE face. Mesuré à l'exécution (rapports
## `SHELL_TO_SKIN_OK`, voir tools/art/skins_1f.yaml) : au-delà de la façade
## principale du Forge (7 m, proche de la largeur naturelle de `wl_garage`,
## 18,5 % d'étirement U ASSUMÉ), toute autre face de ces trois bâtiments
## (profondeur 10/14 m du Forge/des Échoppes, largeur 9/14 m du Magasin/des
## Échoppes) dépasse TRÈS largement le contrat carte (12 %, jusqu'à 48 % mesuré
## sur `wl_fuel_store` avant abandon, cf. rapport de tâche) OU échoue la
## vérification d'ouverture à ±2 cm (second vantail du Magasin, cf. rapport) :
## aucune combinaison de recadrage/travée ne referme cet écart avec les 3
## coques disponibles sans un nouvel asset Tripo (hors budget de cette tâche,
## §7 du plan déjà consommé par ART-93). Ces faces utilisent donc le mur
## peint modulaire kit v2 (`wall_1_level` tuilé + `door_frame` mis à l'échelle
## à la cote RÉELLE de chaque porte, jamais un mur uniformément étiré à plus
## de 12 %) : peau peinte complète (aucune boîte beige), portes réelles
## toutes ouvertes (R3/R4), rien d'assumé au-delà de la mise à l'échelle
## proportionnelle d'un module procédural (jamais une texture photo étirée).
## Aucune fausse porte : chaque module `wall_1_level` est SOLIDE (aucune
## porte peinte dessus) et chaque porte réelle reçoit un vrai passage +
## `door_frame`, jamais l'inverse.
class_name ArtBuildings1F
extends RefCounted

const SKINS_DIR := "res://assets/models/props/wasteland/skins/"
const SHANTY_DIR := "res://assets/models/props/wasteland/shanty/"

## Cotes du module `wall_1_level`/`door`/`door_frame`
## (tools/blender/make_wl_shanty_kit.py::WALL_W_M/WALL_H_M — lu, jamais
## modifié) : 2,0 m de large, 2,7 m de haut. `door_frame` (mode `card_frame`,
## `parts_door_frame()`) est cuit à 1,6 x 2,2 m d'ouverture VIDE — mis à
## l'échelle par-axe ci-dessous à la cote RÉELLE de chaque porte (2,0 à
## 2,4 m de large selon le bâtiment, 2,4 m de haut partout, cf.
## tools/art/data/wasteland_v4_boxes.json et tools/art/skins_1f.yaml) :
## un cadre peint procédural (planches plates) se redimensionne par-axe
## sans le risque d'étirement d'une texture photo (§1 R2) — jamais appliqué
## à une carte Tripo.
const WALL_MODULE_W_M := 2.0
const WALL_MODULE_H_M := 2.7
const DOOR_FRAME_NATURAL_W_M := 1.6
const DOOR_FRAME_NATURAL_H_M := 2.2

## Demi-épaisseur du mur RÉEL du Kit (`Kit._BLD_WALL_T` = 0,25 m, lu
## seulement, même constante que `DEFAULT_WALL_THICKNESS_M` de
## shell_to_skin.py) : `Kit._bld_wall_side` centre CHAQUE mur sur le plan
## `center ± size*0.5` (la limite "nominale" de la boîte `building2`) et
## l'étend de ±0,125 m — le plan de collision RÉEL dépasse donc la boîte
## nominale de 0,125 m vers l'extérieur (vérifié par raycast direct, voir le
## rapport de tâche : un rayon depuis l'extérieur touche la collision de
## ForgeW à z=-14,875, PAS z=-15,0, la cote nominale). `_KIT_WALL_OUTER_M`
## EST ce plan réel (nominal + 0,125) : la référence commune que chaque
## fonction de pose ci-dessous vise, JAMAIS retouchée en fonction du module
## posé (contrairement à un premier essai qui ajoutait cette marge PUIS
## laissait chaque module s'étendre encore de sa propre demi-épaisseur
## au-delà — la sonde de vérification manuelle de cette tâche passait alors
## de 0 % à 41 % d'écart, `wall_1_level`/`door_frame` ressortant de 9 à
## 12,5 cm AU-DELÀ du plan réel plutôt que d'un simple standoff anti-
## z-fighting, cf. rapport de tâche).
const _KIT_WALL_OUTER_M := 0.125

## Petit dégagement anti-z-fighting AU-DELÀ du plan de collision réel
## (`_KIT_WALL_OUTER_M`) — même ordre de grandeur que `CARD_STANDOFF_M`
## (shell_to_skin.py, 3 cm) et `NUDGE_SCALE` (ArtCovers.gd, 2 %), jamais
## retenu comme le seul calcul de marge (voir la constante ci-dessus).
const _STANDOFF_M := 0.006

## Épaisseur propre de `wall_1_level.glb`/`door.glb` (`WALL_D_M` de
## make_wl_shanty_kit.py, lu seulement) et de `door_frame.glb` (son propre
## `wall_thickness`, cuit à `DEFAULT_WALL_THICKNESS_M` de shell_to_skin.py,
## 0,25 m — PAS `WALL_D_M`, ces deux modules n'ont pas la même profondeur).
## Chaque fonction de pose recule son origine de sa PROPRE demi-épaisseur en
## deçà de `_KIT_WALL_OUTER_M`, pour que ce soit la face EXTÉRIEURE du
## module — jamais son origine — qui dépasse le plan réel de `_STANDOFF_M`.
const _WALL_MODULE_D_M := 0.18
const _DOOR_FRAME_D_M := 0.25

## Décalage (le long de la normale sortante) à appliquer à l'ORIGINE d'un
## module de demi-épaisseur `half_thickness_m` pour que sa face extérieure
## affleure `_KIT_WALL_OUTER_M` + `_STANDOFF_M` — jamais directement
## `_KIT_WALL_OUTER_M` (voir les deux constantes ci-dessus et leur
## commentaire).
static func _origin_offset_for(half_thickness_m: float) -> float:
	return _KIT_WALL_OUTER_M + _STANDOFF_M - half_thickness_m

## Profondeur du fond peint anti-vide `_place_wall_backing_quad` (bug de pose
## n°3, voir l'en-tête) : STRICTEMENT en-deçà du plan extérieur commun des
## modules kit v2 (`_KIT_WALL_OUTER_M + _STANDOFF_M`, cf. `_origin_offset_for`
## ci-dessus, qui y affleure la face extérieure de CHAQUE module quelle que
## soit sa propre épaisseur) — ce fond ne doit jamais rivaliser en profondeur
## avec le relief du bardage, qui doit rester seul visible en avant-plan —
## mais STRICTEMENT au-delà du plan de collision réel du Kit
## (`_KIT_WALL_OUTER_M` seul) pour ne jamais z-fighter avec sa boîte
## `building2`. La moitié de `_STANDOFF_M` place ce fond exactement au milieu
## des deux, avec la même marge (3 mm) de chaque côté.
const _BACKING_OFFSET_M := _KIT_WALL_OUTER_M + _STANDOFF_M * 0.5

## Hauteur de porte Kit constatée (tools/art/data/wasteland_v4_boxes.json,
## champ "h" de CHAQUE porte des 3 bâtiments de cette tâche) : absente de
## `data["pieces"]` au runtime (`WastelandLayout._door()` ne renvoie que
## `side/offset/w/floor`, jamais `h` — cf. wasteland.gd, lu seulement) ; ce
## module lit quand même `door.get("h", ...)` par prudence (schéma additif
## futur) et retombe sur cette constante, jamais inventée : c'est la valeur
## RÉELLE exportée par ART-91 depuis la même collision construite pour les
## 11 building2, jamais une hypothèse.
const DOOR_DEFAULT_H_M := 2.4

## Les 5 "kinds" peints du contrat ART-73/92 (voir ArtCovers.gd, même liste
## répétée en dur ici plutôt qu'importée — indépendance des modules).
const _PAINTED_KINDS := ["wood_planks", "corrugated_metal", "rust", "painted_metal", "dirty_glass"]

## Rotation d'un module kit v2 (front en LOCAL -Z quand rot_y=0, voir
## l'en-tête) pour habiller la face dont la normale sortante est donnée en
## clé : N -> -Z, S -> +Z, W -> -X, E -> +X.
## Vérifié empiriquement (`Basis(Vector3.UP, angle) * Vector3(0,0,-1)`, voir
## le rapport de tâche) plutôt que supposé par analogie avec un autre module :
## rot=0 -> local(-Z) = monde -Z (nord) ; rot=PI -> monde +Z (sud) ;
## rot=+PI/2 -> monde -X (ouest) ; rot=-PI/2 -> monde +X (est). Ouest et est
## sont donc l'INVERSE de la convention utilisée par ArtCovers.gd::_skin_
## citerne pour `bund_wall.glb` (`rot=-PI*0.5` à l'ouest) — un mur muret
## symétrique (aucune face avant/arrière visible) ne révèle jamais cette
## inversion, contrairement à un mur de planches asymétrique (jambages/vis)
## comme `wall_1_level`/`door_frame` : la sonde de vérification manuelle de
## cette tâche (raycast + inspection visuelle en jeu) l'a détectée ici,
## corrigée avant rendu.
const _KIT_ROT_Y := {"N": 0.0, "S": PI, "W": PI * 0.5, "E": -PI * 0.5}

# ======================================================================
#  Point d'entrée (contrat WastelandArt.gd : `apply(parent, data) -> void`,
#  fonction STATIQUE, purement visuelle).
# ======================================================================

static func apply(parent: Node3D, data: Dictionary) -> void:
	var by_name := _index_by_name(data.get("pieces", []) as Array)

	# -- Façade principale (carte Tripo, R2 "card") : Forge/Maréchal sud,
	#    seule face de cette tâche dont la largeur cible (7 m) reste assez
	#    proche de la largeur naturelle de wl_garage pour un étirement
	#    documenté raisonnable (voir l'en-tête "Portée retenue") --------
	_hero_facade_s(parent, by_name, "ForgeW", false)
	_hero_facade_s(parent, by_name, "ForgeE", true)

	# -- Toutes les autres faces (kit v2 modulaire, R6 "modules kit v2
	#    cuits", jamais étiré au-delà d'une proportion procédurale) ------
	_skin_building_kit(parent, by_name, "ForgeW", ["W", "E"])
	_skin_building_kit(parent, by_name, "ForgeE", ["W", "E"])
	_skin_building_kit(parent, by_name, "MagasinW", ["S", "W"])
	_skin_building_kit(parent, by_name, "MagasinE", ["S", "E"])
	_skin_building_kit(parent, by_name, "EchoppesW", ["N", "W", "E", "S"])
	_skin_building_kit(parent, by_name, "EchoppesE", ["N", "W", "E", "S"])


# ======================================================================
#  Index et primitives d'instanciation/peinture — copies indépendantes de
#  celles d'ArtCovers.gd (même principe, voir l'en-tête).
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

## Repeint chaque surface par le nom de matériau glTF d'origine — même
## logique qu'ArtCovers.gd::_paint_tree (voir ses commentaires). Un module
## kit v2 (`wall_1_level`/`door_frame`) est TOUJOURS peint (tous ses slots
## portent un des 5 kinds) ; la carte Tripo (`forge_facade_s`) garde son
## albédo intact au slot 0 (R2 d'ART-92) et ne peint que le cadre
## d'ouverture (slot "wood_planks" posé par `shell_to_skin.py`).
## Si une bande de bardage `wall_1_level` ressort malgré tout beige plate en
## jeu, CE N'EST PAS un défaut de cette fonction (vérifié sur le .glb source,
## voir l'en-tête, bug n°3) : c'est un vide RÉEL du maillage (bardage en
## relief, ~80 % d'air par rangée) qui laisse voir la boîte `building2` du
## Kit, jamais peinte, à travers — cf. `_place_wall_backing_quad`.
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


# ======================================================================
#  Façade principale (carte Tripo `forge_facade_s.glb`) — Forge/Maréchal S.
# ======================================================================

## `mirror` (Maréchal, moitié est, R8 "réemploi... au moins deux paramètres
## parmi... miroir") : `scale.x = -1`, même technique déjà posée par
## ArtCovers.gd::_place_fence_run (`mirror_alt`) sur `covers_cloture.glb` —
## une échelle négative sur un seul axe inverse le sens des faces, DÉJÀ
## accepté dans ce dépôt pour un module peint (le shader toon de ce projet
## reste lisible des deux côtés, cf. le même usage sur ClotureW/E). La porte
## du Forge est centrée (offset 0,0) : le miroir ne déplace pas son
## ouverture, seule la silhouette peinte (relief écrasé, callouts) varie
## légèrement d'un côté à l'autre — suffisant pour R8 vu que l'enseigne et
## la teinte (FORGE/chaud contre MARÉCHAL/froid) sont posées par un autre
## module (ArtLandmarks.gd/ArtDressing.gd, ART-99, hors de mon périmètre).
static func _hero_facade_s(parent: Node3D, by_name: Dictionary, name: String, mirror: bool) -> void:
	_for_each(by_name, name, func(p: Dictionary) -> void:
		var pos: Vector3 = p["pos"]
		var size: Vector3 = p["size"]
		var node := _instance(SKINS_DIR + "forge_facade_s.glb")
		if node == null:
			return
		# Origine de la carte : centrée en largeur, au sol (Y=0), au plan de
		# façade (Z=0, standoff de 3 cm déjà appliqué par shell_to_skin.py) —
		# même convention que poste_shell/diligence_shell (ArtCovers.gd) :
		# aucune marge supplémentaire à poser ici.
		# `forge_facade_s.glb` porte déjà son propre standoff (3 cm, appliqué
		# par shell_to_skin.py au bake, dans le plan de coupe de la coque
		# source — voir sa provenance) : l'origine posée ici vise directement
		# le plan de collision réel (`_KIT_WALL_OUTER_M`), jamais réduite
		# d'une demi-épaisseur comme les modules kit v2 ci-dessous (cette
		# carte n'a pas d'épaisseur propre significative après recadrage).
		node.position = Vector3(pos.x, pos.y - size.y * 0.5, pos.z + size.z * 0.5 + _KIT_WALL_OUTER_M)
		node.rotation.y = float(p.get("rot_y", 0.0)) + PI  # voir l'en-tête (vérifié en jeu, pas seulement par analogie)
		if mirror:
			node.scale = Vector3(-1.0, 1.0, 1.0)
		parent.add_child(node)
		_paint_tree(node)
	)


# ======================================================================
#  Murs modulaires kit v2 (`wall_1_level` tuilé + `door_frame` à l'échelle
#  réelle de chaque porte) — toutes les autres faces des 3 bâtiments.
# ======================================================================

## Habille les faces de `sides` (sous-ensemble de "N"/"S"/"W"/"E") du
## bâtiment `name`, en lisant ses VRAIES portes (`p["doors"]`, posées par
## `WastelandLayout._door()`/`_mirror_piece` — jamais recopiées à la main,
## R3) pour savoir où laisser un passage plutôt que de couvrir un mur plein.
static func _skin_building_kit(parent: Node3D, by_name: Dictionary, name: String, sides: Array) -> void:
	_for_each(by_name, name, func(p: Dictionary) -> void:
		var pos: Vector3 = p["pos"]
		var size: Vector3 = p["size"]
		var base_y: float = pos.y - size.y * 0.5
		var all_doors: Array = p.get("doors", [])
		for side in sides:
			var side_doors: Array = []
			for entry in all_doors:
				var d: Dictionary = entry
				if String(d.get("side", "")) == side and int(d.get("floor", 0)) == 0:
					side_doors.append(d)
			side_doors.sort_custom(func(a, b): return float(a["offset"]) < float(b["offset"]))
			match side:
				"N":
					_place_wall_run(parent, Vector3(pos.x, base_y, pos.z - size.z * 0.5), Vector3(1, 0, 0), Vector3(0, 0, -1), size.x, size.y, _KIT_ROT_Y["N"], side_doors)
				"S":
					_place_wall_run(parent, Vector3(pos.x, base_y, pos.z + size.z * 0.5), Vector3(1, 0, 0), Vector3(0, 0, 1), size.x, size.y, _KIT_ROT_Y["S"], side_doors)
				"W":
					_place_wall_run(parent, Vector3(pos.x - size.x * 0.5, base_y, pos.z), Vector3(0, 0, 1), Vector3(-1, 0, 0), size.z, size.y, _KIT_ROT_Y["W"], side_doors)
				"E":
					_place_wall_run(parent, Vector3(pos.x + size.x * 0.5, base_y, pos.z), Vector3(0, 0, 1), Vector3(1, 0, 0), size.z, size.y, _KIT_ROT_Y["E"], side_doors)
	)

## Tuile `wall_1_level.glb` le long d'un tracé de longueur `length` (mesuré
## depuis son centre, comme `offset`), en laissant un `door_frame.glb` mis à
## l'échelle réelle à chaque porte de `doors` (déjà triées par offset).
## `nominal_base` = point à l'offset 0, AU SOL, sur le plan NOMINAL de la
## boîte (`pos ± size*0.5`, jamais encore le plan de collision réel — voir
## `_KIT_WALL_OUTER_M`) ; `dir_u` = vecteur MONDE unitaire le long duquel
## `offset` se mesure (+X pour N/S, +Z pour O/E — jamais affecté par `rot_y`,
## qui ne change que l'orientation VISUELLE du module posé, cf. l'en-tête) ;
## `normal_dir` = vecteur MONDE unitaire SORTANT (perpendiculaire à `dir_u`)
## le long duquel chaque module ci-dessous avance sa propre origine de
## `_origin_offset_for(sa demi-épaisseur)` — jamais un décalage unique
## partagé par des modules d'épaisseurs différentes (voir la constante).
## Chaque tronçon plein ET la zone au-dessus de chaque linteau reçoivent
## d'abord un fond peint (`_place_wall_backing_quad`, bug de pose n°3, voir
## l'en-tête) AVANT le bardage/cadre lui-même, pour qu'aucun vide ne laisse
## voir la boîte `building2` nue du Kit.
static func _place_wall_run(parent: Node3D, nominal_base: Vector3, dir_u: Vector3, normal_dir: Vector3, length: float, height_m: float, rot_y: float, doors: Array) -> void:
	var half := length * 0.5
	var cursor := -half
	for entry in doors:
		var d: Dictionary = entry
		var w: float = float(d.get("w", 1.6))
		var o: float = float(d.get("offset", 0.0))
		var h: float = float(d.get("h", DOOR_DEFAULT_H_M))
		var g0 := o - w * 0.5
		var g1 := o + w * 0.5
		if g0 > cursor + 0.02:
			_place_wall_backing_quad(parent, nominal_base, dir_u, normal_dir, cursor, g0, 0.0, height_m)
			_tile_wall_segment(parent, nominal_base, dir_u, normal_dir, cursor, g0, height_m, rot_y)
		if h < height_m - 0.02:
			# Linteau : `door_frame.glb` ne monte qu'à `h`, jamais jusqu'au
			# sommet du mur — sans ce fond, cette bande reste TOUJOURS nue
			# (aucune fonction ci-dessous ne la couvre autrement).
			_place_wall_backing_quad(parent, nominal_base, dir_u, normal_dir, g0, g1, h, height_m)
		_place_door_frame(parent, nominal_base, dir_u, normal_dir, o, w, h, rot_y)
		cursor = maxf(cursor, g1)
	if cursor < half - 0.02:
		_place_wall_backing_quad(parent, nominal_base, dir_u, normal_dir, cursor, half, 0.0, height_m)
		_tile_wall_segment(parent, nominal_base, dir_u, normal_dir, cursor, half, height_m, rot_y)

## Remplit `[u0, u1]` de copies de `wall_1_level.glb`, chacune mise à
## l'échelle EN LARGEUR SEULE pour occuper exactement sa part du segment
## (même technique que ArtCovers.gd::_place_fence_run — jamais un module
## unique étiré sur toute la longueur) et en HAUTEUR pour atteindre la cote
## réelle du bâtiment (`height_m / WALL_MODULE_H_M`, mise à l'échelle
## proportionnelle d'un motif de planches procédural, jamais une texture
## photo — voir l'en-tête "Portée retenue").
static func _tile_wall_segment(parent: Node3D, nominal_base: Vector3, dir_u: Vector3, normal_dir: Vector3, u0: float, u1: float, height_m: float, rot_y: float) -> void:
	var seg_len := u1 - u0
	if seg_len <= 0.05:
		return
	var n: int = maxi(1, roundi(seg_len / WALL_MODULE_W_M))
	var tile_w := seg_len / float(n)
	var h_scale := height_m / WALL_MODULE_H_M
	var normal_off := normal_dir * _origin_offset_for(_WALL_MODULE_D_M * 0.5)
	for i in range(n):
		var u := u0 + tile_w * (float(i) + 0.5)
		var node := _instance(SHANTY_DIR + "wall_1_level.glb")
		if node == null:
			continue
		node.position = nominal_base + dir_u * u + normal_off
		node.rotation.y = rot_y
		node.scale = Vector3(tile_w / WALL_MODULE_W_M, h_scale, 1.0)
		parent.add_child(node)
		_paint_tree(node)

## Pose `door_frame.glb` à l'offset `o` de largeur/hauteur VIDES `w`/`h`,
## mis à l'échelle par-axe depuis ses cotes naturelles (1,6 x 2,2 m, voir
## `parts_door_frame()` dans make_wl_shanty_kit.py, lu seulement) — un cadre
## peint procédural (jambages/linteau/seuil, jamais de texture photo) se
## redimensionne par-axe sans le risque d'étirement du contrat R2 "card".
static func _place_door_frame(parent: Node3D, nominal_base: Vector3, dir_u: Vector3, normal_dir: Vector3, o: float, w: float, h: float, rot_y: float) -> void:
	var node := _instance(SHANTY_DIR + "door_frame.glb")
	if node == null:
		return
	node.position = nominal_base + dir_u * o + normal_dir * _origin_offset_for(_DOOR_FRAME_D_M * 0.5)
	node.rotation.y = rot_y
	node.scale = Vector3(w / DOOR_FRAME_NATURAL_W_M, h / DOOR_FRAME_NATURAL_H_M, 1.0)
	parent.add_child(node)
	_paint_tree(node)


# ======================================================================
#  Fond peint anti-vide (bug de pose n°3, voir l'en-tête) — comble les
#  vides RÉELS du bardage `wall_1_level.glb` (bardage en relief, jamais un
#  mur plein) et la zone au-dessus de chaque linteau de porte, jamais
#  couverts par les fonctions ci-dessus.
# ======================================================================

## Un quad (2 triangles), même primitive que ArtGround.gd::_quad — dupliquée
## en dur ici plutôt qu'importée (voir l'en-tête : indépendance des modules).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)

## Fond peint plein, construit directement en code (`SurfaceTool`, AUCUN
## nouvel asset .glb — `wall_1_level.glb`/`door_frame.glb` restent hors de
## mon périmètre, RÉUTILISÉS tels quels, voir l'en-tête) : un simple
## rectangle vertical de `u0` à `u1` (le long de `dir_u`) et de `y0` à `y1`
## (hauteur MONDE, jamais affecté par `rot_y`), peint par
## `Cartoon.painted(&"wood_planks")` — triplanaire (aucun UV à poser, voir
## ses commentaires), donc aucune géométrie de détail nécessaire pour ce
## fond, contrairement au bardage qu'il comble. Profondeur `_BACKING_OFFSET_M`
## (voir la constante : entre le plan de collision réel du Kit et le plan
## extérieur commun des modules kit v2, jamais confondu avec l'un ou
## l'autre). DEUX faces opposées (normales inversées, comme les grandes
## faces d'un `_add_beam_segment` d'ArtGround.gd) : un joueur À L'INTÉRIEUR
## du bâtiment doit aussi voir ce fond peint, jamais le dos par défaut d'un
## quad simple face.
static func _place_wall_backing_quad(parent: Node3D, nominal_base: Vector3, dir_u: Vector3, normal_dir: Vector3, u0: float, u1: float, y0: float, y1: float) -> void:
	if u1 - u0 <= 0.02 or y1 - y0 <= 0.02:
		return
	var base := nominal_base + normal_dir * _BACKING_OFFSET_M
	var p00 := base + dir_u * u0 + Vector3.UP * y0
	var p10 := base + dir_u * u1 + Vector3.UP * y0
	var p11 := base + dir_u * u1 + Vector3.UP * y1
	var p01 := base + dir_u * u0 + Vector3.UP * y1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, p00, p10, p11, p01)
	_quad(st, p01, p11, p10, p00)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Cartoon.painted(&"wood_planks")
	parent.add_child(mi)
