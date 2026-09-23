## PlayerInput.gd
## Abstraction d'entrée : point de lecture UNIQUE pour tout le code de
## gameplay (mouvement, arme, capacités...), qu'il s'agisse d'un humain à son
## clavier/manette ou d'un bot serveur (scripts/ai/BotBrain.gd, qui écrit
## directement ces champs avant que le joueur ne les consomme). Enfant "Input"
## du joueur (scenes/player/player.tscn), `process_physics_priority = -100` :
## s'exécute AVANT PlayerController._physics_process (priorité par défaut 0),
## qui lit ces champs (contract-r3.md, R3-IN, "Cross-slice interfaces").
##
## Gating humain : IDENTIQUE au code pré-refactor (PlayerController._read_input
## + Weapon._can_act) — rien n'est lu tant que la souris n'est pas capturée
## (menu pause/options ouvert). Un bot n'a pas de souris : `is_bot` court-
## circuite entièrement la lecture du singleton Input (BotBrain écrit les
## champs lui-même, dans un ordre garanti par sa propre priorité, plus basse
## — voir scripts/ai/BotBrain.gd).
##
## Le regard (souris/manette) reste géré directement dans
## PlayerController._unhandled_input / _gamepad_look (delta brut, réactivité
## inchangée) : `look_delta` n'existe ici que pour les BOTS, qui n'ont ni
## souris ni manette et doivent piloter la caméra par du code
## (PlayerController._apply_bot_look consomme ce champ).
class_name PlayerInput
extends Node

## --- Mouvement / actions (une frame physique) ---
var move: Vector2 = Vector2.ZERO
var look_delta: Vector2 = Vector2.ZERO  ## yaw, pitch (radians) — BOTS uniquement.
var jump_pressed: bool = false
var jump_held: bool = false
var crouch_pressed: bool = false
var crouch_held: bool = false
var walk_held: bool = false
var dive_pressed: bool = false
var fire_pressed: bool = false
var fire_held: bool = false
var aim_held: bool = false
var reload_pressed: bool = false
var pickup_pressed: bool = false
var pickup_held: bool = false
var drop_pressed: bool = false
var weapon_slot_pressed: int = -1  ## -1 = aucun ; sinon index de slot (0/1).
var weapon_next_pressed: bool = false
var weapon_prev_pressed: bool = false
var ability_pressed: String = ""  ## "" ou "C"/"Q"/"E"/"X".

## true pour un joueur simulé par le serveur (bot) : jamais de lecture
## périphérique, voir BotBrain.
var is_bot: bool = false
## true si ce nœud a effectivement lu les périphériques cette frame (humain
## local uniquement — ni bot, ni joueur distant). Informatif (debug/HUD).
var reads_devices: bool = false

var player: PlayerController

const MOVE_ACTIONS := ["move_left", "move_right", "move_forward", "move_back"]

func _ready() -> void:
	process_physics_priority = -100
	player = get_parent() as PlayerController

func _physics_process(_delta: float) -> void:
	# Synchronisé depuis le joueur à chaque tick (source de vérité unique,
	# posée par GameWorld AVANT le spawn — voir PlayerController.is_bot).
	is_bot = player != null and player.is_bot
	if is_bot:
		return  # BotBrain a déjà écrit les champs avant ce tick (priorité plus basse).
	# Gating "souris capturée" (menu pause/options ouvert) : vérifié ICI (pas
	# dans `gather_from_devices`, qui reste une fonction pure de mappage
	# Input -> champs, testable sans dépendre de Input.mouse_mode — voir
	# tests/input/test_player_input.gd).
	reads_devices = player != null and player.is_local_human() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not reads_devices:
		clear()
		return
	gather_from_devices()

## Remet tous les champs à leur valeur neutre (souris relâchée, joueur mort,
## bot désactivé...).
func clear() -> void:
	move = Vector2.ZERO
	look_delta = Vector2.ZERO
	jump_pressed = false
	jump_held = false
	crouch_pressed = false
	crouch_held = false
	walk_held = false
	dive_pressed = false
	fire_pressed = false
	fire_held = false
	aim_held = false
	reload_pressed = false
	pickup_pressed = false
	pickup_held = false
	drop_pressed = false
	weapon_slot_pressed = -1
	weapon_next_pressed = false
	weapon_prev_pressed = false
	ability_pressed = ""

## Lit le singleton Input et remplit TOUS les champs — fonction pure de
## mappage (aucune décision "dois-je lire ?", qui vit dans `_physics_process` :
## Input.mouse_mode n'est pas fiable en tête sans fenêtre réelle, ex. tests
## headless — voir tests/input/test_player_input.gd, qui pilote Input via
## Input.action_press/action_release, standard headless). Public (pas
## préfixé `_`) pour rester directement testable.
func gather_from_devices() -> void:
	move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	look_delta = Vector2.ZERO  # le regard humain passe par _unhandled_input/_gamepad_look.
	jump_pressed = Input.is_action_just_pressed("jump")
	jump_held = Input.is_action_pressed("jump")
	crouch_pressed = Input.is_action_just_pressed("crouch")
	crouch_held = Input.is_action_pressed("crouch")
	walk_held = Input.is_action_pressed("walk")
	dive_pressed = Input.is_action_just_pressed("dive")
	fire_pressed = Input.is_action_just_pressed("fire")
	fire_held = Input.is_action_pressed("fire")
	aim_held = Input.is_action_pressed("aim")
	reload_pressed = Input.is_action_just_pressed("reload")
	pickup_pressed = Input.is_action_just_pressed("pickup")
	pickup_held = Input.is_action_pressed("pickup")
	drop_pressed = Input.is_action_just_pressed("drop")
	weapon_slot_pressed = slot_from_presses(
		Input.is_action_just_pressed("weapon_1"), Input.is_action_just_pressed("weapon_2"))
	weapon_next_pressed = Input.is_action_just_pressed("weapon_next")
	weapon_prev_pressed = Input.is_action_just_pressed("weapon_prev")
	ability_pressed = ability_from_presses(
		Input.is_action_just_pressed("ability_c"), Input.is_action_just_pressed("ability_q"),
		Input.is_action_just_pressed("ability_e"), Input.is_action_just_pressed("ultimate"))

## --- Parties pures (testées directement, sans passer par le singleton Input) ---

## -1 = aucun slot ; sinon l'index (0/1) du premier pressé cette frame.
static func slot_from_presses(slot0_pressed: bool, slot1_pressed: bool) -> int:
	if slot0_pressed:
		return 0
	if slot1_pressed:
		return 1
	return -1

## "" ou "C"/"Q"/"E"/"X" — mappe directement sur Ability.slot (voir
## scripts/agents/AbilityController.gd, qui n'a plus besoin de _action_for).
static func ability_from_presses(c_pressed: bool, q_pressed: bool, e_pressed: bool, ult_pressed: bool) -> String:
	if c_pressed:
		return "C"
	if q_pressed:
		return "Q"
	if e_pressed:
		return "E"
	if ult_pressed:
		return "X"
	return ""
