## FrameStats.gd
## Anneau de temps d'image (ms), classe pure sans accès à l'arbre de scène.
## Fournit le fps moyen, le p99 (nearest-rank) et le "1% low" fps dérivé
## (= 1000 / p99_ms). Tampon vide -> tous les getters renvoient 0.
class_name FrameStats
extends RefCounted

var _capacity: int
var _buffer: Array[float] = []
var _count: int = 0
var _next: int = 0

func _init(capacity: int = 600) -> void:
	_capacity = max(1, capacity)
	_buffer.resize(_capacity)
	_buffer.fill(0.0)

## Ajoute un temps d'image (ms). Écrase le plus ancien au-delà de la capacité.
func add(frame_ms: float) -> void:
	_buffer[_next] = frame_ms
	_next = (_next + 1) % _capacity
	_count = mini(_count + 1, _capacity)

func count() -> int:
	return _count

func avg_fps() -> float:
	if _count == 0:
		return 0.0
	var total := 0.0
	for i in range(_count):
		total += _buffer[i]
	var avg_ms := total / _count
	if avg_ms <= 0.0:
		return 0.0
	return 1000.0 / avg_ms

## 99ᵉ percentile (nearest-rank) du temps d'image, en ms.
func p99_ms() -> float:
	if _count == 0:
		return 0.0
	var samples: Array[float] = []
	for i in range(_count):
		samples.append(_buffer[i])
	samples.sort()
	var rank := clampi(int(ceil(0.99 * samples.size())), 1, samples.size())
	return samples[rank - 1]

func low_1pct_fps() -> float:
	var p := p99_ms()
	if p <= 0.0:
		return 0.0
	return 1000.0 / p

func clear() -> void:
	_count = 0
	_next = 0
