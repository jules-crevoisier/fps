## test_agent_palette.gd
## Spec (tâche ART-14, STYLE_BIBLE.md v3 §4.4 + jetons machine
## docs/style/tokens.json) : les couleurs-clés d'AgentDatabase (donc
## AgentConfig.color) doivent égaler celles de tokens.json "agents.*.key".
## Prototype à un seul agent (décision 2026-09-26) : Verrou est désormais le
## SEUL agent d'AgentDatabase — les cinq autres couleurs-clés (Vif/Choc/
## Vanne/Guet/Roseau) ont disparu avec leurs agents. Le §4.4 promet aussi
## qu'« aucune couleur d'agent ne tombe dans une bande réservée » (tokens.json
## "reserved" : teintes OKLCH 300-355° et 105-145° au-delà de C 0.08,
## exclusives à la surbrillance ennemie) et qu'« aucun texte d'autocollant »
## sur la couleur-clé ne descend sous 4.5:1 (CHK-26).
extends GdUnitTestSuite

## docs/style/tokens.json "agents.*.key" == STYLE_BIBLE.md §4.4 — un seul
## agent survit à la réduction du prototype.
const _EXPECTED_KEY_COLOR := {
	"Verrou": "2a5fc4",
}

## docs/style/tokens.json "agents.*.text_on_key" : "ink" -> Cartoon.INK
## `#1A1410`, "papier" -> le jeton UI `color.papier.text` `#F4EDE1` (jamais le
## `Cartoon.PAPER` `#E6E1D6`, réservé aux socles neutres du monde — ce sont
## deux jetons différents, voir Cartoon.gd et tokens.json "color.papier.text").
const _TEXT_ON_KEY := {
	"Verrou": "papier",
}

const _INK := "1a1410"
const _PAPIER_TEXT := "f4ede1"

## docs/style/tokens.json "reserved" : bandes de teinte OKLCH interdites à
## toute couleur de base (monde, personnage, cosmétique) au-delà de ce seuil
## de chroma — exclusives à la surbrillance ennemie (Magenta/Citron).
const _RESERVED_HUE_BANDS_DEG := [[300.0, 355.0], [105.0, 145.0]]
const _RESERVED_CHROMA_THRESHOLD := 0.08

## CHK-26 (docs/style/tokens.json "checks").
const _TEXT_CONTRAST_MIN := 4.5


func test_agent_colors_match_style_bible_v3_keys() -> void:
	for agent in AgentDatabase.all():
		var config := agent as AgentConfig
		assert_bool(_EXPECTED_KEY_COLOR.has(config.agent_name)).append_failure_message(
			"agent inattendu dans AgentDatabase.all() : %s" % config.agent_name
		).is_true()
		var expected := Color(_EXPECTED_KEY_COLOR[config.agent_name])
		assert_that(config.color).append_failure_message(
			"%s : AgentConfig.color != couleur-clé tokens.json" % config.agent_name
		).is_equal(expected)


func test_the_only_agent_is_covered() -> void:
	var names: Array = []
	for agent in AgentDatabase.all():
		names.append((agent as AgentConfig).agent_name)
	assert_array(names).contains_exactly_in_any_order(_EXPECTED_KEY_COLOR.keys())


func test_no_agent_color_falls_in_a_reserved_hue_band() -> void:
	for agent in AgentDatabase.all():
		var config := agent as AgentConfig
		var lch := _oklch(config.color)
		var chroma: float = lch[1]
		var hue_deg: float = lch[2]
		var in_reserved_band := false
		for band in _RESERVED_HUE_BANDS_DEG:
			if hue_deg >= band[0] and hue_deg <= band[1]:
				in_reserved_band = true
				break
		var violates_reserved_band := in_reserved_band and chroma > _RESERVED_CHROMA_THRESHOLD
		assert_bool(violates_reserved_band).append_failure_message(
			"%s (%s) : h=%.1f° C=%.3f tombe dans une bande de teinte réservée à l'ennemi" % [
				config.agent_name, config.color.to_html(false), hue_deg, chroma
			]
		).is_false()


func test_sticker_text_contrast_reaches_chk_26_minimum() -> void:
	for agent in AgentDatabase.all():
		var config := agent as AgentConfig
		var text_role: String = _TEXT_ON_KEY[config.agent_name]
		var text_color := Color(_INK) if text_role == "ink" else Color(_PAPIER_TEXT)
		var ratio := HudFormat.contrast_ratio(text_color, config.color)
		assert_float(ratio).append_failure_message(
			"%s : texte d'autocollant (%s) à %.2f:1 sur %s, sous le minimum CHK-26 (%.1f:1)" % [
				config.agent_name, text_role, ratio, config.color.to_html(false), _TEXT_CONTRAST_MIN
			]
		).is_greater_equal(_TEXT_CONTRAST_MIN)


## PlayerLook.sky_rim_color() (ART-14, STYLE_BIBLE.md v3 §4.5 "Rim de ciel") :
## doit suivre la teinte d'horizon de la carte en cours (Cartoon.map_palette),
## jamais une couleur fixe ni la couleur d'équipe — c'est justement ce qui la
## distingue du rim ennemi (0.6, Cartoon.enemy_color()).
func test_sky_rim_color_follows_current_map_horizon() -> void:
	var orig := MatchConfig.map_id
	for map_id in ["shipment", "cargo_ship", "port_ferraille"]:
		MatchConfig.map_id = map_id
		assert_that(PlayerLook.sky_rim_color()).is_equal(Cartoon.map_palette(map_id)["sky_horizon"])
	MatchConfig.map_id = orig


func test_sky_rim_color_never_equals_a_team_color() -> void:
	var orig := MatchConfig.map_id
	for map_id in ["shipment", "cargo_ship", "port_ferraille", "val_poussiere", "saint_ombre", "col_du_vautour", "la_fosse", "le_belvedere"]:
		MatchConfig.map_id = map_id
		var rim := PlayerLook.sky_rim_color()
		assert_bool(rim == Cartoon.ally_color()).is_false()
		assert_bool(rim == Color("ff3dc8")).is_false()
		assert_bool(rim == Color("c8ff1f")).is_false()
	MatchConfig.map_id = orig


# ------------------------------------------------------------- OKLCH (local)
# docs/style/tokens.json meta.units "L_C_h" : "OKLab lightness / OKLCH
# chroma / OKLCH hue in degrees, computed from sRGB" — conversion standard de
# Björn Ottosson (https://bottosson.github.io/posts/oklab/), auto-contenue
# ici : aucun utilitaire OKLab partagé n'existe encore dans le dépôt
# (StyleTokens.gd/tools/review/style_check.py, ART-03/ART-05, sont hors du
# périmètre de cette tâche et ne sont pas encore livrés).
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
