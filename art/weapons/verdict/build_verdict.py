"""Verdict « carabine à levier » (arme 4, id WeaponDatabase 4) : modèle Tripo -> arme de jeu, MÊME
pipeline que le Revolver (art/weapons/revolver/build_revolver.py) -- pièces regroupées par rôle,
peintes en couleurs de sommet, encre de courbure -- MAIS la pièce mobile ("Lever", contrat
tools/blender/make_action_weapons.py/WeaponActionAnim.gd) reste un NŒUD SÉPARÉ plutôt que skinnée à
un squelette : ViewModel._update_action_part tourne ce nœud directement (pas de clip
AnimationPlayer), voir tools/blender/lib/painted_weapon.py pour la doc de tête complète.

Source : assets/incoming/tripo/verdict.glb (Tripo Studio, 29 pièces "tripo_part_N", SANS texture,
tâche "quatre armes v2" 2026-09-28 -- voir assets/models/weapons/verdict.provenance.json). Repère
SOURCE mesuré par sondage (tools/blender, scratch de tâche) : avant = +X (canon), haut = +Z ; PAS une
convention Tripo fixe -- voir Fracas, dont le canon sort à -X pour la MÊME consigne de prompt.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --factory-startup --python art/weapons/verdict/build_verdict.py
"""
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender", "lib"))
import toonkit  # noqa: E402
import painted_weapon as pw  # noqa: E402

SRC = os.path.join(ROOT, "assets", "incoming", "tripo", "verdict.glb")
OUT_GLB = os.path.join(ROOT, "assets", "models", "weapons", "verdict.glb")
# Longueur canon-crosse. Concept "~0,95 m" (contrat lead) -- carabine à levier courte (style 1873).
LENGTH_M = 0.95
FRONT_SIGN = +1.0  # avant SOURCE = +X (mesuré)

PAL = {
    "ink": "#140D08",
    "brass": "#B8912F",      # récepteur laiton poli
    "walnut": "#5E3A1E",     # crosse/garde-main noyer miel
    "gunmetal": "#474D57",   # canon octogonal/tube/levier/hausse
}
ZONES = [z for z in sorted(PAL) if z != "ink"]


def zone_of(s: dict) -> str:
    """Classification PAR PIÈCE (comme build_revolver.py::zone_of) -- heuristique position/taille,
    jamais un index de pièce codé un par un (la segmentation Tripo change de granularité d'une
    génération à l'autre). Repères mesurés sur CE modèle (sondage de tâche) : récepteur/crosse vers
    x < 0.02 environ, canon vers x > 0.02."""
    c, size = s["c"], s["size"]
    if c.x < -0.40:
        return "gunmetal"  # plaque de couche (bout de crosse)
    if c.x < -0.06 and size.z > 0.15 and size.x > 0.20:
        return "walnut"  # crosse (gros bloc arrière)
    if c.x < 0.02:
        return "brass"  # récepteur (bloc central, gravé)
    return "gunmetal"  # canon/tube/bandes/hausse/levier -- tout ce qui est devant le récepteur


def build():
    toonkit.reset_scene()
    bpy.ops.import_scene.gltf(filepath=SRC)
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    stats = {o.name: pw.part_stats(o) for o in parts}

    lever_name = max((n for n in stats if -0.30 <= stats[n]["c"].x <= -0.06 and stats[n]["size"].y < 0.06
                       and stats[n]["faces"] > 800), key=lambda n: stats[n]["faces"], default=None)
    assert lever_name, "levier introuvable (profil bas/plat attendu près du récepteur)"
    lever_obj = bpy.data.objects[lever_name]
    print("VERDICT_LEVER", lever_name, stats[lever_name]["c"], stats[lever_name]["size"])

    # Poignée (origine 0,0,0 du jeu) : au poignet de crosse, juste au-dessus de l'anneau du levier
    # (là où la main tient réellement l'arme) -- PAS le centre du gros bloc crosse (trop en arrière,
    # vers la plaque de couche).
    lv = stats[lever_name]
    grip = Vector((lv["c"].x, 0.0, lv["c"].z + 0.035))

    # canon = la pièce la plus longue devant le récepteur (x > 0.02)
    barrel_name = max((n for n in stats if stats[n]["c"].x > 0.02), key=lambda n: stats[n]["size"].x)
    muzzle_src = Vector((stats[barrel_name]["mx"].x, stats[barrel_name]["c"].y, stats[barrel_name]["c"].z))
    forestock_name = max((n for n in stats if -0.06 <= stats[n]["c"].x <= 0.20 and stats[n]["faces"] > 300),
                         key=lambda n: stats[n]["faces"])
    foregrip_src = Vector((stats[forestock_name]["c"].x, 0.0, stats[forestock_name]["c"].z))

    span = max(stats[n]["mx"].x for n in stats) - min(stats[n]["mn"].x for n in stats)
    scale = LENGTH_M / span
    lift = pw.auto_lift(FRONT_SIGN, scale, grip, muzzle_src)
    to_game = pw.to_game_matrix(FRONT_SIGN, scale, grip, lift=lift)

    body_parts = []
    for o in parts:
        # Le levier (pièce MOBILE) garde toujours "gunmetal" (contrat : "lever ... gunmetal"),
        # jamais la classification générique par position -- son centre X tombe dans la fourchette
        # du récepteur (laiton), qui ne s'applique qu'aux pièces STATIQUES restées dans Body.
        zi = ZONES.index("gunmetal") if o.name == lever_name else ZONES.index(zone_of(stats[o.name]))
        pw.bake_zone_src(o, zi)
        if o.name == lever_name:
            lever_obj = o
        else:
            body_parts.append(o)
    body = toonkit.join(body_parts)
    body.name = body.data.name = "Body"

    for obj in (body, lever_obj):
        obj.data.transform(to_game)
    lever_pivot = to_game @ Vector((lv["c"].x, lv["c"].y, lv["mx"].z))
    pw.recenter_to_pivot(lever_obj, lever_pivot)
    lever_obj.name = "Lever"

    root = bpy.data.objects.new("Verdict", None)
    bpy.context.scene.collection.objects.link(root)
    muzzle = bpy.data.objects.new("Muzzle", None)
    muzzle.empty_display_size = 0.01
    muzzle.location = to_game @ muzzle_src
    bpy.context.scene.collection.objects.link(muzzle)
    foregrip = bpy.data.objects.new("Foregrip", None)
    foregrip.empty_display_size = 0.01
    foregrip.location = to_game @ foregrip_src
    bpy.context.scene.collection.objects.link(foregrip)
    for o in (body, lever_obj, muzzle, foregrip):
        o.parent = root

    pw.paint_vertex_colors(body.data, ZONES, PAL, grain_zones=("walnut",))
    pw.paint_vertex_colors(lever_obj.data, ZONES, PAL, grain_zones=("walnut",))
    body.data.materials.clear()
    body.data.materials.append(pw.make_vertex_color_material("Verdict"))
    lever_obj.data.materials.clear()
    lever_obj.data.materials.append(pw.make_vertex_color_material("Verdict_Lever"))
    for name in ("zone", "src"):
        for obj in (body, lever_obj):
            if name in obj.data.attributes:
                obj.data.attributes.remove(obj.data.attributes[name])

    print("VERDICT_BUILD", {"scale": round(scale, 4), "lift": round(lift, 4), "grip": tuple(round(x, 4) for x in grip),
                            "muzzle": tuple(round(x, 4) for x in (to_game @ muzzle_src))})
    toonkit.export_glb(OUT_GLB, [root, body, lever_obj, muzzle, foregrip])


build()
