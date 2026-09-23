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
	for a in ["move_left", "move_right", "move_forward", "move_back", "jump", "crouch", "walk",
			"dive", "fire", "aim", "reload", "pickup", "drop", "weapon_1", "weapon_2",
			"weapon_next", "weapon_prev", "ability_c", "ability_q", "ability_e", "ultimate"]:
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


func test_ability_from_presses_none() -> void:
	assert_str(PlayerInput.ability_from_presses(false, false, false, false)).is_equal("")


func test_ability_from_presses_c() -> void:
	assert_str(PlayerInput.ability_from_presses(true, false, false, false)).is_equal("C")


func test_ability_from_presses_q() -> void:
	assert_str(PlayerInput.ability_from_presses(false, true, false, false)).is_equal("Q")


func test_ability_from_presses_e() -> void:
	assert_str(PlayerInput.ability_from_presses(false, false, true, false)).is_equal("E")


func test_ability_from_presses_ultimate_is_x() -> void:
	assert_str(PlayerInput.ability_from_presses(false, false, false, true)).is_equal("X")


# ---- gather_from_devices() : mappage Input -> champs (état "held", fiable
# en headless ; les actions "just_pressed" dépendent d'une transition de
# frame qu'un test unitaire sans boucle ne peut pas fiablement simuler, donc
# non couvertes ici — le mappage discret correspondant est testé ci-dessus,
# sur `slot_from_presses`/`ability_from_presses` directement). ----

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


func test_crouch_and_walk_held_track_action_pressed() -> void:
	Input.action_press("crouch")
	Input.action_press("walk")
	_input.gather_from_devices()
	assert_bool(_input.crouch_held).is_true()
	assert_bool(_input.walk_held).is_true()


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
	assert_str(_input.ability_pressed).is_equal("")
	assert_float(_input.move.x).is_equal_approx(0.0, 0.0001)
