## WeaponConfig.gd
## Réglages d'une arme (hitscan / shotgun / sniper), façon Valorant : catégorie,
## coût, stats. Duplique en .tres par arme (voir resources/weapons/ + WeaponDatabase).
class_name WeaponConfig
extends Resource

## Type de tir.
enum Type { HITSCAN, SHOTGUN, SNIPER }
## Catégorie (pour la boutique / le catalogue). PISTOL ajoutée en fin de liste
## (tâche "revolver", 2026-09-27) : jamais réordonnée avant MELEE, pour ne pas
## décaler les valeurs entières déjà écrites dans resources/weapons/*.tres
## (`category = 2` pour le Ravage doit rester RIFLE).
enum Category { SIDEARM, SMG, RIFLE, SHOTGUN, SNIPER, HEAVY, MELEE, PISTOL }

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
## Réserve « manche » : valeur historique des .tres, utilisée par les modes à
## manches (Litige/Duel — `Inventory.RULE_ROUND`, docs/research/
## 10_ammo_kits_input.md §2.2) et par tout appelant qui ne précise pas de
## règle de munitions. Rechargée à chaque manche (RoundMode), jamais en cours
## de manche : ne pas confondre avec `arena_reserve_ammo` ci-dessous.
@export var reserve_ammo: int = 120
## Réserve « arène » (Mêlée/Borne — `Inventory.RULE_ARENA`, §2.3) : ×5
## chargeurs par rapport à `reserve_ammo`, sauf la Semeuse (déjà 300, valeur
## inchangée) et le Faucheur (×4, sniper à un coup). Plus généreuse que la
## réserve de manche car une vie d'arène doit tenir plusieurs affrontements
## sans repasser par la boutique (contrairement à une manche du Litige,
## rechargée à chaque round).
@export var arena_reserve_ammo: int = 120
@export var reload_time: float = 1.8

@export_group("Visée (ADS)")
## FOV en visée (zoom). Bas = gros zoom (sniper).
@export var aim_fov: float = 55.0
## Vitesse de transition de visée.
@export var aim_speed: float = 12.0

@export_group("Shotgun")
## Nombre de plombs par tir (1 = arme normale).
@export var pellets: int = 1
## Dispersion des plombs (deg) — utilisée si pellets > 1 (cône à la HANCHE).
@export var pellet_spread: float = 4.0
## Dispersion des plombs (deg) EN VISÉE (ADS) — tâche "quatre armes"
## (2026-09-28, Fracas) : un fusil à pompe vise aussi plus serré qu'à la
## hanche. `-1.0` (défaut) = pas de valeur dédiée, retombe sur `pellet_spread`
## pour la hanche ET la visée (comportement HISTORIQUE inchangé — aucune arme
## du catalogue n'utilisait `pellets > 1` en jeu avant cette tâche). Seul point
## de lecture : `WeaponFeel.pellet_cone_deg`.
@export var pellet_spread_aim: float = -1.0

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

## Comportement du clic DROIT (RMB) — pivot "Valorant Classic" (design
## verrouillé utilisateur, 2026-09-27, révisé après playtest) :
##  - NONE (défaut) : RMB vise (ADS classique — zoom, blend FPP_ADS_In,
##    ralentissement au déplacement) — comportement HISTORIQUE inchangé pour
##    toute arme existante (ex. le Ravage).
##  - FAN : RMB déclenche le tir "fan the hammer" (voir `fan_fire_rate` ci-
##    dessous) — RMB ne vise JAMAIS pour cette arme (aucun zoom, aucun blend
##    ADS, aucun ralentissement — voir PlayerInput.weapon_aims_on_right_click,
##    seul point de lecture de ce champ : chaque consommateur d'`aim_held`
##    hérite automatiquement de la bonne règle sans être modifié un par un).
## Générique par conception ("so future weapons can reuse it") : un futur type
## de clic droit ajouterait une 3e valeur ici, jamais un bool dédié de plus.
enum AltFireMode { NONE, FAN }
@export_group("Clic droit (RMB)")
@export var alt_fire_mode: AltFireMode = AltFireMode.NONE

@export_group("Fan the hammer (tâche revolver, révisé 2026-09-27)")
## Cadence (balles/seconde) du tir "fan the hammer" — déclenché par RMB TENU
## (`alt_fire_mode == FAN`), jamais par LMB (voir Weapon.gd/FanFireClock.gd) :
## "Holding LMB does NOT fan anymore; it fires nothing more until release."
## `0.0` (défaut) désactive complètement le mode fan même si `alt_fire_mode`
## valait FAN par erreur — l'arme se comporte alors comme une arme normale
## (RMB ne fait rien de spécial, `automatic`/`fire_rate` seuls bornent LMB).
@export var fan_fire_rate: float = 0.0
## Dispersion (deg) AJOUTÉE (jamais remplacée) à `spread_hip` pendant un tir
## fan. En pratique TOUJOURS la branche hanche : une arme `alt_fire_mode ==
## FAN` ne vise jamais (voir la doc d'`alt_fire_mode`), `fan_spread_add_aim`
## ci-dessous ne s'applique donc à aucune arme du jeu actuel — gardé pour
## qu'une arme FUTURE puisse un jour combiner ADS (via une 3e voie) et fan.
@export var fan_spread_add_hip: float = 0.0
## Dispersion (deg) AJOUTÉE à `spread_aim` pendant un tir fan (visée/ADS) —
## voir la note ci-dessus (inutilisée tant qu'aucune arme ne vise ET ne fanne).
@export var fan_spread_add_aim: float = 0.0
## Multiplicateur du recul VERTICAL pendant un tir fan (>= 1.0 : le fan
## secoue plus que le tap) — même convention que `WeaponFeel.recoil_for_shot`
## (`recoil_mult`, ne touche jamais la déviation horizontale aléatoire).
@export var fan_recoil_mult: float = 1.0

## Vrai si RMB doit se comporter comme une visée (ADS) pour CETTE arme — voir
## la doc d'`alt_fire_mode`. Fonction PURE (aucun accès à l'arbre de scène),
## seul point de vérité lu par PlayerInput.weapon_aims_on_right_click.
func aims_on_right_click() -> bool:
	return alt_fire_mode == AltFireMode.NONE

## Vrai si RMB doit fanner pour CETTE arme (`alt_fire_mode == FAN` ET une
## cadence fan réellement configurée > 0 — un `fan_fire_rate` resté à 0 par
## erreur désactive le mode sans qu'il faille aussi remettre `alt_fire_mode` à
## NONE). Seul point de vérité lu par Weapon.gd (client ET serveur).
func has_fan_fire() -> bool:
	return alt_fire_mode == AltFireMode.FAN and fan_fire_rate > 0.0

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
## Dispersion (deg) ajoutée à spread_hip/spread_aim quand le joueur se déplace,
## de façon CONTINUE selon sa vitesse (façon Valorant, MV-02) : voir
## WeaponFeel.move_spread_deg (0 sous `move_spread_deadzone`, plein à la
## vitesse de sprint, via smoothstep — plus de tout-ou-rien booléen). Les armes
## fines de contact bougent bien, les armes de précision punissent le mouvement.
@export var move_spread_add: float = 0.0
## Fraction de la vitesse de sprint (0-1) sous laquelle bouger n'ajoute AUCUNE
## dispersion (zone morte façon Valorant : marcher lentement reste précis).
@export_range(0.0, 1.0) var move_spread_deadzone: float = 0.3
## Multiplicateur appliqué à la dispersion de mouvement pendant une glissade
## (slide) : le corps est instable, la pénalité est majorée.
@export var slide_spread_mult: float = 1.3
## Dispersion (deg) ajoutée quand le joueur est en l'air (saut/chute).
@export var air_spread_add: float = 0.0

@export_group("Pénalités de mouvement (temps avant tir)")
## Délai (s) avant de pouvoir tirer après une glissade (slide). Référence
## commune ≈ 0.38 s (docs/ROADMAP.md §4).
@export var slide_to_fire: float = 0.38
## Délai (s) avant de pouvoir tirer après un plongeon (dive). Référence commune
## ≈ 0.46 s (docs/ROADMAP.md §4).
@export var dive_to_fire: float = 0.46
## Durée (s) de la transition de visée (ADS) — l'arme se centre en ce temps ;
## distinct de `aim_speed` qui règle l'interpolation caméra/FOV.
@export var ads_time: float = 0.2

@export_group("Cycle d'action (pompe/levier/verrou)")
## Délai (s) OBLIGATOIRE après un tir avant de pouvoir tirer OU recharger à
## nouveau (tâche "quatre armes", 2026-09-28 : pompe/levier/verrou) — voir
## Inventory.cycle_left/consume_round. `0.0` (défaut) désactive complètement
## ce mécanisme : comportement HISTORIQUE inchangé pour toute arme existante
## (Ravage/Revolver), seuls `fire_rate`/`automatic` bornent alors la cadence.
## "Not interruptible except by weapon switch" (contrat, arme à pompe) : rien
## (tir, rechargement) ne peut s'exécuter tant que ce délai n'est pas écoulé,
## sauf changer d'arme (`Weapon._try_equip` -> `Inventory.equip`, qui remet ce
## délai à zéro pour l'arme quittée — voir aussi `set_loadout`/`give`/
## `replace_current`/`remove_current`, mêmes raisons).
@export var cycle_time: float = 0.0

@export_group("Rechargement par cartouche (pompe/levier)")
## Rechargement PAR CARTOUCHE/BALLE plutôt qu'en un seul bloc (pompe/levier,
## tâche "quatre armes") : une seule munition ajoutée au chargeur à la fois,
## IMMÉDIATEMENT utilisable (voir Inventory._tick_per_round) — contrairement
## au rechargement en bloc (`reload_time` ci-dessus, comportement HISTORIQUE
## inchangé, ex. Ravage/Revolver/tout sniper qui recharge le chargeur entier
## d'un coup). Faux par défaut (aucun effet, `reload_time` seul régit alors le
## rechargement).
@export var reload_per_round: bool = false
## Délai (s) avant que la PREMIÈRE cartouche/balle ne soit insérée (début du
## geste : pompe tirée en arrière, culasse ouverte...) — ignoré si
## `reload_per_round` est faux.
@export var reload_start_time: float = 0.3
## Délai (s) entre deux cartouches/balles insérées — ignoré si
## `reload_per_round` est faux.
@export var reload_round_time: float = 0.45
