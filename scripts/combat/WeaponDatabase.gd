## WeaponDatabase.gd
## Catalogue de toutes les armes du jeu (classe statique). Sert au catalogue du
## menu, à la boutique (plus tard) et au loadout par défaut.
class_name WeaponDatabase
extends RefCounted

const PATHS := [
	"res://resources/weapons/pistolet.tres",
	"res://resources/weapons/magnum.tres",
	"res://resources/weapons/rafale.tres",
	"res://resources/weapons/marqueur.tres",
	"res://resources/weapons/ravage.tres",
	"res://resources/weapons/fracas.tres",
	"res://resources/weapons/faucheur.tres",
	"res://resources/weapons/eclair.tres",
	"res://resources/weapons/semeuse.tres",
	"res://resources/weapons/percuteur.tres",
]

static var _cache: Array = []

static func all() -> Array:
	if _cache.is_empty():
		for p in PATHS:
			var c = load(p)
			if c:
				_cache.append(c)
	return _cache

static func get_by_name(n: String) -> WeaponConfig:
	for w in all():
		if w.weapon_name == n:
			return w
	return null

## ID = index dans PATHS (ordre append-only). Renvoie null hors limites.
static func get_by_id(id: int) -> WeaponConfig:
	var db := all()
	if id < 0 or id >= db.size():
		return null
	return db[id]

## Retrouve l'ID (index) d'une config déjà chargée. -1 si inconnue.
static func id_of(c: WeaponConfig) -> int:
	if c == null:
		return -1
	return all().find(c)

## IDs du loadout de départ (sidearm + fusil), pour l'inventaire serveur.
static func default_loadout_ids() -> Array[int]:
	var ids: Array[int] = []
	for n in ["Ravage", "Pistolet"]:
		var w := get_by_name(n)
		if w:
			ids.append(id_of(w))
	return ids

static func type_name(t: int) -> String:
	match t:
		WeaponConfig.Type.HITSCAN: return "Hitscan"
		WeaponConfig.Type.SHOTGUN: return "Shotgun"
		WeaponConfig.Type.SNIPER: return "Sniper"
	return "?"

static func category_name(c: int) -> String:
	match c:
		WeaponConfig.Category.SIDEARM: return "Arme de poing"
		WeaponConfig.Category.SMG: return "SMG"
		WeaponConfig.Category.RIFLE: return "Fusil"
		WeaponConfig.Category.SHOTGUN: return "Fusil à pompe"
		WeaponConfig.Category.SNIPER: return "Sniper"
		WeaponConfig.Category.HEAVY: return "Lourde"
		WeaponConfig.Category.MELEE: return "Mêlée"
	return "?"
