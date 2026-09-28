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
##  - l'arme du joueur LOCAL (fired/hit_confirmed/weapon_changed) ;
##  - le foley d'arme (rechargement/inspection, revolver+Ravage, tâche "son"
##    2026-09-27) est programmé pour TOUT joueur suivi (local + distants) sur
##    le front montant du bit "reloading" de `anim_state` (répliqué TOUJOURS),
##    voir `_poll_weapon_foley`/WeaponFoley.gd — plus fiable que
##    `reload_started` (prédiction PROPRIÉTAIRE seule) pour un corps distant ;
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

## ------------------------------------------------------------ MIX (tâche "son", 2026-09-27)
## Écarts de mix STATIQUES par bus, ADDITIFS au-dessus du réglage utilisateur
## (Settings.volume_*, voir `_apply_volumes`) — jamais à sa place : monter le
## curseur SFX garde le MÊME équilibre relatif entre ces bus. Choix (dB) :
## les tirs doivent DOMINER (+3, en plus du ducking Feedback existant), les
## pas restent au niveau neutre du bus SFX (0 -- déjà clairement audibles,
## contrat "compétitif"), l'interface reste sous le jeu (-4), le feedback de
## hit doit PERCER même par-dessus des tirs proches (+1.5, avant le ducking
## manuel du bus Shots qui le protège déjà), musique et ambiance de carte
## restent des toiles de fond (-8 / -10).
const MIX_OFFSET_SHOTS_DB := 3.0
const MIX_OFFSET_SFX_DB := 0.0
const MIX_OFFSET_UI_DB := -4.0
const MIX_OFFSET_FEEDBACK_DB := 1.5
const MIX_OFFSET_MUSIC_DB := -8.0
const MIX_OFFSET_AMBIENCE_DB := -10.0
## Foley d'arme (revolver/Ravage) et pas d'un joueur DISTANT : plus discret
## que la version LOCALE en 2D (contrat : "remote players/bots in 3D, quieter").
const MIX_OFFSET_REMOTE_FOLEY_DB := -6.0

## ------------------------------------------------------------ SPATIALISATION/OCCLUSION
## Cadence (s) du sondage occlusion + surface au sol (raycasts, voir
## `_poll_spatial_audio`) — throttlé/mis en cache (contrat), jamais à chaque frame.
const SPATIAL_POLL_INTERVAL := 0.2
## Portée (m) du raycast sol qui classe la surface sous un joueur (voir
## `_classify_ground_surface`) — un peu plus que la marge de collage au sol
## (floor_snap_length 0.4 m, PlayerController) pour rester fiable en pente légère.
const GROUND_SURFACE_RAYCAST_M := 0.6

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

## Dernier id d'arme ayant réellement joué "equip" (voir la docstring de son
## câblage, `_wire_local_extras`) -- LOCAL uniquement (un seul joueur humain
## par client), sentinel -999 pour que le tout premier appel (arme de spawn)
## joue quand même son "equip".
var _local_last_equip_id: int = -999

var _discovery_left: float = 0.0
var _volume_left: float = 0.0

# ------------------------------------------------------------------ journal de debug (vérification mix)

## Off par défaut (coût nul en jeu normal) — activé par un outil de capture
## (tools/audio/audio_capture.gd, tâche "son" 2026-09-27, "vérification que
## tu ne peux pas sauter") pour horodater CHAQUE son réellement joué (nom,
## volume_db résolu) et comparer au log attendu après coup.
var debug_log_enabled: bool = false
var debug_log: Array = []

func _debug_log(name: String, volume_db: float) -> void:
	if debug_log_enabled:
		debug_log.append({"t": Time.get_ticks_msec() / 1000.0, "sound": name, "volume_db": volume_db})

# ------------------------------------------------------------------ spatialisation/occlusion (tâche "son")

## instance_id joueur -> occlus (raycast tête locale -> joueur, throttlé, voir `_poll_spatial_audio`).
var _occlusion_cache: Dictionary = {}
## instance_id joueur -> "metal"/"concrete" (raycast sol sous ses pieds, throttlé).
var _ground_surface_cache: Dictionary = {}
var _spatial_poll_left: float = 0.0

# ------------------------------------------------------------------ foley d'arme (revolver/Ravage, tâche "son")

## instance_id joueur -> id d'arme courant (`Weapon.current_id_changed`,
## diffusé à TOUS les pairs — voir CharacterAnimator._on_current_weapon_changed
## pour le même besoin déjà résolu ainsi côté anim). -1 = encore inconnu.
var _weapon_current_id: Dictionary = {}
## instance_id joueur -> dernier bit "reloading" vu (`anim_state`, répliqué
## TOUJOURS — voir PlayerController.anim_state/CharacterAnimator.unpack_reloading)
## pour détecter le FRONT MONTANT d'un rechargement, pour LE LOCAL comme pour
## un DISTANT : contrairement à `Weapon.reload_started` (prédiction, propriétaire
## SEULEMENT — voir sa docstring), ce bit est fiable pour n'importe quel joueur.
var _reload_flags: Dictionary = {}
## instance_id joueur -> génération de rechargement (incrémentée à chaque
## front montant) : un événement de foley programmé compare sa génération à
## celle-ci avant de jouer, pour ignorer un rechargement déjà ANNULÉ (arme
## changée, mort) même si un autre a démarré entre-temps.
var _reload_session: Dictionary = {}
## Même rôle que `_reload_session`, pour l'inspection du revolver (E) — dict
## séparé : les deux gestes ont chacun leur propre file d'événements/génération.
var _inspect_session: Dictionary = {}
## File des événements de foley programmés (rechargement/inspection) : chacun
## {"player_id", "session", "time_left", "sound", "is_local"} — avancée chaque
## frame comme le ducking Feedback/le fondu d'ambiance (voir `_step_pending_foley`).
var _pending_foley: Array = []

# ------------------------------------------------------------------ ducking (GF-11)

## Volume (dB) courant du bus 'Shots' HORS ducking (recalculé à chaque
## `_apply_volumes`, réglages) — le ducking s'additionne dessus.
var _shots_base_db: float = 0.0
## Secondes écoulées depuis le dernier son Feedback ; -1 = aucun ducking actif.
var _shots_duck_elapsed: float = -1.0

# ------------------------------------------------------------------ assourdissement flash (grenades, tâche "son")

## Filtres passe-bas idempotents posés sur SFX/Shots (voir `_setup_muffle_effects`)
## — modulés en continu par `_step_blind_muffle` pendant que le joueur LOCAL est
## ébloui (UtilityThrower.local_blinded, câblé dans `_wire_local_extras`).
var _sfx_lowpass: AudioEffectLowPassFilter
var _shots_lowpass: AudioEffectLowPassFilter
## Durée (s) d'éblouissement plein écran de l'éblouissement LOCAL en cours (0 =
## aucun) et secondes écoulées depuis son déclenchement (-1 = pas d'éblouissement).
var _blind_duration: float = 0.0
var _blind_elapsed: float = -1.0

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
	_poll_spatial_audio(delta)  # occlusion + surface au sol : throttlé en interne (SPATIAL_POLL_INTERVAL)
	_poll_weapon_foley(delta)  # front montant "reloading" (anim_state) -> programme le foley d'arme
	_step_pending_foley(delta)  # avance/déclenche les événements de foley programmés
	_step_blind_muffle(delta)  # lowpass SFX/Shots pendant l'éblouissement local (grenades)

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
	_debug_log(name, p.volume_db)

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
	_debug_log(name, p.volume_db)

## Son positionnel 3D (tirs/pas des autres joueurs, capacités visibles...).
## `distance` (déjà connue par l'appelant) choisit la variante "_far" au besoin.
## `volume_offset_db` : décalage additif (ex. +3 dB pas ennemi vs allié, GF-11).
## `occluded` (tâche "son", 2026-09-27, point 3) : la SOURCE est-elle derrière
## de la géométrie du monde vue depuis l'auditeur local (voir
## `_poll_spatial_audio`/AudioOcclusion, throttlé/mis en cache par l'appelant —
## jamais recalculé ici) ? Assombrit le filtre de distance et ajoute une
## atténuation, PAR-DESSUS les réglages de spatialisation par catégorie
## (SpatialAudioParams, point 2 — gunshot/footstep_walk/footstep_sprint/
## grenade/explosion, portée + modèle d'atténuation propres à chacun).
func play_at(name: String, pos: Vector3, distance: float = 0.0, volume_offset_db: float = 0.0, occluded: bool = false) -> void:
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
	var category := SpatialAudioParams.category_for_sound(name)
	SpatialAudioParams.apply_to(p, category)
	var base_cutoff: float = SpatialAudioParams.params_for(category)["attenuation_filter_cutoff_hz"]
	p.attenuation_filter_cutoff_hz = AudioOcclusion.occluded_cutoff_hz(occluded, base_cutoff)
	p.stream = s
	p.pitch_scale = pitch_variation(_rng.randf())
	p.volume_db = volume_offset_db + AudioOcclusion.occluded_volume_offset_db(occluded)
	p.global_position = pos
	p.play()
	_debug_log(name, p.volume_db)

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
## Pas d'un joueur DISTANT (retour utilisateur 2026-09-27 : « un bruit qui se répète » = le
## tapotement continu des bots qui marchent). Règle façon CS, cohérente avec la minicarte
## (MinimapHUD.heard : la marche est silencieuse) : la MARCHE (et l'accroupi) ne s'entend que de
## près (<= REMOTE_WALK_MAX_M) et bas (REMOTE_WALK_DB) ; les coéquipiers sont baissés de
## ALLY_FOOTSTEP_DB pour ne pas masquer les ennemis. Renvoie -INF = ne pas jouer. Fonction PURE.
const REMOTE_WALK_MAX_M := 6.0
const REMOTE_WALK_DB := -12.0
const ALLY_FOOTSTEP_DB := -4.0

static func remote_footstep_offset_db(is_walk: bool, is_enemy: bool, distance: float) -> float:
	if is_walk and distance > REMOTE_WALK_MAX_M:
		return -INF
	var db := (REMOTE_WALK_DB if is_walk else 0.0)
	db += ENEMY_FOOTSTEP_BOOST_DB if is_enemy else ALLY_FOOTSTEP_DB
	return db

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
		# Revolver (catégorie PISTOL) : tombait dans le cas par défaut et jouait le FUSIL.
		WeaponConfig.Category.PISTOL:
			return "gunshot_revolver"
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
## Shipment (carte courante, cour à conteneurs) n'a pas encore sa propre
## boucle dédiée -> emprunte celle de la map v1 la plus proche en ambiance
## (port_ferraille : quais/eau) le temps qu'une boucle dédiée arrive. Pas dans
## `_V1_MAP_IDS` (données v1 encore présentes en assets, mais Layouts.gd
## lui-même est supprimé, nettoyage du prototype 2026-09-26) donc testé AVANT
## le repli générique ci-dessous.
##
## Canyon Express (2026-09-28, MapCatalog.gd) : train à l'arrêt sur un pont
## au-dessus d'un canyon -> pas de boucle dédiée non plus, aucun nouveau
## fichier audio (contrat de tâche) -- emprunte parmi les six boucles v1
## existantes (`_V1_MAP_IDS` ci-dessous) celle la plus proche en ambiance :
## port_ferraille (quais/eau), val_poussiere (vallée désertique), saint_ombre,
## col_du_vautour (col de montagne), la_fosse, le_belvedere (promontoire) --
## val_poussiere est la seule à évoquer un vent sec de plein air désertique
## (le canyon n'a ni eau ni intérieur), retenue ici.
const _AMBIENCE_ALIASES := {
	"shipment": "ambience_port_ferraille",
	"canyon_express": "ambience_val_poussiere",
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
	_setup_muffle_effects()

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

## Pose (idempotent, même patron que `_setup_mono_effect`) un
## AudioEffectLowPassFilter sur SFX et Shots — modulé en continu par
## `_step_blind_muffle` pendant l'éblouissement LOCAL (contrat : "muffle the
## world"). Ouvert (GrenadeAudio.OPEN_CUTOFF_HZ) hors éblouissement : ne
## touche jamais le son en dehors de cette fenêtre.
func _setup_muffle_effects() -> void:
	_sfx_lowpass = _ensure_lowpass(BUS_SFX)
	_shots_lowpass = _ensure_lowpass(BUS_SHOTS)

func _ensure_lowpass(bus_name: String) -> AudioEffectLowPassFilter:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return null
	for i in AudioServer.get_bus_effect_count(idx):
		var existing := AudioServer.get_bus_effect(idx, i)
		if existing is AudioEffectLowPassFilter:
			return existing
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = GrenadeAudio.OPEN_CUTOFF_HZ
	AudioServer.add_bus_effect(idx, lp)
	return lp

## Avance l'assourdissement (GrenadeAudio.muffle_cutoff_hz, voir sa docstring :
## plein étouffement pendant l'éblouissement, puis fondu linéaire sur
## FlashMath.RECOVERY_S) — appelé chaque frame comme le ducking Feedback.
func _step_blind_muffle(delta: float) -> void:
	if _blind_elapsed < 0.0:
		return
	_blind_elapsed += delta
	var cutoff := GrenadeAudio.muffle_cutoff_hz(_blind_elapsed, _blind_duration, FlashMath.RECOVERY_S)
	if _sfx_lowpass:
		_sfx_lowpass.cutoff_hz = cutoff
	if _shots_lowpass:
		_shots_lowpass.cutoff_hz = cutoff
	if cutoff >= GrenadeAudio.OPEN_CUTOFF_HZ - 0.01:
		_blind_elapsed = -1.0

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
	# Tâche "son" (point 8, UI) : le clic varie selon le widget — méta
	# "sfx_click" posée par MenuWidgets.gd (tab_button -> "ui_tab", switch_control
	# -> "ui_toggle") ou directement par l'écran qui construit le bouton
	# (HomeScreen._play_button -> "ui_confirm") ; "ui_click" par défaut pour
	# tout bouton ordinaire (inchangé). Jamais posée deux fois (hover séparé).
	b.pressed.connect(func(): play_ui(String(b.get_meta("sfx_click", "ui_click"))))
	b.tree_exited.connect(func(): _wired_buttons.erase(id))

func _on_button_hover() -> void:
	play_ui("ui_hover")

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
	node.tree_exited.connect(func():
		_tracked.erase(id)
		_weapon_current_id.erase(id)
		_reload_flags.erase(id)
		_reload_session.erase(id)
		_inspect_session.erase(id)
		_occlusion_cache.erase(id)
		_ground_surface_cache.erase(id)
	)
	_wire_health(node, is_local)
	_wire_weapon_id_tracking(node, id)
	if is_local:
		_wire_local_extras(node)
	else:
		_wire_remote_weapon(node)

## `Weapon.current_id_changed` — diffusé à TOUS les pairs (voir sa docstring :
## "les tiers en ont besoin pour savoir quelle arme afficher"), donc fiable
## pour n'importe quel joueur (local OU distant), contrairement à `cfg()`/`_inv`
## (prédiction propriétaire seule, jamais mise à jour pour un corps observé
## depuis un AUTRE pair). Alimente `_weapon_current_id`, seule source utilisée
## par `_poll_weapon_foley` pour choisir la table WeaponFoley à programmer.
func _wire_weapon_id_tracking(node: Node, id: int) -> void:
	var w := node.get_node_or_null("Weapon")
	if w and w.has_signal("current_id_changed"):
		w.current_id_changed.connect(func(wid: int): _weapon_current_id[id] = wid)

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
			w.fired.connect(func(cfg: WeaponConfig, is_fan: bool):
				_play_local_gunshot(cfg, node)
				# Tâche "son" : "fan the hammer" (RMB tenu sur le revolver) rejoue le
				# chien à CHAQUE coup en éventail, en plus du tir lui-même — jamais
				# pour un tir tap ou une arme sans mode fan (`is_fan` est alors
				# toujours faux, voir Weapon._owner_tick).
				if is_fan and cfg and cfg.category == WeaponConfig.Category.PISTOL:
					play_local("rev_hammer")
			)
			# Rechargement/inspection du revolver+Ravage : programmés par
			# `_poll_weapon_foley` (front montant du bit "reloading" de
			# `anim_state`, répliqué TOUJOURS — voir sa docstring), plus fiable
			# que `reload_started` (prédiction PROPRIÉTAIRE seule) puisqu'il
			# fonctionne identiquement pour un joueur DISTANT (voir
			# MIX_OFFSET_REMOTE_FOLEY_DB) sans dupliquer la logique ici.
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
			# BUG trouvé pendant la vérification du mix (capture 2026-09-27,
			# tools/audio/audio_capture.gd) : `weapon_changed` est réémis par
			# `Weapon._emit_local()` à CHAQUE tir/rechargement/synchro serveur
			# (pas seulement à un vrai changement d'arme), donc "equip" rejouait
			# à chaque coup de feu -- 23 lectures pour 2 changements d'arme
			# réels sur une capture de test. Dédoublonné ici sur l'id d'arme
			# RÉELLEMENT différent du précédent (`_local_last_equip_id`, sentinel
			# -999 pour que le tout premier appel -- l'arme de spawn -- joue
			# quand même son "equip").
			w.weapon_changed.connect(func(cfg: WeaponConfig):
				var wid := WeaponDatabase.id_of(cfg)
				if wid != _local_last_equip_id:
					_local_last_equip_id = wid
					play_local("equip")
			)
		if w.has_signal("dry_fire"):
			# GF-12 : Weapon n'émet ce signal qu'une fois par appui (front
			# montant fire_pressed) — voir should_play_dry_fire, pure.
			w.dry_fire.connect(func(): play_local("dry_fire"))
	var ab := node.get_node_or_null("Abilities")
	if ab and ab.has_signal("ability_used"):
		ab.ability_used.connect(func(slot: String, ability_name: String):
			play_local(ability_sound_name(slot, ability_name))
		)
	# Grenades (tâche "son") : pin/throw/bounce/détonation sont joués
	# DIRECTEMENT par ThrownUtility.gd/UtilityThrower.gd (mêmes fichiers que le
	# contrat autorise à toucher, voir leur docstring `_play_sfx`) — seul
	# l'assourdissement du MIX pendant l'éblouissement LOCAL relève de cet
	# autoload (accès aux bus SFX/Shots, voir `_step_blind_muffle`).
	var ut := node.get_node_or_null("UtilityThrower")
	if ut and ut.has_signal("local_blinded"):
		ut.local_blinded.connect(func(duration_s: float):
			# "flash_ring" (contrat : "3 s tinnitus") joué UNE fois au déclenchement,
			# en plus de l'assourdissement continu du MIX (_step_blind_muffle) —
			# les deux durent tout l'éblouissement + le fondu (FlashMath.RECOVERY_S).
			play_local("flash_ring")
			_blind_duration = duration_s
			_blind_elapsed = 0.0
		)

## Tirs des AUTRES joueurs (diffusion serveur -> tous sauf le tireur), en 3D.
func _wire_remote_weapon(node: Node) -> void:
	var w := node.get_node_or_null("Weapon")
	if w and w.has_signal("remote_fired"):
		var id := node.get_instance_id()
		w.remote_fired.connect(func(cfg: WeaponConfig, origin: Vector3, _dirs: Array):
			play_at(weapon_gunshot_name(cfg), origin, _listener_distance(origin), 0.0, _occlusion_cache.get(id, false))
		)

func _listener_distance(pos: Vector3) -> float:
	var local := get_tree().get_first_node_in_group("local_player")
	if local == null or not (local is Node3D):
		return 0.0
	return (local as Node3D).global_position.distance_to(pos)

# ======================================================================
#  OCCLUSION + SURFACE AU SOL (tâche "son", 2026-09-27, points 3/7) — un
#  raycast PAR JOUEUR suivi, throttlé à SPATIAL_POLL_INTERVAL (jamais à
#  chaque frame comme les autres sondages coûteux de ce fichier, voir
#  DISCOVERY_INTERVAL/VOLUME_INTERVAL) ; le résultat brut est réduit à une
#  décision par les fonctions PURES d'AudioOcclusion/SurfaceSound (voir
#  tests/audio/) — ce fichier reste seul à toucher la physique/l'arbre.
# ======================================================================

func _poll_spatial_audio(delta: float) -> void:
	_spatial_poll_left -= delta
	if _spatial_poll_left > 0.0:
		return
	_spatial_poll_left = SPATIAL_POLL_INTERVAL
	var local := get_tree().get_first_node_in_group("local_player") as Node3D
	var listener_head := Vector3.ZERO
	if local:
		listener_head = local.head.global_position if ("head" in local and local.head) else local.global_position
	# PhysicsLayers.WORLD (calque 1) porte AUSSI les joueurs ("monde et
	# joueurs", voir PhysicsLayers.gd) : sans exclusion, ce raycast toucherait
	# la capsule de la SOURCE elle-même (juste avant d'atteindre son propre
	# `global_position`) et celle de tout joueur debout entre les deux,
	# donnant un "occlus" à chaque fois même à découvert. On exclut donc TOUS
	# les corps joueurs suivis (jamais le décor) — seule une vraie géométrie
	# de monde doit occlure (contrat lead).
	var player_rids: Array = []
	for pid in _tracked.keys():
		var pn = _tracked[pid].node
		if pn and is_instance_valid(pn) and pn.has_method("get_rid"):
			player_rids.append(pn.get_rid())
	for id in _tracked.keys():
		var info: Dictionary = _tracked[id]
		var p3d := info.node as Node3D
		if p3d == null or not is_instance_valid(p3d):
			continue
		_ground_surface_cache[id] = _classify_ground_surface(p3d, player_rids)
		if info.is_local or local == null:
			continue
		_occlusion_cache[id] = _classify_occlusion(listener_head, p3d, player_rids)

## Raycast vertical sous les pieds de `p3d` (masque PhysicsLayers.WORLD, même
## calque que les tirs/le raycast plafond des tirs ; joueurs exclus, voir
## `_poll_spatial_audio`) -> surface classée (SurfaceSound.surface_of, pure) —
## "concrete" si rien touché (rayon hors sol, ex. en l'air) ou hors de l'arbre.
func _classify_ground_surface(p3d: Node3D, exclude_rids: Array) -> String:
	if not p3d.is_inside_tree():
		return SurfaceSound.CONCRETE
	var origin := p3d.global_position + Vector3.UP * 0.1
	var space := p3d.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * GROUND_SURFACE_RAYCAST_M, PhysicsLayers.WORLD)
	q.exclude = exclude_rids
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	return SurfaceSound.CONCRETE if hit.is_empty() else SurfaceSound.surface_of(hit.collider)

## Raycast auditeur (tête LOCALE) -> `source` (position du joueur DISTANT
## suivi), joueurs exclus (voir `_poll_spatial_audio`) : seule une vraie
## géométrie de monde compte comme occlusion.
func _classify_occlusion(listener_head: Vector3, source: Node3D, exclude_rids: Array) -> bool:
	if not source.is_inside_tree():
		return false
	var space := source.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(listener_head, source.global_position, PhysicsLayers.WORLD)
	q.exclude = exclude_rids
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	return AudioOcclusion.is_occluded_from_hit(hit)

# ======================================================================
#  FOLEY D'ARME (revolver/Ravage, tâche "son" 2026-09-27) — programmé sur le
#  front montant du bit "reloading" de `anim_state` (répliqué TOUJOURS, voir
#  la docstring de `_weapon_current_id`/`_reload_flags`) : marche pour le
#  joueur LOCAL comme pour un DISTANT, contrairement à l'ancien mécanisme
#  (retiré) qui ne branchait `reload_started` — prédiction PROPRIÉTAIRE
#  seule — que côté LOCAL (docs/audit/bugs.md BUG-K02 : la même discipline de
#  "revérifier avant de jouer" est reprise ici via `_reload_session`).
# ======================================================================

## Sondage du front montant "reloading" pour CHAQUE joueur suivi (local +
## distants) — programme la table WeaponFoley adaptée (revolver : 5
## événements de foley dédiés ; toute autre arme : reload_out/reload_in aux
## fractions de rifle.py `build_reload`, voir WeaponFoley.gd).
func _poll_weapon_foley(delta: float) -> void:
	for id in _tracked.keys():
		var info: Dictionary = _tracked[id]
		var pc := info.node as PlayerController
		if pc == null or not is_instance_valid(pc):
			continue
		var reloading := CharacterAnimator.unpack_reloading(pc.anim_state)
		var was: bool = _reload_flags.get(id, false)
		_reload_flags[id] = reloading
		if reloading and not was:
			_start_weapon_foley(id, info.is_local)
		# Inspection (touche E, revolver seul) : `player.input.inspect_pressed`
		# n'est un front fiable QUE pour le LOCAL (aucune animation FP tierce
		# n'est répliquée pour un joueur DISTANT dans ce prototype — FPArmsRig
		# reste caché pour tout le monde sauf son propriétaire, voir Weapon.gd
		# `_muzzle_position` — donc rien à faire sonner pour un observateur ici).
		# Gardé aussi derrière `not reloading` : un E pressé PENDANT un
		# rechargement est annulé côté visuel (FPArmsMath.should_cancel_inspect)
		# et ne doit pas programmer un foley fantôme.
		if info.is_local and not reloading and pc.input and pc.input.inspect_pressed:
			_start_revolver_inspect_foley(id)

func _start_weapon_foley(id: int, is_local: bool) -> void:
	var wid := int(_weapon_current_id.get(id, -1))
	var cfg := WeaponDatabase.get_by_id(wid)
	if cfg == null:
		return  # id pas encore connu (aucun `current_id_changed` reçu) : pas de son fantôme.
	var session := int(_reload_session.get(id, 0)) + 1
	_reload_session[id] = session
	var events: Array = WeaponFoley.revolver_reload_events(cfg.reload_time) if cfg.category == WeaponConfig.Category.PISTOL \
		else WeaponFoley.rifle_reload_events(cfg.reload_time)
	_schedule_foley(id, is_local, "reload", session, wid, events)

## Foley d'inspection du revolver (WeaponFoley.revolver_inspect_events) —
## `REVOLVER_INSPECT_DURATION_S` : aucun champ `WeaponConfig` dédié à la durée
## du geste d'inspection (contrairement à `reload_time`) — valeur recopiée de
## art/characters/frog_cowboy/anim/pistol.py `INSPECT_S` (2.5 s authored),
## voir le rendu de tâche pour ce manque signalé.
const REVOLVER_INSPECT_DURATION_S := 2.5

func _start_revolver_inspect_foley(id: int) -> void:
	var wid := int(_weapon_current_id.get(id, -1))
	var cfg := WeaponDatabase.get_by_id(wid)
	if cfg == null or cfg.category != WeaponConfig.Category.PISTOL:
		return  # inspection foley : revolver seul (contrat) — jamais le Ravage.
	var session := int(_inspect_session.get(id, 0)) + 1
	_inspect_session[id] = session
	_schedule_foley(id, true, "inspect", session, wid, WeaponFoley.revolver_inspect_events(REVOLVER_INSPECT_DURATION_S))

func _schedule_foley(id: int, is_local: bool, kind: String, session: int, wid: int, events: Array) -> void:
	for e in events:
		_pending_foley.append({
			"player_id": id, "kind": kind, "session": session, "weapon_id": wid,
			"time_left": float(e["time"]), "sound": String(e["sound"]), "is_local": is_local,
		})

## Avance/déclenche la file d'événements programmés — appelé chaque frame
## comme le ducking Feedback/le fondu d'ambiance (voir docstring minuteries,
## tête de fichier).
func _step_pending_foley(delta: float) -> void:
	if _pending_foley.is_empty():
		return
	var i := _pending_foley.size() - 1
	while i >= 0:
		var e: Dictionary = _pending_foley[i]
		e["time_left"] = float(e["time_left"]) - delta
		if e["time_left"] <= 0.0:
			_pending_foley.remove_at(i)
			_fire_weapon_foley_event(e)
		else:
			_pending_foley[i] = e
		i -= 1

## Rejoue-t-on ENCORE le même rechargement (génération inchangée) et
## celui-ci est-il TOUJOURS en cours (`anim_state`) ? Sinon : silence plutôt
## qu'un son fantôme (même discipline que l'ancien BUG-K02, généralisée ici à
## TOUS les joueurs et à CHAQUE événement d'un rechargement, pas seulement au
## dernier) — arme changée, joueur mort, ou un AUTRE rechargement a démarré
## entre-temps sur cette même arme.
func _fire_weapon_foley_event(e: Dictionary) -> void:
	var id: int = e["player_id"]
	var kind := String(e["kind"])
	var session_dict := _reload_session if kind == "reload" else _inspect_session
	if int(session_dict.get(id, -1)) != int(e["session"]):
		return
	if kind == "reload" and not bool(_reload_flags.get(id, false)):
		return
	if int(_weapon_current_id.get(id, -1)) != int(e["weapon_id"]):
		return  # arme changée depuis la programmation : jamais de son fantôme sur une autre arme en main.
	var info: Dictionary = _tracked.get(id, {})
	var pc := info.get("node") as PlayerController
	if pc == null or not is_instance_valid(pc):
		return
	var sound := String(e["sound"])
	if bool(e["is_local"]):
		play_local(sound)
	else:
		var pos := pc.global_position
		var occluded: bool = _occlusion_cache.get(id, false)
		play_at(sound, pos, _listener_distance(pos), MIX_OFFSET_REMOTE_FOLEY_DB, occluded)

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
	_debug_log(name, p.volume_db)

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
	_debug_log(name, p.volume_db)
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
		# Tâche "son" (point 7) : pas sur métal (toit de conteneur, passerelle...)
		# -- surface classée par raycast sol throttlé, voir `_poll_spatial_audio`.
		var surface: String = _ground_surface_cache.get(id, SurfaceSound.CONCRETE)
		sname = SurfaceSound.footstep_sound_for(sname, surface)
		for i in mini(int(tick.steps), 2):  # évite une rafale de sons sur un gros lag spike
			if info.is_local:
				play_local(sname)
			else:
				# Marche discrète et coéquipiers en retrait (voir remote_footstep_offset_db).
				var lt := _local_team()
				var is_enemy := lt >= 0 and int(pc.team) >= 0 and int(pc.team) != lt
				var dist := _listener_distance(pc.global_position)
				var offset_db := remote_footstep_offset_db(not sname.contains("sprint"), is_enemy, dist)
				if is_inf(offset_db):
					continue
				play_at(sname, pc.global_position, dist, offset_db, _occlusion_cache.get(id, false))

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
	_set_bus_volume(BUS_MUSIC, Settings.volume_music, MIX_OFFSET_MUSIC_DB)
	_set_bus_volume(BUS_SFX, Settings.volume_sfx, MIX_OFFSET_SFX_DB)
	# UX-06 : volume UI dédié (avant cette tâche, suivait volume_sfx comme Feedback ci-dessous).
	_set_bus_volume(BUS_UI, Settings.volume_ui, MIX_OFFSET_UI_DB)
	_set_bus_volume(BUS_FEEDBACK, Settings.volume_sfx, MIX_OFFSET_FEEDBACK_DB)
	_set_bus_volume(BUS_VOICE, Settings.volume_voice)
	_set_bus_volume(BUS_AMBIENCE, Settings.volume_ambience, MIX_OFFSET_AMBIENCE_DB)
	# BUS_SHOTS n'est PAS mis à jour par _set_bus_volume : le ducking (GF-11)
	# module son volume_db en continu, donc on ne fait que rafraîchir la base
	# (+ MIX_OFFSET_SHOTS_DB, tâche "son" : "les tirs doivent dominer") et
	# laisser _apply_shots_duck réappliquer le ducking en cours par-dessus.
	_shots_base_db = linear_to_db(clampf(Settings.volume_sfx, 0.0, 1.0)) + MIX_OFFSET_SHOTS_DB
	_apply_shots_duck(duck_gain_db(_shots_duck_elapsed) if _shots_duck_elapsed >= 0.0 else 0.0)
	apply_audio_mono()

func _set_bus_volume(bus_name: String, linear: float, offset_db: float = 0.0) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)) + offset_db)
