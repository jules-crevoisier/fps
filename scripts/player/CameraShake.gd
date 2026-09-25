## CameraShake.gd
## Secousse de caméra à « trauma » (GF-08, Squirrel Eiserloh, GDC 2016
## « Juicing Your Cameras With Math », docs/research/01_game_feel.md §2.1/§3) :
## un seul scalaire `trauma` dans [0,1], incrémenté par les événements de jeu
## (tir, dégât reçu, explosion proche) et qui décroît LINÉAIREMENT dans le
## temps. L'amplitude de la secousse suit `trauma²` (pas `trauma` — Eiserloh
## insiste : le carré rend les petits trauma presque invisibles et les gros
## spectaculaires, contrairement à une relation linéaire qui secoue trop tôt).
## La secousse est PUREMENT ROTATIONNELLE (yaw/pitch/roll, jamais de
## translation — « the translational shake is lame », même talk), lue depuis
## du bruit de Perlin (`FastNoiseLite`, trois axes décorrélés par un décalage
## fixe dans le domaine du bruit) plutôt qu'un `randf` pur, pour un mouvement
## fluide plutôt que du grésillement.
##
## Ajoute aussi le « punch FOV » des armes lourdes : un retrait bref du champ
## de vision (impulsion, jamais un lerp continu) qui revient à zéro en
## `PUNCH_FOV_HEAVY_DURATION`.
##
## Classe PURE : ni Node, ni accès à `Settings`/à la scène — seul
## `PlayerCamera` (le SEUL appelant prévu) lit `Settings.camera_shake_enabled`/
## `camera_shake_intensity`/`reduced_motion` et les combine via
## `effective_intensity` avant de les passer en paramètre. Entièrement
## testable hors arbre de scène, voir tests/player/test_camera_shake.gd.
class_name CameraShake
extends RefCounted

## Décroissance du trauma par seconde (linéaire), valeur par défaut Eiserloh.
const DEFAULT_DECAY_PER_SECOND := 1.5
## Angle de rotation MAXIMUM (degrés, par axe) atteint à trauma = 1.0 et
## intensité = 1.0 — jamais dépassé (borné par le bruit, qui reste dans [-1,1]
## pour Perlin).
const MAX_ANGLE_DEG := 1.2
## Vitesse de lecture du bruit de Perlin (unités de bruit par seconde) : assez
## rapide pour un tremblement perceptible, assez lent pour rester fluide
## (jamais du grésillement façon `randf` par frame).
const NOISE_SPEED := 25.0
## Décalages fixes (dans le domaine du bruit) entre les 3 axes de rotation,
## pour qu'ils ne lisent jamais le même point du bruit au même instant — même
## principe que Eiserloh (un seul générateur, trois lectures décalées).
## Volontairement NON ENTIERS : un `FastNoiseLite` de type Perlin vaut
## exactement 0 sur un point de treillis (coordonnées entières des deux
## côtés), ce qui aurait annulé la secousse pile à `_noise_time == 0.0`
## (juste après `_init`, avant le premier `update`).
const _AXIS_OFFSET_PITCH := 0.13
const _AXIS_OFFSET_YAW := 137.71
const _AXIS_OFFSET_ROLL := 281.37

## Trauma fixe ajouté à la réception de dégâts (GF-08).
const TRAUMA_DAMAGE_TAKEN := 0.3
## Trauma fixe ajouté par une explosion proche (GF-08) — le plus violent des
## trois déclencheurs.
const TRAUMA_EXPLOSION_NEAR := 0.6
## Bornes du trauma de tir (GF-08 : « 0.08-0.25 selon l'arme, champ
## WeaponConfig ») — voir `shot_trauma`, qui les applique défensivement même
## si l'appelant transmet une valeur hors bornes.
const SHOT_TRAUMA_MIN := 0.08
const SHOT_TRAUMA_MAX := 0.25

## Punch FOV (GF-08) au tir d'une arme lourde (`WeaponConfig.Category.HEAVY`) :
## -1.5° pendant 60 ms, puis retour à 0 (jamais un simple lerp continu).
const PUNCH_FOV_HEAVY_DEG := -1.5
const PUNCH_FOV_HEAVY_DURATION := 0.06

## Trauma courant, toujours dans [0,1] (voir `clamp_trauma`).
var trauma: float = 0.0
## Vitesse de décroissance (unités de trauma/s) — champ modifiable par
## instance, défaut `DEFAULT_DECAY_PER_SECOND`.
var decay_per_second: float = DEFAULT_DECAY_PER_SECOND

var _noise := FastNoiseLite.new()
var _noise_time: float = 0.0

## Punch FOV en cours : `_fov_punch_elapsed < 0.0` signifie « aucun punch actif ».
var _fov_punch_elapsed: float = -1.0
var _fov_punch_duration: float = PUNCH_FOV_HEAVY_DURATION
var _fov_punch_magnitude: float = 0.0

## `noise_seed` : graine du bruit de Perlin — fixe par défaut (0) pour un
## comportement déterministe et testable ; une caméra réelle peut passer une
## graine différente par joueur (cosmétique, sans effet sur ce contrat).
func _init(noise_seed: int = 0) -> void:
	_noise.noise_type = FastNoiseLite.NoiseType.TYPE_PERLIN
	_noise.seed = noise_seed
	_noise.frequency = 1.0


## Ajoute du trauma brut (déjà dans la bonne plage — voir `add_shot_trauma`/
## `add_damage_trauma`/`add_explosion_trauma` pour les déclencheurs standard),
## borné à [0,1].
func add_trauma(amount: float) -> void:
	trauma = clamp_trauma(trauma + amount)


## Trauma de tir (GF-08) : `amount` vient du champ dédié de `WeaponConfig` de
## l'arme (0.08-0.25 selon l'arme) — reborné ici par sécurité (`shot_trauma`)
## même si l'appelant transmet une valeur hors contrat.
func add_shot_trauma(amount: float) -> void:
	add_trauma(shot_trauma(amount))


## Trauma de dégât reçu (0.3 fixe, GF-08).
func add_damage_trauma() -> void:
	add_trauma(TRAUMA_DAMAGE_TAKEN)


## Trauma d'explosion proche (0.6 fixe, GF-08).
func add_explosion_trauma() -> void:
	add_trauma(TRAUMA_EXPLOSION_NEAR)


## Démarre un punch FOV (GF-08 : -1.5° en 60 ms par défaut, pour les armes
## lourdes). Un punch déjà en cours est remplacé (pas cumulé — un second tir
## très rapproché relance l'impulsion plutôt que de l'additionner, ce qui
## produirait un FOV négatif aberrant en rafale).
func add_fov_punch(magnitude_deg: float = PUNCH_FOV_HEAVY_DEG, duration: float = PUNCH_FOV_HEAVY_DURATION) -> void:
	_fov_punch_magnitude = magnitude_deg
	_fov_punch_duration = maxf(duration, 0.001)
	_fov_punch_elapsed = 0.0


## Avance le trauma (décroissance linéaire) et le temps de bruit d'un pas
## `delta` (secondes). À appeler une fois par frame par le SEUL appelant
## prévu (`PlayerCamera._process`, humain local uniquement).
func update(delta: float) -> void:
	trauma = decayed_trauma(trauma, decay_per_second, delta)
	_noise_time += delta * NOISE_SPEED
	if _fov_punch_elapsed >= 0.0:
		_fov_punch_elapsed += delta
		if _fov_punch_elapsed >= _fov_punch_duration:
			_fov_punch_elapsed = -1.0


## Décalage de rotation courant (degrés, `Vector3(pitch, yaw, roll)`) —
## amplitude = `trauma² × intensity`, jamais de composante de position
## (rotation seule, Eiserloh). `intensity` doit déjà être la valeur EFFECTIVE
## (voir `effective_intensity` : reduced-motion et le réglage « secousses de
## caméra » désactivé donnent tous les deux 0).
func rotation_offset_deg(intensity: float = 1.0) -> Vector3:
	var amp := amplitude_for_trauma(trauma) * clampf(intensity, 0.0, 1.0)
	if amp <= 0.0:
		return Vector3.ZERO
	var pitch := _noise.get_noise_2d(_noise_time, _AXIS_OFFSET_PITCH) * MAX_ANGLE_DEG * amp
	var yaw := _noise.get_noise_2d(_noise_time, _AXIS_OFFSET_YAW) * MAX_ANGLE_DEG * amp
	var roll := _noise.get_noise_2d(_noise_time, _AXIS_OFFSET_ROLL) * MAX_ANGLE_DEG * amp
	return Vector3(pitch, yaw, roll)


## Décalage de FOV courant (degrés, négatif = zoom arrière léger) dû au punch
## en cours, 0 si aucun punch actif. Même paramètre `intensity` EFFECTIF que
## `rotation_offset_deg`.
func fov_offset_deg(intensity: float = 1.0) -> float:
	if _fov_punch_elapsed < 0.0:
		return 0.0
	return fov_punch_value(_fov_punch_elapsed, _fov_punch_duration, _fov_punch_magnitude) * clampf(intensity, 0.0, 1.0)


# ------------------------------------------------------------ FONCTIONS PURES
# Isolées en `static` pour rester testables sans instance ni bruit (courbe
# seule) — même principe que PlayerCamera.dynamic_fov_bonus/stun_dizzy_step.

## Borne le trauma à [0,1].
static func clamp_trauma(v: float) -> float:
	return clampf(v, 0.0, 1.0)


## Décroissance LINÉAIRE du trauma sur `delta` secondes à `decay_per_second`
## (GF-08 : défaut 1.5/s) — jamais négatif (voir `clamp_trauma`).
static func decayed_trauma(current_trauma: float, decay_per_second: float, delta: float) -> float:
	return clamp_trauma(current_trauma - decay_per_second * delta)


## Amplitude de la secousse = trauma² (GF-08/Eiserloh), pas trauma linéaire.
static func amplitude_for_trauma(current_trauma: float) -> float:
	var t := clamp_trauma(current_trauma)
	return t * t


## Reborne un trauma de tir à [SHOT_TRAUMA_MIN, SHOT_TRAUMA_MAX] (GF-08 :
## « 0.08-0.25 selon l'arme »).
static func shot_trauma(amount: float) -> float:
	return clampf(amount, SHOT_TRAUMA_MIN, SHOT_TRAUMA_MAX)


## Courbe du punch FOV : `magnitude_deg` à l'impact (`elapsed = 0`), remonte à
## 0 en `duration` (easeOutQuad — redescend vite puis ralentit, sans jamais
## dépasser 0, contrairement à un ressort avec overshoot).
static func fov_punch_value(elapsed: float, duration: float, magnitude_deg: float) -> float:
	if duration <= 0.0:
		return 0.0
	var p := clampf(elapsed / duration, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - p, 2.0)
	return lerp(magnitude_deg, 0.0, eased)


## Combine le réglage « intensité » (0-100 %, stocké 0-1), le maître
## « secousses de caméra » et le mouvement réduit en UNE intensité effective
## (GF-08 : « réglage 'intensité' 0-100 % et reduced-motion → 0 ») : le
## mouvement réduit et le maître désactivé donnent tous les deux 0, sans
## exception — jamais de secousse ni de punch FOV pour un joueur qui a demandé
## le confort.
static func effective_intensity(intensity_setting: float, shake_enabled: bool, reduced_motion: bool) -> float:
	if reduced_motion or not shake_enabled:
		return 0.0
	return clampf(intensity_setting, 0.0, 1.0)
