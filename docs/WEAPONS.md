# Système d'armes

Armes data-driven façon Valorant/CoD : profils en ressources, plusieurs types de
tir, recul réel, ADS/lunette, inventaire 2 slots, drop/pickup physique, boutique
(gratuite en training), et tir **validé côté serveur**.

---

## 1. Données — `WeaponConfig` (.tres)

Chaque arme est une ressource (`scripts/combat/WeaponConfig.gd`,
`resources/weapons/*.tres`). Catalogue dans `WeaponDatabase.gd`.

| Groupe | Champs clés |
|--------|-------------|
| Identité | `weapon_name`, `weapon_type` (HITSCAN/SHOTGUN/SNIPER), `category`, `cost` |
| Dégâts | `damage`, `damage_min`, `falloff_start`, `falloff_end`, `headshot_mult` |
| Tir | `max_range`, `fire_rate`, `automatic`, `spread_hip`, `spread_aim` |
| Munitions | `mag_size`, `reserve_ammo`, `reload_time` |
| ADS / Lunette | `aim_fov` (zoom), `aim_speed`, `scoped` (overlay lunette) |
| Shotgun | `pellets`, `pellet_spread` |
| Recul | `recoil_vertical`, `recoil_horizontal`, `recoil_recovery`, `recoil_aim_mult` |

### Arsenal actuel (placeholders, noms originaux)

| Arme | Catégorie | Type | Particularité |
|------|-----------|------|---------------|
| Pistolet | poing | hitscan | gratuit |
| Magnum | poing | hitscan | gros dégâts, semi |
| Rafale | SMG | hitscan | auto, cadence élevée |
| Marqueur | fusil | hitscan | semi, précis |
| Ravage | fusil | hitscan | auto polyvalent |
| Fracas | pompe | shotgun | 12 plombs |
| Faucheur | sniper | sniper | one-shot corps, **lunette** |

---

## 2. Inventaire & changement d'arme

- **2 slots** (n'importe quelle arme dans chacun), façon CoD.
- Changement : **1 / 2 / 3**, **molette**, **Y** (manette).
- Munitions suivies **par arme**.

---

## 3. Types de tir

- **Hitscan** : un rayon instantané (BO2-like).
- **Shotgun** : `pellets` rayons dispersés (`pellet_spread`).
- **Sniper** : un rayon, gros dégâts, **lunette** (zoom fort + overlay).

Le tir est **validé côté serveur** : le client envoie origine + directions + l'**ID
d'arme** ; le serveur refait les rayons et applique les dégâts (falloff + headshot).
L'ID d'arme est nécessaire car l'inventaire n'est pas répliqué.

---

## 4. Recul (recoil)

Vrai recul qui **déplace la visée** puis **récupère** : chaque tir ajoute un kick
(montée verticale + déviation horizontale aléatoire) qui s'accumule pendant le
spray, puis revient à zéro (`recoil_recovery`). Moins de recul en visée
(`recoil_aim_mult`). Implémenté dans `PlayerController.add_recoil()` /
`_update_recoil()`.

---

## 5. ADS / Lunette

- **Clic droit** = viser : la caméra zoome au `aim_fov` de l'arme.
- Armes **`scoped`** (sniper) : overlay de **lunette** (vignette + réticule) géré
  par le HUD ; les fusils font un ADS sans lunette (façon CoD).

---

## 6. Drop / Pickup (logique CoD)

- **Drop (G / D-pad bas)** : lâche l'arme en main, **lancée avec une physique** qui
  hérite de ta vitesse/saut (poussée avant + gravité, puis se pose au sol).
- **Pickup** :
  - **slot libre** → ramassage **automatique** en marchant dessus,
  - **inventaire plein** → **F** (ou R3) pour **échanger** l'arme en main avec celle
    du sol (l'ancienne est lâchée sur place).

`scripts/world/WorldWeapon.gd` gère l'arme au sol (physique + ramassage). Local
pour l'instant (training/solo) ; réplication réseau à venir.

---

## 7. Boutique / Loadout

Touche **B** : menu d'achat (`BuyMenu.gd`). En **training c'est gratuit** (argent
infini) — clique une arme pour l'équiper (slot libre sinon remplace l'arme en
main). Le menu principal a aussi une page **Arsenal** (catalogue + stats).

---

## 8. Feedback de hit

- **Chiffres de dégâts flottants** à l'impact (blancs, **orange** pour les
  headshots), affichés chez le tireur.
- **Mannequins d'entraînement** (`TrainingDummy.gd`) dans le terrain d'entraînement :
  PV affichés, se réinitialisent à la mort — pour tester armes/recul/scope en solo.

---

## 9. Régler une arme

Ouvre le `.tres` voulu dans `resources/weapons/` (inspector) ou duplique-le pour
créer une variante. Ajoute le chemin dans `WeaponDatabase.PATHS` pour qu'elle
apparaisse dans l'arsenal / la boutique.
