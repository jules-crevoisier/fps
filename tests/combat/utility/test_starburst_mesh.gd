## test_starburst_mesh.gd
## Spec (contrat lead 2026-09-27, éclats de détonation frag/flash) : un
## polygone en étoile plate à N pointes, en éventail depuis le centre --
## fonction PURE (StarburstMesh.build), testée sans nœud/scène.
##
## `preload` par CHEMIN plutôt que le nom de classe global `StarburstMesh` :
## le cache des classes globales de Godot n'est pas garanti à jour pour un
## fichier tout juste ajouté lors d'un run gdUnit4 en ligne de commande (voir
## la même note dans ThrownUtility.gd).
extends GdUnitTestSuite

const _StarburstMesh := preload("res://scripts/combat/utility/vfx/StarburstMesh.gd")


func test_builds_one_surface() -> void:
	var mesh := _StarburstMesh.build(12, 1.0, 0.45)
	assert_int(mesh.get_surface_count()).is_equal(1)


func test_vertex_count_matches_spike_count_plus_center() -> void:
	var mesh := _StarburstMesh.build(12, 1.0, 0.45)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# 12 pointes -> 24 points de contour (pointe/creux alternés) + 1 centre.
	assert_int(verts.size()).is_equal(25)


func test_triangle_count_matches_point_count() -> void:
	var mesh := _StarburstMesh.build(12, 1.0, 0.45)
	var arrays := mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# Un triangle (3 indices) par point de contour, tous partant du centre (index 0).
	assert_int(indices.size()).is_equal(24 * 3)
	for i in indices.size():
		if i % 3 == 0:
			assert_int(indices[i]).append_failure_message(
				"chaque triangle doit partir du centre (index 0)"
			).is_equal(0)


func test_outer_points_are_farther_from_center_than_inner_points() -> void:
	var mesh := _StarburstMesh.build(6, 2.0, 0.5)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# verts[0] = centre ; verts[1] = pointe (rayon extérieur) ; verts[2] = creux (rayon intérieur).
	assert_float(verts[1].length()).append_failure_message(
		"un point de POINTE doit être au rayon extérieur"
	).is_equal_approx(2.0, 0.001)
	assert_float(verts[2].length()).append_failure_message(
		"un point de CREUX doit être au rayon intérieur"
	).is_equal_approx(0.5, 0.001)


func test_minimum_three_spikes_even_if_fewer_requested() -> void:
	var mesh := _StarburstMesh.build(1, 1.0, 0.4)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_int(verts.size()).append_failure_message(
		"jamais moins de 3 pointes, même si demandé -- 3*2 points de contour + 1 centre"
	).is_equal(7)
