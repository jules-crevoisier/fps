## gameplay_probe.gd
## Sonde de revue automatisée (headless, un seul process) : héberge un match
## local (test_arena.tscn, sans bot) puis fait passer le joueur hôte par
## CHAQUE état de mouvement en pilotant `player.input` (PlayerInput.gd) et en
## tirant à chaque état — le bug remonté par l'utilisateur ("on ne peut pas
## tirer si on ne saute pas") venait précisément de l'absence d'un filet de
## test couvrant "tirer dans TOUS les états de mouvement". Enchaîne ensuite
## rechargement / changement d'arme / ADS / capacités / dégâts-mort / bon sens
## de mouvement / non-blocage au spawn sur chaque map / cycle manche-match de
## chaque mode.
##
## Usage :
##   godot --headless --path . -s res://tools/review/gameplay_probe.gd -- --out=DIR
##
## Écrit "<out>/gameplay_probe.json" : {"checks":[{"name","ok","detail"}], "errors":int}.
## Imprime une ligne de résumé puis quitte 0 (tout est ok) ou 1.
##
## ------------------------------------------------------------------------
##  TABLE DES RÉSULTATS ATTENDUS — fire_in_state (comportement INTENTIONNEL,
##  voir Weapon._can_act() et WeaponFeel.fire_delay_left()/_since_slide/_since_dive
##  dans Weapon._owner_tick). Un check ÉCHOUE seulement si le résultat RÉEL
##  diverge de cette table (donc seulement sur un blocage NON PRÉVU, ou à
##  l'inverse un tir NON PRÉVU qui passerait dans un état censé le bloquer) :
##
##  | État    | Tir attendu | Raison                                                |
##  |---------|-------------|--------------------------------------------------------|
##  | Idle    | OK          | aucune restriction                                      |
##  | Walk    | OK          | aucune restriction                                      |
##  | Sprint  | OK          | sprint auto (docs/MOVEMENT.md) : aucun délai tir après   |
##  |         |             | un sprint (sprint_to_fire retiré, BUG-K01)               |
##  | Crouch  | OK          | aucune restriction                                       |
##  | Air     | OK          | saut/chute : aucune restriction                          |
##  | Slide   | OK          | GF-30 (playtest 2026-09-25) : tir en glissade permis,     |
##  |         |             | dispersion de glissade (WeaponFeel.move_spread_deg)       |
##  | Dive    | BLOQUÉ      | Weapon._can_act() exclut "Dive" explicitement            |
##  | Roll    | BLOQUÉ      | Weapon._can_act() exclut "Roll" (roulade = pas d'action)  |
##  | Stun    | OK          | GF-29/MV-03 : stun adouci, tir avec +3° de dispersion     |
##
##  Pas d'état "ADS" ni "ladder"/"mantle" dans ce projet (voir
##  scripts/player/states/*.gd) : "ads" est testé séparément (modificateur du
##  tir, pas un état de la state machine).
## ------------------------------------------------------------------------
extends SceneTree

const TEST_ARENA := "res://scenes/levels/test_arena.tscn"
const DEFAULT_OUT := "res://.probe_out"
const TIME_BUDGET_SEC := 82.0  ## garde-fou : le run entier doit rester < 90 s.

## IMPORTANT : ce script pilote le joueur via `player.input` DIRECTEMENT
## (champs de PlayerInput.gd), PAS via `Input.action_press()`. Un run
## `--headless` n'a AUCUN display server : `Input.mouse_mode` reste bloqué à
## MOUSE_MODE_VISIBLE quoi qu'on fasse (vérifié empiriquement), donc le garde
## "souris capturée" de `PlayerInput._physics_process` (`reads_devices`)
## n'est JAMAIS vrai pour un humain local en headless — `gather_from_devices()`
## ne tourne alors jamais et `clear()` écrase tout à chaque tick, quels que
## soient les Input.action_press() envoyés (c'est d'ailleurs documenté dans
## PlayerInput.gd : "Input.mouse_mode n'est pas fiable en tête sans fenêtre
## réelle"). La solution retenue est celle déjà utilisée par le jeu pour piloter
## un joueur headless : `PlayerInput._physics_process` ne touche JAMAIS aux
## champs si `is_bot == true` (`if is_bot: return`, avant toute lecture du
## singleton Input) — exactement le mécanisme par lequel BotBrain.gd pilote un
## bot. On bascule donc le joueur hôte en `is_bot = true` juste après le spawn
## (voir `_boot_main_arena`/`_check_spawn_on_map`) puis on écrit ses champs
## `input.*` nous-mêmes, comme le ferait BotBrain — sans jamais toucher au
## regard (`look_delta` reste à zéro, on repositionne directement `rotation`).

## Logger custom (Godot 4.7, OS.add_logger) qui compte les ERREURS réelles
## (push_error / erreurs script), en ignorant les simples avertissements.
class CountingLogger extends Logger:
	var count: int = 0
	var last_messages: Array = []
	func _log_error(_function: String, _file: String, _line: int, _code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array) -> void:
		# ErrorHandlerType : 0 = ERROR, 1 = WARNING, 2 = SCRIPT, 3 = SHADER.
		if error_type == 0 or error_type == 2:
			count += 1
			last_messages.append(rationale)
			if last_messages.size() > 20:
				last_messages.pop_front()

var _out_dir: String = DEFAULT_OUT
var _checks: Array = []
var _logger: CountingLogger
var _started: bool = false
var _t0_msec: int = 0

var _world: Node = null
var _player: PlayerController = null

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)
	_logger = CountingLogger.new()
	OS.add_logger(_logger)

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_t0_msec = Time.get_ticks_msec()
		_run()
		return false
	return false  # `_run()` appelle `quit()` lui-même quand c'est fini.

# ==========================================================================
#  ORCHESTRATION
# ==========================================================================
func _run() -> void:
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = ""
	MatchConfig.bots_enabled = false
	MatchConfig.team_size = 1

	# Pas de `net.host()` explicite ici : `GameWorld._ready()` héberge déjà
	# tout seul si `multiplayer.multiplayer_peer` est nul (voir GameWorld.gd) —
	# un appel séparé ici serait redondant et peut échouer bêtement si le port
	# est encore en TIME_WAIT (process précédent tout juste fermé), polluant
	# le compteur d'erreurs pour rien.
	await _boot_main_arena()
	if _player == null:
		_add_check("boot", false, "le joueur hôte n'a jamais spawné dans test_arena")
		_finish()
		return

	# ---- États de mouvement : tir ----
	await _run_fire_state_checks()

	# ---- Reste des mécaniques (même arène, même joueur) ----
	# Nettoyage du prototype 2026-09-26 : plus de capacités (AbilityController/
	# AgentDatabase ne connaît plus que Verrou, sans capacité) — `_check_
	# abilities` est retiré avec le nœud "Abilities", qui n'existe plus sur
	# le joueur.
	if _budget_left():
		await _check_reload()
	if _budget_left():
		await _check_weapon_switch()
	if _budget_left():
		await _check_ads()
	if _budget_left():
		await _check_damage_and_death()
	if _budget_left():
		await _check_movement_sanity()

	# `_world` (test_arena, group "match" depuis GameWorld._ready) n'est plus
	# utile après les checks ci-dessus : le libérer AVANT les étapes suivantes
	# est nécessaire, pas juste propre — `_check_round_flows` instancie sa
	# PROPRE `GameWorld` (aussi taguée "match"), et `get_first_node_in_group
	# ("match")` renvoie le PREMIER nœud du groupe : sans ce nettoyage, un
	# `_world` encore présent reste retourné à la place de l'instance
	# courante.
	if _world and is_instance_valid(_world):
		_world.free()
		_world = null
		_player = null
		await _wait_physics(4)

	# ---- Spawn non bloqué sur chaque map du catalogue ----
	if _budget_left():
		await _check_spawn_on_all_maps()

	# ---- Cycle manche/match de chaque mode ----
	if _budget_left():
		await _check_round_flows()

	_finish()

func _budget_left() -> bool:
	var elapsed := (Time.get_ticks_msec() - _t0_msec) / 1000.0
	if elapsed >= TIME_BUDGET_SEC:
		_add_check("time_budget", false, "budget de %.0fs dépassé (%.1fs écoulées) — vérifications restantes ignorées" % [TIME_BUDGET_SEC, elapsed])
		return false
	return true

func _finish() -> void:
	Engine.time_scale = 1.0
	var ok_count := 0
	for c in _checks:
		if bool(c["ok"]):
			ok_count += 1
	var all_ok := ok_count == _checks.size() and _checks.size() > 0
	var out := {"checks": _checks, "errors": _logger.count}
	_write_json(_out_dir.path_join("gameplay_probe.json"), out)
	print("GAMEPLAY_PROBE ok=%s checks=%d/%d errors=%d" % [all_ok, ok_count, _checks.size(), _logger.count])
	quit(0 if all_ok else 1)

func _write_json(path: String, data: Dictionary) -> void:
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var dir := abs_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
	else:
		print("GAMEPLAY_PROBE_WARN impossible d'écrire ", abs_path)

func _add_check(name: String, ok: bool, detail: String) -> void:
	_checks.append({"name": name, "ok": ok, "detail": detail})
	print("CHECK %s ok=%s — %s" % [name, ok, detail])

# ==========================================================================
#  BOOT — test_arena.tscn, un seul joueur (l'hôte), pas de bot
# ==========================================================================
func _boot_main_arena() -> void:
	var packed := load(TEST_ARENA) as PackedScene
	if packed == null:
		return
	_world = packed.instantiate()
	if _world.get("agent_select") != null:
		_world.set("agent_select", false)
	if _world.get("allow_bot_fill") != null:
		_world.set("allow_bot_fill", false)
	root.add_child(_world)
	current_scene = _world
	_player = await _wait_for_local_player(6.0)
	if _player:
		_player.is_bot = true  # voir la note en tête de fichier : pilotage direct de `input.*`

func _wait_for_local_player(timeout: float) -> PlayerController:
	var t := 0.0
	while t < timeout:
		# Filtre les instances invalides/en cours de libération : entre deux
		# maps du catalogue, la scène précédente est `queue_free()`ée — sans
		# ce filtre, une frame de recouvrement pourrait renvoyer le joueur de
		# la map d'AVANT (encore dans le groupe le temps que sa suppression
		# différée se propage), qu'on piloterait alors qu'il n'existe déjà plus.
		for n in get_nodes_in_group("local_player"):
			if is_instance_valid(n) and not (n as Node).is_queued_for_deletion():
				return n as PlayerController
		await physics_frame
		t += 1.0 / 60.0
	return null

func _host_id() -> int:
	# `SceneTree` n'a pas de propriété `multiplayer` (ça, c'est sur `Node`) —
	# `get_multiplayer()` est l'accès correct depuis un script `extends SceneTree`.
	return get_multiplayer().get_unique_id()

func _weapon() -> Weapon:
	return _player.get_node_or_null("Weapon") as Weapon

# ==========================================================================
#  UTILITAIRES D'ATTENTE / D'ENTRÉE
# ==========================================================================
func _wait_physics(n: int = 1) -> void:
	for i in n:
		await physics_frame

## Attend `seconds` de temps SIMULÉ (respecte Engine.time_scale — utilisé pour
## accélérer les délais de gameplay pendant les checks round_flow/spawn).
func _wait_sim(seconds: float) -> void:
	await create_timer(seconds).timeout

## Remet le joueur dans un état "propre" avant chaque check indépendant :
## relâche toutes les entrées (`PlayerInput.clear()`, la même fonction pure
## que PlayerInput utilise pour un humain sans souris), replace au point de
## spawn, vide la vélocité, force l'état Idle (API normale de la state
## machine — pas une triche du check lui-même, juste une remise à zéro entre
## deux vérifications isolées), recharge les munitions et la vie.
func _reset_player() -> void:
	_player.input.clear()
	_player.velocity = Vector3.ZERO
	_player.global_position = _player.spawn_point
	_player.rotation = Vector3.ZERO
	_player.head.rotation = Vector3.ZERO
	# `spawn_point` est légèrement AU-DESSUS du sol (comme au vrai spawn : le
	# perso y tombe tout seul les toutes premières frames — invisible en jeu
	# normal). Juste après une téléportation, `is_on_floor()` reste celui du
	# TOUT DERNIER `move_and_slide()` (avant le téléport) : Idle.physics_update
	# le voit gelé à faux et rebondit une frame sur "Air" avant de ratterrir.
	# On laisse ce rebond se dérouler et se stabiliser (sinon un check lancé
	# juste après trouve le joueur en "Air" au lieu de "Idle") avant de forcer
	# l'état — timeout large (chute de qq cm, jamais long en pratique).
	var settle_t := 0
	while settle_t < 60 and not (_player.is_on_floor() and _player.state_machine.current_name == "Idle"):
		if _player.state_machine.current_name != "Idle" and _player.is_on_floor():
			_player.state_machine.transition_to("Idle")
		await physics_frame
		settle_t += 1
	if _player.state_machine.current_name != "Idle":
		_player.state_machine.transition_to("Idle")
	var w := _weapon()
	if w:
		# `server_refill_ammo()` pousse l'inventaire SERVEUR (autoritaire) au
		# propriétaire via `_apply_sync` (l'hôte est les deux à la fois) : le
		# remettre sur le slot 0 (Ravage) et couper un rechargement en cours
		# AVANT l'appel suffit, la synchro écrase `_inv` derrière.
		if w._server_inv:
			w._server_inv.reloading = false
			w._server_inv.reload_left = 0.0
			if w._server_inv.current != 0:
				w._server_inv.equip(0)
		w.server_refill_ammo()
	var hp := _player.get_node_or_null("Health") as Health
	if hp:
		hp.reset()
	# Laisse les minuteries de "sensation d'arme" (WeaponFeel._since_slide/
	# _since_dive — délai de tir après un slide/dive du check PRÉCÉDENT)
	# retomber largement sous leur seuil (~0.3-0.56s selon l'arme) avant
	# d'attaquer le check suivant, sans quoi un test SANS AUCUN rapport avec
	# le slide/dive pourrait voir son tir refusé par un reliquat de délai.
	await _wait_physics(90)

# ==========================================================================
#  FIRE_IN_STATE — pilote l'entrée dans chaque état puis vérifie le tir
# ==========================================================================
func _run_fire_state_checks() -> void:
	await _reset_player()
	await _check_fire_in_state("Idle", false, "aucune entrée : reste Idle")

	await _reset_player()
	await _enter_walk()
	await _check_fire_in_state("Walk", false, "marche (Shift + avancer)")

	await _reset_player()
	await _enter_sprint()
	await _check_fire_in_state("Sprint", false, "course auto (avancer sans Shift)")

	await _reset_player()
	await _enter_crouch()
	await _check_fire_in_state("Crouch", false, "accroupi (Ctrl maintenu)")

	await _reset_player()
	await _enter_sprint()
	await _enter_slide_from_sprint()
	await _check_fire_in_state("Slide", false, "glissade active : tir permis (GF-30)")

	await _reset_player()
	await _enter_air()
	await _check_fire_in_state("Air", false, "en l'air après un saut")

	await _reset_player()
	await _enter_dive()
	await _check_fire_in_state("Dive", true, "plongée (restriction voulue)")
	await _wait_until_state("Roll", 2.5)
	if _player.state_machine.current_name == "Roll":
		await _check_fire_in_state("Roll", true, "roulade d'atterrissage (restriction voulue)")
	else:
		_add_check("fire_in_state:Roll", false, "état Roll jamais atteint après la plongée (timeout)")

	await _reset_player()
	await _enter_stun_via_fall()
	if _player.state_machine.current_name == "Stun":
		await _check_fire_in_state("Stun", false, "étourdissement de chute : tir permis, +3° (GF-29)")
	else:
		_add_check("fire_in_state:Stun", false, "état Stun jamais atteint après une grosse chute (timeout)")

## Vérifie l'état courant puis presse/relâche le tir : `expect_blocked` vient
## de la table en tête de fichier. `ok` == résultat conforme à la table.
func _check_fire_in_state(state_name: String, expect_blocked: bool, note: String) -> void:
	var name := "fire_in_state:%s" % state_name
	if _player.state_machine.current_name != state_name:
		_add_check(name, false, "état non atteint (actuel=%s) — %s" % [_player.state_machine.current_name, note])
		return
	var w := _weapon()
	var ammo_before: int = w._inv.mag[w._inv.current] if w._inv.mag.size() > w._inv.current else 0
	var rejected_before: int = w.rejected_shots
	# `fire_pressed` (une frame, semi-auto) ET `fire_held` (maintenu, auto) :
	# couvre les deux `WeaponConfig.automatic` sans avoir à l'inspecter ici.
	_player.input.fire_pressed = true
	_player.input.fire_held = true
	await _wait_physics(1)
	_player.input.fire_pressed = false
	await _wait_physics(7)
	_player.input.fire_held = false
	await _wait_physics(2)
	var ammo_after: int = w._inv.mag[w._inv.current] if w._inv.mag.size() > w._inv.current else 0
	var rejected_after: int = w.rejected_shots
	var fired := ammo_after < ammo_before
	var ok: bool
	var detail: String
	if expect_blocked:
		ok = not fired
		detail = "%s — munitions %d->%d (%s)" % [note, ammo_before, ammo_after, "bloqué comme attendu" if ok else "MUNITIONS ONT BAISSÉ — restriction cassée"]
	else:
		ok = fired and rejected_after == rejected_before
		detail = "%s — munitions %d->%d, refusés %d->%d (%s)" % [note, ammo_before, ammo_after, rejected_before, rejected_after,
			"tir accepté" if ok else "TIR NON ACCEPTÉ ALORS QU'IL DEVRAIT L'ÊTRE"]
	_add_check(name, ok, detail)

func _wait_until_state(state_name: String, timeout: float) -> void:
	var t := 0.0
	while _player.state_machine.current_name != state_name and t < timeout:
		await physics_frame
		t += 1.0 / 60.0

# ---- Entrées d'état, via l'abstraction d'entrée (player.input, voir note d'en-tête) --------
func _enter_walk() -> void:
	_player.input.walk_held = true
	_player.input.move = Vector2(0, -1)  # avant (voir test_player_input.gd : forward => y < 0)
	await _wait_physics(3)

func _enter_sprint() -> void:
	_player.input.walk_held = false
	_player.input.move = Vector2(0, -1)
	await _wait_physics(20)  # laisse ground_accel amener la vitesse à sprint_speed

func _enter_crouch() -> void:
	_player.input.crouch_held = true
	await _wait_physics(3)

## À appeler juste APRÈS `_enter_sprint()` (vitesse déjà >= slide_min_speed) :
## un tap de crouch pendant le sprint déclenche la glissade (Sprint.gd). Garder
## `crouch_held` vrai APRÈS le tap : Slide.physics_update annule la glissade
## (`_exit_to_ground`) dès que `crouch_held` repasse à faux (slide-cancel).
func _enter_slide_from_sprint() -> void:
	_player.input.crouch_pressed = true
	_player.input.crouch_held = true
	await _wait_physics(1)
	_player.input.crouch_pressed = false
	await _wait_physics(2)

func _enter_air() -> void:
	_player.input.jump_pressed = true
	_player.input.jump_held = true
	await _wait_physics(1)
	_player.input.jump_pressed = false
	_player.input.jump_held = false
	await _wait_physics(1)

func _enter_dive() -> void:
	_player.input.dive_pressed = true
	await _wait_physics(1)
	_player.input.dive_pressed = false
	await _wait_physics(1)

## Simule une GROSSE chute réelle (au-delà de fall_max_height) pour déclencher
## Stun via le pipeline normal (`PlayerController._check_fall_stun`) : seul le
## point de départ est téléporté, la chute/l'atterrissage passent par la
## vraie gravité — pas un `transition_to("Stun")` direct.
func _enter_stun_via_fall() -> void:
	var cfg := _player.config
	_player.global_position = _player.spawn_point + Vector3(0, cfg.fall_max_height + 3.0, 0)
	_player.velocity = Vector3.ZERO
	await _wait_until_state("Stun", 4.0)

# ==========================================================================
#  RELOAD
# ==========================================================================
func _check_reload() -> void:
	await _reset_player()
	var w := _weapon()
	var c := w.cfg()
	# Vide le chargeur (propriétaire + serveur, même joueur ici) pour garantir
	# un VRAI rechargement, pas un no-op sur chargeur déjà plein.
	w._inv.mag[w._inv.current] = 0
	if w._server_inv:
		w._server_inv.mag[w._server_inv.current] = 0
	w._emit_local()
	await _wait_physics(1)

	_player.input.reload_pressed = true
	await _wait_physics(3)
	var started := w._inv.reloading
	_player.input.reload_pressed = false

	# Tenter de tirer PENDANT le rechargement : ne doit rien consommer.
	var ammo_before_fire := w._inv.mag[w._inv.current]
	_player.input.fire_pressed = true
	_player.input.fire_held = true
	await _wait_physics(5)
	_player.input.fire_pressed = false
	_player.input.fire_held = false
	var ammo_mid_reload := w._inv.mag[w._inv.current]
	var blocked_mid_reload := ammo_mid_reload == ammo_before_fire

	var reload_time: float = c.reload_time if c else 1.8
	await _wait_sim(reload_time + Weapon.RELOAD_TOLERANCE + 0.4)
	var ammo_final := w._inv.mag[w._inv.current]
	var mag_size: int = c.mag_size if c else -1
	var refilled := ammo_final > ammo_before_fire and not w._inv.reloading

	var ok := started and blocked_mid_reload and refilled
	_add_check("reload", ok, "started=%s bloqué_pendant=%s munitions_finales=%d/%d" % [started, blocked_mid_reload, ammo_final, mag_size])

# ==========================================================================
#  WEAPON_SWITCH — prototype à une seule arme (Ravage, slot 0) : le slot 1
#  (WeaponDatabase n'a plus qu'une entrée, nettoyage du prototype 2026-09-26)
#  reste un emplacement VIDE — appuyer dessus ne doit ni planter ni changer
#  l'arme équipée (Weapon._handle_switch_input -> _try_equip(1) ->
#  Inventory.equip(1) refuse un slot sans arme, comportement inchangé).
# ==========================================================================
func _check_weapon_switch() -> void:
	await _reset_player()
	var w := _weapon()
	var errors_before := _logger.count
	_player.input.weapon_slot_pressed = 0
	await _wait_physics(4)
	_player.input.weapon_slot_pressed = -1
	await _wait_physics(3)
	var slot0_ok := w._inv.current == 0
	_player.input.weapon_slot_pressed = 1
	await _wait_physics(4)
	_player.input.weapon_slot_pressed = -1
	await _wait_physics(3)
	var empty_slot_rejected := w._inv.current == 0
	var no_new_errors := _logger.count == errors_before
	var ok := slot0_ok and empty_slot_rejected and no_new_errors
	_add_check("weapon_switch", ok, "slot0:%s slot1(vide):%s current_final=%d erreurs+%d" % [
		"ok" if slot0_ok else "FAIL", "rejeté comme attendu" if empty_slot_rejected else "A CHANGÉ D'ARME ALORS QUE LE SLOT EST VIDE",
		w._inv.current, _logger.count - errors_before,
	])

# ==========================================================================
#  ADS (si l'arme le supporte)
# ==========================================================================
func _check_ads() -> void:
	await _reset_player()
	var w := _weapon()
	_player.input.aim_held = true
	await _wait_physics(3)
	var aim_fov := w.current_aim_fov()
	var ammo_before: int = w._inv.mag[w._inv.current]
	_player.input.fire_pressed = true
	_player.input.fire_held = true
	await _wait_physics(8)
	_player.input.fire_pressed = false
	_player.input.fire_held = false
	var ammo_after: int = w._inv.mag[w._inv.current]
	_player.input.aim_held = false
	await _wait_physics(2)
	var fired := ammo_after < ammo_before
	var fov_ok := aim_fov > 0.0 and aim_fov <= _player.config.base_fov + 0.01
	var ok := fired and fov_ok
	_add_check("ads", ok, "aim_fov=%.1f (base=%.1f) tir_en_visée=%s (%d->%d)" % [aim_fov, _player.config.base_fov, fired, ammo_before, ammo_after])

# ==========================================================================
# Nettoyage du prototype 2026-09-26 (« strip to minimal prototype ») :
# capacités/passifs supprimés (AbilityController/AbilityState/Ability n'
# existent plus, AgentDatabase.all() ne renvoie plus que Verrou, sans
# capacité) — `_check_abilities` (qui pilotait le nœud "Abilities", absent
# du joueur désormais) est retiré avec eux.

# ==========================================================================
#  DAMAGE_AND_DEATH — mannequin d'entraînement (test_arena.tscn/Dummies/Dummy1)
# ==========================================================================
func _check_damage_and_death() -> void:
	var dummy := _world.get_node_or_null("Dummies/Dummy1")
	if dummy == null:
		_add_check("damage_and_death", false, "Dummies/Dummy1 introuvable dans test_arena.tscn")
		return
	var hp: Health = dummy.get_node("Health")
	hp.reset()
	await _wait_physics(2)
	var before := hp.current_health
	hp.apply_damage(40.0, _host_id())
	await _wait_physics(2)
	var after_partial := hp.current_health
	var took_damage := after_partial < before and not hp.is_dead
	hp.apply_damage(99999.0, _host_id())
	await _wait_physics(2)
	var died := hp.is_dead
	await _wait_sim(dummy.reset_delay + 0.5)
	var respawned := not hp.is_dead and hp.current_health > 0.0
	var ok := took_damage and died and respawned
	_add_check("damage_and_death", ok, "vie %.0f->%.0f, mort=%s, réinitialisé=%s" % [before, after_partial, died, respawned])

# ==========================================================================
#  MOVEMENT SANITY — hauteur de saut / vitesse de sprint (docs/MOVEMENT.md)
# ==========================================================================
func _check_movement_sanity() -> void:
	await _reset_player()
	var cfg := _player.config
	var start_pos := _player.global_position

	_player.input.move = Vector2(0, -1)
	await _wait_physics(30)
	var speed := _player.horizontal_speed()
	_player.input.move = Vector2.ZERO
	var expected_sprint: float = cfg.sprint_speed
	var sprint_ok := speed >= expected_sprint * 0.9 and speed <= expected_sprint * 1.1
	_add_check("movement_sanity:sprint_speed", sprint_ok, "%.2f m/s mesuré (attendu %.2f ±10%%)" % [speed, expected_sprint])

	var moved := start_pos.distance_to(_player.global_position)
	_add_check("spawn_not_stuck:test_arena", moved > 1.0, "déplacement=%.2fm après 0.5s d'avance" % moved)

	await _reset_player()
	var start_y := _player.global_position.y
	var peak_y := start_y
	_player.input.jump_pressed = true
	await _wait_physics(1)
	_player.input.jump_pressed = false
	var t := 0
	while t < 120:
		await physics_frame
		peak_y = maxf(peak_y, _player.global_position.y)
		if _player.velocity.y <= 0.0 and _player.state_machine.current_name == "Air":
			break
		t += 1
	var measured_height := peak_y - start_y
	var expected_height: float = (cfg.jump_velocity * cfg.jump_velocity) / (2.0 * cfg.gravity)
	var jump_ok := measured_height >= expected_height * 0.9 and measured_height <= expected_height * 1.1
	_add_check("movement_sanity:jump_height", jump_ok, "%.2fm mesuré (attendu %.2fm ±10%%)" % [measured_height, expected_height])

# ==========================================================================
#  SPAWN NON BLOQUÉ — chaque map de MapCatalog
# ==========================================================================
func _check_spawn_on_all_maps() -> void:
	for m in MapCatalog.all():
		if not _budget_left():
			return
		await _check_spawn_on_map(m as Dictionary)

func _check_spawn_on_map(entry: Dictionary) -> void:
	var id := String(entry["id"])
	var check_name := "spawn_not_stuck:%s" % id
	var modes: Array = entry["modes"]
	MatchConfig.set_mode(String(modes[0]) if not modes.is_empty() else "tdm")
	MatchConfig.map_id = id
	MatchConfig.bots_enabled = false
	var packed := load(String(entry["scene"])) as PackedScene
	if packed == null:
		_add_check(check_name, false, "scène introuvable : %s" % entry["scene"])
		return
	var inst := packed.instantiate()
	if inst.get("agent_select") != null:
		inst.set("agent_select", false)
	if inst.get("allow_bot_fill") != null:
		inst.set("allow_bot_fill", false)
	root.add_child(inst)
	current_scene = inst
	var player := await _wait_for_local_player(8.0)
	if player == null:
		_add_check(check_name, false, "joueur non spawné après 8s (navmesh/geo trop lent, ou spawn cassé)")
		inst.free()
		await _wait_physics(2)
		return
	# BUG-24 : `_wait_for_local_player` peut, en théorie, renvoyer un joueur qui
	# n'appartient pas à CETTE instance (fantôme d'une carte précédente resté
	# dans le groupe "local_player" le temps que sa suppression se propage,
	# malgré le filtre `is_queued_for_deletion()` — voir la note de la fonction).
	# Double vérification, avant tout pilotage :
	#   1) le nœud appartient bien à `inst`, la scène qu'on vient d'instancier ;
	#   2) sa position COÏNCIDE avec SON PROPRE `spawn_point` — `GameWorld._spawn_player`
	#      pose `player.position = spawn` ET `player.spawn_point = spawn` à la MÊME
	#      valeur, AVANT l'ajout à l'arbre (voir GameWorld.gd) : un vrai spawn frais
	#      n'a donc dérivé que de qq cm de chute libre à cet instant, alors qu'un
	#      fantôme réutilisé (déjà déplacé pendant le check de la carte précédente)
	#      serait loin du sien. C'est cette vérification par `spawn_point` qui
	#      garantit qu'on teste bien "le joueur réellement apparu sur CETTE carte".
	if not inst.is_ancestor_of(player):
		_add_check(check_name, false, "joueur trouvé hors de la scène de %s — joueur fantôme d'une carte précédente" % id)
		inst.free()
		await _wait_physics(2)
		return
	var spawn_ref: Vector3 = player.spawn_point
	var spawn_drift := Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(spawn_ref.x, spawn_ref.z))
	if spawn_drift > 0.5:
		_add_check(check_name, false, "joueur suspect sur %s : position %s loin de son spawn_point %s (écart %.2fm) — joueur fantôme probable" % [id, player.global_position, spawn_ref, spawn_drift])
		inst.free()
		await _wait_physics(2)
		return
	player.is_bot = true  # voir la note d'en-tête : pilotage direct de `input.*`
	await _wait_physics(4)
	# Les maps duel/duo (la_fosse, le_belvedere : seuls modes supportés) font
	# construire un DuelMode par MapSetup dès `MatchConfig.mode_id="duel"` —
	# RoundMode verrouille le mouvement (`movement_locked`) pendant TOUT le
	# BUY/PREROUND (3 s par défaut), via un `call_deferred("_enter_buy_phase")`
	# posé par RoundMode._ready() : il ne s'exécute qu'APRÈS le `_wait_physics`
	# ci-dessus, donc un dé-verrouillage fait AVANT serait aussitôt réécrasé.
	# On le lève ICI (après coup) et on le RÉ-AFFIRME à chaque segment de
	# direction ci-dessous par sécurité. C'est un verrou VOULU (round_flow:
	# duel/duo le vérifie séparément) — ce check-ci ne teste QUE "le spawn
	# coince-t-il physiquement", donc on le contourne sans jouer tout le cycle.
	player.movement_locked = false
	var start := spawn_ref  # référence = spawn_point vérifié ci-dessus, pas une simple lecture après coup
	Engine.time_scale = 4.0
	# Les marqueurs de spawn de ces maps regardent DÉLIBÉRÉMENT un "bouclier"
	# tout proche (maps-spec.md §3 "blocks every pair", voir aussi les
	# commentaires de tools/map_shots.gd sur ce même point) : "avancer" peut
	# donc buter sur un mur à quelques dizaines de cm PAR CONCEPTION. On
	# cycle avant/arrière/gauche/droite sur les 2 s simulées — un spawn
	# réellement coincé reste bloqué dans les 4 directions, un spawn normal
	# (juste un bouclier devant) se dégage dans au moins une des trois autres.
	# BUG-24 : `_wait_sim` attend un TEMPS RÉEL (Timer d'idle frame), dont le
	# nombre de ticks physiques réellement traversés peut varier de ±1 d'une
	# exécution à l'autre (ordonnancement OS en headless) — sur une carte dont
	# le dégagement est tout juste au-dessus du seuil de 1 m (ex. saint_ombre),
	# ce ±1 tick suffisait à faire basculer le verdict (0.81 m un coup, 1.15 m
	# le suivant) : "verdict stable sur deux exécutions" cassé. On avance donc
	# par un compte FIXE de ticks physiques — déterministe, comme partout
	# ailleurs dans ce fichier — équivalent à 0.5 s simulées à `time_scale`
	# donné (`Engine.time_scale` accélère le `delta` de chaque tick, pas la
	# fréquence des ticks : voir PerfOverlay.gd pour le même calcul).
	var ticks_per_dir := int(round(0.5 * Engine.physics_ticks_per_second / Engine.time_scale))
	for dir_vec in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
		player.movement_locked = false
		player.input.move = dir_vec
		await _wait_physics(ticks_per_dir)
	player.input.move = Vector2.ZERO
	Engine.time_scale = 1.0
	await _wait_physics(2)
	# Distance HORIZONTALE seulement (XZ) : la chute résiduelle depuis un
	# marqueur de spawn légèrement surélevé (comme partout ailleurs dans ce
	# fichier) ne doit pas se compter comme un "déplacement" et masquer un
	# joueur réellement coincé horizontalement.
	var end_pos := player.global_position
	var moved := Vector2(start.x, start.z).distance_to(Vector2(end_pos.x, end_pos.z))
	_add_check(check_name, moved > 1.0, "déplacement=%.2fm (avant/arrière/gauche/droite, 0.5s chacun) depuis son spawn_point vérifié %s" % [moved, start])
	inst.free()
	await _wait_physics(8)

# ==========================================================================
#  ROUND_FLOW — cycle manche/match de chaque mode (MatchConfig.MODES)
# ==========================================================================
func _check_round_flows() -> void:
	# Nettoyage du prototype 2026-09-26 : SnD/Duel/Duo/Hardpoint (et leurs
	# scènes snd_map.tscn/duel_arena.tscn, qui n'ont jamais existé sous
	# scenes/levels/ — déjà des références mortes avant ce nettoyage) ont été
	# supprimés avec leurs modes — TDM (MatchConfig.MODES == ["tdm"]) est
	# désormais le seul flux de manche/match vérifié ici.
	if _budget_left():
		await _round_flow("tdm", "res://scenes/levels/tdm_map.tscn", 1)

func _round_flow(mode_id: String, scene_path: String, team_size: int) -> void:
	Engine.time_scale = 1.0  # filet de sécurité si un check précédent a quitté tôt sans le restaurer.
	var check_name := "round_flow:%s" % mode_id
	MatchConfig.set_mode(mode_id)
	MatchConfig.map_id = ""
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = team_size

	var packed := load(scene_path) as PackedScene
	if packed == null:
		_add_check(check_name, false, "scène introuvable : %s" % scene_path)
		return
	var inst := packed.instantiate() as GameWorld
	if inst.get("agent_select") != null:
		inst.set("agent_select", false)
	if inst.get("allow_bot_fill") != null:
		inst.set("allow_bot_fill", true)

	# Scène STATIQUE (GameMode déjà présent, ex. tdm_map.tscn) : accélère
	# AVANT le premier _ready() (score_to_win pris en compte dès la
	# construction). Map MapSetup (ex. wasteland) : le nœud GameMode
	# n'existe pas encore à ce stade (construit dynamiquement dans
	# MapSetup._enter_tree) — ajusté juste après, avant qu'aucun score réel
	# n'ait pu se produire.
	var static_mode := inst.get_node_or_null("GameMode")
	if static_mode:
		_speed_up_mode(static_mode)

	root.add_child(inst)
	current_scene = inst

	var mode := await _wait_for_game_mode(6.0)
	if mode == null:
		_add_check(check_name, false, "aucun nœud du groupe \"game_mode\" après 6s")
		inst.free()
		return
	if static_mode == null:
		_speed_up_mode(mode)  # cas MapSetup : personne n'a encore pu scorer.

	var t := 0.0
	while inst.player_info.size() < 2 and t < 12.0:
		await physics_frame
		t += 1.0 / 60.0
	if inst.player_info.size() < 2:
		_add_check(check_name, false, "le bot de remplissage n'est jamais apparu après 12s")
		inst.free()
		return

	var host_id := _host_id()
	var players := inst.get_node(inst.players_root)
	var host_node := players.get_node_or_null(str(host_id))
	if host_node == null:
		_add_check(check_name, false, "joueur hôte introuvable sous Players")
		inst.free()
		return
	var host_team := int(host_node.get("team"))

	await _round_flow_single_kill(check_name, mode, players, host_team, host_id)

	inst.free()
	await _wait_physics(15)

## Tue tous les ennemis vivants de `host_team` sous `players` (attaquant =
## `host_id`) ; renvoie VRAI si au moins un ennemi a RÉELLEMENT été éliminé
## (revérifie `hp.is_dead` APRÈS l'appel — `Health.apply_damage` est un no-op
## SILENCIEUX pendant une protection de spawn active (`_protection_left`),
## jamais signalé par une valeur de retour : un simple "l'appel a été fait"
## masquerait ce cas, faisant croire à un kill qui n'a jamais eu lieu).
func _kill_enemy_team(players: Node, host_team: int, host_id: int) -> bool:
	var killed_any := false
	for child in players.get_children():
		if int(child.get("team")) == host_team:
			continue
		var hp := child.get_node_or_null("Health") as Health
		if hp and not hp.is_dead:
			hp.apply_damage(999999.0, host_id)
			if hp.is_dead:
				killed_any = true
	return killed_any

## Modes SANS manches (TDM ici — Hardpoint a son propre check dédié,
## _round_flow_hardpoint, capture par zone) : une élimination doit produire
## directement un vainqueur de MATCH (`score_to_win = 1`, posé par
## _speed_up_mode).
func _round_flow_single_kill(check_name: String, mode: GameMode, players: Node, host_team: int, host_id: int) -> void:
	var errors_before := _logger.count
	var killed_any := _kill_enemy_team(players, host_team, host_id)

	var t3 := 0.0
	while mode.winner == -1 and t3 < 8.0:
		await physics_frame
		t3 += 1.0 / 60.0

	var ok := killed_any and mode.winner != -1 and _logger.count == errors_before
	var detail := "kill->winner=%d (aucun vainqueur = STUCK STATE)" % mode.winner
	if not killed_any:
		detail = "aucun ennemi trouvé à éliminer (team_size/bot fill cassé ?)"
	elif _logger.count != errors_before:
		detail += " — %d nouvelle(s) erreur(s) moteur pendant le cycle" % (_logger.count - errors_before)
	_add_check(check_name, ok, detail)

# Nettoyage du prototype 2026-09-26 : les modes à manches/zone (SnD/Duel/
# Duo/Hardpoint — `_round_flow_rounds`/`_round_flow_hardpoint`) ont été
# supprimés avec RoundMode/RoundState/HardpointMode — TDM (`_round_flow_
# single_kill` ci-dessus) est désormais le seul flux vérifié.

## Accélère le GameMode pour que le cycle tienne dans le budget de temps
## (configuration RUNTIME de l'instance, pas du code/des ressources —
## comportement 100% inchangé en dehors de ce script de revue).
func _speed_up_mode(mode: Node) -> void:
	mode.set("score_to_win", 1)

func _wait_for_game_mode(timeout: float) -> GameMode:
	var t := 0.0
	while t < timeout:
		var m := get_first_node_in_group("game_mode") as GameMode
		if m:
			return m
		await physics_frame
		t += 1.0 / 60.0
	return null
