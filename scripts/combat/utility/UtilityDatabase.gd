## UtilityDatabase.gd
## Catalogue des objets lancés (frag/flash/smoke) — même patron que
## WeaponDatabase.gd : un id = un index dans PATHS (ordre append-only).
class_name UtilityDatabase
extends RefCounted

const FRAG := 0
const FLASH := 1
const SMOKE := 2

const PATHS := [
	"res://resources/utility/frag.tres",
	"res://resources/utility/flash.tres",
	"res://resources/utility/smoke.tres",
]

static var _cache: Array = []

static func all() -> Array:
	if _cache.is_empty():
		for p in PATHS:
			var c = load(p)
			if c:
				_cache.append(c)
	return _cache

## `null` hors limites — jamais une exception (mêmes garanties que
## WeaponDatabase.get_by_id, consommé par du code réseau qui reçoit des ids
## non fiables d'un client).
static func get_by_id(id: int) -> UtilityConfig:
	var db := all()
	if id < 0 or id >= db.size():
		return null
	return db[id]

static func id_of(c: UtilityConfig) -> int:
	if c == null:
		return -1
	return all().find(c)

## Les 3 ids valides, dans l'ordre canonique FRAG/FLASH/SMOKE — utilisé par
## UtilityInventory pour construire le tableau de charges par défaut.
static func all_ids() -> Array[int]:
	return [FRAG, FLASH, SMOKE]
