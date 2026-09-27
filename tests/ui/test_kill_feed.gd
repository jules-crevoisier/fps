## test_kill_feed.gd
## Spec (contrat lead 2026-09-27, HUD en jeu, point 5 "KillFeed") : haut-droite,
## 5 entrées MAX, chacune dure 5 s puis fondu 0.3 s, nouvelle entrée glissée
## depuis la droite ; plaque PAPIER inclinée (JAUNE si le joueur local est le
## tueur), nom du tueur en couleur d'équipe profonde, silhouette de l'arme
## (inconnue -> pictogramme "kill"), pictogramme headshot si `headshot`, nom
## de la victime.
extends GdUnitTestSuite

const KillFeed := preload("res://scripts/ui/hud/KillFeed.gd")


func _feed() -> KillFeed:
	var f: KillFeed = auto_free(KillFeed.new())
	add_child(f)
	return f


# ---- fade_alpha (pure) ----

func test_fade_alpha_is_opaque_during_hold() -> void:
	assert_float(KillFeed.fade_alpha(0.0)).is_equal_approx(1.0, 0.001)
	assert_float(KillFeed.fade_alpha(4.9)).is_equal_approx(1.0, 0.001)


func test_fade_alpha_fades_out_after_hold() -> void:
	assert_float(KillFeed.fade_alpha(5.0)).is_equal_approx(1.0, 0.001)
	assert_float(KillFeed.fade_alpha(5.15)).is_equal_approx(0.5, 0.05)
	assert_float(KillFeed.fade_alpha(5.3)).is_equal_approx(0.0, 0.001)


func test_fade_alpha_never_negative_past_expiry() -> void:
	assert_float(KillFeed.fade_alpha(10.0)).is_equal_approx(0.0, 0.001)


func test_is_expired() -> void:
	assert_bool(KillFeed.is_expired(5.29)).is_false()
	assert_bool(KillFeed.is_expired(5.31)).is_true()


# ---- trim_to_cap (pure) ----

func test_trim_to_cap_keeps_at_most_five() -> void:
	var entries := [1, 2, 3, 4, 5, 6, 7]
	var trimmed := KillFeed.trim_to_cap(entries, 5)
	assert_int(trimmed.size()).is_equal(5)
	assert_int(trimmed[0]).is_equal(3)
	assert_int(trimmed[4]).is_equal(7)


func test_trim_to_cap_noop_under_cap() -> void:
	var entries := [1, 2]
	assert_int(KillFeed.trim_to_cap(entries, 5).size()).is_equal(2)


# ---- nœuds ----

func test_add_kill_creates_an_entry() -> void:
	var f := _feed()
	f.add_kill("Joueur", "Crapaud", 0, 0, "RAVAGE", false, false)
	assert_int(f._entries.size()).is_equal(1)


func test_add_kill_caps_at_five_entries() -> void:
	var f := _feed()
	for i in 7:
		f.add_kill("K%d" % i, "V%d" % i, 0, 0, "RAVAGE", false, false)
	assert_int(f._entries.size()).is_equal(5)


func test_add_kill_by_local_player_uses_yellow_plate() -> void:
	var f := _feed()
	f.add_kill("Joueur", "Crapaud", 0, 0, "RAVAGE", false, true)
	var entry: Dictionary = f._entries[0]
	var sb: StyleBoxComic = (entry["root"] as PanelContainer).get_theme_stylebox("panel")
	assert_bool(sb.fill.is_equal_approx(UiTokens.YELLOW)).is_true()


func test_add_kill_by_other_uses_paper_plate() -> void:
	var f := _feed()
	f.add_kill("Rainette", "Têtard", 1, 0, "RAVAGE", false, false)
	var entry: Dictionary = f._entries[0]
	var sb: StyleBoxComic = (entry["root"] as PanelContainer).get_theme_stylebox("panel")
	assert_bool(sb.fill.is_equal_approx(UiTokens.PAPER)).is_true()


func test_add_kill_shows_headshot_picto_only_when_headshot() -> void:
	var f := _feed()
	f.add_kill("Joueur", "Crapaud", 0, 0, "RAVAGE", true, false)
	var entry: Dictionary = f._entries[0]
	assert_bool((entry["headshot_icon"] as Control).visible).is_true()

	f.add_kill("Joueur", "Crapaud", 0, 0, "RAVAGE", false, false)
	var entry2: Dictionary = f._entries[0]
	assert_bool((entry2["headshot_icon"] as Control).visible).is_false()


func test_add_kill_falls_back_to_kill_picto_for_unknown_weapon() -> void:
	var f := _feed()
	f.add_kill("Joueur", "Crapaud", 0, 0, "Une capacité", false, false)
	var entry: Dictionary = f._entries[0]
	assert_str((entry["weapon_icon"] as TextureRect).texture.resource_path.get_file().get_basename()).is_equal("kill")
