## Loadout.gd
## Sélection de l'arme PRIMAIRE (contrat lead 2026-09-28, "LOADOUT SELECTION")
## — machine PURE (aucun accès à l'arbre de scène), consommée par
## GameWorld.gd (réseau/spawn), ArmoryScreen.gd (salon) et DeathScreen.gd
## (choix pour le PROCHAIN respawn). Le Revolver reste la seconde arme FIXE
## de tout loadout (tâche "revolver", 2026-09-27, WeaponDatabase.PATHS[1]) —
## jamais sélectionnable, jamais remplacé.
##
## Ordre/liste des primaires VERROUILLÉ par le contrat (révision 2026-09-28,
## "drop all frog/swamp flavour", aucun nom de fabricant) : Ravage (existant),
## Rafale (mitraillette/SMG), Fracas (fusil à pompe), Verdict (carabine à
## levier), Aiguille (fusil de précision à verrou) — dans CET ORDRE, qui suit
## les ids append-only 2..5 de WeaponDatabase.PATHS une fois qu'A les aura
## ajoutés. Un nom SANS ressource `.tres` livrée (WeaponDatabase.get_by_name
## renvoie null) est simplement OMIS de `available_primary_ids()` — jamais un
## crash : ce fichier doit rester correct AVANT ET APRÈS l'arrivée des 4
## nouvelles armes (contrat : "your code must resolve primaries by weapon_name
## ... and silently skip missing ones").
class_name Loadout
extends RefCounted

## Ordre de résolution/affichage des primaires (armurerie, écran de mort,
## tirage aléatoire des bots) — VERROUILLÉ, ne jamais réordonner (romprait
## l'ordre des cartes déjà vu par le joueur).
const PRIMARY_NAMES: Array[String] = ["Ravage", "Rafale", "Fracas", "Verdict", "Aiguille"]

## Seconde arme FIXE de tout loadout (jamais sélectionnable) — voir doc de tête.
const SECONDARY_NAME := "Revolver"

## Primaire de repli — spawn AVANT que la moindre .tres des 4 nouvelles armes
## n'existe, choix invalide reçu du réseau, fichier de settings corrompu...
const DEFAULT_PRIMARY_NAME := "Ravage"

## Libellé de rôle affiché (armurerie, une ligne sous le nom de l'arme) par
## nom d'arme primaire — FR, contrat lead 2026-09-28. "" pour un nom hors de
## `PRIMARY_NAMES` (jamais un texte inventé pour une arme inconnue).
const _ROLE_BY_NAME := {
	"Ravage": "Fusil d'assaut",
	"Rafale": "Mitraillette",
	"Fracas": "Fusil à pompe",
	"Verdict": "Carabine à levier",
	"Aiguille": "Fusil de précision",
}


## IDs (WeaponDatabase, résolus via get_by_name/id_of) des primaires
## ACTUELLEMENT chargées, dans l'ordre de `PRIMARY_NAMES` — un nom dont la
## ressource n'existe pas encore (A n'a pas fini) est simplement absent,
## jamais un id invalide/-1 glissé dans ce tableau.
static func available_primary_ids() -> Array[int]:
	var ids: Array[int] = []
	for n in PRIMARY_NAMES:
		var w := WeaponDatabase.get_by_name(n)
		if w:
			ids.append(WeaponDatabase.id_of(w))
	return ids


## ID (WeaponDatabase) du Revolver — `Inventory.EMPTY` si, un jour, cette
## ressource venait à manquer (jamais un crash, même garde que
## `WeaponDatabase.default_loadout_ids`).
static func secondary_id() -> int:
	var w := WeaponDatabase.get_by_name(SECONDARY_NAME)
	return WeaponDatabase.id_of(w) if w else Inventory.EMPTY


## ID de repli (Ravage) — `Inventory.EMPTY` dans le seul cas dégénéré où même
## le Ravage serait absent du catalogue (jamais atteint en jeu réel).
static func default_primary_id() -> int:
	var w := WeaponDatabase.get_by_name(DEFAULT_PRIMARY_NAME)
	return WeaponDatabase.id_of(w) if w else Inventory.EMPTY


## `id` est-il une primaire CONNUE et actuellement chargée ? Utilisé pour
## valider toute entrée non fiable (choix réseau d'un client, contrat réseau :
## "must be a known primary id" — voir GameWorld._server_choose_primary).
static func is_valid_primary_id(id: int) -> bool:
	return available_primary_ids().has(id)


## Loadout complet [primaire, secondaire] pour `primary_id` (contrat point 1)
## — un id INVALIDE (inconnu, pas encore livré, ou -1 sentinelle "aucun choix
## connu") retombe sur le Ravage plutôt que de propager une entrée invalide à
## Inventory.set_loadout.
static func loadout_for(primary_id: int) -> Array[int]:
	var pid := primary_id if is_valid_primary_id(primary_id) else default_primary_id()
	return [pid, secondary_id()]


## Primaire aléatoire (bots, "re-rolled on respawn") parmi les primaires
## ACTUELLEMENT chargées — `default_primary_id()` si aucune n'est encore
## livrée (garde dégénérée, jamais le cas une fois le Ravage présent).
static func random_primary(rng: RandomNumberGenerator) -> int:
	var ids := available_primary_ids()
	if ids.is_empty():
		return default_primary_id()
	return ids[rng.randi() % ids.size()]


## ID (WeaponDatabase) de la primaire nommée `name` — repli sur le Ravage si
## `name` est inconnu ou pas encore chargé (ex. Settings.selected_primary lu
## d'un fichier écrit par une build future, ou une arme retirée du roster).
static func primary_id_for_name(name: String) -> int:
	var w := WeaponDatabase.get_by_name(name)
	if w == null:
		return default_primary_id()
	var id := WeaponDatabase.id_of(w)
	return id if is_valid_primary_id(id) else default_primary_id()


## Nom (WeaponConfig.weapon_name) de la primaire `id` — "Ravage" si `id` ne
## résout à rien (même repli que le reste de ce fichier).
static func name_for_primary_id(id: int) -> String:
	var c := WeaponDatabase.get_by_id(id)
	return c.weapon_name if c else DEFAULT_PRIMARY_NAME


## Libellé de rôle FR (armurerie) pour `name` — "" si `name` est hors de
## `PRIMARY_NAMES` (jamais un texte inventé).
static func role_for(name: String) -> String:
	return String(_ROLE_BY_NAME.get(name, ""))
