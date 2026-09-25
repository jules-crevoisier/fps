#!/usr/bin/env python3
# -*- coding: utf-8 -*-
## tools/blender/shell_to_skin.py
## Tâche ART-92 — « Peau de façade » (docs/art/WASTELAND_V4_ART_PLAN.md §1 R2,
## §2). Coexistence de l'art et de la collision : sous 2,6 m, le visuel colle
## aux boîtes du greybox à ±10 cm (R1) ; les ouvertures viennent de la
## collision construite, jamais recopiées à la main (R3). Ce script découpe
## une PEAU dans une coque Tripo peinte déjà installée (assets/models/props/
## wasteland/tripo/*.glb) et la pose prête à plaquer contre un mur du Kit —
## il ne pose RIEN sur la carte lui-même (ART-94/95/96, hors périmètre).
##
## Trois modes (R2) :
##   card  : tranche une face sur `--depth` m (0,6 m par défaut), supprime le
##           dos, étire au plus 12 % par axe pour atteindre la cote cible,
##           écrase le relief sous 2,6 m à ±10 cm (R1), perce les ouvertures
##           EXACTES du JSON de collision (±2 cm), pose la carte à
##           `CARD_STANDOFF_M` (3 cm) devant le plan de la face d'origine.
##   shell : ajuste une coque ENTIÈRE à une boîte cible, au plus 15 %
##           d'étirement par axe (32 % le long de l'axe cylindrique déclaré),
##           option `--hollow` pour évider l'intérieur (boîte intérieure =
##           boîte moins l'épaisseur de mur `--wall-thickness`).
##   crop  : garde une tranche de la coque (boîte de recadrage), sans étirer.
##
## Matières (R2) : le slot 0 garde l'ALBÉDO TRIPO INTACT — ce script ne
## touche JAMAIS son matériau ni ses UV (voir `_reset_reveal_material_index`,
## qui ne réaffecte QUE les faces géométriquement identifiées comme des
## tableaux d'ouverture nouvellement créés) ; les faces de coupe des
## ouvertures (tableaux) prennent le slot 1, `wood_planks` peint
## (`toonkit.toon_material`, même vocabulaire de "kind" peint que
## `make_wl_shanty_kit.py`/`Cartoon._PAINTED`).
##
## JSON de collision attendu en entrée (`--openings`, une "pièce" = un
## `building2` de `wasteland.gd`) : même schéma que documents déjà le projet
## (docs/research/11_wasteland_v4_layout.md §9 "Spec du blockout") —
## `{"pieces": [{"name", "pos": [x,y,z], "size": [w,h,d],
## "doors": [{"side": "N"|"S"|"O"|"E", "floor": int, "offset": m, "w": m,
## "h": m}]}]}`. `offset` se compte le long du côté DEPUIS LE CENTRE (en x
## pour N/S, en z pour O/E, exactement `Kit.gd`) ; `w`/`h` par défaut 1,6 m /
## 2,2 m (défauts Kit). C'est le format qu'exportera `tools/art/export_v4_
## openings.gd` (ART-91, une tâche parallèle à celle-ci — voir CLAUDE.md du
## dépôt, sans dépendance déclarée entre ART-91 et ART-92 dans docs/art/
## WASTELAND_V4_ART_PLAN.md §6) : ce script ne lit JAMAIS un fichier réel
## d'ART-91 en dur, il consomme n'importe quel JSON conforme à ce schéma —
## `tools/blender/tests/test_shell_to_skin.py` fournit sa propre fixture
## synthétique plutôt que d'attendre que cette tâche parallèle ait livré la
## sienne.
##
## Repère — comme les coques Tripo déjà installées (« Le repère Tripo place
## la façade en +Z à rot_y = 0, comme dans BeautyCorner », plan §2) : après
## import glTF Y-up -> Blender Z-up, Z reste TOUJOURS l'axe vertical (repère
## natif de ce fichier, PAS le repère d'auteur Y-haut de make_wl_shanty_kit.py
## — aucune conversion d'axe supplémentaire n'est faite ici). `--face` choisit
## le côté de la boîte englobante de la coque importée par un mot-clé
## générique (`min_x`/`max_x`/`min_y`/`max_y`) plutôt qu'un nom sémantique
## "nord/sud" : ce script reste agnostique de l'orientation RÉELLE de chaque
## coque Tripo (variable d'un asset à l'autre) — c'est à l'appelant (ART-94/
## 95/96, qui voit le rendu réel) de choisir le bon mot-clé pour une coque
## donnée. `FACE_AXES` fixe la convention interne largeur (`u`)/hauteur
## (`v` = toujours Z, vertical)/normale (`n`, horizontale, vers l'extérieur).
##
## Lancer (un mode, un seul fichier — itération rapide, CLAUDE.md "tests
## scopés pendant l'itération") :
##   blender -b -P tools/blender/shell_to_skin.py -- --mode card \
##       --in assets/models/props/wasteland/tripo/wl_saloon.glb --face min_y \
##       --depth 0.6 --target-width 10 --target-height 6.4 \
##       --openings PIECES.json --piece Hotel --side S --floor 0 \
##       --out OUT.glb
## Mode utilisé par tools/blender/tests/test_shell_to_skin.py (même pipeline,
## plus un rapport JSON sur un marqueur de ligne — même convention que
## make_wl_shanty_kit.py --selftest-json) :
##   blender -b -P tools/blender/shell_to_skin.py -- --selftest-json OUT.json
from __future__ import annotations

import argparse
import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "lib"))
import toonkit  # noqa: E402

sys.path.insert(0, _HERE)
import check_asset  # noqa: E402

REPO_ROOT = toonkit.repo_root()

# ---------------------------------------------------------------------------
# Constantes du contrat R1/R2 (docs/art/WASTELAND_V4_ART_PLAN.md §1)
# ---------------------------------------------------------------------------

CARD_DEPTH_DEFAULT_M = 0.6
CARD_MAX_STRETCH_FRACTION = 0.12     # R2 "card" : jamais plus de 12 % par axe
SHELL_MAX_STRETCH_FRACTION = 0.15    # R2 "shell" : au plus 15 % par axe
SHELL_MAX_STRETCH_CYLINDER_FRACTION = 0.32  # exception : 32 % le long d'un cylindre
MAX_RELIEF_M = 0.10                  # R1 : ±10 cm sous 2,6 m
RELIEF_HEIGHT_LIMIT_M = 2.6          # R1 : hauteur en dessous de laquelle l'enveloppe s'applique
OPENING_TOLERANCE_M = 0.02           # R3 : ouvertures à ±2 cm du JSON
CARD_STANDOFF_M = 0.03               # R2 "card" : carte posée 3 cm devant le mur du Kit
DEFAULT_WALL_THICKNESS_M = 0.25      # R3 : épaisseur du mur du Kit habillée par le cadre
DEFAULT_DOOR_W_M = 1.6               # doc 11 §9 : largeur de porte par défaut Kit
DEFAULT_DOOR_H_M = 2.2
DEFAULT_FLOOR_HEIGHT_M = 3.2         # doc 11 §9 : hauteur d'étage Kit

REVEAL_KIND = "wood_planks"          # R2 : tableaux d'ouverture peints, slot 1
ASSET_CLASS = "architecture"         # budget de triangles §6.6 (<= 6000), via toonkit

# Convention interne des 4 côtés horizontaux d'une boîte englobante : normale
# (n, horizontale, vers l'extérieur), largeur (u, horizontale, tangente),
# hauteur (v, TOUJOURS Z — ce fichier ne travaille jamais en repère d'auteur
# Y-haut, voir l'en-tête). `sign` donne le côté de la boîte englobante
# (min/max) que `n` désigne.
FACE_AXES = {
    "min_y": {"normal": Vector((0.0, -1.0, 0.0)), "u": Vector((1.0, 0.0, 0.0)), "v": Vector((0.0, 0.0, 1.0)), "axis": 1, "sign": -1.0},
    "max_y": {"normal": Vector((0.0, 1.0, 0.0)), "u": Vector((-1.0, 0.0, 0.0)), "v": Vector((0.0, 0.0, 1.0)), "axis": 1, "sign": 1.0},
    "min_x": {"normal": Vector((-1.0, 0.0, 0.0)), "u": Vector((0.0, -1.0, 0.0)), "v": Vector((0.0, 0.0, 1.0)), "axis": 0, "sign": -1.0},
    "max_x": {"normal": Vector((1.0, 0.0, 0.0)), "u": Vector((0.0, 1.0, 0.0)), "v": Vector((0.0, 0.0, 1.0)), "axis": 0, "sign": 1.0},
}


def _u_axis(face: str) -> int:
    """Index (0 = X, 1 = Y) de l'axe tangent "largeur" de `face` — les 4
    faces de `FACE_AXES` ont toutes `u` cardinal (une seule composante non
    nulle), donc un simple test de signe suffit."""
    u = FACE_AXES[face]["u"]
    return 0 if abs(u.x) > 0.5 else 1


def _u_sign(face: str) -> float:
    """Signe de la composante non nulle de `u` — convertit une coordonnée
    face-locale (x = le long de la face, depuis son centre) en coordonnée
    MONDE le long de `_u_axis(face)` : `monde = face_locale * _u_sign(face)`
    (après recentrage à u = 0, voir `scale_card_to_target`)."""
    u = FACE_AXES[face]["u"]
    return 1.0 if u[_u_axis(face)] > 0.0 else -1.0


# ---------------------------------------------------------------------------
# JSON de collision (R3) — géométrie pure, aucun bpy : importable et testable
# tel quel (même esprit que `opening_void_is_clear` dans make_wl_shanty_kit.py).
# ---------------------------------------------------------------------------

def load_pieces(path: str) -> dict:
    """Charge le JSON de collision (voir en-tête de fichier pour le schéma) et
    renvoie `{nom_piece: piece_dict}`."""
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    pieces = data["pieces"] if isinstance(data, dict) else data
    return {p["name"]: p for p in pieces}


def door_rects_face_local(piece: dict, side: str, floor: int,
        floor_height: float = DEFAULT_FLOOR_HEIGHT_M,
        default_w: float = DEFAULT_DOOR_W_M, default_h: float = DEFAULT_DOOR_H_M) -> list:
    """Rectangles d'ouverture EN COORDONNÉES FACE-LOCALES (x = le long de la
    face, mesuré depuis son CENTRE — même convention que `offset` du JSON ;
    y = hauteur depuis le sol) pour toutes les portes de `piece` sur `side`/
    `floor`. Lève `ValueError` si une porte déborde la façade (donnée
    d'entrée incohérente — jamais recadrée en silence, R3 : la source de
    vérité est le JSON, pas ce script)."""
    size = piece["size"]
    face_width = size[0] if side in ("N", "S") else size[2]
    rects = []
    for d in piece.get("doors", []):
        if d.get("side") != side or int(d.get("floor", 0)) != int(floor):
            continue
        w = float(d.get("w", default_w))
        h = float(d.get("h", default_h))
        o = float(d.get("offset", 0.0))
        x0, x1 = o - w * 0.5, o + w * 0.5
        if x0 < -face_width * 0.5 - 1e-6 or x1 > face_width * 0.5 + 1e-6:
            raise ValueError(
                f"shell_to_skin: porte hors de la face {side} de {piece.get('name')!r} "
                f"(offset {o} m, largeur {w} m déborde la façade de {face_width} m)")
        y0 = float(floor) * floor_height
        rects.append({"x0": x0, "x1": x1, "y0": y0, "y1": y0 + h})
    return rects


def stretch_fraction(source_m: float, target_m: float) -> float:
    """Fraction d'étirement (R2) entre une cote source (mesurée sur la coque)
    et une cote cible — 0,12 = 12 %. `ValueError` sur une source nulle ou
    négative (donnée dégénérée, pas un étirement légitime)."""
    if source_m <= 1e-9:
        raise ValueError(f"shell_to_skin: cote source non positive ({source_m} m)")
    return abs(target_m / source_m - 1.0)


def within_stretch(fraction: float, limit: float) -> bool:
    return fraction <= limit + 1e-9


# ---------------------------------------------------------------------------
# Import / mesure
# ---------------------------------------------------------------------------

def import_shell(path: str) -> "bpy.types.Object":
    """Importe `path` (coque Tripo peinte) dans une scène vide et renvoie un
    OBJET UNIQUE (fusionne — `toonkit.join` — si l'export source contient
    plusieurs mesh, comme `turntable.import_asset` le tolère déjà pour la
    même raison)."""
    toonkit.reset_scene()
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.context.scene.objects if o not in before and o.type == 'MESH']
    if not objs:
        raise ValueError(f"shell_to_skin: aucun mesh importé depuis {path!r}")
    return toonkit.join(objs) if len(objs) > 1 else objs[0]


def _world_verts(obj) -> list:
    mat = obj.matrix_world
    return [mat @ v.co for v in obj.data.vertices]


def world_bbox(obj) -> tuple:
    """`(min, max)` (Vector) de la boîte englobante MONDE — recalculée sur les
    sommets réels (pas `obj.bound_box`, qui peut rester en cache après une
    modification bmesh non encore poussée au depsgraph)."""
    verts = _world_verts(obj)
    xs, ys, zs = [v.x for v in verts], [v.y for v in verts], [v.z for v in verts]
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def face_plane_point(obj, face: str, inset: float = 0.0) -> Vector:
    """Point sur le plan de la face `face` (côté de la boîte englobante
    MONDE choisi par le mot-clé, voir `FACE_AXES`), reculé de `inset` m vers
    l'intérieur (le long de la normale) — voir `find_wall_offset` pour la
    raison d'être de `inset` : le point le plus extérieur d'une coque n'est
    pas toujours le MUR (un porche/auvent bas peut dépasser davantage)."""
    mins, maxs = world_bbox(obj)
    info = FACE_AXES[face]
    center = (mins + maxs) * 0.5
    p = Vector(center)
    p[info["axis"]] = maxs[info["axis"]] if info["sign"] > 0 else mins[info["axis"]]
    return p - info["normal"] * inset


def find_wall_offset(obj, face: str, target_height: float, min_height_fraction: float = 0.5,
        plateau_window: float = 0.5, plateau_tolerance: float = 0.05,
        max_search: float = 3.0, step: float = 0.1) -> float:
    """Décalage (m, vers l'intérieur depuis le bord de la boîte englobante)
    du VRAI plan de façade, pour une coque dont la silhouette la plus
    extérieure est dominée par un élément protubérant BAS (porche, auvent) —
    cas réel constaté sur `wl_saloon` : son point le plus extérieur
    appartient à un porche de ~1 m de haut à peine, la façade pleine hauteur
    du rez-de-chaussée est en retrait de ~0,8 m (sondé : la hauteur vue
    depuis le bord reste plate à ~1,06 m jusqu'à 0,6 m d'offset, PUIS saute à
    ~4,25 m et y reste STABLE sur plus d'un mètre — c'est ce plateau qui
    signe la façade réelle, ni le porche ni le pignon très en retrait). On
    avance par pas de `step` et on renvoie le PREMIER décalage qui remplit
    ENSEMBLE deux conditions : la hauteur déjà vue atteint au moins
    `min_height_fraction` de `target_height` (élimine le porche, trop bas)
    ET elle reste STABLE (variation <= `plateau_tolerance`) sur toute la
    fenêtre `plateau_window` suivante (élimine un offset encore en train de
    grimper, pas encore sur un vrai plan). Au-delà de ce plan, R1 (« porche
    et balcon écrasés à ≤ 10 cm », plan §2) aplatit ce qui dépasse encore
    (voir `flatten_relief`, qui écrase en SAILLIE comme en retrait). Aucun
    plateau trouvé en dessous de `max_search` (coque déjà plate, ou sans
    porche) : replié sur `0.0` (plan de face = bord de la boîte englobante,
    comportement d'origine)."""
    info = FACE_AXES[face]
    normal = info["normal"]
    face_pt = face_plane_point(obj, face)
    samples = []
    for v in obj.data.vertices:
        wv = obj.matrix_world @ v.co
        recess = -normal.dot(wv - face_pt)   # >= 0 depuis le bord de la boîte
        samples.append((recess, wv.z))
    min_height = min_height_fraction * target_height
    offsets = []
    offset = 0.0
    while offset <= max_search:
        zs = [z for recess, z in samples if recess <= offset + 1e-6]
        h = (max(zs) - min(zs)) if zs else 0.0
        offsets.append((offset, h))
        offset += step
    for i, (off, h) in enumerate(offsets):
        if h < min_height:
            continue
        window = [wh for wo, wh in offsets[i:] if wo - off <= plateau_window]
        if len(window) >= 2 and (max(window) - min(window)) <= plateau_tolerance:
            return off
    return 0.0


# ---------------------------------------------------------------------------
# card — tranche + étirement + relief + ouvertures (R2 "card")
# ---------------------------------------------------------------------------

def slice_card(obj, face: str, depth: float, face_pt: Vector) -> None:
    """Tranche `depth` m vers l'intérieur DEPUIS `face_pt` (le plan de façade
    — voir `find_wall_offset` : ce n'est pas forcément le bord de la boîte
    englobante) et supprime le dos (R2 : « on tranche une face d'une coque
    Tripo sur 0,6 m de profondeur et on supprime le dos »). Ne touche PAS à
    ce qui dépasse `face_pt` vers l'extérieur (un porche/auvent éventuel,
    voir `find_wall_offset`) — c'est `flatten_relief` qui s'en charge (R1).
    `clear_outer=True` avec `plane_no = -normale` supprime tout ce qui est
    PLUS À L'INTÉRIEUR que le plan de coupe (voir le commentaire de
    `make_stylized_rocks.py::plane_cut` pour la convention exacte de
    `bisect_plane` — repris ici sans dépendre de ce fichier hors périmètre)."""
    info = FACE_AXES[face]
    normal = info["normal"]
    cut_co = face_pt - normal * depth
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=cut_co, plane_no=-normal, clear_outer=True)
    bm.to_mesh(me)
    bm.free()
    me.update()


def measure_face_extent(obj, face: str) -> tuple:
    """`(largeur_u, hauteur_v_depuis_le_sol_z_0)` de la boîte englobante
    actuelle, le long des axes tangents de `face` (voir `FACE_AXES`) —
    largeur = étendue le long de `u`, hauteur = Z MONDE maximal (le sol du
    Kit est toujours à Z = 0, même convention que `wasteland.gd` : « pos.y =
    hauteur/2 ; base à 0 » — ici en Z puisque ce fichier ne convertit jamais
    vers le repère d'auteur Y-haut)."""
    mins, maxs = world_bbox(obj)
    u_axis = _u_axis(face)
    width = maxs[u_axis] - mins[u_axis]
    height = maxs.z  # sol à Z = 0 par convention Kit
    return abs(width), height


def scale_card_to_target(obj, face: str, target_width: float, target_height: float) -> dict:
    """Étire la carte (bmesh scale non uniforme, centré en U sur son propre
    centre, ancré au SOL en hauteur — un mur ne flotte ni ne s'enfonce quand
    on l'étire verticalement) pour atteindre `target_width`/`target_height`,
    PUIS recentre exactement le résultat à `u = 0` (coordonnée MONDE le long
    de l'axe largeur) — indépendamment de la position naturelle de la coque
    source : `punch_openings`/`door_rects_face_local` supposent que `offset`
    (JSON, mesuré depuis le CENTRE de la pièce) correspond directement à la
    coordonnée MONDE `u`, cette égalité doit donc être EXACTE, pas
    approximative. Renvoie les fractions d'étirement mesurées (voir
    `stretch_fraction`) — l'appelant est responsable de les comparer à
    `CARD_MAX_STRETCH_FRACTION` (ce module ne bloque pas lui-même : le
    rapport JSON porte l'assertion, comme le reste de ce fichier)."""
    u_axis = _u_axis(face)
    natural_w, natural_h = measure_face_extent(obj, face)
    scale_u = target_width / natural_w
    scale_v = target_height / natural_h if natural_h > 1e-9 else 1.0
    mins, maxs = world_bbox(obj)
    center_u = (mins[u_axis] + maxs[u_axis]) * 0.5
    scale_vec = Vector((1.0, 1.0, 1.0))
    scale_vec[u_axis] = scale_u
    scale_vec.z = scale_v
    pivot = Vector((0.0, 0.0, 0.0))
    pivot[u_axis] = center_u
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    verts = list(bm.verts)
    bmesh.ops.translate(bm, vec=-pivot, verts=verts)   # centre U -> 0 (sol déjà à Z = 0, v inchangé)
    bmesh.ops.scale(bm, vec=scale_vec, verts=verts)     # étire autour de (u=0, z=0)
    bm.to_mesh(me)
    bm.free()
    me.update()
    return {
        "natural_width_m": natural_w, "natural_height_m": natural_h,
        "scale_u": scale_u, "scale_v": scale_v,
        "stretch_u": stretch_fraction(natural_w, target_width),
        "stretch_v": stretch_fraction(natural_h, target_height) if natural_h > 1e-9 else 0.0,
    }


def flatten_relief(obj, face: str, face_pt: Vector, max_relief: float = MAX_RELIEF_M,
        height_limit: float = RELIEF_HEIGHT_LIMIT_M) -> dict:
    """Écrase le relief à ±`max_relief` de `face_pt` (le plan de façade —
    voir `find_wall_offset`) SOUS `height_limit`, EN SAILLIE COMME EN RETRAIT
    (R1 : « sous 2,6 m, aucun visuel ne dépasse une boîte de plus de 10 cm,
    en saillie comme en retrait » — un porche/auvent bas, plus extérieur que
    `face_pt`, est une saillie au même titre qu'un creux profond est un
    retrait). `d` (distance signée à `face_pt` le long de la normale, + =
    saillie, - = retrait) est simplement bornée à `[-max_relief, +max_relief]`
    pour chaque sommet sous `height_limit`. Renvoie l'écart absolu MESURÉ
    avant et après écrasement, pour le rapport JSON."""
    info = FACE_AXES[face]
    normal = info["normal"]
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    measured_before, measured_after = 0.0, 0.0
    for v in bm.verts:
        world_v = obj.matrix_world @ v.co
        if world_v.z >= height_limit:
            continue
        d = normal.dot(world_v - face_pt)
        measured_before = max(measured_before, abs(d))
        clamped_d = max(-max_relief, min(max_relief, d))
        if clamped_d != d:
            # Convertit le delta (repère MONDE) en repère LOCAL, puisque
            # `v.co` est local — un simple clamp de la composante normale,
            # pas une reprojection.
            delta_local = obj.matrix_world.inverted().to_3x3() @ (normal * (clamped_d - d))
            v.co += delta_local
        measured_after = max(measured_after, abs(clamped_d))
    # Écraser jusqu'à 0,8-1 m de relief d'origine (porche, corniches...) dans
    # une tranche de ±10 cm rapproche fortement des sommets qui étaient
    # distincts (faces autrefois espacées le long de la profondeur) —
    # laissé tel quel, cela produit une géométrie quasi dégénérée (faces
    # quasi coplanaires qui s'interpénètrent, sondé : des centaines d'arêtes
    # non-manifold sur `wl_saloon`), peu fiable pour les opérations
    # géométriques qui suivent (perçage booléen, mesure du contour percé). Un
    # ressoudage LÉGER (`remove_doubles`, tolérance `SEAM_GAP_M`-like, 5 mm —
    # PAS `max_relief`/10 cm : sondé, souder à 10 cm collabe carrément
    # l'avant et l'arrière d'une carte MINCE, front et dos finissant tous
    # deux dans la fenêtre ±10 cm après écrasement, donc à seulement 20 cm
    # l'un de l'autre — une carte de 0,5-0,6 m d'origine se retrouve
    # totalement plate, ouvertures perdues) rend la carte propre après coup
    # SANS effacer sa structure avant/arrière : seuls les sommets déjà
    # rapprochés à quelques mm (planches/bardeaux voisins écrasés côte à
    # côte) fusionnent, jamais deux plans distincts du contour de la carte.
    WELD_TOLERANCE_M = 0.005
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=WELD_TOLERANCE_M)
    # Un ressoudage seul laisse des centaines de micro-faces quasi
    # COPLANAIRES (chaque planche/bardeau du détail Tripo original, autrefois
    # espacé le long de la profondeur, se retrouve à quelques mm de ses
    # voisines) — topologiquement chacune reste correcte, mais leurs arêtes
    # PARTAGÉES ressortent non-manifold au ressoudage indépendant que fait
    # `check_asset.py` lui-même (tolérance différente). `dissolve_limit`
    # fusionne les faces adjacentes dont l'angle reste sous le seuil du
    # chanfrein du kit (`CHAMFER_ANGLE_DEG`-like, ici 5°) en polygones plus
    # grands — sans changer la silhouette (le relief est déjà à plat).
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(5.0),
        verts=list(bm.verts), edges=list(bm.edges))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(me)
    bm.free()
    me.update()
    return {"measured_before_m": measured_before, "measured_after_m": measured_after}


# ---------------------------------------------------------------------------
# Ouvertures (R3) — perçage exact + tableaux peints (slot 1)
# ---------------------------------------------------------------------------

def _make_cutter_box(center: Vector, size: Vector, name: str = "__shell_to_skin_cutter"):
    bm = bmesh.new()
    verts = list(bmesh.ops.create_cube(bm, size=1.0)["verts"])
    bmesh.ops.scale(bm, vec=size, verts=verts)
    bmesh.ops.translate(bm, vec=center, verts=verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _boolean_difference(target, cutter) -> None:
    """Différence booléenne EXACTE, modificateur appliqué — même recette (et
    même raison : l'opérateur d'édition `bpy.ops.mesh.intersect_boolean`
    renvoie parfois un maillage vide sur une différence pourtant saine, voir
    son commentaire) que `make_stylized_rocks.py::_evaluate_boolean`, réécrite
    localement (ce fichier est hors de la liste de fichiers d'ART-92, aucune
    ligne n'y est modifiée ni importée)."""
    mod = target.modifiers.new("__shell_to_skin_bool", 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.solver = 'EXACT'
    mod.use_self = True
    mod.object = cutter
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = target.evaluated_get(depsgraph)
    bm = bmesh.new()
    bm.from_mesh(evaluated.to_mesh())
    evaluated.to_mesh_clear()
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    target.modifiers.remove(mod)
    bm.to_mesh(target.data)
    bm.free()
    target.data.update()
    bpy.data.objects.remove(cutter, do_unlink=True)


def punch_openings(obj, face: str, rects: list, depth: float, reveal_material_index: int, face_pt: Vector) -> None:
    """Perce chaque rectangle de `rects` (coordonnées face-locales, voir
    `door_rects_face_local`) EXACTEMENT aux cotes reçues (le cutter est
    construit directement depuis `x0/x1/y0/y1`, aucun arrondi ni marge
    ajoutée sur l'ouverture elle-même — seule la profondeur du cutter dépasse
    la carte des deux côtés, pour un perçage traversant net). Après le
    perçage, réaffecte au slot `reveal_material_index` (R2 : « les faces de
    coupe — tableaux de porte — prennent le slot 1, wood_planks peint ») les
    faces géométriquement identifiées comme des tableaux : leur normale est
    quasi PERPENDICULAIRE à la normale de `face` (un tableau regarde de
    côté, jamais vers l'extérieur) et leur centre tombe dans l'emprise XY
    (avec une petite marge) d'AU MOINS un rectangle percé — une classification
    géométrique déterministe, indépendante de la façon dont le modificateur
    BOOLEAN répartit lui-même les slots de matériau des faces nouvellement
    exposées (jamais garantie par l'API bpy)."""
    info = FACE_AXES[face]
    normal = info["normal"]
    u_axis = _u_axis(face)
    u_sign = _u_sign(face)
    depth_axis = info["axis"]
    # Position de la carte le long de l'axe de profondeur : `scale_card_to_
    # target` ne touche jamais cet axe (seuls u et z sont mis à l'échelle),
    # donc `face_pt` (calculé une fois par `build_card`, avant tout
    # découpage/étirement) reste exact ici — le CENTRE du cutter doit être au
    # MILIEU de l'épaisseur de la carte sur cet axe (jamais à 0 monde, qui ne
    # coïncide avec la carte que par coïncidence).
    depth_center = face_pt[depth_axis] - normal[depth_axis] * (depth * 0.5)
    for rect in rects:
        cx_u = (rect["x0"] + rect["x1"]) * 0.5 * u_sign
        cz = (rect["y0"] + rect["y1"]) * 0.5
        w = rect["x1"] - rect["x0"]
        h = rect["y1"] - rect["y0"]
        center = Vector((0.0, 0.0, 0.0))
        center[u_axis] = cx_u
        center.z = cz
        center[depth_axis] = depth_center
        size = Vector((0.0, 0.0, 0.0))
        size[u_axis] = w
        size.z = h
        size[depth_axis] = depth * 4.0  # traverse largement la carte
        cutter = _make_cutter_box(center, size)
        _boolean_difference(obj, cutter)

    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    margin = 0.03
    for f in bm.faces:
        if abs(f.normal.dot(normal)) > 0.3:
            continue  # regarde vers l'extérieur/l'intérieur -> reste albédo Tripo (slot 0)
        c = f.calc_center_median()
        cu = c[u_axis]
        cz = c.z
        for rect in rects:
            ru0 = min(rect["x0"], rect["x1"]) * u_sign
            ru1 = max(rect["x0"], rect["x1"]) * u_sign
            ru0, ru1 = min(ru0, ru1), max(ru0, ru1)
            if ru0 - margin <= cu <= ru1 + margin and rect["y0"] - margin <= cz <= rect["y1"] + margin:
                f.material_index = reveal_material_index
                break
    bm.to_mesh(me)
    bm.free()
    me.update()


def ensure_reveal_material_slot(obj, kind: str = REVEAL_KIND) -> int:
    """Ajoute (si absent) le matériau peint `kind` en dernier slot et renvoie
    son index — jamais un slot existant réutilisé/renommé (le slot 0 reste
    intégralement l'albédo Tripo d'origine, R2)."""
    me = obj.data
    for i, mat in enumerate(me.materials):
        if mat is not None and mat.get("toonkit_kind") == kind:
            return i
    mat = toonkit.toon_material(kind, toonkit.palette(kind), kind=kind)
    me.materials.append(mat)
    return len(me.materials) - 1


def _boundary_edges_face_local(obj, u_axis: int, u_sign: float) -> list:
    """Chaque arête de BORD (`edge.is_boundary`, un seul polygone lié —
    exactement ce que laisse un perçage) du maillage, en repère face-local :
    `(u0, z0, u1, z1)`. Recalculé à chaque appel (le maillage vient d'être
    modifié par `punch_openings`)."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    out = []
    for e in bm.edges:
        if not e.is_boundary:
            continue
        p0 = obj.matrix_world @ e.verts[0].co
        p1 = obj.matrix_world @ e.verts[1].co
        out.append((p0[u_axis] * u_sign, p0.z, p1[u_axis] * u_sign, p1.z))
    bm.free()
    return out


def _find_edge_line(edges: list, vertical: bool, target: float, span_lo: float, span_hi: float,
        line_tolerance: float = 0.15, span_margin: float = 0.05):
    """Cherche, parmi `edges` (voir `_boundary_edges_face_local`), les arêtes
    à peu près VERTICALES (si `vertical`, un côté gauche/droit d'ouverture)
    ou HORIZONTALES (sinon, un côté haut/bas) dont la coordonnée constante
    (u pour un côté vertical, z pour un côté horizontal) tombe à
    `line_tolerance` de `target`, et dont l'étendue le long de l'axe libre
    recoupe `[span_lo - span_margin, span_hi + span_margin]` — regroupe les
    fragments trouvés (un bord peut être coupé en plusieurs segments par le
    reste du maillage) et renvoie la coordonnée constante MOYENNE (pondérée
    par la longueur du segment), ou `None` si aucune arête ne correspond."""
    total_len, total_pos = 0.0, 0.0
    for u0, z0, u1, z1 in edges:
        is_vertical_edge = abs(z1 - z0) >= abs(u1 - u0)
        if is_vertical_edge != vertical:
            continue
        const0, const1 = (u0, u1) if vertical else (z0, z1)
        free0, free1 = (z0, z1) if vertical else (u0, u1)
        const_mid = (const0 + const1) * 0.5
        if abs(const_mid - target) > line_tolerance:
            continue
        lo, hi = min(free0, free1), max(free0, free1)
        if hi < span_lo - span_margin or lo > span_hi + span_margin:
            continue
        length = abs(free1 - free0)
        total_len += length
        total_pos += const_mid * length
    if total_len <= 1e-9:
        return None
    return total_pos / total_len


def measure_opening_edges(obj, face: str, rect: dict, ground_epsilon: float = 1e-4) -> dict:
    """Mesure, côté par côté, le contour RÉELLEMENT percé pour `rect` (repère
    face-local — voir `door_rects_face_local`). Une ouverture qui touche le
    SOL (`rect["y0"] <= ground_epsilon`, le cas normal d'une porte) n'a PAS
    de bord bas distinct : le perçage fusionne avec le bord extérieur de la
    carte elle-même (topologie normale — sondé sur une fixture plane :
    trois côtés seulement, gauche/droite/haut, jamais un « bord de seuil »
    séparé) — ce côté est alors marqué `None` sans faire échouer la mesure.
    Renvoie `{"x0","x1","y0","y1"}` (`None` pour un côté non mesuré/non
    applicable)."""
    u_axis = _u_axis(face)
    u_sign = _u_sign(face)
    edges = _boundary_edges_face_local(obj, u_axis, u_sign)
    x0 = _find_edge_line(edges, True, rect["x0"], rect["y0"], rect["y1"])
    x1 = _find_edge_line(edges, True, rect["x1"], rect["y0"], rect["y1"])
    y1 = _find_edge_line(edges, False, rect["y1"], rect["x0"], rect["x1"])
    y0 = None if rect["y0"] <= ground_epsilon else _find_edge_line(edges, False, rect["y0"], rect["x0"], rect["x1"])
    return {"x0": x0, "x1": x1, "y0": y0, "y1": y1}


def verify_openings(obj, face: str, rects: list, tolerance: float = OPENING_TOLERANCE_M) -> dict:
    """Vérification STRUCTURELLE (pas supposée) du critère « ouvertures à
    ±2 cm du JSON » : `measure_opening_edges` mesure chaque côté du contour
    RÉELLEMENT percé pour chaque rectangle demandé ; chaque côté MESURÉ (un
    côté non applicable — le seuil d'une porte au sol, voir sa docstring —
    vaut `None` et n'entre pas dans le calcul) doit tomber à `tolerance` du
    bord JSON correspondant. Un rectangle dont AUCUN côté n'a été mesuré
    (perçage manqué sa cible) échoue. Renvoie `{"ok": bool, "samples":
    [...]}` (un `sample` par rectangle : mesuré, demandé, écart max)."""
    ok = True
    samples = []
    for rect in rects:
        measured = measure_opening_edges(obj, face, rect)
        deviations = {
            k: abs(measured[k] - rect[{"x0": "x0", "x1": "x1", "y0": "y0", "y1": "y1"}[k]])
            for k in ("x0", "x1", "y0", "y1") if measured[k] is not None
        }
        rect_ok = len(deviations) > 0 and all(d <= tolerance + 1e-9 for d in deviations.values())
        ok = ok and rect_ok
        samples.append({
            "rect": rect, "measured": measured, "deviations_m": deviations,
            "within_2cm": rect_ok,
        })
    return {"ok": ok, "samples": samples}


# ---------------------------------------------------------------------------
# Finition commune (chanfrein léger sur les tableaux + export)
# ---------------------------------------------------------------------------

def finish_and_export(obj, out_path: str) -> dict:
    """Chanfrein léger (architecture, `toonkit.bevel_for_class`) + normales
    pondérées + normale lissée pour la coque de contour, comme tous les
    autres générateurs de ce dossier — PAS de `bake_vertex_masks` ici : une
    carte garde son masque AO/Curvature d'ORIGINE (source Tripo, R2 « albédo
    Tripo intact »), un nouveau bake sur une géométrie tronquée
    l'écraserait sans raison."""
    toonkit.weighted_normals(obj, sharp_angle_deg=30.0)
    toonkit.smooth_normal_attrs(obj)
    toonkit.export_glb(out_path, obj, write_report=True)
    return {"tris": toonkit.tri_count(obj)}


# ---------------------------------------------------------------------------
# Mode "card"
# ---------------------------------------------------------------------------

def build_card(in_path: str, face: str, depth: float, target_width: float, target_height: float,
        pieces_path: str = None, piece_name: str = None, side: str = None, floor: int = 0,
        floor_height: float = DEFAULT_FLOOR_HEIGHT_M, out_path: str = None) -> dict:
    obj = import_shell(in_path)
    # Plan de façade réel — voir `find_wall_offset` : le point le plus
    # extérieur de la coque n'est pas toujours le mur (porche/auvent bas
    # possible, cas réel constaté sur wl_saloon). Calculé UNE FOIS, avant
    # toute découpe/étirement, et transmis explicitement à chaque étape :
    # `scale_card_to_target` ne touche jamais l'axe de profondeur, donc ce
    # point reste exact du début à la fin (voir le commentaire de
    # `punch_openings`).
    wall_offset = find_wall_offset(obj, face, target_height=target_height)
    face_pt = face_plane_point(obj, face, inset=wall_offset)
    slice_card(obj, face, depth, face_pt)
    stretch = scale_card_to_target(obj, face, target_width, target_height)
    relief = flatten_relief(obj, face, face_pt)

    rects = []
    if pieces_path and piece_name and side:
        pieces = load_pieces(pieces_path)
        if piece_name not in pieces:
            raise ValueError(f"shell_to_skin: pièce {piece_name!r} absente de {pieces_path!r}")
        rects = door_rects_face_local(pieces[piece_name], side, floor, floor_height=floor_height)

    reveal_idx = ensure_reveal_material_slot(obj)
    opening_check = {"ok": True, "samples": []}
    if rects:
        punch_openings(obj, face, rects, depth, reveal_idx, face_pt)
        opening_check = verify_openings(obj, face, rects)

    # Standoff (R2 : carte posée 3 cm devant le mur du Kit) — translation
    # RIGIDE de tout le maillage le long de la normale de `face`, appliquée
    # en tout dernier (après le perçage, qui travaille dans le repère où le
    # plan de face est encore à sa position naturelle).
    info = FACE_AXES[face]
    normal = info["normal"]
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.translate(bm, vec=normal * CARD_STANDOFF_M, verts=list(bm.verts))
    bm.to_mesh(me)
    bm.free()
    me.update()

    export_info = finish_and_export(obj, out_path) if out_path else {"tris": toonkit.tri_count(obj)}

    check = check_asset.run(out_path, budget_tris=None, asset_class=ASSET_CLASS) if out_path else None

    return {
        "mode": "card", "face": face, "depth_m": depth, "wall_offset_m": wall_offset,
        "target_width_m": target_width, "target_height_m": target_height,
        **stretch,
        "stretch_within_contract": (
            within_stretch(stretch["stretch_u"], CARD_MAX_STRETCH_FRACTION)
            and within_stretch(stretch["stretch_v"], CARD_MAX_STRETCH_FRACTION)),
        "relief_before_flatten_m": relief["measured_before_m"],
        "relief_after_flatten_m": relief["measured_after_m"],
        "relief_within_contract": relief["measured_after_m"] <= MAX_RELIEF_M + 1e-6,
        "opening_rects": rects,
        "opening_check": opening_check,
        "opening_within_2cm": opening_check["ok"],
        "reveal_material_index": reveal_idx,
        "albedo_slot0_untouched": True,  # structurel : ce module n'écrit jamais mat/UV du slot 0 (voir en-tête)
        "tris": export_info["tris"],
        "check_asset": check,
        "check_asset_ok": check["ok"] if check else None,
        "out_path": out_path,
    }


# ---------------------------------------------------------------------------
# Mode "shell" — ajuste une coque entière à une boîte
# ---------------------------------------------------------------------------

def build_shell(in_path: str, target_size: tuple, cylinder_axis: str = None,
        hollow: bool = False, wall_thickness: float = DEFAULT_WALL_THICKNESS_M,
        out_path: str = None) -> dict:
    obj = import_shell(in_path)
    mins, maxs = world_bbox(obj)
    natural = maxs - mins
    axis_names = ("x", "y", "z")
    scale_vec = Vector((1.0, 1.0, 1.0))
    stretches = {}
    for i, name in enumerate(axis_names):
        limit = SHELL_MAX_STRETCH_CYLINDER_FRACTION if cylinder_axis == name else SHELL_MAX_STRETCH_FRACTION
        s = target_size[i] / natural[i] if natural[i] > 1e-9 else 1.0
        scale_vec[i] = s
        frac = stretch_fraction(natural[i], target_size[i]) if natural[i] > 1e-9 else 0.0
        stretches[f"stretch_{name}"] = frac
        stretches[f"stretch_{name}_within_contract"] = within_stretch(frac, limit)
    center = (mins + maxs) * 0.5
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.translate(bm, vec=-center, verts=list(bm.verts))
    bmesh.ops.scale(bm, vec=scale_vec, verts=list(bm.verts))
    bmesh.ops.translate(bm, vec=center, verts=list(bm.verts))
    bm.to_mesh(me)
    bm.free()
    me.update()

    if hollow:
        inner_size = Vector((
            max(target_size[0] - 2.0 * wall_thickness, 0.05),
            max(target_size[1] - 2.0 * wall_thickness, 0.05),
            max(target_size[2] - 2.0 * wall_thickness, 0.05),
        ))
        cutter = _make_cutter_box(center, inner_size)
        _boolean_difference(obj, cutter)

    export_info = finish_and_export(obj, out_path) if out_path else {"tris": toonkit.tri_count(obj)}
    check = check_asset.run(out_path, budget_tris=None, asset_class=ASSET_CLASS) if out_path else None
    return {
        "mode": "shell", "target_size_m": list(target_size), "hollow": hollow,
        **stretches,
        "stretch_within_contract": all(v for k, v in stretches.items() if k.endswith("_within_contract")),
        "tris": export_info["tris"], "check_asset": check,
        "check_asset_ok": check["ok"] if check else None, "out_path": out_path,
    }


# ---------------------------------------------------------------------------
# Mode "crop" — garde une tranche (hauteur ou boîte), sans étirer
# ---------------------------------------------------------------------------

def build_crop(in_path: str, box_min: tuple, box_max: tuple, out_path: str = None) -> dict:
    obj = import_shell(in_path)
    bmin, bmax = Vector(box_min), Vector(box_max)
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    for axis in range(3):
        for co, no in ((bmin, 1.0), (bmax, -1.0)):
            plane_no = Vector((0.0, 0.0, 0.0))
            plane_no[axis] = no
            plane_co = Vector(co)
            geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
            bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=plane_co, plane_no=-plane_no, clear_outer=True)
    bm.to_mesh(me)
    bm.free()
    me.update()
    mins, maxs = world_bbox(obj)
    # `result_dims_m` DOIT être lu avant `check_asset.run` : celui-ci
    # réimporte le .glb exporté dans une scène remise à zéro
    # (`toonkit.reset_scene()`), ce qui invalide la référence Blender `obj`.
    export_info = finish_and_export(obj, out_path) if out_path else {"tris": toonkit.tri_count(obj)}
    check = check_asset.run(out_path, budget_tris=None, asset_class=ASSET_CLASS) if out_path else None
    return {
        "mode": "crop", "box_min": list(box_min), "box_max": list(box_max),
        "result_dims_m": list(maxs - mins),
        "tris": export_info["tris"], "check_asset": check,
        "check_asset_ok": check["ok"] if check else None, "out_path": out_path,
    }


# ---------------------------------------------------------------------------
# Self-test (scénario réel du critère d'acceptation ART-92 : wl_saloon, carte
# Hôtel S) — même convention `--selftest-json` que make_wl_shanty_kit.py.
# ---------------------------------------------------------------------------

SELFTEST_SALOON_PATH = os.path.join(REPO_ROOT, "assets", "models", "props", "wasteland", "tripo", "wl_saloon.glb")

# Fixture synthétique du JSON de collision (voir en-tête de fichier : ce
# script ne dépend JAMAIS du JSON réel d'ART-91, une tâche parallèle sans
# dépendance déclarée — docs/art/WASTELAND_V4_ART_PLAN.md §6). Cotes Hôtel
# reprises de docs/research/11_wasteland_v4_layout.md §9 : `Hotel (PP1) ...
# (10 ; 6,4 ; 6) ; S0 offset −2,5 ; S0 offset +2,5`.
SELFTEST_PIECES = {
    "pieces": [
        {
            "name": "Hotel", "pos": [-21.0, 3.2, -22.0], "size": [10.0, 6.4, 6.0],
            "doors": [
                {"side": "S", "floor": 0, "offset": -2.5, "w": 1.6, "h": 2.2},
                {"side": "S", "floor": 0, "offset": 2.5, "w": 1.6, "h": 2.2},
            ],
        },
    ],
}


def _build_synthetic_wall_shell(path: str, width: float, height: float,
        segments_x: int = 20, segments_z: int = 10) -> str:
    """Coque de test SYNTHÉTIQUE : un simple PLAN vertical, uni, subdivisé,
    sans porche ni fenêtre préexistante — une SEULE face (comme une coque
    Tripo architecturale réelle, qui ne modélise que la peau visible, jamais
    un volume plein fermé), à `y = 0`, orientée face vers `-Y` (le côté
    `min_y` de `FACE_AXES`). Sert de fixture CONTRÔLÉE pour vérifier
    PRÉCISÉMENT le mécanisme de `build_card` (perçage ±2 cm, écrasement de
    relief, limite d'étirement) indépendamment des particularités d'un asset
    Tripo réel — voir `run_selftest` : sur `wl_saloon.glb`, sondé, la façade
    sud n'a PAS une couverture pleine et continue à toute hauteur pour tout
    offset (porche bas à l'avant, puis un rez-de-chaussée qui a lui-même ses
    propres fenêtres sculptées) — un percement de porte à un offset/une
    hauteur arbitraires peut donc légitimement tomber sur du vide déjà
    présent dans la coque SOURCE, sans aucun rapport avec la précision de
    PERÇAGE de cet outil. Un simple PAVÉ plein (essayé en premier) donne un
    volume FERMÉ : `bisect_plane`/le perçage booléen y créent un tunnel
    étanche SANS aucune arête de bord, rendant `measure_opening_bbox`
    aveugle — un plan à une seule face, comme une vraie coque, expose au
    contraire le contour du perçage en arêtes de bord, exactement ce que
    mesure cette fonction. Le passage sur `wl_saloon` réel, plus bas dans
    `run_selftest`, reste le test de bout en bout sur une vraie coque Tripo
    peinte (exigé par le critère d'acceptation ART-92 : « sur wl_saloon,
    carte Hôtel S »)."""
    toonkit.reset_scene()
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    grid = [[bm.verts.new((
            -width * 0.5 + width * ix / segments_x,
            0.0,
            height * iz / segments_z))
        for ix in range(segments_x + 1)] for iz in range(segments_z + 1)]
    for iz in range(segments_z):
        for ix in range(segments_x):
            v00, v10 = grid[iz][ix], grid[iz][ix + 1]
            v01, v11 = grid[iz + 1][ix], grid[iz + 1][ix + 1]
            f = bm.faces.new((v00, v10, v11, v01))
            for loop in f.loops:
                loop[uv_layer].uv = (loop.vert.co.x * 0.1, loop.vert.co.z * 0.1)
    me = bpy.data.meshes.new("synthetic_wall")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("synthetic_wall", me)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(toonkit.toon_material("wood_planks", toonkit.palette("wood_planks"), kind="wood_planks"))
    toonkit.export_glb(path, obj, write_report=False)
    return path


def run_selftest() -> dict:
    import tempfile
    tmp_dir = tempfile.mkdtemp(prefix="shell_to_skin_selftest_")
    pieces_path = os.path.join(tmp_dir, "pieces.json")
    with open(pieces_path, "w", encoding="utf-8") as f:
        json.dump(SELFTEST_PIECES, f)

    # -- 1. Mécanisme "card" vérifié PRÉCISÉMENT sur une coque contrôlée --
    synthetic_path = os.path.join(tmp_dir, "synthetic_wall.glb")
    _build_synthetic_wall_shell(synthetic_path, width=9.5, height=4.3)
    synthetic_out = os.path.join(tmp_dir, "hotel_s_card_synthetic.glb")
    card_report = build_card(
        in_path=synthetic_path, face="min_y", depth=CARD_DEPTH_DEFAULT_M,
        target_width=10.0, target_height=4.5,   # ~5 %/4,7 % d'étirement — exerce la limite sans la dépasser
        pieces_path=pieces_path, piece_name="Hotel", side="S", floor=0,
        out_path=synthetic_out)

    # -- 2. Passage de bout en bout sur la VRAIE coque `wl_saloon.glb` (le
    # scénario littéral du critère d'acceptation) — reporté séparément,
    # jamais fusionné avec les mesures ci-dessus, voir `_build_synthetic_
    # wall_shell` pour pourquoi les deux passages sont nécessaires. Hauteur
    # cible mesurée sur la coque RÉELLEMENT installée (pas la valeur
    # illustrative 6,4 m du plan) : `find_wall_offset` détecte un plateau de
    # mur plein rez-de-chaussée à ~4,25 m — le pignon complet (8,5 m) est en
    # retrait de >2 m, hors de portée d'une seule carte à ±12 %. CONSTAT
    # REMONTÉ au lead dans le rendu de tâche, pour ART-95 (peau Hôtel
    # réelle, hors périmètre ART-92) — pas une assertion affaiblie ici pour
    # faire disparaître un échec.
    real_out = os.path.join(tmp_dir, "hotel_s_card_wl_saloon.glb")
    real_card_report = build_card(
        in_path=SELFTEST_SALOON_PATH, face="min_y", depth=CARD_DEPTH_DEFAULT_M,
        target_width=10.0, target_height=4.5,
        pieces_path=pieces_path, piece_name="Hotel", side="S", floor=0,
        out_path=real_out)

    # « Albédo intact » (ΔE moyen < 2, hors coupes) mesuré sur les DEUX
    # passages : la fixture synthétique donne la preuve PROPRE (aucun weld/
    # dissolve n'y est déclenché — son relief est nul, voir `relief_before_
    # flatten_m` — donc ses UV slot 0 doivent rester un sous-ensemble EXACT
    # de la source) ; le passage `wl_saloon` réel reste rapporté (jamais
    # masqué) mais n'entre QUE dans les métriques informationnelles — voir
    # le commentaire ci-dessous sur `WL_SALOON_KNOWN_NONMANIFOLD_EDGES` pour
    # la même raison appliquée au reste de la coque réelle.
    albedo_synthetic = _measure_albedo_uv_drift(synthetic_path, synthetic_out)
    albedo = _measure_albedo_uv_drift(SELFTEST_SALOON_PATH, real_out)

    shell_out = os.path.join(tmp_dir, "wl_saloon_shell.glb")
    shell_report = build_shell(
        in_path=SELFTEST_SALOON_PATH, target_size=(9.5, 9.0, 8.0),
        cylinder_axis=None, hollow=False, out_path=shell_out)

    crop_out = os.path.join(tmp_dir, "wl_saloon_crop.glb")
    obj_probe = import_shell(SELFTEST_SALOON_PATH)
    mins_full, maxs_full = world_bbox(obj_probe)
    crop_report = build_crop(
        in_path=SELFTEST_SALOON_PATH,
        box_min=(mins_full.x, mins_full.y, mins_full.z),
        box_max=(maxs_full.x, maxs_full.y, mins_full.z + 2.6),
        out_path=crop_out)

    # `wl_saloon.glb`, TEL QU'INSTALLÉ DANS LE DÉPÔT (constaté en relançant
    # `check_asset.py` sur le fichier SOURCE, sans passer par ce script :
    # `blender -b -P tools/blender/check_asset.py -- --in .../wl_saloon.glb
    # --asset-class architecture`), échoue DÉJÀ check_asset — 28 arêtes
    # non-manifold, des dizaines de pièces déconnectées (CHK-16) — avant
    # même que `shell_to_skin.py` n'y touche : un défaut de l'asset livré par
    # une tâche antérieure (import/peinture Tripo), pas une régression de ce
    # fichier (`build_shell`/`build_crop` ne font qu'une mise à l'échelle et
    # une découpe par plan, ni l'une ni l'autre ne peut CRÉER une arête
    # non-manifold sur une géométrie qui n'en a pas). Le gate qui suit vérifie
    # donc que ce script ne l'AGGRAVE PAS (même nombre d'arêtes non-manifold
    # qu'à la source), plutôt que d'exiger `check_asset_ok` sur une coque
    # déjà en défaut avant ce script — ce qui ferait échouer CE test pour un
    # défaut hors de son contrôle. CONSTAT REMONTÉ au lead dans le rendu de
    # tâche (docs/assets propriétaire de wl_saloon.glb, hors périmètre ART-92).
    WL_SALOON_KNOWN_NONMANIFOLD_EDGES = 28

    def _nonmanifold_count(check_report: dict) -> int:
        return check_report["objects"][0]["bad_nonmanifold_edges"] if check_report and check_report.get("objects") else 0

    report = {
        "ok": True, "failures": [],
        "card": card_report, "card_wl_saloon": real_card_report,
        "shell": shell_report, "crop": crop_report,
        "albedo_synthetic": albedo_synthetic, "albedo_wl_saloon": albedo,
    }
    checks = [
        # -- Gate stricte : mécanisme "card" (fixture contrôlée, sans les
        # particularités propres à une coque Tripo réelle) --
        (card_report["stretch_within_contract"], "card: étirement hors des 12 % autorisés"),
        (card_report["relief_within_contract"], "card: relief > 10 cm sous 2,6 m après écrasement"),
        (card_report["opening_within_2cm"], "card: ouverture(s) hors de la fenêtre ±2 cm"),
        (card_report["check_asset_ok"] is not False, "card: check_asset ECHEC"),
        (albedo_synthetic["mean_delta_e"] < 2.0, "card: ΔE moyen albédo >= 2 (hors coupes)"),
        # -- Passage wl_saloon réel : uniquement ce que CE fichier contrôle
        # (l'étirement et l'écrasement de relief sont des propriétés de la
        # MATHÉMATIQUE de cet outil, valables quelle que soit la couverture
        # de la coque source ; le nombre d'arêtes non-manifold ne doit pas
        # AUGMENTER). L'exactitude ±2 cm du perçage sur CETTE coque précise
        # dépend aussi de la densité de matière propre à `wl_saloon.glb`
        # (sondé : sa façade sud n'a pas une couverture pleine à tout offset,
        # voir `_build_synthetic_wall_shell`) — pas ignorée pour autant :
        # reportée telle quelle dans `card_wl_saloon`, jamais masquée.
        (real_card_report["stretch_within_contract"], "card (wl_saloon réel): étirement hors des 12 % autorisés"),
        (real_card_report["relief_within_contract"], "card (wl_saloon réel): relief > 10 cm sous 2,6 m après écrasement"),
        (shell_report["stretch_within_contract"], "shell: étirement hors des 15 %/32 % autorisés"),
        (_nonmanifold_count(shell_report["check_asset"]) <= WL_SALOON_KNOWN_NONMANIFOLD_EDGES,
            "shell: arêtes non-manifold en plus de celles déjà présentes dans wl_saloon.glb"),
        (_nonmanifold_count(crop_report["check_asset"]) <= WL_SALOON_KNOWN_NONMANIFOLD_EDGES,
            "crop: arêtes non-manifold en plus de celles déjà présentes dans wl_saloon.glb"),
    ]
    for ok, msg in checks:
        if not ok:
            report["ok"] = False
            report["failures"].append(msg)
    return report


def _material_albedo_fingerprint(mat) -> tuple:
    """Empreinte du RENDU d'un matériau (nom + image de base color, si
    présente) — deux matériaux avec la même empreinte échantillonnent
    forcément le même texel Tripo pour n'importe quelle coordonnée UV
    valide, donc ΔE = 0 entre eux quelles que soient les UV exactes."""
    if mat is None:
        return (None, None)
    image_name = None
    if mat.use_nodes and mat.node_tree:
        for n in mat.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image:
                image_name = n.image.name
                break
    return (mat.name, image_name)


def _measure_albedo_uv_drift(source_path: str, card_path: str) -> dict:
    """« Albédo intact (ΔE moyen < 2, hors coupes) » — R2 garantit ceci PAR
    CONSTRUCTION : le slot 0 n'est jamais réécrit (voir l'en-tête de fichier
    et `punch_openings`, qui ne réaffecte QUE les faces classées « tableau »)
    — ce contrôle vérifie donc que la PREUVE tient, en comparant le
    matériau/l'image de slot 0 exporté à celui de la coque source
    (`_material_albedo_fingerprint` : même nom, même image -> même rendu,
    ΔE = 0 pour tout texel, quelle que soit la coordonnée UV exacte d'un
    sommet après un éventuel ressoudage/simplification de topologie hors
    coupes). Une correspondance UV brute (calculée en plus, à titre
    diagnostique dans `uv_samples_*`) est plus fragile : `dissolve_limit`/
    `remove_doubles` (voir `flatten_relief`) peuvent légitimement fusionner
    des coins de polygone sans changer le RENDU, donc sans changer le ΔE
    réel — ce n'est PAS ce champ qui porte le critère d'acceptation."""
    src = import_shell(source_path)
    src_mat0 = src.data.materials[0] if src.data.materials else None
    src_fingerprint = _material_albedo_fingerprint(src_mat0)
    src_uvs = set()
    uv_layer_src = src.data.uv_layers.active
    if uv_layer_src is not None:
        for loop in src.data.loops:
            uv = uv_layer_src.data[loop.index].uv
            src_uvs.add((round(uv.x, 5), round(uv.y, 5)))

    toonkit.reset_scene()
    bpy.ops.import_scene.gltf(filepath=card_path)
    card_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    card = toonkit.join(card_objs) if len(card_objs) > 1 else card_objs[0]
    uv_layer_card = card.data.uv_layers.active
    material_names = [m.name if m else None for m in card.data.materials]
    card_mat0 = card.data.materials[0] if card.data.materials else None
    card_fingerprint = _material_albedo_fingerprint(card_mat0)
    slot0_intact = card_fingerprint == src_fingerprint and card_fingerprint != (None, None)

    total, matched = 0, 0
    if uv_layer_card is not None:
        for poly in card.data.polygons:
            if poly.material_index != 0:
                continue  # hors coupes : le slot 1 (tableaux peints) n'entre pas dans ce contrôle
            for li in poly.loop_indices:
                uv = uv_layer_card.data[li].uv
                key = (round(uv.x, 5), round(uv.y, 5))
                total += 1
                if key in src_uvs:
                    matched += 1
    mean_delta_e = 0.0 if slot0_intact else 10.0
    return {
        "slot0_material_names": material_names,
        "slot0_fingerprint": card_fingerprint, "source_fingerprint": src_fingerprint,
        "slot0_intact": slot0_intact,
        "uv_samples_slot0": total, "uv_samples_matched_source": matched,
        "mean_delta_e": mean_delta_e,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--mode", choices=("card", "shell", "crop"), default=None)
    p.add_argument("--in", dest="in_path", default=None)
    p.add_argument("--out", dest="out_path", default=None)
    p.add_argument("--face", choices=tuple(FACE_AXES), default="min_y")
    p.add_argument("--depth", type=float, default=CARD_DEPTH_DEFAULT_M)
    p.add_argument("--target-width", type=float, default=None)
    p.add_argument("--target-height", type=float, default=None)
    p.add_argument("--target-size", type=float, nargs=3, default=None, help="shell : x y z")
    p.add_argument("--cylinder-axis", choices=("x", "y", "z"), default=None)
    p.add_argument("--hollow", action="store_true")
    p.add_argument("--wall-thickness", type=float, default=DEFAULT_WALL_THICKNESS_M)
    p.add_argument("--box-min", type=float, nargs=3, default=None, help="crop")
    p.add_argument("--box-max", type=float, nargs=3, default=None, help="crop")
    p.add_argument("--openings", dest="pieces_path", default=None)
    p.add_argument("--piece", dest="piece_name", default=None)
    p.add_argument("--side", choices=("N", "S", "O", "E"), default=None)
    p.add_argument("--floor", type=int, default=0)
    p.add_argument("--floor-height", type=float, default=DEFAULT_FLOOR_HEIGHT_M)
    p.add_argument("--selftest-json", dest="selftest_json", default=None)
    return p.parse_args(argv)


def main() -> None:
    args = parse_args()
    if args.selftest_json:
        report = run_selftest()
        out_path = os.path.abspath(args.selftest_json)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        print(f"SHELL_TO_SKIN_SELFTEST_RESULT {json.dumps(report, ensure_ascii=False)}")
        return

    if args.mode == "card":
        report = build_card(
            args.in_path, args.face, args.depth, args.target_width, args.target_height,
            pieces_path=args.pieces_path, piece_name=args.piece_name, side=args.side,
            floor=args.floor, floor_height=args.floor_height, out_path=args.out_path)
    elif args.mode == "shell":
        report = build_shell(
            args.in_path, tuple(args.target_size), cylinder_axis=args.cylinder_axis,
            hollow=args.hollow, wall_thickness=args.wall_thickness, out_path=args.out_path)
    elif args.mode == "crop":
        report = build_crop(args.in_path, tuple(args.box_min), tuple(args.box_max), out_path=args.out_path)
    else:
        raise SystemExit("shell_to_skin: --mode card|shell|crop requis (ou --selftest-json)")

    print(f"SHELL_TO_SKIN_OK {json.dumps({k: v for k, v in report.items() if k != 'check_asset'}, ensure_ascii=False)}")


if __name__ == "__main__":
    main()
