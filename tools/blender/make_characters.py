## make_characters.py
## Génère les 6 agents jouables + les avant-bras FP (viewmodel) façon BD/
## graphic-novel : habits AJUSTÉS dupliqués depuis le mannequin squeletté CC0
## Quaternius "Universal Animation Library" (Standard) lui-même (pas des
## primitives flottantes) + gear kitbashé (primitives bmesh, mêmes helpers que
## make_weapons.py) posé par-dessus — voir THIRD_PARTY_LICENSES.md.
##
## Déterministe (aucun random). Slots matériau fixes "cloth"/"gear"/"skin"/
## "accent" (recolorés au runtime par Cartoon.gd + un futur PlayerLook.gd,
## même convention de nommage que make_weapons.py : `f"{id}_{slot}"`, lue via
## `mat.resource_name.ends_with("_%s" % slot)` — voir ViewModel.gd
## `_apply_cartoon_materials`).
##
##   blender --background --python tools/blender/make_characters.py
##
## Source (CC0 1.0, Quaternius — voir THIRD_PARTY_LICENSES.md) : un seul
## fichier `ual.glb` avec un maillage "Mannequin" (8546 verts / 13743 tris,
## matériaux M_Main/M_Joints), une armature "Rig" (53 os DEF-, doigts inclus)
## et 46 actions. Le chemin par défaut pointe vers le scratchpad de la tâche
## qui a téléchargé la source ; surchargeable via la variable d'env
## `UAL_SOURCE_GLB` pour une relance future (la source n'est PAS committée —
## seuls les .glb dérivés dans assets/models/characters/ le sont).
##
## Revue lead (itération 2) : la v1 posait des primitives directement sur le
## mannequin nu (sphères de jointure visibles, couleur d'équipe ~10% de la
## silhouette, gear "en dalles" flottantes). Fix : des VÊTEMENTS AJUSTÉS —
## veste/manches, pantalon, gants, bottes, cagoule — sont construits en
## DUPLIQUANT les faces du mannequin par os dominant, poussées le long de
## leur normale (1.5-3 cm), puis les faces d'origine (peau + jointures) sont
## supprimées sous chaque vêtement. Les poids de skin sont copiés tels quels
## par `bmesh.ops.duplicate` (vérifié par sondage) : la "peau" devient le
## "vêtement" sans aucune perte de qualité d'animation. Le gear kitbashé
## (casques, chapeaux, plaques, sacs...) vient ensuite PAR-DESSUS ces
## vêtements, plus jamais directement sur la peau.
##
## Revue lead (itération 3, retour utilisateur) : la DA passe d'"encre et
## papier" (monochrome + joueurs en couleur) à un cel-shading peint façon
## Borderlands (refs .orchestrator/refs/wasteland_hero.png,
## cargo_ship_hero.png — palette terreuse saturée, cuir/métal, gros aplats).
## `.orchestrator/design.md` v2 (couleurs par agent) était encore en cours de
## rédaction au moment de cette passe ; à défaut de valeurs verrouillées, les
## teintes ci-dessous sont un choix raisonné (cuir/toile terreuse, jamais les
## 4 teintes d'équipe) à réconcilier si le v2 publie des hex différents. Un
## 5e slot matériau `outfit` porte la couleur FIXE de l'agent (veste/manches,
## pantalon reste "gear" neutre cuir) ; `cloth` RÉTRÉCIT à une seule zone
## d'identification d'équipe nette : la bande épaule + haut du bras (un
## "brassard"/"épaulette" au sens propre), recolorée par `Cartoon.character()`
## au runtime — tout le reste du torse (buste + manches d'avant-bras) et la
## tête (bandana/masque) passent en `outfit`.
##
## API bpy 5.2 vérifiée par sondage avant écriture (voir rapport de tâche) :
## - Le fichier source est déjà en repère Blender Z-up (converti par
##   l'IMPORT glTF) ; les coordonnées de repos des os (`bone.head_local`) sont
##   donc directement utilisables comme ancres monde pour poser le gear, SANS
##   le hack de rotation +90°/X qu'utilise make_weapons.py (qui, lui, écrit
##   des coordonnées brutes jamais passées par un import glTF).
## - `bm.verts.layers.deform` porte les poids de skin (dict {index_groupe:
##   poids}) ; les index de groupe doivent correspondre À L'IDENTIQUE À
##   L'ORDRE de `object.vertex_groups` sur l'objet qui reçoit le maillage
##   fusionné (recréés dans le même ordre que sur "Mannequin" avant `to_mesh`).
## - `bmesh.ops.duplicate(bm, geom=[...])` renvoie un dict avec une clé
##   `"geom"` (tous les nouveaux éléments, verts+edges+faces mélangés) — les
##   NOUVEAUX verts portent déjà les MÊMES poids de deform (copiés
##   automatiquement, vérifié par sondage : dict de poids identique
##   avant/après) et leur `.normal` est valide immédiatement (même topologie
##   locale que l'original dupliqué).
## - `bmesh.ops.delete(bm, geom=faces, context='FACES')` retire les faces ET
##   nettoie les verts/edges devenus inutilisés, MAIS conserve ceux encore
##   partagés avec une face gardée (ex. l'anneau de peau au cou, non couvert
##   à dessein — seule peau visible, cf. §têtes ci-dessous).
## - Le maillage source (13743 tris, essentiellement les sphères de
##   jointure "M_Joints" d'un mannequin d'atelier articulé) dépasse à lui
##   seul le budget de 15k tris/perso une fois qu'on ajoute du gear : un
##   modifier DECIMATE (COLLAPSE, ratio 0.5, poids de vertex groups
##   interpolés — vérifié par sondage, aucune perte de poids) appliqué AVANT
##   fusion le ramène à 6871 tris. La technique "vêtement = peau dupliquée
##   puis peau d'origine supprimée" ne change quasi pas ce budget (1
##   remplace 1), donc le gear kitbashé garde toute sa marge.
## - `export_scene.gltf(export_animation_mode='ACTIONS')` exporte TOUTES les
##   actions de `bpy.data.actions` (pas seulement l'action active/NLA) — les
##   46 actions de la source n'ont ni fake_user ni piste NLA, donc c'est le
##   seul mode qui les garde toutes avec leur nom inchangé.
## - `export_apply=False` : le seul modifier restant à l'export est
##   ARMATURE (Decimate a déjà été appliqué et retiré) — il ne doit jamais
##   être "appliqué" à l'export (ça figerait la pose de repos dans le
##   maillage et détruirait le skinning).
import bpy
import bmesh
import math
import os
from collections import Counter
from mathutils import Matrix, Vector

CLOTH, GEAR, SKIN, ACCENT, OUTFIT = 0, 1, 2, 3, 4
SLOT_NAMES = ["cloth", "gear", "skin", "accent", "outfit"]

SRC_GLB = os.environ.get(
	"UAL_SOURCE_GLB",
	r"C:/Users/srko/AppData/Local/Temp/claude/C--Users-srko-Desktop-fps/"
	r"02e156fb-5e66-4722-9835-071a024d62a9/scratchpad/downloads/ual/ual.glb",
)

_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(_ROOT, "assets", "models", "characters")

DECIMATE_RATIO = 0.5
BEVEL_WIDTH = 0.005

# Couleurs plates de base — verrouillées par .orchestrator/design.md v2 §10
# ("Peint au soleil, encré gras", remplace la v1 "encre et papier" monochrome
# après retour utilisateur). Le slot "cloth" est désormais un petit PANNEAU
# épaule + dos (~6% de la silhouette, cf. §10 "Team cue"), retinté à
# l'exécution par Cartoon.character(team_color) — cf. tools/character_shots.gd
# et le futur PlayerLook.gd. "gear"/"skin" restent fixes ; "accent" et
# "outfit" sont la palette FIXE de l'agent ("Trois valeurs, du foncé au
# clair" : gear foncé -> outfit saturé -> accent clair).
CLOTH_PLACEHOLDER = (0.55, 0.52, 0.47, 1.0)     # neutre, canevas pour la teinte d'équipe
GEAR_COLOR = (0.165, 0.145, 0.133, 1.0)         # design.md §10 : "dark gear #2A2522"
SKIN_COLOR = (0.431, 0.396, 0.345, 1.0)         # graphite (Cartoon.GRAPHITE "6e6558")
## Gant fp_arms UNIQUEMENT (via `gear_color_override`, cf. `_finish_object`) —
## les 6 persos gardent GEAR_COLOR inchangé. Revue (tâche viewmodel FPS) :
## GEAR_COLOR (#2A2522) est quasi noir à l'écran une fois ombré de près (le
## gant occupe tout le cadre en vue FP, contrairement au gear des persos, vu
## petit/loin) — "cuir" brun moyen de la famille bois/cuir de design.md §6
## (proche de Bois #9C6A42) pour que l'ombrage se lise encore de près.
FP_GLOVE_COLOR = (0.42, 0.29, 0.20, 1.0)        # cuir brun moyen, jamais quasi-noir

# Veste/manches + bandana (buste, avant-bras, tête) — couleur dominante FIXE
# de l'agent (30-45% de la silhouette). Hex verrouillés design.md §10 :
# Vif #E8703F, Choc #C23B2E, Roc #2F6FC0, Baume #F2C53D ; Guet et Verrou ont
# changé de teinte pour sortir des bandes réservées (§9.1 : hue OKLCH
# 300-355° et 105-145° au-dessus de C 0.08, cf. risque §14.2) -> Guet
# #2E8C7A, Verrou #4B4FA8.
OUTFITS = {
	"vif": (0.910, 0.439, 0.247, 1.0),     # #E8703F
	"choc": (0.761, 0.231, 0.180, 1.0),    # #C23B2E
	"roc": (0.184, 0.435, 0.753, 1.0),     # #2F6FC0
	"guet": (0.180, 0.549, 0.478, 1.0),    # #2E8C7A
	"baume": (0.949, 0.773, 0.239, 1.0),   # #F2C53D
	"verrou": (0.294, 0.310, 0.659, 1.0),  # #4B4FA8
}

# "One light accent (helmet or scarf)" (design.md §10) — pas de hex verrouillé
# par agent : teintes CLAIRES (3e valeur de l'échelle foncé -> clair),
# distinctes entre agents et de la bande réservée à l'ennemi (magenta/citron).
ACCENTS = {
	"vif": (0.561, 0.878, 0.831, 1.0),     # verres pâles turquoise
	"choc": (0.949, 0.851, 0.690, 1.0),    # fente de visière crème chaude
	"roc": (0.788, 0.863, 0.933, 1.0),     # liseré de casque bleu glace
	"guet": (0.910, 0.851, 0.753, 1.0),    # voyant d'antenne sable pâle
	"baume": (0.961, 0.886, 0.627, 1.0),   # bande de gaze crème doré
	"verrou": (0.847, 0.871, 0.878, 1.0),  # liseré de casque gris acier clair
}


# ---------------------------------------------------------------------------
# Régions du corps par os DOMINANT, pour la découpe "vêtement ajusté" —
# chaque os de `Mannequin.vertex_groups` (53, doigts inclus) appartient à
# EXACTEMENT une région, sauf "root" (aucune face) et "DEF-neck" (laissé de
# côté à dessein : un mince anneau de peau visible au cou entre le col de la
# veste et le bas du masque/capuche — la seule peau qui reste "skin").
# ---------------------------------------------------------------------------
# Torse : buste + bras (couleur fixe "outfit") SÉPARÉ des ÉPAULES seules
# (couleur d'équipe "cloth" — design.md §10 "Team cue" : "panels on the
# shoulders and back, about 6% of the silhouette" ; un panneau dorsal
# additionnel est posé en gear kitbashé, cf. `_team_back_panel`). Le
# "stencil" ●/▼ et l'émission 0.4 sont posés par le shader/matériau
# d'exécution (design.md §15, "next pass, not this one") — pas ce script.
TORSO_OUTFIT_BONES = {
	"DEF-spine.001", "DEF-spine.002", "DEF-spine.003",
	"DEF-upper_arm.L", "DEF-upper_arm.R", "DEF-forearm.L", "DEF-forearm.R",
}
TORSO_TEAM_BONES = {"DEF-shoulder.L", "DEF-shoulder.R"}
LEGS_BONES = {"DEF-hips", "DEF-thigh.L", "DEF-thigh.R", "DEF-shin.L", "DEF-shin.R"}
HEAD_BONES = {"DEF-head"}


def _hand_bones() -> set:
	out = {"DEF-hand.L", "DEF-hand.R"}
	for side in ("L", "R"):
		for finger in ("index", "middle", "pinky", "ring"):
			for seg in ("01", "02", "03"):
				out.add(f"DEF-f_{finger}.{seg}.{side}")
		for seg in ("01", "02", "03"):
			out.add(f"DEF-thumb.{seg}.{side}")
	return out


HAND_BONES = _hand_bones()
FOOT_BONES = {"DEF-foot.L", "DEF-foot.R", "DEF-toe.L", "DEF-toe.R"}
FOREARM_ONLY_BONES = {"DEF-forearm.L", "DEF-forearm.R"}  # pour fp_arms (manche courte, pas d'épaule)

# (bone_set, slot, décalage le long de la normale en mètres) — ordre de
# traitement : chaque face n'est réclamée que par UNE région (ensembles
# disjoints), donc l'ordre n'a pas d'incidence sur le résultat. La tête
# (bandana/masque, "outfit") est construite séparément dans `build_character`
# car son slot ne dépend d'aucune variation par agent (toujours "outfit").
SHELL_REGIONS = [
	("torso_outfit", TORSO_OUTFIT_BONES, OUTFIT, 0.020),
	("torso_team", TORSO_TEAM_BONES, CLOTH, 0.020),
	("legs", LEGS_BONES, GEAR, 0.015),
	("hands", HAND_BONES, GEAR, 0.015),
	("feet", FOOT_BONES, GEAR, 0.025),
]


def _clear_scene() -> None:
	for o in list(bpy.data.objects):
		bpy.data.objects.remove(o, do_unlink=True)
	for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.armatures):
		for block in list(coll):
			if block.users == 0:
				coll.remove(block)


def _import_source():
	bpy.ops.import_scene.gltf(filepath=SRC_GLB)
	rig = bpy.data.objects["Rig"]
	mannequin = bpy.data.objects["Mannequin"]
	ico = bpy.data.objects.get("Icosphere")
	if ico is not None:
		bpy.data.objects.remove(ico, do_unlink=True)
	return rig, mannequin


def _decimate(mannequin, ratio: float) -> None:
	mod = mannequin.modifiers.new("Decimate", type='DECIMATE')
	mod.decimate_type = 'COLLAPSE'
	mod.ratio = ratio
	mod.use_collapse_triangulate = True
	idx = mannequin.modifiers.find(mod.name)
	mannequin.modifiers.move(idx, 0)  # avant Armature (voir sondage : sans effet ici, mais évite l'avertissement)
	with bpy.context.temp_override(object=mannequin):
		bpy.ops.object.modifier_apply(modifier=mod.name)


def _bone_point(rig, name: str, tail: bool = False) -> Vector:
	b = rig.data.bones[name]
	return (b.tail_local if tail else b.head_local).copy()


def _face_dominant_bone(face, dl, index_to_name):
	"""Os qui a le vote majoritaire parmi les os DOMINANTS (poids max) des
	sommets de la face — regroupe les faces par région anatomique visible,
	pas juste par un seul sommet (évite qu'un sommet de coin isolé fasse
	basculer toute une face dans la mauvaise région)."""
	votes = []
	for v in face.verts:
		weights = v[dl]
		if not weights:
			continue
		best_idx = max(weights.items(), key=lambda kv: kv[1])[0]
		name = index_to_name.get(best_idx)
		if name:
			votes.append(name)
	if not votes:
		return None
	return Counter(votes).most_common(1)[0][0]


def _select_faces_by_bones(bm, dl, index_to_name, bone_set):
	return [f for f in bm.faces if _face_dominant_bone(f, dl, index_to_name) in bone_set]


def _build_shell(bm, dl, index_to_name, bone_set, material_index, offset):
	"""Duplique les faces de `bone_set` (vêtement ajusté = la peau elle-même,
	poids de skin copiés tels quels), pousse les nouveaux sommets le long de
	leur normale de `offset` mètres, colore le slot, PUIS supprime les faces
	d'origine (peau + jointures dessous — gain de tris, silhouette nette).
	Renvoie les nouvelles faces (pour le calque "vêtement" = lissé, cf.
	`_finish_object`)."""
	bm.normal_update()
	faces = _select_faces_by_bones(bm, dl, index_to_name, bone_set)
	if not faces:
		return []
	geom_set = list({el for f in faces for el in ([f] + list(f.verts) + list(f.edges))})
	dup = bmesh.ops.duplicate(bm, geom=geom_set)
	new_faces = [g for g in dup["geom"] if isinstance(g, bmesh.types.BMFace)]
	new_verts = [g for g in dup["geom"] if isinstance(g, bmesh.types.BMVert)]
	for v in new_verts:
		v.co += v.normal * offset
	for f in new_faces:
		f.material_index = material_index
		f.smooth = True
	bmesh.ops.delete(bm, geom=faces, context='FACES')
	return new_faces


class GearCtx:
	"""Panier d'ancres + fabrique de primitives bmesh pour le gear kitbashé
	(posé PAR-DESSUS les vêtements ajustés, jamais directement sur la peau).
	`box`/`cyl` : pièce RIGIDE, poids 100% sur un seul os (casque, sac,
	plaque, gant renforcé). `box_blend` : pièce SOUPLE façon tissu, poids
	répartis linéairement entre deux os le long de l'axe Z monde (écharpe,
	cape) — la "pondération correcte" demandée pour les pièces façon tissu,
	sans repasser par une simulation physique. Toutes les faces créées ici
	sont taguées `smooth=False` (facettes nettes façon BD, cf.
	`_finish_object`) et suivent un léger BEVEL global à l'export."""

	def __init__(self, bm, dl, gi, rig):
		self.bm = bm
		self.dl = dl
		self.gi = gi          # nom d'os -> index de groupe (aligné sur Mannequin.vertex_groups)
		self.rig = rig

	def pt(self, name: str, tail: bool = False) -> Vector:
		return _bone_point(self.rig, name, tail)

	def _new_faces(self, verts):
		return list({f for v in verts for f in v.link_faces})

	def _tag_prop(self, faces):
		for f in faces:
			f.smooth = False

	def box(self, size, center, slot: int, bone: str, rot=None, weight: float = 1.0):
		verts = list(bmesh.ops.create_cube(self.bm, size=1.0)["verts"])
		faces = self._new_faces(verts)
		bmesh.ops.scale(self.bm, vec=Vector(size), verts=verts)
		if rot:
			axis, deg = rot
			bmesh.ops.rotate(self.bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(deg), 3, axis), verts=verts)
		bmesh.ops.translate(self.bm, vec=Vector(center), verts=verts)
		for f in faces:
			f.material_index = slot
		self._tag_prop(faces)
		gi = self.gi[bone]
		for v in verts:
			v[self.dl][gi] = weight
		return verts, faces

	def cyl(self, radius, depth, center, slot: int, bone: str, segments: int = 10, rot=None,
			radius2=None, weight: float = 1.0):
		verts = list(bmesh.ops.create_cone(
			self.bm, cap_ends=True, cap_tris=False, segments=segments,
			radius1=radius, radius2=radius2 if radius2 is not None else radius, depth=depth)["verts"])
		faces = self._new_faces(verts)
		if rot:
			axis, deg = rot
			bmesh.ops.rotate(self.bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(deg), 3, axis), verts=verts)
		bmesh.ops.translate(self.bm, vec=Vector(center), verts=verts)
		for f in faces:
			f.material_index = slot
		self._tag_prop(faces)
		gi = self.gi[bone]
		for v in verts:
			v[self.dl][gi] = weight
		return verts, faces

	def box_blend(self, size, center, slot: int, bone_a: str, bone_b: str, z_range, rot=None):
		"""`z_range` = (z_au_poids_bone_a, z_au_poids_bone_b) en Z monde ;
		chaque vertex est pondéré selon sa position Z APRÈS rotation/translation,
		interpolée linéairement et bornée [0,1]."""
		verts = list(bmesh.ops.create_cube(self.bm, size=1.0)["verts"])
		faces = self._new_faces(verts)
		bmesh.ops.scale(self.bm, vec=Vector(size), verts=verts)
		if rot:
			axis, deg = rot
			bmesh.ops.rotate(self.bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(deg), 3, axis), verts=verts)
		bmesh.ops.translate(self.bm, vec=Vector(center), verts=verts)
		for f in faces:
			f.material_index = slot
		self._tag_prop(faces)
		gi_a, gi_b = self.gi[bone_a], self.gi[bone_b]
		z0, z1 = z_range
		for v in verts:
			t = 0.0 if z1 == z0 else (v.co.z - z0) / (z1 - z0)
			t = max(0.0, min(1.0, t))
			v[self.dl][gi_a] = 1.0 - t
			v[self.dl][gi_b] = t
		return verts, faces


# ---------------------------------------------------------------------------
# Gabarits gear par agent (mètres, repos T-pose, Z-up, -Y = avant du perso),
# posés PAR-DESSUS les vêtements ajustés (veste/pantalon/gants/bottes/masque
# déjà en place — cf. `_build_shell`). Ancres clés (rest pose, sondées) :
# hanches z=0.92, torse haut z=1.31, nuque z=1.49, base tête z=1.57, épaule
# z=1.44/x=±0.19, coude x=±0.47, poignet x=±0.74, hanche x=±0.09.
# ---------------------------------------------------------------------------

def _team_back_panel(ctx: GearCtx) -> None:
	"""design.md §10 "Team cue" : "panels on the shoulders and back, about 6%
	of the silhouette" — les épaules viennent de `TORSO_TEAM_BONES` (vêtement
	ajusté), ce panneau dorsal rigide complète la zone "dos". Même slot
	"cloth" (couleur d'équipe), posé PAR-DESSUS la veste ajustée."""
	ctx.box((0.20, 0.035, 0.14), (0, 0.11, 1.40), CLOTH, "DEF-spine.003")


def gear_vif(ctx: GearCtx) -> None:
	# Pans d'écharpe (tissu souple, couleur fixe "outfit" — la veste au
	# complet est déjà le cuir rouille de l'agent) : nuque -> milieu du dos.
	for side in (-1, 1):
		ctx.box_blend((0.08, 0.05, 0.46), (side * 0.11, 0.11, 1.20), OUTFIT,
			"DEF-neck", "DEF-spine.001", z_range=(1.46, 0.97))
	# Lunettes (gear) sur le bandana + verres (accent cyan, complémentaire).
	ctx.box((0.20, 0.05, 0.05), (0, -0.13, 1.63), GEAR, "DEF-head")
	for side in (-1, 1):
		ctx.cyl(0.035, 0.03, (side * 0.06, -0.14, 1.63), ACCENT, "DEF-head", segments=10, rot=("X", 90))
	# Écusson (accent) sur le torse — touche "patch" façon Borderlands.
	ctx.box((0.07, 0.03, 0.07), (0.16, -0.15, 1.28), ACCENT, "DEF-spine.002")


def gear_choc(ctx: GearCtx) -> None:
	# Casque intégral à visière (gear) + fente lumineuse (accent).
	ctx.box((0.32, 0.32, 0.34), (0, -0.02, 1.62), GEAR, "DEF-head")
	ctx.box((0.20, 0.04, 0.035), (0, -0.18, 1.60), ACCENT, "DEF-head")
	# Immenses épaulières (gear), très larges pour casser la ligne d'épaule —
	# légèrement plus loin de l'axe pour recouvrir la veste sans s'y fondre.
	for side, bone in ((1, "DEF-shoulder.L"), (-1, "DEF-shoulder.R")):
		ctx.box((0.30, 0.30, 0.24), (side * 0.29, 0.02, 1.47), GEAR, bone)
	# Gantelets (gear) par-dessus les gants ajustés : avant-bras + main.
	for side, bone in ((1, "DEF-forearm.L"), (-1, "DEF-forearm.R")):
		ctx.box((0.17, 0.16, 0.44), (side * 0.60, 0.065, 1.441), GEAR, bone)


def gear_roc(ctx: GearCtx) -> None:
	# Casque carré (gear).
	ctx.box((0.27, 0.27, 0.24), (0, -0.01, 1.62), GEAR, "DEF-head")
	# Plaque-bouclier dorsale, haute et fine (gear) — dépasse nettement au-
	# dessus de la tête pour rester lisible de loin.
	ctx.box((0.50, 0.07, 1.00), (0, 0.19, 1.65), GEAR, "DEF-spine.002")
	# Plastron avant (outfit, couleur fixe acier-bleuté — un plastron gear
	# grisait trop la silhouette de face) — décalé plus en avant (-0.13) pour
	# dégager la veste ajustée dessous.
	ctx.box((0.40, 0.15, 0.42), (0, -0.13, 1.24), OUTFIT, "DEF-spine.002")
	# Épaulettes courtes (gear).
	for side, bone in ((1, "DEF-shoulder.L"), (-1, "DEF-shoulder.R")):
		ctx.box((0.16, 0.16, 0.10), (side * 0.24, 0.03, 1.46), GEAR, bone)
	# Noyau lumineux central (accent).
	ctx.cyl(0.045, 0.03, (0, -0.21, 1.30), ACCENT, "DEF-spine.002", segments=10, rot=("X", 90))


def gear_guet(ctx: GearCtx) -> None:
	# Chapeau à large bord (gear) : calotte fuselée + bord plat.
	ctx.cyl(0.13, 0.12, (0, -0.01, 1.72), GEAR, "DEF-head", segments=12, radius2=0.115)
	ctx.cyl(0.26, 0.025, (0, -0.01, 1.665), GEAR, "DEF-head", segments=16)
	# Long manteau (outfit, kaki désertique — couleur fixe, pas d'équipe) : la
	# veste ajustée s'arrête à la taille — un pan tronconique RIGIDE (poids
	# 100% hanches, évite les artefacts d'un cône tiré entre 2 cuisses
	# indépendantes) le prolonge en manteau long jusqu'au genou, évasé.
	ctx.cyl(0.20, 0.42, (0, 0.0, 0.75), OUTFIT, "DEF-hips", segments=16, radius2=0.27)
	# Sac à dos (gear) + antenne (gear) surmontée d'un voyant (accent).
	ctx.box((0.28, 0.14, 0.30), (0, 0.17, 1.28), GEAR, "DEF-spine.002")
	ctx.cyl(0.012, 0.55, (0, 0.19, 1.72), GEAR, "DEF-spine.003", segments=8)
	ctx.cyl(0.03, 0.05, (0, 0.19, 2.00), ACCENT, "DEF-spine.003", segments=8)
	# Écusson (accent) sur le manteau — touche "patch".
	ctx.box((0.07, 0.03, 0.07), (0.16, -0.14, 1.25), ACCENT, "DEF-spine.002")


def gear_baume(ctx: GearCtx) -> None:
	# Le masque de tête ("outfit", même vert que la cape) : la duplication de
	# peau par `_build_shell` donne déjà une capuche ajustée à la forme du
	# crâne — plus besoin d'une boîte flottante. La bande épaule/bras
	# ("cloth") reste la SEULE zone recolorée par équipe, comme les 5 autres.
	# Cape dorsale (tissu souple, outfit) : épaules -> hanches, un peu plus
	# loin du dos pour dégager la veste ajustée dessous.
	ctx.box_blend((0.36, 0.05, 0.62), (0, 0.16, 1.12), OUTFIT, "DEF-spine.003", "DEF-hips", z_range=(1.44, 0.92))
	# Sacoche (gear) sur la hanche + bandoulière (outfit).
	ctx.box((0.14, 0.11, 0.18), (0.21, 0.03, 0.98), GEAR, "DEF-hips")
	ctx.box((0.08, 0.24, 0.06), (0.10, -0.02, 1.20), OUTFIT, "DEF-spine.002", rot=("Y", 25))
	# Brassard (accent crème, jamais une croix rouge — juste l'anneau de
	# couleur), rayon élargi pour bien envelopper la manche ajustée dessous.
	ctx.cyl(0.085, 0.06, (0.47, 0.065, 1.30), ACCENT, "DEF-upper_arm.L", segments=12, rot=("Y", 90))


def gear_verrou(ctx: GearCtx) -> None:
	# Casque de chantier (gear) : dôme + bord.
	ctx.cyl(0.13, 0.14, (0, -0.01, 1.72), GEAR, "DEF-head", segments=12, radius2=0.12)
	ctx.cyl(0.15, 0.02, (0, -0.01, 1.655), GEAR, "DEF-head", segments=12)
	# Ceinture à outils (gear) + 2 pochettes — par-dessus la veste/pantalon
	# ajustés.
	ctx.box((0.44, 0.21, 0.10), (0, -0.02, 0.96), GEAR, "DEF-hips")
	for side in (-1, 1):
		ctx.box((0.10, 0.13, 0.14), (side * 0.20, 0.02, 0.90), GEAR, "DEF-hips")
	# Sac à conduites (gear, 2 tubes parallèles) + liseré (accent).
	for side in (-1, 1):
		ctx.cyl(0.035, 0.46, (side * 0.07, 0.16, 1.30), GEAR, "DEF-spine.002", segments=10)
	ctx.box((0.26, 0.10, 0.04), (0, 0.16, 1.06), ACCENT, "DEF-spine.002")
	# Écusson (accent) sur le torse — touche "patch".
	ctx.box((0.07, 0.03, 0.07), (0.16, -0.15, 1.28), ACCENT, "DEF-spine.002")


CHARACTERS = {
	"vif": gear_vif,
	"choc": gear_choc,
	"roc": gear_roc,
	"guet": gear_guet,
	"baume": gear_baume,
	"verrou": gear_verrou,
}


def _srgb_to_linear(c: float) -> float:
	"""Toutes les constantes de couleur de ce fichier (OUTFITS/ACCENTS/...)
	sont des tuples "tels qu'on veut les voir à l'écran" (dérivés des hex de
	design.md, sRGB). Mais `bsdf.inputs["Base Color"].default_value` de
	Blender attend du LINÉAIRE : sans cette conversion, la couleur ressort
	systématiquement plus claire et désaturée à l'export/import glTF->Godot
	(mesuré : gear #2A2522 sRGB ressortait en (0.44,0.42,0.40) au lieu de
	(0.165,0.145,0.133), soit l'exacte signature d'un encodage sRGB->linéaire
	appliqué à une valeur déjà sRGB — outfit orange de Vif viré pâle "peau").
	Formule sRGB standard (IEC 61966-2-1)."""
	if c <= 0.04045:
		return c / 12.92
	return ((c + 0.055) / 1.055) ** 2.4


def _slot_material(char_id: str, slot: int, accent_color, outfit_color, gear_color_override=None) -> "bpy.types.Material":
	color = {
		CLOTH: CLOTH_PLACEHOLDER, GEAR: gear_color_override if gear_color_override else GEAR_COLOR,
		SKIN: SKIN_COLOR, ACCENT: accent_color, OUTFIT: outfit_color,
	}[slot]
	linear = tuple(_srgb_to_linear(c) for c in color[:3]) + (color[3],)
	mat = bpy.data.materials.new(f"{char_id}_{SLOT_NAMES[slot]}")
	mat.diffuse_color = linear
	if mat.node_tree:
		bsdf = mat.node_tree.nodes.get("Principled BSDF")
		if bsdf:
			bsdf.inputs["Base Color"].default_value = linear
			bsdf.inputs["Roughness"].default_value = 0.35 if slot == GEAR else 0.75
	return mat


def _finish_object(char_id: str, rig, obj, accent_color, outfit_color, tris_budget: int = 15000,
		gear_color_override=None) -> None:
	for slot in range(len(SLOT_NAMES)):
		obj.data.materials.append(_slot_material(char_id, slot, accent_color, outfit_color, gear_color_override))
	# Le lissage (smooth/flat) est déjà décidé par face AU NIVEAU BMESH avant
	# `to_mesh()` (`_build_shell` -> smooth=True pour les vêtements ajustés,
	# `GearCtx._tag_prop` -> smooth=False pour le gear kitbashé à facettes) ;
	# `bm.to_mesh()` reporte ce drapeau tel quel sur `polygon.use_smooth`, pas
	# besoin de le recalculer ici.

	# `limit_method='ANGLE'` chanfreine aussi les arêtes de BORD OUVERT — et
	# chaque vêtement ajusté (`_build_shell`) EST un bord ouvert (tube/coque
	# détachée du reste du maillage) : mesuré, ça faisait exploser un perso à
	# ~19-20k tris (bord de la veste, du pantalon, des gants... tous
	# chanfreinés en boucle). Le gear kitbashé (facettes nettes, `smooth`
	# False) est donc ISOLÉ dans un groupe de vertex dédié et c'est LUI SEUL
	# que `limit_method='VGROUP'` chanfreine ; les coutures des vêtements
	# ajustés restent des arêtes vives nettes, non chanfreinées (mesuré :
	# ramène un perso complet de ~19-20k à ~7-9k tris).
	bevel_vg = obj.vertex_groups.new(name="_bevel_targets")
	prop_vert_idx = {vi for p in obj.data.polygons if not p.use_smooth for vi in p.vertices}
	if prop_vert_idx:
		bevel_vg.add(list(prop_vert_idx), 1.0, 'REPLACE')

	mod = obj.modifiers.new("bevel", type='BEVEL')
	mod.width = BEVEL_WIDTH
	mod.segments = 2
	mod.limit_method = 'VGROUP'
	mod.vertex_group = bevel_vg.name
	mod.harden_normals = False
	with bpy.context.temp_override(object=obj):
		bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
		bpy.ops.object.modifier_apply(modifier=mod.name)
	obj.data.update()
	leftover_vg = obj.vertex_groups.get("_bevel_targets")
	if leftover_vg:
		obj.vertex_groups.remove(leftover_vg)

	obj.parent = rig
	arm_mod = obj.modifiers.new("Armature", type='ARMATURE')
	arm_mod.object = rig

	obj.data.calc_loop_triangles()
	tris = len(obj.data.loop_triangles)
	print(f"CHAR_TRIS {char_id} = {tris} (budget {tris_budget})")
	if tris > tris_budget:
		print(f"CHAR_TRIS_WARN {char_id} exceeds budget by {tris - tris_budget}")


def _export(char_id: str, rig, obj, out_name: str) -> None:
	os.makedirs(OUT_DIR, exist_ok=True)
	out_path = os.path.join(OUT_DIR, f"{out_name}.glb")
	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	rig.select_set(True)
	bpy.context.view_layer.objects.active = rig
	bpy.ops.export_scene.gltf(
		filepath=out_path,
		export_format='GLB',
		use_selection=True,
		export_apply=False,
		export_yup=True,
		export_materials='EXPORT',
		export_cameras=False,
		export_lights=False,
		export_animations=True,
		export_animation_mode='ACTIONS',
	)
	print(f"CHARACTER_MODEL_OK {char_id} -> {out_path}")


def build_character(char_id: str, gear_fn) -> None:
	_clear_scene()
	rig, mannequin = _import_source()
	_decimate(mannequin, DECIMATE_RATIO)

	group_index = {vg.name: vg.index for vg in mannequin.vertex_groups}
	bone_order = [vg.name for vg in mannequin.vertex_groups]
	index_to_name = {i: n for n, i in group_index.items()}

	bm = bmesh.new()
	bm.from_mesh(mannequin.data)
	dl = bm.verts.layers.deform.verify()
	for f in bm.faces:
		f.material_index = SKIN  # M_Main + M_Joints fusionnés -> "skin" graphite

	# Vêtements ajustés : peau dupliquée par région d'os dominant, poussée le
	# long de sa normale, peau d'origine supprimée dessous (cf. `_build_shell`
	# — supprime aussi les sphères de jointure visibles, qui appartenaient à
	# la peau). "DEF-neck" n'est couvert par aucune région : fin anneau de
	# peau visible entre col et masque/capuche.
	for _name, bone_set, slot, offset in SHELL_REGIONS:
		_build_shell(bm, dl, index_to_name, bone_set, slot, offset)
	_build_shell(bm, dl, index_to_name, HEAD_BONES, OUTFIT, 0.015)  # bandana/masque, couleur fixe

	ctx = GearCtx(bm, dl, group_index, rig)
	_team_back_panel(ctx)  # design.md §10 : panneau dorsal, même zone d'équipe que les épaules
	gear_fn(ctx)

	me_new = bpy.data.meshes.new(char_id)
	bm.to_mesh(me_new)
	bm.free()

	obj = bpy.data.objects.new(char_id.capitalize(), me_new)
	bpy.context.scene.collection.objects.link(obj)
	for name in bone_order:
		obj.vertex_groups.new(name=name)  # même ordre que Mannequin -> index alignés sur le deform layer

	bpy.data.objects.remove(mannequin, do_unlink=True)

	_finish_object(char_id, rig, obj, ACCENTS[char_id], OUTFITS[char_id])
	_export(char_id, rig, obj, char_id)


# ---------------------------------------------------------------------------
# fp_arms.glb : avant-bras/mains/doigts seuls (viewmodel FP), même rig et
# mêmes 46 animations. Manche (cloth, couleur d'équipe) sur l'avant-bras +
# gant (gear) sur main/doigts — MÊME technique `_build_shell` que les 6
# agents (peau dupliquée, poussée, peau d'origine supprimée) ; tout le reste
# du mannequin (torse, jambes, tête, bras du dessus) est ensuite supprimé en
# bloc puisque seuls avant-bras/mains/doigts doivent survivre.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# FP_Hold : pose de tenue FPS dédiée (bras à deux mains, arme parallèle à la
# vue, pointée vers le viseur depuis en bas à droite — réf. Borderlands/
# Valorant/CoD). Remplace l'usage, par ViewModel.gd, des actions bibliothèque
# UAL "Pistol_Idle"/"Pistol_Aim_Neutral" : sondées (voir rapport de tâche),
# elles posent un personnage COMPLET tenant un PISTOLET D'UNE MAIN à la
# hanche en 3e personne (main.R euler ~(-79°,-166°,-13°), main.L quasi au
# même point que main.R) — inutilisable telle quelle pour un viewmodel bras
# nus à deux mains (c'est la cause du bug "arme tenue de travers").
#
# Technique (API bpy 5.2 vérifiée par sondage, voir rapport) :
# `rig.matrix_world` est l'identité (sondé) donc l'espace armature
# (`pose_bone.matrix`) EST l'espace monde ici — pas de conversion à faire.
# Pour chaque bras, on parcourt la chaîne upper_arm -> forearm -> hand et on
# calcule, os par os, la rotation MINIMALE (`Vector.rotation_difference`,
# API mathutils stable — un Vector3 vers un Vector3, aucune torsion
# superflue autour de l'axe, donc le "roll" de la pose de repos — mains
# ouvertes bien orientées en T-pose — est préservé autant que possible)
# qui réoriente la direction de repos de CET os vers sa direction cible
# (`_FP_HOLD_TARGETS`), ACCUMULÉE avec celle de son parent. La position de
# chaque os suit alors naturellement (tête du suivant = tête courante +
# direction accumulée × longueur de repos de l'os) : aucune position n'est
# fixée à la main, donc aucun étirement du maillage (les poids de peau sont
# parfois mélangés à la jointure, cf. `_build_shell`) — seule une rotation
# est appliquée à chaque os, exactement comme un animateur qui ne tourne
# jamais les os autrement qu'à leur propre articulation.
# `DEF-shoulder.*` n'est PAS reposé (aucun maillage fp_arms dessus, cf.
# `FOREARM_ONLY_BONES`/`HAND_BONES` — seul son repos sert de point d'ancrage
# fixe pour `DEF-upper_arm.*`, dont la tête de repos n'est PAS confondue avec
# la queue de l'épaule, sondé : os non connectés, `use_connect=False`).
## ATTENTION unité de repère : `_bone_rest_dir`/les vecteurs ci-dessous sont
## en espace ARMATURE = Blender Z-up (X=droite, Y=AVANT du perso confirmé par
## le placement des lunettes/du panneau dorsal plus haut dans ce fichier,
## Z=haut). L'export Y-up standard envoie Blender.Y -> Godot.Z avec un signe
## INVERSÉ (Godot.z = -Blender.y, vérifié par sondage sur la pose de repos) :
## donc "vers l'avant CAMÉRA" (Godot -Z, cf. REST_POS.z<0 dans ViewModel.gd)
## veut dire Blender.Y **POSITIF** ici, pas négatif (piège rencontré une
## première fois pendant le réglage de cette pose, voir rapport de tâche —
## les mains partaient alors majoritairement sur le côté au lieu de devant).
##
## Bras tenus DROITS (même direction pour upper_arm/forearm/hand) — PAS un
## coude plié : essayé (upper_arm et forearm avec des directions
## DIFFÉRENTES), mais `_build_shell` copie les poids de peau ORIGINAUX du
## mannequin (voir en-tête de fichier), qui MÉLANGENT un peu upper_arm.* et
## forearm.* près du coude (peau lissée entre segments) ; sans maillage sur
## upper_arm (aucune shell dessus, cf. `FOREARM_ONLY_BONES`), un coude plié
## fait quand même tourner CES sommets mélangés d'un avant-bras visible selon
## DEUX rotations différentes à la fois -> le maillage s'étire en un énorme
## blob difforme (constaté par rendu, voir rapport de tâche). Une SEULE
## direction par bras (upper_arm et forearm identiques) élimine le risque :
## tous les sommets, mélangés ou non, suivent alors la MÊME rotation. Choisis
## pour un écart poignet/poignet ~0.34 m (proche de l'écart poignée->
## Foregrip réel des armes, cf. tools/blender/make_weapons.py
## FOREGRIP_FRACTION — voir rapport de tâche, script de vérification pur
## Python, aucune dépendance à bpy). Le poignet reprend la direction de
## l'avant-bras (pas de torsion de poignet séparée).
_FP_HOLD_TARGETS = {
	"R": {  # main gâchette (droite, côté X négatif sur ce rig, sondé).
		"upper_arm": Vector((0.08, 0.85, -0.42)),
		"forearm": Vector((0.08, 0.85, -0.42)),
		"hand": Vector((0.08, 0.85, -0.42)),
	},
	"L": {  # main de soutien (gauche, X positif).
		"upper_arm": Vector((-0.03, 0.93, -0.25)),
		"forearm": Vector((-0.03, 0.93, -0.25)),
		"hand": Vector((-0.03, 0.93, -0.25)),
	},
}
_FP_HOLD_CHAIN = ("upper_arm", "forearm", "hand")


def _bone_rest_dir(rig, name: str) -> Vector:
	b = rig.data.bones[name]
	return (b.tail_local - b.head_local).normalized()


def _bone_rest_length(rig, name: str) -> float:
	b = rig.data.bones[name]
	return (b.tail_local - b.head_local).length


def _pose_fp_hold(rig) -> None:
	action = bpy.data.actions.new("FP_Hold")
	action.use_fake_user = True  # aucune piste NLA/utilisateur -> survivrait pas à un save/reload sans ça.
	rig.animation_data_create()
	rig.animation_data.action = action

	bpy.context.view_layer.objects.active = rig
	bpy.ops.object.mode_set(mode='POSE')
	bpy.ops.pose.select_all(action='DESELECT')

	posed_bones = []
	for side in ("R", "L"):
		targets = _FP_HOLD_TARGETS[side]
		accum = Matrix.Identity(3)  # rotation accumulée repos -> pose (3x3, espace armature = espace monde ici).
		pos = rig.data.bones[f"DEF-upper_arm.{side}"].head_local.copy()  # ancre fixe (épaule non reposée).
		for key in _FP_HOLD_CHAIN:
			bone_name = f"DEF-{key}.{side}"
			rest_dir = _bone_rest_dir(rig, bone_name)
			cur_dir = (accum @ rest_dir).normalized()
			target_dir = targets[key].normalized()
			delta = cur_dir.rotation_difference(target_dir).to_matrix()
			accum = delta @ accum
			new_dir = (accum @ rest_dir).normalized()
			length = _bone_rest_length(rig, bone_name)

			pb = rig.pose.bones[bone_name]
			# `accum` est une rotation DELTA (repos -> cible), pas une
			# orientation absolue : `pose_bone.matrix` (espace armature)
			# veut l'absolue, donc composée avec le repos ABSOLU de CET os
			# précisément — `bone.matrix_local` (bloc-donnée Bone, jamais
			# affecté par le reposage d'un parent en cours de boucle,
			# contrairement à `pose_bone.matrix` qui hérite du FK -- bug
			# constaté par sondage : sans cette composition, `pb.matrix =
			# accum.to_4x4()` remplaçait le repos de l'os par une rotation
			# quasi arbitraire, la main atterrissait à ~2 m de haut).
			rest_rot = rig.data.bones[bone_name].matrix_local.to_3x3()
			new_matrix = (accum @ rest_rot).to_4x4()
			new_matrix.translation = pos
			pb.matrix = new_matrix
			# `pose_bone.matrix` (setter) calcule le `matrix_basis` LOCAL à
			# partir de la pose ÉVALUÉE du parent — sans réévaluer ICI, le
			# prochain os de la chaîne (forearm après upper_arm, hand après
			# forearm) verrait encore le parent à son ANCIENNE pose (repos)
			# au moment de calculer SON PROPRE matrix_basis, corrompant toute
			# la chaîne (bug constaté par sondage : sans cette ligne, seule
			# la main était visiblement fausse, mais en fait CHAQUE os après
			# le premier héritait d'un parent pas encore réévalué). Coûteux
			# par os mais fait une seule fois à l'export, pas en jeu.
			bpy.context.view_layer.update()
			posed_bones.append(pb)
			pos = pos + new_dir * length

	for pb in posed_bones:
		pb.keyframe_insert(data_path="rotation_quaternion", frame=1)
		pb.keyframe_insert(data_path="location", frame=1)

	bpy.ops.object.mode_set(mode='OBJECT')
	rig.animation_data.action = None
	print("FP_HOLD_POSE_OK bones=%d" % len(posed_bones))


def build_fp_arms() -> None:
	_clear_scene()
	rig, mannequin = _import_source()
	_decimate(mannequin, DECIMATE_RATIO)

	group_index = {vg.name: vg.index for vg in mannequin.vertex_groups}
	bone_order = [vg.name for vg in mannequin.vertex_groups]
	index_to_name = {i: n for n, i in group_index.items()}

	bm = bmesh.new()
	bm.from_mesh(mannequin.data)
	dl = bm.verts.layers.deform.verify()
	for f in bm.faces:
		f.material_index = SKIN

	_build_shell(bm, dl, index_to_name, FOREARM_ONLY_BONES, CLOTH, 0.020)  # manche
	_build_shell(bm, dl, index_to_name, HAND_BONES, GEAR, 0.015)           # gant

	# Tout le reste (torse, jambes, tête, bras du dessus, pieds...) ne fait
	# pas partie du viewmodel FP : encore taggé "skin", on le supprime en bloc.
	remaining_skin = [f for f in bm.faces if f.material_index == SKIN]
	bmesh.ops.delete(bm, geom=remaining_skin, context='FACES')

	me_new = bpy.data.meshes.new("fp_arms")
	bm.to_mesh(me_new)
	bm.free()

	obj = bpy.data.objects.new("FPArms", me_new)
	bpy.context.scene.collection.objects.link(obj)
	for name in bone_order:
		obj.vertex_groups.new(name=name)

	bpy.data.objects.remove(mannequin, do_unlink=True)

	_pose_fp_hold(rig)  # action "FP_Hold" — voir ViewModel.gd (remplace Pistol_Idle/Pistol_Aim_Neutral).

	# Pas de budget tris imposé par le contrat pour fp_arms (seuls les 6
	# agents ont une limite de 15k) ; 10k est une marge confortable pour un
	# viewmodel proche caméra. "outfit" est inutilisé ici (la manche reste
	# "cloth"/équipe, cf. en-tête) : couleur neutre de repli. Le gant
	# ("gear") a sa propre couleur cuir (FP_GLOVE_COLOR), jamais GEAR_COLOR
	# (quasi noir une fois ombré de près, cf. son commentaire) : ce
	# viewmodel est la SEULE utilisation de `gear_color_override`, les 6
	# agents (`build_character`) ne le passent jamais et gardent GEAR_COLOR.
	_finish_object("fp_arms", rig, obj, (0.6, 0.6, 0.6, 1.0), (0.6, 0.6, 0.6, 1.0), tris_budget=10000,
		gear_color_override=FP_GLOVE_COLOR)
	_export("fp_arms", rig, obj, "fp_arms")


def main() -> None:
	# FP_ARMS_ONLY=1 : ne reconstruit QUE fp_arms.glb (itération pose FP_Hold
	# sans re-générer les 6 agents, coûteux — voir rapport de tâche). Ne
	# change jamais la sortie des 6 agents (contrat de cette tranche) :
	# `main()` sans cette variable garde exactement l'ancien comportement.
	if os.environ.get("FP_ARMS_ONLY") == "1":
		build_fp_arms()
		return
	for char_id, gear_fn in CHARACTERS.items():
		build_character(char_id, gear_fn)
	build_fp_arms()


if __name__ == "__main__":
	main()
