"""Rafale « mitraillette compacte » (arme 2, id WeaponDatabase 2) : modèle Tripo -> arme de jeu,
même pipeline que Verdict/Aiguille/le Revolver -- voir tools/blender/lib/painted_weapon.py pour la
doc de tête partagée. Pièce mobile : "Magazine" (chargeur, contrat tools/blender/
make_action_weapons.py/WeaponActionAnim.gd) -- TRANSLATE seulement (cas "Magazine" de
ViewModel._update_action_part : réutilise le dip de rechargement générique, amplifié), donc son
origine n'a pas besoin d'être un pivot mécanique exact.

Le chargeur n'est PAS un volume séparé sur ce modèle : la segmentation Tripo a fusionné poignée et
chargeur en UN SEUL bloc vertical (silhouette « chargeur dans la poignée », comme certaines
mitraillettes compactes réelles) -- aucune coupure nette au profil (sondé par script, tâche) pour
séparer proprement l'un de l'autre sans trancher à travers un volume lisse. Décision : TOUT le bloc
devient le nœud "Magazine" (tout le bloc poignée+chargeur plonge légèrement au rechargement) plutôt
que de forcer une coupe arbitraire -- accepté comme simplification stylisée, à revoir seulement si un
futur modèle Rafale sépare vraiment les deux volumes.

Source : assets/incoming/tripo/rafale.glb (Tripo Studio, 59 pièces "tripo_part_N", SANS texture,
tâche "quatre armes v2" 2026-09-28 -- voir assets/models/weapons/rafale.provenance.json). Repère
SOURCE : avant = -X (canon), haut = +Z -- RECORRIGÉ 2026-09-28 (playtest utilisateur, voir FRONT_SIGN
ci-dessous) : la 1re mesure ("avant = +X") était fausse, l'arme rendait canon-vers-la-caméra en jeu.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --factory-startup --python art/weapons/rafale/build_rafale.py
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

SRC = os.path.join(ROOT, "assets", "incoming", "tripo", "rafale.glb")
OUT_GLB = os.path.join(ROOT, "assets", "models", "weapons", "rafale.glb")
LENGTH_M = 0.60  # concept "~0,60 m" (contrat lead) -- SMG compacte
## CORRIGÉ (2026-09-28, playtest utilisateur : « le Rafale est complètement à l'envers », canon
## vers la caméra, crosse vers l'écran) -- la mesure initiale (+1.0, avant SOURCE = +X) prenait le
## bloc "canon/garde-main ajouré" (zone_of, c.x > 0.18) pour l'avant, mais la crosse fil (nombreux
## brins fins, c.x < -0.24) a une section PLUS FINE que le garde-main ajouré à cette silhouette
## précise (constaté par sondage -- outil probe_orientation, ratio de section ambigu ~1.2x -- une
## crosse fil n'est PAS le bloc massif que l'heuristique "plus fin = canon" suppose en général,
## contrairement à Fracas/Verdict/Aiguille dont la crosse est un bloc de bois/métal net) : seul un
## rendu en jeu (fp_shots) tranche sans ambiguïté ici. -X est bien le canon (confirmé par capture
## après ce correctif).
FRONT_SIGN = -1.0  # avant SOURCE = -X (corrigé -- était +X par erreur)

PAL = {
    "ink": "#0E0C08",
    "yellow": "#FFCE1F",     # panneaux de corps
    "cobalt": "#2E8BFF",     # flancs/inserts de poignée
    "gunmetal": "#474D57",   # canon ajouré/rails/crosse fil/chargeur/hausse
}
ZONES = [z for z in sorted(PAL) if z != "ink"]


def zone_of(s: dict) -> str:
    c = s["c"]
    if c.x < -0.24:
        return "gunmetal"  # canon/garde-main ajouré (RECORRIGÉ -- « avant » est -X, pas +X)
    if c.x > 0.18:
        return "gunmetal"  # crosse fil (nombreux brins) + bloc de fixation
    if c.z > 0.38:
        return "gunmetal"  # hausse/rail dessus
    if abs(c.y) > 0.035 and 0.18 < c.z < 0.36:
        return "cobalt"  # flancs de carcasse
    if abs(c.y) > 0.020 and c.z < 0.17:
        return "cobalt"  # inserts de poignée
    return "yellow"  # panneaux de corps (polymère)


def build():
    toonkit.reset_scene()
    bpy.ops.import_scene.gltf(filepath=SRC)
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    stats = {o.name: pw.part_stats(o) for o in parts}

    # Poignée+chargeur fusionnés : la pièce qui descend le plus bas (mn.z minimal) parmi les blocs
    # significatifs proches du centre du corps (x entre le récepteur et l'avant du canon).
    mag_name = min((n for n in stats if 0.0 <= stats[n]["c"].x <= 0.20 and stats[n]["faces"] > 500),
                   key=lambda n: stats[n]["mn"].z)
    assert mag_name, "poignée/chargeur introuvable"
    print("RAFALE_MAGAZINE", mag_name, stats[mag_name]["c"], stats[mag_name]["size"])

    grip = Vector((stats[mag_name]["c"].x, 0.0, 0.17))

    # RECORRIGÉ (2026-09-28, playtest utilisateur -- voir la doc de tête/FRONT_SIGN) : « avant » est
    # -X, pas +X -- le canon/garde-main ajouré est donc la pièce marquante côté x < -0.24 (ex-
    # « crosse fil » mal étiquetée), sa pointe la plus avancée étant son minimum X (pas son maximum,
    # inversé par rapport à l'ancienne lecture +X).
    shroud_name = max((n for n in stats if stats[n]["c"].x < -0.24), key=lambda n: stats[n]["faces"])
    muzzle_src = Vector((stats[shroud_name]["mn"].x, stats[shroud_name]["c"].y, stats[shroud_name]["c"].z))
    foregrip_src = Vector((-0.30, 0.0, stats[shroud_name]["c"].z))

    span = max(stats[n]["mx"].x for n in stats) - min(stats[n]["mn"].x for n in stats)
    scale = LENGTH_M / span
    # Arme tenue par FPArmsRig (os "WeaponGrip", transform locale IDENTITÉ) -- PAS par
    # ViewModel._place_weapon/weapon_nudge_for (repli gants flottants, INACTIF pour Verrou, constaté
    # par capture tâche "quatre armes v2") : la hauteur à l'écran vient ENTIÈREMENT de la géométrie,
    # voir tools/blender/lib/painted_weapon.py::auto_lift/TARGET_MUZZLE_Z.
    lift = pw.auto_lift(FRONT_SIGN, scale, grip, muzzle_src)
    to_game = pw.to_game_matrix(FRONT_SIGN, scale, grip, lift=lift)

    mag_obj = None
    body_parts = []
    for o in parts:
        # Le chargeur (pièce MOBILE) reste "gunmetal" (contrat : "magazine ... gunmetal"), jamais la
        # classification générique -- sa position (près du centre, bas) chevauche la fourchette des
        # inserts poignée/flancs (cobalt) qui ne s'applique qu'aux pièces STATIQUES de Body.
        zi = ZONES.index("gunmetal") if o.name == mag_name else ZONES.index(zone_of(stats[o.name]))
        pw.bake_zone_src(o, zi)
        if o.name == mag_name:
            mag_obj = o
        else:
            body_parts.append(o)
    body = toonkit.join(body_parts)
    body.name = body.data.name = "Body"

    for obj in (body, mag_obj):
        obj.data.transform(to_game)
    mag_pivot = to_game @ Vector((stats[mag_name]["c"].x, stats[mag_name]["c"].y, stats[mag_name]["mx"].z))
    pw.recenter_to_pivot(mag_obj, mag_pivot)
    mag_obj.name = "Magazine"

    root = bpy.data.objects.new("Rafale", None)
    bpy.context.scene.collection.objects.link(root)
    muzzle = bpy.data.objects.new("Muzzle", None)
    muzzle.empty_display_size = 0.01
    muzzle.location = to_game @ muzzle_src
    bpy.context.scene.collection.objects.link(muzzle)
    foregrip = bpy.data.objects.new("Foregrip", None)
    foregrip.empty_display_size = 0.01
    foregrip.location = to_game @ foregrip_src
    bpy.context.scene.collection.objects.link(foregrip)
    for o in (body, mag_obj, muzzle, foregrip):
        o.parent = root

    pw.paint_vertex_colors(body.data, ZONES, PAL)
    pw.paint_vertex_colors(mag_obj.data, ZONES, PAL)
    body.data.materials.clear()
    body.data.materials.append(pw.make_vertex_color_material("Rafale"))
    mag_obj.data.materials.clear()
    mag_obj.data.materials.append(pw.make_vertex_color_material("Rafale_Magazine"))
    for name in ("zone", "src"):
        for obj in (body, mag_obj):
            if name in obj.data.attributes:
                obj.data.attributes.remove(obj.data.attributes[name])

    print("RAFALE_BUILD", {"scale": round(scale, 4), "lift": round(lift, 4),
                           "grip": tuple(round(x, 4) for x in grip),
                           "muzzle": tuple(round(x, 4) for x in (to_game @ muzzle_src))})
    toonkit.export_glb(OUT_GLB, [root, body, mag_obj, muzzle, foregrip])


build()
