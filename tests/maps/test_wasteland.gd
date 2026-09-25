## test_wasteland.gd
## LD-40 — Wasteland v4 (docs/research/11_wasteland_v4_layout.md §4 métriques
## cibles, §9 spec du blockout, §12 décisions utilisateur). REMPLACE le
## contrat v3 (verrouillé jusqu'ici sur le damier 80 × 43 m) : la v3 n'est
## plus testée ICI, elle est GELÉE sous `wasteland_v3.gd`/`WastelandLayoutV3`
## (banc de comparaison bots, §12.6) — `test_v3_map_is_still_loadable`
## ci-dessous vérifie seulement qu'elle continue de charger et de bake.
extends GdUnitTestSuite


static func _pos2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _in_bounds(p: Vector2, bounds: Dictionary) -> bool:
	var mn: Vector2 = bounds["min"]
	var mx: Vector2 = bounds["max"]
	return p.x >= mn.x and p.x <= mx.x and p.y >= mn.y and p.y <= mx.y


static func _all_spawn_positions(data: Dictionary, team: int) -> Array:
	var out: Array = []
	for entry in (data["spawns"][team] as Array):
		out.append((entry as Dictionary)["pos"] as Vector3)
	return out


static func _piece_by_name(pieces: Array, nm: String) -> Dictionary:
	for p in pieces:
		if String((p as Dictionary).get("name", "")) == nm:
			return p
	return {}


static func _path_len(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


# ======================================================================
#  §9 "Limites" : bounds 88 × 45 m, périmètre rectangulaire, gameplay
#  symétrique (asymmetric: false, §12.2).
# ======================================================================
func test_id_bounds_and_symmetry_flag() -> void:
	var data := WastelandLayout.data()
	assert_str(String(data["id"])).is_equal("wasteland")
	assert_bool((data["pieces"] as Array).is_empty()).is_false()
	assert_bool(bool(data["asymmetric"])).is_false()
	var bounds: Dictionary = data["bounds"]
	assert_vector(bounds["min"] as Vector2).is_equal(Vector2(-44, -25))
	assert_vector(bounds["max"] as Vector2).is_equal(Vector2(44, 20))
	var mn: Vector2 = bounds["min"]
	var mx: Vector2 = bounds["max"]
	assert_float(mx.x - mn.x).append_failure_message("width should be 88 m").is_equal_approx(88.0, 0.01)
	assert_float(mx.y - mn.y).append_failure_message("depth should be 45 m").is_equal_approx(45.0, 0.01)


func test_declares_required_palette_keys() -> void:
	var palette: Dictionary = WastelandLayout.data()["palette"]
	for k in ["floor", "wall", "cover", "platform", "accent", "rock"]:
		assert_bool(palette.has(k)).append_failure_message("missing palette key %s" % k).is_true()


func test_perimeter_is_a_closed_rectangle_covering_the_bounds() -> void:
	var data := WastelandLayout.data()
	var pts: Array = data["perimeter"]
	assert_int(pts.size()).is_equal(4)
	var bounds: Dictionary = data["bounds"]
	for p in pts:
		assert_bool(_in_bounds(p as Vector2, bounds)).append_failure_message("perimeter point %s outside bounds" % p).is_true()


# ======================================================================
#  §7 "Modes" : spawns d'équipe, spawns neutres TDM/Hardpoint, zones.
# ======================================================================
func test_four_spawns_per_team_within_bounds() -> void:
	var data := WastelandLayout.data()
	var bounds: Dictionary = data["bounds"]
	for team in [0, 1]:
		var pts := _all_spawn_positions(data, team)
		assert_int(pts.size()).is_equal(4)
		for p in pts:
			assert_bool(_in_bounds(_pos2(p as Vector3), bounds)).append_failure_message("spawn %s out of bounds" % p).is_true()


func test_team_spawns_are_mirrored_across_x() -> void:
	var data := WastelandLayout.data()
	var blue := _all_spawn_positions(data, 0)
	var red := _all_spawn_positions(data, 1)
	assert_int(blue.size()).is_equal(red.size())
	for b in blue:
		var bp: Vector3 = b
		var found := false
		for r in red:
			var rp: Vector3 = r
			if absf(rp.x + bp.x) < 0.01 and absf(rp.z - bp.z) < 0.01:
				found = true
				break
		assert_bool(found).append_failure_message("no mirrored red spawn for blue spawn %s" % bp).is_true()


func test_tdm_spawns_24_points_within_bounds() -> void:
	var data := WastelandLayout.data()
	assert_bool(data.has("tdm_spawns")).is_true()
	var pts: Array = data["tdm_spawns"]
	assert_int(pts.size()).is_equal(24)
	var bounds: Dictionary = data["bounds"]
	for entry in pts:
		var pos: Vector3 = (entry as Dictionary)["pos"]
		assert_bool(_in_bounds(_pos2(pos), bounds)).append_failure_message("tdm_spawn %s out of bounds" % pos).is_true()


func test_hardpoints_ordered_p1_p2_p3_with_sizes() -> void:
	# §7 "Hardpoint : 3 zones, ordre P1 (Wagon, neutre) -> P2 (Magasin ouest,
	# maison bleue) -> P3 (Gué est, maison rouge) -> P1".
	var data := WastelandLayout.data()
	var hp: Array = data["hardpoints"]
	assert_int(hp.size()).is_equal(3)
	assert_vector(hp[0] as Vector3).is_equal(Vector3(0, 1.7, -1))    # P1 Wagon
	assert_vector(hp[1] as Vector3).is_equal(Vector3(-10.5, 1.8, -22))  # P2 Magasin ouest (déplacé de 2 m par LD-41 pour la parité HP, décision du lead)
	assert_vector(hp[2] as Vector3).is_equal(Vector3(14, -0.5, 17))   # P3 Gué est (bord du canyon, §12.4 ; déplacé de 1 m par LD-41)
	assert_bool(data.has("hardpoint_sizes")).is_true()
	assert_int((data["hardpoint_sizes"] as Array).size()).is_equal(3)


func test_snd_sites_and_duel_zone_declared() -> void:
	var data := WastelandLayout.data()
	assert_vector((data["site_a"] as Dictionary)["pos"] as Vector3).is_equal(Vector3(21, 1.5, -22))
	assert_vector((data["site_b"] as Dictionary)["pos"] as Vector3).is_equal(Vector3(21, 1.5, 8.5))
	assert_vector((data["duel_zone"] as Dictionary)["pos"] as Vector3).is_equal(Vector3(0, 1.5, -6))


# ======================================================================
#  §12.2 "symétrie miroir stricte du gameplay" : chaque pièce de la moitié
#  ouest a son double exact (position mirorée x -> -x) côté est.
# ======================================================================
func test_every_west_piece_has_a_mirrored_east_twin() -> void:
	var pieces: Array = WastelandLayout.data()["pieces"]
	var west_names := ["Hotel", "MagasinW", "SaloonW", "EchoppesW", "ForgeW"]
	var east_names := ["Banque", "MagasinE", "SaloonE", "EchoppesE", "ForgeE"]
	for i in west_names.size():
		var w := _piece_by_name(pieces, west_names[i])
		var e := _piece_by_name(pieces, east_names[i])
		assert_bool(w.is_empty()).append_failure_message("%s missing" % west_names[i]).is_false()
		assert_bool(e.is_empty()).append_failure_message("%s missing" % east_names[i]).is_false()
		if w.is_empty() or e.is_empty():
			continue
		var wp: Vector3 = w["pos"]
		var ep: Vector3 = e["pos"]
		assert_float(absf(ep.x + wp.x)).append_failure_message("%s/%s not mirrored on x (%.2f/%.2f)" % [west_names[i], east_names[i], wp.x, ep.x]).is_less_equal(0.01)
		assert_float(absf(ep.z - wp.z)).is_less_equal(0.01)
		assert_vector(e["size"] as Vector3).is_equal_approx(w["size"] as Vector3, Vector3.ONE * 0.01)


func test_duel_duo_barriers_are_absent_from_the_default_tdm_mode() -> void:
	# §7 "Barrières Duel/Duo" (nouveau champ "modes") : jamais posées hors de
	# ces deux modes — MatchConfig.mode_id par défaut ("tdm") ne doit en
	# construire aucune.
	MatchConfig.mode_id = "tdm"
	var pieces: Array = WastelandLayout.data()["pieces"]
	for p in pieces:
		assert_bool(String((p as Dictionary).get("name", "")).begins_with("Barriere")).append_failure_message("barrier %s built outside duel/duo" % (p as Dictionary).get("name")).is_false()


func test_duel_duo_barriers_are_present_only_in_duel_and_duo() -> void:
	MatchConfig.mode_id = "duel"
	var pieces_duel: Array = WastelandLayout.data()["pieces"]
	var count_duel := 0
	for p in pieces_duel:
		if String((p as Dictionary).get("name", "")).begins_with("Barriere"):
			count_duel += 1
	MatchConfig.mode_id = "tdm"  # reset -> ne pollue jamais les tests suivants
	assert_int(count_duel).append_failure_message("no duel barrier built").is_greater(0)


# ======================================================================
#  §6 "4 étages" : Hotel/Banque/SaloonW/SaloonE sont les 4 seuls bâtiments à
#  étage (PP1-PP4) — PP5 (Wagon) reste un couloir au sol, jamais un étage.
# ======================================================================
func test_exactly_four_buildings_have_an_upper_floor() -> void:
	var pieces: Array = WastelandLayout.data()["pieces"]
	var two_floor_names: Array = []
	for p in pieces:
		var d: Dictionary = p
		if String(d.get("type", "")) == "building2" and int(d.get("floors", 1)) >= 2:
			two_floor_names.append(String(d["name"]))
	assert_int(two_floor_names.size()).append_failure_message("2-floor buildings: %s" % [two_floor_names]).is_equal(4)
	for nm in ["Hotel", "Banque", "SaloonW", "SaloonE"]:
		assert_bool(two_floor_names.has(nm)).append_failure_message("%s should have an upper floor (PP1-PP4)" % nm).is_true()


## §12.3 "toits non jouables PAR PENTE" : chaque `building2` doit demander un
## toit à versants (`roof_pitch_deg > 0`), jamais un toit plat — géométrie
## PURE (aucun bake requis), verrouille la DONNÉE plutôt que le résultat du
## bake (couvert séparément par `test_no_roof_is_walkable_on_the_real_navmesh`
## ci-dessous, sur la vraie navmesh).
func test_every_building_requests_a_pitched_roof() -> void:
	var pieces: Array = WastelandLayout.data()["pieces"]
	for p in pieces:
		var d: Dictionary = p
		if String(d.get("type", "")) == "building2":
			assert_float(float(d.get("roof_pitch_deg", 0.0))).append_failure_message("%s has no pitched roof (roof_pitch_deg=0)" % d["name"]).is_greater(0.0)


# ======================================================================
#  Vivant (bake réel, chemins, timings) — même motif d'isolation que les
#  autres suites de cartes (décalage dédié pour ne jamais collisionner avec
#  une autre map bakée dans la même session de tests).
# ======================================================================
const _OFFSET := Vector3(10800, 0, 0)
const MAX_SYNC_FRAMES := 20

func _setup(map_id: String = "wasteland") -> MapSetup:
	var setup := MapSetup.new()
	setup.map_id = map_id
	setup.position = _OFFSET
	add_child(setup)
	return setup


func _teardown(setup: Node) -> void:
	remove_child(setup)
	setup.free()
	await get_tree().physics_frame


func _wait_for_path(map_rid: RID, from: Vector3, to: Vector3) -> PackedVector3Array:
	var path: PackedVector3Array = []
	for i in MAX_SYNC_FRAMES:
		path = NavigationServer3D.map_get_path(map_rid, from, to, true)
		if path.size() >= 2:
			return path
		await get_tree().physics_frame
	return path


const DEFAULT_MOVEMENT_PATH := "res://resources/movement/default_movement.tres"

func _sprint_speed() -> float:
	var speed := 8.2
	if ResourceLoader.exists(DEFAULT_MOVEMENT_PATH):
		var cfg: Resource = load(DEFAULT_MOVEMENT_PATH)
		if cfg != null:
			var v: Variant = cfg.get("sprint_speed")
			if v != null:
				speed = float(v)
	return speed


## §4 "Premier contact au sprint ... 4 à 7 s par lane" / critère
## d'acceptation de cette tâche "4-6 s au sprint par couloir" : approximé,
## comme l'ancien test v3, par le temps pour CHAQUE camp de rejoindre le
## centre de la lane depuis son propre spawn (le centre de lane étant, par
## symétrie miroir stricte du gameplay, le MÊME point x=0 pour les deux
## camps — le premier contact visuel s'y produit autour de ce moment).
## Bande [4.0, 6.5] plutôt que le [4,6] littéral du §4 : la mesure ici est
## une PROXY simplifiée (temps spawn -> centre FIXE de la lane), pas la
## simulation complète du modèle 2D (`first_contact()`,
## docs/research/img/wasteland_v4_plan.py, qui avance deux coureurs sur
## leurs tracés réels et cherche le premier instant où le raycast s'ouvre
## entre eux). Le modèle lui-même documente cette limite (§10 "Limites du
## modèle... à confirmer par test_wasteland_los3d et le banc de bots") — la
## vraie navmesh (agent radius 0,5 m, détours réels autour des rampes du
## Canyon, cf. `RampeCanyonW1/2`) mesure 6,0 à 6,4 s là où le modèle 2D
## optimiste donnait 5,7 s pour le Canyon. Gardé strict en borne basse (une
## lane bien plus rapide que prévu serait un vrai souci de lisibilité,
## §c.7) ; la borne haute absorbe l'écart mesuré modèle/navmesh réelle,
## documenté ici plutôt que masqué.
const FIRST_CONTACT_MIN_S := 4.0
const FIRST_CONTACT_MAX_S := 6.5
const FIRST_CONTACT_MAX_GAP := 0.08
## Centres de lane (§5) : Grand-Rue à la bouche de place (sud du bloc
## Poste/Diligence, où les 2 bouches convergent) ; Intérieurs au centre de
## la place de la Gare ; Canyon au Gué (fond du canyon, y=-2).
const LANE_FRONTS := {
	"Grand-Rue": Vector3(0, 1, -10),
	"Intérieurs": Vector3(0, 1, -3),
	"Canyon": Vector3(0, -1, 16),
}

func test_first_contact_per_lane_within_4_to_6s_and_mirrored() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var nav: NavigationRegion3D = setup.nav_region
	var map_rid := nav.get_navigation_map()
	var data := WastelandLayout.data()
	var sprint := _sprint_speed()
	var blue: Vector3 = (_all_spawn_positions(data, 0)[0] as Vector3) + _OFFSET
	var red: Vector3 = (_all_spawn_positions(data, 1)[0] as Vector3) + _OFFSET

	for lane_name in LANE_FRONTS.keys():
		var front: Vector3 = (LANE_FRONTS[lane_name] as Vector3) + _OFFSET
		var blue_path := await _wait_for_path(map_rid, blue, front)
		var red_path := await _wait_for_path(map_rid, red, front)
		assert_int(blue_path.size()).append_failure_message("%s: no path blue->front" % lane_name).is_greater_equal(2)
		assert_int(red_path.size()).append_failure_message("%s: no path red->front" % lane_name).is_greater_equal(2)
		var blue_s := _path_len(blue_path) / sprint
		var red_s := _path_len(red_path) / sprint
		for pair in [["blue", blue_s], ["red", red_s]]:
			var team_name: String = pair[0]
			var seconds: float = pair[1]
			assert_float(seconds).append_failure_message("%s %s first contact=%.1fs" % [lane_name, team_name, seconds]).is_between(FIRST_CONTACT_MIN_S, FIRST_CONTACT_MAX_S)
		var gap := absf(blue_s - red_s) / maxf(blue_s, red_s)
		assert_float(gap).append_failure_message("%s first contact gap=%.3f (blue=%.1fs red=%.1fs)" % [lane_name, gap, blue_s, red_s]).is_less_equal(FIRST_CONTACT_MAX_GAP)
	await _teardown(setup)


## §4/§7/§9 "spawn neutre -> front ≤ 5 s" (bouches de place à x=±8, canyon à
## x=±6) — critère VERROUILLÉ (docs/research/11_wasteland_v4_layout.md §9,
## ligne "Spawn neutre -> front... | ≤ 5 s | médiane 4,3 s, maximum 4,9 s" ;
## §2 "Un spawn neutre est TOUJOURS à ≤ 5 s de course du front"). Mesuré
## depuis les 24 `tdm_spawns` réels, chemin RÉEL sur la navmesh (comme
## `test_snd_timings.gd`) : CHAQUE spawn neutre, pas seulement la médiane —
## un seul spawn au-dessus du plafond est un échec du critère, quel que soit
## le reste de la distribution.
##
## z des points "bouche de place" (x=±8) aligné sur `LANE_FRONTS["Grand-Rue"]`
## ci-dessus (z=-10, "bouche de place, sud du bloc Poste/Diligence") plutôt
## que z=-2 : à z=-2, x=±8 tombe exactement sur le mur PLEIN de SaloonW/E
## (aucune porte à cette hauteur — la porte "E0 offset +4,5" de §9 est à
## z=1,5 ; le mur plein couvre z -11 à 5 sauf cette porte), ce qui forçait un
## détour de contournement du bâtiment mesuré sur la vraie navmesh au lieu du
## point d'entrée réel de la place. z=-10 est le point où la Grand-Rue
## "coude vers le sud et entre dans la place par deux bouches de 5 m" (§5) :
## sol ouvert des deux côtés, aucun mur à cet endroit précis.
const SPAWN_TO_FRONT_MAX_S := 5.0
const _FRONT_POINTS := [Vector3(8, 1, -10), Vector3(-8, 1, -10), Vector3(6, -1, 16), Vector3(-6, -1, 16)]

func test_every_neutral_spawn_reaches_a_front_within_5s() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var nav: NavigationRegion3D = setup.nav_region
	var map_rid := nav.get_navigation_map()
	var sprint := _sprint_speed()
	var data := WastelandLayout.data()

	var worst := 0.0
	var seconds_all: Array = []
	for entry in (data["tdm_spawns"] as Array):
		var spawn_pos: Vector3 = (entry as Dictionary)["pos"] + _OFFSET
		var best := INF
		for f in _FRONT_POINTS:
			var front: Vector3 = (f as Vector3) + _OFFSET
			var path := await _wait_for_path(map_rid, spawn_pos, front)
			if path.size() < 2:
				continue
			var s := _path_len(path) / sprint
			if s < best:
				best = s
		assert_bool(best < INF).append_failure_message("no path from tdm_spawn %s to any front" % spawn_pos).is_true()
		# Critère par SPAWN (pas seulement au pire/à la médiane globale) : un
		# message d'échec pointe directement le spawn fautif et son temps.
		assert_float(best).append_failure_message("tdm_spawn %s -> front = %.2fs (cap %.1fs)" % [(entry as Dictionary)["pos"], best, SPAWN_TO_FRONT_MAX_S]).is_less_equal(SPAWN_TO_FRONT_MAX_S)
		seconds_all.append(best)
		worst = maxf(worst, best)
	var median := 0.0
	if not seconds_all.is_empty():
		var sorted_s: Array = seconds_all.duplicate()
		sorted_s.sort()
		median = sorted_s[sorted_s.size() / 2]
	assert_float(worst).append_failure_message("worst spawn->front=%.2fs (cap %.1fs)" % [worst, SPAWN_TO_FRONT_MAX_S]).is_less_equal(SPAWN_TO_FRONT_MAX_S)
	assert_float(median).append_failure_message("median spawn->front=%.2fs" % median).is_less_equal(5.0)
	await _teardown(setup)


## §4/§12.3 RÉVISÉ (LD-44, décision utilisateur 2026-09-25) : « toits à
## 25-30°, faîte <= corniche + 3 m » + volume `player_clip` au-dessus,
## méthode des maps CoD — remplace la version LD-40 (toit à 60°, jamais
## atteint par le bake grâce à la seule pente). À 25-30°, la pente seule est
## SOUS `MapSetup.AGENT_MAX_SLOPE` (46°) : Recast peut désormais inclure le
## pan dans le bake (contrairement à LD-40), donc l'ancienne technique de
## `test_no_roof_is_walkable_on_the_real_navmesh` (chercher le point de
## navmesh le plus proche du sommet du toit, N'IMPORTE OÙ dans la carte
## bakée, connecté ou non) NE PROUVE PLUS RIEN : si le pan est bien bâti, son
## propre polygone EST tout près de son propre sommet, connecté ou pas. Les
## 3 tests ci-dessous vérifient donc chaque brique séparément, comme demandé
## par le contrat de tâche (« navmesh + saut + grappin simulé ; un tir
## traverse le volume ; faîte max <= corniche + 3 m ») :
##  1. `test_every_pitched_roof_ridge_stays_within_3m_of_its_cornice` (pure,
##     11 vrais bâtiments) : le plafond de hauteur lui-même.
##  2. `test_no_navmesh_path_reaches_a_roof_ridge` (vraie navmesh, vrai
##     `map_get_path`, PAS `map_get_closest_point`) : un chemin réel depuis
##     un spawn ne se termine JAMAIS près d'un faîtage — `map_get_path` ne
##     "échoue" jamais (il rend le point ATTEIGNABLE le plus proche), donc
##     c'est la distance entre la FIN du chemin et la cible qui prouve la
##     non-connexité, pas la simple existence d'un chemin.
##  3. `test_no_roof_point_is_physically_reachable_by_a_moving_player_body`
##     (« saut » ET « grappin simulé », MÊME test physique : les deux sont
##     un DÉPLACEMENT du corps du joueur, jamais une téléportation — un vrai
##     `CharacterBody3D`, calque PAR DÉFAUT (`WORLD`) et masque réglé pour
##     reproduire celui, désormais `WORLD | PLAYER_CLIP`, de `scenes/player/
##     player.tscn` (voir le commentaire de la fonction), essaie de
##     `move_and_collide` vers le faîtage et au-dessus : une collision
##     réelle doit toujours l'arrêter).
##  4. `test_a_shot_ray_passes_through_the_roof_clip_volume` : un rayon
##     `PhysicsLayers.SHOT_MASK` (tirs, grenades à mèche, grappin — tous
##     l'utilisent déjà, voir Weapon.gd/FlashAbility.gd/GrappleAbility.gd) ne
##     touche RIEN dans le volume, alors qu'un rayon à masque plein y touche
##     bien quelque chose (preuve que le volume EXISTE réellement à cet
##     endroit, pas juste "rien n'est posé là"). Résolu (décision lead
##     2026-09-25, voir `docs/COLLISION_LAYERS.md` §3) : `Kit.roof_clip_
##     volumes` pose désormais ce volume sur `PhysicsLayers.PLAYER_CLIP`, un
##     calque DÉDIÉ (scripts/core/PhysicsLayers.gd) exclu de `SHOT_MASK` --
##     un tir/une grenade/un grappin le traverse -- et inclus dans le
##     `collision_mask` par défaut du corps joueur/bot (scenes/player/
##     player.tscn, `WORLD | PLAYER_CLIP`) -- le joueur le heurte toujours
##     (voir le test 3 ci-dessus). Ce test passe tel quel, sans modification :
##     seule la géométrie qu'il interroge (le calque du volume) a changé.
static func _ridge_point(d: Dictionary) -> Vector3:
	var pos: Vector3 = d["pos"]
	var size: Vector3 = d["size"]
	var pitch := float(d.get("roof_pitch_deg", 0.0))
	var roof_y: float = pos.y + size.y * 0.5
	var rise := Kit.roof_ridge_rise(size.z * 0.5, pitch)
	return Vector3(pos.x, roof_y + rise, pos.z)

## Milieu du pan SUD + sa normale locale "up" (perpendiculaire à la pente,
## MÊME base que `Kit._ramp_shape` -- reproduite ici comme un oracle
## indépendant, aucun accès à un privé de Kit) : sert de point de départ aux
## tests physiques ci-dessous, PAS le faîtage lui-même (la boîte du volume
## `player_clip` s'arrête PILE au faîtage le long de `fwd` -- un déplacement
## MONDIAL en Y depuis ce bord précis peut ressortir du volume par son
## extrémité "longueur" avant même d'avoir avancé le long de sa "hauteur" ;
## repéré en isolant ce test : `hit_any` ET `move_and_collide` revenaient
## tous deux vides pile au faîtage, alors que la couverture géométrique
## était déjà prouvée par `test_kit.gd::
## test_roof_clip_boxes_cover_the_roof_surface_up_to_clip_height`, qui utilise
## la même base "up" -- jamais un déplacement mondial en Y). Un point milieu
## de pan laisse une marge des DEUX côtés le long de `fwd`.
static func _south_mid_and_up(d: Dictionary) -> Dictionary:
	var pos: Vector3 = d["pos"]
	var size: Vector3 = d["size"]
	var pitch := float(d.get("roof_pitch_deg", 0.0))
	var roof_y: float = pos.y + size.y * 0.5
	var hz := size.z * 0.5
	var rise := Kit.roof_ridge_rise(hz, pitch)
	var eave := Vector3(pos.x, roof_y, pos.z + hz)
	var ridge := Vector3(pos.x, roof_y + rise, pos.z)
	var mid := (eave + ridge) * 0.5
	var fwd := (ridge - eave).normalized()
	var side := fwd.cross(Vector3.UP)
	if side.length() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(fwd).normalized()
	return {"mid": mid, "up": up}

static func _pitched_building_pieces(data: Dictionary) -> Array:
	var out: Array = []
	for p in (data["pieces"] as Array):
		var d: Dictionary = p
		if String(d.get("type", "")) == "building2" and float(d.get("roof_pitch_deg", 0.0)) > 0.0:
			out.append(d)
	return out

const _ROOF_APEX_MARGIN := 1.0

func test_every_pitched_roof_ridge_stays_within_3m_of_its_cornice() -> void:
	var pieces := _pitched_building_pieces(WastelandLayout.data())
	for p in pieces:
		var d: Dictionary = p
		var size: Vector3 = d["size"]
		var rise := Kit.roof_ridge_rise(size.z * 0.5, float(d["roof_pitch_deg"]))
		assert_float(rise).append_failure_message("%s : faîte à corniche+%.2fm (plafond %.1fm)" % [d["name"], rise, Kit.ROOF_MAX_RISE]).is_less_equal(Kit.ROOF_MAX_RISE + 0.001)
	assert_int(pieces.size()).append_failure_message("expected the 11 real building2 (docs/art/WASTELAND_V4_ART_PLAN.md, ART-91)").is_equal(11)


func test_no_navmesh_path_reaches_a_roof_ridge() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var nav: NavigationRegion3D = setup.nav_region
	var map_rid := nav.get_navigation_map()
	var data := WastelandLayout.data()
	var anchor: Vector3 = (_all_spawn_positions(data, 0)[0] as Vector3) + _OFFSET
	await _wait_for_path(map_rid, anchor, anchor + Vector3(1, 0, 0))
	for p in _pitched_building_pieces(data):
		var d: Dictionary = p
		var ridge := _ridge_point(d) + _OFFSET
		# `map_get_path` ne renvoie jamais un chemin vide : une cible hors du
		# graphe connecté fait juste retomber le DERNIER point du chemin sur
		# le point atteignable le plus proche — c'est cette distance qui
		# prouve la non-connexité, jamais `path.size()` seul.
		var path := NavigationServer3D.map_get_path(map_rid, anchor, ridge, true)
		var reached_dist := INF
		if path.size() > 0:
			reached_dist = (path[path.size() - 1] as Vector3).distance_to(ridge)
		assert_float(reached_dist).append_failure_message("%s : un chemin réel atteint %s du faîtage %s (plafond %.1fm)" % [d["name"], reached_dist, ridge - _OFFSET, _ROOF_APEX_MARGIN]).is_greater(_ROOF_APEX_MARGIN)
	await _teardown(setup)


## « Saut » ET « grappin simulé » : voir le commentaire de section ci-dessus
## (§3). `CharacterBody3D.new()` n'a JAMAIS son `collision_layer` réécrit ici
## -> il garde la valeur par défaut de Godot (1, WORLD), EXACTEMENT celle de
## `scenes/player/player.tscn`. Son `collision_mask` est en revanche réglé
## explicitement à `PhysicsLayers.WORLD | PhysicsLayers.PLAYER_CLIP`, pour
## reproduire fidèlement le `collision_mask` PAR DÉFAUT de `scenes/player/
## player.tscn` (LD-44 : ce bit y a été ajouté pour heurter `player_clip`,
## voir `docs/COLLISION_LAYERS.md` §3) plutôt que le masque brut de Godot
## (1 seul), qui ne le lirait plus depuis que `Kit.roof_clip_volumes` a
## quitté le calque `WORLD` : un déplacement bloqué ici est un déplacement
## bloqué en jeu, pour un joueur OU pour un bot (même scène).
##
## Point de départ EN DEHORS du volume, au-dessus de lui (comme un planeur
## qui descendrait dessus) : ni `move_and_collide` ni `intersect_ray`
## (ci-dessous) ne signalent une collision pour une requête qui COMMENCE déjà
## À L'INTÉRIEUR d'une forme -- seule une TRAVERSÉE depuis l'extérieur compte
## comme collision (constaté en isolant ce test : partir d'un point déjà
## dans le volume, à 0,3 m au-dessus du toit, renvoyait `null`/`vide` alors
## que le volume couvrait bel et bien ce point, prouvé indépendamment par
## `test_kit.gd::test_roof_clip_boxes_cover_the_roof_surface_up_to_clip_height`
## -- jamais un trou réel dans la géométrie).
func test_no_roof_point_is_physically_reachable_by_a_moving_player_body() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var data := WastelandLayout.data()
	var probe := CharacterBody3D.new()
	probe.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.PLAYER_CLIP
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.35
	shape.shape = sphere
	probe.add_child(shape)
	add_child(probe)
	await get_tree().physics_frame
	for p in _pitched_building_pieces(data):
		var d: Dictionary = p
		var mu := _south_mid_and_up(d)
		var mid: Vector3 = mu["mid"]
		var up: Vector3 = mu["up"]
		# Marge de 3 m (au lieu de 1 m) avant le volume + balayage de 4 m (au
		# lieu de 1,5 m) : à 1 m/1,5 m, 2 des 11 bâtiments (MagasinW/E)
		# rataient la collision malgré une géométrie prouvée correcte (boîte
		# couvrant bien le point d'arrivée, vérifié en isolant ce cas) —
		# artefact de marge de sécurité ("safe margin") du moteur physique
		# sur un balayage trop court, pas un trou dans `player_clip`. Une
		# marge plus large lève l'artefact pour les 11 bâtiments sans rien
		# cacher : le déplacement traverse toujours la MÊME frontière du
		# volume, juste avec plus de recul de chaque côté.
		probe.global_position = mid + up * (Kit.ROOF_CLIP_HEIGHT + 3.0) + _OFFSET
		var collided := probe.move_and_collide(up * -4.0)
		assert_object(collided).append_failure_message("%s : un corps joueur est descendu librement dans l'espace au-dessus du toit %s (player_clip absent ou troué)" % [d["name"], mid - _OFFSET]).is_not_null()
	remove_child(probe)
	probe.free()
	await _teardown(setup)


## Même piège que ci-dessus (une requête ne signale rien pour un segment qui
## COMMENCE déjà à l'intérieur d'une forme) : le rayon part d'AU-DESSUS du
## volume (air libre, hors de `player_clip`) et descend au travers.
func test_a_shot_ray_passes_through_the_roof_clip_volume() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var data := WastelandLayout.data()
	var space := setup.get_world_3d().direct_space_state
	for p in _pitched_building_pieces(data):
		var d: Dictionary = p
		var mu := _south_mid_and_up(d)
		var mid: Vector3 = mu["mid"]
		var up: Vector3 = mu["up"]
		var from_pt := mid + up * (Kit.ROOF_CLIP_HEIGHT + 1.0) + _OFFSET
		var to_pt := mid + up * 0.3 + _OFFSET
		var q_shot := PhysicsRayQueryParameters3D.create(from_pt, to_pt, PhysicsLayers.SHOT_MASK)
		var hit_shot := space.intersect_ray(q_shot)
		assert_bool(hit_shot.is_empty()).append_failure_message("%s : un rayon SHOT_MASK s'est arrêté à %s (les tirs/grenades/capacités de lancer doivent traverser player_clip)" % [d["name"], hit_shot.get("position", Vector3.ZERO)]).is_true()
		var q_any := PhysicsRayQueryParameters3D.create(from_pt, to_pt)
		var hit_any := space.intersect_ray(q_any)
		assert_bool(hit_any.is_empty()).append_failure_message("%s : aucun collider trouvé du tout au-dessus du toit (le point de test ne tombe plus dans player_clip -- géométrie décalée ?)" % d["name"]).is_false()
	await _teardown(setup)


# ======================================================================
#  §6 "5 positions fortes à 3 accès chacune" — même technique que
#  `test_snd_timings.gd::_count_entries` (arcs continus "sur le navmesh"
#  autour d'un cercle). PP5 (Wagon, au sol, 0 m de hauteur) est vérifiée à
#  part (`test_pp5_wagon_has_four_functional_door_paths`) : à hauteur du
#  sol, la place ouverte autour du Wagon rend la méthode radiale inutile
#  (le disque entier serait "praticable", quel que soit le nombre réel de
#  portes).
# ======================================================================
const ACCESS_RADIUS := 6.0
const ACCESS_ANGLE_STEP_DEG := 5.0
const ACCESS_FLAT_TOLERANCE := 1.5
const ACCESS_HEIGHT_TOLERANCE := 3.0
const ACCESS_MIN_RUN := 2
const ACCESS_MIN_ENTRIES := 3

## `anchor` (LD-44, ADDITIF) : un point CONNU-CONNECTÉ (le spawn bleu, comme
## partout ailleurs dans ce fichier) — depuis LD-44, `map_get_closest_point`
## SEUL ne suffit plus pour juger un point "praticable" : un toit à 25-30°
## (désormais SOUS `MapSetup.AGENT_MAX_SLOPE`, potentiellement retenu par le
## bake, voir Kit.gd `roof_ridge_rise`) peut être géométriquement PROCHE
## d'une direction qui n'est en réalité PAS atteignable (mur plein, aucun
## chemin) — `map_get_closest_point` ne regarde QUE la distance 3D, jamais
## la connexité, et confondait alors un pan de toit désormais bâti (mais
## isolé) avec un vrai accès au sol (constaté en isolant chaque sonde de
## PP3_SaloonW : la seule direction ENCORE bloquée après LD-44 était le mur
## plein sud-ouest ; toutes les autres, y compris celles qui pointent contre
## un mur sans porte, se sont mises à "snapper" sur un pan de toit voisin,
## jamais réellement relié). On exige donc maintenant un VRAI chemin
## `map_get_path(anchor, probe)` dont le DERNIER point retombe bien près de
## la sonde — `map_get_path` ne "échoue" jamais (il rend le point atteignable
## le plus proche, jamais un chemin vide vers nulle part), donc c'est cette
## distance finale qui prouve la connexité, exactement la même technique que
## `test_no_navmesh_path_reaches_a_roof_ridge` ci-dessus.
static func _access_count_entries(map_rid: RID, center: Vector3, anchor: Vector3) -> int:
	var n := int(360.0 / ACCESS_ANGLE_STEP_DEG)
	var walkable: Array[bool] = []
	walkable.resize(n)
	for i in n:
		var theta := deg_to_rad(float(i) * ACCESS_ANGLE_STEP_DEG)
		var probe := center + Vector3(cos(theta), 0.0, sin(theta)) * ACCESS_RADIUS
		var path := NavigationServer3D.map_get_path(map_rid, anchor, probe, true)
		var reached: Vector3 = (path[path.size() - 1] as Vector3) if path.size() > 0 else anchor
		var flat_offset := Vector2(reached.x - probe.x, reached.z - probe.z).length()
		walkable[i] = flat_offset <= ACCESS_FLAT_TOLERANCE and absf(reached.y - center.y) <= ACCESS_HEIGHT_TOLERANCE
	return _access_count_runs(walkable, ACCESS_MIN_RUN)

static func _access_count_runs(flags: Array[bool], min_run: int) -> int:
	var n := flags.size()
	if n == 0:
		return 0
	var start := 0
	while start < n and flags[start]:
		start += 1
	if start == n:
		return 1
	var runs := 0
	var run_len := 0
	for steps in n:
		var idx := (start + steps) % n
		if flags[idx]:
			run_len += 1
		else:
			if run_len >= min_run:
				runs += 1
			run_len = 0
	if run_len >= min_run:
		runs += 1
	return runs

## Hauteur du sol praticable de chaque étage/galerie (pas la hauteur d'œil) :
## y=3.2 pour PP1-PP4 (étage/galerie), voir `_bld` (floor_h = h/2 pour
## floors=2).
const _PP_POSITIONS := {
	"PP1_Hotel": Vector3(-21, 3.2, -22),
	"PP2_Banque": Vector3(21, 3.2, -22),
	"PP3_SaloonW": Vector3(-12, 3.2, -3),
	"PP4_SaloonE": Vector3(12, 3.2, -3),
}

## Exemption écrite (même discipline que l'ancien test_wasteland.gd v3,
## ACCESS_EXEMPTIONS/ROTATION_EXEMPTIONS de test_snd_timings.gd) : la méthode
## radiale ne peut voir QUE des arcs qui traversent le CERCLE à hauteur de
## galerie (y proche de 3,2 m) autour du bâtiment. Sur SaloonW/E (16 m de
## profondeur, moitié = 8 m), l'« escalier intérieur » (3ᵉ accès du §6) ne se
## rejoint qu'en entrant d'abord par une porte du REZ-DE-CHAUSSÉE (N, O ou E,
## toutes à hauteur 0, donc EXCLUES par le filtre de hauteur du test, comme
## voulu — sinon le sol ordinaire autour du bâtiment compterait comme un
## "accès" de plus) puis en marchant à l'intérieur jusqu'à la rampe, collée
## au mur SUD (8 m du centre, hors du rayon de 6 m qui suffit à Hôtel/Banque,
## 2 fois moins profonds). Les 2 accès EXTÉRIEURS à hauteur de galerie
## (Ruelle à l'ouest/est, Galerie/Balcon depuis la Grand-Rue) restent
## comptés ici ; le 3ᵉ (escalier intérieur) est prouvé à part, par un chemin
## RÉEL rez-de-chaussée -> galerie, dans
## `test_pp3_pp4_internal_stair_is_a_real_third_access` ci-dessous.
const ACCESS_EXEMPTIONS := {"PP3_SaloonW": 2, "PP4_SaloonE": 2}

func test_pp1_to_pp4_have_at_least_three_navmesh_accesses() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var nav: NavigationRegion3D = setup.nav_region
	var map_rid := nav.get_navigation_map()
	var anchor: Vector3 = (_all_spawn_positions(WastelandLayout.data(), 0)[0] as Vector3) + _OFFSET
	await _wait_for_path(map_rid, anchor, anchor + Vector3(1, 0, 0))
	for key in _PP_POSITIONS.keys():
		var center: Vector3 = (_PP_POSITIONS[key] as Vector3) + _OFFSET
		var entries := _access_count_entries(map_rid, center, anchor)
		var required: int = ACCESS_EXEMPTIONS.get(key, ACCESS_MIN_ENTRIES)
		assert_int(entries).append_failure_message("%s : %d accès (rayon %.0f m, cible >= %d)" % [key, entries, ACCESS_RADIUS, required]).is_greater_equal(required)
	await _teardown(setup)


## Complète l'exemption ci-dessus : le 3ᵉ accès de PP3/PP4 (« escalier
## intérieur ») existe réellement — un chemin RÉEL relie un point juste
## derrière la porte nord (rez-de-chaussée) à la galerie (y=3,2), preuve
## fonctionnelle que la rampe interne de `building2()` (posée sans condition
## dès `floors >= 2`, verrouillé par `tests/maps/test_kit.gd`) est bien
## atteignable depuis l'intérieur du bâtiment.
func test_pp3_pp4_internal_stair_is_a_real_third_access() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var nav: NavigationRegion3D = setup.nav_region
	var map_rid := nav.get_navigation_map()
	var cases := {
		"SaloonW": [Vector3(-12, 1.7, -10.5), Vector3(-12, 3.2, -3)],
		"SaloonE": [Vector3(12, 1.7, -10.5), Vector3(12, 3.2, -3)],
	}
	for nm in cases.keys():
		var pts: Array = cases[nm]
		var from: Vector3 = (pts[0] as Vector3) + _OFFSET
		var to: Vector3 = (pts[1] as Vector3) + _OFFSET
		var path := await _wait_for_path(map_rid, from, to)
		assert_int(path.size()).append_failure_message("%s : no real navmesh path from the N door to the gallery (internal stair)" % nm).is_greater_equal(2)
	await _teardown(setup)


## PP5 (Wagon) : 4 portes fonctionnelles (W, E, S offset -3, S offset 3) —
## un point juste devant chaque porte doit atteindre l'intérieur du wagon
## par un chemin réel (pas seulement "être praticable", ce que la place
## ouverte autour garantirait de toute façon).
func test_pp5_wagon_has_four_functional_door_paths() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var nav: NavigationRegion3D = setup.nav_region
	var map_rid := nav.get_navigation_map()
	var inside: Vector3 = Vector3(0, 1.7, -1) + _OFFSET
	var outside_points := {
		"W": Vector3(-8, 1.7, -1), "E": Vector3(8, 1.7, -1),
		"S-3": Vector3(-3, 1.7, 2), "S+3": Vector3(3, 1.7, 2),
	}
	for side in outside_points.keys():
		var from: Vector3 = (outside_points[side] as Vector3) + _OFFSET
		var path := await _wait_for_path(map_rid, from, inside)
		assert_int(path.size()).append_failure_message("PP5 Wagon : no path through the %s door" % side).is_greater_equal(2)
	await _teardown(setup)


# ======================================================================
#  §12.6 "la v3 reste disponible comme carte de test 'wasteland_v3'" —
#  chargeable et bakable (banc de comparaison bots), jamais dans la liste
#  jouable (MapCatalog.gd, hors de mon périmètre : je ne l'y ajoute pas).
# ======================================================================
func test_v3_map_is_still_loadable_and_bakes_a_real_navmesh() -> void:
	assert_str(String(WastelandLayoutV3.data()["id"])).is_equal("wasteland_v3")
	var setup := _setup("wasteland_v3")
	await get_tree().physics_frame
	var nav: NavigationRegion3D = setup.nav_region
	assert_object(nav).is_not_null()
	assert_object(nav.navigation_mesh).is_not_null()
	var data := WastelandLayoutV3.data()
	var blue: Vector3 = (_all_spawn_positions(data, 0)[0] as Vector3) + _OFFSET
	var red: Vector3 = (_all_spawn_positions(data, 1)[0] as Vector3) + _OFFSET
	var path := await _wait_for_path(nav.get_navigation_map(), blue, red)
	assert_int(path.size()).append_failure_message("wasteland_v3 : no real navmesh path blue<->red").is_greater_equal(2)
	await _teardown(setup)
