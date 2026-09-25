## ArtLandmarks.gd (ART-99)
## docs/art/WASTELAND_V4_ART_PLAN.md §5 "Repères" — module de la couche
## d'art v4 de Wasteland (contrat `WastelandArt.gd`, §1 R9 : voir son
## en-tête pour le contrat imposé à CHAQUE module -- fonction statique
## `apply(parent, data)`, PUREMENT VISUEL, jamais de `CollisionObject3D`).
##
## Pose les repères de rang 1 nommés par le plan -- grue, derrick, auvent
## FUEL, 2 citernes GAS, panneaux FUEL/GAS, éolienne -- tous sur la terrasse
## nord (+6 m) ou le rebord sud du canyon (+4 m), donc HORS des `bounds`
## jouables de `wasteland.gd` ((-44,-25)..(44,20)) : « la grue et le derrick
## sont à plus de 18 m du bord jouable, ou sans collision : aucun point
## d'ancrage pour le grappin » (docs/research/11_wasteland_v4_layout.md §6
## "Règles de hauteur"). Le château d'eau (déjà dans le greybox de
## `wasteland.gd` -- pièces `PiedChateau*`/`ChateauCuve`, §2 du plan d'art,
## ART-96) reste visible SANS action de ce module : aucun repère ni décor
## ci-dessous ne se trouve sur l'axe Grand-Rue/Place qui mène à lui.
##
## Chargeur (`_load_landmark`) dupliqué À DESSEIN depuis
## `DressingKit._repaint_tripo`/`scripts/dev/BeautyCorner.gd::
## _load_painted_tripo` -- même convention documentée par ces deux fichiers :
## chaque sorte peinte Tripo charge et repeint directement SA PROPRE scène,
## jamais un chargeur partagé (voir l'en-tête de DressingKit.gd, section 5).
## Ces 7 fichiers (grue, derrick, auvent, citerne, 2 panneaux, éolienne) ne
## sont PAS dans `DressingKit.TRIPO_KIND_FILE` -- verrouillé à 4 entrées par
## `test_tripo_kind_file_maps_the_four_art89_kinds_to_their_painted_tripo_
## files` (contrat ART-89, jamais retouché ici) : `DressingKit.load_tripo()`
## ne peut donc pas les résoudre, ce module reste autonome, comme
## BeautyCorner avant lui.
class_name ArtLandmarks
extends RefCounted

const _TRIPO_DIR := "res://assets/models/props/wasteland/tripo/"

## Repères fixes (docs/art/WASTELAND_V4_ART_PLAN.md §5, table "Repères") --
## `pos` = contact au sol (même convention que DressingKit, voir son
## en-tête) ; `tint` facultative (absente = teinte peinte d'origine,
## inchangée -- grue/derrick/panneaux/éolienne restent tels que Tripo les a
## peints, comme dans BeautyCorner). Zonage couleur (doc 11 §8) : l'auvent
## FUEL (ouest) prend la tôle bleue partagée `Cartoon.CONTAINER_BLUE`, les 2
## citernes GAS (est) le rouge `Cartoon.CONTAINER_RED` -- mêmes jetons que
## Cargo Ship (aucun des deux dans les bandes de teinte réservées
## 300-355°/105-145°, STYLE_BIBLE §1.1.4/§4.4).
const _LANDMARKS: Array = [
	# Grue (ouest) / derrick (est), §5 "Repères" -- position et hauteur au
	# repère (base à +6 m, terrasse nord) : "Grue (−36 ; +6 ; −31) → 24 m",
	# "Derrick (28 ; +6 ; −31) → 22 m".
	{"file": "wl_crane_lattice", "pos": Vector3(-36.0, 6.0, -31.0), "rot_y": 20.0},
	{"file": "wl_oil_derrick", "pos": Vector3(28.0, 6.0, -31.0), "rot_y": -20.0},
	# Auvent FUEL (ouest seul, §5) : "(−29 ; +6 ; −36,5)".
	{"file": "wl_canopy_station", "pos": Vector3(-29.0, 6.0, -36.5), "rot_y": 0.0, "tint": Cartoon.CONTAINER_BLUE},
	# 2 citernes GAS (est seul, §5) : "(36,5 ; +6 ; −36,5)" -- 2 instances
	# décalées (jamais deux voisines identiques, R8) : travée + rotation.
	{"file": "wl_tank_horizontal", "pos": Vector3(35.0, 6.0, -36.5), "rot_y": 0.0, "tint": Cartoon.CONTAINER_RED},
	{"file": "wl_tank_horizontal", "pos": Vector3(38.5, 6.0, -35.0), "rot_y": 35.0, "tint": Cartoon.CONTAINER_RED},
	# Panneaux FUEL/GAS, §5 : "crête ouest (−46,5 ; +6 ; −20), face à l'est" /
	# "crête est (46,5 ; +6 ; −20), face à l'ouest" -- Tripo place sa façade
	# détaillée en +Z à rot_y=0 (§2 du plan d'art) : viser l'axe de la carte
	# (+X depuis l'ouest, -X depuis l'est) tourne la façade de ∓90°.
	{"file": "wl_fuel_billboard", "pos": Vector3(-46.5, 6.0, -20.0), "rot_y": -90.0},
	{"file": "wl_gas_billboard", "pos": Vector3(46.5, 6.0, -20.0), "rot_y": 90.0},
	# Éolienne, §5 "rebord sud (±38 ; +4 ; 22,2)" -- doc 11 §8 "au bout ouest
	# du canyon, l'éolienne de pompage" : ouest seule (le wagonnet renversé,
	# miroir est, dépend du module `mine_cart` de `make_wl_shanty_kit.py`
	# (ART-92) qui n'est pas encore catalogué dans PropCatalog à cette
	# tâche -- omis plutôt que de poser un repère non résolu).
	{"file": "wl_eolienne", "pos": Vector3(-38.0, 4.0, 22.2), "rot_y": 0.0},
]

## Contrat de module (`WastelandArt.MODULE_PATHS`) : `parent` = le
## `NavigationRegion3D` réel de `MapSetup`, `data` = `WastelandLayout.
## data()`. Ce module n'utilise pas `data` -- les repères sont fixes, hors
## du gabarit paramétrique de la carte (même raison que `Backdrop.gd::
## directional_landmarks`) -- le paramètre reste présent pour respecter le
## contrat commun à tous les modules du registre.
static func apply(parent: Node3D, _data: Dictionary) -> void:
	for i in _LANDMARKS.size():
		var entry: Dictionary = _LANDMARKS[i]
		var tint: Color = entry.get("tint", Color.WHITE)
		var inst := _load_landmark(String(entry["file"]), tint)
		if inst == null:
			continue
		inst.name = "Landmark%d_%s" % [i, String(entry["file"])]
		inst.position = entry["pos"]
		inst.rotation_degrees.y = float(entry["rot_y"])
		parent.add_child(inst)
		# Purement visuel (§1 R9) : AUCUNE collision posée, à la différence de
		# `BeautyCorner._add_box_collision_from_aabb` -- ces repères sont hors
		# de portée du joueur (terrasse nord/rebord sud, hors des `bounds`
		# jouables) et doivent rester SANS point d'ancrage pour le grappin
		# (doc 11 §6 "Règles de hauteur").


## Charge et repeint (teinte incluse) le fichier peint Tripo `file` --
## `null` si introuvable (jamais un crash, même contrat que
## `DressingKit.load_tripo`/`PropCatalog.place` pour un nom inconnu).
static func _load_landmark(file: String, tint: Color = Color.WHITE) -> Node3D:
	var packed := load(_TRIPO_DIR + file + ".glb") as PackedScene
	if packed == null:
		push_warning("ArtLandmarks: repère introuvable « %s »" % file)
		return null
	var inst := packed.instantiate() as Node3D
	_repaint(inst, tint)
	return inst


static func _repaint(node: Node, tint: Color) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mi := node as MeshInstance3D
		for i in range(mi.mesh.get_surface_count()):
			var src: Material = mi.get_surface_override_material(i)
			if src == null:
				src = mi.mesh.surface_get_material(i)
			var tex := Cartoon.texture_from_imported_material(src)
			mi.set_surface_override_material(i, Cartoon.painted_texture_prop(tex, tint))
	for c in node.get_children():
		_repaint(c, tint)
