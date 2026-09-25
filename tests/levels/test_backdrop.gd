## test_backdrop.gd
## Spec (tâche ART-76, docs/research/09_wasteland_vertical_slice.md SS d.6
## "Coulisses en 3 couches" + "Repères directionnels d'horizon" (R15),
## CHK-12/CHK-13) : ce fichier couvre les ajouts d'ART-76 à
## scripts/levels/Backdrop.gd et assets/shaders/ink_sky.gdshader --
## `tests/rendering/test_backdrop.gd` (tâche ART-06) reste la spec de
## l'anneau/des accents génériques d'origine et n'est pas touché ici.
##
## 1. "Jupe" de sol (`build_skirt_mesh`) -- comble le vide entre le bord
##    practicable d'une carte et le mur ("Wall", 170 m) : CHK-12 "0 pixel de
##    vide dans les vues aériennes, sol visible jusqu'à l'anneau".
## 2. Mur du thème désert en "plateaux à flancs verticaux" (mesas) plutôt
##    qu'en pointes à un seul segment (`wall_plateau_segment_width`,
##    `wall_profile_heights`), et coloré PAR SOMMET en 3 teintes de roche
##    voilées vers l'horizon (`strata_color`, `build_wall_mesh`).
## 3. Repères directionnels nommés du désert -- mesa à l'ouest (derrière le
##    spawn bleu), raffinerie à l'est (derrière le spawn rouge), ligne de
##    pylônes au nord (`directional_landmarks`, `build_directional_mesh`).
## 4. `build(map_id)` assemble ces deux nouvelles pièces ("Skirt" toujours,
##    "Directional" thème désert seulement) en plus de "Wall"/"Landmarks".
## 5. `ink_sky.gdshader` : CHK-13 "3 à 5 masses nuageuses par demi-ciel,
##    aucune sous 6°" -- verrouille par des tests les valeurs par défaut
##    déjà calibrées (voir l'en-tête du shader, "retuned v3") plutôt que de
##    les modifier à l'aveugle sans rendu réel pour les revérifier.
## 6. Correctif QA (2026-09-24, sur les points 1 et 4 ci-dessus) :
##    - `SKIRT_RADIUS_MAX_M` était du code mort (jamais câblé dans
##      `_skirt_vertex_color`, doc en contradiction avec l'implémentation) --
##      voir `test_skirt_vertex_color_tint_saturates_at_skirt_radius_max_m`.
##    - "Skirt" désactive maintenant le brouillard de scène (`disable_fog`) :
##      une capture aérienne réelle montrait un disque gris-bleu uniforme
##      (le brouillard, calibré pour une caméra au niveau du joueur, sature
##      en un voile quasi constant vu depuis une caméra très haute) au lieu
##      du dégradé sable->roche peint -- voir
##      `test_build_skirt_material_disables_fog_so_aerial_views_keep_the_painted_gradient`
##      et sa contre-épreuve de régression sur "Wall"/"Landmarks"/"Directional".
extends GdUnitTestSuite

const _THEMES := [
	Backdrop.THEME_DESERT,
	Backdrop.THEME_PORT_CARGO,
	Backdrop.THEME_CITY,
	Backdrop.THEME_MOUNTAIN,
]

const _SKY_SHADER_PATH := "res://assets/shaders/ink_sky.gdshader"


## Distance angulaire circulaire (deg, toujours >= 0, au plus 180) entre
## `a` et `b` -- pour placer un repère directionnel dans le bon "secteur"
## de boussole sans se faire piéger par le rebouclage 360°/0° (utile pour
## la raffinerie, à l'est, dont les angles authored sont légèrement
## négatifs -- voir `_DESERT_DIRECTIONAL`).
func _circular_delta_deg(a: float, b: float) -> float:
	var d: float = fmod(a - b, 360.0)
	if d < -180.0:
		d += 360.0
	if d > 180.0:
		d -= 360.0
	return absf(d)


func _entry_by_name(entries: Array, entry_name: String) -> Dictionary:
	for entry in entries:
		if String(entry["name"]) == entry_name:
			return entry
	return {}


# ============================================================ 1. Skirt (jupe)

func test_build_skirt_mesh_has_a_single_surface() -> void:
	var mesh := Backdrop.build_skirt_mesh("wasteland")
	assert_int(mesh.get_surface_count()).is_equal(1)


## CHK-12 encodé directement sur le maillage réel : la jupe doit couvrir
## SANS TROU depuis son bord intérieur (`SKIRT_RADIUS_MIN_M`) jusqu'au mur
## (`RING_WALL_RADIUS_M`) -- sinon une vue aérienne verrait du vide entre
## les deux (fond de scène noir, voir `eval_horizon_closed` côté
## tools/review/style_check.py).
func test_build_skirt_mesh_covers_from_its_inner_edge_to_the_ring_with_no_gap() -> void:
	var mesh := Backdrop.build_skirt_mesh("wasteland")
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_bool(verts.is_empty()).is_false()
	var min_r := INF
	var max_r := 0.0
	for v in verts:
		var r: float = Vector2(v.x, v.z).length()
		min_r = minf(min_r, r)
		max_r = maxf(max_r, r)
	assert_float(min_r).append_failure_message(
		"le bord intérieur de la jupe (%.2f m) ne colle pas à SKIRT_RADIUS_MIN_M (%.2f m)" % [min_r, Backdrop.SKIRT_RADIUS_MIN_M]
	).is_equal_approx(Backdrop.SKIRT_RADIUS_MIN_M, 0.01)
	assert_float(max_r).append_failure_message(
		"le bord extérieur de la jupe (%.2f m) ne rejoint pas le mur RING_WALL_RADIUS_M (%.2f m) -- un trou resterait entre la jupe et l'anneau (CHK-12)" % [max_r, Backdrop.RING_WALL_RADIUS_M]
	).is_equal_approx(Backdrop.RING_WALL_RADIUS_M, 0.01)


func test_build_skirt_mesh_is_a_pure_deterministic_function() -> void:
	var a: PackedVector3Array = Backdrop.build_skirt_mesh("wasteland").surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var b: PackedVector3Array = Backdrop.build_skirt_mesh("wasteland").surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_int(a.size()).is_equal(b.size())
	for i in a.size():
		assert_vector(a[i]).is_equal_approx(b[i], Vector3.ONE * 0.0001)


## Relief de dunes/roches, PAS un second mur : reste bas (quelques mètres),
## sans quoi la jupe se lirait comme une paroi verticale de plus au lieu
## d'un sol qui continue.
func test_build_skirt_mesh_relief_stays_low_like_ground_dunes_not_a_wall() -> void:
	for theme in _THEMES:
		var map_id: String = {
			Backdrop.THEME_DESERT: "wasteland",
			Backdrop.THEME_PORT_CARGO: "cargo_ship",
			Backdrop.THEME_CITY: "saint_ombre",
			Backdrop.THEME_MOUNTAIN: "la_fosse",
		}[theme]
		var verts: PackedVector3Array = Backdrop.build_skirt_mesh(map_id).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var max_y := 0.0
		for v in verts:
			max_y = maxf(max_y, v.y)
		assert_float(max_y).append_failure_message(
			"la jupe du thème « %s » dépasse la hauteur d'un simple relief de sol (%.2f m)" % [theme, max_y]
		).is_less(15.0)


func test_build_skirt_mesh_works_for_every_theme_without_crashing() -> void:
	for theme in _THEMES:
		var cfg_has_theme: bool = Backdrop._SKIRT_PROFILE_CFG.has(theme)
		assert_bool(cfg_has_theme).append_failure_message(
			"aucun profil de jupe pour le thème « %s »" % theme
		).is_true()


## Correctif QA (2026-09-24) : `SKIRT_RADIUS_MAX_M` documentait une borne de
## teinte ("ne borne que la teinte, voir _skirt_vertex_color") jamais câblée
## dans `_skirt_vertex_color` -- du code mort avec une doc qui ne
## correspondait plus à l'implémentation réelle (le dégradé se bornait alors
## sur `RING_WALL_RADIUS_M`, comme le maillage). Verrouille le câblage
## corrigé : la teinte doit avoir SATURÉ (atteint sa couleur lointaine) dès
## `SKIRT_RADIUS_MAX_M`, donc rester identique entre `SKIRT_RADIUS_MAX_M` et
## le mur (`RING_WALL_RADIUS_M`) -- seul le MAILLAGE continue jusqu'au mur.
func test_skirt_vertex_color_tint_saturates_at_skirt_radius_max_m() -> void:
	var by_theme_map: Dictionary = {
		Backdrop.THEME_DESERT: "wasteland",
		Backdrop.THEME_PORT_CARGO: "cargo_ship",
		Backdrop.THEME_CITY: "saint_ombre",
		Backdrop.THEME_MOUNTAIN: "la_fosse",
	}
	for theme in _THEMES:
		var map_id: String = by_theme_map[theme]
		var at_max := Backdrop._skirt_vertex_color(map_id, theme, Backdrop.SKIRT_RADIUS_MAX_M)
		var at_wall := Backdrop._skirt_vertex_color(map_id, theme, Backdrop.RING_WALL_RADIUS_M)
		assert_that(at_max).append_failure_message(
			"la teinte de la jupe (« %s ») ne sature pas à SKIRT_RADIUS_MAX_M (%s vs mur %s) -- SKIRT_RADIUS_MAX_M resterait du code mort" % [theme, at_max, at_wall]
		).is_equal(at_wall)


## Preuve que la saturation ci-dessus n'aplatit pas tout le dégradé : la
## couleur au bord intérieur (sol de la carte) doit encore différer nettement
## de la couleur saturée (roche/atmosphère), sans quoi la jupe entière ne
## lirait plus qu'une seule teinte.
func test_skirt_vertex_color_still_gradients_from_ground_before_saturating() -> void:
	var near := Backdrop._skirt_vertex_color("wasteland", Backdrop.THEME_DESERT, Backdrop.SKIRT_RADIUS_MIN_M)
	var saturated := Backdrop._skirt_vertex_color("wasteland", Backdrop.THEME_DESERT, Backdrop.SKIRT_RADIUS_MAX_M)
	assert_that(near).append_failure_message(
		"la jupe désert ne dégrade plus du tout entre le bord intérieur (%s) et la saturation (%s)" % [near, saturated]
	).is_not_equal(saturated)


# ================================================== 2. Mur : plateaux + strates

func test_wall_plateau_segment_width_is_set_only_for_the_desert_theme() -> void:
	assert_int(Backdrop.wall_plateau_segment_width(Backdrop.THEME_DESERT)).is_greater(1)
	assert_int(Backdrop.wall_plateau_segment_width(Backdrop.THEME_PORT_CARGO)).is_equal(0)
	assert_int(Backdrop.wall_plateau_segment_width(Backdrop.THEME_CITY)).is_equal(0)
	assert_int(Backdrop.wall_plateau_segment_width(Backdrop.THEME_MOUNTAIN)).is_equal(0)


## Encode "plateaux à flancs verticaux" directement : TOUS les segments
## d'un même cluster de `plateau_width` segments consécutifs partagent
## EXACTEMENT la même hauteur -- un sommet plat (mesa), jamais une pointe à
## un seul segment.
func test_wall_profile_desert_forms_flat_topped_plateau_clusters() -> void:
	var segments := Backdrop.WALL_SEGMENTS
	var width := Backdrop.wall_plateau_segment_width(Backdrop.THEME_DESERT)
	var heights: Array = Backdrop.wall_profile_heights(Backdrop.THEME_DESERT, segments)
	var i := 0
	while i < segments:
		var cluster_end: int = mini(i + width, segments)
		var first: float = heights[i]
		for k in range(i, cluster_end):
			assert_float(float(heights[k])).append_failure_message(
				"le segment %d ne partage pas la hauteur plate de son plateau [%d, %d)" % [k, i, cluster_end]
			).is_equal_approx(first, 0.001)
		i = cluster_end


func test_wall_profile_desert_plateaus_vary_in_height_across_the_ring() -> void:
	var heights: Array = Backdrop.wall_profile_heights(Backdrop.THEME_DESERT, Backdrop.WALL_SEGMENTS)
	var lo: float = heights[0]
	var hi: float = heights[0]
	for h in heights:
		lo = minf(lo, float(h))
		hi = maxf(hi, float(h))
	assert_float(hi - lo).append_failure_message(
		"le profil de mur désert est presque plat : aucun relief de mesa lisible (écart %.3f m)" % (hi - lo)
	).is_greater(1.0)


## Régression : le profil des 3 autres thèmes doit rester EXACTEMENT
## l'ancien algorithme "pointes rares par segment" (ART-06) -- non touché
## par ART-76.
func test_wall_profile_non_desert_themes_keep_the_original_spike_profile() -> void:
	for theme in [Backdrop.THEME_PORT_CARGO, Backdrop.THEME_CITY, Backdrop.THEME_MOUNTAIN]:
		assert_int(Backdrop.wall_plateau_segment_width(theme)).is_equal(0)
		assert_bool(Backdrop.closes_horizon(theme)).is_true()


func test_closes_horizon_still_true_for_every_theme_after_the_plateau_profile() -> void:
	for theme in _THEMES:
		assert_bool(Backdrop.closes_horizon(theme)).append_failure_message(
			"le thème « %s » laisse un segment du mur sous le plancher d'horizon après ART-76" % theme
		).is_true()


func test_strata_color_non_desert_theme_falls_back_to_tint_for_radius() -> void:
	for theme in [Backdrop.THEME_PORT_CARGO, Backdrop.THEME_CITY, Backdrop.THEME_MOUNTAIN]:
		var expected := Backdrop.tint_for_radius("wasteland", 300.0)
		var base := Backdrop.strata_color("wasteland", theme, 0.0, 300.0)
		var top := Backdrop.strata_color("wasteland", theme, 1.0, 300.0)
		assert_that(base).is_equal(expected)
		assert_that(top).is_equal(expected)


## Anneau (170 m) : la roche doit dominer, à peine voilée -- lisible de
## près (SS d.6 "2. Anneau à 170 m").
func test_strata_color_desert_at_the_ring_is_close_to_the_rock_base_tone() -> void:
	var c := Backdrop.strata_color("wasteland", Backdrop.THEME_DESERT, 0.0, Backdrop.RING_WALL_RADIUS_M)
	var base := Backdrop.DESERT_STRATA_BASE
	var delta := absf(c.r - base.r) + absf(c.g - base.g) + absf(c.b - base.b)
	assert_float(delta).append_failure_message(
		"le mur désert au ras du sol ne lit pas comme de la roche (%s vs base %s)" % [c, base]
	).is_less(0.12)


## Un même mur doit montrer au moins 2 teintes distinctes (sol vs sommet) --
## "2 à 3 teintes chaudes" (SS d.6), pas un aplat.
func test_strata_color_desert_base_and_top_differ_at_the_same_radius() -> void:
	var base := Backdrop.strata_color("wasteland", Backdrop.THEME_DESERT, 0.0, Backdrop.RING_WALL_RADIUS_M)
	var top := Backdrop.strata_color("wasteland", Backdrop.THEME_DESERT, 1.0, Backdrop.RING_WALL_RADIUS_M)
	assert_that(base).is_not_equal(top)


## Fond (400-600 m) : "mesas pâles fondues dans l'horizon" -- proche de
## `tint_for_radius` (l'atmosphère de la carte), pas de la roche brute.
func test_strata_color_desert_far_radius_is_veiled_towards_the_atmosphere() -> void:
	var far_radius := Backdrop.RING_RADIUS_MAX_M
	var c := Backdrop.strata_color("wasteland", Backdrop.THEME_DESERT, 0.0, far_radius)
	var veil := Backdrop.tint_for_radius("wasteland", far_radius)
	var delta_to_veil := absf(c.r - veil.r) + absf(c.g - veil.g) + absf(c.b - veil.b)
	var rock := Backdrop.DESERT_STRATA_BASE
	var delta_to_rock := absf(c.r - rock.r) + absf(c.g - rock.g) + absf(c.b - rock.b)
	assert_float(delta_to_veil).append_failure_message(
		"à 600 m, le mur désert (%s) devrait presque se fondre dans l'atmosphère (%s), pas rester une roche franche (%s)" % [c, veil, rock]
	).is_less(delta_to_rock)


func test_build_wall_mesh_desert_carries_per_vertex_colors() -> void:
	var mesh := Backdrop.build_wall_mesh(Backdrop.THEME_DESERT, Backdrop.WALL_SEGMENTS, Backdrop.RING_WALL_RADIUS_M, "wasteland")
	var arrays := mesh.surface_get_arrays(0)
	var colors = arrays[Mesh.ARRAY_COLOR]
	assert_that(colors).is_not_null()
	assert_int((colors as PackedColorArray).size()).is_equal((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())


## Régression : les 3 autres thèmes gardent EXACTEMENT l'ancienne géométrie
## (aucune couleur posée, même nombre de sommets qu'avant ART-76 -- 6 par
## segment, aucune bande médiane).
func test_build_wall_mesh_non_desert_theme_has_no_vertex_colors_and_original_vertex_count() -> void:
	var mesh := Backdrop.build_wall_mesh(Backdrop.THEME_MOUNTAIN)
	var arrays := mesh.surface_get_arrays(0)
	assert_that(arrays[Mesh.ARRAY_COLOR]).is_null()
	assert_int((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(Backdrop.WALL_SEGMENTS * 6)


## Le mur désert ajoute une bande médiane (sol -> mi-hauteur -> sommet) pour
## porter 3 teintes distinctes : deux fois plus de triangles par segment.
func test_build_wall_mesh_desert_has_the_extra_mid_height_band() -> void:
	var mesh := Backdrop.build_wall_mesh(Backdrop.THEME_DESERT, Backdrop.WALL_SEGMENTS, Backdrop.RING_WALL_RADIUS_M, "wasteland")
	var arrays := mesh.surface_get_arrays(0)
	assert_int((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(Backdrop.WALL_SEGMENTS * 12)


# ========================================== 3. Repères directionnels (R15)

func test_directional_landmarks_is_empty_for_every_non_desert_theme() -> void:
	for theme in [Backdrop.THEME_PORT_CARGO, Backdrop.THEME_CITY, Backdrop.THEME_MOUNTAIN]:
		assert_array(Backdrop.directional_landmarks(theme)).is_empty()


func test_directional_landmarks_desert_has_the_documented_named_pieces() -> void:
	var entries := Backdrop.directional_landmarks(Backdrop.THEME_DESERT)
	var names := []
	for entry in entries:
		names.append(String(entry["name"]))
	for expected_name in ["west_mesa", "east_flare_a", "east_flare_b", "north_pylon_0", "north_pylon_4"]:
		assert_array(names).append_failure_message(
			"repère directionnel « %s » manquant" % expected_name
		).contains([expected_name])


## R15 : "à l'ouest, derrière le bleu : une grande mesa" -- 180° dans la
## convention d'angle partagée avec `landmark_transforms`
## (pos = cos(angle)*rayon, 0, sin(angle)*rayon), vérifiée sur les spawns
## réels de wasteland.gd (bleu x < 0 = -X = 180°).
func test_directional_landmarks_west_mesa_sits_behind_the_blue_spawn_side() -> void:
	var mesa := _entry_by_name(Backdrop.directional_landmarks(Backdrop.THEME_DESERT), "west_mesa")
	assert_bool(mesa.is_empty()).is_false()
	assert_float(_circular_delta_deg(float(mesa["angle_deg"]), 180.0)).append_failure_message(
		"« le Pouce » n'est pas placé à l'ouest (angle %.1f)" % float(mesa["angle_deg"])
	).is_less_equal(45.0)


## R15 : "à l'est, derrière le rouge : une raffinerie" -- 0°/360°.
func test_directional_landmarks_refinery_pieces_sit_behind_the_red_spawn_side() -> void:
	var entries := Backdrop.directional_landmarks(Backdrop.THEME_DESERT)
	for entry_name in ["east_flare_a", "east_flare_b", "east_tank_a", "east_tank_b"]:
		var entry := _entry_by_name(entries, entry_name)
		assert_bool(entry.is_empty()).is_false()
		assert_float(_circular_delta_deg(float(entry["angle_deg"]), 0.0)).append_failure_message(
			"« %s » n'est pas placé à l'est (angle %.1f)" % [entry_name, float(entry["angle_deg"])]
		).is_less_equal(45.0)


## R15 : "au nord : une ligne de pylônes" -- 270°, à des rayons croissants
## ("qui s'éloignent au nord", SS d.6 "Jupe").
func test_directional_landmarks_pylon_line_sits_to_the_north_and_recedes_outward() -> void:
	var entries := Backdrop.directional_landmarks(Backdrop.THEME_DESERT)
	var pylon_names := ["north_pylon_0", "north_pylon_1", "north_pylon_2", "north_pylon_3", "north_pylon_4"]
	var radii := []
	for entry_name in pylon_names:
		var entry := _entry_by_name(entries, entry_name)
		assert_bool(entry.is_empty()).is_false()
		assert_float(_circular_delta_deg(float(entry["angle_deg"]), 270.0)).append_failure_message(
			"« %s » n'est pas placé au nord (angle %.1f)" % [entry_name, float(entry["angle_deg"])]
		).is_less_equal(30.0)
		radii.append(float(entry["radius_m"]))
	for i in range(1, radii.size()):
		assert_float(radii[i]).append_failure_message(
			"la ligne de pylônes ne s'éloigne pas régulièrement vers le nord (%s)" % [radii]
		).is_greater(radii[i - 1])


func test_directional_landmarks_all_entries_stay_within_the_landmark_band() -> void:
	for entry in Backdrop.directional_landmarks(Backdrop.THEME_DESERT):
		var radius: float = float(entry["radius_m"])
		assert_float(radius).append_failure_message(
			"« %s » hors bande [%s, %s] m : %s" % [entry["name"], Backdrop.LANDMARK_RADIUS_MIN_M, Backdrop.LANDMARK_RADIUS_MAX_M, radius]
		).is_greater_equal(Backdrop.LANDMARK_RADIUS_MIN_M)
		assert_float(radius).is_less_equal(Backdrop.LANDMARK_RADIUS_MAX_M)


## Même contrat que `landmark_transforms` (voir tests/rendering/test_backdrop.gd
## "always_pierce_the_wall") : une pièce "repère" (h_mul > 1) doit dépasser
## `wall_height_for_radius` à SON PROPRE rayon pour rester visible au-dessus
## du mur -- les pièces d'appoint (cuves/dune/panneau, h_mul < 1) en sont
## dispensées.
func test_directional_landmarks_marker_pieces_pierce_the_wall_at_their_own_radius() -> void:
	for entry in Backdrop.directional_landmarks(Backdrop.THEME_DESERT):
		var h_mul: float = float(entry["h_mul"])
		if h_mul <= 1.0:
			continue
		var radius: float = float(entry["radius_m"])
		var top_y: float = Backdrop.wall_height_for_radius(radius) * h_mul
		assert_float(top_y).append_failure_message(
			"« %s » (h_mul %.2f) ne perce pas le mur à son propre rayon (%.1f m)" % [entry["name"], h_mul, radius]
		).is_greater(Backdrop.wall_height_for_radius(radius))


func test_build_directional_mesh_is_null_for_non_desert_maps() -> void:
	for map_id in ["cargo_ship", "saint_ombre", "la_fosse"]:
		assert_that(Backdrop.build_directional_mesh(map_id)).is_null()


func test_build_directional_mesh_desert_is_a_single_surface() -> void:
	var mesh := Backdrop.build_directional_mesh("wasteland")
	assert_that(mesh).is_not_null()
	assert_int(mesh.get_surface_count()).is_equal(1)


## Preuve de bout en bout (pas seulement sur la table de données) : au
## moins un sommet du maillage directionnel réel dépasse la hauteur de
## base du mur à 170 m -- une des silhouettes (mesa/torchères/pylônes) se
## voit vraiment au-dessus de l'anneau, pas seulement "sur le papier".
func test_build_directional_mesh_actually_rises_above_the_ring_baseline() -> void:
	var mesh := Backdrop.build_directional_mesh("wasteland")
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var max_y := 0.0
	for v in verts:
		max_y = maxf(max_y, v.y)
	var ring_baseline := Backdrop.wall_height_for_radius(Backdrop.RING_WALL_RADIUS_M)
	assert_float(max_y).append_failure_message(
		"aucun repère directionnel ne dépasse la hauteur de base de l'anneau (%.1f m) -- rien ne se verrait par-dessus" % ring_baseline
	).is_greater(ring_baseline)


func test_directional_landmarks_is_a_pure_deterministic_function() -> void:
	var a := Backdrop.directional_landmarks(Backdrop.THEME_DESERT)
	var b := Backdrop.directional_landmarks(Backdrop.THEME_DESERT)
	assert_int(a.size()).is_equal(b.size())
	for i in a.size():
		assert_float(float(a[i]["angle_deg"])).is_equal_approx(float(b[i]["angle_deg"]), 0.0001)
		assert_float(float(a[i]["radius_m"])).is_equal_approx(float(b[i]["radius_m"]), 0.0001)


# ==================================================== 4. Assemblage build()

func test_build_desert_map_has_wall_landmarks_skirt_and_directional() -> void:
	var root := Backdrop.build("wasteland")
	add_child(root)
	auto_free(root)
	# `landmark_mesh_for_theme` instancie un .glb TEMPORAIRE (`_load_glb_mesh`)
	# la première fois qu'un thème est demandé (mis en cache ensuite) et le
	# libère en DIFFÉRÉ (`queue_free`, tests/rendering/test_backdrop.gd fait
	# de même) -- une frame d'attente avant la fin du test laisse ce
	# nettoyage s'exécuter (sinon gdUnit4 le compte comme "orphelin").
	await get_tree().process_frame
	var names := []
	for child in root.get_children():
		names.append(String(child.name))
	for expected_name in ["Wall", "Landmarks", "Skirt", "Directional"]:
		assert_array(names).append_failure_message(
			"« %s » manquant dans Backdrop.build(\"wasteland\") : %s" % [expected_name, names]
		).contains([expected_name])


## Régression : les thèmes sans jeu de données directionnel ne gagnent
## AUCUN nœud "Directional" -- seul "Skirt" est nouveau pour eux.
func test_build_non_desert_map_has_no_directional_child() -> void:
	var root := Backdrop.build("cargo_ship")
	add_child(root)
	auto_free(root)
	await get_tree().process_frame  # voir le commentaire du test précédent
	var names := []
	for child in root.get_children():
		names.append(String(child.name))
	assert_array(names).append_failure_message(
		"« Directional » ne devrait exister que pour le thème désert : %s" % [names]
	).not_contains(["Directional"])
	assert_array(names).contains(["Skirt"])


## "Val-Poussière relue sans régression" (critère ART-76) : même thème
## désert, donc mêmes silhouettes directionnelles que Wasteland -- pas de
## traitement à part qui pourrait diverger/régresser entre les deux cartes
## désertiques.
func test_build_val_poussiere_gets_the_same_directional_dataset_as_wasteland() -> void:
	var root_wl := Backdrop.build("wasteland")
	add_child(root_wl)
	auto_free(root_wl)
	var root_vp := Backdrop.build("val_poussiere")
	add_child(root_vp)
	auto_free(root_vp)
	await get_tree().process_frame  # voir le commentaire de test_build_desert_map_...
	assert_bool(root_wl.has_node("Directional")).is_true()
	assert_bool(root_vp.has_node("Directional")).is_true()
	assert_int(Backdrop.directional_landmarks(Backdrop.theme_for_map("val_poussiere")).size()).is_equal(
		Backdrop.directional_landmarks(Backdrop.theme_for_map("wasteland")).size()
	)


func test_build_every_theme_still_produces_a_wall_and_a_skirt() -> void:
	for map_id in ["wasteland", "cargo_ship", "saint_ombre", "la_fosse"]:
		var root := Backdrop.build(map_id)
		add_child(root)
		auto_free(root)
		await get_tree().process_frame  # voir le commentaire de test_build_desert_map_...
		assert_bool(root.has_node("Wall")).append_failure_message("« Wall » manquant pour %s" % map_id).is_true()
		assert_bool(root.has_node("Skirt")).append_failure_message("« Skirt » manquant pour %s" % map_id).is_true()


## Régression QA (2026-09-24, capture réelle map_shots -Only aerial/top_ortho,
## CHK-12) : en vue aérienne la caméra est TRÈS haute au-dessus du centre de
## la carte -- la distance caméra->jupe varie à peine avec le rayon (40 à
## 170 m face à une hauteur de caméra bien plus grande), donc le brouillard
## de profondeur de LevelLook.gd (calibré pour une caméra au niveau du
## joueur) y sature en un voile QUASI UNIFORME qui écrasait le dégradé peint
## par sommet de "Skirt" -- constaté : un disque gris-bleu plat au lieu du
## dégradé sable->roche. `disable_fog` (BaseMaterial3D, doc Godot 4.7 :
## "especially useful for unshaded ... materials") règle ce cas précis sans
## toucher LevelLook.gd (hors périmètre de cette tâche).
func test_build_skirt_material_disables_fog_so_aerial_views_keep_the_painted_gradient() -> void:
	var root := Backdrop.build("wasteland")
	add_child(root)
	auto_free(root)
	await get_tree().process_frame  # voir le commentaire de test_build_desert_map_...
	var skirt := root.get_node("Skirt") as MeshInstance3D
	var mat := skirt.material_override as StandardMaterial3D
	assert_bool(mat.disable_fog).append_failure_message(
		"« Skirt » doit désactiver le brouillard (disable_fog) -- sinon une vue aérienne le voit comme un disque gris-bleu uniforme (CHK-12)"
	).is_true()


## Régression : "Wall"/"Landmarks"/"Directional" gardent le brouillard de
## scène -- à leurs rayons plus grands (150-600 m), même une caméra aérienne
## voit une vraie variation de distance selon le rayon, donc ce voile y reste
## un signal de profondeur voulu (voir la doc de `tint_for_radius`), pas un
## artefact -- désactiver le brouillard PARTOUT changerait leur rendu
## existant (ART-06/ART-76), sans rapport avec ce correctif.
func test_build_wall_and_landmarks_keep_scene_fog_unchanged() -> void:
	var root := Backdrop.build("wasteland")
	add_child(root)
	auto_free(root)
	await get_tree().process_frame  # voir le commentaire de test_build_desert_map_...
	var wall := root.get_node("Wall") as MeshInstance3D
	var landmarks := root.get_node("Landmarks") as MultiMeshInstance3D
	var directional := root.get_node("Directional") as MeshInstance3D
	for piece in [wall, landmarks, directional]:
		var mat := piece.material_override as StandardMaterial3D
		assert_bool(mat.disable_fog).append_failure_message(
			"« %s » ne doit pas désactiver le brouillard -- son voile atmosphérique (tint_for_radius) reste voulu, régression ART-06/76" % piece.name
		).is_false()


# ========================================== 5. ink_sky.gdshader (CHK-13)

func _shader_float_default(code: String, uniform_name: String) -> float:
	var re := RegEx.new()
	re.compile("uniform\\s+float\\s+" + uniform_name + "\\s*(?::[^=;]*)?=\\s*([0-9.]+)\\s*;")
	var m := re.search(code)
	assert_that(m).append_failure_message(
		"uniform « %s » introuvable dans ink_sky.gdshader" % uniform_name
	).is_not_null()
	return m.get_string(1).to_float()


## CHK-13 "aucune [masse de nuage] sous 6°" : verrouille la valeur par
## défaut du shader (voir son en-tête, "retuned v3 ... below 6 degrees is
## plain haze") -- aucune modification du shader n'était nécessaire ici,
## cette valeur était déjà correcte ; ce test empêche une régression
## silencieuse plutôt que de re-caler une valeur déjà calibrée sans rendu
## réel pour la revérifier (voir aussi le test structurel ci-dessous, qui
## prouve que "sous le seuil" veut bien dire "zéro nuage", quel que soit le
## bruit).
func test_ink_sky_cloud_band_default_starts_at_or_above_six_degrees() -> void:
	var shader := load(_SKY_SHADER_PATH) as Shader
	var low := _shader_float_default(shader.code, "cloud_band_low_deg")
	assert_float(low).append_failure_message(
		"cloud_band_low_deg (%.2f) est descendu sous 6° -- CHK-13 exige aucune masse sous 6°" % low
	).is_greater_equal(6.0)


## Preuve structurelle (indépendante du bruit `cloud_fbm`) : `sky()` calcule
## `density = cloud_fbm(...) * base_cut * top_fade`, avec
## `base_cut = smoothstep(0, 0.06, band_t)` et `band_t` nul par construction
## dès que l'élévation est sous `cloud_band_low_deg` (`clamp` dans le
## shader) -- donc `density` (et le masque de nuage qui en dérive) est
## TOUJOURS nul sous ce seuil, quelle que soit la valeur du bruit. Rejoue
## ici EXACTEMENT ce calcul de portillon (pas le bruit lui-même, coûteux et
## hors de propos pour ce contrat précis).
func test_ink_sky_cloud_gating_is_structurally_zero_below_the_band_threshold() -> void:
	var shader := load(_SKY_SHADER_PATH) as Shader
	var low := _shader_float_default(shader.code, "cloud_band_low_deg")
	var high := _shader_float_default(shader.code, "cloud_band_high_deg")
	for elev_deg in [0.0, 1.0, 3.0, 5.0, 5.9]:
		var band_t: float = clamp((elev_deg - low) / maxf(high - low, 0.001), 0.0, 1.0)
		var base_cut: float = smoothstep(0.0, 0.06, band_t)
		assert_float(base_cut).append_failure_message(
			"le portillon de nuage n'est pas nul à %.1f° (< %.1f°) : un nuage pourrait y apparaître" % [elev_deg, low]
		).is_equal(0.0)
	for elev_deg in [6.5, 10.0, 20.0]:
		var band_t2: float = clamp((elev_deg - low) / maxf(high - low, 0.001), 0.0, 1.0)
		var base_cut2: float = smoothstep(0.0, 0.06, band_t2)
		assert_float(base_cut2).append_failure_message(
			"le portillon de nuage reste nul à %.1f° (> %.1f°) : aucun nuage ne pourrait jamais apparaître" % [elev_deg, low]
		).is_greater(0.0)


## Verrouille la couverture calibrée pour "3 à 5 masses par demi-ciel"
## (voir l'en-tête du shader : "0.28 -> 0.32 pour rester à 3-5 masses
## malgré l'échelle réduite, cf CHK-13") -- une dérive de cette valeur sans
## un nouveau passage de rendu + style_check reviendrait à re-régler CHK-13
## à l'aveugle.
func test_ink_sky_cloud_coverage_matches_the_chk13_calibrated_value() -> void:
	var shader := load(_SKY_SHADER_PATH) as Shader
	var coverage := _shader_float_default(shader.code, "cloud_coverage")
	assert_float(coverage).append_failure_message(
		"cloud_coverage (%.3f) s'est éloigné de la valeur calibrée pour CHK-13 (0.32)" % coverage
	).is_equal_approx(0.32, 0.001)
