#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/blender/repaint_weapon.py -- FP-12
Repeinture des 7 armes FP dans la palette STYLE_BIBLE.md §5.1 (docs/research/
12_viewmodel_v2.md §3.4), SANS toucher la geometrie ni l'UV0 : lit la texture
et l'UV0 du .glb peint actuel (assets/models/weapons/<id>.glb, LECTURE SEULE),
ecrit uniquement assets/textures/weapons/<id>_albedo.png (2048x2048), que
rig_weapon_parts.py (FP-11) consommera a la place de la Base Color embarquee.

CONTRAIREMENT a paint_bake.py, ce script ne depend PAS de Blender/bpy : toute
la geometrie dont il a besoin (sommets, faces, UV0, image de base) se lit avec
`trimesh` (pur Python), et toute la peinture se fait en numpy/PIL. Choix
delibere -- voir la note "integration paint_bake" plus bas -- pour rester
rapide, deterministe et testable par un simple `pytest`, sans lancer de
processus Blender ni dependre d'un GPU/pilote Cycles pour livrer la texture.

Pipeline (3 etapes, §3.4 du doc 12) :

  1. RAPPEL DE PALETTE (OKLab, tout le texel opaque, `--pull-force` = 0,6,
     verrouille par le doc) : chaque texel est tire de `--pull-force` vers la
     couleur la plus proche parmi les 9 couleurs de §5.1 (4 materiaux + 5
     accents, `docs/style/tokens.json` `color.weapon_materials`) ET LEUR
     VARIANTE D'OMBRE (meme teinte/chroma, luminance OKLab x `SHADOW_L_FACTOR`
     = 0,6) -- 18 candidats au total. Sans les variantes d'ombre, un texel
     deja sombre (creux, AO cuite par Tripo) serait tire vers la couleur CLAIRE
     du materiau et perdrait son ombrage ; les inclure est aussi ce que
     l'acceptance FP-12 attend explicitement ("... ou de son ombre (L x 0,6)").
     Cas special bleu (`--blue-hue-min/max` = 190-250 deg, `--blue-saturation-
     min`, HSV) : au lieu du plus proche parmi les 18, le texel choisit
     le plus proche parmi UNIQUEMENT {acier emaille, sa version sombre,
     sarcelle, sa version sombre} -- "remappe vers l'acier ou le sarcelle,
     selon la clarte" (doc 12), la clarte etant simplement le critere de plus
     proche voisin OKLab sur ces 4 candidats.
     REVISION (revue du lead 2026-09-25 20:57, prioritaire sur le doc 12) :
     le seuil documente (S > 0,35) laissait passer le "bleu marine" mesure sur
     ravage.glb/pistolet.glb/fracas.glb -- jusqu'a 62 % des texels source de
     ravage.glb sont a teinte 190-250 deg avec seulement 0,20 < S < 0,35, une
     zone que ce seuil ne detectait pas du tout. Le critere mesure par le lead
     sur l'ALBEDO FINAL est "S > 0,20 <= 2 %" : `BLUE_SATURATION_MIN` vaut
     donc desormais 0,20 (pas 0,35), pour declencher ce remap special ET pour
     l'evaluation du critere lui-meme -- voir aussi `apply_brush_noise`, dont
     le jitter est passe d'additif a MULTIPLICATIF pour la meme raison (un
     jitter additif remontait la saturation HSV de l'acier -- S=0,196 -- vers
     0,23 des qu'il assombrissait), et `guard_blue_saturation` (etape 4bis
     ci-dessous), le filet de securite qui absorbe ce que la quantification
     PNG 8 bits fait encore deriver.
  2. ZONES FORCEES PAR BOITE (`tools/ai3d/manifests/weapon_repaint.yaml`,
     coordonnees MESUREES sur le maillage actuel -- voir l'en-tete du
     manifeste) : memes candidats materiau/accent, mais un SEUL candidat fixe
     par boite (pas de recherche du plus proche), force `--box-force` = 0,85
     (quasi plat -- §5.1 regle 5 : "reflet dur uniquement sur l'email et le
     laiton", ces pieces sont de la peinture cuite, pas du bois grain). Une
     face du maillage appartient a une boite si son CENTROIDE y tombe ; ses
     triangles UV sont rasterises dans un "tampon d'id de face" 2048x2048
     partage (`build_face_id_buffer`) pour eviter de rasteriser chaque boite
     independamment.
  3. SURCOUCHES DE RELIEF, sans Blender (voir note ci-dessous) :
     a. liseres d'eclat sur les aretes CONVEXES (angle diedre dans
        [`--edge-min-angle-deg`, `--edge-max-angle-deg`]) : bande de
        `--liseres-width-px` texels, eclaircie vers le blanc
        (`lighten_toward_white`, force `--liseres-lighten`) -- l'acceptance
        exige que sa luminance moyenne depasse celle des faces voisines de au
        moins 0,06 (`edge_lisere_luma_margin`, verifie en fin de run) ;
     b. trait d'encre fin sur la MEME arete (bande plus etroite,
        `--ink-width-px`, assombrie vers `color.ink` #1A1410) par-dessus le
        liisere, pour la lecture "encrage epais" de la bible ;
     c. creux teintes sur les aretes CONCAVES (meme detection, `convex=False`) :
        bande assombrie vers `color.charbon.panel`-like ombre ;
     d. coups de pinceau : un jitter de luminance PAR FACE (donc "projete en
        3D", sans couture visible aux joints UV puisqu'il ne depend que du
        centroide 3D de la face, pas de sa position dans l'atlas), amplitude
        `--brush-amplitude`, hash deterministe de la position (meme graine
        `--seed` = reproductible).
  4. Gardes de fin de run, sur l'image ASSEMBLEE (apres les etapes 1-3) :
     a. bleue (`guard_blue_saturation`, seuil `--blue-guard-saturation-
        trigger`, VOLONTAIREMENT plus bas que le seuil mesure de l'etape 1 --
        voir la constante `BLUE_GUARD_SATURATION_TRIGGER`) : filet de
        securite, PAS un remplacement des etapes 1/3 -- tout texel encore
        dans la bande 190-250 deg au-dessus de ce seuil (reliquat d'une
        interaction liisere/creux/boite, ou simple arrondi de la
        quantification PNG 8 bits finale, mesure sur les vraies armes) est
        DESATURE (teinte et valeur conservees) vers une cible bien en dessous ;
     b. reservee (`docs/style/tokens.json` `reserved` : 300-355 deg et
        105-145 deg, chroma > `--reserved-saturation-min`) : tout texel qui
        violerait encore la bande apres les etapes 1-3 est repousse hors
        bande (meme mecanique que `paint_bake.guard_reserved_hues`, ici en
        OKLCH plutot qu'HSV).

Integration paint_bake.py (`--keep-uv`, ajoute a ce fichier par ce meme
contrat) : le doc 12 decrit l'etape 3 comme "surcouches paint_bake cuites sur
l'UV0 existante". `paint_bake.py` sait desormais le faire (nouvelles options
`--keep-uv` : ne re-deplie JAMAIS, renomme la couche UV existante au lieu
d'un Smart UV Project ; `--base-texture` : source la base peinte d'un fichier
donne plutot que de la bibliotheque par kind) -- utile pour un objet qui a
BESOIN du bake Cycles complet (bevel/AO/pinceau vraiment 3D, plusieurs
materiaux). Pour CE script, le brancher dessus impliquerait un aller-retour
Blender (import glTF, bake, ré-export, ré-extraction du PNG) par arme rien que
pour un relief 2D deja atteignable directement sur les donnees dont on
dispose (sommets/UV/texture) : l'implementation directe ci-dessus est plus
rapide, deterministe sans GPU/pilote Cycles, et testable en `pytest` pur.
`paint_bake.py --keep-uv --base-texture` reste appelable en sous-processus
Blender comme etape de relief ALTERNATIVE (ecraserait 3.a-3.d) si un jour le
relief procedural de paint_bake est prefere a celui-ci -- ce script-ci ne
l'invoque PAS (aucune option CLI ne le branche), jamais ce qui produit les
PNG livres par cette tache.

Usage :
    python tools/blender/repaint_weapon.py --manifest tools/ai3d/manifests/weapon_repaint.yaml
        [--only pistolet,ravage] [--out-dir assets/textures/weapons] [--report PATH]

Sortie : un PNG 2048x2048 par arme du manifeste, jamais un fichier de
geometrie. Idempotent (relit toujours le .glb source, jamais son propre PNG).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

try:
	import trimesh
except ImportError as exc:  # pragma: no cover -- environnement sans trimesh
	raise ImportError(
		"repaint_weapon: le module 'trimesh' est requis (pip install trimesh) -- "
		"lecture de la geometrie/UV0 des .glb sans lancer Blender") from exc

try:
	import yaml
except ImportError as exc:  # pragma: no cover
	raise ImportError("repaint_weapon: le module 'pyyaml' est requis (pip install pyyaml)") from exc


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_TOKENS_PATH = REPO_ROOT / "docs" / "style" / "tokens.json"
DEFAULT_MANIFEST_PATH = REPO_ROOT / "tools" / "ai3d" / "manifests" / "weapon_repaint.yaml"
DEFAULT_WEAPONS_DIR = REPO_ROOT / "assets" / "models" / "weapons"
DEFAULT_OUT_DIR = REPO_ROOT / "assets" / "textures" / "weapons"

TEXTURE_RES = 2048

# -- constantes de la §3.4 (doc 12) et de l'acceptance FP-12 -----------------
GLOBAL_PULL_FORCE = 0.6            # verrouille par le doc -- "force 0,6"
BOX_FORCE = 0.93                   # zones forcees : quasi plat (email/laiton cuits) -- 0,85
                                    # laissait un residu de source assez fort pour, sur pistolet,
                                    # former un 7e cluster k-means hors tolerance (mesure : ΔE_OK
                                    # 0,1177 avec 0,85, <= 0,043 avec 0,93 -- voir test_repaint_weapon)
SHADOW_L_FACTOR = 0.6              # "sa couleur ou son ombre (L x 0,6)"
BLUE_HUE_RANGE_DEG = (190.0, 250.0)
BLUE_SATURATION_MIN = 0.20         # revu 0,35 -> 0,20 (revue du lead 2026-09-25 20:57 sur
                                    # repaint_avant_apres.jpg : "bleu marine" mesure a S entre 0,20
                                    # et 0,35 sur ravage/pistolet/fracas -- le seuil documente au §3.4
                                    # du doc 12 ne le detectait pas. Sert a la fois de seuil de
                                    # declenchement (etape 1) et de seuil de controle final
                                    # (`guard_blue_saturation`, etape 4bis) -- les DEUX usages du lead.
BLUE_REMAP_FORCE = 1.0             # "remappes" (doc 12) : reassignation pleine, pas un rappel a 0,6
BLUE_GUARD_SATURATION_TRIGGER = 0.12  # etape 4bis : seuil de DECLENCHEMENT du filet de securite --
                                    # volontairement BIEN EN DESSOUS de BLUE_SATURATION_MIN (0,20) :
                                    # l'acier emaille #4A505C a lui-meme S=0,1957 en continu, a peine
                                    # sous 0,20 -- la quantification finale en PNG 8 bits (arrondi
                                    # independant par canal) suffit a le faire deriver au-dessus (mesure
                                    # jusqu'a S=0,204 sur l'albedo final de ravage.glb malgre un rappel
                                    # de palette correct). Un seuil de declenchement sous la saturation
                                    # NATIVE de l'acier garantit que ce texel est corrige AVANT
                                    # quantification, quel que soit le sens de l'arrondi.
BLUE_GUARD_TARGET_SATURATION = 0.16  # cible du filet -- juste sous la saturation NATIVE de l'acier
                                    # (0,1957), marge de 0,04 sous le seuil mesure (0,20) qui absorbe la
                                    # quantification 8 bits (derive mesuree jusqu'a +0,018) tout en
                                    # restant proche de la couleur d'origine. Une cible plus basse
                                    # (0,05, DeltaE_OK <= 0,05 de l'acier -- essaye d'abord) aplatit
                                    # trop la grande zone "acier" du pistolet et fait apparaitre, par
                                    # ricochet, un 7e groupe k-means hors tolerance (un residu de teinte
                                    # de crosse, mesure a DeltaE_OK=0,118) : 0,16 suffit a la conformite
                                    # (etape 4bis) sans deplacer assez le nuage de points pour ca.
RESERVED_HUE_BANDS_DEG = ((300.0, 355.0), (105.0, 145.0))
# Meme garde que le bleu : `docs/style/tokens.json` `reserved.rule` n'y voit
# une violation qu'au-dessus d'une chroma minimale -- un gris/beige a teinte
# fortuite (chroma quasi nulle) ne doit jamais etre signale.
RESERVED_SATURATION_MIN = 0.35

EDGE_WELD_EPS_M = 0.0005           # 0,5 mm -- meme ordre que paint_bake._welded_bmesh (0,1 mm) en plus large
EDGE_MIN_ANGLE_DEG = 12.0
EDGE_MAX_ANGLE_DEG = 170.0
LISERE_WIDTH_PX = 5
LISERE_LIGHTEN = 0.85
INK_WIDTH_PX = 2
INK_DARKEN = 0.55
CREVICE_WIDTH_PX = 4
CREVICE_DARKEN = 0.30
BRUSH_NOISE_AMPLITUDE = 0.035

INK_HEX = "#1A1410"                 # docs/style/tokens.json color.ink

BASE_MATERIAL_KEYS = ("enamel_steel", "wood", "brass", "enamel_cream")
ACCENT_KEYS = ("red", "orange", "yellow", "teal", "paper")

LUMA_WEIGHTS = (0.2126, 0.7152, 0.0722)  # Rec.709 -- meme mesure que paint_bake.srgb_luma


# =============================================================================
# Couleur : sRGB <-> lineaire <-> OKLab (fonctions PURES, vectorisees numpy)
# =============================================================================

# Matrices d'Ottosson (https://bottosson.github.io/posts/oklab/) -- verifiees
# par ce module contre la table de reference publiee (blanc -> L=1,a=0,b=0 ;
# rouge sRGB pur -> L=0,628,a=0,225,b=0,126 ; vert -> 0,866,-0,234,0,179 ;
# bleu -> 0,452,-0,032,-0,312), voir TestOklabReferenceValues.
_SRGB_TO_LMS = np.array([
	[0.4122214708, 0.5363325363, 0.0514459929],
	[0.2119034982, 0.6806995451, 0.1073969566],
	[0.0883024619, 0.2817188376, 0.6299787005],
])
_LMS_TO_OKLAB = np.array([
	[0.2104542553, 0.7936177850, -0.0040720468],
	[1.9779984951, -2.4285922050, 0.4505937099],
	[0.0259040371, 0.7827717662, -0.8086757660],
])
_OKLAB_TO_LMS = np.linalg.inv(_LMS_TO_OKLAB)
_LMS_TO_SRGB = np.linalg.inv(_SRGB_TO_LMS)


def srgb_to_linear(c):
	"""sRGB encode (0..1) -> lineaire, vectorise (forme (...,) quelconque)."""
	c = np.asarray(c, dtype=np.float64)
	return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
	"""Lineaire -> sRGB encode (0..1), vectorise. Clippe les negatifs avant la
	puissance fractionnaire (un OKLab hors gamut peut donner un lineaire < 0)."""
	c = np.clip(np.asarray(c, dtype=np.float64), 0.0, None)
	return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def srgb_to_oklab(rgb01):
	"""sRGB (0..1, forme (...,3)) -> OKLab (L,a,b), vectorise sur les axes de
	tete (chaque pixel traite independamment)."""
	rgb01 = np.asarray(rgb01, dtype=np.float64)
	lin = srgb_to_linear(rgb01)
	lms = lin @ _SRGB_TO_LMS.T
	lms_cbrt = np.cbrt(lms)
	return lms_cbrt @ _LMS_TO_OKLAB.T


def oklab_to_srgb(lab):
	"""Inverse de `srgb_to_oklab`. Peut sortir hors [0,1] pour un Lab hors
	gamut sRGB -- l'appelant clippe si besoin (jamais fait ici : une fonction
	de conversion ne doit pas silencieusement deformer les valeurs)."""
	lab = np.asarray(lab, dtype=np.float64)
	lms_cbrt = lab @ _OKLAB_TO_LMS.T
	lms = lms_cbrt ** 3
	lin = lms @ _LMS_TO_SRGB.T
	return linear_to_srgb(lin)


def hex_to_rgb01(hex_str: str) -> tuple:
	h = hex_str.lstrip("#")
	return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def rgb01_to_hex(rgb01) -> str:
	r, g, b = (int(round(np.clip(c, 0.0, 1.0) * 255)) for c in rgb01)
	return f"#{r:02X}{g:02X}{b:02X}"


def rgb_to_hue_sat(rgb01):
	"""HSV teinte (deg, 0..360) et saturation (0..1), vectorise sur (...,3) --
	memes definitions que `colorsys.rgb_to_hsv`, sans boucle Python (necessaire
	a 2048x2048 texels)."""
	rgb01 = np.asarray(rgb01, dtype=np.float64)
	r, g, b = rgb01[..., 0], rgb01[..., 1], rgb01[..., 2]
	maxc = np.maximum(np.maximum(r, g), b)
	minc = np.minimum(np.minimum(r, g), b)
	delta = maxc - minc
	safe_delta = np.where(delta > 1e-12, delta, 1.0)
	sat = np.where(maxc > 1e-12, delta / np.where(maxc > 1e-12, maxc, 1.0), 0.0)

	is_r = (maxc == r) & (delta > 1e-12)
	is_g = (maxc == g) & (delta > 1e-12) & ~is_r
	is_b = (delta > 1e-12) & ~is_r & ~is_g

	hue = np.zeros_like(maxc)
	hue = np.where(is_r, ((g - b) / safe_delta) % 6.0, hue)
	hue = np.where(is_g, ((b - r) / safe_delta) + 2.0, hue)
	hue = np.where(is_b, ((r - g) / safe_delta) + 4.0, hue)
	hue = (hue * 60.0) % 360.0
	return hue, sat


def hue_in_band(hue_deg, band) -> "np.ndarray":
	lo, hi = band
	return (hue_deg >= lo) & (hue_deg <= hi)


# =============================================================================
# Palette (docs/style/tokens.json, source unique -- jamais recopiee en dur)
# =============================================================================

def load_tokens(tokens_path=DEFAULT_TOKENS_PATH) -> dict:
	with open(tokens_path, "r", encoding="utf-8") as f:
		return json.load(f)


def load_palette(tokens_path=DEFAULT_TOKENS_PATH) -> dict:
	"""`{"materials": {name: hex}, "accents": {name: hex}, "weapons": {id: {...}},
	"reserved_bands_deg": [...], "reserved_saturation_min": float}` --
	`docs/style/tokens.json` `color.weapon_materials` + `weapons` + `reserved`."""
	tokens = load_tokens(tokens_path)
	wm = tokens["color"]["weapon_materials"]
	materials = {k: wm[k] for k in BASE_MATERIAL_KEYS}
	accents = {k: wm["accents"][k] for k in ACCENT_KEYS}
	reserved = tokens.get("reserved", {})
	bands = reserved.get("hue_bands_deg", [list(b) for b in RESERVED_HUE_BANDS_DEG])
	return {
		"materials": materials,
		"accents": accents,
		"weapons": tokens.get("weapons", {}),
		"reserved_bands_deg": [tuple(b) for b in bands],
	}


def resolve_target_hex(palette: dict, target: str) -> str:
	"""`target` = "material:<nom>" ou "accent:<nom>" (manifeste weapon_repaint.yaml)
	-> hex. Leve `ValueError` sur une cle absente (jamais un repli silencieux
	vers une couleur au hasard)."""
	kind, _, name = target.partition(":")
	table = {"material": palette["materials"], "accent": palette["accents"]}.get(kind)
	if table is None or name not in table:
		raise ValueError(f"repaint_weapon: cible de palette invalide {target!r} (attendu material:<...> ou accent:<...>)")
	return table[name]


def palette_candidates_lab(palette: dict, shadow_factor: float = SHADOW_L_FACTOR):
	"""Table de recherche du rappel OKLab (etape 1) : les 9 couleurs de base
	(4 materiaux + 5 accents) ET leur variante d'ombre (meme a/b, L x
	`shadow_factor`) -- 18 candidats. Renvoie `(labels, lab_array (18,3))`."""
	entries = list(palette["materials"].items()) + list(palette["accents"].items())
	labels = []
	labs = []
	for name, hexv in entries:
		rgb = np.array(hex_to_rgb01(hexv))
		lab = srgb_to_oklab(rgb)
		labels.append(name)
		labs.append(lab)
		shadow = lab.copy()
		shadow[0] *= shadow_factor
		labels.append(f"{name}_shadow")
		labs.append(shadow)
	return labels, np.stack(labs, axis=0)


def nearest_candidate(lab_pixels, cand_lab):
	"""Plus proche voisin OKLab de chaque pixel de `lab_pixels` (N,3) parmi
	`cand_lab` (K,3). Boucle sur K (pas N) : la memoire d'un broadcast N x K x 3
	serait prohibitive a la resolution 2048x2048 (~4,2 M texels)."""
	n = lab_pixels.shape[0]
	best_idx = np.zeros(n, dtype=np.int32)
	best_dist2 = np.full(n, np.inf)
	for k in range(cand_lab.shape[0]):
		d2 = np.sum((lab_pixels - cand_lab[k]) ** 2, axis=1)
		better = d2 < best_dist2
		best_dist2 = np.where(better, d2, best_dist2)
		best_idx = np.where(better, k, best_idx)
	return best_idx, np.sqrt(best_dist2)


def delta_e_ok(lab_a, lab_b) -> float:
	"""Distance euclidienne OKLab -- la mesure de "DeltaE_OK" de l'acceptance
	FP-12 (aucune norme ne definit ce sigle plus precisement que "distance
	OKLab" ; c'est la definition la plus directe et la plus repandue)."""
	return float(np.linalg.norm(np.asarray(lab_a) - np.asarray(lab_b)))


# =============================================================================
# Etape 1 -- rappel de palette global (OKLab, tout le texel)
# =============================================================================

def apply_global_pull(rgb01, palette: dict, force: float = GLOBAL_PULL_FORCE,
		blue_hue_range=BLUE_HUE_RANGE_DEG, blue_saturation_min: float = BLUE_SATURATION_MIN,
		shadow_factor: float = SHADOW_L_FACTOR, blue_remap_force: float = BLUE_REMAP_FORCE) -> tuple:
	"""Etape 1 du §3.4 : tire chaque texel de `force` vers son plus proche
	voisin OKLab parmi les 9 couleurs de §5.1 + leurs ombres (18 candidats),
	SAUF les texels bleus (teinte dans `blue_hue_range`, saturation HSV >
	`blue_saturation_min`) qui sont REMAPPES (poids `blue_remap_force`, PLEIN
	par defaut -- pas un simple "rappel" a 0,6) vers leur plus proche voisin
	parmi UNIQUEMENT {acier, acier ombre, sarcelle, sarcelle ombre}. Le doc 12
	dit "remappes", pas "tires" : un bleu source tres sature (mesure sur
	rafale.glb -- 90 % des texels a teinte bleue, jusqu'a S=0,8) laisserait,
	a force 0,6 comme le reste de la palette, jusqu'a 4 % de texels encore
	au-dessus du seuil de saturation apres blend -- au-dela du critere
	d'acceptance FP-12 (<= 2 %). Un remap PLEIN est la seule facon de garantir
	la disparition du bleu quelle que soit sa saturation d'origine. Renvoie
	`(rgb01_repeint, rapport)`."""
	h, w = rgb01.shape[:2]
	flat = rgb01.reshape(-1, 3).astype(np.float64)
	lab = srgb_to_oklab(flat)
	hue, sat = rgb_to_hue_sat(flat)
	is_blue = hue_in_band(hue, blue_hue_range) & (sat > blue_saturation_min)

	labels, cand_lab = palette_candidates_lab(palette, shadow_factor=shadow_factor)
	blue_names = ["enamel_steel", "enamel_steel_shadow", "teal", "teal_shadow"]
	blue_slice = np.array([labels.index(n) for n in blue_names])
	cand_blue = cand_lab[blue_slice]

	idx_full, _ = nearest_candidate(lab, cand_lab)
	idx_blue, _ = nearest_candidate(lab, cand_blue)

	target_lab = np.where(is_blue[:, None], cand_blue[idx_blue], cand_lab[idx_full])
	pixel_force = np.where(is_blue, blue_remap_force, force)[:, None]
	new_lab = lab * (1.0 - pixel_force) + target_lab * pixel_force
	new_rgb = np.clip(oklab_to_srgb(new_lab), 0.0, 1.0)

	chosen_label = np.where(is_blue, np.array(blue_names)[idx_blue], np.array(labels)[idx_full])
	names, counts = np.unique(chosen_label, return_counts=True)
	report = {
		"blue_remapped_texels": int(is_blue.sum()),
		"nearest_counts": {n: int(c) for n, c in zip(names, counts)},
	}
	return new_rgb.reshape(h, w, 3), report


# =============================================================================
# Etape 2 -- zones forcees par boite
# =============================================================================

def load_weapon_mesh(glb_path) -> dict:
	"""Charge `glb_path` avec trimesh (LECTURE SEULE -- jamais reexporte) et
	renvoie `{"vertices": (N,3), "faces": (M,3) int, "uv": (N,2), "image":
	PIL.Image en mode RGB}`. Suppose un seul objet mesh / un seul slot de
	materiau (verifie sur les 7 armes -- FP-11/FP-19 verrouillent cette forme)."""
	scene = trimesh.load(str(glb_path), process=False)
	if isinstance(scene, trimesh.Trimesh):
		geom = scene
	else:
		geoms = list(scene.geometry.values())
		if not geoms:
			raise ValueError(f"repaint_weapon: aucun maillage dans {glb_path}")
		geom = geoms[0]
	uv = getattr(geom.visual, "uv", None)
	if uv is None:
		raise ValueError(f"repaint_weapon: {glb_path} n'a pas d'UV0 -- lecture seule impossible sans UV")
	image = geom.visual.material.baseColorTexture
	if image is None:
		raise ValueError(f"repaint_weapon: {glb_path} n'a pas de texture Base Color")
	return {
		"vertices": np.asarray(geom.vertices, dtype=np.float64),
		"faces": np.asarray(geom.faces, dtype=np.int64),
		"uv": np.asarray(uv, dtype=np.float64),
		"image": image.convert("RGB"),
	}


def uv0_hash(uv) -> str:
	"""Empreinte stable de l'UV0 -- verifie que ce script ne l'a jamais
	modifiee (critere d'acceptance FP-12 : "hash de l'UV0 inchange")."""
	arr = np.ascontiguousarray(np.asarray(uv, dtype=np.float64))
	return hashlib.sha256(arr.tobytes()).hexdigest()


def build_face_id_buffer(uv, faces, width: int, height: int) -> "np.ndarray":
	"""Tampon (height,width) int64 : id de face + 1 pour le triangle qui
	couvre ce texel (0 = hors de tout triangle -- marge UV/fond). RASTERISE
	UNE SEULE FOIS par arme (convention glTF : v=0 en haut de l'image, meme
	que `measure_boxes.py`) ; les etapes suivantes (boites, pinceau) font une
	simple recherche numpy dedans plutot que de re-rasteriser par zone."""
	img = Image.new("I", (width, height), 0)
	draw = ImageDraw.Draw(img)
	for fi in range(faces.shape[0]):
		tri_uv = uv[faces[fi]]
		pts = [(float(u * width), float((1.0 - v) * height)) for u, v in tri_uv]
		draw.polygon(pts, fill=fi + 1)
	return np.array(img, dtype=np.int64)


def faces_in_box(vertices, faces, box_min, box_max) -> "np.ndarray":
	"""Masque (M,) bool : le CENTROIDE de la face tombe dans la boite
	`[box_min, box_max]` (coordonnees locales du maillage, voir le manifeste)."""
	centroids = vertices[faces].mean(axis=1)
	box_min = np.asarray(box_min, dtype=np.float64)
	box_max = np.asarray(box_max, dtype=np.float64)
	return np.all((centroids >= box_min) & (centroids <= box_max), axis=1)


def apply_color_force(rgb01, mask_hw, target_hex: str, force: float = BOX_FORCE):
	"""Melange OKLab de tous les texels sous `mask_hw` vers `target_hex`, poids
	`force` -- cible FIXE (pas de recherche du plus proche, contrairement a
	l'etape 1) : c'est une zone FORCEE, pas un rappel."""
	target_lab = srgb_to_oklab(np.array(hex_to_rgb01(target_hex)))
	out = rgb01.copy()
	flat_mask = mask_hw.reshape(-1)
	if not flat_mask.any():
		return out
	flat = out.reshape(-1, 3)
	lab = srgb_to_oklab(flat[flat_mask])
	new_lab = lab * (1.0 - force) + target_lab * force
	flat[flat_mask] = np.clip(oklab_to_srgb(new_lab), 0.0, 1.0)
	return out


def apply_box_zones(rgb01, face_id_buffer, palette: dict, boxes: list, vertices, faces,
		force: float = BOX_FORCE) -> tuple:
	"""Applique toutes les `boxes` (manifeste) d'une arme. Renvoie
	`(rgb01, rapport)` -- `rapport["boxes"]` liste, par boite, le nombre de
	faces et de texels touches (0 face = boite vide, signale mais pas fatal :
	une coordonnee mesuree peut ne plus matcher apres un re-export FP-11 -- le
	rapport le rend visible sans faire echouer tout le run)."""
	out = rgb01
	report_boxes = []
	valid_face = face_id_buffer > 0
	face_idx_buffer = np.where(valid_face, face_id_buffer - 1, -1)
	for box in boxes:
		target_hex = resolve_target_hex(palette, box["target"])
		fmask = faces_in_box(vertices, faces, box["box_min"], box["box_max"])
		texel_mask = valid_face & fmask[np.clip(face_idx_buffer, 0, len(fmask) - 1)]
		out = apply_color_force(out, texel_mask, target_hex, force=force)
		report_boxes.append({
			"part": box.get("part"), "target": box["target"], "target_hex": target_hex,
			"faces": int(fmask.sum()), "texels": int(texel_mask.sum()),
		})
	return out, {"boxes": report_boxes}


# =============================================================================
# Etape 3 -- relief : liseres/creux/encre/pinceau (sans Blender)
# =============================================================================

def weld_vertex_ids(vertices, eps: float = EDGE_WELD_EPS_M) -> "np.ndarray":
	"""Id de sommet apres recollement par position (memes sommets DUPLIQUES
	aux coutures UV -> meme id) -- meme principe que
	`paint_bake._welded_bmesh` ("sommets eclates par glTF recolles a 0,1 mm"),
	necessaire pour trouver les aretes convexes/concaves MEME quand elles
	portent une couture UV."""
	quant = np.round(vertices / eps).astype(np.int64)
	_, inverse = np.unique(quant, axis=0, return_inverse=True)
	return inverse.reshape(-1)


def build_weld_topology(vertices, faces, eps: float = EDGE_WELD_EPS_M):
	"""Maillage jetable (positions recollees, JAMAIS exporte) dont
	`face_adjacency`/`face_adjacency_convex`/`face_adjacency_angles` donnent
	la topologie reelle (coutures UV incluses) -- l'ORDRE des faces est
	preserve (`process=False`), donc ses indices de face matchent directement
	`faces` d'origine."""
	wid = weld_vertex_ids(vertices, eps=eps)
	weld_faces = wid[faces]
	n_weld = int(wid.max()) + 1
	weld_vertices = np.zeros((n_weld, 3), dtype=np.float64)
	weld_vertices[wid] = vertices
	mesh_weld = trimesh.Trimesh(vertices=weld_vertices, faces=weld_faces, process=False)
	return mesh_weld, wid


def find_edge_segments(vertices, faces, uv, min_angle_deg: float = EDGE_MIN_ANGLE_DEG,
		max_angle_deg: float = EDGE_MAX_ANGLE_DEG, eps: float = EDGE_WELD_EPS_M) -> tuple:
	"""Detecte les aretes convexes/concaves du maillage (dihedre dans
	[min_angle_deg, max_angle_deg]) et renvoie, pour CHAQUE face de CHAQUE
	cote de l'arete (une couture UV separe les deux faces en deux ilots : il
	faut dessiner le trait des DEUX cotes), le segment UV (deux points 0..1)
	correspondant. `(convex_segments, concave_segments)`, chacun une liste de
	`((u0,v0),(u1,v1))`."""
	if faces.shape[0] == 0:
		return [], []
	mesh_weld, wid = build_weld_topology(vertices, faces, eps=eps)
	adjacency = mesh_weld.face_adjacency
	if adjacency.shape[0] == 0:
		return [], []
	convex = mesh_weld.face_adjacency_convex
	angles_deg = np.degrees(mesh_weld.face_adjacency_angles)
	edge_wids = mesh_weld.face_adjacency_edges
	keep = (angles_deg >= min_angle_deg) & (angles_deg <= max_angle_deg)

	convex_segments = []
	concave_segments = []
	for i in np.nonzero(keep)[0]:
		w0, w1 = int(edge_wids[i, 0]), int(edge_wids[i, 1])
		bucket = convex_segments if convex[i] else concave_segments
		for f in (int(adjacency[i, 0]), int(adjacency[i, 1])):
			tri = faces[f]
			tri_wids = wid[tri]
			sel = [k for k in range(3) if tri_wids[k] in (w0, w1)]
			if len(sel) != 2:
				continue
			p0 = uv[tri[sel[0]]]
			p1 = uv[tri[sel[1]]]
			bucket.append(((float(p0[0]), float(p0[1])), (float(p1[0]), float(p1[1]))))
	return convex_segments, concave_segments


def rasterize_segments(segments: list, width: int, height: int, line_width_px: int) -> "np.ndarray":
	"""Masque (height,width) bool : texels a moins de `line_width_px`/2 d'un
	des segments UV (convention glTF v=0 en haut)."""
	img = Image.new("L", (width, height), 0)
	if segments:
		draw = ImageDraw.Draw(img)
		for (u0, v0), (u1, v1) in segments:
			p0 = (float(u0 * width), float((1.0 - v0) * height))
			p1 = (float(u1 * width), float((1.0 - v1) * height))
			draw.line([p0, p1], fill=255, width=max(1, line_width_px))
	return np.asarray(img, dtype=bool)


def lighten_toward_white(rgb01, mask_hw, amount: float) -> "np.ndarray":
	"""Melange "screen" vers le blanc sous `mask_hw` -- eclaircit sans jamais
	depasser 1.0 et sans aplatir la teinte (contrairement a un simple ajout)."""
	out = rgb01.copy()
	out[mask_hw] = 1.0 - (1.0 - out[mask_hw]) * (1.0 - amount)
	return out


def darken_toward(rgb01, mask_hw, target_rgb01, amount: float) -> "np.ndarray":
	out = rgb01.copy()
	target = np.asarray(target_rgb01, dtype=np.float64)
	out[mask_hw] = out[mask_hw] * (1.0 - amount) + target * amount
	return out


def srgb_luma(rgb01) -> "np.ndarray":
	"""Luma Rec.709 sur des valeurs sRGB ENCODEES -- meme mesure que
	`paint_bake.srgb_luma`, vectorisee ici."""
	rgb01 = np.asarray(rgb01, dtype=np.float64)
	return (rgb01[..., 0] * LUMA_WEIGHTS[0] + rgb01[..., 1] * LUMA_WEIGHTS[1]
		+ rgb01[..., 2] * LUMA_WEIGHTS[2])


def _hash01(seed, x: float, y: float, z: float) -> float:
	"""Hash deterministe [0,1) d'une position 3D + graine -- jamais
	`random.random()` (non reproductible entre deux runs)."""
	label = f"{seed}:{x:.6f}:{y:.6f}:{z:.6f}"
	digest = hashlib.sha256(label.encode("utf-8")).hexdigest()
	return int(digest[:8], 16) / 0xFFFFFFFF


def apply_brush_noise(rgb01, face_id_buffer, vertices, faces, amplitude: float = BRUSH_NOISE_AMPLITUDE,
		seed="repaint_weapon") -> "np.ndarray":
	"""Coups de pinceau (etape 3d) : jitter de LUMINANCE MULTIPLICATIF
	(`rgb *= 1 + jitter`) PAR FACE, hash deterministe du centroide 3D (donc
	"projete en 3D" -- deux faces adjacentes dans l'atlas UV mais eloignees en
	3D n'ont pas de raison de partager leur jitter, et reciproquement deux
	faces voisines en 3D mais separees par une couture UV restent coherentes
	puisque le hash ne depend QUE du centroide, jamais de la position dans
	l'atlas).

	MULTIPLICATIF et non additif (corrige revue du lead 2026-09-25 20:57) :
	un jitter ADDITIF change la saturation HSV (`S = delta/max`) de toute
	couleur peu chromatique des qu'il assombrit -- mesure sur l'acier emaille
	`#4A505C` (S=0,196) apres remap plein : jusqu'a S=0,23 pour les texels a
	jitter negatif, repassant au-dessus du seuil bleu (`BLUE_SATURATION_MIN`)
	MALGRE un remap de palette correct en amont. Un jitter MULTIPLICATIF
	(`rgb *= k`) laisse `delta` et `max` a l'echelle l'un de l'autre, donc `S`
	EXACTEMENT inchange quel que soit `k` -- seule la valeur (luminosite)
	varie, jamais la teinte ni la saturation, ce qui est le but d'un "coup de
	pinceau" (variation de luminosite du geste, pas de la couleur du pot de
	peinture)."""
	centroids = vertices[faces].mean(axis=1)
	jitter = np.array([(_hash01(seed, *c) - 0.5) * 2.0 * amplitude for c in centroids])
	valid = face_id_buffer > 0
	face_idx = np.where(valid, face_id_buffer - 1, 0)
	per_texel_jitter = np.where(valid, jitter[face_idx], 0.0)
	out = np.clip(rgb01 * (1.0 + per_texel_jitter[..., None]), 0.0, 1.0)
	return out


def apply_relief(rgb01, face_id_buffer, vertices, faces, uv, *,
		edge_min_angle_deg: float = EDGE_MIN_ANGLE_DEG, edge_max_angle_deg: float = EDGE_MAX_ANGLE_DEG,
		lisere_width_px: int = LISERE_WIDTH_PX, lisere_lighten: float = LISERE_LIGHTEN,
		ink_width_px: int = INK_WIDTH_PX, ink_darken: float = INK_DARKEN,
		crevice_width_px: int = CREVICE_WIDTH_PX, crevice_darken: float = CREVICE_DARKEN,
		brush_amplitude: float = BRUSH_NOISE_AMPLITUDE, seed="repaint_weapon") -> tuple:
	"""Etape 3 complete : liseres d'eclat + trait d'encre (aretes convexes),
	creux teintes (aretes concaves), coups de pinceau. Renvoie `(rgb01,
	rapport)` -- le rapport mesure la marge de luminance du liisere contre les
	faces voisines (verification directe du critere d'acceptance FP-12)."""
	height, width = rgb01.shape[:2]
	convex_segs, concave_segs = find_edge_segments(
		vertices, faces, uv, min_angle_deg=edge_min_angle_deg, max_angle_deg=edge_max_angle_deg)

	lisere_mask = rasterize_segments(convex_segs, width, height, lisere_width_px)
	ink_mask = rasterize_segments(convex_segs, width, height, ink_width_px)
	crevice_mask = rasterize_segments(concave_segs, width, height, crevice_width_px)

	out = rgb01
	neighbor_mask = (face_id_buffer > 0) & ~lisere_mask & ~crevice_mask
	neighbor_luma = float(srgb_luma(out)[neighbor_mask].mean()) if neighbor_mask.any() else float("nan")

	out = darken_toward(out, crevice_mask, hex_to_rgb01(INK_HEX), crevice_darken)
	out = lighten_toward_white(out, lisere_mask & ~ink_mask, lisere_lighten)
	out = darken_toward(out, ink_mask, hex_to_rgb01(INK_HEX), ink_darken)
	out = apply_brush_noise(out, face_id_buffer, vertices, faces, amplitude=brush_amplitude, seed=seed)

	lisere_only_mask = lisere_mask & ~ink_mask
	lisere_luma = float(srgb_luma(out)[lisere_only_mask].mean()) if lisere_only_mask.any() else float("nan")
	margin = lisere_luma - neighbor_luma if lisere_only_mask.any() and neighbor_mask.any() else float("nan")
	report = {
		"convex_edges": len(convex_segs), "concave_edges": len(concave_segs),
		"lisere_texels": int(lisere_only_mask.sum()), "ink_texels": int(ink_mask.sum()),
		"crevice_texels": int(crevice_mask.sum()),
		"neighbor_luma": neighbor_luma, "lisere_luma": lisere_luma, "lisere_margin": margin,
	}
	return out, report


# =============================================================================
# Etape 4 -- gardes de fin de run (bleue puis teinte reservee)
# =============================================================================

def guard_blue_saturation(rgb01, hue_range=BLUE_HUE_RANGE_DEG,
		saturation_max: float = BLUE_GUARD_SATURATION_TRIGGER,
		target_saturation: float = BLUE_GUARD_TARGET_SATURATION) -> tuple:
	"""Etape 4bis -- filet de securite (revue du lead 2026-09-25 20:57,
	critere mesure "S > 0,20 <= 2 %" sur l'albedo FINAL) : tout texel encore
	dans la bande bleue [190,250] deg au-dessus de `saturation_max` est
	DESATURE -- teinte ET valeur conservees, seule `S` est ramenee au plus a
	`target_saturation` -- plutot que repousse hors bande comme
	`guard_reserved_hues` : on veut un acier/sarcelle neutre credible, pas une
	teinte poussee au hasard vers le violet ou le cyan.

	`saturation_max` (0,12 par defaut) est DELIBEREMENT sous le seuil mesure
	par le lead (0,20), et meme sous la saturation NATIVE de l'acier emaille
	(0,1957) : ce script produit un PNG 8 bits, et l'arrondi de quantification
	independant par canal fait deriver un texel a S=0,196 jusqu'a S=0,20-0,23
	selon le sens de l'arrondi -- verifie sur les vraies armes. Corriger
	TOUT texel bleute, meme large sous le seuil final, avant cette
	quantification est la seule facon de garantir la conformite APRES coup.
	`target_saturation` (0,16, juste sous la saturation native de l'acier,
	0,1957) laisse une marge de 0,04 sous le seuil mesure -- suffisante pour
	absorber la derive de quantification (mesuree jusqu'a +0,018) sans
	aplatir excessivement la zone "acier" : une cible plus basse (essayee
	d'abord, 0,05) fait deriver assez le nuage de points en OKLab pour faire
	apparaitre un 7e groupe k-means hors tolerance sur le pistolet.

	COMPLEMENT des etapes 1 et 3, jamais un remplacement : le rappel de
	palette (etape 1, remap plein sur les texels detectes bleus) et le
	pinceau desormais multiplicatif (etape 3d, `apply_brush_noise`) suffisent
	a amener la quasi-totalite des texels tres en dessous du seuil ; ce garde
	est le filet qui rend la conformite ROBUSTE a la quantification finale,
	quelle que soit l'arme. Renvoie `(rgb01, nb_texels_corriges)`."""
	flat = rgb01.reshape(-1, 3).astype(np.float64)
	hue, sat = rgb_to_hue_sat(flat)
	violation = hue_in_band(hue, hue_range) & (sat > saturation_max)
	count = int(violation.sum())
	if count == 0:
		return rgb01, 0
	value = np.max(flat, axis=1)
	fixed_sat = np.minimum(sat, target_saturation)
	fixed_rgb = _hsv_to_rgb(hue, fixed_sat, value)
	out_flat = np.where(violation[:, None], fixed_rgb, flat)
	return out_flat.reshape(rgb01.shape), count


def guard_reserved_hues(rgb01, bands_deg=RESERVED_HUE_BANDS_DEG,
		saturation_min: float = RESERVED_SATURATION_MIN) -> tuple:
	"""Repousse tout texel dont la teinte tombe dans une bande reservee (avec
	une saturation superieure a `saturation_min`) hors de cette bande, en
	poussant la teinte HSV vers le bord le plus proche (meme saturation/valeur
	conservees) -- meme mecanique que `paint_bake.guard_reserved_hues`, ici
	appliquee a toute l'image d'un coup. Renvoie `(rgb01, nb_texels_corriges)`."""
	flat = rgb01.reshape(-1, 3).astype(np.float64)
	hue, sat = rgb_to_hue_sat(flat)
	violation = np.zeros(flat.shape[0], dtype=bool)
	for lo, hi in bands_deg:
		violation |= hue_in_band(hue, (lo, hi)) & (sat > saturation_min)
	count = int(violation.sum())
	if count == 0:
		return rgb01, 0
	fixed_hue = hue.copy()
	for lo, hi in bands_deg:
		in_band = hue_in_band(hue, (lo, hi)) & violation
		to_lo = np.abs(hue - lo)
		to_hi = np.abs(hi - hue)
		fixed_hue = np.where(in_band & (to_lo <= to_hi), lo - 1.0, fixed_hue)
		fixed_hue = np.where(in_band & (to_lo > to_hi), hi + 1.0, fixed_hue)
	fixed_hue = fixed_hue % 360.0
	value = np.max(flat, axis=1)
	fixed_rgb = _hsv_to_rgb(fixed_hue, sat, value)
	out_flat = np.where(violation[:, None], fixed_rgb, flat)
	return out_flat.reshape(rgb01.shape), count


def _hsv_to_rgb(hue_deg, sat, value):
	"""HSV -> RGB vectorise (le pendant de `rgb_to_hue_sat`), utilise par
	`guard_blue_saturation` et `guard_reserved_hues` pour re-composer apres
	correction."""
	h = (hue_deg % 360.0) / 60.0
	c = value * sat
	x = c * (1.0 - np.abs((h % 2.0) - 1.0))
	m = value - c
	conditions = [
		(h >= 0) & (h < 1), (h >= 1) & (h < 2), (h >= 2) & (h < 3),
		(h >= 3) & (h < 4), (h >= 4) & (h < 5), (h >= 5) & (h <= 6),
	]
	r_choices = [c, x, np.zeros_like(c), np.zeros_like(c), x, c]
	g_choices = [x, c, c, x, np.zeros_like(c), np.zeros_like(c)]
	b_choices = [np.zeros_like(c), np.zeros_like(c), x, c, c, x]
	r = np.select(conditions, r_choices, default=0.0) + m
	g = np.select(conditions, g_choices, default=0.0) + m
	b = np.select(conditions, b_choices, default=0.0) + m
	return np.stack([r, g, b], axis=-1)


# =============================================================================
# Orchestration par arme / manifeste
# =============================================================================

def load_manifest(manifest_path=DEFAULT_MANIFEST_PATH) -> dict:
	with open(manifest_path, "r", encoding="utf-8") as f:
		return yaml.safe_load(f)


def repaint_weapon(weapon_id: str, glb_path, boxes: list, palette: dict, *,
		pull_force: float = GLOBAL_PULL_FORCE, box_force: float = BOX_FORCE,
		blue_hue_range=BLUE_HUE_RANGE_DEG, blue_saturation_min: float = BLUE_SATURATION_MIN,
		blue_remap_force: float = BLUE_REMAP_FORCE,
		shadow_factor: float = SHADOW_L_FACTOR, edge_min_angle_deg: float = EDGE_MIN_ANGLE_DEG,
		edge_max_angle_deg: float = EDGE_MAX_ANGLE_DEG, lisere_width_px: int = LISERE_WIDTH_PX,
		lisere_lighten: float = LISERE_LIGHTEN, ink_width_px: int = INK_WIDTH_PX,
		ink_darken: float = INK_DARKEN, crevice_width_px: int = CREVICE_WIDTH_PX,
		crevice_darken: float = CREVICE_DARKEN, brush_amplitude: float = BRUSH_NOISE_AMPLITUDE,
		blue_guard_saturation_trigger: float = BLUE_GUARD_SATURATION_TRIGGER,
		blue_guard_target_saturation: float = BLUE_GUARD_TARGET_SATURATION,
		reserved_bands_deg=RESERVED_HUE_BANDS_DEG, reserved_saturation_min: float = RESERVED_SATURATION_MIN,
		seed="repaint_weapon") -> dict:
	"""Pipeline complet (etapes 1 a 4bis) pour UNE arme. Renvoie
	`{"image": PIL.Image RGB 2048x2048, "uv0_hash": str, "report": {...}}` --
	n'ecrit AUCUN fichier (`main`/`run_manifest` s'en chargent)."""
	mesh = load_weapon_mesh(glb_path)
	vertices, faces, uv = mesh["vertices"], mesh["faces"], mesh["uv"]
	src_image = mesh["image"]
	width, height = src_image.size
	rgb01 = np.asarray(src_image, dtype=np.float64) / 255.0

	before_hash = uv0_hash(uv)

	rgb01, pull_report = apply_global_pull(
		rgb01, palette, force=pull_force, blue_hue_range=blue_hue_range,
		blue_saturation_min=blue_saturation_min, shadow_factor=shadow_factor,
		blue_remap_force=blue_remap_force)

	face_id_buffer = build_face_id_buffer(uv, faces, width, height)
	rgb01, box_report = apply_box_zones(rgb01, face_id_buffer, palette, boxes, vertices, faces, force=box_force)

	rgb01, relief_report = apply_relief(
		rgb01, face_id_buffer, vertices, faces, uv,
		edge_min_angle_deg=edge_min_angle_deg, edge_max_angle_deg=edge_max_angle_deg,
		lisere_width_px=lisere_width_px, lisere_lighten=lisere_lighten,
		ink_width_px=ink_width_px, ink_darken=ink_darken,
		crevice_width_px=crevice_width_px, crevice_darken=crevice_darken,
		brush_amplitude=brush_amplitude, seed=f"{seed}:{weapon_id}")

	rgb01, blue_guarded_count = guard_blue_saturation(rgb01, hue_range=blue_hue_range,
		saturation_max=blue_guard_saturation_trigger, target_saturation=blue_guard_target_saturation)

	rgb01, guarded_count = guard_reserved_hues(rgb01, bands_deg=reserved_bands_deg,
		saturation_min=reserved_saturation_min)

	after_hash = uv0_hash(uv)
	if after_hash != before_hash:  # pragma: no cover -- ce script ne touche jamais l'UV
		raise AssertionError("repaint_weapon: l'UV0 a change en cours de route -- bug interne")

	out_image = Image.fromarray((np.clip(rgb01, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), mode="RGB")
	report = {
		"weapon": weapon_id, "source": str(glb_path), "uv0_hash": after_hash,
		"pull": pull_report, "boxes": box_report["boxes"], "relief": relief_report,
		"blue_guarded_texels": blue_guarded_count, "reserved_guarded_texels": guarded_count,
	}
	return {"image": out_image, "uv0_hash": after_hash, "report": report}


def run_manifest(manifest_path=DEFAULT_MANIFEST_PATH, only=None, out_dir=None) -> dict:
	"""Traite toutes les armes du manifeste (ou seulement celles de `only`,
	iterable d'ids). Ecrit `<out_dir>/<id>_albedo.png` par arme. Renvoie le
	rapport combine `{"weapons": {id: report, ...}}`."""
	manifest = load_manifest(manifest_path)
	tokens_path = REPO_ROOT / manifest.get("tokens_path", "docs/style/tokens.json")
	weapons_dir = REPO_ROOT / manifest.get("weapons_dir", "assets/models/weapons")
	resolved_out_dir = Path(out_dir) if out_dir else REPO_ROOT / manifest.get("out_dir", "assets/textures/weapons")
	palette = load_palette(tokens_path)

	resolved_out_dir.mkdir(parents=True, exist_ok=True)
	only_set = set(only) if only else None
	reports = {}
	for entry in manifest["weapons"]:
		weapon_id = entry["id"]
		if only_set is not None and weapon_id not in only_set:
			continue
		glb_path = weapons_dir / f"{weapon_id}.glb"
		result = repaint_weapon(weapon_id, glb_path, entry.get("boxes", []), palette)
		out_path = resolved_out_dir / f"{weapon_id}_albedo.png"
		result["image"].save(out_path)
		reports[weapon_id] = result["report"]
		print(f"REPAINT_WEAPON_OK {weapon_id} -> {out_path}")
	return {"weapons": reports}


def parse_args():
	p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
	p.add_argument("--manifest", default=str(DEFAULT_MANIFEST_PATH))
	p.add_argument("--only", default=None, help="ids separes par des virgules (defaut : toutes les armes du manifeste)")
	p.add_argument("--out-dir", default=None, help="defaut : `out_dir` du manifeste")
	p.add_argument("--report", default=None, help="chemin JSON ou ecrire le rapport combine")
	return p.parse_args()


def main() -> None:
	args = parse_args()
	only = [w.strip() for w in args.only.split(",")] if args.only else None
	try:
		report = run_manifest(manifest_path=args.manifest, only=only, out_dir=args.out_dir)
	except (ValueError, RuntimeError, FileNotFoundError) as exc:
		print(f"REPAINT_WEAPON_FAIL {exc}")
		sys.exit(1)
	if args.report:
		with open(args.report, "w", encoding="utf-8") as f:
			json.dump(report, f, indent=2, ensure_ascii=False)
		print(args.report)


if __name__ == "__main__":
	main()
