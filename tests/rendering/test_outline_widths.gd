## test_outline_widths.gd
## Spec (docs/STYLE_BIBLE.md §7.3 "ink_outline.gdshader" v3, tâche ART-08) :
## - nouveau `bottom_weight` = 1,25 : le trait s'épaissit de 25 % sous 0,3 m
##   (pieds) pour ancrer le corps au sol (encre tremblée, épingle 06).
## - table de largeurs par distance (§7.3) à ±0,1 px pour "Personnage
##   (allié / neutre)" et "Ennemi : coque de surbrillance", à 5, 10, 20, 30,
##   40, 60 et 90 m. L'ancienne courbe au-delà de `falloff_far_m` (mix vers
##   `falloff_floor_px` avec un facteur fixe 0,6) sortait de la tolérance à
##   60 m (1,85 px mesuré pour 1,75 px cible, delta 0,10) et surtout à 90 m
##   (1,70 px pour 1,5 px cible, delta 0,20) : elle est remplacée par une
##   décroissance exponentielle à demi-vie (`falloff_decay_half_life_m`).
## - la coque de surbrillance ennemie ne redescend jamais sous 2,5 px (base
##   de CHK-20, "ne s'efface jamais").
##
## tools/screenshot.gd note que ce projet n'a pas de vrai swapchain en mode
## headless ("il faut un vrai swapchain pour lire le rendu") : gdUnit4 ne
## peut donc pas mesurer une largeur de silhouette en pixels sur un rendu
## réel ici (voir aussi test_ink_edges_transparency.gd, même limite). Un
## `ShaderMaterial.get_shader_parameter()` non explicitement défini renvoie
## d'ailleurs `null` en headless dans ce projet (vérifié : il ne retombe pas
## sur le défaut compilé du shader), donc lire les défauts via un matériau
## ne marche pas non plus ici -- seule la lecture directe de la source
## GLSL (source de vérité unique du fichier que ce test couvre) donne les
## vraies valeurs par défaut. Ce test (a) extrait ces défauts du `.gdshader`
## par regex, (b) reproduit fidèlement la formule de largeur de vertex()
## (interpolation linéaire près -> loin puis décroissance exponentielle à
## demi-vie au-delà de `falloff_far_m`) pour la comparer point par point à
## la table du §7.3, et (c) vérifie par regex que le GLSL implémente belle
## et bien cette même forme de formule (pas juste des uniforms déclarés et
## inutilisés). Une vérification visuelle réelle (CHK-20) reste à faire via
## `tools/char_ingame_shots.gd` avant de clore la checklist STYLE_BIBLE.
extends GdUnitTestSuite

const _SHADER_PATH := "res://assets/shaders/ink_outline.gdshader"

## §7.3 : "Ennemi : coque de surbrillance" -- valeurs posées par
## Cartoon.character(highlight_color=...) (hors périmètre de cette tâche) ;
## `falloff_near_m`/`falloff_far_m`/`falloff_decay_half_life_m` restent aux
## défauts du shader (Cartoon.gd ne les redéfinit jamais par usage, seuls
## `outline_width_px`/`falloff_far_px`/`falloff_floor_px` changent).
const _ENEMY_HIGHLIGHT_OVERRIDES := {
	"outline_width_px": 3.5,
	"falloff_far_px": 2.5,
	"falloff_floor_px": 2.5,
}

const _CHARACTER_TABLE_M_PX := {
	5.0: 3.0,
	10.0: 3.0,
	20.0: 2.7,
	30.0: 2.3,
	40.0: 2.0,
	60.0: 1.75,
	90.0: 1.5,
}

const _ENEMY_HIGHLIGHT_TABLE_M_PX := {
	5.0: 3.5,
	10.0: 3.5,
	20.0: 3.2,
	30.0: 2.8,
	40.0: 2.5,
	60.0: 2.5,
	90.0: 2.5,
}


func _source() -> String:
	return FileAccess.get_file_as_string(_SHADER_PATH)


## Lit la valeur par défaut réellement écrite dans la déclaration GLSL de
## `uniform_name` (ex. `uniform float bottom_weight : hint_range(...) =
## 1.25;` -> 1.25). C'est la seule façon fiable de lire un défaut de shader
## dans ce projet en headless (voir docstring du fichier).
func _uniform_default(source: String, uniform_name: String) -> float:
	var re := RegEx.new()
	re.compile("uniform\\s+float\\s+%s\\s*(?::[^=;]*)?=\\s*([0-9]*\\.?[0-9]+)\\s*;" % uniform_name)
	var m := re.search(source)
	assert_that(m).append_failure_message(
		"uniform float %s introuvable (ou sans valeur par défaut) dans %s" % [uniform_name, _SHADER_PATH]
	).is_not_null()
	return m.get_string(1).to_float()


## Reproduit exactement le calcul de largeur de vertex() dans
## ink_outline.gdshader : plat jusqu'à `falloff_near_m`, interpolation
## linéaire vers `falloff_far_px` à `falloff_far_m`, puis décroissance
## exponentielle à demi-vie `falloff_decay_half_life_m` vers
## `falloff_floor_px` au-delà -- jamais sous le plancher.
func _width_at(dist_m: float, p: Dictionary) -> float:
	var near_m: float = p["falloff_near_m"]
	var far_m: float = p["falloff_far_m"]
	var far_px: float = p["falloff_far_px"]
	var floor_px: float = p["falloff_floor_px"]
	var half_life_m: float = p["falloff_decay_half_life_m"]
	var t: float = clampf((dist_m - near_m) / maxf(far_m - near_m, 0.001), 0.0, 1.0)
	var w: float = lerpf(p["outline_width_px"], far_px, t)
	if dist_m > far_m:
		var decay: float = pow(0.5, (dist_m - far_m) / maxf(half_life_m, 0.001))
		w = floor_px + (far_px - floor_px) * decay
	return maxf(w, floor_px)


func _character_params() -> Dictionary:
	var source := _source()
	return {
		"outline_width_px": _uniform_default(source, "outline_width_px"),
		"falloff_near_m": _uniform_default(source, "falloff_near_m"),
		"falloff_far_m": _uniform_default(source, "falloff_far_m"),
		"falloff_far_px": _uniform_default(source, "falloff_far_px"),
		"falloff_floor_px": _uniform_default(source, "falloff_floor_px"),
		"falloff_decay_half_life_m": _uniform_default(source, "falloff_decay_half_life_m"),
	}


func _enemy_highlight_params() -> Dictionary:
	var p := _character_params()
	for key in _ENEMY_HIGHLIGHT_OVERRIDES:
		p[key] = _ENEMY_HIGHLIGHT_OVERRIDES[key]
	return p


# --------------------------------------------------- uniforms par défaut

func test_default_bottom_weight_is_1_25() -> void:
	assert_float(_uniform_default(_source(), "bottom_weight")).is_equal_approx(1.25, 0.001)


func test_default_bottom_weight_height_is_0_3m() -> void:
	assert_float(_uniform_default(_source(), "bottom_weight_height_m")).is_equal_approx(0.3, 0.001)


func test_default_character_falloff_matches_style_bible() -> void:
	var p := _character_params()
	assert_float(p["outline_width_px"]).append_failure_message("outline_width_px").is_equal_approx(3.0, 0.001)
	assert_float(p["falloff_near_m"]).append_failure_message("falloff_near_m").is_equal_approx(10.0, 0.001)
	assert_float(p["falloff_far_m"]).append_failure_message("falloff_far_m").is_equal_approx(40.0, 0.001)
	assert_float(p["falloff_far_px"]).append_failure_message("falloff_far_px").is_equal_approx(2.0, 0.001)
	assert_float(p["falloff_floor_px"]).append_failure_message("falloff_floor_px").is_equal_approx(1.5, 0.001)


# ------------------------------------------- §7.3 : table de largeurs

func test_character_outline_width_table_within_0_1px() -> void:
	var p := _character_params()
	for dist_m in _CHARACTER_TABLE_M_PX:
		var expected: float = _CHARACTER_TABLE_M_PX[dist_m]
		var actual := _width_at(dist_m, p)
		assert_float(actual).append_failure_message(
			"perso à %.0f m : attendu %.2f px, calculé %.3f px" % [dist_m, expected, actual]
		).is_equal_approx(expected, 0.1)


func test_enemy_highlight_outline_width_table_within_0_1px() -> void:
	var p := _enemy_highlight_params()
	for dist_m in _ENEMY_HIGHLIGHT_TABLE_M_PX:
		var expected: float = _ENEMY_HIGHLIGHT_TABLE_M_PX[dist_m]
		var actual := _width_at(dist_m, p)
		assert_float(actual).append_failure_message(
			"coque ennemie à %.0f m : attendu %.2f px, calculé %.3f px" % [dist_m, expected, actual]
		).is_equal_approx(expected, 0.1)


## CHK-20 : "ne s'efface jamais" -- vérifie une plage continue, pas
## seulement les points de la table, y compris bien au-delà (asymptote).
func test_enemy_highlight_never_drops_below_2_5px() -> void:
	var p := _enemy_highlight_params()
	var dist_m := 0.0
	while dist_m <= 500.0:
		assert_float(_width_at(dist_m, p)).append_failure_message(
			"coque ennemie à %.1f m sous 2,5 px" % dist_m
		).is_greater_equal(2.5)
		dist_m += 2.5


# --------------------------------------- structure réelle du vertex()

## Preuve que la formule ci-dessus (pas seulement ce test) est bien celle
## implémentée dans le GLSL : décroissance exponentielle à demi-vie
## au-delà de `falloff_far_m`, jamais l'ancien facteur fixe 0,6, et
## toujours reclampée au plancher.
func test_vertex_implements_half_life_decay_beyond_far_m() -> void:
	var source := _source()
	assert_str(source).append_failure_message(
		"le vertex() n'utilise plus falloff_decay_half_life_m"
	).contains("falloff_decay_half_life_m")
	var re_decay := RegEx.new()
	re_decay.compile("pow\\(\\s*0\\.5\\s*,\\s*\\(dist\\s*-\\s*falloff_far_m\\)\\s*/\\s*max\\(falloff_decay_half_life_m")
	assert_that(re_decay.search(source)).append_failure_message(
		"vertex() ne calcule pas une décroissance exponentielle à demi-vie pow(0.5, (dist - falloff_far_m) / half_life)"
	).is_not_null()
	var re_old_factor := RegEx.new()
	re_old_factor.compile("t_beyond\\s*\\*\\s*0\\.6")
	assert_that(re_old_factor.search(source)).append_failure_message(
		"l'ancienne courbe à facteur fixe 0.6 (hors tolérance à 60/90 m) est toujours présente"
	).is_null()
	assert_str(source).append_failure_message(
		"width_px n'est plus reclampé au plancher falloff_floor_px"
	).contains("max(w, falloff_floor_px)")


# ------------------------------------------------ bottom_weight (sol)

## Preuve que bottom_weight est réellement appliqué sous le seuil dans le
## vertex shader (pas un uniform déclaré mais mort) : recherche structurelle
## sur le GLSL -- la mesure en pixels n'est pas possible en headless ici.
func test_shader_applies_bottom_weight_below_height_threshold() -> void:
	var source := _source()
	var re := RegEx.new()
	re.compile("VERTEX\\.y\\s*<\\s*bottom_weight_height_m")
	assert_that(re.search(source)).append_failure_message(
		"vertex() ne compare pas VERTEX.y à bottom_weight_height_m"
	).is_not_null()
	var re_apply := RegEx.new()
	re_apply.compile("width_px\\s*\\*=\\s*bottom_weight")
	assert_that(re_apply.search(source)).append_failure_message(
		"vertex() ne multiplie pas width_px par bottom_weight"
	).is_not_null()
