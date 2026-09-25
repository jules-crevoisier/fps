## PingController.gd
## Ping contextuel (UX-10, docs/research/04_ui_ux.md §2.8 « Ping contextuel
## (Apex) : un appui marque le point... le maintien ouvre une roue »).
## Enfant prévu du joueur LOCAL (même famille que `Input`/`BotBrain` dans
## scenes/player/player.tscn : NON câblé ici -- `player.tscn` et
## `PlayerController.gd` sont hors de la liste de fichiers de cette tâche,
## voir tasks/backlog.yaml UX-10 ; le càblage scène (instanciation comme
## enfant du joueur, assignation de `wheel`) revient à la tâche/à la revue
## qui possède ces fichiers). Cette classe est conçue pour rester TESTABLE
## SANS cette scène : toute la logique de décision (appui/maintien, ce que
## touche un tir sous le viseur, quelle option de roue une direction désigne)
## est extraite en fonctions PURES (voir tests/player/test_ping.gd), la
## lecture réelle des périphériques et le raycast restent de la plomberie
## fine, non testée -- même discipline que PlayerInput.gd
## (gather_from_devices non testé, slot_from_presses/ability_from_presses
## testés) et PlayerController._gamepad_look (axes manette lus BRUTS, sans
## action InputMap).
##
## Entrée BRUTE, volontairement SANS nouvelle action InputMap (project.godot
## n'est PAS dans la liste de fichiers de cette tâche : aucune entrée ne peut
## y être ajoutée ici) -- voir `_ping_button_held()` : bouton central de la
## souris (libre, jamais lié dans project.godot), touche physique T
## (`KEY_T`, position physique jamais liée -- indépendante AZERTY/QWERTY,
## comme tous les `physical_keycode` du projet) et bouton manette X
## (`JOY_BUTTON_X` = index 2, seul bouton de façade encore libre : A/B/Y et
## les gâchettes/D-Pad/sticks sont déjà pris par saut, accroupi/annuler,
## arme suivante, capacités... -- voir project.godot [input]). La direction
## de la roue lit le stick droit BRUT (`JOY_AXIS_RIGHT_X/Y`, même paire que
## `PlayerController._gamepad_look`) ou l'écart souris/centre -- les DEUX
## passent par la MÊME fonction pure `PingWheel.option_for_direction`, donc
## « utilisable à la manette (roue au stick) » est satisfait par construction,
## pas par un second chemin de code. Un futur remappage (Settings/OptionsMenu,
## eux aussi hors périmètre) pourra remplacer cette lecture brute par une
## vraie action InputMap sans changer la logique pure ci-dessous.
class_name PingController
extends Node

# ============================================================ Vocabulaire

## Appui simple (contextuel selon ce qui est sous le viseur, §2.8).
const KIND_GROUND := "ground"
const KIND_ENEMY := "enemy"
const KIND_OBJECT := "object"
## Maintien -> roue à 4 options (§2.8 « ennemi ici », « j'y vais »,
## « défendez », « besoin d'aide »).
const KIND_ENEMY_HERE := "enemy_here"
const KIND_GOING := "going"
const KIND_DEFEND := "defend"
const KIND_NEED_HELP := "need_help"

## Ordre CANONIQUE des 4 options de la roue -- disposition croix (haut/
## droite/bas/gauche), voir `PingWheel.option_for_direction` pour la
## correspondance angle -> index. Référencé par `PingWheel.gd`/
## `PingMarkers.gd` (icônes/libellés) et par `GameWorld.gd` (bots) : UNE
## SEULE liste, jamais une copie qui pourrait diverger.
const WHEEL_KINDS: Array[String] = [KIND_ENEMY_HERE, KIND_GOING, KIND_DEFEND, KIND_NEED_HELP]

## Tous les kinds valides (appui + roue) -- utilisé par GameWorld._server_ping
## pour rejeter un kind fabriqué par un client modifié.
const ALL_KINDS: Array[String] = [KIND_GROUND, KIND_ENEMY, KIND_OBJECT, KIND_ENEMY_HERE, KIND_GOING, KIND_DEFEND, KIND_NEED_HELP]

# ============================================================ Réglages

## Durée (s) au-delà de laquelle un appui devient un MAINTIEN (roue) --
## §2.8 : distinction appui/maintien, valeur choisie par cette tâche (assez
## courte pour rester réactif, assez longue pour ne jamais confondre un tir
## nerveux avec une intention de communication).
const HOLD_THRESHOLD_S := 0.25
## Portée (m) du raycast d'appui simple sous le viseur -- assez long pour
## désigner un point à l'autre bout d'une ligne de vue typique des cartes du
## projet (voir docs/research/03_level_design.md, portées de ligne de vue
## Wasteland/Cargo Ship).
const TAP_RANGE_M := 120.0

## Assignés par la scène qui instancie ce nœud (hors périmètre ici, voir doc
## de classe) : le joueur possédé et sa caméra locale, la roue HUD associée.
var player: PlayerController
var camera: Camera3D
var wheel: PingWheel

## Horodatage (secondes écoulées, `Time.get_ticks_msec`) du début de l'appui
## en cours, -1.0 si le bouton est relâché.
var _press_started_at: float = -1.0

func _ready() -> void:
	if player == null:
		player = get_parent() as PlayerController
	if camera == null and player != null:
		camera = player.get_node_or_null("Head/Camera3D") as Camera3D

func _physics_process(delta: float) -> void:
	# Jamais pour un bot (aucun bouton/roue à lire) ni un joueur distant
	# (seul le propriétaire local doit émettre SES propres pings) -- même
	# garde que PlayerInput._physics_process.
	if player == null or player.is_bot or not player.is_local_human():
		return
	var held := _ping_button_held()
	if held:
		if _press_started_at < 0.0:
			_press_started_at = 0.0
		else:
			_press_started_at += delta
		if is_hold(_press_started_at) and wheel != null and not wheel.visible:
			wheel.open()
		if wheel != null and wheel.visible:
			wheel.update_direction(_wheel_direction())
	elif _press_started_at >= 0.0:
		_on_released(_press_started_at)
		_press_started_at = -1.0

## Relâchement du bouton de ping après `held_duration_s` de maintien --
## appui simple (contexte sous le viseur) sous le seuil, roue au-delà (option
## survolée au moment du relâchement, "" = annulé si le stick/la souris est
## resté(e) neutre -- même comportement qu'Apex).
func _on_released(held_duration_s: float) -> void:
	if is_hold(held_duration_s):
		if wheel == null:
			return
		var kind := wheel.close_and_confirm()
		if kind == "":
			return
		_send_ping(kind, _current_target_position())
	else:
		var hit := _raycast_under_crosshair()
		_send_ping(classify_tap(hit, _local_team()), _target_position(hit))

func _local_team() -> int:
	return int(player.team) if player != null else 0

## Position visée MAINTENANT (roue : le joueur peut avoir bougé le viseur
## pendant tout le maintien, on ping toujours l'endroit regardé AU
## RELÂCHEMENT, comme Apex).
func _current_target_position() -> Vector3:
	return _target_position(_raycast_under_crosshair())

## Envoie la demande de ping au serveur -- GameWorld porte TOUTE la logique
## réseau/anti-triche (rejeu, limite de fréquence, résolution de la zone) :
## trouvé par le groupe "match" comme BuyMenu/SnDMode (jamais une dépendance
## dure sur networking/GameWorld.gd depuis ce fichier).
func _send_ping(kind: String, pos: Vector3) -> void:
	var world := get_tree().get_first_node_in_group("match")
	if world != null and world.has_method("request_ping"):
		world.request_ping(kind, pos)

## Rayon sous le viseur (même construction que `RevealAbility.trajectory_hit` :
## `PhysicsLayers.SHOT_MASK`, aires ignorées) -- Dictionary vide si pas de
## caméra assignée (nœud pas encore câblé dans une scène) ou rien touché.
func _raycast_under_crosshair() -> Dictionary:
	if camera == null or not is_instance_valid(camera):
		return {}
	var world3d := camera.get_world_3d()
	if world3d == null:
		return {}
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * TAP_RANGE_M, PhysicsLayers.SHOT_MASK)
	q.collide_with_areas = true  # les objets ramassables (WorldWeapon/AmmoPack) sont des Area3D.
	if player != null:
		var excl: Array[RID] = [player.get_rid()]
		q.exclude = excl
	return world3d.direct_space_state.intersect_ray(q)

## Point touché, ou un point à `TAP_RANGE_M` le long du regard si rien n'est
## touché (ping "au loin", jamais Vector3.ZERO qui serait une fausse position
## monde).
func _target_position(hit: Dictionary) -> Vector3:
	if not hit.is_empty():
		return hit.get("position", Vector3.ZERO)
	if camera == null or not is_instance_valid(camera):
		return Vector3.ZERO
	return camera.global_position + (-camera.global_transform.basis.z) * TAP_RANGE_M

## Direction courante pour la roue : stick droit BRUT en priorité (manette
## déjà active dès que sa magnitude dépasse la zone morte de la roue),
## sinon l'écart souris/centre de la fenêtre -- voir doc de classe.
func _wheel_direction() -> Vector2:
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() >= PingWheel.DEADZONE:
		return stick
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	var size := vp.get_visible_rect().size
	var center := size * 0.5
	if center.y <= 0.0:
		return Vector2.ZERO
	return (vp.get_mouse_position() - center) / center.y

## Bouton de ping brut (voir doc de classe pour le choix des périphériques) --
## jamais lu pour un bot (aucun périphérique).
func _ping_button_held() -> bool:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		return true
	if Input.is_physical_key_pressed(KEY_T):
		return true
	if Input.is_joy_button_pressed(0, JOY_BUTTON_X):
		return true
	return false

# ================================================================= PUR
#  Fonctions pures -- testées directement sans scène, périphérique ni
#  réseau (tests/player/test_ping.gd), même discipline que
#  PlayerInput.slot_from_presses/ability_from_presses.
# ================================================================= PUR

## Maintien (roue) vs appui simple (marque rapide) -- §2.8.
static func is_hold(held_duration_s: float, threshold_s: float = HOLD_THRESHOLD_S) -> bool:
	return held_duration_s >= threshold_s

## Classe un appui simple selon ce que le rayon a touché (§2.8 « appui =
## marque au sol / ennemi / objet ») :
##  - rien touché, ou collider sans forme reconnue -> KIND_GROUND ;
##  - `WorldWeapon`/`AmmoPack` (ramassables au sol) -> KIND_OBJECT ;
##  - un joueur (duck-typing `"team" in collider`, comme
##    `GameHUD._acquire_map_setup` pour `"map_id" in parent`) d'une équipe
##    DIFFÉRENTE de `local_team` -> KIND_ENEMY ;
##  - un coéquipier ou tout autre corps -> KIND_GROUND (pas de kind "allié"
##    au contrat de cette tâche).
## `hit` : Dictionary au format `PhysicsDirectSpaceState3D.intersect_ray()`
## ("" absent = rien touché). Pure -- testée avec des colliders factices.
static func classify_tap(hit: Dictionary, local_team: int) -> String:
	if hit.is_empty():
		return KIND_GROUND
	var collider = hit.get("collider")
	if collider == null:
		return KIND_GROUND
	if collider is WorldWeapon or collider is AmmoPack:
		return KIND_OBJECT
	if "team" in collider and int(collider.team) != local_team:
		return KIND_ENEMY
	return KIND_GROUND
