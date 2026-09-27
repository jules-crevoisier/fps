"""Texture BD des grenades (frag, flash, smoke), peinte par script.

Modèles Tripo retopologisés (quads) + Smart UV, SANS texture Tripo (consigne du 2026-09-27) :
la couleur est posée ici, texel par texel, à partir de la position 3D de chaque texel.

  1. aplats par zone : règles géométriques sur les parties détachées du modèle (corps, col,
     levier, anneau...) + bandes peintes en hauteur ;
  2. encre dans les creux, lue sur la normal map haute définition que Tripo joint au GLB
     (divergence de la normale en espace tangent : < 0 = creux, > 0 = arête) ;
  3. liseré d'encre aux changements de zone, léger éclat sur les arêtes saillantes ;
  4. débordement UV (tools/blender/lib/uv_mask.py), export GLB à l'échelle réelle,
     origine au centre de la boîte englobante (le projectile tourne autour).

  blender -b --factory-startup --python art/utilities/grenades/texture_grenades.py -- [--only frag] [--preview DIR]

Sources : assets/incoming/tripo/{frag,flash,smoke}.glb (normal maps embarquées).
Sorties : assets/models/utilities/{nom}.glb, art/utilities/grenades/{nom}_albedo.png.
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender", "lib"))
from uv_mask import pad_edges  # noqa: E402
from uv_paint import box_blur, rasterize, smoothstep, zone_edges  # noqa: E402

RES = 1024
SRC = os.path.join(ROOT, "assets", "incoming", "tripo")
OUT = os.path.join(ROOT, "assets", "models", "utilities")
ART = os.path.dirname(os.path.abspath(__file__))

# Palette (sRGB). Encre, papier et jaune signal = jetons de art/style/toon_style.json.
PAL = {
    "ink": "#0E0A12",
    "olive": "#5E7D2A",
    "brass": "#D9A62B",
    "steel": "#B7C2C9",
    "dark": "#3A3E46",
    "hole": "#1F2228",
    "yellow": "#FFCE1F",
    "pale": "#C8D5DC",
    "slate": "#4D6C8C",
    "stripe": "#FFF4E0",
}


def _rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


# -- règles de zones (hauteur du modèle source normalisée 0..1, r = distance à l'axe) --------
def frag_part(p):
    if p["area"] >= 0.3:
        return "olive"                      # les deux moitiés du corps quadrillé
    if p["zmax"] <= 0.05:
        return "dark"                       # culot
    if p["r"] > 0.3 and p["zmax"] < 0.6:
        return "brass"                      # plaque rivetée sur le flanc
    if p["r"] > 0.2 and p["zmin"] > 0.35 and p["zmax"] > 0.6:
        return "brass"                      # anneau de goupille
    if p["zmin"] > 0.8 and p["r"] < 0.12 and p["zmax"] < 0.95:
        return "brass"                      # fusée
    return "steel"                          # levier, charnière, goupille


def frag_band(zone, z):
    return "yellow" if zone == "olive" and z >= 0.705 else zone      # collier sous la fusée


def flash_part(p):
    if p["area"] >= 0.1:                    # coques perforées : bagues haut/bas, tube central
        return "yellow" if (p["cz"] < 0.27 or p["cz"] > 0.56) else "pale"
    if p["zmax"] <= 0.01:
        return "dark"                       # fond
    if p["zmin"] > 0.82 and p["r"] < 0.1 and p["zmax"] < 0.95:
        return "brass"                      # col
    if p["zmax"] < 0.84 and p["r"] < 0.28 and p["area"] < 0.02:
        return "hole"                       # fourreaux des perçages
    return "steel"                          # anneau, levier, chaînette


def smoke_part(p):
    if p["area"] >= 0.5:
        return "slate"                      # fût
    if p["area"] >= 0.2 and p["zmin"] > 0.55:
        return "dark"                       # dôme à évents
    if p["zmax"] <= 0.07:
        return "dark"                       # fond et pieds
    if p["zmin"] > 0.7 and p["r"] < 0.1 and p["zmax"] < 0.86:
        return "brass"                      # col
    if p["zmin"] > 0.6 and p["zmax"] < 0.75 and p["area"] < 0.01:
        return "hole"                       # fourreaux des évents
    return "steel"                          # levier, goupille


def smoke_band(zone, z):
    return "stripe" if zone == "slate" and 0.40 <= z <= 0.47 else zone


GRENADES = {
    # nom : (règle par partie, bande en hauteur, hauteur réelle en m, nom du nœud)
    "frag": (frag_part, frag_band, 0.11, "Frag"),
    "flash": (flash_part, lambda zone, z: zone, 0.12, "Flash"),
    "smoke": (smoke_part, smoke_band, 0.13, "Smoke"),
}


# -- géométrie ----------------------------------------------------------------------------
def loose_parts(me):
    """Partie détachée de chaque polygone + statistiques par partie (aire, centre, boîte)."""
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    part = [-1] * len(bm.faces)
    n = 0
    for f in bm.faces:
        if part[f.index] >= 0:
            continue
        stack = [f]
        while stack:
            x = stack.pop()
            if part[x.index] >= 0:
                continue
            part[x.index] = n
            for e in x.edges:
                stack.extend(g for g in e.link_faces if part[g.index] < 0)
        n += 1
    stats = [{"area": 0.0, "c": Vector(), "zmin": 9.0, "zmax": -9.0} for _ in range(n)]
    for f in bm.faces:
        s = stats[part[f.index]]
        a = f.calc_area()
        s["area"] += a
        s["c"] += f.calc_center_median() * a
        for v in f.verts:
            s["zmin"] = min(s["zmin"], v.co.z)
            s["zmax"] = max(s["zmax"], v.co.z)
    for s in stats:
        c = s["c"] / max(s["area"], 1e-9)
        s["cz"] = c.z
        s["r"] = math.hypot(c.x, c.y)
    bm.free()
    return part, stats


def normal_divergence(img, cover):
    """Divergence de la normale (espace tangent glTF, +Y = haut de l'image) ramenée à RES."""
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)[..., :2] * 2.0 - 1.0
    f = h // RES
    if f > 1:
        px = px.reshape(RES, f, RES, f, 2).mean((1, 3))
    px = pad_edges(px, cover, iterations=4)
    px = box_blur(px, 1)
    dnx = (np.roll(px[..., 0], -1, 1) - np.roll(px[..., 0], 1, 1)) * 0.5
    dny = (np.roll(px[..., 1], -1, 0) - np.roll(px[..., 1], 1, 0)) * 0.5
    return dnx + dny


def paint(name, obj, rule, band):
    me = obj.data
    part, stats = loose_parts(me)
    pos, pid, _ = rasterize(me, RES, part)
    cover = pid >= 0
    zones = sorted(PAL)
    zone_of_part = np.array([zones.index(rule(s)) for s in stats], np.int32)
    zid = np.full(pid.shape, -1, np.int32)
    zid[cover] = zone_of_part[pid[cover]]
    # bandes en hauteur (texel par texel : bords nets, indépendants du maillage)
    zmap = pos[..., 2]
    for zi, zn in enumerate(zones):
        m = cover & (zid == zi)
        if not m.any():
            continue
        banded = np.array([zones.index(band(zn, z)) for z in zmap[m]], np.int32)
        zid[m] = banded
    col = np.zeros((RES, RES, 3), np.float32)
    lut = np.stack([_rgb(PAL[z]) for z in zones])
    col[cover] = lut[zid[cover]]
    # dégradé peint : haut un peu plus clair que le bas
    col *= (0.93 + 0.12 * np.clip(zmap, 0.0, 1.0))[..., None]

    nm = next((i for i in bpy.data.images if "normal" in i.name.lower()), None)
    ink = np.zeros((RES, RES), np.float32)
    shine = np.zeros((RES, RES), np.float32)
    if nm is not None:
        div = normal_divergence(nm, cover)
        d = div[cover]
        q = np.percentile(np.abs(d), [50, 90, 97, 99])
        print(f"DIV {name} |div| p50={q[0]:.4f} p90={q[1]:.4f} p97={q[2]:.4f} p99={q[3]:.4f}")
        t = q[2]
        ink = smoothstep(0.35 * t, 0.9 * t, -div)
        shine = smoothstep(0.5 * t, 1.4 * t, div)
    # liseré aux changements de zone (dans une même île)
    edge = zone_edges(zid, cover)
    ink = np.maximum(ink, edge.astype(np.float32))
    ink[~cover] = 0.0
    shine[~cover] = 0.0
    col = col + (1.0 - col) * (0.35 * shine)[..., None]
    col = col * (1.0 - 0.92 * ink[..., None]) + _rgb(PAL["ink"]) * (0.92 * ink[..., None])
    rgba = np.concatenate([np.clip(col, 0.0, 1.0), np.ones((RES, RES, 1), np.float32)], -1)
    rgba = pad_edges(rgba, cover, iterations=12)
    print(f"ZONES {name} " + " ".join(f"{z}={int((zid == zones.index(z)).sum())}" for z in zones
                                      if (zid == zones.index(z)).any()))
    return rgba


# -- export ---------------------------------------------------------------------------------
def build(name, preview_dir=None):
    rule, band, height, node = GRENADES[name]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, f"{name}.glb"))
    obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    mw = obj.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = mw
    for o in [o for o in bpy.context.scene.objects if o.type == "EMPTY"]:
        bpy.data.objects.remove(o)
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)

    rgba = paint(name, obj, rule, band)
    img = bpy.data.images.new(f"{name}_albedo", RES, RES, alpha=False)
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    png = os.path.join(ART, f"{name}_albedo.png")
    img.filepath_raw = png
    img.file_format = "PNG"
    img.save()
    img.pack()

    mat = bpy.data.materials.new(f"Grenade_{node}")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for i in [i for i in bpy.data.images if i != img]:
        bpy.data.images.remove(i)

    # échelle réelle, origine au centre de la boîte
    cs = [Vector(c) for c in obj.bound_box]
    mn = Vector((min(c.x for c in cs), min(c.y for c in cs), min(c.z for c in cs)))
    mx = Vector((max(c.x for c in cs), max(c.y for c in cs), max(c.z for c in cs)))
    s = height / (mx.z - mn.z)
    obj.data.transform(Matrix.Scale(s, 4) @ Matrix.Translation(-(mn + mx) * 0.5))
    obj.name = node
    obj.data.name = node

    os.makedirs(OUT, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f"{name}.glb"), export_format="GLB",
                              use_selection=True, export_yup=True, export_apply=True,
                              export_animations=False, export_image_format="AUTO")
    print(f"EXPORT {name} -> assets/models/utilities/{name}.glb ({height:.2f} m)")
    if preview_dir:
        render_preview(name, obj, height, preview_dir)


def render_preview(name, obj, height, out_dir):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x = sc.render.resolution_y = 512
    cam_data = bpy.data.cameras.new("preview")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = height * 1.3
    cam = bpy.data.objects.new("preview", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    os.makedirs(out_dir, exist_ok=True)
    for vi, (az, el) in enumerate(((0, 10), (120, 20), (240, 40))):
        a, e = math.radians(az), math.radians(el)
        d = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
        cam.location = d * height * 4
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(out_dir, f"{name}_{vi}.png")
        bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = argv[argv.index("--only") + 1] if "--only" in argv else None
    preview = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    for name in GRENADES:
        if only is None or name == only:
            build(name, preview)


main()
