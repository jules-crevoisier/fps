## ArtCovers.gd
## ART-96 — module de la couche d'art v4 de Wasteland (contrat WastelandArt.gd,
## docs/art/WASTELAND_V4_ART_PLAN.md §1 R9 "mise en œuvre" / §2 "traitement
## par volume") : volumes pleins et couverts du centre et des deux moitiés
## (Poste, Diligence, château d'eau, Pompe, Muret du Goulet, citernes,
## caisses, abreuvoirs, comptoir, tonneaux, traverses, remise, wagon-citerne,
## chariot de mine, charrette, clôture), parapets et barrières Duel/Duo.
##
## Contrat de fichiers (ART-96) : ce script + `assets/models/props/wasteland/
## skins/{poste,diligence,covers}_*` (les .glb neufs de cette tâche — les
## modules kit v2 déjà livrés par ART-92 sous `.../wasteland/shanty/` et les
## coques Tripo d'ART-93 sous `.../wasteland/tripo/` sont RÉUTILISÉS tels
## quels, jamais recopiés ni modifiés ici).
##
## Peau, jamais collision (§1 R9, WastelandArt.gd) : chaque pièce ci-dessous
## garde la boîte de collision que `Kit.build_piece` a DÉJÀ posée pour
## `wasteland.gd`. Deux régimes de rendu coexistent, choisis PIÈCE PAR PIÈCE
## dans `wasteland.gd` (`_box_novisual`, ART-96, additif à `_box`) :
##   - **couverts** (CiterneFUEL, CaisseFUEL, CharretteW, etc., §2 "Couverts
##     et petits volumes" du plan) : pas de `"visual":false`, la boîte peinte
##     plate du Kit reste TOUJOURS OPAQUE dessous. La peau DOIT donc dépasser
##     cette boîte, ne serait-ce que de quelques cm, sur CHAQUE face visible :
##     une peau posée pile à la cote de la boîte (ou plus petite) ne "gagne"
##     jamais le test de profondeur contre la boîte opaque qui l'entoure et
##     reste invisible de l'extérieur, quel que soit son remplissage R7
##     mesuré en isolation (une mesure orthographique du SEUL maillage de la
##     peau ne dit rien de ce qui la recouvre une fois posée sur la boîte
##     réelle). `NUDGE_SCALE` (et les marges par-axe des fonctions dédiées)
##     portent cette marge — technique retenue partout pour cette catégorie
##     (§8 "Z-fighting" du plan : "face extérieure du Kit laissée dessous").
##   - **volumes pleins du centre** (Poste, Diligence, ChateauCuve, Pompe,
##     MuretGouletO/E, les 4 pieds du château) : `wasteland.gd` leur pose
##     `"visual":false` (correctif de revue, 2026-09-25, capture 07 : « on
##     voit la BOITE BEIGE du greybox avec des planches collées dessus »
##     depuis la rue, sur Poste/Diligence — la marge `NUDGE_SCALE` seule ne
##     garantissait pas de gagner le test de profondeur sur CHAQUE point d'une
##     façade non plane, seulement sur la boîte englobante). Le Kit ne rend
##     alors plus RIEN pour ces pièces (collision inchangée, `Kit.gd`
##     l.1016-1029, ART-91) : la peau ci-dessous est la SEULE géométrie
##     visible, plus aucun risque de z-fighting — la marge `NUDGE_SCALE`
##     qu'elles gardent encore n'est plus qu'une sécurité anti-trou (±10 cm
##     R1), jamais un besoin de gagner un test de profondeur qui n'existe
##     plus. Vérifié pièce par pièce (AABB composée de chaque instance ici
##     contre la boîte réelle de `WastelandLayout.data()`, jamais estimé)
##     avant de poser `visual:false`, voir le rapport de tâche.
##
## Bug de fond relevé en vérification (2026-09-25, ART-96) sur `poste_shell`/
## `diligence_shell`/`covers_citerne_tank`/`covers_chateau_cuve`/
## `covers_cuve_w` : `_skin_diligence`/`_skin_chateau_eau`/`_skin_citerne`/
## `_skin_cuve` (fonctions dédiées, jamais passées par `_place_ground`)
## n'appliquaient PAS la marge `NUDGE_SCALE`, contrairement aux pièces posées
## via `_place_ground`/`_place_centered` (qui la reçoivent par défaut) — et
## `poste_shell.glb` était, en plus, cuit à une cote plus petite que sa boîte
## réelle (7,0×8,4 m en largeur/profondeur pour une boîte 8×9 m). Corrigé :
## chaque fonction dédiée applique désormais sa propre marge (uniforme via
## `NUDGE_SCALE` quand la peau est déjà pile aux cotes de sa boîte, ou une
## `Vector3` par axe calculée contre la boîte RÉELLE — jamais contre la
## propre cote naturelle de la peau — quand la peau est plus petite que sa
## boîte) ; `poste_shell` gagne sa propre fonction `_skin_poste` pour porter
## cette marge par-axe. Un second bug, plus grave, a été trouvé et corrigé
## dans `_skin_diligence` en préparant le passage à `visual:false` (ci-
## dessus) : `diligence_crates.glb` (le module `crate_stack_fit` qui comble
## le fond de la boîte, derrière `diligence_shell`) a, comme tous les modules
## `crate_stack_fit` (voir le commentaire de `_place_centered`), son origine
## locale CENTRÉE sur les 3 axes — jamais À LA BASE. Il était pourtant placé
## avec `pos.y - size.y * 0.5` (la convention "base", correcte pour
## `diligence_shell` mais PAS pour ce module) : la moitié du maillage (1,6 m
## sur 3,2 m de haut) se retrouvait donc enterrée sous le sol, et le sommet
## visible ne montait qu'à 1,6 m sur les 3,4 m de la boîte — un vrai trou de
## remplissage (largement sous les 85 % de R7 sur la moitié arrière de la
## Diligence), invisible tant que la boîte Kit opaque restait dessous, mais
## qui SERAIT devenu un trou béant (on voit au travers) une fois `visual:
## false` posé. Corrigé : position Y ramenée au CENTRE de la boîte (`pos.y`,
## comme `_place_centered` le fait pour les autres modules `crate_stack_fit`)
## ; l'échelle X passe de `NUDGE_SCALE` uniforme à `shell_x_scale` (le même
## facteur que `diligence_shell`, calculé contre la largeur RÉELLE de la
## boîte) — la pile de caisses, comme la coque, ne couvrait que 5,6 m des
## 6,0 m de large de la boîte, laissant 14,4 cm de vide de chaque côté sur sa
## tranche de profondeur. Sonde et résultats mesurés (AABB monde contre boîte
## réelle, les 6 faces) dans le rapport de tâche : combiné coque+caisses,
## écart ≤ 6,1 cm en X, ≤ 1,9 cm en Z, ≤ 0,2 cm en Y — toujours un DÉBORD
## (jamais un retrait), donc aucun trou possible, dans la tolérance ±10 cm de
## R1.
##
## R9 "les barrières Duel/Duo se filtrent seules" : `data["pieces"]` a DÉJÀ
## traversé `WastelandLayout._filter_pieces_for_mode` avant d'arriver ici
## (voir `wasteland.gd::data()`) — les pièces `BarriereRue*/BarriereRuelle*/
## BarriereCanyon*` sont ABSENTES de `data["pieces"]` en 4v4 (TDM/Hardpoint,
## aucune entrée `"modes"`) : `_by_name` ne les trouve alors jamais et
## `_skin_barrieres` ne pose rien, sans aucun test de mode ici. C'est le
## critère d'acceptation "barrières absentes en 4v4".
##
## Remplissage R7 (§1 R7, "≥ 85 % par face, mesuré en orthographique") :
## chaque coque/module ci-dessous est soit construit pile aux cotes de sa
## boîte (modules kit v2 paramétrés — remplissage garanti par construction),
## soit une coque Tripo ajustée au contrat d'étirement d'ART-92 (≤ 15 %,
## exception cylindre ≤ 32 %) avec le reste de la profondeur comblé par un
## second volume attenant (Diligence : coque + pile de malles ; Citerne :
## cuve + muret de rétention). Chiffres exacts et dérivation : voir les
## commentaires de chaque fonction `_skin_*` ci-dessous.
class_name ArtCovers
extends RefCounted

const SKINS_DIR := "res://assets/models/props/wasteland/skins/"
const SHANTY_DIR := "res://assets/models/props/wasteland/shanty/"

## Marge de recouvrement (§8 "Z-fighting") appliquée aux peaux "boîte pleine"
## dont la construction atteint pile la cote de la boîte Kit (piles de
## caisses/traverses téléscopées à `_telescoped_cells`, coque Tripo recadrée
## exactement à la hauteur cible) : 2 % dans les 3 axes, toujours à
## l'intérieur de la tolérance ±10 cm de R1 pour ces petits volumes.
const NUDGE_SCALE := 1.02

## Les 5 "kinds" peints du contrat ART-73/92 (make_wl_shanty_kit.py::KINDS,
## Cartoon.gd::_PAINTED) — seul un slot dont le nom (survécu à l'import en
## `Material.resource_name`) tombe dans cette liste est repeint par
## `_paint_tree` ; répété ici en dur plutôt que de lire une constante privée
## (`_PAINTED`) d'un autre script.
const _PAINTED_KINDS := ["wood_planks", "corrugated_metal", "rust", "painted_metal", "dirty_glass"]

# ======================================================================
#  Point d'entrée (contrat WastelandArt.gd : `apply(parent, data) -> void`,
#  fonction STATIQUE, purement visuelle).
# ======================================================================

static func apply(parent: Node3D, data: Dictionary) -> void:
	var by_name := _index_by_name(data.get("pieces", []) as Array)

	# -- Centre : volumes pleins --------------------------------------
	_skin_poste(parent, by_name)
	_skin_diligence(parent, by_name)
	_skin_chateau_eau(parent, by_name)
	# Pas de marge sur Pompe (murs déjà ras des faces de la boîte, toit à
	# débord réduit à 4 cm/côté) : la caméra fixe V5 (tools/art/data/
	# wasteland_v4_views.json) n'a que 0,4 m de dégagement au sud de cette
	# boîte précise, inutile d'y grignoter encore avec `NUDGE_SCALE`. Sans
	# objet pour le z-fighting de toute façon : "Pompe"/"MuretGouletO/E"
	# portent `"visual":false` (wasteland.gd, voir l'en-tête du fichier),
	# couverture vérifiée AABB-contre-boîte avant ce bascule (rapport de
	# tâche) — le module ci-dessous est déjà la SEULE géométrie rendue.
	_place_ground(parent, by_name, "Pompe", SKINS_DIR + "covers_pompe.glb", false)
	_place_ground(parent, by_name, "MuretGouletO", SKINS_DIR + "covers_muret_goulet.glb")
	_place_ground(parent, by_name, "MuretGouletE", SKINS_DIR + "covers_muret_goulet.glb")

	# -- Couverts, ouest + est (mêmes noms, _mirror_piece les reflète déjà) --
	_skin_citerne(parent, by_name, "CiterneFUEL")
	_skin_citerne(parent, by_name, "CiterneGAS")
	_place_centered(parent, by_name, "CaisseFUEL", SHANTY_DIR + "crate_stack_fit.glb")
	_place_centered(parent, by_name, "CaissesW", SKINS_DIR + "covers_caisses_w.glb")
	_place_centered(parent, by_name, "CaissesE", SKINS_DIR + "covers_caisses_w.glb")
	_place_centered(parent, by_name, "CaissesQuaiW", SKINS_DIR + "covers_caisses_quai.glb")
	_place_centered(parent, by_name, "CaissesQuaiE", SKINS_DIR + "covers_caisses_quai.glb")
	_place_ground(parent, by_name, "AbreuvoirW1", SHANTY_DIR + "trough.glb", false)
	_place_ground(parent, by_name, "AbreuvoirW2", SHANTY_DIR + "trough.glb", false)
	_place_ground(parent, by_name, "AbreuvoirE1", SHANTY_DIR + "trough.glb", false)
	_place_ground(parent, by_name, "AbreuvoirE2", SHANTY_DIR + "trough.glb", false)
	_place_ground(parent, by_name, "ComptoirW", SHANTY_DIR + "counter.glb", false)
	_place_ground(parent, by_name, "ComptoirE", SHANTY_DIR + "counter.glb", false)
	_place_ground(parent, by_name, "TonneauxW", SKINS_DIR + "covers_tonneaux.glb", false)
	_place_ground(parent, by_name, "TonneauxE", SKINS_DIR + "covers_tonneaux.glb", false)
	_place_ground(parent, by_name, "TraversesW", SHANTY_DIR + "sleeper_stack.glb")
	_place_ground(parent, by_name, "TraversesE", SHANTY_DIR + "sleeper_stack.glb")
	_place_ground(parent, by_name, "PileTraversesNW", SKINS_DIR + "covers_pile_traverses.glb")
	_place_ground(parent, by_name, "PileTraversesNE", SKINS_DIR + "covers_pile_traverses.glb")
	_place_ground(parent, by_name, "RemiseW", SKINS_DIR + "covers_remise_w.glb")
	_place_ground(parent, by_name, "RemiseE", SKINS_DIR + "covers_remise_w.glb")
	_skin_cuve(parent, by_name, "CuveW")
	_skin_cuve(parent, by_name, "CuveE")
	_place_ground(parent, by_name, "ChariotMineW", SHANTY_DIR + "mine_cart.glb", false)
	_place_ground(parent, by_name, "ChariotMineE", SHANTY_DIR + "mine_cart.glb", false)
	_place_ground(parent, by_name, "CharretteW", SKINS_DIR + "covers_charrette_w.glb")
	_place_ground(parent, by_name, "CharretteE", SKINS_DIR + "covers_charrette_w.glb")

	# -- Clôtures, parapets, barrières (pièces "fence"/"box" en ligne) ------
	_skin_cloture(parent, by_name, "ClotureW")
	_skin_cloture(parent, by_name, "ClotureE")
	for n in [1, 2, 3]:
		_skin_parapet(parent, by_name, "ParapetW%d" % n)
		_skin_parapet(parent, by_name, "ParapetE%d" % n)
	_skin_barrieres(parent, by_name)


# ======================================================================
#  Index et primitives d'instanciation/peinture.
# ======================================================================

## Une même clé peut porter PLUSIEURS pièces : `_mirror_name` (wasteland.gd)
## ne connaît que le suffixe "W"/"W<chiffre>" -> "E"/"E<chiffre>" et une
## petite table explicite (Hotel/CiterneFUEL) ; un nom sans les deux (ex.
## "CaisseFUEL") ressort DEUX FOIS sous le MÊME nom dans `data["pieces"]`
## (l'original ouest et sa position reflétée à l'identique) — `_for_each`
## habille alors les deux occurrences avec la même peau, jamais une seule.
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

## Repeint chaque surface par le nom de matériau glTF d'origine (survécu à
## l'import en `Material.resource_name`, même convention que
## `PropCatalog._paint_slots`, réécrite ici en local — ce module ne dépend
## d'aucune fonction privée d'un autre chantier) : un slot nommé
## "wood_planks"/"rust"/"painted_metal"/"corrugated_metal"/"dirty_glass"
## (les 5 kinds peints du contrat ART-73/92) passe par `Cartoon.
## painted_for_slot`. Une coque Tripo (`poste_shell`, `diligence_shell`,
## `covers_chateau_cuve`, `covers_citerne_tank`, `covers_cuve_w`,
## `covers_charrette_w`, `covers_remise_w`, `covers_cloture`) garde son
## matériau slot 0 SANS nom de kind (R2 d'ART-92 : « albédo Tripo intact ») —
## son `resource_name` ne correspond à aucun des 5 kinds, la boucle le laisse
## alors intact, l'albédo peint Tripo d'origine reste affiché tel quel.
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

## Place une peau dont l'origine locale est à la BASE (sol, y = 0 dans le
## .glb — modules kit v2 murs/toit/piles de traverses, coques Tripo dont
## l'axe hauteur n'a subi AUCUN étirement, voir les commentaires de bake) :
## la base de la boîte Kit (`pos.y - size.y * 0.5`, toujours 0 pour les
## pièces couvertes par ce module) reçoit directement l'origine de la peau.
## `nudge` (déf. vrai) : marge anti-z-fighting `NUDGE_SCALE` (§8) — jamais
## sur les pièces qui débordent déjà nettement leur boîte (abreuvoir/
## comptoir/chariot de mine : modules kit v2 existants, ART-92, non recuits
## ici, dont la coque proprement dite ne touche déjà pas les faces).
## `extra_rot_deg` (déf. 0) : tourne la peau EN PLUS du `rot_y` du
## dictionnaire de pièce (toujours 0 pour les pièces couvertes ici, mais un
## gabarit cuit peut avoir sa longueur le long d'un autre axe que la boîte
## réelle — Barrières Rue/Canyon, voir `_skin_barrieres`) — rotation
## rigide, jamais d'étirement, jamais de risque pour R7.
static func _place_ground(parent: Node3D, by_name: Dictionary, name: String, path: String, nudge: bool = true, extra_rot_deg: float = 0.0) -> void:
	_for_each(by_name, name, func(p: Dictionary) -> void:
		var pos: Vector3 = p["pos"]
		var size: Vector3 = p["size"]
		var node := _instance(path)
		if node == null:
			return
		node.position = Vector3(pos.x, pos.y - size.y * 0.5, pos.z)
		node.rotation.y = float(p.get("rot_y", 0.0)) + deg_to_rad(extra_rot_deg)
		if nudge:
			node.scale = Vector3.ONE * NUDGE_SCALE
		parent.add_child(node)
		_paint_tree(node)
	)

## Place une peau dont l'origine locale est CENTRÉE sur les 3 axes (modules
## `crate_stack_fit` — `_telescoped_cells` centre aussi l'axe hauteur, à la
## différence de `sleeper_stack`/`plank_wall_parts` : mesuré à l'export,
## cf. rapport de tâche) : le centre de la boîte Kit (`pos`, déjà le centre
## par construction de `wasteland.gd::_box`) reçoit directement l'origine.
static func _place_centered(parent: Node3D, by_name: Dictionary, name: String, path: String) -> void:
	_for_each(by_name, name, func(p: Dictionary) -> void:
		var pos: Vector3 = p["pos"]
		var node := _instance(path)
		if node == null:
			return
		node.position = pos
		node.rotation.y = float(p.get("rot_y", 0.0))
		node.scale = Vector3.ONE * NUDGE_SCALE
		parent.add_child(node)
		_paint_tree(node)
	)


# ======================================================================
#  Composites : pièces où une seule coque ne suffit pas à couvrir la boîte
#  (R7), complétées par un second volume attenant — jamais un module qui
#  déborde ou laisse un jour visible (plan §2, R7 "sinon on voit à travers
#  un obstacle qui arrête les balles").
# ======================================================================

## Poste 8×9×6,4 (le "Poste" du shérif, centre de la place — §2, façade
## fausse au-dessus de la boîte solide, voir wasteland.gd `_box("Poste", ...,
## "solid")`). Correctif vérification (2026-09-25) : cette pièce n'avait
## jamais sa propre dérivation ici (avant : un simple appel `_place_ground`,
## seule la marge `NUDGE_SCALE` par défaut s'appliquait) — `poste_shell.glb`
## est en réalité cuite à 7,0 m de large et 8,4 m de profondeur (mesuré sur
## le fichier livré), SOUS les 8×9 m de la boîte réelle sur ces deux axes
## (hauteur 8,5 m, elle, DÉJÀ au-dessus des 6,4 m de la boîte — cohérent avec
## la silhouette "fausse façade" plus haute que le volume solide, §1 "B0" du
## plan — aucun correctif nécessaire sur Y). Sous sa cote réelle en large/
## profondeur, la coque restait invisible derrière la boîte opaque du Kit
## (voir le commentaire d'en-tête du fichier), quel que soit son remplissage
## R7 mesuré en isolation. `scale` ci-dessous (calculé contre la boîte RÉELLE
## 8×9 — jamais retouché en Y, déjà surabondant) fait dépasser la coque de
## 8/9 cm par face en largeur/profondeur (`NUDGE_SCALE` de marge), dans la
## tolérance ±10 cm de R1.
const _POSTE_BOX_WIDTH_M := 8.0
const _POSTE_BOX_DEPTH_M := 9.0
const _POSTE_SHELL_NATURAL_WIDTH_M := 7.0
const _POSTE_SHELL_NATURAL_DEPTH_M := 8.4
static func _skin_poste(parent: Node3D, by_name: Dictionary) -> void:
	var scale := Vector3(
		_POSTE_BOX_WIDTH_M * NUDGE_SCALE / _POSTE_SHELL_NATURAL_WIDTH_M,
		1.0,
		_POSTE_BOX_DEPTH_M * NUDGE_SCALE / _POSTE_SHELL_NATURAL_DEPTH_M)
	_for_each(by_name, "Poste", func(p: Dictionary) -> void:
		var pos: Vector3 = p["pos"]
		var size: Vector3 = p["size"]
		var node := _instance(SKINS_DIR + "poste_shell.glb")
		if node == null:
			return
		node.position = Vector3(pos.x, pos.y - size.y * 0.5, pos.z)
		node.rotation.y = float(p.get("rot_y", 0.0))
		node.scale = scale
		parent.add_child(node)
		_paint_tree(node)
	)

## Diligence 6×5×3,4 (§2 "diligence collée à une pile de malles et de sacs
## postaux... sans jour sous la caisse") : `diligence_shell.glb` (coque
## `wl_diligence` ajustée, ART-92 : étirement 14,4 %/14,1 % en largeur/
## profondeur, 0 % en hauteur — les 3 dans le contrat ≤ 15 %) occupe
## `[-2,5 ; +0,55]` des 5 m de profondeur de la boîte (2,5 → -0,975 de son
## propre centre) ; `diligence_crates.glb` (pile `crate_stack_fit(5.6 ; 3.2 ;
## 1.95)`) comble le reste, `[+0,55 ; +2,5]` (centre +1,525) — la somme des
## deux profondeurs (3,05 + 1,95) vaut exactement 5 m, aucun jour.
##
## Correctif vérification (2026-09-25) : la coque `diligence_shell` (5,6 m de
## large) reste SOUS les 6 m de large de la boîte `Diligence` — un défaut
## d'étirement (ART-92, borné à 15 %) jamais compensé ici, si bien que les
## deux tranches de 0,2 m de boîte nue de chaque côté (jamais posées en
## retrait, `_paint_tree` n'y change rien) restaient DEVANT la coque dans le
## test de profondeur : la coque, bien qu'ajoutée et peinte, ne "gagnait"
## jamais contre la boîte opaque du Kit et restait invisible de face (voir le
## commentaire d'en-tête du fichier). `shell_x_scale` étire la coque en X
## SEULEMENT (jamais Y/Z, déjà exacts au reste du composite ci-dessus) à
## `6,0 × NUDGE_SCALE = 6,12 m`, soit 6 cm de dépassement par côté — dans la
## tolérance ±10 cm de R1, jamais retouché sur Y/Z pour ne pas perturber le
## partage de profondeur avec `diligence_crates` juste au-dessus.
##
## Second correctif, posé en préparant `"visual":false` sur "Diligence"
## (`wasteland.gd`, voir l'en-tête de ce fichier) : `diligence_crates.glb`
## est un module `crate_stack_fit`, donc son origine locale est CENTRÉE sur
## les 3 axes (même convention que `_place_centered`, voir son commentaire) —
## JAMAIS à la base. Il était pourtant placé avec `pos.y - size.y * 0.5` (la
## convention "base", correcte pour `diligence_shell` juste au-dessus, mais
## fausse ici) : la moitié du maillage (1,6 m sur 3,2 m de haut) partait sous
## le sol, le sommet visible ne montant qu'à 1,6 m sur les 3,4 m de la boîte
## — un vrai déficit de remplissage sur la moitié arrière (sous les 85 % de
## R7), resté invisible tant que la boîte Kit opaque restait dessous, mais
## qui aurait ouvert un trou béant une fois la boîte cachée. `crates.position.
## y` passe donc à `pos.y` (le CENTRE de la boîte, comme `_place_centered` le
## fait pour tous les autres modules `crate_stack_fit`) : le maillage,
## centré, couvre alors `[0,07 ; 3,33]` sur les 3,4 m de la boîte (mesuré),
## dans la tolérance ±10 cm de R1. Même correctif en X que `shell_x_scale`
## ci-dessus (le même défaut d'étirement à 5,6 m sur 6,0 m de boîte s'applique
## à la pile) : `crates.scale` passe d'un `NUDGE_SCALE` uniforme (qui ne
## touchait pas le déficit de largeur, laissant 14,4 cm de vide de chaque
## côté) à `Vector3(shell_x_scale, NUDGE_SCALE, NUDGE_SCALE)` — X aligné sur
## la largeur réelle de la boîte, Y/Z gardent la marge uniforme d'origine
## (le partage de profondeur avec la coque n'en dépend pas, lui reste
## inchangé). Mesuré (AABB monde du composite coque+caisses contre la boîte
## réelle) : écart ≤ 6,1 cm en X, ≤ 1,9 cm en Z, ≤ 0,2 cm en Y, toujours un
## DÉBORD — jamais un trou, dans la tolérance ±10 cm de R1.
const _DILIGENCE_BOX_WIDTH_M := 6.0
const _DILIGENCE_SHELL_NATURAL_WIDTH_M := 5.6
static func _skin_diligence(parent: Node3D, by_name: Dictionary) -> void:
	var shell_x_scale := _DILIGENCE_BOX_WIDTH_M * NUDGE_SCALE / _DILIGENCE_SHELL_NATURAL_WIDTH_M
	_for_each(by_name, "Diligence", func(p: Dictionary) -> void:
		var pos: Vector3 = p["pos"]
		var shell := _instance(SKINS_DIR + "diligence_shell.glb")
		if shell != null:
			shell.position = Vector3(pos.x, pos.y - (p["size"] as Vector3).y * 0.5, pos.z - 0.975)
			shell.rotation.y = float(p.get("rot_y", 0.0))
			shell.scale = Vector3(shell_x_scale, 1.0, 1.0)
			parent.add_child(shell)
			_paint_tree(shell)
		var crates := _instance(SKINS_DIR + "diligence_crates.glb")
		if crates != null:
			# Origine CENTRÉE (crate_stack_fit) : `pos.y`, jamais `pos.y -
			# size.y * 0.5` (voir le correctif ci-dessus).
			crates.position = Vector3(pos.x, pos.y, pos.z + 1.525)
			crates.rotation.y = float(p.get("rot_y", 0.0))
			crates.scale = Vector3(shell_x_scale, NUDGE_SCALE, NUDGE_SCALE)
			parent.add_child(crates)
			_paint_tree(crates)
	)

## Château d'eau (§2 "cuve et toit recadrés dans wl_water_tower (mode crop),
## ajustés à la boîte de la cuve. Pieds en bois et fer (module tower_leg) à
## ±5 cm") : la cuve (`covers_chateau_cuve.glb`, ART-92 crop z ∈ [3,6 ; 9,4]
## du modèle complet PUIS ajustement 3,6×3,6×4 — écart au contrat 15 %
## ASSUMÉ et documenté dans le rapport de bake, repère lointain visible de
## partout, §2) est posée sur `ChateauCuve` (base à y=8, cf. wasteland.gd) ;
## les 4 pieds reprennent tel quel `tower_leg.glb` (ART-92, hauteur 8 m —
## cote EXACTE des 4 boîtes `PiedChateau{NO,NE,SO,SE}`, aucune peau neuve
## nécessaire ici).
##
## Correctif vérification (2026-09-25) : `covers_chateau_cuve.glb` (3,6×3,6×
## 4 m) est cuite PILE aux cotes de la boîte `ChateauCuve` (même 3,6×3,6×4)
## — le cas exact que `NUDGE_SCALE` existe pour couvrir (voir son commentaire
## de constante), jamais appliqué ici jusqu'ici (fonction dédiée, jamais
## passée par `_place_ground`) : la boîte opaque du Kit gagnait alors le test
## de profondeur sur toute la hauteur de la cuve. `NUDGE_SCALE` uniforme
## suffit (les 3 axes sont à égalité, aucune raison de sortir un `Vector3`
## par axe comme pour Citerne/Poste).
static func _skin_chateau_eau(parent: Node3D, by_name: Dictionary) -> void:
	_for_each(by_name, "ChateauCuve", func(p: Dictionary) -> void:
		var pos: Vector3 = p["pos"]
		var size: Vector3 = p["size"]
		var cuve := _instance(SKINS_DIR + "covers_chateau_cuve.glb")
		if cuve == null:
			return
		# Origine locale de la coque recadrée : base à z = 4,5 m (mesuré à
		# l'export, cf. rapport de tâche) au lieu de 0 — décalage constant
		# `-4,5` pour ramener sa base au bas RÉEL de la boîte `ChateauCuve`.
		# `NUDGE_SCALE` grandit le maillage AUTOUR de l'origine du nœud (0),
		# pas autour de sa base locale (4,5) : le décalage doit donc reculer
		# de `4,5 * NUDGE_SCALE` (pas `4,5` pile) pour que la base mise à
		# l'échelle retombe encore exactement sur la boîte — sinon la cuve
		# flotterait de `4,5 * (NUDGE_SCALE - 1)` ≈ 9 cm au-dessus des pieds.
		cuve.position = Vector3(pos.x, (pos.y - size.y * 0.5) - 4.5 * NUDGE_SCALE, pos.z)
		cuve.scale = Vector3.ONE * NUDGE_SCALE
		parent.add_child(cuve)
		_paint_tree(cuve)
	)
	for leg_name in ["PiedChateauNO", "PiedChateauNE", "PiedChateauSO", "PiedChateauSE"]:
		_for_each(by_name, leg_name, func(p: Dictionary) -> void:
			var pos: Vector3 = p["pos"]
			var leg := _instance(SHANTY_DIR + "tower_leg.glb")
			if leg == null:
				return
			leg.position = Vector3(pos.x, 0.0, pos.z)
			parent.add_child(leg)
			_paint_tree(leg)
		)

## CiterneFUEL/GAS 4×2,8×4 (§2 "wl_tank_horizontal ×0,8 uniforme, axe E-O,
## sur un muret de rétention kit de 1,2 m") : la cuve seule
## (`covers_citerne_tank.glb`, ART-92 crop hauteur exacte 2,8 m puis
## ajustement largeur 99 %/profondeur 96,9 % — 15 %/32 % (`cylinder_axis`)
## au contrat) atteint déjà ≥ 85 % sur ses 4 faces horizontales ; le muret
## réutilise tel quel `bund_wall.glb` (ART-92, 4×1,2 m — exactement un côté
## de la boîte 4×4) sur les 4 côtés, qui porte le remplissage à ~91 % sur la
## tranche basse (0-1,2 m) là où la cuve seule tombait sous 85 % (calcul :
## voir rapport de tâche). Teinte FUEL/GAS (§2 "pochoir... tôle bleue ou
## rouge") NON appliquée ici : le slot 0 de la coque Tripo reste l'albédo
## d'origine intact (R2 d'ART-92) — un pochoir distinct par cour est hors de
## mon périmètre de fichiers (peinture de texture, pas une teinte de
## surface), signalé en `blocked_on`.
##
## Correctif vérification (2026-09-25) : "atteint déjà ≥ 85 %" ci-dessus est
## une mesure ORTHOGRAPHIQUE du maillage de la cuve seule (R7) — elle ne dit
## rien de ce qui la RECOUVRE une fois posée. À 99 %/96,9 % de la boîte, la
## cuve reste PARTOUT sous la cote de la boîte 4×4×2,8 opaque du Kit
## (`_skin_citerne` ne posait jusqu'ici aucune marge, contrairement aux
## pièces passées par `_place_ground`) : la boîte gagnait alors le test de
## profondeur sur toute la surface de la cuve, invisible de l'extérieur quel
## que soit son remplissage mesuré. `tank_scale` (calculé contre la boîte
## RÉELLE 4×2,8×4 — jamais contre la cote naturelle 3,96×2,8×3,875 de la
## cuve — à `NUDGE_SCALE` de marge) fait dépasser la cuve de 4 à 5,6 cm par
## face, dans la tolérance ±10 cm de R1 ; asymétrique entre X et Z (3,0 %/
## 5,3 %) parce que le déficit d'origine l'est déjà (99 %/96,9 %) — un écart
## bien sous l'exception cylindre (32 %) du contrat d'étirement d'ART-92.
const _CITERNE_BOX_SIZE_M := Vector3(4.0, 2.8, 4.0)
const _CITERNE_TANK_NATURAL_SIZE_M := Vector3(3.96, 2.8, 3.875)
static func _skin_citerne(parent: Node3D, by_name: Dictionary, name: String) -> void:
	var tank_scale := Vector3(
		_CITERNE_BOX_SIZE_M.x * NUDGE_SCALE / _CITERNE_TANK_NATURAL_SIZE_M.x,
		_CITERNE_BOX_SIZE_M.y * NUDGE_SCALE / _CITERNE_TANK_NATURAL_SIZE_M.y,
		_CITERNE_BOX_SIZE_M.z * NUDGE_SCALE / _CITERNE_TANK_NATURAL_SIZE_M.z)
	_for_each(by_name, name, func(p: Dictionary) -> void:
		var pos: Vector3 = p["pos"]
		var size: Vector3 = p["size"]
		var base_y: float = pos.y - size.y * 0.5
		var tank := _instance(SKINS_DIR + "covers_citerne_tank.glb")
		if tank != null:
			tank.position = Vector3(pos.x, base_y, pos.z)
			tank.scale = tank_scale
			parent.add_child(tank)
			_paint_tree(tank)
		var hx: float = size.x * 0.5
		var hz: float = size.z * 0.5
		var walls := [
			{"pos": Vector3(pos.x, base_y, pos.z - hz), "rot": 0.0},
			{"pos": Vector3(pos.x, base_y, pos.z + hz), "rot": PI},
			{"pos": Vector3(pos.x - hx, base_y, pos.z), "rot": -PI * 0.5},
			{"pos": Vector3(pos.x + hx, base_y, pos.z), "rot": PI * 0.5},
		]
		for w in walls:
			var wall := _instance(SHANTY_DIR + "bund_wall.glb")
			if wall == null:
				continue
			wall.position = w["pos"]
			wall.rotation.y = w["rot"]
			parent.add_child(wall)
			_paint_tree(wall)
	)

## CuveW/E (wagon-citerne) 3×2,4×4,5 (§2 "wagon-citerne : wl_tank_horizontal
## ... allongé comme un vrai wagon-citerne, sur un châssis kit posé sur les
## rails") : `covers_cuve_w.glb` est cuite (ART-92) sur l'axe LOCAL de la
## coque — hauteur recadrée à 2,4 m pile (0 % d'étirement résiduel), 4,5 m
## le long de l'axe local X (le grand axe naturel de la coque, -3,3 %) et
## 3,0 m le long de l'axe local Y (+2,2 %), tous deux dans le contrat 15 % —
## d'où la rotation de +90° ici : le grand axe naturel de la coque (son X
## local, 4,5 m) devient alors la PROFONDEUR (Z monde) de la boîte CuveW,
## et son axe court (Y local, 3,0 m) devient la largeur (X monde), sans
## quoi le sens naturel de la coque (façonnée par Tripo pour un tonneau
## COUCHÉ, plus long que large) ne correspondrait pas à la boîte réelle
## (profondeur 4,5 m > largeur 3 m).
## Correctif vérification (2026-09-25) : les 3 cotes recadrées ci-dessus
## tombent PILE sur celles de la boîte `CuveW`/`CuveE` (3x2,4x4,5, une fois
## la rotation +90° appliquée) — encore le cas exact de `NUDGE_SCALE`, encore
## jamais appliqué ici (fonction dédiée, jamais passée par `_place_ground`).
## Origine locale centrée en X/Z et posée au sol en Y (mesuré à l'export) :
## une échelle uniforme autour de cette origine ne déplace ni ne soulève la
## coque, contrairement au château d'eau ci-dessus (origine locale PAS à sa
## base, voir son propre correctif).
static func _skin_cuve(parent: Node3D, by_name: Dictionary, name: String) -> void:
	_for_each(by_name, name, func(p: Dictionary) -> void:
		var pos: Vector3 = p["pos"]
		var size: Vector3 = p["size"]
		var node := _instance(SKINS_DIR + "covers_cuve_w.glb")
		if node == null:
			return
		node.position = Vector3(pos.x, pos.y - size.y * 0.5, pos.z)
		node.rotation.y = float(p.get("rot_y", 0.0)) + PI * 0.5
		node.scale = Vector3.ONE * NUDGE_SCALE
		parent.add_child(node)
		_paint_tree(node)
	)


# ======================================================================
#  Lignes (pièces "fence"/"box" en série) : clôture, parapets, barrières.
# ======================================================================

## Reprend l'orientation EXACTE de `Kit.fence()` (Kit.gd) : origine des
## segments posée au SOL du tracé (`start`/`end`, jamais le centre décalé de
## `height * 0.5` que porte la boîte de collision), base locale X = sens du
## tracé (`fwd`), Y = vertical, Z = travers (`side`) — même convention que
## `plank_rail_solid`/`plank_wall_parts` (longueur le long de l'axe X
## d'auteur). `n` segments de `asset_len` RÉPARTIS pile sur la longueur
## réelle (`length / n`, jamais une longueur fixe qui déborderait ou
## laisserait un bout nu) ; `mirror_alt` (Clôture, §2 "×2, dont un en
## miroir") inverse un segment sur deux (échelle X négative, jamais de
## nouvelle coque).
static func _place_fence_run(parent: Node3D, start: Vector3, end: Vector3, asset_path: String, asset_len: float, mirror_alt: bool = false) -> void:
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
		var mirror := -1.0 if (mirror_alt and i % 2 == 1) else 1.0
		node.scale = Vector3(seg_len / asset_len * mirror, 1.0, 1.0)
		parent.add_child(node)
		_paint_tree(node)

## ClotureW/E (§2 "wl_fence_broken recadré à ≤ 1,1 m, ×2, dont un en
## miroir") : `covers_cloture.glb` (ART-92, crop hauteur ≤ 1,1 m, aucun
## étirement horizontal) tuilé ×2 sur les 4 m du tracé, un exemplaire
## reflété.
static func _skin_cloture(parent: Node3D, by_name: Dictionary, name: String) -> void:
	_for_each(by_name, name, func(p: Dictionary) -> void:
		_place_fence_run(parent, p["start"], p["end"], SKINS_DIR + "covers_cloture.glb", 2.13, true)
	)

## ParapetW1-3/E1-3 (§2 "garde-corps en planches jointives... poteaux tous
## les 2 m") : `plank_rail_solid.glb` (ART-92, module kit v2 déjà livré,
## 4×1,1 m) tuilé sur toute la longueur réelle du tracé (3 à 19 m selon le
## segment, cf. wasteland.gd) — jamais un seul exemplaire étiré à l'excès.
static func _skin_parapet(parent: Node3D, by_name: Dictionary, name: String) -> void:
	_for_each(by_name, name, func(p: Dictionary) -> void:
		_place_fence_run(parent, p["start"], p["end"], SHANTY_DIR + "plank_rail_solid.glb", 4.0)
	)

## Barrières Duel/Duo (§2 "barricade de planches et de sacs de sable, posée
## seulement si la pièce existe" — R9, voir le commentaire d'en-tête :
## absentes de `data["pieces"]` en 4v4, `_for_each` ne trouve alors rien).
## 3 gabarits pré-cuits pile aux 3 empreintes (`covers_barricade_{rue,
## ruelle,canyon}.glb`, longueur 8/4/15 m, hauteur 2,6 m) : Rue/Canyon ont
## leur grand axe le long de Z (boîte (0,5 ; 2,6 ; 8|15)), une rotation de
## 90° aligne leur longueur cuite (le long de X) sur ce grand axe ; Ruelle
## a déjà son grand axe le long de X (boîte (4 ; 2,6 ; 0,5)), aucune
## rotation.
static func _skin_barrieres(parent: Node3D, by_name: Dictionary) -> void:
	for s in [1, -1]:
		_place_ground(parent, by_name, "BarriereRue%d" % s, SKINS_DIR + "covers_barricade_rue.glb", true, 90.0)
	for s in [1, -1]:
		_place_ground(parent, by_name, "BarriereRuelle%d" % s, SKINS_DIR + "covers_barricade_ruelle.glb")
	for s in [1, -1]:
		_place_ground(parent, by_name, "BarriereCanyon%d" % s, SKINS_DIR + "covers_barricade_canyon.glb", true, 90.0)
