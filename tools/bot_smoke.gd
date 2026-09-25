## bot_smoke.gd
## Test de fumée des bots, un seul processus, headless (contract-r3.md,
## R3-IN#3) : héberge un match sur une carte de MapCatalog (scenes/levels/
## maps/), avec l'hôte + des bots jusqu'à `--team-size` par équipe, tourne
## `--duration` secondes puis affiche UNE ligne
##   BOT_SMOKE kills=<n> errors=0 rejected_shots=<n> spawns_t0_distinct=<n> spawns_t0_total=<n>
## et quitte 0 si kills > 0 (sinon 1). `errors=0` est un engagement de ce
## script (aucune condition connue ne doit produire d'erreur ici) — la
## vérification "zéro SCRIPT/SHADER ERROR" se fait en grepant la sortie
## complète du process Godot (mêmes gates que les autres scènes, voir
## contract-r3.md).
##
## Paramétrable (OPS-10, docs/REVIEW.md) pour rejouer un match complet plus
## long que la revue rapide (ex. 10 min de TDM réel — GameMode.match_time_limit
## vaut déjà 600 s par défaut, voir scripts/modes/GameMode.gd) :
##   Usage : godot --headless --path . -s res://tools/bot_smoke.gd -- \
##       [--duration=600] [--mode=tdm] [--map=cargo_ship] [--team-size=4] \
##       [--time-scale=1.0]
## Sans argument (invocation de tools/review/run_review.ps1) : défauts
## INCHANGÉS — 120 s, mode tdm, carte cargo_ship, taille d'équipe du mode
## (4), time_scale 1.0 — pour ne pas ralentir la revue rapide.
## `--mode` : identifiant MatchConfig.MODES (tdm/hardpoint/snd/duel/duo), repli
## sur "tdm" si inconnu (MatchConfig.set_mode). `--map` : identifiant
## MapCatalog (voir scripts/levels/maps/MapCatalog.gd), résolu par
## MatchConfig.resolve_scene — MÊME résolution que le serveur en jeu
## (ServerBoot/NetworkManager) ; un id inconnu retombe sur la carte par
## défaut du mode. `--team-size` : par défaut celle du mode
## (MatchConfig.team_size_for), l'argument la force explicitement. `--time-scale`
## (Engine.time_scale, remis à 1.0 avant de quitter) : accélère la simulation
## pour qu'un match de 600 s n'immobilise pas le process 10 minutes réelles —
## delta déjà mis à l'échelle par le moteur pour CE process, donc `--duration`
## reste bien un temps de match SIMULÉ, cohérent avec le propre chronomètre du
## mode (GameMode.match_elapsed, même delta).
##
## Télémétrie : ce script n'ÉCRIT rien lui-même — GameWorld.gd héberge déjà
## la télémétrie FUN-05 (scripts/core/Telemetry.gd, JSONL versionné :
## match_start/spawn/kill dont `time_since_spawn`/match_end...) dès qu'un match
## tourne, y compris ici. La ligne BOT_SMOKE_START affiche le chemin RÉEL du
## journal (`Telemetry.log_path()` globalisé) pour qu'un outil aval (ex.
## LD-08 tools/heatmap.gd --in=<chemin>) le retrouve sans dépendre du dossier
## utilisateur par défaut. Il RELIT en revanche ce même journal en fin de
## partie (LD-23, `_count_distinct_t0_spawns`, voir sa doc) pour agréger le
## nombre de positions de spawn DISTINCTES parmi le premier spawn de chacun
## des `--team-size * 2` joueurs — la mesure d'anti-empilement de
## `docs/research/09_wasteland_vertical_slice.md` §c.4.
extends SceneTree

const DEFAULT_DURATION := 120.0
const DEFAULT_MODE := "tdm"
const DEFAULT_MAP := "cargo_ship"

var _duration: float = DEFAULT_DURATION
var _mode_id: String = DEFAULT_MODE
var _map_id: String = DEFAULT_MAP
## <= 0 = non fourni par la ligne de commande : résolu depuis le mode
## (MatchConfig.team_size_for) une fois `_mode_id` connu, voir `_start`.
var _team_size_arg: int = -1
var _time_scale: float = 1.0

var _t: float = 0.0
var _started: bool = false
var _world: Node = null

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--duration="):
			_duration = float(a.get_slice("=", 1))
		elif a.begins_with("--mode="):
			_mode_id = a.get_slice("=", 1)
		elif a.begins_with("--map="):
			_map_id = a.get_slice("=", 1)
		elif a.begins_with("--team-size="):
			_team_size_arg = int(a.get_slice("=", 1))
		elif a.begins_with("--time-scale="):
			_time_scale = maxf(0.05, float(a.get_slice("=", 1)))

func _start() -> void:
	_started = true
	MatchConfig.set_mode(_mode_id)
	MatchConfig.map_id = _map_id
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = _team_size_arg if _team_size_arg > 0 else MatchConfig.team_size_for(MatchConfig.mode_id)
	MatchConfig.bot_difficulty = MatchConfig.Difficulty.VETERAN
	Engine.time_scale = _time_scale

	var net := NetworkManager.get_net(self)
	net.host()

	# Même résolution (carte demandée, sinon défaut du mode) que le serveur en
	# jeu — voir MatchConfig.resolve_scene, ServerBoot._resolve_map_scene.
	var level_path := MatchConfig.resolve_scene(MatchConfig.mode_id, _map_id)
	var scene: PackedScene = load(level_path)
	_world = scene.instantiate()
	# Opt-in explicite au remplissage par des bots (voir GameWorld.allow_bot_fill :
	# FAUX par défaut pour ne jamais changer le comportement d'une scène
	# existante, notamment test_arena — partagée avec tools/net_smoke.gd).
	_world.set("allow_bot_fill", true)
	root.add_child(_world)
	current_scene = _world
	# `_world` déjà `_ready()` (add_child sur un arbre en cours d'exécution est
	# synchrone) : GameWorld a donc déjà appelé Telemetry.start_session() —
	# voir doc d'en-tête. Chemin globalisé (Telemetry.log_path() est un chemin
	# virtuel `user://...`) pour rester exploitable hors du process Godot.
	var telemetry_path := ProjectSettings.globalize_path(Telemetry.log_path())
	print("BOT_SMOKE_START level=%s mode=%s map=%s team_size=%d duration=%.0f time_scale=%.1f telemetry=%s" % [
		level_path, MatchConfig.mode_id, _map_id, MatchConfig.team_size, _duration, _time_scale, telemetry_path])

func _process(delta: float) -> bool:
	if not _started:
		_start()
		return false
	_t += delta
	if _t < _duration:
		return false
	_finish()
	return true

func _finish() -> void:
	Engine.time_scale = 1.0
	var kills := 0
	var rejected := 0
	var players := _world.get_node_or_null(_world.players_root) if _world else null
	if players:
		for p in players.get_children():
			var w := p.get_node_or_null("Weapon")
			if w:
				rejected += int(w.rejected_shots)
	if _world:
		for id in _world.player_info.keys():
			kills += int(_world.player_info[id].kills)
	var ok := kills > 0
	var spawns := _count_distinct_t0_spawns()
	print("BOT_SMOKE kills=%d errors=0 rejected_shots=%d spawns_t0_distinct=%d spawns_t0_total=%d" % [
		kills, rejected, spawns.distinct, spawns.total])
	quit(0 if ok else 1)

## LD-23 : agrège les positions de spawn INITIALES ("à t0" — le PREMIER
## `Telemetry.EVENT_SPAWN` de chaque joueur, jamais un respawn après une mort
## en cours de match) du match COURANT (`Telemetry.current_match_id`, mis à
## jour par GameWorld — voir sa doc). Lit le journal JSONL de CE process
## (`Telemetry.log_path()`, déjà affiché par `BOT_SMOKE_START`) avec une
## SECONDE poignée de fichier, en LECTURE : `Telemetry.record` ne vide son
## tampon d'écriture qu'à la fermeture (voir sa doc de classe, "aucun
## flush() par ligne"), d'où le `Telemetry.close_log()` explicite ci-dessous
## AVANT de relire — sans lui, les tout derniers événements écrits par CE
## process pourraient ne pas encore être sur le disque. `close_log()` est
## une API publique existante de Telemetry.gd (tests/core/test_telemetry.gd
## l'utilise déjà avant de relire son propre journal dans le même process) :
## rien à ajouter à ce fichier hors périmètre pour que ceci soit fiable.
## Retourne {"distinct": int, "total": int} — `distinct` compte les positions
## arrondies au centimètre (évite un faux "non distinct" dû au seul bruit de
## flottant) parmi les premiers spawns collectés ; `total` est le nombre de
## joueurs distincts vus (8 en 4v4 par défaut, mais dépend de `--team-size`).
func _count_distinct_t0_spawns() -> Dictionary:
	Telemetry.close_log()
	var file := FileAccess.open(Telemetry.log_path(), FileAccess.READ)
	if file == null:
		return {"distinct": 0, "total": 0}
	var first_spawn_by_player: Dictionary = {}
	for line in file.get_as_text().split("\n"):
		if line.is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if not (parsed is Dictionary):
			continue
		var data: Dictionary = parsed
		if data.get("event") != Telemetry.EVENT_SPAWN:
			continue
		if data.get("match_id") != Telemetry.current_match_id:
			continue
		var pid := int(data.get("player_id", -1))
		if pid < 0 or first_spawn_by_player.has(pid):
			continue  # `has()` : SEUL le PREMIER spawn de ce joueur compte ("à t0").
		var pos = data.get("pos")
		if pos is Array and pos.size() == 3:
			first_spawn_by_player[pid] = Vector3(pos[0], pos[1], pos[2])
	file.close()
	var seen_positions: Dictionary = {}
	for pid in first_spawn_by_player:
		var p: Vector3 = first_spawn_by_player[pid]
		seen_positions["%.2f,%.2f,%.2f" % [p.x, p.y, p.z]] = true
	return {"distinct": seen_positions.size(), "total": first_spawn_by_player.size()}
