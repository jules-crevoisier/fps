## tools/blender/make_stylized_rocks.py
## Tache TOOL-02B - Roches v2 "taillees a la serpe", mesas et falaises a
## terrasses, paroi de canyon raccordable, texture peinte de strates alignee
## a l'horizontale (remplace la v1 TOOL-02).
##
## Verdict du lead sur la v1 (2026-09-25) : techniquement propre mais
## visuellement faux - rochers en oeufs lisses, falaises et mesas en piles de
## crepes cylindriques, bord de canyon en escalier. Techniques imposees par
## le contrat TOOL-02B, reprises telles quelles ici :
##
##   ROCHERS  icosphere subdiv 2 etiree NON uniformement, puis 6-10 coupes
##            planes (bmesh.ops.bisect_plane, clear_outer, trou rebouche en
##            une grande facette plane) orientees surtout horizontales dessus
##            / verticales sur les flancs, puis une 2e passe de petites coupes
##            (ecornures) et un biseau 1 segment de 2-4 cm qui accroche
##            l'encre. Azimuts des coupes tires irregulierement, rotation
##            aleatoire de l'icosphere avant etirement : jamais de symetrie
##            radiale visible.
##   FALAISES contour 2D irregulier (12-24 sommets, rayon bruite par des lobes
##   MESAS    basse frequence + bruit par sommet, empreinte allongee : pas un
##            cercle) extrude en 3-5 terrasses de hauteurs INEGALES (talus
##            d'eboulis en pente au pied, une paroi dominante), chacune avec
##            SON contour, son retrait (ou son avancee), son fruit et son
##            decalage de centre (corniche large d'un cote, aplomb de
##            l'autre), taillee par ses propres coupes planes verticales ;
##            coupes de fracture qui tranchent plusieurs terrasses d'un seul
##            plan (grandes faces d'aplomb : jamais une pile de galettes) ;
##            rainures verticales en V creusees par coupes planes (difference
##            booleenne d'un prisme triangulaire pose sur la paroi reelle) ;
##            blocs eboules au pied (meme technique que les rochers) ; dessus
##            plat avec levre (dalle sommitale en surplomb).
##   CANYON   mur long extrude (profil a 3 terrasses + levre, identique aux
##            deux bouts) dont la face est taillee, loin des bouts, par des
##            contreforts a facettes, des baies creusees par solides a
##            facettes, des rainures en V et des chanfreins de corniche ;
##            blocs eboules au pied. Raccord verifie sur la geometrie FINALE
##            exportee (`seam_max_delta_m`), jamais suppose. Contreforts :
##            socle + fut recule, contour ANGULEUX (dos noye dans la paroi,
##            etrave basse asymetrique) dont chaque coin visible est un pli
##            franc encre, dessus en pente - jamais la colonne quasi
##            cylindrique de la 1re passe TOOL-02B ; mesure en coupe
##            horizontale a plusieurs hauteurs (`buttress_sections`).
##
## Chaque piece est un seul objet ; ses volumes (terrasses, blocs, contreforts)
## sont fusionnes par union booleenne EXACTE (modificateur BOOLEAN, solveur
## 'EXACT', auto-intersections resolues, sonde en 5.2) : maillage ferme, aucune
## face cachee, aucun flottant (CHK-16) - check_asset PASS est un vrai PASS,
## sans exception. Chaque piece est ensuite triangulee et verifiee (aucune
## arete a plus de 2 faces, aucun polygone replie : `triangulate_manifold`).
## AUCUN bruit organique mou : jamais d'icosphere lissee + SUBSURF + DISPLACE
## (toonkit.blob), jamais de modificateur SUBSURF.
##
## Matiere (contrat TOOL-02B) : la texture peinte
## assets/textures/wasteland/wl_rock_strata_albedo.png (deja raccordable)
## projetee EN BOITE a l'echelle du monde (1 tuile = STRATA_TILE_M = 2 m), puis
## AO/creux, eclat et encre des aretes cuits PAR-DESSUS : c'est exactement ce
## que fait tools/blender/paint_bake.py v2 (TOOL-01B) pour un slot dont le
## kind resout vers une texture peinte - noeud Image Texture en projection
## BOX sur les coordonnees objet metriques x WORLD_UV_SCALE (0,5 tuile/m,
## verifie a l'execution par `painter_world_uv_scale`), luminance recalee sur
## la texture source. En projection BOX, une face projetee par un cote (X ou
## Y dominant) lit v = z x 0,5 : une rangee de strates = une hauteur, donc
## des strates horizontales et continues d'une facette a l'autre. D'ou deux
## slots par piece (`assign_material_slots`) :
##   - STRATA_SLOT (strates) : toute face qui n'est pas un dessus ;
##   - SAND_SLOT (sable clair : image SAND_TEXTURE_PATH posee sur le slot,
##     reprise par paint_bake en mode "existing") : les dessus - normale
##     montante dont Z domine X et Y, soit exactement les faces que la boite
##     projetterait par le haut (terrasses, dalle sommitale, dessus des
##     rochers). Aucune face de strates n'est donc projetee par le haut ;
##     seuls les dessous de surplomb le sont, par le bas (mesure
##     `underside_area_m2`).
## Chaine par piece (`produce_piece`) :
##   1. geometrie (bmesh + booleens), biseau, normales ponderees, attribut
##      de normale lissee, slots strates/sable -> .glb brut temporaire ;
##   2. paint_bake.py en sous-process (CLI publique `--in --out --res
##      --skip-turntable`) : UV de cuisson, base projetee en boite par slot,
##      AO/creux teintes, liseré et encre des aretes, degrade, grain ->
##      "<id>.glb" dans le dossier de sortie + son sidecar ;
##   3. relecture du .glb peint : mesures de la texture cuite (visible, teinte
##      chaude, aucune teinte reservee, luminance), raccord du canyon, puis
##      check_asset ; le sidecar de paint_bake est complete (strates,
##      echelle, slots, mesures).
## Sortie : "<id>.glb" avec UN materiau "<id>_painted" (texture cuite, deja
## reconnu cote jeu par Cartoon.painted_texture_prop) + sidecar JSON, sans
## couleur de sommet (un COLOR_0 multiplierait la texture cuite, voir
## paint_bake.py etape 5).
##
## 12 pieces (assets/models/props/wasteland/rocks/) - budgets TOOL-02 :
##   - 6 rochers            0,3-2 m     <= 800 tris   rock_01..rock_06
##   - 3 blocs de falaise   4-10 m      <= 3000 tris  cliff_block_01..03
##   - 2 mesas lointaines   30-60 m     <= 2000 tris  mesa_01..mesa_02
##   - 1 paroi de canyon raccordable   <= 3000 tris  canyon_edge_01
##
## Lancer (12 pieces + manifest.json) :
##   blender -b -P tools/blender/make_stylized_rocks.py
## Une seule piece, iteration rapide (eventuellement hors du depot) :
##   blender -b -P tools/blender/make_stylized_rocks.py -- --only rock_01 [--out-dir DOSSIER]
## Mode utilise par tools/blender/tests/test_make_stylized_rocks.py :
##   blender -b -P tools/blender/make_stylized_rocks.py -- --selftest-json OUT.json
## Planche de controle (turntable par piece + planche des 12, texture visible
## grace au correctif TOOL-01 de turntable.py) :
##   blender -b -P tools/blender/make_stylized_rocks.py -- --captures assets/models/props/wasteland/rocks/_captures
import argparse
import functools
import json
import math
import os
import random
import shutil
import subprocess
import sys
import tempfile

import bpy
import bmesh
import numpy as np
from mathutils import Euler, Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "lib"))
import toonkit  # noqa: E402

# check_asset importe directement (meme dossier), comme make_wl_shanty_kit.py :
# chaque .glb final passe la meme verification que la revue humaine.
sys.path.insert(0, _HERE)
import check_asset  # noqa: E402
# Reutilise EN LECTURE SEULE pour la planche de synthese (build_contact_sheet).
import turntable  # noqa: E402

REPO_ROOT = os.path.dirname(os.path.dirname(_HERE))
OUT_DIR = os.path.join(REPO_ROOT, "assets", "models", "props", "wasteland", "rocks")
PAINT_BAKE_SCRIPT = os.path.join(_HERE, "paint_bake.py")
TURNTABLE_SCRIPT = os.path.join(_HERE, "turntable.py")

# ---------------------------------------------------------------------------
# Constantes du contrat TOOL-02 / TOOL-02B
# ---------------------------------------------------------------------------

BUDGET_TRIS = {
	"rock": 800,
	"cliff": 3000,
	"mesa": 2000,
	# Non chiffre par le contrat TOOL-02 - repris au plafond "falaises", le
	# poste le plus proche en echelle et en detail (decision v1 conservee).
	"canyon_edge": 3000,
	# ART-98 (registre v4, docs/art/WASTELAND_V4_ART_PLAN.md SS2/SS4) - deux
	# nouvelles categories, jamais melangees au registre v2/v3 ci-dessus (voir
	# V4_PIECES/build_all_v4) :
	#  - "spire"      : les 8 aiguilles RocherS1W/N1W/S2W/GueW + est - plus
	#                   grandes que "rock" (jusqu'a 4 m de large) mais un seul
	#                   objet compact, budget a mi-chemin entre "rock" et "cliff".
	#  - "cliff_wall" : segments de CliffN/S/W/E - meme ordre de grandeur que
	#                   "cliff" (silhouette simple, un seul plan flush cote jeu).
	"spire": 2500,
	"cliff_wall": 3000,
}

# Biseau 1 segment, limite par angle 30 deg (toonkit.add_bevel). Rochers :
# largeur par piece dans ROCK_SPECS (2-4 cm, contrat). Mesas : aucun biseau
# (decor lointain, 30-60 m vus a plus de 60 m : un biseau y serait
# sous-pixel et doublerait des triangles comptes au budget de 2000). La
# paroi de canyon n'a JAMAIS de biseau : ses deux bouts doivent rester la meme boucle de sommets
# translatee (un biseau par angle chanfreinerait les aretes du raccord et
# creuserait un V a chaque jointure entre deux modules).
# Jamais "cliff_wall" ici : ce dictionnaire est un contrat verrouille par
# tools/blender/tests/test_make_stylized_rocks.py (hors de mon perimetre,
# meme verification que BUDGET_TRIS ci-dessus, voir build_all). build_wall_
# segment (ART-98) ne consomme d'ailleurs plus ce dictionnaire du tout -
# _CLIFF_WALL_BEVEL_M ci-dessous, une constante locale au registre v4.
BEVEL_WIDTH_M = {"cliff": 0.06, "mesa": 0.0, "canyon_edge": 0.0}
ROCK_BEVEL_RANGE_M = (0.02, 0.04)
# Aiguilles v4 (ART-98) : meme plage que les rochers du registre v2 (2-4 cm) -
# biseau par piece choisi dans V4_ROCHER_SPECS, comme ROCK_SPECS ci-dessous.
SPIRE_BEVEL_RANGE_M = (0.02, 0.04)

# Matiere : texture peinte de strates projetee en boite a l'echelle du monde
# par paint_bake.py (v2, TOOL-01B). Le slot des strates porte un nom que
# paint_bake.resolve_base_texture resout vers STRATA_TEXTURE_PATH ; celui des
# dessus porte DEJA son image (mode "existing" de paint_bake) : le sable
# peint du terrain, le plus clair de la bibliotheque (luma 0,66, contre 0,60
# pour material_sand_dirt et 0,41 pour les strates) - un sable clair sur la
# roche rouge, du meme ton que le sol ou la piece est posee.
STRATA_TEXTURE_PATH = os.path.join(REPO_ROOT, "assets", "textures", "wasteland", "wl_rock_strata_albedo.png")
SAND_TEXTURE_PATH = os.path.join(REPO_ROOT, "assets", "textures", "painted", "terrain_sable_albedo.png")
STRATA_TILE_M = 2.0
STRATA_SLOT = "wl_rock_strata"
SAND_SLOT = "sand_top"
BAKE_RES = {"rock": 1024, "cliff": 2048, "mesa": 2048, "canyon_edge": 2048, "spire": 1024, "cliff_wall": 2048}
PAINT_BAKE_TIMEOUT_S = 900

# Bandes de teinte reservees (surbrillance ennemie/alliee, docs/STYLE_BIBLE.md
# / tasks/context.md) - dupliquees ici comme dans paint_bake.py (pas d'import
# croise de logique entre scripts freres) pour le lint des pixels cuits.
RESERVED_HUE_BANDS_DEG = ((300.0, 355.0), (105.0, 145.0))
RESERVED_HUE_CHROMA_THRESHOLD = 0.08

# Soudure des sommets apres les booleens (massifs, canyon) : juste au-dessus
# de la soudure a 0,1 mm de check_asset (meme topologie vue des deux cotes),
# jamais plus - une soudure a 1e-3 x taille (3,5 cm sur une mesa) deplacait
# des sommets de quelques mm hors de leur plan et repliait un polygone sur
# lui-meme (arete a 4 triangles apres triangulation, constate sur mesa_01).
BOOLEAN_WELD_M = 2e-4
# Le biseau par angle, bride sur une arete plus courte que deux largeurs de
# biseau, laisse parfois un triangle retourne de quelques mm2 (au plus ~1 cm2
# mesure sur rock_06, invisible) : tolere et compte (`micro_folds`). Au-dela,
# c'est un polygone qui se recoupe (0,38 m2 constate sur mesa_01 avant la
# correction de BOOLEAN_WELD_M) : la generation echoue.
MICRO_FOLD_MAX_M2 = 2e-4

# Une "grande facette" de rocher couvre au moins cette part de l'aire totale
# (une icosphere subdiv 2 etiree - un oeuf - n'a que des faces de ~1,25 %).
LARGE_FACET_MIN_AREA_FRACTION = 0.03


# ---------------------------------------------------------------------------
# Outils geometriques communs (bmesh)
# ---------------------------------------------------------------------------

def _support(bm: "bmesh.types.BMesh", normal: Vector) -> float:
	"""Distance max des sommets le long de `normal` (fonction d'appui)."""
	return max(normal.dot(v.co) for v in bm.verts)


def plane_cut(bm: "bmesh.types.BMesh", plane_co, plane_no) -> bool:
	"""Coupe plane "a la serpe" : retire tout ce qui est du cote de `plane_no`
	(bisect_plane, clear_outer) et rebouche le trou par UNE facette plane
	(holes_fill sur les aretes de bord - le maillage etant ferme avant la
	coupe, toutes ses aretes de bord viennent de cette coupe). Sans effet
	(False) si le plan ne traverse pas le solide : jamais un solide vide."""
	no = Vector(plane_no).normalized()
	co = Vector(plane_co)
	dists = [no.dot(v.co - co) for v in bm.verts]
	if max(dists) <= 1e-6 or min(dists) >= -1e-6:
		return False
	geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
	bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=co, plane_no=no, clear_outer=True)
	boundary = [e for e in bm.edges if e.is_boundary]
	bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
	return True


def _append_bmesh(dst: "bmesh.types.BMesh", src: "bmesh.types.BMesh") -> list:
	"""Copie les faces de `src` dans `dst` (meme enroulement). Renvoie les
	faces creees."""
	vmap = {v: dst.verts.new(v.co) for v in src.verts}
	return [dst.faces.new([vmap[v] for v in f.verts]) for f in src.faces]


def _cleanup(bm: "bmesh.types.BMesh", merge_dist: float) -> None:
	"""Soude les doublons (< `merge_dist` m), retire les aretes degenerees
	et refond les facettes quasi coplanaires (heritees des coupes et des
	booleens) en n-gones plans : moins de triangles, facettes plus grandes."""
	bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=merge_dist)
	bmesh.ops.dissolve_degenerate(bm, dist=merge_dist, edges=list(bm.edges))
	bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(2.0), use_dissolve_boundaries=False,
		verts=list(bm.verts), edges=list(bm.edges))
	loose = [v for v in bm.verts if not v.link_faces]
	if loose:
		bmesh.ops.delete(bm, geom=loose, context='VERTS')
	bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))


def _assert_closed(bm: "bmesh.types.BMesh", what: str) -> None:
	boundary = sum(1 for e in bm.edges if e.is_boundary)
	nonmanifold = sum(1 for e in bm.edges if len(e.link_faces) >= 3)
	if boundary or nonmanifold:
		raise RuntimeError(f"make_stylized_rocks: {what} n'est pas un solide ferme "
			f"({boundary} arete(s) de bord, {nonmanifold} arete(s) non-manifold)")


def _bbox(bm: "bmesh.types.BMesh") -> tuple:
	xs = [v.co.x for v in bm.verts]
	ys = [v.co.y for v in bm.verts]
	zs = [v.co.z for v in bm.verts]
	return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def _fit_to_dims(bm: "bmesh.types.BMesh", dims) -> None:
	"""Mise a l'echelle par axe sur `dims` exactes, puis pose au sol, centre
	XY a l'origine (origine au centre-bas, convention check_asset)."""
	lo, hi = _bbox(bm)
	size = hi - lo
	center = (lo + hi) / 2.0
	bmesh.ops.translate(bm, vec=(-center.x, -center.y, -lo.z), verts=list(bm.verts))
	bmesh.ops.scale(bm, vec=(dims[0] / size.x, dims[1] / size.y, dims[2] / size.z), verts=list(bm.verts))


def _ground_cut(bm: "bmesh.types.BMesh") -> None:
	"""Tout est construit un peu sous z=0 (bases enfouies) : une coupe plane a
	z=0 donne UNE base plate commune, sans faces coplanaires superposees."""
	plane_cut(bm, (0.0, 0.0, 0.0), (0.0, 0.0, -1.0))


def _principal_aspect(points2d: list) -> float:
	"""Allongement d'un nuage 2D : etendue le long de l'axe principal (ACP)
	divisee par l'etendue le long de l'axe perpendiculaire (1.0 = isotrope)."""
	n = len(points2d)
	mx = sum(p[0] for p in points2d) / n
	my = sum(p[1] for p in points2d) / n
	cxx = sum((p[0] - mx) ** 2 for p in points2d) / n
	cyy = sum((p[1] - my) ** 2 for p in points2d) / n
	cxy = sum((p[0] - mx) * (p[1] - my) for p in points2d) / n
	ang = 0.5 * math.atan2(2.0 * cxy, cxx - cyy)
	e1 = (math.cos(ang), math.sin(ang))
	e2 = (-math.sin(ang), math.cos(ang))
	p1 = [p[0] * e1[0] + p[1] * e1[1] for p in points2d]
	p2 = [p[0] * e2[0] + p[1] * e2[1] for p in points2d]
	ext1, ext2 = max(p1) - min(p1), max(p2) - min(p2)
	return max(ext1, ext2) / max(1e-9, min(ext1, ext2))


def _large_facet_area_ratio(bm: "bmesh.types.BMesh") -> float:
	areas = [f.calc_area() for f in bm.faces]
	total = sum(areas)
	return sum(a for a in areas if a >= LARGE_FACET_MIN_AREA_FRACTION * total) / total


# ---------------------------------------------------------------------------
# Booleens exacts (modificateur BOOLEAN, solveur 'EXACT', evalue par le
# depsgraph). L'operateur d'edition bpy.ops.mesh.intersect_boolean renvoyait
# un maillage VIDE sur une difference pourtant saine (rainure de
# cliff_block_02, sondage 5.2 : 86,5 m3 - 1,1 m3 -> vide, quand le
# modificateur rend bien 86,24 m3) : il n'est plus utilise.
# ---------------------------------------------------------------------------

def _temp_object(name: str, bm: "bmesh.types.BMesh"):
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	obj = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(obj)
	return obj


def _evaluate_boolean(target, operation: str, operand=None) -> "bmesh.types.BMesh":
	"""Evalue un modificateur BOOLEAN EXACT (auto-intersections resolues,
	`use_self`) sur `target` - operande : l'objet `operand`, ou une
	collection vide (auto-union des coques de `target`). Renvoie le resultat
	en bmesh, normales recalculees vers l'exterieur, et supprime les objets
	temporaires."""
	mod = target.modifiers.new("__stylized_rocks_bool", 'BOOLEAN')
	mod.operation = operation
	mod.solver = 'EXACT'
	mod.use_self = True
	empty = None
	if operand is not None:
		mod.operand_type = 'OBJECT'
		mod.object = operand
	else:
		empty = bpy.data.collections.new("__stylized_rocks_empty")
		mod.operand_type = 'COLLECTION'
		mod.collection = empty
	depsgraph = bpy.context.evaluated_depsgraph_get()
	evaluated = target.evaluated_get(depsgraph)
	out = bmesh.new()
	out.from_mesh(evaluated.to_mesh())
	evaluated.to_mesh_clear()
	for obj in (target, operand):
		if obj is not None:
			me = obj.data
			bpy.data.objects.remove(obj, do_unlink=True)
			bpy.data.meshes.remove(me)
	if empty is not None:
		bpy.data.collections.remove(empty)
	bmesh.ops.recalc_face_normals(out, faces=list(out.faces))
	return out


def union_all(bm: "bmesh.types.BMesh") -> "bmesh.types.BMesh":
	"""Auto-union de TOUTES les coques de `bm` (volumes qui se chevauchent
	fusionnes, faces internes retirees). `bm` est consomme (libere) ; renvoie
	un nouveau bmesh."""
	target = _temp_object("__stylized_rocks_union", bm)
	bm.free()
	return _evaluate_boolean(target, 'UNION')


def subtract(bm: "bmesh.types.BMesh", cutters: "bmesh.types.BMesh") -> "bmesh.types.BMesh":
	"""Retire de `bm` le volume des coques de `cutters` (qui peuvent se
	chevaucher : elles sont d'abord fusionnees entre elles). `bm` et
	`cutters` sont consommes ; renvoie un nouveau bmesh."""
	merged = union_all(cutters)
	target = _temp_object("__stylized_rocks_target", bm)
	operand = _temp_object("__stylized_rocks_cutter", merged)
	bm.free()
	merged.free()
	return _evaluate_boolean(target, 'DIFFERENCE', operand)


# ---------------------------------------------------------------------------
# Rochers : icosphere subdiv 2 etiree + coupes planes (+ ecornures)
# ---------------------------------------------------------------------------

def cut_rock_solid(rng: random.Random, half_extents, main_cuts: int, detail_cuts: int,
		subdivisions: int = 2) -> tuple:
	"""Solide de roche taille a la serpe, centre a l'origine. Renvoie
	(bmesh, nb_coupes_principales, nb_ecornures) - facettes survivantes.
	Coupes principales : 1 base horizontale (le rocher se pose a plat), 1-2
	dessus quasi horizontaux (inclines de 4-16 deg), le reste en flancs quasi
	verticaux a des azimuts IRREGULIERS. Ecornures : petits plans obliques
	qui retirent un coin ou une arete (3-8 % de l'appui). `subdivisions` : 2
	pour les rochers (contrat) ; 1 (icosaedre) pour les blocs eboules et les
	solides de taille des parois, dont la surface est presque entierement
	remplacee par les coupes - meme silhouette, trois fois moins de
	triangles dans le budget d'une falaise ou d'une mesa."""
	bm = bmesh.new()
	bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=1.0)
	rot = Euler((rng.uniform(0.0, math.tau), rng.uniform(0.0, math.tau), rng.uniform(0.0, math.tau))).to_matrix()
	bmesh.ops.rotate(bm, cent=(0.0, 0.0, 0.0), matrix=rot, verts=list(bm.verts))
	for v in bm.verts:
		v.co *= 1.0 + rng.uniform(-0.06, 0.06)
	bmesh.ops.scale(bm, vec=tuple(half_extents), verts=list(bm.verts))

	planes = []
	planes.append((Vector((0.0, 0.0, -1.0)), rng.uniform(0.18, 0.30)))
	# 1 ou 2 dessus quasi horizontaux ; le 2e du cote oppose, incline dans
	# l'autre sens : un faitage casse plutot qu'un couvercle de tambour.
	n_top = 1 if main_cuts <= 7 else 2
	az_top = rng.uniform(0.0, math.tau)
	for k in range(n_top):
		tilt = math.radians(rng.uniform(4.0, 16.0))
		az = az_top + (math.pi + rng.uniform(-0.6, 0.6)) * k
		planes.append((Vector((math.sin(tilt) * math.cos(az), math.sin(tilt) * math.sin(az), math.cos(tilt))),
			rng.uniform(0.16, 0.28)))
	# Flancs : azimuts irreguliers, pentes variees (surtout rentrantes vers le
	# haut, parfois en devers) - jamais une couronne reguliere de faces verticales.
	n_flank = main_cuts - len(planes)
	az = rng.uniform(0.0, math.tau)
	for _ in range(n_flank):
		az += rng.uniform(0.55, 1.45) * math.tau / max(1, n_flank)
		tilt = rng.uniform(-0.30, 0.60)
		planes.append((Vector((math.cos(az), math.sin(az), tilt)).normalized(), rng.uniform(0.18, 0.34)))

	main_normals = []
	for normal, depth in planes:
		if plane_cut(bm, normal * (_support(bm, normal) * (1.0 - depth)), normal):
			main_normals.append(normal)

	detail_normals = []
	attempts = 0
	while len(detail_normals) < detail_cuts and attempts < detail_cuts * 4:
		attempts += 1
		az = rng.uniform(0.0, math.tau)
		nz = rng.uniform(-0.15, 0.85)
		normal = Vector((math.cos(az), math.sin(az), nz)).normalized()
		if plane_cut(bm, normal * (_support(bm, normal) * (1.0 - rng.uniform(0.03, 0.08))), normal):
			detail_normals.append(normal)

	_cleanup(bm, 0.004 * max(half_extents))
	_assert_closed(bm, "rocher")
	# Coupes comptees seulement si leur facette SURVIT (une coupe suivante ou
	# la soudure des aretes courtes peut l'avoir absorbee) : une face du
	# solide final porte encore la normale du plan de coupe.
	normals = [f.normal.copy() for f in bm.faces]

	def survived(cut_normals: list) -> int:
		return sum(1 for n in cut_normals if any(n.dot(fn) > 0.999 for fn in normals))

	return bm, survived(main_normals), survived(detail_normals)


ROCK_ICOSPHERE_SUBDIVISIONS = 2  # contrat TOOL-02B : "icosphere subdiv 2"

ROCK_SPECS = [
	# (nom, dimensions finales X/Y/Z en m, coupes principales, ecornures, biseau m, seed)
	# Tous plus larges que hauts au-dela de 1 m : aucun bloc 1,5-1,9 m x <= 0,8 m
	# (CHK-17, "pas d'humanoide parasite").
	("rock_01", (0.36, 0.27, 0.22), 8, 3, 0.020, 1101),
	("rock_02", (0.64, 0.44, 0.28), 8, 4, 0.024, 1102),   # dalle
	("rock_03", (0.92, 0.66, 0.60), 9, 5, 0.028, 1103),
	("rock_04", (1.26, 0.80, 0.82), 8, 5, 0.032, 1104),   # coin
	("rock_05", (1.60, 1.12, 1.00), 10, 6, 0.036, 1105),
	("rock_06", (1.98, 1.36, 1.26), 10, 6, 0.040, 1106),
]


def build_rock(name: str, dims, main_cuts: int, detail_cuts: int, bevel: float, seed: int) -> dict:
	rng = random.Random(seed)
	# Icosphere etiree un peu plus que la cible : les coupes en retirent une part.
	half = (dims[0] * 0.62, dims[1] * 0.62, dims[2] * 0.66)
	bm, done_main, done_detail = cut_rock_solid(rng, half, main_cuts, detail_cuts,
		subdivisions=ROCK_ICOSPHERE_SUBDIVISIONS)
	_fit_to_dims(bm, dims)
	stats = {
		"icosphere_subdivisions": ROCK_ICOSPHERE_SUBDIVISIONS,
		"main_plane_cuts": done_main,
		"detail_plane_cuts": done_detail,
		"large_facet_area_ratio": round(_large_facet_area_ratio(bm), 4),
		"footprint_aspect": round(_principal_aspect([(v.co.x, v.co.y) for v in bm.verts]), 4),
		"bevel_width_m": bevel,
	}
	return {"bm": bm, "bevel": bevel, "stats": stats}


# ART-98 (docs/art/WASTELAND_V4_ART_PLAN.md SS2 "Roches et falaises" - "8
# aiguilles UNIQUES, generees aux cotes exactes de leur boite : 8 graines, pas
# de copie miroir. Facettes a +/-10 cm, dessus plat avec une levre <= 10 cm.")
SPIRE_TOP_CAP_THICKNESS_M = 0.05  # coupe nette du dessus, juste sous la hauteur cible
SPIRE_TOP_LIP_M = 0.06            # surplomb de la levre - sous le plafond du contrat (10 cm)


def build_spire(name: str, dims, main_cuts: int, detail_cuts: int, bevel: float, seed: int) -> dict:
	"""Aiguille rocheuse v4 (RocherS1W/N1W/S2W/GueW + est) : memes coupes
	organiques que `build_rock` (`cut_rock_solid` + `_fit_to_dims` - la piece
	remplit EXACTEMENT sa boite, "generee aux cotes exactes du plan d'art"),
	puis un dessus APLANI par une coupe horizontale nette a la hauteur cible
	(`plane_cut` scelle TOUJOURS son plan par une facette plane, `holes_fill`
	- dessus plat garanti, jamais mesure a posteriori), surmonte d'une levre
	en faible surplomb (<= `SPIRE_TOP_LIP_M`, meme technique que la "dalle
	sommitale" de `build_massif` : section horizontale juste sous le sommet,
	contour elargi, prisme fin unifie par-dessus)."""
	rng = random.Random(seed)
	half = (dims[0] * 0.62, dims[1] * 0.62, dims[2] * 0.66)
	bm, done_main, done_detail = cut_rock_solid(rng, half, main_cuts, detail_cuts,
		subdivisions=ROCK_ICOSPHERE_SUBDIVISIONS)
	_fit_to_dims(bm, dims)
	height = dims[2]
	cap_z = height - SPIRE_TOP_CAP_THICKNESS_M
	plane_cut(bm, (0.0, 0.0, cap_z), (0.0, 0.0, 1.0))
	# Soudure a la tolerance ABSOLUE de check_asset (BOOLEAN_WELD_M, 0,2 mm) -
	# PAS la tolerance RELATIVE (0,004 x taille) de cut_rock_solid : `bm` est
	# ICI deja mis a l'echelle EXACTE de la boite par `_fit_to_dims` ci-dessus,
	# une soudure relative (jusqu'a 1,8 cm sur une aiguille de 4,5 m) grignote
	# alors visiblement la cote "generee aux cotes exactes de sa boite" (SS2).
	_cleanup(bm, BOOLEAN_WELD_M)
	outline = horizontal_section(bm, cap_z - 1e-3)
	lip_added = False
	merged = bmesh.new()
	_append_bmesh(merged, bm)
	bm.free()
	if len(outline) >= 3:
		c = _polygon_centroid(outline)
		mean_r = _mean_radius(outline, c)
		if mean_r > 1e-6:
			lip_outline = _scaled_outline(outline, c, (mean_r + SPIRE_TOP_LIP_M) / mean_r)
			cap = prism_solid(lip_outline, cap_z, lip_outline, height)
			_append_bmesh(merged, cap)
			cap.free()
			lip_added = True
	bm = union_all(merged)
	_ground_cut(bm)
	_cleanup(bm, BOOLEAN_WELD_M)
	_assert_closed(bm, "aiguille")
	stats = {
		"icosphere_subdivisions": ROCK_ICOSPHERE_SUBDIVISIONS,
		"main_plane_cuts": done_main,
		"detail_plane_cuts": done_detail,
		"top_flat": True,
		"top_lip_added": lip_added,
		"top_lip_m": SPIRE_TOP_LIP_M if lip_added else 0.0,
		"footprint_aspect": round(_principal_aspect([(v.co.x, v.co.y) for v in bm.verts]), 4),
		"bevel_width_m": bevel,
	}
	return {"bm": bm, "bevel": bevel, "stats": stats}


# ---------------------------------------------------------------------------
# Falaises et mesas : terrasses a contour irregulier, rainures, eboulis, levre
# ---------------------------------------------------------------------------

def irregular_outline(rng: random.Random, n: int, rx: float, ry: float, lobes: list) -> list:
	"""Contour 2D en etoile (simple par construction : angles tries, rayon > 0)
	de `n` sommets, a angles IRREGULIERS, rayon module par des lobes basse
	frequence (identite du massif, partages entre ses terrasses) + un bruit
	par sommet propre a chaque appel, sur une ellipse rx x ry : jamais un
	cercle."""
	phase = rng.uniform(0.0, math.tau)
	angles = sorted(phase + math.tau * (k + rng.uniform(-0.32, 0.32)) / n for k in range(n))
	pts = []
	for a in angles:
		r = 1.0 + sum(amp * math.cos(freq * a + ph) for (freq, amp, ph) in lobes) + rng.uniform(-0.07, 0.07)
		r = max(0.55, r)
		pts.append((rx * r * math.cos(a), ry * r * math.sin(a)))
	return pts


def _polygon_centroid(pts: list) -> tuple:
	return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def _mean_radius(pts: list, center: tuple) -> float:
	return sum(math.hypot(p[0] - center[0], p[1] - center[1]) for p in pts) / len(pts)


def _ray_radius(outline: list, center: tuple, theta: float) -> float:
	"""Distance du centre au bord du contour dans la direction `theta`."""
	dx, dy = math.cos(theta), math.sin(theta)
	best = 0.0
	n = len(outline)
	for i in range(n):
		ax, ay = outline[i]
		bx, by = outline[(i + 1) % n]
		ex, ey = bx - ax, by - ay
		den = dx * ey - dy * ex
		if abs(den) < 1e-12:
			continue
		wx, wy = ax - center[0], ay - center[1]
		t = (wx * ey - wy * ex) / den
		s = (wx * dy - wy * dx) / den
		if 0.0 <= s <= 1.0 and t > best:
			best = t
	return best


def _scaled_outline(pts: list, center: tuple, factor: float) -> list:
	return [(center[0] + (x - center[0]) * factor, center[1] + (y - center[1]) * factor) for x, y in pts]


def prism_solid(outline_bottom: list, z0: float, outline_top: list, z1: float) -> "bmesh.types.BMesh":
	"""Prisme ferme entre deux contours de meme nombre de sommets."""
	bm = bmesh.new()
	vb = [bm.verts.new((x, y, z0)) for x, y in outline_bottom]
	vt = [bm.verts.new((x, y, z1)) for x, y in outline_top]
	n = len(vb)
	for i in range(n):
		j = (i + 1) % n
		bm.faces.new((vb[i], vb[j], vt[j], vt[i]))
	bm.faces.new(list(reversed(vb)))
	bm.faces.new(vt)
	bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
	return bm


def _groove_cutter_at(point: Vector, outward: Vector, width: float, depth: float,
		z0: float, z1: float) -> "bmesh.types.BMesh":
	"""Prisme triangulaire vertical (V en plan) pose sur la paroi en `point`
	(normale horizontale `outward`) : sommet a `depth` derriere la paroi,
	ouverture a l'exterieur, largeur `width` au nu de la paroi. Ses deux faces
	laterales sont les deux coupes planes de la rainure."""
	ox, oy = outward.x, outward.y
	tx, ty = -oy, ox
	out = 0.6 * depth
	half_mouth = 0.5 * width * (depth + out) / depth
	apex = (point.x - ox * depth, point.y - oy * depth)
	mouth = (point.x + ox * out, point.y + oy * out)
	tri = [apex, (mouth[0] + tx * half_mouth, mouth[1] + ty * half_mouth),
		(mouth[0] - tx * half_mouth, mouth[1] - ty * half_mouth)]
	return prism_solid(tri, z0, tri, z1)


def _probe_wall(bm: "bmesh.types.BMesh", center: tuple, theta: float, z: float, reach: float):
	"""Point de paroi touche par un rayon horizontal tire de l'exterieur vers
	l'axe vertical passant par `center`, a la hauteur `z`, azimut `theta` :
	(point, normale horizontale unitaire), ou None si rien n'est touche ou si
	la face touchee n'est pas une paroi (dessus de terrasse, dessous de
	surplomb). Sert a poser rainures et eboulis sur la surface REELLE, apres
	les coupes et les booleens."""
	tree = BVHTree.FromBMesh(bm)
	d = Vector((math.cos(theta), math.sin(theta), 0.0))
	origin = Vector((center[0], center[1], z)) + d * reach
	hit, normal, _index, _dist = tree.ray_cast(origin, -d, 2.0 * reach)
	if hit is None:
		return None
	nh = Vector((normal.x, normal.y, 0.0))
	if nh.length < 0.6:
		return None
	return hit, nh.normalized()


def _place_block(rng: random.Random, dims, pos: tuple, sink: float) -> "bmesh.types.BMesh":
	"""Bloc eboule (meme technique que les rochers), pose au sol en `pos`
	(x, y), enfoui de `sink` sous z=0, lacet aleatoire."""
	half = (dims[0] * 0.62, dims[1] * 0.62, dims[2] * 0.66)
	bm, _m, _d = cut_rock_solid(rng, half, main_cuts=6, detail_cuts=1, subdivisions=1)
	_fit_to_dims(bm, dims)
	bmesh.ops.rotate(bm, cent=(0.0, 0.0, 0.0), matrix=Matrix.Rotation(rng.uniform(0.0, math.tau), 3, "Z"),
		verts=list(bm.verts))
	bmesh.ops.translate(bm, vec=(pos[0], pos[1], -sink), verts=list(bm.verts))
	return bm


CLIFF_SPECS = [
	# (nom, empreinte X/Y m, hauteur m,
	#  poids des terrasses bas->haut (hauteurs INEGALES : une paroi dominante),
	#  retrait moyen par terrasse (fraction du rayon ; > 0 retrait -> corniche,
	#  < 0 avancee -> surplomb), fruit par terrasse en deg (>= TALUS_MIN_LEAN_DEG :
	#  talus d'eboulis en pente au pied), sommets de contour (min, max),
	#  coupes de fracture, rainures, blocs eboules, seed)
	("cliff_block_01", (5.8, 3.2), 4.2, (0.50, 0.30, 0.20), (0.0, 0.12, 0.08), (14.0, 6.0, 4.0),
		(12, 14), 2, 3, 4, 2101),
	("cliff_block_02", (7.6, 4.2), 5.8, (0.24, 0.50, 0.26), (0.0, 0.12, 0.10), (28.0, 5.0, 6.0),
		(12, 15), 3, 4, 5, 2102),
	("cliff_block_03", (9.0, 5.0), 7.6, (0.18, 0.46, 0.22, 0.14), (0.0, 0.12, 0.10, 0.06),
		(30.0, 4.0, 7.0, 4.0), (12, 16), 3, 5, 5, 2103),
]
CLIFF_MAX_DIM_M = 10.0

MESA_SPECS = [
	("mesa_01", (34.0, 21.0), 16.0, (0.30, 0.50, 0.20), (0.0, 0.20, 0.10), (34.0, 5.0, 7.0),
		(16, 22), 2, 5, 5, 3101),
	("mesa_02", (48.0, 29.0), 21.0, (0.24, 0.44, 0.18, 0.14), (0.0, 0.18, 0.08, 0.07),
		(36.0, 4.0, 8.0, 5.0), (18, 24), 3, 6, 6, 3102),
]
MESA_MAX_DIM_M = 58.0

# Dalle sommitale ("dessus plat avec levre") : epaisseur relative a la
# hauteur totale et surplomb relatif au rayon moyen de la terrasse du dessous.
CAP_HEIGHT_FRACTION = 0.07
CAP_LIP_FRACTION = 0.08
# Une terrasse dont le fruit atteint cet angle est un talus d'eboulis : la
# paroi de la terrasse suivante descend alors jusqu'au sol, a l'interieur du
# talus (le talus l'habille au lieu de la porter en surplomb).
TALUS_MIN_LEAN_DEG = 20.0
# Coupe de fracture : jamais plus de cette part du rayon de la base retiree.
FRACTURE_MAX_BITE = 0.26

# ART-98 (registre v4) : plafond de dimension par famille de `build_massif`,
# desormais un dictionnaire (au lieu du ternaire cliff/mesa d'origine) pour
# accueillir "cliff_wall" (segments CliffN/S/W/E, jusqu'a 22 m de long) sans
# toucher aux plafonds "cliff"/"mesa" existants (registre v2/v3, inchange).
MASSIF_MAX_DIM_M = {"cliff": CLIFF_MAX_DIM_M, "mesa": MESA_MAX_DIM_M, "cliff_wall": 24.0}


def build_massif(name: str, footprint, height: float, tier_weights, tier_insets, tier_leans_deg,
		outline_range, n_fractures: int, n_grooves: int, n_blocks: int, seed: int, family: str) -> dict:
	"""Falaise ou mesa : terrasses a contour irregulier (chacune son contour,
	son retrait, son fruit, son decalage de centre - corniche large d'un
	cote, paroi d'aplomb de l'autre), tailladees par leurs propres coupes
	planes ; dalle sommitale en surplomb (dessus plat avec levre) ; coupes de
	fracture qui tranchent plusieurs terrasses d'un seul plan (grandes faces
	d'aplomb qui cassent la lecture en pile) ; rainures verticales en V pres
	des aretes ; blocs eboules au pied."""
	rng = random.Random(seed)
	rx, ry = footprint[0] / 2.0, footprint[1] / 2.0
	scale = max(footprint[0], footprint[1], height)
	embed = 0.02 * height
	cap_h = CAP_HEIGHT_FRACTION * height
	body_h = height - cap_h
	lobes = [(2, rng.uniform(0.05, 0.11), rng.uniform(0.0, math.tau)),
		(3, rng.uniform(0.04, 0.09), rng.uniform(0.0, math.tau)),
		(5, rng.uniform(0.02, 0.05), rng.uniform(0.0, math.tau))]

	bm = bmesh.new()
	tiers = []           # (contour_bas, centre, z0, z1, fruit_deg) de chaque terrasse
	outline_counts = []
	offsets_m = []
	tier_cuts = 0
	total_w = sum(tier_weights)
	z = 0.0
	cum_inset = 0.0
	center = (0.0, 0.0)
	prev_top_mean_r = None
	prev_is_talus = False
	for i, (w, inset, lean_deg) in enumerate(zip(tier_weights, tier_insets, tier_leans_deg)):
		h = body_h * w / total_w
		n = rng.randint(outline_range[0], outline_range[1])
		cum_inset += inset
		if i > 0 and inset != 0.0:
			# Decalage du centre vers un cote : corniche large a l'oppose,
			# paroi quasi d'aplomb (ou surplomb) de ce cote.
			phi = rng.uniform(0.0, math.tau)
			shift = abs(inset) * rng.uniform(0.5, 0.95)
			center = (center[0] + math.cos(phi) * shift * rx, center[1] + math.sin(phi) * shift * ry)
		raw = irregular_outline(rng, n, rx * (1.0 - cum_inset), ry * (1.0 - cum_inset), lobes)
		outline = [(x + center[0], y + center[1]) for x, y in raw]
		c = _polygon_centroid(outline)
		mean_r = _mean_radius(outline, c)
		if prev_top_mean_r is not None:
			offsets_m.append(round(prev_top_mean_r - mean_r, 4))
		top = _scaled_outline(outline, c, max(0.5, 1.0 - math.tan(math.radians(lean_deg)) * h / mean_r))
		z0 = -0.1 if (i == 0 or prev_is_talus) else z - embed
		z1 = z + h
		tier = prism_solid(outline, z0, top, z1)
		# Coupes planes quasi verticales pres des deux coins les plus saillants.
		corners = sorted(range(n), key=lambda k: -math.hypot(outline[k][0] - c[0], outline[k][1] - c[1]))
		for k in corners[:2]:
			theta = math.atan2(outline[k][1] - c[1], outline[k][0] - c[0]) + rng.uniform(-0.2, 0.2)
			nrm = Vector((math.cos(theta), math.sin(theta), rng.uniform(-0.18, 0.30))).normalized()
			r_here = math.hypot(outline[k][0] - c[0], outline[k][1] - c[1])
			co = Vector((c[0], c[1], (z0 + z1) / 2.0)) + Vector((math.cos(theta), math.sin(theta), 0.0)) * (
				r_here * (1.0 - rng.uniform(0.05, 0.11)))
			if plane_cut(tier, co, nrm):
				tier_cuts += 1
		_append_bmesh(bm, tier)
		tier.free()
		tiers.append((outline, c, z0, z1, lean_deg))
		outline_counts.append(n)
		prev_top_mean_r = _mean_radius(top, c)
		prev_is_talus = lean_deg >= TALUS_MIN_LEAN_DEG
		z = z1

	# Dalle sommitale en surplomb : dessus plat avec levre.
	last_outline, last_c = tiers[-1][0], tiers[-1][1]
	n_cap = rng.randint(outline_range[0], outline_range[1])
	cap_r_factor = (prev_top_mean_r * (1.0 + CAP_LIP_FRACTION)) / _mean_radius(last_outline, last_c)
	cap_raw = irregular_outline(rng, n_cap, rx * (1.0 - cum_inset) * cap_r_factor,
		ry * (1.0 - cum_inset) * cap_r_factor, lobes)
	cap_outline = [(x + last_c[0], y + last_c[1]) for x, y in cap_raw]
	cap = prism_solid(cap_outline, z - embed, cap_outline, height)
	_append_bmesh(bm, cap)
	cap.free()
	outline_counts.append(n_cap)
	lip_m = round(_mean_radius(cap_outline, _polygon_centroid(cap_outline)) - prev_top_mean_r, 4)
	offsets_m.append(-lip_m)
	bm = union_all(bm)

	# Coupes de fracture : un plan quasi vertical (penche de 2-7 deg en
	# arriere) tranche d'un coup les terrasses d'un cote jusqu'au rayon de la
	# plus rentree (borne a FRACTURE_MAX_BITE du rayon de la base).
	base_outline, base_c = tiers[0][0], tiers[0][1]
	fractures = 0
	az = rng.uniform(0.0, math.tau)
	for k in range(n_fractures):
		if k:
			az += rng.uniform(0.28, 0.55) * math.tau
		radii = [r for r in (_ray_radius(t[0], base_c, az) for t in tiers) if r > 0.0]
		dist = max(min(radii) * 0.96, max(radii) * (1.0 - FRACTURE_MAX_BITE))
		tilt = math.tan(math.radians(rng.uniform(2.0, 7.0)))
		nrm = Vector((math.cos(az), math.sin(az), tilt)).normalized()
		co = Vector((base_c[0] + math.cos(az) * dist, base_c[1] + math.sin(az) * dist, 0.5 * height))
		if plane_cut(bm, co, nrm):
			fractures += 1

	# Rainures verticales en V, posees sur la paroi reelle (rayon tire vers
	# l'axe), dans les terrasses d'aplomb (jamais dans un talus).
	mean_r0 = _mean_radius(base_outline, base_c)
	reach = 2.0 * scale
	wall_tiers = [t for t in tiers if t[4] < TALUS_MIN_LEAN_DEG]
	grooves = bmesh.new()
	n_groove_done = 0
	az = rng.uniform(0.0, math.tau)
	for g in range(n_grooves):
		az += math.tau / n_grooves * rng.uniform(0.7, 1.3)
		_outline, _c, t_z0, t_z1, _lean = wall_tiers[rng.randrange(len(wall_tiers))]
		probe = _probe_wall(bm, base_c, az, 0.5 * (max(0.0, t_z0) + t_z1), reach)
		if probe is None:
			continue
		point, outward = probe
		z_top = t_z1 + rng.uniform(0.0, 0.6) * (t_z1 - t_z0)
		cutter = _groove_cutter_at(point, outward, width=rng.uniform(0.12, 0.18) * mean_r0,
			depth=rng.uniform(0.09, 0.14) * mean_r0, z0=t_z0 - 0.2, z1=min(z_top, height + 1.0))
		_append_bmesh(grooves, cutter)
		cutter.free()
		n_groove_done += 1
	if n_groove_done:
		bm = subtract(bm, grooves)
	else:
		grooves.free()

	# Blocs eboules au pied, a moitie enfouis dans la paroi reelle.
	n_block_done = 0
	az = rng.uniform(0.0, math.tau)
	for _ in range(n_blocks):
		az += math.tau / n_blocks * rng.uniform(0.6, 1.4)
		size = rng.uniform(0.10, 0.16) * height if family in ("cliff", "cliff_wall") else rng.uniform(0.11, 0.18) * height
		dims = (size, size * rng.uniform(0.65, 0.9), size * rng.uniform(0.5, 0.75))
		probe = _probe_wall(bm, base_c, az, 0.3 * dims[2], reach)
		if probe is None:
			continue
		point, outward = probe
		pos = (point.x + outward.x * 0.12 * size, point.y + outward.y * 0.12 * size)
		block = _place_block(rng, dims, pos, sink=0.08 * dims[2])
		_append_bmesh(bm, block)
		block.free()
		n_block_done += 1
	bm = union_all(bm)
	_ground_cut(bm)
	_cleanup(bm, BOOLEAN_WELD_M)

	lo, hi = _bbox(bm)
	max_dim = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
	limit = MASSIF_MAX_DIM_M[family]
	if max_dim > limit:
		bmesh.ops.scale(bm, vec=(limit / max_dim,) * 3, verts=list(bm.verts))
	lo, hi = _bbox(bm)
	bmesh.ops.translate(bm, vec=(-(lo.x + hi.x) / 2.0, -(lo.y + hi.y) / 2.0, -lo.z), verts=list(bm.verts))
	_assert_closed(bm, name)

	stats = {
		"terrace_count": len(tier_weights),
		"outline_vertex_counts": outline_counts,
		"outline_aspect": round(_principal_aspect(base_outline), 4),
		"terrace_offsets_m": offsets_m,
		"tier_plane_cuts": tier_cuts,
		"fracture_plane_cuts": fractures,
		"groove_count": n_groove_done,
		"fallen_block_count": n_block_done,
		"top_lip_overhang_m": lip_m,
	}
	return {"bm": bm, "bevel": BEVEL_WIDTH_M[family], "stats": stats}


# ART-98 (docs/art/WASTELAND_V4_ART_PLAN.md SS4 "Canyon, falaises et fond" -
# segments CliffN/S/W/E). Meme plage que ROCK_BEVEL_RANGE_M/SPIRE_BEVEL_RANGE_M
# (2-4 cm) - constante LOCALE au registre v4, jamais ajoutee a BEVEL_WIDTH_M
# (contrat verrouille par test_make_stylized_rocks.py, voir sa doc).
_CLIFF_WALL_BEVEL_M = 0.05


def build_wall_segment(name: str, length_m: float, height_m: float, depth_m: float, seed: int,
		main_cuts: int = 11, detail_cuts: int = 4) -> dict:
	"""Segment de paroi (CliffN/S/W/E, v4) : coupes planes sur un icosaedre
	etire (`cut_rock_solid`, MEME technique robuste que `build_rock`/
	`build_spire` - jamais `build_massif`, voir ci-dessous), mis a l'echelle
	EXACTE (`_fit_to_dims`, empreinte (length_m, 2*depth_m, height_m)) puis
	une coupe NETTE au plan y=0 en repere LOCAL (`plane_cut` scelle TOUJOURS
	le plan de coupe par UNE facette plane, `holes_fill` - voir sa doc) : le
	cote garde (y<=0, "hors-jeu", R1 "relief libre") garde le relief organique
	des coupes ; la face y=0 ("cote jeu") est donc EXACTEMENT plane PAR
	CONSTRUCTION (0 cm d'ecart, jamais mesuree a posteriori) - le critere
	d'acceptation ART-98 "faces cote jeu a +/- 10 cm" est ainsi garanti dans
	tous les cas, quel que soit le tirage aleatoire des coupes.
	`build_massif` (terrasses + dalle sommitale a decalage de centre) a ete
	essaye en premier ici, puis ABANDONNE : sur une empreinte tres allongee
	(ex. CliffN/S, 22 x 4-4,8 m), une combinaison de graine a produit un
	polygone source auto-intersecte (`v4_cliff_s_00`, 0,62 m2 - voir le rendu
	de tache ART-98) - `cut_rock_solid` (coupes planes sur un solide fini,
	jamais de contours 2D bruites empiles en terrasses) n'a jamais ce defaut,
	deja eprouve sur les 8 aiguilles (empreintes elles aussi tres allongees,
	ex. RocherGueW 1,5 x 4,5 m) et les 6 rochers du registre v2/v3."""
	rng = random.Random(seed)
	half = (length_m * 0.56, depth_m * 1.05, height_m * 0.56)
	bm, done_main, done_detail = cut_rock_solid(rng, half, main_cuts, detail_cuts, subdivisions=1)
	_fit_to_dims(bm, (length_m, depth_m * 2.0, height_m))
	if not plane_cut(bm, (0.0, 0.0, 0.0), (0.0, 1.0, 0.0)):
		raise RuntimeError(f"make_stylized_rocks: {name} - la coupe flush cote jeu n'a rien retire "
			f"(empreinte (length={length_m}, depth={depth_m}) trop etroite face au plan y=0 ?)")
	_cleanup(bm, BOOLEAN_WELD_M)
	_assert_closed(bm, name)
	lo, hi = _bbox(bm)
	stats = {
		"icosphere_subdivisions": 1,
		"main_plane_cuts": done_main,
		"detail_plane_cuts": done_detail,
		"large_facet_area_ratio": round(_large_facet_area_ratio(bm), 4),
		"game_face_flush": True,
		"game_face_deviation_m": 0.0,
		"wall_length_m": round(hi.x - lo.x, 3),
		"wall_depth_m": round(-lo.y, 3),
		"wall_height_m": round(hi.z - lo.z, 3),
		"bevel_width_m": _CLIFF_WALL_BEVEL_M,
	}
	return {"bm": bm, "bevel": _CLIFF_WALL_BEVEL_M, "stats": stats}


# ---------------------------------------------------------------------------
# Paroi de canyon raccordable : profil a terrasses fixe (identique aux deux
# bouts) extrude le long de X, face taillee loin des bouts.
# ---------------------------------------------------------------------------

CANYON_LENGTH_M = 16.0       # axe X, longueur d'un module (8 tuiles de texture de 2 m : raccord de strates exact)
CANYON_END_MARGIN_M = 1.4    # aucune taille a moins de cette distance des bouts : raccord intact
# Profil (y, z), y < 0 = cote canyon (face visible), y > 0 = plateau (arriere).
# 3 terrasses + dalle sommitale en surplomb (levre), base enfouie a z=-0.1
# (la coupe au sol z=0 donne la base plate, identiquement aux deux bouts).
CANYON_PROFILE = [
	(3.2, -0.1),     # arriere, bas
	(3.2, 12.0),     # arriere, plateau
	(-1.05, 12.0),   # plateau -> bord de la levre
	(-1.05, 11.2),   # epaisseur de la levre
	(-0.62, 11.2),   # dessous du surplomb -> paroi de la 3e terrasse
	(-0.85, 8.6),    # 3e terrasse (fruit)
	(-2.0, 8.6),     # corniche 2
	(-2.35, 4.4),    # 2e terrasse
	(-3.55, 4.4),    # corniche 1
	(-3.95, -0.1),   # 1re terrasse (pied de paroi)
]
CANYON_WALL_SEGMENTS = [((-3.95, -0.1), (-3.55, 4.4)), ((-2.35, 4.4), (-2.0, 8.6)), ((-0.85, 8.6), (-0.62, 11.2))]
CANYON_TERRACES = 3
CANYON_SEED = 4101
# Contreforts : (x0, x1, y_avant, y_arriere, z0, z1, volumes). Le dos
# (y_arriere) reste DERRIERE la paroi a toute hauteur du contrefort (jamais
# une fente entre contrefort et paroi) ; 2 volumes = socle large + fut
# etroit recule vers la paroi.
CANYON_BUTTRESS_SEED = 4102
CANYON_BUTTRESSES = [
	(1.8, 5.0, -5.1, -0.5, -0.1, 9.8, 2),
	(8.2, 11.6, -3.0, -0.3, 3.9, 11.6, 2),
	(12.3, 14.2, -4.7, -1.9, -0.1, 5.8, 1),
]
BUTTRESS_MIN_CORNER_TURN_DEG = 52.0
BUTTRESS_OUTLINE_TRIES = 400
BUTTRESS_EMBED_M = 0.25


def extrude_profile(profile: list, length: float) -> "bmesh.types.BMesh":
	bm = bmesh.new()
	v0 = [bm.verts.new((0.0, y, z)) for (y, z) in profile]
	v1 = [bm.verts.new((length, y, z)) for (y, z) in profile]
	n = len(profile)
	for i in range(n):
		j = (i + 1) % n
		bm.faces.new((v0[i], v0[j], v1[j], v1[i]))
	bm.faces.new(list(reversed(v0)))
	bm.faces.new(v1)
	bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
	return bm


def _face_y_at(z: float) -> float:
	"""Position (y) de la paroi du profil canonique a la hauteur z."""
	for (ya, za), (yb, zb) in CANYON_WALL_SEGMENTS:
		if za <= z <= zb:
			return ya + (yb - ya) * (z - za) / (zb - za)
	return CANYON_PROFILE[2][0]


def _check_interior(bm: "bmesh.types.BMesh", what: str) -> None:
	lo, hi = _bbox(bm)
	if lo.x < CANYON_END_MARGIN_M or hi.x > CANYON_LENGTH_M - CANYON_END_MARGIN_M:
		raise RuntimeError(f"make_stylized_rocks: {what} deborde vers un bout de la paroi "
			f"(x {lo.x:.2f}..{hi.x:.2f}, marge {CANYON_END_MARGIN_M} m) - raccord compromis")


def _ledge_chamfer(x0: float, x1: float, y_edge: float, z_ledge: float, skew: float) -> "bmesh.types.BMesh":
	"""Prisme triangulaire le long de X qui tranche en biais l'arete d'une
	corniche (un plan a ~58 deg), bouts obliques (le sommet interieur est
	rentre de `skew`) : le chanfrein s'amorce et meurt en pointe."""
	tri_yz = [(y_edge - 0.8, z_ledge + 1.0), (y_edge - 0.8, z_ledge - 1.9), (y_edge + 1.0, z_ledge + 1.0)]
	bm = bmesh.new()
	v0 = [bm.verts.new((x0 + (skew if k == 2 else 0.0), y, z)) for k, (y, z) in enumerate(tri_yz)]
	v1 = [bm.verts.new((x1 - (skew if k == 2 else 0.0), y, z)) for k, (y, z) in enumerate(tri_yz)]
	for i in range(3):
		j = (i + 1) % 3
		bm.faces.new((v0[i], v0[j], v1[j], v1[i]))
	bm.faces.new(list(reversed(v0)))
	bm.faces.new(v1)
	bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
	return bm


# Contreforts : jamais une colonne quasi cylindrique (retour du verificateur
# TOOL-02B sur canyon_edge_01, view_04). Mesure sur la section horizontale de
# chaque volume de contrefort, a SECTION_FRACTIONS de sa hauteur hors sol :
# sommets quasi alignes (virage < SECTION_COLLINEAR_DEG) fusionnes en une
# seule facette, puis part du virage total portee par des aretes franches et
# part du pourtour visible (devant la paroi) couverte par la plus grande
# facette. Arete franche = virage >= SECTION_SHARP_TURN_DEG : le seuil
# d'encrage des plis de la planche de controle (turntable.py, Freestyle
# crease_angle 134 deg, soit un virage de 46 deg). Un polygone quasi regulier
# de 10-14 cotes (virages de 26-36 deg) n'a AUCUNE arete encree : il se lit
# comme un cylindre lisse, exactement le defaut releve sur view_04.
SECTION_FRACTIONS = (0.3, 0.55, 0.8)
SECTION_COLLINEAR_DEG = 10.0
SECTION_SHARP_TURN_DEG = 46.0


def horizontal_section(bm: "bmesh.types.BMesh", z: float) -> list:
	"""Contour ferme (x, y) de la section du solide `bm` par le plan horizontal
	`z` (la boucle la plus longue), dans l'ordre de parcours. Chaque point de
	section est identifie par l'ARETE coupee (meme point vu des deux faces
	voisines) ; une face non convexe coupee en 4 points est appariee dans
	l'ordre le long de la droite d'intersection."""
	zs = [v.co.z for v in bm.verts]
	while any(abs(vz - z) < 1e-6 for vz in zs):
		z += 1e-4
	bm.edges.index_update()
	points = {}
	adjacency = {}
	for f in bm.faces:
		hits = []
		for e in f.edges:
			a, b = e.verts
			if (a.co.z - z) * (b.co.z - z) < 0.0:
				if e.index not in points:
					t = (z - a.co.z) / (b.co.z - a.co.z)
					points[e.index] = (a.co.x + (b.co.x - a.co.x) * t, a.co.y + (b.co.y - a.co.y) * t)
				hits.append(e.index)
		if len(hits) < 2:
			continue
		d = f.normal.cross(Vector((0.0, 0.0, 1.0)))
		hits.sort(key=lambda k: points[k][0] * d.x + points[k][1] * d.y)
		for k in range(0, len(hits) - 1, 2):
			adjacency.setdefault(hits[k], []).append(hits[k + 1])
			adjacency.setdefault(hits[k + 1], []).append(hits[k])
	best, best_len = [], 0.0
	seen = set()
	for start in adjacency:
		if start in seen:
			continue
		loop, prev, cur = [start], None, start
		seen.add(start)
		while True:
			nxt = [n for n in adjacency[cur] if n != prev and n not in seen]
			if not nxt:
				break
			prev, cur = cur, nxt[0]
			loop.append(cur)
			seen.add(cur)
		pts = [points[k] for k in loop]
		length = sum(math.dist(pts[i], pts[(i + 1) % len(pts)]) for i in range(len(pts)))
		if length > best_len:
			best, best_len = pts, length
	return best


def _turn_deg(a: tuple, b: tuple, c: tuple) -> float:
	"""Virage (deg, signe) au sommet `b` du chemin a -> b -> c."""
	ux, uy = b[0] - a[0], b[1] - a[1]
	vx, vy = c[0] - b[0], c[1] - b[1]
	return math.degrees(math.atan2(ux * vy - uy * vx, ux * vx + uy * vy))


def _merge_collinear(pts: list, min_turn_deg: float) -> list:
	"""Retire un a un le sommet au plus petit virage tant qu'il est sous
	`min_turn_deg` : chaque cote restant est une facette."""
	pts = list(pts)
	while len(pts) > 3:
		n = len(pts)
		turns = [abs(_turn_deg(pts[i - 1], pts[i], pts[(i + 1) % n])) for i in range(n)]
		k = min(range(n), key=turns.__getitem__)
		if turns[k] >= min_turn_deg:
			break
		del pts[k]
	return pts


def _front_length(a: tuple, b: tuple, wall_y: float) -> float:
	"""Longueur de la partie du segment a-b situee devant la paroi (y <
	`wall_y`, cote canyon)."""
	if a[1] >= wall_y and b[1] >= wall_y:
		return 0.0
	if a[1] < wall_y and b[1] < wall_y:
		return math.dist(a, b)
	inside, outside = (a, b) if a[1] < wall_y else (b, a)
	t = (wall_y - inside[1]) / (outside[1] - inside[1])
	return math.dist(inside, (inside[0] + (outside[0] - inside[0]) * t, wall_y))


def section_facet_metrics(pts: list, wall_y: float) -> dict:
	"""Mesures d'une section de contrefort (voir SECTION_*), sur sa seule
	partie VISIBLE (devant la paroi, y < `wall_y`) - les coins du dos, noyes
	dans la paroi, ne comptent pas : nombre de facettes, part du virage des
	coins visibles portee par des aretes franches, part du pourtour visible
	(segments rognes a la paroi) couverte par la plus grande facette."""
	simple = _merge_collinear(pts, SECTION_COLLINEAR_DEG)
	n = len(simple)
	turns = [abs(_turn_deg(simple[i - 1], simple[i], simple[(i + 1) % n]))
		for i in range(n) if simple[i][1] < wall_y]
	total = sum(turns)
	sharp = sum(t for t in turns if t >= SECTION_SHARP_TURN_DEG)
	visible = [length for length in (_front_length(simple[i], simple[(i + 1) % n], wall_y) for i in range(n))
		if length > 0.0]
	return {
		"facets": n,
		"sharp_turn_share": round(sharp / total, 4) if total else 0.0,
		"front_largest_face_share": round(max(visible) / sum(visible), 4) if visible else 0.0,
	}


def buttress_outline(rng: random.Random, x0: float, x1: float, y_front: float, y_back: float) -> list:
	"""Contour ANGULEUX d'un volume de contrefort, inscrit dans
	[x0, x1] x [y_front, y_back] (sens trigonometrique) : dos droit a
	`y_back` (noye dans la paroi, jamais vu), deux flancs quasi
	perpendiculaires a la paroi, puis une etrave basse et ASYMETRIQUE cote
	canyon (pointe decalee, flancs de longueurs differentes) - 3 coins
	visibles, 3 grandes facettes planes. Retire jusqu'a ce que CHAQUE coin
	visible soit convexe et tourne d'au moins BUTTRESS_MIN_CORNER_TURN_DEG
	(pli franc, encre sur la planche, marge sur SECTION_SHARP_TURN_DEG).
	Des coins poses sur une demi-ellipse ne le peuvent pas (les deux coins
	extremes s'y partagent 90 deg de virage : l'un reste sous 46 deg) : ils
	donnaient le polygone quasi regulier qui se lit comme un cylindre."""
	width, depth = x1 - x0, y_back - y_front
	for _ in range(BUTTRESS_OUTLINE_TRIES):
		pts = [
			(x1 - width * rng.uniform(0.0, 0.14), y_back),
			(x0 + width * rng.uniform(0.0, 0.14), y_back),
			(x0 + width * rng.uniform(0.0, 0.1), y_back - depth * rng.uniform(0.5, 0.88)),
			(x0 + width * rng.uniform(0.28, 0.72), y_front),
			(x1 - width * rng.uniform(0.0, 0.1), y_back - depth * rng.uniform(0.5, 0.88)),
		]
		m = len(pts)
		front_turns = [_turn_deg(pts[i - 1], pts[i], pts[(i + 1) % m]) for i in range(2, m)]
		if min(front_turns) >= BUTTRESS_MIN_CORNER_TURN_DEG:
			return pts
	raise RuntimeError(f"make_stylized_rocks: aucun contour de contrefort a coins francs en "
		f"{BUTTRESS_OUTLINE_TRIES} tirages (x {x0:.2f}..{x1:.2f})")


def faceted_buttress_volume(rng: random.Random, x0: float, x1: float, y_front: float, y_back: float,
		z0: float, z1: float, sloped_top: bool) -> tuple:
	"""Volume de contrefort : prisme a contour anguleux (`buttress_outline`)
	dont le haut rentre vers le dos (fruit de 7-14 % : faces avant
	legerement penchees, le dos reste noye dans la paroi) ; `sloped_top` :
	dessus tranche par une coupe plane en pente vers le canyon (16-30 deg,
	50-80 % de la profondeur) - pas un couvercle plat de colonne. Renvoie
	(bmesh, coupes planes)."""
	outline = buttress_outline(rng, x0, x1, y_front, y_back)
	top = _scaled_outline(outline, (0.5 * (x0 + x1), y_back), rng.uniform(0.86, 0.93))
	solid = prism_solid(outline, z0, top, z1)
	cuts = 0
	if sloped_top:
		tilt = math.radians(rng.uniform(16.0, 30.0))
		az = -0.5 * math.pi + rng.uniform(-0.7, 0.7)
		nrm = Vector((math.sin(tilt) * math.cos(az), math.sin(tilt) * math.sin(az), math.cos(tilt)))
		bite = rng.uniform(0.5, 0.8) * math.sin(tilt) * (y_back - y_front)
		if plane_cut(solid, nrm * (_support(solid, nrm) - bite), nrm):
			cuts += 1
	return solid, cuts


def measure_buttress_volume(solid: "bmesh.types.BMesh", buttress: int, volume: int) -> list:
	"""Sections du volume `solid` (avant union avec la paroi : sa partie
	visible, devant la paroi, n'est touchee par aucun autre volume a ces
	hauteurs) a SECTION_FRACTIONS de sa hauteur hors sol."""
	lo, hi = _bbox(solid)
	z_lo = max(0.0, lo.z)
	out = []
	for frac in SECTION_FRACTIONS:
		z = z_lo + frac * (hi.z - z_lo)
		pts = horizontal_section(solid, z)
		if len(pts) < 3:
			continue
		metrics = section_facet_metrics(pts, _face_y_at(z))
		out.append({"buttress": buttress, "volume": volume, "z": round(z, 3), **metrics})
	return out


def build_canyon_edge(name: str) -> dict:
	rng = random.Random(CANYON_SEED)
	L = CANYON_LENGTH_M
	bm = extrude_profile(CANYON_PROFILE, L)

	# Contreforts a facettes (unis) : assez profonds pour COMBLER les
	# corniches sur leur longueur (la paroi ne se lit plus comme un escalier
	# regulier d'un bout a l'autre), en saillie devant la paroi. Chacun est un
	# socle large, puis (s'il est haut) un fut plus etroit recule vers la
	# paroi (corniche sableuse entre les deux) ; chaque volume est un prisme a
	# contour ANGULEUX (`buttress_outline` : dos noye, etrave basse, coins
	# visibles francs) avec fruit, le plus haut tranche par un dessus en pente
	# vers le canyon. Tire a part (graine dediee) : le reste de la face
	# (alcoves, blocs) ne depend pas de ces tirages.
	b_rng = random.Random(CANYON_BUTTRESS_SEED)
	plane_cuts = 0
	sections = []
	volume_count = 0
	for bi, (x0, x1, y_front, y_back, z0, z1, n_volumes) in enumerate(CANYON_BUTTRESSES):
		volumes = [(x0, x1, y_front, y_back, z0, z1, n_volumes == 1)]
		if n_volumes == 2:
			z_split = z0 + (z1 - z0) * b_rng.uniform(0.5, 0.6)
			fw = b_rng.uniform(0.62, 0.76)
			shift = b_rng.uniform(-1.0, 1.0) * 0.5 * (1.0 - fw) * (x1 - x0)
			ux0 = 0.5 * (x0 + x1) + shift - 0.5 * fw * (x1 - x0)
			ux1 = ux0 + fw * (x1 - x0)
			uy_front = y_front + b_rng.uniform(0.2, 0.3) * (y_back - y_front)
			volumes = [(x0, x1, y_front, y_back, z0, z_split, False),
				(ux0, ux1, uy_front, y_back, z_split - BUTTRESS_EMBED_M, z1, True)]
		for vi, (vx0, vx1, vy_front, vy_back, vz0, vz1, sloped_top) in enumerate(volumes):
			solid, cuts = faceted_buttress_volume(b_rng, vx0, vx1, vy_front, vy_back, vz0, vz1, sloped_top)
			plane_cuts += cuts
			_check_interior(solid, "contrefort")
			sections.extend(measure_buttress_volume(solid, bi, vi))
			_append_bmesh(bm, solid)
			solid.free()
			volume_count += 1
	bm = union_all(bm)

	# Taille de la face : alcoves a facettes sur deux terrasses, rainures en V,
	# chanfreins de corniche - toujours loin des bouts ; outils fusionnes puis
	# soustraits.
	cutters = bmesh.new()
	for (xc, yc, zc, dims) in [(6.8, -3.1, 4.2, (2.4, 2.6, 7.4)), (12.6, -1.4, 8.7, (2.0, 2.2, 4.4))]:
		bay, bay_main, bay_detail = cut_rock_solid(rng, (dims[0] * 0.6, dims[1] * 0.6, dims[2] * 0.6), 7, 2,
			subdivisions=1)
		_fit_to_dims(bay, dims)
		bmesh.ops.translate(bay, vec=(xc, yc, zc - dims[2] / 2.0), verts=list(bay.verts))
		_check_interior(bay, "alcove")
		_append_bmesh(cutters, bay)
		bay.free()
		plane_cuts += bay_main + bay_detail
	for (xc, z0, z1, width, depth) in [(5.5, -0.3, 4.9, 0.6, 0.55), (10.6, 4.2, 9.2, 0.5, 0.45),
			(7.9, 8.4, 12.3, 0.5, 0.45)]:
		y_face = _face_y_at(0.5 * (max(0.0, z0) + z1))
		groove = _groove_cutter_at(Vector((xc, y_face, 0.0)), Vector((0.0, -1.0, 0.0)), width, depth, z0, z1)
		_check_interior(groove, "rainure")
		_append_bmesh(cutters, groove)
		groove.free()
		plane_cuts += 2
	for (x0, x1, z_ledge, y_edge) in [(5.2, 8.4, 4.4, -3.55), (11.8, 14.0, 8.6, -2.0)]:
		chamfer = _ledge_chamfer(x0, x1, y_edge, z_ledge, skew=0.9)
		_check_interior(chamfer, "chanfrein de corniche")
		_append_bmesh(cutters, chamfer)
		chamfer.free()
		plane_cuts += 1
	bm = subtract(bm, cutters)

	# Blocs eboules au pied de la paroi, hors des bouts.
	n_blocks = 0
	for (xc, size) in [(5.6, 1.1), (7.6, 0.8), (9.8, 1.4), (11.9, 0.9)]:
		dims = (size, size * rng.uniform(0.7, 0.9), size * rng.uniform(0.55, 0.75))
		block = _place_block(rng, dims, (xc, _face_y_at(0.3) - 0.25 * size), sink=0.08 * dims[2])
		_check_interior(block, "bloc eboule")
		_append_bmesh(bm, block)
		block.free()
		n_blocks += 1
	bm = union_all(bm)
	_ground_cut(bm)
	_cleanup(bm, BOOLEAN_WELD_M)
	_assert_closed(bm, name)
	stats = {
		"length_m": L,
		"terrace_count": CANYON_TERRACES,
		"face_plane_cuts": plane_cuts,
		"buttress_count": len(CANYON_BUTTRESSES),
		"buttress_volume_count": volume_count,
		"buttress_sections": sections,
		"fallen_block_count": n_blocks,
	}
	return {"bm": bm, "bevel": BEVEL_WIDTH_M["canyon_edge"], "stats": stats}


# ---------------------------------------------------------------------------
# Matiere : slots strates / sable, peinture par paint_bake.py, mesures
# ---------------------------------------------------------------------------

def painter_world_uv_scale() -> float:
	"""Echelle de la projection en boite de paint_bake.py (tuiles par metre),
	lue dans le module lui-meme : si TOOL-01B la change, la generation
	echoue au lieu de livrer des strates a une autre echelle que 2 m."""
	import paint_bake  # noqa: E402 - meme dossier (sys.path pose plus haut)
	scale = float(paint_bake.WORLD_UV_SCALE)
	if abs(scale * STRATA_TILE_M - 1.0) > 1e-9:
		raise RuntimeError(f"make_stylized_rocks: paint_bake.WORLD_UV_SCALE = {scale} tuile/m, "
			f"contrat TOOL-02B = 1 tuile / {STRATA_TILE_M} m")
	return scale


def _is_top(normal) -> bool:
	"""Dessus : normale montante dont Z domine X et Y - exactement les faces
	que la projection en boite echantillonnerait par le haut. Toute autre
	face montante ou verticale est projetee par un cote (v = z / 2 m)."""
	return normal.z > 0.0 and normal.z >= max(abs(normal.x), abs(normal.y))


def _is_underside(normal) -> bool:
	return normal.z < 0.0 and -normal.z >= max(abs(normal.x), abs(normal.y))


def _sand_material():
	"""Materiau du slot des dessus : Base Color <- image du sable peint
	(reprise telle quelle par paint_bake.py, mode "existing")."""
	mat = bpy.data.materials.new(SAND_SLOT)
	nt = mat.node_tree
	bsdf = nt.nodes.get("Principled BSDF")
	tex = nt.nodes.new("ShaderNodeTexImage")
	tex.image = bpy.data.images.load(SAND_TEXTURE_PATH, check_existing=True)
	nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
	return mat


def assign_material_slots(obj) -> dict:
	"""Slot 0 `STRATA_SLOT` (strates, toute face non-dessus), slot 1
	`SAND_SLOT` (dessus, image du sable clair). Pose aussi une UV en boite a
	l'echelle du monde (1 tuile = STRATA_TILE_M, meme projection que
	paint_bake) : l'exporteur glTF n'embarque l'image du sable qu'avec une UV,
	et le .glb brut reste lisible tel quel. Renvoie les mesures de controle :
	part de l'aire des strates projetee par un cote (1.0 = strates
	horizontales partout hors dessous de surplomb), aire des dessus, aire des
	dessous."""
	me = obj.data
	me.materials.clear()
	me.materials.append(bpy.data.materials.new(STRATA_SLOT))
	me.materials.append(_sand_material())
	uv = me.uv_layers.new(name="UVMap")
	strata_area = strata_side_area = underside_area = top_area = 0.0
	for poly in me.polygons:
		n = poly.normal
		top = _is_top(n)
		side_x = abs(n.x) >= abs(n.y)
		for li in poly.loop_indices:
			co = me.vertices[me.loops[li].vertex_index].co
			if top or _is_underside(n):
				u, v = co.x, co.y
			elif side_x:
				u, v = co.y, co.z
			else:
				u, v = co.x, co.z
			uv.data[li].uv = (u / STRATA_TILE_M, v / STRATA_TILE_M)
		if top:
			poly.material_index = 1
			top_area += poly.area
			continue
		poly.material_index = 0
		if _is_underside(n):
			underside_area += poly.area
			continue
		strata_area += poly.area
		if max(abs(n.x), abs(n.y)) >= abs(n.z):
			strata_side_area += poly.area
	return {
		"strata_side_projected_ratio": round(strata_side_area / strata_area, 6) if strata_area else 0.0,
		"sand_top_area_m2": round(top_area, 4),
		"underside_area_m2": round(underside_area, 4),
	}


def run_paint_bake(in_path: str, out_path: str, res: int) -> str:
	"""tools/blender/paint_bake.py en sous-process (CLI publique). Renvoie sa
	ligne PAINT_BAKE_OK (luminance calibree ou non)."""
	cmd = [bpy.app.binary_path, "-b", "--factory-startup", "--python-exit-code", "1",
		"-P", PAINT_BAKE_SCRIPT, "--", "--in", in_path, "--out", out_path,
		"--res", str(res), "--skip-turntable"]
	proc = subprocess.run(cmd, capture_output=True, text=True, timeout=PAINT_BAKE_TIMEOUT_S)
	ok_line = next((ln for ln in proc.stdout.splitlines() if ln.startswith("PAINT_BAKE_OK")), None)
	if proc.returncode != 0 or ok_line is None or not os.path.isfile(out_path):
		raise RuntimeError(f"make_stylized_rocks: paint_bake.py a echoue pour {in_path} (code {proc.returncode})\n"
			f"--- stdout ---\n{proc.stdout[-4000:]}\n--- stderr ---\n{proc.stderr[-4000:]}")
	return ok_line


def _albedo_image_of(mat):
	"""Image branchee sur la Base Color d'un materiau importe (sortie de
	paint_bake.py : Principled <- Image Texture)."""
	if mat is None or mat.node_tree is None:
		return None
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	if bsdf is None or not bsdf.inputs["Base Color"].is_linked:
		return None
	src = bsdf.inputs["Base Color"].links[0].from_node
	return src.image if src.type == 'TEX_IMAGE' else None


def _image_srgb_pixels(image) -> "np.ndarray":
	w, h = image.size
	buf = np.empty(w * h * 4, dtype=np.float32)
	image.pixels.foreach_get(buf)
	return buf.reshape(-1, 4)[:, :3]


def _luma(rgb: "np.ndarray") -> "np.ndarray":
	return 0.2126 * rgb[:, 0] + 0.7152 * rgb[:, 1] + 0.0722 * rgb[:, 2]


def _hue_deg_and_chroma(rgb: "np.ndarray") -> tuple:
	mx = rgb.max(axis=1)
	mn = rgb.min(axis=1)
	chroma = mx - mn
	safe = np.where(chroma > 1e-6, chroma, 1.0)
	r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
	hue = np.where(mx == r, ((g - b) / safe) % 6.0, np.where(mx == g, (b - r) / safe + 2.0, (r - g) / safe + 4.0))
	return hue * 60.0, chroma


def albedo_stats(image, source_mean_luma: float) -> dict:
	"""Mesures de la texture cuite (texels couverts = non noirs) : luminance
	moyenne vs la texture de strates source, ecart-type (texture visible, pas
	un aplat), teinte mediane, part de pixels dans les bandes reservees."""
	rgb = _image_srgb_pixels(image)
	covered = rgb[_luma(rgb) > 0.02]
	luma = _luma(covered)
	hue, chroma = _hue_deg_and_chroma(covered)
	saturated = chroma > RESERVED_HUE_CHROMA_THRESHOLD
	reserved = np.zeros(len(covered), dtype=bool)
	for lo, hi in RESERVED_HUE_BANDS_DEG:
		reserved |= saturated & (hue >= lo) & (hue <= hi)
	return {
		"albedo_coverage": round(float(len(covered)) / float(len(rgb)), 4),
		"albedo_mean_luma": round(float(luma.mean()), 4),
		"albedo_luma_std": round(float(luma.std()), 4),
		"albedo_median_hue_deg": round(float(np.median(hue[saturated])) if saturated.any() else 0.0, 2),
		"albedo_reserved_hue_fraction": round(float(reserved.mean()), 6),
		"strata_source_mean_luma": round(source_mean_luma, 4),
	}


def canyon_seam_delta(obj, length: float) -> float:
	"""Ecart max (m) entre la boucle de sommets du bout x=0 et celle du bout
	x=`length` translatee de -`length` (dans les deux sens : chaque sommet
	d'un bout doit avoir son jumeau sur l'autre). Mesure sur la geometrie
	FINALE (le .glb peint relu)."""
	mw = obj.matrix_world
	pts = [mw @ v.co for v in obj.data.vertices]
	end0 = [Vector((0.0, p.y, p.z)) for p in pts if abs(p.x) < 1e-4]
	end1 = [Vector((0.0, p.y, p.z)) for p in pts if abs(p.x - length) < 1e-4]
	if not end0 or not end1:
		return float("inf")

	def one_way(src: list, dst: list) -> float:
		kd = KDTree(len(dst))
		for i, p in enumerate(dst):
			kd.insert(p, i)
		kd.balance()
		return max(kd.find(p)[2] for p in src)

	return max(one_way(end0, end1), one_way(end1, end0))


def _quad_is_convex(a: Vector, x: Vector, b: Vector, y: Vector) -> bool:
	"""Le quadrilatere plan a-x-b-y (diagonale actuelle a-b) est-il convexe,
	c.-a-d. la diagonale x-y passe-t-elle a l'interieur ? Vrai si les
	segments a-b et x-y se coupent (projection sur le plan du quad)."""
	n = (x - a).cross(b - a) + (b - a).cross(y - a)
	if n.length < 1e-12:
		return False
	n.normalize()
	u = (b - a).normalized()
	w = n.cross(u)

	def p2(v: Vector) -> tuple:
		d = v - a
		return (d.dot(u), d.dot(w))

	def side(o, p, q) -> float:
		return (p[0] - o[0]) * (q[1] - o[1]) - (p[1] - o[1]) * (q[0] - o[0])

	A, X, B, Y = p2(a), p2(x), p2(b), p2(y)
	return side(A, B, X) * side(A, B, Y) < 0.0 and side(X, Y, A) * side(X, Y, B) < 0.0


def triangulate_manifold(obj) -> int:
	"""Triangule le maillage final (ce que ferait l'export glTF) puis repare
	les aretes partagees par plus de 2 triangles. Deux n-gones qui ont deux
	sommets NON adjacents en commun peuvent etre triangules par la MEME
	diagonale : l'arete creee porte alors 4 triangles (constate apres la
	refonte des facettes coplanaires et apres le biseau - check_asset
	voyait 1-2 aretes non-manifold sur le .glb). La diagonale est alors
	basculee dans l'un des deux n-gones (quadrilatere convexe, meme plan).
	Renvoie (diagonales basculees, micro-replis tolere) ; RuntimeError si un
	triangle de plus de MICRO_FOLD_MAX_M2 sort replie (polygone source
	auto-intersecte) ou si une arete reste non-manifold."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	# Le biseau, quand il se bride (facettes etroites), laisse des aretes de
	# longueur nulle : soudees ici a la tolerance de check_asset (0,1 mm).
	bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-4)
	bmesh.ops.dissolve_degenerate(bm, dist=1e-4, edges=list(bm.edges))
	poly_id = bm.faces.layers.int.new("__poly_id")
	planar_normals = {}
	for f in bm.faces:
		f[poly_id] = f.index
		# Seuls les polygones PLANS servent de reference : un coin de biseau
		# (n-gone gauche) donne legitimement des triangles d'orientations
		# differentes ; un triangle retourne dans un polygone plan, lui, trahit
		# un contour qui se recoupe.
		center = f.calc_center_median()
		if max(abs(f.normal.dot(v.co - center)) for v in f.verts) < 1e-4:
			planar_normals[f.index] = f.normal.copy()
	bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method='BEAUTY', ngon_method='BEAUTY')
	folded = [f.calc_area() for f in bm.faces
		if f[poly_id] in planar_normals and f.calc_area() > 1e-10
		and f.normal.dot(planar_normals[f[poly_id]]) < 0.0]
	large = [a for a in folded if a > MICRO_FOLD_MAX_M2]
	if large:
		bm.free()
		raise RuntimeError(f"make_stylized_rocks: {obj.name} a {len(large)} triangle(s) replie(s) "
			f"(jusqu'a {max(large):.4f} m2 : polygone source auto-intersecte)")
	flipped = 0
	for _round in range(8):
		bad = [e for e in bm.edges if len(e.link_faces) > 2]
		if not bad:
			break
		for e in bad:
			if not e.is_valid or len(e.link_faces) <= 2:
				continue
			a, b = e.verts
			groups = {}
			for f in e.link_faces:
				groups.setdefault(f[poly_id], []).append(f)
			for pair in groups.values():
				if len(pair) != 2:
					continue
				t1, t2 = pair
				x = next(v for v in t1.verts if v not in (a, b))
				y = next(v for v in t2.verts if v not in (a, b))
				if x is y or bm.edges.get((x, y)) is not None:
					continue
				if not _quad_is_convex(a.co, x.co, b.co, y.co):
					continue
				pid, mat = t1[poly_id], t1.material_index
				bmesh.ops.delete(bm, geom=[t1, t2], context='FACES_ONLY')
				for tri in ((a, x, y), (x, b, y)):
					f = bm.faces.new(tri)
					f[poly_id] = pid
					f.material_index = mat
				flipped += 1
				break
	bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
	remaining = sum(1 for e in bm.edges if len(e.link_faces) > 2)
	bm.faces.layers.int.remove(poly_id)
	bm.to_mesh(me)
	bm.free()
	me.update()
	if remaining:
		raise RuntimeError(f"make_stylized_rocks: {obj.name} garde {remaining} arete(s) a plus de 2 faces apres triangulation")
	return flipped, len(folded)


def _object_from_bm(name: str, bm: "bmesh.types.BMesh"):
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	obj = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(obj)
	return obj


def _painter_slots(sidecar: dict) -> list:
	"""Slots cuits rapportes par paint_bake.py (materiau d'origine, texture de
	base, luminances) - objet unique."""
	objects = sidecar.get("objects") or []
	return [
		{k: s.get(k) for k in ("original_material", "kind", "base_mode", "base_texture",
			"target_luma", "baked_luma", "luma_ok")}
		for s in (objects[0].get("slots", []) if objects else [])
	]


def produce_piece(name: str, category: str, build_fn, out_dir: str, work_dir: str, source_mean_luma: float) -> dict:
	# -- 1. geometrie + slots strates/sable ----------------------------------
	toonkit.reset_scene()
	built = build_fn()
	obj = _object_from_bm(name, built["bm"])
	if built["bevel"] > 0.0:
		toonkit.add_bevel(obj, width=built["bevel"], segments=1, angle_limit_deg=30.0)
	stats = dict(built["stats"])
	stats["flipped_diagonals"], stats["micro_folds"] = triangulate_manifold(obj)
	toonkit.weighted_normals(obj)
	stats.update(assign_material_slots(obj))
	raw_path = os.path.join(work_dir, f"{name}_raw.glb")
	toonkit.export_glb(raw_path, obj, write_report=False)

	# -- 2. paint_bake.py : strates projetees en boite + AO/aretes/encre -----
	res = BAKE_RES[category]
	out_path = os.path.join(out_dir, f"{name}.glb")
	ok_line = run_paint_bake(raw_path, out_path, res)
	sidecar_path = os.path.splitext(out_path)[0] + ".json"
	with open(sidecar_path, "r", encoding="utf-8") as f:
		painter_sidecar = json.load(f)

	# -- 3. .glb peint : normale lissee du contour, mesures -------------------
	# paint_bake reimporte le .glb brut sans ses attributs personnalises : la
	# normale lissee `_smooth_normal` (coque d'encre continue aux aretes
	# vives, assets/shaders/ink_outline.gdshader, CUSTOM0) est reposee ici sur
	# le maillage peint, apres ressoudure des sommets eclates par glTF (les UV
	# restent portees par les coins : la texture cuite ne bouge pas).
	toonkit.reset_scene()
	bpy.ops.import_scene.gltf(filepath=out_path)
	meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
	if len(meshes) != 1:
		raise RuntimeError(f"make_stylized_rocks: {out_path} contient {len(meshes)} objet(s) mesh (1 attendu)")
	obj = meshes[0]
	image = _albedo_image_of(obj.data.materials[0] if obj.data.materials else None)
	if image is None:
		raise RuntimeError(f"make_stylized_rocks: aucune texture cuite dans {out_path}")
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
	bm.to_mesh(obj.data)
	bm.free()
	toonkit.weighted_normals(obj)
	toonkit.smooth_normal_attrs(obj)
	stats.update(albedo_stats(image, source_mean_luma))
	if category == "canyon_edge":
		stats["seam_max_delta_m"] = round(canyon_seam_delta(obj, CANYON_LENGTH_M), 8)
	tris = toonkit.tri_count(obj)
	dims = tuple(round(v, 4) for v in obj.dimensions)
	top_z = max((obj.matrix_world @ v.co).z for v in obj.data.vertices)
	stats["flat_top_area_m2"] = round(sum(p.area for p in obj.data.polygons
		if p.normal.z > 0.999 and p.center.z > top_z - 0.01), 4)
	toonkit.export_glb(out_path, obj, write_report=True)

	with open(sidecar_path, "r", encoding="utf-8") as f:
		sidecar = json.load(f)
	painter_slots = _painter_slots(painter_sidecar)
	sidecar.update({
		"painted": bool(painter_sidecar.get("painted")),
		# Rapport complet de paint_bake.py (slots, luminances, iles), tel quel.
		"paint_bake": painter_sidecar,
		"generator": "tools/blender/make_stylized_rocks.py",
		"source": os.path.basename(raw_path),
		"material": f"{name}_painted",
		"strata_texture": os.path.relpath(STRATA_TEXTURE_PATH, REPO_ROOT).replace("\\", "/"),
		"strata_tile_m": STRATA_TILE_M,
		"strata_slot": STRATA_SLOT,
		"sand_slot": SAND_SLOT,
		"sand_texture": os.path.relpath(SAND_TEXTURE_PATH, REPO_ROOT).replace("\\", "/"),
		"stats": stats,
	})
	with open(sidecar_path, "w", encoding="utf-8") as f:
		json.dump(sidecar, f, indent=2, ensure_ascii=False)

	check = check_asset.run(out_path, budget_tris=BUDGET_TRIS[category], asset_class=None)
	check_asset.print_text(check)
	obj_check = check["objects"][0] if check.get("objects") else {}

	info = {
		"name": name, "category": category, "path": out_path, "tris": tris, "dims_m": dims,
		"budget_tris": BUDGET_TRIS[category],
		"materials": obj_check.get("material_names", []),
		"uv_present": bool(obj_check.get("uv_present", False)),
		"closed": bool(obj_check.get("closed", False)),
		"smooth_normal": bool(sidecar.get("smooth_normal", False)),
		"res": res, "painter": ok_line, "painter_slots": painter_slots,
		"check_asset_ok": check["ok"], "check_asset_failures": check["failures"],
	}
	info.update(stats)
	print(f"STYLIZED_ROCKS_PIECE_OK {name} tris={tris} dims={dims} -> {out_path}")
	return info


# ---------------------------------------------------------------------------
# Registre des 12 pieces + construction/verification globale + self-test JSON
# ---------------------------------------------------------------------------

def _register_pieces() -> dict:
	pieces = {}
	for (spec_name, dims, main_cuts, detail_cuts, bevel, seed) in ROCK_SPECS:
		pieces[spec_name] = ("rock", functools.partial(build_rock, spec_name, dims, main_cuts, detail_cuts, bevel, seed))
	for spec in CLIFF_SPECS:
		pieces[spec[0]] = ("cliff", functools.partial(build_massif, *spec, family="cliff"))
	for spec in MESA_SPECS:
		pieces[spec[0]] = ("mesa", functools.partial(build_massif, *spec, family="mesa"))
	pieces["canyon_edge_01"] = ("canyon_edge", functools.partial(build_canyon_edge, "canyon_edge_01"))
	return pieces


PIECES = _register_pieces()
EXPECTED_CATEGORY_COUNTS = {"rock": 6, "cliff": 3, "mesa": 2, "canyon_edge": 1}


# ===========================================================================
# ART-98 (registre v4, docs/art/WASTELAND_V4_ART_PLAN.md SS2/SS4) - SEPARE du
# registre v2/v3 ci-dessus (PIECES/build_all/EXPECTED_CATEGORY_COUNTS) : le
# contrat de tache ART-98 ne possede QUE assets/models/props/wasteland/
# rocks/v4_* et ne doit jamais changer le comportement/les 12 pieces du
# registre existant, verrouille par tools/blender/tests/test_make_stylized_
# rocks.py (hors de mon perimetre de fichiers). Sortie : v4_manifest.json
# (jamais manifest.json), meme dossier (assets/models/props/wasteland/rocks/).
# ===========================================================================

# Aiguilles (docs/research/11_wasteland_v4_layout.md SS9, wasteland.gd
# `_box("RocherXxxW", x0,x1,z0,z1,y0,y1, "rock")`, cotes GODOT/monde (x, y=
# hauteur, z) converties ici en dims BLENDER (x, y=profondeur, z=hauteur) -
# meme convention que `assign_material_slots`/l'export gltf (Z-up Blender ->
# Y-up glTF/Godot). Est = ouest en BOITE (meme taille, position miroir dans
# `_mirror_piece`) mais JAMAIS en geometrie (graine propre par piece, "pas de
# copie miroir", SS2) : 8 graines uniques.
V4_ROCHER_SPECS = [
	# (nom, dims blender (x,y=profondeur,z=hauteur), coupes principales, ecornures, biseau m, seed)
	("v4_rocher_s1w", (4.0, 4.5, 3.8), 9, 4, 0.032, 9101),
	("v4_rocher_n1w", (3.0, 4.5, 3.8), 9, 4, 0.030, 9102),
	("v4_rocher_s2w", (3.0, 4.5, 3.8), 9, 4, 0.030, 9103),
	("v4_rocher_guew", (1.5, 4.5, 3.8), 8, 3, 0.026, 9104),
	("v4_rocher_s1e", (4.0, 4.5, 3.8), 9, 4, 0.032, 9105),
	("v4_rocher_n1e", (3.0, 4.5, 3.8), 9, 4, 0.030, 9106),
	("v4_rocher_s2e", (3.0, 4.5, 3.8), 9, 4, 0.030, 9107),
	("v4_rocher_guee", (1.5, 4.5, 3.8), 8, 3, 0.026, 9108),
]


def _v4_wall_segment_specs(prefix: str, total_length_m: float, segment_count: int, height_m: float,
		depth_m: float, seed_base: int) -> list:
	"""`segment_count` segments EGAUX qui couvrent exactement `total_length_m`
	(docs/art/WASTELAND_V4_ART_PLAN.md SS2 "CliffW et CliffE ... decoupees en
	segments de 8 m" - division EXACTE plutot qu'un pas fixe de 8 m avec un
	reste, pour qu'aucun segment ne soit une piece partielle)."""
	seg_len = total_length_m / segment_count
	return [(f"{prefix}_{i:02d}", seg_len, height_m, depth_m, seed_base + i) for i in range(segment_count)]


# CliffW/CliffE (wasteland.gd : x -45..-44 / 44..45, z -25..20, y -2..6 -
# 45 m de long, 8 m de haut) : 6 segments de 7,5 m (45 / 6, division exacte -
# voir _v4_wall_segment_specs). CliffN/CliffS (x -44..44, 88 m de long, y
# 0..6 / -2..4, 6 m de haut) : 4 segments de 22 m (88 / 4) - CliffN "n'est
# visible que sur les cours de spawn, l'Impasse et le Passage" (SS2) : moins
# de segments qu'un pas de 8 m littéral (11) suffit largement, CliffS suit la
# meme convention par coherence (paroi sud du canyon, meme traitement "flush
# cote jeu + relief libre cote hors-jeu").
V4_WALL_W_SPECS = _v4_wall_segment_specs("v4_cliff_w", 45.0, 6, 8.0, 2.2, 9201)
V4_WALL_E_SPECS = _v4_wall_segment_specs("v4_cliff_e", 45.0, 6, 8.0, 2.2, 9211)
V4_WALL_N_SPECS = _v4_wall_segment_specs("v4_cliff_n", 88.0, 4, 6.0, 2.0, 9221)
V4_WALL_S_SPECS = _v4_wall_segment_specs("v4_cliff_s", 88.0, 4, 6.0, 2.4, 9231)

# Horizon (SS4 "mesa_01/02 regenerees aux strates x2, entre 60 et 150 m") :
# "x2" est obtenu par une echelle Godot x2 sur l'instance (ArtRocksBackdrop.gd,
# jamais ici - STRATA_TILE_M reste le SEUL reglage de tuilage du pipeline,
# partage avec paint_bake.py, voir painter_world_uv_scale) - ces deux pieces
# sont donc construites a leur taille normale (sous MASSIF_MAX_DIM_M["mesa"] =
# 58 m), puis doublees de taille au moment de la pose : un texel de la
# texture de strates couvre alors 4 m au sol au lieu de 2, lisible a la
# distance du placement (60-150 m).
V4_MESA_SPECS = [
	# (nom, empreinte X/Y m, hauteur m, poids terrasses, retraits, fruits deg, sommets(min,max), fractures, rainures, blocs, seed)
	("v4_mesa_01", (36.0, 22.0), 17.0, (0.30, 0.50, 0.20), (0.0, 0.20, 0.10), (34.0, 5.0, 7.0), (16, 22), 2, 5, 5, 8101),
	("v4_mesa_02", (50.0, 30.0), 22.0, (0.24, 0.44, 0.18, 0.14), (0.0, 0.18, 0.08, 0.07), (36.0, 4.0, 8.0, 5.0), (18, 24), 3, 6, 6, 8102),
]


def _register_v4_pieces() -> dict:
	pieces = {}
	for (spec_name, dims, main_cuts, detail_cuts, bevel, seed) in V4_ROCHER_SPECS:
		pieces[spec_name] = ("spire", functools.partial(build_spire, spec_name, dims, main_cuts, detail_cuts, bevel, seed))
	for (spec_name, length_m, height_m, depth_m, seed) in (V4_WALL_W_SPECS + V4_WALL_E_SPECS + V4_WALL_N_SPECS + V4_WALL_S_SPECS):
		pieces[spec_name] = ("cliff_wall", functools.partial(build_wall_segment, spec_name, length_m, height_m, depth_m, seed))
	for spec in V4_MESA_SPECS:
		pieces[spec[0]] = ("mesa", functools.partial(build_massif, *spec, family="mesa"))
	return pieces


V4_PIECES = _register_v4_pieces()
V4_EXPECTED_CATEGORY_COUNTS = {
	"spire": len(V4_ROCHER_SPECS),
	"cliff_wall": len(V4_WALL_W_SPECS) + len(V4_WALL_E_SPECS) + len(V4_WALL_N_SPECS) + len(V4_WALL_S_SPECS),
	"mesa": len(V4_MESA_SPECS),
}


def build_all_v4(only: str = None, out_dir: str = OUT_DIR, keep_work: bool = False) -> dict:
	"""Meme pipeline que `build_all` (geometrie -> paint_bake -> mesures ->
	check_asset) pour `V4_PIECES` - voir l'en-tete de section pour pourquoi ce
	registre/cette sortie (`v4_manifest.json`) restent separes de
	`build_all`/`PIECES`/`manifest.json`."""
	os.makedirs(out_dir, exist_ok=True)
	names = [only] if only else list(V4_PIECES.keys())
	for n in names:
		if n not in V4_PIECES:
			raise ValueError(f"piece v4 inconnue {n!r} (attendu une de {sorted(V4_PIECES)})")
	if not os.path.isfile(STRATA_TEXTURE_PATH):
		raise FileNotFoundError(f"texture de strates introuvable : {STRATA_TEXTURE_PATH}")

	work_dir = tempfile.mkdtemp(prefix="stylized_rocks_v4_work_")
	source_luma = _source_mean_luma()
	report = {
		"pieces": [], "piece_count": len(names), "ok": True, "failures": [],
		"budgets_tris": {k: BUDGET_TRIS[k] for k in ("spire", "cliff_wall", "mesa")},
		"strata_texture": os.path.relpath(STRATA_TEXTURE_PATH, REPO_ROOT).replace("\\", "/"),
		"strata_tile_m": STRATA_TILE_M,
		"mesa_godot_scale_for_strata_x2": 2.0,
	}
	try:
		for spec_name in names:
			category, build_fn = V4_PIECES[spec_name]
			info = produce_piece(spec_name, category, build_fn, out_dir, work_dir, source_luma)
			report["pieces"].append(info)
			if not info["check_asset_ok"]:
				report["ok"] = False
				report["failures"].append(f"{spec_name}: check_asset ECHEC - {info['check_asset_failures']}")
	finally:
		if keep_work:
			print(f"STYLIZED_ROCKS_V4_WORK_DIR {work_dir}")
		else:
			shutil.rmtree(work_dir, ignore_errors=True)

	if only is None and len(names) < len(V4_PIECES):
		report["ok"] = False
		report["failures"].append(f"seulement {len(names)} piece(s) v4 - {len(V4_PIECES)} attendues")

	counts = {}
	for p in report["pieces"]:
		counts[p["category"]] = counts.get(p["category"], 0) + 1
	report["category_counts"] = counts
	if only is None and counts != V4_EXPECTED_CATEGORY_COUNTS:
		report["ok"] = False
		report["failures"].append(f"repartition v4 par categorie inattendue: {counts} (attendu {V4_EXPECTED_CATEGORY_COUNTS})")

	manifest_path = os.path.join(out_dir, "v4_manifest.json")
	with open(manifest_path, "w", encoding="utf-8") as f:
		json.dump(report, f, indent=2, ensure_ascii=False)
	print(f"STYLIZED_ROCKS_V4_MANIFEST_OK {len(names)} piece(s) -> {manifest_path}")
	return report


def _source_mean_luma() -> float:
	img = bpy.data.images.load(STRATA_TEXTURE_PATH, check_existing=True)
	value = float(_luma(_image_srgb_pixels(img)).mean())
	bpy.data.images.remove(img)
	return value


def build_all(only: str = None, out_dir: str = OUT_DIR, keep_work: bool = False) -> dict:
	os.makedirs(out_dir, exist_ok=True)
	names = [only] if only else list(PIECES.keys())
	for n in names:
		if n not in PIECES:
			raise ValueError(f"piece inconnue {n!r} (attendu une de {sorted(PIECES)})")
	if not os.path.isfile(STRATA_TEXTURE_PATH):
		raise FileNotFoundError(f"texture de strates introuvable : {STRATA_TEXTURE_PATH}")

	work_dir = tempfile.mkdtemp(prefix="stylized_rocks_work_")
	source_luma = _source_mean_luma()
	report = {
		"pieces": [], "piece_count": len(names), "ok": True, "failures": [],
		# Contrat TOOL-02/TOOL-02B verrouille par tools/blender/tests/
		# test_make_stylized_rocks.py::test_budgets_match_contract_notes (hors
		# de mon perimetre) : EXACTEMENT les 4 categories historiques, jamais
		# les categories v4 (ART-98, "spire"/"cliff_wall") meme si elles ont
		# rejoint le dictionnaire global BUDGET_TRIS pour que `produce_piece`
		# (partage avec build_all_v4) les y trouve - filtrage explicite ici,
		# jamais un `dict(BUDGET_TRIS)` qui suivrait silencieusement tout ajout
		# futur au dictionnaire global.
		"budgets_tris": {k: BUDGET_TRIS[k] for k in EXPECTED_CATEGORY_COUNTS},
		"strata_texture": os.path.relpath(STRATA_TEXTURE_PATH, REPO_ROOT).replace("\\", "/"),
		"strata_tile_m": STRATA_TILE_M,
		"painter_world_uv_scale": painter_world_uv_scale(),
		"strata_slot": STRATA_SLOT,
		"sand_slot": SAND_SLOT,
		"sand_texture": os.path.relpath(SAND_TEXTURE_PATH, REPO_ROOT).replace("\\", "/"),
		"rock_bevel_range_m": list(ROCK_BEVEL_RANGE_M),
	}
	try:
		for spec_name in names:
			category, build_fn = PIECES[spec_name]
			info = produce_piece(spec_name, category, build_fn, out_dir, work_dir, source_luma)
			report["pieces"].append(info)
			if not info["check_asset_ok"]:
				report["ok"] = False
				report["failures"].append(f"{spec_name}: check_asset ECHEC - {info['check_asset_failures']}")
	finally:
		if keep_work:
			print(f"STYLIZED_ROCKS_WORK_DIR {work_dir}")
		else:
			shutil.rmtree(work_dir, ignore_errors=True)

	if only is None and len(names) < 12:
		report["ok"] = False
		report["failures"].append(f"seulement {len(names)} piece(s) - 12 attendues")

	counts = {}
	for p in report["pieces"]:
		counts[p["category"]] = counts.get(p["category"], 0) + 1
	report["category_counts"] = counts
	if only is None and counts != EXPECTED_CATEGORY_COUNTS:
		report["ok"] = False
		report["failures"].append(f"repartition par categorie inattendue: {counts} (attendu {EXPECTED_CATEGORY_COUNTS})")

	manifest_path = os.path.join(out_dir, "manifest.json")
	with open(manifest_path, "w", encoding="utf-8") as f:
		json.dump(report, f, indent=2, ensure_ascii=False)
	print(f"STYLIZED_ROCKS_MANIFEST_OK {len(names)} piece(s) -> {manifest_path}")
	return report


# ---------------------------------------------------------------------------
# Planche de controle : turntable.py (corrige par TOOL-01, affiche la texture
# cuite) par piece en sous-process, puis planche de synthese des 12 via sa
# fonction publique build_contact_sheet.
# ---------------------------------------------------------------------------

def render_piece_turntables(names: list, glb_dir: str, out_dir: str) -> None:
	for spec_name in names:
		glb_path = os.path.join(glb_dir, f"{spec_name}.glb")
		piece_out = os.path.join(out_dir, spec_name)
		os.makedirs(piece_out, exist_ok=True)
		cmd = [bpy.app.binary_path, "-b", "--factory-startup", "-P", TURNTABLE_SCRIPT, "--",
			"--in", glb_path, "--out", piece_out]
		proc = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
		ok = proc.returncode == 0 and "TURNTABLE_OK" in proc.stdout
		print(f"STYLIZED_ROCKS_TURNTABLE_{'OK' if ok else 'FAIL'} {spec_name} -> {piece_out}")
		if not ok:
			print(proc.stdout[-2000:])
			print(proc.stderr[-2000:])


def render_overview_board(out_dir: str) -> str:
	tiles = []
	for spec_name, (category, _build_fn) in PIECES.items():
		# Le gros plan (azimut fixe de turntable.py) montre bien les rochers,
		# falaises et mesas ; pour la paroi de canyon (forme LINEAIRE), il
		# tombe sur sa face arriere : on prend la vue orbitale a 225 deg
		# (view_05.png, trois-quarts avant), qui cadre sa face taillee.
		filename = "view_05.png" if category == "canyon_edge" else "closeup.png"
		tile_path = os.path.join(out_dir, spec_name, filename)
		if os.path.isfile(tile_path):
			tiles.append((spec_name, tile_path))
	if not tiles:
		print("STYLIZED_ROCKS_OVERVIEW_SKIP aucune vue disponible (turntables absents)")
		return None
	sheet_path = os.path.join(out_dir, "overview_12_pieces_contact_sheet.png")
	header = [
		"assets/models/props/wasteland/rocks/ - TOOL-02B",
		f"{len(tiles)} piece(s), strates peintes 1 tuile = {STRATA_TILE_M:g} m + paint_bake",
	]
	turntable.build_contact_sheet(sheet_path, tiles, 512, header)
	print(f"STYLIZED_ROCKS_OVERVIEW_OK {sheet_path}")
	return sheet_path


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	p = argparse.ArgumentParser()
	p.add_argument("--only", default=None, help="ne construire qu'une seule piece (iteration rapide)")
	p.add_argument("--out-dir", dest="out_dir", default=OUT_DIR,
		help="dossier de sortie des .glb/sidecars/manifest (defaut : assets/models/props/wasteland/rocks)")
	p.add_argument("--keep-work", dest="keep_work", action="store_true",
		help="garde le dossier temporaire (.glb brut et sortie paint_bake de chaque piece)")
	p.add_argument("--selftest-json", dest="selftest_json", default=None,
		help="ecrit aussi le rapport a ce chemin et imprime le marqueur STYLIZED_ROCKS_SELFTEST_RESULT "
			"(consomme par tools/blender/tests/test_make_stylized_rocks.py)")
	p.add_argument("--captures", dest="captures_dir", default=None,
		help="genere aussi la planche de controle (turntable par piece + planche des 12) dans ce dossier "
			"- construit d'abord les 12 pieces (ignore --only)")
	p.add_argument("--v4", dest="v4", action="store_true",
		help="construit le registre v4 (ART-98, V4_PIECES/v4_manifest.json) au lieu du registre v2/v3 "
			"existant (PIECES/manifest.json, INCHANGE que --v4 soit passe ou non) - --only/--captures/"
			"--selftest-json/--keep-work s'appliquent alors au registre v4")
	return p.parse_args(argv)


def main() -> None:
	args = parse_args()
	out_dir = os.path.abspath(args.out_dir)
	only = None if args.captures_dir else args.only
	if args.v4:
		report = build_all_v4(only=only, out_dir=out_dir, keep_work=args.keep_work)
		if args.selftest_json:
			out_path = os.path.abspath(args.selftest_json)
			os.makedirs(os.path.dirname(out_path), exist_ok=True)
			with open(out_path, "w", encoding="utf-8") as f:
				json.dump(report, f, indent=2, ensure_ascii=False)
			print(f"STYLIZED_ROCKS_V4_SELFTEST_RESULT {json.dumps(report, ensure_ascii=False)}")
		if args.captures_dir:
			captures_dir = os.path.abspath(args.captures_dir)
			os.makedirs(captures_dir, exist_ok=True)
			render_piece_turntables(list(V4_PIECES.keys()), out_dir, captures_dir)
		return
	report = build_all(only=only, out_dir=out_dir, keep_work=args.keep_work)
	if args.selftest_json:
		out_path = os.path.abspath(args.selftest_json)
		os.makedirs(os.path.dirname(out_path), exist_ok=True)
		with open(out_path, "w", encoding="utf-8") as f:
			json.dump(report, f, indent=2, ensure_ascii=False)
		print(f"STYLIZED_ROCKS_SELFTEST_RESULT {json.dumps(report, ensure_ascii=False)}")
	if args.captures_dir:
		captures_dir = os.path.abspath(args.captures_dir)
		os.makedirs(captures_dir, exist_ok=True)
		render_piece_turntables(list(PIECES.keys()), out_dir, captures_dir)
		render_overview_board(captures_dir)


if __name__ == "__main__":
	main()
