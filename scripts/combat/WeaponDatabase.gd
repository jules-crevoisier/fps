## WeaponDatabase.gd
## Catalogue de toutes les armes du jeu (classe statique). Sert au catalogue du
## menu, à la boutique (plus tard) et au loadout par défaut.
class_name WeaponDatabase
extends RefCounted

const PATHS := [
	"res://resources/weapons/classic.tres",
	"res://resources/weapons/sheriff.tres",
	"res://resources/weapons/spectre.tres",
	"res://resources/weapons/guardian.tres",
	"res://resources/weapons/vandal.tres",
	"res://resources/weapons/judge.tres",
	"res://resources/weapons/operator.tres",
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

## Loadout de départ (sidearm + fusil) — utilisé tant qu'il n'y a pas de boutique.
static func default_loadout() -> Array:
	var l: Array = []
	for n in ["Ravage", "Pistolet"]:
		var w := get_by_name(n)
		if w:
			l.append(w)
	if l.is_empty():
		l = all().duplicate()
	return l

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
