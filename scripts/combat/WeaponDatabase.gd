## WeaponDatabase.gd
## Catalogue des armes du jeu (classe statique). Depuis la tâche "revolver"
## (2026-09-27) : DEUX entrées — le Ravage (slot 1, id 0) et le Revolver
## (slot 2, id 1), tout joueur/bot spawn avec les deux (voir
## `default_loadout_ids`). Aucune vente/achat/ramassage d'une TROISIÈME arme
## n'est possible puisqu'aucune autre n'existe dans ce catalogue.
class_name WeaponDatabase
extends RefCounted

## Append-only : l'ID d'une arme est son index ici (voir `get_by_id`/`id_of`).
## Ne JAMAIS réordonner une entrée existante (casserait tout état déjà
## répliqué/sauvegardé qui référence un id).
## Tâche "quatre armes" (2026-09-28) : QUATRE nouvelles entrées, ids 2-5 —
## Rafale (SMG), Fracas (fusil à pompe), Verdict (carbine à levier), Aiguille
## (sniper à verrou). Pas encore dans un loadout par défaut/une boutique — ce
## catalogue les rend seulement RÉSOLUBLES par id (WeaponDatabase.get_by_id),
## voir le rendu de tâche pour ce qui reste à câbler côté sélection/boutique.
const PATHS := [
	"res://resources/weapons/ravage.tres",
	"res://resources/weapons/revolver.tres",
	"res://resources/weapons/rafale.tres",
	"res://resources/weapons/fracas.tres",
	"res://resources/weapons/verdict.tres",
	"res://resources/weapons/aiguille.tres",
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

## IDs du loadout de départ — le Ravage (slot 1) ET le Revolver (slot 2),
## tâche "revolver" 2026-09-27 : chaque joueur/bot spawn avec les deux (voir
## Inventory.set_loadout, qui remplit les slots dans l'ordre de ce tableau).
## Une entrée manquante (.tres introuvable/invalide) est simplement omise —
## jamais de plantage, le slot correspondant reste vide côté Inventory.
static func default_loadout_ids() -> Array[int]:
	var ids: Array[int] = []
	for name in ["Ravage", "Revolver"]:
		var w := get_by_name(name)
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
		WeaponConfig.Category.PISTOL: return "Pistolet"
	return "?"
