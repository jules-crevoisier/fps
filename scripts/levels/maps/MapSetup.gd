## MapSetup.gd
## Nettoyage du prototype (2026-09-26, "clean absolument tout, repart sur de
## bonnes bases") : Wasteland (géométrie procédurale via Kit.gd/Layouts) est
## supprimée. Shipment (scenes/levels/maps/shipment.tscn) est une scène PLATE
## et ÉDITABLE : géométrie (StaticBody3D + MeshInstance3D + CollisionShape3D),
## NavigationRegion3D ("NavRegion", groupe "nav_region") et marqueurs de spawn
## (Marker3D sous "SpawnPoints", méta "team") sont TOUS déjà présents comme
## enfants du nœud racine de la carte (frères de ce nœud) — cette classe ne
## génère plus AUCUNE géométrie. Son seul travail :
##  1. Retrouver la NavigationRegion3D déjà posée dans la scène et bake son
##     navmesh au chargement (mêmes paramètres d'agent qu'avant : la capsule
##     joueur, scenes/player/player.tscn, fait radius 0.4 / height 1.8 ; voir
##     `AGENT_RADIUS`/`AGENT_HEIGHT` ci-dessous pour la marge d'arrondi aux
##     cellules).
##  2. Construire le nœud "GameMode" (TDMMode, seul mode du prototype) comme
##     ENFANT DE LUI-MÊME (pas de la racine GameWorld) : au moment où
##     `_enter_tree` tourne, la racine est encore en train d'ajouter SES
##     PROPRES enfants déclarés dans la scène et refuse tout `add_child()`
##     supplémentaire pendant ce temps ("Parent node is busy setting up
##     children" — vérifié en headless).
##
## `GameWorld.spawn_points_root` pointe directement vers "SpawnPoints" (frère
## de ce nœud, pas "MapSetup/SpawnPoints" comme l'ancien contrat procédural) :
## les marqueurs de spawn sont posés une fois pour toutes dans la scène, ce
## nœud n'a plus besoin de les construire ni de les router par mode.
##
## Toute carte future qui suit la même recette (géométrie statique + NavRegion
## + SpawnPoints) fonctionne sans modifier CE fichier : `map_id` ne sert plus
## qu'à `GameMode._current_map_id()`/quelques scripts de debug, jamais à
## sélectionner un jeu de données ici.
class_name MapSetup
extends Node3D

@export var map_id: String = ""

## Capsule joueur (scenes/player/player.tscn) : radius 0.4, height 1.8. Le bake
## du navmesh (cell_size=cell_height=0.25) exige des agent_radius/agent_height
## MULTIPLES ENTIERS de ces cellules, sinon Godot les arrondit AU-DESSUS en
## silence ("ceiled to cell_size/cell_height voxel units and loses precision")
## -- rendu explicite ici (0.5 = 2 cellules, 2.0 = 8 cellules) plutôt que subi,
## toujours >= la capsule réelle (jamais un bot qui passe là où un joueur ne
## passe pas).
const AGENT_RADIUS := 0.5
const AGENT_HEIGHT := 2.0
const AGENT_MAX_CLIMB := 0.5
const AGENT_MAX_SLOPE := 46.0

var nav_region: NavigationRegion3D

## Zones nommées (callouts) : aucune carte n'en déclare pour l'instant (aucune
## scène statique ne les pose encore) -- `callout_at` renvoie donc toujours ""
## tant que ce tableau reste vide. Laissé en place pour qu'une carte future
## puisse les fournir (Area3D/Marker3D dédiés à lire ici) sans nouveau contrat.
var _callouts: Array = []

func _enter_tree() -> void:
	if nav_region != null:
		return  # déjà construit (garde-fou anti double appel)
	nav_region = _find_nav_region()
	if nav_region != null:
		_bake_navigation(nav_region)
	else:
		push_error("MapSetup : aucune NavigationRegion3D trouvée dans la scène de carte (map_id=\"%s\")" % map_id)
	_build_game_mode()
	add_child(ShaderWarmup.new())

## La géométrie statique (conteneurs, murs, sol) est posée comme enfants de
## CETTE NavigationRegion3D directement dans la scène (voir shipment.tscn) --
## Recast parse par défaut la propre descendance du nœud qu'on bake, donc
## nul besoin de reparenter quoi que ce soit ici.
func _find_nav_region() -> NavigationRegion3D:
	var parent := get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child is NavigationRegion3D:
			return child
	return null

func _bake_navigation(region: NavigationRegion3D) -> void:
	region.add_to_group("nav_region")  # idempotent -- déjà posé par la scène en temps normal.
	var nmesh := NavigationMesh.new()
	# Colliders statiques seulement : évite l'avertissement "parse RenderingServer
	# meshes at runtime" (lecture GPU->CPU coûteuse) -- chaque pièce pose déjà sa
	# propre collision, inutile de reparser les meshes visuels.
	nmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nmesh.agent_radius = AGENT_RADIUS
	nmesh.agent_height = AGENT_HEIGHT
	nmesh.agent_max_climb = AGENT_MAX_CLIMB
	nmesh.agent_max_slope = AGENT_MAX_SLOPE
	# Alignées sur le cell_size/cell_height PAR DÉFAUT de la carte de navigation
	# du projet (0.25, non redéfini dans project.godot).
	nmesh.cell_size = 0.25
	nmesh.cell_height = 0.25
	region.navigation_mesh = nmesh
	# Bake SYNCHRONE (pas de thread) : le navmesh doit être prêt avant
	# GameWorld._ready (qui peut faire spawn des bots la même frame).
	region.bake_navigation_mesh(false)

# ----------------------------------------------------------------------
#  Callouts : repère "où suis-je ?" -- vide tant qu'aucune carte n'en déclare.
# ----------------------------------------------------------------------
func callout_at(pos: Vector3) -> String:
	for entry in _callouts:
		var zone: Dictionary = entry
		var box: AABB = zone["aabb"]
		if box.has_point(pos):
			return String(zone["name"])
	return ""

# ----------------------------------------------------------------------
#  Mode de jeu : TDM, seul mode du prototype (MatchConfig.MODES == ["tdm"]).
# ----------------------------------------------------------------------
func _build_game_mode() -> void:
	var tdm := TDMMode.new()
	tdm.asymmetric_map = false  # Shipment est symétrique -- pas d'échange de côté.
	tdm.name = "GameMode"
	add_child(tdm)
