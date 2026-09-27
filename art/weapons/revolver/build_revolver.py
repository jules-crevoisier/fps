"""Revolver « Frontier nénuphar » (arme 2, petit gun) : modèle Tripo -> arme de jeu.

Source : image de concept -> 3D Tripo, découpé en 51 pièces, SANS texture Tripo (consigne
du 2026-09-27). Ce script :
  1. regroupe les pièces par rôle (carcasse, barillet, bras du barillet, chien, gâchette) ;
  2. construit un petit squelette (Root, Crane, Cylinder, Hammer, Trigger) et skinne chaque
     pièce à 100 % sur son os (pièces rigides, animées par os comme la grenouille) ;
  3. déplie les UV (Blender, toutes pièces dans un même atlas) et peint la texture BD texel
     par texel : acier bleuté, laiton, noyer veiné, nénuphar vert ; encre dans les creux
     (courbure du maillage) et aux changements de zone, éclat sur les arêtes ;
  4. met à l'échelle réelle et au repère des armes du jeu (comme le Ravage : avant = +Y,
     haut = +Z ; origine au centre de la poignée), pose l'empty Muzzle au bout du canon ;
  5. exporte assets/models/weapons/revolver.glb et enregistre revolver_rig.blend (base des
     scripts d'animation).

  blender -b --factory-startup --python art/weapons/revolver/build_revolver.py -- [--preview DIR]
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender", "lib"))
from uv_mask import pad_edges  # noqa: E402
from uv_paint import rasterize, smoothstep, zone_edges  # noqa: E402

SRC = os.path.join(ROOT, "assets", "incoming", "tripo", "revolver.glb")
OUT_GLB = os.path.join(ROOT, "assets", "models", "weapons", "revolver.glb")
OUT_PNG = os.path.join(HERE, "revolver_albedo.png")
OUT_BLEND = os.path.join(HERE, "revolver_rig.blend")
RES = 1024
# Longueur du canon au talon de la crosse. 0,26 m (vrai revolver court) disparaissait dans les
# gros gants de la grenouille : exagéré à 0,32 m, dans l'esprit cartoon du jeu. Garder
# art/characters/frog_cowboy/anim/pistol.py (REVOLVER_LENGTH_M) synchronisé.
LENGTH_M = 0.32

# Repère SOURCE (Tripo) : avant = +X, haut = +Z ; axe du barillet à (y=0, z=AXIS_Z).
AXIS_Z = 0.483
CYL_R = 0.105

PAL = {
    "ink": "#0E0A12",
    "steel": "#5E6B78",     # carcasse, canon
    "cyl": "#74818D",       # barillet, un ton plus clair : on le voit tourner
    "dark": "#414A55",      # chien
    "brass": "#D9A62B",
    "walnut": "#7A4526",
    "lily": "#5FBF2E",      # jeton grass_green
}


def _rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


# -- 1. rôles des pièces ----------------------------------------------------------------------
def part_stats(o):
    vs = [o.matrix_world @ v.co for v in o.data.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    c = (mn + mx) * 0.5
    return {"faces": len(o.data.polygons), "c": c, "size": mx - mn, "mn": mn, "mx": mx}


def bone_of(s):
    """Os qui porte la pièce (rigide)."""
    c, size, faces = s["c"], s["size"], s["faces"]
    radial = math.hypot(c.y, c.z - AXIS_Z)
    if faces >= 2000:
        return "Root"                                   # canon + carcasse
    if -0.14 <= c.x <= -0.06 and 0.20 <= c.z <= 0.33 and size.z >= 0.08 and faces < 200:
        return "Trigger"
    if c.x <= -0.20 and c.z >= 0.53 and size.y <= 0.07:
        return "Hammer"
    if -0.12 <= c.x <= 0.42 and radial <= CYL_R:
        return "Crane" if c.x > 0.2 else "Cylinder"     # baguette d'éjection : bascule sans tourner
    return "Root"


def zone_of(s, bone):
    c, size, faces = s["c"], s["size"], s["faces"]
    if bone == "Trigger":
        return "brass"
    if bone == "Hammer":
        return "dark"
    if bone in ("Cylinder", "Crane"):
        return "cyl" if bone == "Cylinder" else "steel"
    if faces > 500 and c.x < -0.25 and size.y < 0.07:
        return "walnut"                                 # plaquettes de crosse
    if 100 <= faces <= 200 and size.y < 0.01 and c.x < -0.25:
        return "lily"                                   # incrustations nénuphar
    if 400 <= faces <= 700 and 0.2 <= c.z <= 0.3 and size.x > 0.3:
        return "brass"                                  # pontet et bas de carcasse
    if faces <= 60 and c.x < -0.25 and c.z < 0.35:
        return "brass"                                  # vis de crosse (les petits éclats de
                                                        # carcasse restent acier : en laiton, ils
                                                        # faisaient des paillettes autour du barillet)
    return "steel"


# -- 3. courbure par sommet (encre dans les creux) --------------------------------------------
def vertex_concavity(me):
    """> 0 dans un creux, < 0 sur une arête saillante (écart au barycentre des voisins le long
    de la normale, rapporté à la longueur moyenne des arêtes)."""
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


def paint(obj, zones):
    me = obj.data
    conc = vertex_concavity(me)
    face_zone = np.empty(len(me.polygons), np.int32)
    me.attributes["zone"].data.foreach_get("value", face_zone)
    src = np.empty(len(me.vertices) * 3, np.float32)   # position SOURCE, pour les motifs
    me.attributes["src"].data.foreach_get("vector", src)
    src = src.reshape(-1, 3)
    pos, zid, attrs = rasterize(me, RES, face_zone, np.concatenate([conc[:, None], src], 1))
    cover = zid >= 0
    lut = np.stack([_rgb(PAL[z]) for z in zones])
    col = np.zeros((RES, RES, 3), np.float32)
    col[cover] = lut[zid[cover]]
    cv = attrs[..., 0]
    sx, sz = attrs[..., 1], attrs[..., 3]
    # dégradé peint : haut plus clair
    col *= (0.9 + 0.18 * np.clip(sz / 0.64, 0.0, 1.0))[..., None]
    # veinage du noyer : bandes le long de la crosse (inclinée), légèrement ondulées
    wal = cover & (zid == zones.index("walnut"))
    grain = np.sin((sx * 0.55 + sz) * 95.0 + 2.5 * np.sin(sz * 31.0 + sx * 12.0))
    col[wal] *= (1.0 - 0.16 * smoothstep(0.55, 0.95, grain[wal]))[:, None]
    # encre dans les creux, éclat sur les arêtes, liseré aux changements de zone
    q = np.percentile(np.abs(cv[cover]), [90, 97])
    ink = smoothstep(0.55 * q[1], 1.15 * q[1], cv)
    shine = smoothstep(0.6 * q[1], 1.4 * q[1], -cv)
    ink = np.maximum(ink, zone_edges(zid, cover).astype(np.float32))
    ink[~cover] = 0.0
    shine[~cover] = 0.0
    col = col + (1.0 - col) * (0.3 * shine)[..., None]
    col = col * (1.0 - 0.9 * ink[..., None]) + _rgb(PAL["ink"]) * (0.9 * ink[..., None])
    rgba = np.concatenate([np.clip(col, 0.0, 1.0), np.ones((RES, RES, 1), np.float32)], -1)
    return pad_edges(rgba, cover, iterations=12).astype(np.float32)


# -- douilles et chargeur rapide (pour le rechargement) ------------------------------------------
ROUND_LEN = 0.034
ROUND_R = 0.0068
RIM_R = 0.0082


def _round(bm, center: Vector, rear_y: float, scale=1.0):
    """Une cartouche (corps + bourrelet) le long de +Y, culot à rear_y."""
    for r, y0, y1 in ((RIM_R * scale, rear_y - 0.0015, rear_y + 0.0005),
                      (ROUND_R * scale, rear_y + 0.0005, rear_y + ROUND_LEN)):
        res = bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=r, radius2=r, depth=y1 - y0)
        verts = res["verts"]
        bmesh.ops.rotate(bm, verts=verts, cent=Vector(), matrix=Matrix.Rotation(math.radians(-90.0), 3, "X"))
        bmesh.ops.translate(bm, verts=verts, vec=Vector((center.x, (y0 + y1) * 0.5, center.z)))


def add_rounds(gun, zones, cyl_c: Vector, chamber_r: float, rear_y: float):
    """Six douilles dans les chambres (os Casings) et le chargeur rapide (os Loader) : au repos,
    le chargeur est RANGÉ DANS le barillet (cartouches un peu plus fines, disque au milieu du
    barillet) -- rien ne dépasse, même sans animation ; Rev_Reload le fait sortir."""
    made = []
    for name, zone, scale, dy, disc in (("Casings", "brass", 1.0, 0.0, False), ("Loader", "brass", 0.96, 0.001, True)):
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        for k in range(6):
            a = math.radians(90.0 + 60.0 * k)
            c = cyl_c + Vector((chamber_r * math.cos(a), 0.0, chamber_r * math.sin(a)))
            _round(bm, c, rear_y + dy, scale)
        n_round_faces = len(bm.faces)
        if disc:
            res = bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=chamber_r + 0.006,
                                        radius2=chamber_r + 0.006, depth=0.005)
            bmesh.ops.rotate(bm, verts=res["verts"], cent=Vector(), matrix=Matrix.Rotation(math.radians(-90.0), 3, "X"))
            bmesh.ops.translate(bm, verts=res["verts"], vec=Vector((cyl_c.x, rear_y + 0.012, cyl_c.z)))
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        za = me.attributes.new("zone", "INT", "FACE")
        za.data.foreach_set("value", [zones.index(zone) if i < n_round_faces else zones.index("dark")
                                      for i in range(len(me.polygons))])
        sa = me.attributes.new("src", "FLOAT_VECTOR", "POINT")
        sa.data.foreach_set("vector", [0.0] * (len(me.vertices) * 3))
        ob.vertex_groups.new(name=name).add(list(range(len(me.vertices))), 1.0, "REPLACE")
        made.append(ob)
    for o in bpy.context.scene.objects:
        o.select_set(o in made or o is gun)
    bpy.context.view_layer.objects.active = gun
    bpy.ops.object.join()


# -- construction ---------------------------------------------------------------------------
def build(preview_dir=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    stats = {o.name: part_stats(o) for o in parts}
    bones = {o.name: bone_of(stats[o.name]) for o in parts}
    zones = [z for z in sorted(PAL) if z != "ink"]

    # repères SOURCE des pivots
    hammer = [stats[n] for n in stats if bones[n] == "Hammer"]
    trigger = [stats[n] for n in stats if bones[n] == "Trigger"]
    frame = max(parts, key=lambda o: stats[o.name]["faces"])
    walnut = [o for o in parts if zone_of(stats[o.name], bones[o.name]) == "walnut"]
    assert hammer and trigger and walnut, "pièces clés introuvables"
    h, t = hammer[0], trigger[0]
    piv_hammer = Vector((h["c"].x + 0.35 * h["size"].x, 0.0, h["mn"].z + 0.1 * h["size"].z))
    piv_trigger = Vector((t["c"].x + 0.2 * t["size"].x, 0.0, t["mx"].z - 0.01))
    fx = stats[frame.name]["mx"].x
    tip = [frame.matrix_world @ v.co for v in frame.data.vertices if (frame.matrix_world @ v.co).x > fx - 0.012]
    muzzle = Vector((fx, sum(v.y for v in tip) / len(tip), sum(v.z for v in tip) / len(tip)))
    cyl_center = Vector((-0.007, 0.0, AXIS_Z))
    hinge = Vector((cyl_center.x, 0.5 * CYL_R, AXIS_Z - 0.9 * CYL_R))   # à gauche (+Y source), dessous
    gv = [o.matrix_world @ v.co for o in walnut for v in o.data.vertices]
    grip = Vector((sum(v.x for v in gv) / len(gv), 0.0, sum(v.z for v in gv) / len(gv)))

    # source -> repère du jeu : avant +X -> +Y, origine au centre de la poignée, échelle réelle
    span = max(stats[n]["mx"].x for n in stats) - min(stats[n]["mn"].x for n in stats)
    scale = LENGTH_M / span
    to_game = Matrix.Scale(scale, 4) @ Matrix.Rotation(math.radians(90.0), 4, "Z") @ Matrix.Translation(-grip)

    # une seule pièce jointe, groupe de sommets = os ; zone par face et position source par
    # sommet stockées en ATTRIBUTS du maillage (ils suivent la jonction, quel que soit l'ordre)
    for o in parts:
        me = o.data
        me.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
        zone = zones.index(zone_of(stats[o.name], bones[o.name]))
        za = me.attributes.new("zone", "INT", "FACE")
        za.data.foreach_set("value", [zone] * len(me.polygons))
        sa = me.attributes.new("src", "FLOAT_VECTOR", "POINT")
        co = np.empty(len(me.vertices) * 3, np.float32)
        me.vertices.foreach_get("co", co)
        sa.data.foreach_set("vector", co)
        vg = o.vertex_groups.new(name=bones[o.name])
        vg.add(list(range(len(me.vertices))), 1.0, "REPLACE")
        me.materials.clear()
    for o in bpy.context.scene.objects:
        o.select_set(o in parts)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    gun = bpy.context.view_layer.objects.active
    gun.name = gun.data.name = "Revolver"
    for o in [o for o in bpy.context.scene.objects if o.type == "EMPTY"]:
        bpy.data.objects.remove(o)
    gun.data.transform(to_game)
    cyl_g = to_game @ cyl_center
    cyl_group = gun.vertex_groups["Cylinder"].index
    rear_y = min(v.co.y for v in gun.data.vertices if any(gr.group == cyl_group for gr in v.groups))
    add_rounds(gun, zones, cyl_g, (to_game @ muzzle).z - cyl_g.z, rear_y)

    # UV : un seul atlas pour toutes les pièces
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60.0), island_margin=0.012)
    bpy.ops.object.mode_set(mode="OBJECT")

    rgba = paint(gun, zones)
    img = bpy.data.images.new("revolver_albedo", RES, RES, alpha=False)
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw = OUT_PNG
    img.file_format = "PNG"
    img.save()
    img.pack()
    mat = bpy.data.materials.new("Revolver")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 1.0
    gun.data.materials.append(mat)
    for name in ("zone", "src"):
        gun.data.attributes.remove(gun.data.attributes[name])

    # squelette : Y des os = avant (Crane/Cylinder), haut (Hammer), bas (Trigger)
    def g(p):
        return to_game @ p
    arm_data = bpy.data.armatures.new("RevolverRig")
    arm = bpy.data.objects.new("RevolverRig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    L = 0.02

    def bone(name, head, direction, parent, z_axis):
        """Os de `head` vers `direction` (axe Y de l'os), axe Z de l'os aligné sur `z_axis`
        (choisi pour que l'axe X de l'os soit l'axe latéral +X quand l'os tourne en tangage)."""
        b = eb.new(name)
        b.head = head
        b.tail = head + direction.normalized() * L
        b.align_roll(z_axis)
        if parent:
            b.parent = eb[parent]
        b.use_deform = True
        return b

    fwd, up = Vector((0, 1, 0)), Vector((0, 0, 1))
    # Root/Crane/Cylinder : Y = avant, X = droite -> rotation Y = basculer / tourner.
    # Hammer : Y = haut, X = droite -> rotation X positive = armer (la crête part en arrière).
    # Trigger : Y = bas, X = droite -> rotation X négative = presser (le bas part en arrière).
    bone("Root", Vector((0, 0, 0)), fwd, None, up)
    bone("Crane", g(hinge), fwd, "Root", up)
    bone("Cylinder", g(cyl_center), fwd, "Crane", up)
    bone("Casings", g(cyl_center), fwd, "Cylinder", up)   # douilles : glissent hors des chambres
    bone("Loader", g(cyl_center), fwd, "Cylinder", up)    # chargeur rapide : rangé dans le barillet au repos
    bone("Hammer", g(piv_hammer), up, "Root", Vector((0, -1, 0)))
    bone("Trigger", g(piv_trigger), -up, "Root", Vector((0, 1, 0)))
    bpy.ops.object.mode_set(mode="OBJECT")
    gun.parent = arm
    mod = gun.modifiers.new("Armature", "ARMATURE")
    mod.object = arm

    for name, p in (("Muzzle", g(muzzle)),):
        e = bpy.data.objects.new(name, None)
        e.empty_display_size = 0.01
        bpy.context.scene.collection.objects.link(e)
        e.parent = arm
        e.location = p

    info = {k: tuple(round(x, 4) for x in g(v)) for k, v in
            (("muzzle", muzzle), ("hinge", hinge), ("cylinder", cyl_center),
             ("hammer", piv_hammer), ("trigger", piv_trigger))}
    print("REVOLVER_BUILD", {"scale": round(scale, 4), **info,
                             "bones": {b: sum(1 for n in bones if bones[n] == b) for b in set(bones.values())}})
    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    export(arm)
    if preview_dir:
        render_preview(arm, gun, preview_dir)


def export(arm):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True,
                              export_yup=True, export_skins=True, export_animations=True,
                              export_animation_mode="ACTIONS", export_image_format="AUTO")
    print("REVOLVER_EXPORT_OK ->", OUT_GLB)


def render_preview(arm, gun, out_dir):
    """Planche : 3 vues au repos + une vue barillet basculé / chien armé (contrôle des pivots)."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_object_outline = True
    sc.render.resolution_x, sc.render.resolution_y = 640, 480
    cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 0.32
    sc.collection.objects.link(cam)
    sc.camera = cam
    os.makedirs(out_dir, exist_ok=True)
    center = Vector((0.0, 0.09, 0.02))
    pb = arm.pose.bones
    views = ((Vector((1, 0, 0)), "droite"), (Vector((-1, 0, 0)), "gauche"),
             (Vector((0.7, -0.5, 0.5)), "trois_quarts"), (Vector((-0.6, 0.5, 0.6)), "ouvert"))
    for d, name in views:
        for b in pb:
            b.rotation_mode = "XYZ"
            b.rotation_euler = (0, 0, 0)
        if name == "ouvert":
            pb["Crane"].rotation_euler = (0, math.radians(-100.0), 0)
            pb["Hammer"].rotation_euler = (math.radians(35.0), 0, 0)
            pb["Trigger"].rotation_euler = (math.radians(-20.0), 0, 0)
        bpy.context.view_layer.update()
        d = d.normalized()
        cam.location = center + d * 1.0
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(out_dir, f"revolver_{name}.png")
        bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    preview = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    build(preview)


main()
