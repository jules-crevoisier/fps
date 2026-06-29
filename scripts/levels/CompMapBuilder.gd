## CompMapBuilder.gd
## Map compétitive style CoD (SnD / Hardpoint) générée par code : deux spawns
## opposés, trois lanes (mid + deux côtés), deux sites (A / B) marqués, une zone
## Hardpoint centrale, du cover et un peu d'élévation. Géométrie placeholder.
class_name CompMapBuilder
extends Node3D

const C_FLOOR := Color("4f5a66")
const C_FLOOR2 := Color("596570")
const C_WALL := Color("39434e")
const C_COVER := Color("b8863f")
const C_PLATFORM := Color("7d838c")
const C_SITE := Color("d94f44")
const C_HARDPOINT := Color("e0b341")

var _mats: Dictionary = {}

func _ready() -> void:
	build()

func _mat(color: Color, transp := false) -> StandardMaterial3D:
	var key := str(color) + str(transp)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.95
		if transp:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[key] = m
	return _mats[key]

func _block(center: Vector3, size: Vector3, color: Color, nm := "Block") -> void:
	var body := StaticBody3D.new()
	body.name = nm
	body.position = center
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = _mat(color)
	body.add_child(mesh)
	add_child(body)

func _crate(x: float, z: float, h: float, w := 2.0) -> void:
	_block(Vector3(x, h * 0.5, z), Vector3(w, h, w), C_COVER, "Crate")

## Marqueur de zone (visuel translucide) + grande lettre.
func _zone_marker(center: Vector3, size: Vector3, color: Color, letter: String) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.position = center
	var c := color
	c.a = 0.18
	mesh.material_override = _mat(c, true)
	add_child(mesh)
	if letter != "":
		var l := Label3D.new()
		l.text = letter
		l.position = center + Vector3(0, size.y * 0.5 + 0.5, 0)
		l.font_size = 120
		l.pixel_size = 0.01
		l.modulate = color
		l.outline_size = 12
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)

func build() -> void:
	# ----- Sol (64 x 44) -----
	_block(Vector3(0, -0.5, 0), Vector3(64, 1, 44), C_FLOOR, "Floor")

	# ----- Murs périmètre -----
	_block(Vector3(0, 3, 22), Vector3(64, 7, 1), C_WALL, "WallN")
	_block(Vector3(0, 3, -22), Vector3(64, 7, 1), C_WALL, "WallS")
	_block(Vector3(32, 3, 0), Vector3(1, 7, 44), C_WALL, "WallE")
	_block(Vector3(-32, 3, 0), Vector3(1, 7, 44), C_WALL, "WallW")

	# ----- Séparateurs de lanes (murs longitudinaux avec ouvertures) -----
	# Lane Nord / Mid à z=+8, Mid / Sud à z=-8. Trous au milieu pour les rotations.
	for sgn in [1, -1]:
		var z: float = 8.0 * sgn
		_block(Vector3(-16, 2, z), Vector3(20, 4, 1), C_WALL, "LaneWall")
		_block(Vector3(16, 2, z), Vector3(20, 4, 1), C_WALL, "LaneWall")

	# ----- Bâtiment central (mid) + élévation -----
	_block(Vector3(0, 1.0, 0), Vector3(8, 2, 8), C_PLATFORM, "MidBuilding")
	_block(Vector3(0, 2.0, 0), Vector3(6, 0.5, 6), C_PLATFORM, "MidTop")

	# ----- Cover réparti -----
	_crate(-18, 0, 1.4); _crate(18, 0, 1.4)
	_crate(-10, 14, 1.6); _crate(10, 14, 1.6)
	_crate(-10, -14, 1.6); _crate(10, -14, 1.6)
	_crate(-22, 14, 2.0); _crate(22, -14, 2.0)
	_crate(-22, -14, 2.0); _crate(22, 14, 2.0)
	_crate(0, 16, 1.2); _crate(0, -16, 1.2)
	# Murets bas autour des sites.
	_block(Vector3(20, 0.6, 11), Vector3(6, 1.2, 1), C_COVER, "SiteWallA")
	_block(Vector3(20, 0.6, -11), Vector3(6, 1.2, 1), C_COVER, "SiteWallB")

	# ----- Sites A (Nord-Est) et B (Sud-Est) -----
	_zone_marker(Vector3(22, 0.6, 14), Vector3(8, 1.2, 8), C_SITE, "A")
	_zone_marker(Vector3(22, 0.6, -14), Vector3(8, 1.2, 8), C_SITE, "B")
	# La zone Hardpoint est un Area3D mobile défini dans la scène (HardpointMode).
