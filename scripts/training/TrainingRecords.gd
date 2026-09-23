## TrainingRecords.gd
## Persistance locale (user://) du meilleur temps du Contre-la-montre
## (.orchestrator/contract-r4a.md, R4-TRAIN #2 : "best time saved locally").
## Même patron que `scripts/core/Settings.gd` (ConfigFile sous `user://`).
## `course_id` permet plusieurs circuits futurs sans se marcher dessus ;
## le training n'en a qu'un pour l'instant ("parcours").
class_name TrainingRecords
extends RefCounted

const PATH := "user://training_records.cfg"
const SECTION := "best_times"

## -1.0 = aucun record enregistré pour ce circuit.
static func load_best_time(course_id: String = "parcours") -> float:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return -1.0
	return float(cfg.get_value(SECTION, course_id, -1.0))

## N'écrit que si `time` améliore le record existant (ou qu'il n'y en a pas
## encore) — voir `TimeTrialRules.is_new_best`. Renvoie true si un nouveau
## record a été écrit.
static func save_best_time(time: float, course_id: String = "parcours") -> bool:
	var previous := load_best_time(course_id)
	if not TimeTrialRules.is_new_best(time, previous):
		return false
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # ignore l'erreur : fichier absent au premier lancement.
	cfg.set_value(SECTION, course_id, time)
	cfg.save(PATH)
	return true

## Réservé aux tests (évite de polluer le vrai fichier `user://` du joueur
## entre deux exécutions de la suite).
static func _debug_clear(course_id: String = "parcours") -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	cfg.erase_section_key(SECTION, course_id)
	cfg.save(PATH)
