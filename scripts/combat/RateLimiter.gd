## RateLimiter.gd
## Seau à jetons (token bucket) générique. Utilisé côté serveur pour brider la
## cadence de tir déclarée par le client (anti-triche) : un jeton par tir,
## capacité = burst, remplissage = rate jetons/seconde.
class_name RateLimiter
extends RefCounted

var _rate: float
var _burst: float
var _tokens: float
var _last: float = 0.0

## Le seau démarre plein.
func _init(rate_per_sec: float, burst: float) -> void:
	_rate = rate_per_sec
	_burst = burst
	_tokens = burst

## Tente de prélever `cost` jetons à l'instant `now_sec`. Remplit d'abord le
## seau selon le temps écoulé depuis le dernier appel (aucun remplissage si
## le temps recule), plafonné à `burst`, puis prélève si assez de jetons.
func try_take(now_sec: float, cost: float = 1.0) -> bool:
	if now_sec >= _last:
		_tokens = minf(_burst, _tokens + (now_sec - _last) * _rate)
		_last = now_sec
	if _tokens >= cost:
		_tokens -= cost
		return true
	return false
