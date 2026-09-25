## test_training_records.gd
## Spec (contract-r4a.md, R4-TRAIN #2 : "best time saved locally") —
## persistance réelle sous `user://` (ConfigFile, même patron que
## Settings.gd). Le fichier de test utilise un `course_id` dédié pour ne
## jamais toucher au vrai record du joueur, et nettoie après chaque test.
extends GdUnitTestSuite

const COURSE := "__test_course__"


func after_test() -> void:
	# `_debug_clear` (scripts/training/TrainingRecords.gd, hors périmètre de
	# cette tâche) appelle `ConfigFile.erase_section_key` sans garde : sur une
	# clé absente (aucun `save_best_time` dans le test qui vient de tourner,
	# ex. test_load_best_time_defaults_to_negative_when_absent), ça lève une
	# ERROR moteur « Cannot erase key ... from nonexistent section ». Les
	# temps sauvegardés dans cette suite sont toujours >= 0 ; `load_best_time`
	# ne renvoie -1.0 QUE si la clé n'existe pas encore (voir sa doc) — on ne
	# tente donc l'effacement que si un enregistrement a réellement été écrit.
	if TrainingRecords.load_best_time(COURSE) != -1.0:
		TrainingRecords._debug_clear(COURSE)


func test_load_best_time_defaults_to_negative_when_absent() -> void:
	assert_float(TrainingRecords.load_best_time(COURSE)).is_equal(-1.0)


func test_save_then_load_round_trip() -> void:
	var saved := TrainingRecords.save_best_time(21.5, COURSE)
	assert_bool(saved).is_true()
	assert_float(TrainingRecords.load_best_time(COURSE)).is_equal_approx(21.5, 0.001)


func test_save_does_not_overwrite_with_slower_time() -> void:
	TrainingRecords.save_best_time(20.0, COURSE)
	var saved := TrainingRecords.save_best_time(25.0, COURSE)
	assert_bool(saved).is_false()
	assert_float(TrainingRecords.load_best_time(COURSE)).is_equal_approx(20.0, 0.001)


func test_save_overwrites_with_faster_time() -> void:
	TrainingRecords.save_best_time(20.0, COURSE)
	var saved := TrainingRecords.save_best_time(15.0, COURSE)
	assert_bool(saved).is_true()
	assert_float(TrainingRecords.load_best_time(COURSE)).is_equal_approx(15.0, 0.001)
