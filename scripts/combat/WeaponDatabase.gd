## WeaponDatabase.gd
## Catalogue des armes du jeu (classe statique). Prototype à une seule arme
## (décision 2026-09-26) : le Ravage est la SEULE entrée — tout joueur/bot
## spawn avec elle, aucune vente/achat/ramassage d'une autre arme n'est
## possible puisqu'aucune autre n'existe plus dans ce catalogue.
class_name WeaponDatabase
extends RefCounted

const PATHS := [
	"res://resources/weapons/ravage.tres",
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

## IDs du loadout de départ — le Ravage seul (prototype à une arme).
static func default_loadout_ids() -> Array[int]:
	var ids: Array[int] = []
	var w := get_by_name("Ravage")
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
