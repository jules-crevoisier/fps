# Système de mouvement

Objectif : un déplacement **nerveux et fluide**, qui récompense la maîtrise.
Le modèle s'inspire du moteur Source (accélération/friction séparées, air-strafe)
et des FPS modernes (slide + slide cancel façon Apex/CoD).

## Vue d'ensemble

`PlayerController` (CharacterBody3D) contient l'état physique et les **helpers**
partagés (accel, friction, gravité, saut). La **logique** de chaque mode de
déplacement vit dans une *state machine* (`scripts/player/states/`) :

```
Idle ⇄ Walk ⇄ Sprint
  ↓      ↓       ↓
Crouch ← (Ctrl) Slide ──(saut/cancel)──▶ Air
  ↑__________________________________________↓ (atterrissage)
```

Chaque état ne fait que **lire l'input** et **modifier `velocity`** ; le
`PlayerController` appelle `move_and_slide()` une fois par frame.

## Le modèle accel / friction (clé du « fluide »)

`accelerate()` n'ajoute que la composante **manquante** pour atteindre la vitesse
voulue dans la direction visée :

```gdscript
add_speed = wish_speed - velocity.dot(wish_dir)
velocity += min(accel * wish_speed * dt, add_speed) * wish_dir
```

En l'air, `air_speed` est volontairement **faible** : on n'ajoute pas de vitesse
brute, on permet juste de **tourner** le vecteur vitesse → c'est ce qui donne
l'air-strafe et la conservation d'inertie.

## Slide

1. Déclenché par Ctrl en sprint si la vitesse ≥ `slide_min_speed`.
2. Injecte `slide_boost` (plafonné à `slide_max_speed`).
3. `slide_friction` faible → on glisse longtemps.
4. Dans une pente descendante, `slide_slope_accel` **ajoute** de la vitesse.
5. `slide_steer` autorise une légère réorientation.

## Slide cancel

C'est la mécanique de skill du jeu : pendant un slide, **re-tapper Ctrl** (ou
sauter) **annule** le slide en conservant le momentum (`slide_cancel_keep`).
Avec `slide_cooldown = 0`, on peut re-slider immédiatement → on enchaîne
slide → cancel → slide pour **entretenir une vitesse élevée**.

- Cancel dans `slide_cancel_window` : momentum **total** gardé.
- Saut depuis le slide : `do_jump()` + momentum gardé → passe en `Air`.

## Saut « game feel »

- **Coyote time** (`coyote_time`) : sauter encore valable un court instant après
  avoir quitté le sol.
- **Jump buffer** (`jump_buffer_time`) : saut pressé juste avant l'atterrissage
  mémorisé et exécuté au contact.
- **Fall gravity** (`fall_gravity_mult`) : gravité plus forte à la descente →
  sauts plus secs et contrôlés.

## Tuning rapide

Ouvrir `resources/movement/default_movement.tres` dans l'inspector.

| Pour…                              | Régler |
|------------------------------------|--------|
| Mouvement plus « glissant »        | ↓ `ground_friction`, ↑ `air_accel` |
| Slides plus longs                  | ↓ `slide_friction`, ↑ `slide_max_time` |
| Chaînage de slides plus permissif  | `slide_cooldown = 0`, ↑ `slide_cancel_window` |
| Air-strafe plus marqué             | ↓ `air_speed`, ↑ `air_accel` |
| Sauts plus flottants               | ↓ `gravity`, ↓ `fall_gravity_mult` |

Astuce : duplique le `.tres` (`fast_movement.tres`, `floaty.tres`…) et change la
ressource sur le `Player` pour comparer des « feels » sans toucher au code.
