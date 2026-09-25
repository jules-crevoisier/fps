## test_level_look_atmosphere.gd
## Spec (tâche ART-86, docs/STYLE_BIBLE.md §6.3/§7.5, docs/research/
## 09_wasteland_vertical_slice.md, .orchestrator/refs/wasteland_hero.png) :
## le coin beauté Wasteland rendait un éclairage plat et net jusqu'à
## l'horizon (sol et arrière-plan à la même clarté, aucune brume, ombres
## douces) alors que la référence montre un soleil rasant doré, une brume
## chaude qui détache les plans, une occlusion de contact au sol et des
## ombres portées marquées. `LevelLook.build_environment`/`_apply_key_light`
## appliquent désormais un jeu de valeurs PROPRE À WASTELAND (sourcé depuis
## `WastelandLook`, ART-86) UNIQUEMENT quand `map_id` vaut EXACTEMENT
## `"wasteland"` -- ce fichier verrouille :
##  1. le calcul par-carte (Wasteland diffère bien du réglage partagé) ;
##  2. la RÉGRESSION ZÉRO sur les 7 autres cartes ET sur l'appel à `map_id`
##     vide, déjà verrouillé par `tests/rendering/test_level_look.gd` (fichier
##     hors de mon périmètre -- ces tests-ci le complètent sans le dupliquer).
##
## Bornes utilisées ci-dessous : volontairement LARGES (pas de valeur pixel
## calibrée par un rendu réel, `tools/look_probe.gd`/`map_shots.gd` demandent
## un contexte GPU hors de cette itération -- voir le rendu de la tâche). Ce
## fichier verrouille la DIRECTION et l'AMPLEUR raisonnable du changement, pas
## une valeur retouchée à l'aveugle sans vérification image.
extends GdUnitTestSuite

var _saved_map_id: String


func before_test() -> void:
	# MatchConfig est statique (voir tests/networking/test_match_config_sync.gd) :
	# sauvegarder/restaurer évite de polluer les suites voisines qui supposent
	# `map_id` vide par défaut (dont la suite verrouillée `test_level_look.gd`).
	_saved_map_id = MatchConfig.map_id


func after_test() -> void:
	MatchConfig.map_id = _saved_map_id


# ------------------------------------------------------- 1. Soleil (§6.3)

func test_wasteland_sun_is_lower_and_more_grazing_than_its_own_base_elevation() -> void:
	# La palette de base (StyleTokens.gd, hors périmètre) donne 32° à
	# Wasteland ; ART-86 demande un soleil plus rasant pour cette carte.
	var base_palette: Dictionary = Cartoon.map_palette("wasteland")
	assert_float(WastelandLook.SUN_ELEVATION_DEG).append_failure_message(
		"le soleil Wasteland (%s°) n'est pas plus rasant que sa base palette (%s°)" % [WastelandLook.SUN_ELEVATION_DEG, base_palette["sun_elevation_deg"]]
	).is_less(float(base_palette["sun_elevation_deg"]))


func test_wasteland_sun_elevation_stays_within_the_style_bible_legal_range() -> void:
	# §6.3 : "élévation 22-50° selon la carte" -- un soleil plus rasant ne
	# doit pas sortir de cette fourchette commune aux 8 cartes.
	assert_float(WastelandLook.SUN_ELEVATION_DEG).is_greater_equal(22.0)
	assert_float(WastelandLook.SUN_ELEVATION_DEG).is_less(32.0)


func test_apply_key_light_uses_the_lower_wasteland_elevation_when_map_id_is_wasteland() -> void:
	MatchConfig.map_id = "wasteland"
	var look := LevelLook.new()
	var light := DirectionalLight3D.new()
	# `global_transform` exige que le nœud soit dans l'arbre (voir
	# `_apply_key_light`, commentaire sur `look_at_from_position`) : ajouté
	# ici uniquement pour LIRE le résultat, `_apply_key_light` fonctionnerait
	# aussi hors-arbre (comme le test verrouillé de test_level_look.gd).
	add_child(light)
	auto_free(light)
	look._apply_key_light(light)
	# Reproduit exactement le calcul de `_sun_direction` (voir son en-tête) --
	# `look_at_from_position` a orienté la lumière pour que sa direction -Z
	# vaille ce vecteur.
	var expected := LevelLook._sun_direction(WastelandLook.SUN_ELEVATION_DEG, LevelLook._sun_azimuth_deg("wasteland"))
	var actual := -light.global_transform.basis.z
	assert_vector(actual).append_failure_message(
		"la lumière clé ne pointe pas dans la direction attendue pour le soleil rasant de Wasteland (%s attendu, %s obtenu)" % [expected, actual]
	).is_equal_approx(expected, Vector3.ONE * 0.001)
	look.free()


## Régression : les 7 autres cartes (et l'appel à `map_id` vide, verrouillé par
## `tests/rendering/test_level_look.gd`) gardent l'élévation de LEUR PROPRE
## palette -- aucune fuite du réglage Wasteland ailleurs.
func test_apply_key_light_keeps_the_shared_palette_elevation_for_other_maps() -> void:
	MatchConfig.map_id = "cargo_ship"
	var look := LevelLook.new()
	var light := DirectionalLight3D.new()
	add_child(light)
	auto_free(light)
	look._apply_key_light(light)
	var cargo_palette: Dictionary = Cartoon.map_palette("cargo_ship")
	var expected := LevelLook._sun_direction(float(cargo_palette["sun_elevation_deg"]), LevelLook._sun_azimuth_deg("cargo_ship"))
	var actual := -light.global_transform.basis.z
	assert_vector(actual).append_failure_message(
		"cargo_ship ne devrait pas hériter du soleil rasant de Wasteland"
	).is_equal_approx(expected, Vector3.ONE * 0.001)
	look.free()


# --------------------------------------------- 2. Brouillard de profondeur

func test_wasteland_fog_tint_is_a_light_ocre_outside_reserved_hue_bands() -> void:
	var tint := WastelandLook.FOG_TINT_OCRE
	var hue_deg := tint.h * 360.0
	# Bandes réservées (surbrillance ennemie), interdites dans le décor :
	# 300-355° et 105-145° (CLAUDE.md, docs/STYLE_BIBLE.md §6.4).
	assert_bool(hue_deg >= 300.0 and hue_deg <= 355.0).append_failure_message(
		"la teinte de brume Wasteland (%.1f°) empiète sur la bande réservée 300-355°" % hue_deg
	).is_false()
	assert_bool(hue_deg >= 105.0 and hue_deg <= 145.0).append_failure_message(
		"la teinte de brume Wasteland (%.1f°) empiète sur la bande réservée 105-145°" % hue_deg
	).is_false()
	# "Ocre clair" : teinte chaude jaune-orangée, claire (valeur haute).
	assert_float(hue_deg).append_failure_message(
		"la teinte de brume Wasteland (%.1f°) n'est pas dans la famille ocre (25-55°)" % hue_deg
	).is_between(25.0, 55.0)
	assert_float(tint.v).append_failure_message(
		"la teinte de brume Wasteland (valeur %.2f) n'est pas assez claire pour « ocre clair »" % tint.v
	).is_greater_equal(0.7)


func test_wasteland_depth_fog_is_denser_than_the_shared_default_but_not_a_wall() -> void:
	var env := LevelLook.build_environment("wasteland")
	# Défaut partagé (voir LevelLook.build_environment, branche `else`) : 0,001487.
	assert_float(env.fog_density).append_failure_message(
		"le brouillard de profondeur de Wasteland (%s) ne détache pas plus les plans que le défaut partagé (0.001487)" % env.fog_density
	).is_greater(0.001487)
	# Toujours « léger » au sens de la bible -- pas un mur de brume avant 300 m.
	# amount(300) = 1 - exp(-k*300) ; garder ceci sous 0,70 laisse les repères
	# lointains lisibles (voir le commentaire de calibration de LevelLook.gd).
	var amount_300m := 1.0 - exp(-env.fog_density * 300.0)
	assert_float(amount_300m).append_failure_message(
		"le brouillard de profondeur de Wasteland sature déjà à %.0f%% à 300 m -- devient un mur, pas une brume" % (amount_300m * 100.0)
	).is_less(0.70)


func test_environment_fog_color_is_wasteland_specific_ocre_tint() -> void:
	var env := LevelLook.build_environment("wasteland")
	assert_that(env.fog_light_color).is_equal(WastelandLook.FOG_TINT_OCRE)


# ---------------------------------------------- 3. Brouillard de hauteur

func test_wasteland_gets_a_ground_hugging_height_fog() -> void:
	var env := LevelLook.build_environment("wasteland")
	# `fog_height_density` vaut 0,0 par défaut dans Godot 4.7 (aucun effet) --
	# positif = plus dense quand la hauteur DIMINUE (doc Environment 4.7).
	assert_float(env.fog_height_density).append_failure_message(
		"Wasteland ne reçoit aucun brouillard de hauteur (fog_height_density = %s)" % env.fog_height_density
	).is_greater(0.0)
	# Reste une brume BASSE (quelques mètres), pas un plafond bas généralisé.
	assert_float(env.fog_height).is_greater(0.0)
	assert_float(env.fog_height).is_less_equal(15.0)
	assert_float(env.fog_height_density).is_less_equal(0.5)


func test_other_maps_get_no_height_fog_at_all() -> void:
	for map_id in ["", "cargo_ship", "saint_ombre", "la_fosse", "port_ferraille", "col_du_vautour"]:
		var env := LevelLook.build_environment(map_id)
		assert_float(env.fog_height_density).append_failure_message(
			"la carte « %s » a hérité du brouillard de hauteur de Wasteland (fog_height_density = %s)" % [map_id, env.fog_height_density]
		).is_equal(0.0)
		assert_float(env.fog_height).append_failure_message(
			"la carte « %s » a hérité de fog_height de Wasteland (%s)" % [map_id, env.fog_height]
		).is_equal(0.0)


# --------------------------------------------------------------- 4. SSAO

func test_wasteland_ssao_is_a_touch_stronger_but_stays_light() -> void:
	var env := LevelLook.build_environment("wasteland")
	# Défaut partagé : 0,8/1,0/1,5/0,15 (§7.5). Wasteland ancre un peu plus
	# les props au sol, mais reste « léger » (bornes hautes volontairement
	# modestes -- pas un durcissement généralisé de l'AO).
	assert_float(env.ssao_radius).is_greater(0.8)
	assert_float(env.ssao_radius).is_less_equal(1.2)
	assert_float(env.ssao_intensity).is_greater(1.0)
	assert_float(env.ssao_intensity).is_less_equal(1.3)
	assert_float(env.ssao_power).is_greater_equal(1.5)
	assert_float(env.ssao_power).is_less_equal(2.0)
	assert_float(env.ssao_light_affect).is_greater(0.15)
	assert_float(env.ssao_light_affect).is_less_equal(0.3)


func test_other_maps_keep_the_shared_ssao_table_unchanged() -> void:
	for map_id in ["", "cargo_ship", "saint_ombre"]:
		var env := LevelLook.build_environment(map_id)
		assert_float(env.ssao_radius).append_failure_message(
			"la carte « %s » a hérité du SSAO de Wasteland (rayon %s)" % [map_id, env.ssao_radius]
		).is_equal_approx(0.8, 0.001)
		assert_float(env.ssao_intensity).is_equal_approx(1.0, 0.001)
		assert_float(env.ssao_power).is_equal_approx(1.5, 0.001)
		assert_float(env.ssao_light_affect).is_equal_approx(0.15, 0.001)


# ---------------------------------------------------------- 5. Étalonnage

func test_wasteland_enables_a_modest_ink_compatible_calibration() -> void:
	var env := LevelLook.build_environment("wasteland")
	assert_bool(env.adjustment_enabled).is_true()
	# Modeste : les anciennes valeurs v2 pré-WYSIWYG étaient 1,20/1,04 (voir
	# le tableau §7.5 de LevelLook.gd) -- ce contrat reste EN DEÇÀ pour rester
	# « compatible avec l'encre ».
	assert_float(env.adjustment_saturation).is_greater(1.0)
	assert_float(env.adjustment_saturation).is_less_equal(1.20)
	assert_float(env.adjustment_contrast).is_greater(1.0)
	assert_float(env.adjustment_contrast).is_less_equal(1.10)
	# Pas de décalage d'exposition caché dans la calibration.
	assert_float(env.adjustment_brightness).is_equal_approx(1.0, 0.001)


func test_other_maps_keep_adjustment_disabled_the_wysiwyg_golden_rule() -> void:
	for map_id in ["", "cargo_ship", "saint_ombre", "la_fosse"]:
		var env := LevelLook.build_environment(map_id)
		assert_bool(env.adjustment_enabled).append_failure_message(
			"la carte « %s » a hérité de l'étalonnage de Wasteland -- casse la règle d'or WYSIWYG §7.5" % map_id
		).is_false()


# ------------------------------------------------------- 6. Ombres franches

func test_wasteland_shadows_are_crisper_than_the_shared_penumbra() -> void:
	MatchConfig.map_id = "wasteland"
	var look := LevelLook.new()
	var light := DirectionalLight3D.new()
	look._apply_key_light(light)
	assert_float(light.light_angular_distance).append_failure_message(
		"la pénombre de Wasteland (%s°) n'est pas plus fine que le défaut partagé (0,5°) -- ombres pas plus franches" % light.light_angular_distance
	).is_less(0.5)
	assert_float(light.light_angular_distance).is_greater(0.0)
	look.free()
	light.free()


## Régression : portée et découpage PSSM restent la constante moteur
## partagée (hors périmètre de cette tâche), même pour Wasteland -- seule la
## pénombre change.
func test_wasteland_shadow_range_and_pssm_split_are_unchanged() -> void:
	MatchConfig.map_id = "wasteland"
	var look := LevelLook.new()
	var light := DirectionalLight3D.new()
	look._apply_key_light(light)
	assert_float(light.directional_shadow_max_distance).is_equal_approx(120.0, 0.001)
	assert_int(light.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	assert_bool(light.shadow_enabled).is_true()
	look.free()
	light.free()


## Régression directe sur la table verrouillée de `tests/rendering/
## test_level_look.gd::test_key_light_matches_style_bible_shadow_table` :
## le même appel (map_id vide, défaut de test) doit continuer à lire
## EXACTEMENT 0,5° -- la branche Wasteland ne doit jamais se déclencher sur
## une chaîne vide.
func test_key_light_stays_at_the_shared_penumbra_when_map_id_is_empty() -> void:
	var look := LevelLook.new()
	var light := DirectionalLight3D.new()
	look._apply_key_light(light)
	assert_float(light.light_angular_distance).is_equal_approx(0.5, 0.001)
	look.free()
	light.free()
