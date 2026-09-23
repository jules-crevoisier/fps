## bot_smoke.gd
## Test de fumée des bots, un seul processus, headless (contract-r3.md,
## R3-IN#3) : héberge un match TDM (sur une carte de scenes/levels/maps/ si
## R3-MAPS en a déjà livré une, sinon repli test_arena), avec l'hôte + 7 bots
## (4v4 complet), tourne 120 s, puis affiche UNE ligne
##   BOT_SMOKE kills=<n> errors=0 rejected_shots=<n>
## et quitte 0 si kills > 0 (sinon 1). `errors=0` est un engagement de ce
## script (aucune condition connue ne doit produire d'erreur ici) — la
## vérification "zéro SCRIPT/SHADER ERROR" se fait en grepant la sortie
## complète du process Godot (mêmes gates que les autres scènes, voir
## contract-r3.md).
##   Usage : godot --headless --path . -s res://tools/bot_smoke.gd
extends SceneTree

const FALLBACK_LEVEL := "res://scenes/levels/test_arena.tscn"
const MAPS_DIR := "res://scenes/levels/maps"
const DURATION := 120.0

var _t: float = 0.0
var _started: bool = false
var _world: Node = null

func _initialize() -> void:
	pass

func _start() -> void:
	_started = true
	MatchConfig.mode_id = "tdm"
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = 4
	MatchConfig.bot_difficulty = MatchConfig.Difficulty.VETERAN

	var net := NetworkManager.get_net(self)
	net.host()

	var level_path := _pick_level()
	var scene: PackedScene = load(level_path)
	_world = scene.instantiate()
	# Opt-in explicite au remplissage par des bots (voir GameWorld.allow_bot_fill :
	# FAUX par défaut pour ne jamais changer le comportement d'une scène
	# existante, notamment test_arena — partagée avec tools/net_smoke.gd).
	_world.set("allow_bot_fill", true)
	root.add_child(_world)
	current_scene = _world
	print("BOT_SMOKE_START level=%s" % level_path)

## Carte TDM la plus récente livrée par R3-MAPS si elle existe déjà, sinon
## repli sur test_arena (pas de dépendance de compilation à MapCatalog, qui
## peut ne pas encore exister — simple scan de dossier).
func _pick_level() -> String:
	var dir := DirAccess.open(MAPS_DIR)
	if dir:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".tscn"):
				dir.list_dir_end()
				return "%s/%s" % [MAPS_DIR, f]
			f = dir.get_next()
		dir.list_dir_end()
	return FALLBACK_LEVEL

func _process(delta: float) -> bool:
	if not _started:
		_start()
		return false
	_t += delta
	if _t < DURATION:
		return false
	_finish()
	return true

func _finish() -> void:
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
	print("BOT_SMOKE kills=%d errors=0 rejected_shots=%d" % [kills, rejected])
	quit(0 if ok else 1)
