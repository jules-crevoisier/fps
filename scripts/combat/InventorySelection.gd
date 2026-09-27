## InventorySelection.gd
## Machine PURE de sélection façon CS (contrat lead 2026-09-27, "Convert the
## grenade utilities... to a Counter-Strike-style inventory") : un seul index
## unifié 0..4 représente l'objet actuellement équipé —
##   0/1 = emplacement d'arme (Inventory slot 0/1, voir scripts/combat/
##         Inventory.gd) ; 2/3/4 = type de grenade (UtilityDatabase.FRAG/
##         FLASH/SMOKE + 2, voir scripts/combat/utility/UtilityDatabase.gd) —
##   même ordre que les rangées HUD 1..5 (InventoryHUD.gd).
## Aucune dépendance à l'arbre de scène : consommée par
## scripts/combat/utility/UtilityThrower.gd (qui pilote réellement la
## sélection, prédiction propriétaire + autorité serveur, même patron que
## Weapon.gd) des deux côtés (client ET serveur), avec leurs tableaux
## `weapon_filled`/`grenade_charges` RESPECTIFS (prédits ou autoritaires).
class_name InventorySelection
extends RefCounted

const WEAPON_SLOTS := 2
const GRENADE_KINDS := 3
const SLOT_COUNT := WEAPON_SLOTS + GRENADE_KINDS  # 5

static func is_weapon_slot(index: int) -> bool:
	return index >= 0 and index < WEAPON_SLOTS

static func is_grenade_slot(index: int) -> bool:
	return index >= WEAPON_SLOTS and index < SLOT_COUNT

## Emplacement Inventory (0/1) correspondant à `index` — appelant responsable
## de vérifier `is_weapon_slot(index)` au préalable (aucune borne défensive
## ici, voir la même convention que UtilityDatabase.get_by_id vs Inventory.equip).
static func weapon_slot_of(index: int) -> int:
	return index

## Type UtilityDatabase (FRAG/FLASH/SMOKE) correspondant à `index` — appelant
## responsable de vérifier `is_grenade_slot(index)` au préalable.
static func grenade_kind_of(index: int) -> int:
	return index - WEAPON_SLOTS

static func slot_of_grenade(kind: int) -> int:
	return kind + WEAPON_SLOTS

## `index` est-il sélectionnable MAINTENANT (contrat, points 2/3) : une arme
## doit occuper un slot NON VIDE, une grenade doit avoir AU MOINS 1 charge —
## `weapon_filled.size() == WEAPON_SLOTS`, `grenade_charges.size() == GRENADE_KINDS`.
static func is_selectable(index: int, weapon_filled: Array, grenade_charges: Array) -> bool:
	if is_weapon_slot(index):
		return index < weapon_filled.size() and bool(weapon_filled[index])
	if is_grenade_slot(index):
		var k := grenade_kind_of(index)
		return k < grenade_charges.size() and int(grenade_charges[k]) > 0
	return false

## Une sélection DIRECTE (touche 1..5) de `requested` est-elle autorisée
## depuis `current` ? Faux si hors bornes, si `requested == current` (contrat
## point 3 : "Selecting the slot already equipped does nothing"), ou si
## `requested` n'est pas sélectionnable (arme vide / grenade à 0 charge,
## contrat point 3 : "Selecting a grenade slot with 0 charges does nothing").
static func can_select(requested: int, current: int, weapon_filled: Array, grenade_charges: Array) -> bool:
	if requested < 0 or requested >= SLOT_COUNT:
		return false
	if requested == current:
		return false
	return is_selectable(requested, weapon_filled, grenade_charges)

## Prochain index sélectionnable dans le sens `dir` (+1 ou -1), en bouclant
## (contrat point 2 : "cycles through SELECTABLE slots in order 1->5 and
## wraps", "Skip empty weapon slots and grenades with 0 charges"). Renvoie
## `current` inchangé si AUCUN autre emplacement n'est sélectionnable (évite
## toute boucle infinie sur un inventaire dégénéré, ex. tous les tests
## unitaires qui ne posent qu'une seule arme).
static func next_selectable(current: int, dir: int, weapon_filled: Array, grenade_charges: Array) -> int:
	if dir == 0:
		return current
	var step: int = 1 if dir > 0 else -1
	var i := current
	for _n in SLOT_COUNT:
		i = posmod(i + step, SLOT_COUNT)
		if i == current:
			break
		if is_selectable(i, weapon_filled, grenade_charges):
			return i
	return current
