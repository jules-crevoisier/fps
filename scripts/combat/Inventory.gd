## Inventory.gd
## Machine à états pure de l'inventaire d'armes (slots, munitions, rechargement).
## Aucune dépendance à l'arbre de scène : c'est la copie AUTORITAIRE côté
## serveur (une par joueur) et la copie PRÉDITE côté propriétaire (Weapon.gd).
## Les stats d'arme viennent de WeaponDatabase.get_by_id.
class_name Inventory
extends RefCounted

const EMPTY := -1

## Règle de munitions (GameMode.ammo_rule, docs/research/10_ammo_kits_input.md
## §2.2) : quelle réserve `set_loadout`/`give`/`add_into_free`/`replace_current`
## doivent charger. "round" (par défaut, comportement HISTORIQUE inchangé) =
## réserve de manche (`WeaponConfig.reserve_ammo`) : Litige/Duel, et tout
## appelant qui ne précise rien. "arena" = réserve élargie de l'arène
## (`WeaponConfig.arena_reserve_ammo`, §2.3) : Mêlée/Borne. "infinite" =
## entraînement.
const RULE_ROUND := "round"
const RULE_ARENA := "arena"
const RULE_INFINITE := "infinite"
## Réserve « infinie » de l'entraînement : un sentinelle volontairement énorme
## plutôt qu'un cas particulier dans `tick()`/`start_reload()` — à cette
## échelle (des dizaines de milliers de rechargements), aucune session
## d'entraînement ne peut l'épuiser, et tout le reste de la machine à états
## (transfert reserve -> mag, `reserve <= 0` refusant un rechargement...) reste
## un chemin de code UNIQUE, déjà testé, pour les trois règles.
const INFINITE_RESERVE := 999999

var slots: Array[int] = []
var mag: Array[int] = []
var reserve: Array[int] = []
var current: int = 0
var reloading: bool = false
var reload_left: float = 0.0
## Délai (s) restant avant de pouvoir tirer/recharger de nouveau, pour une
## arme à cycle d'action (tâche "quatre armes", 2026-09-28 : pompe/levier/
## verrou — `WeaponConfig.cycle_time`). 0.0 pour toute arme SANS ce champ
## (comportement HISTORIQUE inchangé, ex. Ravage/Revolver) : `consume_round`
## ne le pose que si un `cycle_time > 0.0` lui est explicitement passé. Remis
## à zéro par un changement d'arme (`equip`/`set_loadout`/`give`/
## `replace_current`/`remove_current`) — "not interruptible except by weapon
## switch" (contrat, arme à pompe).
var cycle_left: float = 0.0

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
	cycle_left = 0.0

## Réserve à charger pour `c` sous la règle `ammo_rule` (RULE_ROUND/RULE_ARENA/
## RULE_INFINITE ci-dessus). `0` si `c` est nul (slot vide/id inconnu).
static func reserve_for(c: WeaponConfig, ammo_rule: String) -> int:
	if c == null:
		return 0
	match ammo_rule:
		RULE_ARENA:
			return c.arena_reserve_ammo
		RULE_INFINITE:
			return INFINITE_RESERVE
		_:
			return c.reserve_ammo

## Remplit les slots dans l'ordre (ids en trop ignorés), chargeur plein et
## réserve selon `ammo_rule` (RULE_ROUND par défaut, comportement historique
## inchangé), équipe le premier slot non vide (0 si aucun), annule un rechargement.
func set_loadout(ids: Array[int], ammo_rule: String = RULE_ROUND) -> void:
	for i in slots.size():
		if i < ids.size():
			var id: int = ids[i]
			slots[i] = id
			var c := WeaponDatabase.get_by_id(id)
			mag[i] = c.mag_size if c else 0
			reserve[i] = reserve_for(c, ammo_rule)
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
	cycle_left = 0.0

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

## Range dans un slot libre (chargeur plein, réserve selon `ammo_rule`).
## Équipe seulement si le slot COURANT était vide. Renvoie l'index du slot
## rempli, -1 si plein.
func add_into_free(id: int, ammo_rule: String = RULE_ROUND) -> int:
	var slot := free_slot()
	if slot == -1:
		return -1
	var was_current_empty := current_id() == EMPTY
	var c := WeaponDatabase.get_by_id(id)
	slots[slot] = id
	mag[slot] = c.mag_size if c else 0
	reserve[slot] = reserve_for(c, ammo_rule)
	if was_current_empty:
		current = slot
	return slot

## Remplace l'arme EN MAIN. Renvoie l'id déplacé (EMPTY si le slot était vide).
## Chargeur plein et réserve selon `ammo_rule` pour la nouvelle arme, annule un
## rechargement en cours.
func replace_current(id: int, ammo_rule: String = RULE_ROUND) -> int:
	var displaced := current_id()
	var c := WeaponDatabase.get_by_id(id)
	slots[current] = id
	mag[current] = c.mag_size if c else 0
	reserve[current] = reserve_for(c, ammo_rule)
	reloading = false
	reload_left = 0.0
	cycle_left = 0.0
	return displaced

## Donne une arme : slot libre si possible (et l'équipe), sinon remplace
## l'arme en main. Renvoie l'id déplacé (EMPTY si un slot libre a été utilisé).
func give(id: int, ammo_rule: String = RULE_ROUND) -> int:
	var slot := free_slot()
	if slot == -1:
		return replace_current(id, ammo_rule)
	var c := WeaponDatabase.get_by_id(id)
	slots[slot] = id
	mag[slot] = c.mag_size if c else 0
	reserve[slot] = reserve_for(c, ammo_rule)
	current = slot
	reloading = false
	reload_left = 0.0
	cycle_left = 0.0
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
	cycle_left = 0.0
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
	cycle_left = 0.0
	return true

## `cycle_left` (tâche "quatre armes") bloque le tir tant qu'un cycle d'action
## (pompe/levier/verrou) n'est pas terminé — "not interruptible except by
## weapon switch". 0.0 pour toute arme sans `WeaponConfig.cycle_time` (aucun
## effet, comportement inchangé).
func can_fire() -> bool:
	if current < 0 or current >= slots.size():
		return false
	return slots[current] != EMPTY and not reloading and mag[current] > 0 and cycle_left <= 0.0

## Décrémente le chargeur si `can_fire()`. Renvoie faux sinon. `cycle_time`
## (tâche "quatre armes", 2026-09-28 — `WeaponConfig.cycle_time` de l'arme
## tirée) : si > 0.0, arme `cycle_left` à cette valeur (pompe/levier/verrou) —
## `0.0` par défaut (aucun effet, comportement HISTORIQUE inchangé pour toute
## arme qui ne le passe pas, ex. Ravage/Revolver).
func consume_round(cycle_time: float = 0.0) -> bool:
	if not can_fire():
		return false
	mag[current] -= 1
	if cycle_time > 0.0:
		cycle_left = cycle_time
	return true

## Démarre un rechargement. Faux si déjà en cours, en plein cycle d'action
## (tâche "quatre armes" — "not interruptible except by weapon switch"), slot
## vide, chargeur plein ou réserve à zéro. Rechargement PAR CARTOUCHE
## (`WeaponConfig.reload_per_round`, ex. Fracas/Verdict) : démarre avec
## `reload_start_time` (délai avant la 1ère cartouche, voir `_tick_per_round`)
## plutôt que `reload_time` (bloc entier, comportement HISTORIQUE inchangé,
## ex. Ravage/Revolver/tout sniper qui recharge le chargeur d'un coup).
func start_reload() -> bool:
	if reloading or cycle_left > 0.0:
		return false
	var c := WeaponDatabase.get_by_id(current_id())
	if c == null:
		return false
	if mag[current] >= c.mag_size:
		return false
	if reserve[current] <= 0:
		return false
	reloading = true
	reload_left = c.reload_start_time if c.reload_per_round else c.reload_time
	return true

## Interrompt un rechargement PAR CARTOUCHE en cours au profit d'un tir
## (tâche "quatre armes" : "fire interrupts the reload if >= 1 round loaded" —
## Fracas/Verdict) : n'a d'effet QUE si `c.reload_per_round` est vrai ET qu'au
## moins une cartouche est déjà dans le chargeur (`mag[current] >= 1`) — un
## rechargement en BLOC (`reload_per_round` faux, ex. Ravage/Revolver/tout
## sniper) n'est jamais interruptible par le tir, comportement HISTORIQUE
## inchangé. Renvoie vrai si le rechargement a réellement été interrompu (pour
## que l'appelant sache qu'il peut maintenant tirer).
func interrupt_reload_for_fire(c: WeaponConfig) -> bool:
	if not reloading or c == null or not c.reload_per_round:
		return false
	if mag[current] < 1:
		return false
	reloading = false
	reload_left = 0.0
	return true

## Avance l'inventaire de `delta` secondes : `cycle_left` (pompe/levier/verrou)
## d'abord, TOUJOURS (même hors rechargement — un cycle peut courir seul entre
## deux tirs), puis le rechargement en cours s'il y en a un. Renvoie vrai
## UNIQUEMENT sur un tick qui vient d'ajouter au moins une munition au
## chargeur (fin d'un rechargement en BLOC, OU insertion d'UNE cartouche pour
## un rechargement PAR CARTOUCHE — voir `_tick_per_round`).
func tick(delta: float) -> bool:
	cycle_left = maxf(cycle_left - delta, 0.0)
	if not reloading:
		return false
	var c := WeaponDatabase.get_by_id(current_id())
	if c != null and c.reload_per_round:
		return _tick_per_round(delta, c)
	reload_left -= delta
	if reload_left > 0.0:
		return false
	reloading = false
	reload_left = 0.0
	var mag_size: int = c.mag_size if c else mag[current]
	var needed: int = mag_size - mag[current]
	var taken: int = mini(needed, reserve[current])
	mag[current] += taken
	reserve[current] -= taken
	return true

## Rechargement PAR CARTOUCHE (Fracas/Verdict, tâche "quatre armes") : une
## boucle (et non un simple `if`, défensif contre un gros `delta` — lag
## spike/test qui avance plusieurs secondes d'un coup, même discipline que
## FireClock) insère une cartouche à chaque fois que `reload_left` franchit
## zéro, puis relance le minuteur sur `reload_round_time` (jamais
## `reload_start_time`, réservé à la TOUTE première cartouche) — jusqu'à ce
## que le chargeur soit plein OU la réserve épuisée, auquel cas le
## rechargement se termine de lui-même (comme un rechargement en bloc).
## Renvoie vrai si AU MOINS une cartouche a été insérée ce tick (jamais vrai
## sur un simple décompte sans insertion).
func _tick_per_round(delta: float, c: WeaponConfig) -> bool:
	reload_left -= delta
	var changed := false
	while reloading and reload_left <= 0.0:
		if mag[current] < c.mag_size and reserve[current] > 0:
			mag[current] += 1
			reserve[current] -= 1
			changed = true
		if mag[current] >= c.mag_size or reserve[current] <= 0:
			reloading = false
			reload_left = 0.0
		else:
			reload_left += c.reload_round_time
	return changed

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
		"cycle_left": cycle_left,
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
	inv.cycle_left = float(d.get("cycle_left", 0.0))
	return inv
