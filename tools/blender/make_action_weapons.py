"""tools/blender/make_action_weapons.py — placeholders "quatre armes" (2026-09-28).

Rafale (SMG), Fracas (fusil a pompe), Verdict (carabine a levier), Aiguille
(sniper a verrou) : silhouettes CHUNKY en primitives toonkit (bibliotheque
bpy du depot) -- PAS de texture Tripo peinte, l'art reel viendra plus tard
(voir CLAUDE.md "l'utilisateur cree lui-meme les modeles" ; ce placeholder est
explicitement demande par la tache "quatre armes" du lead, voir son rendu).

Convention d'axes toonkit (Z-up natif Blender, voir tools/blender/lib/
toonkit.py en-tete) + export_yup=True : Blender +Y -> glTF -Z (canon vers
l'avant, camera Godot), Blender +Z -> glTF +Y (haut), Blender +X -> glTF +X
(droite -- le canon revele le flanc DROIT une fois en jeu, voir
ViewModel._MODEL_YAW_DEG). L'origine (0,0,0) de chaque arme est la POIGNEE
(meme convention que les armes existantes, voir ViewModel.REST_POS/
_place_weapon).

Chaque arme expose sa piece MOBILE en objet SEPARE (jamais fusionne au corps
statique) : PumpGrip (Fracas), Lever (Verdict), Bolt (Aiguille), Magazine
(Rafale) -- nom EXACT attendu par ViewModel._action_node_name_for /
WeaponActionAnim.gd. Chaque piece porte un materiau nomme "<partie>_paint"
(voir ViewModel._ACTION_WEAPON_PAINT_MARKER) : elle garde SA PROPRE couleur au
runtime (jamais la palette generique Cartoon.character() de Ravage/Revolver).
Couleurs (contrat : aucun nom de fabricant dans le code/les assets) :
polymere jaune signal + cobalt (Rafale, Aiguille), noyer + acier bleui +
laiton (Fracas, Verdict).

Deux empties partages par toutes les armes existantes (voir Weapon.gd/
ViewModel.gd) : "Muzzle" (bout du canon, flash + tracer distant) et
"Foregrip" (accroche du gant gauche flottant, repli sans effet pour les
armes qui utilisent le rig FPArmsRig plutot que les gants).

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b -P tools/blender/make_action_weapons.py
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
import bpy  # noqa: E402
import toonkit  # noqa: E402

OUT_DIR = os.path.join(toonkit.repo_root(), "assets", "models", "weapons")

# ---------------------------------------------------------------------------
# Couleurs (hex du contrat, convertis 0..1) -- AUCUN nom de fabricant ici.
# ---------------------------------------------------------------------------
YELLOW = (1.0, 0.808, 0.122)      # #FFCE1F, polymere signal
COBALT = (0.180, 0.545, 1.0)      # #2E8BFF, polymere
WALNUT = (0.302, 0.196, 0.106)
BLUED_STEEL = (0.10, 0.11, 0.13)
BRASS = (0.72, 0.58, 0.27)
SIGHT_DARK = (0.05, 0.05, 0.06)


def _empty(name: str, loc: tuple):
	obj = bpy.data.objects.new(name, None)
	obj.location = loc
	obj.empty_display_size = 0.02
	bpy.context.scene.collection.objects.link(obj)
	return obj


def _paint(obj, slot: str, color: tuple, kind: str = "flat"):
	mat = toonkit.toon_material(f"{slot}_paint", color, kind=kind)
	obj.data.materials.append(mat)
	return obj


def _finish(obj, bevel: float = 0.006):
	toonkit.add_bevel(obj, width=bevel, segments=1)
	toonkit.weighted_normals(obj, sharp_angle_deg=35.0)
	return obj


def _parent_all(root, objs):
	for o in objs:
		o.parent = root


## Décalage vertical (Blender Z = haut, voir la doc de tête) appliqué à TOUTE
## la géométrie avant export -- BUG CONSTATÉ PAR CAPTURE (tâche "quatre armes",
## 2026-09-28) : "WeaponGrip" (FPArmsRig.gd, os d'attache premières-personnes)
## place son origine (transform locale IDENTITÉ pour l'arme, voir sa doc) à un
## point qui projette SOUS le cadre visible de la caméra FP une fois composé
## avec RIG_SCALE -- confirmé en comparant aux empties Foregrip/Muzzle de
## `wpn_ravage.glb` (arme de référence, TOUJOURS visible) : les leurs sont à
## Z = 0,215-0,255 (bien AU-DESSUS de leur origine), jamais proches de zéro.
## Nos armes, construites avec la poignée/le corps au même niveau (silhouette
## réaliste), restaient donc entièrement sous le bord visible -- confirmé par
## capture (rien de visible en 1re personne alors que la 3e personne, un
## mécanisme d'attache DIFFÉRENT, ThirdPersonWeapon.gd, rendait la même arme
## parfaitement). Ce décalage NE CHANGE PAS la vue à la 3e personne (même
## logique, juste un point d'origine différent dans la silhouette) ni le
## gabarit des armes entre elles -- seulement leur hauteur relative à
## l'origine "poignée", pour rejoindre la fenêtre qui fonctionne réellement
## avec ce rig. `0.23` = milieu de la fourchette Ravage (0,215-0,255).
GRIP_LIFT = 0.23


def _lift(objs: list, amount: float = GRIP_LIFT):
	for o in objs:
		o.location.z += amount


def _join_static(name: str, parts: list):
	"""Fusionne les pièces STATIQUES en UN SEUL objet (comme `wpn_ravage.glb` --
	voir la doc de tête : un maillage CONTINU qui s'étend de la poignée
	jusqu'au canon rend correctement même quand l'origine elle-même tombe
	hors-cadre côté FPArmsRig, alors que plusieurs PETITS objets disjoints
	proches de l'origine (chacun entièrement hors-cadre à lui seul) ne
	rendent RIEN DU TOUT -- bug constaté par capture, tâche "quatre armes"
	2026-09-28 : voir le rendu de tâche. Les matériaux "<partie>_paint"
	distincts de chaque pièce restent PORTÉS PAR LEURS FACES d'origine
	(Blender `object.join()` fusionne les slots de matériaux, jamais les
	couleurs elles-mêmes) -- `ViewModel._apply_cartoon_materials` itère déjà
	`mesh.get_surface_count()` par matériau, donc rien à changer côté Godot."""
	joined = toonkit.join(parts)
	joined.name = name
	return joined


# ---------------------------------------------------------------------------
# Rafale (SMG, id 2) -- courte, chargeur avant proeminent (silhouette SMG).
# ---------------------------------------------------------------------------
def build_rafale():
	toonkit.reset_scene()
	root = _empty("Rafale", (0.0, 0.0, 0.0))

	body = toonkit.rounded_box((0.05, 0.30, 0.075), bevel_width=0.008, segments=2, name="Body")
	body.location = (0.0, 0.14, 0.02)
	_finish(body)
	_paint(body, "body", COBALT)

	receiver_cap = toonkit.rounded_box((0.045, 0.05, 0.02), bevel_width=0.004, segments=1, name="ReceiverCap")
	receiver_cap.location = (0.0, 0.29, 0.045)
	_finish(receiver_cap, bevel=0.004)
	_paint(receiver_cap, "cap", YELLOW)

	stock = toonkit.rounded_box((0.032, 0.13, 0.045), bevel_width=0.006, segments=1, name="Stock")
	stock.location = (0.0, -0.11, 0.01)
	_finish(stock)
	_paint(stock, "stock", COBALT)

	grip = toonkit.rounded_box((0.032, 0.045, 0.10), bevel_width=0.005, segments=1, name="Grip")
	grip.location = (0.0, -0.01, -0.065)
	grip.rotation_euler = (0.20, 0.0, 0.0)
	_finish(grip)
	_paint(grip, "grip", BLUED_STEEL)

	sight = toonkit.rounded_box((0.012, 0.045, 0.018), bevel_width=0.003, segments=1, name="Sight")
	sight.location = (0.0, 0.10, 0.068)
	_finish(sight, bevel=0.003)
	_paint(sight, "sight", SIGHT_DARK)

	# Piece MOBILE (tâche "quatre armes") : chargeur avant, tres visible --
	# animee au DIP DE RECHARGEMENT générique (ViewModel._update_action_part,
	# kind "Magazine"), la Rafale n'a pas de cycle d'action dédié (SMG auto).
	magazine = toonkit.tapered_cylinder(r1=0.022, r2=0.017, depth=0.17, segments=8, name="Magazine")
	magazine.location = (0.0, 0.185, -0.095)
	magazine.rotation_euler = (0.14, 0.0, 0.0)
	_finish(magazine, bevel=0.004)
	_paint(magazine, "magazine", YELLOW)

	muzzle = _empty("Muzzle", (0.0, 0.30, 0.02))
	foregrip = _empty("Foregrip", (0.0, 0.20, -0.01))

	body_joined = _join_static("Body", [body, receiver_cap, stock, grip, sight])
	parts = [body_joined, magazine]
	_lift(parts + [muzzle, foregrip])
	_parent_all(root, parts + [muzzle, foregrip])
	return toonkit.export_glb(os.path.join(OUT_DIR, "rafale.glb"), [root] + parts + [muzzle, foregrip])


# ---------------------------------------------------------------------------
# Fracas (fusil a pompe, id 3) -- tube epais, pompe/garde-main coulissant,
# crosse bois (noyer), canon/recepteur acier bleui, bande laiton.
# ---------------------------------------------------------------------------
def build_fracas():
	toonkit.reset_scene()
	root = _empty("Fracas", (0.0, 0.0, 0.0))

	barrel = toonkit.tapered_cylinder(r1=0.018, r2=0.016, depth=0.62, segments=10, name="Barrel")
	barrel.location = (0.0, 0.44, 0.055)
	barrel.rotation_euler = (1.5708, 0.0, 0.0)  # axe cree le long de Z -> couche a plat le long de +Y
	_finish(barrel, bevel=0.004)
	_paint(barrel, "barrel", BLUED_STEEL)

	receiver = toonkit.rounded_box((0.045, 0.16, 0.075), bevel_width=0.007, segments=2, name="Receiver")
	receiver.location = (0.0, 0.10, 0.03)
	_finish(receiver)
	_paint(receiver, "receiver", BLUED_STEEL)

	band = toonkit.tapered_cylinder(r1=0.023, r2=0.023, depth=0.03, segments=10, name="Band")
	band.location = (0.0, 0.30, 0.055)
	band.rotation_euler = (1.5708, 0.0, 0.0)
	_finish(band, bevel=0.003)
	_paint(band, "band", BRASS)

	stock = toonkit.rounded_box((0.036, 0.20, 0.05), bevel_width=0.007, segments=2, name="Stock")
	stock.location = (0.0, -0.16, 0.005)
	stock.rotation_euler = (0.10, 0.0, 0.0)
	_finish(stock)
	_paint(stock, "stock", WALNUT)

	grip = toonkit.rounded_box((0.034, 0.05, 0.10), bevel_width=0.005, segments=1, name="Grip")
	grip.location = (0.0, -0.02, -0.06)
	grip.rotation_euler = (0.22, 0.0, 0.0)
	_finish(grip)
	_paint(grip, "grip", WALNUT)

	# Piece MOBILE (contrat : "pump grip", cycle 0.9 s + geste d'insertion
	# cartouche-par-cartouche) : garde-main qui coulisse autour du tube.
	pump = toonkit.rounded_box((0.05, 0.10, 0.08), bevel_width=0.006, segments=2, name="PumpGrip")
	pump.location = (0.0, 0.24, 0.03)
	_finish(pump)
	_paint(pump, "pump", WALNUT)

	muzzle = _empty("Muzzle", (0.0, 0.75, 0.055))
	foregrip = _empty("Foregrip", (0.0, 0.24, 0.0))

	body_joined = _join_static("Body", [barrel, receiver, band, stock, grip])
	parts = [body_joined, pump]
	_lift(parts + [muzzle, foregrip])
	_parent_all(root, parts + [muzzle, foregrip])
	return toonkit.export_glb(os.path.join(OUT_DIR, "fracas.glb"), [root] + parts + [muzzle, foregrip])


# ---------------------------------------------------------------------------
# Verdict (carabine a levier, id 4) -- longue, receveur + levier de sous-garde,
# crosse/garde-main noyer, canon acier bleui, bande laiton (tube).
# ---------------------------------------------------------------------------
def build_verdict():
	toonkit.reset_scene()
	root = _empty("Verdict", (0.0, 0.0, 0.0))

	barrel = toonkit.tapered_cylinder(r1=0.016, r2=0.013, depth=0.58, segments=10, name="Barrel")
	barrel.location = (0.0, 0.40, 0.045)
	barrel.rotation_euler = (1.5708, 0.0, 0.0)
	_finish(barrel, bevel=0.004)
	_paint(barrel, "barrel", BLUED_STEEL)

	tube = toonkit.tapered_cylinder(r1=0.012, r2=0.012, depth=0.40, segments=8, name="MagTube")
	tube.location = (0.0, 0.35, 0.014)
	tube.rotation_euler = (1.5708, 0.0, 0.0)
	_finish(tube, bevel=0.003)
	_paint(tube, "tube", BRASS)

	receiver = toonkit.rounded_box((0.042, 0.15, 0.065), bevel_width=0.007, segments=2, name="Receiver")
	receiver.location = (0.0, 0.09, 0.02)
	_finish(receiver)
	_paint(receiver, "receiver", BLUED_STEEL)

	forestock = toonkit.rounded_box((0.032, 0.22, 0.045), bevel_width=0.006, segments=1, name="Forestock")
	forestock.location = (0.0, 0.28, 0.0)
	_finish(forestock)
	_paint(forestock, "forestock", WALNUT)

	stock = toonkit.rounded_box((0.036, 0.22, 0.05), bevel_width=0.007, segments=2, name="Stock")
	stock.location = (0.0, -0.17, -0.005)
	stock.rotation_euler = (0.08, 0.0, 0.0)
	_finish(stock)
	_paint(stock, "stock", WALNUT)

	# Piece MOBILE (contrat : "loop lever", cycle 0.45 s + geste d'insertion
	# balle-par-balle) : anneau de sous-garde -- approxime en BARRE chunky
	# (silhouette lisible, placeholder primitif) sous le recepteur, pivote
	# autour de son bord ARRIERE (voir ViewModel._update_action_part, kind
	# "Lever" -- rotation autour de l'axe X local).
	lever = toonkit.rounded_box((0.03, 0.11, 0.03), bevel_width=0.005, segments=1, name="Lever")
	lever.location = (0.0, -0.02, -0.075)
	lever.rotation_euler = (0.05, 0.0, 0.0)
	_finish(lever, bevel=0.004)
	_paint(lever, "lever", BLUED_STEEL)

	muzzle = _empty("Muzzle", (0.0, 0.69, 0.045))
	foregrip = _empty("Foregrip", (0.0, 0.30, 0.0))

	body_joined = _join_static("Body", [barrel, tube, receiver, forestock, stock])
	parts = [body_joined, lever]
	_lift(parts + [muzzle, foregrip])
	_parent_all(root, parts + [muzzle, foregrip])
	return toonkit.export_glb(os.path.join(OUT_DIR, "verdict.glb"), [root] + parts + [muzzle, foregrip])


# ---------------------------------------------------------------------------
# Aiguille (sniper a verrou, id 5) -- longue, grosse lunette, poignee de
# culasse sur le flanc, crosse/corps polymere jaune+cobalt.
# ---------------------------------------------------------------------------
def build_aiguille():
	toonkit.reset_scene()
	root = _empty("Aiguille", (0.0, 0.0, 0.0))

	barrel = toonkit.tapered_cylinder(r1=0.015, r2=0.010, depth=0.66, segments=10, name="Barrel")
	barrel.location = (0.0, 0.46, 0.04)
	barrel.rotation_euler = (1.5708, 0.0, 0.0)
	_finish(barrel, bevel=0.004)
	_paint(barrel, "barrel", BLUED_STEEL)

	receiver = toonkit.rounded_box((0.04, 0.20, 0.05), bevel_width=0.007, segments=2, name="Receiver")
	receiver.location = (0.0, 0.09, 0.03)
	_finish(receiver)
	_paint(receiver, "receiver", COBALT)

	stock = toonkit.rounded_box((0.036, 0.28, 0.055), bevel_width=0.007, segments=2, name="Stock")
	stock.location = (0.0, -0.20, 0.005)
	stock.rotation_euler = (0.06, 0.0, 0.0)
	_finish(stock)
	_paint(stock, "stock", YELLOW)

	# Grosse lunette (contrat : "sniper long with big scope") -- tube epais
	# monte au-dessus du recepteur.
	scope_tube = toonkit.tapered_cylinder(r1=0.028, r2=0.028, depth=0.30, segments=12, name="ScopeTube")
	scope_tube.location = (0.0, 0.10, 0.115)
	scope_tube.rotation_euler = (1.5708, 0.0, 0.0)
	_finish(scope_tube, bevel=0.004)
	_paint(scope_tube, "scope", SIGHT_DARK)

	scope_front = toonkit.tapered_cylinder(r1=0.033, r2=0.033, depth=0.03, segments=12, name="ScopeFrontRing")
	scope_front.location = (0.0, 0.24, 0.115)
	scope_front.rotation_euler = (1.5708, 0.0, 0.0)
	_finish(scope_front, bevel=0.003)
	_paint(scope_front, "scope_ring", COBALT)

	scope_back = toonkit.tapered_cylinder(r1=0.033, r2=0.033, depth=0.03, segments=12, name="ScopeBackRing")
	scope_back.location = (0.0, -0.03, 0.115)
	scope_back.rotation_euler = (1.5708, 0.0, 0.0)
	_finish(scope_back, bevel=0.003)
	_paint(scope_back, "scope_ring", COBALT)

	# Piece MOBILE (contrat : "bolt cycle 1.2 s") : poignee de culasse sur le
	# flanc droit -- translate+souleve legerement pendant le cycle (voir
	# ViewModel._update_action_part, kind "Bolt").
	bolt = toonkit.rounded_box((0.05, 0.045, 0.022), bevel_width=0.004, segments=1, name="Bolt")
	bolt.location = (0.036, 0.02, 0.045)
	_finish(bolt, bevel=0.004)
	_paint(bolt, "bolt", BLUED_STEEL)

	muzzle = _empty("Muzzle", (0.0, 0.79, 0.04))
	foregrip = _empty("Foregrip", (0.0, 0.30, 0.0))

	body_joined = _join_static("Body", [barrel, receiver, stock, scope_tube, scope_front, scope_back])
	parts = [body_joined, bolt]
	_lift(parts + [muzzle, foregrip])
	_parent_all(root, parts + [muzzle, foregrip])
	return toonkit.export_glb(os.path.join(OUT_DIR, "aiguille.glb"), [root] + parts + [muzzle, foregrip])


BUILDERS = {
	"rafale": build_rafale,
	"fracas": build_fracas,
	"verdict": build_verdict,
	"aiguille": build_aiguille,
}


if __name__ == "__main__":
	wanted = [a for a in sys.argv[sys.argv.index("--") + 1:]] if "--" in sys.argv else list(BUILDERS)
	wanted = wanted or list(BUILDERS)
	for name in wanted:
		BUILDERS[name]()
