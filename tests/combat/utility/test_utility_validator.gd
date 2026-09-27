## test_utility_validator.gd
## Spec (contrat lead) : le serveur valide (vivant, charge disponible, cadence,
## origine proche de la tête) avant d'accepter un lancer — même patron que
## tests/combat/test_shot_validator.gd.
extends GdUnitTestSuite


func _frag_cfg() -> UtilityConfig:
	return UtilityDatabase.get_by_id(UtilityDatabase.FRAG)


func _flash_cfg() -> UtilityConfig:
	return UtilityDatabase.get_by_id(UtilityDatabase.FLASH)


func test_valid_request_returns_true() -> void:
	var head := Vector3(0.0, 1.8, 0.0)
	assert_bool(UtilityValidator.is_valid_request(head, head, Vector3(0, 0, -1), 0.3, _frag_cfg())).is_true()


func test_origin_too_far_from_head_returns_false() -> void:
	var head := Vector3.ZERO
	var far_origin := head + Vector3(5.0, 0.0, 0.0)
	assert_bool(UtilityValidator.is_valid_request(far_origin, head, Vector3(0, 0, -1), 0.3, _frag_cfg())).is_false()


func test_origin_within_tolerance_returns_true() -> void:
	var head := Vector3.ZERO
	var origin := head + Vector3(UtilityValidator.ORIGIN_TOLERANCE, 0.0, 0.0)
	assert_bool(UtilityValidator.is_valid_request(origin, head, Vector3(0, 0, -1), 0.3, _frag_cfg())).is_true()


func test_nan_origin_returns_false() -> void:
	var head := Vector3.ZERO
	assert_bool(UtilityValidator.is_valid_request(Vector3(NAN, 0.0, 0.0), head, Vector3(0, 0, -1), 0.3, _frag_cfg())).is_false()


func test_non_normalized_direction_returns_false() -> void:
	var head := Vector3.ZERO
	assert_bool(UtilityValidator.is_valid_request(head, head, Vector3(2.0, 0.0, 0.0), 0.3, _frag_cfg())).is_false()


func test_negative_held_duration_returns_false() -> void:
	var head := Vector3.ZERO
	assert_bool(UtilityValidator.is_valid_request(head, head, Vector3(0, 0, -1), -0.1, _frag_cfg())).is_false()


func test_frag_held_duration_at_or_beyond_fuse_is_rejected() -> void:
	var head := Vector3.ZERO
	# Une frag maintenue jusqu'à l'amorce complète explose en main -- elle ne
	# devrait jamais atteindre cette requête de lancer avec ce temps annoncé.
	assert_bool(UtilityValidator.is_valid_request(head, head, Vector3(0, 0, -1), 2.5, _frag_cfg())).is_false()


func test_flash_ignores_the_press_started_fuse_rule() -> void:
	var head := Vector3.ZERO
	# La flashbang démarre son amorce au RELÂCHEMENT (fuse_starts_on_press = false) :
	# un maintien annoncé long n'a pas la même signification que pour la frag.
	assert_bool(UtilityValidator.is_valid_request(head, head, Vector3(0, 0, -1), 5.0, _flash_cfg())).is_true()


func test_can_throw_requires_alive_charge_and_unlocked_round() -> void:
	assert_bool(UtilityValidator.can_throw(true, true, false)).is_true()


func test_can_throw_rejects_dead_player() -> void:
	assert_bool(UtilityValidator.can_throw(false, true, false)).is_false()


func test_can_throw_rejects_missing_charge() -> void:
	assert_bool(UtilityValidator.can_throw(true, false, false)).is_false()


func test_can_throw_rejects_locked_round() -> void:
	assert_bool(UtilityValidator.can_throw(true, true, true)).is_false()


## Contrat point 1 ("short throw on RIGHT click") : `short` est ACCEPTÉ
## (voir la docstring de `is_valid_request`) mais ne change AUCUNE règle de
## validité géométrique — un lancer valide reste valide, qu'il soit court ou
## long, et réciproquement pour un lancer invalide.
func test_short_flag_does_not_change_validity_of_an_otherwise_valid_request() -> void:
	var head := Vector3(0.0, 1.8, 0.0)
	assert_bool(UtilityValidator.is_valid_request(head, head, Vector3(0, 0, -1), 0.3, _frag_cfg(), true)).is_true()


func test_short_flag_does_not_rescue_an_otherwise_invalid_request() -> void:
	var head := Vector3.ZERO
	var far_origin := head + Vector3(5.0, 0.0, 0.0)
	assert_bool(UtilityValidator.is_valid_request(far_origin, head, Vector3(0, 0, -1), 0.3, _frag_cfg(), true)).is_false()
