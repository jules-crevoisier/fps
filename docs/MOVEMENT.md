# Système de mouvement (modèle Apex)

Objectif : un déplacement **fluide et rapide façon Apex Legends**, en un peu plus
permissif. La vitesse se gagne par les **pentes** et les **slide-jumps**, et se
maintient par l'**air control** et le **slide-hop**.

## Vue d'ensemble

`PlayerController` (CharacterBody3D) contient l'état physique et les **helpers**
partagés (accel, friction, gravité, saut, redirection). La **logique** de chaque
mode vit dans une *state machine* (`scripts/player/states/`) :

```
Idle ⇄ Walk ⇄ Sprint ──(crouch + vitesse)──▶ Slide
                                               │  │
                              (saut = slide-jump)  (crouch relâché)
                                               ▼  ▼
                                              Air ⇄ (atterrissage)
                          atterrir crouch maintenu = slide-hop ─▶ Slide
```

Chaque état lit l'input et modifie `velocity` ; le `PlayerController` appelle
`move_and_slide()` une fois par frame.

## Les 4 piliers du feel Apex

### 1. Air strafe + air control (la fluidité)
En l'air, deux choses se combinent :
- `accelerate()` (style Source) ajoute un peu de vitesse dans la direction visée
  si `air_speed` n'est pas atteint → gain en strafe.
- `redirect_velocity()` fait **tourner le vecteur vitesse** vers la direction
  visée *sans perdre de vitesse* (`air_control`). C'est ça qui rend les
  trajectoires courbes et fluides.

### 2. Tap-strafe
Une **nouvelle pression** directionnelle en l'air multiplie l'air control par
`tap_strafe_boost` → on peut réorienter sa course de façon nette vers la caméra,
comme le tap-strafe d'Apex. Désactivable (`tap_strafe_enabled`).

### 3. Slide qui prend de la vitesse en descente
Déclenché par crouch en sprint (vitesse ≥ `slide_min_speed`). Sur du plat il
décroît (`slide_friction`), mais **dans une pente descendante il ACCÉLÈRE**
(`slide_slope_accel`). C'est la source principale de vitesse.

### 4. Slide-jump & slide-hop (l'enchaînement)
- **Slide-jump** : sauter pendant un slide conserve **tout** le momentum
  horizontal (`slide_jump_keep`) + un petit pop vertical (`slide_jump_pop`).
- **Slide-hop** : atterrir en gardant crouch enfoncé relance un slide en
  conservant la vitesse (`slide_hop_enabled`).
- Boucle : sprint → slide → saut → air strafe → atterrir → slide → …
  La vitesse est plafonnée par `chain_speed_cap` pour rester maîtrisable.

## Saut « game feel »

- **Coyote time** (`coyote_time`) : sauter encore valable un instant après avoir
  quitté le sol.
- **Jump buffer** (`jump_buffer_time`) : saut pressé juste avant l'atterrissage,
  exécuté au contact.
- **Fall gravity** (`fall_gravity_mult`) : gravité plus forte à la descente.
- Le saut **conserve toujours** le momentum horizontal.

## Tuning rapide

Ouvrir `resources/movement/default_movement.tres` dans l'inspector.

| Pour…                                   | Régler |
|-----------------------------------------|--------|
| Plus fluide / virages plus serrés       | ↑ `air_control`, ↑ `tap_strafe_boost` |
| Plus de vitesse dans les pentes         | ↑ `slide_slope_accel`, ↑ `slide_max_speed` |
| Enchaînements plus rapides   