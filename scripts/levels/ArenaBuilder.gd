## ArenaBuilder.gd
## Construit par code un PARCOURS DE TEST DE MOUVEMENT, pensé pour éprouver la
## tech façon Apex : pente de vitesse (slide), champ de piliers, kicker + trou à
## franchir en slide-jump, jump pad vers une plateforme haute, et un retour qui
## boucle le circuit (plaza → pente → champ → saut → pad → passerelle → plaza).
##
## Tout est généré au _ready : appuie sur Play pour le voir. Géométrie en boîtes
## (StaticBody3D + BoxShape) avec des couleurs cartoon par zone. Régle/édite ici.
class_name ArenaBuilder
extends Node3D

@export var build_on_ready: bool = true

const JUMP_PAD := preload("res://scripts/levels/JumpPad.gd")

# Palette cartoon (plate, lisible)
const C_PLAZA := Color("4e9bd4")
const C_SLOPE := Color("f2b134")
const C_FIELD := Color("6abf69")
const C_PLATFORM := Color("ece6d4")
const C_PILLAR := Color("d9534f")
const C_WALL := Color("38485a")
const C_PAD := Color("9b59d6")
const C_ACCENT := Color("ff6f59")

var _mats: Dictionary = {}

func _ready() -> void:
	if build_on_ready:
		build()

# ------------------------------------------------------------------ HELPERS
func _mat(color: Color) -> StandardMaterial3D:
	if not _mats.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.95
		_mats[color] = m
	return _mats[color]

func _piece(xform: Transform3D, size: Vector3, color: Color, nm: String) -> StaticBody3D:
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
	return body

## Boîte alignée sur les axes. `center` = centre, `size` = dimensions.
func _block(center: Vector3, size: Vector3, color: Color, nm := "Block") -> StaticBody3D:
	return _piece(Transform3D(Basis(), center), size, color, nm)

## Rampe définie par 2 points sur sa SURFACE (centre des extrémités). Plus simple
## à placer : on donne le début et la fin, la rotation est calculée.
func _ramp(start: Vector3, end: Vector3, width: float, color: Color, thickness := 1.0, nm := "Ramp") -> StaticBody3D:
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
	return _piece(Transform3D(ramp_basis, center), Vector3(length, thickness, width), color, nm)

## Pilier posé sur le sol du champ (sommet du champ à y = -10).
func _pillar(x: float, z: float, h: float, color := C_PILLAR) -> StaticBody3D:
	return _block(Vector3(x, -10.0 + h * 0.5, z), Vector3(3, h, 3), color, "Pillar")

## Jump pad (Area3D) qui propulse vers le haut.
func _pad(center: Vector3, size: Vector3, boost: float) -> Area3D:
	var a := Area3D.new()
	a.set_script(JUMP_PAD)
	a.name = "JumpPad"
	a.set("boost", boost)
	a.transform = Transform3D(Basis(), center)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	a.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = _mat(C_PAD)
	a.add_child(mesh)
	add_child(a)
	return a

# ------------------------------------------------------------------ LAYOUT
func build() -> void:
	# ----- ZONE 1 : PLAZA (warmup / spawn) -----
	_block(Vector3(0, -0.5, 0), Vector3(30, 1, 30), C_PLAZA, "Plaza")
	_block(Vector3(0, 3, -15.5), Vector3(32, 8, 1), C_WALL, "PlazaWallBack")
	_block(Vector3(-15.5, 3, 0), Vector3(1, 8, 32), C_WALL, "PlazaWallLeft")
	_block(Vector3(0, 3, 15.5), Vector3(32, 8, 1), C_WALL, "PlazaWallRight")
	# (côté +X ouvert : c'est l'entrée de la pente)

	# ----- ZONE 2 : PENTE DE VITESSE (slide pour accélérer) -----
	_ramp(Vector3(15, 0, 0), Vector3(60, -10, 0), 20, C_SLOPE, 1.0, "SpeedSlope")

	# ----- ZONE 3 : CHAMP BAS + PILIERS (slalom / cover) -----
	_block(Vector3(100, -10.5, 0), Vector3(80, 1, 70), C_FIELD, "Field")
	# Murs périmètre (côté +X laissé OUVERT pour le trou de slide-jump)
	_block(Vector3(100, -7, 35.5), Vector3(80, 7, 1), C_WALL, "FieldWallZ+")
	_block(Vector3(100, -7, -35.5), Vector3(80, 7, 1), C_WALL, "FieldWallZ-")
	_block(Vector3(60, -7, 26), Vector3(1, 7, 18), C_WALL, "FieldWallEntryR")
	_block(Vector3(60, -7, -26), Vector3(1, 7, 18), C_WALL, "FieldWallEntryL")
	# Piliers de hauteurs variées
	_pillar(80, -8, 4.0)
	_pillar(90, 7, 6.0)
	_pillar(98, -12, 3.0)
	_pillar(105, 9, 7.0)
	_pillar(112, -6, 5.0)
	_pillar(118, 4, 8.0)

	# ----- ZONE 4 : KICKER + TROU (slide-jump par-dessus le vide) -----
	# Le kicker part du sol du champ et lance vers +X au bord de la zone.
	_ramp(Vector3(132, -10, 0), Vector3(140, -6.5, 0), 12, C_ACCENT, 1.0, "Kicker")
	# Vide entre x=140 et x=149 (pas de sol → chute → respawn).
	# Plateforme d'atterrissage (sommet à y = -6).
	_block(Vector3(158, -6.5, 0), Vector3(18, 1, 22), C_PLATFORM, "LandingPlatform")

	# ----- ZONE 5 : JUMP PAD → PLATEFORME HAUTE -----
	_pad(Vector3(158, -5.9, 0), Vector3(6, 0.4, 6), 20.0)
	_block(Vector3(158, 1.5, 0), Vector3(16, 1, 18), C_PLATFORM, "HighLedge")
	_block(Vector3(158, 4, -9.5), Vector3(16, 6, 1), C_WALL, "HighLedgeRailA")
	_block(Vector3(158, 4, 9.5), Vector3(16, 6, 1), C_WALL, "HighLedgeRailB")

	# ----- ZONE 6 : PASSERELLE RETOUR (boucle vers la plaza) -----
	# Longue descente douce de la plateforme haute jusqu'au bord de la plaza.
	_ramp(Vector3(150, 2, 0), Vector3(16, 0.2, 0), 6, C_SLOPE, 1.0, "ReturnBridge")
