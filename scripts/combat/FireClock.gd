## FireClock.gd
## Horloge de tir à reste fractionnaire, pensée pour être tickée à 60 Hz fixe
## (_physics_process). Tant que la gâchette est tenue, le crédit de temps
## s'accumule et chaque franchissement de l'intervalle (1/rate) déclenche un
## tir en conservant le reste — la cadence MOYENNE colle à `rate` (±1 tir/s).
## Le premier tir après une période d'inactivité part immédiatement ; pendant
## l'inactivité, l'horloge redescend vers "prête" sans jamais banquer de tirs
## au-delà (pas de rafale différée qui exploserait à la reprise du tir).
class_name FireClock
extends RefCounted

var _rate: float
var _interval: float
var _t: float

func _init(rate_per_sec: float) -> void:
	set_rate(rate_per_sec)
	reset()

## Change la cadence pour les tirs suivants (ne réinitialise pas le crédit
## en cours, pour ne pas offrir un tir "gratuit" au changement de cadence).
func set_rate(rate: float) -> void:
	_rate = maxf(rate, 0.001)
	_interval = 1.0 / _rate

## Repasse l'horloge à "prête" : le prochain tir sera immédiat.
func reset() -> void:
	_t = _interval

## Avance l'horloge de `delta` secondes ; renvoie le nombre de tirs autorisés
## sur ce tick (0 ou 1 aux cadences ≤ 60/s, la boucle généralise au-delà).
func tick(delta: float, trigger: bool) -> int:
	if not trigger:
		# Inactif : redescend vers "prête" (plafonné) sans banquer de crédit.
		_t = minf(_t + delta, _interval)
		return 0
	_t += delta
	var shots := 0
	while _t >= _interval:
		_t -= _interval
		shots += 1
	return shots
