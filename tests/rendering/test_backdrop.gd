## test_backdrop.gd
## Spec (docs/STYLE_BIBLE.md §6.3 "Coulisses (nouveau, obligatoire)", tâche
## ART-06) : un anneau de silhouettes PLATES et UNSHADED entre 150 et 600 m,
## un thème par famille de carte (désert/port-cargo/ville/montagne), qui
## FERME l'horizon à 100 % sous 5° d'élévation -- "plus aucune vue où la
## carte flotte dans le vide" -- posé automatiquement par
## `LevelLook._style()`/`_add_backdrop()` en enfant du parent du
## WorldEnvironment de la carte (scripts/levels/Backdrop.gd,
## scripts/core/LevelLook.gd).
##
## Relance après QA (map_shots sur les 8 cartes) : `_add_backdrop` posait
## `add_child` de façon SYNCHRONE depuis `_on_node_added` (câblé sur
## `node_added`), qui se déclenche PENDANT que Godot itère les enfants d'un
## nœud qui vient lui-même d'entrer dans l'arbre -- ce nœud est alors
## "occupé" et Godot refuse l'ajout (« Parent node is busy setting up
## children »). L'anneau n'était donc JAMAIS posé en jeu réel. Ce fichier
## couvre :
##   - les fonctions pures (theme_for_map, wall_height_for_radius,
##     closes_horizon, landmark_transforms) -- testables sans arbre de scène ;
##   - la preuve que le nœud "Backdrop" est RÉELLEMENT attaché par
##     `LevelLook._add_backdrop()`, y compris quand le WorldEnvironment entre
##     dans l'arbre PENDANT que son parent est encore "occupé" (le scénario
##     exact du bug) -- et que deux appels rapprochés ne posent jamais deux
##     anneaux.
extends GdUnitTestSuite

const _THEMES := [
	Backdrop.THEME_DESERT,
	Backdrop.THEME_PORT_CARGO,
	Backdrop.THEME_CITY,
	Backdrop.THEME_MOUNTAIN,
]


# ------------------------------------------------------------- theme_for_map

func test_theme_for_map_groups_the_eight_maps_into_four_families() -> void:
	# STYLE_BIBLE.md §6.3 : deux cartes par thème, appariées par famille de
	# décor (voir la doc de tête de Backdrop.gd, `_THEME_BY_MAP`).
	assert_str(Backdrop.theme_for_map("val_poussiere")).is_equal(Backdrop.THEME_DESERT)
	assert_str(Backdrop.theme_for_map("wasteland")).is_equal(Backdrop.THEME_DESERT)
	assert_str(Backdrop.theme_for_map("port_ferraille")).is_equal(Backdrop.THEME_PORT_CARGO)
	assert_str(Backdrop.theme_for_map("cargo_ship")).is_equal(Backdrop.THEME_PORT_CARGO)
	assert_str(Backdrop.theme_for_map("saint_ombre")).is_equal(Backdrop.THEME_CITY)
	assert_str(Backdrop.theme_for_map("le_belvedere")).is_equal(Backdrop.THEME_CITY)
	assert_str(Backdrop.theme_for_map("col_du_vautour")).is_equal(Backdrop.THEME_MOUNTAIN)
	assert_str(Backdrop.theme_for_map("la_fosse")).is_equal(Backdrop.THEME_MOUNTAIN)


func test_theme_for_map_unknown_id_falls_back_to_default_theme() -> void:
	# Même repli qu'un `map_id` vide/inconnu côté Cartoon.map_palette().
	assert_str(Backdrop.theme_for_map("does_not_exist")).is_equal(Backdrop.THEME_DESERT)
	assert_str(Backdrop.theme_for_map("")).is_equal(Backdrop.THEME_DESERT)


# ------------------------------------------------------- wall_height_for_radius

func test_wall_height_for_radius_is_eye_height_at_zero_radius() -> void:
	assert_float(Backdrop.wall_height_for_radius(0.0)).is_equal_approx(Backdrop.EYE_HEIGHT_M, 0.001)


func test_wall_height_for_radius_matches_style_bible_horizon_trigonometry() -> void:
	# STYLE_BIBLE.md §6.3 : ferme l'horizon sous 5° -- un mur plein à
	# `radius_m` doit atteindre eye_height + radius * tan(5°) au minimum.
	var radius := Backdrop.RING_WALL_RADIUS_M
	var expected: float = Backdrop.EYE_HEIGHT_M + radius * tan(deg_to_rad(5.0))
	assert_float(Backdrop.wall_height_for_radius(radius)).is_equal_approx(expected, 0.001)


func test_wall_height_for_radius_increases_with_radius() -> void:
	var near := Backdrop.wall_height_for_radius(Backdrop.RING_RADIUS_MIN_M)
	var far := Backdrop.wall_height_for_radius(Backdrop.RING_RADIUS_MAX_M)
	assert_float(far).is_greater(near)


func test_wall_height_for_radius_increases_with_elevation() -> void:
	var shallow := Backdrop.wall_height_for_radius(300.0, 5.0)
	var steep := Backdrop.wall_height_for_radius(300.0, 10.0)
	assert_float(steep).is_greater(shallow)


# ------------------------------------------------------------- closes_horizon

func test_closes_horizon_is_true_for_every_theme() -> void:
	# CHK-12 (ART-06) encodé directement : aucun segment du mur, pour aucun
	# thème, ne doit descendre sous le plancher qui ferme l'horizon à 5°.
	for theme in _THEMES:
		assert_bool(Backdrop.closes_horizon(theme)).append_failure_message(
			"le thème « %s » laisse un segment du mur sous le plancher d'horizon" % theme
		).is_true()


func test_closes_horizon_is_true_for_unknown_theme_fallback_profile() -> void:
	assert_bool(Backdrop.closes_horizon("does_not_exist")).is_true()


# ----------------------------------------------------------- landmark_transforms

func test_landmark_transforms_returns_the_requested_count() -> void:
	assert_int(Backdrop.landmark_transforms(Backdrop.THEME_DESERT).size()).is_equal(Backdrop.LANDMARK_COUNT)
	assert_int(Backdrop.landmark_transforms(Backdrop.THEME_CITY, 7).size()).is_equal(7)


func test_landmark_transforms_stay_within_the_backdrop_band() -> void:
	for xf in Backdrop.landmark_transforms(Backdrop.THEME_MOUNTAIN):
		var t: Transform3D = xf
		var radius: float = Vector2(t.origin.x, t.origin.z).length()
		assert_float(radius).append_failure_message(
			"landmark hors bande [%s, %s] m : %s" % [Backdrop.LANDMARK_RADIUS_MIN_M, Backdrop.LANDMARK_RADIUS_MAX_M, radius]
		).is_greater_equal(Backdrop.LANDMARK_RADIUS_MIN_M)
		assert_float(radius).is_less_equal(Backdrop.LANDMARK_RADIUS_MAX_M)


## Contrat documenté de `landmark_transforms` : l'échelle Y appliquée à un
## maillage de repli haut de 1 m (`_LANDMARK_REF_HEIGHT`) doit toujours
## dépasser `wall_height_for_radius(rayon)` à CE MÊME rayon -- un accent qui
## ne perce jamais le mur ne se distinguerait pas du profil de mur lui-même.
func test_landmark_transforms_always_pierce_the_wall_at_their_own_radius() -> void:
	for theme in _THEMES:
		for xf in Backdrop.landmark_transforms(theme):
			var t: Transform3D = xf
			var radius: float = Vector2(t.origin.x, t.origin.z).length()
			# Sommet du maillage de repli (base au sol, haut de 1 m) une fois
			# transformé : `basis * UP`, l'origine étant toujours à y=0
			# (SS7.9 "origine = base centrée au sol").
			var top_y: float = (t.basis * Vector3.UP).y
			assert_float(top_y).append_failure_message(
				"un accent de « %s » à %.1f m ne perce pas le mur (sommet %.2f <= mur %.2f)" % [
					theme, radius, top_y, Backdrop.wall_height_for_radius(radius)
				]
			).is_greater(Backdrop.wall_height_for_radius(radius))


func test_landmark_transforms_is_a_pure_deterministic_function() -> void:
	# Aucune RNG/horloge lue (voir `_hash01`) : deux appels avec les mêmes
	# arguments doivent renvoyer exactement les mêmes transformations.
	var a := Backdrop.landmark_transforms(Backdrop.THEME_PORT_CARGO)
	var b := Backdrop.landmark_transforms(Backdrop.THEME_PORT_CARGO)
	assert_int(a.size()).is_equal(b.size())
	for i in a.size():
		var ta: Transform3D = a[i]
		var tb: Transform3D = b[i]
		assert_vector(ta.origin).is_equal_approx(tb.origin, Vector3.ONE * 0.0001)


# ------------------------------------------------ attache réelle dans l'arbre

## Cas nominal : `_add_backdrop` sur un parent déjà dans l'arbre (pas
## "occupé"). `add_child.call_deferred` (le fix) veut dire que le nœud
## n'existe PAS encore de façon synchrone -- seulement après la prochaine
## idle frame.
func test_add_backdrop_attaches_the_backdrop_node_after_one_frame() -> void:
	var parent := Node3D.new()
	add_child(parent)
	auto_free(parent)
	var look := LevelLook.new()

	look._add_backdrop(parent)
	assert_bool(parent.has_node("Backdrop")).append_failure_message(
		"add_child.call_deferred ne doit pas attacher le nœud de façon synchrone"
	).is_false()

	await get_tree().process_frame
	assert_bool(parent.has_node("Backdrop")).is_true()
	assert_that(parent.get_node("Backdrop")).is_not_null()
	look.free()


## Reproduit exactement le bug corrigé (QA, map_shots sur les 8 cartes,
## `Parent node is busy setting up children` à LevelLook.gd:187 avant fix) :
## un WorldEnvironment posé en enfant d'un parent HORS ARBRE, puis ce parent
## ajouté d'un seul coup -- son `node_added` (et celui du WorldEnvironment)
## partent alors PENDANT que Godot itère encore les enfants du parent, qui
## est donc "occupé" au moment même où `_style`/`_add_backdrop` s'exécute.
## Avant le fix, l'`add_child` synchrone échouait ici et l'anneau n'était
## jamais posé ; `add_child.call_deferred` retarde l'ajout hors de cette
## fenêtre "occupée".
func test_add_backdrop_still_attaches_when_worldenvironment_enters_inside_a_busy_parent() -> void:
	var look := LevelLook.new()
	add_child(look)
	auto_free(look)

	var parent := Node3D.new()
	var we := WorldEnvironment.new()
	parent.add_child(we)  # hors arbre : aucun `node_added` ne part encore ici
	add_child(parent)     # parent + we entrent ensemble : we.node_added part
	auto_free(parent)      # pendant que `parent` traite encore ses propres enfants

	await get_tree().process_frame
	assert_bool(parent.has_node("Backdrop")).append_failure_message(
		"l'anneau n'a jamais été posé : régression du bug « Parent node is busy setting up children » (LevelLook._add_backdrop)"
	).is_true()


## Garde anti-doublon (LevelLook.gd, commentaire de `_add_backdrop`) : deux
## appels rapprochés sur le MÊME parent, avant que le premier ajout différé
## ne s'exécute, ne doivent poser qu'un seul anneau -- `parent.has_node`
## seul ne suffit plus comme garde une fois l'ajout différé (le nœud
## n'existe pas encore entre les deux appels).
func test_add_backdrop_called_twice_before_the_deferred_frame_only_adds_one_ring() -> void:
	var parent := Node3D.new()
	add_child(parent)
	auto_free(parent)
	var look := LevelLook.new()

	look._add_backdrop(parent)
	look._add_backdrop(parent)  # avant la frame différée : has_node reste faux ici
	await get_tree().process_frame

	var backdrops: Array = []
	for child in parent.get_children():
		if child.name == "Backdrop":
			backdrops.append(child)
	assert_int(backdrops.size()).append_failure_message(
		"deux anneaux posés l'un sur l'autre au lieu d'un seul"
	).is_equal(1)
	look.free()
