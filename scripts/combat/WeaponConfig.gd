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

@export_group("Recul (motif fixe)")
## Motif de recul FIXE pour les premiers tirs (façon Valorant) : chaque élément
## est un décalage en degrés (x = déviation horizontale/yaw, y = montée
## verticale/pitch) appliqué au tir correspondant. Au-delà de `pattern_shots`,
## le recul redevient pseudo-aléatoire (recoil_vertical/recoil_horizontal
## ci-dessus). Consommé par Weapon.gd (round suivant) — pur champ de données ici.
@export var recoil_pattern: PackedVector2Array = PackedVector2Array()
## Nombre de tirs couverts par `recoil_pattern` avant bascule sur le recul
## pseudo-aléatoire.
@export var pattern_shots: int = 0

@export_group("Dispersion en mouvement")
## Dispersion (deg) ajoutée à spread_hip/spread_aim quand le joueur se déplace
## (marche ou course). Les armes fines de contact bougent bien, les armes de
## précision punissent le mouvement.
@export var move_spread_add: float = 0.0
## Dispersion (deg) ajoutée quand le joueur est en l'air (saut/chute).
@export var air_spread_add: float = 0.0

@export_group("Pénalités de mouvement (temps avant tir)")
## Délai (s) avant de pouvoir tirer après un sprint.
@export var sprint_to_fire: float = 0.15
## Délai (s) avant de pouvoir tirer après une glissade (slide). Référence
## commune ≈ 0.38 s (docs/ROADMAP.md §4).
@export var slide_to_fire: float = 0.38
## Délai (s) avant de pouvoir tirer après un plongeon (dive). Référence commune
## ≈ 0.46 s (docs/ROADMAP.md §4).
@export var dive_to_fire: float = 0.46
## Durée (s) de la transition de visée (ADS) — l'arme se centre en ce temps ;
## distinct de `aim_speed` qui règle l'interpolation caméra/FOV.
@export var ads_time: float = 0.2
