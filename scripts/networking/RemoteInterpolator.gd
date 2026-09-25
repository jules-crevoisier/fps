## RemoteInterpolator.gd
## Tampon d'instantanés (snapshots) réseau + interpolation à délai fixe pour
## les PAIRS DISTANTS (GF-02, docs/research/01_game_feel.md §5). Classe pure
## (RefCounted, aucune dépendance à l'arbre de scène) : consommée par
## PlayerController.gd (branche non-autorité de `_physics_process`) et testée
## directement par tests/networking/test_remote_interpolator.gd.
##
## Principe (snapshot interpolation façon Source/Overwatch) : chaque
## instantané reçu est horodaté par l'ÉMETTEUR (tick physique de l'AUTORITÉ,
## PAS l'heure d'arrivée locale) — c'est ce qui rend le tampon robuste à la
## gigue réseau et au réordonnancement UDP (deux paquets peuvent arriver dans
## le désordre ; `push_snapshot` les remet dans l'ordre CHRONOLOGIQUE réel).
## On ne rend JAMAIS l'instantané le plus récent tel quel : on rend une
## position interpolée entre les deux instantanés qui encadrent
## `render_time = horloge_locale - delay_seconds()`, ce qui donne un
## mouvement lisse même si les paquets arrivent à intervalles irréguliers.
## Si le tampon n'a pas (encore, ou plus) l'instantané nécessaire (démarrage,
## paquet perdu, gigue supérieure au délai), on FIGE sur le dernier/premier
## instantané connu plutôt que d'extrapoler : c'est ce qui garantit qu'aucun
## saut arrière ne peut se produire.
##
## `delay_seconds()` est EXPOSÉ pour GF-01 (compensation de lag serveur) : le
## rembobinage y ajoutera ce délai à la latence réseau mesurée, puisque c'est
## très exactement ce que le tireur voit à l'écran pour une cible distante.
class_name RemoteInterpolator
extends RefCounted

## Délai par défaut : 2 ticks à 60 Hz = 33,3 ms (critère GF-02). 60 Hz suit
## `project.godot` > physics/common/physics_ticks_per_second.
const DEFAULT_DELAY_TICKS := 2
const DEFAULT_TICK_RATE := 60.0
## Instantanés gardés en mémoire au-delà du dernier consommé — large marge
## pour absorber la gigue réseau sans jamais manquer de données pour `sample`.
const MAX_BUFFER := 32

## Un instantané réseau horodaté (temps de simulation de l'ÉMETTEUR, en
## secondes — jamais l'heure d'arrivée locale, voir docstring de la classe).
class Snapshot:
	var t: float
	var position: Vector3
	var rotation: Vector3

	func _init(p_t: float, p_position: Vector3, p_rotation: Vector3) -> void:
		t = p_t
		position = p_position
		rotation = p_rotation

## Réglable (critère GF-02 : « le délai est exposé, réglable ») — voir aussi
## `delay_seconds()`, qui combine les deux en une durée.
var delay_ticks: int = DEFAULT_DELAY_TICKS
var tick_rate: float = DEFAULT_TICK_RATE

var _snapshots: Array[Snapshot] = []

## Délai de rendu fixe, en secondes (2 ticks / 60 Hz = 0.0333... par défaut).
## GF-01 lit cette valeur pour son propre rembobinage — voir docstring de classe.
func delay_seconds() -> float:
	return float(delay_ticks) / tick_rate

## Nombre d'instantanés actuellement bufferisés (diagnostics + tests).
func snapshot_count() -> int:
	return _snapshots.size()

## Horodatage du DERNIER instantané connu (0.0 tant qu'aucun n'est arrivé).
func latest_t() -> float:
	return _snapshots.back().t if not _snapshots.is_empty() else 0.0

## Ajoute un instantané reçu du réseau, horodaté par l'ÉMETTEUR (`t`,
## secondes — PAS l'heure d'arrivée locale). Un instantané plus vieux ou égal
## au plus récent déjà connu est un doublon ou un paquet en retard
## réordonné par UDP : il est ignoré (l'insérer casserait l'ordre croissant
## strict dont `sample` dépend pour ne jamais reculer, voir "aucun saut
## arrière" dans la docstring de classe).
func push_snapshot(t: float, position: Vector3, rotation: Vector3) -> void:
	if not _snapshots.is_empty() and t <= _snapshots.back().t:
		return
	_snapshots.append(Snapshot.new(t, position, rotation))
	while _snapshots.size() > MAX_BUFFER:
		_snapshots.pop_front()

## Vide le tampon (téléportation/respawn d'un pair distant — on ne veut
## jamais interpoler depuis une position d'avant la téléportation).
func reset() -> void:
	_snapshots.clear()

## Position/rotation interpolées au temps `render_time` (secondes, même base
## que les `t` passés à `push_snapshot`). Renvoie
## `{"position": Vector3, "rotation": Vector3}`. Sans aucun instantané reçu,
## renvoie l'origine (rien à rendre). Avant le premier instantané connu OU
## au-delà du dernier (démarrage du tampon, ou flux interrompu par une
## gigue/perte supérieure au délai), FIGE sur l'extrémité disponible la plus
## proche — jamais d'extrapolation, donc jamais de saut en arrière.
func sample(render_time: float) -> Dictionary:
	if _snapshots.is_empty():
		return {"position": Vector3.ZERO, "rotation": Vector3.ZERO}
	if render_time <= _snapshots[0].t:
		return _as_result(_snapshots[0])
	if render_time >= _snapshots.back().t:
		return _as_result(_snapshots.back())
	var pair := _bracket(render_time)
	var a: Snapshot = pair[0]
	var b: Snapshot = pair[1]
	var span := b.t - a.t
	var f: float = 0.0 if span <= 0.0 else clampf((render_time - a.t) / span, 0.0, 1.0)
	return {
		"position": a.position.lerp(b.position, f),
		"rotation": Vector3(
			lerp_angle(a.rotation.x, b.rotation.x, f),
			lerp_angle(a.rotation.y, b.rotation.y, f),
			lerp_angle(a.rotation.z, b.rotation.z, f)),
	}

## Recherche dichotomique du couple d'instantanés CONSÉCUTIFS qui encadre
## `render_time` (précondition assurée par les deux clamps de `sample` :
## `_snapshots[0].t < render_time < back().t`, et `_snapshots.size() >= 2`
## puisqu'un tampon à un seul élément aurait déjà été absorbé par un des deux
## clamps).
func _bracket(render_time: float) -> Array:
	var lo := 0
	var hi := _snapshots.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _snapshots[mid].t <= render_time:
			lo = mid
		else:
			hi = mid
	return [_snapshots[lo], _snapshots[hi]]

static func _as_result(s: Snapshot) -> Dictionary:
	return {"position": s.position, "rotation": s.rotation}
