## test_target_select.gd
## Spec (contract-r2.md, R-B3 acceptance #2/#5): selection de cibles pure pour les
## capacites a zone (Deferlante, Vision totale, Oeil...) : filtre par equipe puis
## par rayon depuis un point d'impact calcule cote serveur.
extends GdUnitTestSuite


func _p(id: int, pos: Vector3, team: int) -> Dictionary:
	return {"id": id, "pos": pos, "team": team}


func test_within_radius_keeps_only_close_candidates() -> void:
	var candidates := [_p(1, Vector3(1, 0, 0), 0), _p(2, Vector3(10, 0, 0), 0)]
	var out := TargetSelect.within_radius(Vector3.ZERO, candidates, 5.0)
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].id).is_equal(1)


func test_within_radius_is_inclusive_at_the_boundary() -> void:
	var candidates := [_p(1, Vector3(5, 0, 0), 0)]
	var out := TargetSelect.within_radius(Vector3.ZERO, candidates, 5.0)
	assert_int(out.size()).is_equal(1)


func test_within_radius_excludes_a_team_when_given() -> void:
	var candidates := [_p(1, Vector3(1, 0, 0), 0), _p(2, Vector3(1, 0, 0), 1)]
	var out := TargetSelect.within_radius(Vector3.ZERO, candidates, 5.0, 0)
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].id).is_equal(2)


func test_within_radius_empty_candidates() -> void:
	var out := TargetSelect.within_radius(Vector3.ZERO, [], 5.0)
	assert_int(out.size()).is_equal(0)


func test_enemies_of_keeps_other_teams_only() -> void:
	var candidates := [_p(1, Vector3.ZERO, 0), _p(2, Vector3.ZERO, 1), _p(3, Vector3.ZERO, 0)]
	var out := TargetSelect.enemies_of(candidates, 0)
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].id).is_equal(2)


func test_enemies_of_empty_when_all_same_team() -> void:
	var candidates := [_p(1, Vector3.ZERO, 0), _p(2, Vector3.ZERO, 0)]
	var out := TargetSelect.enemies_of(candidates, 0)
	assert_int(out.size()).is_equal(0)
