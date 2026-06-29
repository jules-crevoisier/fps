## MovementConfig.gd
## Ressource centralisant TOUS les paramètres de mouvement.
## Modèle inspiré d'APEX LEGENDS (en un peu plus fluide) :
##  - slide qui PREND de la vitesse en descente,
##  - slide-jump qui conserve tout le momentum,
##  - slide-hop : re-slide à l'atterrissage en gardant la vitesse,
##  - air control généreux pour rediriger sa course en l'air.
## Crée des variantes (.tres) pour tester différents "feels" sans toucher au code.
class_name MovementConfig
extends Resource

@export_group("Vitesses (m/s)")
## Vitesse sans sprint (déplacement lent, arme lourde, etc.).
@export var walk_speed: float = 4.2
## Vitesse de course (locomotion principale, comme le sprint tactique d'Apex).
@export var sprint_speed: float = 7.0
## Vitesse max accroupi (immobile/lent).
@export var crouch_speed: float = 2.8
## Cap d'accélération à l'air (faible : style Source, on REDIRIGE plus qu'on pousse).
@export var air_speed: float = 1.4

@export_group("Accélération / Friction")
## Accélération au sol (haut = réponse sèche et nerveuse).
@export var ground_accel: float = 110.0
## Friction au sol quand on relâche (décélération).
@export var ground_friction: float = 7.5
## Accélération en l'air (gain de vitesse en strafe, style Source).
@export var air_accel: float = 55.0
## Friction en l'air (0 = on garde tout le momentum).
@export var air_friction: float = 0.0

@export_group("Air Control (fluidité)")
## Vitesse de redirection du vecteur vitesse vers la direction visée, en l'air.
## C'est LA valeur "fluide" : plus haut = on tourne sa trajectoire vite,
## façon tap-strafe d'Apex. 0 = pas de redirection (air strafe pur).
@export var air_control: float = 9.0
## Active une redirection renforcée sur une nouvelle pression de touche (tap-strafe-like).
@export var tap_strafe_enabled: bool = true
## Multiplicateur d'air control lors d'un tap directionnel frais.
@export var tap_strafe_boost: float = 2.6

@export_group("Saut")
@export var jump_velocity: float = 6.0
## Gravité (m/s²). Appliquée négativement en interne.
@export var gravity: float = 22.0
## Gravité multipliée à la descente (saut plus "punchy").
@export var fall_gravity_mult: float = 1.3
## Fenêtre coyote (s) : saut autorisé juste après avoir quitté le sol.
@export var coyote_time: float = 0.1
## Buffer de saut (s) : saut mémorisé si pressé juste avant d'atterrir.
@export var jump_buffer_time: float = 0.12

@export_group("Slide")
## Vitesse minimale pour déclencher un slide.
@export var slide_min_speed: float = 4.5
## Petit boost injecté au début du slide (modeste, comme sur du plat dans Apex).
@export var slide_boost: float = 2.5
## Vitesse max atteignable en slide (sur pente raide).
@export var slide_max_speed: float = 15.0
## Friction pendant le slide (faible = on glisse longtemps).
@export var slide_friction: float = 3.0
## Durée max d'un slide (s) sur du plat avant de repasser en crouch.
@export var slide_max_time: float = 1.5
## Accélération en descente : c'est là qu'on GAGNE de la vitesse (cœur d'Apex).
@export var slide_slope_accel: float = 24.0
## Contrôle directionnel autorisé pendant le slide (0 = aucun, 1 = total).
@export_range(0.0, 1.0) var slide_steer: float = 0.32

@export_group("Slide-Jump / Slide-Hop")
## Fraction de vitesse horizontale conservée en sautant depuis un slide (1 = tout).
@export_range(0.0, 1.0) var slide_jump_keep: float = 1.0
## Atterrir crouch maintenu => re-slide direct en gardant le momentum (slide-hop).
@export var slide_hop_enabled: bool = true
## Cap de vitesse quand on enchaîne les slides (évite l'accélération infinie).
@export var chain_speed_cap: float = 15.0
## Bonus de vitesse vertical ajouté au saut quand on slide-jump (petit pop).
@export var slide_jump_pop: float = 0.6

@export_group("Crouch")
## Hauteur debout de la collision.
@export var stand_height: float = 1.8
## Hauteur accroup