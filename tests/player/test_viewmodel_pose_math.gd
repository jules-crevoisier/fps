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
