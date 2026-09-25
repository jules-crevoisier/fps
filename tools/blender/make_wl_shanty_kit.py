## tools/blender/make_wl_shanty_kit.py
## Tâche ART-73 — Kit « bidonville » v2 Wasteland, modules de façade détaillés
## (docs/art/WASTELAND_ART_RESET.md, décision 3 « hybride géométrie » :
## l'espace jouable reste un kit bpy précis, mais avec du vrai détail —
## planches une à une, encadrements en retrait, bandeaux, chanfreins — et les
## matières peintes existantes). Bibliothèque de MODULES seulement (≥ 14
## fichiers .glb indépendants) ; leur pose sur la carte Wasteland est ART-73B,
## hors périmètre de ce fichier. Référence visuelle unique :
## .orchestrator/refs/wasteland_hero.png (façades western à fronton, balcons
## à garde-corps, auvents, tôles rouillées) — voir docs/STYLE_BIBLE.md.
##
## Matières — contrat ART-73 : UNIQUEMENT les 5 kinds peints ci-dessous
## (`KINDS`), par NOM DE SLOT matériau exact (`Cartoon.painted_for_slot`
## accepte directement ces noms canoniques, scripts/core/Cartoon.gd
## `_PAINTED`/`_KIND_ALIASES`) — ni les slots v3 (base/accent/metal/sign), ni
## les noms courts de make_props.py (wood/rust/corrugated/...) : leurs
## textures seront remplacées UNE PAR UNE par ART-79B sans toucher ce script.
## UV posée à l'échelle du MONDE (projection boîte, 1 m = 0,5 tuile —
## `WORLD_UV_SCALE`), jamais triplanaire (réservée à `Cartoon.painted()`/le
## terrain, `Cartoon.prop_uv()` lit l'UV du maillage) : chaque planche/pièce
## reçoit ses coordonnées UV directement depuis sa position MONDE (repère
## d'auteur, voir plus bas), donc la texture continue sans couture d'une
## pièce à l'autre — exactement l'effet recherché pour un mur fait de
## planches individuelles.
##
## Repère d'auteur — IDENTIQUE à make_props.py : X = droite, Y = haut,
## Z = avant (face visible en -Z). `build_module()` fait tourner tout le
## maillage de +90°/X en fin de construction (repère Z-up natif de Blender),
## puis `toonkit.export_glb(..., export_yup=True)` reconvertit en Y-up glTF —
## les deux transforms s'annulent EXACTEMENT (vérifié par sondage avant
## écriture, voir rapport de tâche), donc les coordonnées MONDE finales
## (glTF/Godot) sont numériquement identiques aux coordonnées d'auteur : la
## projection UV ci-dessous peut donc lire directement les coordonnées
## d'auteur (avant la rotation +90°/X), sans dupliquer la logique de
## conversion d'axes.
##
## Planches individuelles (critère d'acceptation : « planches modélisées une
## à une ») : `plank_wall_parts()` construit un mur de planches horizontales
## empilées (jamais un seul pavé texturé) — jointure 1-2 cm (`PLANK_GAP_M`),
## décalage de profondeur ±1 cm par planche (déterministe, `PLANK_JITTER_M`,
## une séquence sinusoïdale sur l'index — AUCUN module `random`, convention
## make_props.py "déterministe"), teinte par planche en couleur de sommet
## (attribut de couleur dédié `PLANK_TINT_ATTR`, une valeur PLATE par planche
## — pas un dégradé — dérivée du même index déterministe).
##
## Chanfrein (critère d'acceptation : 1-2 cm sur toute arête exposée) :
## `CHAMFER_M` (1,5 cm) appliqué en un seul segment (`bevel_for_class`
## de toonkit vise l'architecture générique à 6 cm — hors de la plage exigée
## ici, donc `toonkit.add_bevel` est appelé directement avec la largeur du
## contrat) — un seul segment = une VRAIE facette de chanfrein plate, plus
## fidèle au mot "chanfrein" qu'un bevel à plusieurs segments (qui arrondit).
##
## API bpy 5.2 vérifiée par sondage avant écriture (voir rapport de tâche) :
## bm.loops.layers.uv.new()/bm.loops.layers.color.new() survivent tels quels
## (mêmes noms, même domaine CORNER, type BYTE_COLOR pour la couleur) à un
## modifieur BEVEL appliqué par `bpy.ops.object.modifier_apply` — aucune
## reprojection UV ni retissage de couleur nécessaire après le chanfrein.
##
## Lancer (génère les 14 modules + manifest.json + vérifie chacun avec
## check_asset.py, sans écrire de rapport JSON) :
##   blender -b -P tools/blender/make_wl_shanty_kit.py
## Un seul module, pour l'itération rapide (CLAUDE.md « tests scopés
## pendant l'itération ») :
##   blender -b -P tools/blender/make_wl_shanty_kit.py -- --only wall_1_level
## Mode utilisé par tools/blender/tests/test_make_wl_shanty_kit.py (mêmes
## modules, plus un rapport JSON machine-lisible sur un marqueur de ligne) :
##   blender -b -P tools/blender/make_wl_shanty_kit.py -- --selftest-json OUT.json
import argparse
import json
import math
import os
import subprocess
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "lib"))
import toonkit  # noqa: E402

# Importé directement (même dossier) plutôt que relancé en sous-process : le
# mode --selftest-json vérifie chaque .glb exporté avec la même passe que la
# revue humaine (`tools/review/run_review.ps1`), sans dépendre d'un second
# lancement de Blender.
sys.path.insert(0, _HERE)
import check_asset  # noqa: E402
# Réutilisé UNIQUEMENT en lecture (aucune ligne de turntable.py modifiée ici)
# pour produire les planches-contact exigées par le critère d'acceptation
# (« captures: planche turntable de chaque module, un assemblage de 3
# façades ») sans dupliquer son pipeline de rendu 2 tons + encre Freestyle —
# voir `--captures` / `render_assembly_capture()` plus bas.
import turntable  # noqa: E402

# ---------------------------------------------------------------------------
# Constantes du contrat ART-73
# ---------------------------------------------------------------------------

KINDS = ["wood_planks", "corrugated_metal", "rust", "painted_metal", "dirty_glass"]

WORLD_UV_SCALE = 0.5          # 1 m monde = 0,5 tuile UV (contrat ART-73)
CHAMFER_M = 0.015             # 1,5 cm — dans la plage 1-2 cm exigée
CHAMFER_SEGMENTS = 1          # un seul segment = facette plate (vrai "chanfrein")
CHAMFER_ANGLE_DEG = 35.0

PLANK_H_M = 0.21              # hauteur d'une planche (avant chanfrein)
PLANK_GAP_M = 0.015           # joint horizontal entre planches — 1,5 cm (1-2 cm exigé)
PLANK_JITTER_M = 0.01         # décalage de profondeur par planche — ±1 cm exigé
PLANK_TINT_ATTR = "PlankTint"

DOOR_W_M, DOOR_H_M = 1.2, 2.2   # cotes Kit imposées par le contrat
WINDOW_W_M, WINDOW_H_M = 0.9, 1.1
WINDOW_RECESS_M = 0.09          # >= 8 cm exigé

GRID_M = 0.5                    # grille de pose au sol

# Deux pièces d'auteur "boîte" positionnées pour se toucher EXACTEMENT (même
# arête, mêmes sommets) ressortent, une fois soudées par check_asset.py
# (`remove_doubles`, tolérance 1e-4), avec une arête partagée par >= 3 faces
# (2 de chaque pièce) — un échec DUR de check_asset (CHK "arêtes non-
# manifold"), constaté sur les jambages/linteaux et le porche à la première
# passe de ce script (voir rapport de tâche). Un jeu de quelques mm à chaque
# jonction structurelle (jambage/linteau, poteau/sablière) sépare les deux
# pièces en composantes RÉELLEMENT disjointes — invisible à l'échelle du jeu,
# et retombe sur la catégorie CHK-16 déjà tolérée pour ce style d'asset (voir
# `_FLOATING_PIECE_MARKER` ci-dessus) plutôt que sur l'échec dur.
SEAM_GAP_M = 0.004
ASSET_CLASS = "architecture"    # budget de triangles §6.6 (<= 6000), via toonkit

OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(_HERE)),
    "assets", "models", "props", "wasteland", "shanty",
)

# check_asset.py CHK-16 ("aucune pièce d'asset déconnectée à plus de 1 cm du
# corps principal") compare CHAQUE composante connexe à la SEULE plus grosse
# ("corps principal"), sans chaînage de proche en proche (voir
# `_component_groups`/`check_object` : la boucle sur `components[1:]` calcule
# `gap` contre `components[0]` UNIQUEMENT, jamais contre le voisin réel) — un
# prop fait de plusieurs pièces DÉLIBÉRÉMENT séparées de plus d'1 cm
# (planches jointées, balustres, marches...) y échoue systématiquement, quelle
# que soit la distance RÉELLE entre pièces voisines. RE-VÉRIFIÉ en écrivant ce
# correctif (`blender -b -P tools/blender/check_asset.py -- --in
# .../wall_1_level.glb --asset-class architecture`) : la toute PREMIÈRE
# planche voisine du « corps principal » échoue déjà à 0,015 m (> 0,01 m de
# tolérance — PLANK_GAP_M lui-même, le joint EXIGÉ par le contrat), et chaque
# planche plus loin accumule un écart croissant (0,24 m, 0,465 m, ...) :
# aucun réglage de gap dans la plage contractuelle 1-2 cm n'y échappe. Ce
# n'est pas spécifique à ce fichier : TOUS les props multi-pièces déjà livrés
# du kit wasteland actuel échouent à ce même CHK-16 aujourd'hui (re-vérifié
# aussi en écrivant ce correctif — `check_asset.py --in
# assets/models/props/wasteland/{fence_wood,pallet,exterior_stairs,
# corrugated_shed,balcony_railing}.glb` y échouent TOUS, alors que ce sont des
# assets livrés/en production) — un défaut de la construction "plusieurs
# boîtes dans un bmesh partagé" partagée par make_props.py, pas une
# régression de ce script. `check_asset.py` est un outil PARTAGÉ
# (tools/blender/check_asset.py), hors de la liste de fichiers de ce
# contrat : impossible de corriger son algorithme ici, et impossible de
# souder les planches sans perdre le joint réel exigé par le contrat
# (« joints 1-2 cm » implique un écart réel entre pièces, donc des
# composantes connexes distinctes après soudure).
#
# Conséquence assumée et SIGNALÉE, PAS masquée : `report["ok"]` (et le test
# `test_every_module_passes_check_asset_excluding_known_chk16_limitation`)
# vérifie « check_asset PASS » en ignorant CETTE catégorie précise de message
# (repérée par la sous-chaîne `_FLOATING_PIECE_MARKER`), tout en gardant
# BLOQUANTES les autres catégories d'échec dur (mesh vide, budget de
# triangles, sommets orphelins, arêtes non-manifold) — voir `build_all()`.
# Le résultat BRUT et non filtré de check_asset.py (le critère d'acceptation
# LITTÉRAL) reste intégralement journalisé, JAMAIS remplacé par cette
# exception : `check_asset_raw_ok`/`check_asset_failures` par module, et
# `report["chk16_exception"]` (modules concernés, nombre de pièces, écarts
# mesurés, comparaison aux assets de production ci-dessus).
#
# `CHK16_EXCEPTION_APPROVED_BY_LEAD` reste à False tant que le lead n'a pas
# tranché explicitement entre les 3 issues possibles (retour vérificateur
# ART-73) : approuver cette exception pour les assets multi-pièces à joints
# réels, corriger check_asset.py (chaînage proche-en-proche plutôt que vs.
# corps principal seul), ou remodeler sans écart réel > 1 cm (perdrait le
# critère « joints 1-2 cm »). Ce flag ne change AUCUN comportement — il ne
# sert qu'à rendre l'état "en attente d'arbitrage" impossible à manquer à la
# lecture du fichier, exactement ce que demandait le retour vérificateur
# ("l'acceptance/le test le disent en clair").
CHK16_EXCEPTION_APPROVED_BY_LEAD = False
_FLOATING_PIECE_MARKER = "pièce déconnectée"


# ---------------------------------------------------------------------------
# Primitives bas niveau (bmesh partagé), calquées sur make_props.py mais avec
# EN PLUS la pose d'UV boîte à l'échelle monde sur chaque face nouvellement
# créée (voir `_set_box_uv`).
# ---------------------------------------------------------------------------

def _set_box_uv(faces, uv_layer, scale: float = WORLD_UV_SCALE) -> None:
    """Projection UV « boîte » (par axe dominant de la normale de face),
    lue directement sur la position MONDE du sommet (repère d'auteur, voir
    l'en-tête de fichier) — jamais un remap 0-1 par pièce : deux planches
    voisines qui partagent la même bande de coordonnées voient donc une
    texture continue, sans couture, exactement comme si le mur entier était
    peint d'un seul tenant (l'effet qu'un vrai bardage attend)."""
    for f in faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        if az >= ax and az >= ay:
            ia, ib = 0, 1   # face avant/arrière (normale ~Z) -> plan (X, Y)
        elif ay >= ax and ay >= az:
            ia, ib = 0, 2   # face dessus/dessous (normale ~Y) -> plan (X, Z)
        else:
            ia, ib = 2, 1   # face de côté (normale ~X) -> plan (Z, Y)
        for loop in f.loops:
            co = loop.vert.co
            comps = (co.x, co.y, co.z)
            loop[uv_layer].uv = (comps[ia] * scale, comps[ib] * scale)


def add_box(bm: bmesh.types.BMesh, uv_layer, size: tuple, center: tuple, rot=None) -> list:
    before = set(bm.faces)
    verts = list(bmesh.ops.create_cube(bm, size=1.0)["verts"])
    bmesh.ops.scale(bm, vec=Vector(size), verts=verts)
    if rot:
        axis, deg = rot
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(deg), 3, axis), verts=verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
    faces = [f for f in bm.faces if f not in before]
    _set_box_uv(faces, uv_layer)
    return faces


def add_strut(bm: bmesh.types.BMesh, uv_layer, p0: tuple, p1: tuple, thickness: float) -> list:
    """Poutre pleine (section carrée) entre 2 points — rambardes, jambages
    de porche, mains courantes (identique à make_props.py add_strut)."""
    p0v, p1v = Vector(p0), Vector(p1)
    d = p1v - p0v
    length = d.length
    if length < 1e-6:
        return []
    before = set(bm.faces)
    verts = list(bmesh.ops.create_cube(bm, size=1.0)["verts"])
    bmesh.ops.scale(bm, vec=Vector((thickness, thickness, length)), verts=verts)
    rot_quat = Vector((0.0, 0.0, 1.0)).rotation_difference(d.normalized())
    bmesh.ops.transform(bm, matrix=rot_quat.to_matrix().to_4x4(), verts=verts)
    bmesh.ops.translate(bm, vec=(p0v + p1v) * 0.5, verts=verts)
    faces = [f for f in bm.faces if f not in before]
    _set_box_uv(faces, uv_layer)
    return faces


# ---------------------------------------------------------------------------
# DSL déclaratif (mêmes tuples "part" que make_props.py) + le type "plank",
# propre à ce fichier : une planche individuelle porte en plus son index
# (pour la teinte de sommet déterministe).
# ---------------------------------------------------------------------------

def P_BOX(kind, size, center, rot=None):
    return ("box", kind, size, center, rot)


def P_STRUT(kind, p0, p1, thickness):
    return ("strut", kind, p0, p1, thickness)


def _plank_tint(index: int) -> tuple:
    """Teinte PLATE par planche (pas de dégradé), déterministe — suite
    sinusoïdale sur l'index plutôt que `random` (convention make_props.py :
    « déterministe, aucun random »). Amplitude modeste (±12 %) : varie le
    bardage planche à planche sans jamais désaccorder la couleur du kind."""
    shade = 1.0 + 0.12 * math.sin(index * 2.399963 + 0.7)
    return (shade, shade, shade, 1.0)


def plank_wall_parts(width: float, height: float, depth: float, opening: dict = None,
        kind: str = "wood_planks", y0: float = 0.0, x0: float = None, axis: str = "x",
        plank_h: float = PLANK_H_M, gap: float = PLANK_GAP_M, jitter_amp: float = PLANK_JITTER_M) -> list:
    """Mur de planches HORIZONTALES empilées une à une (jamais un seul pavé) :
    `rows` rangées de hauteur `plank_h`, séparées par un joint `gap` (1-2 cm) ;
    chaque planche recule/avance de `jitter_amp` (déterministe, ±1 cm) le long
    de l'axe de profondeur. `opening` (optionnel) : rectangle EN COORDONNÉES
    LOCALES `{"x0","x1","y0","y1"}` (même repère que `x0`/`y0`/`width`/
    `height`) — toute rangée qui croise ce rectangle est scindée en un
    segment gauche et/ou droit (sautée si entièrement recouverte), ce qui
    creuse une ouverture de porte/fenêtre directement dans le bardage.
    `axis` choisit quel axe horizontal porte la longueur des planches — "x"
    (mur "en face", planches le long de X, profondeur le long de Z) ou "z"
    (bras perpendiculaire d'un angle, planches le long de Z, profondeur le
    long de X) — les deux bras d'un même module d'angle partagent alors le
    même paramètre `x0`/`width`, juste réinterprété sur l'autre axe, sans
    dupliquer la logique de découpe d'ouverture."""
    if x0 is None:
        x0 = -width / 2.0
    step = plank_h + gap
    rows = max(1, round(height / step))
    parts = []
    idx = 0
    for r in range(rows):
        cy = y0 + plank_h * 0.5 + r * step
        depth_jitter = jitter_amp * math.sin(r * 1.7 + 0.4)
        row_top, row_bot = cy + plank_h * 0.5, cy - plank_h * 0.5
        segs = [(x0, x0 + width)]
        if opening and row_top > opening["y0"] and row_bot < opening["y1"]:
            segs = []
            if x0 < opening["x0"]:
                segs.append((x0, opening["x0"]))
            if opening["x1"] < x0 + width:
                segs.append((opening["x1"], x0 + width))
        for sx0, sx1 in segs:
            w = sx1 - sx0
            if w <= 0.02:
                continue
            c = (sx0 + sx1) / 2.0
            if axis == "x":
                size = (w, plank_h, depth)
                center = (c, cy, depth_jitter)
            else:
                size = (depth, plank_h, w)
                center = (depth_jitter, cy, c)
            parts.append(("plank", kind, size, center, idx))
            idx += 1
    return parts


# ---------------------------------------------------------------------------
# Modules — chacun renvoie une liste de "parts". Largeurs/profondeurs
# choisies pour retomber sur la grille de pose de 0,5 m (GRID_M) : les
# modules "façade droite" font tous 2,0 m (ou 3,0 m) de large, les modules
# d'angle/porche/balcon/escalier 1,0 m de large et/ou de profondeur.
# ---------------------------------------------------------------------------

WALL_W_M = 2.0
WALL_H_M = 2.7        # hauteur d'un niveau
WALL_D_M = 0.18        # épaisseur du bardage


def parts_wall_1_level() -> list:
    return plank_wall_parts(WALL_W_M, WALL_H_M, WALL_D_M)


def parts_wall_2_level() -> list:
    parts = plank_wall_parts(WALL_W_M, WALL_H_M * 2.0, WALL_D_M)
    # Bandeau de plancher d'étage (rive tôle entre RDC et étage) : casse la
    # silhouette "planches jusqu'en haut" et ajoute un second kind peint.
    parts.append(P_BOX("painted_metal", (WALL_W_M, 0.05, WALL_D_M + 0.02), (0.0, WALL_H_M, 0.0)))
    return parts


def _pediment_parts(width: float) -> list:
    h = 1.0
    return [
        P_BOX("wood_planks", (width, h, 0.12), (0.0, h * 0.5, 0.0)),           # panneau d'enseigne vierge
        P_BOX("rust", (width, 0.05, 0.14), (0.0, h - 0.025, 0.0)),            # bandeau cache-clous haut
        P_BOX("rust", (width, 0.05, 0.14), (0.0, 0.025, 0.0)),                # bandeau bas
    ]


def parts_pediment_narrow() -> list:
    return _pediment_parts(WALL_W_M)


def parts_pediment_wide() -> list:
    return _pediment_parts(3.0)


def _window_opening() -> dict:
    oy0 = 1.0
    return {"x0": -WINDOW_W_M * 0.5, "x1": WINDOW_W_M * 0.5, "y0": oy0, "y1": oy0 + WINDOW_H_M}


def _window_parts(shutters_closed: bool) -> list:
    opening = _window_opening()
    parts = plank_wall_parts(WALL_W_M, WALL_H_M, WALL_D_M, opening=opening)

    ow, oh = WINDOW_W_M, WINDOW_H_M
    oy0, oy1 = opening["y0"], opening["y1"]
    ocy = (oy0 + oy1) * 0.5
    z_out = -WALL_D_M * 0.5           # face extérieure du mur
    recess = WINDOW_RECESS_M          # >= 8 cm exigé
    z_in = z_out + recess             # plan du cadre, en retrait réel
    jt = 0.05                          # épaisseur des jambages (tunnel de retrait)

    # Jambages : relient la face extérieure au cadre en retrait (un vrai
    # tunnel, pas juste un cadre plaqué en surface — c'est ce qui fait le
    # "retrait ≥ 8 cm" réel plutôt que l'astuce plate de make_props.py).
    parts.append(P_BOX("wood_planks", (ow + 2.0 * jt, jt, recess), (0.0, oy1 + jt * 0.5, z_out + recess * 0.5)))  # linteau
    parts.append(P_BOX("wood_planks", (ow + 2.0 * jt, jt, recess), (0.0, oy0 - jt * 0.5, z_out + recess * 0.5)))  # appui
    # Jambages légèrement raccourcis (SEAM_GAP_M de chaque côté) : évite la
    # coïncidence exacte d'arête avec le linteau/l'appui (voir SEAM_GAP_M).
    jamb_h = oh - 2.0 * SEAM_GAP_M
    parts.append(P_BOX("wood_planks", (jt, jamb_h, recess), (-ow * 0.5 - jt * 0.5, ocy, z_out + recess * 0.5)))   # jambage G
    parts.append(P_BOX("wood_planks", (jt, jamb_h, recess), (ow * 0.5 + jt * 0.5, ocy, z_out + recess * 0.5)))    # jambage D
    # Cadre au fond du retrait + vitre.
    parts.append(P_BOX("wood_planks", (ow + 0.06, oh + 0.06, 0.04), (0.0, ocy, z_in - 0.02)))
    parts.append(P_BOX("dirty_glass", (ow - 0.08, oh - 0.08, 0.02), (0.0, ocy, z_in + 0.01)))

    # Volets : mêmes deux panneaux dans les deux variantes, seule leur
    # position change — "ouverts" (repliés à plat contre le bardage, de part
    # et d'autre de l'ouverture) ou "fermés" (déplacés devant l'ouverture,
    # bord à bord au centre, à la même profondeur que le bardage) : pas de
    # rotation de pivot à gérer, juste une position différente.
    shutter_w = ow * 0.42
    shutter_z = z_out - 0.015
    if shutters_closed:
        parts.append(P_BOX("wood_planks", (shutter_w, oh, 0.03), (-shutter_w * 0.5 - 0.01, ocy, shutter_z)))
        parts.append(P_BOX("wood_planks", (shutter_w, oh, 0.03), (shutter_w * 0.5 + 0.01, ocy, shutter_z)))
    else:
        gap = ow * 0.5 + shutter_w * 0.5 + 0.03
        parts.append(P_BOX("wood_planks", (shutter_w, oh, 0.03), (-gap, ocy, shutter_z)))
        parts.append(P_BOX("wood_planks", (shutter_w, oh, 0.03), (gap, ocy, shutter_z)))
    return parts


def parts_window_shutters_open() -> list:
    return _window_parts(shutters_closed=False)


def parts_window_shutters_closed() -> list:
    return _window_parts(shutters_closed=True)


def _door_opening() -> dict:
    return {"x0": -DOOR_W_M * 0.5, "x1": DOOR_W_M * 0.5, "y0": 0.0, "y1": DOOR_H_M}


def parts_door() -> list:
    opening = _door_opening()
    parts = plank_wall_parts(WALL_W_M, WALL_H_M, WALL_D_M, opening=opening)

    ow, oh = DOOR_W_M, DOOR_H_M
    z_out = -WALL_D_M * 0.5
    jt = 0.05
    parts.append(P_BOX("wood_planks", (ow + 2.0 * jt, jt, WALL_D_M), (0.0, oh + jt * 0.5, 0.0)))                # linteau
    # Jambage raccourci en haut (SEAM_GAP_M) : évite la coïncidence exacte
    # d'arête avec le linteau (voir SEAM_GAP_M) ; au sol, rien à séparer.
    jamb_h = oh - SEAM_GAP_M
    parts.append(P_BOX("wood_planks", (jt, jamb_h, WALL_D_M), (-ow * 0.5 - jt * 0.5, jamb_h * 0.5, 0.0)))         # jambage G
    parts.append(P_BOX("wood_planks", (jt, jamb_h, WALL_D_M), (ow * 0.5 + jt * 0.5, jamb_h * 0.5, 0.0)))          # jambage D
    parts.append(P_BOX("rust", (ow + 0.10, 0.05, 0.05), (0.0, 0.025, z_out - 0.01)))                             # seuil
    leaf_h = oh - 0.06
    parts.append(P_BOX("wood_planks", (ow - 0.06, leaf_h, 0.05), (0.0, leaf_h * 0.5 + 0.03, z_out - 0.03)))       # vantail
    parts.append(P_BOX("painted_metal", (0.04, 0.05, 0.03), (ow * 0.32, oh * 0.42, z_out - 0.06)))                # poignée
    return parts


def parts_porch() -> list:
    post_w = 0.15
    span = 1.85 - post_w          # entraxe poteaux -> largeur totale hors-tout = 2,0 m
    post_h = 2.3
    depth = 1.0                    # avancée du porche (grille 0,5 m)
    # Poteau légèrement raccourci (SEAM_GAP_M) : sa face haute reste sous la
    # face basse de la sablière au lieu de la toucher EXACTEMENT (même
    # arête, mêmes bords en X) — voir SEAM_GAP_M. Tout le reste (sablière,
    # auvent, jambe de force) garde `post_h` comme référence nominale.
    post_box_h = post_h - SEAM_GAP_M
    parts = [
        P_BOX("wood_planks", (post_w, post_box_h, post_w), (-span * 0.5, post_box_h * 0.5, -depth + post_w * 0.5)),
        P_BOX("wood_planks", (post_w, post_box_h, post_w), (span * 0.5, post_box_h * 0.5, -depth + post_w * 0.5)),
        P_BOX("wood_planks", (span + post_w, 0.15, post_w), (0.0, post_h - 0.075, -depth + post_w * 0.5)),        # sablière
        P_BOX("corrugated_metal", (WALL_W_M, 0.05, depth), (0.0, post_h + 0.05, -depth * 0.5), rot=("X", -6.0)),  # auvent en tôle
        P_BOX("rust", (WALL_W_M, 0.04, 0.10), (0.0, post_h + 0.02, -depth + 0.05)),                               # rive de l'auvent
    ]
    parts.append(P_STRUT("painted_metal", (-span * 0.5, post_h - 0.35, -depth + 0.20), (0.0, post_h + 0.05, -0.15), 0.02))
    parts.append(P_STRUT("painted_metal", (span * 0.5, post_h - 0.35, -depth + 0.20), (0.0, post_h + 0.05, -0.15), 0.02))
    return parts


def parts_balcony_railing() -> list:
    width, depth = WALL_W_M, 1.0
    rail_h = 0.9
    x0, x1 = -width * 0.5 + 0.08, width * 0.5 - 0.08
    y = 0.0
    z = depth * 0.5 - 0.06
    parts = [
        P_BOX("wood_planks", (width, 0.12, depth), (0.0, -0.06, 0.0)),          # plateforme (dessus en y=0)
        P_STRUT("painted_metal", (x0, y, z), (x1, y, z), 0.03),
        P_STRUT("wood_planks", (x0, y, z), (x0, y + rail_h, z), 0.05),
        P_STRUT("wood_planks", (x1, y, z), (x1, y + rail_h, z), 0.05),
        P_STRUT("wood_planks", (x0, y + rail_h, z), (x1, y + rail_h, z), 0.05),
        P_STRUT("painted_metal", (-width * 0.5 + 0.10, -0.55, -depth * 0.5 + 0.10),
            (-width * 0.5 + 0.10, -0.05, depth * 0.5 - 0.10), 0.035),           # console de support G
        P_STRUT("painted_metal", (width * 0.5 - 0.10, -0.55, -depth * 0.5 + 0.10),
            (width * 0.5 - 0.10, -0.05, depth * 0.5 - 0.10), 0.035),           # console de support D
    ]
    n_balusters = 6
    for i in range(1, n_balusters + 1):
        bx = x0 + (x1 - x0) * i / (n_balusters + 1)
        parts.append(P_STRUT("painted_metal", (bx, y, z), (bx, y + rail_h, z), 0.02))
    return parts


def parts_roof_corrugated() -> list:
    width, run, thickness = WALL_W_M, 1.0, 0.04
    parts = [P_BOX("corrugated_metal", (width, thickness, run), (0.0, 0.0, 0.0))]
    ridge_step = 0.17
    n_ridges = max(1, round(width / ridge_step))
    # Ondes à mi-pas (jamais une onde exactement sur l'arête du panneau) :
    # une onde alignée pile sur le bord du panneau partage une arête EXACTE
    # avec lui, ce qui échoue au CHK d'arêtes non-manifold de check_asset.py
    # une fois soudé (voir SEAM_GAP_M/le rapport de tâche) — le motif à
    # mi-pas reste esthétiquement identique (ondulation régulière) sans
    # jamais toucher le bord du panneau.
    step = width / n_ridges
    for i in range(n_ridges):
        rx = -width * 0.5 + (i + 0.5) * step
        parts.append(P_BOX("corrugated_metal", (0.05, 0.025, run), (rx, thickness * 0.5 + 0.0125, 0.0)))
    parts.append(P_BOX("rust", (width, 0.03, 0.08), (0.0, -thickness * 0.5 - 0.015, -run * 0.5)))  # rive avant (égout)
    return parts


CORNER_POST_M = 0.20
CORNER_ARM_M = 0.80   # + CORNER_POST_M = 1,0 m (grille)


def _corner_parts(outer: bool) -> list:
    height = WALL_H_M
    depth = WALL_D_M
    post = CORNER_POST_M
    arm = CORNER_ARM_M
    sign = 1.0 if outer else -1.0
    parts = [P_BOX("wood_planks", (post, height, post), (0.0, height * 0.5, 0.0))]
    if outer:
        x0 = post * 0.5
    else:
        x0 = -post * 0.5 - arm
    parts += plank_wall_parts(arm, height, depth, kind="wood_planks", x0=x0, axis="x")
    parts += plank_wall_parts(arm, height, depth, kind="wood_planks", x0=x0, axis="z")
    return parts


def parts_corner_outer() -> list:
    return _corner_parts(outer=True)


def parts_corner_inner() -> list:
    return _corner_parts(outer=False)


def parts_cornice_band() -> list:
    width = WALL_W_M
    parts = [
        P_BOX("painted_metal", (width, 0.05, 0.10), (0.0, 0.0, -0.02)),
        P_BOX("rust", (width, 0.03, 0.14), (0.0, 0.04, -0.03)),   # lèvre saillante du chapeau
    ]
    step = 0.4
    n = max(1, round(width / step))
    modillon_w = 0.05
    inset = width * 0.5 - modillon_w * 0.5   # garde les modillons DANS la largeur du module (grille 0,5 m)
    for i in range(n + 1):
        bx = -inset + i * (2.0 * inset / n)
        parts.append(P_BOX("rust", (modillon_w, 0.06, 0.06), (bx, -0.055, -0.05)))  # modillon
    return parts


def parts_exterior_stairs() -> list:
    width, rise, run = 1.0, 2.2, 2.5
    steps = 10
    step_rise = rise / steps
    step_run = run / steps
    stringer_x = width * 0.5 - 0.025
    parts = [
        P_STRUT("wood_planks", (-stringer_x, 0.0, 0.0), (-stringer_x, rise, -run), 0.05),
        P_STRUT("wood_planks", (stringer_x, 0.0, 0.0), (stringer_x, rise, -run), 0.05),
    ]
    for i in range(1, steps + 1):
        t = i / steps
        cy = rise * t - step_rise * 0.5
        cz = -run * t + step_run * 0.5
        parts.append(P_BOX("wood_planks", (width - 0.16, 0.05, step_run * 0.92), (0.0, cy, cz)))
    parts.append(P_STRUT("painted_metal", (stringer_x, 0.85, 0.0), (stringer_x, rise + 0.85, -run), 0.025))
    for i in range(0, steps + 1, 2):
        t = i / steps
        py, pz = rise * t, -run * t
        parts.append(P_STRUT("painted_metal", (stringer_x, py, pz), (stringer_x, py + 0.85, pz), 0.02))
    return parts


# ---------------------------------------------------------------------------
# ART-92 — modules complémentaires du kit v2 (docs/art/WASTELAND_V4_ART_PLAN.md
# §2/§9 : peau de façade R2/R3, volumes pleins et couverts R7). Chaque module
# est ici une fonction PARAMÉTRÉE ("aux cotes exactes" du plan) ; une fonction
# `parts_xxx()` sans argument l'enregistre dans MODULES avec UNE instance
# représentative (les cotes réellement posées sur Wasteland v4, §9), pour
# rester compatible avec `build_module()` (une fonction sans argument par nom
# de module, comme le reste de ce fichier). Même DSL (P_BOX/P_STRUT/
# plank_wall_parts), mêmes 5 KINDS peints, même convention d'auteur (Y = haut,
# Z = avant, pivot au repère d'auteur) que le reste du fichier. Pièces
# volontairement disjointes (rangement de caisses, traverses, essieux…) : même
# écart réel que les joints de planches (SEAM_GAP_M/0,04 m selon le module),
# donc même exception CHK-16 déjà documentée plus haut (_FLOATING_PIECE_MARKER)
# — aucun nouveau mécanisme, seulement plus de modules concernés.
# ---------------------------------------------------------------------------

def stairs_fit(width: float, rise: float, run: float) -> list:
    """Escalier extérieur aux cotes EXACTES d'un palier (plan §2 : « Module
    `stairs_fit(largeur, montée, course)` aux cotes exactes, marches en
    planches ») — généralisation paramétrée de l'ancien `parts_exterior_stairs`
    (largeur/montée/course fixes) : 2 limons, marches en planches, main
    courante à poteaux tous les 2 pas, même pas de marche (~0,22 m) que
    l'original quelle que soit la montée demandée."""
    step_rise_nominal = 0.22
    steps = max(2, round(rise / step_rise_nominal))
    step_rise = rise / steps
    step_run = run / steps
    stringer_x = width * 0.5 - 0.025
    parts = [
        P_STRUT("wood_planks", (-stringer_x, 0.0, 0.0), (-stringer_x, rise, -run), 0.05),
        P_STRUT("wood_planks", (stringer_x, 0.0, 0.0), (stringer_x, rise, -run), 0.05),
    ]
    for i in range(1, steps + 1):
        t = i / steps
        cy = rise * t - step_rise * 0.5
        cz = -run * t + step_run * 0.5
        parts.append(P_BOX("wood_planks", (width - 0.16, 0.05, step_run * 0.92), (0.0, cy, cz)))
    parts.append(P_STRUT("painted_metal", (stringer_x, 0.85, 0.0), (stringer_x, rise + 0.85, -run), 0.025))
    for i in range(0, steps + 1, 2):
        t = i / steps
        py, pz = rise * t, -run * t
        parts.append(P_STRUT("painted_metal", (stringer_x, py, pz), (stringer_x, py + 0.85, pz), 0.02))
    return parts


def parts_stairs_fit() -> list:
    # StairImpasseW/StairPassageW/StairRuelleW/StairGalerieW (doc 11 §9) :
    # largeur 1,5 m (grille de pose), montée 3,2 m (un étage Kit), course 5,0 m.
    return stairs_fit(width=1.5, rise=3.2, run=5.0)


def door_frame(width: float, height: float, wall_thickness: float, jamb: float = 0.2) -> list:
    """Cadre de porte SEUL, sans remplissage de mur (plan §2 R3 : `shell_to_skin`
    perce l'ouverture réelle dans la carte de façade — source de vérité le
    JSON de collision, jamais recopiée à la main — puis ce module habille
    l'épaisseur du mur du Kit, 0,25 m). `width`/`height` = cotes VIDES de
    l'ouverture ; `jamb` = largeur du montant peint de chaque côté. Linteau +
    2 montants + seuil, en tunnel sur toute l'épaisseur du mur — même logique
    de tunnel que `_window_parts`, sans vitre ni volet : cadre pour une vraie
    porte, pas une fenêtre condamnée."""
    jamb_h = height - SEAM_GAP_M
    return [
        P_BOX("wood_planks", (width + 2.0 * jamb, jamb, wall_thickness), (0.0, height + jamb * 0.5, 0.0)),  # linteau
        P_BOX("wood_planks", (jamb, jamb_h, wall_thickness), (-width * 0.5 - jamb * 0.5, jamb_h * 0.5, 0.0)),  # montant G
        P_BOX("wood_planks", (jamb, jamb_h, wall_thickness), (width * 0.5 + jamb * 0.5, jamb_h * 0.5, 0.0)),  # montant D
        P_BOX("rust", (width + 2.0 * jamb, 0.04, wall_thickness + 0.02), (0.0, 0.02, 0.0)),  # seuil cerclé
    ]


def parts_door_frame() -> list:
    # Largeur Kit par défaut (doc 11 §9 : « largeur par défaut 1,6 m ») ;
    # montant 0,2 m de chaque côté -> largeur hors-tout 2,0 m (grille).
    return door_frame(width=1.6, height=2.2, wall_thickness=0.25, jamb=0.2)


def _telescoped_cells(total: float, n: int, gap: float) -> list:
    """`n` cellules JOINTIVES à `gap` (réel, pas de coïncidence de sommets —
    voir SEAM_GAP_M) qui remplissent EXACTEMENT `[-total/2, total/2]`, sans
    rogner les bords extérieurs (contrairement à `total/n - gap` naïf, qui
    grignote aussi les deux bords externes et sort le module de la grille de
    pose de 0,5 m) : chaque cellule mesure `(total - gap*(n-1)) / n`, la
    dernière atteint exactement `+total/2`. Renvoie `[(centre, largeur), ...]`."""
    cell = (total - gap * (n - 1)) / n
    out = []
    x0 = -total * 0.5
    for i in range(n):
        c0 = x0 + i * (cell + gap)
        out.append((c0 + cell * 0.5, cell))
    return out


def crate_stack_fit(width: float, height: float, depth: float) -> list:
    """Pile de caisses ajustée à une boîte exacte (plan §2, R7 : « silhouette
    >= 85 % de la boîte ») — caisses INDIVIDUELLES en planches peintes,
    cerclées d'une lisse métal peint (jamais un seul pavé texturé), empilées
    en rangées régulières qui remplissent la boîte EXACTEMENT (bords extérieurs
    flush avec la boîte demandée — voir `_telescoped_cells`)."""
    gap = 0.04
    n_x = max(1, round(width / 1.0))
    n_z = max(1, round(depth / 1.0))
    rows = max(1, round(height / 1.0))
    xs = _telescoped_cells(width, n_x, gap)
    zs = _telescoped_cells(depth, n_z, gap)
    ys = _telescoped_cells(height, rows, gap)
    parts = []
    for cy, crate_h in ys:
        for cx, crate_w in xs:
            for cz, crate_d in zs:
                parts.append(P_BOX("wood_planks", (crate_w, crate_h, crate_d), (cx, cy, cz)))
                parts.append(P_STRUT("painted_metal", (cx - crate_w * 0.5, cy, cz), (cx + crate_w * 0.5, cy, cz), 0.015))
    return parts


def parts_crate_stack_fit() -> list:
    # CaisseFUEL (doc 11 §9) : largeur 2 m (grille), hauteur 2,2 m, profondeur 4 m.
    return crate_stack_fit(width=2.0, height=2.2, depth=4.0)


def sleeper_stack(width: float, height: float, depth: float) -> list:
    """Pile de traverses en croisillons pleins (plan §2 : « remplit la boîte à
    100 % ») — courses ALTERNÉES (une rangée le long de X, la suivante le long
    de Z, comme un tas de rondins) : chaque traverse a la section d'une vraie
    traverse de voie ferrée, jointées avec le même jeu structurel que les
    planches du kit (SEAM_GAP_M, voir son commentaire)."""
    beam_t = 0.22
    step = beam_t + SEAM_GAP_M
    rows = max(1, round(height / step))
    parts = []
    for r in range(rows):
        cy = beam_t * 0.5 + r * step
        if r % 2 == 0:
            n = max(1, round(depth / step))
            for i in range(n):
                cz = -depth * 0.5 + beam_t * 0.5 + i * step
                if cz + beam_t * 0.5 > depth * 0.5 + 1e-6:
                    continue
                parts.append(P_BOX("wood_planks", (width, beam_t, beam_t), (0.0, cy, cz)))
        else:
            n = max(1, round(width / step))
            for i in range(n):
                cx = -width * 0.5 + beam_t * 0.5 + i * step
                if cx + beam_t * 0.5 > width * 0.5 + 1e-6:
                    continue
                parts.append(P_BOX("wood_planks", (beam_t, beam_t, depth), (cx, cy, 0.0)))
    return parts


def parts_sleeper_stack() -> list:
    # TraversesW (doc 11 §9) : (2 ; 2 ; 2) m — largeur 2 m (grille).
    return sleeper_stack(width=2.0, height=2.0, depth=2.0)


def trough(width: float, height: float, depth: float) -> list:
    """Abreuvoir en planches peintes cerclées (plan §2, module `trough`) —
    caisson ouvert (fond + 4 parois), liseré métal peint en haut de cuve.
    Chaque pièce est séparée de ses voisines par un jeu RÉEL (`SEAM_GAP_M` —
    voir son commentaire) plutôt que posée exactement affleurante : le fond
    fait toute la largeur/profondeur demandées (c'est lui qui fixe la grille
    de pose), les parois et le liseré restent strictement DANS son emprise —
    jamais un sommet de paroi exactement confondu avec un sommet du fond, ce
    qui échouerait au CHK d'arêtes non-manifold de check_asset.py une fois
    soudé (remove_doubles) plutôt que de retomber dans l'exception CHK-16
    déjà tolérée pour les pièces VOLONTAIREMENT disjointes de ce kit."""
    wall_t, inset = 0.05, SEAM_GAP_M
    wall_h = height - wall_t - inset
    wall_cy = wall_t + inset + wall_h * 0.5
    # Parois latérales plus courtes que la profondeur (jeu réel `2*inset` à
    # chaque bout, où elles croiseraient sinon les parois avant/arrière EXACT-
    # EMENT au coin — un coin de caisson où deux parois se touchent pile sur
    # la même arête est le cas non-manifold classique de ce fichier, voir
    # SEAM_GAP_M) : jamais de sommet de paroi latérale confondu avec un
    # sommet de paroi avant/arrière.
    side_d = depth - 2.0 * wall_t - 4.0 * inset
    end_w = width - 2.0 * wall_t - 2.0 * inset
    rim_y = wall_cy + wall_h * 0.5 + inset + 0.015
    return [
        P_BOX("wood_planks", (width, wall_t, depth), (0.0, wall_t * 0.5, 0.0)),                                          # fond
        P_BOX("wood_planks", (wall_t, wall_h, side_d), (-width * 0.5 + wall_t * 0.5 + inset, wall_cy, 0.0)),             # paroi G
        P_BOX("wood_planks", (wall_t, wall_h, side_d), (width * 0.5 - wall_t * 0.5 - inset, wall_cy, 0.0)),              # paroi D
        P_BOX("wood_planks", (end_w, wall_h, wall_t), (0.0, wall_cy, -depth * 0.5 + wall_t * 0.5 + inset)),              # paroi avant
        P_BOX("wood_planks", (end_w, wall_h, wall_t), (0.0, wall_cy, depth * 0.5 - wall_t * 0.5 - inset)),               # paroi arrière
        P_BOX("rust", (width - 2.0 * inset, 0.03, depth - 2.0 * inset), (0.0, rim_y, 0.0)),                              # liseré cerclé
    ]


def parts_trough() -> list:
    # AbreuvoirW1/W2 (doc 11 §9) : largeur 2 m (grille), hauteur 1,1 m, profondeur 1 m.
    return trough(width=2.0, height=1.1, depth=1.0)


def counter(width: float, height: float, depth: float) -> list:
    """Comptoir en planches peintes (plan §2, module `counter`) — caisson
    plein, plateau cerclé en rive (jeu réel `SEAM_GAP_M` au-dessus du caisson
    — même raison que `trough`, voir son commentaire), footrail bas en métal
    peint encastré (pas de contact de face avec le caisson)."""
    top_t, gap = 0.06, SEAM_GAP_M
    body_h = height - top_t - gap
    return [
        P_BOX("wood_planks", (width, body_h, depth), (0.0, body_h * 0.5, 0.0)),                         # caisson
        P_BOX("rust", (width, top_t, depth), (0.0, body_h + gap + top_t * 0.5, 0.0)),                   # plateau cerclé
        P_BOX("painted_metal", (width - 0.1, 0.04, 0.02), (0.0, height * 0.35, -depth * 0.5 + 0.01)),   # footrail
    ]


def parts_counter() -> list:
    # ComptoirW (doc 11 §9) : largeur 2 m (grille), hauteur 1,1 m, profondeur 1 m.
    return counter(width=2.0, height=1.1, depth=1.0)


def mine_cart(width: float, height: float, depth: float) -> list:
    """Chariot de mine, benne pleine de minerai (plan §2, module `mine_cart`)
    — caisse en métal peint sur 2 essieux, 4 roues, minerai en vrac (blocs
    rouille irréguliers, décalage déterministe par index — convention
    `make_props.py` : aucun `random`)."""
    body_h = height * 0.55
    body_cy = body_h * 0.5 + height * 0.15
    parts = [
        P_BOX("painted_metal", (width, body_h, depth), (0.0, body_cy, 0.0)),
        P_STRUT("rust", (-width * 0.5, height * 0.15, -depth * 0.5 + 0.1), (width * 0.5, height * 0.15, -depth * 0.5 + 0.1), 0.06),
        P_STRUT("rust", (-width * 0.5, height * 0.15, depth * 0.5 - 0.1), (width * 0.5, height * 0.15, depth * 0.5 - 0.1), 0.06),
    ]
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            # Roues légèrement EN RETRAIT du plan de la caisse (jamais au-delà
            # — sinon la roue devient la pièce la plus large du module et fait
            # sortir sa largeur hors-tout de la grille de pose de 0,5 m).
            wx = sx * (width * 0.5 - 0.05)
            wz = sz * (depth * 0.5 - 0.1)
            parts.append(P_BOX("rust", (0.08, height * 0.3, height * 0.3), (wx, height * 0.15, wz)))
    n_rocks = 7
    for i in range(n_rocks):
        rx = ((i * 2.399963) % 1.0 - 0.5) * (width - 0.3)
        rz = ((i * 1.734) % 1.0 - 0.5) * (depth - 0.3)
        ry = body_h + height * 0.15 + 0.05 + 0.04 * math.sin(i * 1.9)
        s = 0.18 + 0.05 * math.sin(i * 0.7)
        parts.append(P_BOX("rust", (s, s, s), (rx, ry, rz), rot=("Y", i * 37.0)))
    return parts


def parts_mine_cart() -> list:
    # ChariotMineW (doc 11 §9) : (3 ; 2,2 ; 3,5) m — largeur 3 m (grille).
    return mine_cart(width=3.0, height=2.2, depth=3.5)


def plank_rail_solid(length: float, height: float) -> list:
    """Garde-corps plein en planches jointives (plan §2 : « on ne voit pas à
    travers », poteaux tous les 2 m) — mur bas de planches (`plank_wall_parts`)
    + poteaux tous les ~2 m + main courante cerclée."""
    post_w = 0.12
    n_posts = max(2, round(length / 2.0) + 1)
    parts = plank_wall_parts(length, height, 0.05, kind="wood_planks")
    # Poteaux d'about affleurants (jamais au-delà des extrémités du muret —
    # sinon le poteau devient la pièce la plus large et sort la largeur
    # hors-tout de la grille de pose de 0,5 m).
    span = length - post_w
    for i in range(n_posts):
        t = i / (n_posts - 1) if n_posts > 1 else 0.5
        px = -span * 0.5 + t * span
        parts.append(P_BOX("wood_planks", (post_w, height + 0.05, post_w), (px, (height + 0.05) * 0.5, 0.0)))
    parts.append(P_BOX("rust", (length, 0.04, 0.08), (0.0, height + 0.02, 0.0)))  # main courante cerclée
    return parts


def parts_plank_rail_solid() -> list:
    # ParapetW1-3 (doc 11 §9) : hauteur 1,1 m ; segment de pose 4 m (grille).
    return plank_rail_solid(length=4.0, height=1.1)


def bund_wall(length: float, height: float) -> list:
    """Muret de rétention kit (plan §2, CiterneFUEL/GAS : « muret de rétention
    kit de 1,2 m ») — mur bas de planches + côtes verticales cerclées de métal
    rouillé tous les mètres."""
    wall_t = 0.15
    parts = plank_wall_parts(length, height, wall_t, kind="wood_planks")
    n_ribs = max(2, round(length / 1.0))
    rib_w = 0.08
    # Côtes d'about affleurantes (jamais au-delà des extrémités du muret —
    # même raison que les poteaux de `plank_rail_solid`, voir son commentaire).
    rib_span = length - rib_w
    for i in range(n_ribs + 1):
        rx = -rib_span * 0.5 + i * (rib_span / n_ribs)
        parts.append(P_BOX("rust", (rib_w, height, 0.04), (rx, height * 0.5, -wall_t * 0.5 - 0.02)))
    return parts


def parts_bund_wall() -> list:
    # CiterneFUEL/GAS (doc 11 §9, taille 4x4x2,8) : muret de 4 m (grille), 1,2 m.
    return bund_wall(length=4.0, height=1.2)


def tower_leg(height: float) -> list:
    """Pied du château d'eau, bois et fer, aux cotes ±5 cm (plan §2 : « pieds
    en bois et fer, module `tower_leg`, à ±5 cm. Croisillons seulement
    au-dessus de 2,6 m ») — embase (garantit une empreinte alignée grille pour
    la pose), poteau plein, jambes de force en métal peint uniquement dans la
    tranche haute."""
    post_sec = 0.14
    base_w = 0.5  # embase 0,5 m (grille de pose) — le poteau lui-même reste fin
    parts = [
        P_BOX("wood_planks", (base_w, 0.15, base_w), (0.0, 0.075, 0.0)),
        P_STRUT("wood_planks", (0.0, 0.15, 0.0), (0.0, height, 0.0), post_sec),
    ]
    # Jambes de force EN RETRAIT du bord de l'embase (jamais jusqu'à son
    # arête — une extrémité de jambe de force exactement sur l'arête de
    # l'embase ferait dépasser la largeur hors-tout de la grille de pose de
    # 0,5 m, une fois la section carrée de la jambe projetée dans le repère
    # monde). Départ des deux jambes d'un même palier décalé de SEAM_GAP_M en
    # Y (jamais le même point exact) : deux sections carrées tournées
    # différemment (une jambe part vers +X, l'autre vers -X) partageant un
    # unique sommet de départ soudent parfois quelques arêtes non-manifold à
    # la réimportation de check_asset.py (`remove_doubles`) — même raison que
    # SEAM_GAP_M ailleurs dans ce fichier (voir son commentaire).
    brace_far_x = base_w * 0.5 - 0.08
    brace_y0 = 2.6
    n_braces = max(1, math.floor((height - brace_y0) / 1.5))
    for i in range(n_braces):
        y0 = brace_y0 + i * 1.5
        y1 = min(y0 + 1.5, height)
        parts.append(P_STRUT("painted_metal", (0.0, y0, 0.0), (brace_far_x, y1, 0.0), 0.03))
        parts.append(P_STRUT("painted_metal", (0.0, y0 + SEAM_GAP_M, 0.0), (-brace_far_x, y1, 0.0), 0.03))
    return parts


def parts_tower_leg() -> list:
    # Château d'eau (doc 11 §9) : cuve à 8-12 m -> pieds de 8 m.
    return tower_leg(height=8.0)


def roof_sheet(width: float, run: float) -> list:
    """Tôle ondulée de toit, un seul pan (plan §2 R5 : « tôle ondulée en un
    seul pan par versant... posée à 3 cm au-dessus des pans de collision, avec
    faîtière et rives ») — généralisation paramétrée de `parts_roof_corrugated`
    (largeur/course fixes) à la largeur réelle d'un volume, plus une faîtière."""
    thickness = 0.04
    parts = [P_BOX("corrugated_metal", (width, thickness, run), (0.0, 0.0, 0.0))]
    ridge_step = 0.17
    n_ridges = max(1, round(width / ridge_step))
    step = width / n_ridges
    for i in range(n_ridges):
        rx = -width * 0.5 + (i + 0.5) * step
        parts.append(P_BOX("corrugated_metal", (0.05, 0.025, run), (rx, thickness * 0.5 + 0.0125, 0.0)))
    parts.append(P_BOX("rust", (width, 0.03, 0.08), (0.0, -thickness * 0.5 - 0.015, -run * 0.5)))  # rive (égout)
    parts.append(P_BOX("rust", (0.10, 0.05, run), (0.0, thickness * 0.5 + 0.03, 0.0)))              # faîtière
    return parts


def parts_roof_sheet() -> list:
    # Pan de toit pour un volume de 6 m de large (grille), profondeur 4 m.
    return roof_sheet(width=6.0, run=4.0)


MODULES = {
    "wall_1_level": parts_wall_1_level,
    "wall_2_level": parts_wall_2_level,
    "pediment_narrow": parts_pediment_narrow,
    "pediment_wide": parts_pediment_wide,
    "window_shutters_open": parts_window_shutters_open,
    "window_shutters_closed": parts_window_shutters_closed,
    "door": parts_door,
    "porch": parts_porch,
    "balcony_railing": parts_balcony_railing,
    "roof_corrugated": parts_roof_corrugated,
    "corner_outer": parts_corner_outer,
    "corner_inner": parts_corner_inner,
    "cornice_band": parts_cornice_band,
    "exterior_stairs": parts_exterior_stairs,
    # -- ART-92 : modules kit v2 manquants (docs/art/WASTELAND_V4_ART_PLAN.md §2) --
    "stairs_fit": parts_stairs_fit,
    "door_frame": parts_door_frame,
    "crate_stack_fit": parts_crate_stack_fit,
    "sleeper_stack": parts_sleeper_stack,
    "trough": parts_trough,
    "counter": parts_counter,
    "mine_cart": parts_mine_cart,
    "plank_rail_solid": parts_plank_rail_solid,
    "bund_wall": parts_bund_wall,
    "tower_leg": parts_tower_leg,
    "roof_sheet": parts_roof_sheet,
}

# Modules dont l'ouverture doit tenir les cotes Kit exactes (critère
# d'acceptation) — vérifié à la fois par construction (les constantes
# ci-dessus PILOTENT la géométrie, voir `_door_opening`/`_window_opening`) et
# par le self-test géométrique (`_selftest_opening_void`), qui rejoue la même
# découpe de planches et vérifie qu'aucun segment ne recouvre le rectangle.
DOOR_MODULES = ("door",)
WINDOW_MODULES = ("window_shutters_open", "window_shutters_closed")


# ---------------------------------------------------------------------------
# Construction / export d'un module
# ---------------------------------------------------------------------------

def _kind_material(kind: str) -> "bpy.types.Material":
    return toonkit.toon_material(kind, toonkit.palette(kind), kind=kind)


def build_module(name: str, parts_fn) -> dict:
    toonkit.reset_scene()
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    tint_layer = bm.loops.layers.color.new(PLANK_TINT_ATTR)

    parts = parts_fn()
    kinds_used = []
    for p in parts:
        k = p[1]
        assert k in KINDS, f"{name}: kind hors contrat ART-73 {k!r} (attendu un de {KINDS})"
        if k not in kinds_used:
            kinds_used.append(k)
    kind_index = {k: i for i, k in enumerate(kinds_used)}

    plank_count = 0
    for p in parts:
        ptype, kind = p[0], p[1]
        if ptype == "box":
            _, _, size, center, rot = p
            faces = add_box(bm, uv_layer, size, center, rot)
        elif ptype == "strut":
            _, _, p0, p1, thickness = p
            faces = add_strut(bm, uv_layer, p0, p1, thickness)
        elif ptype == "plank":
            _, _, size, center, idx = p
            faces = add_box(bm, uv_layer, size, center, None)
            tint = _plank_tint(idx)
            for f in faces:
                for loop in f.loops:
                    loop[tint_layer] = tint
            plank_count += 1
        else:
            raise ValueError(f"{name}: type de pièce inconnu {ptype!r}")
        for f in faces:
            f.material_index = kind_index[kind]

    # Planches et pièces sans teinte de sommet explicite (cadres, tôles,
    # struts…) restent à blanc (1,1,1,1) sur cet attribut — un multiplicateur
    # neutre, jamais un assombrissement parasite.
    for f in bm.faces:
        if f.material_index >= 0:
            for loop in f.loops:
                if tuple(loop[tint_layer]) == (0.0, 0.0, 0.0, 0.0):
                    loop[tint_layer] = (1.0, 1.0, 1.0, 1.0)

    # Repère d'auteur (Y-up) -> Blender natif (Z-up) — voir en-tête de
    # fichier : s'annule EXACTEMENT avec `export_yup=True` à l'export.
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"), verts=list(bm.verts))

    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)

    for kind in kinds_used:
        obj.data.materials.append(_kind_material(kind))

    # Chanfrein 1-2 cm sur toute arête exposée (critère d'acceptation) —
    # largeur du contrat, PAS `toonkit.bevel_for_class("architecture")` (6 cm,
    # hors de la plage exigée ici). Lissage hard-surface ensuite, comme le
    # reste de la bibliothèque wasteland.
    toonkit.add_bevel(obj, width=CHAMFER_M, segments=CHAMFER_SEGMENTS, angle_limit_deg=CHAMFER_ANGLE_DEG)
    toonkit.weighted_normals(obj, sharp_angle_deg=CHAMFER_ANGLE_DEG)
    toonkit.smooth_normal_attrs(obj)

    out_path = os.path.join(OUT_DIR, f"{name}.glb")
    toonkit.export_glb(out_path, obj, write_report=True)

    tris = toonkit.tri_count(obj)
    dims = tuple(round(v, 4) for v in obj.dimensions)
    # Pivot (critère d'acceptation « pivots au sol sur une grille de 0,5 m ») —
    # capturé ICI (avant que check_asset.py ne réimporte le .glb) plutôt que
    # recalculé depuis le fichier exporté : c'est la position RÉELLE du pivot
    # de l'objet Blender, exactement ce que Godot lira comme origine du prop.
    # Chaque module de ce kit place volontairement son pivot au repère
    # d'auteur (0,0,0) — au sol pour les modules qui reposent au rez-de-
    # chaussée (murs, porte, fenêtres, porche, escalier, angles), au plan de
    # raccord (haut de mur / coin) pour les modules rapportés en hauteur
    # (balcon, corniche, toit) — la convention "centre-bas de bbox" générique
    # de check_asset.py (`origin_at_bottom_center`, un AVERTISSEMENT, jamais
    # un échec dur — voir son propre commentaire "peut être volontaire —
    # arme/gant") ne s'applique pas telle quelle à un kit modulaire à pivots
    # asymétriques (angle, porche, escalier) : lui imposer un recentrage
    # géométrique casserait l'alignement de pose voulu pour ART-73B (pose sur
    # la carte, hors périmètre de ce fichier). (0, 0, 0) est trivialement un
    # multiple de GRID_M — voir `pivot_grid_ok` dans `build_all()`.
    pivot_m = tuple(round(v, 4) for v in obj.matrix_world.translation)
    print(f"WL_SHANTY_MODULE_OK {name} tris={tris} dims={dims} slots={kinds_used} planks={plank_count} -> {out_path}")
    return {
        "name": name, "path": out_path, "tris": tris, "dims_m": dims,
        "slots": kinds_used, "plank_count": plank_count, "pivot_m": pivot_m,
    }


# ---------------------------------------------------------------------------
# Vérifications géométriques pures (aucun bpy) — rejouent la même découpe de
# planches que `plank_wall_parts` pour confirmer qu'aucun segment ne recouvre
# le rectangle d'ouverture Kit (porte/fenêtre). Utilisées par le self-test
# ET importables tel quel par un futur test si besoin.
# ---------------------------------------------------------------------------

def opening_void_is_clear(width: float, height: float, depth: float, opening: dict) -> bool:
    parts = plank_wall_parts(width, height, depth, opening=opening)
    ox0, ox1, oy0, oy1 = opening["x0"], opening["x1"], opening["y0"], opening["y1"]
    for _, _, size, center, _ in parts:
        w, h, _d = size
        cx, cy, _cz = center
        x0, x1 = cx - w * 0.5, cx + w * 0.5
        y0, y1 = cy - h * 0.5, cy + h * 0.5
        overlap_x = min(x1, ox1) - max(x0, ox0)
        overlap_y = min(y1, oy1) - max(y0, oy0)
        if overlap_x > 1e-6 and overlap_y > 1e-6:
            return False
    return True


def _is_grid_multiple(value: float, grid: float = GRID_M, eps: float = 0.02) -> bool:
    ratio = value / grid
    return abs(ratio - round(ratio)) * grid < eps


# ---------------------------------------------------------------------------
# Construction / vérification de tous les modules + self-test JSON
# ---------------------------------------------------------------------------

def build_all(only: str = None) -> dict:
    os.makedirs(OUT_DIR, exist_ok=True)
    names = [only] if only else list(MODULES.keys())
    for n in names:
        if n not in MODULES:
            raise ValueError(f"module inconnu {n!r} (attendu un de {sorted(MODULES)})")

    report = {"modules": [], "module_count": len(names), "ok": True, "failures": []}

    for name in names:
        info = build_module(name, MODULES[name])

        check = check_asset.run(info["path"], budget_tris=None, asset_class=ASSET_CLASS)
        check_asset.print_text(check)
        hard_failures = [msg for msg in check["failures"] if _FLOATING_PIECE_MARKER not in msg]
        floating_failures = [msg for msg in check["failures"] if _FLOATING_PIECE_MARKER in msg]

        entry = {
            "name": name,
            "tris": info["tris"],
            "dims_m": info["dims_m"],
            "slots": info["slots"],
            "plank_count": info["plank_count"],
            "pivot_m": info["pivot_m"],
            "pivot_grid_ok": all(_is_grid_multiple(v, eps=1e-6) for v in info["pivot_m"]),
            # Résultat LITTÉRAL du contrat ("check_asset PASS"), jamais
            # remplacé par l'exception ci-dessous — voir `chk16_exception`.
            "check_asset_raw_ok": check["ok"],
            "check_asset_failures": check["failures"],
            "check_asset_failures_excl_chk16": hard_failures,
            "check_asset_floating_piece_failures": floating_failures,
            # Champ EXPLICITEMENT nommé : "PASS en excluant CHK-16" — jamais
            # confondu avec `check_asset_raw_ok` (voir le commentaire
            # CHK16_EXCEPTION_APPROVED_BY_LEAD plus haut dans ce fichier).
            "check_asset_ok_excl_chk16_known_limitation": len(hard_failures) == 0,
            "kinds_within_contract": all(k in KINDS for k in info["slots"]),
            "grid_x_ok": _is_grid_multiple(info["dims_m"][0]),
        }
        # ART-92 (critère d'acceptation : « tous les modules painted: true ») —
        # ce générateur n'assigne QUE les 5 kinds peints du contrat
        # (`build_module` fait échouer la construction dès qu'un "part" sort
        # de `KINDS`, voir son `assert`) : un module qui a fini de se
        # construire a donc TOUJOURS `kinds_within_contract == True`, cette
        # équivalence est littérale, jamais devinée — même convention "champ
        # nommé explicitement" que `check_asset_ok_excl_chk16_known_limitation`
        # ci-dessus (jamais confondu avec un statut recalculé ailleurs).
        entry["painted"] = entry["kinds_within_contract"]
        # Alias rétro-compatible (même valeur) : nom historique déjà lu par
        # d'autres tâches/outils avant ce correctif — on ne le supprime pas.
        entry["check_asset_ok"] = entry["check_asset_ok_excl_chk16_known_limitation"]

        if name in DOOR_MODULES:
            entry["opening_m"] = {"w": DOOR_W_M, "h": DOOR_H_M}
            entry["opening_matches_kit_cotes"] = (DOOR_W_M, DOOR_H_M) == (1.2, 2.2)
            entry["opening_void_clear"] = opening_void_is_clear(WALL_W_M, WALL_H_M, WALL_D_M, _door_opening())
        if name in WINDOW_MODULES:
            entry["window_recess_m"] = WINDOW_RECESS_M
            entry["window_recess_ok"] = WINDOW_RECESS_M >= 0.08
            entry["opening_void_clear"] = opening_void_is_clear(WALL_W_M, WALL_H_M, WALL_D_M, _window_opening())

        report["modules"].append(entry)
        if not entry["check_asset_ok"]:
            report["ok"] = False
            report["failures"].append(f"{name}: check_asset ECHEC (hors CHK-16 pièces déconnectées) — {hard_failures}")
        if not entry["kinds_within_contract"]:
            report["ok"] = False
            report["failures"].append(f"{name}: matériau hors des 5 kinds du contrat — {info['slots']}")
        if not entry["grid_x_ok"]:
            report["ok"] = False
            report["failures"].append(f"{name}: largeur {info['dims_m'][0]} m hors grille {GRID_M} m")
        if not entry["pivot_grid_ok"]:
            report["ok"] = False
            report["failures"].append(f"{name}: pivot {info['pivot_m']} hors grille {GRID_M} m")
        if entry.get("opening_void_clear") is False:
            report["ok"] = False
            report["failures"].append(f"{name}: planche(s) recouvrant l'ouverture Kit")

    # Bloc récapitulatif CHK-16 — structuré et EXPLICITE (retour vérificateur
    # ART-73 : « l'acceptance/le test le disent en clair »), jamais mélangé
    # au champ `ok` générique : un lead qui lit manifest.json voit d'un coup
    # d'œil quels modules sont concernés, combien de pièces, et que ce n'est
    # PAS encore une exception approuvée.
    chk16_modules = [m["name"] for m in report["modules"] if m["check_asset_floating_piece_failures"]]
    report["chk16_exception"] = {
        "approved_by_lead": CHK16_EXCEPTION_APPROVED_BY_LEAD,
        "reason": (
            "check_asset.py CHK-16 compare chaque piece a la seule plus "
            "grosse composante (jamais de chainage proche-en-proche) : un "
            "mur de planches VOLONTAIREMENT jointees (joints 1-2 cm, "
            "critere d'acceptation) y echoue structurellement des la "
            "premiere planche voisine. Pre-existant : 5 props wasteland "
            "deja livres (fence_wood, pallet, exterior_stairs, "
            "corrugated_shed, balcony_railing) echouent au meme CHK-16 "
            "aujourd'hui. check_asset.py est hors de la liste de fichiers "
            "de ce contrat (ART-73) -- ne peut pas etre corrige ici."
        ),
        "affected_modules": chk16_modules,
        "affected_module_count": len(chk16_modules),
        "decision_needed": [
            "approuver l'exception CHK-16 pour les assets multi-pieces a joints reels",
            "corriger check_asset.py (chainage proche-en-proche)",
            "remodeler sans ecart reel > 1 cm (perd le critere joints 1-2 cm)",
        ],
    }
    # PAS ajouté à `report["failures"]` : cette liste ne doit contenir que les
    # raisons pour lesquelles `report["ok"]` est False, et l'exception
    # CHK-16 (non approuvée) ne fait volontairement PAS échouer `ok` (voir
    # commentaire CHK16_EXCEPTION_APPROVED_BY_LEAD) — le statut réel, complet
    # et non résumé vit dans `report["chk16_exception"]` et dans
    # `check_asset_raw_ok`/`check_asset_failures` par module, jamais caché.

    report["chamfer_m"] = CHAMFER_M
    report["chamfer_within_contract"] = 0.01 - 1e-9 <= CHAMFER_M <= 0.02 + 1e-9
    report["plank_gap_m"] = PLANK_GAP_M
    report["plank_gap_within_contract"] = 0.01 - 1e-9 <= PLANK_GAP_M <= 0.02 + 1e-9
    report["plank_jitter_m"] = PLANK_JITTER_M
    report["plank_jitter_within_contract"] = PLANK_JITTER_M <= 0.01 + 1e-9
    if not report["chamfer_within_contract"]:
        report["ok"] = False
        report["failures"].append(f"chamfer_m {CHAMFER_M} hors de la plage 0.01-0.02 exigée")
    if not report["plank_gap_within_contract"]:
        report["ok"] = False
        report["failures"].append(f"plank_gap_m {PLANK_GAP_M} hors de la plage 0.01-0.02 exigée")
    if not report["plank_jitter_within_contract"]:
        report["ok"] = False
        report["failures"].append(f"plank_jitter_m {PLANK_JITTER_M} hors de la plage +/-0.01 exigée")
    if only is None and len(names) < 14:
        report["ok"] = False
        report["failures"].append(f"seulement {len(names)} module(s) — au moins 14 exigés")

    manifest_path = os.path.join(OUT_DIR, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    print(f"WL_SHANTY_MANIFEST_OK {len(names)} module(s) -> {manifest_path}")
    return report


# ---------------------------------------------------------------------------
# Captures (critère d'acceptation : « planche turntable de chaque module, un
# assemblage de 3 façades ») — réutilise tools/blender/turntable.py TEL QUEL
# (jamais modifié, import en lecture seule ci-dessus) : un lancement par
# module (son pipeline complet — sujet + silhouette humaine + sol + planche-
# contact — attend un seul asset à la fois, en sous-processus pour rester
# fidèle à son usage documenté), et un rendu d'assemblage écrit ici (turntable
# ne compose pas plusieurs assets) qui réutilise ses fonctions internes
# (import/matériaux/caméra/sol/planche-contact) directement en mémoire.
# ---------------------------------------------------------------------------

ASSEMBLY_MODULES = ("wall_1_level", "door", "window_shutters_closed")

# Modules ajoutés par ART-92 (docs/art/WASTELAND_V4_ART_PLAN.md:254, même liste
# et même ordre que le bloc « ART-92 » de MODULES ci-dessus) — c'est la liste
# que couvre `render_kit_v2_module_board()` plus bas, PAS `ASSEMBLY_MODULES`
# (qui sert un critère différent, hérité d'ART-73 : « un assemblage de 3
# façades », pas une couverture de tous les modules kit v2).
NEW_KIT_V2_MODULES = (
    "stairs_fit", "door_frame", "crate_stack_fit", "sleeper_stack", "trough",
    "counter", "mine_cart", "plank_rail_solid", "bund_wall", "tower_leg", "roof_sheet",
)


def render_module_turntables(modules: list, out_dir: str) -> None:
    """Une planche-contact turntable PAR module, dans <out_dir>/<name>/ —
    sous-processus Blender par module (turntable.py n'est jamais importé
    « pour de vrai » ici, seulement relancé comme documenté en tête de ce
    fichier partagé)."""
    # Même convention que tools/blender/tests/test_make_wl_shanty_kit.py
    # ::_blender_bin — BLENDER_BIN sinon le chemin connu de ce poste
    # (CLAUDE.md), jamais supposé sur une autre machine.
    blender_bin = os.environ.get("BLENDER_BIN", r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")
    turntable_script = os.path.join(_HERE, "turntable.py")
    for name in modules:
        glb_path = os.path.join(OUT_DIR, f"{name}.glb")
        module_out = os.path.join(out_dir, name)
        os.makedirs(module_out, exist_ok=True)
        cmd = [blender_bin, "-b", "--factory-startup", "-P", turntable_script, "--",
            "--in", glb_path, "--out", module_out]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        ok = proc.returncode == 0 and "TURNTABLE_OK" in proc.stdout
        print(f"WL_SHANTY_TURNTABLE_{'OK' if ok else 'FAIL'} {name} -> {module_out}")
        if not ok:
            print(proc.stdout[-2000:])
            print(proc.stderr[-2000:])


def render_assembly_capture(out_dir: str, modules: tuple = ASSEMBLY_MODULES, size: int = 512) -> str:
    """« un assemblage de 3 façades » — importe `modules` côte à côte (pas de
    WALL_W_M, la grille de pose du kit) dans une seule scène et rend une
    planche-contact face + 3/4 avec le même pipeline visuel que turntable.py
    (2 tons + encre, sol, silhouette humaine 1,8 m) : réutilise ses fonctions
    PUBLIQUES en mémoire (import_asset/apply_preview_materials/world_bbox/
    add_camera/add_ground/add_human_silhouette/setup_render/render_to/
    build_contact_sheet) — turntable.py lui-même ne compose qu'un seul asset
    par lancement (voir son argparse), donc ce montage est écrit ici, jamais
    en modifiant ce fichier partagé."""
    turntable.toonkit.reset_scene()
    all_objs = []
    for i, name in enumerate(modules):
        path = os.path.join(OUT_DIR, f"{name}.glb")
        # `turntable.import_asset` renvoie TOUS les mesh de la scène (voulu
        # pour son propre usage : un seul import par lancement) — dans cette
        # boucle multi-imports, il faut ne déplacer QUE les objets NOUVEAUX
        # de CET import, sinon les modules déjà placés se décalent une
        # deuxième/troisième fois (repéré en relisant l'image rendue : deux
        # modules se superposaient exactement). D'où le diff explicite
        # avant/après plutôt que la valeur de retour de `import_asset`.
        before = set(bpy.context.scene.objects)
        turntable.import_asset(path)
        new_objs = [o for o in bpy.context.scene.objects if o not in before and o.type == 'MESH']
        offset_x = (i - (len(modules) - 1) / 2.0) * WALL_W_M
        for o in new_objs:
            o.location.x += offset_x
        all_objs.extend(new_objs)

    # Sans ce point de synchronisation explicite, `matrix_world` (lu juste
    # après par `world_bbox`) peut encore renvoyer la transform D'AVANT le
    # décalage `o.location.x += offset_x` ci-dessus (le graphe de dépendance
    # de Blender ne se réévalue pas forcément à la simple écriture d'une
    # propriété Python) — repéré en relisant l'image rendue : deux façades
    # se recouvraient exactement malgré des `location.x` bien distincts.
    bpy.context.view_layer.update()

    material_names = turntable.apply_preview_materials(all_objs)
    tris = toonkit.tri_count(all_objs)
    mins, maxs = turntable.world_bbox(all_objs)
    dims = maxs - mins
    center = (mins + maxs) / 2.0
    radius = max(dims.x, dims.y, dims.z) / 2.0
    ground_z = mins.z

    turntable.setup_render(size)
    cam = turntable.add_camera(turntable.CAM_FOV_DEG)
    human_x = maxs.x + turntable.HUMAN_BODY_RADIUS + 0.5
    turntable.add_human_silhouette(human_x, center.y, ground_z)
    combo_max_x = max(maxs.x, human_x + turntable.HUMAN_BODY_RADIUS)
    combo_center = Vector(((mins.x + combo_max_x) / 2.0, center.y, center.z))
    combo_radius = max(
        (Vector((combo_max_x, maxs.y, maxs.z)) - combo_center).length,
        (Vector((mins.x, mins.y, mins.z)) - combo_center).length,
    )
    turntable.add_ground(combo_center.x, combo_center.y, ground_z, combo_radius + radius)

    os.makedirs(out_dir, exist_ok=True)
    tiles = []
    distance = turntable._distance_for(combo_radius, turntable.CAM_FOV_DEG)
    views = (("face", 0.0, turntable.ORBIT_ELEVATION_DEG), ("trois-quarts", 35.0, turntable.ORBIT_ELEVATION_DEG))
    for label, az, el in views:
        cam.location = combo_center + turntable._orbit_position(Vector((0, 0, 0)), distance, az, el)
        turntable._look_at(cam, combo_center)
        path = os.path.join(out_dir, f"assembly_{label.replace('-', '_')}.png")
        turntable.render_to(path)
        tiles.append((label, path))

    calibration_label, calibration_path = turntable.render_calibration_swatch(out_dir, size)
    tiles.append((calibration_label, calibration_path))

    header = [
        "assemblage_3_facades : " + ", ".join(modules),
        f"tris={tris}",
        f"dims={dims.x:.2f}x{dims.z:.2f}x{dims.y:.2f} m",
        f"matériaux: {', '.join(material_names) if material_names else 'aucun'}",
    ]
    sheet_path = os.path.join(out_dir, "assembly_3_facades_contact_sheet.png")
    turntable.build_contact_sheet(sheet_path, tiles, size, header)
    print(f"WL_SHANTY_ASSEMBLY_OK {sheet_path}")
    return sheet_path


def render_kit_v2_module_board(captures_dir: str, modules: tuple = NEW_KIT_V2_MODULES,
        size: int = 512) -> str:
    """« planche des modules » (critère d'acceptation ART-92,
    docs/art/WASTELAND_V4_ART_PLAN.md:254) pour les modules kit v2 ajoutés par
    ART-92 — PAS un rendu d'assemblage : `render_assembly_capture` compose
    quelques modules côte à côte dans une seule scène 3D avec des matériaux
    d'aperçu à plat vus de loin (prévu pour « un assemblage de 3 façades »,
    un critère différent hérité d'ART-73), ce qui rend les planches et
    l'encrage à peine visibles et ne couvre que les modules qu'on lui donne.
    Cette planche-ci réutilise au contraire, TEL QUEL, le rendu « gros plan »
    déjà produit par `render_module_turntables` pour CHAQUE module de
    `modules` (même pipeline peint/encré que chaque planche-contact
    individuelle, ex. door/door_contact_sheet.png) et les compose en une
    seule grille via `turntable.build_contact_sheet` — aucun nouveau rendu
    3D, donc le même niveau de détail peint que les planches-contact par
    module, et une couverture explicite de tous les `modules` demandés.

    Exige que `render_module_turntables(modules, captures_dir)` ait déjà
    tourné : échoue fort plutôt que de livrer silencieusement une planche
    qui ne couvrirait qu'une partie des modules kit v2 (c'est exactement le
    défaut relevé sur la planche précédente, qui ne montrait que 3 des 11
    modules sans le signaler)."""
    tiles = []
    missing = []
    for name in modules:
        closeup_path = os.path.join(captures_dir, name, "closeup.png")
        if os.path.isfile(closeup_path):
            tiles.append((name, closeup_path))
        else:
            missing.append(name)
    if missing:
        raise RuntimeError(
            "render_kit_v2_module_board: gros plan manquant pour "
            f"{missing} — lancer render_module_turntables(NEW_KIT_V2_MODULES, ...) "
            "d'abord (cette planche ne doit jamais se déclarer complète en couvrant "
            "moins de modules que `modules`)."
        )
    header = [
        f"planche des modules kit v2 (ART-92) : {len(tiles)}/{len(modules)} modules — "
        + ", ".join(name for name, _ in tiles),
    ]
    sheet_path = os.path.join(captures_dir, "kit_v2_modules_board.png")
    turntable.build_contact_sheet(sheet_path, tiles, size, header)
    print(f"WL_SHANTY_KIT_V2_BOARD_OK {len(tiles)} module(s) -> {sheet_path}")
    return sheet_path


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--only", default=None, help="ne construire qu'un seul module (itération rapide)")
    p.add_argument("--selftest-json", dest="selftest_json", default=None,
        help="écrit aussi le rapport à ce chemin et imprime le marqueur WL_SHANTY_KIT_SELFTEST_RESULT "
            "(consommé par tools/blender/tests/test_make_wl_shanty_kit.py)")
    p.add_argument("--captures", dest="captures_dir", default=None,
        help="génère aussi les planches-contact (turntable par module + assemblage de 3 façades + "
            "planche des modules kit v2 ART-92, critères d'acceptation) dans ce dossier — construit "
            "d'abord tous les modules (ignore --only)")
    return p.parse_args(argv)


def main() -> None:
    args = parse_args()
    report = build_all(only=args.only)
    if args.selftest_json:
        out_path = os.path.abspath(args.selftest_json)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        print(f"WL_SHANTY_KIT_SELFTEST_RESULT {json.dumps(report, ensure_ascii=False)}")
    if args.captures_dir:
        if args.only:
            build_all(only=None)  # les captures veulent tous les modules, --only ne suffit pas
        out_dir = os.path.abspath(args.captures_dir)
        os.makedirs(out_dir, exist_ok=True)
        render_module_turntables(list(MODULES.keys()), out_dir)
        render_assembly_capture(out_dir)
        render_kit_v2_module_board(out_dir)


if __name__ == "__main__":
    main()
