## test_bot_ammo.gd
## Spec (GF-24, docs/research/10_ammo_kits_input.md §2.7, tasks/backlog.yaml) :
## « Hors combat, un bot recharge de lui-même dès que son chargeur descend
## sous 40 %. À sec, il passe au pistolet. Quand il lui reste moins d'un
## chargeur en réserve et qu'aucun ennemi n'est en vue, il fait un détour vers
## une cartouchière ou une caisse à <= 12 m. Tout passe par l'écriture de
## player.input.reload_pressed et weapon_slot_pressed, comme pour un humain. »
##
## Couvre la table PURE ajoutée à BotCombatStyle.gd (§MUNITIONS) : chaque
## fonction ne dépend que de ses arguments, aucun état de scène — même
## discipline que tests/ai/test_bot_combat_style.gd, dont ce fichier complète
## la couverture sans dupliquer les sections déjà testées là-bas (armes de
## précision, distance préférée, rafales, strafe, ADS, marche).
##
## Critère verrouillé (backlog GF-24) : "Sur un banc de 5 min en Mêlée avec
## bots, 0 bot à 0/0 plus de 5 s. Le bot recharge hors combat sous 40 %" — la
## mesure en vif (tools/bot_bench.gd) est HORS de la liste de fichiers de
## cette tâche (voir le rendu, `blocked_on`) ; ce fichier verrouille la règle
## PURE que BotBrain._tick_ammo applique tick par tick pour la satisfaire.
extends GdUnitTestSuite

# ======================================================================
#  Constantes du contrat — valeurs nommées, jamais des littéraux dispersés
#  dans les assertions (même discipline que test_bot_combat_style.gd).
# ======================================================================

func test_reload_threshold_is_40_percent() -> void:
	assert_float(BotCombatStyle.RELOAD_SELF_THRESHOLD_RATIO).is_equal_approx(0.4, 0.0001)


func test_ammo_detour_radius_is_12_meters() -> void:
	assert_float(BotCombatStyle.AMMO_DETOUR_RADIUS_M).is_equal_approx(12.0, 0.0001)


func test_pistol_weapon_name_is_named_explicitly() -> void:
	assert_str(BotCombatStyle.PISTOL_WEAPON_NAME).is_equal("Pistolet")

# ======================================================================
#  should_self_reload — recharge hors combat sous 40 %.
# ======================================================================

func test_should_self_reload_true_out_of_combat_under_40_percent() -> void:
	assert_bool(BotCombatStyle.should_self_reload(false, 7, 25, 50)).is_true()   # 28 % < 40 %.
	assert_bool(BotCombatStyle.should_self_reload(false, 0, 25, 50)).is_true()   # chargeur vide : a fortiori.


func test_should_self_reload_false_in_combat_even_under_40_percent() -> void:
	# Jamais recharger sous le feu, quel que soit l'état du chargeur.
	assert_bool(BotCombatStyle.should_self_reload(true, 0, 25, 50)).is_false()


func test_should_self_reload_false_at_or_above_40_percent() -> void:
	assert_bool(BotCombatStyle.should_self_reload(false, 10, 25, 50)).is_false()  # 40 % pile : pas encore.
	assert_bool(BotCombatStyle.should_self_reload(false, 20, 25, 50)).is_false()  # 80 %.


func test_should_self_reload_false_just_under_the_threshold_boundary() -> void:
	# 9/25 = 36 % : sous le seuil -> vrai. Vérifie que la borne n'est pas décalée
	# d'une unité entière (bug fréquent sur des ratios entiers).
	assert_bool(BotCombatStyle.should_self_reload(false, 9, 25, 50)).is_true()


func test_should_self_reload_false_when_magazine_already_full() -> void:
	assert_bool(BotCombatStyle.should_self_reload(false, 25, 25, 50)).is_false()


func test_should_self_reload_false_when_reserve_is_empty() -> void:
	# Rien à recharger : la réserve est à sec, même chargeur vide.
	assert_bool(BotCombatStyle.should_self_reload(false, 0, 25, 0)).is_false()


func test_should_self_reload_false_with_unknown_weapon() -> void:
	# mag_size <= 0 : arme inconnue (cfg() == null avant le premier achat).
	assert_bool(BotCombatStyle.should_self_reload(false, 0, 0, 50)).is_false()

# ======================================================================
#  should_switch_to_pistol — passage au pistolet à sec.
# ======================================================================

func test_should_switch_to_pistol_when_dry_and_pistol_available() -> void:
	assert_bool(BotCombatStyle.should_switch_to_pistol("Ravage", 0, 0, true)).is_true()


func test_should_switch_to_pistol_false_when_already_on_pistol() -> void:
	# Le pistolet lui-même à sec : rien d'autre à faire (pas de 3e arme).
	assert_bool(BotCombatStyle.should_switch_to_pistol("Pistolet", 0, 0, true)).is_false()


func test_should_switch_to_pistol_false_with_ammo_left_in_magazine() -> void:
	assert_bool(BotCombatStyle.should_switch_to_pistol("Ravage", 1, 0, true)).is_false()


func test_should_switch_to_pistol_false_with_reserve_left() -> void:
	assert_bool(BotCombatStyle.should_switch_to_pistol("Ravage", 0, 1, true)).is_false()


func test_should_switch_to_pistol_false_without_a_pistol_elsewhere() -> void:
	# Le pistolet a été remplacé en boutique (Inventory.give) : rien vers quoi basculer.
	assert_bool(BotCombatStyle.should_switch_to_pistol("Ravage", 0, 0, false)).is_false()

# ======================================================================
#  wants_ammo_detour — détour vers cartouchière/caisse sous un chargeur de
#  réserve, hors combat.
# ======================================================================

func test_wants_ammo_detour_true_out_of_combat_under_one_magazine() -> void:
	assert_bool(BotCombatStyle.wants_ammo_detour(false, 24, 25)).is_true()


func test_wants_ammo_detour_false_in_combat() -> void:
	# "aucun ennemi en vue" : couvert par in_combat (BotBrain._target_id != -1
	## uniquement quand un ennemi est RÉELLEMENT visible ce tick).
	assert_bool(BotCombatStyle.wants_ammo_detour(true, 0, 25)).is_false()


func test_wants_ammo_detour_false_with_at_least_one_full_magazine_in_reserve() -> void:
	assert_bool(BotCombatStyle.wants_ammo_detour(false, 25, 25)).is_false()  # pile un chargeur : pas "moins de".
	assert_bool(BotCombatStyle.wants_ammo_detour(false, 50, 25)).is_false()


func test_wants_ammo_detour_false_with_unknown_weapon() -> void:
	assert_bool(BotCombatStyle.wants_ammo_detour(false, 0, 0)).is_false()

# ======================================================================
#  nearest_ammo_point — point de munitions le plus proche à <= 12 m.
# ======================================================================

func test_nearest_ammo_point_returns_inf_when_no_points() -> void:
	var result := BotCombatStyle.nearest_ammo_point(Vector3.ZERO, [])
	assert_vector(result).is_equal(Vector3.INF)


func test_nearest_ammo_point_returns_the_only_point_within_radius() -> void:
	var p := Vector3(3, 0, 4)  # distance 5 depuis l'origine.
	var result := BotCombatStyle.nearest_ammo_point(Vector3.ZERO, [p])
	assert_vector(result).is_equal(p)


func test_nearest_ammo_point_ignores_points_beyond_the_radius() -> void:
	var far := Vector3(0, 0, 12.1)
	var result := BotCombatStyle.nearest_ammo_point(Vector3.ZERO, [far])
	assert_vector(result).is_equal(Vector3.INF)


func test_nearest_ammo_point_includes_a_point_exactly_at_the_radius() -> void:
	# "<= 12 m" : la borne elle-même compte.
	var at_radius := Vector3(0, 0, 12.0)
	var result := BotCombatStyle.nearest_ammo_point(Vector3.ZERO, [at_radius])
	assert_vector(result).is_equal(at_radius)


func test_nearest_ammo_point_picks_the_closest_of_several() -> void:
	var near := Vector3(2, 0, 0)
	var mid := Vector3(6, 0, 0)
	var far := Vector3(11, 0, 0)
	var result := BotCombatStyle.nearest_ammo_point(Vector3.ZERO, [far, near, mid])
	assert_vector(result).is_equal(near)


func test_nearest_ammo_point_respects_a_custom_radius() -> void:
	var p := Vector3(3, 0, 0)
	assert_vector(BotCombatStyle.nearest_ammo_point(Vector3.ZERO, [p], 2.0)).append_failure_message(
		"un rayon personnalisé de 2 m doit exclure un point à 3 m"
	).is_equal(Vector3.INF)
	assert_vector(BotCombatStyle.nearest_ammo_point(Vector3.ZERO, [p], 5.0)).is_equal(p)
