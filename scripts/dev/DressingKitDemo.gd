## DressingKitDemo.gd (ART-87, dev-only, scripts/dev/ -- exclu des builds)
## Scène de démo AUTONOME (n'importe jamais une vraie carte/layout) pour la
## revue visuelle du kit d'habillage (scripts/levels/dressing/DressingKit.gd,
## lu seul) : une ligne de poteaux + câbles qui pendent, une clôture à
## grillage, trois grappes de props au pied d'un mur (caisses, fûts,
## fouillis) et un semis (cailloux, planches, touffes d'herbe sèche,
## virevoltants) tout autour, sur un sol plat peint.
##
## `MatchConfig.map_id = "wasteland"` avant tout WorldEnvironment/
## DirectionalLight3D (même convention que `scripts/dev/BeautyCorner.gd`) :
## `LevelLook.gd` (autoload "Look", ou simulé par `tools/screenshot.gd` comme
## `tools/map_shots.gd` le fait déjà) restyle alors ciel/soleil/brouillard
## EXACTEMENT comme la vraie carte -- rien de tout ça n'est codé ici.
##
## Capture (contrat ART-87, "démo capturée") : outil GÉNÉRIQUE existant,
## jamais un script de capture dédié (hors du périmètre de ce contrat --
## `tools/review/` n'est pas dans la liste des fichiers possédés) :
##   godot --path . -s res://tools/screenshot.gd -- \
##       --scene=res://scenes/dev/dressing_kit_demo.tscn --out=<chemin>.png \
##       --map_id=wasteland
extends Node3D

const _GROUND_SIZE := 44.0
const _GROUND_TINT := Color("d2a46c")  # sable Wasteland, STYLE_BIBLE §6.4 #07


func _ready() -> void:
	MatchConfig.map_id = "wasteland"
	add_child(WorldEnvironment.new())
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-42.0, -70.0, 0.0)
	add_child(sun)

	_build_ground()
	_build_poles_and_cables()
	_build_fence()
	_build_clusters()
	_build_scatter()
	_build_camera()


func _build_ground() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(_GROUND_SIZE, _GROUND_SIZE)
	mesh.mesh = plane
	mesh.material_override = Cartoon.world(_GROUND_TINT)
	add_child(mesh)


## Ligne de 4 poteaux (>= 3 -> MultiMesh, PropCatalog.place_many) reliés par
## 3 câbles qui pendent (`sag` visible : 0,7 m sur ~10 m de portée).
func _build_poles_and_cables() -> void:
	var points := [Vector3(-15.0, 0.0, -9.0), Vector3(-5.0, 0.0, -9.0), Vector3(5.0, 0.0, -9.0), Vector3(15.0, 0.0, -9.0)]
	DressingKit.poles_and_cables(self, points, 0.7, 6.5)


## Clôture à grillage en deux tronçons (angle), assez longue pour dépasser
## le seuil de 3 panneaux (batching MultiMesh).
func _build_fence() -> void:
	var points := [Vector3(-17.0, 0.0, 5.0), Vector3(-1.0, 0.0, 5.0), Vector3(6.0, 0.0, 11.0)]
	DressingKit.fence_run(self, points, "chainlink")


## Trois grappes distinctes (une par kind du contrat) au pied d'un même mur
## imaginaire (`facing` commun), pour comparer leur lecture côte à côte.
func _build_clusters() -> void:
	DressingKit.cluster_against_wall(self, Vector3(-9.0, 0.0, -2.0), Vector3(0.0, 0.0, -1.0), "crates", 3.0, 1)
	DressingKit.cluster_against_wall(self, Vector3(0.0, 0.0, -2.0), Vector3(0.0, 0.0, -1.0), "barrels", 3.0, 2)
	DressingKit.cluster_against_wall(self, Vector3(9.0, 0.0, -2.0), Vector3(0.0, 0.0, -1.0), "junk", 3.0, 3)


## Semis des 4 kinds procéduraux sur le reste de la scène, avec une boîte
## interdite couvrant l'allée centrale (poteaux/clôture/grappes) pour ne pas
## noyer la lecture des pièces catalogées.
func _build_scatter() -> void:
	var area := Rect2(-20.0, -18.0, 40.0, 32.0)
	var keep_clear := AABB(Vector3(-11.0, -1.0, -4.0), Vector3(22.0, 3.0, 4.0))
	DressingKit.scatter(self, area, ["rock", "plank", "tuft", "tumbleweed"], 0.2, 9, [keep_clear])


func _build_camera() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 60.0
	cam.look_at_from_position(Vector3(0.0, 13.0, 22.0), Vector3(0.0, 1.5, -3.0), Vector3.UP)
	cam.current = true
