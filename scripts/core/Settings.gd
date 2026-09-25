## Settings.gd
## Réglages persistants (user://settings.cfg) : remap clavier/souris ET manette,
## sensibilité souris/manette, inversion Y, FOV, mode d'affichage clavier (UX-14 :
## Auto/AZERTY/QWERTY — un LIBELLÉ seulement, les liaisons restent toujours
## physiques, voir `LAYOUT_OPTIONS`/`label_for_physical`).
## Les bindings par DÉFAUT (clavier + manette) sont dans project.godot ;
## ce fichier ne stocke que les overrides du joueur.
class_name Settings
extends RefCounted

const PATH := "user://settings.cfg"

## Ratio de référence (16:9) pour la conversion FOV horizontal -> vertical
## (UX-02, docs/research/04_ui_ux.md §2.7/§3.1 : Valorant "103° h" / Overwatch
## 2 "103° h" sont DÉFINIS à 16:9, quel que soit l'écran réel du joueur —
## `Camera3D.keep_aspect = KEEP_HEIGHT` (défaut, docs Godot Camera3D "fov"/
## "keep_aspect") applique ensuite tout seul le FOV vertical obtenu ici à
## n'importe quel autre ratio d'écran (Hor+ : les écrans plus larges gagnent
## du FOV horizontal, jamais l'inverse) — pas besoin de relire le ratio de la
## fenêtre courante.
const REF_ASPECT_16_9 := 16.0 / 9.0
## FOV horizontal par défaut (UX-02, cible docs/research/04_ui_ux.md §3.1 :
## "103° par défaut, curseur 80-120"), converti en vertical via `hfov_to_vfov`.
const DEFAULT_FOV_H := 103.0

## Actions remappables (libellé affiché dans le menu Options).
const ACTIONS := {
	"move_forward": "Avancer",
	"move_back": "Reculer",
	"move_left": "Gauche",
	"move_right": "Droite",
	"jump": "Sauter",
	"walk": "Marcher (maintien)",
	"crouch": "Accroupi / Slide",
	"dive": "Plonger",
	"fire": "Tirer",
	"aim": "Viser (ADS)",
	"reload": "Recharger",
}

## Modes d'affichage des libellés clavier (UX-14) : "auto" (détecte la
## disposition RÉELLE de l'OS à l'affichage, `DisplayServer.
## keyboard_get_label_from_physical`, défaut), "azerty" ou "qwerty" (FORCÉS,
## utiles quand l'OS ment : clavier US avec Windows en français, bureau à
## distance…). Les LIAISONS restent TOUJOURS physiques, quel que soit le mode
## (voir `label_for_physical`/`apply_layout` ci-dessous) : ce réglage ne
## change plus jamais une touche, seulement son ÉTIQUETTE affichée —
## contrairement à l'ancien préréglage `LAYOUTS` (retiré), qui réécrivait
## Avancer/Reculer/Gauche/Droite en clavier LOGIQUE et pouvait déclencher deux
## actions à la fois sur un OS AZERTY : la position physique Q (liée à
## Capacité 1 dans `project.godot`) tape la lettre « a » en AZERTY, qui
## correspondait aussi à la liaison logique de Gauche une fois le préréglage
## QWERTY forcé — voir docs/research/10_ammo_kits_input.md §4.1 Bug 2 et
## `reset_movement_bindings` plus bas, qui remplace ce mécanisme.
const LAYOUT_OPTIONS := ["auto", "azerty", "qwerty"]

## Libellés FR de la rangée de lettres quand le mode "azerty" est FORCÉ (l'OS
## n'est alors plus consulté) — couvre les positions déplacées par la
## disposition française par rapport à un clavier US QWERTY (docs/research/
## 10_ammo_kits_input.md §4.2 point 2 / §4.3).
const AZERTY_LABELS := {
	KEY_Q: "A", KEY_W: "Z", KEY_A: "Q", KEY_Z: "W",
	KEY_SEMICOLON: "M", KEY_M: ",",
}

## Table de conversion touche LOGIQUE (ancien préréglage `LAYOUTS["azerty"]`,
## écrit par `apply_layout` avant cette tâche) -> touche PHYSIQUE équivalente,
## utilisée par `migrate_logical_key_event` ci-dessous. Seules Avancer/
## Reculer/Gauche/Droite ont jamais été écrites en logique ; S et D occupent
## déjà la même position physique dans les deux dispositions.
const _AZERTY_LOGICAL_TO_PHYSICAL := {
	KEY_Z: KEY_W, KEY_Q: KEY_A, KEY_S: KEY_S, KEY_D: KEY_D,
}

## Actions de déplacement (UX-14) : les seules que l'ancien `apply_layout`
## réinitialisait — voir `reset_movement_bindings`.
const _MOVEMENT_ACTIONS := ["move_forward", "move_back", "move_left", "move_right"]

## Sensibilité souris par défaut, en rad/pixel (UX-37 — retour de playtest
## utilisateur 2026-09-25 : « la sensibilité de base est beaucoup trop
## haute »). Remplace l'ancien défaut 0.0025 rad/pixel (≈ 8 cm/360° à
## 800 DPI, bien plus rapide que la moyenne compétitive) par 0.001 rad/pixel
## (≈ 0,057°/count, ≈ 21 cm/360° à 800 DPI — proche du défaut de CS2).
## Exposé pour le curseur Options (UX-37, échelle lisible « 1.0 = ce
## défaut ») et pour `migrate_mouse_sensitivity` ci-dessous — jamais
## réinterprété ailleurs, seule cette constante fait foi.
const MOUSE_SENSITIVITY_DEFAULT := 0.001

## Ancien défaut (avant cette tâche) — utilisé UNIQUEMENT par
## `migrate_mouse_sensitivity` pour reconnaître un fichier jamais retouché
## par le joueur (voir sa doc). Ne plus utiliser ailleurs : `mouse_sensitivity`
## et `reset_kb_page` suivent désormais `MOUSE_SENSITIVITY_DEFAULT`.
const _MOUSE_SENSITIVITY_LEGACY_DEFAULT := 0.0025

static var mouse_sensitivity: float = MOUSE_SENSITIVITY_DEFAULT
static var gamepad_sensitivity: float = 3.0
static var invert_y: bool = false
## FOV HORIZONTAL en degrés, à 16:9 (UX-02 — avant cette tâche, cette valeur
## était le FOV vertical passé tel quel à `Camera3D.fov` ; les anciens
## fichiers sauvegardés sont migrés par `load_all()`, voir `migrate_fov`).
## Converti en FOV vertical pour la caméra via `hfov_to_vfov` (PlayerCamera.gd).
static var fov: float = DEFAULT_FOV_H
## Effets de FOV dynamique (sprint/slide/survitesse, PlayerCamera.gd) —
## désactivables pour le confort (mal des transports) ou la compétition
## (docs/research/04_ui_ux.md §3.1 : "effets dynamiques ... désactivables").
static var fov_effects_enabled: bool = true
static var layout: String = "auto"

## Couleur ennemi (DA v2 "Peint au soleil, encré gras", design.md §9) : 0
## Magenta (défaut), 1 Citron — remplace le rouge/jaune/magenta de v1 (ces
## teintes retombaient dans les bandes désormais réservées au monde). Citron
## est recommandé pour les joueurs protanopes/deutéranopes (design.md §9).
## Consommé par Cartoon.enemy_color().
static var enemy_color: int = 0
## Échelle d'interface (design.md, Steam Deck) : 1.0 défaut, 1.15 recommandée
## sur Steam Deck. Multiplie la taille des éléments HUD/menus qui l'exposent.
static var ui_scale: float = 1.0
## Mouvement réduit (design.md §13 "Reduced motion: fades only") : les
## contrôles animés (BrushHeader, KillWordBurst, LowHealthVignette, …) sautent
## le balayage/pop et ne gardent qu'un fondu. Lu via Comic.reduced_motion().
static var reduced_motion: bool = false
## Contours d'arête plein écran (ink_edges.gdshader / InkPost.gd) — activable
## pour le confort/perf (Steam Deck, machines modestes).
static var ink_edges: bool = true
## Volumes (0..1), consommés par Audio.gd (bus Master/SFX/Music/UI/Voix/Ambiance).
static var volume_master: float = 1.0
static var volume_sfx: float = 1.0
static var volume_music: float = 0.7
## UX-06, docs/research/04_ui_ux.md §2.7 "volumes ... voix/UI/ambiance" —
## réglages dédiés, avant cette tâche l'UI et le Feedback suivaient volume_sfx
## (Audio._apply_volumes) sans curseur séparé, et il n'existait ni bus Voix ni
## volume d'ambiance de carte distinct de la musique.
static var volume_ui: float = 1.0
static var volume_voice: float = 1.0
static var volume_ambience: float = 1.0
## Audio mono (accessibilité — un seul canal, gauche = droit à la sortie) —
## UX-06. Appliqué par Audio.apply_audio_mono via un AudioEffectStereoEnhance
## posé sur le bus Master (pan_pullout=0 downmixe en mono, doc Godot
## "AudioEffectStereoEnhance" "pan_pullout"), voir Audio.mono_pan_pullout (pure).
static var audio_mono: bool = false

# ------------------------------------------------------------------ AFFICHAGE (UX-06)
## docs/research/04_ui_ux.md §2.7 "Affichage : mode fenêtre, échelle de rendu,
## vsync, limite d'images, préréglages graphiques, luminosité."

## "windowed" (fenêtré), "borderless" (plein écran SANS exclusivité —
## `DisplayServer.WINDOW_MODE_FULLSCREEN` force `borderless=true`, doc Godot
## "DisplayServer" > WindowMode), "fullscreen" (plein écran EXCLUSIF,
## `WINDOW_MODE_EXCLUSIVE_FULLSCREEN`, recommandé par défaut pour la plupart
## des jeux — bipasse le compositeur). Défaut "windowed" : comportement moteur
## inchangé tant que le joueur ne touche pas ce réglage (`project.godot` ne
## fixe aucun `window/size/mode`, donc le défaut Godot est déjà fenêtré).
const WINDOW_MODES := ["windowed", "borderless", "fullscreen"]
static var window_mode: String = "windowed"

## Échelle du rendu 3D, 50-100 % (UX-06) — `Viewport.scaling_3d_scale` (doc
## Godot "Viewport" "scaling_3d_scale") : < 1.0 sous-échantillonne pour gagner
## en performance (Steam Deck, machines modestes). Volontairement borné à
## 1.0 au maximum : le sur-échantillonnage (> 1.0, coûteux, réservé au mode
## bilinéaire) n'est pas proposé par ce curseur.
static var render_scale: float = 1.0

## Verticale sync (UX-06) — `DisplayServer.window_set_vsync_mode`. Défaut
## `true` : comportement moteur inchangé (le mode par défaut de Godot est
## `VSYNC_ENABLED`, `project.godot` ne le redéfinit pas).
static var vsync_enabled: bool = true

## Limite d'images, 60/144/240/illimitée (UX-06) — 0 = illimitée
## (`Engine.max_fps`, défaut moteur : 0 = pas de limite, laissé au vsync).
## Visible dans PerfOverlay (scripts/core/PerfOverlay.gd, hors du périmètre de
## cette tâche — voir le rendu de tâche).
const FPS_LIMIT_OPTIONS := [0, 60, 144, 240]
static var fps_limit: int = 0

## Préréglages graphiques, dont Steam Deck (UX-06) — combinent render_scale/
## fps_limit/ink_edges/ui_scale (1.15 sur Deck, cf. `clamp_ui_scale`/
## design.md). N'est PAS relu champ par champ au chargement : appliquer un
## préréglage est une ACTION explicite (`apply_graphics_preset`, bouton
## Options) qui écrase ces 4 réglages d'un coup ; `graphics_preset` ne
## mémorise que le dernier préréglage choisi, pour l'affichage (les 4 champs
## restent ensuite modifiables individuellement sans que ce label ne change).
const GRAPHICS_PRESETS := {
	"steam_deck": {"render_scale": 0.7, "fps_limit": 60, "ink_edges": false, "ui_scale": 1.15},
	"performance": {"render_scale": 0.75, "fps_limit": 0, "ink_edges": false, "ui_scale": 1.0},
	"balanced": {"render_scale": 0.85, "fps_limit": 0, "ink_edges": true, "ui_scale": 1.0},
	"quality": {"render_scale": 1.0, "fps_limit": 0, "ink_edges": true, "ui_scale": 1.0},
}
const GRAPHICS_PRESET_DEFAULT := "quality"
static var graphics_preset: String = GRAPHICS_PRESET_DEFAULT

# ------------------------------------------------------------------ CONTRÔLES (UX-06)

## Multiplicateur de sensibilité en visée (ADS), séparé de la sensibilité au
## jugé (UX-06, docs/research/04_ui_ux.md §2.7 : "il faut un multiplicateur
## ADS séparé ... pour garder la mémoire musculaire", Aimlabs/Ubisoft R6). 1.0
## = même sensibilité qu'au jugé. Consommé par PlayerController._look/
## _gamepad_look via `PlayerController.effective_look_sensitivity` (pure —
## voir tests/core/test_settings.gd) : multiplie mouse_sensitivity/
## gamepad_sensitivity quand `player.input.aim_held` est vrai.
static var ads_sensitivity_multiplier: float = 1.0

## Maintien (true, défaut — comportement actuel inchangé) ou bascule (false)
## pour accroupi/visée (ADS)/marche (UX-06, docs/research/04_ui_ux.md §2.7 :
## "maintien ou bascule (accroupi, ADS, marche)"). Consommé par
## PlayerInput.gather_from_devices via `PlayerInput.resolve_hold_or_toggle`
## (pure — voir tests/core/test_settings.gd) : en bascule, l'action s'active
## au premier appui et se désactive au suivant, au lieu de suivre l'état brut
## de la touche (`Input.is_action_pressed`).
static var hold_to_crouch: bool = true
static var hold_to_aim: bool = true
static var hold_to_walk: bool = true

## Secousses de caméra (UX-06, docs/research/04_ui_ux.md §2.7) — désactivables
## pour le confort (mal des transports), même principe que fov_effects_enabled.
## Consommé par PlayerCamera._process : maître ON/OFF du tangage pendant le
## Stun ET de la secousse à trauma (GF-08, tir/dégât/explosion) + du punch FOV
## — voir CameraShake.effective_intensity, qui combine ce booléen avec
## `camera_shake_intensity` et `reduced_motion` en UNE intensité effective.
static var camera_shake_enabled: bool = true
## Intensité de la secousse à trauma (GF-08, CameraShake) — 0-100 % (stocké
## 0.0-1.0, comme les volumes), séparée du maître ON/OFF `camera_shake_enabled`
## ci-dessus (même relation que head_bob_enabled/head_bob_intensity). 1.0 =
## amplitude pleine (CameraShake.MAX_ANGLE_DEG à trauma = 1). Combinée avec
## `camera_shake_enabled` et `reduced_motion` par CameraShake.effective_intensity,
## jamais lue directement par CameraShake (classe pure, sans accès à Settings).
static var camera_shake_intensity: float = 1.0

## Balancement de tête (head-bob), activable/désactivable et son intensité —
## 0 = aucun, 1 = défaut (MovementConfig.bob_amplitude tel quel), 2 = maximum
## (UX-06). Consommé par PlayerCamera._update_bob.
static var head_bob_enabled: bool = true
static var head_bob_intensity: float = 1.0

## Affiche en permanence l'overlay FPS/réseau (UX-06, docs/research/04_ui_ux.md
## §2.7 "afficher FPS et réseau") — sans ce réglage, PerfOverlay ne s'affiche
## qu'au F3 manuel. CONSOMMÉ PAR scripts/core/PerfOverlay.gd (hors du périmètre
## de cette tâche — voir le rendu de tâche).
static var show_perf_overlay: bool = false

# ------------------------------------------------------------------ VISEUR (UX-03)
## Réglages du réticule (couleur, contour, point central, lignes intérieures/
## extérieures, écart, opacité — docs/research/04_ui_ux.md §2.2), TOUJOURS
## normalisé (Crosshair.normalize_settings — voir Crosshair.gd) : `{}` avant
## le premier `load_all()` normalise à `Crosshair.DEFAULT_SETTINGS` (aucune
## clé manquante n'y est jamais interprétée comme une erreur, voir la doc de
## `Crosshair.normalize_settings`), jamais lu/écrit ailleurs que via
## `Crosshair.apply_settings`/CrosshairEditor.gd.
static var crosshair_settings: Dictionary = {}
## Réticule statique (option héritée de GF-09, câblée par cette tâche — voir
## la doc de tête de Crosshair.gd) : ignore la dispersion réelle de l'arme,
## réticule purement cosmétique.
static var static_crosshair: bool = false

static var _loaded: bool = false

static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		apply_ui_scale()  # premier lancement : pas de fichier, mais l'échelle par défaut doit quand même s'appliquer à la fenêtre (BUG-13)
		apply_window_mode()  # idem (UX-06) : les défauts d'affichage doivent s'appliquer même sans fichier
		apply_render_scale()
		apply_vsync()
		apply_fps_limit()
		return  # on garde les autres défauts de project.godot
	# UX-37 : un fichier qui porte EXACTEMENT l'ancien défaut (jamais retouché
	# par le joueur, voir `migrate_mouse_sensitivity`) passe au nouveau défaut,
	# plus bas — toute autre valeur (choisie par le joueur) est conservée telle
	# quelle, simplement bornée (même garde BUG-14 qu'avant cette tâche).
	mouse_sensitivity = migrate_mouse_sensitivity(float(cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)))
	gamepad_sensitivity = clamp_gamepad_sensitivity(float(cfg.get_value("input", "gamepad_sensitivity", gamepad_sensitivity)))
	invert_y = bool(cfg.get_value("input", "invert_y", invert_y))
	# `fov_unit_version` n'existe que dans les fichiers sauvegardés APRÈS UX-02
	# (FOV horizontal) — son absence signale un fichier d'avant cette tâche, où
	# la valeur stockée était le FOV VERTICAL (défaut 90°) : elle ne veut plus
	# rien dire dans le nouveau système horizontal (90° vertical ne redevient
	# PAS "90° horizontal"), donc on ne la réinterprète jamais — voir
	# `migrate_fov`, même principe que `migrate_enemy_color` ci-dessus.
	var has_fov_h_key := cfg.has_section_key("video", "fov_unit_version")
	var stored_fov := float(cfg.get_value("video", "fov", fov))
	fov = migrate_fov(stored_fov, has_fov_h_key)
	fov_effects_enabled = bool(cfg.get_value("video", "fov_effects_enabled", fov_effects_enabled))
	# UX-14 : la valeur BRUTE sauvegardée sert à savoir comment migrer les
	# éventuelles liaisons LOGIQUES ci-dessous (voir `migrate_logical_key_event`)
	# AVANT d'être elle-même migrée (`migrate_layout` — un "qwerty" sauvegardé
	# ne prouve rien sur le clavier réel du joueur, contrairement à "azerty",
	# un vrai choix explicite, conservé tel quel).
	var stored_layout := str(cfg.get_value("input", "layout", layout))
	var was_azerty_save := stored_layout == "azerty"
	layout = migrate_layout(stored_layout)
	# `enemy_palette_version` n'existe que dans les fichiers sauvegardés APRÈS
	# le passage à la DA v2 (0 Magenta/1 Citron) — son absence signale un
	# fichier v1 (0 rouge/1 jaune/2 violet), dont la valeur numérique ne veut
	# plus rien dire dans la nouvelle palette : on force 0 (Magenta, défaut)
	# plutôt que de réinterpréter silencieusement 1 (jaune v1) en 1 (Citron
	# v2) — voir `migrate_enemy_color`.
	var has_v2_key := cfg.has_section_key("render", "enemy_palette_version")
	var stored_enemy_color := int(cfg.get_value("render", "enemy_color", enemy_color))
	enemy_color = migrate_enemy_color(stored_enemy_color, has_v2_key)
	ui_scale = clamp_ui_scale(float(cfg.get_value("video", "ui_scale", ui_scale)))
	reduced_motion = bool(cfg.get_value("accessibility", "reduced_motion", reduced_motion))
	ink_edges = bool(cfg.get_value("render", "ink_edges", ink_edges))
	volume_master = clamp_volume(float(cfg.get_value("audio", "volume_master", volume_master)))
	volume_sfx = clamp_volume(float(cfg.get_value("audio", "volume_sfx", volume_sfx)))
	volume_music = clamp_volume(float(cfg.get_value("audio", "volume_music", volume_music)))
	volume_ui = clamp_volume(float(cfg.get_value("audio", "volume_ui", volume_ui)))
	volume_voice = clamp_volume(float(cfg.get_value("audio", "volume_voice", volume_voice)))
	volume_ambience = clamp_volume(float(cfg.get_value("audio", "volume_ambience", volume_ambience)))
	audio_mono = bool(cfg.get_value("audio", "audio_mono", audio_mono))
	window_mode = clamp_window_mode(str(cfg.get_value("video", "window_mode", window_mode)))
	render_scale = clamp_render_scale(float(cfg.get_value("video", "render_scale", render_scale)))
	vsync_enabled = bool(cfg.get_value("video", "vsync_enabled", vsync_enabled))
	fps_limit = clamp_fps_limit(int(cfg.get_value("video", "fps_limit", fps_limit)))
	graphics_preset = clamp_graphics_preset(str(cfg.get_value("video", "graphics_preset", graphics_preset)))
	ads_sensitivity_multiplier = clamp_ads_sensitivity_multiplier(
		float(cfg.get_value("input", "ads_sensitivity_multiplier", ads_sensitivity_multiplier)))
	hold_to_crouch = bool(cfg.get_value("input", "hold_to_crouch", hold_to_crouch))
	hold_to_aim = bool(cfg.get_value("input", "hold_to_aim", hold_to_aim))
	hold_to_walk = bool(cfg.get_value("input", "hold_to_walk", hold_to_walk))
	camera_shake_enabled = bool(cfg.get_value("camera", "camera_shake_enabled", camera_shake_enabled))
	camera_shake_intensity = clamp_camera_shake_intensity(
		float(cfg.get_value("camera", "camera_shake_intensity", camera_shake_intensity)))
	head_bob_enabled = bool(cfg.get_value("camera", "head_bob_enabled", head_bob_enabled))
	head_bob_intensity = clamp_head_bob_intensity(
		float(cfg.get_value("camera", "head_bob_intensity", head_bob_intensity)))
	show_perf_overlay = bool(cfg.get_value("debug", "show_perf_overlay", show_perf_overlay))
	# UX-03 : le réticule est persisté comme le MÊME code texte que
	# l'import/export de CrosshairEditor.gd (Crosshair.encode/decode) — un
	# fichier d'avant cette tâche (clé absente, `get_value` retombe sur "")
	# décode vers `Crosshair.DEFAULT_SETTINGS` (voir Crosshair.decode).
	crosshair_settings = Crosshair.decode(str(cfg.get_value("video", "crosshair_code", "")))
	static_crosshair = bool(cfg.get_value("video", "static_crosshair", static_crosshair))
	for action in ACTIONS:
		var dk = cfg.get_value("binds_kb", action, null)
		if dk is Dictionary:
			var ev := _dict_to_event(dk)
			if ev is InputEventKey:
				# UX-14 : une liaison sauvegardée avant cette tâche pouvait être
				# LOGIQUE (`keycode` seul, écrit par l'ancien `apply_layout`) —
				# on la convertit en équivalent PHYSIQUE, sans quoi elle
				# risquerait de doubler une autre action (voir Bug 2, note de
				# `LAYOUT_OPTIONS`).
				ev = migrate_logical_key_event(ev, was_azerty_save)
			if ev:
				_replace_keyboard_event(action, ev)
		var dp = cfg.get_value("binds_pad", action, null)
		if dp is Dictionary:
			var evp := _dict_to_event(dp)
			if evp:
				_replace_joy_event(action, evp)
	apply_ui_scale()
	apply_window_mode()
	apply_render_scale()
	apply_vsync()
	apply_fps_limit()

static func save_all() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("input", "gamepad_sensitivity", gamepad_sensitivity)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("input", "layout", layout)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "fov_unit_version", 2)
	cfg.set_value("video", "fov_effects_enabled", fov_effects_enabled)
	cfg.set_value("video", "ui_scale", ui_scale)
	cfg.set_value("accessibility", "reduced_motion", reduced_motion)
	cfg.set_value("render", "enemy_color", enemy_color)
	cfg.set_value("render", "enemy_palette_version", 2)
	cfg.set_value("render", "ink_edges", ink_edges)
	cfg.set_value("audio", "volume_master", volume_master)
	cfg.set_value("audio", "volume_sfx", volume_sfx)
	cfg.set_value("audio", "volume_music", volume_music)
	cfg.set_value("audio", "volume_ui", volume_ui)
	cfg.set_value("audio", "volume_voice", volume_voice)
	cfg.set_value("audio", "volume_ambience", volume_ambience)
	cfg.set_value("audio", "audio_mono", audio_mono)
	cfg.set_value("video", "window_mode", window_mode)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "vsync_enabled", vsync_enabled)
	cfg.set_value("video", "fps_limit", fps_limit)
	cfg.set_value("video", "graphics_preset", graphics_preset)
	cfg.set_value("input", "ads_sensitivity_multiplier", ads_sensitivity_multiplier)
	cfg.set_value("input", "hold_to_crouch", hold_to_crouch)
	cfg.set_value("input", "hold_to_aim", hold_to_aim)
	cfg.set_value("input", "hold_to_walk", hold_to_walk)
	cfg.set_value("camera", "camera_shake_enabled", camera_shake_enabled)
	cfg.set_value("camera", "camera_shake_intensity", camera_shake_intensity)
	cfg.set_value("camera", "head_bob_enabled", head_bob_enabled)
	cfg.set_value("camera", "head_bob_intensity", head_bob_intensity)
	cfg.set_value("debug", "show_perf_overlay", show_perf_overlay)
	cfg.set_value("video", "crosshair_code", Crosshair.encode(crosshair_settings))
	cfg.set_value("video", "static_crosshair", static_crosshair)
	for action in ACTIONS:
		var kb := _first_key_or_mouse(action)
		if kb:
			cfg.set_value("binds_kb", action, _event_to_dict(kb))
		var pad := _first_joy(action)
		if pad:
			cfg.set_value("binds_pad", action, _event_to_dict(pad))
	cfg.save(PATH)

## Borne un index de couleur ennemi (0 Magenta, 1 Citron — DA v2, design.md
## §9). Fonction pure isolée pour rester testable sans dépendre du garde `_loaded`.
static func clamp_enemy_color(v: int) -> int:
	return clampi(v, 0, 1)

## Migration v1 -> v2 (design.md, "Next" : Settings.enemy_color Magenta 0,
## Citron 1) : un fichier de settings SANS la clé `enemy_palette_version`
## vient d'avant la DA v2 — sa valeur numérique (0 rouge/1 jaune/2 violet)
## n'a plus de sens dans la nouvelle palette (2 devient hors-bornes, et 1
## jaune se réinterpréterait à tort en 1 Citron). On la force donc à 0
## (Magenta, défaut) plutôt que de la réinterpréter silencieusement. Un
## fichier déjà v2 (`has_v2_key` vrai) garde sa valeur, simplement bornée.
static func migrate_enemy_color(stored: int, has_v2_key: bool) -> int:
	if not has_v2_key:
		return 0
	return clamp_enemy_color(stored)

## Borne l'échelle d'interface (design.md, Steam Deck : 1.0 défaut, 1.15
## recommandée). Fonction pure isolée pour rester testable sans dépendre du
## garde `_loaded`.
static func clamp_ui_scale(v: float) -> float:
	return clampf(v, 0.8, 1.5)

## Borne un volume (Master/SFX/Musique) à [0, 1]. Fonction pure isolée pour
## rester testable sans dépendre du garde `_loaded`.
static func clamp_volume(v: float) -> float:
	return clampf(v, 0.0, 1.0)

## Borne le mode fenêtre (UX-06) à une valeur connue de `WINDOW_MODES` — un
## fichier corrompu ou d'une version future retombe sur "windowed" plutôt que
## de mémoriser une chaîne que `apply_window_mode` ne saurait pas traduire.
static func clamp_window_mode(v: String) -> String:
	return v if WINDOW_MODES.has(v) else "windowed"

## Borne l'échelle de rendu 3D à 50-100 % (UX-06 — curseur Options).
static func clamp_render_scale(v: float) -> float:
	return clampf(v, 0.5, 1.0)

## Borne la limite d'images à l'un des paliers proposés (UX-06 : 60/144/240/
## illimitée) — toute autre valeur (fichier corrompu) retombe sur illimitée (0).
static func clamp_fps_limit(v: int) -> int:
	return v if FPS_LIMIT_OPTIONS.has(v) else 0

## Borne le préréglage graphique à un nom connu de `GRAPHICS_PRESETS` (UX-06).
static func clamp_graphics_preset(v: String) -> String:
	return v if GRAPHICS_PRESETS.has(v) else GRAPHICS_PRESET_DEFAULT

## Borne le mode d'affichage clavier (UX-14) à une valeur connue de
## `LAYOUT_OPTIONS` — un fichier corrompu ou d'une version future retombe sur
## "auto" (détection à l'affichage) plutôt que de mémoriser une chaîne muette.
## Fonction pure isolée pour rester testable sans dépendre du garde `_loaded`.
static func clamp_layout(v: String) -> String:
	return v if LAYOUT_OPTIONS.has(v) else "auto"

## Migration du réglage `layout` (UX-14) : avant cette tâche, "qwerty" était à
## la fois le défaut ET la valeur FORCÉE par `reset_kb_page()` — un fichier
## qui la porte ne prouve donc rien sur le clavier réel du joueur, contrairement
## à "azerty", un choix explicite qu'on conserve tel quel. On ramène "qwerty"
## à "auto" (détection à l'affichage) plutôt que de le garder comme un faux
## signal. Fonction pure isolée, testable sans fichier réel.
static func migrate_layout(stored: String) -> String:
	if stored == "qwerty":
		return "auto"
	return clamp_layout(stored)

## Borne le multiplicateur de sensibilité ADS (UX-06) — filet de sécurité
## large (0.3-2.0) autour du défaut 1.0, même principe que
## `clamp_mouse_sensitivity`/`clamp_gamepad_sensitivity` (BUG-14).
static func clamp_ads_sensitivity_multiplier(v: float) -> float:
	return clampf(v, 0.3, 2.0)

## Borne l'intensité du head-bob (UX-06) — 0 (aucun) à 2 (maximum), 1 = défaut.
static func clamp_head_bob_intensity(v: float) -> float:
	return clampf(v, 0.0, 2.0)

## Borne l'intensité de la secousse de caméra à trauma (GF-08, CameraShake) —
## 0 (aucune) à 1 (pleine, 100 %), 1 = défaut. Contrairement à
## `clamp_head_bob_intensity`, jamais > 1 : la secousse GF-08 n'a pas de mode
## « exagéré », uniquement un curseur de confort 0-100 %.
static func clamp_camera_shake_intensity(v: float) -> float:
	return clampf(v, 0.0, 1.0)

## Borne la sensibilité souris (BUG-14 : un fichier corrompu ne doit plus
## rendre la souris morte/inversée). Même plage que le slider Options
## (OptionsMenu._build_kb : 0.0005..0.01). Fonction pure isolée pour rester
## testable sans dépendre du garde `_loaded`.
static func clamp_mouse_sensitivity(v: float) -> float:
	return clampf(v, 0.0005, 0.01)

## Migration UX-37 (nouveau défaut souris, retour de playtest 2026-09-25 :
## « la sensibilité de base est beaucoup trop haute ») : une valeur sauvegardée
## qui vaut EXACTEMENT l'ancien défaut `_MOUSE_SENSITIVITY_LEGACY_DEFAULT`
## (0.0025) n'a jamais été retouchée par le joueur — rien dans le fichier ne
## distingue « jamais touché » d'un choix délibéré de 0.0025, donc on retombe
## sur le nouveau défaut plutôt que de figer un joueur sur l'ancienne valeur
## jugée trop rapide. Toute AUTRE valeur (0.0018, etc.) est un réglage
## explicite du joueur : conservée telle quelle, simplement bornée (BUG-14).
## Fonction pure isolée, testable sans fichier réel (même principe que
## `migrate_fov`/`migrate_enemy_color`/`migrate_layout` ci-dessus).
static func migrate_mouse_sensitivity(stored: float) -> float:
	if is_equal_approx(stored, _MOUSE_SENSITIVITY_LEGACY_DEFAULT):
		return MOUSE_SENSITIVITY_DEFAULT
	return clamp_mouse_sensitivity(stored)

## Borne la sensibilité manette (BUG-14). Même plage que le slider Options
## (OptionsMenu._build_pad : 0.5..8.0). Fonction pure isolée pour rester
## testable sans dépendre du garde `_loaded`.
static func clamp_gamepad_sensitivity(v: float) -> float:
	return clampf(v, 0.5, 8.0)

## Borne le champ de vision HORIZONTAL en degrés (BUG-14 : un FOV aberrant
## chargé depuis un fichier corrompu casse le rendu). Filet de sécurité large
## et distinct du curseur affiché dans Options (OptionsMenu._build_kb :
## 80..120, UX-02) — reste 70..120 pour ne pas resserrer silencieusement une
## valeur déjà validée par un fichier de settings existant. Fonction pure
## isolée pour rester testable sans dépendre du garde `_loaded`.
static func clamp_fov(v: float) -> float:
	return clampf(v, 70.0, 120.0)

## Convertit un FOV HORIZONTAL (degrés) en FOV VERTICAL (degrés) pour un
## ratio d'écran donné (largeur/hauteur) — relation standard de projection
## perspective (UX-02, docs/research/04_ui_ux.md §2.7/§3.1 ; formule reprise
## de la définition Valorant/Overwatch "103° h à 16:9") :
##   tan(vfov / 2) = tan(hfov / 2) / aspect
## `hfov_to_vfov(103, 16/9)` ≈ 70,53° (± 0,1° acceptés, PlayerCamera.gd au
## lancement). Fonction pure : aucun accès scène, testable isolément.
static func hfov_to_vfov(hfov_deg: float, aspect: float) -> float:
	var half_h := deg_to_rad(hfov_deg) * 0.5
	return rad_to_deg(2.0 * atan(tan(half_h) / aspect))

## Migration du FOV v1 (vertical, défaut 90°) -> v2 (horizontal, défaut 103°,
## UX-02) : un fichier SANS la clé `fov_unit_version` vient d'avant cette
## tâche, où le nombre stocké était un FOV VERTICAL — le réinterpréter comme
## horizontal donnerait un champ de vision complètement différent de celui
## que le joueur avait réglé (ex. 90° vertical ≠ 90° horizontal), donc on
## revient au défaut v2 plutôt que de le convertir silencieusement, même
## principe que `migrate_enemy_color`. Un fichier déjà v2 (`has_h_key` vrai)
## garde sa valeur, simplement bornée. Fonction pure isolée pour rester
## testable sans dépendre du garde `_loaded`.
static func migrate_fov(stored: float, has_h_key: bool) -> float:
	if not has_h_key:
		return DEFAULT_FOV_H
	return clamp_fov(stored)

## Applique `ui_scale` à la fenêtre courante (BUG-13). `Window.content_scale_factor`
## est, d'après la doc Godot 4.7 (rendering/multiple_resolutions.html), la
## propriété à modifier pour un changement d'échelle UI dynamique en cours de
## partie — contrairement à `gui/theme/default_theme_scale`, qui n'est lu
## qu'au démarrage. Appelée par `load_all()` (démarrage) et par le menu
## Options (en direct). Sans boucle de scène (tests headless sans arbre), ne
## fait rien plutôt que de planter.
static func apply_ui_scale() -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		(loop as SceneTree).root.content_scale_factor = ui_scale

## Applique `window_mode` à la fenêtre courante (UX-06). `DisplayServer` existe
## toujours (y compris en tête headless, où il ne fait rien) : pas de garde
## SceneTree nécessaire ici, contrairement à `apply_ui_scale`/`apply_render_scale`
## qui touchent une propriété portée par `SceneTree.root`.
static func apply_window_mode() -> void:
	match window_mode:
		"windowed":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

## Applique `render_scale` au viewport principal (UX-06, doc Godot "Viewport"
## "scaling_3d_scale"). Sans boucle de scène (tests headless sans arbre), ne
## fait rien plutôt que de planter — même garde que `apply_ui_scale`.
static func apply_render_scale() -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		(loop as SceneTree).root.scaling_3d_scale = render_scale

## Applique `vsync_enabled` à la fenêtre courante (UX-06).
static func apply_vsync() -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)

## Applique `fps_limit` (UX-06) — `Engine.max_fps`, 0 = illimité (défaut moteur).
static func apply_fps_limit() -> void:
	Engine.max_fps = fps_limit

## Applique un préréglage graphique (UX-06, dont Steam Deck) : écrase
## render_scale/fps_limit/ink_edges/ui_scale d'un coup, applique chacun tout de
## suite (sans redémarrage) et sauvegarde. Un nom inconnu retombe sur
## `GRAPHICS_PRESET_DEFAULT` (voir `clamp_graphics_preset`).
static func apply_graphics_preset(name: String) -> void:
	graphics_preset = clamp_graphics_preset(name)
	var p: Dictionary = GRAPHICS_PRESETS[graphics_preset]
	render_scale = clamp_render_scale(float(p.render_scale))
	fps_limit = clamp_fps_limit(int(p.fps_limit))
	ink_edges = bool(p.ink_edges)
	ui_scale = clamp_ui_scale(float(p.ui_scale))
	apply_render_scale()
	apply_fps_limit()
	apply_ui_scale()
	save_all()

## Choisit le mode d'affichage des libellés clavier (UX-14, "auto"/"azerty"/
## "qwerty") — NE TOUCHE PLUS AUCUNE liaison (voir la note sur `LAYOUT_OPTIONS`
## plus haut) : seule `layout` change, persistée. `OptionsMenu._set_layout`
## rafraîchit ensuite les libellés affichés (les touches restent les mêmes).
static func apply_layout(name: String) -> void:
	layout = clamp_layout(name)
	save_all()

## Libellé affiché pour une touche PHYSIQUE, selon `layout` (UX-14) :
## - "azerty"/"qwerty" : mode FORCÉ, ignore l'OS (utile quand celui-ci ment —
##   clavier US avec Windows en français, bureau à distance…) via
##   `AZERTY_LABELS`/le libellé US brut.
## - "auto" (défaut) : lit la disposition RÉELLE de l'OS, comme avant cette
##   tâche (`DisplayServer.keyboard_get_label_from_physical`). En tête
##   headless (tests, CI — pas de vrai clavier), ce DisplayServer ne sait rien
##   traduire : on retombe sur le libellé US brut plutôt que de l'appeler
##   (même précaution que `scripts/training/KeyLabel.gd`, hors de ce lot).
## La rangée de chiffres n'est JAMAIS retraduite (elle reste "1".."0", jamais
## "&"/"é"/"\"" en France) : un joueur FR presse la même touche physique quel
## que soit le mode. Fonction pure sur la touche + `layout` (statique, comme
## le reste de ce fichier), testable pour les 3 modes.
static func label_for_physical(pk: Key) -> String:
	if pk >= KEY_0 and pk <= KEY_9:
		return OS.get_keycode_string(pk)
	match layout:
		"azerty":
			return AZERTY_LABELS.get(pk, OS.get_keycode_string(pk))
		"qwerty":
			return OS.get_keycode_string(pk)
	if DisplayServer.get_name() == "headless":
		return OS.get_keycode_string(pk)
	var lbl := DisplayServer.keyboard_get_label_from_physical(pk)
	return OS.get_keycode_string(lbl if lbl != KEY_NONE else pk)

## Convertit un événement clavier LOGIQUE, sauvegardé par l'ancien
## `apply_layout` (avant cette tâche, voir `LAYOUT_OPTIONS`), en son équivalent
## PHYSIQUE (UX-14, docs/research/10_ammo_kits_input.md §4.2 point 4). Un
## événement déjà physique (`physical_keycode != 0`) ou sans keycode logique
## ressort inchangé : rien à migrer. `was_azerty_save` vient de la valeur
## BRUTE de `layout` LUE dans le fichier, avant sa propre migration (voir
## `migrate_layout` / `load_all`) : sous l'ancien préréglage "qwerty", keycode
## et physical_keycode partagent déjà la même valeur numérique (W/A/S/D) —
## identité ; sous "azerty", `_AZERTY_LOGICAL_TO_PHYSICAL` fait la conversion.
## Fonction pure isolée, testable sans fichier réel.
static func migrate_logical_key_event(ev: InputEventKey, was_azerty_save: bool) -> InputEventKey:
	if ev == null or ev.keycode == 0 or ev.physical_keycode != 0:
		return ev
	var physical: Key = ev.keycode
	if was_azerty_save:
		physical = _AZERTY_LOGICAL_TO_PHYSICAL.get(ev.keycode, ev.keycode) as Key
	var migrated := InputEventKey.new()
	migrated.physical_keycode = physical
	migrated.keycode = 0
	return migrated

## Détecte un clavier français (UX-14, docs/research/10_ammo_kits_input.md
## §4.2 point 8) — sert uniquement à afficher « Auto (AZERTY détecté) » dans
## Options (le mode "auto" adapte de toute façon déjà les libellés tout seul,
## voir `label_for_physical` ci-dessus) : aucun vrai clavier n'existe en tête
## headless (tests, CI), où l'on retombe sur `false` plutôt que d'appeler un
## DisplayServer muet.
static func detected_fr_keyboard() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var lang := DisplayServer.keyboard_get_layout_language(DisplayServer.keyboard_get_current_layout())
	return lang.begins_with("fr")

## Remet les 4 touches de déplacement à leur défaut PHYSIQUE de
## `project.godot` (UX-14) — remplace l'ancien `apply_layout("qwerty")` de
## `reset_kb_page`, qui écrivait un clavier LOGIQUE et pouvait déclencher deux
## actions à la fois sur un OS AZERTY (voir Bug 2, note de `LAYOUT_OPTIONS`).
## `ProjectSettings` reste la SOURCE, jamais réécrite par le jeu : un remap
## individuel (`set_binding`) ou un ancien fichier corrompu peuvent donc
## toujours y revenir. Fonction séparée de `reset_kb_page` pour rester
## testable isolément.
static func reset_movement_bindings() -> void:
	for action in _MOVEMENT_ACTIONS:
		var default_cfg: Dictionary = ProjectSettings.get_setting("input/%s" % action, {})
		for e in default_cfg.get("events", []):
			if e is InputEventKey:
				_replace_keyboard_event(action, e)
				break

## Remappe une action (clavier, souris ou manette — remplace le même type).
static func set_binding(action: String, event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_replace_joy_event(action, event)
	else:
		_replace_keyboard_event(action, event)
	save_all()

# ------------------------------------------------------------ RÉINITIALISATION PAR PAGE (UX-06)
# « Réinitialiser » ne remet les valeurs par défaut QUE de la page affichée
# (acceptance UX-06) — jamais les autres pages. Les touches remappées
# individuellement restent HORS de ce périmètre (elles ne sont pas un
# "réglage" au sens curseur/case à cocher de ces pages), à l'exception des 4
# touches de déplacement sur la page Clavier/Souris, remises à leur défaut
# PHYSIQUE par `reset_movement_bindings` (UX-14 — jamais tir/visée/
# rechargement/etc.) : un `InputMap.load_from_project_settings()` global
# remettrait AUSSI les boutons manette de la page Manette à zéro, ce qui
# violerait "la page seulement".

## Page "Clavier / Souris" : sensibilité souris, FOV + effets, sensibilité
## ADS, maintien/bascule, mode d'affichage clavier (remis à "auto" — UX-14 :
## "réinitialiser" ne force plus jamais QWERTY, voir `LAYOUT_OPTIONS`) et les 4
## touches de déplacement, remises à leur défaut PHYSIQUE via
## `reset_movement_bindings` (et non plus rebranchées en logique).
static func reset_kb_page() -> void:
	mouse_sensitivity = MOUSE_SENSITIVITY_DEFAULT
	fov = DEFAULT_FOV_H
	fov_effects_enabled = true
	ads_sensitivity_multiplier = 1.0
	hold_to_crouch = true
	hold_to_aim = true
	hold_to_walk = true
	layout = "auto"
	reset_movement_bindings()
	save_all()

## Page "Manette" : sensibilité, inversion Y. Les boutons remappés
## individuellement restent inchangés (voir note ci-dessus).
static func reset_pad_page() -> void:
	gamepad_sensitivity = 3.0
	invert_y = false
	save_all()

## Page "Affichage & Son" : affichage (mode/échelle/vsync/limite/préréglage),
## contours d'arête, tous les volumes, audio mono, overlay FPS/réseau.
static func reset_render_page() -> void:
	window_mode = "windowed"
	render_scale = 1.0
	vsync_enabled = true
	fps_limit = 0
	graphics_preset = GRAPHICS_PRESET_DEFAULT
	ink_edges = true
	volume_master = 1.0
	volume_sfx = 1.0
	volume_music = 0.7
	volume_ui = 1.0
	volume_voice = 1.0
	volume_ambience = 1.0
	audio_mono = false
	show_perf_overlay = false
	apply_window_mode()
	apply_render_scale()
	apply_vsync()
	apply_fps_limit()
	save_all()

## Page "Accessibilité" : couleur ennemi, échelle d'interface, mouvement
## réduit, secousses de caméra, head-bob.
static func reset_access_page() -> void:
	enemy_color = 0
	ui_scale = 1.0
	reduced_motion = false
	camera_shake_enabled = true
	camera_shake_intensity = 1.0
	head_bob_enabled = true
	head_bob_intensity = 1.0
	apply_ui_scale()
	save_all()

# ------------------------------------------------------------------ AFFICHAGE
static func binding_text(action: String) -> String:
	var ev := _first_key_or_mouse(action)
	return event_text(ev) if ev else "—"

static func gamepad_text(action: String) -> String:
	var ev := _first_joy(action)
	return event_text(ev) if ev else "—"

static func event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		# Touche logique (keycode) : libellé direct. Ne subsiste normalement
		# que pour un événement pas encore migré (voir `migrate_logical_key_event`) —
		# toute liaison SAUVEGARDÉE passe désormais par `load_all`, qui migre.
		if ev.keycode != 0:
			return OS.get_keycode_string(ev.keycode)
		# Touche PHYSIQUE (le cas normal, UX-14) : le libellé suit `layout`
		# (Auto/AZERTY/QWERTY — Z/Q/S/D en AZERTY, W/A/S/D en QWERTY…), tout en
		# gardant un binding physique pour que ça marche quelle que soit la
		# disposition réelle du clavier.
		return label_for_physical(ev.physical_keycode)
	if ev is InputEventMouseButton:
		match ev.button_index:
			MOUSE_BUTTON_LEFT: return "Clic gauche"
			MOUSE_BUTTON_RIGHT: return "Clic droit"
			MOUSE_BUTTON_MIDDLE: return "Clic milieu"
			_: return "Souris %d" % ev.button_index
	if ev is InputEventJoypadButton:
		return _joy_button_name(ev.button_index)
	if ev is InputEventJoypadMotion:
		return _joy_axis_name(ev.axis, ev.axis_value)
	return "?"

static func _joy_button_name(idx: int) -> String:
	match idx:
		JOY_BUTTON_A: return "A / Croix"
		JOY_BUTTON_B: return "B / Cercle"
		JOY_BUTTON_X: return "X / Carré"
		JOY_BUTTON_Y: return "Y / Triangle"
		JOY_BUTTON_BACK: return "Select"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_LEFT_STICK: return "L3"
		JOY_BUTTON_RIGHT_STICK: return "R3"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_DPAD_UP: return "D-Pad ↑"
		JOY_BUTTON_DPAD_DOWN: return "D-Pad ↓"
		JOY_BUTTON_DPAD_LEFT: return "D-Pad ←"
		JOY_BUTTON_DPAD_RIGHT: return "D-Pad →"
		_: return "Bouton %d" % idx

static func _joy_axis_name(axis: int, value: float) -> String:
	match axis:
		JOY_AXIS_TRIGGER_LEFT: return "LT"
		JOY_AXIS_TRIGGER_RIGHT: return "RT"
		JOY_AXIS_LEFT_X: return "Stick G %s" % ("→" if value > 0 else "←")
		JOY_AXIS_LEFT_Y: return "Stick G %s" % ("↓" if value > 0 else "↑")
		JOY_AXIS_RIGHT_X: return "Stick D %s" % ("→" if value > 0 else "←")
		JOY_AXIS_RIGHT_Y: return "Stick D %s" % ("↓" if value > 0 else "↑")
		_: return "Axe %d" % axis

# ------------------------------------------------------------------ HELPERS
static func _first_key_or_mouse(action: String) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			return e
	return null

static func _first_joy(action: String) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			return e
	return null

static func _replace_keyboard_event(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			InputMap.action_erase_event(action, e)
	InputMap.action_add_event(action, event)

static func _replace_joy_event(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			InputMap.action_erase_event(action, e)
	InputMap.action_add_event(action, event)

static func _event_to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {"type": "key", "physical": int(ev.physical_keycode), "keycode": int(ev.keycode)}
	if ev is InputEventMouseButton:
		return {"type": "mouse", "button": int(ev.button_index)}
	if ev is InputEventJoypadButton:
		return {"type": "joyb", "button": int(ev.button_index)}
	if ev is InputEventJoypadMotion:
		return {"type": "joym", "axis": int(ev.axis), "value": float(ev.axis_value)}
	return {}

static func _dict_to_event(d: Dictionary) -> InputEvent:
	match d.get("type", ""):
		"key":
			var e := InputEventKey.new()
			e.physical_keycode = int(d.get("physical", d.get("code", 0))) as Key
			e.keycode = int(d.get("keycode", 0)) as Key
			return e
		"mouse":
			var e := InputEventMouseButton.new()
			e.button_index = int(d.get("button", 1)) as MouseButton
			return e
		"joyb":
			var e := InputEventJoypadButton.new()
			e.button_index = int(d.get("button", 0)) as JoyButton
			return e
		"joym":
			var e := InputEventJoypadMotion.new()
			e.axis = int(d.get("axis", 0)) as JoyAxis
			e.axis_value = float(d.get("value", 1.0))
			return e
	return null
