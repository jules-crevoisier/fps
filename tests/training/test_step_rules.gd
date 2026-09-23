## test_step_rules.gd
## Spec (contract-r4a.md, R4-TRAIN #1) : détection PURE de chaque étape du
## parcours de mouvement — transitions d'état + seuils de vitesse. Aucune
## scène/joueur nécessaire (StepRules ne dépend que de String/float/Vector3).
extends GdUnitTestSuite

# ---- sprint ----

func test_sprint_step_completes_near_sprint_speed() -> void:
	assert_bool(StepRules.is_sprint_step(8.0, 8.2)).is_true()

func test_sprint_step_not_completed_when_too_slow() -> void:
	assert_bool(StepRules.is_sprint_step(3.0, 8.2)).is_false()

# ---- slide ----

func test_slide_step_from_sprint() -> void:
	assert_bool(StepRules.is_slide_step("Sprint", "Slide")).is_true()

func test_slide_step_from_walk() -> void:
	assert_bool(StepRules.is_slide_step("Walk", "Slide")).is_true()

func test_slide_step_ignores_unrelated_transition() -> void:
	assert_bool(StepRules.is_slide_step("Air", "Roll")).is_false()

func test_slide_step_ignores_wrong_destination() -> void:
	assert_bool(StepRules.is_slide_step("Sprint", "Air")).is_false()

# ---- slide-cancel ----

func test_slide_cancel_to_sprint() -> void:
	assert_bool(StepRules.is_slide_cancel_step("Slide", "Sprint")).is_true()

func test_slide_cancel_to_idle() -> void:
	assert_bool(StepRules.is_slide_cancel_step("Slide", "Idle")).is_true()

func test_slide_cancel_rejects_crouch_finish() -> void:
	# Tenir Ctrl jusqu'au bout de la glissade => Crouch, PAS un cancel.
	assert_bool(StepRules.is_slide_cancel_step("Slide", "Crouch")).is_false()

func test_slide_cancel_rejects_other_origin() -> void:
	assert_bool(StepRules.is_slide_cancel_step("Sprint", "Idle")).is_false()

# ---- slide-jump ----

func test_slide_jump_step_requires_flag() -> void:
	assert_bool(StepRules.is_slide_jump_step("Slide", "Air", true)).is_true()

func test_slide_jump_step_rejects_without_flag() -> void:
	# Glisser hors du sol (piste qui s'arrête) : même transition, pas un saut.
	assert_bool(StepRules.is_slide_jump_step("Slide", "Air", false)).is_false()

func test_slide_jump_step_rejects_wrong_origin() -> void:
	assert_bool(StepRules.is_slide_jump_step("Sprint", "Air", true)).is_false()

# ---- landing-roll (annule le stun) ----

func test_landing_roll_step_from_air() -> void:
	assert_bool(StepRules.is_landing_roll_step("Air", "Roll")).is_true()

func test_landing_roll_step_rejects_from_dive() -> void:
	# Dive -> Roll est la fin NORMALE d'une plongée (voir is_dive_gap_step),
	# pas la roulade d'atterrissage anti-stun.
	assert_bool(StepRules.is_landing_roll_step("Dive", "Roll")).is_false()

# ---- dive gap (plongée au-dessus d'un vide de 8 m) ----

func test_dive_gap_step_completes_over_8m() -> void:
	var start := Vector3(0, 3, -60)
	var end := Vector3(0, 3, -68)
	assert_bool(StepRules.is_dive_gap_step("Dive", "Roll", start, end)).is_true()

func test_dive_gap_step_rejects_short_hop() -> void:
	var start := Vector3(0, 3, -60)
	var end := Vector3(0, 3, -62)
	assert_bool(StepRules.is_dive_gap_step("Dive", "Roll", start, end)).is_false()

func test_dive_gap_step_rejects_wrong_transition() -> void:
	var start := Vector3(0, 3, -60)
	var end := Vector3(0, 3, -70)
	assert_bool(StepRules.is_dive_gap_step("Air", "Roll", start, end)).is_false()

func test_dive_gap_step_custom_threshold() -> void:
	var start := Vector3.ZERO
	var end := Vector3(0, 0, -5)
	assert_bool(StepRules.is_dive_gap_step("Dive", "Roll", start, end, 4.0)).is_true()
	assert_bool(StepRules.is_dive_gap_step("Dive", "Roll", start, end, 6.0)).is_false()

# ---- air-strafe (vitesse gagnée en l'air) ----

func test_air_strafe_step_completes_above_sprint() -> void:
	assert_bool(StepRules.is_air_strafe_step("Air", 10.0, 8.2)).is_true()

func test_air_strafe_step_rejects_at_sprint_speed() -> void:
	assert_bool(StepRules.is_air_strafe_step("Air", 8.2, 8.2)).is_false()

func test_air_strafe_step_rejects_wrong_state() -> void:
	assert_bool(StepRules.is_air_strafe_step("Sprint", 20.0, 8.2)).is_false()

# ---- libellés ----

func test_format_text_substitutes_action_label() -> void:
	var text := StepRules.format_text("slide", "MAJ GAUCHE")
	assert_str(text).contains("MAJ GAUCHE")

func test_format_text_without_action_returns_text_unchanged() -> void:
	var text := StepRules.format_text("sprint", "peu importe")
	assert_str(text).not_contains("%s")
	assert_str(text).is_equal(StepRules.STEPS["sprint"]["text"])

func test_action_for_known_step() -> void:
	assert_str(StepRules.action_for("dive_gap")).is_equal("dive")

func test_action_for_step_without_action() -> void:
	assert_str(StepRules.action_for("air_strafe")).is_equal("")

func test_step_ids_cover_all_labels() -> void:
	for id in StepRules.STEP_IDS:
		assert_bool(StepRules.STEPS.has(id)).is_true()
