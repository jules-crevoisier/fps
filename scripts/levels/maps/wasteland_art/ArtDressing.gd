## ArtDressing.gd (ART-99)
## docs/art/WASTELAND_V4_ART_PLAN.md §5 "Habillage et repères" (table
## "Densités" + "Poteaux et câbles") — module de la couche d'art v4 de
## Wasteland (contrat `WastelandArt.gd`, §1 R9 : fonction statique
## `apply(parent, data)`, PUREMENT VISUEL, jamais de `CollisionObject3D`).
##
## S'appuie sur `DressingKit` (ART-87) pour le semis fin (`scatter`, kinds
## "rock"/"plank"/"tuft"/"tumbleweed" -- exactement le vocabulaire du plan
## d'art : "cailloux et planches"/"touffes sèches"/"virevoltants") et les
## poteaux + câbles (`poles_and_cables`, `collision:false` -- §1 R9). Les
## exclusions (`exclude`, voir `DressingKit`) sont calculées depuis
## `data["pieces"]` (§1 R3 "jamais recopiée à la main") plutôt que recopiées
## à la main : `_solid_exclude_boxes` reprend TOUTE pièce `box`/`building2`
## qui n'est PAS le sol lui-même (`color_key != "floor"`, voir
## `wasteland.gd::_floor_piece`) -- couvertures, murs, jambes/cuve du
## château d'eau, falaises -- pour qu'aucun caillou/planche ne s'enfonce
## dans un volume plein, sans jamais recopier une seule coordonnée de
## bâtiment.
class_name ArtDressing
extends RefCounted

# ======================================================================
#  Densités (§5, table "Densités" -- éléments par m², ±20% au critère
#  d'acceptation) et zones (docs/research/11_wasteland_v4_layout.md §5 "Les
#  lanes" -- z du plateau à y=0, canyon à y=-2).
# ======================================================================

## "① Grand-Rue | cailloux et planches 0,12/m², virevoltants ≤ 0,35 m, 1
## pour 60 m², statiques".
const _RUE_ROCK_PLANK_DENSITY := 0.12
const _RUE_TUMBLEWEED_DENSITY := 1.0 / 60.0
## Doc 11 §5 "① Grand-Rue (z −19 à −11)" -- corridor complet (le bloc
## central Poste/Diligence, `color_key != "floor"`, est retiré par
## `_solid_exclude_boxes`, jamais par un découpage de rect à la main).
const _RUE_Z0 := -19.0
const _RUE_Z1 := -11.0
const _RUE_X0 := -39.0
const _RUE_X1 := 39.0

## "② Intérieurs, Ruelles | planches, paille, verre 0,2/m²" -- seule la
## Ruelle (couloir à l'air libre entre Echoppes et Saloon, doc 11 §5 "allée
## Nord-Sud de 4 m") est couverte ici : un intérieur de bâtiment (Echoppes/
## Saloon) est un volume géré par `ArtBuildings1F.gd`/`ArtBuildings2F.gd`
## (ART-94/95, hors de mon périmètre de fichiers) et n'a pas de largeur
## connue de ce module sans dupliquer leurs données de pièces salle par
## salle.
const _RUELLE_DEBRIS_DENSITY := 0.2
const _RUELLE_WIDTH := 4.0

## "③ Canyon | rock_01/02 (≤ 0,3 m) 0,25/m² au pied des parois, touffes
## sèches ocre" -- doc 11 §5 "Canyon (z 12 à 20, sol −2)".
const _CANYON_ROCK_TUFT_DENSITY := 0.25
const _CANYON_Z0 := 12.0
const _CANYON_Z1 := 20.0
const _CANYON_Y := -2.0

## "Hors-jeu | grappes Tripo libres (densité ×3), tripo_row avec
## collision:false" -- terrasse nord (+6 m, hors des `bounds` jouables),
## juste au-delà de CliffN (z −26..−25 dans `wasteland.gd::_cliffs`).
const _HORS_JEU_Z := -27.0
const _HORS_JEU_X0 := -20.0
const _HORS_JEU_X1 := 20.0
const _HORS_JEU_SPACING := 3.0
const _HORS_JEU_KIND := "junk_pile"

## "Poteaux et câbles (DressingKit.poles_and_cables) : ligne encastrée dans
## le parapet de l'arête (x ±42,5, ±31, ±22, ±11, ±4)" -- même z que les
## segments `ParapetW1/2/3` réels de `wasteland.gd` (11,9 -- vérifié : les 10
## abscisses tombent chacune dans un segment de parapet existant, jamais
## dans une des deux ouvertures de rampe du canyon).
const _ARETE_POLE_X: PackedFloat32Array = [-42.5, -31.0, -22.0, -11.0, -4.0, 4.0, 11.0, 22.0, 31.0, 42.5]
const _ARETE_POLE_Z := 11.9
const _ARETE_POLE_SAG := 0.6
const _ARETE_POLE_HEIGHT := 3.5

const _SEED_RUE_ROCKS := 9901
const _SEED_RUE_TUMBLEWEEDS := 9902
const _SEED_RUELLE_WEST := 9903
const _SEED_RUELLE_EAST := 9904
const _SEED_CANYON := 9905
const _SEED_HORS_JEU := 9906


static func apply(parent: Node3D, data: Dictionary) -> void:
	var solids := _solid_exclude_boxes(data)
	_scatter_grand_rue(parent, solids)
	_scatter_ruelles(parent, data, solids)
	_scatter_canyon(parent, solids)
	_scatter_hors_jeu(parent)
	_poles_and_cables_arete(parent)


## Toute boîte "pleine" de `data["pieces"]` (couverture, mur, jambe/cuve du
## château d'eau, falaise...) -- jamais le sol lui-même (`color_key ==
## "floor"`, `wasteland.gd::_floor_piece`), sans quoi AUCUN semis ne
## survivrait (le sol couvre tout le plateau/canyon à y=0/-2, exactement le
## plan où le semis se pose). `type in {"box","building2"}` seulement : les
## rampes/escaliers/clôtures (types "ramp"/"stairs"/"fence") restent bas et
## ajourés, jamais un obstacle plein pour un caillou au sol.
static func _solid_exclude_boxes(data: Dictionary) -> Array:
	var out: Array = []
	for entry in (data.get("pieces", []) as Array):
		var piece: Dictionary = entry
		var kind := String(piece.get("type", ""))
		if kind != "box" and kind != "building2":
			continue
		if String(piece.get("color_key", "")) == "floor":
			continue
		var pos: Vector3 = piece["pos"]
		var size: Vector3 = piece["size"]
		out.append(AABB(pos - size * 0.5, size))
	return out


static func _scatter_grand_rue(parent: Node3D, solids: Array) -> void:
	var area := Rect2(_RUE_X0, _RUE_Z0, _RUE_X1 - _RUE_X0, _RUE_Z1 - _RUE_Z0)
	DressingKit.scatter(parent, area, ["rock", "plank"], _RUE_ROCK_PLANK_DENSITY, _SEED_RUE_ROCKS, solids, {}, 0.0)
	DressingKit.scatter(parent, area, ["tumbleweed"], _RUE_TUMBLEWEED_DENSITY, _SEED_RUE_TUMBLEWEEDS, solids, {}, 0.0)


## Ruelle ouest/est : couloir Nord-Sud entre Echoppes et Saloon (doc 11 §5),
## centré sur le milieu du vide entre le mur est d'EchoppesW et le mur
## ouest de SaloonW -- même dérivation que `tools/art/v4_shots.gd::
## _build_poses` (vue V7), reprise ici pour ne jamais recopier une
## coordonnée de bâtiment à la main.
static func _scatter_ruelles(parent: Node3D, data: Dictionary, solids: Array) -> void:
	_scatter_one_ruelle(parent, data, solids, "EchoppesW", "SaloonW", _SEED_RUELLE_WEST)
	_scatter_one_ruelle(parent, data, solids, "EchoppesE", "SaloonE", _SEED_RUELLE_EAST)


static func _scatter_one_ruelle(parent: Node3D, data: Dictionary, solids: Array, echoppes_name: String, saloon_name: String, seed_value: int) -> void:
	var echoppes := _piece(data, echoppes_name)
	var saloon := _piece(data, saloon_name)
	if echoppes.is_empty() or saloon.is_empty():
		return
	var echoppes_pos: Vector3 = echoppes["pos"]
	var echoppes_size: Vector3 = echoppes["size"]
	var saloon_pos: Vector3 = saloon["pos"]
	var saloon_size: Vector3 = saloon["size"]
	var echoppes_east: float = echoppes_pos.x + echoppes_size.x * 0.5
	var saloon_west: float = saloon_pos.x - saloon_size.x * 0.5
	var lo: float = minf(echoppes_east, saloon_west)
	var hi: float = maxf(echoppes_east, saloon_west)
	if hi - lo < 0.5:
		return  # bâtiments jointifs ou pièces incohérentes -- rien à semer
	var ruelle_x: float = (lo + hi) * 0.5
	var z0: float = minf(echoppes_pos.z - echoppes_size.z * 0.5, saloon_pos.z - saloon_size.z * 0.5)
	var z1: float = maxf(echoppes_pos.z + echoppes_size.z * 0.5, saloon_pos.z + saloon_size.z * 0.5)
	var area := Rect2(ruelle_x - _RUELLE_WIDTH * 0.5, z0, _RUELLE_WIDTH, z1 - z0)
	DressingKit.scatter(parent, area, ["rock", "plank"], _RUELLE_DEBRIS_DENSITY, seed_value, solids, {}, 0.0)


static func _piece(data: Dictionary, piece_name: String) -> Dictionary:
	for entry in (data.get("pieces", []) as Array):
		var p: Dictionary = entry
		if String(p.get("name", "")) == piece_name:
			return p
	return {}


static func _scatter_canyon(parent: Node3D, solids: Array) -> void:
	var area := Rect2(_RUE_X0 - 5.0, _CANYON_Z0, (_RUE_X1 - _RUE_X0) + 10.0, _CANYON_Z1 - _CANYON_Z0)
	DressingKit.scatter(parent, area, ["rock", "tuft"], _CANYON_ROCK_TUFT_DENSITY, _SEED_CANYON, solids, {}, _CANYON_Y)


## "Hors-jeu | grappes Tripo libres (densité ×3)" -- une rangée de bric-à-
## brac Tripo sur la terrasse nord, au-delà de CliffN, purement décorative
## (jamais foulée par un joueur : au nord des `bounds` jouables). `collision:
## false` (ART-99, additif -- voir `DressingKit.tripo_row`) : §1 R9,
## PUREMENT VISUEL, même hors des bornes.
static func _scatter_hors_jeu(parent: Node3D) -> void:
	var points := [Vector3(_HORS_JEU_X0, 6.0, _HORS_JEU_Z), Vector3(_HORS_JEU_X1, 6.0, _HORS_JEU_Z)]
	DressingKit.tripo_row(parent, points, _HORS_JEU_KIND, _HORS_JEU_SPACING, _SEED_HORS_JEU, 0.0, 20.0, false)


## "Poteaux et câbles (`DressingKit.poles_and_cables`) : ligne encastrée
## dans le parapet de l'arête" -- une ligne continue le long du rebord du
## canyon (z 11,9, juste au sud des arrière-cours), `collision: false`
## (§1 R9 : la couche d'art ne pose jamais de collision, même pour un
## poteau planté sur une pièce déjà collidable).
static func _poles_and_cables_arete(parent: Node3D) -> void:
	var points: Array = []
	for x in _ARETE_POLE_X:
		points.append(Vector3(x, 0.0, _ARETE_POLE_Z))
	DressingKit.poles_and_cables(parent, points, _ARETE_POLE_SAG, _ARETE_POLE_HEIGHT, Color.WHITE, false)
