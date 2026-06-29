## MovementConfig.gd
## Ressource centralisant TOUS les paramètres de mouvement.
## Feeling visé : CALL OF DUTY: MODERN WARFARE 2019.
##  - sol NERVEUX et ancré : démarrage/arrêt secs (modèle move_toward),
##  - contrôle aérien LIMITÉ (pas de flottement façon Apex/Source),
##  - slide court et contrôlable + SLIDE-CANCEL rapide,
##  - momentum conservé au saut/slide-jump.
## Duplique en .tres pour tester différents feels sans toucher au code.
class_name MovementConfig
extends Resource

@export_group("Vitesses (m/s)")
## Vitesse sans sprint.
@export var walk_speed: float = 5.2
## Vitesse de sprint.
@export var sprint_speed: float = 8.2
## Vitesse max accroupi.
@export var crouch_speed: float = 3.2

@export_group("Réactivité sol (CoD-like)")
## Accélération au sol en m/s^2 (HAUT = démarrage instantané, très réactif).
@export var ground_accel: float = 85.0
## Décélération au sol en m/s^2 (HAUT = arrêt net quand on relâche).
@export var ground_friction: float = 75.0

@export_group("Contrôle aérien (modèle CS / Valorant)")
## Accélération aérienne (modèle Source). HAUT = atteint vite la vitesse souhaitée.
@export var air_accel: float = 100.0
## "Vitesse souhaitée" en l'air (m/s) : paramètre du air-strafe (gain de vitesse).
## Bas (~1.0-1.6) = strafe façon CS/Valo (tourner la souris en strafant gagne
## de la vitesse). C'est ce qui permet de GAGNER de la vitesse en l'air.
@export var air_wishspeed: float = 1.6
## Contrôle directionnel DIRECT en l'air (m/s²) : permet de FREINER et de
## RÉORIENTER sa trajectoire — force ressentie dans toutes les directions, y
## compris à l'opposé du saut. N'ajoute PAS de vitesse (ça, c'est le strafe).
@export var air_control: float = 25.0

@export_group("Saut")
@export var jump_velocity: float = 7.2
## Gravité (m/s²). Appliquée négativement en interne.
@export var gravity: float = 19.0
## Gravité multipliée à la descente (saut plus "punchy", moins flottant).
@export var fall_gravity_mult: float = 1.25
## Fenêtre coyote (s).
@export var coyote_time: float = 0.08
## Buffer de saut (s).
@export var jump_buffer_time: float = 0.1

@export_group("Slide")
## Vitesse minimale pour déclencher un slide (au-dessus de la marche, donc
## un tap de crouch en marche = s'accroupir, en sprint = slide).
@export var slide_min_speed: float = 6.5
## Boost de vitesse au début du slide.
@export var slide_boost: float = 3.5
## Vitesse max atteignable en slide.
@export var slide_max_speed: float = 12.0
## Décélération du slide (taux exponentiel : ~1 = perd la moitié de sa vitesse
## en ~0.7s). BAS = slide long et glissant, HAUT = slide court.
@export var slide_friction: float = 1.2
## Durée max d'un slide (s).
@export var slide_max_time: float = 1.0
## Accélération en descente pendant le slide (m/s^2).
@export var slide_slope_accel: float = 16.0
## Contrôle directionnel pendant le slide (0 = aucun, 1 = total).
@export_range(0.0, 1.0) var slide_steer: float = 0.18

@export_group("Slide-Cancel / Slide-Jump")
## Slide-cancel : re-tapper crouch (ou sauter) annule le slide en gardant la
## vitesse, pour repartir vite (mécanique signature de MW2019).
@export var slide_cancel_enabled: bool = true
## Fraction de vitesse gardée lors d'un cancel/slide-jump (1 = tout).
@export_range(0.0, 1.0) var slide_keep: float = 1.0
## Petit pop vertical ajouté au slide-jump.
@export var slide_jump_pop: float = 0.4
## Atterrir crouch maintenu relance un slide en gardant la vitesse.
@export var slide_hop_enabled: bool = true
## Cap de vitesse en enchaînant les slides.
@export var chain_speed_cap: float = 12.0

@export_group("Dive / Roulade (dolphin dive)")
## Active la plongée (touche "dive", V par défaut).
@export var dive_enabled: bool = true
## Vitesse horizontale de la plongée (nettement > sprint => saut plus LONG).
@export var dive_speed: float = 13.0
## Pop vertical de la plongée (> jump_velocity => saut plus HAUT qu'un saut sprint).
@export var dive_jump: float = 8.0
## Frein horizontal pendant la plongée (0 = on garde toute la distance).
@export var dive_air_drag: float = 0.0
## Durée de la roulade à l'atterrissage (s) = durée du spin caméra.
@export var roll_duration: float = 0.65
## Décélération pendant la roulade (taux exponentiel). Bas = on garde de l'élan.
@export var roll_friction: float = 3.0
## Nombre de tours complets de la caméra pendant la roulade (effet machine à laver).
@export var roll_spins: float = 1.0
## Fenêtre de timing (s) pour la roulade d'atterrissage, sur une chute LENTE.
## Petit = plus technique, grand = plus permissif.
@export var land_roll_window: float = 0.3
## Fenêtre élargie pour les chutes RAPIDES (= hautes) : plus facile à timer
## quand on tombe vite. La fenêtre s'interpole entre les deux selon la vitesse.
@export var land_roll_window_max: float = 0.85
## Vitesse de chute (m/s) à partir de laquelle la fenêtre est maximale.
@export var land_roll_fast_speed: float = 20.0

@export_group("Stun de chute (cartoon, pas de dégâts)")
## Active le stun à l'atterrissage d'une chute trop haute.
@export var stun_enabled: bool = true
## En dessous de cette hauteur de chute (m), aucun stun.
@export var fall_min_height: float = 4.0
## Hauteur de chute (m) à partir de laquelle le stun est maximal.
@export var fall_max_height: float = 14.0
## Durée mini d'un stun quand il se déclenche (s).
@export var stun_min_time: float = 0.5
## Durée maxi du stun (s).
@export var stun_max_time: float = 2.5

@export_group("Crouch")
@export var stand_height: float = 1.8
@export var crouch_height: float = 0.9
@export var crouch_lerp_speed: float = 16.0

@export_group("Caméra")
## Sensibilité souris.
@export var mouse_sensitivity: float = 0.0025
## FOV de base.
@export var base_fov: float = 90.0
## FOV ajouté au sprint.
@export var sprint_fov_add: float = 5.0
## FOV ajouté au slide.
@export var slide_fov_add: float = 9.0
## FOV bonus max lié à la survitesse.
@export var speed_fov_add: float = 6.0
## Vitesse d'interpolation du FOV.
@export var fov_lerp_speed: float = 10.0
## Inclinaison (deg) de la caméra en strafe. 0 = désactivé (par défaut).
@export var strafe_tilt: float = 0.0
## Inclinaison (deg) supplémentaire pendant le slide. 0 = désactivé.
@export var slide_tilt: float = 0.0
## Vitesse d'interpolation du tilt.
@export var tilt_lerp_speed: float = 10.0
## Amplitude du head-bob (0 = désactivé).
@export var bob_amplitude: float = 0.025
## Fréquence du head-bob.
@export var bob_frequency: float = 9.0
