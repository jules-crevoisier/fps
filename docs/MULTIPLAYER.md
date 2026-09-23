# Multijoueur, combat & netcode

Ce document décrit la fondation réseau : menu, host/join, autorité serveur,
vie, tir, zones de test, mort/respawn, et comment tester à 2 fenêtres.

---

## 1. Tester à 2 fenêtres dans Godot (le plus utile)

Pour jouer host + client sur la même machine, sans builder :

1. Ouvre le projet dans Godot 4.7.
2. Menu du haut : **Debug → Run Multiple Instances → Run 2 Instances**
   (dans certaines versions : *Déboguer → Exécuter plusieurs instances*).
3. Appuie sur **F5**. Deux fenêtres s'ouvrent.
4. Dans la **fenêtre 1** : clique **Héberger**.
5. Dans la **fenêtre 2** : laisse l'IP `127.0.0.1` et clique **Rejoindre**.

Astuce : pour décaler les fenêtres et garder la souris, tu peux régler
*Editor Settings → Run → Window Placement*. Chaque fenêtre capture la souris
quand elle a le focus (Échap pour libérer).

> Tu peux aussi exporter un `.exe` et lancer deux exécutables, ou lancer une
> instance en éditeur + un export.

---

## 2. Architecture réseau (autorité serveur)

API multijoueur haut-niveau de Godot (ENet), autoload **`Net`**
(`NetworkManager.gd`) : `Net.host()` / `Net.join(ip)`.

Modèle **serveur-autoritaire pour le combat** (pragmatique et robuste) :

| Système | Autorité | Détail |
|---------|----------|--------|
| Mouvement / caméra | **Client** propriétaire | Chaque joueur simule son perso ; répliqué via `MultiplayerSynchronizer`. Passe côté serveur en Phase 1 (netfox). |
| Vie (`Health`) | **Serveur** (peer 1) | Seul le serveur applique dégâts/soin/mort, puis réplique la valeur par RPC. Aucun soin n'est demandé par le client. |
| Armes (`Weapon`) | **Serveur** | Inventaire, munitions, rechargement, achat, ramassage, lâcher : tout est validé par le serveur (voir §3). |
| Capacités (`Abilities`) | **Serveur** | Charges, cooldowns et ultime sont comptés côté serveur ; le propriétaire prédit pour la réactivité. |
| Armes au sol | **Serveur** | Le serveur attribue un identifiant, fait apparaître et disparaître l'arme chez tous. |
| Zones dmg/heal | **Serveur** | Appliquées uniquement côté serveur. |
| Spawn / équipes / agent / respawn | **Serveur** | `GameWorld` assigne équipe et agent (répliqués au spawn), place au spawn, respawn après mort. |

### Règles réseau (à respecter dans tout nouveau code)

- Les nœuds de gameplay `Health`, `Weapon` et `Abilities` ont le **serveur** comme
  autorité (fixé dans `PlayerController._enter_tree`). Le corps du joueur garde
  son propriétaire comme autorité (synchro du mouvement).
- Requête client → serveur : RPC `any_peer` qui transmet à une méthode
  `_server_*(sender_id, ...)`. Celle-ci vérifie **toujours** que `sender_id` est
  le propriétaire du joueur, puis valide chaque argument.
- Serveur → client : RPC `authority` (le moteur refuse tout autre émetteur).
- Le serveur ne renvoie l'état au propriétaire que quand il **refuse** une action :
  une synchro après une action acceptée arriverait en retard et effacerait les
  actions prédites entre-temps.
- Si le serveur disparaît, le client revient au menu avec le motif affiché.

L'autorité de chaque joueur est fixée **de façon identique sur tous les pairs**
dans `PlayerController._ready` (basée sur le nom du nœud = id du peer). La vie est
ensuite **re-forcée sur le serveur** (sinon le réglage récursif de l'autorité du
joueur l'écraserait — piège classique de Godot).

Les clients **demandent leur spawn** une fois leur map chargée
(`_request_spawn` RPC) pour éviter la course « le serveur spawn avant que le
spawner du client existe ».

---

## 3. Tir hitscan (type BO2)

`Weapon.gd` + `WeaponConfig.gd` (ressource `resources/weapons/default_rifle.tres`).

- **Hitscan** : balle instantanée (raycast), comme la plupart des armes de BO2.
- **Client** : prédit le tir (chargeur, traceur, recul) puis envoie origine,
  directions et ID d'arme au serveur.
- **Serveur** : refuse le tir si l'expéditeur n'est pas le propriétaire, si le
  tireur est mort, si l'arme n'est pas celle qu'il a en main, si le chargeur est
  vide ou en rechargement, si la cadence dépasse celle de l'arme (seau de jetons,
  rafale de 2), ou si l'origine est à plus de 3 m de sa tête / les directions
  sont invalides (`ShotValidator`). Les tirs acceptés sont mis en **file** et
  résolus dans `_physics_process` ; les refus sont comptés (`rejected_shots`).
- **Damage falloff** : dégâts pleins jusqu'à `falloff_start`, puis chute linéaire
  jusqu'à `damage_min` à `falloff_end`.
- **Headshot** : `headshot_mult` si l'impact touche le haut de la capsule.
- **Munitions / rechargement** : `mag_size`, `reserve_ammo`, `reload_time`.
- **ADS** : `aim_fov` (clic droit), dispersion réduite en visée.

Paramètres clés (dans le `.tres`) : `damage`, `fire_rate`, `range`, `automatic`,
`spread_hip` / `spread_aim`, `mag_size`, `reload_time`.

---

## 4. Système de vie & test

`Health.gd` (enfant `Health` du joueur) :
- `max_health`, régénération après `regen_delay` à `regen_rate` (façon CoD).
- Signaux `health_changed`, `died`, `respawned` (branchés au HUD).

Pour **tester la vie**, la map 1v1 contient deux zones (visibles en couleur) :
- **Zone rouge** = `DamageZone` (`damage_per_second`) : entre dedans, ta vie chute.
- **Zone verte** = `HealZone` (`heal_per_second`) : entre dedans, tu te soignes.

Mort → écran « ÉLIMINÉ » → respawn automatique après `respawn_delay` (3 s) au
spawn de ton équipe.

---

## 5. Map 1v1 / 2v2 (goulag)

`scenes/levels/arena_1v1.tscn` : petite arène symétrique générée par
`GulagBuilder.gd` (sol, murs, couvertures, zones dmg/heal). Les **spawns** sont
4 `Marker3D` (`SpawnPoints`) avec une métadonnée `team` (0 ou 1). `team_count`
sur `GameWorld` gère 1v1 / 2v2.

---

## 6. Tick & compétitif

Le tick de simulation = le tick **physique** de Godot, réglé dans
`project.godot` :

```
[physics]
common/physics_ticks_per_second=60
```

- **60 Hz** : valeur par défaut, correcte pour commencer.
- Pour un feeling **plus compétitif**, monte à **128** (référence CS) — change
  `physics_ticks_per_second` à `128`. La logique de mouvement et de combat
  tourne déjà dans `_physics_process`, donc elle suit le tick automatiquement.
- Côté réseau, le `MultiplayerSynchronizer` réplique à la fréquence configurable
  (propriété *Replication Interval* du nœud) ; laisse 0 pour « chaque frame ».

### Limites actuelles (honnêteté)

Ce n'est **pas encore** un netcode compétitif complet :
- Le **mouvement** reste client-autoritaire (chaque joueur a raison sur sa
  position) : c'est le chantier P1.1-P1.2 de la roadmap (netfox).
- Les hits sont validés serveur mais **sans rembobinage** des positions selon le
  ping de l'attaquant (pas de lag comp, P1.3). En LAN / faible latence, c'est correct.
- Un joueur qui rejoint en cours de partie ne voit pas les armes déjà au sol.

### Test réseau automatique (2 processus)

`tools/net_smoke.gd` lance un hôte et un client headless sur le terrain
d'entraînement : le client tire 3 fois légitimement puis tente 4 triches (arme non
possédée, origine à 50 m, rafale au-delà de la cadence, tir usurpé au nom de
l'hôte). L'hôte affiche `NET_SMOKE_RESULT ok=true ...` si tout est conforme.

```bash
godot --headless --path . -s res://tools/net_smoke.gd -- --role=host &
sleep 3; godot --headless --path . -s res://tools/net_smoke.gd -- --role=client
```

---

## 7. Réglages type FPS (CoD / Valo / CS)

- **Sensibilité / FOV** : `MovementConfig` (`mouse_sensitivity`, `base_fov`),
  `WeaponConfig.aim_fov` pour le zoom ADS.
- **Armes** : duplique `default_rifle.tres` pour créer des profils (SMG rapide,
  sniper gros dégâts, etc.) — voir §3.
- **Tick** : §6.
- **Vie / régen** : `Health` (`max_health`, `regen_delay`, `regen_rate`).
