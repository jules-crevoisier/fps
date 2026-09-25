## tools/blender/ai_restyle.py
## Restyle d'une sortie IA brute (image/texte -> 3D, ex. Tripo/Meshy — voir
## docs/research/06_ai_3d_pipeline.md §A2/§A6, docs/3D_PIPELINE.md §6) vers
## la convention "maison" : la forme vient de l'IA, TOUT le reste (matiere,
## normales, encre, echelle) vient d'ici. Ce script ne modifie JAMAIS le
## fichier source (import en memoire, comme turntable.py/check_asset.py) et
## ne garde RIEN de la texture/matiere IA d'origine dans la sortie.
##
##   blender -b --factory-startup --python-exit-code 1 -P tools/blender/ai_restyle.py -- \
##       --in assets_src/ai_raw/<id>/model.glb --family heads --budget 3000 \
##       --out assets/models/heads/head_tv.glb
##
## Pipeline (docs/research/06_ai_3d_pipeline.md §A6.2-§A6.5) :
##   1. import                 .glb/.gltf/.fbx/.obj -> un seul objet mesh (fusionne si l'IA a
##                              livre plusieurs sous-objets, comme toonkit.join)
##   2. nettoyage               fusion des sommets quasi confondus (bruit de triangulation IA
##                              typique) + suppression des morceaux isoles (fragments fantomes)
##   3. transfert de palette    CHAQUE materiau importe (texture ou couleur plate) est
##                              echantillonne, classe par plus proche voisin perceptuel (Lab,
##                              CIE76) parmi les kinds peints connus de Cartoon.gd
##                              (Cartoon._PAINTED), puis remplace par un toonkit.toon_material()
##                              de CETTE couleur de palette exacte — jamais la texture IA
##                              (jetee). Deux materiaux qui quantifient vers le meme kind
##                              partagent UN seul materiau de sortie.
##   4. etancheite               un maillage IA peut avoir des trous (scan incomplet) : remesh en
##                              voxel GLOBAL (l'objet entier, jamais par kind — un remesh par kind
##                              produit des parois internes qui se recouvrent a l'ancienne
##                              frontiere, verifie par sondage, voir rapport de tache) s'il n'est
##                              pas etanche, PUIS suppression de tout fragment reste disjoint du
##                              corps principal (un remesh Voxel global scelle chaque ilot en un
##                              solide manifold INDEPENDANT mais n'en recolle jamais deux — un
##                              simple test « aucune arete de bord » ne suffit pas a le detecter,
##                              voir `_drop_floating_islands`). Garantit un solide manifold UNIQUE ;
##                              en echange, si l'objet porte plusieurs kinds, ne garde que le kind
##                              DOMINANT (le plus de faces d'origine) pour tout l'objet — compromis
##                              trace dans le rapport JSON (`watertight_fix`), jamais une perte
##                              silencieuse. A3D-15 : un AVERTISSEMENT, jamais un blocage dur — si
##                              aucune taille de voxel n'aboutit, le maillage D'ORIGINE (non etanche
##                              mais complet, jamais mutile par une tentative rejetee) est conserve
##                              tel quel (`watertight_fix["remesh_failed"]`) ; check_asset.py::CHK-16
##                              ne traite deja un bord ouvert que comme un avertissement.
##   5. budget                  Decimate COLLAPSE iteratif jusqu'au budget de tris demande AVANT le
##                              biseau (echec loud, jamais un depassement silencieux), PUIS une
##                              seconde passe (`decimate_group_to_budget`, sur le corps ET ses pieces
##                              separees) APRES le biseau de l'etape 6 (A3D-15) : le biseau AJOUTE
##                              des triangles sur chaque arete vive, et un maillage deja sous son
##                              budget avant lui (donc jamais decime a cette premiere passe) peut
##                              seul en repasser au-dessus — le budget final n'est donc verifie, et
##                              tenu, qu'APRES le biseau, jamais avant lui seul.
##   6. normales/encre          toonkit.weighted_normals + smooth_normal_attrs (coque de
##                              contour) + bake_vertex_ao + curvature_edge_mask.
##   7. echelle/origine         toonkit.apply_transforms (bake le node-scale qu'un GLB IA laisse
##                              souvent non resolu — TOT si le remesh en a besoin, voir
##                              `_needs_early_scale_fix`, puis a nouveau en filet de securite)
##                              et toonkit.set_origin_bottom (base au sol, +Y une fois exporte).
##   8. export + revue          toonkit.export_glb (rapport JSON tris/attributs) + un rapport
##                              propre a ce script (kinds/deltaE/ilots remeshes) + le turntable
##                              (tools/blender/turntable.py, lance dans un sous-process Blender
##                              dedie — meme regard que pour un asset "maison", docs/
##                              3D_PIPELINE.md §1/§6).
##
## Rien de specifique a la provenance IA ne doit fuiter plus loin dans le pipeline : une fois
## ce script passe, l'asset est indiscernable d'un asset construit a la main avec toonkit
## (docs/3D_PIPELINE.md §6, derniere ligne).
import argparse
import colorsys
import json
import math
import os
import subprocess
import sys

import bpy
import bmesh
from mathutils import Vector
from mathutils.kdtree import KDTree

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
import toonkit  # noqa: E402

# ---------------------------------------------------------------------------
# Vocabulaire de sortie — UNIQUEMENT les kinds peints reconnus PAR
# scripts/core/Cartoon.gd AUJOURD'HUI (Cartoon._PAINTED, meme liste que
# tools/blender/check_asset.py::KNOWN_MATERIAL_KINDS et que
# tools/textures/gen_textures.py::MATERIALS — les trois DOIVENT rester
# synchrones). PAS les 5 slots generiques v3 (base/accent/metal/glass/sign,
# docs/STYLE_BIBLE.md §7.9) : cette migration n'est pas faite, Cartoon.painted()
# ne les consomme pas encore (docs/3D_PIPELINE.md §5) — un asset qui sortirait
# avec ces noms-la ne serait PAS rendu correctement au runtime aujourd'hui.
# Chaque nom est A LA FOIS le nom du materiau de sortie ET la cle
# toonkit.palette()/toonkit.toon_material(kind=...) — les trois vocabulaires
# partagent le meme mot par construction (voir Cartoon.gd, commentaire sur
# _PAINTED : "Kinds match tools/textures/gen_textures.py's MATERIALS dict
# one-for-one").
CANDIDATE_KINDS = [
	"painted_metal", "rust", "corrugated_metal", "container_paint", "wood_planks",
	"sand_dirt", "cracked_concrete", "asphalt", "ship_deck", "rubber_tire", "dirty_glass",
]

# Budgets de tris par famille (docs/research/06_ai_3d_pipeline.md §A5, table reprise dans
# docs/3D_PIPELINE.md §5) — utilises seulement si l'appelant omet --budget.
FAMILY_BUDGETS = {
	"heads": 3000,
	"characters": 15000,
	"weapons": 10000,
	"props_small": 1500,
	"props_large": 5000,
	"props": 3000,
}

MERGE_DIST_RATIO = 0.0005      # fraction de la diagonale de bbox pour la fusion de sommets
# A3D-15 : seuil de PROXIMITE SPATIALE (gap de boite englobante, meme mesure
# que check_asset.py::FLOATING_GAP_TOLERANCE_M/CHK-16) utilise pour regrouper
# des ilots topologiquement disjoints (`_face_islands` : aucune arete
# partagee) en clusters (`_cluster_islands_by_gap`) — remplace l'ancien
# ISLAND_MIN_FACE_RATIO/ISLAND_MIN_FACE_ABSOLUTE (seuil de NOMBRE DE FACES
# relatif au total, sans notion de distance) : releve concret de tache sur la
# vague 1 (wl_oil_derrick, wl_crane_lattice, cs_deck_crane, cs_ship_mast...) —
# un assemblage IA multi-pieces legitime (mat + cabine + fleche de grue,
# jambes + croisillons d'un pylone treillis) sort de Tripo en PLUSIEURS ilots
# topologiquement separes (jamais ressoudes par `merge_by_distance`, chaque
# piece etant son propre sous-maillage), dont AUCUN n'est individuellement le
# plus gros par nombre de faces (une petite cabine detaillee peut porter plus
# de faces qu'un long fut simple) : l'ancien seuil par RATIO ne gardait alors
# que l'ilot le plus gros et jetait TOUS les autres, amputant la silhouette
# (ex. wl_oil_derrick : 10 m de treillis reduits a 0,53 m, seule la couronne
# survivant). Un cluster de proximite (transitif : A proche de B, B proche de
# C => meme cluster meme si A et C sont trop loin l'un de l'autre directement)
# capture correctement ces assemblages TOUCHANTS tout en continuant a rejeter
# un vrai fragment fantome, geometriquement ISOLE (gap > tolerance) du reste —
# voir `remove_isolated_islands`/`_drop_floating_islands`, qui partagent
# desormais ce seul et meme critere.
ISLAND_GAP_TOLERANCE_M = 0.01
VOXEL_RESOLUTION = 48.0        # taille de voxel = diagonale de l'ilot / cette resolution
VOXEL_SIZE_MIN = 0.002         # 2 mm — plancher (evite un remesh interminable sur un micro-ilot)
VOXEL_SIZE_MAX = 0.2           # 20 cm — plafond (garde du detail sur un ilot deja gros)
VOXEL_REMESH_MIN_EXTENT_RATIO = 0.5  # voir _voxel_remesh : refuse un resultat qui a "mange" >50% de la taille d'entree
# A3D-12 : garde-fou explicite sur le VOLUME clos (pas seulement l'etendue de
# la bbox ci-dessus) — refuse tout remesh qui perd plus de 10 % du volume
# clos d'entree (voir `_mesh_volume`/`_remesh_result_acceptable`). Complete le
# garde-fou d'etendue (`VOXEL_REMESH_MIN_EXTENT_RATIO`, deja plus permissif a
# 50 %) : un ilot peut perdre peu de DIAGONALE de bbox tout en perdant
# beaucoup de volume interne (paroi amincie de l'interieur) — l'inverse est
# vrai aussi (voir rapport de tache) : les deux verifications sont
# complementaires, jamais redondantes.
VOXEL_REMESH_MAX_VOLUME_LOSS_RATIO = 0.10
DECIMATE_MAX_ITERATIONS = 6
TURNTABLE_SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "turntable.py")

# ---------------------------------------------------------------------------
# Bandes de teinte reservees (docs/assets/ASSET_PLAN.md §3.4 : "aucune teinte
# h in [300 deg, 355 deg] U [105 deg, 145 deg] avec C > 0,08" — surbrillance
# ennemie/alliee reservee par Cartoon.gd). CANDIDATE_KINDS n'est fait QUE de
# couleurs de palette fixes (toonkit.palette(kind)) : cette bande est donc une
# garantie STRUCTURELLE (verifiee une fois, au premier appel de
# `nearest_kind`, voir `_validate_candidate_kinds_reserved_bands`) plutot
# qu'un filtre par echantillon — si un futur tokens.json faisait deriver un
# kind connu dans la bande reservee, ce serait une erreur DURE a corriger
# dans la palette, jamais une teinte reservee exportee en silence. Chroma
# approximee en HSV (saturation * valeur) — pas une vraie chroma
# perceptuelle (Lab/OKLCH), documentee comme telle : suffisante pour ce
# garde-fou binaire "haute-chroma dans la bande interdite".
RESERVED_HUE_BANDS_DEG = [(300.0, 355.0), (105.0, 145.0)]
RESERVED_HUE_CHROMA_THRESHOLD = 0.08

# Zone (canal A de toonkit.bake_vertex_masks, §7.9 : 0 base / 0.33 accent-
# verre / 0.66 metal / 1 decalque) pour le VIEUX vocabulaire de kinds peints
# (Cartoon._PAINTED) que ce script utilise encore (voir CANDIDATE_KINDS) —
# toonkit.ZONE_BY_KIND ne connait que les 4 slots v3 (base/accent/metal/
# sign) : ce module choisit ici, explicitement, le slot v3 le plus proche de
# chaque kind peint pour que le canal A du masque unifie porte une
# information reelle plutot que de retomber silencieusement sur 0 partout
# (voir `restyle_materials`, qui pose cette valeur en ecrasant
# `mat["toonkit_kind"]` APRES `toonkit.toon_material`, sans toucher au preset
# PBR d'apercu choisi par le kind peint lui-meme).
_ZONE_KIND_FOR_PAINTED = {
	"painted_metal": "metal", "rust": "metal", "corrugated_metal": "metal", "ship_deck": "metal",
	"container_paint": "base", "wood_planks": "base", "sand_dirt": "base", "cracked_concrete": "base",
	"asphalt": "base", "rubber_tire": "base",
	"dirty_glass": "glass",
}

# Classe de biseau/LOD (toonkit.BEVEL_CLASSES/toonkit.LOD_CLASSES, docs/
# STYLE_BIBLE.md §6.6) par defaut pour chaque famille --family de ce script —
# `--bevel-class` reste prioritaire s'il est fourni explicitement (un meme
# --family peut recouvrir plusieurs classes reelles, ex. "props_large" va du
# petit conteneur au repere ajoure : voir docs/assets/ASSET_PLAN.md §4).
DEFAULT_BEVEL_CLASS_BY_FAMILY = {
	"heads": "character",
	"characters": "character",
	"weapons": "weapon_fp",
	"props_small": "prop_small",
	"props_large": "prop_container",
	"props": "prop_crate",
}


# ---------------------------------------------------------------------------
# Contexte d'operateur — reimplemente ici (pas importe de toonkit._apply_modifier,
# prive a ce module : ce fichier ne doit dependre que de l'API PUBLIQUE de
# toonkit, voir docs/3D_PIPELINE.md §2).
# ---------------------------------------------------------------------------

def _apply_modifier(obj, modifier) -> None:
	"""Applique `modifier` sur `obj` et GARANTIT qu'il n'est plus dans la pile
	au retour — rattrape TROIS pieges reels de `bpy.ops.object.modifier_apply`
	(constates par sondage, voir rapport de verification de tache, tous les
	trois reproduits hors de tout pipeline IA, sur un simple cube) :
	1) si `modifier` n'est pas EN PREMIER dans la pile (typiquement un
	   modificateur d'une tentative precedente encore present — cas de
	   `_voxel_remesh` sur plusieurs tentatives), l'operateur l'applique quand
	   meme (avertissement Blender « Applied modifier was not first, result
	   may not be as expected ») MAIS ne bake alors PAS que l'effet de CE
	   modificateur : il bake l'effet COMBINE de toute la pile jusqu'a lui
	   inclus, puis ne retire QUE lui — les modificateurs precedents restent
	   empiles, non retires, alors que leur effet est deja bake dans la mesh
	   de base. Ils sont donc REJOUES une seconde fois en silence a l'export
	   (`toonkit.export_glb(..., export_apply=True)` reevalue la pile
	   restante), corrompant la geometrie APRES que `final_tris` a ete mesure
	   et valide contre le budget (mesure : 4x la subdivision attendue sur un
	   cas minimal a deux modificateurs SUBSURF). On deplace donc TOUJOURS
	   `modifier` en tete de pile avant de l'appliquer, pour ne jamais se
	   retrouver dans ce cas — quels que soient les modificateurs deja
	   presents.
	2) l'operateur peut renvoyer `{'CANCELLED'}` sans lever d'exception : on
	   verifie le resultat et on echoue fort (jamais un modificateur laisse
	   silencieusement non applique dans la pile jusqu'a l'export).
	3) MEME en premiere position, l'operateur peut renvoyer `{'FINISHED'}`
	   SANS retirer le modificateur de la pile ET sans changer la geometrie —
	   un cas degenere DEJA documente cote appelant (voir `_voxel_remesh` :
	   "a CERTAINES tailles de voxel precises... la geometrie ressort
	   STRICTEMENT IDENTIQUE a l'entree"), reproduit ici avec un Remesh Voxel
	   sur un cube troue (`polys_before == polys_after`, modificateur present
	   des deux cotes). Comme la geometrie n'a alors reellement PAS change, il
	   n'y a rien a perdre a retirer nous-memes ce modificateur devenu un
	   pur no-op — c'est le SEUL cas ou cette fonction retire un modificateur
	   sans qu'il ait ete "applique" au sens strict ; l'appelant (`_voxel_remesh`)
	   detecte cette absence de progres via `_is_watertight` et retente avec
	   une autre taille de voxel. Si en revanche la geometrie a bel et bien
	   change (verts/polys differents) alors que le modificateur reste
	   empile — un echec partiel jamais observe mais distinct du cas ci-dessus
	   — on echoue fort plutot que de deviner.
	Post-condition garantie : `modifier` n'est jamais dans `obj.modifiers` au
	retour normal de cette fonction.

	A3D-15 : `name` est capture UNE SEULE FOIS, avant tout appel a
	`modifier_apply`, et reutilise partout ensuite — jamais `modifier.name`
	relu apres l'appel. Releve concret de tache (decimate_group_to_budget sur
	un maillage deja biseaute, cs_container_20 entre autres) : dans le cas
	NORMAL (non degenere) ou l'operateur retire reellement le modificateur de
	la pile, le wrapper Python `modifier` pointe alors sur de la memoire
	liberee cote C — la relire (`modifier.name`) n'importe pas toujours de
	facon fiable une `ReferenceError` propre (deja le cas attendu si Blender
	invalide bien le wrapper) : sur un maillage qui porte deja des attributs
	de couleur/des normales personnalisees (post-biseau, voir
	`toonkit.apply_stylekit_shading`), la memoire liberee peut deja avoir ete
	reutilisee au moment de cette lecture, et `modifier.name` renvoie alors des
	octets non-UTF8 (`UnicodeDecodeError` a la lecture de la chaine RNA) plutot
	que l'erreur attendue. Capturer `name` avant l'apply ecarte ce risque
	completement : on ne touche plus jamais `modifier` apres l'apply, sauf
	dans le SEUL cas ou il est confirme encore present dans la pile (cas
	degenere documente (3), ou rien n'a ete libere)."""
	name = modifier.name
	index = obj.modifiers.find(name)
	if index < 0:
		raise RuntimeError(f"ai_restyle: modificateur \"{name}\" introuvable sur \"{obj.name}\"")
	if index != 0:
		with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
			move_result = bpy.ops.object.modifier_move_to_index(modifier=name, index=0)
		if 'FINISHED' not in move_result:
			raise RuntimeError(
				f"ai_restyle: impossible de remonter \"{name}\" en tete de pile sur "
				f"\"{obj.name}\" ({move_result!r})")
	before = (len(obj.data.vertices), len(obj.data.polygons))
	with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
		apply_result = bpy.ops.object.modifier_apply(modifier=name)
	if 'FINISHED' not in apply_result:
		raise RuntimeError(
			f"ai_restyle: bpy.ops.object.modifier_apply a echoue ({apply_result!r}) pour "
			f"\"{name}\" sur \"{obj.name}\"")
	if obj.modifiers.find(name) >= 0:
		after = (len(obj.data.vertices), len(obj.data.polygons))
		if after != before:
			raise RuntimeError(
				f"ai_restyle: \"{name}\" a modifie la geometrie de \"{obj.name}\" "
				f"({before} -> {after} verts/polys) mais est reste empile apres application "
				"(echec partiel, jamais silencieux)")
		obj.modifiers.remove(modifier)  # cas degenere documente (3) : no-op reel, rien a perdre


def _bbox_diagonal(obj) -> float:
	"""Diagonale de la bbox en espace LOCAL (objet) — `obj.bound_box` est
	DEJA en coordonnees locales (verifie par sondage, voir rapport de tache),
	PAS en monde : c'est cet espace que `bmesh`/les modifieurs (Decimate,
	Remesh) utilisent reellement pour leurs propres seuils/tailles. Un
	`matrix_world @` ici donnerait un seuil de fusion/une taille de voxel
	calibres sur la MAUVAISE echelle des qu'un import externe laisse un scale
	non applique (cas typique d'un GLB IA — voir `_needs_early_scale_fix` :
	c'est precisement pour NE JAMAIS se retrouver dans ce cas que le scale
	est baked TOT quand il ne vaut pas deja l'identite)."""
	corners = [Vector(c) for c in obj.bound_box]
	mins = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
	maxs = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
	return (maxs - mins).length


def _needs_early_scale_fix(obj, tol: float = 1e-5) -> bool:
	"""True si `obj` porte encore un scale/rotation non resolu (cas typique
	d'un GLB IA dont le node glTF garde un TRS que l'import Blender reporte
	tel quel sur l'objet, voir fixture 3 du rapport de tache) — SEULS le
	scale et la rotation affectent la taille de voxel choisie par
	`_voxel_remesh` (base sur `_bbox_diagonal`, invariante par translation) ;
	une simple location non nulle n'a donc pas besoin d'etre corrigee ICI.
	Sert a n'appeler `toonkit.apply_transforms` TOT (avant tout remesh, voir
	plus bas) QUE quand c'est reellement necessaire : sondage (rapport de
	tache) — appeler cet operateur PLUS TOT que necessaire (y compris sur un
	objet qui n'a qu'une location a corriger) perturbe le Remesh Voxel plus
	loin dans le pipeline, un effet de bord constate mais non explique par
	ailleurs ; un objet qui n'a qu'une location a corriger passe donc
	uniquement par l'appel final (fin de `restyle`), jamais par celui-ci."""
	scale_ok = all(abs(s - 1.0) < tol for s in obj.scale)
	rotation_ok = all(abs(r) < tol for r in obj.rotation_euler)
	return not (scale_ok and rotation_ok)


# ---------------------------------------------------------------------------
# Couleur — sRGB (telle que renvoyee par toonkit.palette()/Image.pixels : sondage
# confirme que .pixels ne linearise PAS — memes valeurs avant/apres un aller-
# retour PNG sur disque, voir rapport de tache) -> Lab D65, pour classer un
# echantillon par distance perceptuelle CIE76. Sert UNIQUEMENT a CHOISIR le
# kind le plus proche ; la couleur reellement exportee est toujours
# `toonkit.palette(kind)` telle quelle (jamais la couleur echantillonnee),
# donc la couleur moyenne du slot de sortie colle EXACTEMENT a la palette
# (delta E = 0 par construction) — voir `restyle_materials`.
# ---------------------------------------------------------------------------

def _srgb_to_linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _rgb_to_lab(rgb) -> tuple:
	r, g, b = (_srgb_to_linear(max(0.0, min(1.0, c))) for c in rgb[:3])
	x = r * 0.4124564 + g * 0.3575761 + b * 0.1804375
	y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750
	z = r * 0.0193339 + g * 0.1191920 + b * 0.9503041
	xn, yn, zn = 0.95047, 1.0, 1.08883

	def f(t):
		return t ** (1.0 / 3.0) if t > 0.008856 else (7.787 * t + 16.0 / 116.0)

	fx, fy, fz = f(x / xn), f(y / yn), f(z / zn)
	return (116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


def _delta_e(lab1: tuple, lab2: tuple) -> float:
	return math.sqrt(sum((a - b) ** 2 for a, b in zip(lab1, lab2)))


def _hue_chroma_deg(rgb) -> tuple:
	"""(teinte en degres 0-360, chroma approximee HSV) — voir le commentaire
	au-dessus de RESERVED_HUE_BANDS_DEG pour ce que "chroma" veut dire ici."""
	h, s, v = colorsys.rgb_to_hsv(max(0.0, min(1.0, rgb[0])), max(0.0, min(1.0, rgb[1])),
		max(0.0, min(1.0, rgb[2])))
	return (h * 360.0, s * v)


def _in_reserved_band(rgb) -> bool:
	"""True si `rgb` tombe dans une bande de teinte reservee a haute chroma
	(docs/assets/ASSET_PLAN.md §3.4) — voir RESERVED_HUE_BANDS_DEG."""
	hue_deg, chroma = _hue_chroma_deg(rgb)
	if chroma <= RESERVED_HUE_CHROMA_THRESHOLD:
		return False
	return any(lo <= hue_deg <= hi for lo, hi in RESERVED_HUE_BANDS_DEG)


_candidate_kinds_validated = False


def _validate_candidate_kinds_reserved_bands() -> None:
	"""Garde-fou DUR (une seule fois, memoize) : aucun kind de CANDIDATE_KINDS
	ne doit avoir une palette (toonkit.palette(kind)) dans une bande de teinte
	reservee — voir le commentaire de RESERVED_HUE_BANDS_DEG. Une violation ne
	peut venir que d'un futur changement de docs/style/tokens.json : erreur
	dure immediate plutot qu'un asset exporte avec une teinte reservee en
	silence des mois plus tard."""
	global _candidate_kinds_validated
	if _candidate_kinds_validated:
		return
	offenders = [k for k in CANDIDATE_KINDS if _in_reserved_band(toonkit.palette(k))]
	if offenders:
		raise RuntimeError(
			f"ai_restyle: kind(s) de palette dans une bande de teinte reservee "
			f"(docs/assets/ASSET_PLAN.md §3.4) : {offenders} — corriger docs/style/tokens.json, "
			"jamais cette verification")
	_candidate_kinds_validated = True


def nearest_kind(rgb) -> tuple:
	"""Kind de CANDIDATE_KINDS dont `toonkit.palette(kind)` est le plus proche
	(CIE76, Lab D65) de `rgb` (0..1, sRGB) — renvoie (kind, delta_e). Verifie
	(une fois) qu'aucun candidat ne viole une bande de teinte reservee avant
	de choisir (voir `_validate_candidate_kinds_reserved_bands`)."""
	_validate_candidate_kinds_reserved_bands()
	sample_lab = _rgb_to_lab(rgb)
	best_kind, best_delta = CANDIDATE_KINDS[0], None
	for kind in CANDIDATE_KINDS:
		delta = _delta_e(sample_lab, _rgb_to_lab(toonkit.palette(kind)))
		if best_delta is None or delta < best_delta:
			best_kind, best_delta = kind, delta
	return best_kind, best_delta


# ---------------------------------------------------------------------------
# Etape 1 — import (fusionne en un seul objet, comme un appel a toonkit.join)
# ---------------------------------------------------------------------------

def import_asset(path: str) -> list:
	ext = os.path.splitext(path)[1].lower()
	if ext in (".glb", ".gltf"):
		bpy.ops.import_scene.gltf(filepath=path)
	elif ext == ".fbx":
		bpy.ops.import_scene.fbx(filepath=path)
	elif ext == ".obj":
		bpy.ops.wm.obj_import(filepath=path)
	else:
		raise ValueError(f"ai_restyle: extension non supportee: {ext!r} (attendu .glb/.gltf/.fbx/.obj)")
	return [o for o in bpy.context.scene.objects if o.type == 'MESH']


# ---------------------------------------------------------------------------
# Etape 2 — nettoyage : fusion de sommets + suppression des morceaux isoles
# ---------------------------------------------------------------------------

def merge_by_distance(obj, ratio: float = MERGE_DIST_RATIO) -> int:
	"""Fusionne les sommets quasi confondus (bruit de triangulation IA
	typique) — distance RELATIVE a la diagonale de bbox, jamais un epsilon
	absolu (un petit prop et une skin de plusieurs metres n'ont pas la meme
	echelle). Renvoie le nombre de sommets retires."""
	diag = max(_bbox_diagonal(obj), 1e-6)
	dist = max(1e-6, diag * ratio)
	me = obj.data
	before = len(me.vertices)
	bm = bmesh.new()
	bm.from_mesh(me)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
	bm.to_mesh(me)
	bm.free()
	me.update()
	return before - len(me.vertices)


_SLIVER_AREA_RATIO = 0.05  # une face >= 20x plus petite que la plus grande sur la meme arete est un eclat degenere


def _remove_nonmanifold_slivers(bm: "bmesh.types.BMesh", bad_edges: list, strict: bool = True) -> int:
	"""Sur chaque arete de `bad_edges` (>= 3 faces liees, apres deduplication
	deja tentee par `_remove_duplicate_faces` — voir `_fill_holes`), retire
	les faces les plus PETITES jusqu'a n'en garder que 2 (les deux plus
	grandes, les moins destructrices a garder). A3D-15 : releve concret de
	tache (wpn_faucheur) — un maillage Tripo brut peut porter, en plus d'un
	doublon exact (voir `_remove_duplicate_faces`), un ou plusieurs triangles
	nettement plus petits (artefact de (de)simplification IA, jamais une
	piece reelle) qui se greffent sur une arete par ailleurs normale — les
	retirer est strictement moins destructeur que d'echouer tout le pipeline
	sur une piece par ailleurs correcte.

	`strict=True` (defaut, utilise par le nettoyage GLOBAL preventif de
	`repair_nonmanifold_edges`, avant meme de savoir si une coupe va toucher
	la zone) : ne retire une face que si elle est CLAIREMENT un eclat degenere
	(aire >= 20x plus petite que la plus grande face liee, `_SLIVER_AREA_RATIO`)
	— une arete dont les faces en exces restent comparables en aire n'est PAS
	touchee, laissee telle quelle (rien a gagner a nettoyer par precaution une
	zone qu'aucune coupe ne visitera peut-etre jamais).

	`strict=False` (dernier recours LOCAL de `_fill_holes`, juste avant
	d'echouer fort sur une coupe precise) : aucun seuil — garde TOUJOURS les 2
	faces de plus grande aire, quel que soit l'ecart avec les autres. A ce
	stade, l'arete est deja confirmee non-manifold sur une coupe reelle (une
	surface manifold n'a jamais 3+ faces sur une arete) : il n'existe pas de
	"bonne" resolution qui garderait tout, et garder les deux plus grandes
	faces (celles qui preservent le plus de silhouette) est la moins
	destructrice des options reellement disponibles — strictement preferable
	a un echec dur du pipeline sur une piece par ailleurs correcte (releve
	concret : wpn_faucheur, un ecart de seulement ~7x, sous le seuil strict
	mais bien au-dessus d'un vrai doublon).

	Renvoie le nombre de faces retirees (0 si aucune arete ne qualifie en mode
	strict, ou si aucune arete n'a plus de 2 faces)."""
	to_delete = set()
	for e in bad_edges:
		linked = [f for f in e.link_faces if f not in to_delete]
		while len(linked) > 2:
			areas = [(f.calc_area(), f) for f in linked]
			areas.sort(key=lambda t: t[0])
			smallest_area, smallest_face = areas[0]
			largest_area = areas[-1][0]
			if strict and (largest_area <= 0 or smallest_area > _SLIVER_AREA_RATIO * largest_area):
				break  # ni l'un ni l'autre n'est un eclat clair : on laisse cette arete telle quelle
			to_delete.add(smallest_face)
			linked = [f for f in linked if f is not smallest_face]
	if to_delete:
		bmesh.ops.delete(bm, geom=list(to_delete), context='FACES')
	return len(to_delete)


def _remove_duplicate_faces(bm: "bmesh.types.BMesh") -> int:
	"""Supprime toute face qui partage EXACTEMENT le meme ensemble de sommets
	qu'une face deja vue (ne garde que la premiere) — bruit de generation IA
	distinct du "bruit de triangulation" que `merge_by_distance` resout deja
	(sommets QUASI confondus, fusionnes en un seul) : ICI, les sommets sont
	DEJA les memes (identite d'index, generalement APRES un `merge_by_distance`
	qui a fusionne des sommets quasi confondus en sommets partages), mais DEUX
	FACES DISTINCTES referencent ce meme ensemble — un vrai doublon de
	geometrie (deux triangles superposes), jamais detecte ni corrige par
	`bmesh.ops.remove_doubles` (qui ne fusionne QUE des sommets, jamais des
	faces). A3D-15 : releve concret de tache — une arete "partagee par >= 3
	faces" (non-manifold) sur un maillage Tripo brut, avant meme toute
	separation de piece, vient dans plusieurs cas observes d'une PAIRE de
	faces EXACTEMENT dupliquees (memes 3 sommets, meme aire) plutot que d'une
	geometrie reellement ambigue a 3+ faces distinctes — un defaut de
	generation ponctuel (constate y compris loin de toute piece separee,
	wpn_faucheur/cs_deck_crane) que ce nettoyage elimine a la source, avant
	que la palette/l'etancheite/la separation de pieces n'aient a y faire
	face. Fonction PURE bmesh (testable isolement) : opere sur `bm` deja
	charge, ne touche ni import ni export. Renvoie le nombre de faces
	retirees."""
	seen = {}
	dupes = []
	for f in bm.faces:
		key = frozenset(v.index for v in f.verts)
		if key in seen:
			dupes.append(f)
		else:
			seen[key] = f
	if dupes:
		bmesh.ops.delete(bm, geom=dupes, context='FACES')
	return len(dupes)


def remove_duplicate_faces(obj) -> int:
	"""Wrapper mesh-level de `_remove_duplicate_faces` (memes conventions
	d'entree/sortie que `merge_by_distance`/`remove_isolated_islands` : charge
	`obj.data` dans un bmesh de travail, applique, reecrit). Renvoie le nombre
	de faces retirees."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	removed = _remove_duplicate_faces(bm)
	bm.to_mesh(me)
	bm.free()
	me.update()
	return removed


def repair_nonmanifold_edges(obj) -> dict:
	"""Nettoyage best-effort des aretes non-manifold (>= 3 faces liees) d'un
	maillage BRUT, AVANT tout le reste du pipeline (palette/etancheite/
	decimation/separation) — deux passes dans l'ordre, JAMAIS un blocage dur
	ici (nettoyage preventif ; check_asset.py::CHK reste le juge final en aval
	si une arete resiste aux deux passes, comme pour tout autre defaut de
	maillage brut non corrige) :
	1. `_remove_duplicate_faces` (deux triangles EXACTEMENT superposes).
	2. `_remove_nonmanifold_slivers` (eclat degenere greffe sur une arete par
	   ailleurs normale, distinct d'un doublon exact).
	A3D-15 : releve concret de tache (cs_deck_crane, vague 1) — 4 aretes
	non-manifold sur le CORPS ENTIER, jamais issues d'une separation de piece
	(`separate_parts`/`_fill_holes` ne s'appliquent qu'aux armes) : ce meme
	defaut de generation IA (doublons/eclats) touche aussi les meshes qui ne
	passent jamais par une separation de piece — ce nettoyage s'applique donc
	ICI, tot dans `restyle()`, a TOUT asset, pas seulement aux armes.
	Renvoie {"duplicate_faces": int, "sliver_faces": int,
	"remaining_nonmanifold_edges": int}."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	dupes = _remove_duplicate_faces(bm)
	bad = [e for e in bm.edges if len(e.link_faces) >= 3]
	slivers = _remove_nonmanifold_slivers(bm, bad) if bad else 0
	if slivers:
		bad = [e for e in bm.edges if len(e.link_faces) >= 3]
	bm.to_mesh(me)
	bm.free()
	me.update()
	return {
		"duplicate_faces": dupes,
		"sliver_faces": slivers,
		"remaining_nonmanifold_edges": len(bad),
	}


def _face_islands(bm: "bmesh.types.BMesh") -> list:
	"""Composantes connexes par adjacence d'arete (flood fill) — un morceau
	isole IA (fragment fantome, plaque decrochee du corps principal) n'a
	AUCUNE face liee au reste du maillage."""
	bm.faces.ensure_lookup_table()
	seen = set()
	islands = []
	for seed in bm.faces:
		if seed.index in seen:
			continue
		stack = [seed]
		seen.add(seed.index)
		comp = []
		while stack:
			f = stack.pop()
			comp.append(f)
			for e in f.edges:
				for nf in e.link_faces:
					if nf.index not in seen:
						seen.add(nf.index)
						stack.append(nf)
		islands.append(comp)
	return islands


def remove_isolated_islands(obj, gap_tolerance: float = ISLAND_GAP_TOLERANCE_M) -> int:
	"""Supprime tout CLUSTER d'ilots (`_cluster_islands_by_gap` : ilots
	topologiquement disjoints regroupes par PROXIMITE SPATIALE, jamais par
	nombre de faces, voir le commentaire de ISLAND_GAP_TOLERANCE_M) sauf le
	plus gros cluster (par nombre total de faces) — garde TOUJOURS ce dernier,
	meme s'il ne represente qu'une petite fraction du maillage (cas degenere
	jamais rencontre mais a ne pas planter dessus). A3D-15 : remplace l'ancien
	seuil par RATIO/ABSOLU de nombre de faces (`ISLAND_MIN_FACE_RATIO`/
	`ISLAND_MIN_FACE_ABSOLUTE`, retire) qui jetait a tort des assemblages
	multi-pieces legitimes (mat+cabine+fleche, treillis en plusieurs jambes)
	des lors qu'aucun de leurs ilots n'etait individuellement le plus gros.
	Renvoie le nombre de faces retirees."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	islands = _face_islands(bm)
	removed = 0
	if len(islands) > 1:
		clusters = _cluster_islands_by_gap(islands, gap_tolerance)
		if len(clusters) > 1:
			clusters.sort(key=lambda cl: sum(len(comp) for comp in cl), reverse=True)
			to_delete = [f for cluster in clusters[1:] for comp in cluster for f in comp]
			if to_delete:
				removed = len(to_delete)
				bmesh.ops.delete(bm, geom=to_delete, context='FACES')
				orphan_verts = [v for v in bm.verts if not v.link_faces]
				if orphan_verts:
					bmesh.ops.delete(bm, geom=orphan_verts, context='VERTS')
	bm.to_mesh(me)
	bm.free()
	me.update()
	return removed


# ---------------------------------------------------------------------------
# Etape 3 — transfert de palette : chaque materiau importe (texture IA ou
# couleur plate) -> le kind connu de Cartoon.gd perceptuellement le plus
# proche, et UNIQUEMENT sa couleur de palette (jamais la texture IA, jetee).
# ---------------------------------------------------------------------------

def _average_image_color(image: "bpy.types.Image") -> tuple:
	"""Teinte moyenne d'une texture IA (Base Color bakee) — un pas de foulee
	fixe suffit largement (on n'en tire qu'une classification de kind, pas un
	rendu), et evite de lire des millions de floats pour une texture 2-4k."""
	w, h = image.size
	if w <= 0 or h <= 0:
		return (0.7, 0.7, 0.7, 1.0)
	channels = image.channels or 4
	pixels = list(image.pixels)
	total_px = w * h
	stride = max(1, total_px // 4096)
	r = g = b = 0.0
	count = 0
	for i in range(0, total_px, stride):
		base = i * channels
		alpha = pixels[base + 3] if channels >= 4 else 1.0
		if alpha < 0.05:
			continue  # pixel transparent (fond du bake IA) : ne compte pas dans la moyenne
		r += pixels[base]
		g += pixels[base + 1] if channels >= 2 else pixels[base]
		b += pixels[base + 2] if channels >= 3 else pixels[base]
		count += 1
	if count == 0:
		return (0.7, 0.7, 0.7, 1.0)
	return (r / count, g / count, b / count, 1.0)


def _read_flat_color(mat: "bpy.types.Material") -> tuple:
	"""Couleur moyenne « telle qu'on la voit » d'un materiau importe — lit la
	texture Base Color si l'IA en a bake une (cas courant, verifie par
	sondage sur un aller-retour export/import glTF : Base Color -> Image
	Texture directement, voir rapport de tache), sinon la couleur plate.
	Ne suit PAS le montage « Mix vertex-color x albedo » de
	turntable.py::_read_albedo : un GLB brut sorti d'un service image/texte
	-> 3D n'a jamais de vertex colors bakees en entree de CE script (elles
	n'existent qu'APRES lui, voir bake_vertex_ao/curvature_edge_mask) — rien
	a demeler ici."""
	if mat is None:
		return (0.7, 0.7, 0.7, 1.0)
	if not mat.use_nodes or mat.node_tree is None:
		return tuple(mat.diffuse_color)
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	if bsdf is None or "Base Color" not in bsdf.inputs:
		return tuple(mat.diffuse_color)
	socket = bsdf.inputs["Base Color"]
	if not socket.is_linked:
		c = socket.default_value
		return (c[0], c[1], c[2], c[3])
	src = socket.links[0].from_node
	if src.type == 'TEX_IMAGE' and src.image is not None:
		return _average_image_color(src.image)
	return tuple(mat.diffuse_color)


def _material_image_node(mat: "bpy.types.Material"):
	"""Image branchee sur Base Color de `mat` (comme `_read_flat_color`), ou
	None si `mat` n'a pas de texture (couleur plate/materiau absent) — sert a
	decider, PAR FACE, si on echantillonne l'image a l'UV de la face ou si on
	retombe sur la couleur plate/moyenne (voir `restyle_materials`)."""
	if mat is None or not mat.use_nodes or mat.node_tree is None:
		return None
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	if bsdf is None or "Base Color" not in bsdf.inputs:
		return None
	socket = bsdf.inputs["Base Color"]
	if not socket.is_linked:
		return None
	src = socket.links[0].from_node
	if src.type == 'TEX_IMAGE' and src.image is not None:
		return src.image
	return None


def _image_pixel_cache(image: "bpy.types.Image") -> tuple:
	"""(pixels, largeur, hauteur, canaux) — `list(image.pixels)` UNE SEULE
	fois par image (couteux sur une texture 2-4k : des millions de floats),
	puis reutilise pour un echantillonnage PAR FACE en O(1) (voir
	`_sample_image_at_uv`). Contrairement a `_average_image_color` (qui
	n'avait besoin que d'une moyenne globale et pouvait se contenter d'un pas
	de foulee), la quantification PAR FACE (A3D-12) a besoin d'un acces
	aleatoire reel a l'image entiere."""
	w, h = image.size
	channels = image.channels or 4
	return (list(image.pixels), w, h, channels)


def _sample_image_at_uv(cache: tuple, u: float, v: float) -> tuple:
	"""Couleur (RGBA, 0..1) au texel le plus proche de l'UV (`u`, `v`) —
	`image.pixels` est range ligne par ligne en partant du BAS de l'image
	(convention Blender, coherente avec l'origine (0,0) en bas-gauche des UV :
	verifie par sondage, voir rapport de tache — v croissant vers le haut des
	deux cotes, aucun retournement necessaire ici)."""
	pixels, w, h, channels = cache
	if w <= 0 or h <= 0:
		return (0.7, 0.7, 0.7, 1.0)
	x = min(w - 1, max(0, int(u * w)))
	y = min(h - 1, max(0, int(v * h)))
	base = (y * w + x) * channels
	r = pixels[base]
	g = pixels[base + 1] if channels >= 2 else r
	b = pixels[base + 2] if channels >= 3 else r
	a = pixels[base + 3] if channels >= 4 else 1.0
	return (r, g, b, a)


def _face_uv_centroid(me: "bpy.types.Mesh", poly, uv_layer) -> tuple:
	"""UV moyen (u, v) des coins de `poly` sur `uv_layer` — un centroide UV
	suffit a classer la face (on ne reconstruit pas un bake par texel, juste
	un point de classification par face, voir `restyle_materials`)."""
	n = len(poly.loop_indices)
	us = vs = 0.0
	for li in poly.loop_indices:
		uv = uv_layer.data[li].uv
		us += uv.x
		vs += uv.y
	return (us / n, vs / n)


def restyle_materials(obj, report_slots: list) -> None:
	"""Remplace TOUS les materiaux de `obj` par des `toonkit.toon_material()`
	nommes d'apres un kind connu de Cartoon.gd (CANDIDATE_KINDS) — jamais la
	texture/couleur IA d'origine. Quantification **PAR FACE** (A3D-12,
	docs/assets/ASSET_PLAN.md §0/§2) : une texture Tripo bakee peut peindre
	PLUSIEURS couleurs de piece (crosse bois, canon acier, chargeur orange...)
	sur un SEUL materiau/slot — echantillonner la moyenne du materiau entier
	(comportement A3D-07) les aurait toutes fondues en un seul kind. Ici,
	chaque FACE d'un materiau texture est echantillonnee a son propre
	centroide UV (`_face_uv_centroid`/`_sample_image_at_uv`) et classee
	independamment (`nearest_kind`) ; un materiau SANS texture (couleur plate)
	ou SANS UV (repli sur la moyenne globale de l'image, voir
	`_average_image_color`) garde une seule couleur pour toutes ses faces,
	comme avant. Deux faces (du meme slot d'origine ou de slots differents)
	qui quantifient vers le MEME kind partagent UN seul materiau de sortie
	(pas de doublon « rust.001 »). La couleur du materiau de sortie est
	TOUJOURS `toonkit.palette(kind)` telle quelle : delta E slot -> palette
	exporte = 0 par construction, quel que soit l'ecart mesure a l'echantillon
	IA d'origine — c'est la definition meme du « transfert » (docs/research/
	06_ai_3d_pipeline.md §A6.3). `mat["toonkit_kind"]` est ensuite ecrase par
	le slot v3 le plus proche (`_ZONE_KIND_FOR_PAINTED`) pour que le canal A
	(zone) de `toonkit.bake_vertex_masks` porte une vraie information — sans
	toucher au preset PBR d'apercu (roughness/metallic) du kind peint
	d'origine, pose par `toonkit.toon_material(kind, ..., kind=kind)` juste
	avant. `report_slots` recoit un agrégat (materiau source, kind assigne,
	nombre de faces, delta E moyen de l'echantillon a CE kind) par paire
	(materiau source, kind) reellement observee — plus riche qu'un rapport
	par slot d'origine puisqu'un seul slot peut desormais produire plusieurs
	kinds."""
	me = obj.data
	original_materials = list(me.materials) or [None]
	uv_layer = me.uv_layers.active

	# Renomme IMMEDIATEMENT chaque materiau d'origine sous un nom garanti
	# unique — un GLB d'entree (rare mais possible : un asset deja restyle une
	# fois, ou un nommage manuel coincidant) peut porter un materiau nomme
	# EXACTEMENT comme un kind connu (ex. "rust") ; sans ce renommage,
	# `bpy.data.materials.new(kind)` plus bas se ferait reattribuer
	# "rust.001" par Blender (collision de nom), et le nom FINAL du materiau
	# de sortie ne serait alors plus le kind attendu (`assigned_kinds` echoue
	# le garde-fou "hors vocabulaire connu" plus loin dans `restyle`, sur un
	# GLB par ailleurs parfaitement valide). Les data-blocks renommes
	# deviennent orphelins des que `me.materials.clear()` s'execute plus bas
	# (plus aucun utilisateur) : purges en fin de fonction, comme les images.
	original_names = [m.name if m is not None else "__none__" for m in original_materials]
	for i, m in enumerate(original_materials):
		if m is not None:
			m.name = f"__ai_restyle_src_{i}_{m.name}"

	image_caches = {}       # nom d'image -> cache (_image_pixel_cache)
	flat_colors = {}        # index materiau -> couleur plate/moyenne (calculee au besoin, une fois)
	kind_materials = {}     # kind -> nouveau bpy.types.Material (dedoublonne)
	new_materials = []
	new_indices = [0] * len(me.polygons)
	aggregates = {}         # (nom materiau source, kind) -> {"faces": int, "delta_e_sum": float}

	def _flat_color_for(old_index: int, mat) -> tuple:
		if old_index not in flat_colors:
			flat_colors[old_index] = _read_flat_color(mat)
		return flat_colors[old_index]

	for poly in me.polygons:
		old_index = poly.material_index
		mat = original_materials[old_index] if 0 <= old_index < len(original_materials) else None
		image = _material_image_node(mat)
		if image is not None and uv_layer is not None:
			if image.name not in image_caches:
				image_caches[image.name] = _image_pixel_cache(image)
			u, v = _face_uv_centroid(me, poly, uv_layer)
			sample = _sample_image_at_uv(image_caches[image.name], u, v)
		elif image is not None:
			# Texture presente mais aucune UV sur le maillage : repli sur la
			# moyenne globale de l'image (une seule couleur pour tout le
			# slot, comme A3D-07) — pas de centroide UV possible sans UV map.
			sample = _average_image_color(image)
		else:
			sample = _flat_color_for(old_index, mat)

		kind, delta_e = nearest_kind(sample)
		mat_name = original_names[old_index] if 0 <= old_index < len(original_names) else "__none__"
		agg = aggregates.setdefault((mat_name, kind), {"faces": 0, "delta_e_sum": 0.0})
		agg["faces"] += 1
		agg["delta_e_sum"] += delta_e

		if kind not in kind_materials:
			new_mat = toonkit.toon_material(kind, toonkit.palette(kind), kind=kind)
			new_mat["toonkit_kind"] = _ZONE_KIND_FOR_PAINTED.get(kind, "base")
			kind_materials[kind] = new_mat
			new_materials.append(new_mat)
		new_indices[poly.index] = new_materials.index(kind_materials[kind])

	me.materials.clear()
	for m in new_materials:
		me.materials.append(m)
	for poly, idx in zip(me.polygons, new_indices):
		poly.material_index = idx
	me.update()

	for (mat_name, kind), agg in sorted(aggregates.items()):
		report_slots.append({
			"original_material": mat_name,
			"assigned_kind": kind,
			"face_count": agg["faces"],
			"avg_delta_e_sample_to_kind": round(agg["delta_e_sum"] / agg["faces"], 3),
		})

	# Aucune image ne doit fuiter dans la sortie (docs/assets/ASSET_PLAN.md
	# §0 : "la texture Tripo est jetee") : purge des data-blocks Image devenus
	# orphelins maintenant que plus aucun materiau ne les reference (defensif
	# — l'exporteur glTF ne suit que le graphe de noeuds des materiaux
	# reellement assignes, donc une image orpheline ne serait de toute facon
	# jamais ecrite dans le .glb, mais la purger evite qu'elle traine dans
	# `bpy.data` pour le reste du pipeline, ex. un rapport ulterieur qui
	# listerait `bpy.data.images`).
	for img in list(bpy.data.images):
		if img.users == 0:
			bpy.data.images.remove(img)
	# Materiaux d'origine renommes (voir plus haut) devenus orphelins des que
	# `me.materials.clear()` ci-dessus les a detaches — meme hygiene que les
	# images : rien qui traine dans bpy.data au-dela de ce dont ce script a
	# encore besoin.
	for old_mat in original_materials:
		if old_mat is not None and old_mat.users == 0:
			bpy.data.materials.remove(old_mat)


# ---------------------------------------------------------------------------
# Etape 4 — etancheite : un maillage NON etanche casse la coque de contour
# inversee et le bake AO/courbure (docs/research/06_ai_3d_pipeline.md §A6.2).
#
# Remesher CHAQUE kind separement (bpy.ops.mesh.separate puis un Voxel par
# piece) a ete essaye et ABANDONNE (voir rapport de tache) : le Remesh Voxel
# scelle TOUJOURS sa piece en un solide clos independant, meme partie d'un
# maillage plus grand — deux pieces adjacentes remeshees chacune de son cote
# se retrouvent avec des parois internes qui SE RECOUVRENT a l'ancienne
# frontiere commune, produisant des aretes non-manifold (constate : 51 aretes
# a >= 3 faces apres rejointure sur une fixture de test a 2 materiaux
# trouee). Un remesh Voxel GLOBAL (l'objet entier en un seul passage) scelle
# lui TOUJOURS CHAQUE ilot connexe qu'il touche en un solide manifold valide
# (aucune arete de bord) — MAIS ceci est une garantie LOCALE, PAS globale : un
# ilot deja disjoint (debris IA trop gros pour `remove_isolated_islands`, ou
# tout simplement trop loin du corps principal pour que le voxel de taille
# choisie les recolle) ressort remeshe en un solide manifold INDEPENDANT,
# separe, jamais recolle au corps principal (confirme par sondage : deux
# solides distants de plusieurs metres restent deux solides distants de
# plusieurs metres apres un Remesh Voxel global — `_is_watertight` seule, qui
# ne compte que les aretes de bord, ne peut PAS le detecter puisque chaque
# solide est individuellement sans bord). `ensure_watertight` verifie donc
# EN PLUS, apres coup, qu'il ne reste qu'UN SEUL solide a plus de
# `DISCONNECTED_GAP_TOLERANCE_M` de distance (voir `_drop_floating_islands`,
# meme seuil que tools/blender/check_asset.py::FLOATING_GAP_TOLERANCE_M/CHK-16)
# et supprime les fragments flottants trouves — trace dans le rapport JSON
# (`watertight_fix["dropped_disconnected_faces"]`), jamais une perte
# silencieuse. Par ailleurs, quand un remesh est necessaire ET que l'objet
# porte plusieurs kinds, le Remesh Voxel aplatit les multi-materiaux
# (limitation DOCUMENTEE de l'operateur, voir manuel Blender) : on ne garde
# alors que le kind DOMINANT (le plus de faces d'origine) pour tout l'objet —
# un second compromis assume et trace dans le rapport JSON
# (`watertight_fix["collapsed_to"]`/`["dropped_kinds"]`), pas une perte
# silencieuse non plus.
# ---------------------------------------------------------------------------

def _is_watertight(me: "bpy.types.Mesh") -> bool:
	"""Aucune arete de bord — « etanche localement ». NE garantit PAS un
	solide UNIQUE : plusieurs solides clos disjoints (chacun sans bord)
	passent aussi ce test (verifie par sondage sur un cube + une sphere
	distants, voir rapport de verification de tache). Sert uniquement a
	decider si un trou reste a combler (`_voxel_remesh`) ; la connexite
	(un seul solide, ou des solides secondaires assez proches pour ne pas
	etre des fragments flottants) est verifiee SEPAREMENT, voir
	`_drop_floating_islands`."""
	bm = bmesh.new()
	bm.from_mesh(me)
	boundary = sum(1 for e in bm.edges if len(e.link_faces) == 1)
	bm.free()
	return boundary == 0


def _island_world_aabb(island_faces: list) -> tuple:
	"""Boite englobante (espace local — coherent avec `_bbox_diagonal` : voir
	sa docstring sur pourquoi le local est le bon espace ici, le scale/rotation
	etant deja bakes a ce stade du pipeline, voir `_needs_early_scale_fix`)
	d'un ilot de faces (`_face_islands`)."""
	verts = {v for f in island_faces for v in f.verts}
	xs = [v.co.x for v in verts]
	ys = [v.co.y for v in verts]
	zs = [v.co.z for v in verts]
	return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def _aabb_gap(mins_a: Vector, maxs_a: Vector, mins_b: Vector, maxs_b: Vector) -> float:
	"""Distance heuristique entre deux boites englobantes (0 si elles se
	chevauchent/se touchent sur les 3 axes) — meme formule que
	check_asset.py::_aabb_gap (CHK-16), pour que « flottant » veuille dire
	la meme chose ici et a la verification en aval."""
	dx = max(mins_a.x - maxs_b.x, mins_b.x - maxs_a.x, 0.0)
	dy = max(mins_a.y - maxs_b.y, mins_b.y - maxs_a.y, 0.0)
	dz = max(mins_a.z - maxs_b.z, mins_b.z - maxs_a.z, 0.0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)


def _cluster_islands_by_gap(islands: list, gap_tolerance: float) -> list:
	"""Regroupe des ilots de faces (`_face_islands`) en clusters connexes par
	PROXIMITE SPATIALE (gap de boite englobante <= `gap_tolerance`, meme
	mesure que `_aabb_gap`/CHK-16) — deux ilots topologiquement disjoints
	(aucune arete partagee) mais qui se touchent ou se frolent dans l'espace
	(joints d'un assemblage IA en plusieurs pieces jamais ressoudees par
	`merge_by_distance`, ex. un mat/une cabine/une fleche de grue, chacun un
	ilot separe) rejoignent alors le MEME cluster, par TRANSITIVITE (A proche
	de B, B proche de C => A, B et C forment un seul cluster meme si A et C
	sont, eux, trop loin l'un de l'autre directement) — union-find sur les
	paires d'ilots, jamais une simple distance au plus gros ilot seul (qui
	manquerait cette transitivite sur une chaine a 3 pieces ou plus, voir
	A3D-15 et le commentaire de ISLAND_GAP_TOLERANCE_M). Renvoie une liste de
	clusters, chacun une liste d'ilots (listes de faces bmesh) — un seul
	cluster si tous les ilots sont mutuellement proches, autant de clusters
	que d'ilots si aucun n'est proche d'un autre."""
	n = len(islands)
	aabbs = [_island_world_aabb(comp) for comp in islands]
	parent = list(range(n))

	def find(i: int) -> int:
		while parent[i] != i:
			parent[i] = parent[parent[i]]
			i = parent[i]
		return i

	def union(i: int, j: int) -> None:
		ri, rj = find(i), find(j)
		if ri != rj:
			parent[ri] = rj

	for i in range(n):
		mins_i, maxs_i = aabbs[i]
		for j in range(i + 1, n):
			mins_j, maxs_j = aabbs[j]
			if _aabb_gap(mins_i, maxs_i, mins_j, maxs_j) <= gap_tolerance:
				union(i, j)

	clusters_by_root = {}
	for i in range(n):
		clusters_by_root.setdefault(find(i), []).append(islands[i])
	return list(clusters_by_root.values())


def _drop_floating_islands(obj, gap_tolerance: float = ISLAND_GAP_TOLERANCE_M) -> int:
	"""Supprime tout ilot de faces (`_face_islands`) situe a plus de
	`gap_tolerance` du plus gros ilot (le corps principal, par nombre de
	faces) — dernier filet APRES `_voxel_remesh`/`separate_parts`/le biseau :
	contrairement a `remove_isolated_islands` (meme mesure de proximite, mais
	regroupee en CLUSTERS transitifs, voir `_cluster_islands_by_gap` — utile
	TOT, sur le maillage brut encore entier, pour ne pas casser un assemblage
	IA multi-pieces legitime comme un mat+cabine+fleche de grue), celui-ci
	compare chaque ilot DIRECTEMENT au plus gros, SANS transitivite —
	deliberement, releve concret de tache (wpn_rafale, wpn_pistolet,
	wpn_magnum : une coupe/un biseau peut laisser une dizaine de petits eclats
	disperses, chacun a une distance DIFFERENTE du corps ; regrouper ces
	eclats ENTRE EUX (transitif) les faisait a tort survivre en formant leur
	propre "cluster" au lieu d'etre chacun compare au corps — aucun de ces
	eclats n'est un assemblage multi-pieces legitime, contrairement au cas
	vise par `remove_isolated_islands`).

	A3D-15 : une tentative de clustering TRANSITIF ICI (memes clusters que
	`remove_isolated_islands`, pour ne pas amputer wl_oil_derrick — un treillis
	a plusieurs jambes, chacune proche de sa voisine mais pas du corps
	DIRECTEMENT) a ete ESSAYEE PUIS ABANDONNEE : `check_asset.py::CHK-16`
	(`_component_groups`) compare lui-meme chaque composante connexe
	DIRECTEMENT a la plus grosse, JAMAIS par cluster transitif — un ilot que
	CETTE fonction laisse survivre parce qu'il est transitivement proche
	(jamais DIRECTEMENT) du corps principal echoue donc quand meme CHK-16 a
	l'export, avec un message different (« pièce déconnectée ») plutot que de
	faire passer l'asset. Releve concret de tache : cette tentative a
	regresse cs_ship_mast/cs_deck_crane (des dizaines de nouveaux echecs
	CHK-16 sur des boulons/greffons Tripo jamais soudes, jusque-la
	silencieusement retires par CETTE fonction) ET wpn_pistolet (culasse+corps,
	auparavant propre) sans faire gagner un seul asset en G3 PASS — le
	clustering ici n'a de sens QUE si le poste de verification en aval
	l'applique aussi, ce qui n'est pas le cas. Rester EXACTEMENT aligne sur
	l'algorithme de `check_asset.py` (comparaison directe) est donc le seul
	choix qui ne desynchronise jamais "ce que ai_restyle.py juge acceptable"
	de "ce que check_asset.py verifie reellement" — le treillis multi-pieces
	(wl_oil_derrick, wl_crane_lattice, cs_deck_crane, cs_ship_mast) reste un
	defaut CONNU, hors de portee d'un ajustement de ce seul filet (a documenter
	en exemption G3, jamais une raison de desynchroniser les deux couches de
	verification).

	Un ilot proche du corps (touche/quasi-touche, ex. un accessoire qui n'a
	pas ete soude par `merge_by_distance`) est de toute facon laisse en place
	— pas une perte inutile. Renvoie le nombre de faces retirees (0 si un seul
	ilot, ou si tous les ilots secondaires sont assez proches DU CORPS)."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	islands = _face_islands(bm)
	removed = 0
	if len(islands) > 1:
		islands.sort(key=len, reverse=True)
		main_mins, main_maxs = _island_world_aabb(islands[0])
		to_delete = []
		for comp in islands[1:]:
			comp_mins, comp_maxs = _island_world_aabb(comp)
			gap = _aabb_gap(main_mins, main_maxs, comp_mins, comp_maxs)
			if gap > gap_tolerance:
				to_delete.extend(comp)
		if to_delete:
			removed = len(to_delete)
			bmesh.ops.delete(bm, geom=to_delete, context='FACES')
			orphan_verts = [v for v in bm.verts if not v.link_faces]
			if orphan_verts:
				bmesh.ops.delete(bm, geom=orphan_verts, context='VERTS')
	bm.to_mesh(me)
	bm.free()
	me.update()
	return removed


def _count_islands(me: "bpy.types.Mesh") -> int:
	bm = bmesh.new()
	bm.from_mesh(me)
	n = len(_face_islands(bm))
	bm.free()
	return n


def _mesh_volume(me: "bpy.types.Mesh") -> float:
	"""Volume clos approximatif de `me` (somme signee de tetraedres
	face/origine-locale, meme formule que check_asset.py::_signed_volume,
	valeur absolue) — calcule MEME sur un maillage NON etanche : un bord
	ouvert n'empeche pas la somme de tetraedres de converger vers une
	approximation raisonnable du volume "comme si" le trou etait rebouche par
	un eventail plat depuis l'origine locale, TANT que le trou reste petit
	devant le volume total (le cas vise ici : un scan IA troue, pas un objet a
	moitie manquant). Sert UNIQUEMENT a COMPARER un avant/apres remesh
	(`_voxel_remesh`/`_remesh_result_acceptable`) — jamais une verite
	geometrique absolue sur un maillage troue, voir `ensure_watertight` qui,
	lui, ne fait confiance qu'a un resultat REELLEMENT etanche."""
	bm = bmesh.new()
	bm.from_mesh(me)
	vol = 0.0
	for f in bm.faces:
		verts = f.verts
		if len(verts) < 3:
			continue
		v0 = verts[0].co
		for i in range(1, len(verts) - 1):
			v1, v2 = verts[i].co, verts[i + 1].co
			vol += v0.dot(v1.cross(v2)) / 6.0
	bm.free()
	return abs(vol)


def _remesh_result_acceptable(islands_before: int, extent_before: float, volume_before: float,
		me: "bpy.types.Mesh", min_extent_ratio: float = VOXEL_REMESH_MIN_EXTENT_RATIO,
		max_volume_loss_ratio: float = VOXEL_REMESH_MAX_VOLUME_LOSS_RATIO) -> bool:
	"""Decision d'acceptation d'une tentative de `_voxel_remesh` — extraite en
	fonction PURE (mesure directement sur `me`, l'etat COURANT du maillage)
	pour rester testable sans avoir a reproduire un Remesh Voxel reel : voir
	tools/blender/tests/test_ai_restyle_watertight.py, qui construit un
	AVANT/APRES synthetique (deux mesh reelles, un volume perdu > 10 % connu a
	l'avance) et verifie que CETTE fonction — celle reellement appelee par
	`_voxel_remesh` ci-dessous — rejette bien. Trois conditions, TOUTES
	necessaires (voir la docstring de `_voxel_remesh` pour l'origine de
	chacune) :
	1. `_is_watertight(me)` : aucun bord ouvert restant.
	2. `_count_islands(me) <= islands_before` : pas de fragmentation nouvelle.
	3. Ni l'etendue (`_mesh_bbox_diagonal`) ni le VOLUME clos (`_mesh_volume`,
	   A3D-12) n'ont recule de plus que leur ratio respectif — les deux sont
	   COMPLEMENTAIRES (voir le commentaire de VOXEL_REMESH_MAX_VOLUME_LOSS_RATIO) :
	   un remesh peut amincir une paroi (volume en baisse, etendue quasi
	   inchangee) ou faire disparaitre un morceau distant (etendue ET volume
	   en chute)."""
	if not _is_watertight(me):
		return False
	if _count_islands(me) > islands_before:
		return False
	min_extent_after = extent_before * min_extent_ratio
	if _mesh_bbox_diagonal(me) < min_extent_after:
		return False
	min_volume_after = volume_before * (1.0 - max_volume_loss_ratio)
	if _mesh_volume(me) < min_volume_after:
		return False
	return True


def _mesh_bbox_diagonal(me: "bpy.types.Mesh") -> float:
	"""Diagonale de la bbox calculee DIRECTEMENT depuis `me.vertices` — jamais
	`obj.bound_box`/`obj.dimensions` (voir `_bbox_diagonal`) : sondage (voir
	rapport de verification de tache) — ces deux proprietes Blender restent
	PERIMEES apres une edition mesh directe (`bmesh` + `Mesh.update()`), et
	MEME apres un `bpy.ops.object.modifier_apply()` reussi tant qu'aucune mise
	a jour de depsgraph/view-layer n'a eu lieu entre-temps (reproduit : un
	Decimate ou un Remesh applique via l'operateur, `obj.dimensions` ne bouge
	pas d'un iota). Lire `me.vertices` directement evite toute ambiguite —
	c'est le SEUL moyen fiable ici de comparer une taille AVANT/APRES un
	modificateur dans la MEME execution Python (voir `_voxel_remesh`)."""
	if len(me.vertices) == 0:
		return 0.0
	xs = [v.co.x for v in me.vertices]
	ys = [v.co.y for v in me.vertices]
	zs = [v.co.z for v in me.vertices]
	return Vector((max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))).length


def _voxel_remesh(obj, max_attempts: int = 8) -> bool:
	"""Applique un modifieur Remesh Voxel et VERIFIE que le resultat est
	reellement exploitable — DEUX sondages (voir rapport de verification de
	tache) montrent qu'un simple "l'operateur a rendu {'FINISHED'}" ne suffit
	PAS a le garantir :
	1) a CERTAINES tailles de voxel precises, `modifier_apply` renvoie
	   {'FINISHED'} mais la geometrie ressort STRICTEMENT IDENTIQUE a
	   l'entree (rattrape par `_apply_modifier`, voir sa docstring point 3 —
	   ce cas se traduit ici simplement par `_is_watertight` toujours faux,
	   rien de plus a faire ICI que retenter).
	2) a D'AUTRES tailles (reproduit sur un simple cylindre ouvert, un seul
	   ilot AVANT remesh), l'operateur reussit ({'FINISHED'}, `_is_watertight`
	   VRAI) mais FRAGMENTE la geometrie en dizaines d'ilots manifold
	   independants (jusqu'a 24 constates sur une fixture de test a 24 cotes)
	   — un artefact numerique de la reconstruction voxel a cette resolution
	   PRECISE, sans rapport avec une quelconque piece "reellement" separee
	   de l'entree. `_is_watertight` seul (aucun bord) ne peut PAS distinguer
	   ce cas d'un vrai resultat propre : les deux sont "sans bord". On
	   compare donc en plus le nombre d'ilots APRES au nombre d'ilots AVANT
	   (mesure une seule fois, avant la premiere tentative) — un remesh qui
	   fragmente STRICTEMENT PLUS que l'entree n'avait d'ilots est rejete et
	   retente avec une autre taille de voxel, jamais accepte tel quel.
	3) a D'AUTRES tailles encore (reproduit sur un objet a DEUX ilots avant
	   remesh, l'un ouvert/troue, l'autre deja clos) l'operateur reussit
	   ({'FINISHED'}, `_is_watertight` VRAI, UN SEUL ilot en sortie — passe
	   donc les deux garde-fous ci-dessus) mais NE RECONSTRUIT QUE l'ilot deja
	   clos d'origine et ELIMINE SILENCIEUSEMENT tout l'ilot troue — pourtant
	   largement le plus gros des deux avant remesh (mesure : la piece
	   principale, ~85% des faces d'entree, disparait entierement ; seul un
	   petit debris deja etanche survit, meme a la plus fine resolution
	   testee). Ni `_is_watertight` ni le compte d'ilots ne peuvent detecter
	   cette disparition puisque le resultat est un solide UNIQUE et sans
	   bord — on compare donc en plus la diagonale de bbox (`_mesh_bbox_diagonal`,
	   PAS `_bbox_diagonal`/`obj.dimensions` : voir sa docstring) du resultat a
	   celle de l'entree : un resultat qui a perdu plus de
	   `1 - VOXEL_REMESH_MIN_EXTENT_RATIO` de la taille d'origine est rejete et
	   retente, jamais accepte tel quel.
	Dans tous les cas, on ne peut pas faire confiance a un simple "ca s'est
	applique sans exception" : on retente avec une taille de voxel legerement
	decalee (facteur non rond, pour ne pas retomber sur une autre valeur
	degeneree par coincidence) jusqu'a ce que le resultat soit a la fois
	etanche, pas plus fragmente qu'avant ET pas draconiennement plus petit
	qu'avant, ou jusqu'a epuisement des tentatives — renvoie alors False APRES
	AVOIR RESTAURE le maillage tel qu'il etait avant la toute premiere
	tentative (A3D-15 : un echec de remesh ne doit plus jamais laisser sur
	`obj.data` la geometrie mutilee de la DERNIERE tentative rejetee — voir
	`ensure_watertight`, qui traite desormais ce cas comme un AVERTISSEMENT,
	le maillage d'origine, non etanche mais complet, restant exporte tel
	quel plutot qu'un blocage dur ; releve de tache A3D-13, confirme sur les
	Smart Mesh deja propres/bas-poly de la vague 1, dont l'echec ne venait
	JAMAIS d'un maillage reellement troue mais d'un Remesh Voxel qui n'a
	jamais trouve de taille acceptable sur cette topologie precise). Un ilot
	deja present et reellement distinct AVANT le remesh (vrai debris IA, voir
	`ensure_watertight`/`_drop_floating_islands`) n'est PAS ici la cible des
	garde-fous 2/3 : le remesh qui les conserve TOUS LES DEUX (nombre d'ilots
	inchange ou en baisse, taille globale preservee) est accepte normalement,
	et `_drop_floating_islands` s'occupe separement de la distance entre eux.

	A3D-12 : la decision d'acceptation elle-meme (etancheite + fragmentation +
	etendue + VOLUME clos, ce dernier nouveau) vit dans `_remesh_result_acceptable`
	(fonction pure, testee isolement) — cette fonction se contente de mesurer
	l'etat AVANT la premiere tentative et de rejouer les tentatives."""
	diag = max(_bbox_diagonal(obj), 1e-6)
	voxel_size = max(VOXEL_SIZE_MIN, min(VOXEL_SIZE_MAX, diag / VOXEL_RESOLUTION))
	islands_before = max(1, _count_islands(obj.data))
	extent_before = max(_mesh_bbox_diagonal(obj.data), 1e-6)
	volume_before = _mesh_volume(obj.data)
	# Filet de securite A3D-15 : copie INDEPENDANTE du maillage AVANT la
	# premiere tentative (chaque tentative bake son modificateur DANS
	# `obj.data` via `_apply_modifier` — sans cette copie, un echec complet
	# laisserait la geometrie mutilee de la DERNIERE taille de voxel tentee,
	# jamais l'entree d'origine).
	original_mesh = obj.data.copy()
	for attempt in range(max_attempts):
		mod = obj.modifiers.new(f"ai_restyle_voxel_remesh_{attempt}", type='REMESH')
		mod.mode = 'VOXEL'
		mod.voxel_size = voxel_size
		mod.use_smooth_shade = False
		_apply_modifier(obj, mod)
		obj.data.update()
		if _remesh_result_acceptable(islands_before, extent_before, volume_before, obj.data):
			bpy.data.meshes.remove(original_mesh)  # plus besoin du filet : succes
			return True
		voxel_size = max(VOXEL_SIZE_MIN, voxel_size * 0.63)
	# Aucune tentative acceptable : restaure le maillage D'ORIGINE (avant la
	# premiere tentative) sur `obj` et purge le maillage mutile devenu
	# orphelin — jamais une geometrie de tentative rejetee qui traine.
	mutilated_mesh = obj.data
	obj.data = original_mesh
	bpy.data.meshes.remove(mutilated_mesh)
	return False


def _capture_face_materials(me: "bpy.types.Mesh") -> list:
	"""Photo, AVANT tout remesh, de chaque face de `me` : (centre en espace
	LOCAL, `material_index`) — sert de reference a
	`_reassign_materials_by_nearest_face` pour recoller un materiau a chaque
	face du maillage remesh (le Remesh Voxel reinitialise `material_index` a
	0 sur TOUTES les faces qu'il produit, cf. commentaire de
	`_reassign_materials_by_nearest_face`, mais ne touche jamais la liste
	`obj.data.materials` elle-meme : les index captures ici restent valides
	APRES remesh)."""
	return [(p.center.copy(), p.material_index) for p in me.polygons]


def _reassign_materials_by_nearest_face(obj, snapshot: list) -> None:
	"""Reassigne `material_index` de CHAQUE face du maillage COURANT de `obj`
	(deja remesh) en cherchant, dans `snapshot` (centres de face AVANT
	remesh, voir `_capture_face_materials`), le centre le PLUS PROCHE (KD-tree,
	`mathutils.kdtree` — un maillage de plusieurs milliers de faces rend une
	recherche naive O(n) par face bien trop lente) et en reprenant SON
	`material_index`.

	A3D-15 : remplace l'ancien "collapse vers le kind dominant" (le Remesh
	Voxel APPLIQUE reinitialise `material_index` a 0 sur toutes ses faces —
	limitation DOCUMENTEE de l'operateur, voir manuel Blender — mais ne vide
	JAMAIS `obj.data.materials` : tous les slots de kind d'origine restent
	disponibles, seule l'AFFECTATION par face est perdue). Puisque le Remesh
	Voxel RECONSTRUIT la surface pres de sa position d'origine (a la
	resolution du voxel choisi, voir `_voxel_remesh`), le centre de chaque
	nouvelle face reste proche du centre de la face d'origine qu'elle
	remplace : une reaffectation par plus proche voisin recolle donc chaque
	kind a la bonne region de l'objet plutot que d'ecraser tout l'objet en un
	seul kind — releve concret de tache (vague 1 : cs_container_20/40,
	cs_lifeboat_davits, gp_bomb, gp_borne, wl_water_tower, wpn_eclair,
	wpn_fracas, wpn_rafale, wpn_ravage, wpn_semeuse — tous multi-kind et tous
	amputes a un seul kind par l'ancien collapse). N'est appelee que si
	`obj.data.materials` porte reellement PLUSIEURS materiaux (voir
	`ensure_watertight`) : sur un seul kind, rien a transferer."""
	kd = KDTree(len(snapshot))
	for i, (center, _mi) in enumerate(snapshot):
		kd.insert(center, i)
	kd.balance()
	me = obj.data
	for p in me.polygons:
		_co, idx, _dist = kd.find(p.center)
		p.material_index = snapshot[idx][1]
	me.update()


def ensure_watertight(obj) -> dict:
	"""Remesh l'objet ENTIER en un seul passage Voxel si necessaire (jamais
	par kind, voir commentaire ci-dessus), PUIS supprime tout fragment
	flottant restant (`_drop_floating_islands` — un remesh Voxel global ne
	recolle jamais deux ilots distants, voir commentaire au-dessus de
	`_is_watertight`), que ce dernier ait tourne ou non (un GLB IA deja sans
	trou peut quand meme porter un debris deja clos, distinct, jamais soude
	par `merge_by_distance`/`remove_isolated_islands` en amont). Renvoie
	`{"remeshed": bool, "remesh_failed": bool, "collapsed_to": kind|None,
	"dropped_kinds": [...], "dropped_disconnected_faces": int}` pour le
	rapport JSON — `collapsed_to`/`dropped_kinds` restent desormais TOUJOURS
	vides (A3D-15, voir `_reassign_materials_by_nearest_face` : un remesh
	accepte ne sacrifie plus aucun kind, il les reaffecte par proximite),
	conserves dans le rapport pour compatibilite ascendante ; `dropped_
	disconnected_faces` reste a 0 si tous les ilots restants sont a moins de
	`ISLAND_GAP_TOLERANCE_M` du corps principal (rien a jeter).

	A3D-15 : le watertight est un AVERTISSEMENT, jamais un blocage dur — releve
	de tache A3D-13 (ce meme remesh Voxel echouait DUR, `RuntimeError`, sur la
	majorite des Smart Mesh de la vague 1, deja propres et bas-poly ; leur
	echec ne venait jamais d'un maillage reellement fragmente/ampute mais d'un
	Remesh Voxel qui ne trouvait aucune taille de voxel acceptable sur cette
	topologie precise — voir `_voxel_remesh`). Si aucune tentative n'est
	acceptee, `_voxel_remesh` a deja restaure le maillage TEL QU'IL ETAIT avant
	la premiere tentative (voir sa docstring) : on continue donc ici avec ce
	maillage d'origine (potentiellement non etanche), `remesh_failed=True` dans
	le rapport plutot qu'une exception — check_asset.py::CHK-16 traite deja un
	bord ouvert comme un AVERTISSEMENT ("normal si non ferme"), jamais un
	echec dur, donc ce choix ne cree aucune incoherence en aval. Les DEUX
	autres garde-fous durs restent inchanges : `_drop_floating_islands` (voir
	plus bas, invariant verifie SEULEMENT quand le maillage etait etanche
	avant cette suppression) et `_remesh_result_acceptable` lui-meme (perte de
	volume > 10 %, fragmentation, etendue — toujours verifies PAR TENTATIVE,
	rien de tolere a ce niveau-la : seul l'EPUISEMENT de toutes les
	tentatives devient non bloquant)."""
	remeshed = False
	remesh_failed = False
	collapsed_to = None
	dropped_kinds = []

	was_watertight = _is_watertight(obj.data)
	if not was_watertight:
		materials = list(obj.data.materials)
		multi_material = len(materials) > 1
		# Photo AVANT remesh (voir _capture_face_materials) : c'est le SEUL
		# instant ou `obj.data` porte encore l'affectation par face fiable —
		# `_voxel_remesh` peut tenter plusieurs tailles de voxel en interne,
		# mutant `obj.data` a chaque tentative, mais mesure lui-meme ses
		# propres garde-fous (ilots/etendue/volume) contre CET etat d'avant sa
		# toute premiere tentative (voir sa docstring) : le repere spatial
		# reste donc valide quel que soit le nombre de tentatives internes.
		face_snapshot = _capture_face_materials(obj.data) if multi_material else None

		if _voxel_remesh(obj):
			remeshed = True
			if multi_material:
				_reassign_materials_by_nearest_face(obj, face_snapshot)
		else:
			# A3D-15 : avertissement, pas un blocage — voir docstring ci-dessus.
			# Le maillage restaure par `_voxel_remesh` garde TOUS ses kinds
			# d'origine (rien a reassigner puisque rien n'a ete remesh).
			remesh_failed = True
			print(f"AI_RESTYLE_WARN \"{obj.name}\" reste non etanche (aucune taille de "
				"voxel acceptable trouvee) — maillage d'origine conserve, avertissement "
				"non bloquant (A3D-15)")

	# L'invariant "la suppression d'ilots flottants ne doit jamais ROUVRIR un
	# bord" ne s'applique que si le maillage etait etanche avant cette
	# suppression (soit des l'entree, soit apres un remesh ACCEPTE) : un
	# maillage deja non etanche (remesh en echec, voir ci-dessus) reste
	# candidat a cette suppression (un debris distant reste un debris,
	# etanche ou non, voir `_drop_floating_islands`), sans que son bord
	# preexistant ne declenche cette verification.
	watertight_before_drop = was_watertight or remeshed
	dropped_disconnected_faces = _drop_floating_islands(obj)
	if watertight_before_drop and dropped_disconnected_faces and not _is_watertight(obj.data):
		raise RuntimeError(
			"ai_restyle: la suppression des ilots flottants a rouvert un bord sur "
			f"\"{obj.name}\" (invariant viole)")

	return {
		"remeshed": remeshed,
		"remesh_failed": remesh_failed,
		"collapsed_to": collapsed_to,
		"dropped_kinds": dropped_kinds,
		"dropped_disconnected_faces": dropped_disconnected_faces,
	}


# ---------------------------------------------------------------------------
# Etape 5 — budget de tris (Decimate COLLAPSE iteratif, jamais un depassement
# silencieux : voir `restyle` qui echoue fort si ce plafond d'iterations ne
# suffit pas a redescendre sous le budget).
# ---------------------------------------------------------------------------

DECIMATE_PLANAR_ANGLE_LIMIT = 0.0872665  # ~5 degres (radians)
DECIMATE_STALL_RATIO = 0.99  # une passe COLLAPSE qui ne gagne pas au moins 1 % est consideree "en plateau"
# A3D-15 : plafond d'iterations DEDIE a `decimate_group_to_budget` (jamais a
# `decimate_to_budget`, appelee AVANT le biseau — voir sa docstring, ce cas ne
# s'est jamais montre a court d'iterations en pratique) — releve concret de
# tache : wl_gas_billboard (12312 tris pour un budget de 3000, x4) et
# wl_oil_derrick (12402 pour 12000, +3 %) epuisaient encore les 6 iterations
# de `DECIMATE_MAX_ITERATIONS` MEME avec la passe DISSOLVE de secours
# (`_decimate_planar_pass`) puisque celle-ci n'etait tentee qu'UNE SEULE FOIS
# par objet (voir l'ancienne restriction `planar_tried`, retiree ci-dessous) :
# une topologie tres beveillee peut plafonner PLUSIEURS fois de suite (chaque
# DISSOLVE debloque une marge de progression pour la COLLAPSE suivante, qui
# peut elle-meme replafonner, voir la docstring de `_decimate_planar_pass`) —
# un budget d'iterations plus genereux, dedie a CE poste precis (jamais
# necessaire ailleurs, jamais un cout en pratique grace au retour anticipe des
# que le budget est tenu), lui laisse la marge de converger.
DECIMATE_GROUP_MAX_ITERATIONS = 10
# A3D-15 : plafond du nombre de passes DISSOLVE de secours REJOUEES par objet
# (voir ci-dessus, "plus de restriction une seule fois") — releve concret de
# tache (wl_gas_billboard) : au-dela de 2-3 essais, DISSOLVE ne debloque plus
# aucune marge supplementaire pour COLLAPSE (plancher topologique reellement
# atteint, pas juste "pas encore assez essaye") — continuer a la retenter a
# CHAQUE iteration restante coute cher (chaque passe COLLAPSE+DISSOLVE sur un
# maillage beveille de plusieurs milliers de tris n'est pas gratuite) pour un
# gain mesure negligeable (~1 % sur 20 iterations completes contre 6). Ce
# plafond borne le cout dans ce cas sans reduire la marge de convergence des
# cas qui EN ONT reellement besoin (wl_oil_derrick convergeait deja largement
# sous ce plafond).
DECIMATE_PLANAR_MAX_RETRIES = 3


def _decimate_planar_pass(obj) -> None:
	"""Passe DISSOLVE (fusion des faces quasi coplanaires, angle <= 5 degres)
	— A3D-15, releve concret de tache (wl_oil_derrick, vague 1) : sur une
	topologie tres beveillee/en treillis (toonkit.apply_stylekit_shading en
	ajoute beaucoup), Decimate COLLAPSE seul peut PLAFONNER bien au-dessus du
	budget quel que soit le nombre de passes (sondage : ~20 200 tris fixes sur
	8 passes de COLLAPSE, budget 12 000) — un plancher topologique de
	l'operateur sur ce type de maillage (beaucoup de faces fines quasi
	planes issues du biseau, que COLLAPSE ne simplifie pas efficacement).
	DISSOLVE s'attaque a une geometrie DIFFERENTE (facettes coplanaires) et
	debloque une marge de progression pour les passes COLLAPSE suivantes —
	voir `decimate_to_budget`/`decimate_group_to_budget`, qui ne la tentent
	qu'UNE SEULE FOIS, des qu'une passe COLLAPSE ne gagne quasiment rien
	(`DECIMATE_STALL_RATIO`), jamais systematiquement (moins puissante que
	COLLAPSE seul sur un maillage qui progresse normalement, donc jamais
	utile hors plateau)."""
	mod = obj.modifiers.new("ai_restyle_decimate_planar", type='DECIMATE')
	mod.decimate_type = 'DISSOLVE'
	mod.angle_limit = DECIMATE_PLANAR_ANGLE_LIMIT
	_apply_modifier(obj, mod)
	obj.data.update()


def decimate_to_budget(obj, budget: int, max_iterations: int = DECIMATE_MAX_ITERATIONS) -> int:
	planar_retries = 0
	for _ in range(max_iterations):
		tris = toonkit.tri_count(obj)
		if tris <= budget:
			return tris
		ratio = max(0.02, min(0.95, budget / float(tris)))
		mod = obj.modifiers.new("ai_restyle_decimate", type='DECIMATE')
		mod.decimate_type = 'COLLAPSE'
		mod.ratio = ratio
		_apply_modifier(obj, mod)
		obj.data.update()
		new_tris = toonkit.tri_count(obj)
		# A3D-15 : rejouee a CHAQUE plateau, jusqu'a `DECIMATE_PLANAR_MAX_RETRIES`
		# fois (plus de restriction "une seule fois", mais plus un nombre
		# illimite non plus — voir sa docstring) — un seul essai suffisait
		# rarement sur une topologie tres beveillee, qui peut replafonner apres
		# un premier DISSOLVE, mais au-dela de ce plafond le gain mesure devient
		# negligeable pour un cout non negligeable (chaque passe n'est pas
		# gratuite). Sans cout au-dela du necessaire : un objet qui progresse
		# normalement ne plafonne jamais, donc ne declenche jamais ce chemin.
		if (new_tris > budget and new_tris >= tris * DECIMATE_STALL_RATIO
				and planar_retries < DECIMATE_PLANAR_MAX_RETRIES):
			planar_retries += 1
			_decimate_planar_pass(obj)
	return toonkit.tri_count(obj)


def decimate_group_to_budget(objs: list, budget: int, max_iterations: int = DECIMATE_MAX_ITERATIONS) -> int:
	"""Comme `decimate_to_budget`, mais reparti sur PLUSIEURS objets qui
	partagent un budget TOTAL commun (le corps et ses pieces separees, §3.5)
	— necessaire pour tenir le budget APRES le biseau (A3D-15,
	docs/assets/ASSET_PLAN.md notes de tache) : `toonkit.apply_stylekit_shading`
	(biseau + normales/masque) AJOUTE des triangles sur chaque arete vive, et
	sur un maillage Smart Mesh deja bas-poly cet ajout a lui seul peut
	repasser au-dessus du budget alors que `decimate_to_budget`, appele PLUS
	TOT sur le maillage brut (encore SANS biseau), n'avait rien eu a faire
	(releve concret : cs_container_20, 829 tris avant biseau pour un budget de
	2500, mais 3334 apres — le budget n'etait donc JAMAIS verifie APRES le
	poste qui l'aurait fait deborder). Meme algorithme que
	`decimate_to_budget` (ratio global = budget / total courant, RE-CALCULE et
	REAPPLIQUE a CHAQUE objet du groupe a chaque iteration — jamais un seul
	objet vide de tout son exces pendant qu'un autre garde le sien, ce qui
	preserverait une repartition disproportionnee entre corps et pieces
	separees). Un objet deja vide (0 triangle, ex. une piece degenerescente)
	est saute silencieusement (rien a decimer). A3D-15 : meme filet anti-
	plateau que `decimate_to_budget` (`_decimate_planar_pass`, REJOUEE A CHAQUE
	plateau, plus de restriction "une seule fois par objet" — voir
	`DECIMATE_GROUP_MAX_ITERATIONS`) des qu'une passe COLLAPSE ne gagne
	quasiment rien sur CET objet precis. Releve concret de tache : un seul
	essai de secours suffisait rarement sur une topologie tres beveillee
	(wl_gas_billboard, budget x4 depasse encore apres 6 iterations ; wl_oil_
	derrick, +3 % encore au-dessus) — chaque DISSOLVE ne debloque souvent
	qu'UNE marge de progression limitee pour les COLLAPSE suivantes, qui
	peuvent elles-memes replafonner (voir `_decimate_planar_pass`) : la
	retenter a chaque nouveau plateau, sur le budget d'iterations plus genereux
	de `DECIMATE_GROUP_MAX_ITERATIONS`, laisse la marge necessaire pour
	converger sans jamais couter d'iteration a un objet qui progresse
	normalement (chemin jamais emprunte dans ce cas)."""
	objs = [o for o in objs if o is not None]
	planar_retries = {id(o): 0 for o in objs}
	for _ in range(max_iterations):
		total = toonkit.tri_count(objs)
		if total <= budget:
			return total
		ratio = max(0.02, min(0.95, budget / float(total)))
		for i, obj in enumerate(objs):
			before = toonkit.tri_count(obj)
			if before <= 0:
				continue
			mod = obj.modifiers.new(f"ai_restyle_decimate_post_bevel_{i}", type='DECIMATE')
			mod.decimate_type = 'COLLAPSE'
			mod.ratio = ratio
			_apply_modifier(obj, mod)
			obj.data.update()
			after = toonkit.tri_count(obj)
			if after >= before * DECIMATE_STALL_RATIO and planar_retries[id(obj)] < DECIMATE_PLANAR_MAX_RETRIES:
				planar_retries[id(obj)] += 1
				_decimate_planar_pass(obj)
	return toonkit.tri_count(objs)


# ---------------------------------------------------------------------------
# Separation des pieces mobiles (armes, docs/assets/ASSET_PLAN.md §3.5/§2) :
# une boite locale par piece declaree (chargeur, pompe, culasse, barillet,
# chien, couvercle de trémie) decoupe les faces qu'elle contient en un NOUVEL
# objet mesh, et rebouche le trou laisse par la decoupe des DEUX cotes (corps
# restant ET piece detachee) — jamais de trou visible ni sur l'un ni sur
# l'autre. Marqueurs `Muzzle`/`Foregrip` (memes noms qu'aujourd'hui, lus par
# ViewModel.gd) ajoutes comme de vrais empties `bpy.data.objects.new(name,
# None)` (meme convention que tools/blender/make_weapons.py) : PAS des mesh a
# 0 face (check_asset.py echoue DUR sur un mesh vide, "0 triangle") et PAS de
# parentage a la mesh (l'exporteur glTF, meme en `use_selection=True`,
# n'inclut PAS les enfants non selectionnes d'un objet selectionne — verifie
# par sondage, voir rapport de tache : un empty parente mais non selectionne
# disparait silencieusement du .glb) — `export_with_markers` selectionne donc
# explicitement TOUS les objets (mesh + empties) a exporter.
# ---------------------------------------------------------------------------

def _select_only(objs) -> None:
	bpy.ops.object.select_all(action='DESELECT')
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]


def _fill_holes(obj) -> int:
	"""Rebouche tout bord ouvert de `obj` par un remplissage direct du contour
	(n-gon, `bmesh.ops.holes_fill`, PUIS triangulation immediate du/des n-gon(s)
	crees — A3D-15, voir plus bas) — utilise apres `separate_parts` pour
	qu'aucun trou ne reste visible ni sur le corps restant ni sur la piece
	detachee (docs/assets/ASSET_PLAN.md §2 : "trous rebouches"). Un objet deja
	etanche (aucun bord) : no-op, renvoie 0. Renvoie le nombre de faces
	creees (apres triangulation).

	A3D-15 : releve concret de tache (wpn_magnum : barillet/chien/corps,
	wpn_marqueur : capuchon/corps, wpn_pistolet : chargeur/culasse/corps —
	notes de tache) — un contour de coupe issu d'une surface COURBE (barillet
	de revolver, chien) n'est generalement PAS planaire ; le n-gon que
	`holes_fill` cree pour le reboucher peut alors se retrouver, une fois
	triangule IMPLICITEMENT plus loin (export glTF, ou l'analyse de
	check_asset.py), avec une triangulation DIFFERENTE de celle qu'un simple
	ngon plat aurait — dans certains cas degeneres (contour concave/gauchi),
	cette triangulation implicite peut partager une arete entre plus de deux
	triangles (arete non-manifold, >= 3 faces). Trianguler ICI, sur le
	maillage de travail, juste apres le remplissage, garantit que la
	topologie VERIFIEE ci-dessous est EXACTEMENT celle qui sera exportee —
	plus aucune triangulation implicite en aval ne peut diverger. Le
	garde-fou dur final porte sur TOUT `obj` (pas seulement la zone
	rebouchee) : une piece peut porter, ailleurs sur sa propre surface, un
	defaut deja present sur le maillage brut avant meme cette coupe (releve
	concret : wpn_percuteur "chien" - persiste quelle que soit la position
	de la boite de decoupe). Deux passes de reparation (doublons exacts,
	puis eclats degeneres en dernier recours NON STRICT) sont tentees sur la
	zone rebouchee PUIS, si necessaire, sur l'objet entier avant d'echouer
	fort plutot que d'exporter une piece non-manifold en silence -
	check_asset.py::CHK detecterait la meme chose bien plus tard, avec un
	message bien moins precis."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	bm.edges.ensure_lookup_table()
	boundary = [e for e in bm.edges if len(e.link_faces) == 1]
	created = 0
	if boundary:
		fill_result = bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
		new_faces = fill_result.get("faces", [])
		if new_faces:
			tri_result = bmesh.ops.triangulate(bm, faces=new_faces, ngon_method='EAR_CLIP')
			new_faces = tri_result.get("faces") or new_faces
		created = len(new_faces)
		bad = sorted({e for f in new_faces for e in f.edges if len(e.link_faces) >= 3},
			key=lambda e: e.index)
		if bad:
			# A3D-15 : deux derniers recours AVANT d'echouer fort, dans l'ordre —
			# 1) un doublon de face du maillage BRUT (deux triangles superposes,
			#    jamais retire par `bmesh.ops.remove_doubles` qui ne fusionne
			#    que des sommets, voir `_remove_duplicate_faces`) peut n'etre
			#    expose comme arete non-manifold qu'une fois le bord voisin
			#    rebouche ici. `restyle()` purge deja ce defaut sur le maillage
			#    ENTIER avant tout le reste (donc ce cas ne devrait plus se
			#    produire en pratique) ; ce filet ne fait que reappliquer le
			#    MEME nettoyage, localement.
			# 2) un eclat degenere du maillage brut (triangle quasi nul, pas un
			#    doublon exact) qui se greffe sur une arete par ailleurs
			#    normale — voir `_remove_nonmanifold_slivers` (releve concret :
			#    wpn_faucheur, ou une arete a 4 faces liees combinait un
			#    doublon exact ET un eclat distinct, aucune des deux passes
			#    seule ne suffisant).
			removed_dupes = _remove_duplicate_faces(bm)
			if removed_dupes:
				created -= removed_dupes
			bad = sorted({e for f in new_faces if f.is_valid for e in f.edges if len(e.link_faces) >= 3},
				key=lambda e: e.index)
			if bad:
				removed_slivers = _remove_nonmanifold_slivers(bm, bad, strict=False)
				if removed_slivers:
					created -= removed_slivers
					bad = sorted({e for f in new_faces if f.is_valid for e in f.edges if len(e.link_faces) >= 3},
						key=lambda e: e.index)
		# A3D-15 : la coupe elle-meme peut ressortir propre (aucune arete
		# non-manifold sur `new_faces`, voir ci-dessus) alors que la piece
		# porte, AILLEURS sur SA PROPRE surface, un defaut deja present sur le
		# maillage brut avant meme cette coupe (releve concret : wpn_percuteur
		# "chien" — le meme defaut persiste quelle que soit la position de la
		# boite de decoupe, preuve qu'il n'a jamais tenu a la coupe). Le
		# nettoyage GLOBAL preventif de `restyle()` (`repair_nonmanifold_edges`,
		# mode STRICT) a deja essaye et renonce (aires comparables, pas un
		# eclat clair) : `_fill_holes` promet un objet ENTIEREMENT propre (pas
		# seulement "le trou qu'il vient de reboucher"), donc un dernier
		# passage NON STRICT sur TOUT `bm` ICI, PUIS seulement le garde-fou dur
		# — jamais l'inverse, cette passe non stricte ne s'applique qu'a ce
		# stade tardif, jamais dans le nettoyage global preventif.
		bad = sorted((e for e in bm.edges if len(e.link_faces) >= 3), key=lambda e: e.index)
		if bad:
			removed_slivers = _remove_nonmanifold_slivers(bm, bad, strict=False)
			if removed_slivers:
				created -= removed_slivers
			bad = sorted((e for e in bm.edges if len(e.link_faces) >= 3), key=lambda e: e.index)
		if bad:
			raise RuntimeError(
				f"ai_restyle: {len(bad)} arete(s) non-manifold (>= 3 faces) sur \"{obj.name}\" "
				"apres reboucher+trianguler la coupe — piece non reparable telle quelle, "
				"jamais exportee en silence (A3D-15)")
	bm.to_mesh(me)
	bm.free()
	me.update()
	return created


def separate_parts(obj, parts_spec: list) -> list:
	"""Decoupe `obj` selon `parts_spec` (`[{"name": str, "box_min": [x,y,z],
	"box_max": [x,y,z]}, ...]`, coordonnees dans le repere LOCAL de `obj` — le
	meme repere que `_bbox_diagonal`/`_island_world_aabb`, deja etabli comme
	l'espace de travail de ce fichier) : pour chaque piece declaree, selectionne
	les faces dont le CENTRE tombe dans la boite, les separe en un nouvel objet
	(`bpy.ops.mesh.separate`, qui preserve correctement les affectations de
	materiau des deux cotes), puis rebouche le trou laisse sur `obj` ET sur la
	piece detachee (`_fill_holes`). Renvoie la liste des nouveaux objets, dans
	l'ordre de `parts_spec`. Leve une erreur si une boite ne contient AUCUNE
	face (piece declaree introuvable — jamais une piece manquante en
	silence) ; ne modifie PAS l'ordre des pieces deja separees si une piece
	suivante echoue (l'appelant recoit une exception, `restyle` ne va pas plus
	loin)."""
	created = []
	for part in parts_spec:
		name = part["name"]
		box_min = Vector(part["box_min"])
		box_max = Vector(part["box_max"])
		me = obj.data
		for p in me.polygons:
			p.select = False
		for e in me.edges:
			e.select = False
		for v in me.vertices:
			v.select = False
		matched = 0
		for p in me.polygons:
			c = p.center
			if (box_min.x <= c.x <= box_max.x and box_min.y <= c.y <= box_max.y
					and box_min.z <= c.z <= box_max.z):
				p.select = True
				matched += 1
		if matched == 0:
			raise RuntimeError(
				f"ai_restyle: aucune face dans la boite de la piece {name!r} "
				f"({part['box_min']} .. {part['box_max']}) — piece introuvable sur \"{obj.name}\"")
		before_names = {o.name for o in bpy.data.objects}
		with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
			bpy.ops.object.mode_set(mode='EDIT')
			bpy.ops.mesh.separate(type='SELECTED')
			bpy.ops.object.mode_set(mode='OBJECT')
		new_names = [n for n in (o.name for o in bpy.data.objects) if n not in before_names]
		if len(new_names) != 1:
			raise RuntimeError(
				f"ai_restyle: separation de la piece {name!r} attendue en UN nouvel objet, "
				f"obtenu {new_names!r}")
		new_obj = bpy.data.objects[new_names[0]]
		new_obj.name = name
		_fill_holes(obj)
		_fill_holes(new_obj)
		created.append(new_obj)
	return created


def create_marker(name: str, position) -> "bpy.types.Object":
	"""Empty `PLAIN_AXES` nomme `name` a `position` (repere LOCAL, meme espace
	que `separate_parts` — voir sa docstring) — meme convention que
	tools/blender/make_weapons.py (`Muzzle`/`Foregrip`, lus par
	ViewModel.gd::_refresh_model/_left_glove_anchor)."""
	empty = bpy.data.objects.new(name, None)
	empty.empty_display_type = 'PLAIN_AXES'
	empty.empty_display_size = 0.03
	empty.location = Vector(position)
	bpy.context.scene.collection.objects.link(empty)
	return empty


def load_parts_spec(path: str) -> dict:
	"""Charge un fichier JSON `{"parts": [...], "markers": [...]}` (voir
	`separate_parts`/`create_marker` pour le schema de chaque entree)."""
	with open(path, "r", encoding="utf-8") as f:
		spec = json.load(f)
	if not isinstance(spec, dict):
		raise ValueError(f"ai_restyle: --parts {path!r} : attendu un objet JSON {{'parts':..., 'markers':...}}")
	return spec


def export_with_markers(path: str, mesh_objs: list, marker_objs: list) -> dict:
	"""Exporte `mesh_objs` (corps + pieces separees) ET `marker_objs` (empties
	Muzzle/Foregrip) dans le MEME .glb — memes reglages glTF que
	`toonkit.export_glb` (Y-up, modificateurs appliques, materiaux,
	color_attributes actives, attributs `_`-prefixes), reimplementes ICI car
	l'API PUBLIQUE de toonkit (`toonkit.export_glb`) ne sait exporter QUE des
	objets mesh (`obj.data.materials` plante sur un Empty, `obj.data is None`)
	et que l'exporteur glTF, meme en `use_selection=True`, n'inclut PAS les
	enfants NON selectionnes d'un objet selectionne (verifie par sondage, voir
	rapport de tache) — les empties doivent donc etre selectionnes
	explicitement au meme titre que les mesh. Renvoie `{"tris": int, "nodes":
	[str, ...]}` pour le rapport JSON de `restyle`."""
	all_objs = list(mesh_objs) + list(marker_objs)
	if not mesh_objs:
		raise ValueError("ai_restyle: export_with_markers: aucun objet mesh a exporter")
	for o in mesh_objs:
		if not o.data.materials:
			print(f"AI_RESTYLE_WARN \"{o.name}\" n'a aucun materiau assigne — "
				"ses eventuelles color_attributes NE seront PAS exportees")
	os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
	_select_only(all_objs)
	bpy.ops.export_scene.gltf(
		filepath=path,
		export_format='GLB',
		use_selection=True,
		export_apply=True,
		export_yup=True,
		export_materials='EXPORT',
		export_vertex_color='ACTIVE',
		export_all_vertex_colors=True,
		export_attributes=True,
		export_cameras=False,
		export_lights=False,
		export_animations=False,
	)
	tris = toonkit.tri_count(mesh_objs)
	node_names = [o.name for o in all_objs]
	print(f"AI_RESTYLE_EXPORT_OK {os.path.basename(path)} tris={tris} nodes={node_names} -> {path}")
	return {"tris": tris, "nodes": node_names}


# ---------------------------------------------------------------------------
# A3D-15 : reparation non-manifold FINALE, APRES biseau/seconde decimation —
# releve concret de tache (wpn_fracas "pompe", wpn_percuteur "chien",
# wpn_pistolet "culasse", wpn_magnum, wl_water_tower) : `_fill_holes` garantit
# deja un objet propre juste apres `separate_parts`, mais le biseau
# (`toonkit.apply_stylekit_shading`) ET la seconde passe de Decimate COLLAPSE
# qu'il peut declencher (`decimate_group_to_budget`, tous deux plus loin dans
# `restyle()`) peuvent CHACUN introduire une NOUVELLE arete non-manifold
# (>= 3 faces liees) — un mode de defaillance DISTINCT de celui deja couvert
# par `_drop_floating_islands` (ilots DISJOINTS) : ici, la topologie reste UN
# SEUL ilot connexe, mais une arete precise se retrouve partagee par 3 faces
# ou plus (ex. un Decimate COLLAPSE qui fusionne deux sommets proches d'un
# bord fraichement rebouche). check_asset.py::CHK-16 ne verifie que le .glb
# DEJA EXPORTE : sans ce filet, ce defaut n'apparait qu'en aval, avec un
# message bien moins precis que celui que `_fill_holes` sait deja produire.
# ---------------------------------------------------------------------------

# Plafond d'aretes non-manifold reparees ICI, en dernier recours (voir
# `_remove_nonmanifold_slivers(strict=False)` — garde TOUJOURS les 2 faces de
# plus grande aire, quel que soit l'ecart, la seule resolution disponible pour
# une arete a 3+ faces) : au-dela, la reparation supprimerait trop de faces
# d'un coup pour rester "la moins destructrice des options disponibles" (voir
# sa docstring) — releve concret de tache : wl_crane_lattice porte plus de
# 2000 aretes non-manifold sur son PROPRE treillis (defaut du maillage brut,
# jamais introduit par le biseau/la decimation) ; les y appliquer mutilerait
# la silhouette a la place d'une simple retouche locale. Un asset au-dela de
# ce plafond reste donc EN L'ETAT (non repare ici), a documenter comme
# exemption G3 (docs/assets/ASSET_PLAN.md §9 risque #2) plutot qu'a forcer.
NONMANIFOLD_FINAL_REPAIR_MAX_EDGES = 50

# A3D-15 : EXACTEMENT la meme tolerance de ressoudage que
# `check_asset.py::check_object` (`bmesh.ops.remove_doubles(bm_welded,
# verts=bm_welded.verts, dist=1e-4)`, sur sa copie ressoudee du .glb
# reimporte) — jamais une valeur inventee ici : toute difference entre les
# deux ferait DIVERGER la topologie que `_repair_nonmanifold_final` verifie de
# celle que `check_asset.py` mesurera reellement en aval (voir sa docstring).
_CHECK_ASSET_WELD_DIST_M = 1e-4


def _repair_nonmanifold_final(objs: list) -> dict:
	"""Reparation best-effort (JAMAIS un blocage dur — voir le plafond
	ci-dessus, esprit "watertight non bloquant" A3D-15) des aretes
	non-manifold (>= 3 faces liees) de chaque objet mesh de `objs`, APRES
	biseau/seconde decimation. Meme sequence de nettoyage que `_fill_holes`
	(doublons exacts PUIS eclats non stricts, voir `_remove_duplicate_faces`/
	`_remove_nonmanifold_slivers`), reappliquee ici car un objet dont
	`_fill_holes` avait deja verifie la proprete PLUS TOT dans le pipeline
	peut avoir ete re-sali par un poste ULTERIEUR (voir le commentaire de
	module ci-dessus). Renvoie {"duplicate_faces": int, "sliver_faces": int,
	"remaining_nonmanifold_edges": int, "skipped_max_edges": [str, ...]} —
	`skipped_max_edges` liste les objets dont le nombre d'aretes non-manifold
	depassait `NONMANIFOLD_FINAL_REPAIR_MAX_EDGES` AVANT reparation (exemptes,
	jamais touches par la passe non stricte).

	A3D-15 : deux mises a niveau AVANT de chercher une arete non-manifold, pour
	que la topologie VERIFIEE ici soit EXACTEMENT celle que `check_asset.py`
	mesurera ensuite sur le .glb exporte (jamais une approximation optimiste) :

	1. Ressoudage par POSITION (`bmesh.ops.remove_doubles`, distance
	   `_CHECK_ASSET_WELD_DIST_M` — EXACTEMENT la meme tolerance que
	   `check_asset.py::check_object` applique sur sa propre copie ressoudee,
	   jamais une valeur inventee ici) — releve concret de tache (wpn_magnum) :
	   un Decimate COLLAPSE (biseau/`decimate_group_to_budget`) peut faire
	   converger deux sommets vers des coordonnees SI PROCHES qu'elles se
	   soudent chez `check_asset.py` (qui, lui, ressoude par POSITION) sans
	   etre IDENTIQUES au sens de `bmesh` (qui ne partage une arete qu'entre
	   sommets litteralement identiques) — un defaut invisible ICI sans ce
	   ressoudage prealable, qui ne ressort qu'a la verification en aval, avec
	   un message bien moins precis. Fusionner ici ne change RIEN au rendu
	   exporte (les normales lissees/dures restent portees PAR FACE-CORNER,
	   jamais par sommet, dans le modele de donnees Blender — la fusion ne fait
	   que reveler la MEME topologie que verra `check_asset.py`).
	2. Triangule TOUT `bm` (`ngon_method='EAR_CLIP'`, meme choix que
	   `_fill_holes`) — releve concret de tache (wpn_fracas "pompe") : le
	   biseau (`toonkit.apply_stylekit_shading`) peut laisser des n-gones
	   (capuchons de biseau) sur le maillage de travail ; verifier les aretes
	   AVANT triangulation manque exactement le defaut que `_fill_holes`
	   documente deja (une triangulation IMPLICITE differente, a l'export
	   glTF, peut partager une arete entre 3 triangles ou plus alors qu'aucune
	   arete du n-gone d'origine n'etait elle-meme non-manifold)."""
	total_dupes = 0
	total_slivers = 0
	total_remaining = 0
	skipped = []
	for obj in objs:
		if obj is None or obj.type != 'MESH':
			continue
		me = obj.data
		bm = bmesh.new()
		bm.from_mesh(me)
		bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=_CHECK_ASSET_WELD_DIST_M)
		ngons = [f for f in bm.faces if len(f.verts) > 3]
		if ngons:
			bmesh.ops.triangulate(bm, faces=ngons, ngon_method='EAR_CLIP')
		dupes = _remove_duplicate_faces(bm)
		bad = [e for e in bm.edges if len(e.link_faces) >= 3]
		if bad and len(bad) <= NONMANIFOLD_FINAL_REPAIR_MAX_EDGES:
			slivers = _remove_nonmanifold_slivers(bm, bad, strict=False)
			bad = [e for e in bm.edges if len(e.link_faces) >= 3] if slivers else bad
		else:
			slivers = 0
			if bad:
				skipped.append(obj.name)
		bm.to_mesh(me)
		bm.free()
		me.update()
		total_dupes += dupes
		total_slivers += slivers
		total_remaining += len(bad)
	return {
		"duplicate_faces": total_dupes,
		"sliver_faces": total_slivers,
		"remaining_nonmanifold_edges": total_remaining,
		"skipped_max_edges": skipped,
	}


# ---------------------------------------------------------------------------
# Etape 8 (revue) — turntable dans un sous-process Blender dedie (meme regard
# qu'un asset "maison", docs/3D_PIPELINE.md §1/§6). `bpy.app.binary_path` est
# l'executable Blender EN COURS (celui qui fait tourner ce meme script), donc
# toujours coherent avec la version qui a produit le .glb.
# ---------------------------------------------------------------------------

def run_turntable(glb_path: str, views: int = 8, size: int = 512, timeout_s: int = 600) -> str:
	cmd = [
		bpy.app.binary_path, "-b", "--factory-startup", "--python-exit-code", "1",
		"-P", TURNTABLE_SCRIPT, "--",
		"--in", glb_path, "--views", str(views), "--size", str(size),
	]
	proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
	if proc.returncode != 0:
		raise RuntimeError(
			f"ai_restyle: le turntable a echoue (code {proc.returncode}) pour {glb_path}\n"
			f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}")
	# turntable.py imprime "TURNTABLE_OK ..." PUIS le chemin de la planche sur
	# la ligne suivante (voir son main()) : on va chercher CE marqueur plutot
	# que de prendre "la derniere ligne" telle quelle -- Blender ecrit son
	# propre banniere de sortie ("Blender X.Y.Z ...", "Blender quit") sur
	# stdout APRES la fin du script en mode -b, ce qui la ferait sinon passer
	# pour le chemin (constate en sondage, voir rapport de tache).
	lines = proc.stdout.splitlines()
	for i, line in enumerate(lines):
		if line.strip().startswith("TURNTABLE_OK") and i + 1 < len(lines):
			path = lines[i + 1].strip()
			if path:
				return path
	raise RuntimeError(
		f"ai_restyle: pas de marqueur TURNTABLE_OK dans la sortie du turntable pour {glb_path}\n"
		f"--- stdout ---\n{proc.stdout}")


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

def restyle(in_path: str, out_path: str, budget: int, family: str,
		merge_ratio: float = MERGE_DIST_RATIO, island_gap_tolerance: float = ISLAND_GAP_TOLERANCE_M,
		turntable_views: int = 8, turntable_size: int = 512, skip_turntable: bool = False,
		bevel_class: str = None, parts_spec: dict = None) -> dict:
	toonkit.reset_scene()
	mesh_objs = import_asset(in_path)
	if not mesh_objs:
		raise RuntimeError(f"ai_restyle: aucun mesh dans {in_path}")
	obj = toonkit.join(mesh_objs) if len(mesh_objs) > 1 else mesh_objs[0]

	# `apply_transforms` TOT, mais SEULEMENT si l'objet porte reellement un
	# scale/rotation/location non resolu (voir `_needs_early_scale_fix`) : un
	# GLB IA laisse parfois un node-scale non resolu (obj.scale != 1, voir
	# fixture 3 du rapport de tache), et le modificateur Remesh Voxel s'est
	# revele INSTABLE tant que cette echelle traine (sondage : la MEME taille
	# de voxel, en unites locales, se comporte en no-op silencieux sur une
	# large bande de valeurs quand `obj.scale` est petit et non applique) —
	# bake l'echelle/rotation ici ecarte cette instabilite AVANT
	# `ensure_watertight`/`decimate_to_budget`. On n'appelle PAS cette meme
	# fonction sur un objet DEJA a l'identite (cas courant d'un export
	# `export_apply=True`) : sondage — l'operateur laisse une trace qui
	# perturbe le Remesh Voxel plus loin MEME quand il n'avait rien a
	# appliquer, un effet de bord non explique par ailleurs, evite en ne
	# l'appelant que quand il a effectivement du travail a faire.
	if _needs_early_scale_fix(obj):
		toonkit.apply_transforms(obj)

	merged_vertices = merge_by_distance(obj, ratio=merge_ratio)
	# A3D-15 : APRES la fusion de sommets (un doublon de face ne partage
	# generalement le MEME ensemble de sommets qu'une fois les sommets quasi
	# confondus fusionnes), AVANT tout le reste (palette/etancheite/
	# separation de pieces) — un doublon ou un eclat degenere non retire ici
	# cree une arete non-manifold (>= 3 faces) qui peut ressortir n'importe ou
	# en aval, y compris sur le corps entier (releve concret : cs_deck_crane)
	# ou apres separation d'une piece (wpn_faucheur) — voir
	# `repair_nonmanifold_edges`.
	nonmanifold_repair = repair_nonmanifold_edges(obj)
	removed_faces = remove_isolated_islands(obj, gap_tolerance=island_gap_tolerance)

	report_slots = []
	restyle_materials(obj, report_slots)

	watertight_fix = ensure_watertight(obj)

	decimate_to_budget(obj, budget)

	# Separation des pieces mobiles (armes, docs/assets/ASSET_PLAN.md §3.5) —
	# APRES la decimation (un seul budget a verifier sur le maillage encore
	# joint, plus simple qu'un budget reparti entre plusieurs objets) et AVANT
	# le biseau/les normales/le masque unifie (chaque piece detachee doit
	# recevoir le MEME traitement de rendu que le corps, voir la boucle
	# ci-dessous — sinon une piece separee exporterait sans COLOR_0/biseau).
	part_objs = []
	marker_objs = []
	if parts_spec:
		part_objs = separate_parts(obj, parts_spec.get("parts", []))
		for marker in parts_spec.get("markers", []):
			marker_objs.append(create_marker(marker["name"], marker["position"]))

	# A3D-15 : `separate_parts` (boite locale, `bpy.ops.mesh.separate`) peut
	# laisser, en effet de bord, un morceau du corps restant desormais disjoint
	# du reste de SA PROPRE geometrie (ex. une facette fine qui n'etait reliee
	# au corps QUE par des faces tombees dans la boite de la piece separee) —
	# jamais detecte par le `_drop_floating_islands` plus haut (dans
	# `ensure_watertight`, qui tourne AVANT cette separation sur le maillage
	# encore entier) ni par `_fill_holes` (qui ne fait que reboucher un bord,
	# jamais verifier la connexite du resultat). Releve concret de tache
	# (wpn_pistolet, vague 1) : `check_asset.py::CHK-16` trouvait, apres
	# export, jusqu'a 7 pieces flottantes a 8-18 cm du corps sur un maillage
	# dont `ensure_watertight` n'avait pourtant rien remesh ni rien jete
	# (watertight_fix vide, remesh_failed=True) — la fragmentation venait de
	# `separate_parts` lui-meme, jamais de l'etancheite. On rejoue donc le
	# MEME filet (`_drop_floating_islands`, deja teste et trace plus haut) sur
	# le corps ET sur chaque piece fraichement separee — jamais une perte
	# silencieuse : comptee dans le rapport JSON
	# (`post_separation_dropped_faces`), jamais fondue dans
	# `watertight_fix["dropped_disconnected_faces"]` (une notion distincte,
	# survenant a une etape distincte du pipeline).
	post_separation_dropped_faces = 0
	for mesh_obj in [obj] + part_objs:
		post_separation_dropped_faces += _drop_floating_islands(mesh_obj)

	# Biseau par classe + normales ponderees + normale lissee (coque de
	# contour) + masque vertex unifie COLOR_0 (AO/convexite/hauteur/zone) —
	# docs/STYLE_BIBLE.md §7.9, meme sequence que toonkit.apply_stylekit_shading
	# (bevel_for_class -> weighted_normals -> smooth_normal_attrs ->
	# bake_vertex_masks), appliquee a CHAQUE objet mesh de l'asset (corps ET
	# pieces separees : une piece qui reculerait de ce traitement exporterait
	# sans COLOR_0, echouant le critere G3/check_asset en aval).
	effective_bevel_class = bevel_class or DEFAULT_BEVEL_CLASS_BY_FAMILY.get(family, "prop_crate")
	for mesh_obj in [obj] + part_objs:
		toonkit.apply_stylekit_shading(mesh_obj, effective_bevel_class)

	# Budget TENU APRES le biseau (A3D-15) : le biseau ci-dessus AJOUTE des
	# triangles sur chaque arete vive (voir toonkit.BEVEL_CLASSES) — sur un
	# maillage Smart Mesh deja bas-poly (donc souvent tres en dessous du
	# budget AVANT ce point, `decimate_to_budget` plus haut n'ayant alors rien
	# eu a faire), cet ajout a lui seul peut repasser au-dessus du budget.
	# Deuxieme passe de decimation, ICI seulement (jamais quand elle n'est pas
	# necessaire, pour ne pas emousser un biseau qui tenait deja son budget),
	# sur le GROUPE corps+pieces separees (`decimate_group_to_budget` : un
	# budget total, pas un budget par objet — une piece separee minuscule ne
	# doit jamais, a elle seule, epuiser les iterations pendant que le corps
	# garde tout son exces).
	all_mesh_objs_pre_export = [obj] + part_objs
	if toonkit.tri_count(all_mesh_objs_pre_export) > budget:
		decimate_group_to_budget(all_mesh_objs_pre_export, budget, max_iterations=DECIMATE_GROUP_MAX_ITERATIONS)

	# A3D-15 : le biseau (toonkit.apply_stylekit_shading, ci-dessus) ET la
	# seconde decimation qu'il peut declencher (decimate_group_to_budget,
	# ci-dessus) peuvent CHACUN fragmenter un objet deja propre en ilots
	# desormais disjoints (un biseau sur une arete fine peut detacher un
	# eclat ; un Decimate COLLAPSE agressif peut de meme separer une portion
	# mince du reste) — un mode de defaillance DISTINCT de celui deja trace
	# par `post_separation_dropped_faces` ci-dessus (qui ne couvre que l'effet
	# de bord de `separate_parts`, AVANT le biseau/cette seconde decimation).
	# Releve concret de tache (vague 1 : wpn_pistolet, wpn_magnum, wpn_rafale
	# jusqu'a 37 echecs CHK-16, wpn_marqueur, wpn_faucheur — des pieces
	# flottantes a 1 cm a 35 cm du corps, jamais presentes avant le biseau)
	# — meme filet (`_drop_floating_islands`), rejoue ICI sur CHAQUE objet
	# mesh de l'asset, jamais une perte silencieuse (compte dans le rapport
	# JSON, `post_bevel_dropped_faces`, une notion distincte de
	# `post_separation_dropped_faces` et de `watertight_fix
	# ["dropped_disconnected_faces"]`, chacune survenant a une etape propre du
	# pipeline).
	post_bevel_dropped_faces = 0
	for mesh_obj in all_mesh_objs_pre_export:
		post_bevel_dropped_faces += _drop_floating_islands(mesh_obj)

	# A3D-15 : reparation non-manifold FINALE — voir `_repair_nonmanifold_final`
	# (juste au-dessus de `restyle`) pour le releve de tache complet (arete
	# introduite par le biseau/la seconde decimation, jamais presente avant,
	# jamais couverte par `_drop_floating_islands` ci-dessus qui ne traite que
	# les ilots DISJOINTS, pas une arete a 3+ faces sur un maillage restant
	# connexe). Rejouee ICI, sur CHAQUE objet mesh de l'asset, APRES le dernier
	# poste connu a pouvoir introduire ce defaut (le filet anti-ilots
	# ci-dessus) et AVANT la mesure de `final_tris` (une reparation retire des
	# faces, donc change le compte de triangles exporte).
	post_bevel_nonmanifold_repair = _repair_nonmanifold_final(all_mesh_objs_pre_export)

	# Filet de securite final (docs/3D_PIPELINE.md §6, position documentee) :
	# no-op si le bloc ci-dessus a deja tout applique, mais garantit un
	# scale/rotation identite avant l'export meme dans un chemin qui n'aurait
	# pas eu besoin de remesh (donc jamais passe par le bloc precedent). Ne
	# porte que sur `obj` (le corps) : les pieces separees heritent DEJA du
	# repere local de `obj` au moment de la separation (memes coordonnees,
	# `bpy.ops.mesh.separate` ne deplace rien) — leur position MONDE reste
	# donc correcte sans appel separe, meme si `obj` change ensuite d'origine
	# (set_origin_bottom ne fait que deplacer le PIVOT de `obj`, jamais sa
	# geometrie monde ni celle des autres objets).
	toonkit.apply_transforms(obj)
	toonkit.set_origin_bottom(obj)

	all_mesh_objs = [obj] + part_objs
	final_tris = toonkit.tri_count(all_mesh_objs)
	if final_tris > budget:
		raise RuntimeError(
			f"ai_restyle: budget depasse apres decimation : {final_tris} > {budget} tris "
			f"(topologie trop dense pour ce budget en {DECIMATE_GROUP_MAX_ITERATIONS} passes de Decimate)")

	# Kinds REELLEMENT presents sur le maillage exporte — pas la classification
	# d'origine de `report_slots` : `ensure_watertight` a pu en sacrifier une
	# partie (voir `watertight_fix`) si un remesh global a ete necessaire.
	assigned_kinds = sorted({m.name for o in all_mesh_objs for m in o.data.materials if m is not None})
	unknown_kinds = [k for k in assigned_kinds if k not in CANDIDATE_KINDS]
	if unknown_kinds:
		# Ne peut arriver que si CANDIDATE_KINDS a change sous nos pieds entre
		# la classification et ici — garde-fou, jamais attendu en pratique.
		raise RuntimeError(f"ai_restyle: kind(s) hors vocabulaire connu assigne(s): {unknown_kinds}")

	# Garde-fou final avant l'export : un export avec `export_apply=True`
	# REEVALUE et reapplique tout modificateur encore empile au moment de
	# l'export — APRES que `final_tris` ci-dessus a deja ete mesure et valide
	# contre le budget (voir `_apply_modifier` pour le mecanisme de corruption
	# exact que ceci empeche). `_apply_modifier` garantit deja qu'aucun
	# modificateur ne survit a son propre appel, donc ce garde-fou ne devrait
	# jamais se declencher en pratique — mais le verifier EXPLICITEMENT ici,
	# avant l'export, est la seule facon de ne jamais exporter en silence une
	# geometrie differente de celle mesuree.
	for mesh_obj in all_mesh_objs:
		if mesh_obj.modifiers:
			raise RuntimeError(
				f"ai_restyle: {len(mesh_obj.modifiers)} modificateur(s) encore empile(s) sur "
				f"\"{mesh_obj.name}\" avant l'export ({[m.name for m in mesh_obj.modifiers]}) — "
				"un export avec export_apply=True les reappliquerait en silence APRES la mesure "
				"de final_tris, corrompant la geometrie reellement ecrite sur disque")

	if part_objs or marker_objs:
		export_info = export_with_markers(out_path, all_mesh_objs, marker_objs)
	else:
		toonkit.export_glb(out_path, obj)
		export_info = {"tris": final_tris, "nodes": [obj.name]}

	report = {
		"input": os.path.abspath(in_path),
		"output": os.path.abspath(out_path),
		"family": family,
		"budget_tris": budget,
		"final_tris": final_tris,
		"merged_vertices": merged_vertices,
		"nonmanifold_repair": nonmanifold_repair,
		"removed_isolated_faces": removed_faces,
		"post_separation_dropped_faces": post_separation_dropped_faces,
		"post_bevel_dropped_faces": post_bevel_dropped_faces,
		"post_bevel_nonmanifold_repair": post_bevel_nonmanifold_repair,
		"watertight_fix": watertight_fix,
		"slots": report_slots,
		"assigned_kinds": assigned_kinds,
		# La couleur EXPORTEE de chaque slot est toujours toonkit.palette(kind)
		# telle quelle (voir restyle_materials) : delta E slot -> palette = 0
		# par construction, quel que soit l'ecart mesure ci-dessus entre
		# l'echantillon IA d'origine et le kind choisi.
		"delta_e_output_to_palette": 0.0,
		"bevel_class": effective_bevel_class,
		"nodes": export_info["nodes"],
		"parts": [p.name for p in part_objs],
		"markers": [m.name for m in marker_objs],
	}

	turntable_path = None
	if not skip_turntable:
		turntable_path = run_turntable(out_path, views=turntable_views, size=turntable_size)
	report["turntable_contact_sheet"] = turntable_path

	report_path = os.path.splitext(out_path)[0] + ".ai_restyle.json"
	with open(report_path, "w", encoding="utf-8") as f:
		json.dump(report, f, indent=2, ensure_ascii=False)

	print(f"AI_RESTYLE_OK {os.path.basename(out_path)} tris={final_tris} kinds={assigned_kinds}")
	print(f"AI_RESTYLE_REPORT {report_path}")
	if turntable_path:
		print(turntable_path)
	return report


def parse_args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	p = argparse.ArgumentParser()
	p.add_argument("--in", dest="in_path", required=True)
	p.add_argument("--out", dest="out_path", required=True)
	p.add_argument("--family", default="props")
	p.add_argument("--budget", dest="budget", type=int, default=None)
	p.add_argument("--views", dest="views", type=int, default=8)
	p.add_argument("--size", dest="size", type=int, default=512)
	p.add_argument("--merge-ratio", dest="merge_ratio", type=float, default=MERGE_DIST_RATIO)
	p.add_argument("--island-gap-tolerance", dest="island_gap_tolerance", type=float,
		default=ISLAND_GAP_TOLERANCE_M)
	p.add_argument("--bevel-class", dest="bevel_class", default=None,
		help="classe toonkit.BEVEL_CLASSES (defaut derive de --family, voir DEFAULT_BEVEL_CLASS_BY_FAMILY)")
	p.add_argument("--parts", dest="parts_path", default=None,
		help="JSON {'parts': [{'name','box_min','box_max'}...], 'markers': [{'name','position'}...]} "
			"(voir separate_parts/create_marker) — pieces mobiles + marqueurs Muzzle/Foregrip d'une arme")
	p.add_argument("--skip-turntable", dest="skip_turntable", action="store_true",
		help="saute le rendu turntable (iteration rapide — jamais pour une livraison)")
	return p.parse_args(argv)


def main() -> None:
	args = parse_args()
	in_path = os.path.abspath(args.in_path)
	if not os.path.isfile(in_path):
		print(f"AI_RESTYLE_FAIL fichier introuvable: {in_path}")
		sys.exit(1)
	budget = args.budget if args.budget is not None else FAMILY_BUDGETS.get(args.family)
	if budget is None:
		print(f"AI_RESTYLE_FAIL --budget omis et famille \"{args.family}\" sans budget par defaut "
			f"(connues: {sorted(FAMILY_BUDGETS)})")
		sys.exit(1)
	out_path = os.path.abspath(args.out_path)
	parts_spec = load_parts_spec(args.parts_path) if args.parts_path else None
	restyle(
		in_path, out_path, budget, args.family,
		merge_ratio=args.merge_ratio, island_gap_tolerance=args.island_gap_tolerance,
		turntable_views=args.views, turntable_size=args.size, skip_turntable=args.skip_turntable,
		bevel_class=args.bevel_class, parts_spec=parts_spec,
	)


if __name__ == "__main__":
	main()
