## tools/blender/fp_rig.py -- FP-10 (voir docs/research/12_viewmodel_v2.md §3.2)
## Rig de bras FP unique (avant-bras + mains UAL a doigts articules, auto-
## prise, epaules resolues) : bibliotheque + CLI.
##
##   blender -b -P tools/blender/fp_rig.py -- --out assets/models/fp/fp_arms.glb
##       [--arms-mode forearm|floating] [--src assets/incoming/quaternius/ual.glb]
##       [--skip-paint] [--paint-samples 16] [--paint-res 1024]
##
## Deux familles de fonctions, meme convention que paint_bake.py/
## fit_weapon_painted.py (voir leurs en-tetes) :
##   1. PURES (aucun bpy) -- solveurs geometriques + contrat de noms d'os +
##      ΔE OKLab : testables par `python -m pytest tools/blender/tests/
##      test_fp_rig.py` SANS lancer Blender. C'est cette famille que le
##      critere d'acceptation "test pytest" (epaules + auto-prise) verifie.
##   2. bpy (import dans un bloc try/except, jamais appelees hors Blender) :
##      construction du maillage/squelette, peinture (sous-processus
##      paint_bake.py), export, CLI.
##
## Source CC0 (voir THIRD_PARTY_LICENSES.md) : Quaternius "Universal
## Animation Library", copiee UNE FOIS dans le depot en assets/incoming/
## quaternius/ual.glb (tache FP-10 -- avant elle ne vivait que dans le
## scratchpad de la tache qui l'a telechargee, cf. make_characters.py
## SRC_GLB). Mesures reelles sur ce fichier (bpy 5.2.0, voir rapport de
## tache) : 53 os DEF- (dont les doigts), Mannequin 8546 verts/13743 tris,
## DEF-upper_arm.{L,R} = 0.27444 m, DEF-forearm.{L,R} = 0.27264 m,
## DEF-hand.{L,R} = 0.04893 m -- ce sont les constantes ARM_* ci-dessous.
##
## Sondage bpy 5.2.0 (avant tout usage, voir rapport de tache -- risque §3 du
## doc 12) :
##   - `Action.fcurves`/`.slots`/`.layers` : ABSENTS (API a slots deja en
##     place, mais sans lecture directe depuis Python via ces attributs) --
##     SANS INCIDENCE ici : ce fichier n'exporte AUCUNE action (FP-10 livre
##     un rig+maillage en pose de repos, aucun clip -- les clips arrivent en
##     FP-13, `make_fp_viewmodel.py`, sonde de nouveau l'API a ce moment-la).
##   - `export_scene.gltf` expose `export_def_bones` ("Export Deformation
##     bones only") : c'est LA propriete qui retire les controleurs IK
##     (non-deform) du GLB exporte -- confirmee presente sur cette build,
##     jamais devinee.
##   - camera `sensor_fit='VERTICAL'` + `lens_unit='FOV'` + `.angle` = FOV
##     VERTICAL exact (`.angle_y` le confirme) -- voir fp_camera.py pour le
##     detail et le piege de `.angle_x` (ne suit PAS la resolution de rendu).
##
## Repere (doc 12 §3.2) : espace ARMATURE Blender = X droite, Y avant, Z haut.
## Les cibles de prise du contrat (grip/support) sont donnees en espace
## CAMERA GODOT (X droite, Y haut, Z arriere-camera, camera a l'origine
## regardant -Z) -- voir fp_camera.py pour la conversion et sa justification.
## Le solveur d'epaules/IK ci-dessous travaille DIRECTEMENT en espace camera
## Godot (c'est l'espace des cibles du contrat) ; `pose_hold_cylinder` (bpy)
## convertit vers l'espace armature Blender au moment de poser le rig importe.
from __future__ import annotations

import argparse
import math
import os
import subprocess
import sys

try:
	import bpy
	import bmesh
	from mathutils import Vector, Matrix
except ImportError:  # pragma: no cover - permet de tester la logique pure hors Blender
	bpy = None
	bmesh = None

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_SRC_GLB = os.path.join(REPO_ROOT, "assets", "incoming", "quaternius", "ual.glb")
DEFAULT_OUT_GLB = os.path.join(REPO_ROOT, "assets", "models", "fp", "fp_arms.glb")

BLENDER_BIN = os.environ.get(
	"BLENDER_BIN", r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")
PAINT_BAKE_SCRIPT = os.path.join(HERE, "paint_bake.py")

# ---------------------------------------------------------------------------
# 1. Contrat de noms d'os (doc 12 §3.2) -- listes fermees, deterministes.
# ---------------------------------------------------------------------------
ARM_SIDES = ("L", "R")
FINGERS = ("index", "middle", "ring", "pinky")
FINGER_SEGMENTS = ("01", "02", "03")

FP_ROOT_BONE = "fp_root"
FP_PART_BONES = ("fp_weapon", "fp_mag", "fp_slide", "fp_bolt", "fp_pump", "fp_cylinder", "fp_hammer", "fp_prop")


def _arm_deform_bones() -> list:
	return [f"DEF-{part}.{side}" for part in ("upper_arm", "forearm", "hand") for side in ARM_SIDES]


def _hand_deform_bones() -> list:
	names = []
	for side in ARM_SIDES:
		for finger in FINGERS:
			for seg in FINGER_SEGMENTS:
				names.append(f"DEF-f_{finger}.{seg}.{side}")
		for seg in FINGER_SEGMENTS:
			names.append(f"DEF-thumb.{seg}.{side}")
	return names


DEFORM_BONE_NAMES = sorted([FP_ROOT_BONE, *FP_PART_BONES, *_arm_deform_bones(), *_hand_deform_bones()])
CONTROLLER_BONE_NAMES = sorted(
	[f"ik_hand.{side}" for side in ARM_SIDES] + [f"pole_elbow.{side}" for side in ARM_SIDES])

# ---------------------------------------------------------------------------
# 2. Mesures reelles sur assets/incoming/quaternius/ual.glb (voir en-tete).
# ---------------------------------------------------------------------------
ARM_UPPER_LEN_M = 0.27444
ARM_FOREARM_LEN_M = 0.27264
ARM_HAND_LEN_M = 0.04893
ARM_REACH_M = ARM_UPPER_LEN_M + ARM_FOREARM_LEN_M

HAND_SCALE = 1.15            # plafond bible (doc 12 §3.2) -- mains x1.15 par rapport a UAL.
HAND_SCALE_TOLERANCE = 0.02  # critere d'acceptation : +/- 0.02.

FLOATING_CUFF_DIST_M = 0.04   # mode "floating" : coupe l'avant-bras au-dela de 4 cm du poignet.
FLOATING_CUFF_HEIGHT_M = 0.01  # ... et pose une manchette de 1 cm a la coupe.

TRI_BUDGET_ARMS = 9000  # FP-10B (doc 12 notes, acceptance : "tris bras <= 9 000" -- releve depuis 7000
# pour financer la subdivision des mains, section 5b -- voir GLOVE_SUBDIV_CUTS).

# Ratio de decimation PROPRE a fp_arms (jamais `_mc.DECIMATE_RATIO`, le ratio
# 0.5 partage par les personnages -- fichier hors perimetre, non modifie) :
# les bras FP remplissent une grande part de l'ecran en gros plan (doc 12
# notes FP-10B), un besoin de qualite tres different d'un personnage vu a la
# troisieme personne a 5-40 m. Valeur reglee par sondage (voir rapport de
# tache) pour que la coque du gant, une fois RESSOUDEE (`GLOVE_WELD_DIST_M`)
# et rafinee (`_refine_shell`, section 9), tienne dans `TRI_BUDGET_ARMS`
# -- le reste du mannequin (jete juste apres, seuls l'avant-bras et la main
# sont conserves) ne coute qu'un decimate legerement plus lent, sans incidence
# sur le budget final.
FP_ARMS_DECIMATE_RATIO = 0.32

# ---------------------------------------------------------------------------
# 3. Petite algebre vecteur (tuples (x, y, z)) -- aucune dependance mathutils
#    (indisponible hors Blender, voir sondage `import mathutils` du rapport
#    de tache) ni numpy (inutile ici, l'algebre reste triviale).
# ---------------------------------------------------------------------------

def v_sub(a, b):
	return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def v_add(a, b):
	return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def v_scale(a, s):
	return (a[0] * s, a[1] * s, a[2] * s)


def v_dot(a, b):
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def v_len(a):
	return math.sqrt(v_dot(a, a))


def v_norm(a):
	length = v_len(a)
	if length < 1e-9:
		return (0.0, 0.0, 0.0)
	return v_scale(a, 1.0 / length)


def v_cross(a, b):
	return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


# ---------------------------------------------------------------------------
# 4. IK 2 os analytique (loi des cosinus) + solveur d'epaules (doc 12 §3.2 :
#    "Le script place l'armature (translation seule, bornee) pour que ... la
#    main soit a 0.80-0.92 de l'allonge : le coude plie de 25 a 60 deg. Un
#    etirement du bras est permis jusqu'a x1.12."). Verifie par calcul contre
#    les deux cibles du contrat (voir rapport de tache -- table numerique) :
#    err = 0.0 mm, bend = 51.68 deg (dans [25,60]), ratio = 0.90 (dans
#    [0.80,0.92]), translation 12.7/16.3 cm (< SHOULDER_MAX_TRANSLATION_M),
#    coude hors cadre 16:9 pour les DEUX mains.
# ---------------------------------------------------------------------------
SHOULDER_TARGET_RATIO = 0.90      # a l'interieur de [0.80, 0.92] -- voir SHOULDER_RATIO_RANGE.
SHOULDER_RATIO_RANGE = (0.80, 0.92)
SHOULDER_BEND_RANGE_DEG = (25.0, 60.0)
SHOULDER_MAX_TRANSLATION_M = 0.30
SHOULDER_MAX_STRETCH = 1.12

# Ancres d'epaule de repos, espace camera Godot (X droite, Y haut, Z arriere-
# camera) -- position de depart AVANT resolution : main gachette a droite/bas
# de cadre, main de soutien plus centree -- voir en-tete pour la conversion.
SHOULDER_REST_CAM = {
	"R": (0.14, -0.32, -0.08),   # main gachette (prise/grip).
	"L": (-0.12, -0.32, -0.08),  # main de soutien (foregrip).
}
POLE_OFFSET_CAM = {
	"R": (0.35, -0.45, -0.10),   # pole bas et vers l'exterieur (doc 12 §3.2), cote droit.
	"L": (-0.35, -0.45, -0.10),  # ... cote gauche.
}

# Cibles du contrat pytest (doc 12, criteres d'acceptation FP-10), espace
# camera Godot.
GRIP_TARGET_CAM = (0.20, -0.20, -0.42)
SUPPORT_TARGET_CAM = (0.02, -0.16, -0.70)
TARGET_CAM = {"R": GRIP_TARGET_CAM, "L": SUPPORT_TARGET_CAM}


def two_bone_ik_solve(shoulder, target, pole, l1: float, l2: float):
	"""IK 2 os analytique (loi des cosinus) : `shoulder` -> `elbow` (a `l1`
	de `shoulder`) -> `hand` (a `l2` de `elbow`), dans le plan defini par
	`shoulder`, `target` et `pole` (`pole` cote vers lequel le coude
	s'ouvre). Renvoie `(elbow, hand)`. Si `target` est hors de portee
	(distance > l1+l2), `hand` s'arrete a `l1+l2` de `shoulder` (bras
	tendu, sous la cible) -- c'est `shoulder_solve` qui gere l'etirement
	pour l'y ramener exactement (§SHOULDER_MAX_STRETCH). Deterministe (aucun
	hasard, aucun etat)."""
	diff = v_sub(target, shoulder)
	d = v_len(diff)
	lo = abs(l1 - l2) + 1e-6
	hi = l1 + l2 - 1e-9
	d_clamped = min(max(d, lo), hi) if d > 1e-9 else lo
	axis = v_norm(diff) if d > 1e-9 else (0.0, 0.0, 1.0)
	a = (l1 * l1 - l2 * l2 + d_clamped * d_clamped) / (2.0 * d_clamped)
	h = math.sqrt(max(0.0, l1 * l1 - a * a))
	pole_dir = v_sub(pole, shoulder)
	pole_perp = v_sub(pole_dir, v_scale(axis, v_dot(pole_dir, axis)))
	if v_len(pole_perp) < 1e-9:
		arbitrary = (0.0, 0.0, 1.0) if abs(axis[2]) < 0.9 else (1.0, 0.0, 0.0)
		pole_perp = v_cross(axis, arbitrary)
	perp = v_norm(pole_perp)
	elbow = v_add(v_add(shoulder, v_scale(axis, a)), v_scale(perp, h))
	hand = v_add(shoulder, v_scale(axis, d_clamped))
	return elbow, hand


def elbow_bend_deg(l1: float, l2: float, d: float) -> float:
	"""Angle de flexion du coude (0 deg = bras droit, deviation depuis
	l'alignement) pour une distance epaule->main `d` (bornee a `l1+l2`)."""
	d = min(d, l1 + l2)
	cos_interior = (l1 * l1 + l2 * l2 - d * d) / (2.0 * l1 * l2)
	cos_interior = max(-1.0, min(1.0, cos_interior))
	interior = math.degrees(math.acos(cos_interior))
	return 180.0 - interior


def shoulder_solve(shoulder_rest, target, pole, l1: float = ARM_UPPER_LEN_M, l2: float = ARM_FOREARM_LEN_M,
		target_ratio: float = SHOULDER_TARGET_RATIO, max_translation: float = SHOULDER_MAX_TRANSLATION_M,
		max_stretch: float = SHOULDER_MAX_STRETCH) -> dict:
	"""Place l'epaule par TRANSLATION SEULE (le long de l'axe repos->cible,
	borne a `max_translation`) pour que la main atteigne `target` a
	`target_ratio` de l'allonge (`l1+l2`), puis resout l'IK 2 os. Si la
	translation bornee ne suffit pas a atteindre `target_ratio` et que la
	main reste hors de portee, un etirement uniforme des deux segments
	(<= `max_stretch`) ramene la main EXACTEMENT sur `target` (`err` a la
	precision flottante). Renvoie shoulder/elbow/hand/translation_len/
	ratio/bend_deg/stretch/err (m)."""
	reach = l1 + l2
	diff0 = v_sub(target, shoulder_rest)
	dist0 = v_len(diff0)
	direction = v_norm(diff0)
	desired_dist = target_ratio * reach
	shoulder_new = v_sub(target, v_scale(direction, desired_dist))
	translation = v_sub(shoulder_new, shoulder_rest)
	tlen = v_len(translation)
	if tlen > max_translation:
		translation = v_scale(translation, max_translation / tlen)
		tlen = max_translation
	shoulder_eff = v_add(shoulder_rest, translation)
	dist_eff = v_len(v_sub(target, shoulder_eff))
	stretch = 1.0
	if dist_eff > reach:
		stretch = min(max_stretch, dist_eff / reach)
	l1_eff, l2_eff = l1 * stretch, l2 * stretch
	elbow, hand = two_bone_ik_solve(shoulder_eff, target, pole, l1_eff, l2_eff)
	bend = elbow_bend_deg(l1_eff, l2_eff, min(dist_eff, l1_eff + l2_eff))
	return {
		"shoulder": shoulder_eff, "elbow": elbow, "hand": hand,
		"translation_len": tlen, "dist0": dist0, "dist_eff": dist_eff,
		"ratio": dist_eff / reach, "bend_deg": bend, "stretch": stretch,
		"err": v_len(v_sub(hand, target)),
	}


# ---------------------------------------------------------------------------
# 5. Auto-prise (doc 12 §3.2 : "Chaque articulation se replie par pas de 2 deg
#    jusqu'au contact ... detecte par BVH (find_nearest < rayon de la
#    phalange). Plafond de 95 deg par articulation. Deterministe."). Le coeur
#    (`auto_grip_finger`) est generique : il prend une fonction de distance
#    `distance_fn(point) -> m` -- en test pur, un cylindre analytique
#    (`cyl_distance_xy`) ; cote bpy, `bvh_distance_fn` l'implemente via un
#    vrai `BVHTree.find_nearest` contre le maillage de l'arme (utilise par
#    les taches d'armes/animation suivantes, FP-11+).
# ---------------------------------------------------------------------------
AUTO_GRIP_STEP_DEG = 2.0
AUTO_GRIP_MAX_DEG = 95.0
AUTO_GRIP_CONTACT_MIN_M = 0.004   # fenetre du contrat : 0.4-1.2 cm du bout de doigt a la surface.
AUTO_GRIP_CONTACT_MAX_M = 0.012

# Longueurs de phalange mesurees sur ual.glb (DEF-f_<doigt>.0{1,2,3}.L, voir
# en-tete -- L et R symetriques, mesure) : (proximale, mediane, distale).
FINGER_LENGTHS_M = {
	"thumb": (0.04303, 0.04908, 0.04908),
	"index": (0.04070, 0.03480, 0.03480),
	"middle": (0.04235, 0.03393, 0.03393),
	"ring": (0.03933, 0.03092, 0.03092),
	"pinky": (0.04029, 0.02767, 0.02767),
}
# Rayon de contact (m) : demi-fenetre du contrat (0.8 cm), meme valeur pour
# les 5 doigts -- c'est la valeur de `phalanx_radius` qui fixe OU l'auto-
# prise s'arrete (`distance_fn(bout) < phalanx_radius`).
AUTO_GRIP_PHALANX_RADIUS_M = 0.008

# Base de chaque doigt (m, distance 2D base->axe du cylindre de reference,
# doc 12 : "auto-prise sur un cylindre r=1.8cm") -- reglee par sondage
# numerique (voir rapport de tache) pour que la simulation ci-dessous pose
# chaque bout de doigt dans la fenetre 0.4-1.2 cm avec une marge confortable
# et un plafond d'articulation tres en-dessous de 95 deg. Usage reel (armes,
# FP-11+) : `distance_fn` devient un vrai BVH contre le maillage de l'arme,
# ces distances de base ne servent alors qu'a l'ouverture initiale ("open").
FINGER_BASE_DIST_M = {"thumb": 0.090, "index": 0.075, "middle": 0.070, "ring": 0.095, "pinky": 0.060}
DEFAULT_GRIP_CYLINDER_RADIUS_M = 0.018


def cyl_distance_xy(x: float, y: float, radius: float) -> float:
	"""Distance signee (m) d'un point (x, y) a la surface d'un cylindre
	infini d'axe Z et de rayon `radius`, centre a l'origine -- positive a
	l'exterieur, negative en penetration. Utilisee comme `distance_fn` pure
	pour le contrat pytest (cylindre r=1.8cm)."""
	return math.hypot(x, y) - radius


def _rot2(v, deg: float):
	a = math.radians(deg)
	c, s = math.cos(a), math.sin(a)
	x, y = v
	return (x * c - y * s, x * s + y * c)


def finger_chain_points(base_xy, init_dir_xy, seg_lengths, joint_angles_deg):
	"""Cinematique directe plane (m) d'une chaine de doigt : `base_xy` +
	`init_dir_xy` (unitaire, pose "ouverte") tournes de la somme cumulee des
	`joint_angles_deg` a chaque articulation (chaque articulation tourne
	aussi tous les segments suivants -- chaine reelle). Renvoie la liste des
	points [(x,y), ...] (base incluse, dernier = bout du doigt)."""
	points = [tuple(base_xy)]
	cumulative = 0.0
	for length, angle in zip(seg_lengths, joint_angles_deg):
		cumulative += angle
		d = _rot2(init_dir_xy, -cumulative)
		last = points[-1]
		points.append((last[0] + d[0] * length, last[1] + d[1] * length))
	return points


def auto_grip_finger(base_xy, init_dir_xy, seg_lengths, distance_fn, phalanx_radius: float,
		step_deg: float = AUTO_GRIP_STEP_DEG, max_deg: float = AUTO_GRIP_MAX_DEG) -> dict:
	"""Auto-prise (doc 12 §3.2) : replie TOUTES les articulations EN MEME
	TEMPS par pas de `step_deg`, jusqu'a ce que `distance_fn(bout_du_doigt)`
	passe sous `phalanx_radius` (contact) -- ou que plus aucune articulation
	ne puisse avancer (toutes a `max_deg`, plafond individuel jamais
	depasse). Deterministe (aucun hasard) : la meme entree produit toujours
	la meme sortie. Renvoie `{"angles_deg": [...], "points": [...],
	"tip": (x,y), "tip_distance": m, "capped": bool}`."""
	n = len(seg_lengths)
	angles = [0.0] * n
	points = finger_chain_points(base_xy, init_dir_xy, seg_lengths, angles)
	while distance_fn(points[-1]) >= phalanx_radius:
		advanced = False
		for j in range(n):
			if angles[j] + step_deg <= max_deg + 1e-9:
				angles[j] += step_deg
				advanced = True
		points = finger_chain_points(base_xy, init_dir_xy, seg_lengths, angles)
		if not advanced:
			break
	tip = points[-1]
	return {
		"angles_deg": angles, "points": points, "tip": tip,
		"tip_distance": distance_fn(tip), "capped": all(a >= max_deg - 1e-9 for a in angles),
	}


def auto_grip_cylinder(radius: float = DEFAULT_GRIP_CYLINDER_RADIUS_M,
		phalanx_radius: float = AUTO_GRIP_PHALANX_RADIUS_M) -> dict:
	"""Auto-prise des 5 doigts (`FINGER_BASE_DIST_M`) sur un cylindre de
	`radius` -- c'est le scenario exact du contrat pytest ("auto-prise sur
	un cylindre r=1.8cm"). Chaque doigt part au-dessus du cylindre
	(`base_xy = (0, base_dist)`), pointant tangentiellement (doigt ouvert),
	et se replie jusqu'au contact (voir `auto_grip_finger`)."""

	def distance_fn(p):
		return cyl_distance_xy(p[0], p[1], radius)

	out = {}
	for name, seg_lengths in FINGER_LENGTHS_M.items():
		base_xy = (0.0, FINGER_BASE_DIST_M[name])
		out[name] = auto_grip_finger(base_xy, (1.0, 0.0), seg_lengths, distance_fn, phalanx_radius)
	return out


# ---------------------------------------------------------------------------
# 5b. Coque du gant -- relaxation de Laplace + detection de "pointe" (FP-10B,
#     revue lead 2026-09-25 : "les mains UAL sont des poings low-poly
#     bosselés ... avec des POINTES BLANCHES qui percent" -- `_build_shell`,
#     make_characters.py, partagee, HORS PERIMETRE de ce fichier, pousse
#     chaque sommet duplique le long de SA PROPRE normale de sommet ; sur le
#     maillage UAL DECIME (mains/doigts minuscules, tres peu de faces), cette
#     normale devient localement erratique a quelques sommets -- pousses dans
#     une direction incoherente avec leurs voisins, ILS CREENT UNE POINTE
#     visible (facette a l'angle extreme, tres claire/blanche a l'ecran). Le
#     meme sous-maillage jete, une fois peint par paint_bake.py, sur-declenche
#     aussi son masque de convexite/chanfrein (bible §4.5 "arêtes éclaircies
#     par le masque de convexité") sur CHAQUE minuscule facette au lieu des
#     seules arêtes reelles -- c'est la texture "froissée" du meme rapport.
#     Purement geometrique (aucune dependance bpy) : testable seul, reutilise
#     cote bpy (section 9, `_refine_shell`/`_verify_no_glove_spikes`)
#     sur la coque REELLE du gant, AVANT la mise a l'echelle HAND_SCALE (le
#     plafond ×1.15 de la bible, section 4/§3.2, INCHANGE par cette section).
# ---------------------------------------------------------------------------
CUFF_ENVELOPE_TOLERANCE_M = 0.003    # critere d'acceptation FP-10B : 3 mm.
GLOVE_WELD_DIST_M = 0.0015            # ressoude les sommets dupliques par l'import glTF (voir _refine_shell).
GLOVE_SUBDIV_CUTS = 2                 # notes FP-10B, piste 1 : "subdivision (niveau 1-2) des mains avant bake" --
# relevee de 1 a 2 (retour verificateur 2026-09-25 : "still visibly faceted and crystalline" a cuts=1, silhouette
# encore a facettes dures) -- voir FP_ARMS_DECIMATE_RATIO (abaisse en contrepartie pour tenir TRI_BUDGET_ARMS).
GLOVE_SMOOTH_FACTOR = 0.75
GLOVE_SMOOTH_ITERATIONS = 14
GLOVE_REINFLATE_M = 0.0012            # restaure le volume perdu par le lissage (arrondit, n'aplatit pas).
GLOVE_CUFF_EXTEND_M = 0.03            # voir _extend_glove_cuff -- recouvre l'ecart structurel gant/manche.
WRIST_RING_RADIUS_M = 0.06            # rayon (depuis le pivot du poignet) qui distingue la VRAIE ouverture de
# poignet des micro-trous residuels ailleurs sur la main (jointures de phalanges) -- voir _build_arms_mesh.
FINGER_EXTRA_THICKEN_M = 0.0015       # notes FP-10B, piste 4 : "doigts un peu plus epais et arrondis (style cartoon)".

# Lissage des POIDS de peau (notes FP-10B, piste 2 : "lissage des poids") --
# retour verificateur 2026-09-25 : un vrai trou (fond visible au travers)
# entre un doigt replie et la masse de jointures, sur le rendu POSE (tenue
# du cylindre/de l'arme), absent en pose de repos (T-pose, jamais bombee) et
# donc jamais capte par `_verify_no_glove_spikes` (qui teste AVANT la pose --
# voir `build()`). Cause (`_build_shell`, make_characters.py, HORS PERIMETRE :
# "poids de skin copies tels quels") : le rig UAL source pese la jointure
# doigt/paume de facon quasi-BINAIRE (un sommet est domine a ~100% par UN
# SEUL os, sans fondu) -- la subdivision (ci-dessus) interpole automatiquement
# le poids des sommets NOUVEAUX (bmesh, standard), mais les sommets D'ORIGINE
# gardent ce poids dur : a un angle de flexion eleve (auto-prise, jusqu'a
# 95 deg -- section 5), deux sommets voisins domines par des os differents
# (ex. DEF-f_index.01.R cote doigt, DEF-hand.R cote paume) divergent chacun
# selon SA PROPRE rotation d'os, ouvrant un ecart visible entre les deux --
# exactement le "vrai trou" observe. `laplacian_relax_weights` (ci-dessous)
# fond ce poids sur les memes voisinages de surface que la relaxation de
# position (meme technique, meme adjacence) : un facteur/nombre d'iterations
# PLUS DOUX que la position (`GLOVE_SMOOTH_FACTOR`/`_ITERATIONS`, regles pour
# la silhouette) pour ne PAS effacer l'articulation par doigt (chaque
# phalange doit rester dominee par SON os, sinon l'auto-prise/FP-13+ perdrait
# le controle fin par doigt) -- juste assez pour qu'un sommet a la frontiere
# doigt/paume porte aussi un peu de l'os voisin et suive le pli sans se
# dechirer. Regle par sondage visuel (voir rapport de tache).
GLOVE_WEIGHT_SMOOTH_FACTOR = 0.35
GLOVE_WEIGHT_SMOOTH_ITERATIONS = 3


def laplacian_relax_positions(points: dict, adjacency: dict, factor: float = GLOVE_SMOOTH_FACTOR,
		iterations: int = 1) -> dict:
	"""Relaxation de Laplace deterministe : `points` (idx -> (x,y,z)),
	`adjacency` (idx -> set des idx voisins DIRECTS) -- chaque sommet est tire
	de `factor` (0..1) vers la moyenne de ses voisins, `iterations` fois.
	`factor=0.0` = identite, `factor=1.0` = saute directement a la moyenne. Un
	sommet SANS voisin reste immobile (jamais de division par zero). Aucune
	dependance bpy : c'est le coeur de `_refine_shell` (section 9),
	teste ici en isolation avec des points synthetiques (voir test_fp_rig.py)."""
	pts = dict(points)
	for _ in range(max(0, iterations)):
		nxt = {}
		for idx, nbrs in adjacency.items():
			if not nbrs:
				nxt[idx] = pts[idx]
				continue
			avg = (0.0, 0.0, 0.0)
			for n in nbrs:
				avg = v_add(avg, pts[n])
			avg = v_scale(avg, 1.0 / len(nbrs))
			nxt[idx] = v_add(v_scale(pts[idx], 1.0 - factor), v_scale(avg, factor))
		pts.update(nxt)
	return pts


def vertex_spike_distances(points: dict, adjacency: dict) -> dict:
	"""Pour chaque sommet (idx), distance (m) entre sa position et la moyenne
	DIRECTE de ses voisins (`adjacency`) -- une "pointe" (FP-10B) est un
	sommet dont cette distance depasse `CUFF_ENVELOPE_TOLERANCE_M` : c'est la
	definition operationnelle de "hors de l'enveloppe du gant" retenue ici
	(l'enveloppe = la moyenne locale de la coque elle-meme, jamais une
	reference externe -- purement locale, donc testable sans geometrie d'arme
	ni de manche). Un sommet sans voisin -> 0.0 (jamais indefini)."""
	out = {}
	for idx, nbrs in adjacency.items():
		if not nbrs:
			out[idx] = 0.0
			continue
		avg = (0.0, 0.0, 0.0)
		for n in nbrs:
			avg = v_add(avg, points[n])
		avg = v_scale(avg, 1.0 / len(nbrs))
		out[idx] = v_len(v_sub(points[idx], avg))
	return out


def spike_vertex_indices(points: dict, adjacency: dict, tolerance_m: float = CUFF_ENVELOPE_TOLERANCE_M) -> list:
	"""Indices (tries) des sommets "pointe" (`vertex_spike_distances` >
	`tolerance_m`) -- critere d'acceptation FP-10B : liste vide sur la coque
	du gant EXPORTEE (verifie cote bpy par `_verify_no_glove_spikes`, section 9)."""
	dists = vertex_spike_distances(points, adjacency)
	return sorted(idx for idx, d in dists.items() if d > tolerance_m)


# ---------------------------------------------------------------------------
# 6. Preregelages de doigts (angles par articulation, degres, meme ordre que
#    FINGER_SEGMENTS -- proximale/mediane/distale). Constantes deterministes
#    (doc 12 §3.2) ; l'auto-prise (§5) est un 6e mode CALCULE, pas dans cette
#    table. Reutilisees par les taches d'armes/animation (FP-11+).
# ---------------------------------------------------------------------------
FINGER_PRESETS = {
	"open": {"thumb": (0.0, 0.0, 0.0), "index": (0.0, 0.0, 0.0), "middle": (0.0, 0.0, 0.0),
		"ring": (0.0, 0.0, 0.0), "pinky": (0.0, 0.0, 0.0)},
	"flat": {"thumb": (5.0, 0.0, 0.0), "index": (5.0, 0.0, 0.0), "middle": (5.0, 0.0, 0.0),
		"ring": (5.0, 0.0, 0.0), "pinky": (5.0, 0.0, 0.0)},
	"grip": {"thumb": (40.0, 55.0, 50.0), "index": (60.0, 75.0, 70.0), "middle": (65.0, 80.0, 75.0),
		"ring": (65.0, 80.0, 75.0), "pinky": (60.0, 75.0, 70.0)},
	"trigger": {"thumb": (35.0, 50.0, 45.0), "index": (20.0, 25.0, 20.0), "middle": (60.0, 75.0, 70.0),
		"ring": (60.0, 75.0, 70.0), "pinky": (55.0, 70.0, 65.0)},
	"support": {"thumb": (30.0, 45.0, 40.0), "index": (50.0, 60.0, 55.0), "middle": (55.0, 65.0, 60.0),
		"ring": (55.0, 65.0, 60.0), "pinky": (50.0, 60.0, 55.0)},
	"pinch": {"thumb": (45.0, 70.0, 65.0), "index": (45.0, 70.0, 65.0), "middle": (10.0, 15.0, 10.0),
		"ring": (10.0, 15.0, 10.0), "pinky": (10.0, 15.0, 10.0)},
}
FINGER_PRESET_MAX_DEG = 95.0
assert all(0.0 <= a <= FINGER_PRESET_MAX_DEG for preset in FINGER_PRESETS.values()
	for angles in preset.values() for a in angles), "fp_rig: un prereglage de doigt depasse le plafond de 95 deg"


# ---------------------------------------------------------------------------
# 7. ΔE OKLab (Bjorn Ottosson) -- cuir fp_glove a ΔE_OK <= 0.08 de #6B4A2E
#    (doc 12 §3.2 / critere d'acceptation).
# ---------------------------------------------------------------------------

def hex_to_srgb01(hex_str: str) -> tuple:
	h = hex_str.lstrip("#")
	return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def _srgb_to_linear1(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def srgb_to_oklab(rgb) -> tuple:
	"""sRGB [0,1] (encode) -> OKLab (L, a, b). Formule de reference Bjorn
	Ottosson (https://bottosson.github.io/posts/oklab/), matrices M1/M2
	standard."""
	r, g, b = (_srgb_to_linear1(c) for c in rgb[:3])
	l_ = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
	m_ = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
	s_ = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
	l_, m_, s_ = l_ ** (1.0 / 3.0), m_ ** (1.0 / 3.0), s_ ** (1.0 / 3.0)
	return (
		0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
		1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
		0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
	)


def delta_e_ok(rgb_a, rgb_b) -> float:
	"""Distance euclidienne en OKLab entre deux couleurs sRGB [0,1] -- petite
	(< 0.1) pour deux couleurs perceptuellement proches, c'est la mesure
	"ΔE_OK" du contrat FP-10."""
	la, aa, ba = srgb_to_oklab(rgb_a)
	lb, ab, bb = srgb_to_oklab(rgb_b)
	return math.sqrt((la - lb) ** 2 + (aa - ab) ** 2 + (ba - bb) ** 2)


FP_GLOVE_HEX = "#6B4A2E"       # doc 12 §3.2 / docs/style/tokens.json color.character_shared.leather.
FP_SLEEVE_HEX = "#BFAE86"      # docs/style/tokens.json color.viewmodel.fp_arms.sleeve ("toile ecrue").
FP_GLOVE_DELTA_E_MAX = 0.08

# ---------------------------------------------------------------------------
# 8. Projection camera pure -- reprise de fp_camera.py (memes formules,
#    memes constantes) pour verifier que les coudes du solveur d'epaules
#    restent hors du cadre 16:9 (critere d'acceptation).
# ---------------------------------------------------------------------------
sys.path.insert(0, HERE)
import fp_camera  # noqa: E402 -- project_point/is_outside_frame (pures, pas de bpy requis pour ces fonctions).

is_outside_frame = fp_camera.is_outside_frame
project_point = fp_camera.project_point


# ---------------------------------------------------------------------------
# 9. Section bpy -- jamais appelee hors de Blender (voir garde d'import).
# ---------------------------------------------------------------------------
if bpy is not None:
	import make_characters as _mc  # noqa: E402 -- reutilise _build_shell/_face_dominant_bone (meme technique, doc 12).

	def probe_bpy_api() -> None:
		"""Sonde l'API bpy installee AVANT de l'utiliser (doc 12, risque §3) :
		echoue avec un message clair si `export_def_bones` (retire les
		controleurs IK non-deform du GLB exporte) n'existe pas sur cette
		build."""
		rna = bpy.ops.export_scene.gltf.get_rna_type()
		names = {p.identifier for p in rna.properties}
		if "export_def_bones" not in names:
			raise RuntimeError(
				"fp_rig: bpy.ops.export_scene.gltf n'expose pas 'export_def_bones' sur cette build "
				f"({bpy.app.version_string}) -- impossible d'exclure les controleurs IK du GLB exporte, "
				"le contrat FP-10 (os deform uniquement) ne peut pas etre tenu. Verifier la version de "
				"Blender (5.2 attendu) ou adapter ce script a l'API constatee.")
		print(f"FP_RIG_BPY_PROBE_OK {bpy.app.version_string} export_def_bones=ok")

	def reset_scene() -> None:
		for o in list(bpy.data.objects):
			bpy.data.objects.remove(o, do_unlink=True)
		for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.armatures, bpy.data.images, bpy.data.actions):
			for block in list(coll):
				if block.users == 0:
					coll.remove(block)

	def _import_ual(src_glb: str):
		"""Importe `src_glb` (UAL) : `Rig` (armature) + `Mannequin` (maillage).
		La source porte un objet "Icosphere" utilise comme FORME
		PERSONNALISEE d'affichage (`pose_bone.custom_shape`) de TOUS les os
		du rig (widget de viewport, sondage : verifie sur les 53 os) --
		`do_unlink=True` seul ne suffit PAS a couper ces references (constate
		par sondage : l'objet reapparaissait dans le GLB exporte malgre sa
		suppression de la scene, cf. rapport de tache) : on vide d'abord
		`custom_shape` sur chaque os AVANT de retirer l'objet."""
		bpy.ops.import_scene.gltf(filepath=src_glb)
		rig = bpy.data.objects["Rig"]
		mannequin = bpy.data.objects["Mannequin"]
		for pb in rig.pose.bones:
			if pb.custom_shape is not None:
				pb.custom_shape = None
		ico = bpy.data.objects.get("Icosphere")
		if ico is not None:
			bpy.data.objects.remove(ico, do_unlink=True)
		for mesh in [m for m in bpy.data.meshes if m.users == 0]:
			bpy.data.meshes.remove(mesh, do_unlink=True)
		bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
		return rig, mannequin

	def _add_fp_part_bones(rig) -> None:
		"""Ajoute les os de l'arme (deform, doc 12 §3.2) : `fp_root` pres de
		la main droite (poignee -- parent commun de `fp_weapon` et de ses
		pieces, jamais skinne a un maillage), `fp_weapon` (meme point,
		origine de l'arme), et les pieces mobiles `fp_mag`/`fp_slide`/
		`fp_bolt`/`fp_pump`/`fp_cylinder`/`fp_hammer`/`fp_prop` -- de simples
		os-reperes (2 cm), positionnes le long de `fp_weapon` : les taches
		d'armes (FP-11+) les repositionneront contre la geometrie reelle de
		chaque arme (ce fichier ne connait aucune arme)."""
		bpy.context.view_layer.objects.active = rig
		bpy.ops.object.mode_set(mode='EDIT')
		eb = rig.data.edit_bones
		hand_r = eb["DEF-hand.R"]
		grip_head = hand_r.head.copy()
		forward = Vector((0.0, 1.0, 0.0))

		root = eb.new(FP_ROOT_BONE)
		root.head = grip_head
		root.tail = grip_head + forward * 0.05
		root.use_deform = True
		root.use_connect = False

		weapon = eb.new("fp_weapon")
		weapon.head = grip_head
		weapon.tail = grip_head + forward * 0.15
		weapon.use_deform = True
		weapon.use_connect = False
		weapon.parent = root

		for i, name in enumerate(FP_PART_BONES[1:]):  # tout sauf fp_weapon (deja cree ci-dessus).
			offset = Vector((0.0, 0.02 + i * 0.02, 0.01 * (i % 2)))
			b = eb.new(name)
			b.head = grip_head + offset
			b.tail = grip_head + offset + forward * 0.02
			b.use_deform = True
			b.use_connect = False
			b.parent = weapon

		for side in ARM_SIDES:
			hand = eb[f"DEF-hand.{side}"]
			ik = eb.new(f"ik_hand.{side}")
			ik.head = hand.head.copy()
			ik.tail = hand.tail.copy()
			ik.roll = hand.roll
			ik.use_deform = False
			ik.use_connect = False

			forearm = eb[f"DEF-forearm.{side}"]
			outward = 1.0 if side == "L" else -1.0
			pole_pos = forearm.head + Vector((outward * 0.30, 0.05, -0.35))
			pole = eb.new(f"pole_elbow.{side}")
			pole.head = pole_pos
			pole.tail = pole_pos + Vector((0.0, 0.0, 0.03))
			pole.use_deform = False
			pole.use_connect = False

		bpy.ops.object.mode_set(mode='OBJECT')
		for side in ARM_SIDES:
			pb = rig.pose.bones[f"DEF-forearm.{side}"]
			con = pb.constraints.new('IK')
			con.target = rig
			con.subtarget = f"ik_hand.{side}"
			con.pole_target = rig
			con.pole_subtarget = f"pole_elbow.{side}"
			con.chain_count = 2
			con.use_rotation = True
			con.mute = True  # jamais utilisee par notre solveur (pb.matrix direct, voir
			# _pose_arm_chain/_bake_hold_pose_as_rest) -- coupee pour qu'elle n'interfere
			# JAMAIS avec le bake de pose ci-dessous (une contrainte IK active tirerait la
			# main vers ik_hand.<side>, jamais deplace, au lieu de la cible du contrat).
			# glTF n'exporte de toute facon aucune contrainte Blender (revue de tache) :
			# ces os/contraintes ne servent qu'a un artiste qui retoucherait a la main
			# dans Blender, jamais lus par ce pipeline ni par Godot.

	def _mark_only_contract_bones_deform(rig) -> None:
		"""Garde-fou : force `use_deform` exactement sur `DEFORM_BONE_NAMES`
		(True) et tout le reste (True) sauf les controleurs (False) -- au cas
		ou un os UAL non liste (ex. `DEF-hips`, `DEF-spine.*`, `root`) serait
		reste marque deform par defaut depuis l'import."""
		deform_set = set(DEFORM_BONE_NAMES)
		for bone in rig.data.bones:
			bone.use_deform = bone.name in deform_set

	def _hand_pivot(rig, side: str) -> Vector:
		return rig.data.bones[f"DEF-hand.{side}"].head_local.copy()

	def _scale_verts(verts, pivot: Vector, factor: float) -> None:
		for v in verts:
			v.co = pivot + (v.co - pivot) * factor

	def _face_ring_adjacency(faces) -> dict:
		"""idx (BMVert.index -- l'appelant DOIT avoir appele
		`bm.verts.index_update()` juste avant) -> set des idx voisins relies
		par une arete, restreint aux aretes INTERNES a `faces` (jamais un
		voisin hors de la coque du gant -- section 5b, `laplacian_relax_positions`/
		`spike_vertex_indices` consomment cette adjacence)."""
		adjacency = {}
		for f in faces:
			for v in f.verts:
				adjacency.setdefault(v.index, set())
			for e in f.edges:
				a, b = e.verts
				adjacency.setdefault(a.index, set()).add(b.index)
				adjacency.setdefault(b.index, set()).add(a.index)
		return adjacency

	def _glove_boundary_verts(faces) -> set:
		"""Sommets du bord OUVERT de la coque du gant -- `_build_shell` (voir
		son en-tete, make_characters.py) produit une piece totalement
		DECONNECTEE du reste du maillage (sommets dupliques, faces d'origine
		supprimees) : son SEUL bord ouvert, cote poignet (la main s'arrete la
		ou `HAND_BONES` s'arrete), est donc `edge.is_boundary` (exactement 1
		face liee) DANS cette piece -- c'est la "manchette" (ouverture) du
		gant, critere d'acceptation FP-10B ("aucun sommet de manchette a plus
		de 3 mm hors de l'enveloppe du gant")."""
		return {v for f in faces for e in f.edges if e.is_boundary for v in e.verts}

	def _refine_shell(bm, faces: list, material_index: int, subdiv_cuts: int, smooth_factor: float,
			smooth_iterations: int, reinflate_m: float) -> list:
		"""Corrige les "poings bosseles a pointes blanches" (revue lead
		2026-09-25, notes FP-10B -- voir section 5b pour la cause) : SUBDIVISE
		la coque (ajoute de la resolution la ou le maillage UAL DECIME n'en
		avait presque pas -- piste 1, "subdivision niveau 1-2 des mains avant
		bake"), RELAXE (Laplace, section 5b) chaque sommet vers la moyenne de
		ses voisins directs -- efface les normales de coque erratiques de
		`_build_shell` sur un maillage decime (LA cause des pointes) et LISSE
		LES POIDS DE PEAU du meme geste (bmesh interpole les data-layers, dont
		le calque de deformation, sur les sommets nouvellement crees par la
		subdivision -- piste 2, "lissage des poids") -- puis REGONFLE
		legerement le long des normales recalculees (arrondit/epaissit un peu
		-- piste 4, restaure aussi le volume perdu par le lissage). Ne touche
		PAS a HAND_SCALE pour le gant (le plafond ×1.15 de la bible, applique
		APRES par l'appelant, sur ce maillage deja rafine) ; la manche
		(material_index=0) n'a pas de HAND_SCALE. `subdiv_cuts=0` saute la
		subdivision (utilise pour la manche : garde son budget de tris,
		seul le lissage/regonflement compte pour elle -- le sceau visible
		dans `fp_arms_closeup.png`, revue lead 2026-09-25, n'etait pas QUE
		sur le gant). Renvoie la liste RAFINEE des faces, identifiees par
		`material_index` (les faces filles d'une subdivision HERITENT du
		`material_index` de leur face mere, sonde bpy standard : plus fiable
		qu'un suivi des cles exactes, non sondees pour ce fichier, du dict que
		renvoie `bmesh.ops.subdivide_edges`, variables selon la version de bpy).

		Suppose que l'appelant a deja ressoude le maillage SOURCE (voir
		`_build_arms_mesh`, `GLOVE_WELD_DIST_M`, AVANT tout `_build_shell`) --
		une coque construite a partir d'un maillage source non ressoude reste
		fragmentee (sondage sur le maillage reel : 28 % des sommets du gant
		sur un bord OUVERT, bien plus que la seule ouverture de poignet
		attendue -- voir rapport de tache) et ni la subdivision ni la
		relaxation ci-dessous ne peuvent recoller des morceaux deja distants
		de plusieurs centimetres (deux normales de sommet DIFFERENTES a une
		couture, chacune offsetee independamment par `_build_shell`)."""
		bm.normal_update()
		if subdiv_cuts > 0:
			edges = list({e for f in faces for e in f.edges})
			bmesh.ops.subdivide_edges(bm, edges=edges, cuts=subdiv_cuts, use_grid_fill=True)
		refined = [f for f in bm.faces if f.material_index == material_index]
		for f in refined:
			f.smooth = True

		bm.verts.index_update()
		verts = {v for f in refined for v in f.verts}
		adjacency = _face_ring_adjacency(refined)
		points = {v.index: tuple(v.co) for v in verts}
		points = laplacian_relax_positions(points, adjacency, factor=smooth_factor, iterations=smooth_iterations)
		by_index = {v.index: v for v in verts}
		for idx, pos in points.items():
			by_index[idx].co = Vector(pos)

		bm.normal_update()
		for v in verts:
			v.co += v.normal * reinflate_m
		bm.normal_update()
		return refined

	def _thicken_fingers(dl, index_to_name, verts, amount: float = FINGER_EXTRA_THICKEN_M) -> None:
		"""Pousse un peu plus loin, le long de LEUR normale (l'appelant vient
		de faire `bm.normal_update()`), les sommets dont l'os DOMINANT (poids
		max, meme regle que `_face_dominant_bone`) est une phalange
		(`DEF-f_*`/`DEF-thumb.*`) -- jamais la paume (`DEF-hand.*`) : "doigts
		un peu plus epais et arrondis (style cartoon)" (notes FP-10B), SANS
		toucher HAND_SCALE (le plafond ×1.15 de la bible, deja applique par
		l'appelant avant ce passage)."""
		for v in verts:
			weights = v[dl]
			if not weights:
				continue
			best_idx = max(weights.items(), key=lambda kv: kv[1])[0]
			name = index_to_name.get(best_idx, "")
			if name.startswith("DEF-f_") or name.startswith("DEF-thumb."):
				v.co += v.normal * amount

	def _fill_glove_holes(bm, verts) -> list:
		"""Bouche les MICRO-TROUS residuels du gant (`verts` : un sous-ensemble
		de `_glove_boundary_verts`, LOIN du poignet -- voir `_build_arms_mesh`,
		`WRIST_RING_RADIUS_M`) -- sondage sur le maillage reel (voir rapport de
		tache) : le ressoudage (`GLOVE_WELD_DIST_M`) + la relaxation
		n'eliminent pas TOUS les trous non-manifold d'un maillage UAL decime
		(quelques-uns survivent, epars, aux jointures de phalanges -- bien
		en-dessous de `CUFF_ENVELOPE_TOLERANCE_M`, donc invisibles au test de
		pointe, mais visibles comme de petites lucarnes sur le FOND blanc en
		gros plan). `bmesh.ops.holes_fill` les bouche avec des faces neuves
		(jamais la VRAIE manchette -- filtree par distance au pivot par
		l'appelant, jamais touchee ici)."""
		boundary_edges = list({e for v in verts for e in v.link_edges if e.is_boundary})
		if not boundary_edges:
			return []
		ret = bmesh.ops.holes_fill(bm, edges=boundary_edges)
		new_faces = ret.get("faces", [])
		for f in new_faces:
			f.material_index = 1
			f.smooth = True
		return new_faces

	def _extend_glove_cuff(bm, boundary_verts_this_side, direction: Vector, amount: float = GLOVE_CUFF_EXTEND_M) -> list:
		"""Etire la manchette du gant (son bord ouvert, cote poignet -- SEULEMENT
		les sommets de CE cote, `boundary_verts_this_side`) de `amount` metres
		vers le coude (`direction`, deja unitaire) : `_build_shell` construit
		la manche et le gant comme deux coques INDEPENDANTES, offsets
		differents (0.020 vs 0.015) sur des normales calculees a des MOMENTS
		differents du pipeline (le gant est duplique/offsete APRES que la
		manche a deja supprime ses faces d'origine, sondage -- voir rapport de
		tache) : leurs bords ouverts respectifs ne coincident donc JAMAIS
		exactement, ce qui laissait voir le FOND (blanc) a travers l'ecart en
		gros plan (revue lead 2026-09-25). Etendre simplement le bord du gant
		vers le coude le fait RECOUVRIR cet ecart (comme le revers d'un vrai
		gant par-dessus une manche) -- le bord ouvert AVANCE, il ne se ferme
		jamais (`_glove_boundary_verts` continue de trouver une manchette a
		l'export -- critere d'acceptation FP-10B). APPELE APRES
		`_verify_no_glove_spikes` (jamais avant, voir `_build_arms_mesh") :
		les aretes "laterales" du nouveau segment relient DELIBEREMENT
		l'ancien bord au nouveau, distants de `amount` -- une translation
		UNIFORME (jamais de nouvelle relaxation ici) qui ne cree AUCUNE
		irregularite DANS le nouveau bord lui-meme, mais que le detecteur de
		pointe generique (section 5b, qui compare aussi aux voisins
		STRUCTURELS hors-bord) confondrait a tort avec une pointe s'il tournait
		dessus."""
		boundary_edges = list({e for v in boundary_verts_this_side for e in v.link_edges if e.is_boundary})
		ret = bmesh.ops.extrude_edge_only(bm, edges=boundary_edges)
		new_verts = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMVert)]
		new_faces = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMFace)]
		for v in new_verts:
			v.co += direction * amount
		for f in new_faces:
			f.material_index = 1
			f.smooth = True
		return new_faces

	def _verify_no_glove_spikes(bm, glove_faces: list, tolerance_m: float = CUFF_ENVELOPE_TOLERANCE_M) -> None:
		"""Critere d'acceptation FP-10B : "aucune pointe (test : aucun sommet
		de manchette a plus de 3 mm hors de l'enveloppe du gant)" -- sur la
		coque du gant FINALE (apres `_refine_shell` + mise a l'echelle
		HAND_SCALE + `_thicken_fingers`), verifie qu'aucun sommet de la
		"manchette" (le bord ouvert du gant, cote poignet --
		`_glove_boundary_verts`, la zone la plus exposee aux pointes, notes
		FP-10B) ne s'ecarte de plus de `tolerance_m` de la moyenne de SES
		voisins directs (`spike_vertex_indices`, section 5b) -- leve une
		RuntimeError sinon (meme convention que le budget de tris, `build()`)."""
		bm.verts.index_update()
		boundary = _glove_boundary_verts(glove_faces)
		if not boundary:
			raise RuntimeError(
				"fp_rig: aucun bord de manchette trouve sur la coque du gant -- topologie inattendue "
				"(doc 12 notes FP-10B)")
		adjacency = _face_ring_adjacency(glove_faces)
		points = {v.index: tuple(v.co) for f in glove_faces for v in f.verts}
		dists = vertex_spike_distances(points, adjacency)
		boundary_idx = {v.index for v in boundary}
		worst_mm = max((dists[i] for i in boundary_idx), default=0.0) * 1000.0
		bad_boundary = sorted(i for i in boundary_idx if dists[i] > tolerance_m)
		if bad_boundary:
			raise RuntimeError(
				f"fp_rig: {len(bad_boundary)} sommet(s) de manchette percent l'enveloppe du gant de plus de "
				f"{tolerance_m * 1000:.1f} mm (pire ecart {worst_mm:.2f} mm) -- doc 12 notes FP-10B, revue lead "
				f"2026-09-25 -- indices {bad_boundary[:8]}")
		print(f"FP_RIG_CUFF_CHECK_OK {len(boundary)} sommets de manchette / {len(points)} sommets de gant, "
			f"pire ecart {worst_mm:.2f} mm (tolerance {tolerance_m * 1000:.1f} mm)")

	def _build_arms_mesh(rig, mannequin, arms_mode: str):
		"""Maillage avant-bras + mains + manche (technique `_build_shell` de
		make_characters.py, doc 12 §3.2) : 2 slots -- 0 "fp_sleeve" (manche,
		`_mc.FOREARM_ONLY_BONES`), 1 "fp_glove" (gant, `_mc.HAND_BONES`,
		RAFINE par `_refine_shell` -- subdivision + lissage de Laplace +
		regonflement, FP-10B, section 5b/9 -- puis mis a l'echelle HAND_SCALE
		autour du poignet de chaque cote, PUIS legerement epaissi sur les
		phalanges par `_thicken_fingers` -- seule la geometrie du gant
		grossit, ni les os ni l'avant-bras : le rig reste au gabarit UAL
		commun aux 6 agents, doc 12 §3.2). `_verify_no_glove_spikes` leve une
		RuntimeError si un sommet de manchette (bord ouvert du gant, cote
		poignet) perce l'enveloppe du gant de plus de 3 mm (critere
		d'acceptation FP-10B). `arms_mode='floating'` coupe ensuite l'avant-
		bras au-dela de FLOATING_CUFF_DIST_M du poignet et ajoute une
		manchette (doc 12 §3.2). Renvoie l'objet mesh fini (materiaux/bevel/
		armature deja poses, pas encore exporte)."""
		_mc._decimate(mannequin, FP_ARMS_DECIMATE_RATIO)
		group_index = {vg.name: vg.index for vg in mannequin.vertex_groups}
		bone_order = [vg.name for vg in mannequin.vertex_groups]
		index_to_name = {i: n for n, i in group_index.items()}

		bm = bmesh.new()
		bm.from_mesh(mannequin.data)
		# Ressoude les sommets dupliques par l'import glTF de ual.glb (normales
		# eclatees a chaque couture/angle de shading, sondage -- voir DIAG dans
		# le rapport de tache) AVANT toute duplication de coque : `_build_shell`
		# offset chaque sommet le long de SA PROPRE normale, et deux copies
		# coincidentes MAIS non ressoudees ont des normales differentes -- une
		# fois offsetees indépendamment, elles s'ecartent l'une de l'autre de
		# jusqu'a 2x l'offset de la coque (jusqu'a 3 cm), la VRAIE cause des
		# "pointes blanches" (notes FP-10B) -- ressouder ICI, sur le maillage
		# SOURCE (avant offset), les rend a nouveau coincidentes avec UNE SEULE
		# normale partagee, donc une coque continue une fois dupliquee.
		bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=GLOVE_WELD_DIST_M)
		dl = bm.verts.layers.deform.verify()
		for f in bm.faces:
			f.material_index = _mc.SKIN

		sleeve_faces = _mc._build_shell(bm, dl, index_to_name, _mc.FOREARM_ONLY_BONES, 0, 0.020)
		glove_faces = _mc._build_shell(bm, dl, index_to_name, _mc.HAND_BONES, 1, 0.015)
		glove_faces = _refine_shell(bm, glove_faces, material_index=1, subdiv_cuts=GLOVE_SUBDIV_CUTS,
			smooth_factor=GLOVE_SMOOTH_FACTOR, smooth_iterations=GLOVE_SMOOTH_ITERATIONS,
			reinflate_m=GLOVE_REINFLATE_M)
		# La manche (jamais mise a l'echelle HAND_SCALE) n'est PAS rafinee ici :
		# `FOREARM_ONLY_BONES` en fait un tube OUVERT AUX DEUX BOUTS (coude et
		# poignet) -- sondage sur le maillage reel (voir rapport de tache) : y
		# appliquer la MEME relaxation de Laplace (section 5b, pensee pour une
		# coque a UNE seule ouverture, le poignet du gant) tire ses DEUX bords
		# ouverts l'un vers l'autre le long de l'axe du tube et fait jaillir une
		# pointe qui traverse toute la manche -- pire que le probleme d'origine.
		# La manche garde donc sa geometrie `_build_shell` telle quelle (deja
		# ressoudee plus haut, `GLOVE_WELD_DIST_M`) ; le raccord manche/gant
		# reste couvert par `_extend_glove_cuff` (le gant deborde par-dessus).

		for side in ARM_SIDES:
			pivot = _hand_pivot(rig, side)
			sign = 1.0 if side == "L" else -1.0
			side_glove_verts = {v for f in glove_faces for v in f.verts if (v.co.x * sign) > 0.0}
			_scale_verts(list(side_glove_verts), pivot, HAND_SCALE)
			bm.normal_update()
			_thicken_fingers(dl, index_to_name, side_glove_verts)

		bm.normal_update()
		_verify_no_glove_spikes(bm, glove_faces)

		# Etend la manchette du gant vers le coude, APRES verification (l'extension
		# est une translation UNIFORME d'un bord deja valide -- section 5b/9 -- donc
		# ne PEUT PAS introduire de pointe de surface ; mais ses aretes "laterales",
		# structurelles, relient DELIBEREMENT deux points distants de
		# `GLOVE_CUFF_EXTEND_M`, ce que `_verify_no_glove_spikes` interpreterait a
		# tort comme une pointe si on l'appelait APRES -- voir _extend_glove_cuff).
		for side in ARM_SIDES:
			pivot = _hand_pivot(rig, side)
			side_boundary = {v for v in _glove_boundary_verts(glove_faces) if (v.co.x * (1.0 if side == "L" else -1.0)) > 0.0}
			near_wrist = {v for v in side_boundary if (v.co - pivot).length <= WRIST_RING_RADIUS_M}
			far_holes = side_boundary - near_wrist
			glove_faces = glove_faces + _fill_glove_holes(bm, far_holes)
			forearm_bone = rig.data.bones[f"DEF-forearm.{side}"]
			elbow_dir = (forearm_bone.head_local - forearm_bone.tail_local).normalized()
			glove_faces = glove_faces + _extend_glove_cuff(bm, near_wrist, elbow_dir)
			if arms_mode == "forearm":
				# La manche n'est jamais rafinee (voir plus haut) mais son propre bord
				# pres du poignet est LUI AUSSI etire vers la main (translation
				# UNIFORME d'une SEULE boucle, cote oppose au coude -- jamais une
				# relaxation plein-tube) : recouvre l'ecart DES DEUX COTES (revue
				# lead 2026-09-25). SEULEMENT en mode "forearm" : en mode
				# "floating", la manche est coupee courte puis fermee par sa PROPRE
				# manchette (`_add_cuff_ring`, plus bas) -- l'etirer ici la ferait
				# survivre partiellement au decoupage, un anneau parasite flottant
				# separe du moignon d'avant-bras (constate a l'image, voir rapport
				# de tache).
				sleeve_near_wrist = {v for v in _glove_boundary_verts(sleeve_faces)
					if (v.co.x * (1.0 if side == "L" else -1.0)) > 0.0 and (v.co - pivot).length <= WRIST_RING_RADIUS_M}
				sleeve_faces = sleeve_faces + _extend_glove_cuff(bm, sleeve_near_wrist, -elbow_dir, amount=GLOVE_CUFF_EXTEND_M)
		bm.normal_update()

		if arms_mode == "floating":
			# Un SEUL passage sur `sleeve_faces` (calcule les centres et decide
			# QUOI supprimer pour les deux cotes AVANT toute suppression) :
			# `bmesh.ops.delete` invalide les BMFace supprimees, et une
			# deuxieme boucle sur la MEME liste (cote par cote) plantait
			# (`ReferenceError: BMesh data ... has been removed`) des qu'elle
			# retombait sur une face deja supprimee par le premier cote.
			pivots = {side: _hand_pivot(rig, side) for side in ARM_SIDES}
			far_sleeve = []
			for f in sleeve_faces:
				center = sum((v.co for v in f.verts), Vector()) / len(f.verts)
				side = "L" if center.x > 0.0 else "R"
				if (center - pivots[side]).length > FLOATING_CUFF_DIST_M:
					far_sleeve.append(f)
			bmesh.ops.delete(bm, geom=far_sleeve, context='FACES')
			for side in ARM_SIDES:
				_add_cuff_ring(bm, dl, group_index, pivots[side], side)

		remaining_skin = [f for f in bm.faces if f.material_index == _mc.SKIN]
		bmesh.ops.delete(bm, geom=remaining_skin, context='FACES')

		me_new = bpy.data.meshes.new("fp_arms")
		bm.to_mesh(me_new)
		bm.free()

		obj = bpy.data.objects.new("FPArms", me_new)
		bpy.context.scene.collection.objects.link(obj)
		for name in bone_order:
			obj.vertex_groups.new(name=name)
		bpy.data.objects.remove(mannequin, do_unlink=True)

		obj.data.materials.append(_flat_image_material("fp_sleeve", FP_SLEEVE_HEX))
		obj.data.materials.append(_flat_image_material("fp_glove", FP_GLOVE_HEX))

		_finish_mesh(obj, rig)
		return obj

	def _add_cuff_ring(bm, dl, group_index, pivot: Vector, side: str) -> None:
		"""Manchette de FLOATING_CUFF_HEIGHT_M (1 cm) a FLOATING_CUFF_DIST_M
		(4 cm) du poignet (mode "floating", doc 12 §3.2), rigide (100% sur
		DEF-hand.<side>), slot "fp_sleeve" (0)."""
		sign = 1.0 if side == "L" else -1.0
		center = pivot + Vector((sign * FLOATING_CUFF_DIST_M, 0.0, 0.0))
		segs = bmesh.ops.create_cone(bm, cap_ends=False, cap_tris=False, segments=16,
			radius1=0.045, radius2=0.045, depth=FLOATING_CUFF_HEIGHT_M)
		verts = segs["verts"]
		bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90.0), 3, 'Y'), verts=verts)
		bmesh.ops.translate(bm, vec=center, verts=verts)
		gi = group_index[f"DEF-hand.{side}"]
		for v in verts:
			v[dl][gi] = 1.0
		for f in {f for v in verts for f in v.link_faces}:
			f.material_index = 0
			f.smooth = False

	def _flat_image_material(name: str, hex_color: str):
		"""Materiau avec une image UNIE (8x8) branchee sur Base Color -- pas
		une simple couleur BSDF plate : `paint_bake.py::_material_image_node`
		exige une IMAGE liee pour peindre en mode "existing" (base = cette
		couleur exacte, calibree en luminance, jamais un kind de palette
		devine -- voir `paint_slots`)."""
		size = 8
		rgb = hex_to_srgb01(hex_color)
		img = bpy.data.images.new(f"{name}_base", size, size, alpha=False)
		img.pixels[:] = (rgb[0], rgb[1], rgb[2], 1.0) * (size * size)  # `pixels` : toujours RGBA (4 floats/texel).
		mat = bpy.data.materials.new(name)
		mat.use_nodes = True
		nt = mat.node_tree
		bsdf = nt.nodes.get("Principled BSDF")
		tex = nt.nodes.new("ShaderNodeTexImage")
		tex.image = img
		nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
		return mat

	def _finish_mesh(obj, rig) -> None:
		"""Bevel LIMITE PAR VERTEX GROUP (jamais `limit_method='ANGLE'') :
		make_characters.py documente (voir son en-tete, mesure) qu'un bevel
		ANGLE chanfreine aussi les bords ouverts de `_build_shell` (chaque
		manche/gant EST un bord ouvert, detache du reste du maillage), ce qui
		fait exploser le budget de tris. Seules les faces marquees
		`smooth=False` (le gear rigide -- ici, uniquement l'anneau de
		manchette du mode "floating", cf. `_add_cuff_ring`) sont chanfreinees ;
		en mode "forearm" (tout `smooth=True`), le bevel ne touche rien."""
		bevel_vg = obj.vertex_groups.new(name="_bevel_targets")
		prop_vert_idx = {vi for p in obj.data.polygons if not p.use_smooth for vi in p.vertices}
		if prop_vert_idx:
			bevel_vg.add(list(prop_vert_idx), 1.0, 'REPLACE')
		mod = obj.modifiers.new("bevel", type='BEVEL')
		mod.width = _mc.BEVEL_WIDTH
		mod.segments = 2
		mod.limit_method = 'VGROUP'
		mod.vertex_group = bevel_vg.name
		mod.harden_normals = False
		with bpy.context.temp_override(object=obj):
			bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
			bpy.ops.object.modifier_apply(modifier=mod.name)
		obj.data.update()
		leftover_vg = obj.vertex_groups.get("_bevel_targets")
		if leftover_vg:
			obj.vertex_groups.remove(leftover_vg)

		# Triangulation EXPLICITE (deterministe, poids de vertex groups
		# preserves -- operateur standard) : le glTF ne connait QUE des
		# triangles, l'exporteur triangule sinon lui-meme silencieusement --
		# `_apply_painted_material`/`_measure_glove_delta_e` doivent pouvoir
		# mettre en correspondance, polygone par polygone, `obj.data` (cette
		# session) et sa version reimportee depuis un GLB peint : seule une
		# topologie DEJA tout-triangle avant l'export garantit que les deux
		# cotes s'alignent 1-a-1 (sondage, voir rapport de tache -- avec des
		# quads restants, l'ordre/nombre de polygones divergeait de la
		# reimportation, glissant le masque de mesure vers la manche).
		bpy.context.view_layer.objects.active = obj
		bpy.ops.object.mode_set(mode='EDIT')
		bpy.ops.mesh.select_all(action='SELECT')
		bpy.ops.mesh.quads_convert_to_tris(quad_method='BEAUTY', ngon_method='BEAUTY')
		bpy.ops.object.mode_set(mode='OBJECT')

		obj.parent = rig
		arm_mod = obj.modifiers.new("Armature", type='ARMATURE')
		arm_mod.object = rig

		obj.data.calc_loop_triangles()
		tris = len(obj.data.loop_triangles)
		print(f"FP_RIG_TRIS {tris} (budget {TRI_BUDGET_ARMS})")
		if tris > TRI_BUDGET_ARMS:
			raise RuntimeError(f"fp_rig: {tris} tris > budget {TRI_BUDGET_ARMS} (doc 12 §3.2)")

	def _export(rig, obj, out_path: str) -> str:
		"""`use_selection=True`, `rig`/`obj` seuls selectionnes -- la source
		UAL laisse un objet "Icosphere" orphelin (widget de forme
		personnalisee des os, purge par `_import_ual`) : filet de securite
		ici en plus (retire tout objet qui ne serait ni `obj` ni `rig`),
		au cas ou un autre widget orphelin apparaitrait un jour dans une
		source future."""
		os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
		for stray in [o for o in bpy.data.objects if o not in (obj, rig)]:
			bpy.data.objects.remove(stray, do_unlink=True)
		bpy.ops.object.select_all(action='DESELECT')
		obj.select_set(True)
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
			export_animations=False,
			export_skins=True,
			export_def_bones=True,   # retire les controleurs IK (non-deform) du GLB -- voir probe_bpy_api.
		)
		print(f"FP_RIG_EXPORT_OK -> {out_path}")
		return out_path

	def _export_mesh_only(obj, out_path: str) -> str:
		"""Exporte UNIQUEMENT `obj` (jamais `rig`) -- utilise pour la
		peinture (`paint_slots`) : `paint_bake.py` n'a besoin que du
		maillage/materiaux, jamais du squelette. Sondage (voir rapport de
		tache) : un GLB contenant une ARMATURE SKINNEE, une fois REIMPORTE
		par `bpy.ops.import_scene.gltf` (par n'importe quel outil bpy en
		aval -- paint_bake.py, turntable.py, cette meme fonction plus loin),
		gagne un objet "Icosphere" fantome (widget de forme personnalisee
		que L'IMPORTEUR Blender invente lui-meme pour afficher les os --
		confirme : ABSENT du JSON du GLB, verifie octet par octet, donc rien
		a "nettoyer" cote export -- c'est une pure convenance de viewport de
		l'IMPORTEUR, jamais serialisee dans le fichier ni recreee par
		l'IMPORTEUR de Godot). Un maillage SANS squelette n'en genere jamais
		(verifie) : la peinture (qui n'a besoin d'aucun os) passe donc par un
		GLB volontairement sans armature."""
		os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
		bpy.ops.object.select_all(action='DESELECT')
		obj.select_set(True)
		bpy.context.view_layer.objects.active = obj
		bpy.ops.export_scene.gltf(
			filepath=out_path,
			export_format='GLB',
			use_selection=True,
			export_apply=False,
			export_yup=True,
			export_materials='EXPORT',
			export_cameras=False,
			export_lights=False,
			export_animations=False,
			export_skins=False,
		)
		return out_path

	def paint_slots(in_path: str, out_path: str, res: int = 1024, samples: int = 16,
			skip_turntable: bool = True) -> dict:
		"""Peint fp_sleeve/fp_glove via `paint_bake.py` EN SOUS-PROCESS (CLI,
		lecture seule -- doc 12 §3.2). `in_path` porte deja des materiaux a
		image UNIE (`_flat_image_material`) : paint_bake les detecte en mode
		"existing" (`_material_image_node`) et peint AUTOUR de cette couleur
		exacte, jamais d'un "kind" de palette devine (aucune entree plate
		"leather"/"canvas" dans docs/style/tokens.json au niveau que lit
		`toonkit.palette()`, verifie par lecture -- voir rapport de tache).
		`in_path`/`out_path` sont tous deux des GLB MAILLAGE SEUL (voir
		`_export_mesh_only`) -- jamais le rig."""
		cmd = [
			BLENDER_BIN, "-b", "--factory-startup", "--python-exit-code", "1",
			"-P", PAINT_BAKE_SCRIPT, "--",
			"--in", in_path, "--out", out_path, "--res", str(res), "--samples", str(samples),
			"--hue-max-deg", "0",  # une seule ile par slot (gant/manche) : evite un decalage de teinte inutile.
		]
		if skip_turntable:
			cmd.append("--skip-turntable")
		proc = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
		if proc.returncode != 0:
			raise RuntimeError(
				f"fp_rig: paint_bake.py a echoue (code {proc.returncode})\n"
				f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}")
		print(proc.stdout)
		return {"stdout": proc.stdout, "sidecar": os.path.splitext(out_path)[0] + ".json"}

	def _match_polygons_by_centroid(dst_polygons, src_polygons, round_ndigits: int = 4) -> list:
		"""Indice `src_polygons` le plus proche de chaque polygone de
		`dst_polygons` (meme geometrie, ORDRE potentiellement different --
		voir `_apply_painted_material`) : appariement par centre arrondi
		(match direct, cas normal), puis par plus proche voisin parmi les
		polygones encore libres pour les rares cas de bruit flottant du
		roundtrip glTF. Necessite `len(dst_polygons) == len(src_polygons)`
		(verifie par l'appelant)."""
		from collections import defaultdict
		buckets = defaultdict(list)
		for j, p in enumerate(src_polygons):
			buckets[tuple(round(c, round_ndigits) for c in p.center)].append(j)
		mapping = [None] * len(dst_polygons)
		unmatched = []
		for i, p in enumerate(dst_polygons):
			bucket = buckets.get(tuple(round(c, round_ndigits) for c in p.center))
			if bucket:
				mapping[i] = bucket.pop(0)
			else:
				unmatched.append(i)
		if unmatched:
			remaining = [j for bucket in buckets.values() for j in bucket]
			for i in unmatched:
				best = min(remaining, key=lambda j: (src_polygons[j].center - dst_polygons[i].center).length)
				mapping[i] = best
				remaining.remove(best)
		return mapping

	def _apply_painted_material(obj, painted_mesh_glb_path: str):
		"""Reimporte `painted_mesh_glb_path` (maillage seul, sans armature --
		voir `_export_mesh_only` : jamais d'"Icosphere" fantome ici) dans la
		MEME session, recupere son materiau cuit (un seul, `paint_bake.py`
		fusionne tous les slots) et le pose sur `obj` A LA PLACE de ses
		materiaux provisoires (`fp_sleeve`/`fp_glove` a image unie) --
		l'objet temporaire importe est ensuite supprime. `obj` garde son
		armature/ses groupes de sommets d'origine intacts (seul le
		materiau change). Mesure et renvoie le ΔE_OK du gant (`_measure_glove_delta_e`,
		AVANT de reecrire les material_index -- voir plus bas)."""
		sys.path.insert(0, HERE)
		import paint_bake as _pb  # noqa: E402
		before = set(bpy.data.objects.keys())
		bpy.ops.import_scene.gltf(filepath=painted_mesh_glb_path)
		imported = [o for o in bpy.data.objects if o.name not in before and o.type == 'MESH']
		if not imported:
			raise RuntimeError(f"fp_rig: aucun maillage reimporte depuis {painted_mesh_glb_path}")
		painted_obj = imported[0]
		painted_mat = painted_obj.data.materials[0]
		image = _pb._material_image_node(painted_mat)
		if image is None:
			raise RuntimeError(f"fp_rig: le materiau peint de {painted_mesh_glb_path} n'a pas d'image liee")

		# `paint_bake.py` cuit sur une UV DEDIEE qu'il cree lui-meme
		# (Smart UV Project) sur SA PROPRE copie reimportee (`painted_obj`) --
		# `obj` (le notre, jamais reexporte/reimporte) n'a aucune UV
		# correspondant a cette image, et NE PEUT PAS etre copiee loop par
		# loop a l'identique (sondage, voir rapport de tache) : le GLB, en
		# EXPORTANT une primitive glTF PAR MATERIAU, fait qu'un REIMPORT
		# regroupe les polygones PAR SLOT (tous les "fp_sleeve" d'abord, puis
		# tous les "fp_glove") -- un ordre QUI NE CORRESPOND PAS a celui,
		# potentiellement entrelace, de `obj.data.polygons` (verifie : le
		# premier polygone de `obj` est un polygone de gant, celui du
		# reimport un polygone de manche, meme nombre total et memes 5
		# derniers centres identiques -- seul le DEBUT differe). On apparie
		# donc les polygones par CENTRE (meme geometrie, ordre indifferent),
		# puis chaque coin (loop) DANS la paire par position de sommet (une
		# face n'a que 3-4 sommets, jamais ambigu en pratique).
		src_uv = painted_obj.data.uv_layers.active
		if src_uv is None:
			raise RuntimeError(f"fp_rig: UV de cuisson introuvable sur {painted_mesh_glb_path}")
		if len(painted_obj.data.polygons) != len(obj.data.polygons):
			raise RuntimeError(
				f"fp_rig: topologie changee par paint_bake.py ({len(obj.data.polygons)} -> "
				f"{len(painted_obj.data.polygons)} polygones) -- mesure/texturage impossibles")
		poly_map = _match_polygons_by_centroid(obj.data.polygons, painted_obj.data.polygons)

		# `_export_mesh_only(obj, ...)` (plus haut dans `build()`) a laisse sur
		# `obj.data` deux UV "UVMap"/"UVMap.001" FANTOMES, VIDES (uv=(0,0)
		# partout) -- une par materiau provisoire de `_build_arms_mesh`
		# (fp_sleeve/fp_glove, aucun des deux n'a jamais eu de vraie UV) :
		# l'exporteur glTF, pour satisfaire les DEUX materiaux "Base Color =
		# image" sans coordonnee de texture sur le maillage, ecrit un
		# TEXCOORD_0 de repli PAR PRIMITIVE ET LE PERSISTE sur `obj.data`
		# (mesure, voir rapport de tache -- pas un simple detail transitoire
		# de l'export). Si on cree "fp_baked_uv" PAR-DESSUS sans les retirer,
		# elle atterrit en INDEX 2 (0=UVMap, 1=UVMap.001, 2=fp_baked_uv) :
		# `uv_layers.active` la designe bien comme "active" cote Blender, mais
		# l'aller-retour export/import glTF ignore ce marqueur et relie le
		# materiau au TEXCOORD_0 = INDEX 0 = "UVMap" (vide) -- le maillage
		# peint reimporte echantillonne alors la marge NOIRE de l'image
		# (0,0,0) sur TOUTE sa surface (revue lead 2026-09-25 : "aucune
		# texture visible ... noire", mesure -- luminance nulle au rendu,
		# alors que `_measure_glove_delta_e` ci-dessous, qui lit l'UV EN
		# MEMOIRE dans CETTE session avant tout aller-retour, la mesurait
		# juste). On retire les UV existantes avant de creer "fp_baked_uv" :
		# elle devient l'UNIQUE UV (index 0 = TEXCOORD_0), plus aucune
		# ambiguite possible cote exporteur/importeur.
		for stray_uv in list(obj.data.uv_layers):
			obj.data.uv_layers.remove(stray_uv)
		dst_uv = obj.data.uv_layers.new(name="fp_baked_uv")
		obj.data.uv_layers.active = dst_uv
		for i, dst_poly in enumerate(obj.data.polygons):
			src_poly = painted_obj.data.polygons[poly_map[i]]
			src_by_vertex = {}
			for li in src_poly.loop_indices:
				vi = painted_obj.data.loops[li].vertex_index
				key = tuple(round(c, 4) for c in painted_obj.data.vertices[vi].co)
				src_by_vertex[key] = li
			for li in dst_poly.loop_indices:
				vi = obj.data.loops[li].vertex_index
				key = tuple(round(c, 4) for c in obj.data.vertices[vi].co)
				src_li = src_by_vertex.get(key)
				if src_li is None:
					# repli (bruit flottant du roundtrip) : sommet le plus proche DANS cette face.
					dst_co = obj.data.vertices[vi].co
					src_li = min(src_poly.loop_indices,
						key=lambda l: (painted_obj.data.vertices[painted_obj.data.loops[l].vertex_index].co - dst_co).length)
				dst_uv.data[li].uv = src_uv.data[src_li].uv

		# Mesure AVANT de reecrire les material_index de `obj` sur le slot
		# unique 0 (ci-dessous) : le masque par slot ("fp_glove" = 1) n'a de
		# sens que tant que l'assignation d'origine (0=sleeve/1=glove,
		# `_build_arms_mesh`) est encore en place.
		delta_e = _measure_glove_delta_e(obj, image)

		obj.data.materials.clear()
		obj.data.materials.append(painted_mat)
		for poly in obj.data.polygons:
			poly.material_index = 0

		painted_mesh_data = painted_obj.data
		bpy.data.objects.remove(painted_obj, do_unlink=True)
		if painted_mesh_data.users == 0:
			bpy.data.meshes.remove(painted_mesh_data)
		return delta_e

	def _measure_glove_delta_e(obj, image) -> float:
		"""Mesure la couleur MOYENNE (sRGB) du slot "fp_glove" (index 1
		avant peinture, cf. `_build_arms_mesh` -- `_apply_painted_material`
		remet tous les polygones sur le slot 0 APRES cette mesure, jamais
		avant) dans `image` (reutilise les fonctions numpy pures de
		paint_bake.py -- lecture seule), et renvoie `delta_e_ok(mesure,
		FP_GLOVE_HEX)`. Doit etre appelee AVANT `_apply_painted_material`
		n'a de sens que sur les material_index encore d'ORIGINE (0/1) --
		voir l'ordre d'appel dans `build()`."""
		sys.path.insert(0, HERE)
		import paint_bake as _pb  # noqa: E402
		rgb = _pb._read_rgb(image)
		masks = _pb._uv_slot_masks(obj, image.size[0])
		mask = masks.get(1)  # slot 1 = fp_glove (voir _build_arms_mesh).
		if mask is None or not mask.any():
			raise RuntimeError("fp_rig: slot fp_glove (index 1) introuvable sur le maillage peint")
		avg = tuple(float(rgb[:, :, c][mask].mean()) for c in range(3))
		target = hex_to_srgb01(FP_GLOVE_HEX)
		print(f"FP_RIG_GLOVE_AVG_RGB {avg[0]:.4f},{avg[1]:.4f},{avg[2]:.4f} target={target[0]:.4f},{target[1]:.4f},{target[2]:.4f}")
		return delta_e_ok(avg, target)

	# -- reutilise par fp_camera.py (planche de controle "tenue") -----------

	def import_fp_arms(glb_path: str):
		"""Reimporte un fp_arms*.glb DEJA EXPORTE (rig + maillage skinne) --
		contient donc, cote VIEWPORT BLENDER seulement, l'objet "Icosphere"
		fantome documente par `_export_mesh_only` (jamais serialise dans le
		fichier, jamais recree par l'importeur de Godot) : exclu par nom ici,
		pas par type, pour ne jamais le confondre avec `FPArms`."""
		reset_scene()
		bpy.ops.import_scene.gltf(filepath=glb_path)
		rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
		arms = next(o for o in bpy.context.scene.objects if o.type == 'MESH' and o.name != "Icosphere")
		return rig, arms

	def _pose_arm_chain(rig, side: str, shoulder_eff, elbow, hand) -> None:
		"""Pose DEF-upper_arm.<side>/DEF-forearm.<side> pour que la chaine
		passe par `shoulder_eff` -> `elbow` -> `hand` (espace armature
		Blender). Meme technique que `make_characters._pose_fp_hold` --
		`pose_bone.matrix` pose directement la matrice ARMATURE (absolue)
		du bone, Blender en deduit lui-meme `rotation_quaternion`/`location`
		locaux (voir le commentaire detaille de `_pose_fp_hold`, non
		reproduit ici) : plus simple et plus sur qu'une composition manuelle
		de quaternions locaux. `bpy.context.view_layer.update()` entre les
		deux os pour que le second lise le PREMIER deja repose (sa propre
		matrice locale se calcule a partir de la pose EVALUEE du parent)."""
		bpy.context.view_layer.objects.active = rig
		bpy.ops.object.mode_set(mode='POSE')
		for bone_name, head, tail in (
			(f"DEF-upper_arm.{side}", shoulder_eff, elbow),
			(f"DEF-forearm.{side}", elbow, hand),
		):
			pb = rig.pose.bones[bone_name]
			rest_bone = rig.data.bones[bone_name]
			rest_dir = (rest_bone.tail_local - rest_bone.head_local).normalized()
			new_dir = (tail - head).normalized()
			delta = rest_dir.rotation_difference(new_dir).to_matrix()
			rest_rot = rest_bone.matrix_local.to_3x3()
			new_matrix = (delta @ rest_rot).to_4x4()
			new_matrix.translation = head
			pb.matrix = new_matrix
			bpy.context.view_layer.update()
		bpy.ops.object.mode_set(mode='OBJECT')

	def _apply_finger_angles(rig, side: str, finger: str, angles_deg) -> None:
		axis = Vector((0.0, 0.0, 1.0)) if side == "L" else Vector((0.0, 0.0, -1.0))
		names = [f"DEF-f_{finger}.{seg}.{side}" for seg in FINGER_SEGMENTS] if finger != "thumb" else \
			[f"DEF-thumb.{seg}.{side}" for seg in FINGER_SEGMENTS]
		for name, angle in zip(names, angles_deg):
			pb = rig.pose.bones.get(name)
			if pb is None:
				continue
			pb.rotation_mode = 'XYZ'
			pb.rotation_euler = (0.0, 0.0, 0.0)
			pb.rotation_mode = 'AXIS_ANGLE'
			pb.rotation_axis_angle = (math.radians(angle), axis.x, axis.y, axis.z)

	def pose_hold_cylinder(rig, cylinder_radius: float = DEFAULT_GRIP_CYLINDER_RADIUS_M) -> None:
		"""Pose le rig importe (bras + doigts) tenant le cylindre de
		reference, avec EXACTEMENT les solveurs purs valides par le contrat
		pytest (`shoulder_solve`/`auto_grip_cylinder`) -- ce qu'on voit dans
		la planche de controle (`fp_camera.render_hold_checkpoint`) est donc
		calcule par le meme code que le test, jamais une pose approximee a
		part (doc 12 §3.1 : "ce qu'on voit dans Blender est ce qu'on aura en
		jeu")."""
		grip = auto_grip_cylinder(cylinder_radius)
		for side in ARM_SIDES:
			target = TARGET_CAM[side]
			pole = tuple(a + b for a, b in zip(SHOULDER_REST_CAM[side], POLE_OFFSET_CAM[side]))
			solved = shoulder_solve(SHOULDER_REST_CAM[side], target, pole)
			shoulder_b = Vector(fp_camera.godot_to_blender(solved["shoulder"]))
			elbow_b = Vector(fp_camera.godot_to_blender(solved["elbow"]))
			hand_b = Vector(fp_camera.godot_to_blender(solved["hand"]))
			_pose_arm_chain(rig, side, shoulder_b, elbow_b, hand_b)
			for finger, result in grip.items():
				_apply_finger_angles(rig, side, finger, result["angles_deg"])
		bpy.context.view_layer.update()

	def _bake_hold_pose_as_rest(rig, obj, cylinder_radius: float = DEFAULT_GRIP_CYLINDER_RADIUS_M) -> None:
		"""Pose le rig (bras + doigts) en tenue de reference -- EXACTEMENT
		`pose_hold_cylinder`, memes solveurs que le contrat pytest -- puis
		FIGE cette pose dans le GLB EXPORTE : le contrat exige que le GLB
		exporte ait "une bbox de bras coherente avec la pose de tenue (mains a
		~40-70 cm devant la camera, ecart des mains <= 45 cm, pas de T-pose)"
		(revue lead 2026-09-25 -- prioritaire sur le §3.2 du doc 12, qui
		prevoyait une livraison FP-10 en pose de repos neutre).

		Sondage bpy (voir rapport de tache) : `bpy.ops.pose.armature_apply`
		SEUL ne suffit PAS -- il fige la pose au niveau des matrices de repos
		des OS, mais laisse `obj.data` (les sommets bruts du maillage) tel
		quel (T-pose UAL). Or `_export` passe `export_apply=False` (jamais de
		bake des modificateurs a l'export, voir sa docstring) : le GLB exporte
		emet donc les sommets BRUTS (T-pose) + un skin dont les inverseBind-
		matrices s'alignent TOUJOURS exactement sur le repos courant des os
		(par construction du format skin) -- au repos (aucune animation), le
		resultat skinne redonne donc PRECISEMENT les sommets bruts, quelle que
		soit la pose de repos des os : mesure sur un export reel (voir rapport
		de tache), la bbox du maillage reimporte restait ~2 m (T-pose) meme
		apres `armature_apply` seul.

		Correctif : on BAKE la deformation courante (Armature modifier evalue,
		"tenue" du cylindre) DANS les sommets bruts (copie evaluee du
		depsgraph, `bpy.data.meshes.new_from_object`) AVANT de figer la pose
		de repos des os -- desormais, `obj.data` contient directement la forme
		"tenue" (mains repliees, coude plie), et `armature_apply` (ensuite)
		remet la pose courante des os a zero SANS reintroduire de deformation
		(elle a deja ete cuite dans les sommets) : au repos, le maillage
		exporte est donc bien la pose de tenue, comme mesure/verifie sur cette
		meme technique dans `_build_toon_preview`/pipeline de peinture
		(`_apply_painted_material`, meme depot). Les groupes de vertex (poids
		de peau) et les materiaux sont preserves par `new_from_object` (meme
		topologie, memes UV/material_index -- seules les POSITIONS bougent) :
		le maillage reste anime-able normalement par FP-13+ (skin intact,
		juste une nouvelle "forme de repos").

		Les os `fp_root`/`fp_weapon`/pieces (aucun maillage skinne dessus dans
		ce fichier) restent a leur position d'origine (pres de l'ancienne main
		T-pose) : non repositionnes ici, une arme reelle n'existe pas encore
		(FP-11+ les repositionnera contre sa propre geometrie, voir
		_add_fp_part_bones) -- sans incidence sur la bbox du maillage (ce sont
		des os, jamais skinnes a aucun sommet)."""
		pose_hold_cylinder(rig, cylinder_radius=cylinder_radius)
		bpy.context.view_layer.update()

		depsgraph = bpy.context.evaluated_depsgraph_get()
		obj_eval = obj.evaluated_get(depsgraph)
		baked_mesh = bpy.data.meshes.new_from_object(obj_eval, preserve_all_data_layers=True, depsgraph=depsgraph)
		old_mesh = obj.data
		old_name = old_mesh.name
		obj.data = baked_mesh
		bpy.data.meshes.remove(old_mesh)
		baked_mesh.name = old_name  # libere par le remove ci-dessus -- evite le suffixe ".001".
		obj.data.calc_loop_triangles()

		bpy.context.view_layer.objects.active = rig
		bpy.ops.object.mode_set(mode='POSE')
		bpy.ops.pose.select_all(action='SELECT')
		bpy.ops.pose.armature_apply(selected=False)
		bpy.ops.object.mode_set(mode='OBJECT')
		bpy.context.view_layer.update()

	# -- pipeline complet + CLI ----------------------------------------------

	def build(out_path: str = DEFAULT_OUT_GLB, arms_mode: str = "forearm", src_glb: str = DEFAULT_SRC_GLB,
			paint: bool = True, paint_res: int = 1024, paint_samples: int = 16) -> dict:
		if arms_mode not in ("forearm", "floating"):
			raise ValueError(f"fp_rig: --arms-mode invalide: {arms_mode!r} (forearm|floating)")
		if not os.path.isfile(src_glb):
			raise RuntimeError(
				f"fp_rig: source UAL introuvable: {src_glb} -- attendu dans assets/incoming/quaternius/ "
				"(doc 12 §3.2, copiee une fois par la tache FP-10 depuis le scratchpad qui l'a telechargee)")
		probe_bpy_api()
		reset_scene()
		rig, mannequin = _import_ual(src_glb)
		_add_fp_part_bones(rig)
		_mark_only_contract_bones_deform(rig)
		obj = _build_arms_mesh(rig, mannequin, arms_mode)

		exported_bones = sorted(b.name for b in rig.data.bones if b.use_deform)
		if exported_bones != DEFORM_BONE_NAMES:
			missing = sorted(set(DEFORM_BONE_NAMES) - set(exported_bones))
			extra = sorted(set(exported_bones) - set(DEFORM_BONE_NAMES))
			raise RuntimeError(f"fp_rig: contrat d'os deform viole -- manquants={missing} en_trop={extra}")

		_bake_hold_pose_as_rest(rig, obj)

		n_verts = len(obj.data.vertices)
		n_tris = len(obj.data.loop_triangles)

		if paint:
			unpainted_path = os.path.splitext(out_path)[0] + "._unpainted_mesh.glb"
			painted_mesh_path = os.path.splitext(out_path)[0] + "._painted_mesh.glb"
			_export_mesh_only(obj, unpainted_path)
			paint_slots(unpainted_path, painted_mesh_path, res=paint_res, samples=paint_samples)
			delta_e = _apply_painted_material(obj, painted_mesh_path)
			for tmp in (unpainted_path, painted_mesh_path):
				if os.path.isfile(tmp):
					os.remove(tmp)
				tmp_json = os.path.splitext(tmp)[0] + ".json"
				if os.path.isfile(tmp_json):
					os.remove(tmp_json)
			_export(rig, obj, out_path)
		else:
			_export(rig, obj, out_path)
			delta_e = None

		print("FP_RIG_BONES " + ",".join(exported_bones))
		print(f"FP_RIG_VERTS {n_verts}")
		print(f"FP_RIG_HAND_SCALE {HAND_SCALE}")
		if delta_e is not None:
			print(f"FP_RIG_GLOVE_DELTA_E {delta_e:.5f}")
		print(f"FP_RIG_OK {out_path}")
		return {
			"bones": exported_bones, "verts": n_verts, "tris": n_tris,
			"hand_scale": HAND_SCALE, "glove_delta_e": delta_e, "out_path": out_path,
		}

	def parse_args(argv=None):
		p = argparse.ArgumentParser(description="FP-10 -- rig de bras FP (voir docs/research/12_viewmodel_v2.md).")
		p.add_argument("--out", dest="out_path", default=DEFAULT_OUT_GLB)
		p.add_argument("--arms-mode", dest="arms_mode", choices=("forearm", "floating"), default="forearm")
		p.add_argument("--src", dest="src_glb", default=DEFAULT_SRC_GLB)
		p.add_argument("--skip-paint", dest="skip_paint", action="store_true",
			help="saute la peinture paint_bake.py (iteration rapide -- jamais pour une livraison)")
		p.add_argument("--paint-res", dest="paint_res", type=int, default=1024)
		p.add_argument("--paint-samples", dest="paint_samples", type=int, default=16)
		return p.parse_args(argv)

	def main(argv=None) -> None:
		args = parse_args(argv)
		build(
			out_path=os.path.abspath(args.out_path), arms_mode=args.arms_mode,
			src_glb=os.path.abspath(args.src_glb), paint=not args.skip_paint,
			paint_res=args.paint_res, paint_samples=args.paint_samples,
		)

	if __name__ == "__main__":
		argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
		main(argv)
elif __name__ == "__main__":  # pragma: no cover
	raise SystemExit(
		"fp_rig.py doit etre lance depuis Blender (bpy introuvable) : "
		"blender -b -P tools/blender/fp_rig.py -- --out assets/models/fp/fp_arms.glb")
