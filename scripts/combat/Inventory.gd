## Inventory.gd
## Machine à états pure de l'inventaire d'armes (slots, munitions, rechargement).
## Aucune dépendance à l'arbre de scène : c'est la copie AUTORITAIRE côté
## serveur (une par joueur) et la copie PRÉDITE côté propriétaire (Weapon.gd).
## Les stats d'arme viennent de WeaponDatabase.get_by_id.
class_name Inventory
extends RefCounted

const EMPTY := -1

var slots: Array[int] = []
var mag: Array[int] = []
var reserve: Array[int] = []
var current: int = 0
var reloading: bool = false
var reload_left: float = 0.0

func _init(slot_count: int = 2) -> void:
	slots = []
	mag = []
	reserve = []
	for i in slot_count:
		slots.append(EMPTY)
		mag.append(0)
		reserve.append(0)
	current = 0
	reloading = false
	reload_left = 0.0

## Remplit les slots dans l'ordre (ids en trop ignorés), chargeur/réserve
## pleins, équipe le premier slot non vide (0 si aucun), annule un rechargement.
func set_loadout(ids: Array[int]) -> void:
	for i in slots.size():
		if i < ids.size():
			var id: int = ids[i]
			slots[i] = id
			var c := WeaponDatabase.get_by_id(id)
			mag[i] = c.mag_size if c else 0
			reserve[i] = c.reserve_ammo if c else 0
		else:
			slots[i] = EMPTY
			mag[i] = 0
			reserve[i] = 0
	current = 0
	for i in slots.size():
		if slots[i] != EMPTY:
			current = i
			break
	reloading = false
	reload_left = 0.0

func current_id() -> int:
	if current < 0 or current >= slots.size():
		return EMPTY
	return slots[current]

func has_weapon(id: int) -> bool:
	return slots.has(id)

## Premier slot vide, -1 si l'inventaire est plein.
func free_slot() -> int:
	for i in slots.size():
		if slots[i] == EMPTY:
			return i
	return -1

## Range dans un slot libre (chargeur/réserve pleins). Équipe seulement si le
## slot COURANT était vide. Renvoie l'index du slot rempli, -1 si plein.
func add_into_free(id: int) -> int:
	var slot := free_slot()
	if slot == -1:
		return -1
	var was_current_empty := current_id() == EMPTY
	var c := WeaponDatabase.get_by_id(id)
	slots[slot] = id
	mag[slot] = c.mag_size if c else 0
	reserve[slot] = c.reserve_ammo if c else 0
	if was_current_empty:
		current = slot
	return slot

## Remplace l'arme EN MAIN. Renvoie l'id déplacé (EMPTY si le slot était vide).
## Chargeur/réserve pleins pour la nouvelle arme, annule un rechargement en cours.
func replace_current(id: int) -> int:
	var displaced := current_id()
	var c := WeaponDatabase.get_by_id(id)
	slots[current] = id
	mag[current] = c.mag_size if c else 0
	reserve[current] = c.reserve_ammo if c else 0
	reloading = false
	reload_left = 0.0
	return displaced

## Donne une arme : slot libre si possible (et l'équipe), sinon remplace
## l'arme en main. Renvoie l'id déplacé (EMPTY si un slot libre a été utilisé).
func give(id: int) -> int:
	var slot := free_slot()
	if slot == -1:
		return replace_current(id)
	var c := WeaponDatabase.get_by_id(id)
	slots[slot] = id
	mag[slot] = c.mag_size if c else 0
	reserve[slot] = c.reserve_ammo if c else 0
	current = slot
	reloading = false
	reload_left = 0.0
	return EMPTY

## Retire l'arme en main (munitions à zéro). L'index `current` lui-même ne
## change pas ; il se retrouve naturellement sur le premier slot non vide
## restant puisqu'on le fait pointer dessus explicitement s'il en existe un.
func remove_current() -> int:
	var removed := current_id()
	slots[current] = EMPTY
	mag[current] = 0
	reserve[current] = 0
	reloading = false
	reload_left = 0.0
	for i in slots.size():
		if slots[i] != EMPTY:
			current = i
			break
	return removed

## Change l'arme courante. Faux si index hors limites, slot déjà courant,
## slot vide, ou pendant un rechargement.
func equip(slot: int) -> bool:
	if slot < 0 or slot >= slots.size():
		return false
	if slot == current:
		return false
	if slots[slot] == EMPTY:
		return false
	if reloading:
		return false
	current = slot
	return true

func can_fire() -> bool:
	if current < 0 or current >= slots.size():
		return false
	return slots[current] != EMPTY and not reloading and mag[current] > 0

## Décrémente le chargeur si `can_fire()`. Renvoie faux sinon.
func consume_round() -> bool:
	if not can_fire():
		return false
	mag[current] -= 1
	return true

## Démarre un rechargement. Faux si déjà en cours, slot vide, chargeur plein
## ou réserve à zéro.
func start_reload() -> bool:
	if reloading:
		return false
	var c := WeaponDatabase.get_by_id(current_id())
	if c == null:
		return false
	if mag[current] >= c.mag_size:
		return false
	if reserve[current] <= 0:
		return false
	reloading = true
	reload_left = c.reload_time
	return true

## Avance le rechargement en cours de `delta` secondes. Renvoie vrai UNIQUEMENT
## sur le tick où il se termine (transfert reserve -> mag, plafonné aux deux).
func tick(delta: float) -> bool:
	if not reloading:
		return false
	reload_left -= delta
	if reload_left > 0.0:
		return false
	reloading = false
	reload_left = 0.0
	var c := WeaponDatabase.get_by_id(current_id())
	var mag_size: int = c.mag_size if c else mag[current]
	var needed: int = mag_size - mag[current]
	var taken: int = mini(needed, reserve[current])
	mag[current] += taken
	reserve[current] -= taken
	return true

## Termine tout de suite un rechargement dont il reste au plus `tolerance`
## secondes. Sert au serveur : le tir qui suit un rechargement peut arriver
## une fraction de tick avant la fin serveur (gigue réseau). Faux si aucun
## rechargement n'est en cours ou s'il reste plus que `tolerance`.
func finish_reload_if_within(tolerance: float) -> bool:
	if not reloading or reload_left > tolerance:
		return false
	return tick(reload_left)

func to_dict() -> Dictionary:
	return {
		"slots": slots.duplicate(),
		"mag": mag.duplicate(),
		"reserve": reserve.duplicate(),
		"current": current,
		"reloading": reloading,
		"reload_left": reload_left,
	}

## Reconstruit un Inventory depuis to_dict() — round-trip sans perte, utilisé
## par la synchronisation serveur -> propriétaire.
static func from_dict(d: Dictionary) -> Inventory:
	var inv := Inventory.new(0)
	var s: Array[int] = []
	for v in (d.get("slots", []) as Array):
		s.append(int(v))
	var m: Array[int] = []
	for v in (d.get("mag", []) as Array):
		m.append(int(v))
	var r: Array[int] = []
	for v in (d.get("reserve", []) as Array):
		r.append(int(v))
	inv.slots = s
	inv.mag = m
	inv.reserve = r
	inv.current = int(d.get("current", 0))
	inv.reloading = bool(d.get("reloading", false))
	inv.reload_left = float(d.get("reload_left", 0.0))
	return inv
