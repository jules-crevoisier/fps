## WeaponConfig.gd
## Réglages d'une arme (hitscan / shotgun / sniper), façon Valorant : catégorie,
## coût, stats. Duplique en .tres par arme (voir resources/weapons/ + WeaponDatabase).
class_name WeaponConfig
extends Resource

## Type de tir.
enum Type { HITSCAN, SHOTGUN, SNIPER }
## Catégorie (pour la boutique / le catalogue).
enum Category { SIDEARM, SMG, RIFLE, SHOTGUN, SNIPER, HEAVY, MELEE }

@export var weapon_name: String = "Rifle"
@export var weapon_type: Type = Type.HITSCAN
@export var category: Category = Category.RIFLE
## Coût en crédits (boutique façon Valo).
@export var cost: int = 2900

@export_group("Dégâts")
## Dégâts à bout portant.
@export var damage: float = 25.0
## Dégâts au-delà de la distance max (chute de dégâts / damage falloff).
@export var damage_min: float = 12.0
## Distance (m) où les dégâts commencent à chuter.
@export var falloff_start: float = 25.0
## Distance (m) où les dégâts atteignent damage_min.
@export var falloff_end: float = 60.0
## Multiplicateur de dégâts sur un tir à la tête.
@export var headshot_mult: float = 1.5

@export_group("Tir")
## Portée max du rayon (m).
@export var max_range: float = 200.0
## Cadence (balles/seconde).
@export var fire_rate: float = 10.0
## Tir auto (maintenir) ou semi-auto (tap).
@export var automatic: bool = true
## Dispersion à la hanche (deg).
@export var spread_hip: float = 2.0
## Dispersion en visée (deg).
@export var spread_aim: float = 0.3

@export_group("Munitions")
@export var mag_size: int = 30
@export var reserve_ammo: int = 120
@export var reload_time: float = 1.8

@export_group("Visée (ADS)")
## FOV en visée (zoom). Bas = gros zoom (sniper).
@export var aim_fov: float = 55.0
## Vitesse de transition de visée.
@export var aim_speed: float = 12.0

@export_group("Shotgun")
## Nombre de plombs par tir (1 = arme normale).
@export var pellets: int = 1
## Dispersion des plombs (deg) — utilisée si pellets > 1.
@export var pellet_spread: float = 4.0

@export_group("Recul (recoil)")
## Montée verticale par tir (deg). Le recul s'accumule pendant le spray.
@export var recoil_vertical: float = 0.55
## Déviation horizontale aléatoire par tir (deg).
@export var recoil_horizontal: float = 0.35
## Vitesse de récupération (retour à zéro). Haut = revient vite.
@export var recoil_recovery: float = 7.0
## Multiplicateur de recul en visée (ADS). < 1 = plus stable en visée.
@export var recoil_aim_mult: float = 0.6

@export_group("Lunette / Scope")
## Affiche une lunette (overlay) en visée — pour les snipers.
@export var scoped: bool = false
