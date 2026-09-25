## cosmetic_lint.gd
## Lint des teintes réservées sur les textures de skin (FUN-08, docs/research/
## 05_fun_retention.md §2.4 « un cosmétique ne doit jamais toucher les teintes
## réservées à l'ennemi » + §5 FUN-08). `StyleTokens.RESERVED_HUE_BANDS_DEG`/
## `RESERVED_CHROMA_THRESHOLD` (docs/style/tokens.json "reserved", même
## source que tests/agents/test_agent_palette.gd et tools/review/
## style_check.py CHK-06/CHK-21) réservent les bandes OKLCH 300–355° et
## 105–145° (chroma > 0,08) à la surbrillance ennemie (Magenta `#FF3DC8` /
## Citron `#C8FF1F`).
##
## Seuil DÉDIÉ (contrat FUN-08 : 2 %), pas celui de CHK-06 (décor de carte,
## tools/review/style_check.py, 0,1 %) : une texture de skin PEUT contenir un
## accent proche d'une bande réservée sans confusion ennemie tant qu'il reste
## minoritaire — le décor, lui, doit en être quasi exempt partout où le
## regard se pose en combat.
##
## Conversion sRGB -> OKLCH : mêmes matrices que
## tools/review/style_check.py::rgb01_to_oklab/oklab_to_oklch et
## tests/agents/test_agent_palette.gd::_oklch — une seule formule, trois
## implémentations (Python hors moteur, GDScript jeu/outillage) car aucune
## des trois ne peut importer les deux autres.
##
## Usage CLI (garde-fou à brancher sur le pipeline de skins dès qu'il existe
## — aucun asset de skin n'est encore livré au moment de FUN-08) :
##   godot --headless --path . -s res://tools/cosmetic_lint.gd -- \
##       --in=<texture1.png> [--in=<texture2.png> ...]
## Affiche COSMETIC_LINT_OK/COSMETIC_LINT_FAIL par texture, puis quitte avec
## le code 1 si UNE SEULE texture dépasse le seuil ou ne charge pas, 0 sinon.
extends SceneTree

## Contrat FUN-08 : « cosmetic_lint échoue si une texture de skin a > 2 % de
## pixels dans les bandes OKLCH réservées ». Une texture exactement à 2 %
## passe (le contrat dit « > 2 % », pas « >= »).
const MAX_RESERVED_FRACTION := 0.02

static func _srgb_to_linear(c: float) -> float:
	if c <= 0.04045:
		return c / 12.92
	return pow((c + 0.055) / 1.055, 2.4)

## Retourne `[L, C, h_deg]` en OKLCH pour une Color sRGB — même formule que
## tests/agents/test_agent_palette.gd::_oklch (voir la doc d'en-tête).
static func oklch(color: Color) -> Array:
	var r := _srgb_to_linear(color.r)
	var g := _srgb_to_linear(color.g)
	var b := _srgb_to_linear(color.b)

	var l := 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
	var m := 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
	var s := 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

	var l_ := signf(l) * pow(absf(l), 1.0 / 3.0)
	var m_ := signf(m) * pow(absf(m), 1.0 / 3.0)
	var s_ := signf(s) * pow(absf(s), 1.0 / 3.0)

	var big_l := 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
	var a := 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
	var b2 := 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_

	var chroma := sqrt(a * a + b2 * b2)
	var hue_deg := rad_to_deg(atan2(b2, a))
	if hue_deg < 0.0:
		hue_deg += 360.0
	return [big_l, chroma, hue_deg]

## Vrai si `(hue_deg, chroma)` tombe dans une bande de teinte réservée à la
## surbrillance ennemie (`StyleTokens.RESERVED_HUE_BANDS_DEG`) avec une
## chroma strictement au-delà de `StyleTokens.RESERVED_CHROMA_THRESHOLD`.
static func is_reserved(hue_deg: float, chroma: float) -> bool:
	if chroma <= StyleTokens.RESERVED_CHROMA_THRESHOLD:
		return false
	for band in StyleTokens.RESERVED_HUE_BANDS_DEG:
		if hue_deg >= band[0] and hue_deg <= band[1]:
			return true
	return false

## Fraction de pixels VISIBLES (alpha > 0 — une texture de skin est souvent un
## atlas avec du remplissage transparent, qu'il ne faut pas compter) dont la
## couleur tombe dans une bande réservée. 0.0 si `image` n'a aucun pixel
## visible. Pur : aucune E/S, aucun état — testable directement sur une
## Image construite en mémoire (tests/meta/test_shop_rules.gd).
static func reserved_pixel_fraction(image: Image) -> float:
	var width := image.get_width()
	var height := image.get_height()
	var included := 0
	var reserved := 0
	for y in height:
		for x in width:
			var px := image.get_pixel(x, y)
			if px.a <= 0.0:
				continue
			included += 1
			var lch := oklch(px)
			if is_reserved(lch[2], lch[1]):
				reserved += 1
	if included == 0:
		return 0.0
	return float(reserved) / float(included)

## Résultat structuré pour une image déjà chargée : `{fraction, max_fraction,
## status}` avec `status` "PASS" (fraction <= MAX_RESERVED_FRACTION) ou
## "FAIL". Pur.
static func evaluate_image(image: Image) -> Dictionary:
	var fraction := reserved_pixel_fraction(image)
	return {
		"fraction": fraction,
		"max_fraction": MAX_RESERVED_FRACTION,
		"status": "PASS" if fraction <= MAX_RESERVED_FRACTION else "FAIL",
	}

## Charge `path` (res://, user:// ou chemin disque) et évalue. `status`
## "ERROR" (jamais "PASS") si le fichier ne charge pas — une texture
## illisible ne doit jamais laisser passer un skin par défaut.
static func evaluate_texture_file(path: String) -> Dictionary:
	var image := Image.new()
	var err := image.load(path)
	if err != OK:
		return {"path": path, "status": "ERROR", "detail": "chargement impossible (err=%d)" % err}
	var result := evaluate_image(image)
	result["path"] = path
	return result


func _initialize() -> void:
	var paths := _parse_args()
	if paths.is_empty():
		print("COSMETIC_LINT_FAIL --in=<texture> est requis (au moins une fois)")
		quit(1)
		return
	var all_pass := true
	for path in paths:
		var result := evaluate_texture_file(path)
		match result.get("status"):
			"PASS":
				print("COSMETIC_LINT_OK %s fraction=%.4f" % [path, result["fraction"]])
			"FAIL":
				all_pass = false
				print("COSMETIC_LINT_FAIL %s fraction=%.4f > %.4f (bandes 300-355°/105-145°, C>%.2f)" % [
					path, result["fraction"], result["max_fraction"], StyleTokens.RESERVED_CHROMA_THRESHOLD,
				])
			_:
				all_pass = false
				print("COSMETIC_LINT_FAIL %s %s" % [path, result.get("detail", "erreur inconnue")])
	quit(0 if all_pass else 1)


func _parse_args() -> Array[String]:
	var out: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--in="):
			out.append(a.get_slice("=", 1))
	return out
