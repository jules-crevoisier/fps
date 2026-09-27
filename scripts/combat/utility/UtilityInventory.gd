## UtilityInventory.gd
## Machine à états PURE des charges d'objets lancés (1 de chaque par vie,
## rechargées à chaque spawn, perdues à la mort — contrat lead). Aucune
## dépendance à l'arbre de scène : c'est la copie AUTORITAIRE côté serveur
## (une par joueur, sur UtilityThrower.gd) et la copie PRÉDITE côté
## propriétaire — même patron que Inventory.gd/Weapon.gd.
class_name UtilityInventory
extends RefCounted

## Charges par id UtilityDatabase (FRAG/FLASH/SMOKE) — un seul exemplaire de
## chaque au départ, jamais de stock supplémentaire (contrat lead : "1 of
## each per life").
const CHARGES_PER_KIND := 1

var charges: Array[int] = []

func _init() -> void:
	refill()

## Remplit les 3 charges au maximum (1 chacune) — appelé à CHAQUE spawn
## (contrat lead : "refilled on every spawn").
func refill() -> void:
	charges = []
	for _id in UtilityDatabase.all_ids():
		charges.append(CHARGES_PER_KIND)

## Vide toutes les charges (mort — contrat lead : "lost on death"). Distinct
## de `refill()` pour rester explicite à l'appel (voir UtilityThrower.
## _server_on_death, seul appelant prévu côté serveur).
func clear() -> void:
	charges = []
	for _id in UtilityDatabase.all_ids():
		charges.append(0)

func has_charge(kind: int) -> bool:
	return kind >= 0 and kind < charges.size() and charges[kind] > 0

## Consomme UNE charge de `kind`. Renvoie faux (sans effet) si `kind` est hors
## limites ou déjà à sec — jamais de valeur négative.
func consume(kind: int) -> bool:
	if not has_charge(kind):
		return false
	charges[kind] -= 1
	return true

## Copie défensive (l'appelant HUD ne doit jamais pouvoir modifier l'état
## réel en modifiant le tableau renvoyé — même précaution que
## GameWorld.agent_picks_roster).
func snapshot() -> Array[int]:
	var out: Array[int] = []
	for c in charges:
		out.append(c)
	return out

## Sérialisation minimale pour la synchro serveur -> propriétaire (voir
## Weapon._push_server_sync/Inventory.to_dict/from_dict, même convention).
func to_dict() -> Dictionary:
	return {"charges": snapshot()}

static func from_dict(d: Dictionary) -> UtilityInventory:
	var inv := UtilityInventory.new()
	var arr = d.get("charges", [])
	if arr is Array:
		for i in inv.charges.size():
			inv.charges[i] = int(arr[i]) if i < arr.size() else 0
	return inv
