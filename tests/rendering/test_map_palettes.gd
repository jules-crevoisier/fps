## test_map_palettes.gd
## Spec (STYLE_BIBLE.md v3 §7.7, tâche ART-05) :
## - `Cartoon.map_palette()` (donc `Cartoon._MAP_PALETTES`, généré par
##   `tools/style/gen_style_tokens.py` dans `scripts/core/StyleTokens.gd`)
##   reprend `docs/style/tokens.json` "maps" (ciel, soleil, élévation, ombre,
##   sol) SANS AUCUN assombrissement de compensation — en particulier
##   Wasteland et Cargo Ship, dont le ciel était manuellement assombri en v2
##   contre un tonemap Filmic depuis remplacé par le LINÉAIRE WYSIWYG
##   (LevelLook.gd §7.5) : `_expect_map_matches_tokens_json` compare CHAQUE
##   carte aux hex bruts de tokens.json, transcrits indépendamment ci-dessous
##   (jamais lus depuis l'implémentation elle-même).
## - CHK-07 (tokens.json "checks", bloquant) : aucune couleur de
##   `_MAP_PALETTES` ne tombe dans une bande de teinte réservée à la
##   surbrillance ennemie (OKLCH, 300–355° ou 105–145°, chroma > 0,08).
## - `Cartoon.prop_uv(kind, tint)` sert les maillages Blender (props/décor) :
##   UV du maillage (jamais triplanaire, contrairement à `painted()`) +
##   masques vertex (déjà lus par défaut par `world()`), même bibliothèque de
##   textures/alias/règle de teinte que `painted()`.
## - `_TRIPLANAR_SCALE` (terrain, `painted()`) vaut 1/4 (§7.2 : « 1/3 → 1/4 »).
## - `_CHARACTER_GRAIN` (`character_surface()`) vaut 0 partout (§4.2 « aucun
##   grain », CHK-27 « paint_grain_strength = 0 »). NOTE POUR LE LEAD : ceci
##   contredit deux assertions PRÉEXISTANTES hors du périmètre de cette tâche
##   — `tests/rendering/test_cartoon_materials.gd`
##   ("test_character_surface_grain_varies_by_kind_within_six_percent",
##   "test_character_surface_unknown_kind_gets_a_safe_default_grain") et
##   `tests/rendering/test_ink_toon_params.gd`
##   ("test_cartoon_character_surface_still_sets_paint_grain_on_v3_shader",
##   verrouillée à 0,06 pour "gear") — datées de la tâche ART-02, avant que
##   STYLE_BIBLE.md v3.1 §4.2/CHK-27 et le titre même de cette tâche
##   (« zéro grain ») ne figent le grain à 0. Signalé dans `blocked_on` :
##   ces deux fichiers sont hors de la liste de fichiers d'ART-05, donc
##   non modifiés ici.
extends GdUnitTestSuite

const _INK_TOON_SHADER := preload("res://assets/shaders/ink_toon.gdshader")

## docs/style/tokens.json "maps" — transcription INDÉPENDANTE (jamais lue
## depuis Cartoon.gd/StyleTokens.gd) des six champs que §7.7 nomme : ciel
## (sky_zenith/sky_horizon), soleil (sun_color/sun_elevation_deg), ombre
## (shadow_tint), sol (ground).
const _EXPECTED := {
	"port_ferraille": {
		"sky_zenith": "4a8fe0", "sky_horizon": "d6ecf6",
		"sun_color": "fff1d0", "sun_elevation_deg": 40.0,
		"shadow_tint": "5f71a8", "ground": "bba98c",
	},
	"val_poussiere": {
		"sky_zenith": "3c7fd9", "sky_horizon": "f2d7a8",
		"sun_color": "ffc98a", "sun_elevation_deg": 28.0,
		"shadow_tint": "6a63a0", "ground": "c9a06e",
	},
	"saint_ombre": {
		"sky_zenith": "3f6f86", "sky_horizon": "f0b860",
		"sun_color": "ffb870", "sun_elevation_deg": 22.0,
		"shadow_tint": "3e4f7a", "ground": "6e6a73",
	},
	"col_du_vautour": {
		"sky_zenith": "1f63d0", "sky_horizon": "cfe6f7",
		"sun_color": "fff6e0", "sun_elevation_deg": 42.0,
		"shadow_tint": "6c86c8", "ground": "f1f4f8",
	},
	"la_fosse": {
		"sky_zenith": "3a80dc", "sky_horizon": "d3e7f5",
		"sun_color": "ffe0a6", "sun_elevation_deg": 50.0,
		"shadow_tint": "6072ae", "ground": "e3d3ae",
	},
	"le_belvedere": {
		"sky_zenith": "5a8fd8", "sky_horizon": "ffd9a0",
		"sun_color": "ffd3a0", "sun_elevation_deg": 25.0,
		"shadow_tint": "5e6aa8", "ground": "c9b79a",
	},
	"wasteland": {
		"sky_zenith": "2f74d8", "sky_horizon": "bfddf2",
		"sun_color": "ffd99a", "sun_elevation_deg": 32.0,
		"shadow_tint": "5b6ca6", "ground": "d2a46c",
	},
	"cargo_ship": {
		"sky_zenith": "3e86e0", "sky_horizon": "cde8f8",
		"sun_color": "fff0c8", "sun_elevation_deg": 45.0,
		"shadow_tint": "5a6ea8", "ground": "8d959b",
	},
}

## tokens.json "reserved" : bandes de teinte OKLCH interdites à toute couleur
## de base (monde, personnage, cosmétique) au-delà de ce seuil de chroma —
## exclusives à la surbrillance ennemie (Magenta/Citron). Même valeurs que
## tests/agents/test_agent_palette.gd (ART-14) et StyleTokens.
## RESERVED_HUE_BANDS_DEG/RESERVED_CHROMA_THRESHOLD (ART-05) — transcrites
## ici indépendamment, comme le reste de ce fichier.
const _RESERVED_HUE_BANDS_DEG := [[300.0, 355.0], [105.0, 145.0]]
const _RESERVED_CHROMA_THRESHOLD := 0.08


# --------------------------------------------------------- map_palette() : §7.7

func test_map_palette_matches_tokens_json_for_every_map() -> void:
	for map_id in _EXPECTED:
		var expected: Dictionary = _EXPECTED[map_id]
		var palette := Cartoon.map_palette(map_id)
		for key in ["sky_zenith", "sky_horizon", "sun_color", "shadow_tint", "ground"]:
			assert_that(palette[key]).append_failure_message(
				"%s.%s != tokens.json (#%s)" % [map_id, key, expected[key]]
			).is_equal(Color(expected[key]))
		assert_float(palette["sun_elevation_deg"]).append_failure_message(
			"%s.sun_elevation_deg != tokens.json" % map_id
		).is_equal_approx(expected["sun_elevation_deg"], 0.001)


## Régression directe du critère « sans assombrissement de compensation » :
## Wasteland et Cargo Ship avaient un ciel manuellement assombri en v2 par
## rapport aux hex bruts de design.md/tokens.json (mesuré contre un tonemap
## Filmic depuis remplacé) — ce test échouerait sur les anciennes valeurs
## `Color("265dad")`/`Color("a8c2d5")` (Wasteland) et `Color("4693ee")`/
## `Color("d8eefc")` (Cargo Ship).
func test_map_palette_wasteland_and_cargo_ship_skies_are_no_longer_darkened() -> void:
	var wasteland := Cartoon.map_palette("wasteland")
	assert_that(wasteland["sky_zenith"]).is_equal(Color("2f74d8"))
	assert_that(wasteland["sky_horizon"]).is_equal(Color("bfddf2"))

	var cargo_ship := Cartoon.map_palette("cargo_ship")
	assert_that(cargo_ship["sky_zenith"]).is_equal(Color("3e86e0"))
	assert_that(cargo_ship["sky_horizon"]).is_equal(Color("cde8f8"))


func test_map_palette_covers_exactly_the_eight_maps() -> void:
	for map_id in _EXPECTED:
		assert_bool(Cartoon._MAP_PALETTES.has(map_id)).append_failure_message(
			"carte manquante dans Cartoon._MAP_PALETTES : %s" % map_id
		).is_true()
	assert_int(Cartoon._MAP_PALETTES.size()).is_equal(_EXPECTED.size())


func test_map_palette_unknown_map_falls_back_to_wasteland() -> void:
	var unknown := Cartoon.map_palette("does_not_exist")
	var empty := Cartoon.map_palette("")
	var wasteland := Cartoon.map_palette("wasteland")
	assert_that(unknown["sky_zenith"]).is_equal(wasteland["sky_zenith"])
	assert_that(empty["sky_zenith"]).is_equal(wasteland["sky_zenith"])


# --------------------------------------------------------------------- CHK-07

func test_no_map_palette_color_falls_in_a_reserved_hue_band() -> void:
	for map_id in _EXPECTED:
		var palette := Cartoon.map_palette(map_id)
		for key in ["sky_zenith", "sky_horizon", "sun_color", "shadow_tint", "ground"]:
			var color: Color = palette[key]
			var lch := _oklch(color)
			var chroma: float = lch[1]
			var hue_deg: float = lch[2]
			var in_band := false
			for band in _RESERVED_HUE_BANDS_DEG:
				if hue_deg >= band[0] and hue_deg <= band[1]:
					in_band = true
					break
			var violates := in_band and chroma > _RESERVED_CHROMA_THRESHOLD
			assert_bool(violates).append_failure_message(
				"%s.%s (%s) : h=%.1f° C=%.3f tombe dans une bande de teinte réservée à l'ennemi" % [
					map_id, key, color.to_html(false), hue_deg, chroma
				]
			).is_false()


# ------------------------------------------------------------------ prop_uv()

func test_prop_uv_known_kind_uses_uv_not_triplanar() -> void:
	var m := Cartoon.prop_uv(&"rust")
	assert_that(m.shader).is_equal(_INK_TOON_SHADER)
	assert_bool(m.get_shader_parameter("use_albedo_texture")).is_true()
	assert_that(m.get_shader_parameter("use_triplanar")).is_not_equal(true)
	assert_that(m.get_shader_parameter("albedo_texture")).is_not_null()


func test_prop_uv_default_tint_is_white() -> void:
	var m := Cartoon.prop_uv(&"sand_dirt")
	assert_that(m.get_shader_parameter("albedo_color")).is_equal(Color.WHITE)


func test_prop_uv_tint_multiplies_the_tintable_container_base() -> void:
	var m := Cartoon.prop_uv(&"container_paint", Cartoon.CONTAINER_RED)
	assert_that(m.get_shader_parameter("albedo_color")).is_equal(Cartoon.CONTAINER_RED)


func test_prop_uv_baked_colour_kind_keeps_only_a_light_tint() -> void:
	# Même règle que painted() (effective_tint) : une texture déjà colorée
	# (sable) ne doit pas être multipliée en entier par la teinte de carte,
	# sous peine de l'assombrir deux fois.
	var ochre := Color("c4935a")
	var m := Cartoon.prop_uv(&"sand_dirt", ochre)
	assert_that(m.get_shader_parameter("albedo_color")).is_equal(Cartoon.effective_tint(&"sand_dirt", ochre))


func test_prop_uv_material_with_grime_mask_enables_it_without_a_uv_scale() -> void:
	var m := Cartoon.prop_uv(&"wood_planks")
	assert_bool(m.get_shader_parameter("use_grime_texture")).is_true()
	assert_that(m.get_shader_parameter("grime_texture")).is_not_null()


func test_prop_uv_material_without_grime_mask_leaves_it_disabled() -> void:
	var m := Cartoon.prop_uv(&"asphalt")
	assert_that(m.get_shader_parameter("use_grime_texture")).is_not_equal(true)


func test_prop_uv_unknown_kind_falls_back_to_flat_world_material() -> void:
	var m := Cartoon.prop_uv(&"nonexistent_kind", Color.RED)
	assert_that(m.shader).is_equal(_INK_TOON_SHADER)
	assert_that(m.get_shader_parameter("use_albedo_texture")).is_not_equal(true)
	assert_that(m.get_shader_parameter("albedo_color")).is_equal(Color.RED)


## prop_uv() accepte les mêmes alias de bibliothèque de props que painted()
## (même table `_KIND_ALIASES`) et pointe vers la MÊME texture qu'elle pour
## un kind donné (seule la méthode d'échantillonnage change).
func test_prop_uv_accepts_props_library_aliases_and_matches_painted_texture() -> void:
	var pairs := {
		&"corrugated": &"corrugated_metal",
		&"container": &"container_paint",
		&"wood": &"wood_planks",
	}
	for alias in pairs:
		var canonical: StringName = pairs[alias]
		var via_alias := Cartoon.prop_uv(alias)
		var via_canonical := Cartoon.prop_uv(canonical)
		assert_that(via_alias.get_shader_parameter("albedo_texture")).is_equal(via_canonical.get_shader_parameter("albedo_texture"))
		assert_that(via_canonical.get_shader_parameter("albedo_texture")).is_equal(Cartoon.painted(canonical).get_shader_parameter("albedo_texture"))


# --------------------------------------------------------- _TRIPLANAR_SCALE

## §7.2/§7.7 : « triplanar_scale : 1/3 → 1/4 (1 répétition / 4 m) », terrain
## seulement (painted()) -- prop_uv() ne pose jamais triplanar_scale (testé
## ci-dessus, use_triplanar reste false).
func test_painted_triplanar_scale_is_one_quarter() -> void:
	var m := Cartoon.painted(&"rust")
	assert_float(m.get_shader_parameter("triplanar_scale")).is_equal_approx(1.0 / 4.0, 0.0001)


# --------------------------------------------------------- _CHARACTER_GRAIN

## STYLE_BIBLE.md v3.1 §4.2 « aucun grain » / CHK-27 « paint_grain_strength =
## 0 » / §7.7 « _CHARACTER_GRAIN à 0 ». Voir la note en tête de fichier :
## contredit sciemment deux tests préexistants hors périmètre (ART-02),
## signalé dans blocked_on plutôt que corrigé ici.
func test_character_surface_grain_is_zero_for_every_known_kind() -> void:
	for kind in [&"skin", &"cloth", &"outfit", &"gear", &"accent"]:
		var m := Cartoon.character_surface(kind, Color.WHITE)
		assert_float(m.get_shader_parameter("paint_grain_strength")).append_failure_message(
			"character_surface(&\"%s\", ...) : paint_grain_strength != 0" % kind
		).is_equal_approx(0.0, 0.0001)


func test_character_surface_grain_is_zero_for_unknown_kind() -> void:
	var m := Cartoon.character_surface(&"unknown_slot", Color.WHITE)
	assert_float(m.get_shader_parameter("paint_grain_strength")).is_equal_approx(0.0, 0.0001)


# ------------------------------------------------------------------ OKLCH (local)
# Même conversion sRGB->OKLab que tests/agents/test_agent_palette.gd's
# `_oklch()`/tools/look_probe.gd's `_oklab_l()`/tools/style/gen_style_tokens.
# py's `oklch()` -- aucun utilitaire OKLab partagé n'existe encore dans le
# dépôt (ART-03, futur, en serait le foyer naturel ; hors périmètre ART-05).

static func _srgb_to_linear(c: float) -> float:
	if c <= 0.04045:
		return c / 12.92
	return pow((c + 0.055) / 1.055, 2.4)


## Retourne `[L, C, h_deg]` en OKLCH pour une Color sRGB.
static func _oklch(color: Color) -> Array:
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
