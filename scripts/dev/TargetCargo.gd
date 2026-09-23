## TargetCargo.gd (dev-only, scripts/dev/ -- excluded from exports)
## Recreates the composition of .orchestrator/refs/cargo_ship_hero.png:
## red/blue/orange/white container stacks on a painted steel deck, a cargo
## crane and bridge/mast silhouette in back, under a big blue sky.
extends Node3D

const P := "res://assets/models/props/cargo_ship/"

func _ready() -> void:
	MatchConfig.map_id = "cargo_ship"
	_build_env_and_light()
	_build_deck()
	_build_containers()
	_build_ship()
	_build_camera()

func _build_env_and_light() -> void:
	add_child(WorldEnvironment.new())
	var light := DirectionalLight3D.new()
	light.shadow_enabled = true
	add_child(light)

func _build_deck() -> void:
	var deck := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(60.0, 0.4, 60.0)
	deck.mesh = bm
	deck.position = Vector3(0, -0.2, -20)
	deck.material_override = Cartoon.painted(&"ship_deck")
	add_child(deck)

func _prop(name: String, pos: Vector3, rot_y := 0.0, tints := {}, scale := 1.0) -> void:
	var packed := load(P + name + ".glb") as PackedScene
	if packed == null:
		return
	var inst := packed.instantiate() as Node3D
	inst.position = pos
	inst.rotation_degrees.y = rot_y
	if scale != 1.0:
		inst.scale = Vector3.ONE * scale
	PropKit.paint(inst, tints)
	add_child(inst)

## Real ISO container height (assets/models/props/manifest.json:
## container_20ft/40ft footprint.h = 2.59, center-pivoted). Lead review:
## the earlier 2.3 m tier spacing under-shot this by 0.29 m per tier, so
## stacked containers interpenetrated -- a jagged z-fighting seam that read
## as a "jagged red/blue split" rather than a clean stack boundary.
const _CONTAINER_H := 2.59
const _TIER1 := _CONTAINER_H * 0.5
const _TIER2 := _TIER1 + _CONTAINER_H
const _TIER3 := _TIER2 + _CONTAINER_H

## One colour block per quadrant (design.md v2 SS7 "Cargo Ship: one container
## colour per quadrant") -- stacked 20ft/40ft containers, red/blue/orange/
## white, either side of a lane down the middle like the reference.
func _build_containers() -> void:
	var reds := {"container": Cartoon.CONTAINER_RED}
	var blues := {"container": Cartoon.CONTAINER_BLUE}
	var oranges := {"container": Cartoon.CONTAINER_ORANGE}
	var whites := {"container": Cartoon.CONTAINER_WHITE}

	# Left stack (front): red over blue, two tiers.
	_prop("container_40ft", Vector3(-6.0, _TIER1, 4.0), 0.0, reds)
	_prop("container_40ft", Vector3(-6.0, _TIER2, 4.0), 0.0, blues)
	_prop("container_20ft", Vector3(-6.0, _TIER1, -2.0), 0.0, oranges)
	_prop("container_20ft", Vector3(-6.0, _TIER2, -2.0), 0.0, whites)

	# Right stack (front): orange/white over blue/red, offset for variety.
	_prop("container_40ft", Vector3(6.0, _TIER1, 3.0), 0.0, oranges)
	_prop("container_40ft", Vector3(6.0, _TIER2, 3.0), 0.0, whites)
	_prop("container_20ft", Vector3(6.0, _TIER1, -3.0), 90.0, blues)
	_prop("container_20ft", Vector3(6.0, _TIER2, -3.0), 90.0, reds)

	# Further stacks receding down the lane, three tiers tall like the ref.
	_prop("container_40ft", Vector3(-5.5, _TIER1, -12.0), 0.0, blues)
	_prop("container_40ft", Vector3(-5.5, _TIER2, -12.0), 0.0, reds)
	_prop("container_40ft", Vector3(-5.5, _TIER3, -12.0), 0.0, oranges)
	_prop("container_40ft", Vector3(5.5, _TIER1, -13.0), 0.0, whites)
	_prop("container_40ft", Vector3(5.5, _TIER2, -13.0), 0.0, oranges)
	_prop("container_40ft", Vector3(5.5, _TIER3, -13.0), 0.0, blues)

	_prop("hatch_cover", Vector3(0.0, 0.05, -4.0))
	_prop("bollard", Vector3(-2.0, 0.0, 9.0))
	_prop("bollard", Vector3(2.0, 0.0, 9.0))

func _build_ship() -> void:
	_prop("cargo_crane", Vector3(0.0, 0.0, -20.0), 0.0, {"accent": Color("f2b51d")})
	_prop("bridge_superstructure", Vector3(0.0, 0.0, -32.0), 0.0, {"accent": Cartoon.CONTAINER_WHITE})
	_prop("mast_antennas", Vector3(0.0, 8.0, -32.0), 0.0, {"accent": Color("f2b51d")})
	_prop("deck_railing", Vector3(-9.5, 0.0, -4.0), 0.0)
	_prop("deck_railing", Vector3(9.5, 0.0, -4.0), 0.0)
	_prop("life_ring", Vector3(-9.3, 1.2, 6.0), 0.0, {"accent": Color("c8322b")})
	_prop("stairs_ladder", Vector3(0.0, 0.0, -26.0))

func _build_camera() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 72.0
	cam.look_at_from_position(Vector3(-2.0, 1.7, 12.0), Vector3(0.0, 3.0, -25.0), Vector3.UP)
	cam.current = true
