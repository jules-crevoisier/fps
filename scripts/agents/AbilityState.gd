## AbilityState.gd
## Machine à états PURE (pas d'accès à l'arbre de scène) pour un jeu de
## capacités : charges/cooldown par capacité non-ultime, points cumulés pour
## l'ultime. Utilisée deux fois par AbilityController : une copie AUTORITAIRE
## côté serveur, une copie PRÉDICTIVE côté propriétaire (corrigée via
## to_dict()/apply_dict()). Testée directement (tests/agents/test_ability_state.gd).
class_name AbilityState
extends RefCounted

## Points d'ultime gagnés par seconde (partagés par la capacité ultime, s'il y en a une).
var ult_charge_rate: float = 0.45

var _abilities: Array = []   # Array[Ability]
var _charges: Array = []     # charges restantes par capacité (int)
var _cooldowns: Array = []   # temps de cooldown restant par capacité (float)
var _ult_points: float = 0.0

func _init(abilities: Array) -> void:
	_abilities = abilities
	_charges.clear()
	_cooldowns.clear()
	for ab in _abilities:
		var a: Ability = ab
		_charges.append(a.charges)
		_cooldowns.append(0.0)

## Avance l'état de `delta` secondes : régénère les charges à cooldown écoulé
## (en redémarrant le cooldown tant qu'il manque des charges) et accumule les
## points d'ultime (cappés à `ult_cost`).
func tick(delta: float) -> void:
	for i in _abilities.size():
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
