## bot_behaviour_probe.gd
## Outil de VÉRIFICATION DE COMPORTEMENT (tâche "bots humains", 2026-09-27) —
## héberge TDM 4v4 BOTS SEULS (aucun joueur humain : `ServerBoot.active = true`
## AVANT d'instancier la carte, voir GameWorld._ready — « ce process n'est
## jamais un joueur », les 8 emplacements des deux équipes se remplissent donc
## de bots via `_fill_bots_if_needed`, sans avoir à figer/geler un joueur
## humain) sur `--map=shipment` (défaut), laisse tourner `--duration=90` s de
## temps de jeu, puis imprime un tableau de métriques PAR BOT :
##   - % temps sprint / marche / immobile ;
##   - écart moyen |lacet du regard - lacet du déplacement| en mouvement ;
##   - changements de direction du regard par minute à l'arrêt ;
##   - durée de tenue moyenne (immobile, entre deux changements de cible) ;
##   - distance parcourue par minute ;
##   - changements de but (`TDMMode._bot_goal_cache`) par minute.
##
## Même famille que tools/style/capture_shipment.gd (SceneTree, `_process`
## pour laisser le moteur tourner avant d'agir) et tools/bake_bot_spots.gd
## (phases). FENÊTRÉ, PAS headless : `--headless` a déjà posé souci ailleurs
## dans ce dépôt pour du contenu qui a besoin d'un cycle de rendu réel (voir
## capture_shipment.gd) — ici, la carte est ajoutée EN DIFFÉRÉ
## (`add_child.call_deferred`), sinon l'autoload `Look` (scripts/core/
## LevelLook.gd) rate l'entrée dans l'arbre (constaté empiriquement, voir le
## contrat de tâche). `DisplayServer.window_set_flag(WINDOW_FLAG_NO_FOCUS,
## true)` : ne vole pas le focus pendant les 90 s de mesure.
##
## Usage :
##   "%GODOT%" --path . --screen 1 -s res://tools/ai/bot_behaviour_probe.gd -- \
##       --map=shipment --duration=90 --label=baseline \
##       --out=reports/checkpoints/2026-09-27_bots
##
## Lit CES underscored (`_look`, `_target_kind`, `_bot_goal_cache`...) de
## BotBrain/BotLook/TDMMode À DES FINS D'INSTRUMENTATION SEULEMENT — même
## discipline qu'un banc déjà pratiqué dans ce dépôt ("tools/bot_bench.gd lit
## `stuck.get('_phase')`", voir scripts/ai/BotCombatStyle.gd tête de fichier) :
## un outil de mesure PEUT regarder l'état interne sans le modifier, ce
## fichier n'écrit jamais dans un champ de BotBrain/BotLook/TDMMode.
extends SceneTree

const STATIONARY_SPEED_THRESHOLD := 0.3  ## m/s — sous ce seuil, un bot est jugé "immobile" (probe seulement, pas une constante de jeu).
const SETTLE_EXTRA_FRAMES := 60           ## Frames de stabilisation SUPPLÉMENTAIRES une fois les 8 bots présents (spawn/premier repath).
const SPAWN_WAIT_TIMEOUT_S := 30.0        ## Abandon si les 8 bots ne sont pas au monde dans ce délai (config/carte cassée).
const EXPECTED_BOTS := 8                  ## 4v4.

var _map_id := "shipment"
var _duration_s := 90.0
var _label := "run"
var _out_dir := "reports/checkpoints/2026-09-27_bots"

var _phase := 0
var _wait_elapsed_s := 0.0
var _settle_frames_left := SETTLE_EXTRA_FRAMES
var _elapsed_s := 0.0
var _world: Node = null
var _mode: Node = null
var _bots: Array = []          ## Array de {"id": int, "player": PlayerController, "brain": Node}.
var _stats: Dictionary = {}    ## bot_id (int) -> Dictionary d'accumulateurs, voir `_new_stats`.
## Diagnostic (tâche "bots humains" passe 2) : répartition du gaze_gap en
## ROULEMENT (kind dans `_ROAM_KINDS`, voir sa docstring) par `BotLook.
## _target_kind` (agrégée TOUS bots confondus, jamais persistée dans le
## rapport principal) -- sert à identifier QUELLE cible de regard domine
## l'écart mesuré (ex. "corner" pré-visé en continu sur une carte pleine de
## virages serrés, contre "angle"/"path_point" du L8/L1).
## kind (String) -> {"sum": float, "samples": int}.
var _kind_gap_out: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			_map_id = a.get_slice("=", 1)
		elif a.begins_with("--duration="):
			_duration_s = float(a.get_slice("=", 1))
		elif a.begins_with("--label="):
			_label = a.get_slice("=", 1)
		elif a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)


func _process(delta: float) -> bool:
	match _phase:
		0:
			_boot()
			_phase = 1
			return false
		1:
			return _wait_for_bots(delta)
		2:
			_settle_frames_left -= 1
			if _settle_frames_left <= 0:
				_start_measurement()
				_phase = 3
			return false
		3:
			return _measure(delta)
	return true


func _boot() -> void:
	# Aucun joueur humain (voir la docstring de tête) : `ServerBoot.active`
	# DOIT être posé AVANT que GameWorld._ready() ne s'exécute (donc avant
	# l'ajout de la carte à l'arbre, même différé).
	ServerBoot.active = true
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = _map_id
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = EXPECTED_BOTS / 2
	MatchConfig.bot_difficulty = MatchConfig.Difficulty.VETERAN
	var scene_path := "res://scenes/levels/maps/%s.tscn" % _map_id
	var packed := load(scene_path) as PackedScene
	if packed == null:
		printerr("BOT_PROBE_FAIL scene_not_found path=%s" % scene_path)
		call_deferred("quit", 1)
		return
	_world = packed.instantiate()
	# DIFFÉRÉ (contrat de tâche) : un `add_child` synchrone ici fait rater
	# l'entrée dans l'arbre à l'autoload `Look` (scripts/core/LevelLook.gd).
	get_root().add_child.call_deferred(_world)


func _wait_for_bots(delta: float) -> bool:
	_wait_elapsed_s += delta
	var world := get_root().get_tree().get_first_node_in_group("match")
	if world != null:
		_world = world
		var players_root := world.get_node_or_null(world.get("players_root"))
		if players_root != null and players_root.get_child_count() >= EXPECTED_BOTS:
			_mode = get_root().get_tree().get_first_node_in_group("game_mode")
			_collect_bots(players_root)
			if _bots.size() >= EXPECTED_BOTS:
				_phase = 2
				return false
	if _wait_elapsed_s >= SPAWN_WAIT_TIMEOUT_S:
		printerr("BOT_PROBE_FAIL bots_not_spawned elapsed=%.1f" % _wait_elapsed_s)
		call_deferred("quit", 1)
		return true
	return false


func _collect_bots(players_root: Node) -> void:
	_bots.clear()
	for child in players_root.get_children():
		if not bool(child.get("is_bot")):
			continue
		var brain := child.get_node_or_null("BotBrain")
		if brain == null:
			continue
		_bots.append({"id": str(child.name).to_int(), "player": child, "brain": brain})


func _new_stats(pos: Vector3) -> Dictionary:
	return {
		"sprint_s": 0.0, "walk_s": 0.0, "stationary_s": 0.0,
		"gaze_gap_sum": 0.0, "gaze_gap_samples": 0,
		# Tâche "bots humains" passe 2 (diagnostic lead : "report the split
		# in-combat vs out-of-combat if you can") — `gaze_gap_sum/samples`
		# ci-dessus reste la moyenne GLOBALE (comparable telle quelle à la
		# table "after" de la passe 1) ; ces deux paires la DÉCOMPOSENT par
		# `BotLook._target_kind` (LECTURE SEULE, voir `_sample_bot`/
		# `_ROAM_KINDS`), PAS par `BotBrain._target_id` : un essai initial avec
		# `_target_id` classait "enemy"/"heard" (mémoire fraîche d'un contact,
		# L1 #1-2, TOUJOURS actif dès qu'un ennemi a été vu/entendu récemment,
		# CONTINUE après que `_target_id` soit retombé à -1 -- perte de vue)
		# comme "hors combat", alors qu'ils dominaient numériquement (65k+
		# échantillons sur ce run, contre ~4k pour route/coin/angle/balayage
		# combinés -- carte petite, combats fréquents) et gonflaient
		# artificiellement `gaze_gap_out_deg` : le contrat de la passe 2 vise
		# "route/coin/angle/balayage" (L1 #4-5, L2, L5, L8), PAS la mémoire de
		# contact (L1 #1-2, un signal de sécurité "jamais soumis à la
		# minuterie", inchangé -- voir BotLook.gd). "roam" (kind dans
		# `_ROAM_KINDS`) est donc la cible du contrat < 20° ; "alert"
		# (enemy/heard) reste volontairement large (le warp visuel gère le
		# strafe, pas le regard).
		"gaze_gap_out_sum": 0.0, "gaze_gap_out_samples": 0,
		"gaze_gap_combat_sum": 0.0, "gaze_gap_combat_samples": 0,
		"look_changes": 0, "last_look_kind": "", "last_look_pos": Vector3.INF,
		"last_look_kind_was_idle": false, "idle_stationary_s": 0.0,
		"distance_m": 0.0, "last_pos": pos,
		"goal_changes": 0, "last_goal": Vector3.INF,
	}


func _start_measurement() -> void:
	_elapsed_s = 0.0
	_stats.clear()
	for entry in _bots:
		var e: Dictionary = entry
		var player: Node = e.player
		_stats[int(e.id)] = _new_stats((player as Node3D).global_position)
	# Diagnostic (tâche "bots humains" passe 2, bake_bot_spots.gd) : vérifie
	# EN DIRECT que `GameWorld.bot_spots` est bien chargé pour cette carte —
	# `null`/vide signale immédiatement un bake manquant/périmé plutôt que de
	# laisser `hold_s` retomber silencieusement à 0 sans explication.
	var spots_count := -1
	if _world != null and ("bot_spots" in _world):
		var bs = _world.get("bot_spots")
		spots_count = bs.spots.size() if bs != null else 0
	print("BOT_PROBE_START label=%s map=%s bots=%d duration=%.0f bot_spots=%d" % [
		_label, _map_id, _bots.size(), _duration_s, spots_count])


func _measure(delta: float) -> bool:
	_elapsed_s += delta
	for entry in _bots:
		var e: Dictionary = entry
		_sample_bot(int(e.id), e.player, e.brain, delta)
	if _elapsed_s >= _duration_s:
		_report()
		call_deferred("quit", 0)
		return true
	return false


## Cibles de ROULEMENT/BALAYAGE de BotLook (L1 #4-5, L2, L5, L8) — PAS les
## signaux de sécurité "enemy"/"heard" (L1 #1-2, mémoire de contact, TOUJOURS
## actifs tant qu'elle est fraîche, "jamais soumis à la minuterie" -- voir
## BotLook.gd). Sert à la fois au comptage des changements de regard À
## L'ARRÊT (inchangé depuis avant la passe 2) ET à la décomposition
## roam/alerte du gaze_gap EN MOUVEMENT (voir `_new_stats`) : les DEUX usages
## veulent la même distinction, "en train de rouler" contre "sur ses gardes".
const _ROAM_KINDS := ["", "path_point", "corner", "angle", "sweep"]


func _sample_bot(bot_id: int, player: Node, brain: Node, delta: float) -> void:
	var stats: Dictionary = _stats[bot_id]
	var pos: Vector3 = (player as Node3D).global_position
	var vel: Vector3 = player.get("velocity") if "velocity" in player else Vector3.ZERO
	var flat_speed := Vector2(vel.x, vel.z).length()

	stats.distance_m += (stats.last_pos as Vector3).distance_to(pos)
	stats.last_pos = pos

	var look = brain.get("_look")
	var kind := String(look.get("_target_kind")) if look != null else "?"
	var is_roam_kind := kind in _ROAM_KINDS

	var stationary := flat_speed < STATIONARY_SPEED_THRESHOLD
	if stationary:
		stats.stationary_s += delta
	else:
		var walk_held := bool(player.get("input").walk_held) if player.get("input") != null else false
		if walk_held:
			stats.walk_s += delta
		else:
			stats.sprint_s += delta
		var gaze_yaw_deg := rad_to_deg((player as Node3D).rotation.y)
		var gap := BotLook.gaze_move_gap_deg(gaze_yaw_deg, vel)
		stats.gaze_gap_sum += gap
		stats.gaze_gap_samples += 1
		# Décomposition roam/alerte (voir la docstring de `_new_stats`) : par
		# `BotLook._target_kind`, pas `BotBrain._target_id` (voir pourquoi).
		if is_roam_kind:
			stats.gaze_gap_out_sum += gap
			stats.gaze_gap_out_samples += 1
			# Diagnostic (voir la docstring de `_kind_gap_out`) : quelle cible de
			# regard domine l'écart mesuré en ROULEMENT.
			var bucket: Dictionary = _kind_gap_out.get(kind, {"sum": 0.0, "samples": 0})
			bucket.sum = float(bucket.sum) + gap
			bucket.samples = int(bucket.samples) + 1
			_kind_gap_out[kind] = bucket
		else:
			stats.gaze_gap_combat_sum += gap
			stats.gaze_gap_combat_samples += 1

	# Changements de cible de regard (BotLook._target_kind/_target_pos, LECTURE
	# SEULE — voir la docstring de tête) à l'arrêt ET seulement pour une cible
	# de ROULEMENT/BALAYAGE (`_ROAM_KINDS`) — "enemy"/"heard" sont des cibles
	# URGENTES dont `_target_pos` SUIT une position qui bouge à CHAQUE tick
	# tant qu'elles restent actives (voir BotLook._select_target : "suit une
	# cible urgente qui bouge... sans relancer la minuterie") : les compter
	# ferait exploser artificiellement ce compteur (des centaines de
	# "changements"/min) sans rapport avec le balayage humain que ce métrique
	# veut mesurer (BOT-25).
	if look != null:
		var target_pos: Vector3 = look.get("_target_pos")
		if stationary and is_roam_kind:
			stats.idle_stationary_s += delta
			if stats.last_look_kind != "" and stats.last_look_kind_was_idle \
					and (kind != stats.last_look_kind or not target_pos.is_equal_approx(stats.last_look_pos)):
				stats.look_changes += 1
		stats.last_look_kind = kind
		stats.last_look_kind_was_idle = is_roam_kind
		stats.last_look_pos = target_pos

	# Changements de but de mode (TDMMode._bot_goal_cache, LECTURE SEULE) —
	# même méthode que tests/ai/test_bot_goals.gd (comparaison `is_equal_approx`
	# entre deux échantillons successifs).
	if _mode != null:
		var cache: Dictionary = _mode.get("_bot_goal_cache")
		if cache != null and cache.has(bot_id):
			var goal: Vector3 = (cache[bot_id] as Dictionary).get("pos", Vector3.INF)
			if stats.last_goal != Vector3.INF and not goal.is_equal_approx(stats.last_goal):
				stats.goal_changes += 1
			stats.last_goal = goal

	_stats[bot_id] = stats


func _report() -> void:
	var minutes := _duration_s / 60.0
	var lines: Array = []
	var header := "%-6s %8s %8s %8s %14s %14s %14s %16s %14s %12s %12s" % [
		"bot", "sprint%", "walk%", "still%", "gaze_gap_deg", "gaze_out_deg", "gaze_cbt_deg",
		"look_chg/min", "hold_s", "dist_m/min", "goal_chg/min"]
	lines.append(header)
	lines.append("-".repeat(header.length()))
	var summary: Dictionary = {"label": _label, "map": _map_id, "duration_s": _duration_s, "bots": {}}
	for entry in _bots:
		var bot_id: int = int((entry as Dictionary).id)
		var s: Dictionary = _stats[bot_id]
		var moving_s: float = float(s.sprint_s) + float(s.walk_s)
		var total_s: float = moving_s + float(s.stationary_s)
		var sprint_pct := (float(s.sprint_s) / total_s * 100.0) if total_s > 0.0 else 0.0
		var walk_pct := (float(s.walk_s) / total_s * 100.0) if total_s > 0.0 else 0.0
		var still_pct := (float(s.stationary_s) / total_s * 100.0) if total_s > 0.0 else 0.0
		var mean_gap := (float(s.gaze_gap_sum) / float(s.gaze_gap_samples)) if int(s.gaze_gap_samples) > 0 else 0.0
		var mean_gap_out := (float(s.gaze_gap_out_sum) / float(s.gaze_gap_out_samples)) if int(s.gaze_gap_out_samples) > 0 else 0.0
		var mean_gap_combat := (float(s.gaze_gap_combat_sum) / float(s.gaze_gap_combat_samples)) if int(s.gaze_gap_combat_samples) > 0 else 0.0
		var look_chg_per_min := float(s.look_changes) / minutes
		var hold_s := (float(s.idle_stationary_s) / float(s.look_changes)) if int(s.look_changes) > 0 else float(s.idle_stationary_s)
		var dist_per_min := float(s.distance_m) / minutes
		var goal_chg_per_min := float(s.goal_changes) / minutes
		lines.append("%-6d %8.1f %8.1f %8.1f %14.1f %14.1f %14.1f %16.2f %14.2f %12.1f %12.2f" % [
			bot_id, sprint_pct, walk_pct, still_pct, mean_gap, mean_gap_out, mean_gap_combat,
			look_chg_per_min, hold_s, dist_per_min, goal_chg_per_min])
		summary.bots[bot_id] = {
			"sprint_pct": sprint_pct, "walk_pct": walk_pct, "stationary_pct": still_pct,
			"mean_gaze_gap_deg": mean_gap, "mean_gaze_gap_roam_deg": mean_gap_out,
			"mean_gaze_gap_alert_deg": mean_gap_combat, "look_changes_per_min": look_chg_per_min,
			"hold_duration_s": hold_s, "distance_per_min_m": dist_per_min,
			"goal_changes_per_min": goal_chg_per_min,
		}
	var table := "\n".join(lines)
	print("BOT_PROBE_TABLE label=%s\n%s" % [_label, table])

	# Diagnostic (voir `_kind_gap_out`) : imprimé à part, jamais dans le
	# tableau/JSON principal (pas un contrat de test, juste un outil de mise
	# au point pour cette tâche).
	var kind_lines: Array = ["BOT_PROBE_GAZE_KIND_BREAKDOWN label=%s (roulement, _ROAM_KINDS)" % _label]
	for k in _kind_gap_out.keys():
		var b: Dictionary = _kind_gap_out[k]
		var mean := float(b.sum) / float(b.samples) if int(b.samples) > 0 else 0.0
		kind_lines.append("  kind=%-12s samples=%-6d mean_gap_deg=%.1f" % [k, int(b.samples), mean])
	print("\n".join(kind_lines))

	var abs_dir := ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var txt_path := "%s/bot_behaviour_%s.txt" % [_out_dir, _label]
	var f := FileAccess.open(txt_path, FileAccess.WRITE)
	if f:
		f.store_string(table + "\n")
		f.close()
	var json_path := "%s/bot_behaviour_%s.json" % [_out_dir, _label]
	var jf := FileAccess.open(json_path, FileAccess.WRITE)
	if jf:
		jf.store_string(JSON.stringify(summary, "  "))
		jf.close()
	print("BOT_PROBE_DONE label=%s txt=%s json=%s" % [_label, txt_path, json_path])
