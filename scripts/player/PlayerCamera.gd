## PlayerCamera.gd
## Effets de caméra réactifs au mouvement : FOV dynamique (sprint/slide),
## inclinaison (tilt) en strafe, et head-bob au sol. Branche-toi sur le
## PlayerController parent. À mettre sur le Camera3D.
##
## Interpolation physique (GF-03, docs Godot "advanced physics interpolation") :
## la position du corps/de la tête n'avance qu'au tick physique (60 Hz par
## défaut) alors que l'écran peut rafraîchir bien plus vite (144 Hz) — sans
## rien faire, la caméra resterait figée plusieurs frames puis sauterait d'un
## coup ("motif 3-2"). On lit donc en _process la transform INTERPOLÉE de la
## tête (%Head, notre parent) pour la POSITION, tout en gardant la ROTATION
## souris strictement immédiate (jamais interpolée — sinon la visée accuserait
## un temps de retard perceptible) : voir `_apply_interpolated_transform`.
##
## `top_level = true` (mis en _ready) est l'AUTRE moitié obligatoire du
## pattern (doc Godot "Advanced physics interpolation" > Cameras) : sans lui,
## Godot recompose notre `global_transform` déjà lissée à partir de la
## transform LIVE (non interpolée) de %Head à chaque fois qu'on la relit — un
## retour en arrière (« feedback ») entre le parent mobile et la caméra qui
## peut réintroduire le retard ou la désynchronisation qu'on cherche
## justement à éliminer. `top_level` sort la caméra de la composition
## parent→enfant : `global_transform` devient alors la seule source de vérité,
## écrite une fois par frame ci-dessous, sans recomposition parasite.
##
## FOV (UX-02, docs/research/04_ui_ux.md §2.7/§3.1) : `Settings.fov` est
## désormais HORIZONTAL à 16:9 (défaut 103°, ex. Valorant/Overwatch 2) —
## converti ici en FOV VERTICAL (`Settings.hfov_to_vfov`) pour `Camera3D.fov`,
## qui reste vertical (`keep_aspect = KEEP_HEIGHT`, défaut Godot). Les bonus
## de FOV dynamique (sprint/slide/survitesse, `_update_fov`) sont plafonnés en
## cumul à `MAX_DYNAMIC_FOV_BONUS` et neutralisés si
## `Settings.fov_effects_enabled` est faux (`dynamic_fov_bonus`, fonction pure
## testée hors scène dans tests/player/test_fov.gd).
##
## Confort (UX-06, docs/research/04_ui_ux.md §2.7) : `Settings.camera_shake_enabled`
## désactive la secousse de caméra du Stun (voir `_process`) ET la secousse à
## trauma + le punch FOV ci-dessous (GF-08) ; `Settings.head_bob_enabled`/
## `head_bob_intensity` activent/désactivent et graduent le head-bob
## (`_update_bob`) — même principe que `fov_effects_enabled` ci-dessus.
##
## Secousse à trauma + punch FOV (GF-08, Eiserloh, docs/research/01_game_feel.md
## §2.1/§3, voir CameraShake.gd) : `_shake` (une `CameraShake`, classe PURE)
## accumule du trauma sur `add_shot_trauma`/`add_damage_trauma`/
## `add_explosion_trauma`, à appeler par les systèmes de tir/dégâts/explosion
## (hors du périmètre de cette tâche — voir son rendu) via `player.camera` (typé
## `PlayerCamera`, comme dans tests/player/test_fov.gd). `_process` avance
## `_shake` d'un pas et compose sa rotation dans `_apply_interpolated_transform`
## (même espace LOCAL que `_tilt_z`/`_roll_x`, jamais `rotation` — voir la note
## de tête sur `_bob_offset`) et son décalage de FOV par-dessus le résultat de
## `_update_fov` : `_last_fov_punch` retire l'ancien décalage AVANT de relire
## `fov` comme base « propre », pour que le lerp de `_update_fov` ne l'absorbe
## jamais dans sa propre convergence (le punch doit durer EXACTEMENT
## `CameraShake.PUNCH_FOV_HEAVY_DURATION`, pas la vitesse de `config.fov_lerp_speed`).
## `Settings.camera_shake_enabled`/`camera_shake_intensity`/`reduced_motion` sont
## combinés en UNE intensité effective par `CameraShake.effective_intensity`
## (jamais lus directement par la classe pure `CameraShake`).
class_name PlayerCamera
extends Camera3D

const INK_POST := preload("res://scripts/core/InkPost.gd")

## Bonus MAXIMUM cumulé des effets de FOV dynamique (sprint + slide +
## survitesse), quelles que soient les valeurs individuelles de
## `MovementConfig` (docs/research/04_ui_ux.md §3.1 — cible "effets
## dynamiques ≤ +5°, désactivables") : le plafond s'applique à la SOMME, pas à
## chaque source séparément, voir `dynamic_fov_bonus`.
const MAX_DYNAMIC_FOV_BONUS := 5.0

@export var player_path: NodePath
var player: PlayerController
var config: MovementConfig

var _bob_time: float = 0.0
## Décalage LOCAL (relatif à la tête) du head-bob — jamais lu depuis la
## propriété `position` du nœud : celle-ci n'est plus la source de vérité une
## fois la transform globale recomposée chaque frame (voir
## `_apply_interpolated_transform`), pour éviter qu'une reconstruction locale
## "polluée" par l'origine interpolée ne fausse le calcul de la frame suivante.
var _bob_offset: Vector3 = Vector3.ZERO

# Inclinaison de strafe (tilt, axe Z) et tangage additionnel de la roulade/du
# stun (axe X) — mêmes raisons : angles LOCAUX suivis à part, jamais relus
# depuis `rotation`.
var _tilt_z: float = 0.0
var _roll_x: float = 0.0

# Roulade (effet "machine à laver")
var _roll_t: float = -1.0
var _roll_dur: float = 0.65
var _roll_turns: float = 1.0
var _dizzy_t: float = 0.0
## Vrai si l'état Stun était déjà actif à la frame précédente — sert à
## détecter le FRONT D'ENTRÉE en Stun (voir `stun_dizzy_step`, BUG-20).
var _was_stun: bool = false

## Secousse à trauma + punch FOV (GF-08) — voir la note de tête de fichier.
var _shake := CameraShake.new()
## Décalage de FOV (degrés) ajouté par `_shake` à LA FRAME PRÉCÉDENTE — retiré
## avant de relire `fov` comme base « propre » pour `_update_fov` (voir
## `_process`), pour que le punch ne fuie jamais dans le lerp de FOV de base.
var _last_fov_punch: float = 0.0

## Lance l'animation de roulade : la caméra fait `turns` tour(s) complet(s)
## en `dur` secondes. Appelé par l'état Roll.
func play_roll(dur: float, turns: float = 1.0) -> void:
	_roll_dur = max(dur, 0.05)
	_roll_turns = turns
	_roll_t = 0.0

## Trauma de tir (GF-08) : `amount` vient du champ dédié de `WeaponConfig` de
## l'arme tirée (0.08-0.25 selon l'arme — CameraShake.SHOT_TRAUMA_MIN/MAX),
## reborné défensivement par `CameraShake.add_shot_trauma`. À appeler par
## Weapon.gd à chaque tir LOCAL confirmé (hors du périmètre de cette tâche —
## voir son rendu). Pour une arme lourde (`WeaponConfig.Category.HEAVY`),
## appeler aussi `punch_fov_heavy()`.
func add_shot_trauma(amount: float) -> void:
	_shake.add_shot_trauma(amount)

## Trauma de dégât reçu (0.3 fixe, GF-08). À appeler par Health.gd quand le
## joueur LOCAL encaisse des dégâts (hors du périmètre de cette tâche).
func add_damage_trauma() -> void:
	_shake.add_damage_trauma()

## Trauma d'explosion proche (0.6 fixe, GF-08). À appeler par la logique de
## grenade/explosion quand le joueur LOCAL est dans le rayon (hors du
## périmètre de cette tâche).
func add_explosion_trauma() -> void:
	_shake.add_explosion_trauma()

## Punch FOV -1.5° en 60 ms (GF-08) au tir d'une arme lourde
## (`WeaponConfig.Category.HEAVY`). À appeler par Weapon.gd en complément de
## `add_shot_trauma` (hors du périmètre de cette tâche).
func punch_fov_heavy() -> void:
	_shake.add_fov_punch(CameraShake.PUNCH_FOV_HEAVY_DEG, CameraShake.PUNCH_FOV_HEAVY_DURATION)

func _ready() -> void:
	if not player_path.is_empty():
		player = get_node(player_path) as PlayerController
	else:
		player = get_parent().get_parent() as PlayerController
	# On recompose nous-mêmes la transform globale chaque frame (position
	# interpolée + rotation immédiate, voir `_apply_interpolated_transform`) :
	# l'interpolation physique AUTOMATIQUE du moteur sur la caméra elle-même
	# ferait doublon (et retarderait ce calcul déjà lissé) — doc Godot
	# "advanced physics interpolation" > Exceptions > Cameras. Sans effet sur
	# la lecture `global_transform`/`global_position` en gameplay (utilisée
	# par `Weapon._fire_local` pour l'origine du tir) : ce mode ne pilote QUE
	# le lissage visuel côté rendu, jamais la transform "live" lue en script —
	# on peut donc le mettre à OFF pour TOUTES les instances (humain local,
	# bot, joueur distant simulé serveur) sans risque.
	set_physics_interpolation_mode(Node.PHYSICS_INTERPOLATION_MODE_OFF)
	if player:
		config = player.config
		fov = Settings.hfov_to_vfov(Settings.fov, Settings.REF_ASPECT_16_9)
		if player.is_local_human():
			# Post-traitement "encre" (contours d'arête plein écran) : SEULE la
			# caméra de l'humain local le porte — pas de coût pour les autres pairs
			# (ni pour un bot, qui n'a pas d'écran).
			var post := INK_POST.new()
			post.name = "InkPost"
			add_child(post)
			# Deuxième moitié obligatoire du pattern (même page de doc) : la
			# caméra doit être en espace GLOBAL, pas enfant transformé de
			# %Head, sinon un feedback entre le parent mobile et la caméra
			# corrompt l'interpolation (cf. tête de section ci-dessus). On ne
			# peut pas cocher la case dans la scène ici (player.tscn n'est
			# pas dans notre périmètre de fichiers) : on obtient exactement
			# le même effet en le mettant à true au runtime, avant la
			# première écriture de `global_transform`.
			#
			# RÉSERVÉ à l'humain local (`is_local_human()`), à dessein : SEUL
			# `_process` de cette instance appelle `_apply_interpolated_
			# transform` chaque frame (voir plus bas, même garde). Pour un
			# bot ou un joueur distant simulé serveur, `_process` sort tout
			# de suite (return anticipé ci-dessous) — passer cette caméra en
			# top_level la figerait alors définitivement à sa transform de
			# spawn (elle ne serait plus jamais recomposée depuis %Head), au
			# lieu de suivre automatiquement le parent comme un enfant normal
			# non top-level. Or `Weapon._fire_local` (Weapon.gd:260-261) lit
			# `camera.global_position`/`global_transform` en TEMPS RÉEL pour
			# résoudre CHAQUE tir, y compris pour les bots (simulés en appel
			# direct sur le serveur, donc `is_multiplayer_authority()` vrai
			# mais `is_local_human()` faux) : une caméra figée y tirerait
			# indéfiniment depuis la position de spawn — priorité n°1 du
			# projet étant justement la fiabilité du tir
			# (docs/research/01_game_feel.md §1).
			top_level = true

func _process(delta: float) -> void:
	if player == null or not player.is_local_human():
		return
	# Retire le punch FOV de la frame précédente AVANT de relire `fov` comme
	# base « propre » (GF-08, voir la note de tête de fichier) : sans ce
	# retrait, `_update_fov` lerperait depuis une valeur déjà décalée par le
	# punch, qui fuirait dans sa convergence au lieu de rester une impulsion
	# de durée fixe.
	fov -= _last_fov_punch
	_update_fov(delta)
	_shake.update(delta)
	var shake_intensity := CameraShake.effective_intensity(
		Settings.camera_shake_intensity, Settings.camera_shake_enabled, Settings.reduced_motion)
	_last_fov_punch = _shake.fov_offset_deg(shake_intensity)
	fov += _last_fov_punch
	# Pendant la roulade, le spin pilote le tangage (on saute tilt + bob).
	if _roll_t >= 0.0:
		_update_roll(delta)
	elif player.state_machine.current_name == "Stun":
		# Pendant le stun : caméra qui tangue (tête qui tourne) — secousse
		# désactivable pour le confort (UX-06, docs/research/04_ui_ux.md
		# section 2.7 secousses de camera desactivables, mal des transports),
		# meme principe que Settings.fov_effects_enabled.
		var step := stun_dizzy_step(_dizzy_t, not _was_stun, Settings.camera_shake_enabled, delta)
		_dizzy_t = step.x
		_tilt_z = step.y
		_was_stun = true
	else:
		_was_stun = false
		_update_tilt(delta)
		_update_bob(delta)
	_apply_interpolated_transform(shake_intensity)

func _update_roll(delta: float) -> void:
	_roll_t += delta
	var p := clampf(_roll_t / _roll_dur, 0.0, 1.0)
	var eased := p * p * (3.0 - 2.0 * p)  # smoothstep : accélère puis ralentit
	# Galipette AVANT : rotation autour de l'axe X (tangage), dans le plan vertical.
	_roll_x = -TAU * _roll_turns * eased
	if p >= 1.0:
		_roll_t = -1.0
		_roll_x = 0.0

func _update_fov(delta: float) -> void:
	# Visée (ADS) : zoom au FOV de l'arme courante. Prioritaire sur tout le reste.
	if player.input.aim_held:
		var w := player.get_node_or_null("Weapon")
		var aim_target: float = w.current_aim_fov() if w and w.has_method("current_aim_fov") else 55.0
		fov = lerp(fov, aim_target, 16.0 * delta)
		return

	var base := Settings.hfov_to_vfov(Settings.fov, Settings.REF_ASPECT_16_9)
	var over := player.horizontal_speed() - config.sprint_speed
	var bonus := dynamic_fov_bonus(
		player.state_machine.current_name, over, config, Settings.fov_effects_enabled)
	fov = lerp(fov, base + bonus, config.fov_lerp_speed * delta)

## Bonus de FOV dynamique (sprint/slide + léger bonus proportionnel à la
## survitesse), plafonné en cumul à `MAX_DYNAMIC_FOV_BONUS` et neutralisé si
## `effects_enabled` est faux (UX-02). Fonction PURE (aucun accès scène) :
## `state_name` = `state_machine.current_name` ; `speed_over_sprint` = vitesse
## horizontale actuelle moins `config.sprint_speed` (négatif/nul = pas de
## survitesse). Testée isolément dans tests/player/test_fov.gd.
static func dynamic_fov_bonus(state_name: String, speed_over_sprint: float, config: MovementConfig, effects_enabled: bool) -> float:
	if not effects_enabled:
		return 0.0
	var bonus := 0.0
	if state_name == "Sprint":
		bonus += config.sprint_fov_add
	elif state_name == "Slide":
		bonus += config.slide_fov_add
	if speed_over_sprint > 0.0:
		bonus += clampf(speed_over_sprint * 0.6, 0.0, config.speed_fov_add)
	return clampf(bonus, 0.0, MAX_DYNAMIC_FOV_BONUS)

## Avance d'un pas le tangage "étourdi" (tête qui tourne) du Stun et calcule
## le `_dizzy_t` suivant. `entering_stun` = vrai sur le FRONT D'ENTRÉE en Stun
## (état précédent différent de "Stun") : on y remet `dizzy_t` à zéro AVANT
## de l'incrémenter, pour repartir de `sin(0) == 0` (tangage nul) au lieu de
## reprendre le `_dizzy_t` résiduel d'un stun précédent — c'était ce résidu
## qui produisait une secousse brusque de caméra à l'entrée en Stun (BUG-20,
## docs/audit/bugs.md). Fonction PURE (aucun accès scène), même principe que
## `dynamic_fov_bonus` ci-dessus : testable isolément (test ou sonde hors
## scène). Retourne `Vector2(next_dizzy_t, next_tilt_z)`.
static func stun_dizzy_step(dizzy_t: float, entering_stun: bool, shake_enabled: bool, delta: float) -> Vector2:
	if entering_stun:
		dizzy_t = 0.0
	if not shake_enabled:
		return Vector2(0.0, 0.0)
	dizzy_t += delta
	var tilt := deg_to_rad(5.0) * sin(dizzy_t * 7.0)
	return Vector2(dizzy_t, tilt)

func _update_tilt(delta: float) -> void:
	# Roule la caméra dans le sens du strafe (renforcé pendant le slide).
	var tilt := config.strafe_tilt
	if player.state_machine.current_name == "Slide":
		tilt += config.slide_tilt
	var target_roll := -player.input_vector.x * deg_to_rad(tilt)
	_tilt_z = lerp(_tilt_z, target_roll, config.tilt_lerp_speed * delta)

func _update_bob(delta: float) -> void:
	# Balancement de tete (head-bob), activable et son intensite reglables
	# (UX-06, docs/research/04_ui_ux.md section 2.7 balancement de tete) :
	# desactive, on relache doucement vers zero comme a l arret plutot que
	# de couper net (evite un saut visuel si le joueur le desactive en
	# pleine foulee).
	if not Settings.head_bob_enabled:
		_bob_time = 0.0
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, 10.0 * delta)
		return
	var grounded := player.is_on_floor()
	var speed := player.horizontal_speed()
	if grounded and speed > 0.5 and player.state_machine.current_name != "Slide":
		_bob_time += delta * config.bob_frequency * clamp(speed / config.sprint_speed, 0.4, 1.4)
		var offset_y := sin(_bob_time) * config.bob_amplitude * Settings.head_bob_intensity
		var offset_x := cos(_bob_time * 0.5) * config.bob_amplitude * 0.6 * Settings.head_bob_intensity
		_bob_offset = Vector3(offset_x, offset_y, 0.0)
	else:
		_bob_time = 0.0
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, 10.0 * delta)

## Recompose la transform GLOBALE de la caméra à partir de deux sources
## distinctes (GF-03, docs Godot "advanced physics interpolation") :
## - la POSITION vient de `get_global_transform_interpolated()` sur la tête
##   (notre parent, %Head) : elle avance au tick physique (mouvement du corps
##   ET lerp de hauteur accroupi, cf. PlayerController._update_crouch_height)
##   mais on l'affiche ici LISSÉE entre les deux derniers ticks, à la
##   fréquence de rendu réelle — élimine le "motif 3-2" quand tick physique et
##   rafraîchissement écran ne coïncident pas.
## - la ROTATION vient de la transform COURANTE (non interpolée) de la tête :
##   le lacet du corps et le tangage de la tête sont appliqués immédiatement
##   dans PlayerController._unhandled_input, hors du tick physique — les
##   lisser ajouterait un temps de retard perceptible à la visée souris. On y
##   compose ensuite les effets locaux de CETTE caméra (tilt/roulade/stun) et
##   le head-bob, en espace tête (jamais via `position`/`rotation`, polluées
##   par la reconstruction locale que ferait Godot si on les relisait après
##   avoir écrit `global_transform`).
##
## `shake_intensity` : intensité EFFECTIVE déjà calculée par `_process`
## (CameraShake.effective_intensity — secousses de caméra désactivées ou
## mouvement réduit donnent 0). Ajoute la rotation de `_shake` (yaw/pitch/roll,
## GF-08) par-dessus tilt/roulade/stun, jamais de composante de position
## (Eiserloh : "the translational shake is lame").
func _apply_interpolated_transform(shake_intensity: float = 0.0) -> void:
	var head_node := get_parent() as Node3D
	if head_node == null:
		return
	var smooth_origin := head_node.get_global_transform_interpolated().origin
	var live_basis := head_node.global_transform.basis
	var shake_deg := _shake.rotation_offset_deg(shake_intensity)
	var euler := Vector3(_roll_x, 0.0, _tilt_z) + Vector3(
		deg_to_rad(shake_deg.x), deg_to_rad(shake_deg.y), deg_to_rad(shake_deg.z))
	var local_basis := Basis.from_euler(euler)
	global_transform = Transform3D(live_basis * local_basis, smooth_origin + live_basis * _bob_offset)
