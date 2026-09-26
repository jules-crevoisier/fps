## test_player_input.gd
## Spec (contract-r3.md, R3-IN, interfaces "PlayerInput") : les parties PURES
## de PlayerInput — le mappage discret slot/capacité (indépendant du
## singleton Input) et `gather_from_devices` (mappage Input -> champs, SANS
## décision "dois-je lire ?" : ce gating vit dans `_physics_process`, qui
## dépend de `Input.mouse_mode`, non fiable en tête headless sans fenêtre
## réelle — voir PlayerInput.gd). `gather_from_devices` est piloté en tapant
## directement sur le singleton Input (Input.action_press/action_release,
## standard headless). N'a besoin d'aucune scène/joueur : `player` reste
## null, non utilisé par `gather_from_devices`/`clear`.
extends GdUnitTestSuite

var _input: PlayerInput


func before_test() -> void:
	_input = auto_free(PlayerInput.new())
	_release_all()


func after_test() -> void:
	_release_all()


func _release_all() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back", "jump", "crouch", "sprint",
			"dive", "fire", "aim", "reload", "pickup", "drop", "weapon_1", "weapon_2",
			"weapon_next", "weapon_prev"]:
		Input.action_release(a)


# ---- Mappages purs (aucune dépendance au singleton Input) ----

func test_slot_from_presses_none() -> void:
	assert_int(PlayerInput.slot_from_presses(false, false)).is_equal(-1)


func test_slot_from_presses_first_slot() -> void:
	assert_int(PlayerInput.slot_from_presses(true, false)).is_equal(0)


func test_slot_from_presses_second_slot() -> void:
	assert_int(PlayerInput.slot_from_presses(false, true)).is_equal(1)


func test_slot_from_presses_prefers_first_on_conflict() -> void:
	assert_int(PlayerInput.slot_from_presses(true, true)).is_equal(0)


# ---- gather_from_devices() : mappage Input -> champs (état "held", fiable
# en headless ; les actions "just_pressed" dépendent d'une transition de
# frame qu'un test unitaire sans boucle ne peut pas fiablement simuler, donc
# non couvertes ici — le mappage discret correspondant est testé ci-dessus,
# sur `slot_from_presses` directement). ----

func test_move_vector_forward() -> void:
	Input.action_press("move_forward")
	_input.gather_from_devices()
	assert_float(_input.move.y).is_less(0.0)


func test_fire_held_tracks_action_pressed() -> void:
	Input.action_press("fire")
	_input.gather_from_devices()
	assert_bool(_input.fire_held).is_true()
	Input.action_release("fire")
	_input.gather_from_devices()
	assert_bool(_input.fire_held).is_false()


func test_aim_held_tracks_action_pressed() -> void:
	Input.action_press("aim")
	_input.gather_from_devices()
	assert_bool(_input.aim_held).is_true()


func test_crouch_held_tracks_action_pressed_and_walking_is_the_default() -> void:
	# Contrat 2026-09-26 : on MARCHE par défaut, le sprint est une bascule (touche "sprint").
	Input.action_press("crouch")
	_input.gather_from_devices()
	assert_bool(_input.crouch_held).is_true()
	assert_bool(_input.walk_held).is_true()


# ---- Sprint façon Apex (fonctions pures) ----

const FWD := Vector2(0.0, -1.0)

func test_sprint_press_starts_sprinting() -> void:
	assert_bool(PlayerInput.resolve_sprint_toggle(false, true, FWD)).is_true()


func test_sprint_stays_on_without_holding_the_key() -> void:
	assert_bool(PlayerInput.resolve_sprint_toggle(true, false, FWD)).is_true()
	assert_bool(PlayerInput.resolve_sprint_toggle(true, false, Vector2(1.0, 0.0))).is_true()


func test_second_press_or_full_stop_ends_sprinting() -> void:
	assert_bool(PlayerInput.resolve_sprint_toggle(true, true, FWD)).is_false()
	assert_bool(PlayerInput.resolve_sprint_toggle(true, false, Vector2.ZERO)).is_false()


func test_aiming_firing_or_not_going_forward_only_suspends_sprint() -> void:
	assert_bool(PlayerInput.sprint_suppressed(FWD, true, false)).is_true()
	assert_bool(PlayerInput.sprint_suppressed(FWD, false, true)).is_true()
	assert_bool(PlayerInput.sprint_suppressed(Vector2(1.0, 0.0), false, false)).is_true()
	assert_bool(PlayerInput.sprint_suppressed(Vector2(0.0, 1.0), false, false)).is_true()


func test_forward_and_diagonals_sprint_freely() -> void:
	assert_bool(PlayerInput.sprint_suppressed(FWD, false, false)).is_false()
	assert_bool(PlayerInput.sprint_suppressed(Vector2(0.7, -0.7), false, false)).is_false()


# ---- clear() : remet tout à l'état neutre (souris relâchée, mort, bot...) ----

func test_clear_resets_every_field() -> void:
	Input.action_press("fire")
	Input.action_press("aim")
	_input.gather_from_devices()
	_input.clear()
	assert_bool(_input.fire_held).is_false()
	assert_bool(_input.fire_pressed).is_false()
	assert_bool(_input.aim_held).is_false()
	assert_int(_input.weapon_slot_pressed).is_equal(-1)
	assert_float(_input.move.x).is_equal_approx(0.0, 0.0001)
