## test_imported_map_geometry.gd
## Spec (brief lead 2026-09-28, Canyon Express) : contrat de plomberie pour
## une carte dont l'art + la collision viennent d'un glTF exporté depuis
## Blender (le lead modélise Canyon Express en parallèle -- pas de .glb à
## disposition ici, ces tests construisent donc un arbre SYNTHÉTIQUE qui
## reproduit exactement la convention d'export documentée par
## ImportedMapGeometry.gd) :
##  - StaticBody3D nommé "COL_<surface>_<Nom>" -> méta "surface" + calques
##    physiques IDENTIQUES à ceux de Shipment (PhysicsLayers.WORLD des deux
##    côtés -- confirmé par lecture de shipment.tscn, qui n'en surcharge
##    aucun).
##  - sous-arbre marqué meta "imported_art" = true -> ToonStyle.apply_to(.., "world")
##    (matériaux toon_bd, profil décor -- rim/spéculaire/trame désactivés).
##  - Shipment (aucun nœud COL_*/imported_art) : `prepare()` ne doit rien
##    changer.
extends GdUnitTestSuite

const ImportedMapGeometry := preload("res://scripts/levels/maps/ImportedMapGeometry.gd")
const _TOON_SHADER := preload("res://assets/shaders/toon_bd.gdshader")


# --------------------------------------------------------------- collision

func test_metal_token_sets_metal_surface_meta() -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	body.name = "COL_metal_CargoDoorLeft"
	ImportedMapGeometry.prepare(body)
	assert_str(str(body.get_meta("surface"))).is_equal(SurfaceSound.METAL)


func test_wood_and_rock_and_unknown_tokens_fall_back_to_concrete() -> void:
	# SurfaceSound ne connaît que metal/concrete (aucune variante bois
	# dédiée, voir sa doc + tests/audio/test_surface_sound.gd) -- "wood",
	# "rock" et tout jeton inconnu retombent donc sur CONCRETE.
	for token in ["wood", "rock", "whatever"]:
		var body: StaticBody3D = auto_free(StaticBody3D.new())
		body.name = "COL_%s_Piece" % token
		ImportedMapGeometry.prepare(body)
		assert_str(str(body.get_meta("surface"))).append_failure_message(
			"jeton '%s' n'est pas retombé sur concrete" % token
		).is_equal(SurfaceSound.CONCRETE)


func test_explicit_meta_surface_convention_matches_col_prefix_parsing() -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	body.name = "COL_metal_BridgeRailing"
	ImportedMapGeometry.prepare(body)
	# La méta posée doit être celle que SurfaceSound.surface_of() relira
	# ensuite en priorité absolue (voir sa doc) -- ces deux scripts doivent
	# rester d'accord sur le même vocabulaire.
	assert_str(SurfaceSound.surface_of(body)).is_equal(SurfaceSound.METAL)


func test_collision_proxy_gets_shipment_default_physics_layers() -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	body.name = "COL_metal_Beam"
	ImportedMapGeometry.prepare(body)
	assert_int(body.collision_layer).is_equal(PhysicsLayers.WORLD)
	assert_int(body.collision_mask).is_equal(PhysicsLayers.WORLD)


func test_non_col_prefixed_static_body_is_left_untouched() -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	body.name = "BridgeDeck"  # pas de préfixe COL_ -- un décor non-collision-proxy.
	body.collision_layer = 1
	body.collision_mask = 1
	ImportedMapGeometry.prepare(body)
	assert_bool(body.has_meta("surface")).is_false()


func test_prepare_walks_several_levels_deep() -> void:
	var root: Node3D = auto_free(Node3D.new())
	var mid := Node3D.new()
	root.add_child(mid)
	var body := StaticBody3D.new()
	body.name = "COL_metal_Deep"
	mid.add_child(body)
	ImportedMapGeometry.prepare(root)
	assert_str(str(body.get_meta("surface"))).is_equal(SurfaceSound.METAL)


func test_prepare_tolerates_a_null_root() -> void:
	ImportedMapGeometry.prepare(null)  # ne doit jamais planter.


## `clip` (Canyon Express, garde-corps en corde de la passerelle) : bloque le
## CORPS des joueurs/bots (PhysicsLayers.PLAYER_CLIP, même bit que le
## collision_mask par défaut de scenes/player/player.tscn) mais JAMAIS un tir/
## une ligne de vue -- jamais posé sur PhysicsLayers.WORLD (contrairement à
## metal/wood/rock ci-dessus).
func test_clip_token_is_layered_on_player_clip_only() -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	body.name = "COL_clip_FbRail1"
	ImportedMapGeometry.prepare(body)
	assert_int(body.collision_layer).is_equal(PhysicsLayers.PLAYER_CLIP)
	assert_int(body.collision_mask).is_equal(0)
	# Ni le bit WORLD (un tir/une ligne de vue doit le traverser) ni le
	# SHOT_MASK (qui exclut PLAYER_CLIP par construction) ne doivent matcher.
	assert_int(body.collision_layer & PhysicsLayers.WORLD).is_equal(0)
	assert_int(body.collision_layer & PhysicsLayers.SHOT_MASK).is_equal(0)


## Contrat de tâche : « chaque corps COL a une méta surface », garde-corps
## clip compris (aucun tir ne peut de toute façon jamais l'atteindre -- voir
## le test ci-dessus -- mais la méta existe quand même, retombe sur CONCRETE
## comme tout jeton hors "metal").
func test_clip_token_still_gets_a_surface_meta() -> void:
	var body: StaticBody3D = auto_free(StaticBody3D.new())
	body.name = "COL_clip_FbRail-1"
	ImportedMapGeometry.prepare(body)
	assert_bool(body.has_meta("surface")).is_true()
	assert_str(str(body.get_meta("surface"))).is_equal(SurfaceSound.CONCRETE)


# --------------------------------------------------------------- visuel (imported_art)

func _mesh_with_standard_material(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var std := StandardMaterial3D.new()
	std.albedo_color = color
	mi.set_surface_override_material(0, std)
	return mi


func test_marked_subtree_gets_toon_bd_world_profile_material() -> void:
	var root: Node3D = auto_free(Node3D.new())
	root.set_meta("imported_art", true)
	var mi := _mesh_with_standard_material(Color("8c3a2e"))
	root.add_child(mi)

	ImportedMapGeometry.prepare(root)

	var applied := mi.get_surface_override_material(0) as ShaderMaterial
	assert_that(applied).is_not_null()
	assert_that(applied.shader).is_equal(_TOON_SHADER)
	assert_that(applied.get_shader_parameter("albedo_color")).is_equal(Color("8c3a2e"))
	# Profil "world" (ToonStyle.gd) : pas de liseré/reflet/trame sur du décor plat.
	assert_bool(applied.get_shader_parameter("rim_enabled")).is_false()
	assert_bool(applied.get_shader_parameter("specular_enabled")).is_false()
	assert_bool(applied.get_shader_parameter("halftone_enabled")).is_false()


func test_unmarked_subtree_keeps_its_standard_material() -> void:
	var root: Node3D = auto_free(Node3D.new())
	var mi := _mesh_with_standard_material(Color("445566"))
	root.add_child(mi)
	var original := mi.get_surface_override_material(0)

	ImportedMapGeometry.prepare(root)

	assert_that(mi.get_surface_override_material(0)).is_same(original)


func test_imported_art_meta_set_to_false_is_not_treated_as_marked() -> void:
	var root: Node3D = auto_free(Node3D.new())
	root.set_meta("imported_art", false)
	var mi := _mesh_with_standard_material(Color("223344"))
	root.add_child(mi)
	var original := mi.get_surface_override_material(0)

	ImportedMapGeometry.prepare(root)

	assert_that(mi.get_surface_override_material(0)).is_same(original)


# --------------------------------------------------------------- Shipment : comportement inchangé

## Reproduction minimale de la topologie de shipment.tscn (StaticBody3D +
## MeshInstance3D avec un material_override, aucun préfixe COL_/méta
## imported_art) -- `prepare()` ne doit rien y changer.
func test_prepare_does_not_alter_a_shipment_like_tree() -> void:
	var nav_region: Node3D = auto_free(Node3D.new())
	var wall := StaticBody3D.new()
	wall.name = "WallSouth"
	nav_region.add_child(wall)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var flat := ShaderMaterial.new()
	flat.shader = _TOON_SHADER
	flat.set_shader_parameter("albedo_color", Color(0.46, 0.46, 0.44, 1.0))
	mesh.material_override = flat
	wall.add_child(mesh)
	wall.collision_layer = 1
	wall.collision_mask = 1

	ImportedMapGeometry.prepare(nav_region)

	assert_bool(wall.has_meta("surface")).is_false()
	assert_int(wall.collision_layer).is_equal(1)
	assert_int(wall.collision_mask).is_equal(1)
	assert_that(mesh.material_override).is_same(flat)
