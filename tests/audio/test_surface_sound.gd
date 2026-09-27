## test_surface_sound.gd
## Spec (tâche "son", 2026-09-27, point 6/7 "impacts/whizz" + "pas sur métal") :
## classification PURE d'une surface (métal/béton) depuis un collider — méta
## "surface" posée par l'auteur de carte en priorité, repli sur une
## heuristique de NOM (conteneur/container -> métal) sinon béton par défaut —
## puis conversion vers le nom de son d'impact/de pas correspondant. Aucune
## dépendance à une scène réelle : `Node.new()` + `set_meta`/`name` suffisent.
extends GdUnitTestSuite


func test_surface_of_reads_meta_first() -> void:
	var n := Node.new()
	n.set_meta("surface", "metal")
	n.name = "SolBeton"  # le nom ne doit jamais l'emporter sur la méta explicite.
	assert_str(SurfaceSound.surface_of(n)).is_equal("metal")
	n.free()


func test_surface_of_falls_back_to_container_name_heuristic() -> void:
	var n := Node.new()
	n.name = "Container_Red_03"
	assert_str(SurfaceSound.surface_of(n)).is_equal("metal")
	n.free()


func test_surface_of_falls_back_to_french_conteneur_name_heuristic() -> void:
	var n := Node.new()
	n.name = "ConteneurBleu"
	assert_str(SurfaceSound.surface_of(n)).is_equal("metal")
	n.free()


func test_surface_of_defaults_to_concrete() -> void:
	var n := Node.new()
	n.name = "Sol"
	assert_str(SurfaceSound.surface_of(n)).is_equal("concrete")
	n.free()


func test_surface_of_null_collider_is_concrete() -> void:
	assert_str(SurfaceSound.surface_of(null)).is_equal("concrete")


func test_impact_sound_for_metal() -> void:
	assert_str(SurfaceSound.impact_sound_for("metal")).is_equal("impact_metal")


func test_impact_sound_for_concrete_and_unknown() -> void:
	assert_str(SurfaceSound.impact_sound_for("concrete")).is_equal("impact_concrete")
	assert_str(SurfaceSound.impact_sound_for("wood")).is_equal("impact_concrete")


func test_footstep_sound_for_metal_walk_and_sprint() -> void:
	assert_str(SurfaceSound.footstep_sound_for("footstep_walk", "metal")).is_equal("footstep_metal_walk")
	assert_str(SurfaceSound.footstep_sound_for("footstep_sprint", "metal")).is_equal("footstep_metal_sprint")


func test_footstep_sound_for_concrete_is_unchanged() -> void:
	assert_str(SurfaceSound.footstep_sound_for("footstep_walk", "concrete")).is_equal("footstep_walk")
	assert_str(SurfaceSound.footstep_sound_for("footstep_sprint", "concrete")).is_equal("footstep_sprint")


func test_footstep_sound_for_empty_base_name_stays_empty() -> void:
	assert_str(SurfaceSound.footstep_sound_for("", "metal")).is_equal("")
