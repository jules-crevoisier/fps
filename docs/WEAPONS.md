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
| Munitions | `mag_size`, `reserve_ammo`, `arena_reserve_ammo`, `reload_time` |
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
- **Chargeur et réserve à zéro** : un premier clic à vide (`dry_fire`) bascule
  **automatiquement** sur l'autre arme (`Weapon._owner_tick`), sans qu'il soit
  besoin d'appuyer sur 1/2/molette — même délai que le changement manuel
  (`SWITCH_DELAY`, 0,25 s).

### Munitions par mode (`Inventory.set_loadout(ids, ammo_rule)`, GF-21)

`GameMode.ammo_rule` fixe QUELLE réserve un loadout charge (docs/research/
10_ammo_kits_input.md §2.2) :

| Mode | Règle | Réserve chargée | Recharge au respawn |
|---|---|---|---|
| Mêlée (TDM) / Borne (Hardpoint) | `"arena"` | `WeaponConfig.arena_reserve_ammo` (§2.3, tableau ci-dessous) | oui, loadout complet (GF-20, `Weapon.server_refill_ammo`) |
| Litige (SnD) / Duel / Duo | `"round"` | `WeaponConfig.reserve_ammo` (comportement historique, inchangé) | à chaque manche (`RoundMode`, propre à chaque mode concret) |
| Entraînement (aucune scène de `GameMode`) | `"infinite"` | Réserve volontairement énorme (`Inventory.INFINITE_RESERVE`) | libre, jamais à sec |

`GameMode.ammo_rule` est un champ **calculé** (`"round"` si
`respawns_immediately() == false`, `"arena"` sinon) : TDM/Hardpoint en
héritent tels quels, `RoundMode` (SnD/Duel/Duo) l'obtient automatiquement en
surchargeant déjà `respawns_immediately()`.

**Boutique en arène (§2.6)** : elle ne recharge gratuitement l'inventaire EN
COURS DE VIE que dans les **10 premières secondes** après le spawn
(`Weapon.ARENA_BUY_WINDOW`, `arena_buy_allowed` — vérifié côté serveur dans
`_server_buy`) ; au-delà, un achat ne fait plus que choisir le loadout du
**prochain** respawn. Le Litige garde sa propre phase d'achat (`buy_phase`),
le Duel n'a pas de boutique (`DuelMode.server_try_purchase` renvoie faux),
l'entraînement reste libre.

---

## 3. Types de tir

- **Hitscan** : un rayon instantané (BO2-like).
- **Shotgun** : `pellets` rayons dispersés (`pellet_spread`).
- **Sniper** : un rayon, gros dégâts, **lunette** (zoom fort + overlay).

Le tir est **validé côté serveur** : le client envoie origine + directions + l'**ID
d'arme** ; le serveur vérifie que c'est bien l'arme en main dans **son** inventaire
(autoritaire), que le chargeur et la cadence le permettent, puis refait les rayons
et applique les dégâts (falloff + headshot, `WeaponMath`). Détail des contrôles :
[`MULTIPLAYER.md`](MULTIPLAYER.md) §3.

### Zone de tête (headshot)

`WeaponMath.is_headshot` compare le point d'impact au **sommet de la capsule
courante** (`body_origin_y + body_height`, `body_height` = hauteur COURANTE de la
cible — debout OU accroupie, `PlayerController.current_height` répliquée serveur)
**moins `HEAD_SIZE` = 0,40 m** : un impact strictement au-dessus de ce seuil compte
comme headshot.

- **Debout** (`stand_height` = 1,80 m) : seuil à 1,80 − 0,40 = **1,40 m** (inchangé
  depuis l'ancien seuil fixe).
- **Accroupi** (`crouch_height` = 0,90 m) : seuil à 0,90 − 0,40 = **0,50 m**.

Décision du lead (conflit §14 de [`STYLE_BIBLE.md`](STYLE_BIBLE.md)) : la tête garde
sa **taille réelle** (0,40 m de haut) quelle que soit la posture, plutôt que de
rétrécir proportionnellement à la capsule — l'approche proportionnelle utilisée
avant réduisait la bande headshot accroupie à 0,20 m, plus petite qu'une tête.
`HEAD_SIZE` est une constante absolue, jamais une proportion de `body_height`.

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

`scripts/world/WorldWeapon.gd` gère l'arme au sol (physique + détection). Elle est
**répliquée** : le serveur lui attribue un identifiant et la fait apparaître chez
tous ; le client ne fait que **demander** le ramassage, le serveur vérifie la
distance (≤ 2 m) puis met à jour l'inventaire.

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
créer une variante. Ajoute le chemin **à la fin** de `WeaponDatabase.PATHS` pour
qu'elle apparaisse dans l'arsenal / la boutique : l'index dans cette liste est
l'identifiant réseau de l'arme, on n'insère ni ne réordonne jamais.

Les calculs (dégâts à distance, coups pour tuer, TTK) sont dans
`scripts/combat/WeaponMath.gd` et couverts par `tests/combat/`.
