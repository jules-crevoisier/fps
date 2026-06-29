## MovementConfig.gd
## Ressource centralisant TOUS les paramètres de mouvement.
## Crée des variantes (.tres) pour tester différents "feels" sans toucher au code.
## Inspiré du modèle accélération/friction de Source (air-strafe) + slide cancel façon Apex/CoD.
class_name MovementConfig
extends Resource

@export_group("Vitesses (m/s)")
## Vitesse de marche de base.
@export var walk_speed: float = 6.0
## Vitesse en sprint.
@export var sprint_speed: float = 9.5
## Vitesse max accroupi.
@export var crouch_speed: float = 3.0
## Vitesse en l'air visée (faible : on garde l'inertie, on ne "pousse" pas fort).
@export var air_speed: float = 1.2

@export_group("Accélération / Friction")
## Accélération au sol (plus haut = réponse plus sèche).
@export var ground_accel: float = 90.0
## Friction au sol quand on relâche les touches (décélération).
@export var ground_friction: float = 60.0
## Accélération en l'air (clé du air-strafe fluide : laisser bas).
@export var air_accel: float = 28.0
## Friction en l'air (≈0 pour conserver le momentum).
@export var air_friction: float = 0.0

@export_group("Saut")
@export var jump_velocity: float = 6.2
## Gravité (m/s²). Négatif appliqué en interne.
@export var gravity: float = 20.0
## Gravité multipliée à la descente (saut plus "punchy").
@export var fall_gravity_mult: float = 1.45
## Fenêtre coyote (s) : saut autorisé juste après avoir quitté le sol.
@export var coyote_time: float = 0.12
## Buffer de saut (s) : saut mémorisé si pressé juste avant d'atterrir.
@export var jump_buffer_time: float = 0.12
## Conserve la vitesse horizontale au décollage (bunny-hop friendly).
@export var preserve_momentum_on_jump: bool = true

@export_group("Slide")
## Vitesse minimale pour déclencher un slide.
@export var slide_min_speed: float = 6.5
## Boost de vitesse injecté au début du slide.
@export var slide_boost: float = 4.0
## Vitesse max atteignable par un slide.
@export var slide_max_speed: float = 16.0
## Friction pendant le slide (faible = on glisse longtemps).
@export var slide_friction: float = 4.5
## Durée max d'un slide (s) avant de repasser en crouch.
@export var slide_max_time: float = 1.1
## Accélération bonus dans les descentes pendant le slide.
@export var slide_slope_accel: float = 18.0
## Contrôle directionnel autorisé pendant le slide (0 = aucun, 1 = total).
@export_range(0.0, 1.0) var slide_steer: float = 0.25

@export_group("Slide Cancel")
## Active la mécanique de slide cancel (chaîner les slides pour garder la vitesse).
@export var slide_cancel_enabled: bool = true
## Fenêtre (s) après le début du slide pendant laquelle un cancel garde tout le momentum.
@export var slide_cancel_window: float = 0.45
## Cooldown entre deux slides. 0 = chaînage libre (mouvement très permissif).
@export var slide_cooldown: float = 0.0
## Fraction de vitesse conservée lors d'un cancel propre (1.0 = tout gardé).
@export_range(0.0, 1.0) var slide_cancel_keep: float = 1.0

@export_group("Crouch")
## Hauteur debout de la collision.
@export var stand_height: float = 1.8
## Hauteur accroupi de la collision.
@export var crouch_height: float = 0.9
## Vitesse de transition de hauteur (lerp).
@export var crouch_lerp_speed: float = 12.0

@export_group("Caméra")
## Sensibilité souris.
@export var mouse_sensitivity: float = 0.0025
## FOV de base.
@export var base_fov: float = 90.0
## FOV ajouté au sprint.
@export var sprint_fov_add: float = 8.0
## FOV ajouté au slide.
@export var slide_fov_add: float = 14.0
## Vitesse d'interpolation du FOV.
@export var fov_lerp_speed: float = 8.0
## Inclinaison (deg) de la caméra en strafe.
@export var strafe_tilt: float = 1.6
## Vitesse d'interpolation du tilt.
@export var tilt_lerp_speed: float = 9.0
## Amplitude du head-bob.
@export var bob_amplitude: float = 0.045
## Fréquence du head-bob.
@export var bob_frequency: float = 9.0
