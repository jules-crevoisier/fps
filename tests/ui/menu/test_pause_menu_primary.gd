## Retour de test 2026-09-28 : choisir l'arme principale depuis le menu Échap en pleine partie
## (appliquée à la prochaine réapparition, comme l'écran de mort).
extends GdUnitTestSuite

const PauseMenuScript := preload("res://scripts/ui/menu/PauseMenu.gd")


func _menu() -> PauseMenu:
	var m: PauseMenu = auto_free(PauseMenuScript.new())
	add_child(m)
	return m


func _with_saved_selected_primary(callback: Callable) -> void:
	var before := Settings.selected_primary
	callback.call()
	Settings.selected_primary = before


func _buttons(m: PauseMenu) -> Array:
	var out: Array = []
	for b in m._primary_row.get_children():
		if b is Button:
			out.append(b)
	return out


func test_pause_menu_lists_every_available_primary_in_order() -> void:
	var m := _menu()
	var ids := Loadout.available_primary_ids()
	var buttons := _buttons(m)
	assert_int(buttons.size()).is_equal(ids.size())
	for i in ids.size():
		assert_str((buttons[i] as Button).text).is_equal(Loadout.name_for_primary_id(ids[i]).to_upper())   # comic_button met en capitales


func test_choosing_in_the_pause_menu_persists_the_next_primary() -> void:
	_with_saved_selected_primary(func() -> void:
		var m := _menu()
		m._on_primary_chosen("Aiguille")
		assert_str(Settings.selected_primary).is_equal("Aiguille")
	)


func test_the_chosen_primary_is_highlighted_after_choosing() -> void:
	_with_saved_selected_primary(func() -> void:
		var m := _menu()
		m._on_primary_chosen("Fracas")
		for b in _buttons(m):
			var sb := (b as Button).get_theme_stylebox("normal") as StyleBoxComic
			var expected := UiTokens.YELLOW if (b as Button).text == "FRACAS" else UiTokens.PAPER
			assert_bool(sb.fill.is_equal_approx(expected)).append_failure_message((b as Button).text).is_true()
	)
