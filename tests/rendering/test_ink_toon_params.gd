## test_ink_toon_params.gd
## Spec (docs/STYLE_BIBLE.md §7.2 "ink_toon.gdshader" v3, tâche ART-02) :
## - `band_count` 2 par défaut, `band_softness` 0,10 (bord peint au monde).
## - `shadow_strength` (facteur linéaire brut) est REMPLACÉ par `shadow_value`
##   (0,66, cible de RATIO OKLab L ombre/éclairé, §7.5 "0,62-0,70") +
##   `shadow_tint_mix` (0,40, part de `shadow_tint` mélangée, normalisée par
##   sa propre luminance pour ne piloter que la teinte, jamais la noirceur).
## - `use_vertex_masks` (nouveau, true par défaut) lit `COLOR` peint par le
##   pipeline Blender (§7.9) : R=AO (`ao_min` 0,55), G=arête convexe
##   (`edge_highlight` 0,15), B=gradient de hauteur (`height_grad_min` 0,88 ->
##   `height_grad_max` 1,04).
## - `wash_scale`/`wash_strength` (nouveau, 0,35 / 0,04) : lavis monde basse
##   fréquence en espace monde, casse la répétition triplanaire.
## - `gloss_strength`/`gloss_size` (nouveau, 0 / 0,10) : reflet dur, inactif
##   par défaut (surfaces laquées uniquement, hors périmètre ART-02).
## - `paint_grain_strength` reste à 0 par défaut (inchangé).
## - Les appels existants de Cartoon.gd (`world()`, `prop()`, `character()`,
##   `painted()`, `character_surface()`) restent fonctionnels : aucun d'eux ne
##   référence `shadow_strength` (grep vérifié avant cette tâche) ni aucun des
##   nouveaux uniforms, donc leurs seuls réglages explicites (`albedo_color`,
##   `shadow_tint`, `use_albedo_texture`, `use_triplanar`, `triplanar_scale`,
##   `use_grime_texture`, `grime_texture`, `grime_scale`, `paint_grain_strength`)
##   continuent de fonctionner sur les nouveaux défauts v3.
##
## tools/look_probe.gd (ART-01) n'est pas headless (« il faut un vrai
## swapchain » — voir son en-tête) : gdUnit4 ne peut donc pas mesurer un vrai
## rendu ici (même limite que test_outline_widths.gd/
## test_ink_edges_transparency.gd). `ShaderMaterial.get_shader_parameter()`
## non explicitement défini renvoie `null` en headless dans ce projet (vérifié
## par ces mêmes tests) : seule la lecture directe de la source GLSL (source
## unique de vérité) donne les vraies valeurs par défaut. Ce test (a) extrait
## les défauts par regex et (b) vérifie par regex que le GLSL implémente belle
## et bien les formules documentées (pas juste des uniforms déclarés et
## inutilisés).
##
## CE QUE CE FICHIER NE PEUT PAS VÉRIFIER (et pourquoi) : le ratio OKLab L
## ombre/éclairé réel (§7.5 « 0,62-0,70 », CHK-01/CHK-09) dépend d'une
## contribution d'ambiance/radiance-map que Godot ajoute AUTOMATIQUEMENT à
## partir du ciel de l'Environment -- hors de portée de `light()`/`fragment()`
## (voir l'en-tête du shader) et donc IMPOSSIBLE à reproduire fidèlement par
## un calcul GDScript hors-rendu. L'exposant -1,5 de `pow(shadow_value, -1.5)`
## dans light() (facteur linéaire ~1,87 -- une ÉCLAIRCIE, pas un assombrissement,
## malgré le nom "shadow") est calibré EMPIRIQUEMENT contre cette ambiance
## réelle, mesuré via `tools/look_probe.gd` sur les 8 cartes de
## `Cartoon._MAP_PALETTES` (rapport de tâche ART-02, pas ce test) : ratio
## 0,633-0,660 sur les 8, confortablement dans la cible 0,62-0,70. Les tests
## ci-dessous vérifient donc uniquement la STRUCTURE de la formule (le bon
## exposant, la bonne normalisation de teinte) -- jamais une prédiction de
## ratio réel.
extends GdUnitTestSuite

const _SHADER_PATH := "res://assets/shaders/ink_toon.gdshader"


func _source() -> String:
	return FileAccess.get_file_as_string(_SHADER_PATH)


## Lit la valeur par défaut réellement écrite dans la déclaration GLSL de
## `uniform_name` (ex. `uniform float shadow_value : hint_range(...) =
## 0.66;` -> 0.66). Seule façon fiable de lire un défaut de shader dans ce
## projet en headless (voir docstring du fichier).
func _uniform_default(source: String, uniform_name: String) -> float:
	var re := RegEx.new()
	re.compile("uniform\\s+float\\s+%s\\s*(?::[^=;]*)?=\\s*(-?[0-9]*\\.?[0-9]+)\\s*;" % uniform_name)
	var m := re.search(source)
	assert_that(m).append_failure_message(
		"uniform float %s introuvable (ou sans valeur par défaut) dans %s" % [uniform_name, _SHADER_PATH]
	).is_not_null()
	return m.get_string(1).to_float()


func _uniform_default_bool(source: String, uniform_name: String) -> bool:
	var re := RegEx.new()
	re.compile("uniform\\s+bool\\s+%s\\s*=\\s*(true|false)\\s*;" % uniform_name)
	var m := re.search(source)
	assert_that(m).append_failure_message(
		"uniform bool %s introuvable (ou sans valeur par défaut) dans %s" % [uniform_name, _SHADER_PATH]
	).is_not_null()
	return m.get_string(1) == "true"


# ========================================================================
# §7.2 : uniforms et valeurs par défaut
# ========================================================================

func test_default_band_count_is_2() -> void:
	assert_float(_uniform_default(_source(), "band_count")).is_equal_approx(2.0, 0.001)


func test_default_band_softness_is_0_10() -> void:
	assert_float(_uniform_default(_source(), "band_softness")).is_equal_approx(0.10, 0.001)


## `shadow_strength` (facteur linéaire v2) est entièrement remplacé -- ne
## doit plus exister comme uniform.
func test_shadow_strength_uniform_no_longer_exists() -> void:
	var re := RegEx.new()
	re.compile("uniform\\s+float\\s+shadow_strength\\b")
	assert_that(re.search(_source())).append_failure_message(
		"shadow_strength doit être remplacé par shadow_value (§7.2)"
	).is_null()


func test_default_shadow_value_is_0_66() -> void:
	assert_float(_uniform_default(_source(), "shadow_value")).is_equal_approx(0.66, 0.001)


func test_default_shadow_tint_mix_is_0_40() -> void:
	assert_float(_uniform_default(_source(), "shadow_tint_mix")).is_equal_approx(0.40, 0.001)


func test_default_use_vertex_masks_is_true() -> void:
	assert_bool(_uniform_default_bool(_source(), "use_vertex_masks")).is_true()


func test_default_ao_min_is_0_55() -> void:
	assert_float(_uniform_default(_source(), "ao_min")).is_equal_approx(0.55, 0.001)


func test_default_edge_highlight_is_0_15() -> void:
	assert_float(_uniform_default(_source(), "edge_highlight")).is_equal_approx(0.15, 0.001)


func test_default_height_grad_is_0_88_to_1_04() -> void:
	assert_float(_uniform_default(_source(), "height_grad_min")).append_failure_message("height_grad_min").is_equal_approx(0.88, 0.001)
	assert_float(_uniform_default(_source(), "height_grad_max")).append_failure_message("height_grad_max").is_equal_approx(1.04, 0.001)


func test_default_wash_scale_is_0_35() -> void:
	assert_float(_uniform_default(_source(), "wash_scale")).is_equal_approx(0.35, 0.001)


func test_default_wash_strength_is_0_04() -> void:
	assert_float(_uniform_default(_source(), "wash_strength")).is_equal_approx(0.04, 0.001)


func test_default_gloss_strength_is_0() -> void:
	assert_float(_uniform_default(_source(), "gloss_strength")).is_equal_approx(0.0, 0.001)


func test_default_gloss_size_is_defined_and_positive() -> void:
	assert_float(_uniform_default(_source(), "gloss_size")).is_greater(0.0)


func test_default_paint_grain_strength_is_still_0() -> void:
	assert_float(_uniform_default(_source(), "paint_grain_strength")).is_equal_approx(0.0, 0.001)


# ========================================================================
# Structure réelle du GLSL : preuve que les uniforms sont bien BRANCHÉS
# (pas juste déclarés et morts), pas seulement leur valeur par défaut.
# ========================================================================

func test_fragment_applies_ao_mask_from_color_r() -> void:
	var re := RegEx.new()
	re.compile("mix\\(ao_min,\\s*1\\.0,\\s*COLOR\\.r\\)")
	assert_that(re.search(_source())).append_failure_message(
		"fragment() n'applique pas le masque AO (R) via mix(ao_min, 1.0, COLOR.r)"
	).is_not_null()


func test_fragment_applies_edge_highlight_from_color_g() -> void:
	var re := RegEx.new()
	re.compile("edge_highlight\\s*\\*\\s*COLOR\\.g")
	assert_that(re.search(_source())).append_failure_message(
		"fragment() n'applique pas edge_highlight sur COLOR.g (arête convexe)"
	).is_not_null()


func test_fragment_applies_height_grad_from_color_b() -> void:
	var re := RegEx.new()
	re.compile("mix\\(height_grad_min,\\s*height_grad_max,\\s*COLOR\\.b\\)")
	assert_that(re.search(_source())).append_failure_message(
		"fragment() n'applique pas le gradient de hauteur (B) via mix(height_grad_min, height_grad_max, COLOR.b)"
	).is_not_null()


func test_vertex_masks_are_gated_by_use_vertex_masks() -> void:
	var re := RegEx.new()
	re.compile("if\\s*\\(\\s*use_vertex_masks\\s*\\)\\s*\\{")
	assert_that(re.search(_source())).append_failure_message(
		"les masques vertex (AO/arête/hauteur) doivent être gatés par use_vertex_masks"
	).is_not_null()


func test_fragment_applies_world_space_wash_using_world_pos_and_wash_scale() -> void:
	var re := RegEx.new()
	re.compile("value_noise3\\(\\s*world_pos\\s*\\*\\s*wash_scale\\s*\\)")
	assert_that(re.search(_source())).append_failure_message(
		"le lavis monde doit échantillonner le bruit en world_pos * wash_scale (espace monde, jamais objet/UV)"
	).is_not_null()


func test_wash_is_gated_by_wash_strength() -> void:
	var re := RegEx.new()
	re.compile("if\\s*\\(\\s*wash_strength\\s*>\\s*0\\.0\\s*\\)")
	assert_that(re.search(_source())).append_failure_message(
		"le lavis monde doit être gaté par wash_strength > 0.0"
	).is_not_null()


## Le lavis ne doit jamais lire comme du bruit facetté : preuve qu'il utilise
## le bruit LISSÉ (value_noise3), jamais hash13() échantillonné via floor()
## comme le fait paint_grain_strength (bruit fin, texel).
func test_wash_uses_smooth_value_noise_not_texel_hash() -> void:
	var source := _source()
	assert_str(source).append_failure_message(
		"value_noise3() (bruit lissé) doit exister pour le lavis monde"
	).contains("float value_noise3(vec3 p)")
	var re_floor_world := RegEx.new()
	re_floor_world.compile("hash13\\(\\s*floor\\(\\s*world_pos")
	assert_that(re_floor_world.search(source)).append_failure_message(
		"le lavis monde ne doit pas échantillonner hash13() via floor(world_pos ...) (facetterait le lavis)"
	).is_null()


func test_fragment_applies_masks_and_wash_before_paint_grain_and_albedo_assignment() -> void:
	var source := _source()
	var mask_pos := source.find("use_vertex_masks) {")
	var wash_pos := source.find("wash_strength > 0.0")
	var grain_pos := source.find("paint_grain_strength > 0.0")
	var albedo_pos := source.find("ALBEDO = base.rgb;")
	assert_int(mask_pos).append_failure_message("masques vertex introuvables avant ALBEDO=base.rgb").is_less(albedo_pos)
	assert_int(wash_pos).append_failure_message("lavis introuvable avant ALBEDO=base.rgb").is_less(albedo_pos)
	assert_int(grain_pos).append_failure_message("paint_grain introuvable avant ALBEDO=base.rgb").is_less(albedo_pos)


## light() : la formule perceptuelle -- shadow_value converti en facteur
## linéaire par pow(., -1.5) (calibration empirique contre l'ambiance
## automatique de Godot, voir l'en-tête du shader -- PAS la dérivation OKLab
## pure +3.0, mesurée insuffisante), la teinte normalisée par sa propre
## luminance avant mix (jamais appliquée brute, sinon elle rajoute sa propre
## noirceur).
func test_light_converts_shadow_value_to_linear_factor_via_calibrated_power() -> void:
	var re := RegEx.new()
	re.compile("pow\\(\\s*clamp\\(shadow_value,\\s*0\\.0,\\s*1\\.0\\),\\s*-1\\.5\\s*\\)")
	assert_that(re.search(_source())).append_failure_message(
		"light() doit convertir shadow_value en facteur linéaire via pow(clamp(shadow_value, 0.0, 1.0), -1.5) (calibration ART-02, voir en-tête du shader)"
	).is_not_null()


## L'exposant -1.5 doit rester le SEUL endroit dans light() qui code cette
## calibration -- pas un vestige de la dérivation OKLab pure (+3.0) laissé en
## commentaire actif ou en code mort ailleurs.
func test_naive_oklab_cube_exponent_is_not_used_in_light() -> void:
	var re := RegEx.new()
	re.compile("pow\\(\\s*clamp\\(shadow_value,\\s*0\\.0,\\s*1\\.0\\),\\s*3\\.0\\s*\\)")
	assert_that(re.search(_source())).append_failure_message(
		"la dérivation OKLab pure (exposant +3.0), mesurée insuffisante contre l'ambiance automatique de Godot, ne doit plus être utilisée"
	).is_null()


func test_light_normalizes_shadow_tint_by_its_own_luma_before_mixing() -> void:
	var source := _source()
	assert_str(source).append_failure_message(
		"shadow_tint doit être normalisée par sa propre luminance (tint_luma) avant le mix"
	).contains("shadow_tint.rgb / max(tint_luma")
	var re := RegEx.new()
	re.compile("mix\\(vec3\\(1\\.0\\),\\s*tint_norm,\\s*shadow_tint_mix\\)")
	assert_that(re.search(source)).append_failure_message(
		"shadow_color doit mélanger vec3(1.0) et la teinte normalisée via shadow_tint_mix"
	).is_not_null()


func test_shadow_color_multiplies_albedo_by_tint_mix_and_linear_factor() -> void:
	var re := RegEx.new()
	re.compile("shadow_color\\s*=\\s*ALBEDO\\s*\\*\\s*mix\\(vec3\\(1\\.0\\),\\s*tint_norm,\\s*shadow_tint_mix\\)\\s*\\*\\s*shadow_linear")
	assert_that(re.search(_source())).append_failure_message(
		"shadow_color doit être ALBEDO * mix(1, tint_norm, shadow_tint_mix) * shadow_linear (§7.2)"
	).is_not_null()


## Le "hot edge" v2 ne fonctionnait qu'avec une bande médiane distincte
## (band_count impair) -- doit être généralisé pour band_count=2 (défaut v3).
func test_hot_edge_no_longer_relies_on_a_fixed_middle_band_index() -> void:
	var source := _source()
	assert_str(source).append_failure_message(
		"l'ancien schéma 'mid_index' (bande médiane fixe, ne marche pas à band_count=2) doit disparaître"
	).not_contains("mid_index")
	assert_str(source).append_failure_message(
		"light() doit calculer la proximité de la frontière de bande la plus proche (nearest_boundary)"
	).contains("nearest_boundary")


func test_hot_edge_terminator_works_at_the_single_boundary_of_two_bands() -> void:
	# Reproduit exactement le calcul de light() : bands=2, step_pos=ndotl*2.
	# À la frontière (ndotl=0.5, step_pos=1.0) : is_terminator doit être ~1.
	# Loin de toute frontière (ndotl=0 ou 1, step_pos=0 ou 2) : ~0.
	var bands := 2.0
	for ndotl_and_expected in [[0.5, 1.0], [0.0, 0.0], [1.0, 0.0]]:
		var ndotl: float = ndotl_and_expected[0]
		var expected: float = ndotl_and_expected[1]
		var step_pos := ndotl * bands
		var nearest_boundary := clampf(roundf(step_pos), 1.0, bands - 1.0)
		var boundary_dist := absf(step_pos - nearest_boundary)
		var is_terminator := 1.0 - smoothstep(0.0, 0.5, boundary_dist)
		assert_float(is_terminator).append_failure_message(
			"ndotl=%.2f : is_terminator=%.3f, attendu ~%.1f" % [ndotl, is_terminator, expected]
		).is_equal_approx(expected, 0.05)


## Reflet dur : ajouté à DIFFUSE_LIGHT (jamais SPECULAR_LIGHT -- le shader
## déclare `specular_disabled`, qui désactive le pipeline spéculaire intégré
## de Godot), gaté par gloss_strength > 0.0, formule smoothstep documentée.
func test_gloss_is_gated_and_added_to_diffuse_light_not_specular() -> void:
	var source := _source()
	var re_gate := RegEx.new()
	re_gate.compile("if\\s*\\(\\s*gloss_strength\\s*>\\s*0\\.0\\s*\\)")
	assert_that(re_gate.search(source)).append_failure_message(
		"le reflet dur doit être gaté par gloss_strength > 0.0"
	).is_not_null()
	var re_formula := RegEx.new()
	re_formula.compile("smoothstep\\(1\\.0\\s*-\\s*gloss_size,\\s*1\\.0\\s*-\\s*gloss_size\\s*\\+\\s*0\\.02,\\s*ndoth\\)")
	assert_that(re_formula.search(source)).append_failure_message(
		"le reflet dur doit utiliser smoothstep(1.0 - gloss_size, 1.0 - gloss_size + 0.02, dot(N, H)) (§7.2)"
	).is_not_null()
	assert_str(source).append_failure_message(
		"le reflet dur doit s'ajouter à DIFFUSE_LIGHT (SPECULAR_LIGHT est mort : render_mode specular_disabled)"
	).contains("DIFFUSE_LIGHT += gloss_color")
	assert_str(source).append_failure_message(
		"render_mode specular_disabled doit rester déclaré (sinon SPECULAR_LIGHT redeviendrait pertinent)"
	).contains("specular_disabled")


func test_gloss_color_mixes_albedo_toward_white() -> void:
	var re := RegEx.new()
	re.compile("mix\\(ALBEDO,\\s*vec3\\(1\\.0\\),\\s*0\\.7\\)")
	assert_that(re.search(_source())).append_failure_message(
		"gloss_color doit être mix(albédo, blanc, 0.7) (§7.2)"
	).is_not_null()


## Correctif retour vérificateur (ART-02, tools/look_probe.gd, CHK-01) :
## `light_tint` doit être normalisée par la LUMA (601) de `LIGHT_COLOR`, pas
## par son canal max -- sinon un `sun_color` saturé (Cartoon._MAP_PALETTES,
## hors périmètre ART-02) assombrit `lit_L` sous la fenêtre CHK-01 même si
## la teinte reste "hue-only" en apparence (voir l'en-tête du shader pour la
## dérivation complète : un canal max normalisé à 1.0 n'implique PAS une
## luma de 1.0 dès que la couleur est saturée).
func test_light_tint_is_normalized_by_luma_not_max_channel() -> void:
	var source := _source()
	var re_luma := RegEx.new()
	re_luma.compile("float\\s+light_luma\\s*=\\s*dot\\(\\s*LIGHT_COLOR\\s*,\\s*vec3\\(0\\.299,\\s*0\\.587,\\s*0\\.114\\)\\s*\\)")
	assert_that(re_luma.search(source)).append_failure_message(
		"light() doit calculer light_luma = dot(LIGHT_COLOR, vec3(0.299, 0.587, 0.114)) (CHK-01)"
	).is_not_null()
	var re_tint := RegEx.new()
	re_tint.compile("vec3\\s+light_tint\\s*=\\s*LIGHT_COLOR\\s*/\\s*max\\(\\s*light_luma,\\s*0\\.001\\s*\\)")
	assert_that(re_tint.search(source)).append_failure_message(
		"light_tint doit être LIGHT_COLOR / max(light_luma, 0.001) (normalisation par luma, pas par canal max)"
	).is_not_null()
	var re_old_max_norm := RegEx.new()
	re_old_max_norm.compile("light_tint\\s*=\\s*LIGHT_COLOR\\s*/\\s*max\\(\\s*max\\(\\s*LIGHT_COLOR\\.r")
	assert_that(re_old_max_norm.search(source)).append_failure_message(
		"l'ancienne normalisation par canal max (LIGHT_COLOR / max(max(LIGHT_COLOR.r, ...))) doit avoir disparu (assombrissait les soleils saturés, CHK-01)"
	).is_null()


## `ramp * light_tint` doit rester la SEULE utilisation de light_tint dans
## light() côté rampe -- preuve que le correctif ne casse pas le branchement
## existant (juste sa normalisation), toujours la dernière étape avant le
## reflet dur optionnel.
func test_diffuse_light_still_adds_ramp_times_light_tint() -> void:
	var re := RegEx.new()
	re.compile("DIFFUSE_LIGHT\\s*\\+=\\s*ramp\\s*\\*\\s*light_tint")
	assert_that(re.search(_source())).append_failure_message(
		"DIFFUSE_LIGHT += ramp * light_tint doit rester branché (correctif CHK-01 ne change que la normalisation)"
	).is_not_null()


## Preuve numérique de la propriété recherchée : une fois normalisée par sa
## PROPRE luma, `light_tint` a toujours une luma 601 de 1,0 -- quelle que
## soit la saturation de la couleur d'entrée -- contrairement à la
## normalisation par canal max (dont la luma résultante dépend de la
## saturation, voir l'en-tête du shader). Reproduit le calcul GDScript, pas
## le rendu réel (impossible hors-rendu, voir la docstring du fichier) :
## sert de garde-fou structurel sur la formule elle-même.
func test_luma_normalized_tint_has_constant_luma_regardless_of_saturation() -> void:
	var luma_weights := Vector3(0.299, 0.587, 0.114)
	# saint_ombre (Cartoon._MAP_PALETTES) : sun_color le plus saturé du
	# roster de cartes (#FFB870) -- celui qui échouait le plus (lit_L=0.6873).
	var saturated_colors := [
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 0.7216, 0.4392),  # #FFB870
	]
	for color in saturated_colors:
		var c: Vector3 = color
		var luma: float = c.x * luma_weights.x + c.y * luma_weights.y + c.z * luma_weights.z
		var tint: Vector3 = c / maxf(luma, 0.001)
		var tint_luma: float = tint.x * luma_weights.x + tint.y * luma_weights.y + tint.z * luma_weights.z
		assert_float(tint_luma).append_failure_message(
			"la luma de light_tint normalisée par luma doit rester 1.0 (couleur %s), obtenu %.4f" % [c, tint_luma]
		).is_equal_approx(1.0, 0.001)


# ========================================================================
# Cohérence numérique de la formule -- PAS une prédiction du ratio OKLab L
# réel (voir la docstring du fichier : l'ambiance automatique de Godot, hors
# de portée de light()/fragment(), rend ça impossible à vérifier hors-rendu).
# ========================================================================

## Reproduit exactement le calcul de `shadow_linear` dans light(). À la
## valeur par défaut verrouillée (0.66), le facteur doit être une ÉCLAIRCIE
## (> 1.0) et non un assombrissement -- surprenant pour un uniform nommé
## "shadow_value", mais nécessaire (voir en-tête du shader : calibré contre
## l'ambiance automatique de Godot qui, seule, plafonne déjà le ratio mesuré
## sous la cible §7.5). Sert de garde-fou : si quelqu'un "corrige" l'exposant
## vers une valeur positive en pensant réparer une erreur de signe, ce test
## échoue et pointe vers l'explication de l'en-tête.
func test_shadow_linear_factor_is_a_brightening_not_a_darkening_at_default() -> void:
	var shadow_linear: float = pow(0.66, -1.5)
	assert_float(shadow_linear).append_failure_message(
		"pow(shadow_value=0.66, -1.5) = %.4f doit être > 1.0 (éclaircie calibrée, voir en-tête du shader)" % shadow_linear
	).is_greater(1.0)
	assert_float(shadow_linear).append_failure_message("valeur exacte attendue ~1.865").is_equal_approx(1.8650, 0.001)


## Monotonie : avec un exposant NÉGATIF, `shadow_linear` DÉCROÎT quand
## `shadow_value` CROÎT (l'inverse de ce qu'on attendrait d'un exposant
## positif) -- propriété directe de la formule, vérifiée pour ne pas
## surprendre un futur ajustement de shadow_value sans relire l'en-tête.
func test_shadow_linear_factor_decreases_as_shadow_value_increases() -> void:
	var lower: float = pow(0.60, -1.5)
	var higher: float = pow(0.70, -1.5)
	assert_float(higher).append_failure_message(
		"pow(0.70, -1.5)=%.4f doit être < pow(0.60, -1.5)=%.4f (exposant négatif)" % [higher, lower]
	).is_less(lower)


# ========================================================================
# Compatibilité Cartoon.gd (appels existants inchangés et fonctionnels)
# ========================================================================

const _INK_TOON_SHADER := preload("res://assets/shaders/ink_toon.gdshader")


func test_cartoon_world_still_builds_a_valid_shader_material_on_v3_shader() -> void:
	var m := Cartoon.world(Color.RED)
	assert_that(m.shader).is_equal(_INK_TOON_SHADER)
	assert_that(m.get_shader_parameter("albedo_color")).is_equal(Color.RED)
	assert_that(m.get_shader_parameter("shadow_tint")).is_not_null()


func test_cartoon_painted_still_sets_triplanar_params_on_v3_shader() -> void:
	var m := Cartoon.painted(&"rust")
	assert_that(m.shader).is_equal(_INK_TOON_SHADER)
	assert_bool(m.get_shader_parameter("use_albedo_texture")).is_true()
	assert_bool(m.get_shader_parameter("use_triplanar")).is_true()


## STYLE_BIBLE.md v3.1 §4.2/§5.3 « aucun grain » + CHK-27 : `_CHARACTER_GRAIN`
## passe à 0 pour tous les kinds (y compris "gear", qui portait 0,06 à l'ère
## ART-02).
func test_cartoon_character_surface_still_sets_paint_grain_on_v3_shader() -> void:
	var m := Cartoon.character_surface(&"gear", Color.BLUE)
	assert_that(m.shader).is_equal(_INK_TOON_SHADER)
	assert_float(m.get_shader_parameter("paint_grain_strength")).is_equal_approx(0.0, 0.001)
