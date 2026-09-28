"""Aiguille « sniper à verrou » (arme 5, id WeaponDatabase 5) : modèle Tripo -> arme de jeu, même
pipeline que Verdict/le Revolver -- voir tools/blender/lib/painted_weapon.py pour la doc de tête
partagée ("une seule texture, deux objets"). Pièce mobile : "Bolt" (poignée de culasse, contrat
tools/blender/make_action_weapons.py/WeaponActionAnim.gd) -- TRANSLATE seulement
(ViewModel._update_action_part, cas "Bolt"), donc son origine locale n'a pas besoin d'être un pivot
mécanique exact (contrairement au "Lever" du Verdict, qui TOURNE) : le centre de son propre volume
suffit, voir tools/blender/lib/painted_weapon.py::recenter_to_pivot.

Source : assets/incoming/tripo/aiguille.glb (Tripo Studio, 44 pièces "tripo_part_N", SANS texture,
tâche "quatre armes v2" 2026-09-28 -- voir assets/models/weapons/aiguille.provenance.json). Repère
SOURCE mesuré par sondage : avant = +X (canon), haut = +Z (même sens que Rafale/Verdict -- PAS une
convention Tripo garantie, voir Fracas, dont le canon sort à -X).

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --factory-startup --python art/weapons/aiguille/build_aiguille.py
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

SRC = os.path.join(ROOT, "assets", "incoming", "tripo", "aiguille.glb")
OUT_GLB = os.path.join(ROOT, "assets", "models", "weapons", "aiguille.glb")
## Concept "~1,20 m" -- MAIS l'arme est tenue par FPArmsRig avec une contre-échelle FIXE
## (FPArmsMath.RIG_SCALE, pas de réglage par arme comme l'ancien weapon_scale_for, INACTIF pour
## Verrou) : à 1,20 m, la grosse lunette (proche de la poignée) envahissait tout le cadre FP
## (constaté par capture, tâche "quatre armes v2"). Réduit vers la taille du Ravage (0,945 m, seule
## autre arme aussi longue tenue par CE MÊME rig) plutôt que la longueur "réaliste" d'un fusil de
## précision.
LENGTH_M = 0.72
FRONT_SIGN = +1.0  # avant SOURCE = +X (mesuré)

## REPEINT (2026-09-28, retour utilisateur : « gris-bleu terne, bruit de peinture de sommet par
## endroits ») -- nouvelle palette (concept choisi par l'utilisateur) : crosse+carcasse en cobalt,
## repose-pouce/plaque de couche/détente/capuchons de lunette en jaune signal (accents), tube/bagues
## de lunette/canon/frein de bouche/bipied/verrou/chargeur en gunmetal SOMBRE (#34313F, pas le
## #6E7580 clair d'avant -- consigne "DARK gunmetal (not light grey)").
PAL = {
    "ink": "#0C1420",
    "cobalt": "#2E8BFF",     # crosse + carcasse (châssis bullpup monobloc)
    "yellow": "#FFCE1F",     # repose-pouce, plaque de couche, détente, capuchons de lunette
    "gunmetal": "#34313F",   # tube/bagues lunette, canon, frein de bouche, bipied, verrou, chargeur
}
ZONES = [z for z in sorted(PAL) if z != "ink"]


def zone_of(s: dict) -> str:
    """Heuristique position/taille (comme build_revolver.py::zone_of), mesurée sur CE modèle."""
    c, size = s["c"], s["size"]
    if c.x < -0.45:
        return "yellow"  # plaque de couche, tout au bout de la crosse
    if c.x < -0.10 and size.x > 0.15:
        return "cobalt"  # crosse -- gros bloc arrière
    if -0.18 <= c.x <= 0.10 and 0.08 < c.z <= 0.19 and size.y <= 0.09:
        # Carcasse/châssis + habillage visible du récepteur (bande position/hauteur, PAS un seul
        # gros bloc : sondage par rendu -- tripo_part_0, LE bloc monobloc qui court sur près de la
        # moitié de la longueur de l'arme, s'est avéré ENTIÈREMENT masqué par les petites pièces de
        # boîtier/rail qui l'habillent -- le peindre seul ne changeait rien à l'écran). Bande
        # bornée par : la hauteur de la crosse elle-même (0.08, au-dessus du chargeur qui descend
        # plus bas) jusqu'au bas du groupe lunette (0.19, voir son propre seuil plus bas) ; la
        # poignée de culasse (asymétrique, size.y > 0.09) est explicitement exclue -- seul filtre
        # POSITION/TAILLE qui la distingue ici, jamais son nom "tripo_part_13" codé en dur (déjà
        # trouvé par `bolt_name` ci-dessus, colorée gunmetal comme le contrat "verrou").
        return "cobalt"  # carcasse/châssis
    return "gunmetal"  # canon/frein de bouche/tube+bagues lunette/bipied/verrou/chargeur/sous-garde


def _small_accent_parts(stats: dict) -> dict:
    """Pièces D'ACCENT (jaune signal) trouvées par heuristique position/taille -- jamais un index de
    pièce codé en dur (la segmentation Tripo change de granularité d'une génération à l'autre, même
    discipline que `zone_of`) : le repose-pouce (petit bloc distinct posé sur le dessus-avant de la
    crosse), le groupe détente (petit amas distinct juste devant la crosse, sous la carcasse) et les
    deux capuchons de lunette (les pièces aux DEUX extrémités X du groupe lunette, capuchons
    articulés/protections d'objectif -- voir le sondage par rendu ID isolé, tâche "repeinture
    Aiguille"). Retourne {nom_pièce: "yellow"} -- fusionné par l'appelant dans les zones normales de
    `zone_of` (mêmes pièces gunmetal par défaut sinon)."""
    out: dict = {}

    stock_name = next((n for n in stats if stats[n]["c"].x < -0.10 and stats[n]["size"].x > 0.15), None)
    if stock_name:
        s_mn, s_mx = stats[stock_name]["mn"], stats[stock_name]["mx"]
        candidates = [n for n in stats if n != stock_name
                      and s_mn.x <= stats[n]["c"].x <= s_mx.x
                      # Fenêtre Z bornée par le HAUT de la crosse elle-même (`s_mx.z`) : exclut les
                      # pièces de la LUNETTE (hauteur bien plus grande, x chevauchant celui de la
                      # crosse sur ce bullpup -- constaté : tripo_part_15, un des deux capuchons de
                      # lunette, satisfait sinon aussi ce filtre et l'emporte sur le VRAI repose-pouce
                      # au tri par nombre de faces).
                      and s_mn.z + 0.6 * (s_mx.z - s_mn.z) < stats[n]["c"].z <= s_mx.z
                      and stats[n]["faces"] < 500
                      and stats[n]["size"].y > 0.03]
        if candidates:
            out[max(candidates, key=lambda n: stats[n]["faces"])] = "yellow"  # repose-pouce

    trigger_names = [n for n in stats if -0.18 <= stats[n]["c"].x <= -0.13
                     and stats[n]["c"].z < 0.15 and stats[n]["size"].y < 0.03]
    for n in trigger_names:
        out[n] = "yellow"  # détente (petit amas devant la crosse -- garde comprise)

    # faces > 150 : écarte les petites pièces de garniture (vis/bagues fines, ex. tripo_part_40,
    # 61 faces) qui dépassent parfois légèrement plus en X que le VRAI capuchon (un bloc bien plus
    # détaillé, > 250 faces sur cette génération) -- sans ce filtre, min()/max() ci-dessous
    # retombent sur la garniture plutôt que sur le capuchon.
    scope_names = [n for n in stats if stats[n]["c"].z > 0.19 and stats[n]["c"].x < 0.15
                   and stats[n]["faces"] > 150]
    if scope_names:
        out[min(scope_names, key=lambda n: stats[n]["c"].x)] = "yellow"  # capuchon arrière
        out[max(scope_names, key=lambda n: stats[n]["c"].x)] = "yellow"  # capuchon avant/objectif

    return out


def build():
    toonkit.reset_scene()
    bpy.ops.import_scene.gltf(filepath=SRC)
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    stats = {o.name: pw.part_stats(o) for o in parts}

    # Poignée de culasse : pièce nettement ASYMÉTRIQUE en Y (dépasse d'un flanc, contrairement à
    # tout le reste du modèle -- quasi symétrique autour de son propre centre Y) ET positionnée
    # entre récepteur et crosse (x négatif, avant la crosse elle-même) -- voir la doc de tête.
    bolt_name = max((n for n in stats if -0.25 <= stats[n]["c"].x <= -0.05 and stats[n]["size"].y > 0.09),
                    key=lambda n: stats[n]["size"].y)
    assert bolt_name, "poignée de culasse introuvable (pièce asymétrique attendue près du récepteur)"
    print("AIGUILLE_BOLT", bolt_name, stats[bolt_name]["c"], stats[bolt_name]["size"])

    grip = Vector((-0.20, 0.0, 0.085))  # sous-garde/poignée de crosse, mesuré à l'œil sur les bbox

    barrel_name = max((n for n in stats if stats[n]["c"].x > 0.10), key=lambda n: stats[n]["size"].x)
    muzzle_src = Vector((stats[barrel_name]["mx"].x, stats[barrel_name]["c"].y, stats[barrel_name]["c"].z))
    foregrip_src = Vector((0.12, 0.0, stats[barrel_name]["c"].z - 0.05))

    span = max(stats[n]["mx"].x for n in stats) - min(stats[n]["mn"].x for n in stats)
    scale = LENGTH_M / span
    lift = pw.auto_lift(FRONT_SIGN, scale, grip, muzzle_src)
    to_game = pw.to_game_matrix(FRONT_SIGN, scale, grip, lift=lift)

    # Accents jaune signal (repose-pouce/détente/capuchons de lunette -- voir la doc de
    # `_small_accent_parts`) : calculés UNE FOIS sur toutes les pièces sources, fusionnés dans la
    # classification normale ci-dessous (repli sur `zone_of` pour toute pièce absente de ce dict).
    accents = _small_accent_parts(stats)
    print("AIGUILLE_ACCENTS", accents)

    bolt_obj = None
    body_parts = []
    for o in parts:
        zi = ZONES.index(accents.get(o.name) or zone_of(stats[o.name]))
        pw.bake_zone_src(o, zi)
        if o.name == bolt_name:
            bolt_obj = o
        else:
            body_parts.append(o)
    body = toonkit.join(body_parts)
    body.name = body.data.name = "Body"

    for obj in (body, bolt_obj):
        obj.data.transform(to_game)
    bolt_pivot = to_game @ stats[bolt_name]["c"]
    pw.recenter_to_pivot(bolt_obj, bolt_pivot)
    bolt_obj.name = "Bolt"

    root = bpy.data.objects.new("Aiguille", None)
    bpy.context.scene.collection.objects.link(root)
    muzzle = bpy.data.objects.new("Muzzle", None)
    muzzle.empty_display_size = 0.01
    muzzle.location = to_game @ muzzle_src
    bpy.context.scene.collection.objects.link(muzzle)
    foregrip = bpy.data.objects.new("Foregrip", None)
    foregrip.empty_display_size = 0.01
    foregrip.location = to_game @ foregrip_src
    bpy.context.scene.collection.objects.link(foregrip)
    for o in (body, bolt_obj, muzzle, foregrip):
        o.parent = root

    # `curvature_scale` relevé (voir sa doc dans painted_weapon.py) : le maillage Tripo brut de
    # l'Aiguille n'est jamais parfaitement plan même sur les grands panneaux (carcasse/flancs de
    # crosse), l'encre de courbure par défaut y retombait en TACHES plutôt que sur les vraies
    # arêtes/creux (retour utilisateur, tâche "repeinture Aiguille") -- Rafale/Fracas/Verdict/
    # Revolver restent au calibrage par défaut (1.0), inchangés.
    pw.paint_vertex_colors(body.data, ZONES, PAL, curvature_scale=2.2)
    pw.paint_vertex_colors(bolt_obj.data, ZONES, PAL, curvature_scale=2.2)
    body.data.materials.clear()
    body.data.materials.append(pw.make_vertex_color_material("Aiguille"))
    bolt_obj.data.materials.clear()
    bolt_obj.data.materials.append(pw.make_vertex_color_material("Aiguille_Bolt"))
    for name in ("zone", "src"):
        for obj in (body, bolt_obj):
            if name in obj.data.attributes:
                obj.data.attributes.remove(obj.data.attributes[name])

    print("AIGUILLE_BUILD", {"scale": round(scale, 4), "lift": round(lift, 4), "grip": tuple(round(x, 4) for x in grip),
                             "muzzle": tuple(round(x, 4) for x in (to_game @ muzzle_src))})
    toonkit.export_glb(OUT_GLB, [root, body, bolt_obj, muzzle, foregrip])


build()
