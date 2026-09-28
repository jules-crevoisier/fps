"""Rafale « mitraillette compacte » (arme 2, id WeaponDatabase 2) : modèle Tripo -> arme de jeu,
même pipeline que Verdict/Aiguille/le Revolver -- voir tools/blender/lib/painted_weapon.py pour la
doc de tête partagée. Pièce mobile : "Magazine" (chargeur, contrat tools/blender/
make_action_weapons.py/WeaponActionAnim.gd) -- TRANSLATE seulement (cas "Magazine" de
ViewModel._update_action_part : réutilise le dip de rechargement générique, amplifié), donc son
origine n'a pas besoin d'être un pivot mécanique exact.

CORRIGÉ (2026-09-28, playtest utilisateur : « la main ne tient pas la crosse du Rafale, l'arme
flotte en bas à droite ») -- la lecture précédente de ce script était FAUSSE : poignée et chargeur ne
sont PAS fusionnés sur ce modèle (silhouette Kriss Vector -- chargeur nettement AVANCÉ devant la
poignée, garde-détente entre les deux, voir le sondage par rendu ID par pièce, tâche). Le filtre qui
cherchait le "bloc poignée+chargeur" (0.0<=c.x<=0.20, faces>500, mn.z minimal) trouvait en réalité
LA POIGNÉE SEULE ("tripo_part_3" dans la génération source, jamais un index codé en dur ici -- voir
`grip_name` ci-dessous, MÊME filtre, juste renommé) : elle devenait donc, à tort, le nœud "Magazine"
qui TRANSLATE au rechargement (`ViewModel._update_action_part`, cas "Magazine") -- la poignée
entière plongeait donc légèrement à chaque rechargement, et surtout l'origine de TOUTE l'arme
(calculée depuis `grip`, voir `to_game_matrix`) utilisait une hauteur Z devinée à l'œil (0.17, ni le
bas ni le haut réel de la poignée) plutôt qu'un point mesuré sur la poignée -- d'où une arme qui ne
« tombe » pas correctement dans la main posée par FPArmsRig (os "WeaponGrip", transform locale
IDENTITÉ, voir sa docstring de classe).

Fix : `grip_name` (MÊME filtre position/taille qu'avant, juste renommé -- il isole déjà correctement
LA POIGNÉE, pas le chargeur) reste dans `body_parts` (statique, plus de dip au rechargement) ; un
NOUVEAU filtre trouve le VRAI chargeur (`mag_name` : parmi les pièces significatives -- faces>500 --
situées à x <= 0.02 SOURCE, c-a-d à hauteur du récepteur ou en avant -- jamais aussi loin en arrière
que la poignée, x=0.081 -- celle qui descend le plus bas, mn.z minimal ; sélectionne "tripo_part_5"
sur cette génération, un bloc net et distinct, faces=815) et devient SEUL le nœud "Magazine". L'origine
de l'arme (`grip`, passé à `to_game_matrix`) prend désormais le CENTRE (x,y) de la poignée mais son
HAUT réel (`mx.z`, mesuré -- pas deviné) : « le haut de la poignée », même convention que le Ravage
(origine posée sur la poignée, jamais en l'air ni sous le maillage).

2e correctif (relecture des captures par le lead, même tâche) : la crosse fil droite dépassait vers
le haut-droit de l'écran (l'arme est courte, TARGET_MUZZLE_Z cale le canon près de la caméra, donc la
crosse ÉTENDUE finissait devant l'objectif plutôt qu'à l'épaule). Le concept prévoyait une crosse
REPLIABLE -- voir `stock_name`/`fold` dans `build()` : repliée à 180° autour d'une charnière VERTICALE
mesurée sur son propre bord d'attache, elle vient se loger contre le flanc droit de la carcasse, sous
le viseur (une rotation pure autour de Z ne change jamais la hauteur).

Source : assets/incoming/tripo/rafale.glb (Tripo Studio, 59 pièces "tripo_part_N", SANS texture,
tâche "quatre armes v2" 2026-09-28 -- voir assets/models/weapons/rafale.provenance.json). Repère
SOURCE : avant = -X (canon), haut = +Z -- RECORRIGÉ 2026-09-28 (playtest utilisateur, voir FRONT_SIGN
ci-dessous) : la 1re mesure ("avant = +X") était fausse, l'arme rendait canon-vers-la-caméra en jeu.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --factory-startup --python art/weapons/rafale/build_rafale.py
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

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
## Crosse fil repliée contre le flanc (True) ou dépliée vers l'épaule (False, choix utilisateur 2026-09-28).
STOCK_FOLDED = False
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

    # Poignée (voir la doc de tête -- ex-"mag_name", MÊME filtre, juste renommé) : la pièce qui
    # descend le plus bas (mn.z minimal) parmi les blocs significatifs proches du centre du corps
    # (x entre le récepteur et l'avant du canon) -- isole déjà correctement LA POIGNÉE SEULE sur ce
    # modèle (elle est la seule pièce >500 faces dans cette fourchette de x).
    grip_name = min((n for n in stats if 0.0 <= stats[n]["c"].x <= 0.20 and stats[n]["faces"] > 500),
                    key=lambda n: stats[n]["mn"].z)
    assert grip_name, "poignée introuvable"
    print("RAFALE_GRIP", grip_name, stats[grip_name]["c"], stats[grip_name]["size"])

    # Chargeur (voir la doc de tête) : parmi les pièces significatives situées à hauteur du récepteur
    # ou en avant (x <= 0.02, donc STRICTEMENT devant la poignée, x=0.081 pour `grip_name` ci-dessus),
    # celle qui descend le plus bas -- un bloc net et distinct de la poignée (silhouette Kriss Vector,
    # chargeur avancé devant la garde-détente).
    mag_name = min((n for n in stats if stats[n]["c"].x <= 0.02 and stats[n]["faces"] > 500),
                   key=lambda n: stats[n]["mn"].z)
    assert mag_name and mag_name != grip_name, "chargeur introuvable (ou confondu avec la poignée)"
    print("RAFALE_MAGAZINE", mag_name, stats[mag_name]["c"], stats[mag_name]["size"])

    # Origine de l'arme = HAUT de la poignée (mx.z, MESURÉ -- plus une hauteur devinée à l'œil), même
    # convention que le Ravage (voir la doc de tête) : le point que la main de FPArmsRig referme
    # dessus, jamais un point en l'air ni sous le maillage.
    grip = Vector((stats[grip_name]["c"].x, 0.0, stats[grip_name]["mx"].z))

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

    # Repliage de la crosse fil (consigne du lead après relecture des captures, 2026-09-28 : « the
    # gun is short so the straight stock ends in front of the camera instead of at the shoulder --
    # show it FOLDED »). AVANT le calcul span/scale/grip/muzzle_src ci-dessus n'utilise QUE
    # `shroud_name`/`grip_name`/`mag_name` -- jamais la crosse -- donc repliée APRÈS ce calcul, le
    # cadrage (poignée/canon) déjà réglé (voir la doc de tête, 3e passage) n'est PAS affecté ; seule
    # la silhouette de la crosse change. Isolée comme ses PROPRES objets Blender (pas de nœud "Stock"
    # séparé dans l'export -- rien ne l'anime en jeu, contrairement au "Magazine" -- juste un moyen
    # de pivoter SES sommets sans entraîner le reste de la carcasse) : repère SOURCE (avant to_game).
    # `stock_names` : PLUSIEURS pièces (pas une seule) -- sondage complet (toutes les pièces à
    # c.x > 0.10) montre que la segmentation Tripo a coupé l'ensemble crosse+patte de fixation en
    # QUATRE morceaux distincts (le grand fil "tripo_part_2", c.x=0.344, ET trois petites pièces de
    # bride/fixation groupées c.x=0.145-0.176, MÊME hauteur ~z=0.31-0.32 que le bord d'attache du
    # fil) plutôt qu'un seul bloc -- un premier repliage qui ne pivotait QUE le grand fil (filtre
    # zone_of, c.x > 0.18) laissait ces trois petites pièces immobiles, toujours tendues vers
    # l'arrière (constaté par capture -- un fin arceau dépassait encore en haut à droite). Le filtre
    # c.x > 0.10 (couvre les quatre) exclut bien tripo_part_52 (c.x=0.112 mais c.z=0.057, un tout
    # autre détail bas près de la poignée) grâce au plancher c.z > 0.20 (toutes les pièces de
    # crosse/bride sont hautes, z >= 0.25 -- voir le sondage).
    stock_names = [n for n in stats if stats[n]["c"].x > 0.10 and stats[n]["c"].z > 0.20]
    assert stock_names, "crosse fil (+ bride) introuvable"
    stock_objs = [bpy.data.objects[n] for n in stock_names]
    stock_verts = [o.matrix_world @ v.co for o in stock_objs for v in o.data.vertices]
    # Charnière VERTICALE (axe Z, "haut" repère SOURCE) : bord AVANT de l'ensemble crosse+bride
    # (mn.x sur TOUTES les pièces ci-dessus -- attache carcasse, jamais le bord arrière ni le
    # centre), hauteur MESURÉE sur les sommets de CE bord (moyenne, marge 1 cm) -- pas devinée :
    # c'est là que la patte d'attache existe réellement (mesuré ~z=0.30-0.32, net au-dessus du
    # chargeur/de la poignée). Décalage latéral Y choisi (le point d'attache mesuré tombe quasi sur
    # l'axe, y≈0 -- cette génération Tripo ne code aucun côté) pour dégager la poignée/le chargeur
    # (demi-largeurs mesurées ~0.03-0.035) tout en restant dans la demi-largeur de la carcasse
    # (~0.065) -- flanc DROIT (consigne du lead), voir la vérification visuelle (capture) qui a
    # confirmé le signe.
    hinge_x = min(v.x for v in stock_verts)
    near_hinge = [v for v in stock_verts if v.x <= hinge_x + 0.01]
    hinge_z = sum(v.z for v in near_hinge) / len(near_hinge)
    STOCK_HINGE_Y = 0.055
    hinge = Vector((hinge_x, STOCK_HINGE_Y, hinge_z))
    # 180° autour de Z SEULEMENT : une rotation pure autour de l'axe "haut" ne change JAMAIS Z, donc
    # la crosse repliée reste à la même fourchette de hauteur (z=0,147-0,358) qu'à l'origine --
    # largement sous le viseur réflexe (z≈0,456, pièce distincte) sans code séparé pour "sous la
    # ligne de mire". Se replie donc bien VERS L'AVANT (mx.x -> proche de -mx.x, dans la zone
    # récepteur/poignée) et se loge contre le flanc (décalage Y ci-dessus) plutôt que de rester dans
    # l'axe du canon. LES QUATRE pièces pivotent RIGIDEMENT ENSEMBLE (même `hinge`, même angle) pour
    # ne pas rouvrir un écart entre le fil et sa bride de fixation.
    # Retour de test 2026-09-28 : crosse repliée = « l'arme a l'air coupée ». Dépliée depuis que la
    # poignée est posée à la place de celle de Ravage (la crosse part alors vers l'épaule, hors
    # écran) ; STOCK_FOLDED garde le repliage disponible.
    fold_deg = 180.0 if STOCK_FOLDED else 0.0
    fold = (Matrix.Translation(hinge) @ Matrix.Rotation(math.radians(fold_deg), 4, "Z")
            @ Matrix.Translation(-hinge))
    for stock_obj in stock_objs:
        stock_obj.data.transform(stock_obj.matrix_world)
        stock_obj.matrix_world = Matrix.Identity(4)
        stock_obj.data.transform(fold)
    print("RAFALE_STOCK_FOLD", stock_names, "hinge", tuple(round(x, 4) for x in hinge))

    mag_obj = None
    body_parts = []
    for o in parts:
        # Le chargeur (pièce MOBILE, "Magazine") reste "gunmetal" (contrat : "magazine ... gunmetal"),
        # jamais la classification générique -- sa position (près du centre, bas) chevauche la
        # fourchette des inserts poignée/flancs (cobalt) qui ne s'applique qu'aux pièces STATIQUES de
        # Body. La poignée (`grip_name`), elle, reste dans `body_parts` (statique -- voir la doc de
        # tête) et suit la classification générique `zone_of` comme le reste du corps.
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

    pw.paint_vertex_colors(body.data, ZONES, PAL, curvature_scale=2.2)   # grands pans nets (retour lead 2026-09-28)
    pw.paint_vertex_colors(mag_obj.data, ZONES, PAL, curvature_scale=2.2)
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
