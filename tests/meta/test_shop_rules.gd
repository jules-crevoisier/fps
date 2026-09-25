## test_shop_rules.gd
## Spec (FUN-08, docs/research/05_fun_retention.md §2.5/§5) :
## - `ShopRules.validate(offer)` refuse toute offre `random: true`,
##   `expires_at` présent, `stock_limit` présent, `currency` != EUR ou
##   `tradable: true` — chaque refus cite sa source (`ShopRules.SOURCES`,
##   testé ici, pas seulement documenté en commentaire).
## - `tools/cosmetic_lint.gd` échoue (`status` "FAIL") si une texture a
##   strictement plus de 2 % de pixels VISIBLES dont la teinte OKLCH tombe
##   dans une bande réservée (300–355° ou 105–145°, chroma > 0,08) —
##   `StyleTokens.RESERVED_HUE_BANDS_DEG`/`RESERVED_CHROMA_THRESHOLD`, mêmes
##   jetons que docs/style/tokens.json "reserved" et
##   tests/agents/test_agent_palette.gd.
extends GdUnitTestSuite

const LINT := preload("res://tools/cosmetic_lint.gd")

## Offre de référence : passe tous les garde-fous (baseline pour les tests de
## rejet, qui ne mutent qu'UN champ à la fois).
const _VALID_OFFER := {
	"id": "skin_choc_braise",
	"name": "Choc — Braise",
	"currency": "EUR",
	"price_cents": 899,
}

## `#FF3DC8` (Magenta) / `#C8FF1F` (Citron) — docs/style/tokens.json
## "reserved.enemy_highlight", mêmes hex que
## tests/agents/test_agent_palette.gd. OKLCH vérifié indépendamment (mêmes
## matrices que tools/review/style_check.py) : Magenta h≈342,26° C≈0,260 ;
## Citron h≈124,21° C≈0,226 — tous deux dans une bande réservée.
const _RESERVED_MAGENTA := "ff3dc8"
const _RESERVED_CITRON := "c8ff1f"

## `#D2A46C` — sol Wasteland (StyleTokens.MAP_PALETTES), h≈71,18° C≈0,091 :
## hors bande réservée malgré une chroma non négligeable (seule la teinte
## compte hors bande).
const _SAFE_GROUND := "d2a46c"


# ---------------------------------------------------------------------
#  ShopRules.validate() / violations()
# ---------------------------------------------------------------------

func test_valid_offer_passes() -> void:
	assert_bool(ShopRules.validate(_VALID_OFFER)).append_failure_message(
		"une offre EUR sans champ interdit doit passer : %s" % [ShopRules.violations(_VALID_OFFER)]
	).is_true()
	assert_array(ShopRules.violations(_VALID_OFFER)).is_empty()


func test_random_true_is_rejected() -> void:
	var offer := _VALID_OFFER.duplicate()
	offer["random"] = true
	assert_bool(ShopRules.validate(offer)).is_false()
	var reasons := ShopRules.violations(offer)
	assert_int(reasons.size()).is_equal(1)
	assert_str(reasons[0]).contains("random")
	assert_str(reasons[0]).contains(ShopRules.SOURCES["PEGI"])


func test_random_false_is_accepted() -> void:
	var offer := _VALID_OFFER.duplicate()
	offer["random"] = false
	assert_bool(ShopRules.validate(offer)).is_true()


func test_expires_at_present_is_rejected_regardless_of_value() -> void:
	var offer := _VALID_OFFER.duplicate()
	offer["expires_at"] = 0
	var reasons := ShopRules.violations(offer)
	assert_int(reasons.size()).is_equal(1)
	assert_str(reasons[0]).contains("expires_at")
	assert_str(reasons[0]).contains(ShopRules.SOURCES["PEGI"])


func test_stock_limit_present_is_rejected_regardless_of_value() -> void:
	var offer := _VALID_OFFER.duplicate()
	offer["stock_limit"] = 0
	var reasons := ShopRules.violations(offer)
	assert_int(reasons.size()).is_equal(1)
	assert_str(reasons[0]).contains("stock_limit")
	assert_str(reasons[0]).contains(ShopRules.SOURCES["PEGI"])


func test_non_eur_currency_is_rejected() -> void:
	for bad_currency in ["USD", "GEM", "COIN", ""]:
		var offer := _VALID_OFFER.duplicate()
		offer["currency"] = bad_currency
		var reasons := ShopRules.violations(offer)
		assert_int(reasons.size()).append_failure_message(
			"currency=%s aurait dû être refusée" % bad_currency
		).is_equal(1)
		assert_str(reasons[0]).contains(ShopRules.SOURCES["DFA"])


func test_missing_currency_is_rejected() -> void:
	var offer := _VALID_OFFER.duplicate()
	offer.erase("currency")
	assert_bool(ShopRules.validate(offer)).is_false()


func test_tradable_true_is_rejected() -> void:
	var offer := _VALID_OFFER.duplicate()
	offer["tradable"] = true
	var reasons := ShopRules.violations(offer)
	assert_int(reasons.size()).is_equal(1)
	assert_str(reasons[0]).contains("tradable")
	assert_str(reasons[0]).contains(ShopRules.SOURCES["JONUM"])


func test_tradable_false_is_accepted() -> void:
	var offer := _VALID_OFFER.duplicate()
	offer["tradable"] = false
	assert_bool(ShopRules.validate(offer)).is_true()


func test_multiple_violations_are_all_reported() -> void:
	var offer := _VALID_OFFER.duplicate()
	offer["random"] = true
	offer["tradable"] = true
	offer["currency"] = "USD"
	var reasons := ShopRules.violations(offer)
	assert_int(reasons.size()).is_equal(3)


func test_sources_cite_pegi_dfa_jonum_with_real_content() -> void:
	for key in ["PEGI", "DFA", "JONUM"]:
		assert_bool(ShopRules.SOURCES.has(key)).append_failure_message(
			"ShopRules.SOURCES doit citer %s" % key
		).is_true()
	assert_str(ShopRules.SOURCES["PEGI"]).contains("PEGI")
	assert_str(ShopRules.SOURCES["PEGI"]).contains("2026")
	assert_str(ShopRules.SOURCES["DFA"]).contains("Digital Fairness Act")
	assert_str(ShopRules.SOURCES["JONUM"]).contains("SREN")
	assert_str(ShopRules.SOURCES["JONUM"]).contains("2026")


# ---------------------------------------------------------------------
#  cosmetic_lint.gd — conversion OKLCH
# ---------------------------------------------------------------------

func test_oklch_matches_reserved_magenta() -> void:
	var lch := LINT.oklch(Color(_RESERVED_MAGENTA))
	assert_float(lch[0]).is_equal_approx(0.6947, 0.01)  # L
	assert_float(lch[1]).is_equal_approx(0.2601, 0.01)  # C
	assert_float(lch[2]).is_equal_approx(342.26, 0.5)   # h


func test_oklch_matches_reserved_citron() -> void:
	var lch := LINT.oklch(Color(_RESERVED_CITRON))
	assert_float(lch[0]).is_equal_approx(0.9286, 0.01)
	assert_float(lch[1]).is_equal_approx(0.2257, 0.01)
	assert_float(lch[2]).is_equal_approx(124.21, 0.5)


func test_oklch_matches_safe_ground() -> void:
	var lch := LINT.oklch(Color(_SAFE_GROUND))
	assert_float(lch[2]).is_equal_approx(71.18, 0.5)  # h, hors bande


# ---------------------------------------------------------------------
#  cosmetic_lint.gd — is_reserved()
# ---------------------------------------------------------------------

func test_is_reserved_true_for_magenta_and_citron() -> void:
	var magenta := LINT.oklch(Color(_RESERVED_MAGENTA))
	var citron := LINT.oklch(Color(_RESERVED_CITRON))
	assert_bool(LINT.is_reserved(magenta[2], magenta[1])).is_true()
	assert_bool(LINT.is_reserved(citron[2], citron[1])).is_true()


func test_is_reserved_false_for_safe_ground_and_neutral_gray() -> void:
	var ground := LINT.oklch(Color(_SAFE_GROUND))
	assert_bool(LINT.is_reserved(ground[2], ground[1])).is_false()
	assert_bool(LINT.is_reserved(0.0, 0.0)).is_false()   # gris pur, chroma nulle
	assert_bool(LINT.is_reserved(330.0, 0.0)).is_false()  # teinte réservée, chroma nulle


func test_is_reserved_chroma_threshold_is_strict() -> void:
	# hue=330° tombe dans la bande 300-355 ; C=0,08 ne dépasse PAS le seuil
	# (contrat : "C > 0,08"), C=0,081 le dépasse.
	assert_bool(LINT.is_reserved(330.0, 0.08)).is_false()
	assert_bool(LINT.is_reserved(330.0, 0.081)).is_true()


func test_is_reserved_hue_band_edges_are_inclusive() -> void:
	for hue in [300.0, 355.0, 105.0, 145.0]:
		assert_bool(LINT.is_reserved(hue, 0.5)).append_failure_message(
			"h=%.1f° (bord de bande) aurait dû être réservé" % hue
		).is_true()
	for hue in [299.9, 355.1, 104.9, 145.1]:
		assert_bool(LINT.is_reserved(hue, 0.5)).append_failure_message(
			"h=%.1f° (juste hors bande) n'aurait pas dû être réservé" % hue
		).is_false()


# ---------------------------------------------------------------------
#  cosmetic_lint.gd — reserved_pixel_fraction() / evaluate_image()
# ---------------------------------------------------------------------

func test_reserved_pixel_fraction_is_zero_for_a_safe_texture() -> void:
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(_SAFE_GROUND))
	assert_float(LINT.reserved_pixel_fraction(img)).is_equal_approx(0.0, 0.0001)
	assert_str(LINT.evaluate_image(img)["status"]).is_equal("PASS")


func test_reserved_pixel_fraction_is_one_for_an_all_reserved_texture() -> void:
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(_RESERVED_MAGENTA))
	assert_float(LINT.reserved_pixel_fraction(img)).is_equal_approx(1.0, 0.0001)
	assert_str(LINT.evaluate_image(img)["status"]).is_equal("FAIL")


func test_reserved_pixel_fraction_exactly_two_percent_still_passes() -> void:
	# 100 px, 2 réservés (magenta) : fraction = 0,02 == seuil -> PASS
	# (contrat : "> 2 %", pas ">= 2 %").
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(_SAFE_GROUND))
	img.set_pixel(0, 0, Color(_RESERVED_MAGENTA))
	img.set_pixel(1, 0, Color(_RESERVED_MAGENTA))
	var result := LINT.evaluate_image(img)
	assert_float(result["fraction"]).is_equal_approx(0.02, 0.0001)
	assert_str(result["status"]).is_equal("PASS")


func test_reserved_pixel_fraction_just_above_two_percent_fails() -> void:
	# 100 px, 3 réservés (magenta) : fraction = 0,03 > seuil -> FAIL.
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(_SAFE_GROUND))
	img.set_pixel(0, 0, Color(_RESERVED_MAGENTA))
	img.set_pixel(1, 0, Color(_RESERVED_MAGENTA))
	img.set_pixel(2, 0, Color(_RESERVED_MAGENTA))
	var result := LINT.evaluate_image(img)
	assert_float(result["fraction"]).is_equal_approx(0.03, 0.0001)
	assert_str(result["status"]).is_equal("FAIL")


func test_reserved_pixel_fraction_ignores_fully_transparent_pixels() -> void:
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(_RESERVED_MAGENTA, 0.0))  # 100% réservé en couleur, mais invisible
	assert_float(LINT.reserved_pixel_fraction(img)).is_equal_approx(0.0, 0.0001)


func test_reserved_pixel_fraction_excludes_transparent_pixels_from_denominator() -> void:
	# 10x10 : les 5 premières rangées opaques magenta, les 5 dernières
	# transparentes magenta. Si le calcul comptait le total du bitmap plutôt
	# que les seuls pixels VISIBLES, la fraction lirait 0,5 au lieu de 1,0.
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	for y in range(10):
		for x in range(10):
			var alpha := 1.0 if y < 5 else 0.0
			img.set_pixel(x, y, Color(_RESERVED_MAGENTA, alpha))
	assert_float(LINT.reserved_pixel_fraction(img)).is_equal_approx(1.0, 0.0001)


func test_evaluate_texture_file_reports_error_for_missing_file() -> void:
	var result := LINT.evaluate_texture_file("res://tests/meta/__no_such_skin_texture__.png")
	assert_str(result["status"]).is_equal("ERROR")
