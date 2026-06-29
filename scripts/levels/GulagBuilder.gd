## GulagBuilder.gd
## Construit par code une arène symétrique 1v1 / 2v2 avec un vrai "blocking" :
## plateforme centrale surélevée + rampes (verticalité), couvertures étagées,
## et deux zones (dégâts / soin) placées À L'ÉCART des spawns pour tester la vie.
## Spawns : aux deux extrémités (définis dans arena_1v1.tscn).
class_name GulagBuilder
extends Node3D

const DAMAGE_ZONE := preload("res://scripts/world/DamageZone.gd")
const HEAL_ZONE := preload("res://scripts/world/HealZone.gd")

const C_FLOOR := Color("5a6470")
const C_FLOOR2 := Color("646e7a")
const C_WALL := Color("39424d")
const C_COVER := Color("c0843d")
const C_PLATFORM := Color("8a8f98")
const C_DMG := Color("d9433f")
const C_HEAL := Color("3fb56b")

var _mats: Dictionary = {}

func _ready() -> void:
	build()

func _mat(color: Color, transparent := false) -> StandardMaterial3D:
	var key := str(color) + str(transparent)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.95
		if transparent:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[key] = m
	return _mats[key]

func _piece(xform: Transform3D, size: Vector3, color: Color, nm: String) -> void:
	var body := StaticBody3D.new()
	body.name = nm
	body.transform = xform
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

func _block(center: Vector3, size: Vector3, color: Color, nm := "Block") -> void:
	_piece(Transform3D(Basis(), center), size, color, nm)

## Crate de couverture (sommet posé sur le sol à y=0).
func _crate(x: float, z: float, h: float, w := 2.0) -> void:
	_block(Vector3(x, h * 0.5, z), Vector3(w, h, w), C_COVER, "Crate")

## Rampe définie par 2 points sur sa surface (début, fin) + largeur.
func _ramp(start: Vector3, end: Vector3, width: float, color: Color, thickness := 1.0) -> void:
	var dir := end - start
	var length := dir.length()
	var fwd := dir.normalized()
	var side := Vector3.UP.cross(fwd)
	if side.length() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := fwd.cross(side).normalized()
	var ramp_basis := Basis(fwd, up, side)
	var center := (start + end) * 0.5 - up * (thickness * 0.5)
	_piece(Transform3D(ramp_basis, center), Vector3(length, thickness, width), color, "Ramp")

func _zone(center: Vector3, size: Vector3, color: Color, script: Script, nm: String) -> void:
	var area := Area3D.new()
	area.set_script(script)
	area.name = nm
	area.position = center
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	area.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var c := color
	c.a = 0.28
	mesh.material_override = _mat(c, true)
	area.add_child(mesh)
	add_child(area)

func build() -> void:
	# ----- Sol (40 x 24, sommet à y=0) -----
	_block(Vector3(0, -0.5, 0), Vector3(40, 1, 24), C_FLOOR, "Floor")

	# ----- Murs périmètre (hauteur 6) -----
	_block(Vector3(0, 3, 12.0), Vector3(40, 6, 1), C_WALL, "WallN")
	_block(Vector3(0, 3, -12.0), Vector3(40, 6, 1), C_WALL, "WallS")
	_block(Vector3(20.0, 3, 0), Vector3(1, 6, 24), C_WALL, "WallE")
	_block(Vector3(-20.0, 3, 0), Vector3(1, 6, 24), C_WALL, "WallW")

	# ----- Plateforme centrale surélevée (catwalk) + rampes -----
	_block(Vector3(0, 0.75, 0), Vector3(10, 1.5, 6), C_PLATFORM, "CenterPlatform")
	# Rampes d'accès depuis +z et -z (montent du sol jusqu'au sommet à y=1.5).
	_ramp(Vector3(0, 0, 7.0), Vector3(0, 1.5, 3.0), 6.0, C_PLATFORM)
	_ramp(Vector3(0, 0, -7.0), Vector3(0, 1.5, -3.0), 6.0, C_PLATFORM)

	# ----- Couvertures étagées symétriques -----
	# Près de chaque spawn (caisses basses pour se mettre à couvert au réveil).
	_crate(-13, 5, 1.4); _crate(-13, -5, 1.4)
	_crate(13, 5, 1.4);  _crate(13, -5, 1.4)
	# Cover mid-terrain, hauteurs variées.
	_crate(-7, 8, 2.0); _crate(7, -8, 2.0)
	_crate(-7, -8, 1.2); _crate(7, 8, 1.2)
	_crate(-4, 0, 1.0, 1.5); _crate(4, 0, 1.0, 1.5)
	# Murets bas le long du milieu (cassent les lignes de tir).
	_block(Vector3(-9, 0.5, 0), Vector3(1.5, 1.0, 5), C_COVER, "LowWallW")
	_block(Vector3(9, 0.5, 0), Vector3(1.5, 1.0, 5), C_COVER, "LowWallE")

	# ----- Zones de test (à l'écart des spawns x=±16) -----
	_zone(Vector3(-8, 1.5, 9), Vector3(4, 3, 4), C_DMG, DAMAGE_ZONE, "DamageZone")
	_zone(Vector3(8, 1.5, -9), Vector3(4, 3, 4), C_HEAL, HEAL_ZONE, "HealZone")
