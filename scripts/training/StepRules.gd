## StepRules.gd
## Logique PURE (aucun nœud, aucune scène) de détection des étapes du
## "Parcours de mouvement" (.orchestrator/contract-r4a.md, R4-TRAIN #1) —
## consommée par `scripts/training/MovementTutorial.gd`, qui écoute
## `PlayerStateMachine.state_changed` (et interroge la vitesse/l'état courant
## à chaque tick physique) et appelle ces fonctions avec les valeurs lues.
## Testée directement dans tests/training/test_step_rules.gd.
class_name StepRules
extends RefCounted

## Ordre des étapes du parcours (contract-r4a.md #1 : "sprint, slide,
## slide-cancel, slide-jump, air-strafe, dolphin dive over a gap, roll on
## landing to cancel the fall stun, dive across an 8 m gap" — le dernier
## élément de la liste du contrat redécrit la même mécanique de plongée que
## "dolphin dive over a gap" ; les 7 étapes distinctes retenues ici couvrent
## chaque mécanique nommée UNE fois).
const STEP_IDS := [
	"sprint", "slide", "slide_cancel", "slide_jump", "air_strafe", "dive_gap", "landing_roll",
]

## Marge sous `sprint_speed` tolérée pour valider l'étape "sprint" (le
## sprint est automatique dès qu'on bouge, mais la vitesse met un instant à
## atteindre sa cible avec `ground_move`/move_toward).
const SPRINT_FACTOR := 0.95

## Marge AU-DESSUS de `sprint_speed` exigée en l'air pour valider
## "air-strafe" (contract : vitesse gagnée en tournant + strafant qui
## dépasse ce qu'un sprint au sol permettrait).
const AIR_STRAFE_FACTOR := 1.1

## Distance horizontale minimale (m) entre le début et la fin d'une plongée
## réussie pour valider "dive_gap" — un peu sous les 8 m réels du vide
## construit (contract : "dive across an 8 m gap"), tolérance de mesure
## (position capturée à l'ENTRÉE de l'état Dive, pas exactement au bord).
const DIVE_GAP_MIN := 7.0

## --- Détection par transition d'état (from -> to, PlayerStateMachine.state_changed) ---

static func is_slide_step(from_state: String, to_state: String) -> bool:
	return to_state == "Slide" and from_state in ["Sprint", "Walk", "Idle"]

## Sortie de Slide SANS avoir sauté (slide-cancel : relâcher crouch en
## gardant l'élan — Slide._exit_to_ground transitionne vers Idle/Walk/Sprint,
## JAMAIS vers Crouch dans ce cas précis d'après le code : relâcher crouch
## est la condition d'entrée de cette branche).
static func is_slide_cancel_step(from_state: String, to_state: String) -> bool:
	return from_state == "Slide" and to_state in ["Idle", "Walk", "Sprint"]

## Sortie de Slide EN SAUTANT (slide-jump) : la transition seule (Slide -> Air)
## ne suffit pas à distinguer un slide-jump d'une sortie de piste (glisser
## hors du sol) — `slide_jumped` (PlayerController, vrai UNIQUEMENT juste
## après un slide-jump) lève l'ambiguïté.
static func is_slide_jump_step(from_state: String, to_state: String, slide_jumped: bool) -> bool:
	return from_state == "Slide" and to_state == "Air" and slide_jumped

## Roulade d'ATTERRISSAGE (annule le stun de chute) : Air -> Roll, PAS
## Dive -> Roll (qui est la fin normale d'une plongée, voir `is_dive_gap_step`).
static func is_landing_roll_step(from_state: String, to_state: String) -> bool:
	return from_state == "Air" and to_state == "Roll"

## Plongée qui traverse un vide d'au moins `min_gap` mètres (à vol d'oiseau,
## XZ) entre l'entrée dans Dive et l'atterrissage (Dive -> Roll, cf. Dive.gd :
## la roulade suit TOUJOURS une plongée à l'atterrissage).
static func is_dive_gap_step(from_state: String, to_state: String, start_pos: Vector3, end_pos: Vector3, min_gap: float = DIVE_GAP_MIN) -> bool:
	if from_state != "Dive" or to_state != "Roll":
		return false
	var flat_start := Vector2(start_pos.x, start_pos.z)
	var flat_end := Vector2(end_pos.x, end_pos.z)
	return flat_start.distance_to(flat_end) >= min_gap

## --- Détection continue (interrogée à chaque tick physique) ---

static func is_sprint_step(horizontal_speed: float, sprint_speed: float, factor: float = SPRINT_FACTOR) -> bool:
	return horizontal_speed >= sprint_speed * factor

static func is_air_strafe_step(state_name: String, horizontal_speed: float, sprint_speed: float, factor: float = AIR_STRAFE_FACTOR) -> bool:
	return state_name == "Air" and horizontal_speed > sprint_speed * factor

## --- Libellés (FR, "%s" à substituer par le libellé de touche réel) ---

const STEPS := {
	"sprint": {"action": "", "text": "Avancez — le sprint se déclenche automatiquement."},
	"slide": {"action": "crouch", "text": "En pleine course, appuyez sur %s pour glisser."},
	"slide_cancel": {"action": "crouch", "text": "Pendant la glissade, RELÂCHEZ %s pour annuler en gardant l'élan."},
	"slide_jump": {"action": "jump", "text": "Glissez puis appuyez sur %s : c'est un slide-jump."},
	"air_strafe": {"action": "", "text": "Sautez au-dessus du vide et tournez en l'air en strafant pour gagner de la vitesse."},
	"dive_gap": {"action": "dive", "text": "Appuyez sur %s pour plonger au-dessus du grand vide (8 m)."},
	"landing_roll": {"action": "dive", "text": "Sautez de la tour et appuyez sur %s juste avant l'impact pour rouler et annuler l'étourdissement."},
}

## Texte final d'une étape, `%s` remplacé par `action_label` s'il y a une
## action associée (sinon le texte est renvoyé tel quel — pur, testable sans
## dépendre de `Settings`/`DisplayServer`, qui restent côté Node appelant).
static func format_text(step_id: String, action_label: String) -> String:
	var step: Dictionary = STEPS.get(step_id, {})
	var text: String = step.get("text", "")
	var action: String = step.get("action", "")
	if action == "":
		return text
	return text % action_label

static func action_for(step_id: String) -> String:
	var step: Dictionary = STEPS.get(step_id, {})
	return step.get("action", "")
