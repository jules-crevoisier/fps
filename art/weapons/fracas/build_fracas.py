"""Fracas « fusil à pompe » (arme 3, id WeaponDatabase 3) : modèle Tripo -> arme de jeu, même
pipeline que Rafale/Verdict/Aiguille/le Revolver -- voir tools/blender/lib/painted_weapon.py pour la
doc de tête partagée. Pièce mobile : "PumpGrip" (garde-main coulissant, contrat tools/blender/
make_action_weapons.py/WeaponActionAnim.gd) -- TRANSLATE seulement (cas "PumpGrip" de
ViewModel._update_action_part).

Contrairement au Levier (Verdict) ou au Verrou (Aiguille), le garde-main n'est PAS une pièce Tripo
séparée : la segmentation a fusionné canon + tube + garde-main en UN SEUL bloc continu -- MAIS un
sondage de profil (hauteur de section par tranche de X, script de tâche) y révèle DEUX ruptures
nettes (hauteur ~0,10 sur le canon, ~0,20 sur le garde-main, ~0,11 en approchant du récepteur) : une
VRAIE variation de silhouette dans le maillage, pas un point arbitraire. `_PUMP_X_RANGE` ci-dessous
reprend ces deux bornes mesurées pour détacher le garde-main proprement
(tools/blender/lib/painted_weapon.py::split_by_x_range), plutôt que de trancher à travers un tube
lisse.

Repère SOURCE mesuré par sondage : avant = -X (canon), haut = +Z -- INVERSE de Rafale/Verdict/
Aiguille pour la MÊME consigne de prompt Tripo Studio (pas une convention Tripo garantie).

Source : assets/incoming/tripo/fracas.glb (Tripo Studio, 30 pièces "tripo_part_N", SANS texture,
tâche "quatre armes v2" 2026-09-28 -- voir assets/models/weapons/fracas.provenance.json).

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --factory-startup --python art/weapons/fracas/build_fracas.py
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

SRC = os.path.join(ROOT, "assets", "incoming", "tripo", "fracas.glb")
OUT_GLB = os.path.join(ROOT, "assets", "models", "weapons", "fracas.glb")
## Concept "~0,80 m" (contrat lead) -- MAIS l'arme est tenue par FPArmsRig avec une contre-échelle
## FIXE (FPArmsMath.RIG_SCALE, pas de réglage par arme comme l'ancien weapon_scale_for, INACTIF
## pour Verrou) : à 0,80 m, la poignée (proche du récepteur, x=0,28 source -- voir `grip` plus bas)
## laisse le canon fusionné (0,78 des 0,80 m, x de -0,5 à 0,28) envahir tout le cadre FP (constaté
## par capture, tâche "quatre armes v2" -- voir reports/checkpoints/2026-09-28_weapons/fracas_fps.png
## de ce passage). Réduit à la taille qui cadre bien (mesure au même titre que le reste de ce
## fichier), toujours dans l'esprit "silhouette chunky, proportions exagérées" du contrat.
LENGTH_M = 0.58
FRONT_SIGN = -1.0  # avant SOURCE = -X (mesuré, INVERSE des 3 autres armes)
# Bornes mesurées (sondage de profil, tâche) : rupture de silhouette canon -> garde-main -> récepteur.
_PUMP_X_RANGE = (-0.336, -0.125)

PAL = {
    "ink": "#0A0D12",
    "blued_steel": "#5C636D",  # canon/tube/récepteur/pontet/bande
    "walnut": "#3D2612",       # crosse + poignet + garde-main (bois)
    "brass": "#B8912F",        # rivets/vis du récepteur
}
ZONES = [z for z in sorted(PAL) if z != "ink"]


def zone_of(s: dict) -> str:
    c, size = s["c"], s["size"]
    if s["faces"] < 90 and -0.05 <= c.x <= 0.25:
        return "brass"  # rivets/vis du récepteur
    if c.x > 0.20 and c.z > 0.10:
        return "walnut"  # crosse + poignet (bois) -- exclut le pontet, bas et métallique
    return "blued_steel"  # canon/tube/récepteur/pontet/bande


def build():
    toonkit.reset_scene()
    bpy.ops.import_scene.gltf(filepath=SRC)
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    stats = {o.name: pw.part_stats(o) for o in parts}

    barrel_name = max(stats, key=lambda n: stats[n]["faces"])
    barrel_stats = dict(stats[barrel_name])  # copie : sert de repère canon/muzzle AVANT la coupe
    print("FRACAS_BARREL", barrel_name, barrel_stats["c"], barrel_stats["size"])
    barrel_obj = bpy.data.objects[barrel_name]
    pump_obj = pw.split_by_x_range(barrel_obj, _PUMP_X_RANGE[0], _PUMP_X_RANGE[1], "PumpGrip_src")
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    stats = {o.name: pw.part_stats(o) for o in parts}  # recalcul (deux objets à la place d'un seul)

    grip = Vector((0.28, 0.0, 0.11))  # poignet de crosse, sous le récepteur (mesuré à l'œil sur bbox)
    muzzle_src = Vector((barrel_stats["mn"].x, barrel_stats["c"].y, barrel_stats["c"].z))
    foregrip_src = Vector((sum(_PUMP_X_RANGE) * 0.5, 0.0, 0.22))

    span = max(stats[n]["mx"].x for n in stats) - min(stats[n]["mn"].x for n in stats)
    scale = LENGTH_M / span
    lift = pw.auto_lift(FRONT_SIGN, scale, grip, muzzle_src)
    to_game = pw.to_game_matrix(FRONT_SIGN, scale, grip, lift=lift)

    body_parts = []
    for o in parts:
        # Le garde-main coulissant (pièce MOBILE) reste "walnut" (contrat : "pump grip ... dark
        # walnut"), jamais la classification générique -- sa position (x négatif) chevauche la
        # fourchette du canon (acier bleui) qui ne s'applique qu'aux pièces STATIQUES de Body.
        zi = ZONES.index("walnut") if o is pump_obj else ZONES.index(zone_of(stats[o.name]))
        pw.bake_zone_src(o, zi)
        if o is not pump_obj:
            body_parts.append(o)
    body = toonkit.join(body_parts)
    body.name = body.data.name = "Body"

    for obj in (body, pump_obj):
        obj.data.transform(to_game)
    pump_pivot = to_game @ Vector((sum(_PUMP_X_RANGE) * 0.5, 0.0, stats[pump_obj.name]["c"].z))
    pw.recenter_to_pivot(pump_obj, pump_pivot)
    pump_obj.name = "PumpGrip"

    root = bpy.data.objects.new("Fracas", None)
    bpy.context.scene.collection.objects.link(root)
    muzzle = bpy.data.objects.new("Muzzle", None)
    muzzle.empty_display_size = 0.01
    muzzle.location = to_game @ muzzle_src
    bpy.context.scene.collection.objects.link(muzzle)
    foregrip = bpy.data.objects.new("Foregrip", None)
    foregrip.empty_display_size = 0.01
    foregrip.location = to_game @ foregrip_src
    bpy.context.scene.collection.objects.link(foregrip)
    for o in (body, pump_obj, muzzle, foregrip):
        o.parent = root

    pw.paint_vertex_colors(body.data, ZONES, PAL, grain_zones=("walnut",))
    pw.paint_vertex_colors(pump_obj.data, ZONES, PAL, grain_zones=("walnut",))
    body.data.materials.clear()
    body.data.materials.append(pw.make_vertex_color_material("Fracas"))
    pump_obj.data.materials.clear()
    pump_obj.data.materials.append(pw.make_vertex_color_material("Fracas_PumpGrip"))
    for name in ("zone", "src"):
        for obj in (body, pump_obj):
            if name in obj.data.attributes:
                obj.data.attributes.remove(obj.data.attributes[name])

    print("FRACAS_BUILD", {"scale": round(scale, 4), "lift": round(lift, 4), "grip": tuple(round(x, 4) for x in grip),
                           "muzzle": tuple(round(x, 4) for x in (to_game @ muzzle_src))})
    toonkit.export_glb(OUT_GLB, [root, body, pump_obj, muzzle, foregrip])


build()
