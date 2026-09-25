## AbilityState.gd
## Machine à états PURE (pas d'accès à l'arbre de scène) pour un jeu de
## capacités : charges/cooldown par capacité non-ultime, points cumulés pour
## l'ultime. Utilisée deux fois par AbilityController : une copie AUTORITAIRE
## côté serveur, une copie PRÉDICTIVE côté propriétaire (corrigée via
## to_dict()/apply_dict()). Testée directement (tests/agents/test_ability_state.gd).
class_name AbilityState
extends RefCounted

## Valeur par défaut de `ult_charge_rate` ci-dessous -- exposée en constante
## pour qu'AbilityController.gd (mode à MANCHES, §3.4/AGT-02) puisse y revenir
## explicitement sans dupliquer ce nombre magique (voir
## AbilityController._sync_ult_charge_rate).
const DEFAULT_ULT_CHARGE_RATE := 0.02

## Points d'ultime gagnés par seconde en continu (phase LIVE, joueur vivant --
## voir `tick`), partagés par la capacité ultime, s'il y en a une. Plafonné à
## 0,1 pt/s par BUG-04 (au-delà, l'ultime se rechargeait seul en ~16 s) ;
## ramené à **0,02 pt/s** par §3.4 (docs/research/10_ammo_kits_input.md,
## AGT-02, qui remplace la valeur de BUG-04) pour qu'un ultime dépende
## surtout des dégâts/kills (GameWorld.ULT_DAMAGE_RATE/ULT_KILL_POINTS) --
## ~1 tous les 3 à 4 kills -- plutôt que du seul temps passé en vie. En mode à
## manches (Litige/SnD, Duel/Duo), ce gain continu est mis à ZÉRO par
## AbilityController._sync_ult_charge_rate et remplacé par un bonus fixe à la
## pose/au désamorçage (GameWorld.charge_ult_for_objective, câblé par
## SnDMode._do_plant/_do_defuse) -- cette bascule par mode vit hors de cet état
## PUR (AbilityController.gd), qui reste agnostique du mode de jeu.
var ult_charge_rate: float = DEFAULT_ULT_CHARGE_RATE

var _abilities: Array = []   # Array[Ability]
var _charges: Array = []     # charges restantes par capacité (int)
var _cooldowns: Array = []   # temps de cooldown restant par capacité (float)
var _ult_points: float = 0.0
## Fenêtre de relance restante par capacité (float, s) -- 0.0 = non armée. Voir
## `arm`/`is_armed`/`disarm` (docs/research/10_ammo_kits_input.md §3.5, ex.
## Faux départ de Vif : réappuyer E dans la fenêtre déclenche un comportement
## différent, géré par la capacité concrète -- ce state ne fait
## qu'exposer/décompter la fenêtre).
var _armed: Array = []

func _init(abilities: Array) -> void:
	_abilities = abilities
	_charges.clear()
	_cooldowns.clear()
	_armed.clear()
	for ab in _abilities:
		var a: Ability = ab
		_charges.append(a.charges)
		_cooldowns.append(0.0)
		_armed.append(0.0)

## Avance l'état de `delta` secondes : régénère les charges à cooldown écoulé
## (en redémarrant le cooldown tant qu'il manque des charges) et accumule les
## points d'ultime (cappés à `ult_cost`). `active` doit être vrai UNIQUEMENT
## pendant la phase LIVE et tant que le joueur est vivant (BUG-04) : à `false`
## (valeur par défaut, l'état sûr), rien n'est ajouté — ni régénération de
## charges/cooldown, ni points d'ultime — l'état reste gelé (mort ou hors
## phase active, ex. phase d'achat).
func tick(delta: float, active: bool = false) -> void:
	if not active:
		return
	for i in _abilities.size():
		if _armed[i] > 0.0:
			_armed[i] = maxf(_armed[i] - delta, 0.0)
		var ab: Ability = _abilities[i]
		if ab.is_ultimate:
			_ult_points = minf(_ult_points + delta * ult_charge_rate, float(ab.ult_cost))
			continue
		if _charges[i] >= ab.charges or _cooldowns[i] <= 0.0:
			continue
		_cooldowns[i] -= delta
		# Boucle pour absorber un delta plus grand que le cooldown restant
		# (peut régénérer plusieurs charges d'un coup sans perdre le surplus).
		while _cooldowns[i] <= 0.0 and _charges[i] < ab.charges:
			var overflow: float = -_cooldowns[i]
			_charges[i] += 1
			if _charges[i] < ab.charges:
				_cooldowns[i] = ab.cooldown - overflow
			else:
				_cooldowns[i] = 0.0
				break

func can_activate(i: int) -> bool:
	if i < 0 or i >= _abilities.size():
		return false
	var ab: Ability = _abilities[i]
	if ab.is_ultimate:
		return _ult_points >= float(ab.ult_cost)
	return _charges[i] > 0

## Consomme une charge (ou remet l'ultime à zéro) si possible. Le cooldown
## d'une capacité non-ultime ne redémarre QUE si les charges étaient pleines
## avant cette consommation (sinon il continue de courir depuis l'activation
## précédente).
func try_activate(i: int) -> bool:
	if not can_activate(i):
		return false
	var ab: Ability = _abilities[i]
	if ab.is_ultimate:
		_ult_points = 0.0
		return true
	var was_full: bool = _charges[i] >= ab.charges
	_charges[i] -= 1
	if was_full:
		_cooldowns[i] = ab.cooldown
	return true

## Ajoute des points à l'ultime (ex. sur un kill), cappés à `ult_cost`. Sans
## effet s'il n'y a pas de capacité ultime dans ce jeu.
func add_ult(points: float) -> void:
	for ab in _abilities:
		var a: Ability = ab
		if a.is_ultimate:
			_ult_points = minf(_ult_points + points, float(a.ult_cost))
			return

## Recharge de début de manche (BUG-04) : remet les charges de chaque capacité
## non-ultime à son maximum et vide son cooldown, sans toucher aux points
## d'ultime (l'ultime accumulé ne doit pas être perdu au reset de manche).
func refill() -> void:
	for i in _abilities.size():
		var ab: Ability = _abilities[i]
		if ab.is_ultimate:
			continue
		_charges[i] = ab.charges
		_cooldowns[i] = 0.0

## Ajoute une charge (bornée au maximum de la capacité) SANS toucher au
## cooldown déjà en cours (docs/research/10_ammo_kits_input.md §3.5, ex.
## passif "Mèche courte" de Vif : élimination/assistance rend une charge de
## Ruée, plafonnée à 2). Si la capacité est déjà pleine après l'octroi, son
## cooldown est aussi remis à zéro (rien à régénérer). Sans effet sur une
## capacité ultime (pas de "charges" au sens classique) ou un index hors bornes.
func grant_charge(i: int) -> void:
	if i < 0 or i >= _abilities.size():
		return
	var ab: Ability = _abilities[i]
	if ab.is_ultimate:
		return
	if _charges[i] < ab.charges:
		_charges[i] += 1
	if _charges[i] >= ab.charges:
		_cooldowns[i] = 0.0

## Arme la capacité `i` pour une fenêtre de relance de `window` secondes (voir
## docstring de `_armed`). Un second appel avant expiration REMPLACE la
## fenêtre restante (pas de cumul).
func arm(i: int, window: float) -> void:
	if i < 0 or i >= _abilities.size():
		return
	_armed[i] = window

func is_armed(i: int) -> bool:
	if i < 0 or i >= _armed.size():
		return false
	return _armed[i] > 0.0

## Désarme immédiatement (ex. la capacité concrète consomme la fenêtre à la
## relance, ou l'annule sur un événement -- braise détruite, etc.).
func disarm(i: int) -> void:
	if i < 0 or i >= _armed.size():
		return
	_armed[i] = 0.0

func charges(i: int) -> int:
	if i < 0 or i >= _charges.size():
		return 0
	return _charges[i]

func cooldown_left(i: int) -> float:
	if i < 0 or i >= _cooldowns.size():
		return 0.0
	return _cooldowns[i]

func ult_points() -> float:
	return _ult_points

## Sérialise l'état runtime (pas les métadonnées des capacités, déjà connues
## des deux côtés). Utilisé pour la correction serveur -> propriétaire.
func to_dict() -> Dictionary:
	return {
		"charges": _charges.duplicate(),
		"cooldowns": _cooldowns.duplicate(),
		"ult_points": _ult_points,
		"armed": _armed.duplicate(),
	}

func apply_dict(d: Dictionary) -> void:
	if d.has("charges"):
		var c: Array = d["charges"]
		for i in mini(c.size(), _charges.size()):
			_charges[i] = int(c[i])
	if d.has("cooldowns"):
		var cd: Array = d["cooldowns"]
		for i in mini(cd.size(), _cooldowns.size()):
			_cooldowns[i] = float(cd[i])
	if d.has("ult_points"):
		_ult_points = float(d["ult_points"])
	if d.has("armed"):
		var ar: Array = d["armed"]
		for i in mini(ar.size(), _armed.size()):
			_armed[i] = float(ar[i])
