## TargetWasteland.gd (dev-only, scripts/dev/ -- excluded from exports)
## Recreates the composition of .orchestrator/refs/wasteland_hero.png with
## the real props (assets/models/props/manifest.json) so the painted-toon
## lighting/material rework (Cartoon/LevelLook/ink_*.gdshader) can be judged
## and tuned against the reference directly, independent of any other
## builder's placeholder level geometry. Camera at eye height, at the near
## end of a dirt street: shacks + a FUEL billboard on the left, sheds/shops
## on the right, two wrecked cars in the street, a derrick/water tower/
## gantry crane in the back.
extends Node3D

const P := "res://assets/models/props/wasteland/"

## Wasteland accent palette -- reserved-hue-safe (design.md v2 SS9: no world
## hue in 300-355 deg or 105-145 deg above chroma 0.08), mixing the "faded
## blue tin" family (SS7 "Wasteland: ... faded blue tin") with warm ochre and
## the FUEL/GAS sign colours (SS6 "Enseignes").
const _TEAL := Color("3fa3a0")
const _OCHRE := Color("c9853f")
const _GOLD := Color("f2c230")
const _RED_SIGN := Color("c8322b")
const _BLUE_SIGN := Color("2f63b8")
const _CREAM := Color("e6e1d6")

func _ready() -> void:
	MatchConfig.map_id = "wasteland"
	_build_env_and_light()
	_build_ground()
	_build_street()
	_build_background()
	_build_camera()

## A bare WorldEnvironment/DirectionalLight3D: LevelLook.gd (autoloaded, or
## simulated by tools/screenshot.gd) restyles ANY of these that enter the
## tree, so this dev scene never hardcodes sky/light values itself -- it
## exercises the exact same runtime path a real level does.
func _build_env_and_light() -> void:
	add_child(WorldEnvironment.new())
	var light := DirectionalLight3D.new()
	light.shadow_enabled = true
	add_child(light)

func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(140.0, 0.4, 140.0)
	ground.mesh = bm
	ground.position = Vector3(0, -0.2, -30)
	ground.material_override = Cartoon.painted(&"sand_dirt")
	add_child(ground)

func _prop(name: String, pos: Vector3, rot_y := 0.0, tints := {}, scale := 1.0) -> void:
	var inst := PropKit.instance(P + name + ".glb", pos, rot_y, tints)
	if inst:
		if scale != 1.0:
			inst.scale = Vector3.ONE * scale
		add_child(inst)

func _build_street() -> void:
	# -- Left row (shacks, FUEL) -- scaled up + pulled toward the camera
	# path so the near building looms the way wasteland_hero.png's does.
	_prop("wooden_shack", Vector3(-5.0, 0, 5.0), 90.0, {"accent": _TEAL, "glass": Color.WHITE}, 1.35)
	_prop("fuel_billboard", Vector3(-6.6, 0, 7.5), 8.0, {"sign": _BLUE_SIGN, "accent": _CREAM}, 1.2)
	_prop("fuel_pump", Vector3(-4.0, 0, 7.2), 0.0, {"accent": _RED_SIGN})
	_prop("wooden_shack", Vector3(-6.0, 0, -6.0), 90.0, {"accent": _OCHRE, "glass": Color.WHITE}, 1.2)
	_prop("wooden_crate", Vector3(-4.0, 0, -1.5), 20.0, {"accent": _OCHRE})
	_prop("wooden_crate", Vector3(-3.6, 0, -1.0), -10.0, {"accent": _TEAL})
	_prop("power_pole", Vector3(-7.0, 0, 1.5))
	_prop("fence_wood", Vector3(-7.0, 0, -10.0), 90.0)

	# -- Right row (sheds/shops) ------------------------------------------
	_prop("corrugated_shed", Vector3(5.6, 0, 3.0), -90.0, {"accent": _OCHRE}, 1.25)
	_prop("shop_sign", Vector3(4.2, 0, 6.5), -20.0, {"accent": _GOLD})
	_prop("corrugated_shed", Vector3(6.5, 0, -8.0), -90.0, {"accent": _TEAL})
	_prop("gas_billboard", Vector3(5.8, 0, 0.0), -8.0, {"sign": _RED_SIGN, "accent": _CREAM})
	_prop("oil_drum", Vector3(3.6, 0, 4.4), 0.0, {"accent": _RED_SIGN})
	_prop("oil_drum", Vector3(4.0, 0, 3.9), 0.0, {"accent": _BLUE_SIGN})
	_prop("tyre_stack", Vector3(3.8, 0, -5.0))
	_prop("pallet", Vector3(4.6, 0, -4.4), 15.0)
	_prop("power_pole", Vector3(7.5, 0, -4.0))

	# -- Street centre: two wrecked cars, off-axis so the lane still reads
	_prop("sedan_wreck", Vector3(1.8, 0, 0.0), 12.0, {"accent": _OCHRE})
	_prop("truck_wreck", Vector3(-1.6, 0, -9.0), -18.0, {"accent": _TEAL})
	_prop("sandbags", Vector3(0.6, 0, 8.5), 0.0)

func _build_background() -> void:
	_prop("oil_derrick", Vector3(-9.0, 0, -34.0))
	_prop("water_tower", Vector3(7.0, 0, -36.0))
	_prop("gantry_crane", Vector3(0.5, 0, -40.0), 90.0, {"accent": _OCHRE})
	_prop("pipe_straight", Vector3(-3.0, 0, -28.0), 0.0, {"accent": _TEAL})
	_prop("fence_chainlink", Vector3(-10.0, 0, -20.0), 90.0)
	_prop("fence_chainlink", Vector3(10.0, 0, -22.0), 90.0)

func _build_camera() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	# Eye height (~1.7 m), close to the left shack like wasteland_hero.png's
	# tight framing (street edges loom close on both sides, buildings fill
	# most of the frame height) -- pulled in from the v1-v4 wider blocking.
	cam.fov = 72.0
	cam.look_at_from_position(Vector3(-0.2, 1.65, 10.5), Vector3(0.3, 2.1, -30.0), Vector3.UP)
	cam.current = true
	set_meta("_cam", cam)
