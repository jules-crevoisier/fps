## hitbox_probe.gd
## Sonde de revue automatisée (headless, un seul process) : vérifie que le
## tir SERVEUR (Weapon._resolve_ray/WeaponMath.is_headshot) résout
## correctement la hitbox d'une cible ACCROUPIE dont la hauteur arrive par
## RÉPLICATION (GF-04 : `PlayerController._apply_body_height` appliquée côté
## non-autorité — voir tests/player/test_capsule_per_player.gd, qui isole le
## mécanisme de capsule sans jamais tirer dessus) :
##   - une cible accroupie voit sa capsule serveur RÉELLEMENT rétrécie
##     (`current_height`/capsule appliqués sur le pair NON-autorité, comme un
##     serveur qui observe un humain distant accroupi) ;
##   - un tir 10 cm AU-DESSUS de sa tête (donc au-dessus du sommet de la
##     capsule accroupie, mais largement EN DESSOUS de l'ancienne capsule
##     debout à 1,80 m) ne touche RIEN — avant GF-04, une capsule restée
##     debout aurait ici enregistré un impact corps ;
##   - un tir DANS sa tête (zone relative à 0,9 m accroupi, jamais le seuil
##     absolu 1,4 m de l'ancien code — WeaponMath.HEAD_HEIGHT_RATIO) compte
##     bien comme headshot ;
##   - debout, le seuil de tête (1,4 m, inchangé) continue de fonctionner
##     comme avant (garde de non-régression).
##
## Usage :
##   godot --headless --path . -s res://tools/review/hitbox_probe.gd -- --out=DIR
##
## Écrit "<out>/hitbox_probe.json" : {"checks":[{"name","ok","detail"}], "errors":int}.
## Imprime une ligne de résumé puis quitte 0 (tous les checks passent) ou 1 —
## comme tools/review/gameplay_probe.gd, `errors` (erreurs moteur réelles) est
## reporté dans le JSON mais n'influence PAS le code de sortie (le gate
## dédié vit dans tools/review/report.py, voir docs/REVIEW.md).
extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const DEFAULT_OUT := "res://.probe_out"

## Écart XZ (m) tireur -> cible : loin de toute géométrie (scène vide, aucun
## sol) mais très en-deçà de max_range (200 m par défaut, WeaponConfig.gd).
const SHOOTER_POS := Vector3(0.0, 1.0, 0.0)
const TARGET_POS := Vector3(5.0, 0.0, 0.0)
## Marge (m) au-dessus du sommet de la capsule accroupie pour le tir "raté"
## (contrat : "10 cm au-dessus de sa tête").
const MISS_MARGIN := 0.10
## Décalage (m) au-dessus du seuil de tête (WeaponMath.is_headshot est un
## test STRICTEMENT supérieur) pour retomber nettement DANS la zone de tête,
## jamais pile sur la frontière (évite un flanc de test fragile).
const HEAD_MARGIN := 0.05

## Logger custom (Godot 4.7, OS.add_logger) qui compte les ERREURS réelles
## (push_error / erreurs script), en ignorant les simples avertissements —
## identique à tools/review/gameplay_probe.gd (CountingLogger).
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

var _shooter: PlayerController
var _target: PlayerController
var _target_health: Health
var _weapon: Weapon
## Rempli par _on_hit_confirmed (voir Weapon.hit_confirmed) à chaque tir
## RÉSOLU côté tireur — vidé avant chaque tir par _fire_and_wait.
var _hit_log: Array = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)
	_logger = CountingLogger.new()
	OS.add_logger(_logger)

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
		return false
	return false  # `_run()` appelle `quit()` lui-même quand c'est fini.

# ==========================================================================
#  ORCHESTRATION
# ==========================================================================
func _run() -> void:
	await _setup()
	if _shooter == null or _target == null or _target_health == null or _weapon == null:
		_add_check("boot", false, "échec de l'instanciation tireur/cible (scenes/player/player.tscn)")
		_finish()
		return

	await _check_crouched_target_replicated_server_side()
	await _check_crouched_shot_above_head_misses()
	await _check_crouched_head_shot_is_headshot()
	await _check_standing_head_shot_unchanged()

	_finish()

func _finish() -> void:
	var ok_count := 0
	for c in _checks:
		if bool(c["ok"]):
			ok_count += 1
	var all_ok := ok_count == _checks.size() and _checks.size() > 0
	var out := {"checks": _checks, "errors": _logger.count}
	_write_json(_out_dir.path_join("hitbox_probe.json"), out)
	print("HITBOX_PROBE ok=%s checks=%d/%d errors=%d" % [all_ok, ok_count, _checks.size(), _logger.count])
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
		print("HITBOX_PROBE_WARN impossible d'écrire ", abs_path)

func _add_check(name: String, ok: bool, detail: String) -> void:
	_checks.append({"name": name, "ok": ok, "detail": detail})
	print("CHECK %s ok=%s — %s" % [name, ok, detail])

func _wait_physics(n: int = 1) -> void:
	for i in n:
		await physics_frame

# ==========================================================================
#  SETUP — un tireur BOT (autorité serveur, comme l'hôte/un bot) et une
#  cible dont l'id de nœud désigne un pair RÉEL distant (< BOT_ID_START,
#  jamais 1 : id local par défaut sans MultiplayerPeer, cf.
#  tests/player/test_capsule_per_player.gd::_remote_player) — sa hauteur
#  n'est donc JAMAIS recalculée localement (`_update_crouch_height` ne
#  tourne que côté autorité) : on la POSE directement, exactement comme le
#  ferait un MultiplayerSynchronizer qui reçoit la valeur répliquée par le
#  vrai joueur distant. Aucune scène de niveau chargée (pas de sol) : les
#  deux joueurs sont ajoutés directement sous `root`, comme
#  test_capsule_per_player.gd le fait sous son nœud de test.
# ==========================================================================
func _setup() -> void:
	_shooter = PLAYER_SCENE.instantiate()
	_shooter.name = str(PlayerController.BOT_ID_START)
	_shooter.set("is_bot", true)
	_shooter.position = SHOOTER_POS
	_shooter.set("spawn_point", SHOOTER_POS)
	root.add_child(_shooter)

	# Conteneur dédié (jamais de nœud "9001" dedans) pour la cible : isole-la
	# de tout FRÈRE nommé comme le tireur. Sans ça, Health._push_damage_direction
	# (flèche de direction du HUD, hors périmètre de ce check) retrouverait le
	# tireur comme frère (players.get_node_or_null(str(attacker_id))) et
	# tenterait un RPC CIBLÉ vers le pair "101" — qui n'est PAS un vrai pair
	# réseau connecté ici (juste un id simulé pour l'autorité, voir la note
	# plus haut), d'où "Attempt to call RPC with unknown peer ID: 101" : un
	# bruit d'artefact de ce test isolé, pas un bug de gameplay réel (en
	# vraie partie, ce pair EST un vrai client connecté). Isoler la cible
	# fait échouer proprement cette résolution de frère (Vector3.INF), comme
	# pour n'importe quel attaquant non identifiable — _push_damage_direction
	# renonce alors AVANT de tenter le RPC (voir Health.gd).
	var target_container := Node.new()
	target_container.name = "TargetContainer"
	root.add_child(target_container)

	_target = PLAYER_SCENE.instantiate()
	_target.name = "101"  # pair "distant" simulé : jamais 1, jamais >= BOT_ID_START.
	_target.position = TARGET_POS
	_target.set("spawn_point", TARGET_POS)
	target_container.add_child(_target)

	await _wait_physics(2)

	_target_health = _target.get_node_or_null("Health") as Health
	_weapon = _shooter.get_node_or_null("Weapon") as Weapon
	if _weapon:
		_weapon.hit_confirmed.connect(_on_hit_confirmed)

func _on_hit_confirmed(pos: Vector3, dmg: float, headshot: bool, is_kill: bool) -> void:
	_hit_log.append({"pos": pos, "dmg": dmg, "headshot": headshot, "is_kill": is_kill})

# ==========================================================================
#  TIR — reproduit exactement le chemin serveur (Weapon._do_request_fire ->
#  _server_fire, appel DIRECT ici : multiplayer.is_server() est vrai par
#  défaut sans MultiplayerPeer, comme tout le reste de ce fichier). Le tir
#  est mis en FILE côté serveur (_pending_shots) et résolu au TICK PHYSIQUE
#  suivant (_server_tick), d'où l'attente après l'appel.
# ==========================================================================
func _fire_and_wait(test_y: float) -> Dictionary:
	_hit_log.clear()
	# Repart d'un tireur/santé propres à chaque tir — indépendant des tirs
	# précédents (pas de dérive de gravité accumulée, cible jamais déjà morte).
	_shooter.global_position = SHOOTER_POS
	_shooter.velocity = Vector3.ZERO
	_target_health.reset()
	await _wait_physics(2)

	var origin := Vector3(SHOOTER_POS.x, test_y, SHOOTER_POS.z)
	var target_point := Vector3(TARGET_POS.x, test_y, TARGET_POS.z)
	var dir := (target_point - origin).normalized()
	var weapon_id := _weapon._server_inv.current_id()

	var rejected_before := _weapon.rejected_shots
	var health_before := _target_health.current_health
	_weapon._do_request_fire(origin, [dir], weapon_id)
	await _wait_physics(3)  # laisse _server_tick résoudre le tir en attente.

	return {
		"hit": _target_health.current_health < health_before,
		"headshot": not _hit_log.is_empty() and bool(_hit_log[0]["headshot"]),
		"health_before": health_before,
		"health_after": _target_health.current_health,
		"rejected_delta": _weapon.rejected_shots - rejected_before,
	}

# ==========================================================================
#  CHECKS
# ==========================================================================

## Précondition des 3 checks suivants : la cible accroupie a-t-elle une
## capsule SERVEUR réellement rétrécie (côté NON-autorité, cf. doc d'en-tête
## de fichier) ? Si ce check échoue, les checks de tir qui suivent tirent
## sur une hitbox déjà fausse — leur propre échec ne dirait pas POURQUOI.
func _check_crouched_target_replicated_server_side() -> void:
	_target.is_crouching = true
	_target.current_height = _target.config.crouch_height  # "reçu par réplication"
	await _wait_physics(3)

	var non_authority := not _target.is_multiplayer_authority()
	var height_ok := absf(_target.current_height - _target.config.crouch_height) < 0.001
	var capsule_ok := absf(_target.collision.shape.height - _target.config.crouch_height) < 0.01
	var ok := non_authority and height_ok and capsule_ok
	_add_check("crouched_target_replicated_server_side", ok,
		"pair non-autorité=%s current_height=%.3f capsule.height=%.3f (cible %.2fm)" % [
			non_authority, _target.current_height, _target.collision.shape.height, _target.config.crouch_height])

## "un tir 10 cm au-dessus de sa tête ne touche rien" : sommet de la capsule
## accroupie + 10 cm — largement sous l'ancienne capsule debout (1,80 m),
## donc un échec ici indique une capsule restée debout (régression GF-04).
func _check_crouched_shot_above_head_misses() -> void:
	var crouched_top: float = _target.current_height  # capsule = [0, current_height], voir doc d'en-tête.
	var test_y := crouched_top + MISS_MARGIN
	var r := await _fire_and_wait(test_y)
	var ok: bool = r["rejected_delta"] == 0 and not r["hit"]
	var reason: String
	if r["rejected_delta"] != 0:
		reason = "tir REFUSÉ par la validation anti-triche (ShotValidator) — problème de calibrage du test, pas du gameplay"
	elif r["hit"]:
		reason = "IMPACT INATTENDU — la capsule accroupie n'a pas rétréci comme attendu (régression GF-04 ?)"
	else:
		reason = "aucun impact, comme attendu"
	_add_check("crouched_target_shot_10cm_above_head_misses", ok,
		"tir horizontal à y=%.2fm (sommet capsule accroupie=%.2fm +%.0fcm) — vie %.1f->%.1f (%s)" % [
			test_y, crouched_top, MISS_MARGIN * 100.0, r["health_before"], r["health_after"], reason])

## "un tir dans la tête compte headshot" (cible accroupie) : dans la zone de
## tête RELATIVE à 0,9 m (WeaponMath.HEAD_HEIGHT_RATIO), jamais l'ancien
## seuil absolu 1,4 m — un tir à cette hauteur serait un corps (pas une tête)
## sous l'ancien code non-relatif.
func _check_crouched_head_shot_is_headshot() -> void:
	var crouch_height: float = _target.config.crouch_height
	var test_y := crouch_height * WeaponMath.HEAD_HEIGHT_RATIO + HEAD_MARGIN
	var r := await _fire_and_wait(test_y)
	var ok: bool = r["rejected_delta"] == 0 and r["hit"] and r["headshot"]
	var reason: String
	if r["rejected_delta"] != 0:
		reason = "tir REFUSÉ par la validation anti-triche (ShotValidator) — problème de calibrage du test, pas du gameplay"
	elif not r["hit"]:
		reason = "AUCUN IMPACT — attendu dans la zone de tête accroupie"
	elif not r["headshot"]:
		reason = "impact au CORPS, pas à la TÊTE — seuil relatif (crouch) pas appliqué (régression GF-04 ?)"
	else:
		reason = "headshot confirmé, comme attendu"
	_add_check("crouched_target_head_shot_is_headshot", ok,
		"tir horizontal à y=%.2fm (seuil tête accroupi=%.2fm) — vie %.1f->%.1f (%s)" % [
			test_y, crouch_height * WeaponMath.HEAD_HEIGHT_RATIO, r["health_before"], r["health_after"], reason])

## "debout inchangé" : garde de non-régression — le seuil de tête DEBOUT
## (1,4 m, inchangé par GF-04 — HEAD_HEIGHT_RATIO est calibré exprès pour
## retomber pile dessus, voir sa doc) continue de compter comme headshot.
func _check_standing_head_shot_unchanged() -> void:
	_target.is_crouching = false
	_target.current_height = _target.config.stand_height
	await _wait_physics(3)

	var stand_height: float = _target.config.stand_height
	var test_y := stand_height * WeaponMath.HEAD_HEIGHT_RATIO + HEAD_MARGIN
	var r := await _fire_and_wait(test_y)
	var ok: bool = r["rejected_delta"] == 0 and r["hit"] and r["headshot"]
	var reason: String
	if r["rejected_delta"] != 0:
		reason = "tir REFUSÉ par la validation anti-triche (ShotValidator) — problème de calibrage du test, pas du gameplay"
	elif not r["hit"]:
		reason = "AUCUN IMPACT — attendu dans la zone de tête debout"
	elif not r["headshot"]:
		reason = "impact au CORPS, pas à la TÊTE — régression sur le comportement debout (inchangé attendu)"
	else:
		reason = "headshot confirmé, comme avant GF-04 (comportement debout inchangé)"
	_add_check("standing_target_head_shot_unchanged", ok,
		"tir horizontal à y=%.2fm (seuil tête debout=%.2fm) — vie %.1f->%.1f (%s)" % [
			test_y, stand_height * WeaponMath.HEAD_HEIGHT_RATIO, r["health_before"], r["health_after"], reason])
