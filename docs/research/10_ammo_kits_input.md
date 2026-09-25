# 10 — Munitions, kits d'agents, AZERTY, boucles d'animation

> Statut : REMPLI (recherche du 2026-09-24). Répond aux retours de playtest du jour :
> (1) « on tombe vite à court de munitions » ; (2) « rendre chaque perso unique : une capacité, un passif » ;
> (3) « un switch AZERTY dans les réglages » ; (4) « les animations doivent boucler ».
> Code lu : `scripts/combat/` (Weapon, Inventory, WeaponConfig, WeaponDatabase), `resources/weapons/*.tres`,
> `scripts/networking/GameWorld.gd`, `scripts/modes/` (TDM, SnD, Duel), `scripts/agents/` (+ `abilities/`),
> `scripts/core/Settings.gd`, `scripts/ui/OptionsMenu.gd`, `scripts/ui/hud/AbilityBar.gd`, `project.godot [input]`,
> `scripts/player/PlayerInput.gd`, `scripts/player/CharacterAnimator.gd`, `tools/review/anim_reel.gd`, `docs/LORE.md`.
> Mesures : sondes GDScript lancées en `--headless` sur Godot 4.7 (glb des 6 agents + `fp_arms.glb`).
> Chiffres marqués *(proposition)* = nos valeurs, à valider en playtest.

## 0. Résumé

1. **Munitions — cause n°1 : un bug.** En Mêlée et en Borne (TDM, Hardpoint), le respawn ne recharge jamais l'inventaire. `Weapon.server_refill_ammo()` existe, mais rien ne l'appelle. Après 2 ou 3 vies, le joueur est à sec pour le reste du match, et les bots aussi.
2. **Munitions — système :** recharge complète au respawn (P0), réserves arène à ×5 chargeurs (P0), une **cartouchière** lâchée à chaque mort (P1) et 4 **Caisses du Comptoir** sur le Relais de la Soif (P2). Le Litige reste à la manche, comme Valorant.
3. **Kits — constat :** les 6 agents se partagent 8 primitives. Il y a 3 dash, 3 murs, 3 fumées et 3 tremplins. Aucun agent n'a de passif, et le soin de Roseau fait doublon avec la régénération de base (4 s, 35 PV/s).
4. **Kits — proposition :** chaque agent reçoit un **passif** et une **signature (E) qu'il est seul à avoir**. Les ultimes sont gardés ou ajustés. 6 nouvelles capacités reposent sur un socle commun (passifs, statuts, assistances).
5. **Économie d'ultime trop rapide :** 0,05 pt par PV infligé + 2 pts par kill, soit environ 7 pts par kill, pour un coût de 7 à 9. On descend à 0,01 pt/PV et 1 pt/kill.
6. **AZERTY :** les touches sont déjà liées par **position physique**, donc ZQSD marche. En revanche, le HUD affiche « Q » là où le Français doit presser « A ». Le switch actuel écrit des touches *logiques* et peut casser les contrôles : « Réinitialiser » force le QWERTY.
7. **AZERTY — correctif :** menu `Auto / AZERTY / QWERTY` qui ne change **que les libellés** (les liaisons restent physiques), libellés réels partout, remap complet capturé en physique.
8. **Animations en jeu :** les boucles d'import sont **correctes** (`loop_mode = 1`, raccord ≤ 0,09°). Ce qui ne boucle pas : l'étourdissement et l'interaction (clips uniques de 0,4 s et 2 s pour des états de 2 à 7 s). S'y ajoutent `AnimationNodeTransition` qui redémarre les clips (`reset = true` par défaut) et un haut du corps figé.
9. **Animations en revue :** les GIF de `anim_reel.gd` font toujours 45 images (1,5 s), quelle que soit la durée du clip. Aucun GIF ne boucle proprement : Idle dure 2,5 s et Sprint 0,667 s.
10. **Tâches (§6) :** P0 = GF-20, GF-21, GF-27, GF-28, UX-13, UX-14, AGT-01, AGT-02. Les 6 fiches d'agents viennent ensuite, en parallèle sur des fichiers disjoints.

---

## 1. Constats (tableau sourcé)

| # | Constat | Source | Ce qu'on en fait |
|---|---|---|---|
| 1 | Overwatch : seulement un chargeur et des rechargements infinis, sans réserve. Le joueur reste dans l'action et le débutant n'a rien à gérer. Le prix à payer, c'est le spam sur les passages étroits et les boucliers. | [Overwatch Wiki — Weapon](https://overwatch.fandom.com/wiki/Weapon), [GosuGamers — Infinite Ammo](https://www.gosugamers.net/overwatch/features/38916-infinite-ammo-depth-spam-and-everything-in-between) | Réserve infinie **seulement à l'entraînement**. En arène, on garde une réserve pour limiter le spam. |
| 2 | Deadlock : chargeur plus rechargement, sans réserve. Les objets modifient les munitions (Extended Magazine : +30 % de munitions max). | [Deadlock Wiki — Ammo](https://deadlock.wiki/Ammo), [Extended Magazine](https://deadlock.wiki/Extended_Magazine) | Confirme le modèle « héros » : les munitions ne doivent pas être une contrainte en arène. |
| 3 | Valorant : la réserve vaut pour une manche et se recharge à chaque manche. Au patch 6.11, la réserve du Vandal est passée de 75 à 50 pour réduire le spam. | [VALORANT Wiki — Vandal](https://wiki.playvalorant.com/en-us/Vandal) | Le Litige garde nos réserves actuelles (Ravage 25/75, soit l'ancien Vandal), rechargées à chaque manche. C'est **déjà fait** par `SnDMode._after_round_respawn`. |
| 4 | Apex : types de munitions en piles d'inventaire (60 légères ou 40 lourdes par emplacement), ramassées au sol. | [Apex Wiki — Ammo](https://apexlegends.wiki.gg/wiki/Ammo) | Logique de battle royale : **écartée**, car trop de gestion pour du 4v4 arène. |
| 5 | CoD : l'atout Scavenger recharge munitions et équipement sur les sacs des ennemis tombés. Il revient dans MWII et BO6. | [CoD Wiki — Scavenger](https://callofduty.fandom.com/wiki/Scavenger_(perk)) | Base de notre **cartouchière**, donnée à tous et non réservée à un atout. |
| 6 | Splitgate : la capacité totale est plafonnée. Marcher sur un point d'arme avec la même arme redonne des munitions. L'atout « Ammo Recycle » donne de la réserve sur kill. | [Splitgate AR — Weapons](https://splitgatearenareloaded.wiki.gg/wiki/Weapons), [Perks](https://splitgatearenareloaded.wiki.gg/wiki/Perks) | Plafond de réserve par arme et ramassage en marchant dessus. |
| 7 | Halo Infinite : ramasser la même arme recharge ses munitions ; les râteliers et socles d'armes servent de points de réapprovisionnement. | [Twinfinite — Halo Infinite ammo](https://twinfinite.net/guides/halo-infinite-how-to-get-more-ammo/) | Base des **Caisses du Comptoir** (points fixes et lisibles). |
| 8 | Titanfall 2 : pas de source fiable trouvée sur sa gestion de réserve. | — | Non utilisé. |
| 9 | Valorant : capacités de base (achetées), **signature** (une charge gratuite à chaque manche, parfois rendue par les kills) et ultime (points gagnés sur kill, mort, orbe, pose ou désamorçage). Tailwind (Jett) se recharge tous les 2 kills. | [VALORANT Wiki — Abilities](https://wiki.playvalorant.com/en-us/Abilities/Ultimate), [Valorant Wiki — Tailwind](https://valorant.fandom.com/wiki/Tailwind) | Structure « signature unique » et précédent de la charge rendue au kill (passif de Vif). |
| 10 | Riot : les capacités servent le tir ; même les capacités à dégâts visent surtout à créer une menace. | [ONE Esports — Valorant devs](https://www.oneesports.gg/valorant/devs-talk-you-dont-kill-with-abilities/) | Aucune capacité ne tue seule. Les dégâts de capacité restent **≤ 15 PV** et ne retirent jamais plus d'une balle au Ravage. |
| 11 | Apex : passif (sans recharge), tactique et ultime. Tactiques de 2 à 45 s, ultimes de 40 s à 4 min 30. | [EA — Legend guide](https://help.ea.com/en/articles/apex-legends/abilities/), [Charlie INTEL — cooldowns](https://www.charlieintel.com/apex-legends/every-apex-legends-ultimate-and-tactical-ability-cooldown-83869/) | Nos recharges de base visent 10 à 24 s. |
| 12 | Respawn : un passif doit servir le reste du kit ; un passif qui oblige à ouvrir la carte sans cesse est jugé mauvais. | [ESPN — Apex dev interview](https://www.espn.com/gaming/story/_/id/43704473/apex-legends-season-24-takeover-interview) | Chaque passif ci-dessous renforce la signature ou le rôle de son agent. |
| 13 | Overwatch (fév. 2026), passifs de sous-rôle : Stalwart réduit **de 40 % les repoussées et les ralentissements** subis ; Bruiser réduit de 25 % les dégâts critiques subis ; Initiator se soigne de 75 PV en l'air. | [Overwatch patch notes 2026-02](https://overwatch.blizzard.com/en-us/news/patch-notes/live/2026/02/) | Modèle du passif de Choc (−40 % sur les contrôles subis). |
| 14 | Deadlock : 4 capacités, dont parfois un passif qui occupe un emplacement. Recharges de base de 10 à 45 s, capacité 4 jusqu'à 230 s. | [Deadlock Wiki — Abilities](https://deadlock.wiki/Ability_Point), [PC Gamer — Deadlock heroes](https://www.pcgamer.com/games/moba/deadlock-characters-heroes-abilities/) | Bornes de recharge. |
| 15 | Overwatch, GDC 2016 « Play by Sound » : chaque capacité a une signature sonore lisible par l'ennemi. Les capacités sont scriptées et validées côté serveur. | [GDC Vault — Play by Sound](https://gdcvault.com/play/1023317/Overwatch-The-Elusive-Goal-Play), [GDC Vault — Networking Scripted Weapons and Abilities](https://www.gdcvault.com/play/1024041/Networking-Scripted-Weapons-and-Abilities) | Chaque signature et chaque passif a un **repère sonore et visuel** (contre-jeu), et tout est validé par le serveur. |
| 16 | Godot 4.7, `InputEventKey` : `keycode` est la lettre latine de la disposition active ; `physical_keycode` est la position sur un clavier US QWERTY. À la comparaison, `keycode` passe avant `physical_keycode`, puis `unicode`. | [Godot — InputEventKey](https://docs.godotengine.org/en/stable/classes/class_inputeventkey.html) | Une liaison qui porte un `keycode` devient logique et dépend de la disposition. Il faut capturer en physique seul. |
| 17 | Godot, `DisplayServer.keyboard_get_label_from_physical()` : convertit une position physique en libellé de la disposition active, sous Windows, macOS et Linux. `keyboard_get_layout_language()` renvoie le code de langue ISO-639. | [DisplayServer.xml](https://github.com/godotengine/godot/blob/master/doc/classes/DisplayServer.xml) | Libellé « Auto » et détection d'un clavier FR au premier lancement. |
| 18 | Godot n'a pas voulu d'une Input Map par défaut compatible AZERTY (issue fermée « not planned »). | [godot#28157](https://github.com/godotengine/godot/issues/28157) | C'est au jeu de gérer les libellés. |
| 19 | Import glTF : un clip dont le nom commence ou finit par `loop`/`cycle` est importé en boucle. | [Godot — name suffixes](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html) | Vérifié par sonde : `Idle_Loop` devient `Idle`, avec `loop_mode = 1`. |
| 20 | `AnimationNodeTransition` : si « reset » est actif sur une entrée, l'animation cible redémarre à chaque transition. `AnimationNodeAnimation.use_custom_timeline` permet d'imposer un `loop_mode` différent de celui de la ressource. **Sonde 4.7 : `is_input_reset(0) == true` par défaut.** | [Godot — AnimationNodeTransition](https://docs.godotengine.org/en/stable/classes/class_animationnodetransition.html), [AnimationNodeAnimation](https://docs.godotengine.org/en/stable/classes/class_animationnodeanimation.html) | Correctifs du §5. |

---

## 2. Munitions

### 2.1 Diagnostic (pourquoi on tombe à sec)

1. **Pas de recharge au respawn en arène.** `GameWorld._on_player_died` (`scripts/networking/GameWorld.gd:544-563`) téléporte le joueur et remet sa vie à neuf (`hp.reset()`), sans toucher à `Weapon`. `Weapon.server_refill_ammo()` (`scripts/combat/Weapon.gd:595`) n'a **aucun appelant**. L'inventaire vient de `Inventory.set_loadout` au `_ready` (`Weapon.gd:112-117`), une seule fois par match : ce qui est tiré dans une vie est perdu pour toutes les suivantes.
2. **Aucune source de munitions en arène.** Pas de ramassage ni de caisse. Les armes ne tombent pas à la mort (`_server_spawn_world_weapon` ne sert qu'au lâcher volontaire et à l'échange).
3. **Seule parade, cachée : la boutique.** En Mêlée et en Borne, `B` est gratuit et sans limite (`BuyMenu.gd:11-13`). `Weapon._try_purchase` renvoie vrai quand le mode n'a pas d'économie (`Weapon.gd:557-561`), et racheter une arme la rend pleine. Personne ne le sait, et c'est une recharge illimitée en plein combat.
4. **Les bots ne gèrent rien.** `scripts/ai/` n'écrit jamais `reload_pressed` ni `weapon_slot_pressed`. Un bot ne recharge qu'à chargeur vide (`Weapon.gd:222-229`) et ne passe jamais au pistolet. Une fois à sec, il reste inoffensif jusqu'à la fin du match.
5. **Réserves serrées pour tenir plusieurs vies.** Le loadout par défaut est Ravage + Pistolet (`WeaponDatabase.default_loadout_ids`) : 100 balles de Ravage, soit **10 s de gâchette**.

Arsenal actuel (`resources/weapons/*.tres`). STK = coups au corps pour tuer 100 PV à bout portant. « Kills/plein » = total × 35 % de précision ÷ STK *(hypothèse de précision « casual »)*.

| Arme | Chargeur | Réserve (.tres) | Total | Secondes de feu | STK corps | Kills/plein |
|---|---|---|---|---|---|---|
| Pistolet | 12 | 60 | 72 | 10,7 | 5 | 5,0 |
| Magnum | 6 | 24 | 30 | 13,6 | 3 | 3,5 |
| Rafale | 32 | 96 | 128 | 9,8 | 6 | 7,5 |
| Éclair | 26 | 104 | 130 | 12,3 | 6 | 7,6 |
| Ravage | 25 | 75 | 100 | 10,0 | 5 | 7,0 |
| Marqueur | 20 | 80 | 100 | 14,3 | 4 | 8,8 |
| Percuteur | 12 | 48 | 60 | 14,0 | 3 | 7,0 |
| Semeuse | 100 | 200 | 300 | 27,3 | 6 | 17,5 |
| Fracas | 6 | 24 | 30 | 25,0 | 1 (≤ 4 m) | ≈ 10 |
| Faucheur | 5 | 15 | 20 | 10,0 | 2 | ≈ 5 |

Une vie moyenne ne compte pas 7 kills : **si l'on recharge au respawn, les réserves actuelles suffisent presque**. Ce qui manque, c'est la recharge, puis de quoi soutenir une série de kills.

### 2.2 Règles par mode

| Mode (monde / code) | Recharge au respawn | Réserve | Cartouchière | Caisses | Boutique |
|---|---|---|---|---|---|
| Mêlée (TDM) | **oui, loadout complet** | **arène** (§2.3) | oui | oui | loadout choisi seulement ≤ 10 s après le spawn, appliqué aux respawns suivants |
| Borne (Hardpoint) | oui | arène | oui | oui | idem |
| Litige (SnD) | à chaque manche (déjà fait) | .tres actuel (par manche) | **non** | **non** | phase d'achat (existant) |
| Duel / Duo | à chaque manche (déjà fait, `DuelMode._after_round_respawn`) | .tres actuel | non | non | non (armes tirées au sort) |
| Entraînement | oui | **infinie** | — | — | libre |

Mise en œuvre : `GameMode.ammo_rule` vaut `"arena"`, `"round"` ou `"infinite"`, et `Inventory.set_loadout(ids, rule)` choisit la réserve. Les ids réseau et l'ordre de `WeaponDatabase.PATHS` ne changent pas.

### 2.3 Réserves arène *(proposition)*

Nouveau champ `WeaponConfig.arena_reserve_ammo`. La règle est ×5 chargeurs, sauf la Semeuse (déjà 300) et le Faucheur (×4).

| Arme | Chargeur | Réserve arène | Total | Secondes de feu | Kills/plein à 35 % |
|---|---|---|---|---|---|
| Pistolet | 12 | 60 (inchangé) | 72 | 10,7 | 5,0 |
| Magnum | 6 | **30** | 36 | 16,4 | 4,2 |
| Rafale | 32 | **160** | 192 | 14,8 | 11,2 |
| Éclair | 26 | **130** | 156 | 14,7 | 9,1 |
| Ravage | 25 | **125** | 150 | 15,0 | 10,5 |
| Marqueur | 20 | **100** | 120 | 17,1 | 10,5 |
| Percuteur | 12 | **60** | 72 | 16,7 | 8,4 |
| Semeuse | 100 | 200 (inchangé) | 300 | 27,3 | 17,5 |
| Fracas | 6 | **30** | 36 | 30,0 | ≈ 12 |
| Faucheur | 5 | **20** | 25 | 12,5 | ≈ 6 |

Ce changement ne touche ni les dégâts ni la cadence : le TTK et `docs/BALANCE.md` restent identiques, à part une colonne « réserve arène » à ajouter dans `tools/balance_table.gd`.

### 2.4 Cartouchière (munitions sur kill, arène seulement) *(proposition)*

- Le serveur la fait apparaître à la position de la mort, à +0,3 m. Elle reste 20 s. On en garde 16 au maximum sur la carte (la plus ancienne disparaît).
- On la ramasse **en marchant dessus** (rayon 1,2 m). Tout joueur vivant peut la prendre, allié ou ennemi, si l'une de ses réserves n'est pas pleine.
- Effet : **+1 chargeur** (`mag_size`) dans la réserve de **chacune des deux armes**, plafonné à la réserve arène. Pas de soin.
- Pourquoi pour tous : cela récompense le joueur qui avance sur le lieu du kill (Scavenger sans atout), et le camp qui tient la zone.
- Lisibilité : objet crème et bleu de la Commission qui tourne, reflet visible à 25 m, cliquetis au ramassage. Toast « +25 RAVAGE / +12 PISTOLET » près du panneau de munitions.
- Réseau : même patron que `WorldWeapon` (uid serveur, apparition répliquée, le client *demande* le ramassage, le serveur vérifie la distance). Nouvel appel `Weapon.server_add_reserve_mags(n)` qui pousse `_push_server_sync()`.

### 2.5 Caisses du Comptoir sur le Relais de la Soif (`wasteland`) *(proposition)*

Le Comptoir est l'armurerie de la Commission (LORE §2.5). Les caisses portent le pochoir « COMPTOIR ».

- On marche dessus (rayon 1,5 m). Elles remplissent la **réserve** des deux armes au maximum arène, pas le chargeur. **Recharge personnelle de 25 s** par caisse et par joueur (disque d'attente visible pour lui seul). Actives en Mêlée et en Borne, absentes en Litige et en Duel.
- Règles de placement : à 12–18 m de son propre spawn, à ≥ 8 m du centre de toute Borne, hors de la vue directe du spawn adverse, et pas sur les sites du Litige.
- Positions candidates, calculées sur les boîtes de `scripts/levels/maps/layouts/wasteland.gd`. **À valider par `map_shots` et le navmesh avant de les figer :**

| Caisse | Position (x, y, z) | Repère | Distance au spawn de son camp |
|---|---|---|---|
| O-Nord | (-24, 0, -6) | sous la passerelle `FuelPlank`, entre `FuelHouse` et `Garage` | 14 m (spawn O ≈ (-37, 0)) |
| O-Sud | (-24.5, 0, 6) | entre `Shack` et l'auvent des pompes | 14 m |
| E-Nord | (21.8, 0, -7) | ruelle entre `WestBlock` et `GasOffice` | 17 m (spawn E ≈ (37, 0)) |
| E-Sud | (25.5, 0, 5) | cour des cuves, entre `CourtCrates` et `TankS` | 12,5 m |

Les données vont dans un nouveau champ de layout, `"ammo_crates": [Vector3...]`, lu par `MapSetup`. Même format que `hardpoints`.

### 2.6 Retour UI (panneau munitions et invites)

- **Réserve** : couleur crème par défaut ; ocre quand il reste ≤ 1 chargeur en réserve ; rouge d'encre avec la mention **« VIDE »** à 0. Le chargeur garde ses chiffres « pinceau » à ≤ 25 % (`tokens.json` `low_ammo_threshold: 0.25`, STYLE_BIBLE : chiffres pinceau si ≤ 25 %).
- **Invite « [R] RECHARGER »** : quand le chargeur est à ≤ 25 %, qu'il reste de la réserve, et 1,5 s après la dernière rafale (jamais pendant le tir). La touche affichée est le **vrai libellé** (UX-13).
- **Chargeur et réserve à 0** : invite « [1] CHANGER D'ARME » et **passage automatique à l'autre arme** après le premier clic à vide (le signal `dry_fire` existe déjà ; on garde le délai `SWITCH_DELAY` de 0,25 s).
- **Ramassage** : toast « +N ARME » pendant 1,2 s, plus le son de la cartouchière ou de la caisse.
- **Boutique en arène** : elle choisit le loadout du prochain respawn. Elle n'agit tout de suite que ≤ 10 s après le spawn, ce qui ferme la recharge gratuite en plein combat (vérifié côté serveur dans `Weapon._server_buy`).

### 2.7 Bots

Hors combat, un bot recharge de lui-même dès que son chargeur descend sous 40 %. À sec, il passe au pistolet. Quand il lui reste moins d'un chargeur en réserve et qu'aucun ennemi n'est en vue, il fait un détour vers une cartouchière ou une caisse à ≤ 12 m. Tout passe par l'écriture de `player.input.reload_pressed` et `weapon_slot_pressed`, comme pour un humain.

---

## 3. Kits d'agents : un passif et une signature unique chacun

### 3.1 Constat

| Primitive (fichier) | Agents qui l'utilisent aujourd'hui (`AgentDatabase.gd`) |
|---|---|
| Dash (`DashAbility`) | Vif (Ruée), Choc (Charge), Vanne (Piquet) |
| Mur (`WallAbility`) | Choc, Vanne, Verrou, plus les ultimes Forteresse et Bastion |
| Fumée (`SmokeAbility`) | Vanne, Guet, Roseau |
| Tremplin (`JumpPadAbility`) | Vif, Guet, Verrou |
| Piège étourdissant (`StunTrapAbility`) | Choc, Verrou |
| Révélation (`RevealAbility`) | Guet, Roseau, plus les ultimes Vision totale et Sursaut |
| Éblouissement (`FlashAbility`) | Vif |
| Soin (`HealAbility`) | Roseau (Apaisement : 60 PV si 3 s sans dégât) |

- **Aucun passif** dans le code : ni `Passive`, ni hook de passif.
- Roseau, le seul « Soutien » qui soigne, **ne soigne qu'elle-même** (Apaisement, Sursaut). Et l'Apaisement fait doublon avec la régénération de base (`Health.gd:28-29` : reprise après 4 s, 35 PV/s).
- **L'ultime se charge trop vite.** On gagne 0,05 pt par PV infligé (`GameWorld.gd:570`), +2 par kill (`GameWorld.gd:593`) et 0,1 pt/s en continu (`AbilityState.gd:55`). Un kill à 100 dégâts rapporte donc 7 pts, pour un coût d'ultime de 7 à 9.

### 3.2 Règles de kit *(proposition)*

- Un kit se compose d'un **passif** (toujours actif, sans touche), de C et Q (capacités de base), de **E = signature** (mécanique qu'aucun autre agent n'a) et de X = ultime.
- Recharge : base de 12 à 24 s ; signature de 10 à 24 s ; ultime de 7 à 9 pts.
- **Aucune capacité ne tue seule** : ≤ 15 PV de dégâts, ce qui ne retire au plus qu'une balle au Ravage (100 → 85 PV reste 5 balles de 21).
- Chaque passif et chaque signature a un **repère visuel et sonore** perçu par l'ennemi, et un contre-jeu écrit.
- Aucun passif ne touche aux PV max ni aux dégâts d'arme : le TTK corps du Ravage reste à 400 ms.

### 3.3 Fiches

Colonne « Code » : **existe** = primitive déjà là, à régler ; **à construire** = nouveau fichier ou nouveau hook.

#### Vif — Entrée, « l'Allumette » (elle part avant le coup de feu)

| Slot | Proposition | Chiffres | Contre-jeu | Code |
|---|---|---|---|---|
| Passif | **Mèche courte** : chaque élimination ou assistance lui rend une charge de Ruée, et sa chevelure s'embrase (précédent : Tailwind de Jett) | +1 charge de Ruée (plafond 2) et +10 % de vitesse au sol pendant 2 s. Assistance = ≥ 40 dégâts sur la victime dans les 5 s avant sa mort. Flamme et « fshh » audibles à 20 m | pas de recharge sans kill ; la flamme annonce la Ruée | à construire : `AssistTracker`, hook `on_kill`, `AbilityState.grant_charge`, bonus de vitesse (`StatusEffects`) |
| **E Signature** | **Faux départ** (remplace Tremplin) : pose une braise à ses pieds ; réappuyer E la ramène dessus | Fenêtre de 5 s, portée max 30 m, retour instantané (fondu de 0,15 s, PV et munitions conservés). Recharge 16 s (lancée à la pose). Braise visible de tous (0,4 m, crépitement audible à 15 m), détruite à 30 dégâts | pré-viser la braise, ou la détruire pour annuler le retour | à construire : `FauxDepartAbility.gd`, état « armé » (relance) dans `AbilityState`, téléportation chez le propriétaire et validation serveur (distance et âge de la braise) |
| C | Ruée (inchangée) | 17 m/s, 2 charges, 6 s | trajectoire droite | existe |
| Q | Éblouissement : ajouter une **mèche de 0,3 s** et un projectile visible | aveugle 1,3 s, rayon 9 m ; recharge 22 → **18 s** | se retourner, casser la ligne de vue | existe (`FlashAbility`), la mèche est à ajouter |
| X | Résurgence (inchangée) | soin complet et bond à 6,5 m/s ; coût 8 → **7** | la finir avant ou juste après le bond | existe |

#### Choc — Entrée, « la Cloche » (il frappe d'abord)

| Slot | Proposition | Chiffres | Contre-jeu | Code |
|---|---|---|---|---|
| Passif | **Tête de cloche** : durée des étourdissements, éblouissements et ralentissements subis réduite (modèle : Stalwart d'Overwatch) | **−40 %** : étourdissement 2,2 → 1,3 s, éblouissement 1,3 → 0,8 s, Glu 1,5 → 0,9 s. « Ding » et étoiles plus brèves | le tuer au fusil plutôt qu'au contrôle | à construire : multiplicateur de contrôle (`StatusEffects.cc_mult`) appliqué dans `net_apply_stun`/`net_apply_flash` |
| **E Signature** | **Tape-la-cloche** (fusionne l'ancienne Charge du C) : charge d'épaule ; le premier ennemi touché vacille | Armement de 0,15 s (la cloche sonne, audible à 25 m), puis 0,5 s à 20 m/s (≈ 10 m) dans l'axe de visée à plat. Victime : **15 dégâts**, repoussée de 3 m, étourdie 0,5 s. Contre un mur, Choc s'étourdit lui-même 0,5 s. Pas de tir pendant la charge. Recharge 14 s | pas de côté (trajectoire figée après l'armement) ; la Glu arrête la charge | existe : mouvement (`DashAbility`), `net_apply_stun`. À construire : contact serveur le long de la trajectoire (ShapeCast), RPC `net_apply_impulse` (le mouvement est client-autoritaire) |
| C | Mur d'assaut (déplacé de E vers C) | 3,2 × 2,4 m, 5 s, 12 s | il expire vite | existe |
| Q | Piège-choc (seul piège étourdissant du jeu une fois celui de Verrou devenu Glu) | 2,2 s, pose ≤ 6 m, 20 s, 18 s | avancer prudemment sur les flancs | existe |
| X | Déferlante : ajouter un **armement de 0,4 s** (coup de cloche visible) | rayon 5,5 m ; étourdissement 1,8 → **1,5 s** ; coût 8 | se disperser au son | existe, l'armement est à ajouter |

Effet sur le TTK : 15 PV ne changent rien au Ravage (5 balles). Ils retirent une balle au Rafale (6 → 5), à l'Éclair (6 → 5) et au Pistolet (5 → 4).

#### Vanne — Contrôle, « la Digue » (elle ferme les rivières)

| Slot | Proposition | Chiffres | Contre-jeu | Code |
|---|---|---|---|---|
| Passif | **Relevé** : sa coffreuse mesure les impacts ; tout ennemi qui tire dans un de ses murs est marqué pour son équipe | marqueur « ! » pendant 1,5 s ; au plus une marque par ennemi toutes les 4 s ; impact « plâtre » et icône « repéré » chez la victime | ne pas tirer dans le béton, contourner | à construire : les murs de `cast_barrier` portent une métadonnée de propriétaire ; `Weapon._resolve_pending_shots` signale un impact sur un mur à son propriétaire, puis `cast_reveal` (existe) |
| **E Signature** | **Piquet d'arpenteur** (remplace le Piquet-poussée) : un vrai **grappin**, conforme au lore (« elle se hale d'un coup ») | ancrage sur le décor à ≤ 18 m (rayon `SHOT_MASK`, jamais sur un joueur), traction à 22 m/s pendant 0,8 s max ; Saut lâche le câble ; recharge 10 s ; câble visible et « clac » | trajectoire rectiligne, arrivée prévisible | à construire : `GrappleAbility.gd`, mouvement côté propriétaire, validation serveur (raycast depuis la vue serveur, ≤ 18 m + 1 m de marge) |
| C | Mur (inchangé) | 4 × 2,6 m, 8 s, 16 s | attendre la fin, prendre à revers | existe |
| Q | Fumée (inchangée) | rayon 3,2 m, 10 s, 20 s | contourner, s'approcher | existe |
| X | Forteresse (inchangée) | 7 × 3,4 m, 14 s ; coût 9 | autre rotation | existe |

#### Guet — Contrôle, « le Dé » (il a perdu le ciel)

| Slot | Proposition | Chiffres | Contre-jeu | Code |
|---|---|---|---|---|
| Passif | **Planeur** : ses pans de queue-de-pie font office d'ailes. Maintenir Saut en l'air le fait planer (« ce qui ressemble le plus à voler », LORE) | chute plafonnée à 2,5 m/s pendant 2 s max (recharge au sol) ; contrôle aérien +30 % ; pas d'étourdissement de chute tant qu'il plane. La dispersion en l'air s'applique toujours (`air_spread_add`) : il plane, il ne snipe pas | cible lente et lisible en l'air | à construire : branche « planeur » dans `scripts/player/states/Air.gd`, gardée par le passif |
| **E Signature** | **Coup de dé** (refonte de l'Œil, qui devient la seule révélation par projectile) : il lance son d20 | projectile visible, portée 22 m, 0,5 s de vol ; à l'arrêt, révèle les ennemis ≤ 9 m pendant 2,5 s ; chaque ennemi révélé voit une icône « œil » et entend un roulement de dé ; recharge 24 → **20 s** | l'avertissement dit de bouger (les marqueurs restent figés à l'instant du lancer) | existe (`RevealAbility`) ; à construire : délai de vol, RPC d'avertissement aux victimes |
| C | Rideau (inchangé) | fumée à 22 m | contourner | existe |
| Q | Poste avancé (inchangé) | tremplin, 18 s | emplacement fixe | existe |
| X | Vision totale : ajouter une annonce ennemie, « La cote vient de changer » | 3 s ; coût 7 | se replacer dès l'annonce | existe, l'annonce est à ajouter |

#### Roseau — Soutien, « la Passeuse » (elle plie, elle ne rompt pas)

| Slot | Proposition | Chiffres | Contre-jeu | Code |
|---|---|---|---|---|
| Passif | **Baume au repos** (remplace le C Apaisement, redondant) : « le baume ne prend qu'au repos » | sa régénération démarre après **2,5 s** sans dégât au lieu de 4 s, à **40 PV/s** au lieu de 35 ; à l'arrêt, elle se tient sur une patte | pression continue | à construire : `regen_delay` et `regen_rate` de `Health` réglés au spawn par le passif (ces champs existent déjà) |
| **E Signature** | **Baume du Palud** : elle lance un bocal qui forme une flaque de soin pour sa cordée, **le premier soin d'alliés du jeu** | portée 12 m ; zone de 4 m de rayon pendant 6 s ; **12 PV/s** aux alliés et à elle (72 max) ; soin divisé par 2 sur une cible touchée depuis < 1 s ; recharge 24 s ; zone sarcelle visible de tous | la zone est une cible (grenade, poussée) ; 12 PV/s pèsent peu face aux 210 PV/s d'un Ravage | existe en partie : `scripts/world/HealZone.gd` (Area3D serveur). À construire : filtre d'équipe, durée, `cast_heal_zone` répliqué |
| C | Brume (déplacée de E vers C) | rayon 2,2 m, 7 s, 16 s | la déborder | existe |
| Q | Voile (inchangé) | révélation autour d'un point, 3 s, 20 s | fenêtre courte | existe |
| X | Sursaut, **version d'équipe** : soin complet pour elle **et ses alliés à ≤ 10 m**, et révélation des ennemis à ≤ 12 m pendant 2 s | coût 7 → **8** | la tuer d'une rafale avant l'activation | existe pour elle seule ; la portée aux alliés est à ajouter |

#### Verrou — Soutien, « le Crapaud » (lent à dégainer, jamais pris)

| Slot | Proposition | Chiffres | Contre-jeu | Code |
|---|---|---|---|---|
| Passif | **Sang-froid** : immobile ou accroupi, il vise plus juste | après 0,4 s au sol sous 0,5 m/s, ou accroupi : dispersion **−30 %** et recul vertical **−20 %**. Les dégâts ne changent pas. Pose : main au chapeau | le déloger (Éblouissement, Tape-la-cloche), le prendre de flanc | à construire : multiplicateur passé à `WeaponFeel.total_spread_deg` et à `recoil_for_shot` |
| **E Signature** | **Glu** (refonte de la Chausse-trape, conforme au lore : la glu des dendrobates) : une plaque collante qui ralentit, au lieu d'un étourdissement | pose ≤ 6 m ; rayon 2,5 m ; 20 s ; reflet bleu visible à ≤ 10 m. Sur la plaque, un ennemi perd **50 % de vitesse**, ne peut ni sauter, ni glisser, ni plonger, et l'effet dure 1,5 s après la sortie. Zone persistante (plusieurs victimes). Détruite à 40 dégâts. Recharge 18 s | visible de près, destructible, contournable | existe : pose au sol (`StunTrapAbility`) ; à construire : effet de ralentissement (`StatusEffects`) et zone persistante |
| C | Rempart (déplacé de E vers C) | 4 × 2,6 m, 8 s, 16 s | attendre la fin | existe |
| Q | Passerelle (inchangée) | tremplin partagé | emplacement fixe | existe |
| X | Bastion : mur **et Glu** au lieu du piège étourdissant | mur de 12 s, Glu de 16 s ; coût 8 | autre axe | existe, à rebrancher sur la Glu |

Bilan des familles après changement : dash 1, charge 1, grappin 1, téléport de retour 1, flash 1, piège étourdissant 1, Glu 1, zone de soin 1, tremplin 2, révélation 2. **Murs et fumées restent à 3 porteurs**, avec des paramètres distincts (Valorant compte 5 contrôleurs à fumée). Les diversifier est une dette de conception, hors P1.

### 3.4 Économie d'ultime (AGT-02) *(proposition)*

| Source | Aujourd'hui | Proposé |
|---|---|---|
| Dégâts infligés | 0,05 pt/PV (`GameWorld.gd:570`) | **0,01 pt/PV** |
| Élimination | +2 (`GameWorld.gd:593`) | **+1** |
| Temps (vivant, phase LIVE) | 0,1 pt/s (`AbilityState.gd:55`) | **0,02 pt/s** en arène ; 0 en Litige, où l'on ajoute **+1 à la pose ou au désamorçage** (modèle Valorant, constat 9) |
| Coûts | 7 à 9 | 7 à 9 (inchangés) |

Résultat : un ultime tous les 3 à 4 kills, soit environ 2 min en Mêlée, au lieu d'un par kill.

### 3.5 Socle commun à construire (AGT-01)

- `scripts/agents/Passive.gd` (Resource), branché dans `AgentConfig.passive`. Hooks serveur : `on_spawn`, `on_kill`, `on_assist`, `modify_cc_duration(d)`, `spread_mult(player)`, `on_air(player)`.
- `scripts/agents/StatusEffects.gd` (état pur, autorité serveur, poussé au propriétaire par RPC) : `speed_mult`, `jump_locked`, `cc_mult`, avec expirations. Lu par `PlayerController.ground_move` et par les transitions Jump, Slide et Dive.
- `scripts/agents/AssistTracker.gd` (pur) : assistance = ≥ 40 dégâts dans les 5 s avant la mort. Alimenté par `GameWorld._on_player_damaged` et `_record_kill`.
- `AbilityController.net_apply_impulse(v)` pour la repoussée, et `AbilityState.grant_charge(i)` / `arm(i, window)` pour la relance.
- `BotBrain` : choix de capacités pour les nouvelles signatures (AGT-09). Sinon, les bots n'utilisent pas le nouveau kit.

---

## 4. AZERTY : recette pour notre code

### 4.1 État actuel

- `project.godot [input]` : **toutes** les touches sont liées en `physical_keycode`, avec `keycode: 0`. Les positions marchent donc déjà sur un AZERTY : l'avance est sur Z, les capacités sur **A** et E.
- `Settings.event_text` (`Settings.gd:558-569`) affiche le vrai libellé via `DisplayServer.keyboard_get_label_from_physical`. C'est correct dans les Options et les invites d'entraînement (`KeyLabel`).
- **Bug 1, libellés codés en dur :** `AbilityBar.gd:30` affiche `s.slot` (« C/Q/E/X ») ; de même `AgentSelectScreen.gd:171/206` et `AgentMenu.gd:93`. Un joueur AZERTY lit « Q », presse sa touche Q, qui est la position physique A, et **fait un pas à gauche**.
- **Bug 2, le switch est logique et partiel :** `Settings.apply_layout` (`:465-473`) écrit des `keycode` logiques, et seulement pour les 4 touches de déplacement.
  - Préréglage « qwerty » sur un clavier AZERTY : l'avance passe sur W, en bas à gauche. La gauche passe sur la touche A, **la même que la capacité Q** : les deux actions se déclenchent.
  - `reset_kb_page()` (`:496-505`) **force** `apply_layout("qwerty")`.
  - Le menu déroulant affiche « QWERTY » par défaut (`layout = "qwerty"`), même sur un clavier AZERTY.
- **Bug 3, remap :** `OptionsMenu._input` (`:555-560`) enregistre l'événement brut, avec `keycode` et `physical_keycode`. Comme `keycode` passe en priorité (constat 16), toute touche remappée devient **logique** sans que rien ne le signale. Par ailleurs, `Settings.ACTIONS` ne contient ni les capacités, ni `weapon_1..3`, ni `pickup`, `drop`, `buy_menu` ou `scoreboard` : elles ne sont pas remappables.

### 4.2 Recette

1. **Les liaisons restent physiques dans tous les cas.** `project.godot` reste la source. Le réglage `Settings.layout` prend `"auto"` (défaut), `"azerty"` ou `"qwerty"`, et **ne change que les libellés** : un scancode est positionnel, quelle que soit la disposition de l'OS. `"azerty"`/`"qwerty"` servent quand l'OS ment : clavier US avec Windows en FR, bureau à distance, etc.
2. **Une seule fonction de libellé**, utilisée par `event_text` et par `KeyLabel` :

```gdscript
## Settings.gd
const AZERTY_LABELS := {KEY_Q: "A", KEY_W: "Z", KEY_A: "Q", KEY_Z: "W", KEY_SEMICOLON: "M", KEY_M: ","}
static func label_for_physical(pk: Key) -> String:
	if pk >= KEY_0 and pk <= KEY_9:
		return OS.get_keycode_string(pk)            # rangée des chiffres : « 1 », jamais « & »
	match layout:
		"azerty": return AZERTY_LABELS.get(pk, OS.get_keycode_string(pk))
		"qwerty": return OS.get_keycode_string(pk)
	if DisplayServer.get_name() == "headless":      # voir KeyLabel.gd
		return OS.get_keycode_string(pk)
	var lbl := DisplayServer.keyboard_get_label_from_physical(pk)
	return OS.get_keycode_string(lbl if lbl != KEY_NONE else pk)
```

3. **`apply_layout(name)`** ne réécrit plus aucune liaison. Il enregistre `layout`, rafraîchit les libellés et émet `Settings.bindings_changed`, auquel le HUD et les menus sont abonnés. `reset_kb_page()` remet les touches par défaut depuis `ProjectSettings.get_setting("input/<action>")["events"]`, pour les seules actions clavier, et ne force plus rien.
4. **Migration au chargement** (`load_all`) :
   - une liaison sauvegardée avec `keycode != 0` et `physical == 0` vient de l'ancien switch. On la convertit en physique : `KEY_Z → KEY_W`, `KEY_Q → KEY_A`, `S → S` et `D → D` si l'ancien `layout` valait `"azerty"` ; identité si c'était `"qwerty"` ;
   - toute liaison qui a `physical != 0` perd son `keycode` ;
   - `layout` qui valait `"qwerty"` devient `"auto"`.
5. **Capture du remap en physique** (`OptionsMenu._input`) :

```gdscript
var ev := InputEventKey.new()
ev.physical_keycode = event.physical_keycode   # keycode reste 0 : liaison par POSITION
Settings.set_binding(_listening_action, ev)
```

   On ajoute aussi une **détection de conflit** : si la position est déjà prise par une autre action de jeu, on échange les deux touches et on affiche « Échangé avec : … ».
6. **Remap complet** : `Settings.ACTIONS` s'étend à `ability_c` (« Capacité 1 »), `ability_q` (« Capacité 2 »), `ability_e` (« Signature »), `ultimate` (« Ultime »), `weapon_1..3`, `pickup`, `drop`, `buy_menu` et `scoreboard`.
7. **Libellés réels partout** : `PlayerInput.action_for_slot(slot)` renvoie `ability_c`, `ability_q`, `ability_e` ou `ultimate`. `AbilityBar`, `AgentSelectScreen` et `AgentMenu` affichent `KeyLabel.for_action(PlayerInput.action_for_slot(ab.slot))`. `Ability.slot` reste l'identifiant **interne** (réseau, bots) et ne s'affiche plus jamais.
8. **Détection au premier lancement** (pas de `settings.cfg`) : on lit `DisplayServer.keyboard_get_layout_language(DisplayServer.keyboard_get_current_layout())`. Si la langue commence par `fr`, on affiche un toast unique : « Clavier AZERTY détecté : déplacements Z Q S D, capacités C A E X ». Le menu affiche « Auto (AZERTY détecté) ». Un simple toast suffit : `fr-CA` est souvent en QWERTY, et les libellés « auto » restent justes dans tous les cas.

### 4.3 Table des actions

| Action | `physical_keycode` | Libellé QWERTY | Libellé AZERTY FR |
|---|---|---|---|
| Avancer / Gauche / Reculer / Droite | W / A / S / D (87/65/83/68) | W A S D | **Z Q S D** |
| Capacité 1 / 2 / Signature / Ultime | C / Q / E / X (67/81/69/88) | C Q E X | **C A E X** |
| Recharger / Ramasser / Lâcher / Plonger / Boutique | R / F / G / V / B | R F G V B | R F G V B |
| Armes 1 / 2 / 3 | 1 / 2 / 3 (49–51) | 1 2 3 | **1 2 3** (et non `& é "`) |
| Onglet menu préc. / suiv. | Q / E | Q E | **A E** |
| Saut, Accroupi, Marcher, Tableau | Espace, Ctrl, Maj, Tab | — | — |

Vérification : `ui_shots` des Options et du HUD avec `layout = "azerty"` forcé. La page Options doit montrer « Z Q S D » et la barre de capacités « C A E X ».

---

## 5. Boucles d'animation

### 5.1 Mesures (sonde headless Godot 4.7 sur `vif`, `choc`, `vanne`, `guet`, `roseau`, `verrou`, `fp_arms`)

| Clip (état) | `loop_mode` | Durée | Raccord (os `DEF-hips`, 1re vs dernière clé) |
|---|---|---|---|
| Idle, Walk, Jog_Fwd, Sprint | 1 (linéaire) | 2,5 / 1,333 / 0,917 / 0,667 s | ≤ 0,09° : sans couture |
| Crouch_Idle, Crouch_Fwd, Jump (AIR/DIVE), Pistol_Idle | 1 | 2,917 / 2,0 / 2,5 / 1,667 s | 0,00° |
| Hit_Head (**STUN**) | 0 | **0,417 s** | — |
| Interact (**INTERACT**) | 0 | **2,0 s** | — |
| Pistol_Aim_Down, Neutral, Up (haut du corps) | 0 | 0,167 s (poses) | — |
| Pistol_Reload / Pistol_Shoot / Roll / Death01 | 0 | 1,667 / 0,625 / 1,458 / 2,375 s | — |

Les 6 agents ont les **mêmes 46 clips**. L'import (`nodes/use_name_suffixes=true`) retire bien le suffixe `_Loop` et active la boucle. **L'asset n'est pas en cause.**

### 5.2 Ce qui ne boucle pas, et pourquoi

1. **États longs sur des clips uniques.**
   - `STUN` joue Hit_Head (0,417 s) alors que l'étourdissement dure 1,8 à 2,2 s (`StunTrap`, `StunBurst`, `Bastion`) : la pose reste figée environ 1,5 s.
   - `INTERACT` joue Interact (2 s) alors qu'on tient F 4 s pour poser et 7 s pour désamorcer (`SnDMode.PLANT_TIME`/`DEFUSE_TIME`) : 2 à 5 s de figé.
   - De plus, `interacting = input.pickup_held` (`PlayerController.gd:379`) : maintenir F **n'importe où** déclenche cette pose.
2. **Clips redémarrés à chaque transition.** `_build_tree` (`CharacterAnimator.gd:603-613`) laisse `reset = true` sur chaque entrée (valeur par défaut, vérifiée par sonde). Chaque changement de locomotion relance le clip à l'image 0.
   - Cela arrive au seuil Jog/Sprint (`JOG_SPEED_THRESHOLD = 6.0`, sans hystérésis), à l'Idle/Walk d'un bot qui freine en virage, et à l'Air/Idle sur les marches (StairStep).
   - La boucle n'arrive jamais au bout : à l'œil, elle « ne boucle pas ».
3. **Haut du corps figé.** Le calque `UpperBody` mélange à **100 %** trois poses statiques de 0,167 s sur la colonne et les bras, pendant toute la locomotion debout (`:616-626`, `:657-663`). Les jambes marchent, les bras sont figés ; `Pistol_Idle` (respiration en boucle) n'est pas utilisé.
4. **Rechargement désynchronisé.** Pistol_Reload dure 1,667 s pour des rechargements de 1,5 à 4,2 s (Semeuse) : le geste se termine puis le personnage reste immobile.
5. **Reels de revue faux.** `tools/review/anim_reel.gd:11` fixe `FRAMES := 45` (1,5 s à 30 i/s) pour **tous** les clips (`_seek_all` fait un `fmod`), et `anim_gif.py` boucle le GIF à l'infini (`loop=0`). Idle (2,5 s), Walk (1,333 s), Sprint (0,667 s, soit 2,25 cycles) et Roll sautent au retour. Les GIF montrés ne bouclent jamais, alors que le jeu boucle.

### 5.3 Correctifs

```gdscript
## CharacterAnimator._build_tree()
const _LOOPING := [Locomotion.IDLE, Locomotion.WALK, Locomotion.JOG, Locomotion.SPRINT,
	Locomotion.CROUCH_IDLE, Locomotion.CROUCH_FWD, Locomotion.SLIDE, Locomotion.AIR,
	Locomotion.STUN, Locomotion.INTERACT]
for i in Locomotion.size():
	locomotion_node.set_input_reset(i, not _LOOPING.has(i))   # une boucle garde sa phase
# STUN et INTERACT : boucle forcée sans toucher au .glb
_force_loop(bt, Locomotion.STUN, Animation.LOOP_PINGPONG)   # Hit_Head en va-et-vient = « sonné » cartoon (+ StunStars)
_force_loop(bt, Locomotion.INTERACT, Animation.LOOP_LINEAR)  # clip -> "Fixing_Kneeling" (5,17 s)
func _force_loop(bt: AnimationNodeBlendTree, loco: int, mode: Animation.LoopMode) -> void:
	var leaf := bt.get_node("Loco_%d" % loco) as AnimationNodeAnimation
	var anim := _character_body.get_anim_player().get_animation(leaf.animation)
	leaf.use_custom_timeline = true
	leaf.timeline_length = anim.length      # renseigner la durée réelle du clip
	leaf.stretch_time_scale = false
	leaf.loop_mode = mode
```

- **Hystérésis et temps de maintien** : on passe en SPRINT à ≥ 6,4 m/s et on revient en JOG à ≤ 5,6 m/s (fonction pure `sprint_or_jog(speed, was_sprint)`, testée). Dans `_drive_locomotion`, un changement entre deux locomotions *en boucle* est ignoré s'il survient moins de 0,1 s après le précédent. Ce filtre ne s'applique jamais à DEAD, STUN, ROLL ni JUMP_*.
- **INTERACT** seulement pendant une vraie pose ou un vrai désamorçage : porteur dans un site, ou défenseur près de la bombe posée. Le propriétaire le calcule depuis l'état répliqué de `SnDMode`, et non plus depuis `pickup_held` seul.
- **Haut du corps** : `blend_amount` vaut 1,0 à l'arrêt, en marche et accroupi ; 0,7 en Jog ; **0,4 en Sprint**, pour que les bras du clip Sprint balancent. On ajoute Pistol_Idle à 0,35 par-dessus la pose de visée (respiration). À valider dans le reel.
- **Rechargement** : un `AnimationNodeTimeScale` « ReloadSpeed » avant `ReloadClip`, réglé à `1.667 / reload_time` de l'arme en main. L'id est déjà diffusé par `_broadcast_current_id`.
- **Reels** : `FRAMES = roundi(len × 30)` par clip (Idle 75, Walk 40, Jog 28, Sprint 20), un GIF par clip. Les clips uniques tiennent leur dernière image 10 images avant de reboucler. On ajoute un contrôle : différence de pixels entre l'image 0 et l'image N+1 sous un seuil, sinon « LOOP_FAIL » dans `summary.md`.

---

## 6. Tâches priorisées

Chaque tâche liste ses **fichiers possédés**. Deux tâches qui touchent le même fichier sont séquencées par `dépend`.

| Id | Titre | Prio | Taille | Fichiers possédés | Acceptation | Dépend |
|---|---|---|---|---|---|---|
| **GF-20** | Recharge complète au respawn en arène | P0 | S | `scripts/networking/GameWorld.gd` (`_on_player_died`), `tests/networking/test_respawn_refill.gd` | Un joueur mort à 0/0 réapparaît avec son loadout plein, en hôte, en client distant et en bot. Litige et Duel inchangés (test). Sonde de gameplay : 3 vies de suite sans chargeur vide au spawn | — |
| **GF-21** | Réserves arène, règle de munitions par mode, boutique arène limitée au spawn, passage automatique à l'autre arme à sec | P0 | M | `scripts/combat/WeaponConfig.gd`, `resources/weapons/*.tres`, `scripts/combat/Inventory.gd`, `scripts/combat/Weapon.gd`, `scripts/modes/GameMode.gd`, `tools/balance_table.gd`, `docs/BALANCE.md`, `docs/WEAPONS.md`, `tests/combat/test_inventory.gd` | Valeurs du §2.3 en Mêlée et Borne. Litige et Duel sur les .tres. Réserve infinie à l'entraînement. Achat arène refusé au-delà de 10 s après le spawn (test serveur). Bascule automatique après un clic à vide. BALANCE.md régénéré | GF-20 |
| **GF-22** | Cartouchière lâchée à la mort (arène) | P1 | M | `scripts/world/AmmoPack.gd` (nouveau), `scripts/networking/GameWorld.gd`, `scripts/combat/Weapon.gd` (`server_add_reserve_mags`), `tests/world/test_ammo_pack.gd` | Apparaît à la mort, reste 20 s, 16 au plus. Ramassage serveur à ≤ 1,2 m. +1 chargeur par arme, plafonné. Absente en Litige et en Duel. Vérifiée en image | GF-21 |
| **GF-23** | HUD munitions : états de la réserve, invites « [R] RECHARGER » et « CHANGER D'ARME », toast « +N » | P1 | S | `scripts/ui/hud/AmmoPanel.gd`, `scripts/ui/HudFormat.gd`, `scripts/ui/BuyMenu.gd` (message « loadout au prochain respawn »), `tests/ui/test_hud_format.gd` | Seuils du §2.6. Libellé de touche réel. `ui_shots` à 1080p et 720p conformes à STYLE_BIBLE §8.3 | UX-13 |
| **GF-24** | Bots et munitions : recharge tactique, passage au pistolet, détour vers cartouchière ou caisse | P1 | M | `scripts/ai/BotBrain.gd`, `scripts/ai/BotCombatStyle.gd`, `tests/ai/test_bot_ammo.gd` | Sur un banc de 5 min en Mêlée avec bots, 0 bot à 0/0 plus de 5 s. Le bot recharge hors combat sous 40 % | GF-22 |
| **GF-25** | Caisses du Comptoir sur le Relais de la Soif | P2 | M | `scripts/world/AmmoCrate.gd` (nouveau), `scripts/levels/maps/layouts/wasteland.gd`, `scripts/levels/maps/MapSetup.gd`, `tests/maps/test_ammo_crates.gd` | 4 caisses du §2.5, atteignables au navmesh, ≥ 8 m de chaque Borne. Recharge personnelle de 25 s. Absentes en Litige. `map_shots` validés | GF-22 |
| **GF-26** | Litige : l'arme principale tombe à la mort, ramassable avec ses munitions restantes | P2 | S | `scripts/combat/Weapon.gd`, `scripts/modes/SnDMode.gd`, `tests/modes/test_snd_drop.gd` | L'arme tombe avec son chargeur et sa réserve. Ramassage par l'échange existant. Absente en arène | GF-22 |
| **GF-27** | Boucles d'animation en jeu : `reset` coupé sur les boucles, hystérésis, STUN et INTERACT en boucle, vrai INTERACT, haut du corps selon la locomotion, rechargement calé sur `reload_time` | P0 | M | `scripts/player/CharacterAnimator.gd`, `scripts/player/PlayerController.gd` (`_update_anim_state`), `tests/player/test_character_animator.gd` | Test pur : aucun changement de locomotion quand la vitesse oscille entre 5,8 et 6,2 m/s. `is_input_reset` faux sur les boucles. Reel d'un bot étourdi 2,2 s et en désamorçage 7 s : aucune image figée plus de 0,2 s | — |
| **GF-28** | Reels de revue qui bouclent : images par clip, un GIF par clip, contrôle LOOP_FAIL | P0 | S | `tools/review/anim_reel.gd`, `tools/review/anim_gif.py` | Idle 75 images, Walk 40, Jog 28, Sprint 20. Écart image 0 / N+1 sous le seuil pour chaque boucle. `summary.md` liste les LOOP_FAIL | — |
| **UX-13** | Libellés réels des touches partout (barre de capacités, sélection d'agent, menu Agents, invites) | P0 | S | `scripts/ui/hud/AbilityBar.gd`, `scripts/ui/AgentSelectScreen.gd`, `scripts/ui/AgentMenu.gd`, `scripts/training/KeyLabel.gd`, `scripts/player/PlayerInput.gd` (`action_for_slot`), `tests/ui/test_key_labels.gd` | En AZERTY forcé, la barre montre « C A E X ». `Ability.slot` n'est plus jamais affiché. Démarrage headless sans SCRIPT ERROR | — |
| **UX-14** | Disposition clavier `Auto / AZERTY / QWERTY` (libellés seulement), migration des anciennes liaisons logiques, réinitialisation qui ne force plus le QWERTY, détection FR | P0 | M | `scripts/core/Settings.gd`, `scripts/ui/OptionsMenu.gd`, `tests/core/test_settings.gd`, `docs/CONTROLS.md` | Tests : `label_for_physical` pour les 3 modes. Une sauvegarde ancienne (Z/Q/S/D logiques) migre en physique. Après réinitialisation, plus aucune double action A→(gauche + capacité). `ui_shots` des Options en AZERTY | UX-13 |
| **UX-15** | Remap complet (capacités, armes 1–3, ramasser, lâcher, boutique, tableau), capture physique, échange en cas de conflit | P1 | S | `scripts/core/Settings.gd`, `scripts/ui/OptionsMenu.gd`, `tests/core/test_settings_remap.gd` | Toute liaison capturée a `keycode == 0`. Conflit → échange et message. Persiste au redémarrage | UX-14 |
| **AGT-01** | Socle : passifs, statuts, assistances, repoussée, relance | P0 | M | `scripts/agents/Passive.gd`, `StatusEffects.gd`, `AssistTracker.gd` (nouveaux), `scripts/agents/AgentConfig.gd`, `AbilityController.gd`, `AbilityState.gd`, `scripts/player/PlayerController.gd` (`ground_move` × `speed_mult`), `tests/agents/test_passives.gd`, `tests/agents/test_status_effects.gd` | Hooks serveur appelés (test). Statuts poussés au propriétaire en ≤ 1 tick, y compris pour un bot en appel direct. Repoussée appliquée chez le propriétaire distant | GF-27 (PlayerController) |
| **AGT-02** | Économie d'ultime (§3.4) et annonces ennemies d'ultime | P0 | S | `scripts/networking/GameWorld.gd` (`_charge_ult`, `_on_player_damaged`), `scripts/agents/AbilityState.gd` (`ult_charge_rate`), `tests/agents/test_ability_state.gd` | 100 dégâts + 1 kill = 2 pts (test). Coût 8 atteint en ≈ 3 à 4 kills. Litige : +1 à la pose ou au désamorçage | AGT-01, GF-22 |
| **AGT-03** | Vif : Mèche courte, Faux départ, mèche de l'Éblouissement | P1 | M | `scripts/agents/abilities/FauxDepartAbility.gd`, `scripts/agents/passives/MecheCourte.gd`, `scripts/agents/abilities/FlashAbility.gd`, tests dédiés | Chiffres du §3.3. Retour refusé côté serveur au-delà de 30 m ou 5 s. Braise destructible. Turntable ou reel du VFX | AGT-01 |
| **AGT-04** | Choc : Tête de cloche, Tape-la-cloche, armement de la Déferlante | P1 | M | `scripts/agents/abilities/BellChargeAbility.gd`, `passives/TeteDeCloche.gd`, `StunBurstAbility.gd`, tests | Contact serveur ; 15 PV, 3 m, 0,5 s ; auto-étourdissement contre un mur ; −40 % sur les contrôles subis (test) | AGT-01 |
| **AGT-05** | Vanne : Relevé, Piquet d'arpenteur (grappin) | P1 | M | `scripts/agents/abilities/GrappleAbility.gd`, `passives/Releve.gd`, tests | Ancrage ≤ 18 m validé côté serveur. Marque de 1,5 s, 1 marque par ennemi toutes les 4 s. Branchement sur l'impact de mur dans `Weapon.gd` par un hook fourni par GF-21 | AGT-01, GF-21 |
| **AGT-06** | Guet : Planeur, Coup de dé | P1 | M | `scripts/player/states/Air.gd`, `passives/Planeur.gd`, `scripts/agents/abilities/RevealAbility.gd`, tests | Chute ≤ 2,5 m/s pendant 2 s, pas d'étourdissement de chute en planant. Délai de vol de 0,5 s. Avertissement reçu par les seules victimes | AGT-01 |
| **AGT-07** | Roseau : Baume au repos, Baume du Palud, Sursaut d'équipe, retrait de l'Apaisement | P1 | M | `scripts/world/HealZone.gd`, `abilities/BalmZoneAbility.gd`, `abilities/RenewalAbility.gd`, `passives/BaumeAuRepos.gd`, tests | Zone filtrée par équipe, 12 PV/s pendant 6 s, divisée par 2 si touché depuis < 1 s. Sursaut soigne les alliés à ≤ 10 m. Régénération 2,5 s / 40 PV/s pour elle seule | AGT-01 |
| **AGT-08** | Verrou : Sang-froid, Glu, Bastion avec Glu | P1 | M | `scripts/combat/WeaponFeel.gd` (multiplicateurs), `abilities/GlueAbility.gd`, `abilities/BastionAbility.gd`, `passives/SangFroid.gd`, tests | −30 % de dispersion et −20 % de recul après 0,4 s immobile (test pur). Glu : −50 %, ni saut, ni glissade, ni plongeon, +1,5 s après la sortie. Plusieurs victimes | AGT-01 |
| **AGT-09** | Câblage : `AgentDatabase`, UI des passifs et signatures, bots, docs | P1 | M | `scripts/agents/AgentDatabase.gd`, `scripts/ui/AgentSelectScreen.gd`, `scripts/ui/AgentMenu.gd`, `scripts/ui/hud/AbilityBar.gd` (badge de passif), `scripts/ai/BotBrain.gd` (choix de capacités), `docs/AGENTS.md`, `docs/LORE.md` §4 | Kits du §3.3 en jeu. Les bots utilisent chaque signature au moins une fois en 5 min. `ui_shots` de la sélection d'agent. AGENTS.md et LORE.md alignés | AGT-03 à AGT-08, UX-13, GF-24 |

**Vague 1 en parallèle, fichiers disjoints :** GF-20, GF-27, GF-28, UX-13. **Vague 2 :** GF-21, UX-14, AGT-01. **Vague 3 :** GF-22, GF-23, UX-15, AGT-02, puis AGT-03 à AGT-08 en parallèle. **Vague 4 :** GF-24, GF-25, GF-26, AGT-09.

Hors périmètre, pour mémoire : `assets/models/characters/baume.glb` et `roc.glb` sont périmés (LORE §9), avec 230 et 138 clips dont des doublons `.001`. Ils sont à retirer lors d'un nettoyage.

---

## 7. Sources

- Overwatch Wiki — Weapon : https://overwatch.fandom.com/wiki/Weapon
- GosuGamers — Infinite Ammo in Overwatch : https://www.gosugamers.net/overwatch/features/38916-infinite-ammo-depth-spam-and-everything-in-between
- Deadlock Wiki — Ammo : https://deadlock.wiki/Ammo · Extended Magazine : https://deadlock.wiki/Extended_Magazine · Abilities : https://deadlock.wiki/Ability_Point
- PC Gamer — Deadlock heroes : https://www.pcgamer.com/games/moba/deadlock-characters-heroes-abilities/
- VALORANT Wiki — Vandal : https://wiki.playvalorant.com/en-us/Vandal · Abilities : https://wiki.playvalorant.com/en-us/Abilities/Ultimate
- Valorant Wiki — Tailwind : https://valorant.fandom.com/wiki/Tailwind
- ONE Esports — Valorant devs on abilities : https://www.oneesports.gg/valorant/devs-talk-you-dont-kill-with-abilities/
- Apex Wiki — Ammo : https://apexlegends.wiki.gg/wiki/Ammo
- EA — Apex Legend guide : https://help.ea.com/en/articles/apex-legends/abilities/
- Charlie INTEL — Apex cooldowns : https://www.charlieintel.com/apex-legends/every-apex-legends-ultimate-and-tactical-ability-cooldown-83869/
- ESPN — Apex dev interview : https://www.espn.com/gaming/story/_/id/43704473/apex-legends-season-24-takeover-interview
- CoD Wiki — Scavenger : https://callofduty.fandom.com/wiki/Scavenger_(perk)
- Splitgate Arena Reloaded Wiki — Weapons : https://splitgatearenareloaded.wiki.gg/wiki/Weapons · Perks : https://splitgatearenareloaded.wiki.gg/wiki/Perks
- Twinfinite — Halo Infinite ammo : https://twinfinite.net/guides/halo-infinite-how-to-get-more-ammo/
- Overwatch patch notes, février 2026 (passifs de sous-rôle) : https://overwatch.blizzard.com/en-us/news/patch-notes/live/2026/02/
- GDC Vault — Overwatch, Play by Sound : https://gdcvault.com/play/1023317/Overwatch-The-Elusive-Goal-Play
- GDC Vault — Networking Scripted Weapons and Abilities in Overwatch : https://www.gdcvault.com/play/1024041/Networking-Scripted-Weapons-and-Abilities
- Godot — InputEventKey : https://docs.godotengine.org/en/stable/classes/class_inputeventkey.html
- Godot — DisplayServer.xml : https://github.com/godotengine/godot/blob/master/doc/classes/DisplayServer.xml
- Godot — issue #28157 (AZERTY) : https://github.com/godotengine/godot/issues/28157
- Godot — suffixes d'import (boucles) : https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html
- Godot — AnimationNodeTransition : https://docs.godotengine.org/en/stable/classes/class_animationnodetransition.html
- Godot — AnimationNodeAnimation : https://docs.godotengine.org/en/stable/classes/class_animationnodeanimation.html
