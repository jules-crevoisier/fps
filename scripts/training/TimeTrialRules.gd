## TimeTrialRules.gd
## Logique PURE du "Contre-la-montre" (.orchestrator/contract-r4a.md,
## R4-TRAIN #2) : progression des checkpoints, formatage du temps et calcul
## de médaille (Or/Argent/Bronze), comparaison au meilleur temps local.
## Aucun nœud/scène — consommée par `scripts/training/TimeTrialCourse.gd`.
class_name TimeTrialRules
extends RefCounted

const MEDAL_GOLD := "or"
const MEDAL_SILVER := "argent"
const MEDAL_BRONZE := "bronze"
const MEDAL_NONE := ""

## Un checkpoint (identifié par son index, 0 = porte de DÉPART) ne fait
## avancer la course que s'il correspond EXACTEMENT au prochain attendu —
## retoucher un checkpoint déjà validé (ex. revenir en arrière) ou en
## déclencher un plus loin (ex. raccourci hors piste) ne change rien.
static func advance_checkpoint(next_expected: int, entered_index: int, total_checkpoints: int) -> int:
	if entered_index != next_expected:
		return next_expected
	return mini(next_expected + 1, total_checkpoints)

static func is_finished(next_expected: int, total_checkpoints: int) -> bool:
	return next_expected >= total_checkpoints

## Seuils exprimés en secondes, du plus exigeant (or) au plus permissif
## (bronze). Un temps au-delà de `bronze_t` ne rapporte aucune médaille.
static func medal_for_time(time: float, gold_t: float, silver_t: float, bronze_t: float) -> String:
	if time <= gold_t:
		return MEDAL_GOLD
	if time <= silver_t:
		return MEDAL_SILVER
	if time <= bronze_t:
		return MEDAL_BRONZE
	return MEDAL_NONE

## `previous_best <= 0` signifie "aucun record local" (voir TrainingRecords) :
## le tout premier temps chronométré devient toujours le meilleur.
static func is_new_best(time: float, previous_best: float) -> bool:
	return previous_best <= 0.0 or time < previous_best

## "MM:SS.cc" — centièmes, jamais de valeur négative (chronomètre affiché).
static func format_time(t: float) -> String:
	var clamped := maxf(t, 0.0)
	var total_cs := int(round(clamped * 100.0))
	var minutes := total_cs / 6000
	var seconds := (total_cs / 100) % 60
	var centis := total_cs % 100
	return "%02d:%02d.%02d" % [minutes, seconds, centis]
