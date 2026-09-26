## Audio.gd  (Autoload : "Sfx")
## Système audio global : bus Master/Music/SFX/UI/Shots/Feedback (voir
## default_bus_layout.tres) + Voice/Ambience créés au démarrage par ce fichier
## (UX-06 : volumes voix/ambiance dédiés — absents de la ressource, hors du
## périmètre de cette tâche, voir `_ensure_bus`), pools de lecteurs
## réutilisés (2D pour les sons "locaux" joueur/UI, 3D pour les sons
## positionnels distants) — pool saturé (tous en train de jouer) : `_free_player`
## vole le lecteur dont la lecture a le plus avancé (tourniquet, jamais
## toujours le même canal, voir docs/audit/bugs.md BUG-15), API simple pour
## les autres scripts :
##   Sfx.play_ui(name)         -- boutons, stingers de manche...
##   Sfx.play_local(name)      -- sons du joueur local (tir, pas, capacités...)
##   Sfx.play_at(name, pos, distance = 0.0)  -- sons positionnels 3D
## AUTO-CÂBLAGE (contract-r2.md, "R-E audio") sur les signaux des autres
## slices, posé avec `has_signal()` pour ne jamais planter si un signal
## n'est pas encore arrivé (construction en parallèle) :
##  - chaque BaseButton qui entre dans l'arbre (survol/focus + clic) ;
##  - l'arme du joueur LOCAL (fired/reload_started/hit_confirmed/weapon_changed) —
##    "reload_in" (sur reload_started) est différé sans bloquer sur l'arme :
##    `_step_pending_reload_ins` revérifie à l'échéance qu'elle existe ENCORE
##    et recharge TOUJOURS (docs/audit/bugs.md BUG-K02, voir aussi la règle
##    minuteries plus bas) ;
##  - la vie de TOUS les joueurs suivis (Health.died, déjà présent sans garde,
##    sert aussi à détecter "c'est MOI qui ai fait le kill" via killer_id) ;
##  - Health.damaged (dégâts reçus) du joueur LOCAL seulement ;
##  - les capacités du joueur LOCAL (AbilityController.ability_used) ;
##  - les pas : sondage de state_machine.current_name + vélocité (LOCAL),
##    vélocité seule pour les AUTRES joueurs (leur state machine ne tourne
##    que chez leur propriétaire — seules position/rotation/vélocité sont
##    répliquées, voir player.tscn) ;
##  - les tirs distants (Weapon.remote_fired) de chaque AUTRE joueur, en 3D,
##    avec la variante `_far` au-delà de FAR_DISTANCE.
## MUSIQUE DE PARTIE (contract-r4a.md, "R4-AMB") — deux systèmes distincts,
## tous deux silencieux hors de leur contexte :
##  - Ambiance de carte : `MatchConfig.map_id` -> `ambience_<id>.wav`
##    (assets/audio/music/, générés par tools/audio/gen_ambience.py), jouée
##    en fondu enchaîné (deux lecteurs alternés, loi des sinus à puissance
##    constante) dès qu'une scène de match (groupe "match", voir GameWorld)
##    est courante ; silence en menu (le menu garde sa propre boucle,
##    `_update_menu_music`, inchangée) ou sur une carte inconnue du
##    catalogue (fallback legacy sans id, voir MainMenu.FALLBACK_SCENES). Sur
##    le bus DÉDIÉ `BUS_AMBIENCE` (UX-06, docs/research/04_ui_ux.md §2.7
##    "volume ... ambiance" — avant cette tâche, sur le bus Music comme les
##    stings ci-dessous, sans curseur de volume séparé).
##  - Stings de MATCH sur le bus Music (pas de manche — round_start/round_win/
##    round_lose restent gérés par RoundMode.gd, hors de portée ici) : sondage du nœud
##    du groupe "game_mode" (GameMode et ses sous-classes), gardé par
##    `has_method`/`.get()` nul-safe à chaque lookup (peut ne pas exister
##    encore, ou plus, en construction parallèle/tests headless) —
##    `match_start` à la découverte du mode, `match_last_minute` +
##    `last_minute_loop` (boucle superposée) sur la dernière minute du
##    minuteur de match OU un point de match (SnD/Duel, `is_match_point`),
##    `match_victory`/`match_defeat` selon l'équipe du joueur LOCAL au
##    changement de `winner`.
## AUDIO D'ARME EN COUCHES + MIX PRIORISÉ (GF-11, docs/research/01_game_feel.md
## §2.5) :
##  - Le tir du joueur LOCAL seul est joué EN COUCHES (transitoire + corps +
##    mécanique + sub, sur le bus 'Shots') plutôt qu'un unique échantillon
##    pré-mixé — le sub donne le poids de l'arme et n'est JAMAIS diffusé pour
##    un tir distant (voir `_play_local_gunshot`/`_wire_remote_weapon`, ce
##    dernier inchangé : `gunshot_<classe>.wav` pré-mixé + `_far`). Une queue
##    de réverbération (`tail_indoor`/`tail_outdoor`) est choisie par un
##    raycast plafond depuis la tête du tireur (`gunshot_tail_name`, pure —
##    voir tests/audio/test_audio_mix.gd).
##  - Bus 'Feedback' dédié (hitmarker/headshot/kill_confirm, voir
##    `is_feedback_sound`) : ne doit JAMAIS être masqué par les tirs. Chaque
##    son Feedback déclenche un ducking manuel (Godot n'a pas de compresseur à
##    sidechain natif) du bus 'Shots' de -4 dB pendant 120 ms
##    (`duck_gain_db`/`_step_shots_duck`).
##  - Les pas des joueurs DISTANTS sont +3 dB pour un ennemi vs un allié
##    (`footstep_team_volume_offset_db`) — repère tactique, jamais sur les pas
##    LOCAUX (on s'entend soi-même normalement).
##  - Son de réception d'atterrissage (`land`) : LOCAL uniquement — `is_on_floor()`
##    n'est mis à jour que côté autorité (move_and_slide ne tourne pas pour un
##    pair distant, voir PlayerController._physics_process), donc impossible à
##    détecter de façon fiable pour les autres joueurs depuis cet autoload.
## CLIC À VIDE (GF-12, docs/research/01_game_feel.md #14) : `Weapon.dry_fire`
## (front montant de la gâchette sur un chargeur ET une réserve à zéro — aucun
## rechargement possible) est câblé sur `play_local("dry_fire")`, comme les
## autres signaux du joueur LOCAL (voir `_wire_local_extras`). Un seul son par
## appui : `Weapon` n'émet le signal que sur la frame `fire_pressed` (front
## montant natif de Godot), jamais en continu tant que la gâchette reste
## enfoncée sur une arme automatique — voir `should_play_dry_fire`, pure.
## Toutes les fonctions PURES ci-dessous (pick_variation, far_suffix,
## footstep_*, weapon_gunshot_name, weapon_layer_name, gunshot_tail_name,
## is_feedback_sound, duck_gain_db, footstep_team_volume_offset_db,
## should_play_landing, should_play_dry_fire, ability_sound_name, is_local_kill,
## ambience_name_for_map, crossfade_*, is_last_minute, match_result_sting...)
## sont `static` : testables sans passer par l'autoload (voir tests/audio/,
## tests/combat/test_fire_clock.gd pour should_play_dry_fire — GF-12).
class_name Audio
extends Node

# ------------------------------------------------------------------ CONSTANTES

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const MUSIC_MENU := "res://assets/audio/music/menu_loop.wav"
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

## Durée (s) du fondu enchaîné entre deux ambiances de carte (ou vers/depuis
## le silence) — voir `_step_ambience_fade`.
const AMBIENCE_CROSSFADE_S := 2.5
## Fenêtre (s) de "dernière minute" du minuteur de MATCH — voir `is_last_minute`.
const LAST_MINUTE_WINDOW := 60.0

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_UI := "UI"
## Couches de tir LOCAL (transitoire/corps/mécanique/sub/queue) — voir docstring GF-11.
const BUS_SHOTS := "Shots"
## Hitmarker/headshot/kill_confirm — jamais masqué par les tirs (ducking de BUS_SHOTS).
const BUS_FEEDBACK := "Feedback"
## Chat vocal (UX-06 : volume dédié — aucune capture/diffusion de voix
## n'existe encore dans ce projet, ce bus prépare la route pour quand elle
## arrivera). Créé au démarrage par `_ensure_bus` : absent de
## default_bus_layout.tres (hors du périmètre de cette tâche).
const BUS_VOICE := "Voice"
## Ambiance de carte (UX-06 : volume dédié, séparé de Music — voir docstring
## en tête de fichier). Créé au démarrage par `_ensure_bus`, même raison que BUS_VOICE.
const BUS_AMBIENCE := "Ambience"

## Distance (m) au-delà de laquelle un son positionnel utilise sa variante lointaine.
const FAR_DISTANCE := 30.0
## Étalement de hauteur (pitch) aléatoire (+/- 5 %) pour éviter l'effet "disque rayé".
const PITCH_SPREAD := 0.05

const POOL_UI := 6
const POOL_LOCAL := 10
const POOL_3D := 16
## Une couche par tir local peut se chevaucher avec la précédente si le joueur
## tire vite (SMG/auto) : plusieurs voix par couche pour ne pas se couper.
const POOL_SHOT_LAYER := 6
const POOL_FEEDBACK := 4

## Sons routés sur BUS_FEEDBACK (voir `is_feedback_sound`) — jamais sur BUS_SFX.
const FEEDBACK_SOUNDS := ["hitmarker", "headshot", "kill_confirm"]
## Profondeur (dB, négatif) et durée du ducking du bus des tirs déclenché par
## un son Feedback (contract GF-11 : "-4 dB ... pendant 120 ms").
const SHOTS_DUCK_DB := -4.0
const SHOTS_DUCK_DURATION_S := 0.12
## Fin de fenêtre de ducking sur laquelle le gain remonte à 0 dB (évite un
## "pop" audible en relâchant instantanément le bus des tirs).
const SHOTS_DUCK_RELEASE_S := 0.03

## Portée (m) du raycast plafond qui choisit la queue de réverbération du tir
## local (`gunshot_tail_name`) — au-delà, l'espace est considéré ouvert.
const INDOOR_CEILING_MAX := 6.0
## Écart de hauteur du plafond au-dessus de la tête pour lequel on tire le rayon.
const CEILING_RAYCAST_HEAD_OFFSET := 1.5

## Pas ennemis (joueur distant) +3 dB par rapport aux pas alliés (repère
## tactique) — voir `footstep_team_volume_offset_db`.
const ENEMY_FOOTSTEP_BOOST_DB := 3.0

## Hauteur de chute (m) à partir de laquelle l'atterrissage joue un son —
## au-delà de `floor_snap_length` (0.4 m, PlayerController) pour ne pas
## déclencher sur un simple accrochage de marche.
const LANDING_MIN_FALL_HEIGHT := 0.6

## Fréquence de sondage (joueurs/menu, volumes) — le contrat demande ≤ 2 Hz pour les volumes.
const DISCOVERY_INTERVAL := 0.35
const VOLUME_INTERVAL := 0.5

## Distance (m) entre deux pas, marche / sprint (utilisée par footstep_stride).
const WALK_STRIDE := 1.3
const SPRINT_STRIDE := 1.7

## Vitesses de repli si le MovementConfig du joueur est introuvable.
const FALLBACK_WALK_SPEED := 5.2
const FALLBACK_SPRINT_SPEED := 8.2

## Mots-clés (déjà en minuscules, sans accents) -> nom de son, pour classer une
## capacité par son display_name (voir ability_sound_name). Ordre = priorité.
const _ABILITY_KEYWORDS := [
	["heal", ["heal", "soin", "regen"]],
	["wall_slam", ["mur", "wall", "barrier", "barriere", "rempart"]],
	["smoke", ["fume", "smoke", "voile", "brume"]],
	["flash", ["flash", "eblou", "aveugl"]],
	["stun_twinkle", ["stun", "etourdi", "sonne", "piege", "trap"]],
	["reveal", ["reveal", "revele", "detect", "marqueur", "radar", "ping", "sonar"]],
	["dash", ["dash", "ruee", "rue", "fonce", "surge", "bond", "tremplin", "impulsion", "charge", "onde"]],
]

## Accents français -> ASCII, pour un classement de mots-clés insensible aux accents.
const _ACCENT_MAP := {
	"é": "e", "è": "e", "ê": "e", "ë": "e", "à": "a", "â": "a", "ä": "a",
	"î": "i", "ï": "i", "ô": "o", "ö": "o", "û": "u", "ù": "u", "ü": "u", "ç": "c",
}

# ------------------------------------------------------------------ ÉTAT

var _manifest: Dictionary = {}       # nom logique -> nb de variations trouvées sur disque
var _stream_cache: Dictionary = {}   # chemin res:// -> AudioStream (chargé une fois)

var _ui_pool: Array = []
var _local_pool: Array = []
var _pool3d: Array = []
var _music_player: AudioStreamPlayer

## Couches de tir LOCAL (GF-11) — un pool de voix par couche, toutes sur BUS_SHOTS.
var _shot_transient_pool: Array = []
var _shot_body_pool: Array = []
var _shot_mech_pool: Array = []
var _shot_sub_pool: Array = []
var _shot_tail_pool: Array = []
## Hitmarker/headshot/kill_confirm — pool dédié sur BUS_FEEDBACK.
var _feedback_pool: Array = []

## Downmix stéréo->mono du bus Master (UX-06, "Settings.audio_mono") — voir
## `_setup_mono_effect`/`apply_audio_mono`/`mono_pan_pullout`.
var _mono_effect: AudioEffectStereoEnhance

var _rng := RandomNumberGenerator.new()

var _tracked: Dictionary = {}        # instance_id -> {node, is_local, accum}
var _wired_buttons: Dictionary = {}  # instance_id -> true (anti double-câblage)

## Rechargements LOCAUX en attente du son différé "reload_in" (voir
## `_wire_local_extras`) — id d'instance de l'arme (jamais une référence
## directe : voir docstring minuteries, tête de fichier) -> secondes restantes
## avant de rejouer le son. Avancé chaque frame comme le ducking Feedback / le
## fondu d'ambiance (voir `_step_pending_reload_ins`), plutôt qu'un
## `get_tree().create_timer()` dont le lambda capturerait l'arme.
var _pending_reload_ins: Dictionary = {}

var _discovery_left: float = 0.0
var _volume_left: float = 0.0

# ------------------------------------------------------------------ ducking (GF-11)

## Volume (dB) courant du bus 'Shots' HORS ducking (recalculé à chaque
## `_apply_volumes`, réglages) — le ducking s'additionne dessus.
var _shots_base_db: float = 0.0
## Secondes écoulées depuis le dernier son Feedback ; -1 = aucun ducking actif.
var _shots_duck_elapsed: float = -1.0

# ------------------------------------------------------------------ atterrissage (GF-11, LOCAL uniquement)

var _local_air_peak_y: float = 0.0
var _local_was_on_floor: bool = true

# ------------------------------------------------------------------ AMBIANCE DE CARTE

var _ambience_players: Array = []    # 2x AudioStreamPlayer (bus BUS_AMBIENCE), alternés au fondu
var _ambience_active_idx: int = 0    # index (dans _ambience_players) de la piste CIBLE actuelle
var _ambience_target: String = ""    # nom logique en cours ("" = silence, ex. menu)
var _ambience_fade_t: float = -1.0   # secondes écoulées dans le fondu courant ; -1 = aucun fondu

# ------------------------------------------------------------------ STINGS DE MATCH

var _music_sting_player: AudioStreamPlayer
var _last_minute_player: AudioStreamPlayer
var _game_mode_node: Node = null
var _last_winner_seen: int = -1
var _last_minute_active: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_scan_manifest()
	_build_pools()
	_apply_volumes()
	get_tree().node_added.connect(_on_node_added)

func _process(delta: float) -> void:
	_discovery_left -= delta
	if _discovery_left <= 0.0:
		_discovery_left = DISCOVERY_INTERVAL
		_discover_players()
		_update_menu_music()
		_update_match_stings()
	_volume_left -= delta
	if _volume_left <= 0.0:
		_volume_left = VOLUME_INTERVAL
		_apply_volumes()
	_poll_footsteps(delta)
	_poll_landing()
	_update_map_ambience(delta)  # fondu enchaîné : doit avancer à chaque frame, pas au sondage
	_step_shots_duck(delta)  # ducking Feedback -> Shots : doit avancer à chaque frame
	_step_pending_reload_ins(delta)  # son "reload_in" différé : doit avancer à chaque frame

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		play_ui("ui_back")

# ======================================================================
#  API PUBLIQUE
# ======================================================================

## Son d'interface (boutons, stingers de manche...) — bus UI, non positionnel.
func play_ui(name: String) -> void:
	var s := _resolve(name)
	if s == null:
		return
	var p: AudioStreamPlayer = _free_player(_ui_pool)
	if p == null:
		return
	p.stream = s
	p.pitch_scale = pitch_variation(_rng.randf())
	p.play()

## Son du joueur LOCAL (tir, pas, capacité, dégâts reçus...) — bus SFX, non
## positionnel. Hitmarker/headshot/kill_confirm (voir `is_feedback_sound`)
## sont routés à la place sur BUS_FEEDBACK avec ducking du bus des tirs
## (GF-11) : ce détour est automatique, n'importe quel appelant de ces trois
## noms passe par le mix priorisé sans avoir à le savoir.
func play_local(name: String) -> void:
	if name == "":
		return
	if is_feedback_sound(name):
		_play_feedback(name)
		return
	var s := _resolve(name)
	if s == null:
		return
	var p: AudioStreamPlayer = _free_player(_local_pool)
	if p == null:
		return
	p.stream = s
	p.pitch_scale = pitch_variation(_rng.randf())
	p.play()

## Son positionnel 3D (tirs/pas des autres joueurs, capacités visibles...).
## `distance` (déjà connue par l'appelant) choisit la variante "_far" au besoin.
## `volume_offset_db` : décalage additif (ex. +3 dB pas ennemi vs allié, GF-11).
func play_at(name: String, pos: Vector3, distance: float = 0.0, volume_offset_db: float = 0.0) -> void:
	if name == "":
		return
	var suffix := far_suffix(distance)
	var s := _resolve(name + suffix) if suffix != "" else null
	if s == null:
		s = _resolve(name)  # repli : pas de variante lointaine pour ce son
	if s == null:
		return
	var p: AudioStreamPlayer3D = _free_player(_pool3d)
	if p == null:
		return
	p.stream = s
	p.pitch_scale = pitch_variation(_rng.randf())
	p.volume_db = volume_offset_db
	p.global_position = pos
	p.play()

# ======================================================================
#  FONCTIONS PURES (testées directement dans tests/audio/, sans autoload)
# ======================================================================

## Choisit un index de variation [0, count) à partir d'un flottant [0,1).
static func pick_variation(count: int, r: float) -> int:
	if count <= 1:
		return 0
	return clampi(int(floor(r * count)), 0, count - 1)

## Distance (m) -> "" (proche) ou "_far" (>= threshold), pour les sons positionnels.
static func far_suffix(distance: float, threshold: float = FAR_DISTANCE) -> String:
	return "_far" if distance >= threshold else ""

## Flottant [0,1) -> multiplicateur de hauteur dans [1-spread, 1+spread].
static func pitch_variation(r: float, spread: float = PITCH_SPREAD) -> float:
	return 1.0 + (r * 2.0 - 1.0) * spread

## Chemin res:// d'une variation (1-based sur le disque : nom_1.wav, nom_2.wav...).
static func sfx_path(name: String, variation_index: int) -> String:
	return "%s%s_%d.wav" % [SFX_DIR, name, variation_index + 1]

## Retire le suffixe "_<n>" final d'un nom de fichier (sans extension) pour
## retrouver le nom logique du son (ex. "gunshot_pistol_far_2" -> "gunshot_pistol_far").
static func strip_variation_suffix(basename: String) -> String:
	var parts := basename.split("_")
	if parts.size() >= 2 and parts[-1].is_valid_int():
		parts.remove_at(parts.size() - 1)
		return "_".join(parts)
	return basename

## Vitesse horizontale -> distance (m) entre deux pas, ou 0.0 si trop lent pour marcher.
static func footstep_stride(speed: float, walk_speed: float, sprint_speed: float) -> float:
	if speed < walk_speed * 0.35:
		return 0.0
	if speed >= sprint_speed * 0.9:
		return SPRINT_STRIDE
	return WALK_STRIDE

## Foulée -> nom du son ("footstep_walk"/"footstep_sprint"/"" si aucun pas).
static func footstep_sound_name(stride: float) -> String:
	if stride <= 0.0:
		return ""
	return "footstep_sprint" if stride >= SPRINT_STRIDE else "footstep_walk"

## Avance l'accumulateur de distance parcourue ; renvoie {steps, accum}.
## `steps` peut dépasser 1 sur un gros delta (lag spike) — l'appelant décide
## combien de sons il déclenche réellement.
static func footstep_ticks(accum: float, distance: float, stride: float) -> Dictionary:
	if stride <= 0.0:
		return {"steps": 0, "accum": 0.0}
	var total := accum + distance
	var steps := int(floor(total / stride))
	return {"steps": steps, "accum": total - steps * stride}

## États de mouvement qui produisent des bruits de pas (marche/sprint/accroupi).
static func state_allows_footsteps(state_name: String) -> bool:
	return state_name == "Walk" or state_name == "Sprint" or state_name == "Crouch"

## Écart de volume (dB, additif) à appliquer aux pas d'un joueur DISTANT :
## +ENEMY_FOOTSTEP_BOOST_DB s'il est ennemi, 0 s'il est allié (repère tactique,
## GF-11 — jamais appliqué aux pas LOCAUX). Équipe locale ou distante inconnue
## (< 0, ex. pas encore assignée par le serveur) : neutre (0 dB), on ne devine pas.
static func footstep_team_volume_offset_db(local_team: int, other_team: int) -> float:
	if local_team < 0 or other_team < 0:
		return 0.0
	return ENEMY_FOOTSTEP_BOOST_DB if other_team != local_team else 0.0

## Hauteur de chute (m, positive) -> faut-il jouer le son d'atterrissage ?
## (GF-11 — voir LANDING_MIN_FALL_HEIGHT).
static func should_play_landing(fall_height: float) -> bool:
	return fall_height >= LANDING_MIN_FALL_HEIGHT

## Front montant de la gâchette (`fire_pressed`, vrai UNE seule frame par
## appui — voir Weapon._owner_tick) sur un chargeur ET une réserve à zéro
## (aucun rechargement possible, sinon Weapon recharge à la place) -> faut-il
## jouer le clic à vide `dry_fire` (GF-12) ? `mag`/`reserve_ammo` négatifs
## comptent comme vides (défensif, ne devrait pas arriver en pratique).
static func should_play_dry_fire(trigger_edge: bool, mag: int, reserve_ammo: int) -> bool:
	return trigger_edge and mag <= 0 and reserve_ammo <= 0

## WeaponConfig -> nom du coup de feu ("gunshot_<classe>"), voir contract-r2.md
## "R-E audio" (pistol/magnum/smg/rifle/marksman/shotgun/sniper). Category ne
## distingue pas pistolet/magnum ni rifle/marksman : on affine avec les autres
## champs (dégâts, tir auto) qui, eux, séparent déjà ces armes dans le catalogue.
static func weapon_gunshot_name(cfg: WeaponConfig) -> String:
	if cfg == null:
		return "gunshot_rifle"
	match cfg.category:
		WeaponConfig.Category.SHOTGUN:
			return "gunshot_shotgun"
		WeaponConfig.Category.SNIPER:
			return "gunshot_sniper"
		WeaponConfig.Category.SMG:
			return "gunshot_smg"
		WeaponConfig.Category.RIFLE:
			return "gunshot_rifle" if cfg.automatic else "gunshot_marksman"
		WeaponConfig.Category.SIDEARM:
			return "gunshot_magnum" if cfg.damage >= 45.0 else "gunshot_pistol"
		_:
			return "gunshot_rifle"

## Nom logique d'une couche isolée du tir LOCAL (GF-11 : transient/body/mech/
## sub, générées par tools/audio/gen_weapon_layers.py) pour cette arme, ex.
## `weapon_layer_name(cfg, "sub")` -> "gunshot_rifle_sub".
static func weapon_layer_name(cfg: WeaponConfig, layer: String) -> String:
	return "%s_%s" % [weapon_gunshot_name(cfg), layer]

## Raycast plafond (depuis la tête du tireur LOCAL) -> nom logique de la queue
## de réverbération du tir ("tail_indoor"/"tail_outdoor", GF-11). Aucun impact
## dans la portée `INDOOR_CEILING_MAX`, ou aucun impact du tout : extérieur
## (grand ciel ouvert ou hangar/auvent trop haut pour renvoyer le son).
static func gunshot_tail_name(has_ceiling_hit: bool, ceiling_distance: float) -> String:
	if has_ceiling_hit and ceiling_distance <= INDOOR_CEILING_MAX:
		return "tail_indoor"
	return "tail_outdoor"

## slot ("C"/"Q"/"E"/"X") + display_name -> nom de son de capacité. L'ultime
## (X) joue toujours "ult" ; les autres sont classées par mots-clés (FR/EN,
## insensible aux accents/majuscules) ; repli sur "ability_generic".
static func ability_sound_name(slot: String, ability_name: String) -> String:
	if slot == "X":
		return "ult"
	var n := _fold(ability_name)
	for entry in _ABILITY_KEYWORDS:
		var sound: String = entry[0]
		for kw in entry[1]:
			if n.contains(kw):
				return sound
	return "ability_generic"

## killer_id (Health.died, déjà répliqué à tous) -> est-ce MOI qui ai tué un
## AUTRE joueur ? (kill_confirm ne doit jamais sonner sur sa propre mort).
static func is_local_kill(killer_id: int, local_peer_id: int, victim_is_local: bool) -> bool:
	return not victim_is_local and killer_id > 0 and killer_id == local_peer_id

# ---------------------------------------------------------- mix priorisé (GF-11)

## Un son doit-il être routé sur BUS_FEEDBACK (hitmarker/headshot/kill) plutôt
## que BUS_SFX, et déclencher le ducking du bus des tirs ? Voir `play_local`.
static func is_feedback_sound(name: String) -> bool:
	return FEEDBACK_SOUNDS.has(name)

## Gain (dB, additif — 0 = pas de ducking) à appliquer au bus des tirs
## `elapsed` secondes après le déclenchement d'un ducking de durée `duration`
## et de profondeur `depth_db` (négatif) : plein ducking IMMÉDIAT (le hit doit
## couper le tir sans rampe d'attaque, sinon le premier instant du son
## Feedback reste masqué), tenu, puis relâché LINÉAIREMENT à 0 dB sur les
## `SHOTS_DUCK_RELEASE_S` dernières secondes de la fenêtre (évite un "pop"
## audible en relâchant instantanément). `elapsed` hors [0, duration) : 0 dB
## (ducking pas encore déclenché, ou déjà terminé).
static func duck_gain_db(elapsed: float, duration: float = SHOTS_DUCK_DURATION_S, depth_db: float = SHOTS_DUCK_DB) -> float:
	if elapsed < 0.0 or elapsed >= duration:
		return 0.0
	var release_start := duration - SHOTS_DUCK_RELEASE_S
	if elapsed < release_start or release_start <= 0.0:
		return depth_db
	var t := (elapsed - release_start) / (duration - release_start)
	return depth_db * (1.0 - clampf(t, 0.0, 1.0))

# ---------------------------------------------------------- ambiance de carte

## Identifiant de carte (`Layouts.MAP_IDS` / `MatchConfig.map_id`) -> nom
## logique de la boucle d'ambiance ("" si l'identifiant est vide/inconnu —
## carte legacy sans catalogue, voir MainMenu.FALLBACK_SCENES : pas d'ambiance
## plutôt qu'un chargement qui échoue).
## maps-spec-v2.md : cargo_ship/wasteland n'ont pas encore leur propre boucle
## dédiée -> empruntent celle de la map v1 la plus proche en ambiance
## (port_ferraille : quais/eau ; val_poussière : désert/soleil) le temps
## qu'une boucle dédiée arrive. Ces deux id ne sont PAS dans `Layouts.MAP_IDS`
## (données hors Layouts.gd, voir layouts/cargo_ship.gd, layouts/wasteland.gd)
## donc testés AVANT le repli générique ci-dessous.
const _AMBIENCE_ALIASES := {
	"cargo_ship": "ambience_port_ferraille",
	"wasteland": "ambience_val_poussiere",
}

## Six maps v1 "dessinées à la main" (ex-`Layouts.MAP_IDS` — le fichier
## `Layouts.gd` lui-même a été supprimé avec leurs scènes/layouts lors du
## nettoyage du prototype 2026-09-26, mais leur ambiance sonore reste un id
## valide : comportement inchangé pour ces six noms, recopiés ICI en dur
## plutôt que de garder une dépendance à un fichier qui n'existe plus).
const _V1_MAP_IDS := [
	"port_ferraille", "val_poussiere", "saint_ombre",
	"col_du_vautour", "la_fosse", "le_belvedere",
]

static func ambience_name_for_map(map_id: String) -> String:
	if _AMBIENCE_ALIASES.has(map_id):
		return _AMBIENCE_ALIASES[map_id]
	if map_id == "" or not _V1_MAP_IDS.has(map_id):
		return ""
	return "ambience_%s" % map_id

# ---------------------------------------------------------- fondu enchaîné (crossfade)

## Progression [0,1] d'un fondu enchaîné de durée `duration` (s) à l'instant
## `elapsed` (s) écoulé depuis son déclenchement. `duration <= 0` : fondu
## instantané (progression 1 tout de suite, évite une division par zéro).
static func crossfade_progress(elapsed: float, duration: float) -> float:
	if duration <= 0.0:
		return 1.0
	return clampf(elapsed / duration, 0.0, 1.0)

## Gain (loi des sinus, à puissance constante) de la piste SORTANTE pour une
## progression `t` [0,1] de fondu enchaîné (1.0 à t=0, 0.0 à t=1).
static func crossfade_gain_out(t: float) -> float:
	return cos(clampf(t, 0.0, 1.0) * PI * 0.5)

## Gain (loi des sinus, à puissance constante) de la piste ENTRANTE pour une
## progression `t` [0,1] de fondu enchaîné (0.0 à t=0, 1.0 à t=1).
static func crossfade_gain_in(t: float) -> float:
	return sin(clampf(t, 0.0, 1.0) * PI * 0.5)

# ---------------------------------------------------------- stings de match

## Vrai durant la fenêtre de "dernière minute" du minuteur de MATCH commun
## (GameMode.match_elapsed/match_time_limit, TDM/Hardpoint). `limit <= 0`
## (pas de minuteur de match — modes à manches SnD/Duel, voir
## RoundMode.is_match_point pour leur équivalent) : jamais.
static func is_last_minute(elapsed: float, limit: float, window: float = LAST_MINUTE_WINDOW) -> bool:
	if limit <= 0.0:
		return false
	return elapsed >= limit - window and elapsed < limit

## "match_victory"/"match_defeat"/"" (pas encore de vainqueur, ou pas de
## joueur local) pour l'équipe locale, à partir de `winner`
## (GameMode.winner : -1 en cours, 0/1 équipe gagnante) et `local_team`.
static func match_result_sting(winner: int, local_team: int) -> String:
	if winner < 0 or local_team < 0:
		return ""
	return "match_victory" if winner == local_team else "match_defeat"

## Minuscules + accents français retirés (pour le classement par mots-clés).
static func _fold(s: String) -> String:
	var out := s.to_lower()
	for k in _ACCENT_MAP:
		out = out.replace(k, _ACCENT_MAP[k])
	return out

# ======================================================================
#  INITIALISATION
# ======================================================================

func _scan_manifest() -> void:
	_manifest.clear()
	var dir := DirAccess.open("res://assets/audio/sfx")
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".wav"):
			var name := strip_variation_suffix(f.get_basename())
			_manifest[name] = int(_manifest.get(name, 0)) + 1
		f = dir.get_next()
	dir.list_dir_end()

func _build_pools() -> void:
	_ensure_bus(BUS_VOICE)
	_ensure_bus(BUS_AMBIENCE)
	for i in POOL_UI:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_UI
		add_child(p)
		_ui_pool.append(p)
	for i in POOL_LOCAL:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_local_pool.append(p)
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = BUS_SFX
		add_child(p3)
		_pool3d.append(p3)
	for i in POOL_SHOT_LAYER:
		var p_tr := AudioStreamPlayer.new()
		p_tr.bus = BUS_SHOTS
		add_child(p_tr)
		_shot_transient_pool.append(p_tr)
	for i in POOL_SHOT_LAYER:
		var p_bd := AudioStreamPlayer.new()
		p_bd.bus = BUS_SHOTS
		add_child(p_bd)
		_shot_body_pool.append(p_bd)
	for i in POOL_SHOT_LAYER:
		var p_mc := AudioStreamPlayer.new()
		p_mc.bus = BUS_SHOTS
		add_child(p_mc)
		_shot_mech_pool.append(p_mc)
	for i in POOL_SHOT_LAYER:
		var p_sb := AudioStreamPlayer.new()
		p_sb.bus = BUS_SHOTS
		add_child(p_sb)
		_shot_sub_pool.append(p_sb)
	for i in POOL_SHOT_LAYER:
		var p_tl := AudioStreamPlayer.new()
		p_tl.bus = BUS_SHOTS
		add_child(p_tl)
		_shot_tail_pool.append(p_tl)
	for i in POOL_FEEDBACK:
		var pf := AudioStreamPlayer.new()
		pf.bus = BUS_FEEDBACK
		add_child(pf)
		_feedback_pool.append(pf)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = BUS_MUSIC
	add_child(_music_player)
	for i in 2:
		var ap := AudioStreamPlayer.new()
		ap.bus = BUS_AMBIENCE
		add_child(ap)
		_ambience_players.append(ap)
	_music_sting_player = AudioStreamPlayer.new()
	_music_sting_player.bus = BUS_MUSIC
	add_child(_music_sting_player)
	_last_minute_player = AudioStreamPlayer.new()
	_last_minute_player.bus = BUS_MUSIC
	add_child(_last_minute_player)
	_setup_mono_effect()

## Crée le bus `name` s'il n'existe pas encore (UX-06 : BUS_VOICE/BUS_AMBIENCE,
## absents de default_bus_layout.tres — hors du périmètre de cette tâche),
## envoyé vers BUS_MASTER comme les autres bus (voir default_bus_layout.tres
## pour Music/SFX/UI/Shots/Feedback). Idempotent : un rechargement de scène ou
## un test headless qui ré-instancierait l'autoload ne duplique jamais le bus.
func _ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return idx
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, BUS_MASTER)
	return idx

## Pose l'effet de downmix stéréo->mono sur BUS_MASTER (UX-06, accessibilité —
## "audio mono = canal gauche = droit") : `AudioEffectStereoEnhance.pan_pullout`
## à 0 downmixe les canaux latéraux en mono (doc Godot "AudioEffectStereoEnhance"
## "pan_pullout" : "A value of 0 will downmix stereo to mono"), 1.0 (défaut
## moteur) laisse la stéréo intacte — voir `mono_pan_pullout`, pure. Posé sur
## MASTER (après tous les bus/envois) pour couvrir tout le son (SFX/UI/
## Musique/Voix/Ambiance/Tirs/Feedback), pas seulement une couche. Idempotent
## comme `_ensure_bus` : réutilise un effet déjà posé plutôt que d'en empiler un second.
func _setup_mono_effect() -> void:
	var idx := AudioServer.get_bus_index(BUS_MASTER)
	if idx < 0:
		return
	for i in AudioServer.get_bus_effect_count(idx):
		var existing := AudioServer.get_bus_effect(idx, i)
		if existing is AudioEffectStereoEnhance:
			_mono_effect = existing
			return
	_mono_effect = AudioEffectStereoEnhance.new()
	_mono_effect.pan_pullout = mono_pan_pullout(Settings.audio_mono)
	AudioServer.add_bus_effect(idx, _mono_effect)

## `Settings.audio_mono` -> `pan_pullout` de l'effet de downmix (voir
## `_setup_mono_effect`) : 0 = mono (canal gauche = canal droit), 1 = stéréo
## intacte (défaut moteur `AudioEffectStereoEnhance`). Fonction PURE isolée
## pour rester testable sans passer par l'autoload (même principe que les
## autres fonctions pures de ce fichier — voir tête de fichier).
static func mono_pan_pullout(enabled: bool) -> float:
	return 0.0 if enabled else 1.0

## Rafraîchit `pan_pullout` selon `Settings.audio_mono` — appelée par
## `_apply_volumes` (sondage ≤ 2 Hz, voir VOLUME_INTERVAL) et directement par
## OptionsMenu au clic pour un retour immédiat.
func apply_audio_mono() -> void:
	if _mono_effect:
		_mono_effect.pan_pullout = mono_pan_pullout(Settings.audio_mono)

# ======================================================================
#  RÉSOLUTION SON -> FLUX
# ======================================================================

func _resolve(name: String) -> AudioStream:
	var count := int(_manifest.get(name, 0))
	if count <= 0:
		return null
	var idx := pick_variation(count, _rng.randf())
	return _load_stream(sfx_path(name, idx))

func _load_stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var s := load(path) as AudioStream
	if s:
		_stream_cache[path] = s
	return s

## Cherche un lecteur libre dans `pool` (AudioStreamPlayer / AudioStreamPlayer3D) ;
## à défaut (pool saturé, tous en train de jouer), vole le PLUS ANCIEN — celui
## dont la lecture a le plus avancé (tourniquet : ne vole plus jamais toujours
## le même canal, voir docs/audit/bugs.md BUG-15 — l'ancien code renvoyait
## systématiquement `pool[0]`).
func _free_player(pool: Array):
	if pool.is_empty():
		return null
	var oldest = pool[0]
	var oldest_position := -1.0
	for p in pool:
		if not p.playing:
			return p
		var position: float = p.get_playback_position()
		if position > oldest_position:
			oldest_position = position
			oldest = p
	return oldest

# ======================================================================
#  AUTO-CÂBLAGE — BOUTONS
# ======================================================================

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_wire_button(node)

func _wire_button(b: BaseButton) -> void:
	var id := b.get_instance_id()
	if _wired_buttons.has(id):
		return
	_wired_buttons[id] = true
	b.mouse_entered.connect(_on_button_hover)
	b.focus_entered.connect(_on_button_hover)
	b.pressed.connect(_on_button_pressed)
	b.tree_exited.connect(func(): _wired_buttons.erase(id))

func _on_button_hover() -> void:
	play_ui("ui_hover")

func _on_button_pressed() -> void:
	play_ui("ui_click")

# ======================================================================
#  AUTO-CÂBLAGE — JOUEURS (local + distants)
# ======================================================================

func _discover_players() -> void:
	var local := get_tree().get_first_node_in_group("local_player")
	if local and not _tracked.has(local.get_instance_id()):
		_track_player(local, true)
	var scene := get_tree().current_scene
	var players_root := scene.get_node_or_null("Players") if scene else null
	if players_root:
		for child in players_root.get_children():
			if child is CharacterBody3D and not _tracked.has(child.get_instance_id()):
				_track_player(child, child.is_in_group("local_player"))

func _track_player(node: Node, is_local: bool) -> void:
	var id := node.get_instance_id()
	_tracked[id] = {"node": node, "is_local": is_local, "accum": 0.0}
	node.tree_exited.connect(func(): _tracked.erase(id))
	_wire_health(node, is_local)
	if is_local:
		_wire_local_extras(node)
	else:
		_wire_remote_weapon(node)

## Vie : câblée sur TOUS les joueurs suivis (pas seulement le local), car
## Health.died est déjà diffusé à tous (_sync_health/_notify_death en
## call_local) et c'est le seul moyen fiable de savoir "c'est moi qui ai
## tué X" (killer_id) pour jouer kill_confirm côté tireur.
func _wire_health(node: Node, is_local: bool) -> void:
	var hp := node.get_node_or_null("Health")
	if hp == null:
		return
	if is_local and hp.has_signal("damaged"):
		hp.damaged.connect(func(_amount, _attacker_id): play_local("damage_taken"))
	hp.died.connect(func(killer_id: int):
		if is_local:
			play_local("death")
		if is_local_kill(killer_id, multiplayer.get_unique_id(), is_local):
			play_local("kill_confirm")
	)

## Arme + capacités du joueur LOCAL uniquement (prédiction propriétaire).
func _wire_local_extras(node: Node) -> void:
	var w := node.get_node_or_null("Weapon")
	if w:
		if w.has_signal("fired"):
			# GF-11 : tir LOCAL joué EN COUCHES (jamais le mix pré-mixé
			# `gunshot_<classe>.wav`, réservé aux tirs DISTANTS — voir `_wire_remote_weapon`).
			w.fired.connect(func(cfg: WeaponConfig): _play_local_gunshot(cfg, node))
		if w.has_signal("reload_started"):
			var weapon_id := w.get_instance_id()
			w.reload_started.connect(func(cfg: WeaponConfig):
				play_local("reload_out")
				var reload_time: float = cfg.reload_time if cfg else 1.5
				# BUG-K02 : le son "reload_in" est différé via _pending_reload_ins
				# (id d'instance, pas l'arme elle-même) plutôt qu'un
				# get_tree().create_timer() + lambda qui la capturerait — et
				# _play_reload_in_if_still_reloading revérifie à l'échéance qu'elle
				# existe ENCORE et recharge TOUJOURS (sinon : silence, pas un son
				# fantôme sur une arme changée, déposée, ou un joueur mort/déco).
				_pending_reload_ins[weapon_id] = maxf(reload_time, 0.05)
			)
		if w.has_signal("hit_confirmed"):
			# GF-07 : UNE confirmation par tir et par cible (plombs agrégés,
			# somme des dégâts) -> UN SEUL son hitmarker par tir, même pour un
			# fusil à pompe (12 plombs). `_is_kill` (vérité serveur) ne pilote
			# aucun son ici : "kill_confirm" reste câblé sur Health.died
			# (voir _wire_health) pour ne jamais sonner sur la propre mort.
			w.hit_confirmed.connect(func(_pos: Vector3, _dmg: float, headshot: bool, _is_kill: bool):
				play_local("hitmarker")
				if headshot:
					play_local("headshot")
			)
		if w.has_signal("weapon_changed"):
			w.weapon_changed.connect(func(_cfg: WeaponConfig): play_local("equip"))
		if w.has_signal("dry_fire"):
			# GF-12 : Weapon n'émet ce signal qu'une fois par appui (front
			# montant fire_pressed) — voir should_play_dry_fire, pure.
			w.dry_fire.connect(func(): play_local("dry_fire"))
	var ab := node.get_node_or_null("Abilities")
	if ab and ab.has_signal("ability_used"):
		ab.ability_used.connect(func(slot: String, ability_name: String):
			play_local(ability_sound_name(slot, ability_name))
		)

## Tirs des AUTRES joueurs (diffusion serveur -> tous sauf le tireur), en 3D.
func _wire_remote_weapon(node: Node) -> void:
	var w := node.get_node_or_null("Weapon")
	if w and w.has_signal("remote_fired"):
		w.remote_fired.connect(func(cfg: WeaponConfig, origin: Vector3, _dirs: Array):
			play_at(weapon_gunshot_name(cfg), origin, _listener_distance(origin))
		)

func _listener_distance(pos: Vector3) -> float:
	var local := get_tree().get_first_node_in_group("local_player")
	if local == null or not (local is Node3D):
		return 0.0
	return (local as Node3D).global_position.distance_to(pos)

# ======================================================================
#  RECHARGEMENT — son "reload_in" différé (voir _wire_local_extras, BUG-K02)
# ======================================================================

## Avance les rechargements locaux en attente du son différé "reload_in" ;
## appelé chaque frame comme les autres minuteries manuelles de cet autoload
## (ducking Feedback, fondu d'ambiance) — jamais un `get_tree().create_timer()`
## dont le lambda capturerait l'arme (docstring minuteries, tête de fichier) :
## on ne garde que son id d'instance, résolu seulement à l'échéance.
func _step_pending_reload_ins(delta: float) -> void:
	if _pending_reload_ins.is_empty():
		return
	var due: Array = []
	for weapon_id in _pending_reload_ins:
		var left: float = _pending_reload_ins[weapon_id] - delta
		if left > 0.0:
			_pending_reload_ins[weapon_id] = left
		else:
			due.append(weapon_id)
	for weapon_id in due:
		_pending_reload_ins.erase(weapon_id)
		_play_reload_in_if_still_reloading(weapon_id)

## L'arme qui a demandé "reload_in" existe-t-elle ENCORE et recharge-t-elle
## TOUJOURS ? Sinon : silence plutôt qu'un son de rechargement fantôme
## (docs/audit/bugs.md BUG-K02) — arme/joueur détruits entretemps (mort,
## déconnexion, fin de manche) OU rechargement annulé (ramassage, dépôt,
## achat, nouvelle manche : voir Inventory.set_loadout/give/replace_current/
## remove_current, qui remettent toutes `reloading` à faux).
func _play_reload_in_if_still_reloading(weapon_id: int) -> void:
	var w := instance_from_id(weapon_id)
	if w == null or not is_instance_valid(w):
		return
	var inv = w.get("_inv")
	if inv == null or not bool(inv.get("reloading")):
		return
	play_local("reload_in")

# ======================================================================
#  TIR LOCAL EN COUCHES (GF-11) — transitoire + corps + mécanique + sub
#  (jamais pour un tir distant) + queue choisie par raycast plafond.
# ======================================================================

func _play_local_gunshot(cfg: WeaponConfig, player: Node) -> void:
	_play_shot_layer(weapon_layer_name(cfg, "transient"), _shot_transient_pool)
	_play_shot_layer(weapon_layer_name(cfg, "body"), _shot_body_pool)
	_play_shot_layer(weapon_layer_name(cfg, "mech"), _shot_mech_pool)
	_play_shot_layer(weapon_layer_name(cfg, "sub"), _shot_sub_pool)
	_play_shot_layer(_local_gunshot_tail_name(player), _shot_tail_pool)

func _play_shot_layer(name: String, pool: Array) -> void:
	var s := _resolve(name)
	if s == null:
		return
	var p: AudioStreamPlayer = _free_player(pool)
	if p == null:
		return
	p.stream = s
	p.pitch_scale = pitch_variation(_rng.randf())
	p.play()

## Raycast vertical depuis la tête du tireur LOCAL jusqu'au plafond (masque
## PhysicsLayers.WORLD, même calque que les tirs) -> queue indoor/outdoor
## (fonction pure `gunshot_tail_name`, voir tests/audio/test_audio_mix.gd).
func _local_gunshot_tail_name(player: Node) -> String:
	var p3d := player as Node3D
	if p3d == null:
		return gunshot_tail_name(false, 0.0)
	var origin := p3d.global_position + Vector3.UP * CEILING_RAYCAST_HEAD_OFFSET
	var space := p3d.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.UP * INDOOR_CEILING_MAX, PhysicsLayers.WORLD)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return gunshot_tail_name(false, 0.0)
	return gunshot_tail_name(true, origin.distance_to(hit.position))

# ======================================================================
#  MIX PRIORISÉ (GF-11) — bus Feedback (hitmarker/headshot/kill) + ducking
#  manuel du bus des tirs (Godot n'a pas de compresseur à sidechain natif).
# ======================================================================

func _play_feedback(name: String) -> void:
	var s := _resolve(name)
	if s == null:
		return
	var p: AudioStreamPlayer = _free_player(_feedback_pool)
	if p == null:
		return
	p.stream = s
	p.pitch_scale = pitch_variation(_rng.randf())
	p.play()
	_shots_duck_elapsed = 0.0
	_apply_shots_duck(duck_gain_db(0.0))

## Avance le ducking en cours (voir `duck_gain_db`) ; appelé chaque frame
## depuis `_process`, indépendamment du sondage (comme le fondu d'ambiance).
func _step_shots_duck(delta: float) -> void:
	if _shots_duck_elapsed < 0.0:
		return
	_shots_duck_elapsed += delta
	if _shots_duck_elapsed >= SHOTS_DUCK_DURATION_S:
		_shots_duck_elapsed = -1.0
		_apply_shots_duck(0.0)
	else:
		_apply_shots_duck(duck_gain_db(_shots_duck_elapsed))

func _apply_shots_duck(extra_db: float) -> void:
	var idx := AudioServer.get_bus_index(BUS_SHOTS)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, _shots_base_db + extra_db)

# ======================================================================
#  PAS — sondage state/vélocité (voir docstring en tête de fichier)
# ======================================================================

func _poll_footsteps(delta: float) -> void:
	if delta <= 0.0:
		return
	for id in _tracked.keys():
		var info: Dictionary = _tracked[id]
		var node = info.node
		if not is_instance_valid(node):
			continue
		var pc := node as PlayerController
		if pc == null:
			continue
		var allowed := true
		if info.is_local:
			allowed = pc.is_on_floor() and state_allows_footsteps(pc.state_machine.current_name)
		var speed := Vector2(pc.velocity.x, pc.velocity.z).length()
		var walk_speed := FALLBACK_WALK_SPEED
		var sprint_speed := FALLBACK_SPRINT_SPEED
		if pc.config:
			walk_speed = pc.config.walk_speed
			sprint_speed = pc.config.sprint_speed
		var stride := footstep_stride(speed, walk_speed, sprint_speed) if allowed else 0.0
		var tick: Dictionary = footstep_ticks(info.accum, speed * delta, stride)
		info.accum = tick.accum
		_tracked[id] = info
		if tick.steps <= 0:
			continue
		var sname := footstep_sound_name(stride)
		if sname == "":
			continue
		for i in mini(int(tick.steps), 2):  # évite une rafale de sons sur un gros lag spike
			if info.is_local:
				play_local(sname)
			else:
				# GF-11 : pas ennemi +3 dB vs allié (repère tactique, jamais sur les pas LOCAUX).
				var offset_db := footstep_team_volume_offset_db(_local_team(), int(pc.team))
				play_at(sname, pc.global_position, _listener_distance(pc.global_position), offset_db)

# ======================================================================
#  ATTERRISSAGE (GF-11, LOCAL uniquement — voir docstring en tête de fichier)
# ======================================================================

func _poll_landing() -> void:
	var local := get_tree().get_first_node_in_group("local_player")
	var pc := local as PlayerController
	if pc == null:
		return
	var on_floor := pc.is_on_floor()
	if on_floor:
		if not _local_was_on_floor and should_play_landing(_local_air_peak_y - pc.global_position.y):
			play_local("land")
		_local_air_peak_y = pc.global_position.y
	else:
		_local_air_peak_y = maxf(_local_air_peak_y, pc.global_position.y)
	_local_was_on_floor = on_floor

# ======================================================================
#  MUSIQUE DE MENU
# ======================================================================

func _update_menu_music() -> void:
	var scene := get_tree().current_scene
	var in_menu := scene != null and scene.scene_file_path == MAIN_MENU_SCENE
	if in_menu:
		if not _music_player.playing:
			var s := _load_stream(MUSIC_MENU)
			if s is AudioStreamWAV:
				(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			if s:
				_music_player.stream = s
				_music_player.play()
	elif _music_player.playing:
		_music_player.stop()

# ======================================================================
#  AMBIANCE DE CARTE — fondu enchaîné entre `MatchConfig.map_id` et le
#  silence/une autre carte (voir docstring en tête de fichier).
# ======================================================================

## Une scène de MATCH (GameWorld, groupe "match") est-elle courante ? (par
## opposition au menu ou à une scène d'outillage sans ce nœud).
func _map_scene_active() -> bool:
	return get_tree().get_first_node_in_group("match") != null

func _update_map_ambience(delta: float) -> void:
	var target := ambience_name_for_map(MatchConfig.map_id) if _map_scene_active() else ""
	if target != _ambience_target:
		_begin_ambience_fade(target)
	_step_ambience_fade(delta)

## Démarre un nouveau fondu vers `target` ("" = fondu vers le silence : la
## piste ENTRANTE n'a rien à jouer, seule la piste courante s'éteint).
func _begin_ambience_fade(target: String) -> void:
	_ambience_target = target
	var in_idx := 1 - _ambience_active_idx
	var p: AudioStreamPlayer = _ambience_players[in_idx]
	if target != "":
		var s := _load_stream(MUSIC_DIR + target + ".wav")
		if s:
			if s is AudioStreamWAV:
				(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			p.stream = s
			p.volume_db = -80.0
			p.play()
	_ambience_active_idx = in_idx
	_ambience_fade_t = 0.0

func _step_ambience_fade(delta: float) -> void:
	if _ambience_fade_t < 0.0:
		return
	_ambience_fade_t += delta
	var t := crossfade_progress(_ambience_fade_t, AMBIENCE_CROSSFADE_S)
	var in_p: AudioStreamPlayer = _ambience_players[_ambience_active_idx]
	var out_p: AudioStreamPlayer = _ambience_players[1 - _ambience_active_idx]
	in_p.volume_db = linear_to_db(maxf(crossfade_gain_in(t), 0.0001))
	out_p.volume_db = linear_to_db(maxf(crossfade_gain_out(t), 0.0001))
	if t >= 1.0:
		_ambience_fade_t = -1.0
		out_p.stop()

# ======================================================================
#  STINGS DE MATCH — sondage du nœud du groupe "game_mode" (voir docstring
#  en tête de fichier). Chaque lookup est gardé (has_method/.get() nul-safe) :
#  ne casse jamais si le mode n'a pas (encore) cette forme.
# ======================================================================

func _update_match_stings() -> void:
	var gm := get_tree().get_first_node_in_group("game_mode")
	if gm == null or not is_instance_valid(gm):
		if _game_mode_node != null:
			_reset_match_sting_tracking()
		return

	if gm != _game_mode_node:
		_game_mode_node = gm
		_last_winner_seen = -1
		_last_minute_active = false
		_stop_last_minute_loop()
		_play_music_sting("match_start")

	var local_team := _local_team()
	var winner_val = gm.get("winner")
	var winner := int(winner_val) if winner_val != null else -1
	if winner != _last_winner_seen:
		_last_winner_seen = winner
		var sting := match_result_sting(winner, local_team)
		if sting != "":
			_play_music_sting(sting)
			_last_minute_active = false
			_stop_last_minute_loop()

	if winner == -1:
		_update_last_minute(gm, local_team)
	elif _last_minute_active:
		_last_minute_active = false
		_stop_last_minute_loop()

## Dernière minute du minuteur de MATCH (TDM/Hardpoint, `is_last_minute`) OU
## point de match (modes à manches SnD/Duel, `RoundMode.is_match_point`) :
## joue le sting une fois à l'entrée, démarre/arrête la boucle percussive.
func _update_last_minute(gm: Node, local_team: int) -> void:
	var active := false
	var elapsed_val = gm.get("match_elapsed")
	var limit_val = gm.get("match_time_limit")
	if elapsed_val != null and limit_val != null:
		active = is_last_minute(float(elapsed_val), float(limit_val))
	if not active and local_team >= 0 and gm.has_method("is_match_point"):
		active = bool(gm.call("is_match_point", local_team))

	if active and not _last_minute_active:
		_last_minute_active = true
		_play_music_sting("match_last_minute")
		_start_last_minute_loop()
	elif not active and _last_minute_active:
		_last_minute_active = false
		_stop_last_minute_loop()

func _reset_match_sting_tracking() -> void:
	_game_mode_node = null
	_last_winner_seen = -1
	if _last_minute_active:
		_last_minute_active = false
		_stop_last_minute_loop()

## Équipe du joueur LOCAL (-1 s'il n'existe pas encore).
func _local_team() -> int:
	var arr := get_tree().get_nodes_in_group("local_player")
	if arr.is_empty():
		return -1
	var t = arr[0].get("team")
	return int(t) if t != null else -1

func _play_music_sting(name: String) -> void:
	var s := _load_stream(MUSIC_DIR + name + ".wav")
	if s == null:
		return
	_music_sting_player.stream = s
	_music_sting_player.play()

func _start_last_minute_loop() -> void:
	if _last_minute_player.playing:
		return
	var s := _load_stream(MUSIC_DIR + "last_minute_loop.wav")
	if s == null:
		return
	if s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_last_minute_player.stream = s
	_last_minute_player.play()

func _stop_last_minute_loop() -> void:
	if _last_minute_player.playing:
		_last_minute_player.stop()

# ======================================================================
#  VOLUMES (Settings.volume_master/volume_sfx/volume_music/volume_ui/
#  volume_voice/volume_ambience/audio_mono, UX-06 — 0..1)
# ======================================================================

func _apply_volumes() -> void:
	_set_bus_volume(BUS_MASTER, Settings.volume_master)
	_set_bus_volume(BUS_MUSIC, Settings.volume_music)
	_set_bus_volume(BUS_SFX, Settings.volume_sfx)
	# UX-06 : volume UI dédié (avant cette tâche, suivait volume_sfx comme Feedback ci-dessous).
	_set_bus_volume(BUS_UI, Settings.volume_ui)
	_set_bus_volume(BUS_FEEDBACK, Settings.volume_sfx)
	_set_bus_volume(BUS_VOICE, Settings.volume_voice)
	_set_bus_volume(BUS_AMBIENCE, Settings.volume_ambience)
	# BUS_SHOTS n'est PAS mis à jour par _set_bus_volume : le ducking (GF-11)
	# module son volume_db en continu, donc on ne fait que rafraîchir la base
	# et laisser _apply_shots_duck réappliquer le ducking en cours par-dessus.
	_shots_base_db = linear_to_db(clampf(Settings.volume_sfx, 0.0, 1.0))
	_apply_shots_duck(duck_gain_db(_shots_duck_elapsed) if _shots_duck_elapsed >= 0.0 else 0.0)
	apply_audio_mono()

func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))
