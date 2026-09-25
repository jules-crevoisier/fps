## tools/blender/paint_bake.py -- TOOL-01, v2 TOOL-01B
## Peinture automatique Blender : cuit une texture albedo "peinte a la main"
## (Cycles, bake EMIT) sur N'IMPORTE QUEL modele .glb/.gltf/.blend d'entree,
## sans peintre et sans Substance -- demande utilisateur du 2026-09-25
## (« cree-toi des outils en surcouche de Blender pour faire de la belle 3D
## et les textures toi-meme »). Ce script ne modifie JAMAIS le fichier
## source (import en memoire, comme turntable.py/check_asset.py/ai_restyle.py).
##
##   blender -b -P tools/blender/paint_bake.py -- --in X --out Y \
##       [--res 1024|2048] [--palette kind] [--margin-px 4] \
##       [--bake-margin-px 8] [--samples 16] [--seed 0] [--hue-max-deg 6] \
##       [--skip-turntable] [--views 8] [--size 512] [--turntable-out-dir D]
##
## v2 (TOOL-01B, verdict du lead du 2026-09-25 sur la v1 : « trop sombre et
## plat, mur de planches brun uniforme, fut rouge fonce uni, pas de lecture
## peint a la main ») -- trois causes mesurees, trois corrections :
##   - la v1 peignait la couleur PLATE de `toonkit.palette(kind)` (#735230
##     pour wood_planks : luminance 0,34 contre 0,44 pour la texture peinte
##     du meme kind) -> v2 : la base est TOUJOURS la texture peinte du kind,
##     projetee en boite a l'echelle du monde, et la luminance moyenne cuite
##     est recalee sur celle de cette texture (+/- `LUMA_TOLERANCE`) ;
##   - la v1 lisait aretes et creux dans `Pointiness`, qui vaut une constante
##     (0,696 mesure) sur un .glb importe : l'importeur glTF eclate les
##     sommets a chaque arete vive, donc aucun sommet n'est partage entre deux
##     faces d'angle different -> v2 : liseré au noeud Bevel (normale
##     arrondie vs normale de face), faces de chanfrein detectees sur un
##     maillage RESOUDE en memoire, convexite par une AO courte (5 cm : 1,0
##     sur une arete convexe, ~0,55 dans un angle rentrant, mesure) ;
##   - la v1 assombrissait les faces planes (AO a 0,35 m sans seuil) -> v2 :
##     seuls les vrais creux sont teintes (AO seuillee) ;
##   - la v1 cuisait un objet a plusieurs slots EN ENTIER avec le materiau du
##     premier (`materials.clear()` remet tous les polygones sur le slot 0,
##     sondage bpy 5.2) : porte, fut et toit des demos -> v2 : index de
##     materiau sauvegardes et restaures autour de l'echange de slots.
##
## Pipeline (par objet mesh de l'asset importe) :
##   1. UV            depliage automatique DEDIE a la cuisson, TOUJOURS
##                     (Smart UV Project, marge `--margin-px` px a la
##                     resolution `--res` -- `ensure_uv`) : une UV presente
##                     peut etre une projection MONDE/tuilee (ex.
##                     make_wl_shanty_kit.py, destinee a `Cartoon.prop_uv()`)
##                     ou plusieurs faces PARTAGENT la meme region UV (BUG
##                     CONSTATE v1, wall_1_level.glb : moitie du canevas
##                     noire). Toute UV d'origine est retiree apres l'unwrap.
##   2. analyse        sur une copie bmesh RESOUDEE (`_welded_bmesh`, les
##                     sommets eclates par glTF recolles a 0,1 mm) :
##                       - iles de MAILLAGE = planches/pieces
##                         (`compute_mesh_islands`) ;
##                       - faces de chanfrein (`compute_bevel_faces` : bande
##                         de moins de 2,5 cm bordee d'une arete convexe de
##                         15-75 deg, aucune arete concave).
##                     Les iles UV (`compute_uv_face_islands`) ne servent plus
##                     qu'au rapport (fragmentation de l'atlas).
##   3. attributs      couleurs de coin temporaires lues par le shader de
##                     cuisson : "island_hue" (teinte par planche, +/-
##                     `--hue-max-deg`), "island_value" (valeur par planche,
##                     +/- `DEFAULT_VALUE_MAX_FRAC`), "stroke_axis" (sens des
##                     coups de pinceau = axe long de la planche), "bevel_face"
##                     (1 sur un chanfrein). TOUS les attributs de couleur
##                     (les notres et tout AO/Curvature preexistant) sont
##                     retires APRES la cuisson (etape 6) : un COLOR_0 glTF
##                     est TOUJOURS multiplie dans le baseColor par tout
##                     consommateur conforme (BUG CONSTATE v1, oil_drum.glb).
##   4. shader cuit     un materiau PAR SLOT d'origine (`_build_bake_material`) :
##                        a. base = texture peinte projetee en BOITE, en
##                           coordonnees objet METRIQUES a `WORLD_UV_SCALE`
##                           (1 repetition / 2 m, meme echelle que l'UV monde
##                           du kit, contrat ART-73) : texture d'image deja
##                           posee sur le slot, sinon celle du kind
##                           (`resolve_base_texture` : assets/textures/painted/
##                           material_<kind>_albedo.png ou assets/textures/
##                           wasteland/*), sinon (accent, kind inconnu) le
##                           DETAIL d'une texture peinte recolore a
##                           `toonkit.palette(kind)` -- jamais une couleur unie ;
##                        b. teinte et valeur par planche (attributs) ;
##                        c. coups de pinceau (bruit etire le long de la
##                           planche, +/- `STROKE_STRENGTH`) + grain fin ;
##                        d. degrade vertical leger + dessus plus clair
##                           (+6 %, bible §6.2) ;
##                        e. gain de luminance du slot (etape 5) ;
##                        f. creux (AO seuillee) assombris ET teintes vers
##                           `palette("shadow_tint")` -- faces ouvertes
##                           intactes ;
##                        g. liseré d'eclat net (~1-2 cm) sur les aretes
##                           convexes : bande Bevel + faces de chanfrein,
##                           filtrees par l'AO courte (jamais un angle
##                           rentrant) ;
##                        h. trait d'encre fin (Bevel de 6 mm) sur ces memes
##                           aretes.
##                     Emission -> Material Output (cible de bake EMIT).
##   5. cuisson         UNE image par objet, un appel `bake(type='EMIT')` par
##                     passe. Calibration d'abord a `CALIBRATION_RES` : la
##                     luminance sRGB moyenne cuite de chaque slot (texels
##                     de ses triangles, `_uv_slot_masks`) est comparee a
##                     celle de sa texture source et le gain du slot corrige
##                     (`linear_gain_step`) jusqu'a +/- `LUMA_CONVERGE` ; puis
##                     cuisson finale a `--res`, garde de teinte reservee
##                     (`guard_reserved_hues`) et mesure finale rapportee.
##   6. materiau final  UN SEUL materiau par objet, nomme "<id>_painted" (ou
##                     "<id>_painted_N" au-dela du premier objet -- convention
##                     de ViewModel.gd/ThirdPersonWeapon.gd, `name.contains(
##                     "_painted")` -> `Cartoon.painted_texture_prop()`),
##                     Base Color = la texture cuite.
##   7. export          toonkit.export_glb (.glb + rapport JSON), puis sidecar
##                     augmente (`augment_sidecar` : "painted", "source",
##                     "res", objets/slots avec luminances cible/cuite).
##   8. turntables      avant (fichier source) / apres (sortie peinte),
##                     tools/blender/turntable.py en sous-process
##                     (`run_turntable`) -- sauf `--skip-turntable`
##                     (iteration rapide, jamais pour une livraison).
##
## Luminance : `srgb_luma` = luma Rec.709 sur les valeurs ENCODEES sRGB
## (0,2126 R' + 0,7152 G' + 0,0722 B'), la meme mesure pour la texture source
## et pour la texture cuite.
##
## Ce fichier importe bpy/bmesh dans un bloc try/except (comme
## ai_import_painted.py/fit_weapon_painted.py) : les fonctions PURES (section
## suivante) ne dependent d'AUCUN etat Blender et sont testables par un
## simple `python -m pytest`, sans lancer Blender -- voir
## tools/blender/tests/test_paint_bake.py.
from __future__ import annotations

import argparse
import colorsys
import hashlib
import json
import math
import os
import re
import subprocess
import sys

import numpy as np

try:
	import bpy
	import bmesh
except ImportError:  # pragma: no cover - permet de tester la logique pure hors Blender
	bpy = None
	bmesh = None

if bpy is not None:
	sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
	import toonkit  # noqa: E402

TURNTABLE_SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "turntable.py")
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PAINTED_TEX_DIR = os.path.join(REPO_ROOT, "assets", "textures", "painted")
WASTELAND_TEX_DIR = os.path.join(REPO_ROOT, "assets", "textures", "wasteland")

# ---------------------------------------------------------------------------
# Constantes. Seules --res/--margin-px/--bake-margin-px/--samples/--seed/
# --hue-max-deg sont exposees en CLI : les autres sont des choix de "look"
# verifies par turntable avant/apres (reports/paint_bake/) et par les cas v2
# de tools/blender/tests/test_paint_bake.py.
# ---------------------------------------------------------------------------
ALLOWED_RES = (1024, 2048)
DEFAULT_RES = 1024
DEFAULT_MARGIN_PX = 4              # marge d'ile UV (Smart UV Project), en pixels a --res
DEFAULT_BAKE_MARGIN_PX = 8         # dilatation de bake (evite les coutures visibles)
DEFAULT_SAMPLES = 16               # echantillons Cycles de la cuisson (moyennent AO/Bevel)
DEFAULT_SEED = 0
DEFAULT_HUE_MAX_DEG = 6.0          # variation de teinte par planche, +/- degres
DEFAULT_VALUE_MAX_FRAC = 0.05      # variation de valeur par planche, +/- fraction

# Base : projection boite a l'echelle du monde.
WORLD_UV_SCALE = 0.5               # 1 m = 0,5 tuile (make_wl_shanty_kit.py, contrat ART-73)
BOX_BLEND = 0.2                    # fondu entre les 3 projections de la boite
WELD_DIST_M = 1e-4                 # recollage des sommets eclates par glTF (analyse seulement)

# Luminance (critere TOOL-01B : +/- 10 % de la texture source).
LUMA_TOLERANCE = 0.10
LUMA_CONVERGE = 0.03               # cible de la calibration, marge sous la tolerance
MAX_CALIBRATION_PASSES = 4
CALIBRATION_RES = 256              # la moyenne d'un slot se mesure bien a basse resolution
CALIBRATION_MARGIN_PX = 2
MAX_FULL_RES_PASSES = 3            # corrections a pleine resolution (petits slots : la mesure a
                                   # CALIBRATION_RES peut s'ecarter de +15 %, porte de la demo)
GAIN_MIN = 0.25
GAIN_MAX = 4.0
SRGB_GAMMA_APPROX = 2.2            # gain lineaire ~ (rapport de luma sRGB) ** 2,2

# Coups de pinceau et grain (frequences en cycles par metre).
STROKE_LONG_FREQ = 1.6             # le long de la planche : traits de ~60 cm
STROKE_SHORT_FREQ = 14.0           # en travers : traits de ~7 cm de large
STROKE_MIN_ELONGATION = 1.25       # en dessous, piece "compacte" : traits horizontaux
STROKE_STRENGTH = 0.15             # +/- fraction de valeur (lineaire)
STROKE_NOISE_LOW = 0.38            # plage du bruit etalee sur +/- STROKE_STRENGTH : pente
STROKE_NOISE_HIGH = 0.62           # raide, paliers aux extremes = touches franches
GRAIN_FREQ = 55.0
GRAIN_STRENGTH = 0.025             # discret : un grain fort se lit comme du bruit (bible §7.2)

# Degrade vertical et dessus plus clair (bible §6.2 : dessus +6 % L).
GRAD_LOW = 0.95
GRAD_HIGH = 1.05
TOP_LIFT = 1.06
TOP_NORMAL_MIN = 0.55
TOP_NORMAL_MAX = 0.85

# Creux : AO seuillee (une face ouverte, AO >= CREVICE_AO_OPEN, n'est jamais touchee).
CREVICE_AO_DISTANCE_M = 0.2
CREVICE_AO_OPEN = 0.85
CREVICE_AO_CLOSED = 0.35
CREVICE_STRENGTH = 0.9
CREVICE_VALUE = 0.5                # facteur lineaire au fond d'un creux
SHADOW_TINT_MIX = 0.35             # part de la teinte d'ombre (normalisee en luminance)

# Aretes convexes : liseré d'eclat + encre fine.
EDGE_BEVEL_RADIUS_M = 0.03         # bande utile ~1,2 cm sur une arete vive a 90 deg (mesure)
EDGE_DOT_START = 0.985             # dot(normale Bevel, normale) : debut du liseré...
EDGE_DOT_FULL = 0.97               # ...liseré plein (transition courte = bord net)
EDGE_LIGHTEN_LIN = 1.5             # eclaircissement lineaire du liseré (~+20 % de luma sRGB)
EDGE_SUN_MIX = 0.12                # part de la couleur du soleil dans le liseré
# Soleil de Wasteland (bible §6.4, #FFD99A) : un liseré melange au blanc
# papier virait au ROSE sur les metaux rouges (rendu v2 intermediaire du fut) ;
# la lumiere chaude le garde dans la famille de teinte du support.
EDGE_SUN_SRGB = (1.0, 0.851, 0.604)
CONVEX_AO_DISTANCE_M = 0.05
CONVEX_AO_CONCAVE = 0.72           # AO courte d'un angle rentrant (~0,55 mesure)...
CONVEX_AO_OPEN = 0.9               # ...et d'une arete convexe (1,0 mesure)
BEVEL_FACE_MAX_W_M = 0.025         # largeur max d'une face de chanfrein (kit : ~2,1 cm)
BEVEL_TURN_MIN_DEG = 15.0
BEVEL_TURN_MAX_DEG = 75.0
INK_BEVEL_RADIUS_M = 0.006
INK_DOT_START = 0.985
INK_DOT_FULL = 0.955
INK_STRENGTH = 0.65                # jamais un noir plein : l'encre du jeu reste le post-process
NODE_SAMPLES = 8                   # echantillons des noeuds AO/Bevel (x DEFAULT_SAMPLES)

# Bandes de teinte reservees (docs/assets/ASSET_PLAN.md §3.4, dupliquees ici
# -- meme convention que ai_restyle.py::RESERVED_HUE_BANDS_DEG : ce fichier
# ne depend que de l'API PUBLIQUE de toonkit, jamais d'un script frere).
RESERVED_HUE_BANDS_DEG = ((300.0, 355.0), (105.0, 145.0))
RESERVED_HUE_CHROMA_THRESHOLD = 0.08
RESERVED_HUE_MARGIN_DEG = 2.0

# Alias de noms de slot -> kind canonique : COPIE de scripts/core/Cartoon.gd
# `_KIND_ALIASES` (verifiee par test_paint_bake.py::TestCanonicalKind, qui
# relit le GDScript) -- la cuisson doit choisir la meme texture que le jeu.
KIND_ALIASES = {
	"painted_metal": "painted_metal",
	"rust": "rust",
	"corrugated": "corrugated_metal",
	"corrugated_metal": "corrugated_metal",
	"container": "container_paint",
	"container_paint": "container_paint",
	"wood": "wood_planks",
	"wood_planks": "wood_planks",
	"sand": "sand_dirt",
	"sand_dirt": "sand_dirt",
	"concrete": "cracked_concrete",
	"cracked_concrete": "cracked_concrete",
	"asphalt": "asphalt",
	"ship_deck": "ship_deck",
	"rubber": "rubber_tire",
	"rubber_tire": "rubber_tire",
	"glass": "dirty_glass",
	"dirty_glass": "dirty_glass",
}
# Kind sans texture propre -> texture dont on garde le DETAIL peint, recolore
# a `palette(kind)`. "accent" suit Cartoon.painted_for_slot (painted_metal
# teinte) ; tout autre kind prend le socle neutre des conteneurs.
RECOLOR_DETAIL_KIND = {"accent": "painted_metal"}
DEFAULT_RECOLOR_DETAIL_KIND = "container_paint"

LUMA_WEIGHTS = (0.2126, 0.7152, 0.0722)


# ---------------------------------------------------------------------------
# Fonctions PURES (aucune dependance bpy) -- voir l'en-tete de fichier.
# ---------------------------------------------------------------------------

def uv_margin_fraction(margin_px: float, res: int) -> float:
	"""Marge d'ile UV (fraction de l'espace UV [0,1], ce qu'attend
	`bpy.ops.uv.smart_project(island_margin=...)`) pour obtenir `margin_px`
	pixels de marge reelle sur une texture `res` x `res`. Leve `ValueError`
	si `res` <= 0 (appel d'usage invalide, jamais un `ZeroDivisionError` brut)."""
	if res <= 0:
		raise ValueError(f"paint_bake: resolution invalide ({res})")
	return max(0.0, margin_px / float(res))


def resolve_kind(material_name: str, stored_kind, default_kind) -> str:
	"""Kind de palette pour un slot de materiau importe : priorite au
	`toonkit_kind` deja pose par `toonkit.toon_material` (`stored_kind`), puis
	au nom du materiau lui-meme (les kits peints du projet nomment DEJA leurs
	materiaux `wood_planks`/`corrugated_metal`/... par convention
	`Cartoon.painted_for_slot`), puis a `default_kind` (`--palette`), et enfin
	"flat" (jamais un `None`/crash). Le suffixe Blender de deduplication
	(".001", ...) est retire avant comparaison."""
	if stored_kind:
		return stored_kind
	if material_name and material_name != "__none__":
		return material_name.split(".")[0]
	return default_kind or "flat"


_PAINTED_SUFFIX_RE = re.compile(r"_painted(?:_\d+)?$")


def output_material_name(stem: str, index: int, count: int) -> str:
	"""Nom du materiau final -- "<id>_painted" (index 0) / "<id>_painted_N"
	(index >= 1 sur un asset a plusieurs objets mesh), convention reconnue
	cote jeu par `ViewModel.gd::_PAINTED_MATERIAL_MARKER` /
	`ThirdPersonWeapon.gd`. Un suffixe "_painted"/"_painted_N" deja present
	dans `stem` (le `--out` porte deja "_painted" par convention) est retire
	avant d'en ajouter un frais : jamais "<id>_painted_painted" (bogue
	constate v1 sur les 4 livrables)."""
	base = _PAINTED_SUFFIX_RE.sub("", stem)
	if count <= 1:
		return f"{base}_painted"
	return f"{base}_painted_{index}"


def _hash_unit(label: str) -> float:
	"""[0, 1] deterministe (32 premiers bits d'un SHA-256), jamais un `random`
	non seede : reproductible d'une execution a l'autre."""
	digest = hashlib.sha256(label.encode("utf-8")).hexdigest()
	return int(digest[:8], 16) / 0xFFFFFFFF


def island_hue_offset(seed, obj_name: str, island_index: int, max_deg: float = DEFAULT_HUE_MAX_DEG) -> float:
	"""Decalage de teinte deterministe (degres, dans [-max_deg, max_deg])
	pour une ile -- hash de `(seed, obj_name, island_index)`."""
	return (_hash_unit(f"{seed}:{obj_name}:{island_index}") * 2.0 - 1.0) * max_deg


def island_value_offset(seed, obj_name: str, island_index: int,
		max_frac: float = DEFAULT_VALUE_MAX_FRAC) -> float:
	"""Decalage de valeur deterministe (fraction, dans [-max_frac,
	max_frac]) pour une ile -- tirage INDEPENDANT de `island_hue_offset`
	(prefixe de hash distinct) : une planche plus chaude n'est pas
	systematiquement plus claire."""
	return (_hash_unit(f"value:{seed}:{obj_name}:{island_index}") * 2.0 - 1.0) * max_frac


def hue01_from_offset_deg(offset_deg: float) -> float:
	"""Decalage en degres -> valeur [0,1] de l'entree "Hue" d'un
	`ShaderNodeHueSaturation` (0,5 = aucun changement, 0..1 = -180..+180 deg)."""
	return max(0.0, min(1.0, 0.5 + offset_deg / 360.0))


def canonical_kind(kind: str) -> str:
	"""Kind canonique de la bibliotheque peinte (`KIND_ALIASES`), ou `kind`
	lui-meme s'il n'y figure pas (textures wasteland, kinds de palette)."""
	return KIND_ALIASES.get(kind, kind)


def resolve_base_texture(kind: str, painted_dir: str = PAINTED_TEX_DIR,
		wasteland_dir: str = WASTELAND_TEX_DIR) -> dict:
	"""Texture peinte qui sert de BASE a un slot de kind `kind` :
	`{"mode": "texture"|"recolor", "path": str, "kind": canonique}`.
	"texture" : la texture propre du kind (painted/material_<canonique>_
	albedo.png, puis wasteland/wl_<kind>_albedo.png, puis wasteland/<kind>_
	albedo.png -- avec ou sans prefixe "wl_"). "recolor" : pas de texture
	propre (accent, kind de palette) -> le DETAIL peint de
	`RECOLOR_DETAIL_KIND`, que l'appelant recolore a `palette(kind)`. Jamais
	une couleur unie : bibliotheque introuvable -> `RuntimeError`."""
	canonical = canonical_kind(kind)
	bare = kind[3:] if kind.startswith("wl_") else kind
	candidates = (
		os.path.join(painted_dir, f"material_{canonical}_albedo.png"),
		os.path.join(wasteland_dir, f"wl_{bare}_albedo.png"),
		os.path.join(wasteland_dir, f"{bare}_albedo.png"),
	)
	for path in candidates:
		if os.path.isfile(path):
			return {"mode": "texture", "path": path, "kind": canonical}
	detail = RECOLOR_DETAIL_KIND.get(canonical, DEFAULT_RECOLOR_DETAIL_KIND)
	path = os.path.join(painted_dir, f"material_{detail}_albedo.png")
	if os.path.isfile(path):
		return {"mode": "recolor", "path": path, "kind": canonical}
	raise RuntimeError(
		f"paint_bake: aucune texture peinte pour le kind {kind!r} ni de detail de repli "
		f"({path}) -- une base unie est interdite (TOOL-01B)")


def srgb_luma(rgb) -> float:
	"""Luma Rec.709 d'une couleur ENCODEE sRGB (0..1) -- la mesure de
	luminance de tout ce fichier (source et cuisson)."""
	return LUMA_WEIGHTS[0] * rgb[0] + LUMA_WEIGHTS[1] * rgb[1] + LUMA_WEIGHTS[2] * rgb[2]


def linear_gain_step(target_luma: float, measured_luma: float, gamma: float = SRGB_GAMMA_APPROX) -> float:
	"""Facteur LINEAIRE a appliquer au gain d'un slot pour amener sa luma
	sRGB cuite `measured_luma` vers `target_luma` (encodage sRGB ~ puissance
	1/2,2), borne a [GAIN_MIN, GAIN_MAX] (une mesure nulle -- slot noir -- ne
	divise jamais par zero)."""
	if measured_luma <= 0.0:
		return GAIN_MAX
	return max(GAIN_MIN, min(GAIN_MAX, (target_luma / measured_luma) ** gamma))


def luma_within_tolerance(measured_luma: float, target_luma: float, tol: float = LUMA_TOLERANCE) -> bool:
	"""True si `measured_luma` est a +/- `tol` (relatif) de `target_luma`."""
	return target_luma > 0.0 and abs(measured_luma / target_luma - 1.0) <= tol


def stroke_frequencies(extents) -> tuple:
	"""Frequences (cycles/m) du bruit de coups de pinceau sur X, Y, Z pour
	une piece d'etendue `extents` (m) : basse le long de l'axe long (traits
	etires le long de la planche), haute en travers. Une piece compacte
	(axe long < `STROKE_MIN_ELONGATION` x le suivant) garde des traits
	HORIZONTAUX, le long du plus grand de X/Y."""
	ext = [max(float(e), 0.0) for e in extents]
	order = sorted(range(3), key=lambda i: -ext[i])
	long_axis = order[0]
	if ext[order[1]] > 0.0 and ext[order[0]] / ext[order[1]] < STROKE_MIN_ELONGATION:
		long_axis = 0 if ext[0] >= ext[1] else 1
	return tuple(STROKE_LONG_FREQ if i == long_axis else STROKE_SHORT_FREQ for i in range(3))


def _hue_chroma_deg(rgb) -> tuple:
	"""(teinte 0-360 deg, chroma approximee HSV) -- meme heuristique que
	ai_restyle.py::_hue_chroma_deg (dupliquee ici, voir l'en-tete)."""
	r, g, b = (max(0.0, min(1.0, c)) for c in rgb[:3])
	h, s, v = colorsys.rgb_to_hsv(r, g, b)
	return (h * 360.0, s * v)


def reserved_band_violation(rgb) -> bool:
	"""True si `rgb` (0..1) tombe dans une bande de teinte reservee a haute
	chroma (surbrillance ennemie/alliee, docs/assets/ASSET_PLAN.md §3.4)."""
	hue_deg, chroma = _hue_chroma_deg(rgb)
	if chroma <= RESERVED_HUE_CHROMA_THRESHOLD:
		return False
	return any(lo <= hue_deg <= hi for lo, hi in RESERVED_HUE_BANDS_DEG)


def guard_reserved_hues(rgb) -> tuple:
	"""Ramene hors des bandes reservees chaque pixel de `rgb` (tableau (N, 3),
	sRGB 0..1) qui y tombe a haute chroma -- meme critere que
	`reserved_band_violation` : teinte deplacee vers le bord de bande le plus
	proche (+ `RESERVED_HUE_MARGIN_DEG`), saturation et valeur HSV
	conservees. Filet de securite apres cuisson (un creux teinte vers l'ombre
	bleue sur un metal rouge frole le magenta). Renvoie `(copie corrigee,
	nombre de pixels corriges)` ; les pixels hors bande sont rendus a
	l'identique."""
	arr = np.clip(np.asarray(rgb, dtype=np.float64).reshape(-1, 3), 0.0, 1.0)
	out = arr.copy()
	r, g, b = arr[:, 0], arr[:, 1], arr[:, 2]
	mx = arr.max(axis=1)
	mn = arr.min(axis=1)
	delta = mx - mn
	safe = np.where(delta > 0.0, delta, 1.0)
	rc, gc, bc = (mx - r) / safe, (mx - g) / safe, (mx - b) / safe
	hue = np.where(r == mx, bc - gc, np.where(g == mx, 2.0 + rc - bc, 4.0 + gc - rc))
	hue_deg = ((hue / 6.0) % 1.0) * 360.0
	violating = delta > RESERVED_HUE_CHROMA_THRESHOLD
	in_band = np.zeros_like(violating)
	new_hue = hue_deg.copy()
	for lo, hi in RESERVED_HUE_BANDS_DEG:
		band = (hue_deg >= lo) & (hue_deg <= hi)
		in_band |= band
		to_low = (hue_deg - lo) <= (hi - hue_deg)
		new_hue = np.where(band, np.where(to_low, lo - RESERVED_HUE_MARGIN_DEG, hi + RESERVED_HUE_MARGIN_DEG), new_hue)
	fix = violating & in_band
	count = int(fix.sum())
	if count == 0:
		return out, 0
	h6 = (new_hue[fix] % 360.0) / 60.0
	v = mx[fix]
	s = delta[fix] / v
	i = np.floor(h6).astype(np.int64) % 6
	f = h6 - np.floor(h6)
	p = v * (1.0 - s)
	q = v * (1.0 - s * f)
	t = v * (1.0 - s * (1.0 - f))
	choices_r = np.select([i == 0, i == 1, i == 2, i == 3, i == 4], [v, q, p, p, t], default=v)
	choices_g = np.select([i == 0, i == 1, i == 2, i == 3, i == 4], [t, v, v, q, p], default=p)
	choices_b = np.select([i == 0, i == 1, i == 2, i == 3, i == 4], [p, p, t, v, v], default=q)
	out[fix] = np.stack([choices_r, choices_g, choices_b], axis=1)
	return out, count


def augment_sidecar(glb_path: str, extra: dict) -> str:
	"""Ajoute les cles de `extra` au rapport JSON deja ecrit par
	`toonkit.export_glb` a cote de `glb_path` (meme fichier augmente -- meme
	idee que ai_import_painted.py::_augment_sidecar, dupliquee ici)."""
	sidecar_path = os.path.splitext(glb_path)[0] + ".json"
	with open(sidecar_path, "r", encoding="utf-8") as f:
		data = json.load(f)
	data.update(extra)
	with open(sidecar_path, "w", encoding="utf-8") as f:
		json.dump(data, f, indent=2, ensure_ascii=False)
	return sidecar_path


def _union_find_groups(n: int, pairs) -> list:
	"""Composantes connexes de `range(n)` reliees par `pairs` (listes
	d'index, ordre stable)."""
	parent = list(range(n))

	def find(i):
		root = i
		while parent[root] != root:
			root = parent[root]
		while parent[i] != root:
			parent[i], i = root, parent[i]
		return root

	for a, b in pairs:
		ra, rb = find(a), find(b)
		if ra != rb:
			parent[ra] = rb
	groups = {}
	for i in range(n):
		groups.setdefault(find(i), []).append(i)
	return list(groups.values())


def _repo_relative(path: str) -> str:
	"""Chemin relatif a la racine du depot (barres obliques), ou `path` tel
	quel s'il est ailleurs -- lisible et stable dans les rapports."""
	try:
		rel = os.path.relpath(path, REPO_ROOT)
	except ValueError:  # autre lecteur (Windows)
		return path
	return path if rel.startswith("..") else rel.replace(os.sep, "/")


def _srgb_to_linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _srgb_to_linear_color(rgba) -> tuple:
	a = rgba[3] if len(rgba) > 3 else 1.0
	return tuple(_srgb_to_linear(c) for c in rgba[:3]) + (a,)


def _srgb_to_linear_np(x):
	return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)


def _linear_to_srgb_np(x):
	x = np.clip(x, 0.0, None)
	return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1.0 / 2.4) - 0.055)


# ---------------------------------------------------------------------------
# Fonctions dependantes de bpy -- jamais appelees hors de Blender.
# ---------------------------------------------------------------------------

def import_asset(path: str) -> list:
	ext = os.path.splitext(path)[1].lower()
	if ext in (".glb", ".gltf"):
		bpy.ops.import_scene.gltf(filepath=path)
	elif ext == ".blend":
		bpy.ops.wm.open_mainfile(filepath=path)
	else:
		raise ValueError(f"paint_bake: extension non supportee: {ext!r} (attendu .glb/.gltf/.blend)")
	return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def _material_image_node(mat):
	"""Image branchee sur Base Color de `mat` -- meme logique que
	ai_restyle.py::_material_image_node (dupliquee ici), ou `None` si `mat`
	n'a pas de texture (couleur plate)."""
	if mat is None or not mat.use_nodes or mat.node_tree is None:
		return None
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	if bsdf is None or "Base Color" not in bsdf.inputs:
		return None
	socket = bsdf.inputs["Base Color"]
	if not socket.is_linked:
		return None
	src = socket.links[0].from_node
	if src.type == 'TEX_IMAGE' and src.image is not None:
		return src.image
	return None


BAKE_UV_LAYER = "paint_bake_uv"


def ensure_uv(obj, margin_px: float = DEFAULT_MARGIN_PX, res: int = DEFAULT_RES,
		bake_uv_name: str = BAKE_UV_LAYER) -> bool:
	"""Cree TOUJOURS une UV FRAICHE et DEDIEE a la cuisson (`bake_uv_name`,
	Smart UV Project, marge `margin_px` px a la resolution `res`), puis
	retire toute UV preexistante. BOGUE CONSTATE v1 (`wall_1_level.glb`) :
	reutiliser l'UV MONDE/tuilee de make_wl_shanty_kit.py (plusieurs planches
	PARTAGENT la meme region UV, une grande partie du carre [0,1] vide)
	donnait une cuisson a moitie NOIRE. Une UV unique et sans chevauchement
	est une PRECONDITION de toute cuisson par texel. Renvoie True si l'objet
	portait deja une UV (informatif pour le rapport)."""
	me = obj.data
	had_uv_before = len(me.uv_layers) > 0
	bake_layer = me.uv_layers.new(name=bake_uv_name)
	me.uv_layers.active = bake_layer
	bake_layer.active_render = True
	# `_select_only` pose l'etat de SELECTION REEL : un objet construit a la
	# main (primitive puis toonkit.join) n'est pas garanti actif/selectionne
	# au sens du poll de `mode_set`, contrairement a un objet fraichement
	# importe.
	_select_only([obj])
	with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
		bpy.ops.object.mode_set(mode='EDIT')
		bpy.ops.mesh.select_all(action='SELECT')
		bpy.ops.uv.smart_project(
			angle_limit=math.radians(66.0),
			island_margin=uv_margin_fraction(margin_px, res),
			area_weight=0.0,
		)
		bpy.ops.object.mode_set(mode='OBJECT')
	for other in [l for l in me.uv_layers if l.name != bake_uv_name]:
		me.uv_layers.remove(other)
	return had_uv_before


def compute_uv_face_islands(obj, eps: float = 1e-4) -> list:
	"""Iles UV de `obj` (listes d'index de polygones) : deux faces adjacentes
	sont dans la MEME ile seulement si leurs UV COINCIDENT aux deux extremites
	de l'arete partagee. Sans UV active, une seule composante par ile de
	maillage non resoude."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	bm.faces.ensure_lookup_table()
	uv_layer = bm.loops.layers.uv.active
	pairs = []

	def _uv_at(face, vert):
		for loop in face.loops:
			if loop.vert == vert:
				return loop[uv_layer].uv
		return None

	for edge in bm.edges:
		if len(edge.link_faces) != 2:
			continue
		f1, f2 = edge.link_faces
		if uv_layer is None:
			pairs.append((f1.index, f2.index))
			continue
		v0, v1 = edge.verts
		uv0_f1, uv1_f1 = _uv_at(f1, v0), _uv_at(f1, v1)
		uv0_f2, uv1_f2 = _uv_at(f2, v0), _uv_at(f2, v1)
		if None in (uv0_f1, uv1_f1, uv0_f2, uv1_f2):
			continue
		if (uv0_f1 - uv0_f2).length < eps and (uv1_f1 - uv1_f2).length < eps:
			pairs.append((f1.index, f2.index))
	n = len(bm.faces)
	bm.free()
	return _union_find_groups(n, pairs)


def _welded_bmesh(obj):
	"""Copie bmesh de `obj` aux sommets RECOLLES (`WELD_DIST_M`) : l'importeur
	glTF eclate les sommets a chaque arete vive (normales/UV par face), si
	bien qu'aucune arete n'y relie deux faces d'angle different -- sans ce
	recollage, ni les planches (iles) ni la convexite des aretes ne sont
	lisibles. Chaque face garde l'index du polygone d'origine dans la couche
	entiere renvoyee (`(bm, couche)`) ; le maillage de `obj` n'est PAS
	modifie. L'appelant libere `bm`."""
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	layer = bm.faces.layers.int.new("paint_bake_face")
	for face in bm.faces:
		face[layer] = face.index
	bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=WELD_DIST_M)
	bm.faces.ensure_lookup_table()
	bm.normal_update()
	return bm, layer


def compute_mesh_islands(obj) -> list:
	"""Iles de MAILLAGE (pieces/planches) de `obj`, en index de polygones
	d'origine, apres recollage (`_welded_bmesh`). Une face degeneree retiree
	par le recollage reste une ile a elle seule."""
	n = len(obj.data.polygons)
	bm, layer = _welded_bmesh(obj)
	pairs = []
	for edge in bm.edges:
		faces = edge.link_faces
		for other in faces[1:]:
			pairs.append((faces[0][layer], other[layer]))
	bm.free()
	return _union_find_groups(n, pairs)


def compute_bevel_faces(obj) -> set:
	"""Index des polygones de `obj` qui sont des faces de CHANFREIN/biseau :
	bande de moins de `BEVEL_FACE_MAX_W_M` de large (hauteur sur l'arete la
	plus longue pour un triangle -- les .glb sont triangules --, aire/
	longueur sinon), bordee d'au moins une arete CONVEXE tournant de
	`BEVEL_TURN_MIN_DEG`-`BEVEL_TURN_MAX_DEG` et d'aucune arete concave. Ce
	sont les faces que le liseré d'eclat doit couvrir entierement (bible §7.9 :
	« faces de biseau a 1 ») : le noeud Bevel seul ne les voit pas, sa normale
	arrondie y retombe sur la normale du chanfrein par symetrie."""
	bm, layer = _welded_bmesh(obj)
	lo = math.radians(BEVEL_TURN_MIN_DEG)
	hi = math.radians(BEVEL_TURN_MAX_DEG)
	found = set()
	for face in bm.faces:
		longest = max(e.calc_length() for e in face.edges)
		if longest <= 0.0:
			continue
		width = (2.0 if len(face.verts) == 3 else 1.0) * face.calc_area() / longest
		if width > BEVEL_FACE_MAX_W_M:
			continue
		convex = False
		concave = False
		for edge in face.edges:
			if len(edge.link_faces) != 2:
				continue
			angle = edge.calc_face_angle_signed(0.0)
			if lo <= angle <= hi:
				convex = True
			elif angle <= -lo:
				concave = True
		if convex and not concave:
			found.add(face[layer])
	bm.free()
	return found


def _write_face_color_attr(obj, attr_name: str, face_rgba, attr_type: str = 'FLOAT_COLOR'):
	"""(Re)cree l'attribut de couleur `attr_name` (domaine CORNER) de `obj`
	avec une couleur PLATE par polygone (`face_rgba`, tableau (n_polygones,
	4))."""
	me = obj.data
	idx = me.color_attributes.find(attr_name)
	if idx != -1:
		me.color_attributes.remove(me.color_attributes[idx])
	attr = me.color_attributes.new(name=attr_name, type=attr_type, domain='CORNER')
	totals = np.empty(len(me.polygons), dtype=np.int64)
	me.polygons.foreach_get("loop_total", totals)
	loop_face = np.repeat(np.arange(len(me.polygons)), totals)
	colors = np.asarray(face_rgba, dtype=np.float32)[loop_face]
	attr.data.foreach_set("color", colors.ravel())
	me.update()
	return attr


def _per_island_rgba(n_faces: int, islands: list, value_of_island) -> "np.ndarray":
	rgba = np.ones((n_faces, 4), dtype=np.float32)
	for island_index, face_indices in enumerate(islands):
		v = value_of_island(island_index, face_indices)
		rgba[face_indices, :3] = v
	return rgba


def bake_island_hue_attr(obj, islands: list, seed, max_deg: float = DEFAULT_HUE_MAX_DEG,
		attr_name: str = "island_hue"):
	"""Bake `island_hue_offset` (remappe [0,1] par `hue01_from_offset_deg`)
	dans un attribut BYTE_COLOR (domaine CORNER), R=G=B : lu par le noeud
	Hue/Saturation du shader de cuisson via `ShaderNodeVertexColor` (qui
	convertit une RGBA en flottant par luma ; R=G=B rend la conversion
	exacte)."""
	rgba = _per_island_rgba(len(obj.data.polygons), islands,
		lambda i, _faces: hue01_from_offset_deg(island_hue_offset(seed, obj.name, i, max_deg=max_deg)))
	return _write_face_color_attr(obj, attr_name, rgba, 'BYTE_COLOR')


def bake_island_value_attr(obj, islands: list, seed, max_frac: float = DEFAULT_VALUE_MAX_FRAC,
		attr_name: str = "island_value"):
	"""Multiplicateur de valeur HSV par ile (1 + `island_value_offset`),
	FLOAT_COLOR R=G=B (pas de quantification)."""
	rgba = _per_island_rgba(len(obj.data.polygons), islands,
		lambda i, _faces: 1.0 + island_value_offset(seed, obj.name, i, max_frac=max_frac))
	return _write_face_color_attr(obj, attr_name, rgba)


def bake_stroke_axis_attr(obj, islands: list, attr_name: str = "stroke_axis"):
	"""Frequences de coups de pinceau (X, Y, Z en cycles/m, voir
	`stroke_frequencies`) par ile, d'apres son etendue METRIQUE (echelle de
	l'objet comprise) -- lues comme un vecteur par le shader de cuisson."""
	me = obj.data
	co = np.empty(len(me.vertices) * 3, dtype=np.float64)
	me.vertices.foreach_get("co", co)
	co = co.reshape(-1, 3) * np.asarray(obj.scale, dtype=np.float64)
	face_verts = [list(p.vertices) for p in me.polygons]
	rgba = np.ones((len(me.polygons), 4), dtype=np.float32)
	for face_indices in islands:
		verts = sorted({v for f in face_indices for v in face_verts[f]})
		pts = co[verts]
		rgba[face_indices, :3] = stroke_frequencies(pts.max(axis=0) - pts.min(axis=0))
	return _write_face_color_attr(obj, attr_name, rgba)


def bake_bevel_face_attr(obj, bevel_faces: set, attr_name: str = "bevel_face"):
	"""1 sur les faces de chanfrein (`compute_bevel_faces`), 0 ailleurs."""
	rgba = np.zeros((len(obj.data.polygons), 4), dtype=np.float32)
	rgba[:, 3] = 1.0
	if bevel_faces:
		rgba[sorted(bevel_faces), :3] = 1.0
	return _write_face_color_attr(obj, attr_name, rgba)


def _read_rgb(image) -> "np.ndarray":
	"""Pixels RGB de `image`, tableau (h, w, 3) float64 -- valeurs ENCODEES
	sRGB pour une image 8 bits (la cuisson et les PNG peints), lineaires pour
	une image flottante."""
	w, h = image.size
	flat = np.empty(w * h * image.channels, dtype=np.float32)
	image.pixels.foreach_get(flat)
	return flat.reshape(h, w, image.channels)[:, :, :3].astype(np.float64)


def _write_rgb(image, rgb) -> None:
	w, h = image.size
	rgba = np.ones((h, w, image.channels), dtype=np.float32)
	rgba[:, :, :3] = np.asarray(rgb, dtype=np.float32).reshape(h, w, 3)
	image.pixels.foreach_set(rgba.ravel())
	image.update()


def load_texture_image(path: str):
	image = bpy.data.images.load(path, check_existing=True)
	image.colorspace_settings.name = 'sRGB'
	return image


def image_stats(image) -> dict:
	"""`{"luma": luma sRGB moyenne, "linear_rgb": couleur lineaire moyenne}`
	de `image` (toute l'image : une texture peinte est tuilable, sa moyenne
	est celle que la projection en boite restitue)."""
	rgb = _read_rgb(image)
	if image.is_float:
		linear = rgb
		encoded = _linear_to_srgb_np(rgb)
	else:
		encoded = rgb
		linear = _srgb_to_linear_np(rgb)
	luma = float((encoded * np.asarray(LUMA_WEIGHTS)).sum(axis=2).mean())
	return {"luma": luma, "linear_rgb": tuple(float(c) for c in linear.reshape(-1, 3).mean(axis=0))}


def _slot_base(mat, kind: str) -> dict:
	"""Base peinte d'un slot (etape 4a de l'en-tete) : `{"mode", "image",
	"path", "recolor", "target_luma"}` -- "existing" (image deja posee sur le
	slot), "texture" (texture du kind) ou "recolor" (detail peint recolore a
	`palette(kind)`, facteur lineaire par canal dans "recolor")."""
	existing = _material_image_node(mat)
	if existing is not None:
		path = bpy.path.abspath(existing.filepath) if existing.filepath else existing.name
		return {"mode": "existing", "image": existing, "path": path, "recolor": None,
			"target_luma": image_stats(existing)["luma"]}
	resolved = resolve_base_texture(kind)
	image = load_texture_image(resolved["path"])
	stats = image_stats(image)
	if resolved["mode"] == "texture":
		return {"mode": "texture", "image": image, "path": resolved["path"], "recolor": None,
			"target_luma": stats["luma"]}
	color_srgb = toonkit.palette(kind)
	color_lin = _srgb_to_linear_color(color_srgb)[:3]
	factor = tuple(c / max(m, 1e-4) for c, m in zip(color_lin, stats["linear_rgb"]))
	return {"mode": "recolor", "image": image, "path": resolved["path"], "recolor": factor,
		"target_luma": srgb_luma(color_srgb)}


# -- noeuds -------------------------------------------------------------------

def _mul_color(nt, color_socket, factor_socket):
	"""`color_socket` x `factor_socket` (flottant diffuse sur R/G/B, ou
	couleur) via `ShaderNodeMixRGB` MULTIPLY, Factor=1."""
	m = nt.nodes.new("ShaderNodeMixRGB")
	m.blend_type = 'MULTIPLY'
	m.inputs[0].default_value = 1.0
	nt.links.new(color_socket, m.inputs[1])
	nt.links.new(factor_socket, m.inputs[2])
	return m.outputs["Color"]


def _mix_color(nt, fac, color_a, color_b):
	"""`color_a` (Fac=0) -> `color_b` (Fac=1) via `ShaderNodeMixRGB` MIX --
	`fac` : socket de sortie (relie) ou nombre (`default_value`)."""
	m = nt.nodes.new("ShaderNodeMixRGB")
	m.blend_type = 'MIX'
	if isinstance(fac, (int, float)):
		m.inputs[0].default_value = fac
	else:
		nt.links.new(fac, m.inputs[0])
	nt.links.new(color_a, m.inputs[1])
	nt.links.new(color_b, m.inputs[2])
	return m.outputs["Color"]


def _map_range(nt, value_socket, from_min, from_max, to_min, to_max, clamp=True):
	mr = nt.nodes.new("ShaderNodeMapRange")
	mr.clamp = clamp
	mr.inputs["From Min"].default_value = from_min
	mr.inputs["From Max"].default_value = from_max
	mr.inputs["To Min"].default_value = to_min
	mr.inputs["To Max"].default_value = to_max
	nt.links.new(value_socket, mr.inputs["Value"])
	return mr.outputs["Result"]


def _math(nt, operation, a, b=None):
	"""`ShaderNodeMath(operation)` -- `a`/`b` : socket de sortie (relie) ou
	nombre (`default_value`)."""
	m = nt.nodes.new("ShaderNodeMath")
	m.operation = operation
	for socket, value in ((m.inputs[0], a), (m.inputs[1], b)):
		if value is None:
			continue
		if isinstance(value, (int, float)):
			socket.default_value = value
		else:
			nt.links.new(value, socket)
	return m.outputs[0]


def _rgb_const(nt, rgb):
	node = nt.nodes.new("ShaderNodeRGB")
	node.outputs[0].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
	return node.outputs[0]


def _metric_coords(nt, obj_scale, extra_scale: float = 1.0):
	"""Coordonnees OBJET mises a l'echelle METRIQUE (x echelle de l'objet),
	x `extra_scale`."""
	tex_coord = nt.nodes.new("ShaderNodeTexCoord")
	mapping = nt.nodes.new("ShaderNodeMapping")
	mapping.vector_type = 'POINT'
	mapping.inputs["Scale"].default_value = tuple(s * extra_scale for s in obj_scale)
	nt.links.new(tex_coord.outputs["Object"], mapping.inputs["Vector"])
	return mapping.outputs["Vector"]


def _bevel_dot(nt, geo, radius: float):
	"""dot(normale arrondie du noeud Bevel de rayon `radius`, normale de
	surface) : 1 sur une face plane, decroit a moins de ~`radius`/2 d'une
	arete (profil mesure, voir constantes EDGE_*)."""
	bevel = nt.nodes.new("ShaderNodeBevel")
	bevel.samples = NODE_SAMPLES
	bevel.inputs["Radius"].default_value = radius
	dot = nt.nodes.new("ShaderNodeVectorMath")
	dot.operation = 'DOT_PRODUCT'
	nt.links.new(bevel.outputs["Normal"], dot.inputs[0])
	nt.links.new(geo.outputs["Normal"], dot.inputs[1])
	return dot.outputs["Value"]


def _ambient_occlusion(nt, distance: float):
	ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
	ao.samples = NODE_SAMPLES
	ao.inputs["Distance"].default_value = distance
	return ao.outputs["AO"]


def _build_bake_material(name: str, base: dict, obj_scale):
	"""Materiau de cuisson (Emission -> Material Output) d'UN slot : etapes
	4a-4h de l'en-tete, dans cet ordre. Renvoie `(materiau,
	noeud_image_de_cuisson, noeud_gain)` : l'appelant pose l'image cible sur
	le premier (actif/selectionne, cible de `bpy.ops.object.bake`) et le gain
	de luminance du slot sur `noeud_gain.outputs[0].default_value`."""
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	nt = mat.node_tree
	for n in list(nt.nodes):
		nt.nodes.remove(n)
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	emission = nt.nodes.new("ShaderNodeEmission")
	nt.links.new(emission.outputs["Emission"], out.inputs["Surface"])
	geo = nt.nodes.new("ShaderNodeNewGeometry")

	# a. base : texture peinte projetee en boite, echelle du monde ----------
	tex = nt.nodes.new("ShaderNodeTexImage")
	tex.image = base["image"]
	tex.projection = 'BOX'
	tex.projection_blend = BOX_BLEND
	tex.interpolation = 'Linear'
	tex.extension = 'REPEAT'
	nt.links.new(_metric_coords(nt, obj_scale, WORLD_UV_SCALE), tex.inputs["Vector"])
	color = tex.outputs["Color"]
	if base["recolor"] is not None:
		color = _mul_color(nt, color, _rgb_const(nt, base["recolor"]))

	# b. teinte et valeur par planche ---------------------------------------
	hue_sat = nt.nodes.new("ShaderNodeHueSaturation")
	hue_sat.inputs["Saturation"].default_value = 1.0
	hue_sat.inputs[3].default_value = 1.0  # Factor
	hue_attr = nt.nodes.new("ShaderNodeVertexColor")
	hue_attr.layer_name = "island_hue"
	value_attr = nt.nodes.new("ShaderNodeVertexColor")
	value_attr.layer_name = "island_value"
	nt.links.new(hue_attr.outputs["Color"], hue_sat.inputs["Hue"])
	nt.links.new(value_attr.outputs["Color"], hue_sat.inputs["Value"])
	nt.links.new(color, hue_sat.inputs["Color"])
	color = hue_sat.outputs["Color"]

	# c. coups de pinceau (etires le long de la planche) + grain fin ---------
	metric = _metric_coords(nt, obj_scale)
	stroke_attr = nt.nodes.new("ShaderNodeAttribute")
	stroke_attr.attribute_type = 'GEOMETRY'
	stroke_attr.attribute_name = "stroke_axis"
	stretched = nt.nodes.new("ShaderNodeVectorMath")
	stretched.operation = 'MULTIPLY'
	nt.links.new(metric, stretched.inputs[0])
	nt.links.new(stroke_attr.outputs["Vector"], stretched.inputs[1])
	stroke_noise = nt.nodes.new("ShaderNodeTexNoise")
	stroke_noise.inputs["Scale"].default_value = 1.0
	stroke_noise.inputs["Detail"].default_value = 3.0
	stroke_noise.inputs["Roughness"].default_value = 0.55
	stroke_noise.inputs["Distortion"].default_value = 0.4
	nt.links.new(stretched.outputs["Vector"], stroke_noise.inputs["Vector"])
	stroke = _map_range(nt, stroke_noise.outputs[0], STROKE_NOISE_LOW, STROKE_NOISE_HIGH,
		1.0 - STROKE_STRENGTH, 1.0 + STROKE_STRENGTH)
	grain_noise = nt.nodes.new("ShaderNodeTexNoise")
	grain_noise.inputs["Scale"].default_value = GRAIN_FREQ
	grain_noise.inputs["Detail"].default_value = 1.0
	nt.links.new(metric, grain_noise.inputs["Vector"])
	grain = _map_range(nt, grain_noise.outputs[0], 0.3, 0.7, 1.0 - GRAIN_STRENGTH, 1.0 + GRAIN_STRENGTH)

	# d. degrade vertical (boite objet normalisee) + dessus plus clair ------
	tex_coord = nt.nodes.new("ShaderNodeTexCoord")
	generated = nt.nodes.new("ShaderNodeSeparateXYZ")
	nt.links.new(tex_coord.outputs["Generated"], generated.inputs["Vector"])
	gradient = _map_range(nt, generated.outputs["Z"], 0.0, 1.0, GRAD_LOW, GRAD_HIGH)
	normal = nt.nodes.new("ShaderNodeSeparateXYZ")
	nt.links.new(geo.outputs["Normal"], normal.inputs["Vector"])
	top = _map_range(nt, normal.outputs["Z"], TOP_NORMAL_MIN, TOP_NORMAL_MAX, 1.0, TOP_LIFT)

	# e. gain de luminance du slot (calibre par bake_object_texture) --------
	gain = nt.nodes.new("ShaderNodeValue")
	gain.outputs[0].default_value = 1.0
	factor = _math(nt, 'MULTIPLY', _math(nt, 'MULTIPLY', stroke, grain),
		_math(nt, 'MULTIPLY', _math(nt, 'MULTIPLY', gradient, top), gain.outputs[0]))
	color = _mul_color(nt, color, factor)

	# f. creux : AO seuillee, assombris ET teintes vers l'ombre de la carte --
	occlusion = _map_range(nt, _ambient_occlusion(nt, CREVICE_AO_DISTANCE_M),
		CREVICE_AO_CLOSED, CREVICE_AO_OPEN, CREVICE_STRENGTH, 0.0)
	tint = _srgb_to_linear_color(toonkit.palette("shadow_tint"))[:3]
	tint_luma = max(sum(w * c for w, c in zip(LUMA_WEIGHTS, tint)), 1e-4)
	crevice_mul = tuple(((1.0 - SHADOW_TINT_MIX) + SHADOW_TINT_MIX * c / tint_luma) * CREVICE_VALUE for c in tint)
	color = _mix_color(nt, occlusion, color, _mul_color(nt, color, _rgb_const(nt, crevice_mul)))

	# g. liseré d'eclat net sur les aretes convexes -------------------------
	convex_gate = _map_range(nt, _ambient_occlusion(nt, CONVEX_AO_DISTANCE_M),
		CONVEX_AO_CONCAVE, CONVEX_AO_OPEN, 0.0, 1.0)
	band = _map_range(nt, _bevel_dot(nt, geo, EDGE_BEVEL_RADIUS_M), EDGE_DOT_START, EDGE_DOT_FULL, 0.0, 1.0)
	bevel_face = nt.nodes.new("ShaderNodeVertexColor")
	bevel_face.layer_name = "bevel_face"
	edge = _math(nt, 'MULTIPLY', _math(nt, 'MAXIMUM', band, bevel_face.outputs["Color"]), convex_gate)
	sun = _srgb_to_linear_color(EDGE_SUN_SRGB)[:3]
	lightened = _mul_color(nt, color, _rgb_const(nt, (EDGE_LIGHTEN_LIN,) * 3))
	highlight = _mix_color(nt, EDGE_SUN_MIX, lightened, _rgb_const(nt, sun))
	color = _mix_color(nt, edge, color, highlight)

	# h. trait d'encre fin sur ces memes aretes -----------------------------
	ink_amount = _map_range(nt, _bevel_dot(nt, geo, INK_BEVEL_RADIUS_M), INK_DOT_START, INK_DOT_FULL,
		0.0, INK_STRENGTH)
	ink = _srgb_to_linear_color(toonkit.palette("ink"))[:3]
	color = _mix_color(nt, _math(nt, 'MULTIPLY', ink_amount, convex_gate), color, _rgb_const(nt, ink))

	nt.links.new(color, emission.inputs["Color"])
	img_node = nt.nodes.new("ShaderNodeTexImage")
	return mat, img_node, gain


def _select_only(objs) -> None:
	bpy.ops.object.select_all(action='DESELECT')
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]


def _bake_emit(obj, margin_px: int, samples: int) -> None:
	"""Un appel `bpy.ops.object.bake(type='EMIT')` sur `obj` (UV
	`BAKE_UV_LAYER`, image = noeud actif de chaque materiau), Cycles le temps
	de l'appel ; moteur, echantillons et selection restaures ensuite."""
	scene = bpy.context.scene
	prev_engine = scene.render.engine
	prev_samples = getattr(scene.cycles, "samples", None)
	prev_selected = list(bpy.context.selected_objects)
	prev_active = bpy.context.view_layer.objects.active
	scene.render.engine = 'CYCLES'
	import gpu_compute  # tools/blender/lib (déjà sur sys.path) : GPU + moitié des cœurs
	gpu_compute.use_gpu_for_cycles(scene)
	scene.cycles.samples = samples
	_select_only([obj])
	try:
		with bpy.context.temp_override(object=obj, active_object=obj,
				selected_objects=[obj], selected_editable_objects=[obj]):
			bpy.ops.object.bake(type='EMIT', target='IMAGE_TEXTURES', uv_layer=BAKE_UV_LAYER,
				margin=margin_px, margin_type='EXTEND', use_clear=True)
	finally:
		scene.render.engine = prev_engine
		if prev_samples is not None:
			scene.cycles.samples = prev_samples
		_select_only(prev_selected or [obj])
		if prev_active is not None:
			bpy.context.view_layer.objects.active = prev_active


def _uv_slot_masks(obj, res: int) -> dict:
	"""{index de slot: masque booleen (res, res)} des texels dont le CENTRE
	tombe dans un triangle UV (UV active) de ce slot -- ligne 0 = v 0, comme
	`image.pixels`. Rasterisation par fonctions d'arete, triangle par
	triangle."""
	me = obj.data
	me.calc_loop_triangles()
	n_tri = len(me.loop_triangles)
	uv = np.empty(len(me.loops) * 2, dtype=np.float64)
	me.uv_layers.active.data.foreach_get("uv", uv)
	uv = uv.reshape(-1, 2) * res
	tri_loops = np.empty(n_tri * 3, dtype=np.int64)
	me.loop_triangles.foreach_get("loops", tri_loops)
	tri_mat = np.empty(n_tri, dtype=np.int64)
	me.loop_triangles.foreach_get("material_index", tri_mat)
	masks = {int(s): np.zeros((res, res), dtype=bool) for s in np.unique(tri_mat)}
	corners = uv[tri_loops].reshape(n_tri, 3, 2)
	for t in range(n_tri):
		a, b, c = corners[t]
		x0 = max(int(math.floor(min(a[0], b[0], c[0]))), 0)
		x1 = min(int(math.ceil(max(a[0], b[0], c[0]))), res - 1)
		y0 = max(int(math.floor(min(a[1], b[1], c[1]))), 0)
		y1 = min(int(math.ceil(max(a[1], b[1], c[1]))), res - 1)
		if x1 < x0 or y1 < y0:
			continue
		area = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
		if abs(area) < 1e-12:
			continue
		px, py = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
		w0 = ((b[0] - px) * (c[1] - py) - (b[1] - py) * (c[0] - px)) / area
		w1 = ((c[0] - px) * (a[1] - py) - (c[1] - py) * (a[0] - px)) / area
		w2 = 1.0 - w0 - w1
		inside = (w0 >= 0.0) & (w1 >= 0.0) & (w2 >= 0.0)
		masks[int(tri_mat[t])][y0:y1 + 1, x0:x1 + 1] |= inside
	return masks


def _slot_lumas(rgb, masks: dict, slot_count: int) -> list:
	"""Luma sRGB moyenne des texels de chaque slot (`None` : aucun texel)."""
	luma = (rgb * np.asarray(LUMA_WEIGHTS)).sum(axis=2)
	out = []
	for s in range(slot_count):
		mask = masks.get(s)
		out.append(float(luma[mask].mean()) if mask is not None and mask.any() else None)
	return out


def _calibrate_and_bake(obj, image, masks: dict, gain_nodes: list, gains: list, targets: list,
		margin_px: int, samples: int, max_passes: int) -> tuple:
	"""Cuit `obj` dans `image` (deja posee sur les noeuds cibles) et corrige
	le gain de chaque slot (`linear_gain_step`) jusqu'a ce que sa luma sRGB
	moyenne (`masks`) soit a +/- `LUMA_CONVERGE` de sa cible, en
	`max_passes` cuissons au plus. Renvoie `(gains de la derniere cuisson,
	nombre de cuissons, pixels RGB de la derniere cuisson)`."""
	passes = 0
	while True:
		for node, g in zip(gain_nodes, gains):
			node.outputs[0].default_value = g
		_bake_emit(obj, margin_px, samples)
		passes += 1
		rgb = _read_rgb(image)
		measured = _slot_lumas(rgb, masks, len(gains))
		converged = all(m is None or luma_within_tolerance(m, t, LUMA_CONVERGE) for m, t in zip(measured, targets))
		if converged or passes >= max_passes:
			return gains, passes, rgb
		gains = [g if m is None else g * linear_gain_step(t, m) for g, m, t in zip(gains, measured, targets)]


def bake_object_texture(obj, res: int, bake_margin_px: int, samples: int, seed, hue_max_deg: float,
		palette_kind, image_name: str, margin_px: float = DEFAULT_MARGIN_PX) -> dict:
	"""Peint `obj` : etapes 1 a 6 de l'en-tete. Renvoie le rapport de
	l'objet (`slots` : kind, base, luminances cible/cuite, gain ; iles ;
	pixels corriges par la garde de teinte) -- ne construit PAS le nom final
	du materiau (`output_material_name`, appele par l'orchestrateur)."""
	had_uv_before = ensure_uv(obj, margin_px=margin_px, res=res)
	uv_islands = compute_uv_face_islands(obj)
	mesh_islands = compute_mesh_islands(obj)
	bevel_faces = compute_bevel_faces(obj)
	bake_island_hue_attr(obj, mesh_islands, seed=seed, max_deg=hue_max_deg)
	bake_island_value_attr(obj, mesh_islands, seed=seed)
	bake_stroke_axis_attr(obj, mesh_islands)
	bake_bevel_face_attr(obj, bevel_faces)

	original_materials = list(obj.data.materials) or [None]
	slots_report = []
	bake_materials = []
	img_nodes = []
	gain_nodes = []
	for slot_index, mat in enumerate(original_materials):
		stored_kind = mat.get("toonkit_kind") if mat is not None else None
		mat_name = mat.name if mat is not None else "__none__"
		kind = resolve_kind(mat_name, stored_kind, palette_kind)
		base = _slot_base(mat, kind)
		bake_mat, img_node, gain_node = _build_bake_material(
			f"__paint_bake_src_{obj.name}_{slot_index}", base, tuple(obj.scale))
		for n in bake_mat.node_tree.nodes:
			n.select = False
		img_node.select = True
		bake_mat.node_tree.nodes.active = img_node
		bake_materials.append(bake_mat)
		img_nodes.append(img_node)
		gain_nodes.append(gain_node)
		slots_report.append({
			"original_material": mat_name, "kind": kind,
			"had_existing_texture": base["mode"] == "existing",
			"base_mode": base["mode"], "base_texture": _repo_relative(base["path"]),
			"target_luma": round(base["target_luma"], 4),
		})
	targets = [s["target_luma"] for s in slots_report]

	# `materials.clear()` remet TOUS les polygones sur le slot 0 (sondage bpy
	# 5.2) : sans cette sauvegarde, un objet a plusieurs slots etait cuit en
	# entier avec le materiau du premier (BUG CONSTATE v1 : porte, fut et toit
	# des demos cuits tout en bois/rouille).
	me = obj.data
	material_indices = np.empty(len(me.polygons), dtype=np.int32)
	me.polygons.foreach_get("material_index", material_indices)
	me.materials.clear()
	for bake_mat in bake_materials:
		me.materials.append(bake_mat)
	me.polygons.foreach_set("material_index", material_indices)
	me.update()

	# Calibration de luminance (etape 5) : d'abord a basse resolution (rapide),
	# puis corrigee a pleine resolution si un slot s'en ecarte encore.
	calib_image = bpy.data.images.new(f"{image_name}__calibration", width=CALIBRATION_RES,
		height=CALIBRATION_RES, alpha=False)
	for node in img_nodes:
		node.image = calib_image
	gains, calibration_passes = _calibrate_and_bake(
		obj, calib_image, _uv_slot_masks(obj, CALIBRATION_RES), gain_nodes, [1.0] * len(gain_nodes), targets,
		CALIBRATION_MARGIN_PX, samples, MAX_CALIBRATION_PASSES)[:2]
	bpy.data.images.remove(calib_image)

	bake_image = bpy.data.images.new(image_name, width=res, height=res, alpha=False)
	for node in img_nodes:
		node.image = bake_image
	masks = _uv_slot_masks(obj, res)
	gains, full_res_passes, rgb = _calibrate_and_bake(
		obj, bake_image, masks, gain_nodes, gains, targets, bake_margin_px, samples, MAX_FULL_RES_PASSES)

	# Garde de teinte reservee, puis mesure rapportee (sur les pixels livres).
	guarded, guarded_count = guard_reserved_hues(rgb.reshape(-1, 3))
	if guarded_count:
		rgb = guarded.reshape(rgb.shape)
		_write_rgb(bake_image, rgb)
	final = _slot_lumas(rgb, masks, len(slots_report))
	for slot, g, baked in zip(slots_report, gains, final):
		slot["gain_linear"] = round(g, 4)
		slot["baked_luma"] = None if baked is None else round(baked, 4)
		slot["luma_ratio"] = None if baked is None else round(baked / slot["target_luma"], 4)
		slot["luma_ok"] = baked is None or luma_within_tolerance(baked, slot["target_luma"])
		if not slot["luma_ok"]:
			print(f"PAINT_BAKE_WARN {obj.name} slot {slot['original_material']!r} : luminance cuite "
				f"{slot['baked_luma']} hors de +/-{LUMA_TOLERANCE:.0%} de la source {slot['target_luma']}")
	bake_image.pack()

	# Retire TOUT attribut de couleur (COLOR_0/1/..., les notres ET tout
	# AO/Curvature preexistant) : un COLOR_0 glTF est TOUJOURS multiplie dans
	# le baseColor par tout consommateur conforme (dont Godot) -- jamais
	# souhaite sur une texture DEJA cuite (BUG CONSTATE v1, oil_drum.glb).
	for attr in list(me.color_attributes):
		me.color_attributes.remove(attr)

	# Materiau final : une seule texture couvre deja tout l'objet.
	final_mat = bpy.data.materials.new("__paint_bake_final__")
	final_mat.use_nodes = True
	fnt = final_mat.node_tree
	bsdf = fnt.nodes.get("Principled BSDF")
	tex = fnt.nodes.new("ShaderNodeTexImage")
	tex.image = bake_image
	fnt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
	bsdf.inputs["Roughness"].default_value = 0.85
	if "Metallic" in bsdf.inputs:
		bsdf.inputs["Metallic"].default_value = 0.0

	obj.data.materials.clear()
	obj.data.materials.append(final_mat)
	for poly in obj.data.polygons:
		poly.material_index = 0

	for bake_mat in bake_materials:
		if bake_mat.users == 0:
			bpy.data.materials.remove(bake_mat)

	return {
		"had_uv_before": had_uv_before,
		"islands": len(uv_islands),
		"mesh_islands": len(mesh_islands),
		"bevel_faces": len(bevel_faces),
		"calibration_passes": calibration_passes,
		"full_res_passes": full_res_passes,
		"reserved_hue_guarded": guarded_count,
		"slots": slots_report,
		"image": bake_image.name,
		"final_material_placeholder": final_mat.name,
	}


def run_turntable(glb_or_blend_path: str, out_dir: str, views: int = 8, size: int = 512,
		timeout_s: int = 600) -> str:
	"""Lance tools/blender/turntable.py EN SOUS-PROCESS sur `glb_or_blend_path`
	(meme technique que ai_restyle.py::run_turntable) -- capture "avant"
	(fichier source, jamais modifie) ET "apres" (sortie peinte)."""
	os.makedirs(out_dir, exist_ok=True)
	cmd = [
		bpy.app.binary_path, "-b", "--factory-startup", "--python-exit-code", "1",
		"-P", TURNTABLE_SCRIPT, "--",
		"--in", glb_or_blend_path, "--out", out_dir, "--views", str(views), "--size", str(size),
	]
	proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
	if proc.returncode != 0:
		raise RuntimeError(
			f"paint_bake: le turntable a echoue (code {proc.returncode}) pour {glb_or_blend_path}\n"
			f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}")
	lines = proc.stdout.splitlines()
	for i, line in enumerate(lines):
		if line.strip().startswith("TURNTABLE_OK") and i + 1 < len(lines):
			path = lines[i + 1].strip()
			if path:
				return path
	raise RuntimeError(
		f"paint_bake: pas de marqueur TURNTABLE_OK dans la sortie du turntable pour "
		f"{glb_or_blend_path}\n--- stdout ---\n{proc.stdout}")


def paint_bake(in_path: str, out_path: str, res: int = DEFAULT_RES, palette_kind: str = None,
		margin_px: float = DEFAULT_MARGIN_PX, bake_margin_px: int = DEFAULT_BAKE_MARGIN_PX,
		samples: int = DEFAULT_SAMPLES, seed=DEFAULT_SEED, hue_max_deg: float = DEFAULT_HUE_MAX_DEG,
		skip_turntable: bool = False, turntable_views: int = 8, turntable_size: int = 512,
		turntable_out_dir: str = None) -> dict:
	if res not in ALLOWED_RES:
		raise ValueError(f"paint_bake: --res {res} hors de {ALLOWED_RES}")

	turntable_before = None
	if not skip_turntable:
		before_dir = os.path.join(turntable_out_dir, "before") if turntable_out_dir else None
		if before_dir is None:
			stem_src = os.path.splitext(os.path.basename(in_path))[0]
			before_dir = os.path.join(os.path.dirname(os.path.abspath(out_path)), f"{stem_src}_before")
		turntable_before = run_turntable(in_path, before_dir, views=turntable_views, size=turntable_size)

	toonkit.reset_scene()
	mesh_objs = import_asset(in_path)
	if not mesh_objs:
		raise RuntimeError(f"paint_bake: aucun mesh dans {in_path}")

	stem = os.path.splitext(os.path.basename(out_path))[0]
	object_reports = []
	for obj_index, obj in enumerate(mesh_objs):
		image_name = f"{stem}_albedo" if len(mesh_objs) <= 1 else f"{stem}_{obj_index}_albedo"
		bake_report = bake_object_texture(
			obj, res=res, bake_margin_px=bake_margin_px, samples=samples,
			seed=f"{seed}:{stem}", hue_max_deg=hue_max_deg, palette_kind=palette_kind,
			image_name=image_name, margin_px=margin_px)
		final_name = output_material_name(stem, obj_index, len(mesh_objs))
		obj.data.materials[0].name = final_name
		bake_report["object"] = obj.name
		bake_report["material"] = final_name
		del bake_report["final_material_placeholder"]
		object_reports.append(bake_report)

	toonkit.export_glb(out_path, mesh_objs)

	turntable_after = None
	if not skip_turntable:
		after_dir = os.path.join(turntable_out_dir, "after") if turntable_out_dir else None
		if after_dir is None:
			after_dir = os.path.join(os.path.dirname(os.path.abspath(out_path)), f"{stem}_after")
		turntable_after = run_turntable(out_path, after_dir, views=turntable_views, size=turntable_size)

	luma_ok = all(slot["luma_ok"] for report in object_reports for slot in report["slots"])
	sidecar_path = augment_sidecar(out_path, {
		"painted": True,
		"paint_bake_version": 2,
		"source": os.path.abspath(in_path),
		"res": res,
		"palette": palette_kind,
		"seed": seed,
		"hue_max_deg": hue_max_deg,
		"luma_tolerance": LUMA_TOLERANCE,
		"luma_ok": luma_ok,
		"objects": object_reports,
		"turntable_before": turntable_before,
		"turntable_after": turntable_after,
	})

	print(f"PAINT_BAKE_OK {os.path.basename(out_path)} objets={len(object_reports)} res={res} "
		f"luminance={'ok' if luma_ok else 'HORS TOLERANCE'}")
	print(sidecar_path)
	return {
		"output": os.path.abspath(out_path), "sidecar": sidecar_path, "luma_ok": luma_ok,
		"objects": object_reports, "turntable_before": turntable_before, "turntable_after": turntable_after,
	}


def parse_args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	p = argparse.ArgumentParser()
	p.add_argument("--in", dest="in_path", required=True)
	p.add_argument("--out", dest="out_path", required=True)
	p.add_argument("--res", dest="res", type=int, default=DEFAULT_RES)
	p.add_argument("--palette", dest="palette", default=None,
		help="kind de repli (docs/style/tokens.json) pour un slot de materiau sans kind resoluble")
	p.add_argument("--margin-px", dest="margin_px", type=float, default=DEFAULT_MARGIN_PX)
	p.add_argument("--bake-margin-px", dest="bake_margin_px", type=int, default=DEFAULT_BAKE_MARGIN_PX)
	p.add_argument("--samples", dest="samples", type=int, default=DEFAULT_SAMPLES)
	p.add_argument("--seed", dest="seed", default=DEFAULT_SEED)
	p.add_argument("--hue-max-deg", dest="hue_max_deg", type=float, default=DEFAULT_HUE_MAX_DEG)
	p.add_argument("--skip-turntable", dest="skip_turntable", action="store_true",
		help="saute les turntables avant/apres (iteration rapide -- jamais pour une livraison)")
	p.add_argument("--views", dest="views", type=int, default=8)
	p.add_argument("--size", dest="size", type=int, default=512)
	p.add_argument("--turntable-out-dir", dest="turntable_out_dir", default=None,
		help="dossier de base pour les captures avant/apres (defaut : a cote de --out)")
	return p.parse_args(argv)


def main() -> None:
	args = parse_args()
	in_path = os.path.abspath(args.in_path)
	if not os.path.isfile(in_path):
		print(f"PAINT_BAKE_FAIL fichier introuvable: {in_path}")
		sys.exit(1)
	out_path = os.path.abspath(args.out_path)
	try:
		paint_bake(
			in_path, out_path, res=args.res, palette_kind=args.palette,
			margin_px=args.margin_px, bake_margin_px=args.bake_margin_px,
			samples=args.samples, seed=args.seed, hue_max_deg=args.hue_max_deg,
			skip_turntable=args.skip_turntable, turntable_views=args.views, turntable_size=args.size,
			turntable_out_dir=os.path.abspath(args.turntable_out_dir) if args.turntable_out_dir else None,
		)
	except (ValueError, RuntimeError) as exc:
		print(f"PAINT_BAKE_FAIL {exc}")
		sys.exit(1)


if __name__ == "__main__":
	main()
