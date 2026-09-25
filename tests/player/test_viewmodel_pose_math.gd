## test_viewmodel_pose_math.gd
## Spec (tâche "fp gloves") : maths PURES du geste de rechargement dédié au
## gant gauche (`ViewModel.AnimState.reload_glove_offset`, aucun accès à
## l'arbre de scène — même principe que les autres méthodes de `AnimState`
## testées dans tests/combat/test_weapon_fx.gd).
##
## `solve_grip_transform`/`shortest_arc_basis` (testés ici jusqu'à la tâche
## "fp gloves") ont été SUPPRIMÉS de ViewModel.gd avec le rig fp_arms
## squeletté qu'ils servaient : ils résolvaient l'orientation/l'échelle de
## l'arme pour atteindre une position de main GAUCHE mesurée sur un
## squelette (pose "FP_Hold") — un système qui, après 3 tentatives, produisait
## un bras en travers de l'écran avec une arme illisible (voir scratchpad
## shots/fp_final/fp_ravage.png, décision lead). Le nouveau système (deux
## gants flottants, assets/models/characters/fp_gloves.glb) rattache chaque
## gant DIRECTEMENT à un point d'ancrage déjà présent sur l'arme (origine =
## poignée, empty "Foregrip" — tools/blender/make_weapons.py), sans aucune
## résolution géométrique : plus rien à tester ici pour cette partie.
extends GdUnitTestSuite

const DT := 1.0 / 60.0


# ---------------------------------------------------------------- reload_glove_offset
func test_reload_glove_offset_is_zero_when_not_reloading() -> void:
	var s := ViewModel.AnimState.new()
	assert_vector(s.reload_glove_offset()).is_equal(Vector3.ZERO)


func test_reload_glove_offset_reaches_toward_magazine_mid_reload() -> void:
	var s := ViewModel.AnimState.new()
	s.start_reload(0.5)
	s.tick_reload(0.25)  # milieu du rechargement -> geste au maximum (sin(p*PI), p=0.5)
	var off := s.reload_glove_offset()
	assert_float(off.y).is_less(0.0)     # plonge vers le bas (zone du chargeur)
	assert_float(off.z).is_greater(0.0)  # recule vers le corps, pas vers le canon


func test_reload_glove_offset_peaks_at_full_reach_at_reload_midpoint() -> void:
	var s := ViewModel.AnimState.new()
	s.start_reload(0.5)
	s.tick_reload(0.25)
	assert_vector(s.reload_glove_offset()).is_equal_approx(
		ViewModel.AnimState.RELOAD_GLOVE_REACH, Vector3.ONE * 0.001)


func test_reload_glove_offset_returns_to_zero_after_duration() -> void:
	var s := ViewModel.AnimState.new()
	s.start_reload(0.5)
	var last := Vector3.ZERO
	for i in 40:  # dépasse largement les 0.5 s de rechargement
		s.tick_reload(DT)
		last = s.reload_glove_offset()
	assert_vector(last).is_equal(Vector3.ZERO)


func test_reload_glove_offset_tracks_the_same_timer_as_the_overall_dip() -> void:
	# Les deux doivent démarrer et finir ENSEMBLE (même minuteur partagé
	# reload_t/reload_dur) : le gant ne doit ni traîner ni anticiper le dip
	# d'ensemble du modèle.
	var s := ViewModel.AnimState.new()
	s.start_reload(0.5)
	s.tick_reload(0.5)  # p >= 1.0 -> tick_reload remet reload_t à -1 CE tick
	assert_vector(s.reload_glove_offset()).is_equal(Vector3.ZERO)


# ------------------------------------------------------------- weapon_scale_for / weapon_nudge_for
# Spec (FP-01) : cadrage FPS par ARME (`WeaponDatabase` id), pas seulement par
# catégorie (ART-12) — les silhouettes Tripo peintes (A3D-20) ont chacune
# leurs propres proportions. Pins de non-régression sur les 7 armes déjà
# peintes (id 0..6, voir `assets/models/weapons/*.glb`), mesurées au masque
# avec l'outil OFFICIEL du projet (jamais un seuil/une zone réimplémentés à
# la main) :
#   godot --path . -s res://tools/fp_shots.gd -- --out=<dossier>
#   python tools/review/style_check.py <dossier_run>
# contre les critères réels de docs/STYLE_BIBLE.md §11.4 / docs/style/tokens.json
# (clé `viewmodel`), plus un critère ajouté au 2e passage de FP-01 (décision du
# lead du 2026-09-25, absent de tokens.json/style_check.py donc mesuré à la
# main sur les masques) :
#   CHK-28 : carré central 20 % x 20 % à 0 PIXEL de viewmodel PILE (seuil de
#   pixel non noir > 127) pour les 7 armes.
#   Tiers haut de l'écran : 0 pixel de viewmodel dans le tiers supérieur
#   (y < 1/3 de la hauteur) pour les 7 armes, EN PLUS de CHK-28 (2e passage :
#   le Fracas et le Faucheur montaient jusqu'au bord haut au 1er passage).
#   CHK-29 : couverture d'écran PAR CATÉGORIE (`coverage_hip`, décision du lead
#   du 2026-09-25 qui remplace la fourchette générique "12-28 %" initiale) —
#   poing 7-10 %, SMG 11-15 %, fusil 13-17 %, pompe/lourde 15-19 %,
#   sniper 15-19 %. Tenu pour 6 des 7 armes ; le FAUCHEUR (id 6) est
#   l'exception documentée dans `ViewModel._WEAPON_SCALE_BY_ID` : sa lunette
#   (longue silhouette Tripo peinte) rend CHK-28 + tiers haut et la couverture
#   cible incompatibles à cette échelle de rendu — plus de 20 combinaisons
#   mesurées au 1er passage puis ~45 de plus à une 2e mesure (dichotomie sur
#   l'échelle 1,28-2,00 et le décalage), 12,55 % est le meilleur résultat qui
#   tienne les DEUX critères bloquants pile (mieux que les 11,76 % du 1er
#   passage) ; couverture cible toujours non atteinte, signalé au lead.
# Une valeur change seulement après un nouveau passage au masque, jamais pour
# faire "passer" ce test sans mesure.
func test_weapon_scale_for_matches_tuned_constant_for_each_painted_weapon() -> void:
	assert_float(ViewModel.weapon_scale_for(0)).is_equal_approx(0.95, 0.001)  # Pistolet
	assert_float(ViewModel.weapon_scale_for(1)).is_equal_approx(1.06, 0.001)  # Magnum
	assert_float(ViewModel.weapon_scale_for(2)).is_equal_approx(0.95, 0.001)  # Rafale
	assert_float(ViewModel.weapon_scale_for(3)).is_equal_approx(1.01, 0.001)  # Marqueur
	assert_float(ViewModel.weapon_scale_for(4)).is_equal_approx(1.14, 0.001)  # Ravage
	assert_float(ViewModel.weapon_scale_for(5)).is_equal_approx(1.70, 0.001)  # Fracas
	assert_float(ViewModel.weapon_scale_for(6)).is_equal_approx(1.35, 0.001)  # Faucheur


func test_weapon_nudge_for_matches_tuned_constant_for_each_painted_weapon() -> void:
	assert_vector(ViewModel.weapon_nudge_for(0)).is_equal_approx(Vector3(0.02, -0.006, -0.02), Vector3.ONE * 0.001)
	assert_vector(ViewModel.weapon_nudge_for(1)).is_equal_approx(Vector3(0.0, 0.02, 0.0), Vector3.ONE * 0.001)
	assert_vector(ViewModel.weapon_nudge_for(2)).is_equal_approx(Vector3(0.09, -0.065, -0.04), Vector3.ONE * 0.001)
	assert_vector(ViewModel.weapon_nudge_for(3)).is_equal_approx(Vector3(0.165, -0.10, -0.06), Vector3.ONE * 0.001)
	assert_vector(ViewModel.weapon_nudge_for(4)).is_equal_approx(Vector3(0.145, -0.125, -0.08), Vector3.ONE * 0.001)
	assert_vector(ViewModel.weapon_nudge_for(5)).is_equal_approx(Vector3(0.255, -0.135, -0.09), Vector3.ONE * 0.001)
	assert_vector(ViewModel.weapon_nudge_for(6)).is_equal_approx(Vector3(0.289, -0.118, 0.0), Vector3.ONE * 0.001)


func test_weapon_scale_and_nudge_fall_back_to_category_for_a_weapon_not_yet_painted() -> void:
	# Percuteur (id 9, catégorie RIFLE, ART-13 pas encore livré à l'heure de
	# FP-01) : pas d'entrée par arme -> repli sur le réglage de catégorie
	# hérité d'ART-12, PAS sur celui, propre à Marqueur/Ravage, ci-dessus.
	var percuteur_id := WeaponDatabase.get_by_name("Percuteur")
	assert_object(percuteur_id).is_not_null()
	var id := WeaponDatabase.id_of(percuteur_id)
	assert_float(ViewModel.weapon_scale_for(id)).is_equal_approx(1.46, 0.001)
	assert_vector(ViewModel.weapon_nudge_for(id)).is_equal_approx(Vector3(0.10, -0.09, 0.0), Vector3.ONE * 0.001)


func test_weapon_scale_and_nudge_default_to_neutral_for_an_unknown_id() -> void:
	# Hors limites de WeaponDatabase.PATHS (jamais censé arriver hors tests) :
	# repli neutre, jamais un crash (WeaponDatabase.get_by_id renvoie null).
	assert_float(ViewModel.weapon_scale_for(-1)).is_equal_approx(1.0, 0.001)
	assert_vector(ViewModel.weapon_nudge_for(-1)).is_equal(Vector3.ZERO)
