## test_game_mode_tiebreak.gd
## Spec (docs/audit/bugs.md, BUG-01) : quand le temps du match (TDM/Hardpoint)
## expire avec des scores à égalité, la partie ne doit JAMAIS rester bloquée
## sans vainqueur. GameMode retente `_try_decide_by_score()` à CHAQUE tick
## une fois le temps écoulé (`_time_expired`), pas seulement au tick où il
## expire : le prochain point marqué — par n'importe quel chemin, avec ou
## sans passer par `check_win()` — tranche au tick suivant, et le mode
## expose un bandeau "MORT SUBITE" tant que l'égalité n'est pas rompue.
extends GdUnitTestSuite

const DT := 1.0 / 60.0


func _new_mode(time_limit: float = 0.0) -> GameMode:
	var mode := GameMode.new()
	mode.match_time_limit = time_limit
	add_child(mode)
	auto_free(mode)
	return mode


# ----------------------------------------------------------------------
#  Avant expiration : jeu normal, pas de mort subite.
# ----------------------------------------------------------------------
func test_no_winner_and_no_banner_before_time_expires() -> void:
	var mode := _new_mode(100.0)
	mode.team_scores = [1.0, 1.0]
	mode._physics_process(DT)
	assert_int(mode.winner).is_equal(-1)
	assert_str(mode.sudden_death_notice).is_equal("")


# ----------------------------------------------------------------------
#  Expiration avec un écart déjà présent : décidé immédiatement, sans
#  passer par la mort subite (comportement existant, non régressé).
# ----------------------------------------------------------------------
func test_time_expires_with_score_gap_decides_immediately_without_banner() -> void:
	var mode := _new_mode()
	mode.team_scores = [4.0, 2.0]
	mode._physics_process(DT)
	assert_int(mode.winner).is_equal(0)
	assert_str(mode.sudden_death_notice).is_equal("")


# ----------------------------------------------------------------------
#  Cas BUG-01 : égalité à l'expiration -> bandeau "MORT SUBITE", pas de
#  vainqueur ; puis un point marqué -> vainqueur fixé au tick suivant, et
#  le bandeau retombe.
# ----------------------------------------------------------------------
func test_tied_score_at_expiry_raises_sudden_death_banner_with_no_winner() -> void:
	var mode := _new_mode()
	mode.team_scores = [3.0, 3.0]
	mode._physics_process(DT)
	assert_int(mode.winner).is_equal(-1)
	assert_str(mode.sudden_death_notice).is_equal("MORT SUBITE")


func test_point_scored_after_tied_expiry_sets_winner_next_tick() -> void:
	var mode := _new_mode()
	mode.team_scores = [3.0, 3.0]
	mode._physics_process(DT)  # expire à égalité -> mort subite, pas de vainqueur
	assert_int(mode.winner).is_equal(-1)

	mode.team_scores[0] += 1.0  # le point de la mort subite
	mode._physics_process(DT)  # tick suivant
	assert_int(mode.winner).is_equal(0)
	assert_str(mode.sudden_death_notice).is_equal("")


func test_point_scored_for_other_team_after_tied_expiry_sets_winner_next_tick() -> void:
	var mode := _new_mode()
	mode.team_scores = [7.0, 7.0]
	mode._physics_process(DT)
	assert_int(mode.winner).is_equal(-1)

	mode.team_scores[1] += 1.0
	mode._physics_process(DT)
	assert_int(mode.winner).is_equal(1)
	assert_str(mode.sudden_death_notice).is_equal("")


# ----------------------------------------------------------------------
#  Le point du critère : la reprise ne dépend pas d'un appel explicite à
#  check_win() par le mode concret (ex. Hardpoint qui n'incrémente/ne
#  vérifie le score que quand une équipe SEULE tient la zone) — aucune
#  partie ne doit rester sans vainqueur plus de 1 tick après un
#  changement de score, même si rien n'appelle check_win().
# ----------------------------------------------------------------------
func test_score_change_without_check_win_still_resolves_within_one_tick() -> void:
	var mode := _new_mode()
	mode.team_scores = [5.0, 5.0]
	mode._physics_process(DT)
	assert_int(mode.winner).is_equal(-1)

	# Score modifié directement, sans appeler check_win() (ex. Hardpoint : le
	# capteur n'a repris son tick de score qu'à la frame suivante).
	mode.team_scores[1] += 0.5
	mode._physics_process(DT)
	assert_int(mode.winner).is_equal(1)


func test_score_stays_tied_keeps_banner_and_no_winner_across_several_ticks() -> void:
	var mode := _new_mode()
	mode.team_scores = [2.0, 2.0]
	for i in 5:
		mode._physics_process(DT)
		assert_int(mode.winner).is_equal(-1)
		assert_str(mode.sudden_death_notice).is_equal("MORT SUBITE")


# ----------------------------------------------------------------------
#  check_win() (chemin utilisé par TDM/Hardpoint après un point) doit lui
#  aussi trancher immédiatement une mort subite déjà engagée.
# ----------------------------------------------------------------------
func test_check_win_resolves_sudden_death_immediately() -> void:
	var mode := _new_mode()
	mode.team_scores = [1.0, 1.0]
	mode._physics_process(DT)
	assert_int(mode.winner).is_equal(-1)

	mode.team_scores[0] += 1.0
	mode.check_win()
	assert_int(mode.winner).is_equal(0)
	assert_str(mode.sudden_death_notice).is_equal("")


# ----------------------------------------------------------------------
#  reset_match() (revanche) doit repartir sur une ardoise propre : plus de
#  bandeau de mort subite qui traînerait d'un match précédent.
# ----------------------------------------------------------------------
func test_reset_match_clears_sudden_death_banner() -> void:
	var mode := _new_mode()
	mode.team_scores = [2.0, 2.0]
	mode._physics_process(DT)
	assert_str(mode.sudden_death_notice).is_equal("MORT SUBITE")

	mode.reset_match()
	assert_int(mode.winner).is_equal(-1)
	assert_str(mode.sudden_death_notice).is_equal("")
	assert_bool(mode._time_expired).is_false()
