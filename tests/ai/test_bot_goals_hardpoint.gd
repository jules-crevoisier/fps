## test_bot_goals_hardpoint.gd
## BOT-24 (T5, docs/research/08_bots_humanlike.md §3.6/§3.7) : rôles Hardpoint
## de bot lus depuis `bot_knowledge.hp_holds` (BOT-22/22B) —
##  - 2 positions de TENUE distinctes DANS la zone, au moins 3 m d'écart,
##    jamais le centre commun de la zone ;
##  - 1 ou 2 bots en SURVEILLANCE (positions `hp_holds[...].watch`) ;
##  - 1 SEUL bot part en PRÉ-ROTATION vers la zone SUIVANTE pendant les 15 s
##    de l'aperçu (`HardpointMode.BOT_PREROTATE_LEAD`) — les autres tiennent
##    la zone ACTUELLE jusqu'à la rotation réelle ;
##  - rôle stable au moins 10 s (aucun évènement ne doit le faire changer plus
##    souvent) ;
##  - jamais 2 bots (d'une même équipe, ids CONSÉCUTIFS — cas normal du
##    remplissage d'équipe, même convention que TDM T1/BOT-23) sur la même
##    position.
## L'acceptance B18 (bot_bench.gd, phase `hp_veteran`, 180 s simulées) est
## hors de mon périmètre (tools/bot_bench.gd n'y est pas) : ce fichier
## couvre la logique PURE de `HardpointMode._compute_bot_goal` qu'elle mesure
## en jeu (nombre de bots dans la zone, espacement, surveillance, délai
## d'arrivée après rotation — tous des conséquences directes des rôles
## vérifiés ici).
##
## Style : une fixture LOCALE (`_FixtureHardpoint`, `_bot_knowledge()`
## surchargée) pour la logique de rôle/pré-rotation, DÉCOUPLÉE des
## coordonnées réelles de Wasteland — même patron que `_CountingMode`/
## `_ClockedTDMMode` de tests/ai/test_bot_goals.gd (hors de ma liste de
## fichiers, non modifié). Un dernier test grounde la même logique contre les
## données RÉELLES `WastelandBots.data()["bot_knowledge"]`.
extends GdUnitTestSuite


# ======================================================================
#  Double de test : connaissance de carte FIXÉE, 2 zones Hardpoint "P0"
#  (courante) / "P1" (suivante), coordonnées arbitraires mais contrôlées.
# ======================================================================
class _FixtureHardpoint extends HardpointMode:
	var fixture_bk: Dictionary = {}
	func _bot_knowledge() -> Dictionary:
		return {"bot_knowledge": fixture_bk}


const _ZONE_P0_HOLD := [Vector3(0, 0, 0), Vector3(5, 0, 0)]
const _ZONE_P0_WATCH := [Vector3(10, 0, 0), Vector3(-10, 0, 0), Vector3(0, 0, 10)]
const _ZONE_P1_HOLD := [Vector3(100, 0, 0), Vector3(105, 0, 0)]
const _ZONE_P1_WATCH := [Vector3(110, 0, 0), Vector3(90, 0, 0)]

## bot_id consécutifs (cas normal d'un remplissage d'équipe, BOT-23) —
## restes mod 4 : 9001->1 (tenue #2), 9002->2 (surveillance #1),
## 9003->3 (surveillance #2 / créneau de pré-rotation), 9004->0 (tenue #1).
const _BOT_HOLD0 := 9004
const _BOT_HOLD1 := 9001
const _BOT_WATCH0 := 9002
const _BOT_PREROTATE := 9003


func _fixture_bk() -> Dictionary:
	return {
		"hp_holds": [
			{"zone": "P0", "hold": _ZONE_P0_HOLD.duplicate(), "watch": _ZONE_P0_WATCH.duplicate()},
			{"zone": "P1", "hold": _ZONE_P1_HOLD.duplicate(), "watch": _ZONE_P1_WATCH.duplicate()},
		],
	}


func _centroid(pts: Array) -> Vector3:
	var c := Vector3.ZERO
	for p in pts:
		c += (p as Vector3)
	return c / pts.size()


## Construit un HardpointMode fixture, 2 points de rotation (P0 courante,
## P1 suivante), zone Area3D positionnée sur le centroïde de P0 (appariement
## par proximité, voir `HardpointMode._hp_holds_index_near`).
func _make_mode(rotate_interval: float = 45.0) -> _FixtureHardpoint:
	var mode := _FixtureHardpoint.new()
	mode.fixture_bk = _fixture_bk()
	mode.rotate_interval = rotate_interval
	add_child(mode)
	auto_free(mode)

	var p0 := Node3D.new()
	p0.position = _centroid(_ZONE_P0_HOLD)
	var p1 := Node3D.new()
	p1.position = _centroid(_ZONE_P1_HOLD)
	mode.add_child(p0)
	mode.add_child(p1)
	mode._points = [p0, p1]
	mode._point_index = 0

	var zone := Area3D.new()
	zone.position = p0.position
	mode.add_child(zone)
	mode._zone = zone
	return mode


# ======================================================================
#  Repli propre (LD-25, inchangé) : sans bot_knowledge/hp_holds, le centre
#  commun de la zone reste le but, quel que soit bot_id.
# ======================================================================
func test_falls_back_to_the_shared_zone_center_without_hp_holds_data() -> void:
	var mode := HardpointMode.new()
	add_child(mode)
	auto_free(mode)
	var zone := Area3D.new()
	zone.position = Vector3(7, 0, 3)
	mode.add_child(zone)
	mode._zone = zone

	for bot_id in [9001, 9002, 9003, 9004]:
		var goal: Vector3 = mode._compute_bot_goal(0, bot_id, Vector3.ZERO)
		assert_bool(goal.is_equal_approx(zone.position)).append_failure_message(
			"sans hp_holds, le repli doit rester le centre commun de la zone (bot %d)" % bot_id
		).is_true()


# ======================================================================
#  T5 : 2 positions de tenue distinctes dans la zone, >= 3 m d'écart,
#  jamais le centre commun.
# ======================================================================
func test_two_hold_slots_are_distinct_positions_at_least_3m_apart_never_the_center() -> void:
	var mode := _make_mode()

	var goal_hold0: Vector3 = mode._compute_bot_goal(0, _BOT_HOLD0, Vector3.ZERO)
	var goal_hold1: Vector3 = mode._compute_bot_goal(0, _BOT_HOLD1, Vector3.ZERO)

	assert_bool(goal_hold0.is_equal_approx(_ZONE_P0_HOLD[0])).append_failure_message(
		"BOT-24 : le 1er créneau de tenue doit viser hp_holds[P0].hold[0]"
	).is_true()
	assert_bool(goal_hold1.is_equal_approx(_ZONE_P0_HOLD[1])).append_failure_message(
		"BOT-24 : le 2e créneau de tenue doit viser hp_holds[P0].hold[1]"
	).is_true()
	assert_bool(goal_hold0.is_equal_approx(mode._zone.global_position)).append_failure_message(
		"T5 : un bot en tenue ne doit jamais viser le centre COMMUN de la zone"
	).is_false()
	assert_bool(goal_hold1.is_equal_approx(goal_hold0)).append_failure_message(
		"T5 : les 2 positions de tenue doivent être DISTINCTES"
	).is_false()
	assert_float(goal_hold0.distance_to(goal_hold1)).append_failure_message(
		"T5 : les 2 positions de tenue doivent être espacées d'au moins 3 m"
	).is_greater_equal(3.0)


# ======================================================================
#  T5 : 1 ou 2 bots en surveillance, sur des positions "watch" distinctes
#  de la tenue et l'une de l'autre — hors fenêtre de pré-rotation.
# ======================================================================
func test_watch_slots_target_distinct_watch_points_outside_the_prerotate_window() -> void:
	var mode := _make_mode()
	mode._rotate_timer = 0.0  # 45 s restantes : bien hors de la fenêtre (15 s).

	var goal_watch0: Vector3 = mode._compute_bot_goal(0, _BOT_WATCH0, Vector3.ZERO)
	var goal_watch1: Vector3 = mode._compute_bot_goal(0, _BOT_PREROTATE, Vector3.ZERO)

	assert_bool(goal_watch0.is_equal_approx(_ZONE_P0_WATCH[0])).append_failure_message(
		"BOT-24 : le 1er créneau de surveillance doit viser hp_holds[P0].watch[0]"
	).is_true()
	assert_bool(goal_watch1.is_equal_approx(_ZONE_P0_WATCH[1])).append_failure_message(
		"BOT-24 : le 2e créneau de surveillance doit viser hp_holds[P0].watch[1] hors pré-rotation"
	).is_true()
	assert_bool(goal_watch0.is_equal_approx(goal_watch1)).append_failure_message(
		"T5 : les positions de surveillance doivent être DISTINCTES entre elles"
	).is_false()


# ======================================================================
#  T5 : "1 bot part vers la zone suivante 15 s avant la rotation" — SEUL le
#  créneau désigné bascule ; les autres tiennent la zone ACTUELLE.
# ======================================================================
func test_only_one_designated_bot_prerotates_within_15s_others_keep_holding_the_current_zone() -> void:
	var mode := _make_mode(45.0)
	var next_zone_pos: Vector3 = (mode._points[1] as Node3D).global_position

	mode._rotate_timer = 25.0  # 20 s restantes : hors de la fenêtre (15 s).
	var far_prerotate: Vector3 = mode._compute_bot_goal(0, _BOT_PREROTATE, Vector3.ZERO)
	var far_hold: Vector3 = mode._compute_bot_goal(0, _BOT_HOLD0, Vector3.ZERO)
	assert_bool(far_prerotate.is_equal_approx(_ZONE_P0_WATCH[1])).append_failure_message(
		"à 20 s de la rotation (hors fenêtre), le créneau de pré-rotation doit encore surveiller"
	).is_true()

	mode._rotate_timer = 33.0  # 12 s restantes : DANS la fenêtre de 15 s (pas celle de 10 s du HUD).
	var near_prerotate: Vector3 = mode._compute_bot_goal(0, _BOT_PREROTATE, Vector3.ZERO)
	var near_hold: Vector3 = mode._compute_bot_goal(0, _BOT_HOLD0, Vector3.ZERO)
	var near_watch0: Vector3 = mode._compute_bot_goal(0, _BOT_WATCH0, Vector3.ZERO)

	assert_bool(near_prerotate.is_equal_approx(next_zone_pos)).append_failure_message(
		"T5 : à moins de 15 s de la rotation, LE bot désigné doit basculer sur la zone SUIVANTE"
	).is_true()
	assert_bool(near_prerotate.is_equal_approx(far_prerotate)).append_failure_message(
		"le créneau de pré-rotation doit avoir changé de but en entrant dans la fenêtre"
	).is_false()
	assert_bool(near_hold.is_equal_approx(far_hold)).append_failure_message(
		"T5 (\"1 bot\") : un bot en TENUE ne doit PAS bouger avant la rotation réelle"
	).is_true()
	assert_bool(near_watch0.is_equal_approx(_ZONE_P0_WATCH[0])).append_failure_message(
		"T5 (\"1 bot\") : l'AUTRE bot en surveillance doit rester sur sa position actuelle"
	).is_true()


func test_prerotate_window_is_15s_not_the_10s_hud_preview() -> void:
	var mode := _make_mode(45.0)
	var next_zone_pos: Vector3 = (mode._points[1] as Node3D).global_position

	mode._rotate_timer = 30.0  # 15 s restantes pile : entrée dans la fenêtre bot.
	var at_15s: Vector3 = mode._compute_bot_goal(0, _BOT_PREROTATE, Vector3.ZERO)
	assert_bool(at_15s.is_equal_approx(next_zone_pos)).append_failure_message(
		"BOT_PREROTATE_LEAD = 15 s (T5) : la bascule doit être active dès 15 s restantes, pas seulement 10 s"
	).is_true()

	mode._rotate_timer = 29.0  # 16 s restantes : encore hors fenêtre.
	var at_16s: Vector3 = mode._compute_bot_goal(0, _BOT_PREROTATE, Vector3.ZERO)
	assert_bool(at_16s.is_equal_approx(next_zone_pos)).append_failure_message(
		"à 16 s restantes, encore hors de la fenêtre de 15 s : le créneau doit encore surveiller"
	).is_false()


# ======================================================================
#  Rôle stable au moins 10 s (BOT-24) : ni la tenue/surveillance hors
#  fenêtre, ni la pré-rotation à l'intérieur de sa fenêtre de 15 s, ne
#  doivent changer sur un simple écoulement de quelques secondes.
# ======================================================================
func test_roles_stay_identical_across_a_10s_span_outside_any_rotation_event() -> void:
	var mode := _make_mode(45.0)
	mode._rotate_timer = 0.0  # 45 s restantes.
	var goals_t0 := {
		_BOT_HOLD0: mode._compute_bot_goal(0, _BOT_HOLD0, Vector3.ZERO),
		_BOT_HOLD1: mode._compute_bot_goal(0, _BOT_HOLD1, Vector3.ZERO),
		_BOT_WATCH0: mode._compute_bot_goal(0, _BOT_WATCH0, Vector3.ZERO),
		_BOT_PREROTATE: mode._compute_bot_goal(0, _BOT_PREROTATE, Vector3.ZERO),
	}

	mode._rotate_timer = 10.0  # 10 s plus tard, toujours hors de toute fenêtre/rotation.
	for bot_id in goals_t0.keys():
		var again: Vector3 = mode._compute_bot_goal(0, bot_id, Vector3.ZERO)
		assert_bool(again.is_equal_approx(goals_t0[bot_id])).append_failure_message(
			"BOT-24 : le rôle du bot %d doit rester stable sur 10 s sans évènement" % bot_id
		).is_true()


func test_prerotating_role_stays_identical_across_a_10s_span_inside_its_15s_window() -> void:
	var mode := _make_mode(45.0)
	var next_zone_pos: Vector3 = (mode._points[1] as Node3D).global_position

	mode._rotate_timer = 30.0  # 15 s restantes : entrée dans la fenêtre.
	var goal_start: Vector3 = mode._compute_bot_goal(0, _BOT_PREROTATE, Vector3.ZERO)
	mode._rotate_timer = 40.0  # 5 s restantes : 10 s plus tard, encore dans la fenêtre.
	var goal_later: Vector3 = mode._compute_bot_goal(0, _BOT_PREROTATE, Vector3.ZERO)

	assert_bool(goal_start.is_equal_approx(next_zone_pos)).is_true()
	assert_bool(goal_later.is_equal_approx(goal_start)).append_failure_message(
		"le créneau de pré-rotation doit rester stable (zone suivante) pendant toute sa fenêtre de 15 s"
	).is_true()


# ======================================================================
#  Jamais 2 bots (d'une même équipe, ids consécutifs) sur la même position.
# ======================================================================
func test_a_full_team_of_4_consecutive_bots_never_share_a_position() -> void:
	var mode := _make_mode()
	mode._rotate_timer = 0.0  # hors de toute fenêtre de pré-rotation.

	var goals: Array = []
	for bot_id in [9001, 9002, 9003, 9004]:
		goals.append(mode._compute_bot_goal(0, bot_id, Vector3.ZERO))

	for i in goals.size():
		for j in range(i + 1, goals.size()):
			assert_bool((goals[i] as Vector3).is_equal_approx(goals[j] as Vector3)).append_failure_message(
				"jamais 2 bots d'une même équipe sur la même position (bots #%d et #%d : %s)" % [i, j, goals]
			).is_false()


# ======================================================================
#  Intégration contre les données RÉELLES de Wasteland — RETIRÉE (2026-09-26,
#  « fais la carte block que je puisse la tester in game » — v7 greybox, TDM
#  seul, voir l'en-tête de `scripts/levels/maps/layouts/wasteland.gd`) :
#  Wasteland ne déclare plus de zones Hardpoint du tout (`WastelandLayout
#  .data()` n'a plus de clé "hardpoints", `WastelandBots.gd` n'a plus de
#  `_bk_hp_holds()`/`hp_hold_points` réels — `bot_knowledge.hp_holds` vaut
#  `[]`). Les deux tests qui vivaient ici (« 2 créneaux à 3 m contre les
#  hold réels », « les hold réels restent dans la boîte Hardpoint réelle »)
#  n'ont donc plus de sujet : la logique GÉNÉRIQUE qu'ils exerçaient
#  (espacement des créneaux, boîte de zone) reste couverte par les fixtures
#  ci-dessus (`test_two_hold_slots_are_distinct_positions_at_least_3m_apart_
#  never_the_center`, etc.), découplées de toute carte réelle. Écart connu,
#  signalé au rendu de tâche : `MapCatalog.gd` annonce encore Wasteland pour
#  "hardpoint" (hors de mon périmètre de fichiers cette manche).
# ======================================================================


# ======================================================================
#  Diagnostic 2026-09-25 (banc hp_veteran Wasteland, occupation minimale
#  0,2 % malgré BOT-24/BOT-30) : les rôles ci-dessus étaient justes, mais
#  BotBrain ne les suivait presque jamais — un tir ENTENDU (<= 22 m) primait
#  sur `bot_goal_for` (58 % des ticks vivants) et un combat faisait
#  poursuivre la cible hors de la zone (29 %). Contrat : en Hardpoint, tout
#  bot tient sa position ; le bruit ne dirige que le regard, et il se bat
#  DEPUIS son point. Les autres modes gardent l'enquête et la poursuite.
# ======================================================================
func test_every_hardpoint_role_holds_its_position() -> void:
	var mode := _make_mode(45.0)
	for bot_id in [_BOT_HOLD0, _BOT_HOLD1, _BOT_WATCH0, _BOT_PREROTATE]:
		for team in [0, 1]:
			assert_bool(mode.bot_holds_position(team, bot_id)).append_failure_message(
				"Hardpoint (T5) : le bot %d (équipe %d) doit tenir sa position (tenue, surveillance ou pré-rotation)" % [bot_id, team]
			).is_true()


func test_hardpoint_without_zone_holds_nothing() -> void:
	var mode := HardpointMode.new()
	add_child(mode)
	auto_free(mode)
	assert_bool(mode.bot_holds_position(0, _BOT_HOLD0)).append_failure_message(
		"sans zone Hardpoint câblée, aucune position à tenir"
	).is_false()


func test_arena_and_round_modes_keep_investigating_and_chasing() -> void:
	var modes := {"GameMode": GameMode.new(), "TDMMode": TDMMode.new()}
	for mode_name in modes:
		var mode: GameMode = modes[mode_name]
		add_child(mode)
		auto_free(mode)
		assert_bool(mode.bot_holds_position(0, _BOT_HOLD0)).append_failure_message(
			"%s ne fait tenir aucune position : l'enquête au bruit et la poursuite restent actives" % mode_name
		).is_false()


func test_heard_gunfire_never_diverts_a_bot_that_holds_a_position() -> void:
	assert_bool(BotBrain.hearing_diverts_goal(true, true)).append_failure_message(
		"un tir entendu ne doit pas faire quitter sa position à un bot qui la tient"
	).is_false()
	assert_bool(BotBrain.hearing_diverts_goal(true, false)).append_failure_message(
		"hors position à tenir, un tir entendu reste un but d'enquête (inchangé)"
	).is_true()
	assert_bool(BotBrain.hearing_diverts_goal(false, false)).is_false()
	assert_bool(BotBrain.hearing_diverts_goal(false, true)).is_false()


func test_a_bot_that_holds_a_position_fights_from_it_instead_of_chasing() -> void:
	assert_bool(BotBrain.chases_combat_target(true, true)).append_failure_message(
		"en combat, un bot qui tient une position vise depuis son point au lieu de poursuivre sa cible"
	).is_false()
	assert_bool(BotBrain.chases_combat_target(true, false)).append_failure_message(
		"hors position à tenir, le combat navigue toujours vers la cible (inchangé)"
	).is_true()
	assert_bool(BotBrain.chases_combat_target(false, false)).is_false()
	assert_bool(BotBrain.chases_combat_target(false, true)).is_false()
