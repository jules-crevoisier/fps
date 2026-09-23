# Roadmap — du prototype au shooter en ligne « qualité AAA »

*Validée le 23/09/2026 (format corrigé en 4v4 + Duel/Duo). Mise à jour le même
soir : **direction artistique changée** (cel-shading peint et coloré façon
Borderlands, voir §2 et Phase 3) et avancement coché au §6. Journal au §12.
Recherches web et audit du code : sources au §11.*

---

## 0. Ce que « triple A » veut dire ici

Un AAA, c'est des centaines de personnes et des dizaines de millions. Ici, un seul
producteur (Claude) écrit le code et les shaders et fabrique les assets ; toi, tu
valides, tu fournis ce qui demande un compte ou un paiement, et tu playtestes. On ne
vise donc pas la **quantité** d'un AAA, on vise ses **standards**, sur un périmètre
tenu :

- **Ressenti** : mouvement, tir, son et retours de touche au niveau des meilleurs.
- **Fiabilité en ligne** : serveurs dédiés qui ont le dernier mot, prédiction
  client, compensation de lag. Plus jamais de « je l'avais touché sur mon écran ».
- **Lisibilité** : repérer un ennemi et comprendre la situation en 100 ms, même en
  plein effet.
- **Finition** : chaque écran a ses états (chargement, vide, erreur, focus manette),
  60 fps sur Steam Deck, aucun crash qui passe inaperçu.
- **Respect du joueur** : tous les agents gratuits, cosmétiques seulement, aucune
  loot box, bots toujours signalés.

Contenu du lancement volontairement serré : **6 agents, 10 armes, 4 maps 4v4 +
2 arènes de duel, 5 modes**.
Un contenu court et parfait vaut mieux qu'un contenu large et bancal. C'est la leçon
de tous les shooters fermés entre 2024 et 2026 (§10).

---

## 1. Vision et piliers

**Pitch** : un shooter 4v4 en cel-shading peint et encré gras, façon Borderlands,
où l'on glisse, plonge et roule entre les balles. Arène nerveuse en partie rapide, manches tactiques en classé, et
des duels 1v1 et 2v2 pour le skill pur.

1. **Le mouvement fait l'identité.** Slide-cancel, dolphin dive, roulade qui annule
   l'étourdissement de chute : aucun autre shooter n'offre ça. Le TTK, les maps et les
   capacités sont réglés pour le mettre en valeur, pas pour le neutraliser.
2. **Peint au soleil, encré gras — et l'ennemi toujours visible.** Un monde saturé et
   peint à la main (rouille, sable, conteneurs vifs sous un grand ciel bleu), des
   contours encrés épais. L'ennemi porte un contour **magenta** ou **citron** (au
   choix, pensé pour les daltoniens) : deux teintes interdites au décor, donc
   toujours uniques, même dans un monde très coloré.
3. **Des duels courts mais jouables.** TTK de 350 à 500 ms : assez court pour punir,
   assez long pour qu'un dash ou un mur change l'issue.
4. **Les capacités préparent le combat, elles ne le gagnent pas.** Se repositionner,
   couper une ligne de vue, se soigner hors combat. Chacune a un contre-jeu.
5. **Trois rythmes, un seul jeu.** L'Arène 4v4 (TDM, Hardpoint, respawn) pour le fun,
   la Tactique 4v4 (Recherche & Destruction + économie) pour la tension, et le
   Duel 1v1 / Duo 2v2 pour le skill pur (mouvement + visée, sans capacités). Le
   Classé 4v4 alterne Hardpoint et R&D, comme la ligue pro de Call of Duty, qui se
   joue elle aussi en 4v4.

---

## 2. Décisions verrouillées

| Sujet | Décision | Pourquoi |
|---|---|---|
| Producteur | Claude fait le jeu ; toi, tu valides et fournis ce qui demande un compte ou un paiement | Brief |
| Plateforme | PC Steam + Steam Deck | Sur console, Godot passe par des portages tiers coûteux |
| Cœur | Arène en casual, Tactique en classé, Duel/Duo à côté | Brief |
| Format | **4v4** pour l'Arène, la Tactique et le Classé ; **Duel 1v1** et **Duo 2v2** en plus | Ton choix. Le 4v4 est le format de la ligue CoD : maps compactes, files vite remplies. Le 1v1 et le 2v2 mettent le mouvement en vitrine et vivent avec très peu de joueurs |
| Ton visuel | Cel-shading **peint et coloré, façon Borderlands** : ciel bleu à gros nuages, textures peintes, décor dense, encrage épais ; UI sombre à bandeaux rouges au pinceau | Tes planches de référence (Wasteland, Cargo Ship). La première piste « encre et papier » désaturée a été abandonnée le 23/09 |
| Modèle éco | F2P cosmétique envisagé, tranché plus tard | Brief : le code doit permettre le F2P sans l'imposer |
| Moteur | Godot 4.7 (Forward+, Jolt, GDScript) | Existant ; 4.7.2 disponible |

Le détail de la direction (palettes par carte, matières peintes, règles de
lisibilité, UI) est tenu dans le document de direction artistique v2. La technique
déjà construite (contours à l'encre, rendu toon, tokens d'UI) est réutilisée.

---

## 3. État des lieux (audit du 23/09/2026)

*Instantané de départ, conservé pour mémoire. L'état actuel est au §6 (cases
cochées) et au §12 (journal).*

Environ 5 100 lignes de GDScript, bien organisées pour un prototype, mais rien n'est
encore prêt pour du jeu en ligne public.

| Système | Fichiers | Prêt (0-5) | Constat |
|---|---|---|---|
| Mouvement | `PlayerController.gd` + 9 états | 3 | Riche et réglable, mais **le client décide de sa position** |
| Tir et armes | `Weapon.gd`, `WeaponConfig.gd`, 8 `.tres` | 2 | Piloté par les données, mais **exploitable** (voir plus bas) |
| Agents | `scripts/agents/**` | 1,5 | 2 agents, 4 capacités provisoires, non répliquées |
| Modes | `GameMode`, `TDMMode`, `HardpointMode` | 2,5 | Le serveur décide, c'est propre |
| Réseau | `NetworkManager`, `GameWorld` | 1 | ENet brut : ni serveur dédié, ni authentification, ni compensation de lag |
| UI | `GameHUD` (556 l.), `MainMenu` (432 l.) | 2,5 | Fonctionne ; fichiers trop gros ; refonte BD en cours, non commitée |
| Maps | `*Builder.gd` | 1 | Boîtes générées par code, aucun art |
| Contenu | `assets/` | 0 | Ni modèle, ni texture, ni shader, ni son |
| Tests | — | 0 | Ni framework, ni test |

**Failles critiques à fermer en premier** (un client modifié pouvait les exploiter ;
toutes fermées en P0.4 et vérifiées par `tools/net_smoke.gd`) :

1. `Weapon.request_fire` accepte n'importe quel ID d'arme, origine et direction. On
   peut tirer au sniper sans l'avoir, depuis n'importe où (`Weapon.gd:259-276`).
2. Aucune limite de cadence côté serveur (`Weapon.gd:265-277`).
3. `Health.request_heal(amount)` n'a pas de borne : soin infini (`Health.gd:52-55`).
4. Le ramassage d'arme est 100 % local (`WorldWeapon.gd:89-106`).

**Risques légaux** : les fichiers `resources/weapons/*.tres` portent les noms des
armes de Valorant (classic, sheriff, vandal, operator…). Ces noms n'apparaissent pas
en jeu, mais ils sont inclus dans le build. La licence OFL de la police Lato n'est
pas jointe.

---

## 4. Chiffres de départ (à régler en playtest)

Ce sont des points de départ tirés des jeux de référence (§11), pas des vérités. Ils
deviennent des **tests automatiques** : si un patch fait sortir une arme de sa
fourchette, la CI le signale.

| Réglage | Valeur | Référence |
|---|---|---|
| TTK optimal des armes principales (corps) | 350-500 ms | BO6/BO7 ≈ 165-350 ms, Valorant (Vandal) ≈ 310 ms ; plus long ici pour que les capacités comptent |
| TTK avec headshots | 250-350 ms | |
| Pistolet | 550-700 ms ; Magnum : 2 têtes ou 3 corps | |
| Pompe | one-shot jusqu'à 4 m, **gerbe fixe** (sans aléatoire) | Apex, Overwatch |
| Sniper | one-shot à la tête et au haut du torse ; sprint-to-fire ≥ 300 ms | BO6 |
| Pénalités de mouvement | slide-to-fire ≈ 380 ms, dive-to-fire ≈ 460 ms, dispersion accrue en l'air | BO6 saison 2 |
| Recul | premières balles selon un motif fixe, puis déviation pseudo-aléatoire | Valorant |
| Régénération | après 4 s | BO6 : 3,5 s |
| Joueurs | 4v4 ; Duel 1v1 ; Duo 2v2 | |
| TDM | 50 éliminations ou 10 min ; respawn 3 s | CoD en 6v6 : 75, ramené au 4v4 |
| Hardpoint | 250 pts ou 10 min ; zone de 60 s annoncée 15 s avant ; respawn 5 s | Ligue CoD (4v4) : 250 pts |
| R&D | premier à 6 manches, changement de camp après 5 ; manche de 90 s ; bombe de 45 s | Ligue CoD 2026 (4v4) |
| Duel / Duo | premier à 6 manches ; manche de 40 s puis zone centrale à capturer ; même équipement imposé pour tous, qui change toutes les 2 manches ; pas de capacités ni de régénération pendant la manche | Inspiré du Gunfight de CoD (2v2) ; notre choix, à valider en playtest |
| Économie R&D | victoire 3000 ; défaite 1900/2400/2900 ; élimination 200 ; pose 300 (adapté à nos prix) | Valorant |
| Protection au spawn | ≤ 1 s, annulée au premier tir | |
| Tick serveur | 60 Hz ; rembobinage de la lag comp plafonné à 200 ms | Overwatch 63 Hz, CS2 64 Hz |
| Équilibrage des agents | taux de victoire hors miroir entre 47 et 53 % | Overwatch, Valorant |
| Performance | 144 fps en 1080p (config recommandée) ; 60 fps sur Steam Deck en 800p | Steam Deck Verified exige 30 |

---

## 5. Stack technique retenue

| Besoin | Choix | Écarté (pourquoi) |
|---|---|---|
| Netcode | **netfox** : tick fixe, prédiction client et réconciliation, interpolation, lag comp par rejeu, filtre de visibilité | `MultiplayerSynchronizer` seul (ni prédiction, ni lag comp) |
| Serveur de match | Export Godot « Dedicated Server » headless Linux, image `debian:trixie-slim`, 1 conteneur par match | Plusieurs matchs par process (un crash les tue tous) ; Alpine (libc incompatible) |
| Hébergement des serveurs | Pool fixe sur **Dokploy** (ports UDP ouverts dans le compose), puis **Edgegap** pour plusieurs régions | Hathora (fermé en mai 2026), Rivet (reconverti dans l'IA), W4 Cloud (en sommeil), Agones (Kubernetes trop lourd pour démarrer) |
| Comptes, amis, groupes, matchmaking, classements | **Nakama** (Apache-2.0, Postgres) sur Dokploy | Backend maison |
| Steam | **GodotSteam** (Codeberg, GDExtension pour Godot 4.4+) : authentification, overlay, voix, succès | — |
| Estimation du niveau | **OpenSkill** : gère les équipes et les tailles inégales, licence libre | TrueSkill (licence restrictive), Glicko-2 (pensé pour le 1v1) |
| Anti-triche | Autorité serveur, filtre de visibilité, contrôle des entrées, signalements ; EAC via EOS à étudier plus tard | Chiffrement du PCK (clé extraite en quelques millisecondes), confiance dans le client |
| Crashs | **sentry-godot** 2.x (Godot 4.5+) | — |
| Télémétrie | **Talo** auto-hébergé sur Dokploy (événements, stats, Steam) | GameAnalytics (données chez un tiers) |
| Tests | **gdUnit4** (Godot 4.5-4.7, scene runner, CI) | GUT (valable, moins outillé pour la CI) |
| CI et build | GitHub Actions + image godot-ci 4.7.x + steam-deploy | — |
| Voix | Voix Steam via GodotSteam | Vivox (pas de SDK Godot) |

Règle de sécurité : le client est considéré comme **open source**, car gdsdecomp
reconstitue tout le projet à partir d'un build. Rien de secret côté client, et le
code serveur est exclu des exports client.

---

## 6. Les phases

Chaque phase a un **critère de sortie** mesurable. On ne passe pas à la suivante tant
qu'il n'est pas atteint. Les numéros (P0.1…) servent au suivi.

### Phase 0 — Assainir les fondations

But : pouvoir avancer vite sans rien casser, et fermer les failles.

- [x] **P0.1** Décider du sort du travail BD non commité (HUD, menu, thème), puis le committer sur sa propre branche
- [x] **P0.2** gdUnit4 + lancement headless (`Godot --headless`) + premiers tests : dégâts, falloff, headshot, TTK par arme, santé et régénération, score des modes
- [x] **P0.3** CI GitHub Actions : import, tests, exports Windows, Linux et serveur dédié *(à confirmer au premier push)*
- [x] **P0.4** Fermer les 4 failles :
  - le serveur vérifie que le tireur possède bien l'arme ;
  - l'origine du tir est bornée autour de la tête du tireur ;
  - la cadence est limitée côté serveur ;
  - le serveur calcule lui-même le soin (le client n'envoie plus de montant) ;
  - le ramassage d'arme passe par le serveur.
- [x] **P0.5** Renommer les ressources d'armes (identifiants neutres) ; ajouter `THIRD_PARTY_LICENSES` (OFL…)
- [x] **P0.6** Indépendance au framerate : toute la simulation tourne au tick physique fixe (60 Hz, réglé explicitement), cadence de tir lissée sur le tick (pas de balles perdues entre deux ticks) ; le lissage visuel des autres joueurs arrive avec l'interpolation de netfox (P1.2)
- [ ] **P0.7** Découper `GameHUD` et `MainMenu` en composants ; capacités 100 % définies en données (`.tres`) *(en partie : HUD découpé en composants ; capacités encore définies en code)*
- [ ] **P0.8** Textes passés par `tr()` (préparation FR/EN)
- [x] **P0.9** Scène de benchmark + compteur de perf (fps, 1 % low, draw calls) pour mesurer chaque phase

**Sortie** : CI verte, 4 failles fermées avec un test chacune, benchmark de référence enregistré.

### Phase 1 — Netcode compétitif et serveur dédié

But : un jeu juste à 100 ms de ping.

- [ ] **P1.1** **Essai de netfox (1 sprint)** : faire passer la state machine de mouvement (slide, dive, roll, stun) en prédiction + réconciliation. Décision à la fin : netfox ou couche maison
- [ ] **P1.2** Mouvement décidé par le serveur, entrées horodatées au tick, correction douce côté client, interpolation des autres joueurs
- [ ] **P1.3** Lag comp pour le hitscan (rembobinage ≤ 200 ms), hitbox tête, corps et membres
- [x] **P1.4** Tout répliquer : capacités (mur, dash), identité d'agent et équipe, armes au sol, économie
- [ ] **P1.5** Filtre de visibilité : le serveur n'envoie pas la position d'un ennemi hors de vue (anti-wallhack)
- [x] **P1.6** Serveur dédié headless *(image construite et testée par la CI au premier push)* :
  - `Dockerfile` multi-étapes (build en CI, runtime debian-slim) ;
  - utilisateur non-root, UDP 7777 ;
  - port TCP de santé pour le `HEALTHCHECK` ;
  - `docker-compose.yml` pour tester en local.
- [x] **P1.7** Jetons de connexion : seul un joueur assigné au match peut entrer ; vérification de version entre client et serveur
- [ ] **P1.8** Reconnexion après une coupure ; fin de match propre si le serveur tombe *(en partie : retour au menu avec message si le serveur tombe)*
- [ ] **P1.9** Banc de test réseau : latence, gigue et perte simulées (netem dans Docker), clients headless automatisés *(en partie : test hôte/client en 2 processus, partie de bots automatisée ; pas encore de latence simulée)*
- [x] **P1.10** **Bots** (navmesh, combat, objectifs), toujours affichés « BOT » : entraînement, remplissage des parties, tests de charge

**Sortie** :
- 8 joueurs (bots compris) tournent à 60 Hz dans un seul conteneur ;
- à 100 ms de ping et 1 % de perte, pas d'effet élastique en jeu normal, et les tirs qui touchent à l'écran sont validés ;
- CPU et bande passante par match mesurés et notés.

### Phase 2 — Trouver le fun en gray-box

But : que le jeu soit **amusant avec des cubes**. S'il ne l'est pas à ce stade, l'art n'y changera rien.

- [x] **P2.1** Arsenal de 10 armes, chacune la meilleure dans au moins une tranche de distance ; table TTK × distance générée depuis les `.tres` ; tests des fourchettes du §4
- [x] **P2.2** Recul à motif fixe, gerbes fixes, délais sprint/slide/dive-to-fire, dispersion accrue en l'air
- [x] **P2.3** **6 agents** sur 3 rôles (entrée, contrôle, soutien) ; environ 4 capacités chacun, avec un contre-jeu écrit pour chaque ; l'ultime se charge aux dégâts, aux objectifs et aux éliminations (plus au temps)
- [x] **P2.4** Modes : TDM, Hardpoint (zone annoncée), **Recherche & Destruction** avec phase d'achat, pose et désamorçage, changement de camp ; **Duel 1v1** et **Duo 2v2** (manches courtes, équipement imposé tournant, zone d'overtime), qui prolongent le goulag actuel
- [ ] **P2.5** Choix des spawns pondéré (pression ennemie, lignes de vue), anti spawn-trap, protection au spawn *(en partie : protection au spawn, spawns par rôle en R&D, spawn le plus éloigné des ennemis sur la Wasteland)*
- [x] **P2.6** **4 maps 4v4 + 2 arènes Duel/Duo** en gray-box, dans des scènes éditables (fin des maps générées par code) :
  - maps 4v4 compactes : Highguard a fermé en partie parce que ses maps étaient trop grandes pour ses équipes ;
  - 3 couloirs par map ;
  - lignes de vue calées sur les portées des armes ;
  - verticalité pensée pour le slide et la plongée ;
  - chaque map 4v4 accueille TDM, Hardpoint et R&D ; les arènes sont symétriques et petites.
- [ ] **P2.7** Parties personnalisées (réglages de mode, bots, équipes) *(en partie : mode, carte, bots et difficulté au menu)*
- [ ] **P2.8** Télémétrie Talo et outil de heatmap :
  - **par élimination** : positions, arme, distance, état de mouvement, capacité active, temps écoulé depuis le spawn ;
  - **par match** : taux de victoire par camp et par zone, morts moins de 3 s après le spawn, agents choisis.
- [ ] **P2.9** Playtests : 2 sessions internes d'1 h par semaine, 1 session externe par mois, questionnaire court

**Sortie** :
- playtests notés « fun » à 4/5 ou plus ;
- toutes les armes dans leur fourchette ;
- en R&D, chaque camp gagne entre 45 et 55 % des manches sur chaque map ;
- aucune arme au-dessus de 30 % d'utilisation.

### Phase 3 — Direction artistique peinte et production

But : un look qui arrête le regard sur une capture d'écran, sans jamais nuire à la lisibilité.

**Direction** (v2, à partir de tes planches Wasteland et Cargo Ship) : « Peint au
soleil, encré gras ». Grand ciel bleu à cumulus peints, soleil chaud, ombres
bleu-violet (jamais grises), matières saturées peintes à la main (rouille, sable,
tôle ondulée, bois, conteneurs rouges, bleus, orange et blancs), décor dense
(voitures, pompes, panneaux FUEL/GAS, grues, derricks, cabanes à auvents), encre
peinte dans les textures et silhouettes encrées à l'écran. Lisibilité : contour
ennemi magenta ou citron, teintes interdites au décor.

Références : tes planches (Wasteland, Cargo Ship) ; **Borderlands 3** et **Tiny
Tina's Wonderlands** (encre peinte dans les textures) ; **Valorant** et
**Overwatch** (lisibilité des silhouettes et des couleurs ennemies).

*Première piste abandonnée le 23/09 : « encre et papier » désaturé (XIII, Sin
City). Le rendu toon, les contours et l'arme en main construits pour elle sont
repris.*

Rendu :
- [ ] **P3.1** Shader toon peint : rampe à 3 bandes avec bord chaud, ombres bleu-violet, textures peintes en triplanaire *(en cours)*
- [x] **P3.2** Contours :
  - persos, arme en main et objets : coque inversée, normales lissées, épaisseur constante à l'écran ;
  - décors : passe post-process sur la profondeur et les normales ;
  - épaisseur variable, façon plume.
- [ ] **P3.3** Textures peintes générées par script (rouille, tôle, bois, sable, béton, pont de navire, conteneurs), encre des arêtes cuite dedans ; ciel bleu à cumulus peints *(en cours)*
- [ ] **P3.4** *(en cours)* Éclairage : LightmapGI + 1 lumière directionnelle ; ombres dynamiques seulement sur l'arme en main, pour qu'aucun réglage graphique ne donne d'information en plus (règle Valorant)
- [ ] **P3.5** *(en cours)* Lisibilité :
  - contour ennemi coloré (**magenta** ou **citron**, au choix) bordé d'encre ; alliés en contour encre simple ;
  - ces deux teintes interdites dans les décors ; forme doublant toujours la couleur ;
  - budget d'opacité pour les effets ; fumées à bords nets.
- [x] **P3.6** Arme en main : FOV séparé dans le vertex shader, pas d'ombre portée, animation procédurale (balancement, recul, rechargement) en plus des clips
- [ ] **P3.7** Préréglages graphiques, dont un **Steam Deck** (FSR 1 à 0,75, sans SSR/SSIL/SDFGI, shader baker)

Production :
- [x] **P3.8** Pipeline Blender scripté (`bpy`) vers glTF : armes, kits modulaires de maps, props, normales lissées pour les contours
- [ ] **P3.9** Persos : 6 agents sur le mannequin CC0 de Quaternius (vêtements ajustés, équipement, une silhouette par rôle, couleur par agent), 46 animations CC0, bras FPS *(modèles faits ; intégration en jeu en cours ; qualité encore sommaire)*
- [ ] **P3.10** Art pass : les deux cartes phares **Cargo Ship** et **Wasteland** d'après tes planches, et repeint des 6 cartes existantes avec 41 décors 3D (volumes validés inchangés) *(en cours)*
- [ ] **P3.11** Effets : flipbooks à environ 12 fps (flash de bouche, impacts) ; onomatopées sur les éliminations (≤ 300 ms, jamais sur le réticule) *(en partie : flash de bouche, onomatopées, marqueur de touche, direction des dégâts, vignette de vie basse ; impacts à faire)*
- [x] **P3.12** Son, la moitié du ressenti *(94 effets générés par synthèse, ambiances par carte, musiques de match ; réverbération par zone à faire)* :
  - armes en 3 couches (mécanique, corps, queue selon le lieu) ;
  - pas différents selon la surface, pour jouer à l'oreille ;
  - capacités en version alliée et en version ennemie ;
  - sons de touche, de tête et d'élimination distincts, déclenchés sur confirmation du serveur ;
  - mixage par bus et réverbération par zone ;
  - musique de menu et de fin de manche.
- [ ] **P3.13** UI et HUD *(v1 papier faite ; v2 sombre à bandeaux rouges au pinceau en cours)* :
  - centre de l'écran dégagé ;
  - killfeed en cartouches de récit ; fin de manche en planche de BD ;
  - tous les états (chargement, vide, erreur, focus manette) ;
  - texte d'au moins 12 px en 800p ;
  - police de titrage sous licence OFL (Blambot exige une licence payante pour les jeux vidéo).

**Sortie** : une « image cible » validée par toi sur une map ; budgets de perf du §4
tenus en config recommandée et sur Steam Deck.

### Phase 4 — Plateforme en ligne

But : lancer le jeu, cliquer sur « Jouer » et être en match en moins d'une minute.

- [ ] **P4.1** Steamworks (app ID) + GodotSteam : connexion Steam, puis session Nakama
- [ ] **P4.2** Nakama + Postgres sur Dokploy (compose, healthchecks, sauvegardes, restauration testée)
- [ ] **P4.3** Amis Steam, groupes, invitations
- [ ] **P4.4** Matchmaking :
  - OpenSkill (niveau, ping, région, taille du groupe) ;
  - files **Arène 4v4**, **Tactique 4v4**, **Duel 1v1**, **Duo 2v2**, **Classé 4v4** (ouvert quand la population le permet ; un Classé Duo 2v2 peut venir avant, il demande 4 fois moins de joueurs), **Entraînement contre bots**, **Personnalisée** ;
  - bots signalés pour compléter les parties, en casual seulement.
- [ ] **P4.5** Attribution des serveurs : pool Dokploy, puis Edgegap quand il faut plusieurs régions
- [ ] **P4.6** Classé :
  - accessible après un certain nombre de victoires ;
  - 5 matchs de placement ;
  - niveau caché + rangs visibles ;
  - pas de perte de rang avec l'inactivité, mais replacement après une longue absence ;
  - pénalités d'abandon ;
  - **points rendus** si un adversaire est banni pour triche.
- [ ] **P4.7** Anti-triche : détection des anomalies (cadence, visée qui saute d'une cible à l'autre, vitesse), outil de revue des signalements, bans par Steam ID
- [ ] **P4.8** Social : signalement, mute, filtre du chat, recommandations entre joueurs (40 % de matchs perturbés en moins chez Overwatch), voix en push-to-talk
- [ ] **P4.9** Exploitation : Sentry, logs, tableau de bord, mode maintenance, mise à jour forcée si la version est incompatible

**Sortie** : test de charge à 50 joueurs simultanés (bots et clients headless) ;
matchmaking en moins de 60 s à la population visée ; mise à jour du backend sans coupure.

### Phase 5 — Méta, progression, boutique

But : une raison de revenir le lendemain, sans jamais vendre de puissance.

- [x] **P5.1** Tutoriel interactif du mouvement (slide-cancel, plongée, roulade anti-stun) + **contre-la-montre de mouvement** avec classement
- [x] **P5.2** Stand de tir, tutoriel par agent, premiers matchs contre des bots *(terrain d'entraînement : stand de tir, coin capacités ; bots au menu)*
- [ ] **P5.3** Niveau de compte, maîtrise d'arme (camos d'encre), maîtrise d'agent, défis quotidiens et hebdomadaires
- [ ] **P5.4** Carte de joueur, bannières et tags en cases de BD ; historique et statistiques des matchs ; résumé de fin de match en planche
- [ ] **P5.5** Killcam (depuis l'historique du serveur), puis replays
- [ ] **P5.6** *Si le F2P est confirmé* :
  - une seule monnaie, avec les prix en euros affichés ;
  - un pass qui n'expire jamais ;
  - aucune loot box payante ;
  - tous les agents gratuits ;
  - aucun cosmétique ne nuit à la lisibilité (la couleur des ennemis reste prioritaire).

**Sortie** : 5 nouveaux testeurs terminent le tutoriel et leur premier match sans aide.

### Phase 6 — Qualité de sortie et lancement

- [ ] **P6.1** Perf : configs minimale et recommandée, temps de chargement, 1 % low, vérification Steam Deck
- [ ] **P6.2** Accessibilité :
  - couleur des ennemis au choix, sous-titres, taille de l'UI ;
  - réglages de secousse et de balancement de la caméra ;
  - choix entre maintien et bascule pour les actions ;
  - audio mono ;
  - aide à la visée réglable à la manette.
- [ ] **P6.3** Localisation FR/EN (puis ES, DE, PT-BR)
- [ ] **P6.4** Juridique :
  - CGU/EULA ;
  - politique de confidentialité RGPD (Nakama, Talo, Sentry) ;
  - classification IARC ;
  - crédits et licences ;
  - recherche de marque sur le nom du jeu.
- [ ] **P6.5** Steam :
  - page du jeu avec des visuels en graphic novel, trailer capturé en jeu ;
  - **Steam Playtest** ouvert par créneaux ;
  - démo pour un **Next Fest** ;
  - puis décision entre Early Access et 1.0.
- [ ] **P6.6** Communauté : Discord, devlog, press kit, signalement de bugs en jeu
- [ ] **P6.7** Plan de fin de vie : version serveur communautaire prête (leçon de Knockout City et Splitgate)

**Sortie** : checklist de lancement entièrement validée.

### Phase 7 — Jeu en service

- Patchs d'équilibrage espacés (toutes les 4 à 6 semaines), guidés par la télémétrie et les limites du §4 ; serveur de test public
- Saisons : 1 agent ou 1 map par saison, avec des cosmétiques ; modes temporaires
- Surveillance anti-triche et modération continues

---

## 7. Comment je fabrique les assets

Le style peint repose sur les couleurs, le ciel, les contours et la densité du
décor : tout cela se produit bien par code. Les modèles 3D générés par script
restent en revanche plus sommaires que tes planches.

| Asset | Méthode (réelle) | Limite honnête |
|---|---|---|
| Shaders, effets, UI | Code, je fais tout | — |
| Textures peintes | Générées par script (numpy), encre cuite dedans | Moins riches qu'un peintre de textures |
| Armes (7), décors (41), kits de cartes | Blender 5.2 scripté (`bpy`), export glTF | Formes massives, peu de détail fin |
| Persos (6) + bras FPS | Mannequin CC0 de Quaternius, vêtements et équipement générés en Blender | Qualité prototype : pour s'approcher des planches, il faudra de meilleurs modèles (packs plus détaillés, génération 3D par IA avec ton compte, ou un artiste) |
| Animations | 46 animations CC0 (Quaternius) + animation procédurale de l'arme en main | Pas d'animation de fusil dédiée pour l'instant |
| Sons, ambiances, musiques | Synthèse par script (numpy/scipy), déterministe | Voix des agents : comédiens ou rien (pas de synthèse vocale sans licence) |

Chaque asset tiers est tracé dans `THIRD_PARTY_LICENSES`, avec sa source et sa licence.

---

## 8. Ce dont j'ai besoin de toi

- **Valider à chaque fin de phase**, surtout l'image cible de la Phase 3.
- **Me montrer des références visuelles** (comme tes planches) avant toute grosse production artistique : un mot comme « graphic novel » peut se lire de plusieurs façons.
- **Comptes et paiements**, car je ne peux ni créer de compte ni payer :
  - Steamworks (100 $ + infos fiscales) ;
  - Sentry ;
  - un VPS avec Dokploy ;
  - plus tard, Edgegap et un nom de domaine.
- **Téléchargements** : je te demande avant chaque pack (nom, source, taille).
- **Des humains pour playtester** : les bots ne diront jamais si c'est fun.
- **Un nom de jeu** : on peut le chercher ensemble ; la marque sera vérifiée en P6.4.

---

## 9. Risques et parades

| Risque | Parade |
|---|---|
| Pas assez de joueurs (première cause de fermeture) | Bots signalés, 4v4, Duel et Duo qui se lancent avec 2 à 4 joueurs, peu de files, Steam Playtest par créneaux, serveurs communautaires en réserve |
| netfox ne suit pas notre mouvement | Essai d'un sprint en P1.1 avec décision explicite ; plan B : couche maison |
| Un seul producteur, donc production lente | Contenu serré, kits modulaires, pipeline scripté, bases CC0 |
| Look « fait par un programmeur » | Tes références visuelles avant chaque grosse production, image cible validée par toi sur chaque carte, et de meilleurs modèles de base si les modèles générés restent trop sommaires |
| Triche (le client est lisible) | Le serveur décide de tout, filtre de visibilité, détection des anomalies |
| Marché des hero shooters saturé | Identité propre : mouvement, graphic novel franco-belge, humour cartoon (étoiles de stun) |
| Monétisation mal reçue | Règles de P5.6 ; aucun prix fixé avant d'avoir des joueurs |

---

## 10. Ce que le marché 2024-2026 nous apprend

- **Ceux qui tiennent** :
  - Marvel Rivals : héros gratuits, uniquement des cosmétiques, pass sans date d'expiration ;
  - Overwatch : relancé en 2026 après avoir écouté les joueurs ;
  - Deadlock : grosses mises à jour de contenu.
- **Ceux qui ont fermé** :
  - Concord : payant, héros génériques, fermé en 2 semaines ;
  - Spectre Divide : skins à 85-90 $, matchmaking cassé ;
  - XDefiant : détection des touches défaillante ;
  - Supervive : les joueurs ne restaient pas ;
  - Highguard : maps trop grandes pour du 3v3, perf PC, fermé en 45 jours ;
  - Splitgate 2 : identité perdue, passé sur des serveurs hébergés par les joueurs.
- **Ce que les joueurs sanctionnent** : les prix au lancement, trop de monnaies, le
  gratuit qui devient payant, les bots cachés, les effets illisibles, le gameplay qui
  dépend du framerate, la triche non traitée.
- **Gratuit ou payant, ça ne sauve rien à soi seul** : Arc Raiders a vendu à 40 $,
  Concord et Marathon ont échoué au même prix. Le jeu doit d'abord être fun.

---

## 11. Sources principales

**Marché**
- [Marvel Rivals : cosmétiques seulement, pass permanents](https://www.gamespot.com/articles/marvel-rivals-will-only-sell-cosmetics-will-let-players-keep-purchased-battle-passes-forever/1100-6528239/)
- [Fermeture de Spectre Divide](https://www.gamedeveloper.com/business/mountaintop-studios-shutting-down-after-debut-shooter-spectre-divide-falls-short)
- [Concord](https://en.wikipedia.org/wiki/Concord_(video_game)) · [Splitgate 2](https://en.wikipedia.org/wiki/Splitgate_2) · [Supervive](https://dotesports.com/supervive/news/supervive-shutting-down-february-2026) · [Highguard](https://www.vice.com/en/article/why-highguard-is-facing-so-much-backlash-from-players/)
- [Marvel Rivals : gameplay dépendant du framerate](https://www.pcgamer.com/games/third-person-shooter/marvel-rivals-fps-bug-puts-players-with-potato-pcs-at-a-disadvantage-and-thats-not-the-only-optimisation-issue-happening-right-now/)
- [Steam Playtest](https://partner.steamgames.com/doc/features/playtest) · [Fin de vie de Knockout City](https://www.pcgamer.com/knockout-city-sunset-gdc-talk/)
- [Loot boxes : Brésil 2026](https://iapp.org/news/a/brazil-s-digital-eca-rethinking-monetization-and-design-in-games)

**Game design et équilibrage**
- [BO6, notes de la saison 2 (délais slide/dive-to-fire, snipers)](https://www.callofduty.com/patchnotes/2025/01/call-of-duty-black-ops-6-season-02-patch-notes)
- [Comment Riot équilibre Valorant](https://playvalorant.com/en-us/news/dev/how-we-balance-valorant/) · [Équilibrage d'Overwatch](https://overwatch.blizzard.com/en-us/news/23917966/director-s-take-balancing-heroes-and-matchmaking/)
- [Level Design Book : équilibrage des maps](https://book.leveldesignbook.com/process/combat/balance) · [Maps CoD : la règle des 3 couloirs](https://www.gamesradar.com/how-to-build-a-great-call-of-duty-multiplayer-map-according-to-the-players-that-know-the-game-best/)
- [Réglages compétitifs CDL 2026](https://dotesports.com/call-of-duty/news/cdl-2026-competitive-settings) · [Recommandations Overwatch et toxicité](https://variety.com/2019/gaming/features/how-blizzard-reduced-toxic-behavior-with-overwatchs-endorsement-system-1203169999/)

**Rendu et direction artistique**
- [Valorant : shaders et lisibilité](https://www.riotgames.com/en/news/valorant-shaders-and-gameplay-clarity)
- [Hi-Fi Rush, GDC 2024](https://gdcvault.com/play/1034330/3D-Toon-Rendering-in-Hi) · [Guilty Gear Xrd, GDC 2015](https://www.gdcvault.com/play/1022031/GuiltyGearXrd-s-Art-Style-The) · [Contours ASW 2025](https://www.docswell.com/s/ASW_Academy/5LVY67-GG-Toonline-Eng)
- [Le style de Borderlands](https://www.destructoid.com/borderlands-explains-its-not-cel-shaded-actually-art-style/)
- [Godot : Compositor](https://docs.godotengine.org/en/stable/tutorials/rendering/compositor.html) · [godot4-cel-shader (MIT)](https://github.com/eldskald/godot4-cel-shader) · [Shader d'arme en main (CC0)](https://godotshaders.com/shader/first-person-view-model-shader-updated-for-godot-4-3/)
- [Compatibilité Steam Deck](https://partner.steamgames.com/doc/steamdeck/compat) · [Licences Blambot](https://blambot.com/pages/licensing)

**Technique**
- [Valorant : netcode et avantage du peeker](https://www.riotgames.com/en/news/peeking-valorants-netcode)
- [netfox](https://github.com/foxssake/netfox) · [documentation netfox](https://foxssake.github.io/netfox/latest/)
- [Godot : export serveur dédié](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html) · [Dokploy et UDP](https://github.com/Dokploy/dokploy/issues/934) · [Plugin Edgegap pour Godot](https://github.com/edgegap/edgegap-godot-plugin)
- [Fermeture de Hathora](https://www.gamedeveloper.com/business/stormgate-rushing-offline-mode-after-losing-server-access-to-an-ai-company)
- [Nakama](https://github.com/heroiclabs/nakama) · [SDK Godot de Nakama](https://github.com/heroiclabs/nakama-godot) · [GodotSteam](https://codeberg.org/godotsteam/godotsteam) · [OpenSkill](https://arxiv.org/abs/2401.05451)
- [gdsdecomp](https://github.com/GDRETools/gdsdecomp) · [sentry-godot](https://github.com/getsentry/sentry-godot/releases) · [Talo](https://github.com/TaloDev/godot) · [gdUnit4](https://github.com/godot-gdunit-labs/gdUnit4) · [godot-ci](https://github.com/abarichello/godot-ci)
- Notes de version Godot : [4.5](https://godotengine.org/releases/4.5/) · [4.6](https://godotengine.org/releases/4.6/) · [4.7](https://godotengine.org/releases/4.7/)

---

## 12. Journal

**23/09/2026**
- Brief, recherches (marché, équilibrage, rendu, stack en ligne), audit du code, roadmap.
- Format corrigé : 4v4 + Duel 1v1 et Duo 2v2.
- **Phase 0** : tests (gdUnit4) et CI, 8 failles réseau fermées, armes renommées,
  licences, tick fixe, outils de perf. Test réseau à 2 processus.
- **Vague 2** : rendu toon et contours, 7 armes 3D et arme en main, son (94 effets),
  modes R&D (bombe, économie) et Duel/Duo, 10 armes équilibrées, 6 agents
  (24 capacités validées par le serveur).
- **Vague 3** : couche d'entrées commune, bots (navigation, visée par difficulté,
  objectifs), 6 cartes au plan distinct, interface v1.
- **Vague 4** : serveur dédié (Docker, santé, jetons, version), terrain
  d'entraînement, ambiances et musiques, retours de combat, 6 personnages.
- **Changement de direction artistique** : la piste « encre et papier » désaturée
  ne correspondait pas à ce que tu voulais ; passage au cel-shading peint et coloré
  façon Borderlands d'après tes planches, et UI sombre à bandeaux rouges.

---

## Prochaine étape

1. Finir le passage au style peint : rendu, Cargo Ship et Wasteland, repeint des
   6 cartes, personnages animés en jeu, interface v2 — puis te montrer une image
   cible par carte.
2. Commiter par thème et pousser : la CI vérifie les tests, les exports et l'image
   Docker du serveur.
3. Netcode compétitif : P1.1 à P1.3 (netfox, mouvement autoritaire, lag comp).
4. Plateforme en ligne (Phase 4) : Steam, Nakama, matchmaking — il faudra alors tes
   comptes (Steamworks, VPS Dokploy).
