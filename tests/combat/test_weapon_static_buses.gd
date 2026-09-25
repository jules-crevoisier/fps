## test_weapon_static_buses.gd
## Spec BUG-33 (« Isolation des tests : bus statiques de Weapon
## (recent_gunfire/recent_impacts) qui fuient entre suites ») : `Weapon.
## recent_gunfire`/`Weapon.recent_impacts` sont des `static var` -- partagés
## par TOUTE la durée de vie du processus (voir Weapon.gd, docstring de
## `reset_buses`) : un tir/impact simulé par UNE suite gdUnit4 reste visible
## par TOUTE AUTRE suite qui s'enchaîne dans le MÊME run tant qu'il n'a pas
## expiré (`BotPerception.HEAR_EVENT_MEMORY_S`, 1 s d'horloge murale — bien
## assez pour qu'une suite plus tard dans le même run en hérite). Ce fichier
## prouve que `Weapon.reset_buses()` vide bien les deux bus, quel que soit
## leur mode de remplissage (`_remember_gunfire`/`_remember_impact`, seuls
## appelants en jeu — voir `_server_fire`/`_resolve_ray` — ou un futur
## appelant qui écrirait directement dans le tableau). La CONSOMMATION des
## bus (audition des bots) est déjà couverte par tests/ai/ (hors de la liste
## de fichiers de cette tâche) : rien ici ne duplique ces cas, seule
## l'isolation entre suites est testée.
extends GdUnitTestSuite


## Ce fichier lit/écrit directement les bus statiques pour les observer --
## il s'isole donc lui-même AVANT et APRÈS chaque cas, jamais dépendant de
## l'ordre d'exécution ni d'une suite voisine (même discipline que celle
## ajoutée à tests/ui/test_buy_menu.gd pour cette même tâche).
func before_test() -> void:
	Weapon.reset_buses()


func after_test() -> void:
	Weapon.reset_buses()


func test_buses_start_empty() -> void:
	assert_array(Weapon.recent_gunfire).is_empty()
	assert_array(Weapon.recent_impacts).is_empty()


func test_remember_gunfire_appends_a_pos_team_time_entry() -> void:
	Weapon._remember_gunfire(Vector3(1.0, 2.0, 3.0), 1)

	assert_array(Weapon.recent_gunfire).has_size(1)
	var entry: Dictionary = Weapon.recent_gunfire[0]
	assert_that(entry.pos).is_equal(Vector3(1.0, 2.0, 3.0))
	assert_int(entry.team).is_equal(1)
	assert_bool(entry.has("time")).append_failure_message(
		"BotBrain._hear_gunfire filtre par fraîcheur (HEAR_EVENT_MEMORY_S) : chaque entrée doit porter une horodate"
	).is_true()


func test_remember_impact_appends_a_pos_team_time_entry() -> void:
	Weapon._remember_impact(Vector3(4.0, 5.0, 6.0), 0)

	assert_array(Weapon.recent_impacts).has_size(1)
	var entry: Dictionary = Weapon.recent_impacts[0]
	assert_that(entry.pos).is_equal(Vector3(4.0, 5.0, 6.0))
	assert_int(entry.team).is_equal(0)
	assert_bool(entry.has("time")).is_true()


func test_reset_buses_empties_recent_gunfire_populated_by_remember_gunfire() -> void:
	Weapon._remember_gunfire(Vector3.ZERO, 0)
	Weapon._remember_gunfire(Vector3.ONE, 1)
	assert_array(Weapon.recent_gunfire).append_failure_message(
		"précondition du test : le bus doit être non vide avant reset_buses()"
	).is_not_empty()

	Weapon.reset_buses()

	assert_array(Weapon.recent_gunfire).append_failure_message(
		"BUG-33 : reset_buses() doit vider recent_gunfire, sinon une suite plus tard dans le même run gdUnit4 hérite de tirs qu'elle n'a jamais produits"
	).is_empty()


func test_reset_buses_empties_recent_impacts_populated_by_remember_impact() -> void:
	Weapon._remember_impact(Vector3.ZERO, 0)
	Weapon._remember_impact(Vector3.ONE, 1)
	assert_array(Weapon.recent_impacts).append_failure_message(
		"précondition du test : le bus doit être non vide avant reset_buses()"
	).is_not_empty()

	Weapon.reset_buses()

	assert_array(Weapon.recent_impacts).append_failure_message(
		"BUG-33 : reset_buses() doit vider recent_impacts (ajouté par BOT-03 à côté de recent_gunfire, voir le titre de la tâche)"
	).is_empty()


## Peuplé par append() DIRECT, pas via _remember_* : reset_buses() ne doit
## jamais dépendre du CHEMIN de remplissage, seulement du CONTENU des deux
## tableaux -- une garantie plus large que les deux tests ci-dessus.
func test_reset_buses_clears_both_buses_together_regardless_of_how_they_were_filled() -> void:
	Weapon.recent_gunfire.append({"pos": Vector3.ZERO, "team": 0, "time": 0.0})
	Weapon.recent_impacts.append({"pos": Vector3.ZERO, "team": 0, "time": 0.0})

	Weapon.reset_buses()

	assert_array(Weapon.recent_gunfire).is_empty()
	assert_array(Weapon.recent_impacts).is_empty()


func test_reset_buses_on_already_empty_buses_is_a_safe_no_op() -> void:
	assert_array(Weapon.recent_gunfire).is_empty()
	assert_array(Weapon.recent_impacts).is_empty()

	Weapon.reset_buses()

	assert_array(Weapon.recent_gunfire).is_empty()
	assert_array(Weapon.recent_impacts).is_empty()
