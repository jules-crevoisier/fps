## FireClock.gd
## Horloge de tir à reste fractionnaire, pensée pour être tickée à 60 Hz fixe
## (_physics_process). Tant que la gâchette est tenue, le crédit de temps
## s'accumule et chaque franchissement de l'intervalle (1/rate) déclenche un
## tir en conservant le reste — la cadence MOYENNE colle à `rate` (±1 tir/s).
## Le premier tir après une période d'inactivité part immédiatement ; pendant
## l'inactivité, l'horloge redescend vers "prête" sans jamais banquer de tirs
## au-delà (pas de rafale différée qui exploserait à la reprise du tir).
## BUFFER D'ENTRÉE (GF-12, docs/research/01_game_feel.md #13) : un `trigger`
## reçu alors que le cooldown n'est pas terminé (`_t < _interval`, typiquement
## un clic semi-auto — `fire_pressed` n'est vrai qu'une seule frame) n'est plus
## perdu : il est mémorisé `INPUT_BUFFER_S` (120 ms) et déclenche le tir dès
## que l'intervalle est atteint, même si la gâchette a été relâchée entre
## temps. Un SEUL clic reste mémorisé à la fois (un second clic pendant la
## même fenêtre rafraîchit juste l'échéance, n'empile jamais un second tir) ;
## passé 120 ms sans que l'intervalle ne soit atteint, le clic mémorisé expire
## sans jamais tirer (pas de rafale surprise longtemps après le clic).
class_name FireClock
extends RefCounted

## Fenêtre de mémorisation (s) d'un clic reçu pendant le cooldown — 120 ms
## (contract GF-12).
const INPUT_BUFFER_S := 0.12

var _rate: float
var _interval: float
var _t: float
## Secondes restantes avant expiration du clic mémorisé ; -1.0 = aucun clic en attente.
var _buffered_s: float = -1.0

func _init(rate_per_sec: float) -> void:
	set_rate(rate_per_sec)
	reset()

## Change la cadence pour les tirs suivants (ne réinitialise pas le crédit
## en cours, pour ne pas offrir un tir "gratuit" au changement de cadence).
func set_rate(rate: float) -> void:
	_rate = maxf(rate, 0.001)
	_interval = 1.0 / _rate

## Repasse l'horloge à "prête" : le prochain tir sera immédiat. Oublie aussi
## tout clic mémorisé en attente (ex. changement d'arme).
func reset() -> void:
	_t = _interval
	_buffered_s = -1.0

## Avance l'horloge de `delta` secondes ; renvoie le nombre de tirs autorisés
## sur ce tick (0 ou 1 aux cadences ≤ 60/s, la boucle généralise au-delà).
## `trigger` reçu pendant le cooldown arme le buffer d'entrée (voir docstring
## de classe) plutôt que d'être perdu.
func tick(delta: float, trigger: bool) -> int:
	if trigger and _t < _interval:
		_buffered_s = INPUT_BUFFER_S  # un seul clic mémorisé : rafraîchit, n'empile jamais.
	if not trigger and _buffered_s < 0.0:
		# Inactif SANS clic mémorisé en attente : redescend vers "prête"
		# (plafonné) sans banquer de crédit.
		_t = minf(_t + delta, _interval)
		return 0
	_t += delta
	var shots := 0
	while _t >= _interval:
		_t -= _interval
		shots += 1
		_buffered_s = -1.0  # le clic mémorisé vient de partir : consommé.
	if shots == 0 and _buffered_s >= 0.0:
		_buffered_s -= delta
		if _buffered_s < 0.0:
			_buffered_s = -1.0  # fenêtre de 120 ms dépassée : le clic expire sans jamais tirer.
	return shots
