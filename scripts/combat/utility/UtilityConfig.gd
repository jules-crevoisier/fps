## UtilityConfig.gd
## Réglages d'un objet lancé (grenade à fragmentation / flashbang / fumigène),
## façon WeaponConfig.gd : UNE classe, une ressource .tres PAR TYPE (voir
## resources/utility/frag.tres, flash.tres, smoke.tres + UtilityDatabase.gd).
## Champs communs (vol/rebond) + groupes spécifiques par type — un type donné
## n'utilise que son propre groupe, les autres restent à leur valeur par
## défaut sans effet (mêmes conventions que WeaponConfig avec pellets/scoped/
## etc. qui ne s'appliquent qu'à certaines armes).
class_name UtilityConfig
extends Resource

enum Kind { FRAG, FLASH, SMOKE }

@export var utility_name: String = "Frag"
@export var kind: Kind = Kind.FRAG

@export_group("Lancer")
## Vitesse initiale (m/s) donnée par UtilityThrower le long du regard.
@export var throw_speed: float = 18.0
## Facteur appliqué à `throw_speed` pour le lancer COURT (clic droit, contrat
## lead 2026-09-27 "short throw on RIGHT click") — même vitesse de base que le
## lancer long, juste ralentie et redirigée vers le haut (voir
## UtilityThrower.throw_velocity) pour un lob sous-main proche plutôt qu'un jet
## tendu au loin.
@export var short_throw_speed_factor: float = 0.42
## Rayon (m) de la sphère de collision utilisée par l'intégrateur — décale le
## point de rebond de la surface touchée pour éviter que le mesh ne s'y enfonce.
@export var collision_radius: float = 0.05

@export_group("Intégrateur (rebond)")
## Restitution du rebond (~0.35, contrat lead) : fraction de la vitesse NORMALE
## conservée après un rebond (0 = colle au mur, 1 = rebond parfait).
@export_range(0.0, 1.0) var restitution: float = 0.35
## Fraction de la vitesse TANGENTIELLE perdue à chaque rebond (frottement).
@export_range(0.0, 1.0) var friction: float = 0.35
## Vitesse (m/s) sous laquelle l'objet est considéré immobile après un rebond.
@export var rest_speed: float = 0.4

@export_group("Amorce")
## Durée (s) de l'amorce. Frag : depuis le retrait de la goupille (touche
## enfoncée). Flash/Smoke : depuis le relâchement (voir `fuse_starts_on_release`).
@export var fuse_time: float = 2.5
## Frag uniquement : l'amorce démarre au premier appui (peut "cuire" dans la
## main) plutôt qu'au relâchement.
@export var fuse_starts_on_press: bool = true

@export_group("Frag — dégâts")
## Dégâts au centre de l'explosion.
@export var frag_damage: float = 130.0
## Rayon (m) au-delà duquel les dégâts tombent à 0 (chute linéaire).
@export var frag_damage_radius: float = 6.5

@export_group("Flash — éblouissement")
## Rayon (m) dans lequel une cible avec ligne de vue est affectée.
@export var flash_radius: float = 20.0
## Durée (s) d'éblouissement plein écran si la cible fait FACE au flash (dot > 0.5).
@export var flash_facing_seconds: float = 2.2
## Durée (s) si la cible est de PROFIL (dot entre -0.5 et 0.5).
@export var flash_side_seconds: float = 1.0
## Durée (s) si la cible tourne le DOS au flash (dot < -0.5).
@export var flash_behind_seconds: float = 0.35

@export_group("Smoke — nuage")
## Rayon (m) final du nuage, atteint après `smoke_grow_seconds`.
@export var smoke_radius: float = 4.5
## Durée (s) de croissance du nuage depuis la détonation.
@export var smoke_grow_seconds: float = 1.0
## Durée (s) pendant laquelle le nuage reste à pleine taille.
@export var smoke_hold_seconds: float = 12.0
## Durée (s) de dissipation finale.
@export var smoke_fade_seconds: float = 1.5
## Détonation anticipée si le fumigène touche le sol après au moins ce délai
## écoulé depuis le relâchement (sinon détonation à `fuse_time`).
@export var smoke_ground_arm_seconds: float = 0.8
