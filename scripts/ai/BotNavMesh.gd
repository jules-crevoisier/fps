## BotNavMesh.gd
## Garantit qu'une NavigationRegion3D (groupe "nav_region") existe et est
## BAKED avant que GameWorld ne fasse spawn les bots (contract-r3.md,
## "Cross-slice interfaces" : "Bots need... baked before GameWorld._ready
## spawns bots"). Les nouvelles cartes (R3-MAPS, MapSetup) en fournissent déjà
## une ; ce helper en construit une À LA VOLÉE pour les scènes qui n'en ont
## pas (ex. scenes/levels/test_arena.tscn), en parsant les colliders
## STATIQUES de toute la scène.
##
## Godot 4.7 (docs Context7 /websites/godotengine_en_4_7,
## "Baking a navigation mesh with the NavigationServer") : `bake()` sur
## NavigationMeshGenerator est DÉPRÉCIÉ ; l'API courante est
## `NavigationServer3D.parse_source_geometry_data()` (thread principal) puis
## `NavigationServer3D.bake_from_source_geometry_data()` — synchrone (sans le
## suffixe `_async`), pour être prête AVANT le premier spawn, sans callback à
## attendre. Repli sur l'API dépréciée si l'une des deux méthodes venait à
## manquer (robustesse entre variantes mineures du moteur).
class_name BotNavMesh
extends RefCounted

static func ensure_baked(scene: Node) -> NavigationRegion3D:
	if scene == null:
		return null
	var existing := scene.get_tree().get_first_node_in_group("nav_region") as NavigationRegion3D
	if existing:
		return existing

	var navmesh := NavigationMesh.new()
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.agent_radius = 0.4
	navmesh.agent_height = 1.8
	navmesh.agent_max_climb = 0.6
	navmesh.agent_max_slope = 52.0
	navmesh.cell_size = 0.2
	navmesh.cell_height = 0.2

	if NavigationServer3D.has_method("parse_source_geometry_data") \
			and NavigationServer3D.has_method("bake_from_source_geometry_data"):
		var source := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(navmesh, source, scene)
		NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	elif NavigationMeshGenerator.has_method("bake"):
		NavigationMeshGenerator.bake(navmesh, scene)  # repli déprécié mais synchrone.
	else:
		push_warning("BotNavMesh: aucune API de baking de navmesh disponible.")

	var region := NavigationRegion3D.new()
	region.name = "BakedNavRegion"
	region.navigation_mesh = navmesh
	region.add_to_group("nav_region")
	scene.add_child(region)
	return region
