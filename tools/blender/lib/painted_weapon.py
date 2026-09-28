"""tools/blender/lib/painted_weapon.py — pipeline partagée « Tripo -> arme peinte par script »,
factorisée depuis art/weapons/revolver/build_revolver.py (tâche "quatre armes v2", 2026-09-28) pour
les 4 armes à pièce mobile SÉPARÉE (Rafale/Fracas/Verdict/Aiguille -- convention
tools/blender/make_action_weapons.py : PumpGrip/Lever/Bolt/Magazine sont des NŒUDS distincts,
jamais skinnés à un squelette, contrairement au barillet/chien du Revolver).

Repère SOURCE Tripo : mesuré par script (voir chaque build_<id>.py — l'axe "avant" et son signe
varient d'une génération Tripo à l'autre, PAS une convention fixe malgré le prompt partagé, constaté
en sondant les bbox des 4 .glb). Repère JEU (comme le Revolver/Ravage) : avant = +Y, haut = +Z,
origine = poignée (le point que la main tient).

Peinture en COULEURS DE SOMMET (voir `paint_vertex_colors` pour la raison -- un premier essai en
texture peinte par atlas UV partagé, comme le Revolver, produisait un bruit "grain de sel" à
l'export sur ces maillages) : Body ET pièce mobile portent chacun leur PROPRE matériau
`make_vertex_color_material`, tous deux nommés plainement "<Nom>"/"<Nom>_<pièce>" (repli SANS
marqueur "_paint"/"_painted", voir la doc de tête : couleurs déjà correctes sur les sommets, pas de
contour post-traitement par pièce nécessaire côté ViewModel/ThirdPersonWeapon -- même choix que le
Revolver, vérifié en lisant assets/models/weapons/revolver.glb : son matériau s'appelle "Revolver",
pas "revolver_painted", et ViewModel._apply_cartoon_materials le laisse tel quel, contour venant du
pass plein écran ToonStyle.add_outline_pass).

Couleurs : hex sRGB (contrat) converties en linéaire via `hex_to_linear` avant d'être écrites dans
l'attribut de couleur -- le glTF COLOR_0 est un canal LINÉAIRE par spécification (contrairement à une
texture baseColor, qui elle est sRGB), donc AUCUNE reconversion ne doit avoir lieu à la lecture :
écrire directement la valeur linéaire est la conversion correcte pour ce canal précis (le bug
rapporté par la tâche, "le cobalt vire au cyan", venait d'un chemin DIFFÉRENT -- toonkit.toon_material
sur les placeholders, qui pose du hex/255 sur l'entrée Base Color d'un BSDF, un paramètre LINÉAIRE
sans conversion -- absent ici puisque `hex_to_linear` convertit explicitement avant écriture).
"""
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

import sys as _sys
_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in _sys.path:
    _sys.path.insert(0, _HERE)
from uv_paint import smoothstep  # noqa: E402


def hex_to_linear(h: str) -> np.ndarray:
    """"#RRGGBB" sRGB -> (r,g,b) linéaire [0,1] (formule standard sRGB EOTF, précision suffisante
    pour de la peinture procédurale -- la même que Blender/glTF appliquent à la lecture)."""
    h = h.lstrip("#")
    srgb = np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float64)
    lin = np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4)
    return lin.astype(np.float32)


def part_stats(o) -> dict:
    """Bbox/centre/faces d'un objet MESH, en repère MONDE (avant toute transformation vers le jeu)
    -- même contrat que build_revolver.py::part_stats, réutilisé par le classificateur zone_of de
    chaque arme (heuristique par position/taille, jamais un index de pièce codé en dur un par un :
    la segmentation Tripo change de granularité d'une génération à l'autre)."""
    vs = [o.matrix_world @ v.co for v in o.data.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    c = (mn + mx) * 0.5
    return {"faces": len(o.data.polygons), "c": c, "size": mx - mn, "mn": mn, "mx": mx, "name": o.name}


def vertex_concavity(me) -> np.ndarray:
    """> 0 dans un creux, < 0 sur une arête saillante -- copie de build_revolver.py (encre dans les
    creux, éclat sur les arêtes), un seul maillage à la fois (appelé par `bake_zone_src` avant la
    jonction/séparation Body vs pièce mobile, comme le Revolver)."""
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    out = np.zeros(len(bm.verts), np.float32)
    for v in bm.verts:
        if not v.link_edges:
            continue
        nb = [e.other_vert(v).co for e in v.link_edges]
        avg = sum(nb, Vector()) / len(nb)
        el = sum((co - v.co).length for co in nb) / len(nb)
        out[v.index] = v.normal.dot(avg - v.co) / max(el, 1e-6)
    bm.free()
    return out


def bake_zone_src(o, zone_index: int) -> None:
    """Bake matrix_world dans le maillage (repère SOURCE Tripo figé), puis pose deux attributs par
    face/sommet -- "zone" (int, un seul par objet ENTIER : la segmentation Tripo est déjà la
    granularité de classification, comme build_revolver.py) et "src" (position SOURCE par sommet,
    pour les motifs procéduraux -- veinage du noyer). Survit à `toonkit.join`/`bpy.ops.mesh.separate`
    (attributs, pas des données dérivées)."""
    me = o.data
    me.transform(o.matrix_world)
    o.matrix_world = Matrix.Identity(4)
    if "zone" not in me.attributes:
        za = me.attributes.new("zone", "INT", "FACE")
    else:
        za = me.attributes["zone"]
    za.data.foreach_set("value", [zone_index] * len(me.polygons))
    if "src" not in me.attributes:
        sa = me.attributes.new("src", "FLOAT_VECTOR", "POINT")
    else:
        sa = me.attributes["src"]
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    sa.data.foreach_set("vector", co)


def paint_vertex_colors(me, zones: list, palette: dict, grain_zones: tuple = ()) -> None:
    """Peint le maillage `me` (attributs "zone"/"src" déjà posés, voir `bake_zone_src`) en COULEURS
    DE SOMMET (attribut de couleur "Color", domaine CORNER, comme `toonkit.bake_vertex_ao` -- même
    recette que build_revolver.py::paint : encre dans les creux, éclat sur les arêtes, liseré aux
    changements de zone, dégradé "haut plus clair", veinage optionnel -- calculée par SOMMET plutôt
    que par TEXEL d'atlas.

    Remplace un premier essai en texture peinte (UV smart_project -> rasterisation, voir
    tools/blender/lib/uv_paint.py) : sur ces maillages (~18-19k triangles, des dizaines de pièces
    Tripo à l'origine, chacune SANS UV -- `smart_project` en repart de zéro) l'empaquetage d'îles de
    `bpy.ops.uv.smart_project` en session `-b` ne s'est PAS avéré sans chevauchement malgré un usage
    identique à build_revolver.py -- constaté par capture ET par un test isolé dédié (zones peintes
    par larges blocs spatialement cohérents, résultat en bruit "grain de sel" avec des texels de
    zones DIFFÉRENTES entremêlés partout, pas seulement aux bords d'île) : cause non isolée avec
    certitude (empaquetage `smart_project` qui dégrade avec un très grand nombre d'îles ? spécifique à
    Blender 5.2 en `-b` ? aux deux ?), mais le contournement est robuste et déjà éprouvé dans CE dépôt
    (toonkit.bake_vertex_ao/bake_vertex_masks) : aucune UV requise, aucun risque de chevauchement
    puisqu'il n'y a plus d'atlas 2D à empaqueter, juste un attribut PAR SOMMET."""
    conc = vertex_concavity(me)
    face_zone = np.empty(len(me.polygons), np.int32)
    me.attributes["zone"].data.foreach_get("value", face_zone)
    src = np.empty(len(me.vertices) * 3, np.float32)
    me.attributes["src"].data.foreach_get("vector", src)
    src = src.reshape(-1, 3)

    n_loops = len(me.loops)
    loop_vert = np.empty(n_loops, np.int32)
    me.loops.foreach_get("vertex_index", loop_vert)
    loop_face = np.empty(n_loops, np.int32)
    for poly in me.polygons:
        loop_face[poly.loop_start:poly.loop_start + poly.loop_total] = poly.index

    zid = face_zone[loop_face]
    lut = np.stack([hex_to_linear(palette[z]) for z in zones])
    col = lut[zid].copy()

    lv_conc = conc[loop_vert]
    lv_src = src[loop_vert]
    lx, lz = lv_src[:, 0], lv_src[:, 2]
    top_norm = (lz - lz.min()) / max(lz.max() - lz.min(), 1e-6)
    col *= (0.88 + 0.16 * top_norm)[:, None]

    for gz in grain_zones:
        if gz not in zones:
            continue
        mask = zid == zones.index(gz)
        grain = np.sin((lx * 0.55 + lz) * 95.0 + 2.5 * np.sin(lz * 31.0 + lx * 12.0))
        col[mask] *= (1.0 - 0.16 * smoothstep(0.55, 0.95, grain[mask]))[:, None]

    # Liseré aux changements de zone : un sommet partagé par des faces de zones DIFFÉRENTES.
    poly_vidx = np.empty(sum(p.loop_total for p in me.polygons), np.int32)
    poly_zone_of_vert = np.empty_like(poly_vidx)
    i = 0
    for poly in me.polygons:
        n = poly.loop_total
        poly_vidx[i:i + n] = [me.loops[li].vertex_index for li in range(poly.loop_start, poly.loop_start + n)]
        poly_zone_of_vert[i:i + n] = face_zone[poly.index]
        i += n
    order = np.argsort(poly_vidx, kind="stable")
    sv, sz_ = poly_vidx[order], poly_zone_of_vert[order]
    edge_vert = np.zeros(len(me.vertices), bool)
    uniq_v, start_idx, counts = np.unique(sv, return_index=True, return_counts=True)
    for v_i, s, c in zip(uniq_v, start_idx, counts):
        if c > 1 and len(set(sz_[s:s + c].tolist())) > 1:
            edge_vert[v_i] = True
    lv_edge = edge_vert[loop_vert]

    q = np.percentile(np.abs(conc), [90, 97]) if len(conc) else np.array([0.02, 0.05])
    ink = smoothstep(0.55 * q[1], 1.15 * q[1], lv_conc)
    shine = smoothstep(0.6 * q[1], 1.4 * q[1], -lv_conc)
    ink = np.maximum(ink, lv_edge.astype(np.float32))
    col = col + (1.0 - col) * (0.3 * shine)[:, None]
    ink_rgb = hex_to_linear(palette.get("ink", "#0E0A12"))
    col = col * (1.0 - 0.9 * ink[:, None]) + ink_rgb * (0.9 * ink[:, None])
    col = np.clip(col, 0.0, 1.0)
    rgba = np.concatenate([col, np.ones((n_loops, 1), np.float32)], -1)

    if "Color" not in me.color_attributes:
        attr = me.color_attributes.new(name="Color", type="BYTE_COLOR", domain="CORNER")
    else:
        attr = me.color_attributes["Color"]
    attr.data.foreach_set("color", rgba.ravel())
    idx = me.color_attributes.find("Color")
    me.color_attributes.active_color_index = idx
    me.color_attributes.render_color_index = idx


## Marqueur du matériau couleurs-de-sommet (voir `paint_vertex_colors`) -- le glTF exporté ne porte
## AUCUN lien "lire la couleur de sommet" (la liaison nœud Blender VertexColor -> Base Color n'a pas
## d'équivalent dans le matériau glTF/PBR standard, seul le maillage exporte VRAIMENT COLOR_0) : sans
## ce marqueur, Godot importe un StandardMaterial3D blanc uni (`vertex_color_use_as_albedo` à false
## par défaut, confirmé par rendu isolé, tâche "quatre armes v2") -- ViewModel.gd/ThirdPersonWeapon.gd
## doivent donc reconnaître ce suffixe et POSER ce drapeau eux-mêmes au runtime (voir leurs
## `_apply_cartoon_materials`).
VERTEX_COLOR_MATERIAL_MARKER = "_vcolor"


def make_vertex_color_material(name: str) -> "bpy.types.Material":
    """Matériau qui lit l'attribut de couleur "Color" (voir `paint_vertex_colors`) comme Base Color
    en PRÉVISUALISATION Blender (nœud VertexColor -- utile pour inspecter le résultat dans Blender,
    SANS effet sur l'export glTF, voir `VERTEX_COLOR_MATERIAL_MARKER`) -- roughness 1.0, comme le
    Revolver/build_revolver.py."""
    mat = bpy.data.materials.new(f"{name}{VERTEX_COLOR_MATERIAL_MARKER}")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    vc = mat.node_tree.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Color"
    mat.node_tree.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 1.0
    return mat


def split_by_x_range(obj, x_lo: float, x_hi: float, new_name: str):
    """Détache en un NOUVEL objet les faces de `obj` (repère LOCAL/objet, avant `bake_zone_src`) dont
    le centre tombe dans [x_lo, x_hi] -- utilisé quand la segmentation Tripo a FUSIONNÉ la pièce
    mobile avec le canon/la carcasse en un seul maillage continu (constaté par sondage de profil,
    voir le script de l'arme concernée pour la mesure qui a produit ces deux bornes) : la coupe suit
    une VRAIE rupture géométrique du maillage (largeur de section mesurée par tranche de X, pas un
    point arbitraire), donc un bord net, jamais une tranche à travers un tube parfaitement lisse."""
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.scene.objects:
        o.select_set(o is obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    bpy.ops.mesh.select_all(action="DESELECT")
    mw = obj.matrix_world
    for f in bm.faces:
        c = mw @ f.calc_center_median()  # même repère (MONDE) que le sondage de profil qui a mesuré x_lo/x_hi
        f.select = x_lo <= c.x <= x_hi
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    new_obj = next(o for o in bpy.context.selected_objects if o is not obj)
    new_obj.name = new_name
    return new_obj


def recenter_to_pivot(obj, pivot: Vector) -> None:
    """Recentre le maillage de `obj` (déjà en repère JEU, coordonnées ABSOLUES) sur `pivot` :
    soustrait `pivot` des sommets et pose `obj.location = pivot`. Indispensable pour toute pièce qui
    TOURNE (Lever -- `ViewModel._update_action_part` tourne le nœud autour de SON PROPRE repère
    local, voir sa doc) ; pour une pièce qui ne fait que translater (Magazine/PumpGrip/Bolt) c'est
    surtout une question de PROPRETÉ (origine posée à un point physique -- attache/centre -- plutôt
    que sur la poignée de l'arme entière, cf `_action_rest_pos` capturé par ViewModel à
    `_resolve_action_part`, purement additif donc correct dans les deux cas)."""
    obj.data.transform(Matrix.Translation(-pivot))
    obj.location = pivot


def to_game_matrix(front_sign: float, scale: float, grip: Vector, lift: float = 0.0) -> Matrix:
    """Repère SOURCE (mesuré par script, voir chaque build_<id>.py) -> repère JEU : avant SOURCE ->
    +Y JEU (bascule +90°/Z si `front_sign` = +1.0, c-a-d avant SOURCE = +X ; -90°/Z si -1.0, avant
    SOURCE = -X -- axe mesuré au cas par cas, PAS une convention Tripo fixe malgré un prompt partagé,
    voir la doc de tête), origine = poignée, échelle réelle -- même construction que
    build_revolver.py::build (`Matrix.Scale @ Matrix.Rotation(±90°,'Z') @ Matrix.Translation(-grip)`).

    `lift` (mètres jeu, axe Z/haut) : décalage vertical ADDITIONNEL après la mise à l'échelle/
    rotation -- PAS pour un cadrage à l'œil (contrairement à GRIP_LIFT de tools/blender/
    make_action_weapons.py, une constante partagée devinée avant toute mesure), mais pour rejoindre
    la fourchette Z RÉELLEMENT mesurée sur l'empty "Muzzle" de wpn_ravage.glb (0,215-0,255, voir la
    doc GRIP_LIFT) -- l'arme est tenue par le rig bras FP (FPArmsRig.gd, os "WeaponGrip", transform
    LOCALE IDENTITÉ) chez CE personnage (Verrou), jamais par `ViewModel._place_weapon`/
    `weapon_nudge_for` (chemin de repli gants flottants, INACTIF ici) : la hauteur à l'écran vient
    ENTIÈREMENT de la géométrie exportée, mesurée par script (voir chaque build_<id>.py) plutôt que
    devinée à l'œil comme le placeholder chunky."""
    m = Matrix.Scale(scale, 4) @ Matrix.Rotation(math.radians(90.0 if front_sign > 0.0 else -90.0), 4, "Z") \
        @ Matrix.Translation(-grip)
    return Matrix.Translation(Vector((0.0, 0.0, lift))) @ m


## Milieu de la fourchette Z (repère Blender/haut) mesurée sur l'empty "Muzzle" de wpn_ravage.glb
## (0,215-0,255 -- voir make_action_weapons.py::GRIP_LIFT) : l'arme est tenue par FPArmsRig (os
## "WeaponGrip", transform locale IDENTITÉ), jamais par ViewModel._place_weapon/weapon_nudge_for
## (repli gants flottants, INACTIF pour Verrou) -- la hauteur à l'écran vient ENTIÈREMENT de la
## géométrie exportée.
TARGET_MUZZLE_Z = 0.235


def auto_lift(front_sign: float, scale: float, grip: Vector, muzzle_src: Vector,
              target_z: float = TARGET_MUZZLE_Z) -> float:
    """Décalage `lift` (voir `to_game_matrix`) qui amène l'empty "Muzzle" à `target_z` -- calculé
    plutôt que deviné à l'œil (une constante à la main se désynchroniserait dès que `scale`/`grip`
    changent, ex. un réglage de LENGTH_M) : construit la transformation SANS lift, mesure où
    "Muzzle" tombe, en déduit l'écart."""
    prelim = to_game_matrix(front_sign, scale, grip, lift=0.0)
    return target_z - (prelim @ muzzle_src).z
