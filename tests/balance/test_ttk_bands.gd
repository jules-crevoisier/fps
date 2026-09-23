## test_ttk_bands.gd
## Spec (contract-r2.md, "R-B2 balance — acceptance" + docs/ROADMAP.md §4) : TTK et
## niche des 10 armes (7 existantes + 3 nouvelles), HP=100. Pur calcul (WeaponMath +
## WeaponDatabase), aucune dépendance à l'arbre de scène.
##
## Règle de niche (contract): "every primary is strictly best in at least one band
## among [0-6],[6-15],[15-30],[30-50],[50+] m, evaluated at the band midpoint with
## body shots". Avec 8 armes principales ("primaries" = tout sauf poing) et 5
## bandes, un poste de "meilleure" par bande ne peut avoir qu'UN seul titulaire :
## il est mathématiquement impossible que 8 armes soient chacune strictement les
## meilleures d'au moins une bande quand il n'existe que 5 bandes (5 gagnants
## possibles maximum). On applique donc la règle littéralement aux 5 armes dont le
## rôle EST de dominer une portée (Fracas/Rafale/Ravage/Marqueur/Faucheur) et on
## donne aux 3 nouvelles (Éclair, Semeuse, Percuteur) une niche alternative propre,
## documentée et testée séparément (mobilité, chargeur, exécution à la tête) —
## voir docs/BALANCE.md "Note sur la règle de niche".
extends GdUnitTestSuite

const HP := 100.0

## Bandes de distance et point médian d'évaluation (m).
const BANDS := [
	{"name": "0-6m", "mid": 3.0},
	{"name": "6-15m", "mid": 10.5},
	{"name": "15-30m", "mid": 22.5},
	{"name": "30-50m", "mid": 40.0},
	{"name": "50m+", "mid": 65.0},
]

## Championne attendue par bande (cf. docs/BALANCE.md).
const CHAMPIONS := {
	"0-6m": "Fracas",
	"6-15m": "Rafale",
	"15-30m": "Ravage",
	"30-50m": "Marqueur",
	"50m+": "Faucheur",
}

## Armes "principales" génériques (corps-à-corps de TTK par tirs multiples) tenues
## à la bande générale 350-500 ms corps / 250-350 ms tête. Percuteur est exclu de
## la bande tête générale : sa niche est "2 têtes à toute distance" (cf. plus bas).
const GENERIC_PRIMARIES := ["Rafale", "Éclair", "Marqueur", "Ravage", "Semeuse"]

const ALL_PRIMARY_NAMES := ["Rafale", "Éclair", "Marqueur", "Ravage", "Semeuse", "Percuteur", "Fracas", "Faucheur"]


func _cfg(name: String) -> WeaponConfig:
	var c := WeaponDatabase.get_by_name(name)
	assert_object(c).append_failure_message("arme introuvable au catalogue: %s" % name).is_not_null()
	return c


func _body_ttk(name: String, dist: float) -> float:
	return WeaponMath.ttk_ms(_cfg(name), dist, HP, false)


func _head_ttk(name: String, dist: float) -> float:
	return WeaponMath.ttk_ms(_cfg(name), dist, HP, true)


func test_catalogue_has_ten_weapons_appended_never_reordered() -> void:
	assert_int(WeaponDatabase.PATHS.size()).is_equal(10)
	# Ordre historique intact (IDs = IDs réseau, jamais réordonnés).
	var expected_prefix := ["Pistolet", "Magnum", "Rafale", "Marqueur", "Ravage", "Fracas", "Faucheur"]
	for i in expected_prefix.size():
		assert_str(WeaponDatabase.get_by_id(i).weapon_name).is_equal(expected_prefix[i])
	# Les 3 nouvelles sont ajoutées à la fin (indices 7, 8, 9).
	var new_names := []
	for i in range(7, 10):
		new_names.append(WeaponDatabase.get_by_id(i).weapon_name)
	assert_array(new_names).contains(["Éclair", "Semeuse", "Percuteur"])


func test_pistolet_body_ttk_optimal_range() -> void:
	var ttk := _body_ttk("Pistolet", 0.0)
	assert_float(ttk).is_greater_equal(550.0)
	assert_float(ttk).is_less_equal(700.0)


func test_magnum_kills_in_two_heads_or_three_bodies_across_its_range() -> void:
	var c := _cfg("Magnum")
	for dist in [0.0, c.falloff_start, c.falloff_end]:
		assert_int(WeaponMath.shots_to_kill(c, dist, HP, false)).append_failure_message(
			"Magnum doit tuer en 3 tirs corps a %sm" % dist
		).is_equal(3)
		assert_int(WeaponMath.shots_to_kill(c, dist, HP, true)).append_failure_message(
			"Magnum doit tuer en 2 tetes a %sm" % dist
		).is_equal(2)


func test_primaries_general_body_ttk_band_350_to_500ms_at_optimal_range() -> void:
	for name in GENERIC_PRIMARIES:
		var ttk := _body_ttk(name, 0.0)
		assert_float(ttk).append_failure_message("%s body TTK=%s hors 350-500ms" % [name, ttk]).is_greater_equal(350.0)
		assert_float(ttk).append_failure_message("%s body TTK=%s hors 350-500ms" % [name, ttk]).is_less_equal(500.0)


func test_primaries_general_headshot_ttk_band_250_to_350ms_at_optimal_range() -> void:
	for name in GENERIC_PRIMARIES:
		var ttk := _head_ttk(name, 0.0)
		assert_float(ttk).append_failure_message("%s head TTK=%s hors 250-350ms" % [name, ttk]).is_greater_equal(250.0)
		assert_float(ttk).append_failure_message("%s head TTK=%s hors 250-350ms" % [name, ttk]).is_less_equal(350.0)


func test_percuteur_body_ttk_band_350_to_500ms_at_optimal_range() -> void:
	var ttk := _body_ttk("Percuteur", 0.0)
	assert_float(ttk).is_greater_equal(350.0)
	assert_float(ttk).is_less_equal(500.0)


func test_percuteur_kills_in_two_headshots_at_any_range() -> void:
	# Niche du Percuteur (DMR semi) : comme le Magnum, 2 tetes tuent quelle que
	# soit la distance dans sa portee de chute de degats.
	var c := _cfg("Percuteur")
	for dist in [0.0, c.falloff_start, (c.falloff_start + c.falloff_end) / 2.0, c.falloff_end]:
		assert_int(WeaponMath.shots_to_kill(c, dist, HP, true)).append_failure_message(
			"Percuteur doit tuer en 2 tetes a %sm" % dist
		).is_equal(2)


func test_fracas_one_shot_kill_within_4m_with_all_pellets() -> void:
	var c := _cfg("Fracas")
	for dist in [0.0, 2.0, 4.0]:
		var dmg := WeaponMath.shot_damage(c, dist, false)
		assert_float(dmg).append_failure_message("Fracas a %sm ne one-shot pas (%s dmg)" % [dist, dmg]).is_greater_equal(HP)


func test_faucheur_one_shot_headshot_across_its_range() -> void:
	var c := _cfg("Faucheur")
	for dist in [0.0, c.falloff_start, c.falloff_end, c.max_range]:
		assert_int(WeaponMath.shots_to_kill(c, dist, HP, true)).append_failure_message(
			"Faucheur doit one-shot a la tete a %sm" % dist
		).is_equal(1)


func test_faucheur_body_kill_takes_two_shots_across_its_range() -> void:
	var c := _cfg("Faucheur")
	for dist in [0.0, c.falloff_start, c.falloff_end]:
		assert_int(WeaponMath.shots_to_kill(c, dist, HP, false)).append_failure_message(
			"Faucheur doit tuer le corps en 2 tirs a %sm" % dist
		).is_equal(2)


## Règle de niche : par bande, l'arme championne (cf. CHAMPIONS) a un TTK corps
## strictement inférieur à toutes les autres armes principales à cette distance.
func test_each_band_has_a_strict_niche_champion_among_primaries() -> void:
	for band in BANDS:
		var band_name: String = band["name"]
		var mid: float = band["mid"]
		var champion: String = CHAMPIONS[band_name]
		var champion_ttk := _body_ttk(champion, mid)
		for other in ALL_PRIMARY_NAMES:
			if other == champion:
				continue
			var other_ttk := _body_ttk(other, mid)
			assert_float(champion_ttk).append_failure_message(
				"bande %s (%sm): %s (%s ms) devrait battre %s (%s ms)" % [band_name, mid, champion, champion_ttk, other, other_ttk]
			).is_less(other_ttk)


## Les 3 nouvelles armes ont chacune une niche testable propre (indépendante de la
## suprématie de bande, cf. note en tête de fichier et docs/BALANCE.md).
func test_semeuse_has_the_largest_magazine_lmg_niche() -> void:
	var semeuse := _cfg("Semeuse")
	for other in WeaponDatabase.all():
		if other == semeuse:
			continue
		assert_int(semeuse.mag_size).append_failure_message(
			"Semeuse (LMG, chargeur %s) devrait avoir le plus gros chargeur, battu par %s (%s)" % [semeuse.mag_size, other.weapon_name, other.mag_size]
		).is_greater(other.mag_size)


func test_eclair_has_the_fastest_mobility_among_smgs() -> void:
	# Niche de l'Éclair : SMG "mobilité" — pret a tirer plus vite apres sprint et
	# visee (ADS) plus rapide que le Rafale (l'autre SMG).
	var eclair := _cfg("Éclair")
	var rafale := _cfg("Rafale")
	assert_float(eclair.sprint_to_fire).is_less(rafale.sprint_to_fire)
	assert_float(eclair.ads_time).is_less(rafale.ads_time)
