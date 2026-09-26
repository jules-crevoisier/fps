## wasteland_look.gd
## Wasteland v7 — greybox pur (2026-09-26, « fais la carte block que je
## puisse la tester in game »). RÉÉCRIT ENTIÈREMENT : la palette peinte v4
## (calibration ART-70, encore visible dans l'historique) est remplacée par
## une palette DE DÉVELOPPEMENT dérivée de la SOURCE UNIQUE
## `data/maps/wasteland_plan.json` (`materials.wall/floor/cover/stairs/oob/
## platform`, un hex par rôle) — jamais un jeton recopié à la main : modifier
## la teinte d'un rôle se fait dans le JSON (puis `python tools/maps/
## render_plan.py` pour re-générer le plan et l'image), pas ici.
##
## `"<rôle>_kind" = "dev_grid"` sur chaque rôle (sauf `accent`, purement
## dérivé pour compat) bascule `Kit.build_piece`/`Cartoon.painted` vers
## `Cartoon.dev_grid()` (scripts/core/Cartoon.gd, ADDITIF, kind canonique
## dédié "dev_grid") : une grille triplanaire monde (1 m mineure / 5 m
## majeure, `assets/shaders/dev_grid.gdshader`) plutôt qu'une texture peinte
## (`tools/textures/gen_textures.py`, hors sujet ici — décision utilisateur
## 2026-09-25 « la carte reste en greybox pur », toujours en vigueur,
## `WastelandArt.ART_ENABLED := false`). Couleur EXACTE du rôle (aucune
## dilution `Cartoon.effective_tint`, voir son commentaire) : `painted()`
## redirige vers `dev_grid()` AVANT tout calcul de teinte.
class_name WastelandLook
extends RefCounted

## ---------------------------------------------------------------- Atmosphère
## (ART-86, INCHANGÉ par cette tâche — greybox pur = matériaux/`palette()`
## seulement, jamais le ciel/le brouillard/le post-traitement) : consommées
## par `scripts/core/LevelLook.gd` UNIQUEMENT quand `map_id == "wasteland"`
## (comparaison stricte). Conservées ICI À L'IDENTIQUE (mêmes valeurs) —
## `LevelLook.gd` est hors de mon périmètre de fichiers et référence ces
## constantes par leur nom, les retirer casserait son chargement (constaté :
## `SCRIPT ERROR: Cannot find member "FOG_TINT_OCRE" in base "WastelandLook"`
## dès qu'elles manquent).
const SUN_ELEVATION_DEG := 24.0
const FOG_TINT_OCRE := Color("e8c179")
const FOG_DENSITY := 0.0024
const FOG_HEIGHT_M := 6.0
const FOG_HEIGHT_DENSITY := 0.003
const SSAO_RADIUS := 0.9
const SSAO_INTENSITY := 1.15
const SSAO_POWER := 1.6
const SSAO_LIGHT_AFFECT := 0.2
const ADJUSTMENT_SATURATION := 1.008
const ADJUSTMENT_CONTRAST := 1.008
const SHADOW_ANGULAR_DISTANCE := 0.2

## Rôles Kit (`color_key`) couverts par `data/maps/wasteland_plan.json`
## `materials.<rôle>.color` — mêmes noms que `materials.by_kind` values
## (jamais un rôle inventé ici : `WastelandLayout._role_for_kind` lit le
## MÊME dictionnaire `materials.by_kind` pour assigner `color_key` à chaque
## pièce, donc chaque rôle qu'il peut produire est forcément couvert ici).
const _ROLES := ["wall", "floor", "cover", "stairs", "platform"]

static func _hex_color(materials: Dictionary, role: String, fallback: String) -> Color:
	var entry: Dictionary = materials.get(role, {})
	var code := String(entry.get("color", fallback))
	return Color(code.trim_prefix("#"), float(entry.get("alpha", 1.0)))

## Dictionnaire `color_key`/`"<rôle>_kind"` consommé par `Kit.build_piece`
## (voir son en-tête « `mat` … avant `color_key` ») via `WastelandLayout
## .data()["palette"]`. Fonction statique pure (aucun état propre — la seule
## dépendance est la LECTURE, mise en cache, du JSON via
## `WastelandLayout.plan()`) : mêmes valeurs à chaque appel tant que le
## fichier ne change pas, testable sans arbre de scène.
static func palette() -> Dictionary:
	var plan := WastelandLayout.plan()
	var materials: Dictionary = plan.get("materials", {})
	var out: Dictionary = {}
	for role in _ROLES:
		out[role] = _hex_color(materials, role, "888888")
		out["%s_kind" % role] = "dev_grid"
	out["oob"] = _hex_color(materials, "oob", "6F5BB0")
	out["oob_kind"] = "dev_grid"
	# Toit des `building2` (color_key "wall") : même grille que ses murs,
	# jamais le toit plat d'origine de `Cartoon.world()` (voir le
	# commentaire de tête de `Kit.build_piece` sur `roof_kind`).
	out["wall_roof_kind"] = "dev_grid"
	# `accent` : compat pour `MapSetup._build_markers` (`palette.get("accent",
	# ...)`, toujours lu même sans zone Hardpoint/SnD/Duel construite pour
	# Wasteland — TDM seul cette tâche) ; retombe sur la couleur "mur".
	out["accent"] = out["wall"]
	return out
