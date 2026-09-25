## tools/blender/rig_tripo_character.py
## Rigge un maillage Tripo (image->3D, "forme seule" : UN matériau, UNE
## texture 2K bakée, AUCUN squelette — voir docs/AI_TOOLS.md §Tripo) sur le
## squelette COMMUN des 6 agents (UAL-G, 53 os `DEF-`, 46 actions — la MÊME
## armature que tools/blender/make_characters.py, importée depuis la même
## source `ual.glb`), en GARDANT la texture d'origine (contrairement à
## make_characters.py, qui construit des vêtements plaqués sur le mannequin
## nu avec des slots de couleur plate — ce script part d'un maillage DÉJÀ
## habillé et texturé, livré par un outil externe).
##
##   blender -b -P tools/blender/rig_tripo_character.py -- --in <glb Tripo>
##       --id <agent_id> [--weld-dist D] [--out DIR]
##
## §Notes ART-11Z (bug corrigé par cette passe, bande démo anim_reel du
## 2026-09-24) : la version précédente posait les bras sur une cible FIXE
## (0,15 ; 0,05 ; -0,97) puis appliquait cette pose comme NOUVEAU REPOS
## (`pose.armature_apply`) juste avant la liaison par poids automatiques. Or
## les 46 actions UAL sont des rotations LOCALES relatives au repos — changer
## le repos change donc ce que la MÊME action produit une fois rejouée : dans
## les 46 animations (authored contre le repos T-pose D'ORIGINE de `ual.glb`),
## chaque delta qui abaissait déjà les bras les repoussait une SECONDE fois
## une fois le repos changé (bras croisés/tordus/traversant le torse). La
## cible fixe ne correspondait en plus pas aux maillages Tripo, livrés en
## A-pose (bras à ~40° du corps, jamais bras-le-long-du-corps — voir
## docs/style/character_prompts.md, "both arms held about 40 degrees away
## from the body"), pas au gabarit qui avait servi à la calibrer.
## Correctif : la liaison par poids automatiques a TOUJOURS besoin d'un
## repos posé qui coïncide avec la pose réelle du maillage (§ci-dessous,
## étape 4) — mais ce repos de LIAISON reste TEMPORAIRE : une fois le
## skinning calculé, le squelette est reposé sur son orientation T-pose
## D'ORIGINE (mesurée avant toute modification), le maillage est CUIT dans
## cette pose (le modificateur Armature appliqué transforme la géométrie
## brute, poids de peau inchangés), puis ce même repos T-pose est réappliqué
## comme repos FINAL — identique à `ual.glb`, os par os (voir
## `_restore_original_rest` et le critère d'acceptation ART-11Z, vérifié en
## fin de script par `_compare_rest_to_source`). Les 46 actions retrouvent
## alors exactement le repos pour lequel elles ont été animées.
##
## Étapes (voir docstring de chaque fonction pour le détail/les mesures) :
##   1. import + réparation des arêtes non-manifold (sondé : 21 sur
##      assets/incoming/tripo/verrou_v1.glb, un repli de sangle/pochette de
##      ceinturon localisé sur ~5 cm — PAS un défaut de fusion par distance
##      simple, voir `_repair_nonmanifold`) ;
##   2. mise à l'échelle 1,80 m pieds à l'origine (gabarit commun,
##      docs/STYLE_BIBLE.md §4) ;
##   3. import du squelette commun (mêmes 46 actions), mis À LA MÊME échelle
##      1,80 m (proportions générales) — la direction de repos T-pose
##      D'ORIGINE des bras est mesurée ICI, avant toute pose (`_bone_rest_dir`),
##      pour pouvoir y revenir exactement à l'étape 5b ;
##   4. MESURE la direction RÉELLE des bras du maillage Tripo (axe principal
##      des sommets au-delà de l'épaule, par côté — `_measure_arm_axis`, PAS
##      une cible fixe, cf. §Notes ART-11Z), pose les bras du squelette
##      commun sur cette direction mesurée PUIS applique cette pose comme
##      repos TEMPORAIRE de liaison (`_apply_bind_rest`) — condition
##      nécessaire pour que la liaison par poids automatiques (heat
##      weighting, proximité squelette/maillage) capture correctement les
##      bras au lieu de tout assigner au torse le plus proche ;
##   5. liaison du maillage par poids automatiques (`ARMATURE_AUTO`) ;
##   5a. §Notes ART-11X (Choc/ART-11C fusionnée ici) : les petits îlots
##      topologiques détachés (Smart Mesh Tripo — bord de couvre-chef,
##      lunettes, réservoir, collerette, basques...) sont RIGIDIFIÉS (100% de
##      poids sur l'os du sommet du corps principal le plus proche, jamais de
##      mélange qui étire — voir `_rigidify_small_islands`) ; l'objet-widget
##      parasite "Icosphere" créé par l'IMPORTEUR glTF de `ual.glb` est retiré
##      (`_purge_icosphere_widgets`) ;
##   5b. le squelette est reposé sur son orientation T-pose D'ORIGINE (mesurée
##      à l'étape 3), le maillage est CUIT dans cette pose (modificateur
##      Armature appliqué), ce même repos T-pose est réappliqué comme repos
##      FINAL et le modificateur Armature est remis (mêmes groupes de sommets,
##      jamais reliés une seconde fois) — voir `_restore_original_rest` ;
##   6. le matériau unique du maillage Tripo est renommé `f"{id}_tex"`
##      (texture conservée telle quelle — aucun repeint, contrairement aux 6
##      agents "maison") ;
##   7. export avec les 46 actions (mêmes réglages `export_scene.gltf` que
##      make_characters.py : `ACTIONS`, `export_apply=False`) ;
##   8. vérification numérique du repos exporté contre `ual.glb`, os par os
##      (`_compare_rest_to_source`, critère d'acceptation ART-11Z : écart
##      d'orientation < `REST_ORIENTATION_TOLERANCE_DEG`).
##
## Vérifier ensuite (docs/3D_PIPELINE.md §1) :
##   blender -b -P tools/blender/check_asset.py -- --in <sortie> --asset-class character
##   godot --path . -s tools/character_shots.gd -- --out=<dossier>
import argparse
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector, Matrix

TARGET_HEIGHT = 1.80  # gabarit commun, docs/STYLE_BIBLE.md §4 : "1,80 m pile, tout compris".

# Même mécanisme de surcharge que tools/blender/make_characters.py (source
# NON committée — seuls les .glb dérivés dans assets/models/characters/ le
# sont) : `UAL_SOURCE_GLB` pointe par défaut vers le scratchpad de la tâche
# qui a téléchargé `ual.glb` (Quaternius "Universal Animation Library",
# CC0 1.0 — voir THIRD_PARTY_LICENSES.md), relançable via la variable d'env.
UAL_SOURCE_GLB = os.environ.get(
	"UAL_SOURCE_GLB",
	r"C:/Users/srko/AppData/Local/Temp/claude/C--Users-srko-Desktop-fps/"
	r"02e156fb-5e66-4722-9835-071a024d62a9/scratchpad/downloads/ual/ual.glb",
)

_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(_ROOT, "assets", "models", "characters")

# Distance de fusion pour DÉTECTER les arêtes non-manifold — même seuil que
# `tools/blender/check_asset.py` (`bm_welded`, dist=1e-4) : au-delà, la fusion
# se met à souder des surfaces PROCHES mais topologiquement distinctes
# (doigts/lanières contre le tissu) et EN CRÉE de nouvelles (sondé : 21 à
# 5e-5/1e-4/2e-4, mais 23 à 5e-4 et 28 à 1e-3 — la fusion par distance seule
# n'est PAS le bon outil de réparation ici, voir `_repair_nonmanifold`).
NONMANIFOLD_WELD_DIST = 0.0001

# Chaîne bras droit (colinéaire en T-pose, UAL-G) reposée d'un seul bloc —
# même choix que `make_characters._pose_fp_hold` (bras TENDU, pas de coude
# plié) et pour la MÊME raison : le poids de peau au coude, une fois lié,
# mélange un peu upper_arm/forearm (heat weighting, transition continue) ;
# une SEULE direction par bras élimine le risque de blob difforme si jamais
# la liaison automatique répartit un sommet entre deux segments pliés
# différemment. La direction ciblée n'est PLUS une constante fixe (§Notes
# ART-11Z, tête de fichier) : `_measure_arm_axis` la mesure sur le maillage
# RÉEL de chaque agent, par côté.
_ARM_CHAIN = ("upper_arm", "forearm", "hand")

# Marge (mètres, monde) au-delà de la position X de l'épaule (`DEF-shoulder.
# <side>.tail_local`, même ancre que `_pose_arm_chain`) pour qu'un sommet du
# maillage soit considéré comme appartenant au bras plutôt qu'au torse —
# sondé sur le gabarit commun (épaule ~0,19 m du centre à 1,80 m, cf.
# `make_characters.py` §"Ancres clés") : le buste ne dépasse jamais ce point,
# alors que le bras (tenu ~40° du corps, cf. docs/style/character_prompts.md)
# s'en écarte tout de suite, épaule comprise. Volontairement PETIT : on veut
# capturer tout le bras (épaule -> main), pas seulement l'avant-bras, pour
# que l'axe principal (PCA) porte sur toute la longueur du membre.
_ARM_SIDE_MARGIN_M = 0.03

# Nombre minimal de sommets "au-delà de l'épaule" pour qu'une mesure d'axe
# soit fiable — en dessous, `_measure_arm_axis` échoue fort plutôt que de
# renvoyer un axe construit sur un échantillon non représentatif (bruit de
# maillage, îlot topologique isolé confondu avec le bras...).
_ARM_MIN_SAMPLE_VERTS = 30

# Itérations de la méthode de la puissance (PCA sans dépendance à numpy, non
# garanti dans le Python embarqué de Blender selon la distribution) pour
# extraire l'axe principal (plus grande valeur propre) de la matrice de
# covariance des sommets du bras — un bras est une forme fortement allongée
# dans une seule direction (rapport de valeurs propres élevé), donc la
# convergence est rapide ; cette marge reste largement suffisante (sondé :
# stable dès ~5 itérations sur verrou_v1.glb/vif_v1.glb).
_PCA_POWER_ITERATIONS = 12

# Rayon (mètres) autour de l'axe mesuré, au-delà duquel un sommet est écarté
# de l'échantillon lors de l'élagage itératif (`_measure_arm_axis` — RANSAC
# simplifié) : un bras/avant-bras est un tube d'un rayon de quelques
# centimètres, jamais plus de ~10-12 cm même déformé/gainé ; un vêtement
# ample (poncho, manteau) proche du bras au repos de liaison, lui, s'écarte
# largement au-delà. Choisi généreux (couvre un bras + marge) pour ne jamais
# élaguer le bras lui-même par erreur.
_ARM_AXIS_TRIM_RADIUS_M = 0.12

# Passes d'élagage de `_measure_arm_axis` — chaque passe resserre
# l'échantillon puis recalcule le PCA dessus ; converge vite (un vêtement
# ample, une fois écarté, ne revient jamais dans un rayon de bras).
_ARM_AXIS_TRIM_ITERATIONS = 3

# Tolérance d'écart d'orientation (degrés), par os `DEF-`, entre le repos
# exporté et celui de `ual.glb` — critère d'acceptation ART-11Z, vérifié par
# `_compare_rest_to_source`.
REST_ORIENTATION_TOLERANCE_DEG = 0.5


def parse_args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	p = argparse.ArgumentParser()
	p.add_argument("--in", dest="in_path", required=True)
	p.add_argument("--id", dest="char_id", required=True)
	p.add_argument("--weld-dist", dest="weld_dist", type=float, default=NONMANIFOLD_WELD_DIST)
	p.add_argument("--out", dest="out_dir", default=OUT_DIR)
	p.add_argument("--weights", dest="weights", choices=("mannequin", "heat"), default="mannequin",
		help="mannequin : copie des poids du mannequin UAL (défaut) ; heat : poids automatiques Blender")
	return p.parse_args(argv)


def _clear_scene() -> None:
	for o in list(bpy.data.objects):
		bpy.data.objects.remove(o, do_unlink=True)
	for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.armatures, bpy.data.images):
		for block in list(coll):
			if block.users == 0:
				coll.remove(block)


def _import_tripo(path: str) -> "bpy.types.Object":
	bpy.ops.import_scene.gltf(filepath=path)
	meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
	if not meshes:
		raise RuntimeError("rig_tripo_character: aucun maillage dans %r" % path)
	if len(meshes) > 1:
		# Un seul objet mesh attendu (forme Tripo unique) — sondé sur
		# verrou_v1.glb : 1 objet. Si un futur export en a plusieurs, on les
		# fusionne (même géométrie exportée au final, un seul matériau visé).
		bpy.ops.object.select_all(action='DESELECT')
		for m in meshes:
			m.select_set(True)
		bpy.context.view_layer.objects.active = meshes[0]
		bpy.ops.object.join()
	return bpy.context.view_layer.objects.active if len(meshes) > 1 else meshes[0]


## Répare les arêtes non-manifold "dures" (>= 3 faces sur une même arête —
## le seul échec DUR de check_asset.py qui nous concerne ici, le maillage
## Tripo passant déjà les autres critères). Fusion par distance seule NE
## SUFFIT PAS (voir NONMANIFOLD_WELD_DIST) : sondé sur verrou_v1.glb, les 21
## arêtes en défaut forment un unique petit repli localisé (~5 cm, 26
## sommets, sur le rabat d'une sangle/pochette de ceinturon) — un vrai pli de
## géométrie superposée, pas une paire de sommets quasi-coïncidents. La
## fusion NE CHANGE MÊME PAS le nombre de triangles à ces seuils (sondé :
## 14449 -> 14449), elle ne fait que consolider les doublons de couture UV
## (16362 sommets position -> 7446 après fusion, sans toucher aux faces) —
## comportement NORMAL d'un réimport glTF (une position dupliquée par UV
## différente à CHAQUE couture, cf. l'en-tête de check_asset.py) : on ne
## fusionne donc JAMAIS le maillage RÉEL (ça perdrait les UV d'un côté de
## chaque couture), seulement une COPIE jetable qui sert à repérer les
## arêtes en défaut.
##
## Technique de réparation (sur le maillage RÉEL, indices de face alignés 1:1
## sur la copie soudée tant qu'aucune face n'est supprimée par la fusion —
## vérifié par sondage : `bm.copy()` puis `remove_doubles` à ce seuil laisse
## le même nombre de faces, dans le même ordre, sur cet asset) : tant qu'il
## reste une arête à >= 3 faces, on retire la PLUS PETITE face qui la borde
## (répété jusqu'à convergence — sondé : 19 faces supprimées suffisent pour
## les 21 arêtes de verrou_v1.glb, sur 14449 au total, donc largement sous le
## budget). Les quelques arêtes de bord nouvellement ouvertes par ces
## suppressions (PAS les bords ouverts préexistants du maillage, volontaires
## ailleurs — un maillage Tripo n'est pas nécessairement étanche, cf.
## check_asset.py : "boundary_edges" n'est qu'un avertissement) sont
## rebouchées du mieux possible (`holes_fill`) ; les quelques nouvelles faces
## ainsi créées n'ont pas d'UV pertinente, mais elles sont minuscules et
## cachées dans le même repli localisé de ~5 cm — sans impact visuel en jeu.
def _repair_nonmanifold(mesh_obj: "bpy.types.Object", weld_dist: float) -> int:
	bm = bmesh.new()
	bm.from_mesh(mesh_obj.data)
	bm.faces.ensure_lookup_table()
	bm.edges.ensure_lookup_table()

	bm_check = bm.copy()
	bmesh.ops.remove_doubles(bm_check, verts=bm_check.verts, dist=weld_dist)
	bm_check.faces.ensure_lookup_table()
	if len(bm_check.faces) != len(bm.faces):
		# La fusion a fait disparaître une face dégénérée : l'alignement
		# d'indices n'est plus garanti -> on abandonne la réparation
		# chirurgicale plutôt que de risquer de supprimer la mauvaise face.
		print("RIG_TRIPO_WARN fusion a changé le nombre de faces (%d -> %d) : "
			"réparation non-manifold ignorée, vérifier check_asset.py manuellement"
			% (len(bm.faces), len(bm_check.faces)))
		bm.to_mesh(mesh_obj.data)
		bm.free()
		bm_check.free()
		return 0

	before_boundary_keys = {
		frozenset(round(c, 5) for v in e.verts for c in v.co)
		for e in bm.edges if len(e.link_faces) == 1
	}

	deleted_indices: list = []
	for _ in range(len(bm_check.faces)):
		bad = [e for e in bm_check.edges if len(e.link_faces) >= 3]
		if not bad:
			break
		e = max(bad, key=lambda e: len(e.link_faces))
		f = min(e.link_faces, key=lambda f: f.calc_area())
		deleted_indices.append(f.index)
		bmesh.ops.delete(bm_check, geom=[f], context='FACES')
	bm_check.free()

	if deleted_indices:
		bm.faces.ensure_lookup_table()
		# `deleted_indices` peut contenir le même indice plusieurs fois : les
		# indices lus sur `bm_check` (ci-dessus) ne sont PAS garantis stables
		# d'une itération à l'autre après un `bmesh.ops.delete` (Blender peut
		# recompacter la table interne des faces restantes) — deux faces
		# distinctes de `bm_check`, supprimées à des passes différentes,
		# peuvent donc avoir livré la MÊME valeur de `.index`. Sans
		# dédoublonnage, `bm.faces[i]` renvoie alors DEUX FOIS le même objet
		# BMFace de `bm` dans `geom`, et `bmesh.ops.delete` échoue avec
		# « geom: found the same (BMVert/BMEdge/BMFace) used multiple times »
		# (sondé lors de la relance QA sur vif_v1.glb). `dict.fromkeys`
		# déduplique en gardant l'ordre de première apparition.
		unique_indices = list(dict.fromkeys(deleted_indices))
		bmesh.ops.delete(bm, geom=[bm.faces[i] for i in unique_indices], context='FACES')
		bm.normal_update()

	# Passe de convergence finale DIRECTEMENT sur le maillage réel (pas la
	# copie soudée) : une arête à >= 3 faces peut exister nativement (sans
	# fusion) indépendamment de celles détectées ci-dessus — sondé sur
	# verrou_v1.glb, 1 cas (une couture UV scinde l'arête fusionnée en
	# plusieurs arêtes réelles, chacune avec son propre compte de faces). Même
	# technique (plus petite face de la pire arête), répétée jusqu'à
	# convergence totale : le nombre de cas résiduels est toujours minuscule
	# (quelques unités au plus), jamais un deuxième passage sur toute la
	# fusion.
	extra_deleted = 0
	for _ in range(len(bm.faces)):
		bad = [e for e in bm.edges if len(e.link_faces) >= 3]
		if not bad:
			break
		e = max(bad, key=lambda e: len(e.link_faces))
		f = min(e.link_faces, key=lambda f: f.calc_area())
		bmesh.ops.delete(bm, geom=[f], context='FACES')
		extra_deleted += 1
	if extra_deleted:
		bm.normal_update()
		print("RIG_TRIPO_NONMANIFOLD passe directe supplémentaire : %d face(s)" % extra_deleted)

	new_boundary = [
		e for e in bm.edges if len(e.link_faces) == 1
		and frozenset(round(c, 5) for v in e.verts for c in v.co) not in before_boundary_keys
	]
	if new_boundary:
		bmesh.ops.holes_fill(bm, edges=new_boundary, sides=0)

	bad_left = sum(1 for e in bm.edges if len(e.link_faces) >= 3)
	total_repaired = len(deleted_indices) + extra_deleted
	if total_repaired:
		print("RIG_TRIPO_NONMANIFOLD réparées=%d restantes=%d" % (total_repaired, bad_left))

	bm.to_mesh(mesh_obj.data)
	mesh_obj.data.update()
	bm.free()
	return total_repaired


## Recale à 1,80 m (gabarit commun), pieds (Z mini de la bbox monde) à
## l'origine, centré en X/Y — même convention que `check_asset.py`
## (`origin_at_bottom_center`). Le maillage Tripo est DÉJÀ à l'origine
## centre-bas (sondé, `check_asset.py` sur verrou_v1.glb ne l'avertit pas),
## seule l'échelle change (hauteur normalisée Tripo ~1,00 m -> 1,80 m) —
## MAIS la formule ci-dessous reste correcte même si un futur import Tripo
## n'a pas déjà son origine pile au centre-bas (`obj.location` quelconque
## avant transform_apply) : `L_new = (L0 - centre) * facteur` place le
## point-repère centre-bas (mesuré en espace MONDE, donc valable quels que
## soient l'échelle/l'emplacement d'origine du fichier) exactement à l'origine
## monde une fois la nouvelle échelle appliquée (dérivation : world(p) =
## L0 + S0⊙p en l'absence de rotation, donc p_repère = (centre-L0)/S0 ; on
## veut L_new + (S0*facteur)⊙p_repère = 0, ce qui élimine S0 et donne
## exactement cette formule — sans le terme `L0 *`, un fichier source dont
## l'origine ne serait pas déjà proche du centre-bas finirait décentré).
def _rescale_feet_to_origin(obj: "bpy.types.Object", target_height: float) -> None:
	bpy.context.view_layer.update()
	corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
	min_v = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
	max_v = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
	height = max_v.z - min_v.z
	if height <= 0.0:
		raise RuntimeError("rig_tripo_character: hauteur nulle sur %r" % obj.name)
	scale = target_height / height
	center = Vector(((min_v.x + max_v.x) / 2.0, (min_v.y + max_v.y) / 2.0, min_v.z))
	old_location = obj.location.copy()
	obj.scale = obj.scale * scale
	obj.location = (old_location - center) * scale
	bpy.context.view_layer.update()
	with bpy.context.temp_override(object=obj, selected_editable_objects=[obj], active_object=obj):
		bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	print("RIG_TRIPO_SCALE hauteur_source=%.4f facteur=%.4f -> %.4f m" % (height, scale, target_height))


## Retire tout objet-widget « Icosphere » de la scène (repère d'affichage de
## `pose_bone.custom_shape`, jamais un objet du costume). §Notes ART-11X
## (échecs QA ART-11G/ART-11N) : ce widget est recréé par l'IMPORTEUR glTF
## lui-même à CHAQUE `import_scene.gltf(UAL_SOURCE_GLB)`, alors que le JSON
## glTF de `ual.glb` ne référence lui-même AUCUN mesh nommé "Icosphere"
## (vérifié par sondage direct sur le fichier : `bpy.data.objects` gagne un
## "Icosphere" dès l'import, un comportement de l'IMPORTEUR — probablement
## lié aux réglages d'affichage de bone stockés dans le glTF — pas du
## fichier source). Appelée juste après l'import du squelette commun ET,
## défensivement, juste avant CHAQUE export (`_do_export`) : élimine aussi un
## homonyme numéroté ("Icosphere.001", si jamais un import répété en laissait
## un orphelin) sans jamais toucher un objet du costume Tripo (nommé d'après
## le fichier source, ex. "guet_v1", ou "Rig"/"Mannequin").
def _purge_icosphere_widgets() -> int:
	removed = 0
	for o in list(bpy.data.objects):
		if o.name.split(".")[0] == "Icosphere":
			bpy.data.objects.remove(o, do_unlink=True)
			removed += 1
	return removed


## Importe le squelette commun (même source que make_characters.py) et
## renvoie `(rig, hauteur_mesurée_du_mannequin)`. Le mannequin sert
## UNIQUEMENT de référence de mesure (proportion du gabarit) — il est
## supprimé juste après, le maillage exporté restant celui de Tripo.
## Le mannequin UAL est CONSERVÉ (plus supprimé ici) : il sert de source de
## poids propre pour `_bind_from_mannequin` (mêmes 52 groupes `DEF-` que le
## squelette, sondé), puis il est retiré avant l'export.
def _import_common_rig() -> tuple:
	bpy.ops.import_scene.gltf(filepath=UAL_SOURCE_GLB)
	rig = bpy.data.objects["Rig"]
	mannequin = bpy.data.objects["Mannequin"]
	_purge_icosphere_widgets()
	bpy.context.view_layer.update()
	corners = [mannequin.matrix_world @ Vector(c) for c in mannequin.bound_box]
	height = max(c.z for c in corners) - min(c.z for c in corners)
	return rig, mannequin, height


## Même mise à l'échelle que `_scale_rig_uniform`, appliquée aux sommets du
## mannequin (repère monde, pieds à l'origine) : changer le repos des os en
## mode édition ne déforme pas le maillage lié, il faut donc le mettre à
## l'échelle séparément pour qu'il reste collé au squelette.
def _scale_mannequin(mannequin: "bpy.types.Object", factor: float) -> None:
	mannequin.data.transform(Matrix.Scale(factor, 4))
	mannequin.data.update()


## Ajuste le squelette commun aux proportions du modèle : mise à l'échelle
## UNIFORME de tous les os (édition directe des repos `head_local`/
## `tail_local`, PAS un scale d'objet — le rig reste à l'identité, comme
## make_characters.py l'attend) pour que le gabarit du squelette (mesuré sur
## SON mannequin de référence, ~1,83 m) rejoigne exactement la même hauteur
## cible que le maillage Tripo (1,80 m, cf. `_rescale_feet_to_origin`) : les
## deux repères coïncident avant la liaison par poids automatiques. Un
## ajustement plus fin (par membre : longueur de jambe/bras individuelle)
## demanderait une détection de repères anatomiques sur un maillage SANS
## squelette existant (silhouette, coupes horizontales...) — hors budget de
## cette passe pour un jeu stylisé en cel-shading dont le contrat accepte
## explicitement les "poids automatiques" ; la vérification reste visuelle
## (character_shots Idle/Sprint, cf. docs/3D_PIPELINE.md §1) plutôt qu'un
## seuil numérique de proportion.
def _scale_rig_uniform(rig: "bpy.types.Object", factor: float) -> None:
	bpy.context.view_layer.objects.active = rig
	bpy.ops.object.mode_set(mode='EDIT')
	for b in rig.data.edit_bones:
		b.head = b.head * factor
		b.tail = b.tail * factor
	bpy.ops.object.mode_set(mode='OBJECT')


def _bone_rest_dir(rig: "bpy.types.Object", name: str) -> Vector:
	b = rig.data.bones[name]
	return (b.tail_local - b.head_local).normalized()


def _bone_rest_length(rig: "bpy.types.Object", name: str) -> float:
	b = rig.data.bones[name]
	return (b.tail_local - b.head_local).length


## Axe principal (PCA, méthode de la puissance — voir `_PCA_POWER_ITERATIONS`)
## de `pts` (Vector, repère monde) autour de `anchor` : matrice de covariance
## résolue par itération de puissance (pas de dépendance à numpy). L'axe
## propre d'une matrice de covariance est une DROITE (signe ambigu) : orienté
## explicitement vers l'EXTÉRIEUR de `anchor` (jamais vers lui), en accord
## avec le sens géométrique "s'éloigne de l'épaule" attendu par les appelants.
def _pca_principal_axis(pts: list, anchor: "Vector") -> Vector:
	centroid = Vector((0.0, 0.0, 0.0))
	for p in pts:
		centroid += p
	centroid /= len(pts)

	cov_rows = [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for p in pts:
		d = p - centroid
		for i in range(3):
			for j in range(3):
				cov_rows[i][j] += d[i] * d[j]
	cov = Matrix((tuple(cov_rows[0]), tuple(cov_rows[1]), tuple(cov_rows[2])))

	out_of_anchor = centroid - anchor
	axis = out_of_anchor.normalized() if out_of_anchor.length > 1e-9 else Vector((1.0, 0.0, 0.0))
	for _ in range(_PCA_POWER_ITERATIONS):
		nxt = cov @ axis
		if nxt.length < 1e-12:
			break  # covariance quasi nulle (échantillon dégénéré) : garde le dernier axe valide
		axis = nxt.normalized()
	if axis.dot(out_of_anchor) < 0.0:
		axis = -axis  # résout l'ambiguïté de signe de l'axe propre (droite, pas vecteur)
	return axis


## Distance perpendiculaire de `p` à la DROITE passant par `anchor`, de
## direction `axis` (normalisé) — sert à `_measure_arm_axis` pour ne garder
## que les sommets PROCHES de l'axe mesuré (un membre fin, cylindrique),
## jamais une pièce large/plate proche mais hors-axe (poncho, manteau...).
def _perp_distance_to_line(p: "Vector", anchor: "Vector", axis: "Vector") -> float:
	d = p - anchor
	return (d - d.dot(axis) * axis).length


## Axe principal des sommets du maillage Tripo réel qui appartiennent au bras
## `side` (`_ARM_SIDE_MARGIN_M` au-delà de l'épaule, cf. sa docstring) : mesure
## la direction RÉELLE du bras de CE maillage plutôt que de supposer une pose
## relâchée fixe (§Notes ART-11Z, tête de fichier — l'ancienne cible fixe ne
## correspondait pas aux maillages Tripo, livrés en A-pose ~40°, cf.
## docs/style/character_prompts.md).
##
## L'échantillon initial ("au-delà de l'épaule") n'est PAS filtré par
## appartenance anatomique — un vêtement AMPLE proche du bras à ce stade
## (poncho, manteau, cape) y entre aussi, et son volume (bien plus large
## qu'un bras) peut alors DOMINER l'axe principal mesuré (sondé sur
## verrou.glb : axe mesuré quasi vertical, ~7° de l'aplomb, très loin des
## ~40° du gabarit de concept — le poncho, qui pend le long du corps, tirait
## l'axe vers la verticale). `_ARM_AXIS_TRIM_ITERATIONS` passes d'élagage
## (RANSAC simplifié) resserrent l'échantillon sur les sommets à MOINS de
## `_ARM_AXIS_TRIM_RADIUS_M` de l'axe courant (un bras est un tube fin, un
## poncho s'en écarte largement) et recalculent le PCA dessus, jusqu'à
## convergence vers la forme la plus fine et la plus allongée du voisinage —
## le bras, pas le vêtement.
##
## Mesure PRINCIPALE (2026-09-24, après constat sur la bande démo) : l'élagage
## ci-dessus ne suffit pas — sur verrou_v1.glb il converge encore sur les bords
## du poncho (axe mesuré (0,001 ; -0,130 ; -0,991), vertical) alors que la
## planche source montre des bras en A-pose à ~45°. Conséquence : bras lié à un
## os vertical, puis cuit de 90° vers la T-pose -> maillage du bras 45° AU-DESSUS
## de l'horizontale, d'où bras écartés en Repos et levés au Tir dans toutes les
## animations. La main est l'extrémité la plus latérale de la silhouette en
## A-pose (aucun vêtement ne la dépasse) : l'axe du bras est la droite épaule ->
## centroïde des sommets les plus latéraux de ce côté. L'axe PCA n'est gardé
## qu'en repli, si la main mesurée tombe quasiment à l'aplomb de l'épaule
## (bras réellement pendants, où la hanche/le manteau peuvent être plus latéraux).
_HAND_LATERAL_BAND_M = 0.06
_HAND_AXIS_MIN_ANGLE_DEG = 15.0


def _measure_hand_axis(pts: list, shoulder_world: "Vector", sign: float) -> "Vector | None":
	band_min = max(sign * (p.x - shoulder_world.x) for p in pts) - _HAND_LATERAL_BAND_M
	hand = [p for p in pts if sign * (p.x - shoulder_world.x) >= band_min and p.z < shoulder_world.z]
	if len(hand) < 8:
		return None
	centroid = Vector((0.0, 0.0, 0.0))
	for p in hand:
		centroid += p
	centroid /= len(hand)
	axis = (centroid - shoulder_world).normalized()
	if axis.angle(Vector((0.0, 0.0, -1.0))) < math.radians(_HAND_AXIS_MIN_ANGLE_DEG):
		return None
	return axis


def _measure_arm_axis(mesh_obj: "bpy.types.Object", rig: "bpy.types.Object", side: str) -> Vector:
	shoulder_world = rig.matrix_world @ rig.data.bones["DEF-shoulder.%s" % side].tail_local
	sign = 1.0 if side == "L" else -1.0
	mw = mesh_obj.matrix_world
	pts = [mw @ v.co for v in mesh_obj.data.vertices
		if sign * ((mw @ v.co).x - shoulder_world.x) > _ARM_SIDE_MARGIN_M]
	if len(pts) < _ARM_MIN_SAMPLE_VERTS:
		raise RuntimeError(
			"rig_tripo_character: pas assez de sommets au-delà de l'épaule %s pour mesurer "
			"la direction du bras (%d < %d) — vérifier --weld-dist / le maillage source"
			% (side, len(pts), _ARM_MIN_SAMPLE_VERTS))
	hand_axis = _measure_hand_axis(pts, shoulder_world, sign)
	if hand_axis is not None:
		print("RIG_TRIPO_ARM_AXIS %s = (%.3f, %.3f, %.3f) épaule -> main (%.1f° de la verticale)"
			% (side, hand_axis.x, hand_axis.y, hand_axis.z,
				math.degrees(hand_axis.angle(Vector((0.0, 0.0, -1.0))))))
		return hand_axis
	initial_count = len(pts)

	axis = _pca_principal_axis(pts, shoulder_world)
	for _ in range(_ARM_AXIS_TRIM_ITERATIONS):
		trimmed = [p for p in pts if _perp_distance_to_line(p, shoulder_world, axis) < _ARM_AXIS_TRIM_RADIUS_M]
		if len(trimmed) < _ARM_MIN_SAMPLE_VERTS:
			break  # échantillon élagué trop court : garde le dernier axe valide (avant cet élagage)
		pts = trimmed
		axis = _pca_principal_axis(pts, shoulder_world)

	print("RIG_TRIPO_ARM_AXIS %s = (%.3f, %.3f, %.3f) sur %d/%d sommet(s) (après élagage)"
		% (side, axis.x, axis.y, axis.z, len(pts), initial_count))
	return axis


## Repose le bras `side` (chaîne `_ARM_CHAIN`, accumulée os par os via
## `Vector.rotation_difference` — même technique que
## `make_characters._pose_fp_hold`, voir son commentaire pour le détail de
## l'API bpy vérifiée par sondage) vers `target_dir` : bras TENDU (une seule
## direction cible, upper_arm/forearm/hand identiques), jamais un coude plié
## — même choix et même raison que `make_characters._pose_fp_hold` (le poids
## de peau mélange un peu upper_arm/forearm au coude une fois lié). Pose PURE
## (jamais appliquée au repos ici) : lit le repos COURANT du squelette
## (`_bone_rest_dir`/`matrix_local`), donc utilisable aussi bien pour poser
## depuis le repos T-pose D'ORIGINE (`_apply_bind_rest`) que depuis un repos
## de liaison déjà modifié (`_restore_original_rest`) — le squelette doit
## être en mode POSE (l'appelant gère l'entrée/sortie, pour poser les deux
## bras dans la même passe avant un éventuel `armature_apply`).
def _pose_arm_chain(rig: "bpy.types.Object", side: str, target_dir: "Vector") -> None:
	target_dir = target_dir.normalized()
	accum = Matrix.Identity(3)
	pos = rig.data.bones["DEF-shoulder.%s" % side].tail_local.copy()
	for key in _ARM_CHAIN:
		bone_name = "DEF-%s.%s" % (key, side)
		rest_dir = _bone_rest_dir(rig, bone_name)
		cur_dir = (accum @ rest_dir).normalized()
		delta = cur_dir.rotation_difference(target_dir).to_matrix()
		accum = delta @ accum
		new_dir = (accum @ rest_dir).normalized()
		length = _bone_rest_length(rig, bone_name)

		pb = rig.pose.bones[bone_name]
		rest_rot = rig.data.bones[bone_name].matrix_local.to_3x3()
		new_matrix = (accum @ rest_rot).to_4x4()
		new_matrix.translation = pos
		pb.matrix = new_matrix
		bpy.context.view_layer.update()
		pos = pos + new_dir * length


## Pose les deux bras sur `arm_dirs` (mesurés par `_measure_arm_axis`, PAS une
## cible fixe — voir §Notes ART-11Z, tête de fichier) PUIS applique cette pose
## comme nouveau repos TEMPORAIRE de liaison (`armature_apply`) : condition
## nécessaire pour que la liaison par poids automatiques qui suit (`_bind_
## automatic`) capture correctement les bras au lieu de tout assigner au
## torse le plus proche (les bras du maillage Tripo réel ne sont jamais en
## croix comme la T-pose de repos). Ce repos n'est PAS le repos final exporté
## — voir `_restore_original_rest`, appelé après la liaison/rigidification,
## qui le remplace par le repos T-pose D'ORIGINE (identique à `ual.glb`) une
## fois le skinning calculé.
##
## `bake_meshes` : maillages liés au squelette (le mannequin UAL) à CUIRE dans
## cette pose avant qu'elle devienne le repos — `armature_apply` ne déforme
## pas les maillages enfants, sans cette cuisson le mannequin garderait ses
## bras en croix alors que le squelette les a baissés.
def _apply_bind_rest(rig: "bpy.types.Object", arm_dirs: dict, bake_meshes: tuple = ()) -> None:
	bpy.context.view_layer.objects.active = rig
	bpy.ops.object.mode_set(mode='POSE')
	bpy.ops.pose.select_all(action='DESELECT')
	for side in ("L", "R"):
		_pose_arm_chain(rig, side, arm_dirs[side])
	bpy.ops.object.mode_set(mode='OBJECT')
	for mesh in bake_meshes:
		for mod in [m for m in mesh.modifiers if m.type == 'ARMATURE']:
			with bpy.context.temp_override(object=mesh, active_object=mesh):
				bpy.ops.object.modifier_apply(modifier=mod.name)
	bpy.context.view_layer.objects.active = rig
	bpy.ops.object.mode_set(mode='POSE')
	with bpy.context.temp_override(object=rig, active_object=rig):
		bpy.ops.pose.armature_apply(selected=False)
	bpy.ops.object.mode_set(mode='OBJECT')
	print("RIG_TRIPO_POSE_OK bras posés sur la direction mesurée du maillage (repos de liaison temporaire)")


## `root_name` et TOUS ses descendants (parcours de `Bone.children`, en
## profondeur — l'ordre n'a pas d'importance pour les appelants) dans le
## squelette COURANT — utilisé pour capturer/reposer le sous-arbre ENTIER du
## bras (avant-bras, main, ET tous les doigts) plutôt qu'une liste d'os codée
## en dur (§Notes ART-11Z) : les doigts ne sont JAMAIS posés explicitement,
## mais `armature_apply` (dans `_apply_bind_rest`) fait hériter leur repos de
## celui de la main via la hiérarchie FK (un enfant non posé explicitement
## EST TOUT DE MÊME réorienté par `armature_apply`, qui bake le repos à partir
## de la pose ÉVALUÉE, parent compris) — les IGNORER à la restauration
## romprait cette hiérarchie : sondé, jusqu'à 92,55° d'écart sur
## `DEF-f_index.01.R` avant ce correctif (la main reposée sans ses enfants,
## laissés dans leur orientation du repos de LIAISON).
def _bone_subtree_names(rig: "bpy.types.Object", root_name: str) -> list:
	out = []
	stack = [rig.data.bones[root_name]]
	while stack:
		b = stack.pop()
		out.append(b.name)
		stack.extend(b.children)
	return out


## Les deux sous-arbres "DEF-upper_arm.<side>" (bras + avant-bras + main +
## tous les doigts, cf. `_bone_subtree_names`) — l'ensemble EXACT d'os dont le
## repos doit être capturé/restauré autour d'ART-11Z.
def _arm_subtree_bone_names(rig: "bpy.types.Object") -> tuple:
	names = []
	for side in ("L", "R"):
		names.extend(_bone_subtree_names(rig, "DEF-upper_arm.%s" % side))
	return tuple(names)


## Capture (head, tail, roll — en mode ÉDITION, repère armature) de chaque os
## du sous-arbre du bras (`_arm_subtree_bone_names`), AVANT toute pose : le
## repos T-pose D'ORIGINE du squelette commun, identique à `ual.glb` par
## construction (importé de la même source, jamais encore posé à cet instant
## de `main()`). `_restore_original_rest` réécrit ces valeurs OCTET PRÈS en
## fin de script — voir sa docstring pour pourquoi un simple ALLER-RETOUR PAR
## ROTATION (poser vers le repos de liaison PUIS reposer vers `_bone_rest_dir`
## d'origine, sans snapshot) ne suffit PAS : sondé sur `ual.glb`, la chaîne
## bras UAL-G n'est PAS parfaitement colinéaire en T-pose (~1,97°
## upper_arm<->forearm, ~0,98° upper_arm<->hand — un léger coude/poignet est
## bien présent au repos), donc partager UN SEUL accum de chaîne
## (`_pose_arm_chain`, conçu pour le bras TENDU du repos de liaison, cf. sa
## docstring) laisse un résidu conjugué sur forearm/hand une fois revenu au
## repos d'origine — mesuré à exactement 1,9690° sur `DEF-forearm.R` lors du
## premier passage de cette correction (au-dessus de
## `REST_ORIENTATION_TOLERANCE_DEG`), la preuve empirique de ce défaut
## d'approche.
def _snapshot_arm_rest(rig: "bpy.types.Object") -> dict:
	snap = {}
	bpy.context.view_layer.objects.active = rig
	bpy.ops.object.mode_set(mode='EDIT')
	for name in _arm_subtree_bone_names(rig):
		eb = rig.data.edit_bones[name]
		snap[name] = (eb.head.copy(), eb.tail.copy(), eb.roll)
	bpy.ops.object.mode_set(mode='OBJECT')
	return snap


## Réécrit le repos de CHAQUE os du bras OCTET PRÈS depuis `snapshot`
## (`_snapshot_arm_rest`) — mode ÉDITION, jamais une pose appliquée
## (`armature_apply`) : `head`/`tail` (position ET direction, repère armature)
## et `roll` (torsion propre à l'os, absente d'une simple direction) sont
## réécrits directement, donc EXACTS par construction, quel que soit le degré
## de colinéarité de la chaîne d'origine (cf. docstring de `_snapshot_arm_rest`).
def _restore_arm_rest(rig: "bpy.types.Object", snapshot: dict) -> None:
	bpy.context.view_layer.objects.active = rig
	bpy.ops.object.mode_set(mode='EDIT')
	for name, (head, tail, roll) in snapshot.items():
		eb = rig.data.edit_bones[name]
		eb.head = head
		eb.tail = tail
		eb.roll = roll
	bpy.ops.object.mode_set(mode='OBJECT')


## Nombre de pas de l'interpolation sphérique bind -> repos T-pose d'origine
## (`_restore_original_rest`) — §Notes ART-11Z (bande démo de relance) : un
## SEUL saut direct (repos de liaison "bras mesurés" ~88° -> T-pose
## horizontale) casse le blending linéaire des sommets à poids MÉLANGÉS
## (coude upper_arm/forearm ~50/50 — effet "papillote" classique du Linear
## Blend Skinning sur une grande rotation) : sondé sur verrou.glb, un sommet
## du coude gauche pondéré 52,5 %/46,7 % upper_arm/forearm ressortait CUIT à
## z=1,86 m (quasi la hauteur du chapeau) au lieu de ~1,4 m (hauteur d'épaule
## attendue en T-pose), gonflant tout le maillage bras/cape jusqu'à 1,94 m de
## haut / 1,93 m de large — largement visible dans Idle_Loop ensuite (largeur
## 1,60 m au lieu de ~0,73 m sur le mannequin ual.glb de référence). Fractionner
## la MÊME rotation totale en `_BAKE_SUBSTEPS` petits pas, chacun cuit et
## appliqué comme repos AVANT le suivant (`armature_apply`, pas seulement une
## pose), réduit l'angle par pas à ~88°/N — l'erreur de blending linéaire
## décroît bien plus vite que l'angle, donc quelques pas suffisent (sondé :
## `_BAKE_SUBSTEPS = 16` combiné à `_pose_arm_chain`, cf. ci-dessous, ramène
## le même sommet de coude à un écart de hauteur négligeable).
_BAKE_SUBSTEPS = 16


## Applique LA MÊME rotation `delta` (3x3, calculée UNE fois pour ce pas par
## l'appelant, cf. `_restore_original_rest`) aux 3 os du bras `side`
## (`_ARM_CHAIN`), comme un seul bloc RIGIDE tournant autour de l'épaule
## (`DEF-shoulder.<side>.tail_local`, ancre FIXE) — PAS `_pose_arm_chain`
## (conçu pour un unique très grand saut, cf. `_apply_bind_rest`) : sondé,
## rappeler `_pose_arm_chain` À CHAQUE pas incrémental (`_BAKE_SUBSTEPS`) lui
## fait re-dériver, à CHAQUE pas, sa petite correction de colinéarité
## upper_arm/forearm (~2°, cf. `_snapshot_arm_rest` — la chaîne UAL-G n'est
## pas parfaitement colinéaire) — une correction qui ne s'annule PAS d'un pas
## à l'autre mais COMPOSE (toujours dans le même sens), et dérive alors très
## au-delà de la cible après `_BAKE_SUBSTEPS` répétitions (sondé sur
## verrou.glb : un sommet de coude, à poids mélangés upper_arm/forearm,
## dépassait déjà la position de la main en X et grimpait bien au-dessus de
## la hauteur d'épaule en Z, la dérive s'aggravant à chaque pas). En
## appliquant la MÊME rotation rigide aux 3 os (rotation autour d'un pivot
## fixe unique), tout sommet à poids mélangés ENTRE deux de ces 3 os reçoit
## une transformation IDENTIQUE quel que soit l'os dominant (preuve : pour un
## point X, `pose_i @ rest_i^{-1} @ X = pivot + delta @ (X - pivot)` pour
## CHAQUE os i de la chaîne, indépendamment de son repos individuel — le
## Linear Blend Skinning ne peut alors PAS diverger, aucune "papillote"
## possible par construction).
def _pose_arm_rigid_step(rig: "bpy.types.Object", side: str, delta: "Matrix") -> None:
	anchor = rig.data.bones["DEF-shoulder.%s" % side].tail_local.copy()
	for key in _ARM_CHAIN:
		bone_name = "DEF-%s.%s" % (key, side)
		bone = rig.data.bones[bone_name]
		rest_rot = bone.matrix_local.to_3x3()
		pb = rig.pose.bones[bone_name]
		new_matrix = (delta @ rest_rot).to_4x4()
		new_matrix.translation = anchor + delta @ (bone.head_local - anchor)
		pb.matrix = new_matrix
		bpy.context.view_layer.update()


## CUIT le maillage dans la pose ACTUELLE (`_pose_arm_rigid_step` par côté,
## cf. sa docstring) puis applique cette MÊME pose comme nouveau repos
## (`armature_apply`) — le "pas" élémentaire répété `_BAKE_SUBSTEPS` fois par
## `_restore_original_rest` (cf. sa docstring : jamais un seul grand pas,
## effet "papillote" du Linear Blend Skinning). Seuls upper_arm/forearm/hand
## sont posés explicitement PAR CÔTÉ ; les doigts ne sont JAMAIS touchés
## directement — ils suivent la main par la hiérarchie FK normale (comme pour
## `_apply_bind_rest`) et `armature_apply` capture correctement leur repos
## ainsi hérité à CHAQUE pas, sans jamais leur assigner une matrice absolue
## (poser CHAQUE os de doigt indépendamment casserait leur rattachement
## "connecté", tête forcée sur la queue du parent). Modificateur Armature
## retiré puis remis à l'identique (mêmes groupes de sommets) à CHAQUE pas :
## `modifier_apply` exige de le retirer, et le pas SUIVANT (ou la
## restauration finale exacte, `_restore_arm_rest`) a besoin qu'il soit
## présent pour évaluer la déformation suivante / l'export final.
def _bake_and_advance_rest(rig: "bpy.types.Object", mesh_obj: "bpy.types.Object", deltas: dict) -> None:
	bpy.context.view_layer.objects.active = rig
	bpy.ops.object.mode_set(mode='POSE')
	bpy.ops.pose.select_all(action='DESELECT')
	for side, delta in deltas.items():
		_pose_arm_rigid_step(rig, side, delta)
	bpy.ops.object.mode_set(mode='OBJECT')

	arm_mod = mesh_obj.modifiers.get("Armature")
	if arm_mod is None:
		raise RuntimeError("rig_tripo_character: modificateur Armature introuvable avant cuisson du repos")
	with bpy.context.temp_override(object=mesh_obj, active_object=mesh_obj, selected_editable_objects=[mesh_obj]):
		bpy.ops.object.modifier_apply(modifier=arm_mod.name)

	bpy.context.view_layer.objects.active = rig
	bpy.ops.object.mode_set(mode='POSE')
	with bpy.context.temp_override(object=rig, active_object=rig):
		bpy.ops.pose.armature_apply(selected=False)
	bpy.ops.object.mode_set(mode='OBJECT')

	mesh_obj.parent = rig
	new_mod = mesh_obj.modifiers.new("Armature", type='ARMATURE')
	new_mod.object = rig


## Rétablit le repos T-pose D'ORIGINE du squelette (capturé par l'appelant
## AVANT `_apply_bind_rest`, cf. `arm_snapshot`/`_snapshot_arm_rest`) après
## que la liaison par poids automatiques + la rigidification des îlots
## (`_bind_automatic`, `_rigidify_small_islands`) ont été calculées sur le
## repos de liaison (bras mesurés, cf. `_apply_bind_rest`) — §Notes ART-11Z,
## tête de fichier : les 46 actions UAL sont des deltas relatifs au repos
## T-pose D'ORIGINE de `ual.glb`, jamais au repos de liaison, donc le repos
## FINAL exporté doit redevenir identique à celui de `ual.glb`, os par os.
##
## Ne fait JAMAIS un simple `armature_apply` immédiat (ça romprait le
## skinning tout juste calculé : le maillage RESTERAIT visuellement dans sa
## forme "bras relâchés" alors que le repos redeviendrait T-pose, un
## désaccord direct entre géométrie brute et repos de peau — la MÊME classe
## de bug que §Notes ART-11Z corrige, à l'envers). Technique en 3 phases :
##   1. CUIT le maillage en `_BAKE_SUBSTEPS` PETITS pas RIGIDES (une seule
##      rotation par pas, `_pose_arm_rigid_step` — PAS `_pose_arm_chain` :
##      voir sa docstring, rappeler `_pose_arm_chain` à chaque pas composerait
##      dangereusement une petite correction de colinéarité). Chaque pas fait
##      tourner le bras de `DEF-upper_arm.<side>`'s direction COURANTE vers un
##      point intermédiaire de l'interpolation sphérique (`Vector.slerp`)
##      entre le repos de liaison D'ORIGINE et le repos T-pose D'ORIGINE — un
##      seul grand pas casse le Linear Blend Skinning des sommets à poids
##      mélangés à l'articulation (coude upper_arm/forearm), cf. docstring de
##      `_pose_arm_rigid_step`. Chaque pas cuit ET avance le repos (bras +
##      doigts, qui suivent par hiérarchie), donc à la fin de la boucle le
##      squelette est DÉJÀ approximativement en T-pose (à l'imprécision de
##      l'interpolation par pas près) ;
##   2. réécrit le repos OCTET PRÈS depuis `arm_snapshot` (`_restore_arm_
##      rest`, mode ÉDITION, sous-arbre COMPLET bras + doigts — jamais un
##      `armature_apply` qui hériterait de la moindre imprécision résiduelle
##      de l'étape 1, cf. sa docstring) PUIS remet la pose des os du bras (et
##      des doigts) à l'identité (`matrix_basis` — le repos venant d'être
##      réécrit directement, la pose courante, relative à l'ANCIEN repos
##      intermédiaire, ne correspond plus à rien et DOIT être effacée pour
##      qu'"aucune action jouée" corresponde exactement au nouveau repos) ;
##   3. le modificateur Armature est déjà en place (remis à chaque pas de
##      l'étape 1, cf. `_bake_and_advance_rest`) : la liaison par poids
##      automatiques n'est JAMAIS refaite, mêmes groupes de sommets du début
##      à la fin.
def _restore_original_rest(rig: "bpy.types.Object", mesh_obj: "bpy.types.Object", arm_snapshot: dict) -> None:
	start_dirs = {side: _bone_rest_dir(rig, "DEF-upper_arm.%s" % side) for side in ("L", "R")}
	target_dirs = {}
	for side in ("L", "R"):
		head, tail, _roll = arm_snapshot["DEF-upper_arm.%s" % side]
		target_dirs[side] = (tail - head).normalized()

	for step in range(1, _BAKE_SUBSTEPS + 1):
		t_prev = (step - 1) / _BAKE_SUBSTEPS
		t_next = step / _BAKE_SUBSTEPS
		deltas = {}
		for side in ("L", "R"):
			dir_prev = start_dirs[side].slerp(target_dirs[side], t_prev)
			dir_next = start_dirs[side].slerp(target_dirs[side], t_next)
			# Rotation de CE pas UNIQUEMENT (repère COURANT de upper_arm ->
			# point suivant de l'interpolation) : jamais recalculée depuis le
			# repos de liaison D'ORIGINE, ce qui ferait resurgir un aller-
			# retour complet à chaque pas plutôt qu'une avance incrémentale.
			deltas[side] = dir_prev.rotation_difference(dir_next).to_matrix()
		_bake_and_advance_rest(rig, mesh_obj, deltas)

	_restore_arm_rest(rig, arm_snapshot)

	bpy.context.view_layer.objects.active = rig
	bpy.ops.object.mode_set(mode='POSE')
	for bone_name in arm_snapshot:
		rig.pose.bones[bone_name].matrix_basis = Matrix.Identity(4)
	bpy.ops.object.mode_set(mode='OBJECT')

	print("RIG_TRIPO_REST_RESTORED repos T-pose d'origine rétabli (identique à ual.glb, os par os), maillage cuit dans cette pose")


## Liaison par poids automatiques (heat weighting, `ARMATURE_AUTO` — même
## opérateur que le menu Ctrl+P > "With Automatic Weights") : seule option
## praticable pour un maillage Tripo arbitraire SANS groupes de sommets
## préexistants (contrat ART-11 : "poids automatiques OU transfert depuis le
## mannequin UAL").
##
## PAS directement sur le maillage réel : sondé — l'opérateur échoue
## TOTALEMENT (0 sommet pondéré sur les 16 342, `Bone Heat Weighting: failed
## to find solution for one or more bones`) sur verrou.glb même parfaitement
## manifold, à cause de la densité de sommets dupliqués aux coutures UV
## (16 342 sommets pour ~7 446 positions réelles — le solveur de chaleur de
## Blender ne s'en accommode pas, contrairement à la LISIBILITÉ de la
## topologie qui, elle, n'a besoin d'aucun repère par sommet). Sondé aussi :
## sur une COPIE fusionnée par distance (mêmes 7 446 positions), l'opérateur
## réussit à 99,7% (7 424/7 446, avec les bras reposés — voir
## `_apply_bind_rest` : SANS repose, la même copie ne pond que 94,9%, preuve
## que la pose ET la densité de sommets comptent toutes les deux). On lie
## donc une COPIE JETABLE fusionnée (jamais le maillage réel : la fusion
## perdrait l'UV d'un côté de chaque couture, cf. `_repair_nonmanifold`),
## on comble les quelques sommets encore orphelins par plus-proche-voisin
## PONDÉRÉ (petit îlot de topologie isolé malgré la fusion — sondé : ~22
## sommets sur un même repli de ceinturon que la réparation non-manifold),
## puis on TRANSFÈRE les poids obtenus sur le maillage réel par
## correspondance de position (`mathutils.kdtree`, même technique que
## `bpy.ops.object.data_transfer` mais sans dépendre d'un contexte de
## viewport) : chaque sommet réel hérite des poids du sommet fusionné le
## plus proche (distance 0 pour la quasi-totalité, la fusion ne DÉPLACE pas
## les sommets conservés).
def _bind_automatic(mesh_obj: "bpy.types.Object", rig: "bpy.types.Object") -> None:
	import mathutils.kdtree

	bm = bmesh.new()
	bm.from_mesh(mesh_obj.data)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=NONMANIFOLD_WELD_DIST)
	# La fusion peut réintroduire quelques arêtes non-manifold localement
	# (sondé : 14) — sans conséquence sur l'UV/le maillage réel puisque cette
	# copie est jetée après avoir servi au calcul des poids ; on la répare
	# quand même pour maximiser la couverture du heat weighting.
	for _ in range(len(bm.faces)):
		bad = [e for e in bm.edges if len(e.link_faces) >= 3]
		if not bad:
			break
		e = max(bad, key=lambda e: len(e.link_faces))
		f = min(e.link_faces, key=lambda f: f.calc_area())
		bmesh.ops.delete(bm, geom=[f], context='FACES')
	bm.normal_update()
	loose = [v for v in bm.verts if len(v.link_faces) == 0]
	if loose:
		bmesh.ops.delete(bm, geom=loose, context='VERTS')

	weld_mesh = bpy.data.meshes.new("_rig_tripo_weld_tmp")
	bm.to_mesh(weld_mesh)
	bm.free()
	weld_obj = bpy.data.objects.new("_rig_tripo_weld_tmp", weld_mesh)
	bpy.context.scene.collection.objects.link(weld_obj)
	weld_obj.matrix_world = mesh_obj.matrix_world.copy()

	bpy.ops.object.select_all(action='DESELECT')
	weld_obj.select_set(True)
	rig.select_set(True)
	bpy.context.view_layer.objects.active = rig
	bpy.ops.object.parent_set(type='ARMATURE_AUTO')

	# Comble les rares sommets encore orphelins (îlot isolé malgré la fusion,
	# cf. docstring) par les poids du sommet PONDÉRÉ le plus proche.
	kd_all = mathutils.kdtree.KDTree(len(weld_mesh.vertices))
	for i, v in enumerate(weld_mesh.vertices):
		kd_all.insert(v.co, i)
	kd_all.balance()
	weighted_idx = [i for i, v in enumerate(weld_mesh.vertices) if v.groups]
	filled = 0
	for v in weld_mesh.vertices:
		if v.groups:
			continue
		for _co, idx, _dist in kd_all.find_n(v.co, len(weighted_idx) + 1):
			if weld_mesh.vertices[idx].groups:
				for g in weld_mesh.vertices[idx].groups:
					weld_obj.vertex_groups[g.group].add([v.index], g.weight, 'REPLACE')
				filled += 1
				break
	if filled:
		print("RIG_TRIPO_BIND comblés par plus-proche-voisin : %d" % filled)

	# Transfert des poids (copie fusionnée -> maillage réel) par position.
	kd = mathutils.kdtree.KDTree(len(weld_mesh.vertices))
	for i, v in enumerate(weld_mesh.vertices):
		kd.insert(v.co, i)
	kd.balance()
	for vg in weld_obj.vertex_groups:
		if vg.name not in mesh_obj.vertex_groups:
			mesh_obj.vertex_groups.new(name=vg.name)
	unmatched = 0
	for v in mesh_obj.data.vertices:
		_co, idx, dist = kd.find(v.co)
		if dist > 0.01:
			unmatched += 1
		src = weld_mesh.vertices[idx]
		for g in src.groups:
			group_name = weld_obj.vertex_groups[g.group].name
			mesh_obj.vertex_groups[group_name].add([v.index], g.weight, 'REPLACE')
	if unmatched:
		print("RIG_TRIPO_BIND_WARN %d sommet(s) sans correspondance exacte (> 1 cm)" % unmatched)

	bpy.data.objects.remove(weld_obj, do_unlink=True)
	bpy.data.meshes.remove(weld_mesh)

	mesh_obj.parent = rig
	arm_mod = mesh_obj.modifiers.new("Armature", type='ARMATURE')
	arm_mod.object = rig


# Poids inférieurs à ce seuil ignorés, puis au plus 4 influences par sommet
# (limite de skinning glTF/Godot) renormalisées à 1.
BIND_WEIGHT_MIN = 0.01
BIND_MAX_INFLUENCES = 4
# Demi-largeur horizontale du volume « tête + accessoires » verrouillé sur
# DEF-head (enveloppe de tête 0,34 m + débord de bec/bord de chapeau).
HEAD_LOCK_RADIUS_M = 0.30


## Coordonnées barycentriques de `p` (déjà projeté sur le triangle abc),
## négatives ramenées à 0 puis renormalisées (point projeté sur une arête).
def _barycentric(p: "Vector", a: "Vector", b: "Vector", c: "Vector") -> tuple:
	v0, v1, v2 = b - a, c - a, p - a
	d00, d01, d11 = v0.dot(v0), v0.dot(v1), v1.dot(v1)
	d20, d21 = v2.dot(v0), v2.dot(v1)
	denom = d00 * d11 - d01 * d01
	if abs(denom) < 1e-12:
		return (1.0, 0.0, 0.0)
	v = (d11 * d20 - d01 * d21) / denom
	w = (d00 * d21 - d01 * d20) / denom
	u = 1.0 - v - w
	u, v, w = max(u, 0.0), max(v, 0.0), max(w, 0.0)
	s = u + v + w
	return (u / s, v / s, w / s) if s > 0.0 else (1.0, 0.0, 0.0)


## Liaison par COPIE DES POIDS du mannequin UAL (méthode par défaut, remplace le
## heat weighting de `_bind_automatic`, gardé derrière `--weights heat`).
## Constat du 2026-09-24 (bande démo tools/review/anim_reel.gd) : le heat
## weighting pondère ~1750 sommets de poncho/manteau à 50/50 vers upper_arm /
## forearm ; dès que le bras bouge (cuisson vers la T-pose, puis chaque
## animation), le vêtement s'étire en « membrane » entre le bras et la cuisse
## (Verrou, Roseau, Choc, Vanne). Le mannequin UAL, lui, porte des poids propres
## sur les 52 os `DEF-` et il est posé EXACTEMENT comme le maillage (mêmes bras
## mesurés, cuit par `_apply_bind_rest`) : chaque sommet Tripo reçoit les poids
## interpolés du point de surface du mannequin le plus proche. Un pan de
## manteau au niveau de la hanche tombe sur la hanche/la cuisse, jamais sur la
## main, puisque le bras du mannequin est écarté du corps comme celui du
## personnage.
def _bind_from_mannequin(mesh_obj: "bpy.types.Object", rig: "bpy.types.Object",
		mannequin: "bpy.types.Object") -> None:
	from mathutils.bvhtree import BVHTree

	src = mannequin.data
	src.calc_loop_triangles()
	src_mw = mannequin.matrix_world
	src_verts = [src_mw @ v.co for v in src.vertices]
	src_tris = [tuple(t.vertices) for t in src.loop_triangles]
	bvh = BVHTree.FromPolygons(src_verts, src_tris)
	group_names = {g.index: g.name for g in mannequin.vertex_groups}
	src_weights = [
		{group_names[g.group]: g.weight for g in v.groups
			if group_names[g.group].startswith(_DEF_BONE_PREFIX) and g.weight > 0.0}
		for v in src.vertices
	]
	for name in sorted({n for d in src_weights for n in d}):
		if name not in mesh_obj.vertex_groups:
			mesh_obj.vertex_groups.new(name=name)
	groups = {g.name: g for g in mesh_obj.vertex_groups}

	# Tout ce qui dépasse AU-DESSUS de la base du crâne (bec de Roseau, huppe,
	# bords de chapeau, suroît) suit la tête d'un bloc : ces volumes débordent du
	# mannequin, leur point de surface le plus proche peut tomber sur le cou et
	# leur donner un mélange tête/cou qui les fait plier (bec de Roseau « mou »
	# sur la bande démo du 2026-09-24). Rayon horizontal limité pour ne jamais
	# capturer une main levée.
	head_bone = rig.data.bones["DEF-head"]
	head_base = rig.matrix_world @ head_bone.head_local
	dst_mw = mesh_obj.matrix_world
	far = 0
	head_locked = 0
	for v in mesh_obj.data.vertices:
		world = dst_mw @ v.co
		if world.z >= head_base.z and Vector((world.x - head_base.x, world.y - head_base.y)).length < HEAD_LOCK_RADIUS_M:
			groups["DEF-head"].add([v.index], 1.0, 'REPLACE')
			head_locked += 1
			continue
		loc, _normal, tri_index, dist = bvh.find_nearest(world)
		if loc is None:
			continue
		if dist > 0.15:
			far += 1
		a, b, c = src_tris[tri_index]
		bary = _barycentric(loc, src_verts[a], src_verts[b], src_verts[c])
		acc = {}
		for w, vi in zip(bary, (a, b, c)):
			for name, gw in src_weights[vi].items():
				acc[name] = acc.get(name, 0.0) + w * gw
		if not acc:
			continue
		top = sorted(acc.items(), key=lambda kv: -kv[1])
		kept = [kv for kv in top[:BIND_MAX_INFLUENCES] if kv[1] >= BIND_WEIGHT_MIN] or top[:1]
		total = sum(x for _, x in kept)
		for name, x in kept:
			groups[name].add([v.index], x / total, 'REPLACE')
	print("RIG_TRIPO_BIND_MANNEQUIN %d sommets, %d à plus de 15 cm du mannequin, %d verrouillés sur la tête"
		% (len(mesh_obj.data.vertices), far, head_locked))

	mesh_obj.parent = rig
	arm_mod = mesh_obj.modifiers.new("Armature", type='ARMATURE')
	arm_mod.object = rig


## Seuil de GAP (mètres, écart de bbox monde au corps principal) au-delà
## duquel un îlot topologique (voir `_connected_components`) est traité comme
## une PIÈCE DÉTACHÉE LÉGITIME du costume (bord de suroît, verre de lunette,
## réservoir dorsal, collerette, basques — §Notes ART-11X : Vanne en a 8
## à <= 0,13 m, Guet en a 3 à <= 0,20 m). MÊME seuil et MÊME mesure que
## `check_asset.py::FLOATING_GAP_TOLERANCE_M` (dupliqué ici À DESSEIN, cf.
## docs/3D_PIPELINE.md §2) : un îlot qui ne serait de toute façon JAMAIS
## repéré comme "flottant" par CHK-16 (bbox encore au contact du corps
## principal, gap <= ce seuil) doit rester skinné NORMALEMENT (poids
## automatiques mélangés, comme le reste du corps) plutôt que d'être
## rigidifié à tort.
##
## Sondage qui a mené à ce choix (remplace un premier essai à base de
## fraction de sommets, cf. historique) : un maillage Smart Mesh Tripo est
## fragmenté en dizaines de composantes topologiques distinctes (35 sur
## Vanne, 36 sur Guet — coutures de matériau/UV qui séparent des pans de
## vêtement pourtant géométriquement soudés au corps), dont l'écrasante
## majorité (27/35 sur Vanne, 33/36 sur Guet) a un gap de 0,0 m — y compris
## des composantes de plus de 1000 sommets (un pan de vêtement entier). Un
## critère par FRACTION de sommets (l'ancien `SMALL_ISLAND_MAX_VERTEX_
## FRACTION`) confondait ces gros pans "juste touchants" avec de vraies
## pièces détachées et les rigidifiait à tort — un pan de vêtement de plus
## de 1000 sommets figé sur un seul os au lieu de suivre plusieurs os en
## douceur DÉCHIRE visiblement en pose (Sprint), l'inverse du but de cette
## tâche. Ne restent, avec le critère de gap, que les 3 (Guet) / 8 (Vanne)
## pièces RÉELLEMENT décrites par le contrat — sondé exactement à ces
## comptes sur guet_v1.glb/vanne_v1.glb.
SMALL_ISLAND_GAP_THRESHOLD_M = 0.01

## Garde-fou secondaire (pas le critère principal, cf. ci-dessus) : même une
## composante à gap réel ne doit jamais être rigidifiée si elle est énorme
## (signe d'un vrai membre mal segmenté par le solveur plutôt que d'une
## garniture) — choisi largement au-dessus de la plus grosse pièce détachée
## sondée (190 sommets sur 17 176, ~1,1%) et largement en dessous d'un membre
## réel.
SMALL_ISLAND_MAX_VERTEX_FRACTION = 0.08

# Préfixe des os "DEF-" (déformation, UAL-G) — seuls candidats valables pour
# `_nearest_deform_bone` : les autres os du rig UAL-G (contrôleurs "root",
# IK...) ne portent aucun groupe de sommets côté maillage, cf. en-tête de
# fichier (53 os `DEF-`).
_DEF_BONE_PREFIX = "DEF-"


## Composantes connexes (sommets reliés par au moins une arête), triées par
## taille décroissante — même définition que `check_asset.py::
## _component_groups` (dupliquée ici À DESSEIN : docs/3D_PIPELINE.md §2 dit
## explicitement que chaque script de ce dossier garde ses propres helpers,
## ne pas les fusionner). L'appelant doit avoir appelé `bm.verts.
## ensure_lookup_table()` et `bm.verts.index_update()` sur CE bmesh avant.
def _connected_components(bm: "bmesh.types.BMesh") -> list:
	visited = [False] * len(bm.verts)
	groups = []
	for start in bm.verts:
		if visited[start.index]:
			continue
		stack = [start]
		visited[start.index] = True
		comp = []
		while stack:
			v = stack.pop()
			comp.append(v)
			for e in v.link_edges:
				other = e.other_vert(v)
				if not visited[other.index]:
					visited[other.index] = True
					stack.append(other)
		groups.append(comp)
	groups.sort(key=len, reverse=True)
	return groups


## AABB monde d'un groupe de `BMVert` (même calcul que
## `check_asset.py::_aabb_from_verts`, dupliqué ici À DESSEIN — voir
## docs/3D_PIPELINE.md §2).
def _component_world_aabb(comp: list, matrix_world: "Matrix") -> tuple:
	pts = [matrix_world @ v.co for v in comp]
	mins = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
	maxs = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
	return mins, maxs


## Écart heuristique entre deux bbox monde alignées aux axes — même calcul que
## `check_asset.py::_aabb_gap` (dupliqué ici À DESSEIN — voir
## docs/3D_PIPELINE.md §2) : 0 si elles se chevauchent/se touchent sur les 3
## axes, sinon la norme du vecteur d'écart par axe. Utiliser EXACTEMENT le
## même calcul ici et côté lint est indispensable : c'est ce qui garantit que
## "cet îlot sera rigidifié" et "cet îlot serait sinon rejeté par CHK-16"
## désignent la MÊME population de composantes (voir docstring de
## `_rigidify_small_islands`).
def _aabb_gap(mins_a: "Vector", maxs_a: "Vector", mins_b: "Vector", maxs_b: "Vector") -> float:
	dx = max(mins_a.x - maxs_b.x, mins_b.x - maxs_a.x, 0.0)
	dy = max(mins_a.y - maxs_b.y, mins_b.y - maxs_a.y, 0.0)
	dz = max(mins_a.z - maxs_b.z, mins_b.z - maxs_a.z, 0.0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)


## Distance point -> segment (projection bornée à [0, 1] le long de `a -> b`)
## — mesure standard, utilisée pour situer un sommet par rapport à l'OS
## `head_local -> tail_local` d'un os plutôt que par rapport à un simple
## sommet de peau (voir `_nearest_deform_bone` : pourquoi la peau la plus
## proche n'est PAS un bon proxy pour "l'os le plus proche").
def _point_segment_distance(p: "Vector", a: "Vector", b: "Vector") -> float:
	ab = b - a
	length_sq = ab.length_squared
	if length_sq < 1e-12:
		return (p - a).length
	t = max(0.0, min(1.0, (p - a).dot(ab) / length_sq))
	return (p - (a + ab * t)).length


## Os `DEF-` (repos, monde) géométriquement le plus proche de `world_point` —
## remplace une première tentative basée sur "le sommet de PEAU confiant le
## plus proche" (cf. historique de cette fonction), qui menait à un
## contresens anatomique : le heat weighting assigne souvent la peau de
## l'ÉPAULE de façon dominante à l'os `upper_arm` (son extrémité `head_local`
## est littéralement à l'épaule) — un sommet de peau "confiant" proche d'un
## chapeau ou d'une collerette est donc, la plupart du temps, un sommet
## d'ÉPAULE dominé par `upper_arm`, PAS un sommet de tête/cou dominé par
## `head`/`neck` (sondé : les 3 îlots de Guet — dont le haut-de-forme —
## votaient TOUS `upper_arm.L/R`, envoyant le chapeau valser au-dessus de la
## tête dès l'animation Idle ; sur Vanne, la coffreuse dorsale votait
## `shoulder.*`, la faisant suivre le grand débattement du bras plutôt que le
## dos, presque immobile). Chercher l'os DONT LE SEGMENT (pas un sommet de
## peau) est le plus proche, PARMI TOUS les os `DEF-` (pas seulement ceux du
## corps principal), va directement à l'intuition de conception ("attacher
## la pièce à ce qui passe physiquement le plus près d'elle") sans dépendre
## de la qualité, par endroits ambiguë, du heat weighting.
def _nearest_deform_bone(rig: "bpy.types.Object", world_point: "Vector",
		exclude: frozenset = frozenset()) -> "str | None":
	best_name = None
	best_dist = None
	mw = rig.matrix_world
	for bone in rig.data.bones:
		if not bone.name.startswith(_DEF_BONE_PREFIX) or bone.name in exclude:
			continue
		head = mw @ bone.head_local
		tail = mw @ bone.tail_local
		dist = _point_segment_distance(world_point, head, tail)
		if best_dist is None or dist < best_dist:
			best_dist = dist
			best_name = bone.name
	return best_name


# Os de tête/cou : responsables du hochement/regard des animations Idle —
# swing amplifié pour toute pièce qui n'est pas VRAIMENT posée dessus (sondé :
# le haut-de-forme de Guet, à 0,090 m de `DEF-head`, est un chapeau LÉGITIME
# posé sur la tête, aucun souci ; le réservoir dorsal de Vanne, "plaqué au
# dos" par le contrat mais à 0,17-0,18 m de `DEF-head`/0,20-0,22 m de
# `DEF-neck` — aucun os ne le traverse vraiment, cf. `t` toujours saturé à 1.0
# dans `_point_segment_distance` — swingait largement hors de son emplacement
# dès l'animation Idle une fois rigidifié dessus). Sous ce seuil (calibré
# entre les deux : 0,090 m légitime, 0,17 m ne l'est pas), l'os est considéré
# "vraiment porté" (chapeau, collerette moulante) et reste éligible ; au-delà,
# `_HEAD_NECK_BONES` est exclu et la recherche retombe sur l'os stable le
# plus proche parmi le reste du squelette (torse/épaule/membre).
_HEAD_NECK_BONES = frozenset({"DEF-head", "DEF-neck"})
_HEAD_NECK_WORN_DIST_M = 0.12


## `_nearest_deform_bone`, mais qui écarte `DEF-head`/`DEF-neck` quand ils ne
## sont PAS vraiment "portés" (cf. `_HEAD_NECK_WORN_DIST_M`) — voir docstring
## de la constante pour le sondage qui a mené à cette règle.
def _nearest_stable_bone(rig: "bpy.types.Object", world_point: "Vector") -> "str | None":
	name = _nearest_deform_bone(rig, world_point)
	if name in _HEAD_NECK_BONES:
		mw = rig.matrix_world
		bone = rig.data.bones[name]
		dist = _point_segment_distance(world_point, mw @ bone.head_local, mw @ bone.tail_local)
		if dist > _HEAD_NECK_WORN_DIST_M:
			return _nearest_deform_bone(rig, world_point, exclude=_HEAD_NECK_BONES)
	return name


## Un SEUL os pour TOUT l'îlot (jamais un os différent par sommet) : appelle
## `_nearest_stable_bone` pour CHAQUE sommet de l'îlot, puis renvoie l'os
## majoritaire (vote) — une pièce rigide DOIT bouger comme un bloc unique ;
## si deux sommets voisins de la MÊME pièce retombaient (calcul indépendant,
## sommet par sommet) sur deux os différents proches d'un coude de squelette,
## la pièce se retrouverait déchirée entre deux transforms d'os distincts dès
## que la pose s'écarte du repos (sondé : la toute première version de cette
## fonction, par sommet, donnait une pièce visuellement "éclatée" en
## plusieurs lames sur Vanne). Voter sur l'os le plus fréquent parmi TOUS les
## sommets de l'îlot élimine ce risque : un sommet individuel isolément côté
## d'une frontière ne peut plus, à lui seul, décider de l'os d'une pièce
## entière. Renvoie None si l'îlot n'a aucun sommet (jamais le cas en
## pratique, cf. appelant).
def _island_dominant_bone(rig: "bpy.types.Object", mesh_obj: "bpy.types.Object",
		me: "bpy.types.Mesh", vidx_list: list) -> "str | None":
	votes: dict = {}
	mw = mesh_obj.matrix_world
	for vidx in vidx_list:
		world_point = mw @ me.vertices[vidx].co
		name = _nearest_stable_bone(rig, world_point)
		if name is not None:
			votes[name] = votes.get(name, 0) + 1
	if not votes:
		return None
	return max(votes.items(), key=lambda kv: kv[1])[0]


## Après la liaison par poids automatiques (`_bind_automatic`), certains
## petits îlots topologiques du costume Tripo — RÉELLEMENT détachés du corps
## (gap monde > `SMALL_ISLAND_GAP_THRESHOLD_M`, cf. sa docstring), pas
## seulement séparés par couture — ressortent MAL pondérés par le solveur de
## chaleur : trop loin/trop peu connectés au squelette pour un poids fiable,
## ils mélangent parfois deux os voisins (un bord de collerette qui suit un
## peu la rotation de la tête ET un peu celle du torse) — un mélange qui
## ÉTIRE la pièce hors de sa forme d'origine dès que la pose s'écarte du bind
## pose (sondé sur Guet : une pièce sombre de la collerette/basque traverse
## le torse en Idle pour cette raison précise).
##
## Cette fonction REMPLACE leur pondération par une attache RIGIDE — 100% de
## poids sur l'os `DEF-` GÉOMÉTRIQUEMENT le plus proche de l'îlot
## (`_island_dominant_bone`, vote par sommet sur `_nearest_deform_bone`),
## jamais de mélange : proximité au SQUELETTE, pas à un sommet de peau (cf.
## docstring de `_nearest_deform_bone` pour le contresens que ça évite).
## Renvoie le nombre de sommets rigidifiés (0 si rien à faire).
def _rigidify_small_islands(mesh_obj: "bpy.types.Object", rig: "bpy.types.Object",
		weld_dist: float, max_vertex_fraction: float) -> int:
	import mathutils.kdtree

	me = mesh_obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	bm.verts.ensure_lookup_table()
	bm_welded = bm.copy()
	bmesh.ops.remove_doubles(bm_welded, verts=bm_welded.verts, dist=weld_dist)
	bm_welded.verts.ensure_lookup_table()
	bm_welded.verts.index_update()
	components = _connected_components(bm_welded)
	bm.free()

	if len(components) <= 1:
		bm_welded.free()
		return 0

	# Correspondance sommet soudé -> sommet(s) RÉELS d'origine (mêmes indices
	# que `me.vertices`) par position — même technique que `_bind_automatic`
	# (la fusion à `weld_dist` ne déplace quasiment pas les sommets
	# conservés, donc le plus-proche-voisin suffit, cf. sa docstring).
	kd_welded = mathutils.kdtree.KDTree(len(bm_welded.verts))
	for v in bm_welded.verts:
		kd_welded.insert(v.co, v.index)
	kd_welded.balance()
	comp_of_welded_index = {}
	for ci, comp in enumerate(components):
		for v in comp:
			comp_of_welded_index[v.index] = ci

	orig_by_comp: dict = {}
	for i, v in enumerate(me.vertices):
		_co, widx, _dist = kd_welded.find(v.co)
		ci = comp_of_welded_index[widx]
		orig_by_comp.setdefault(ci, []).append(i)

	total_verts = len(me.vertices)
	fraction_threshold = max_vertex_fraction * total_verts
	main_mins, main_maxs = _component_world_aabb(components[0], mesh_obj.matrix_world)

	rigidified = 0
	islands_touched = 0
	for ci, comp in enumerate(components):
		if ci == 0 or len(comp) > fraction_threshold:
			continue  # corps principal, ou composante trop grosse pour être une pièce parasite
		comp_mins, comp_maxs = _component_world_aabb(comp, mesh_obj.matrix_world)
		gap = _aabb_gap(main_mins, main_maxs, comp_mins, comp_maxs)
		if gap <= SMALL_ISLAND_GAP_THRESHOLD_M:
			continue  # composante juste séparée par une couture, encore au contact du corps :
			          # jamais repérée par CHK-16 (check_asset.py), doit garder son skinning normal
		vidx_list = orig_by_comp.get(ci, [])
		target_name = _island_dominant_bone(rig, mesh_obj, me, vidx_list)
		if target_name is None:
			continue  # îlot vide (jamais le cas en pratique)
		if target_name not in mesh_obj.vertex_groups:
			mesh_obj.vertex_groups.new(name=target_name)
		for vidx in vidx_list:
			for vg in mesh_obj.vertex_groups:
				vg.remove([vidx])
			mesh_obj.vertex_groups[target_name].add([vidx], 1.0, 'REPLACE')
			rigidified += 1
		islands_touched += 1
	bm_welded.free()
	if rigidified:
		print("RIG_TRIPO_RIGID_ISLANDS sommets rigidifiés=%d sur %d îlot(s) (gap > %.2f m des %d sommets)"
			% (rigidified, islands_touched, SMALL_ISLAND_GAP_THRESHOLD_M, total_verts))
	return rigidified


## Garde le matériau (et sa texture 2K) du fichier Tripo tel quel — seul le
## NOM change, en `f"{char_id}_tex"` (convention lue par
## `scripts/player/PlayerLook.gd`/`tools/character_shots.gd` : un matériau
## `*_tex` porte sa propre texture d'albédo et n'est jamais repeint en aplat,
## contrairement aux slots `outfit`/`cloth`/`gear`/`skin`/`accent` des 6
## agents "maison", cf. `tools/review/model_preview.gd::_restyle`).
def _rename_material(mesh_obj: "bpy.types.Object", char_id: str) -> None:
	if not mesh_obj.data.materials:
		raise RuntimeError("rig_tripo_character: aucun matériau sur %r" % mesh_obj.name)
	for slot in mesh_obj.data.materials:
		if slot is not None:
			slot.name = "%s_tex" % char_id


def _do_export(rig: "bpy.types.Object", mesh_obj: "bpy.types.Object", out_path: str) -> None:
	# Défensif (voir `_purge_icosphere_widgets`) : `use_selection=True`
	# ci-dessous ne sélectionne jamais ce widget, mais on s'assure qu'aucun
	# homonyme orphelin ne traîne dans `bpy.data.objects` avant d'écrire.
	_purge_icosphere_widgets()
	bpy.ops.object.select_all(action='DESELECT')
	mesh_obj.select_set(True)
	rig.select_set(True)
	bpy.context.view_layer.objects.active = rig
	bpy.ops.export_scene.gltf(
		filepath=out_path,
		export_format='GLB',
		use_selection=True,
		export_apply=False,
		export_yup=True,
		export_materials='EXPORT',
		export_cameras=False,
		export_lights=False,
		export_animations=True,
		export_animation_mode='ACTIONS',
	)


## Retire les objets d'une passe de vérification ET les datablocks devenus
## orphelins (actions/maillages/matériaux/textures) — indispensable ici :
## `export_animation_mode='ACTIONS'` exporte TOUTES les actions de
## `bpy.data.actions` (voir l'en-tête de make_characters.py), donc une
## réimportation qui laisserait les 46 actions (et le matériau + sa texture
## 2K) de la passe précédente en orphelins les ferait réexporter EN PLUS des
## nouveaux à la prochaine passe (sondé : export 10 s -> 27 s -> 50 s -> 113 s
## sans ce nettoyage, tout s'accumulant à chaque repasse).
##
## `bpy.data.objects.remove` est appelé défensivement (`try/except
## ReferenceError`) : `imported` peut contenir un objet nommé "Icosphere"
## (widget de bone recréé par l'IMPORTEUR glTF à CHAQUE réimport d'un
## squelette — §Notes ART-11X, voir `_purge_icosphere_widgets`) DÉJÀ retiré
## entre-temps par l'appel défensif de `_do_export` sur la passe de réexport
## (`_export` : `_do_export(imported_rig, imported_mesh, out_path)` PUIS
## `_purge_verification_objects(imported)` — le même "Icosphere" figure dans
## les DEUX). Sans cette garde, le second retrait lève `ReferenceError:
## StructRNA of type Object has been removed` (sondé sur vanne_v1.glb dès
## qu'une passe de réparation post-export a lieu, cf. `_MAX_EXPORT_VERIFY_
## PASSES` : un cas courant, pas un cas limite).
def _purge_verification_objects(imported: list) -> None:
	for o in imported:
		try:
			bpy.data.objects.remove(o, do_unlink=True)
		except ReferenceError:
			pass  # déjà supprimé (ex. "Icosphere" purgé par un _do_export intermédiaire)
	# Matériaux et texture 2K compris (sondé : sans eux, chaque repasse garde
	# en mémoire une copie orpheline de plus de l'image — export 10 s -> 23 s
	# -> 35 s -> 48 s malgré le nettoyage des seules actions/maillages).
	for coll in (bpy.data.actions, bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.images):
		for block in list(coll):
			if block.users == 0:
				coll.remove(block)


## Cf. `_repair_nonmanifold` : l'export glTF d'un maillage skinné peut lui-
## même réintroduire quelques arêtes non-manifold (fusion de sommets de
## couture dont les poids d'os quantifiés finissent par coïncider). Chaque
## repasse en corrige un peu moins (sondé sur verrou.glb : 12 -> 5 -> 2 -> 0,
## convergence en 4 passes) — une convergence par paliers décroissants, pas un
## point fixe immédiat. Le RYTHME de décroissance dépend du maillage : sondé
## sur vif_v1.glb (relance QA de ce fichier), la même mécanique décroît plus
## lentement et de façon légèrement non déterministe d'une exécution à
## l'autre (ordre d'itération bmesh sur des faces à aire égale) — observé
## 19 -> 16 -> 12 -> 9 -> 7 -> 3 (6 passes, PAS encore convergé, 1 arête
## résiduelle -> `check_asset.py` en échec dur) puis, sur une relance
## identique, 19 -> 16 -> 12 -> 9 -> 7 -> 3 -> 1 -> 0 (convergence en 7
## passes). `_MAX_EXPORT_VERIFY_PASSES = 6` était donc insuffisant pour ce
## maillage ; la valeur ci-dessous laisse une marge (le nettoyage ci-dessus
## rend chaque repasse rapide, ~13 s sur vif_v1.glb).
_MAX_EXPORT_VERIFY_PASSES = 12


## Exporte PUIS réimporte le .glb TEL QU'ÉCRIT pour vérifier/corriger : seul
## le FICHIER RÉEL fait foi (docs/3D_PIPELINE.md §1 : jamais juger sur l'état
## en mémoire), et sondé — l'export glTF d'un maillage SKINNÉ peut lui-même
## réintroduire quelques arêtes non-manifold (jusqu'à 12 sur verrou.glb,
## jamais présentes dans le maillage en mémoire juste avant l'export) en
## fusionnant à l'export deux sommets de couture UV dont les poids d'os
## quantifiés (JOINTS_0/WEIGHTS_0, précision fixe du format glTF) finissent
## par coïncider EXACTEMENT — un artefact du ré-indexage des sommets par
## l'exportateur, pas du maillage qu'on lui donne. On relit donc ce qu'on
## vient d'écrire et, si besoin, on répare (`_repair_nonmanifold`, skinning/
## animations intacts : ne touche que quelques faces, jamais les os) puis on
## réexporte par-dessus, jusqu'à convergence (`_MAX_EXPORT_VERIFY_PASSES`).
def _export(char_id: str, rig: "bpy.types.Object", mesh_obj: "bpy.types.Object", out_dir: str) -> None:
	os.makedirs(out_dir, exist_ok=True)
	out_path = os.path.join(out_dir, "%s.glb" % char_id)
	_do_export(rig, mesh_obj, out_path)
	# Libère le nom du matériau ("<id>_tex") avant la première réimportation
	# de vérification : sinon la copie réimportée entre en collision avec
	# l'objet original encore en mémoire et Blender la renomme "<id>_tex.001"
	# (puis .002, .003... à chaque repasse) — ce nom AURAIT fini dans le
	# fichier final, cassant la convention `*_tex` lue par PlayerLook.gd.
	bpy.data.objects.remove(mesh_obj, do_unlink=True)
	bpy.data.objects.remove(rig, do_unlink=True)
	_purge_verification_objects([])

	converged = False
	for attempt in range(_MAX_EXPORT_VERIFY_PASSES):
		verify_objs_before = set(bpy.data.objects.keys())
		bpy.ops.import_scene.gltf(filepath=out_path)
		imported = [o for o in bpy.data.objects if o.name not in verify_objs_before]
		imported_meshes = [o for o in imported if o.type == 'MESH' and o.data and len(o.data.polygons) > 100]
		# Renomme défensivement (cf. commentaire ci-dessus) : garantit que
		# c'est TOUJOURS "<id>_tex", quel que soit ce que Blender a nommé la
		# copie réimportée.
		for imp in imported_meshes:
			_rename_material(imp, char_id)
		# `_repair_nonmanifold` fait SA PROPRE détection sur une copie soudée
		# (comme check_asset.py) : un comptage brut ICI, SANS fusion, sous-
		# évaluerait le problème (sondé : la quasi-totalité des arêtes en
		# défaut n'apparaissent qu'après fusion des doublons de couture UV,
		# cf. sa docstring) — on l'appelle donc SYSTÉMATIQUEMENT (no-op, vite,
		# si le fichier exporté est déjà propre) plutôt que de présélectionner.
		total_repaired = 0
		for imp in imported_meshes:
			total_repaired += _repair_nonmanifold(imp, NONMANIFOLD_WELD_DIST)
		if total_repaired == 0:
			converged = True
			_purge_verification_objects(imported)
			break
		print("RIG_TRIPO_EXPORT_REPAIR passe %d : %d face(s) réparée(s) après export, réexport"
			% (attempt + 1, total_repaired))
		imported_rig = next((o for o in imported if o.type == 'ARMATURE'), None)
		imported_mesh = next((o for o in imported_meshes), None)
		if imported_rig is None or imported_mesh is None:
			_purge_verification_objects(imported)
			break
		_do_export(imported_rig, imported_mesh, out_path)
		_purge_verification_objects(imported)

	if not converged:
		print("RIG_TRIPO_WARN non-manifold résiduel après %d passes de vérification — "
			"relancer check_asset.py sur %s pour confirmer" % (_MAX_EXPORT_VERIFY_PASSES, out_path))

	print("RIG_TRIPO_CHARACTER_OK %s -> %s" % (char_id, out_path))


## Critère d'acceptation ART-11Z : "pour chaque os, le repos exporté égale
## celui de ual.glb (écart d'orientation < 0,5°, vérifié par script)".
## Réimporte l'agent EXPORTÉ (le fichier réel, jamais l'état en mémoire — même
## principe que `_export`/docs/3D_PIPELINE.md §1) ET une copie fraîche de la
## source commune `ual.glb`, puis compare la DIRECTION de repos (tail_local -
## head_local, normalisée) de chaque os `DEF-` entre les deux squelettes.
## Comparer une DIRECTION plutôt que la matrice complète est volontaire : la
## mise à l'échelle uniforme du squelette (`_scale_rig_uniform`, un facteur
## scalaire appliqué à `head`/`tail`, jamais une matrice de rotation) ne
## change AUCUNE direction de bone — seule la longueur/position changent —
## donc c'est la mesure qui isole exactement "le repos a-t-il gardé la MÊME
## orientation que la source", indépendamment du gabarit (1,80 m vs le
## mannequin de référence ual.glb, ~1,83 m, cf. `_scale_rig_uniform`).
def _compare_rest_to_source(out_path: str) -> dict:
	_clear_scene()
	bpy.ops.import_scene.gltf(filepath=UAL_SOURCE_GLB)
	ual_rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
	ual_dirs = {b.name: (b.tail_local - b.head_local).normalized()
		for b in ual_rig.data.bones if b.name.startswith(_DEF_BONE_PREFIX)}

	_clear_scene()
	bpy.ops.import_scene.gltf(filepath=out_path)
	out_rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
	out_bones = {b.name for b in out_rig.data.bones}

	per_bone_deg = {}
	worst_bone, worst_deg = None, 0.0
	for name, ual_dir in ual_dirs.items():
		if name not in out_bones:
			continue  # os manquant : signalé séparément via `missing_bones` ci-dessous
		out_dir = (out_rig.data.bones[name].tail_local - out_rig.data.bones[name].head_local).normalized()
		dot = max(-1.0, min(1.0, ual_dir.dot(out_dir)))  # borné : erreurs de virgule flottante -> acos hors domaine
		deg = math.degrees(math.acos(dot))
		per_bone_deg[name] = round(deg, 4)
		if deg > worst_deg:
			worst_bone, worst_deg = name, deg

	missing_bones = sorted(set(ual_dirs) - out_bones)
	ok = worst_deg < REST_ORIENTATION_TOLERANCE_DEG and not missing_bones
	return {
		"ok": ok,
		"bones_checked": len(per_bone_deg),
		"worst_bone": worst_bone,
		"worst_deg": round(worst_deg, 4),
		"missing_bones": missing_bones,
		"per_bone_deg": per_bone_deg,
	}


def main() -> None:
	args = parse_args()
	in_path = os.path.abspath(args.in_path)
	if not os.path.isfile(in_path):
		print("RIG_TRIPO_FAIL fichier introuvable : %s" % in_path)
		sys.exit(1)

	_clear_scene()
	mesh_obj = _import_tripo(in_path)
	_repair_nonmanifold(mesh_obj, args.weld_dist)
	_rescale_feet_to_origin(mesh_obj, TARGET_HEIGHT)

	rig, mannequin, mannequin_height = _import_common_rig()
	_scale_rig_uniform(rig, TARGET_HEIGHT / mannequin_height)
	_scale_mannequin(mannequin, TARGET_HEIGHT / mannequin_height)
	# Repos T-pose D'ORIGINE, capturé AVANT toute pose (§Notes ART-11Z, tête de
	# fichier) : `_restore_original_rest` y ramènera le squelette OCTET PRÈS
	# une fois le skinning calculé sur le repos de liaison temporaire
	# ci-dessous (voir `_snapshot_arm_rest` : jamais un round-trip par
	# rotation seul, la chaîne UAL-G n'est pas parfaitement colinéaire).
	arm_snapshot = _snapshot_arm_rest(rig)

	measured_arm_dirs = {side: _measure_arm_axis(mesh_obj, rig, side) for side in ("L", "R")}
	_apply_bind_rest(rig, measured_arm_dirs, bake_meshes=(mannequin,))

	if args.weights == "heat":
		_bind_automatic(mesh_obj, rig)
	else:
		_bind_from_mannequin(mesh_obj, rig, mannequin)
	mannequin_mesh = mannequin.data
	bpy.data.objects.remove(mannequin, do_unlink=True)
	bpy.data.meshes.remove(mannequin_mesh)
	_rigidify_small_islands(mesh_obj, rig, args.weld_dist, SMALL_ISLAND_MAX_VERTEX_FRACTION)
	_rename_material(mesh_obj, args.char_id)

	_restore_original_rest(rig, mesh_obj, arm_snapshot)

	mesh_obj.data.calc_loop_triangles()
	tris = len(mesh_obj.data.loop_triangles)
	print("RIG_TRIPO_TRIS %s = %d" % (args.char_id, tris))

	_export(args.char_id, rig, mesh_obj, args.out_dir)

	out_path = os.path.join(args.out_dir, "%s.glb" % args.char_id)
	rest_check = _compare_rest_to_source(out_path)
	if rest_check["ok"]:
		print("RIG_TRIPO_REST_CHECK_OK %s : %d os comparés, écart max %.4f° (%s) < %.1f°"
			% (args.char_id, rest_check["bones_checked"], rest_check["worst_deg"],
				rest_check["worst_bone"], REST_ORIENTATION_TOLERANCE_DEG))
	else:
		print("RIG_TRIPO_REST_CHECK_FAIL %s : écart max %.4f° sur l'os %r (seuil %.1f°), os manquants=%s"
			% (args.char_id, rest_check["worst_deg"], rest_check["worst_bone"],
				REST_ORIENTATION_TOLERANCE_DEG, rest_check["missing_bones"]))
		sys.exit(1)


if __name__ == "__main__":
	main()
