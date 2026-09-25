## test_ground_builder.gd
## Spec (tâche ART-85, docs/art/WASTELAND_ART_RESET.md "Coin beauté d'abord" +
## verdict utilisateur 2026-09-25 "le terrain [...] on dirait des modèles 3D
## posés") : `GroundBuilder.build(spec) -> Node3D` -- maillage en grille
## avec relief (bruit doux + piste creusée à deux ornières + jupes de terre),
## couleurs de sommet = poids de mélange normalisés (sable/terre battue/
## piste/roche), collision `HeightMapShape3D` calée sur le maillage à
## +/-2 cm, navmesh bakable sur ce sol.
##
## `height_at`/`weights_at` sont des fonctions PURES (voir l'en-tête de
## GroundBuilder.gd) : la plupart des assertions ci-dessous les appellent
## directement, sans arbre de scène -- rapide, déterministe. Seules les
## sections "collision physique" et "navmesh" ont besoin d'un nœud
## réellement `add_child()`-é (comme tests/maps/test_navmesh.gd/
## tests/ai/test_bot_spots.gd).
extends GdUnitTestSuite

const GroundBuilderScript := preload("res://scripts/levels/ground/GroundBuilder.gd")

const _ROAD_WIDTH := 8.0
const _ROAD_DEPTH := 0.15
const _RUT_OFFSET := 1.4
const _RUT_WIDTH := 0.9
const _RUT_DEPTH := 0.05
const _MOUND_POS := Vector2(5.0, 5.0)
const _MOUND_RADIUS := 2.0
const _MOUND_HEIGHT := 0.12


## Route rectiligne le long de +X à z=0 -- lateral == z, dist == |z| tant que
## x reste dans [-20, 20] (voir GroundBuilder._road_profile).
static func _road_spec(size := Vector2(20.0, 20.0)) -> Dictionary:
	return {
		"size": size, "cell": 0.5, "noise_amp": 0.0,
		"roads": [{
			"points": [Vector2(-20.0, 0.0), Vector2(20.0, 0.0)],
			"width": _ROAD_WIDTH, "depth": _ROAD_DEPTH,
			"ruts": {"offset": _RUT_OFFSET, "width": _RUT_WIDTH, "depth": _RUT_DEPTH},
		}],
	}


static func _mound_spec() -> Dictionary:
	return {
		"size": Vector2(20.0, 20.0), "cell": 0.5, "noise_amp": 0.0,
		"mounds": [{"pos": _MOUND_POS, "radius": _MOUND_RADIUS, "height": _MOUND_HEIGHT}],
	}


static func _mixed_spec() -> Dictionary:
	var spec := _road_spec(Vector2(24.0, 16.0))
	spec["mounds"] = [{"pos": Vector2(9.0, 6.0), "radius": 1.8, "height": 0.1}]
	return spec


# =========================================================== height_at()

func test_road_center_digs_down_by_its_configured_depth() -> void:
	var h := GroundBuilderScript.height_at(_road_spec(), 0.0, 0.0)
	assert_float(h).append_failure_message("piste : hauteur=%.3f, attendu ~-%.2f" % [h, _ROAD_DEPTH]).is_equal_approx(-_ROAD_DEPTH, 0.005)


func test_road_depth_is_clamped_into_the_10_to_20cm_contract_range() -> void:
	var too_shallow := _road_spec()
	too_shallow["roads"][0]["depth"] = 0.02
	var too_deep := _road_spec()
	too_deep["roads"][0]["depth"] = 0.90
	var h_shallow := GroundBuilderScript.height_at(too_shallow, 0.0, 0.0)
	var h_deep := GroundBuilderScript.height_at(too_deep, 0.0, 0.0)
	assert_float(absf(h_shallow)).append_failure_message("profondeur non bornée en bas : %.3f" % h_shallow).is_greater_equal(0.0995)
	assert_float(absf(h_deep)).append_failure_message("profondeur non bornée en haut : %.3f" % h_deep).is_less_equal(0.2005)


func test_rut_center_digs_deeper_than_the_plain_track() -> void:
	var h_rut := GroundBuilderScript.height_at(_road_spec(), 0.0, _RUT_OFFSET)
	var h_track := GroundBuilderScript.height_at(_road_spec(), 0.0, 0.0)
	assert_float(h_rut).append_failure_message("ornière (%.3f) devrait creuser plus que la piste seule (%.3f)" % [h_rut, h_track]).is_less(h_track)
	assert_float(h_rut).append_failure_message("ornière : hauteur=%.3f, attendu ~-(%.2f+%.2f)" % [h_rut, _ROAD_DEPTH, _RUT_DEPTH]).is_equal_approx(-(_ROAD_DEPTH + _RUT_DEPTH), 0.005)


func test_the_two_ruts_are_symmetric_on_either_side_of_the_track_axis() -> void:
	var h_left := GroundBuilderScript.height_at(_road_spec(), 0.0, -_RUT_OFFSET)
	var h_right := GroundBuilderScript.height_at(_road_spec(), 0.0, _RUT_OFFSET)
	assert_float(h_left).append_failure_message("ornières non symétriques : %.4f vs %.4f" % [h_left, h_right]).is_equal_approx(h_right, 0.0001)


func test_track_edge_rises_into_a_raised_lip_above_the_surrounding_ground() -> void:
	var half_width := _ROAD_WIDTH * 0.5
	var h_edge := GroundBuilderScript.height_at(_road_spec(), 0.0, half_width)
	assert_float(h_edge).append_failure_message("bourrelet de bord absent/négatif : %.4f" % h_edge).is_greater(0.0)


func test_far_from_any_road_or_mound_height_is_flat_with_noise_disabled() -> void:
	var h := GroundBuilderScript.height_at(_road_spec(), 0.0, 50.0)
	assert_float(h).append_failure_message("loin de la piste, hauteur=%.4f, attendu ~0" % h).is_equal_approx(0.0, 0.001)


func test_mound_center_reaches_its_configured_height() -> void:
	var h := GroundBuilderScript.height_at(_mound_spec(), _MOUND_POS.x, _MOUND_POS.y)
	assert_float(h).append_failure_message("jupe : hauteur=%.4f, attendu %.2f" % [h, _MOUND_HEIGHT]).is_equal_approx(_MOUND_HEIGHT, 0.0005)


func test_mound_height_fades_to_zero_at_its_radius() -> void:
	var h := GroundBuilderScript.height_at(_mound_spec(), _MOUND_POS.x + _MOUND_RADIUS, _MOUND_POS.y)
	assert_float(h).append_failure_message("jupe pas retombée à 0 au rayon : %.4f" % h).is_equal_approx(0.0, 0.001)


func test_overlapping_mounds_take_the_tallest_not_the_sum() -> void:
	var spec := {
		"size": Vector2(20.0, 20.0), "cell": 0.5, "noise_amp": 0.0,
		"mounds": [
			{"pos": Vector2(0.0, 0.0), "radius": 3.0, "height": 0.10},
			{"pos": Vector2(0.5, 0.0), "radius": 3.0, "height": 0.16},
		],
	}
	var h := GroundBuilderScript.height_at(spec, 0.0, 0.0)
	assert_float(h).append_failure_message("jupes qui se recouvrent : %.4f devrait rester proche de la plus haute (0.16), pas s'additionner" % h).is_less_equal(0.16 + 0.001)
	assert_float(h).is_greater(0.10)


func test_noise_amplitude_bounds_the_relief_away_from_roads_and_mounds() -> void:
	var spec := {"size": Vector2(10.0, 10.0), "cell": 0.5, "noise_amp": 0.05, "seed": 7}
	for i in 12:
		var x := float(i) * 0.83 - 4.0
		var z := float(i) * -0.61 + 3.0
		var h: float = GroundBuilderScript.height_at(spec, x, z)
		assert_float(absf(h)).append_failure_message("bruit hors amplitude à (%.2f,%.2f) : %.4f" % [x, z, h]).is_less_equal(0.05 + 0.0001)


func test_height_at_is_deterministic_for_the_same_spec_and_point() -> void:
	var spec := {"size": Vector2(10.0, 10.0), "cell": 0.5, "noise_amp": 0.05, "seed": 3}
	var a := GroundBuilderScript.height_at(spec, 1.23, -4.56)
	var b := GroundBuilderScript.height_at(spec, 1.23, -4.56)
	assert_float(a).is_equal_approx(b, 0.00001)


# ============================================================ weights_at()

func test_weights_are_always_normalized_to_sum_one() -> void:
	var spec := _mixed_spec()
	var points := [Vector2(0, 0), Vector2(0, 1.4), Vector2(0, 50), Vector2(9, 6), Vector2(9, 7), Vector2(3, -3)]
	for p in points:
		var w: PackedFloat32Array = GroundBuilderScript.weights_at(spec, p.x, p.y)
		var total := w[0] + w[1] + w[2] + w[3]
		assert_float(total).append_failure_message("poids non normalisés en %s : somme=%.4f" % [p, total]).is_equal_approx(1.0, 0.001)


func test_far_from_everything_ground_is_pure_sand() -> void:
	var w: PackedFloat32Array = GroundBuilderScript.weights_at(_road_spec(), 0.0, 50.0)
	assert_float(w[0]).append_failure_message("sable attendu loin de tout : %s" % [w]).is_equal_approx(1.0, 0.01)
	assert_float(w[1] + w[2] + w[3]).is_equal_approx(0.0, 0.01)


func test_track_center_is_dominated_by_the_track_weight() -> void:
	var w: PackedFloat32Array = GroundBuilderScript.weights_at(_road_spec(), 0.0, 0.0)
	assert_float(w[2]).append_failure_message("poids piste attendu dominant au centre : %s" % [w]).is_greater(0.9)


func test_rut_center_shifts_weight_from_track_to_dirt() -> void:
	var w_track: PackedFloat32Array = GroundBuilderScript.weights_at(_road_spec(), 0.0, 0.0)
	var w_rut: PackedFloat32Array = GroundBuilderScript.weights_at(_road_spec(), 0.0, _RUT_OFFSET)
	assert_float(w_rut[1]).append_failure_message("terre battue attendue plus forte dans l'ornière : %s vs %s" % [w_rut, w_track]).is_greater(w_track[1])


func test_mound_center_blends_dirt_and_rock_with_no_sand() -> void:
	var w: PackedFloat32Array = GroundBuilderScript.weights_at(_mound_spec(), _MOUND_POS.x, _MOUND_POS.y)
	assert_float(w[0]).append_failure_message("sable ne devrait pas dominer au pied du bâtiment : %s" % [w]).is_less(0.05)
	assert_float(w[1]).append_failure_message("terre battue attendue au pied du bâtiment : %s" % [w]).is_greater(0.3)
	assert_float(w[3]).append_failure_message("roche/gravats attendus au pied du bâtiment : %s" % [w]).is_greater(0.3)


# ============================================================== build()

func test_build_returns_one_mesh_and_one_collision_body() -> void:
	var ground: Node3D = auto_free(GroundBuilderScript.build(_mixed_spec()))
	assert_int(ground.get_child_count()).is_equal(2)
	assert_object(ground.get_node("GroundMesh")).is_not_null()
	assert_object(ground.get_node("GroundCollision")).is_not_null()


func test_build_with_an_empty_spec_never_crashes() -> void:
	var ground: Node3D = auto_free(GroundBuilderScript.build({}))
	assert_object(ground).is_not_null()
	assert_int(ground.get_child_count()).is_equal(2)


func test_ground_mesh_uses_the_ink_ground_shader_with_its_four_textures_set() -> void:
	var ground: Node3D = auto_free(GroundBuilderScript.build(_mixed_spec()))
	var mesh_inst := ground.get_node("GroundMesh") as MeshInstance3D
	var mat := mesh_inst.material_override as ShaderMaterial
	assert_object(mat).is_not_null()
	assert_str(mat.shader.resource_path).is_equal("res://assets/shaders/ink_ground.gdshader")
	for param in ["tex_sand", "tex_dirt", "tex_track", "tex_rock"]:
		assert_object(mat.get_shader_parameter(param)).append_failure_message("%s non posé" % param).is_not_null()


## Sens de bobinage correct (voir GroundBuilder._emit_tri) : sur un sol
## PARFAITEMENT PLAT (bruit désactivé, aucune piste/jupe), les normales
## générées par SurfaceTool doivent pointer vers le haut -- sinon
## `cull_back` escamoterait tout le sol vu depuis une caméra normale.
func test_flat_ground_mesh_normals_point_upward() -> void:
	var spec := {"size": Vector2(4.0, 4.0), "cell": 1.0, "noise_amp": 0.0}
	var ground: Node3D = auto_free(GroundBuilderScript.build(spec))
	var mesh_inst := ground.get_node("GroundMesh") as MeshInstance3D
	var arrays := mesh_inst.mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_int(normals.size()).is_greater(0)
	for n in normals:
		assert_float((n as Vector3).y).append_failure_message("normale vers le bas : %s" % n).is_greater(0.9)


## Les hauteurs de sommet du maillage RÉEL viennent du même `height_at` que
## les tests purs ci-dessus (même grille, même origine) -- vérifie le
## câblage de `_build_geometry`, pas seulement la formule elle-même.
func test_mesh_vertex_heights_match_height_at_on_a_relief_spec() -> void:
	var spec := _mixed_spec()
	var ground: Node3D = auto_free(GroundBuilderScript.build(spec))
	var mesh_inst := ground.get_node("GroundMesh") as MeshInstance3D
	var arrays := mesh_inst.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_int(verts.size()).is_greater(0)
	var checked := 0
	for v in verts:
		var p: Vector3 = v
		var expected := GroundBuilderScript.height_at(spec, p.x, p.z)
		assert_float(p.y).append_failure_message("sommet (%.2f,%.2f) : maillage=%.4f, height_at=%.4f" % [p.x, p.z, p.y, expected]).is_equal_approx(expected, 0.001)
		checked += 1
	assert_int(checked).is_greater(0)


# ======================================================= collision (pure)

func test_heightmap_collision_dims_match_the_mesh_grid() -> void:
	var spec := _mixed_spec()
	var ground: Node3D = auto_free(GroundBuilderScript.build(spec))
	var body := ground.get_node("GroundCollision") as StaticBody3D
	var shape := (body.get_child(0) as CollisionShape3D).shape as HeightMapShape3D
	assert_object(shape).is_not_null()
	var size: Vector2 = spec["size"]
	var cell: float = spec["cell"]
	var expected_cols := int(round(size.x / cell))
	var expected_rows := int(round(size.y / cell))
	assert_int(shape.map_width).is_equal(expected_cols + 1)
	assert_int(shape.map_depth).is_equal(expected_rows + 1)


## Critère d'acceptation : "collision = maillage à +/-2 cm" -- comparaison
## directe des données `HeightMapShape3D.map_data` (dé-pré-échelonnées par
## `cell`, voir GroundBuilder._build_collision) contre `height_at()` aux
## mêmes points de grille.
func test_heightmap_collision_data_matches_height_at_within_2cm() -> void:
	var spec := _mixed_spec()
	var cell: float = spec["cell"]
	var size: Vector2 = spec["size"]
	var origin: Vector2 = Vector2.ZERO - size * 0.5
	var ground: Node3D = auto_free(GroundBuilderScript.build(spec))
	var body := ground.get_node("GroundCollision") as StaticBody3D
	var col_shape := body.get_child(0) as CollisionShape3D
	var shape := col_shape.shape as HeightMapShape3D
	var stride := shape.map_width
	var checked := 0
	for row in range(0, shape.map_depth, 3):
		for col in range(0, shape.map_width, 3):
			var wx: float = origin.x + float(col) * cell
			var wz: float = origin.y + float(row) * cell
			var expected := GroundBuilderScript.height_at(spec, wx, wz)
			var stored: float = shape.map_data[row * stride + col] * cell
			assert_float(absf(stored - expected)).append_failure_message("collision vs. hauteur à (col=%d,row=%d) : %.4f vs %.4f" % [col, row, stored, expected]).is_less_equal(0.02)
			checked += 1
	assert_int(checked).is_greater(0)


# =================================================== collision (physique)

## Même critère que ci-dessus, vérifié cette fois par un VRAI raycast
## physique (comme tests/maps/test_navmesh.gd) -- valide, en plus de la
## formule, l'orientation réelle de la grille `HeightMapShape3D` dans le
## moteur (X/Z, centrage, pré-échelle) : une inversion col/row ou un mauvais
## centrage romprait ce test sans nécessairement casser le test "pur"
## ci-dessus (qui relit ses données avec la MÊME convention des deux côtés).
func test_physics_raycast_hits_the_ground_within_2cm_of_its_visual_height() -> void:
	var spec := _mixed_spec()
	var ground := GroundBuilderScript.build(spec)
	add_child(ground)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := ground.get_world_3d().direct_space_state
	var samples := [Vector2(0.0, 0.0), Vector2(0.0, _RUT_OFFSET), Vector2(-9.0, -6.0), Vector2(9.0, 6.0)]
	for s in samples:
		var expected := GroundBuilderScript.height_at(spec, s.x, s.y)
		var from := Vector3(s.x, expected + 5.0, s.y)
		var to := Vector3(s.x, expected - 5.0, s.y)
		var query := PhysicsRayQueryParameters3D.create(from, to)
		var result := space.intersect_ray(query)
		assert_bool(result.is_empty()).append_failure_message("aucun impact physique en %s" % s).is_false()
		if not result.is_empty():
			var hit_y: float = (result["position"] as Vector3).y
			assert_float(absf(hit_y - expected)).append_failure_message("collision=%.3f, maillage=%.3f en %s" % [hit_y, expected, s]).is_less_equal(0.02)
	remove_child(ground)
	ground.free()


# ============================================================== navmesh

## Critère d'acceptation : "navmesh bakée sur le sol" -- `bake_navmesh` est
## un appel séparé de `build()` (voir l'en-tête de GroundBuilder.gd) : le
## sol doit d'abord être `add_child()`-é dans un arbre de scène actif.
func test_bake_navmesh_produces_polygons_over_the_ground() -> void:
	var spec := _mixed_spec()
	var ground := GroundBuilderScript.build(spec)
	add_child(ground)
	var region := GroundBuilderScript.bake_navmesh(ground)
	for i in 15:
		await get_tree().physics_frame
	assert_object(region).is_not_null()
	assert_object(region.navigation_mesh).is_not_null()
	assert_int(region.navigation_mesh.get_polygon_count()).append_failure_message("aucun polygone de navmesh baké sur le sol").is_greater(0)
	remove_child(ground)
	ground.free()


# ==================================================== calibration (OKLab)
## Retour vérificateur (ART-85, capture reports/beauty/beauty_corner.png
## datée 09:19, scan dense x=600..1750px à y=900/950/1000/1050) : la piste
## rendait comme un brun quasi uniforme (R 61-76, G 28-39, B 13-20) une fois
## passée par le shader -- bien en dessous de la cible §6.2/CHK-04 "sol
## jouable" (L OKLab 0,60-0,78, chroma <= 0,10), en plein dans la bande
## "boue" CHK-02 (0,25-0,33 de L) voire dessous, alors que les poids de
## sommet (données/tests géométriques ci-dessus) sont corrects -- le défaut
## venait des teintes de rôle (GroundBuilder._TINT_DIRT/_TRACK/_ROCK), pas du
## maillage. Ce bloc recalcule la même métrique OKLab que tools/review/
## style_check.py::rgb01_to_oklab (CHK-04) sur la couleur RÉELLEMENT posée
## par `_material()` (texture moyenne x teinte de rôle) pour chaque matière
## -- garde-fou headless (pas de rendu GPU) contre une régression vers cet
## aplat sombre.
##
## Vérifie l'ALBÉDO (avant la rampe lumière/ombre du shader), pas le pixel
## RENDU -- voir le commentaire de GroundBuilder._TINT_DIRT/_TRACK : la rampe
## partagée avec ink_toon.gdshader (hors périmètre, jamais modifiée ici)
## déplace la teinte perçue (mesuré : jusqu'à ~-15° de teinte, chroma x~1,5)
## entre l'un et l'autre, donc ceci reste un PROXY (garde-fou contre une
## régression vers l'aplat sombre d'origine), pas une reproduction exacte de
## CHK-04 (qui mesure, lui, la capture finale).
const _OKLAB_M1 := [
	Vector3(0.4122214708, 0.5363325363, 0.0514459929),
	Vector3(0.2119034982, 0.6806995451, 0.1073969566),
	Vector3(0.0883024619, 0.2817188376, 0.6299787005),
]
const _OKLAB_M2 := [
	Vector3(0.2104542553, 0.7936177850, -0.0040720468),
	Vector3(1.9779984951, -2.4285922050, 0.4505937099),
	Vector3(0.0259040371, 0.7827717662, -0.8086757660),
]


static func _srgb_channel_to_linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


## (L, chroma) OKLCH d'une couleur sRGB [0,1] -- mêmes matrices que
## tools/review/style_check.py::rgb01_to_oklab/oklab_to_oklch (CHK-04).
static func _oklch(rgb: Color) -> Vector2:
	var lin := Vector3(_srgb_channel_to_linear(rgb.r), _srgb_channel_to_linear(rgb.g), _srgb_channel_to_linear(rgb.b))
	var lms := Vector3(_OKLAB_M1[0].dot(lin), _OKLAB_M1[1].dot(lin), _OKLAB_M1[2].dot(lin))
	var lms_root := Vector3(pow(maxf(lms.x, 0.0), 1.0 / 3.0), pow(maxf(lms.y, 0.0), 1.0 / 3.0), pow(maxf(lms.z, 0.0), 1.0 / 3.0))
	var lab := Vector3(_OKLAB_M2[0].dot(lms_root), _OKLAB_M2[1].dot(lms_root), _OKLAB_M2[2].dot(lms_root))
	return Vector2(lab.x, Vector2(lab.y, lab.z).length())


## Couleur moyenne (sous-échantillonnée 32x32, filtre LANCZOS -- réservé au
## RÉTRÉCISSEMENT par la doc Godot 4.7, même convention que
## tools/review/beauty_shot.gd) d'une texture préchargée : le "pixel
## représentatif" de la même vérification que le vérificateur mène sur une
## capture réelle, mais exécutable headless (pas de rendu GPU).
static func _average_texture_color(tex: Texture2D) -> Color:
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(32, 32, Image.INTERPOLATE_LANCZOS)
	var sum := Color(0.0, 0.0, 0.0)
	for y in range(32):
		for x in range(32):
			sum += img.get_pixel(x, y)
	return sum / (32.0 * 32.0)


func test_dirt_track_and_rock_tints_land_in_the_style_bible_ground_lightness_band() -> void:
	var ground: Node3D = auto_free(GroundBuilderScript.build(_mixed_spec()))
	var mesh_inst := ground.get_node("GroundMesh") as MeshInstance3D
	var mat := mesh_inst.material_override as ShaderMaterial
	var roles := {
		"terre battue (dirt)": ["tex_dirt", "tint_dirt"],
		"piste (track)": ["tex_track", "tint_track"],
		"roche (rock)": ["tex_rock", "tint_rock"],
	}
	for role_name in roles:
		var param_names: Array = roles[role_name]
		var tex: Texture2D = mat.get_shader_parameter(param_names[0])
		var tint: Color = mat.get_shader_parameter(param_names[1])
		var avg := _average_texture_color(tex)
		var final_color := Color(avg.r * tint.r, avg.g * tint.g, avg.b * tint.b)
		var lc := _oklch(final_color)
		assert_float(lc.x).append_failure_message("%s : L OKLab=%.3f hors gabarit §6.2/CHK-04 [0.60, 0.78] -- rgb=(%.3f,%.3f,%.3f), retomberait dans la 'boue' CHK-02 si < 0.33" % [role_name, lc.x, final_color.r, final_color.g, final_color.b]).is_greater_equal(0.60)
		assert_float(lc.x).append_failure_message("%s : L OKLab=%.3f hors gabarit §6.2/CHK-04 [0.60, 0.78]" % [role_name, lc.x]).is_less_equal(0.78)
		assert_float(lc.y).append_failure_message("%s : chroma OKLab=%.3f > 0.10 (§6.2/CHK-04, sol jouable)" % [role_name, lc.y]).is_less_equal(0.10)


# ============================================ jupe de terre (pied de bâtiment)
## Retour vérificateur (ART-85) : `BeautyCorner._build_ground` place chaque
## jupe EXACTEMENT à `_PORCH_DEPTH + 0.2` (1,8 m) au-delà du bord de piste --
## à l'ancien rayon (1,8, == cette distance), `falloff = 1 - smoothstep(0,
## radius, dist)` s'annule PILE à `dist == radius`, donc une influence
## EXACTEMENT nulle au bord de piste. Mêmes chiffres que BeautyCorner (radius
## 3.0, décalage 1.8) : vérifie que ce n'est plus le cas, sans dépendre de
## BeautyCorner.gd (scène de dev, hors périmètre de test_ground_builder.gd).
func test_a_building_mound_still_influences_the_ground_at_the_track_edge() -> void:
	const _BUILDING_MOUND_RADIUS := 3.0
	const _MOUND_TO_TRACK_EDGE_DIST := 1.8  # _PORCH_DEPTH (1.6) + 0.2, BeautyCorner.gd
	var spec := {
		"size": Vector2(20.0, 20.0), "noise_amp": 0.0,
		"mounds": [{"pos": Vector2(6.0, 0.0), "radius": _BUILDING_MOUND_RADIUS, "height": 0.12}],
	}
	var h := GroundBuilderScript.height_at(spec, 6.0, _MOUND_TO_TRACK_EDGE_DIST)
	assert_float(h).append_failure_message("jupe : hauteur=%.4f au bord de piste, attendu > 0 (pas EXACTEMENT 0 comme avec l'ancien rayon 1.8)" % h).is_greater(0.01)
	var w: PackedFloat32Array = GroundBuilderScript.weights_at(spec, 6.0, _MOUND_TO_TRACK_EDGE_DIST)
	assert_float(w[1] + w[3]).append_failure_message("jupe : terre battue+roche=%.4f au bord de piste, attendu > 0 (mélange visible à la couture piste/trottoir)" % (w[1] + w[3])).is_greater(0.02)


# ===================================================== visual_only (ART-97)
## Contrat additif ART-97 (docs/art/WASTELAND_V4_ART_PLAN.md §3) : les
## instances de sol posées par `ArtGround.gd` sur les cartes v4 sont
## PUREMENT VISUELLES (§1 R9 "aucun CollisionObject3D ajouté dans les
## bornes") et doivent rester à +/-8 cm des boîtes de sol du greybox
## (critère d'acceptation ART-97) -- deux garanties portées par
## `GroundBuilder` lui-même : `visual_only` supprime la collision, et
## `height_at` plafonne le relief total à +/-8 cm quand `visual_only` est
## vrai, quelle que soit la combinaison bruit/piste/ornière/jupe fournie par
## l'appelant (défense en profondeur : ArtGround ne peut pas, même par
## erreur de configuration, dépasser le budget du critère).
func test_visual_only_build_has_no_collision_body() -> void:
	var spec := _mixed_spec()
	spec["visual_only"] = true
	var ground: Node3D = auto_free(GroundBuilderScript.build(spec))
	assert_int(ground.get_child_count()).append_failure_message("visual_only=true devrait omettre le corps de collision (contrat R9 'aucun CollisionObject3D ajouté')").is_equal(1)
	assert_object(ground.get_node("GroundMesh")).is_not_null()
	assert_bool(ground.has_node("GroundCollision")).is_false()


func test_default_build_still_has_a_collision_body_when_visual_only_is_absent() -> void:
	# Non-régression : défaut inchangé (aucun appelant existant, BeautyCorner
	# compris, ne passe `visual_only`) -- `build()` garde son comportement
	# actuel tant que la clé est absente.
	var ground: Node3D = auto_free(GroundBuilderScript.build(_mixed_spec()))
	assert_int(ground.get_child_count()).is_equal(2)
	assert_object(ground.get_node("GroundCollision")).is_not_null()


func test_visual_only_allows_a_shallower_road_depth_than_the_10cm_physical_floor() -> void:
	# Plan §3 : "la profondeur des pistes, ornières et buttes peut descendre
	# à 0,03 m" en visual_only -- sous le plancher physique MIN_ROAD_DEPTH
	# (0,10 m, ART-85) qui reste, lui, le plancher du sol AVEC collision.
	var shallow := _road_spec()
	shallow["visual_only"] = true
	shallow["roads"][0]["depth"] = 0.03
	var h := GroundBuilderScript.height_at(shallow, 0.0, 0.0)
	assert_float(absf(h)).append_failure_message("piste visual_only à 0,03 m écrasée au plancher physique : %.4f" % h).is_equal_approx(0.03, 0.005)


func test_visual_only_clamps_deep_road_depth_to_the_8cm_contract_ceiling() -> void:
	var deep := _road_spec()
	deep["visual_only"] = true
	deep["roads"][0]["depth"] = 0.20  # profondeur physique valide (ART-85), hors plafond visuel
	var h := GroundBuilderScript.height_at(deep, 0.0, 0.0)
	assert_float(absf(h)).append_failure_message("piste visual_only non plafonnée à 0,08 m : %.4f" % h).is_less_equal(0.0801)


## Plafond de SÉCURITÉ sur le relief TOTAL (bruit + piste + ornière + jupe
## combinés) -- pas seulement sur `depth` pris isolément : une configuration
## qui cumule une jupe haute ET une ornière au même point ne doit jamais
## dépasser +/-8 cm en visual_only, même si aucun des deux paramètres pris
## seul n'est plafonné explicitement par l'appelant.
func test_visual_only_caps_the_combined_relief_even_when_mound_and_road_overlap() -> void:
	var spec := {
		"size": Vector2(20.0, 20.0), "cell": 0.5, "visual_only": true,
		"noise_amp": 0.05, "seed": 11,
		"roads": [{
			"points": [Vector2(-20.0, 0.0), Vector2(20.0, 0.0)],
			"width": 8.0, "depth": 0.20,
			"ruts": {"offset": 1.4, "width": 0.9, "depth": 0.05},
		}],
		"mounds": [{"pos": Vector2(0.0, 1.4), "radius": 3.0, "height": 0.30}],
	}
	var checked := 0
	for i in 41:
		var x := float(i) - 20.0
		for j in 41:
			var z := float(j) - 20.0
			var h := GroundBuilderScript.height_at(spec, x, z)
			assert_float(absf(h)).append_failure_message("relief visual_only hors budget +/-8cm en (%.1f,%.1f) : %.4f" % [x, z, h]).is_less_equal(0.0801)
			checked += 1
	assert_int(checked).is_greater(0)


## Critère d'acceptation ART-97 formulé littéralement : 2000 points
## échantillonnés sur une empreinte représentative d'une instance de sol
## `ArtGround` (bruit + piste Grand-Rue + jupes), tous à +/-8 cm de la boîte
## de sol (l'origine locale ici -- ArtGround positionne ensuite le nœud
## entier sur le dessus RÉEL de la boîte, un simple décalage Y qui ne change
## aucune des différences vérifiées ici).
func test_2000_sample_points_stay_within_8cm_of_the_ground_box_top_in_visual_only() -> void:
	var spec := {
		"size": Vector2(88.0, 37.0), "cell": 1.0, "center": Vector2(0.0, -6.5),
		"visual_only": true, "noise_amp": 0.05, "seed": 4,
		"roads": [{
			"points": [Vector2(-44.0, -14.5), Vector2(-6.5, -14.5), Vector2(-4.6, -9.9), Vector2(4.6, -9.9), Vector2(6.5, -14.5), Vector2(44.0, -14.5)],
			"width": 6.2, "depth": 0.06,
			"ruts": {"offset": 1.5, "width": 0.9, "depth": 0.04},
		}],
		"mounds": [
			{"pos": Vector2(-21.0, -22.0), "radius": 2.0, "height": 0.06},
			{"pos": Vector2(21.0, -22.0), "radius": 2.0, "height": 0.06},
		],
		"zones": [
			{"rect": Rect2(Vector2(-44.0, -11.0), Vector2(88.0, 23.0)), "paint": "dirt", "feather": 2.0},
		],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var worst := 0.0
	for i in 2000:
		var x := rng.randf_range(-44.0, 44.0)
		var z := rng.randf_range(-25.0, 12.0)
		var h := GroundBuilderScript.height_at(spec, x, z)
		worst = maxf(worst, absf(h))
	assert_float(worst).append_failure_message("2000 points échantillonnés : pire écart au sol=%.4f m, attendu <= 0,08 m (critère d'acceptation ART-97)" % worst).is_less_equal(0.0801)


# ========================================== "paint" par route (ART-97 §3)
## `road.paint` ("sand"|"dirt"|"track"|"rock", défaut "track" -- comportement
## d'avant inchangé) : dessine une route en terre battue ou en ballast
## plutôt qu'en piste, réutilisant le même moteur de creusement/ornières
## (ex. les Ruelles/la Place en terre battue, le lit de ballast le long des
## rails) sans dupliquer la logique de piste.
func test_road_paint_defaults_to_track_when_absent() -> void:
	var w: PackedFloat32Array = GroundBuilderScript.weights_at(_road_spec(), 0.0, 0.0)
	assert_float(w[2]).append_failure_message("comportement par défaut changé : %s" % [w]).is_greater(0.9)


func test_road_paint_dirt_routes_its_weight_into_the_dirt_channel_not_track() -> void:
	var spec := _road_spec()
	spec["roads"][0]["paint"] = "dirt"
	var w: PackedFloat32Array = GroundBuilderScript.weights_at(spec, 0.0, 0.0)
	assert_float(w[1]).append_failure_message("paint=dirt : terre battue attendue dominante au centre : %s" % [w]).is_greater(0.9)
	assert_float(w[2]).append_failure_message("paint=dirt : piste ne devrait plus dominer : %s" % [w]).is_less(0.1)


func test_road_paint_rock_routes_its_weight_into_the_rock_channel() -> void:
	var spec := _road_spec()
	spec["roads"][0]["paint"] = "rock"
	var w: PackedFloat32Array = GroundBuilderScript.weights_at(spec, 0.0, 0.0)
	assert_float(w[3]).append_failure_message("paint=rock : roche/ballast attendue dominante au centre : %s" % [w]).is_greater(0.9)


func test_road_paint_never_changes_the_height_profile() -> void:
	# Le relief (creux/ornières/bourrelet) ne dépend que de la géométrie de
	# la route, jamais de son rôle de peinture.
	var track := _road_spec()
	var dirt := _road_spec()
	dirt["roads"][0]["paint"] = "dirt"
	assert_float(GroundBuilderScript.height_at(track, 0.0, 0.0)).is_equal_approx(GroundBuilderScript.height_at(dirt, 0.0, 0.0), 0.0001)


# ================================================== zones (ART-97 §3)
## `zones: [{rect: Rect2 | poly: Array[Vector2], paint, feather}]` -- peint
## une zone en dur (défaut : nulle part, tableau absent = comportement
## d'avant inchangé), fondue sur `feather` mètres à sa bordure. Purement une
## affaire de POIDS (`weights_at`) : jamais de relief (§3 "zones ... paint"
## ne porte aucun champ de hauteur).
func test_zones_absent_leaves_weights_unchanged() -> void:
	# `_mixed_spec()` ne pose jamais de clé "zones" -- comportement d'avant,
	# vérifié explicitement contre un appel équivalent SANS la clé du tout.
	var spec := _mixed_spec()
	assert_bool(spec.has("zones")).is_false()
	var w := GroundBuilderScript.weights_at(spec, 3.0, -3.0)
	var w2 := GroundBuilderScript.weights_at(_mixed_spec(), 3.0, -3.0)
	for i in 4:
		assert_float(w2[i]).is_equal_approx(w[i], 0.0001)


func test_rect_zone_paints_pure_dirt_deep_inside_its_rect() -> void:
	var spec := {
		"size": Vector2(40.0, 40.0), "noise_amp": 0.0,
		"zones": [{"rect": Rect2(Vector2(-10.0, -10.0), Vector2(20.0, 20.0)), "paint": "dirt", "feather": 1.0}],
	}
	var w: PackedFloat32Array = GroundBuilderScript.weights_at(spec, 0.0, 0.0)
	assert_float(w[1]).append_failure_message("centre de la zone rect : terre battue attendue pure : %s" % [w]).is_equal_approx(1.0, 0.01)


func test_rect_zone_fades_out_at_its_boundary() -> void:
	var spec := {
		"size": Vector2(40.0, 40.0), "noise_amp": 0.0,
		"zones": [{"rect": Rect2(Vector2(-10.0, -10.0), Vector2(20.0, 20.0)), "paint": "dirt", "feather": 1.0}],
	}
	# Pile sur le bord de la zone (x=10) : aucune influence encore appliquée.
	var w_edge: PackedFloat32Array = GroundBuilderScript.weights_at(spec, 10.0, 0.0)
	assert_float(w_edge[0]).append_failure_message("bord de zone : sable attendu (pas encore fondu vers terre battue) : %s" % [w_edge]).is_greater(0.9)
	# Loin dehors : entièrement sable, la zone n'a aucun effet.
	var w_far: PackedFloat32Array = GroundBuilderScript.weights_at(spec, 25.0, 25.0)
	assert_float(w_far[0]).append_failure_message("hors de la zone : sable attendu : %s" % [w_far]).is_greater(0.99)


func test_poly_zone_paints_pure_rock_deep_inside_its_polygon() -> void:
	var spec := {
		"size": Vector2(40.0, 40.0), "noise_amp": 0.0,
		"zones": [{
			"poly": [Vector2(-10.0, -10.0), Vector2(10.0, -10.0), Vector2(10.0, 10.0), Vector2(-10.0, 10.0)],
			"paint": "rock", "feather": 1.0,
		}],
	}
	var w: PackedFloat32Array = GroundBuilderScript.weights_at(spec, 0.0, 0.0)
	assert_float(w[3]).append_failure_message("centre du polygone : roche attendue pure : %s" % [w]).is_equal_approx(1.0, 0.01)


func test_poly_zone_has_no_effect_outside_its_polygon() -> void:
	var spec := {
		"size": Vector2(40.0, 40.0), "noise_amp": 0.0,
		"zones": [{
			"poly": [Vector2(-10.0, -10.0), Vector2(10.0, -10.0), Vector2(10.0, 10.0), Vector2(-10.0, 10.0)],
			"paint": "rock", "feather": 1.0,
		}],
	}
	var w: PackedFloat32Array = GroundBuilderScript.weights_at(spec, 18.0, 18.0)
	assert_float(w[0]).append_failure_message("hors du polygone : sable attendu : %s" % [w]).is_greater(0.99)


func test_zones_never_change_the_height_profile() -> void:
	var spec := {
		"size": Vector2(40.0, 40.0), "noise_amp": 0.0,
		"zones": [{"rect": Rect2(Vector2(-10.0, -10.0), Vector2(20.0, 20.0)), "paint": "rock", "feather": 1.0}],
	}
	var h := GroundBuilderScript.height_at(spec, 0.0, 0.0)
	assert_float(h).append_failure_message("une zone ne doit jamais modifier le relief (paint seulement)").is_equal_approx(0.0, 0.0001)


func test_weights_stay_normalized_with_zones_applied() -> void:
	var spec := _mixed_spec()
	spec["zones"] = [
		{"rect": Rect2(Vector2(-2.0, -2.0), Vector2(6.0, 6.0)), "paint": "dirt", "feather": 1.5},
		{"poly": [Vector2(6.0, 4.0), Vector2(10.0, 4.0), Vector2(10.0, 8.0), Vector2(6.0, 8.0)], "paint": "rock", "feather": 1.0},
	]
	var points := [Vector2(0, 0), Vector2(0, 1.4), Vector2(9.0, 6.0), Vector2(3, -3), Vector2(-5, 5)]
	for p in points:
		var w: PackedFloat32Array = GroundBuilderScript.weights_at(spec, p.x, p.y)
		var total := w[0] + w[1] + w[2] + w[3]
		assert_float(total).append_failure_message("poids non normalisés (zones) en %s : somme=%.4f" % [p, total]).is_equal_approx(1.0, 0.001)
