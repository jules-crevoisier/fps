# Système de mouvement — Documentation de référence

Ce document décrit **toutes** les mécaniques de mouvement du jeu, leur
fonctionnement interne et les paramètres pour les régler. Le feeling visé mêle :

- **sol** nerveux et ancré façon *Call of Duty: Modern Warfare 2019* ;
- **air** technique façon *CS / Valorant* (air-strafe) + un contrôle direct pour freiner/réorienter ;
- des mécaniques signatures : **slide / slide-cancel / slide-jump**, **dolphin dive + roulade**, et un **stun de chute cartoon** (pas de dégâts).

Tous les réglages vivent dans une ressource unique :
`resources/movement/default_movement.tres` (script `scripts/movement/MovementConfig.gd`).
Duplique-la pour créer des variantes de feeling sans toucher au code.

---

## 1. Architecture

Le joueur est un `CharacterBody3D` (`scripts/player/PlayerController.gd`) qui
contient l'état physique partagé et les **helpers** de mouvement. La **logique**
de chaque mode vit dans une *state machine* (`scripts/player/states/`), où chaque
état est un `Node` enfant nommé.

```
PlayerController (CharacterBody3D)
├── helpers : ground_move, accelerate, air_control_move, apply_friction,
│             apply_gravity, do_jump, redirect_velocity…
├── suivi : coyote time, jump buffer, roll buffer, hauteur de chute
└── StateMachine
    ├── Idle    — immobile au sol
    ├── Walk    — marche lente (Shift)
    ├── Sprint  — course (par défaut)
    ├── Crouch  — accroupi (maintien)
	├── Air     — en l'air (air-strafe CS + contrôle direct)
	├── Slide   — glissade (+ cancel / jump)
	├── Dive    — plongée dolphin dive
	├── Roll    — roulade d'atterrissage (galipette caméra)
    └── Stun    — étourdissement cartoon (étoiles)
```

Boucle physique (`_physics_process`) : lire les entrées → mettre à jour les
timers → `state.physics_update()` → appliquer la hauteur de crouch →
`move_and_slide()` → vérifier le stun de chute.

Seul le pair **propriétaire** (multijoueur) simule les entrées ; les autres
joueurs sont répliqués via le `MultiplayerSynchronizer`.

---

## 2. Contrôles

| Action | Clavier* | Manette (Xbox) |
|--------|----------|----------------|
| Déplacement | W / A / S / D | Stick gauche |
| Visée | Souris | Stick droit |
| Sauter | Espace | A |
| Marche lente (sinon **sprint auto**) | Shift (maintenu) | L3 |
| Accroupi / Slide | Ctrl (maintien) | B |
| Dive / Landing-roll | V | LB |
| Tirer / Viser (ADS) | Clic G / Clic D | RT / LT |
| Recharger | R | X |
| Pause | Échap | Start |

\* Les touches sont en **position physique** (donc ZQSD sur AZERTY), et leur
**libellé s'adapte à la disposition système** (DisplayServer). Tout est
remappable dans Options (clavier + manette), + switch AZERTY/QWERTY. Détails :
[`docs/CONTROLS.md`](CONTROLS.md).

---

## 3. Déplacement au sol (MW2019)

Modèle **`ground_move()`** : la vitesse horizontale est tirée directement vers
`direction × vitesse_visée` avec `move_toward` (linéaire). Résultat : démarrage
**instantané** et arrêt **net**, sans glisse — la nervosité CoD.

- **Sprint automatique** : dès que tu bouges, tu cours à `sprint_speed`.
- **Marche** : maintenir Shift réduit à `walk_speed`.
- **Crouch (maintien)** : tenir Ctrl = accroupi (`crouch_speed`) ; relâcher relève
  (si le plafond est dégagé — `CeilingCheck`). Jamais bloqué.

| Paramètre | Déf. | Rôle |
|-----------|------|------|
| `walk_speed` | 5.2 | Vitesse marche (Shift). |
| `sprint_speed` | 8.2 | Vitesse course (défaut). |
| `crouch_speed` | 3.2 | Vitesse accroupi. |
| `ground_accel` | 85 | Accélération sol (haut = sec). |
| `ground_friction` | 75 | Décélération sol (haut = arrêt net). |

---

## 4. Saut

`do_jump()` fixe la vitesse verticale et **conserve toujours** le momentum
horizontal. Confort de saut :

- **Coyote time** : sauter reste valable un court instant après avoir quitté le sol.
- **Jump buffer** : un saut pressé juste avant l'atterrissage est mémorisé et
  exécuté au contact.
- **Fall gravity** : gravité plus forte à la descente → sauts moins flottants.

| Paramètre | Déf. | Rôle |
|-----------|------|------|
| `jump_velocity` | 7.2 | Hauteur du saut. |
| `gravity` | 19 | Gravité de base (bas = flottant). |
| `fall_gravity_mult` | 1.25 | Multiplicateur de gravité à la descente. |
| `coyote_time` | 0.08 | Fenêtre coyote (s). |
| `jump_buffer_time` | 0.1 | Fenêtre du buffer de saut (s). |

---

## 5. Contrôle aérien (CS / Valorant)

Deux systèmes combinés dans l'état `Air` :

1. **Air-strafe (modèle Source)** — `accelerate(wish_dir, air_wishspeed, air_accel)`.
   On n'ajoute de la vitesse que jusqu'à une petite « vitesse souhaitée »
   (`air_wishspeed`) dans la direction visée. Tenir avant ne fait presque rien ;
   en **tournant la souris tout en strafant**, on redresse et on **gagne** de la
   vitesse (air-strafe / surf de CS). Le momentum est conservé (pas de friction).

2. **Contrôle direct** — `air_control_move(air_control)`. Permet de **freiner**
   et de **réorienter** la trajectoire dans toutes les directions (y compris à
   l'opposé du saut). Il ne **crée pas** de vitesse (toute hausse est ramenée à
   la vitesse d'entrée) : seul l'air-strafe ci-dessus en fournit.

| Paramètre | Déf. | Rôle |
|-----------|------|------|
| `air_accel` | 100 | Accélération de l'air-strafe (atteinte du cap). |
| `air_wishspeed` | 1.6 | « Vitesse souhaitée » air. Bas = technique (CS/Valo). |
| `air_control` | 25 | Force du contrôle direct (frein / réorientation). |

---

## 6. Slide

Déclenché par un **tap de Ctrl en courant** (vitesse ≥ `slide_min_speed`).
Un boost initial, puis décélération ; dans une **pente descendante** le slide
**accélère** (`slide_slope_accel`). Steer limité pour infléchir la trajectoire.

Contrôle simple (une seule touche, sans conflit) :

- **Slide-cancel** : **relâcher Ctrl** pendant le slide → on se relève en gardant
  l'élan (`slide_keep`). Tenir Ctrl jusqu'au bout → on finit accroupi (relâcher
  relève ensuite).
- **Slide-jump** : sauter pendant le slide conserve le momentum + un petit pop
  vertical (`slide_jump_pop`).
- **Slide-hop** : atterrir en gardant Ctrl enfoncé relance un slide en gardant la
  vitesse → enchaînements sprint → slide → saut → slide.

| Paramètre | Déf. | Rôle |
|-----------|------|------|
| `slide_min_speed` | 6.5 | Vitesse mini pour slider (au-dessus de la marche). |
| `slide_boost` | 3.5 | Boost à l'entrée du slide. |
| `slide_max_speed` | 12 | Vitesse max en slide. |
| `slide_friction` | 1.2 | Décélération (exponentielle). Bas = glisse longtemps. |
| `slide_max_time` | 1.0 | Durée max d'un slide (s). |
| `slide_slope_accel` | 16 | Accélération en descente. |
| `slide_steer` | 0.18 | Contrôle directionnel pendant le slide (0–1). |
| `slide_cancel_enabled` | true | Active le slide-cancel. |
| `slide_keep` | 1.0 | Fraction de vitesse gardée au cancel / slide-jump. |
| `slide_jump_pop` | 0.4 | Pop vertical du slide-jump. |
| `slide_hop_enabled` | true | Re-slide à l'atterrissage si Ctrl maintenu. |
| `chain_speed_cap` | 12 | Cap de vitesse en enchaînant les slides. |

---

## 7. Dolphin dive + roulade

**Dive** (touche V au sol) : plongée dans la direction de la caméra, plus **haute**
et plus **longue** qu'un saut sprint (avantage de mobilité), au prix d'une
**roulade** à l'atterrissage pendant laquelle on ne peut pas agir.

**Roll** : à l'atterrissage de la plongée, la caméra fait une **galipette avant**
(rotation autour de l'axe de tangage = effet « machine à laver »), on décélère,
puis on se relève. **Rouler absorbe la chute → aucun stun.**

| Paramètre | Déf. | Rôle |
|-----------|------|------|
| `dive_enabled` | true | Active la plongée. |
| `dive_speed` | 13 | Vitesse horizontale de la plongée (> sprint). |
| `dive_jump` | 8 | Pop vertical (> `jump_velocity`). |
| `dive_air_drag` | 0 | Frein horizontal en plongée (0 = portée max). |
| `roll_duration` | 0.65 | Durée de la roulade = durée du spin caméra (s). |
| `roll_friction` | 3 | Décélération pendant la roulade. |
| `roll_spins` | 1.0 | Nombre de tours de caméra (2 = plus violent). |

---

## 8. Stun de chute (cartoon, sans dégâts)

À la place de dégâts de chute : un **étourdissement**. Le contrôleur suit
l'altitude max atteinte en l'air (`_air_peak_y`) ; à l'atterrissage il calcule la
hauteur tombée.

- Chute < `fall_min_height` → rien.
- Au-delà → état **Stun** : perso figé, **étoiles ★ qui tournent** au-dessus de
  la tête (`StunStars`), caméra qui tangue. Durée interpolée entre `stun_min_time`
  et `stun_max_time` selon la hauteur (plafonnée à `fall_max_height`).
- **Annuler le stun** : faire une roulade à l'atterrissage (voir §9), ou plonger.

| Paramètre | Déf. | Rôle |
|-----------|------|------|
| `stun_enabled` | true | Active le stun de chute. |
| `fall_min_height` | 4 | Hauteur (m) en dessous de laquelle aucun stun. |
| `fall_max_height` | 14 | Hauteur (m) où le stun est maximal. |
| `stun_min_time` | 0.5 | Durée mini du stun (s). |
| `stun_max_time` | 2.5 | Durée maxi du stun (s). |

---

## 9. Landing-roll (annuler le stun au timing)

Appuyer sur **V pendant une chute**, juste avant de toucher le sol, déclenche une
**roulade d'atterrissage** qui **annule le stun**. Trop tôt = la fenêtre expire =
stun.

La fenêtre **s'élargit avec la vitesse de chute** : plus tu tombes vite (= chute
haute), plus c'est facile à timer. Implémenté via un *buffer* (`_roll_buffer_timer`)
dont la durée est interpolée entre `land_roll_window` et `land_roll_window_max`.

> Détail important : la décision roulade-vs-stun est centralisée dans
> `_check_fall_stun()` du contrôleur, et la **roulade est prioritaire**. C'est
> nécessaire car `move_and_slide()` détecte le sol avant que l'état `Air` n'ait sa
> frame ; sans cette priorité, le stun se déclencherait en premier.

| Paramètre | Déf. | Rôle |
|-----------|------|------|
| `land_roll_window` | 0.3 | Fenêtre de timing sur chute lente (s). |
| `land_roll_window_max` | 0.85 | Fenêtre sur chute rapide (= haute). |
| `land_roll_fast_speed` | 20 | Vitesse de chute (m/s) donnant la fenêtre max. |

---

## 10. Caméra (`PlayerCamera.gd`)

Effets réactifs au mouvement, sur le `Camera3D` :

- **FOV dynamique** : +`sprint_fov_add` en sprint, +`slide_fov_add` en slide, et
  bonus de survitesse plafonné à `speed_fov_add`.
- **Tilt** en strafe (désactivé par défaut : `strafe_tilt = 0`).
- **Head-bob** au sol.
- **Roulade** : galipette avant (rotation X) pendant `roll_duration`.
- **Stun** : la caméra tangue (effet « tête qui tourne »).

| Paramètre | Déf. | Rôle |
|-----------|------|------|
| `mouse_sensitivity` | 0.0025 | Sensibilité souris. |
| `base_fov` | 90 | FOV de base. |
| `sprint_fov_add` / `slide_fov_add` | 5 / 9 | FOV ajouté en sprint / slide. |
| `speed_fov_add` | 6 | Bonus FOV de survitesse (max). |
| `fov_lerp_speed` | 10 | Vitesse d'interpolation du FOV. |
| `strafe_tilt` / `slide_tilt` | 0 / 0 | Inclinaison caméra (deg). 0 = off. |
| `bob_amplitude` / `bob_frequency` | 0.025 / 9 | Head-bob. |

---

## 11. Hauteur de collision & crouch

La capsule se redimensionne en douceur entre `stand_height` et `crouch_height`
(`crouch_lerp_speed`), et la tête suit la hauteur.

| Paramètre | Déf. | Rôle |
|-----------|------|------|
| `stand_height` | 1.8 | Hauteur debout. |
| `crouch_height` | 0.9 | Hauteur accroupi. |
| `crouch_lerp_speed` | 16 | Vitesse de transition de hauteur. |

---

## 12. Recettes de réglage

| Pour… | Régler |
|-------|--------|
| Mouvement sol plus mou / glissant | ↓ `ground_friction`, ↓ `ground_accel` |
| Sauts plus hauts / flottants | ↑ `jump_velocity`, ↓ `gravity` |
| Retomber plus sec | ↑ `fall_gravity_mult` |
| Air-strafe CS plus marqué | ↑ `air_wishspeed` (≈2) |
| Pouvoir freiner/tourner plus en l'air | ↑ `air_control` |
| Slides plus longs | ↓ `slide_friction`, ↑ `slide_max_time` |
| Enchaînements de slides plus permissifs | ↑ `chain_speed_cap` |
| Plongée plus loin / haut | ↑ `dive_speed` / `dive_jump` |
| Effet roulade plus violent | ↑ `roll_spins` (2) |
| Landing-roll plus facile (hautes chutes) | ↑ `land_roll_window_max` |
| Stun plus court | ↓ `stun_max_time` |
| Désactiver une mécanique | `dive_enabled` / `stun_enabled` / `slide_cancel_enabled` = false |

Astuce : duplique `default_movement.tres` (ex. `fast.tres`, `floaty.tres`) et
change la ressource `config` sur le `Player` pour comparer des feelings sans
toucher au code.
