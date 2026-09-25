# Bible de style v3 — « Bric-à-brac peint »

> Version 3.0 — 2026-09-23. Remplace `.orchestrator/design.md` v2 (« Peint au soleil, encré gras ») pour tout ce qui touche l'image, le son d'interface et les effets. Jetons machine : [`docs/style/tokens.json`](style/tokens.json).
> Révision 3.1 — 2026-09-24 : §4 Personnages réécrit (héros athlétiques sur un gabarit commun, fin des têtes-objets) ; les paragraphes qui en dépendaient (§1, §2, §3, §5.3, §9.5, §10, §11, §12, §13, §14) sont alignés. Prompts de concept des agents : [`docs/style/character_prompts.md`](style/character_prompts.md).
> Statut : **proposition à verrouiller par l'utilisateur**.

## Sommaire

0. [Diagnostic : pourquoi « la 3D c'est terrible »](#0-diagnostic)
1. [Thèse, piliers, ce que le jeu n'est pas](#1-thèse)
2. [Lecture des références](#2-références)
3. [Univers et ton](#3-univers)
4. [Personnages](#4-personnages)
5. [Armes](#5-armes)
6. [Environnement](#6-environnement)
7. [Technique de rendu](#7-rendu)
8. [Interface](#8-interface)
9. [VFX et feedback](#9-vfx)
10. [Anti-patterns](#10-anti-patterns)
11. [Checklist de revue](#11-checklist)
12. [Backlog art priorisé](#12-backlog)
13. [Prompt kit](#13-prompts)
14. [Risques](#14-risques)

---

## 0. Diagnostic
<a id="0-diagnostic"></a>

Captures analysées : `tools/map_shots.gd` sur Wasteland et Cargo Ship (10 vues chacune, 23/09, 1280×800), plus les captures précédentes de personnages (`character_shots`, `char_ingame_shots`), de viewmodel (`fp_shots`) et d'interface v2 (`ui_v2/*`). Voici ce qui rend la 3D « terrible », classé par impact.

### 0.1 Monde

1. **Des veines noires partout.** `gen_textures.py` peint des traits d'encre ondulés (`creases()`, `wavy_lines()`) *dans* les textures. Le triplanaire les répète toutes les ~0,75 m, sans rapport avec la géométrie. Résultat : conteneurs, sol et murs sont zébrés de fissures noires qui ressemblent à de la moisissure (`wasteland_centre_map`, `cargo_ship_point_haut`). L'encre de Borderlands suit les arêtes du modèle ; ici elle suit une grille.
2. **De la boue au lieu d'aplats.** Le bruit fbm à grosses taches (sigma 120 px), multiplié par une teinte, puis par l'exposition 0,42 du tonemap Filmic, donne des surfaces sombres et floues. En gros plan, un conteneur rouge devient bordeaux-noir (`closeup_container_stack3`). Aucune zone ne reste un aplat lisible.
3. **Pas de forme, que des boîtes.** Les murs sont des plans géants sans biseau, sans trim, sans rupture de silhouette. Les coins de conteneurs flottent en cubes rouges et les marches d'escalier sont décollées de leurs limons (`cargo_ship_spawn_bleu`). La lumière n'a aucune arête à accrocher.
4. **Le sol crie plus fort que les objets.** Le sol de Wasteland est un rouge-rouille saturé de même valeur que les murs (`wasteland_spawn_bleu`). Un joueur n'aura aucun fond calme sur lequel se détacher.
5. **La carte flotte dans le vide.** Les vues aériennes montrent un plateau posé sur un ciel gris uniforme, sans horizon ni arrière-plan (`wasteland_aerial_nw`, `cargo_ship_aerial_se`). À hauteur de joueur, le ciel est un dégradé avec quelques nuages minuscules.
6. **Mauvaise échelle de détail.** Les ondulations de tôle font 12 cm mais les taches font 1 m : c'est du bruit à la mauvaise fréquence, qui se lit comme du flou.

### 0.2 Personnages et armes

7. **Des mannequins interchangeables.** Cinq des six silhouettes sont identiques (`silhouette_lineup`). Tête minuscule (1:7,8), pantalon noir sur la moitié du corps, aucune personnalité.
8. **Un viewmodel en boîtes, au centre de l'écran.** L'arme couvre la zone du réticule et se lit comme un assemblage de parallélépipèdes (`fp_gloves_final/fp_ravage`).

### 0.3 Interface

9. **Une interface d'outil de développement.** La sélection d'agent affiche des lettres géantes à la place des portraits et des colonnes de texte (`agent_select_1920`). L'achat est un tableur (`buy_1920`). Le lobby expose un champ IP `127.0.0.1` en premier plan et s'intitule « FPS » (`lobby_1920`). Le HUD est une suite de puces grises génériques.
10. **Le bandeau pinceau est le seul geste graphique**, et sa « queue de poisson » a l'air d'un bug.

### 0.4 Conclusion

Le problème n'est pas la palette : les tons de v2 sont bons et restent. Le problème, c'est **la méthode**. On a essayé d'imiter la *surface* de Borderlands (peint à la main, sale, encré dans la texture) avec du bruit procédural, ce qui est impossible sans peintre. La v3 change de méthode : **la forme et l'aplat d'abord, l'encre vient de la géométrie, le détail vient des décalques**. C'est entièrement faisable en `bpy` et en shader.

## 1. Thèse
<a id="1-thèse"></a>

> **Six champions hauts en couleur s'affrontent sur un plateau de télé peint au soleil : une sprinteuse aux cheveux de flamme, un boxeur casqué d'une cloche, une ingénieure des eaux au suroît, un gentleman vautour, une héronne passeuse et un crapaud shérif. Ce sont de vrais héros de hero-shooter, athlétiques et lisibles à 40 m, sur un gabarit commun. Le décor est fait de formes biseautées en aplats francs, l'encre suit les arêtes, et l'interface est une affiche de combat faite d'autocollants sur fond charbon.**

- **Retenu parce que** c'est le point de rencontre entre trois choses :
  - ce que l'utilisateur a épinglé : au moins 12 épingles sur 23 sont des personnages décalés, des autocollants ou des barres BD ;
  - ce qu'il a précisé le 2026-09-24 : des héros « type valo, apex » sur une hitbox commune, sans perdre l'originalité du crapaud cowboy ;
  - ce qu'un pipeline `bpy` et shader, plus Tripo pour la forme des personnages, peut produire proprement : des formes, des aplats, des dégradés de vertex color, des décalques.
- **Rejeté :** un Borderlands fidèle (surface peinte à la main, crasse, encre dans la texture). Il faut des peintres ; sans eux, on obtient exactement la boue actuelle (§0).
- **Rejeté aussi :** le collage BD acide plein écran de l'épingle 05. Il noierait la lisibilité compétitive et vit dans les teintes réservées à l'ennemi.

### 1.1 Les quatre piliers

1. **Des personnages avec du caractère.** Chaque agent a un crochet de tête reconnaissable à 40 m, une démarche, une pose et une onomatopée, sur un gabarit commun (§4.1). Au moins la moitié du roster n'est pas humaine. Même les décors ont de l'humour : panneaux peints à la main, autocollants, rustines. On ne saigne pas, on se fait « remballer » (§3).
2. **La forme et l'aplat d'abord.**
   - Tout asset se lit comme une silhouette pleine à sa distance de jeu.
   - Les biseaux accrochent la lumière.
   - Le détail vient de la géométrie ou d'un décalque, jamais d'un bruit.
   - Un hex de la palette est ce qu'on voit au soleil (WYSIWYG, §7.5).
   - Les ombres sont bleu-violet.
   - Le sol se tait, les objets parlent.
3. **L'encre suit l'objet.** Les traits naissent de la géométrie : silhouette en post-process, plis sur les biseaux, coque inversée sur les personnages et armes. Leur largeur dépend de la distance, et aucune texture ne contient d'encre.
4. **Le jeu ne ment jamais.**
   - Seul l'ennemi porte le Magenta `#FF3DC8` ou le Citron `#C8FF1F`.
   - Ce qu'on voit au-dessus de 1,40 m, c'est le col et la tête, et rien d'autre : ils coïncident avec la zone headshot de `WeaponMath.HEAD_HEIGHT_RATIO` (1,4 / 1,8).
   - Un couvert a l'air d'un couvert ; un décor fin a l'air fin.

### 1.2 Ce que le jeu n'est PAS

- **Pas un Borderlands de surface :** ni grunge peint, ni crasse procédurale, ni traits d'encre dans les textures.
- **Pas du PBR réaliste :** pas de reflets, pas de métal brillant, pas de variation de rugosité.
- **Pas l'« encre et papier » de v1 :** pas de monde désaturé, pas de grain papier, pas de hachures.
- **Pas un clone gris d'e-sport :** pas de néon sur noir, pas de HUD en puces grises génériques.
- **Pas gore :** pas de sang, pas de cadavre. Un agent éliminé fait « pouf » en rembourrage et confettis.
- **Pas de mascotte ni de chibi :** une grosse tête sur un petit corps ne permet pas de lire une pose de tir à 30 m et ne joue pas comme un héros. On vise un crâne à 1:7 (§4.1).
- **Pas un collage BD plein écran :** trame, éclat et onomatopées sont un assaisonnement réservé aux moments forts, jamais au HUD permanent.
- **Pas de fan-art ni de licence :** aucun personnage, logo ou panneau copié d'une épingle (Spider-Verse, Mr. Rabbit, Terraria…). On prend des principes, pas des costumes.

## 2. Références
<a id="2-références"></a>

Sources :
- `.orchestrator/refs/*` : deux planches de map et leurs vues « hero ».
- `.orchestrator/refs/pinterest/pin_01…23.jpg` : le tableau « projet jeu 2026 ».

Chaque image a été regardée. Aucune n'est un costume à cloner.

| Réf | Ce que c'est | On prend | On laisse |
|---|---|---|---|
| wasteland_sheet | Planche de map sombre, bandeaux pinceau rouges, titres blancs condensés italiques, légende à puces | La grammaire de page (bandeau pinceau, titre italique, labels à puce) et la lecture par couleur de zone | La densité de détail peint, inatteignable en procédural |
| wasteland_hero | Rue de relais pétrolier, soleil latéral chaud, ciel bleu, panneaux FUEL/GAS | Le soleil chaud et les ombres froides, les enseignes comme repères de spawn, la brume d'horizon | Le sol rouge-orange saturé, trop fort pour un fond de jeu |
| cargo_ship_sheet | Planche Cargo Ship, conteneurs par quadrant, flèches de spawn | Une couleur de conteneur par zone, qui sert aussi de callout ; le pont gris calme | La coque rouge moyenne (L 0,48), qui échoue au contraste ennemi, assombrie en `#8F2B22` |
| cargo_ship_hero | Conteneurs unis pochoirés, mer cyan, grand ciel | Les blocs monochromes avec pochoir, un seul accent par objet | La rouille et la crasse picturales |
| pin_01 | Sculpt Blender d'un boxeur chibi (sphère-tête, gants rouges, tee-shirt « BOOM ») | Le pipeline concept 2D puis blockout 3D ; Choc est boxeur | Le ratio 1:2,5 et les gants géants (on vise un crâne à 1:7, mains ×1,15) |
| pin_02 | Icônes hexagonales de capacités avec touche manette, bulles BD de ping à ombre décalée noire | L'**hexagone de capacité** avec son onglet de touche, les **pings en bulles**, l'ombre portée dure décalée | Les dégradés dans les icônes (on reste en aplat) |
| pin_03 | Gentleman à tête de d20 violet galaxie, glyphe œil-soleil, haut-de-forme | Le corps « dandy » et l'œil-soleil sur la face du dé : ils devenaient **Guet**, alors à tête de dé à la taille d'une tête de jeu — depuis remplacée par une tête de vautour éveillé, le d20 restant son emblème (lore §4.0, §4.4) | Le violet (bande réservée), décalé en indigo `#5157B8` |
| pin_04 | Crapaud cowboy qui tire avec une écrevisse, disque solaire orange | Le crapaud cowboy lui-même, qui devient **Verrou** avec des proportions de héros ; le **disque solaire derrière le portrait** | La peau vert-olive (risque de bande réservée), remplacée par un dendrobate cobalt ; le corps trapu |
| pin_05 | UI « Rad Comic » : collage de cases, trame, logo graffiti, violet et vert acides | Trame et éclat pour les **moments** (match trouvé, victoire, verrouillage), tuiles de nav inclinées | Le violet et le vert acides (réservés), le collage de cases sous licence, le bruit visuel permanent |
| pin_06 | Créature à l'encre tremblée sur papier | Une ligne d'épaisseur variable a du caractère : le trait s'épaissit en bas et au contact | Le grain papier et la désaturation (c'était v1) |
| pin_07 | Arlequin sombre (photo IA), losanges violets, grelots | Le motif arlequin comme **skin cosmétique**, le ton « menace costumée » pour un futur agent | Le violet et le réalisme sombre |
| pin_08 | Personnage-guimauve cubique, 2 tons, trait noir épais | La preuve qu'une primitive + 2 tons + un trait épais suffisent | Le monde neutre gris |
| pin_09 | Planche « Movements of the two legged figure » (cycles de marche) | Une **démarche par agent** (strut, sneak, double bounce, tiptoe, skip) | — (référence d'animation pure) |
| pin_10 | Tuto logo « IGNITE » : grille inclinée, contour, ombre portée | La **recette du titre-autocollant** : grille inclinée à 12°, contour d'encre, ombre dure décalée | L'accent rose (proche de la bande réservée) |
| pin_11 | Champignon « Truffle » : chapeau bleu, contour d'autocollant, typo géante derrière | Le contour extérieur plus épais que les traits intérieurs, le **poster typographique** derrière l'agent | Le personnage lui-même (fan-art) |
| pin_12 | Panneau de réglages en bois boulonné (curseurs MUSIC/SOUND, bouton X hexagonal rouge) | La **tactilité** (curseur en fente, bouton de fermeture hexagonal rouge) | Le skeuomorphisme bois sur tous les écrans, gardé pour la page Réglages seulement |
| pin_13 | Décalque « GIGGLE » posé sur une guitare dans Blender | Le **décalque comme système de détail et de cosmétique** (autocollants sur les armes) | Le rendu PBR réaliste de la guitare |
| pin_14 | « Basil » : fille à tête de pot en terre cuite, arrosoir, pots à visages, glaçure crème à coulures bleues | L'arrosoir et la glaçure à coulures, qui passaient chez l'ancienne **Baume** (bord de pot en ceinture, jupe évasée), remplacée par Roseau, héronne éveillée (lore §4.0, §4.4) | La tête-pot et les mains en moufle ; le vert feuille (réservé), décalé en sarcelle |
| pin_15 | Barres « CLIMB 70 % » inclinées orange, cyan, violet, perso qui déborde, ombre noire | La **carte-joueur inclinée** d'où le rendu déborde (tableau des scores, fin de match, sélection) | La barre violette (réservée) |
| pin_16 | Peindre un crâne stylisé : esquisse, forme, volume, rendu | L'échelle de rendu : forme plate, puis volume en 2 bandes, puis **un seul reflet brillant** | L'étape « rendu » grunge bruité, qui est exactement notre boue actuelle |
| pin_17 | Dés d20 mimiques (violet, bleu) avec dents et langue, figurines peintes | Le **laqué de figurine** (reflet dur) pour les parties émaillées (tête de Guet, casque de Choc) ; le d20 mimique devient l'ultime de Guet ou un skin | Le violet |
| pin_18 | Ruine isométrique : aplats, trait noir net, un seul ton d'ombre, mousse verte | La recette décor : **aplat, un ton d'ombre, trait net, pierres biseautées** | La mousse vert-citron (réservée) |
| pin_19 | Sélection d'agent « Mr. Rabbit » : fond jaune plein, rendu au centre, roster à gauche, bouton NEXT incliné | La mise en page de la **sélection d'agent** : aplat couleur de l'agent, roster à gauche, rendu géant, CTA incliné | Le personnage, le filigrane d'école, les accents magenta et violet |
| pin_20 | Plan de quartier « New Maerimydra » en rendu argile, callouts | La **présentation de map** (rendu argile + callouts) pour chargement et planches ; la densité de quartier | Le blanc-gris seul |
| pin_21 | Blockout SketchUp : anneau de bâtiments autour d'une place, repères cylindriques | La discipline de blockout : un **anneau de « skins » hauts** autour d'un cœur jouable, des repères lisibles de partout | — |
| pin_22 | Diorama d'immeuble en ruine : traits fins nets, enduit plat, gravats orange | La **cible de rendu décor** : matériaux simples, trait fin, gravats biseautés, silhouette cassée | La palette pâle désaturée |
| pin_23 | « Palmera » : fille à tête de palmier, paillote, coco | La couronne de feuilles en guise de chevelure, reprise par l'ancienne Baume ; la peau crème-tan | Le vert (réservé), la pose sexualisée (hors ton) |
| contact_sheet | Planche contact des 23 épingles | La vue d'ensemble : **les personnages décalés dominent le tableau**, puis l'UI BD, puis les blockouts | — |

**Bilan.** Le tableau pousse vers des personnages décalés et l'UI autocollant. Les planches, elles, apportent la palette, les repères et la grammaire de page sombre. La v3 garde les deux, en séparant leurs rôles (§8.1).

Le 2026-09-24, l'utilisateur a recadré les personnages : des héros « type valo, apex » sur une hitbox commune, sans perdre l'originalité des idées (le crapaud cowboy reste un crapaud). La v3.1 en tire le §4.

## 3. Univers
<a id="3-univers"></a>

> **Univers et histoire : [`docs/LORE.md`](LORE.md)** (« La Ruée vers la Braise »). Remplace *BRIC-À-BRAC*, le tournoi télévisé à objet fétiche de la v3 : LORE.md est la source unique de l'origine des pouvoirs, des factions et de l'histoire des agents. Ce §3 n'en garde que ce qui pilote l'image et le ton.

Il y a trente et un ans, la comète **Braise** s'est brisée au-dessus du **Palud**, un marais tiède en bordure du désert : ses éclats ne s'éteignent jamais, ils ont éveillé les bêtes du marais en peuples pensants et donné des dons à quelques humains (lore §0, §2.2). Pour trancher la guerre des concessions qui a suivi, la **Charte** a inventé les **Joutes** : un match est un procès, entre jouteurs licenciés qu'un **Sauf-conduit** « remballe » au lieu de les tuer (lore §2.5). Cette saison, la Compagnie **Ardente** veut noyer le Palud sous un Grand Barrage, et le pays entier suit les Joutes à la radio.

Les sites de joute sont aménagés par la Commission des Joutes pour la retransmission : bâches peintes, panneaux au pochoir, projecteurs, gradins (lore §2.4). C'est la raison, dans le monde, du « plateau peint » du §6.1 : couleurs franches, bords épais, soleil éternel de fin d'après-midi.

**Ce que le ton implique, concrètement :**

- **Mort :** pas de sang. Le halo du Sauf-conduit encaisse chaque impact et crache une bouffée de mousse crème, **la bourre** ; à zéro, le jeton du jouteur saute et il est « remballé » dans un nuage de bourre et de confettis couleur-clé, aspiré vers la Consigne (lore §2.5). L'écran de mort dit « REMBALLÉ » (§9.5).
- **Voix :** le Crieur de Radio-Joute, audio optionnel, texte toujours présent.
  - Les onomatopées sont en français : **PAF, BAM, CLONK, DING, TCHAK, SPLOTCH, FLOUF**.
  - Les multi-kills s'annoncent « DOUBLÉ », « TRIPLÉ », « GRAND CHELEM ».
- **Décor :** un site de joute aménagé pour la retransmission. Panneaux et enseignes sont peints à la main (pochoirs, fautes de kerning volontaires). Au loin, projecteurs et gradins se devinent sous forme de silhouettes d'arrière-plan.
- **Cosmétiques F2P :** toujours un objet du monde (lore §7) — tenues de faction (Ardente, Ligue du Palud, Francs), couvre-chefs (toujours dans l'enveloppe de tête du §4.1), décalques d'armes, jetons de Sauf-conduit, poses et onomatopées du Crieur. Jamais de néon, de science-fiction ni de licence.
- **Humour :** dans les formes et les poses, jamais dans du texte écrit sur l'écran pendant le combat ; 70 % sérieux, 30 % absurde dans les cartes de litige (lore §5).

## 4. Personnages
<a id="4-personnages"></a>

> **Histoire du monde et des agents : [`docs/LORE.md`](LORE.md)** (« La Ruée vers la Braise ») : origine des pouvoirs, factions, raison d'être de chaque agent. Ce §4 n'en garde que le dessin.

> **v3.1 (2026-09-24).** Les personnages à tête-objet de la v3 sont abandonnés à la demande de l'utilisateur : « on veut des perso type valo, apex […] il faut l'adapter en personnage de jeu, […] les personnages doivent avoir la même hitbox », puis « il faut pas perdre d'originalité non plus, le cowboy grenouille était bien, juste pas les bonnes proportions ». La v3.1 garde les six idées et les six couleurs-clés, portées par des héros athlétiques qui partagent un gabarit unique. Le reste de la bible (monde, rendu, interface, VFX) ne change pas.

**Thèse.** Six héros de hero-shooter, grands, athlétiques et lisibles à 40 m, dont quatre ne sont pas humains. Chacun porte l'objet de la v3 comme motif (cheveux, casque, tête stylisée, gadgets, emblème), jamais comme un changement de gabarit : même squelette, même capsule, même enveloppe de tête, même masse visible.

**Rejeté :** déplacer le seuil de headshot pour permettre des proportions réalistes (épaules à 1,47 m). C'est du code et de l'équilibrage (`WeaponMath`), hors du périmètre de l'art. Le dessin s'adapte au seuil existant (§4.1) ; le repli est décrit au §14.

### 4.1 Gabarit commun : une seule cible pour six silhouettes

**Ce que le code fixe (vérifié le 2026-09-24) :**
- **Une seule capsule pour tous.**
  - `scenes/player/player.tscn` : `CapsuleShape3D` de rayon 0,40 m et de hauteur 1,80 m debout.
  - `MovementConfig.crouch_height` = 0,90 m dès que `is_crouching` est vrai : accroupi, glissade, plongeon et roulade.
  - `PlayerController._apply_body_height` applique `current_height`, répliquée, à la capsule.
  - `AgentDatabase` n'a aucun champ de taille.
- **Les balles ne voient que la capsule.**
  - `Weapon._resolve_ray` touche le `PlayerController`, jamais un os ni un maillage.
  - Headshot (`WeaponMath.is_headshot`) : impact au-dessus de `current_height × 1,4/1,8`, soit **1,40 m debout** et **0,70 m accroupi**.
  - Debout, cette zone est exactement l'hémisphère supérieur de la capsule (centre à 1,40 m, rayon 0,40 m).
- **La caméra** (`%Head`) est à `current_height − 0,20` : **1,60 m** debout, 0,70 m accroupi.
- **Le modèle est cosmétique.** `CharacterBody.gd` instancie `assets/models/characters/<agent>.glb` sans collision, puis le met à l'échelle pour que sa boîte englobante de repos mesure 1,80 m de haut.

La hitbox est donc **identique pour les six agents par construction**, et aucun choix d'art ne peut la modifier. L'art peut seulement **mentir** sur elle : une tête qui sort de la zone, un chapeau qui fait rétrécir le corps, une silhouette plus fine ou plus grosse que les autres. Le gabarit ci-dessous interdit ces trois mensonges.

> **Défaut de code constaté (sonde headless du 2026-09-24).** La `CapsuleShape3D` est une sous-ressource **partagée** par toutes les instances de `player.tscn` (`resource_local_to_scene` = false). Un joueur qui s'accroupit raccourcit donc la capsule de tous les autres joueurs du même pair, serveur compris. Le correctif relève du code et fait l'objet d'une tâche à part. Tant qu'il n'est pas livré, aucune revue de hitbox n'est fiable.

**Trois conséquences pour le dessin :**
1. **1,80 m pile, tout compris.** `CharacterBody` divise 1,80 par la hauteur de la boîte englobante. Un chapeau qui dépasse de 6 cm rétrécit donc tout le corps de 3 % et fait descendre la tête sous sa zone. Le point le plus haut (cheveux, chapeau, feuilles, yeux de grenouille) est à 1,80 m, et le crâne passe dessous.
2. **1,40 m est une ligne de dessin : le col.** Au-dessus : le col, le cou, la tête et ce qui la coiffe, rien d'autre. En dessous : les épaules, le torse et les armes. La jonction col–épaules se lit par un changement de valeur ou de matière.
3. **La capsule fait 0,80 m de large, et aucun corps ne la remplit.** La marge d'air doit être la même pour tous : même masse visible (± 10 %), même enveloppe de tête, même longueur de bras.

**Squelette commun « UAL-G ».**
- Le rig UAL (Quaternius, CC0, 53 os `DEF-`, 46 animations) est retouché **une seule fois**, pour les six agents et pour `fp_arms` :
  - les épaules (`DEF-upper_arm`) descendent à environ 1,32 m, pour que le sommet du deltoïde passe sous 1,38 m ;
  - les clavicules sont en pente et le cou est allongé d'environ 3 cm ;
  - `DEF-head` est replacé pour mettre le menton à 1,49 m et les yeux à 1,62 m.
- Le bassin et les jambes ne bougent pas : les pieds restent au sol dans les 46 clips.
- Aucun agent n'ajoute d'os de déformation au corps. Seuls des os cosmétiques en bout de chaîne (`COS-*` : pans de poncho, feuilles, flamme) sont permis, et aucune animation partagée n'en dépend.

**Gabarit debout** (pose de repos, semelles à 0, en mètres) :

| Repère | Valeur | Tolérance | Pourquoi |
|---|---|---|---|
| Point le plus haut, tout compris | 1,80 | ± 0,005 | mise à l'échelle par la boîte englobante |
| Sommet du crâne | 1,75 | ± 0,01 | laisse au plus 5 cm de cheveux ou de couvre-chef |
| Ligne des yeux | 1,62 | ± 0,02 | la caméra est à 1,60 : le modèle regarde d'où le joueur voit. Exception : les yeux de Verrou, au sommet du crâne, sont son crochet |
| Menton | 1,49 | ± 0,02 | crâne de 0,26 m, soit 1:7 |
| Col (jonction col–épaules) | 1,40 | ± 0,02 | seuil headshot |
| Haut du col, devant | ≤ 1,48 | — | le menton reste visible de face |
| Sommet des deltoïdes, épaulettes, sangles, brassard | ≤ 1,38 | 0 | 2 cm sous le seuil |
| Largeur aux épaules, hors tout | 0,46–0,60 | — | Guet au minimum, Choc au maximum |
| Largeur à la poitrine et aux hanches | 0,34–0,46 | — | — |
| Profondeur du torse, sac compris | ≤ 0,50 (± 0,25 autour de l'axe) | — | le corps reste dans la capsule |
| Entrejambe | 0,84 | ± 0,03 | jambes UAL inchangées |
| Longueur de bras (épaule → bout des doigts) | celle d'UAL-G | 0 | même tenue d'arme ; le canon dépasse d'un angle au même moment pour tous |
| Mains, pieds | ×1,15 au plus par rapport à UAL | — | le ×1,4 de la v3 faisait des moufles de mascotte |

**Proportions.**
- Le crâne mesure 1:7 de la hauteur (0,26 m). Avec cheveux ou couvre-chef, la tête se lit entre 1:6 et 1:6,5. C'est plus lisible que le mannequin UAL à 1:7,8 critiqué au §0, sans revenir à la mascotte 1:4,5 de la v3.
- Le seuil à 1,40 m impose une stylisation assumée : **épaules tombantes, col haut, torse court, jambes longues.**
- Le col (col montant, capuche, bandana, collerette, gorge de grenouille) habille les 10 cm entre les épaules et le menton. Visuellement, il appartient au bloc de la tête.

**Enveloppe de tête commune** (tout compris : cheveux, oreilles, yeux, feuilles, casque, chapeau, visière) :

| Mesure | Valeur |
|---|---|
| Hauteur | de 1,47 à 1,80 m |
| Largeur | ≤ 0,34 m |
| Profondeur | ≤ 0,36 m |
| Aire de face | 0,046–0,058 m², soit environ une ellipse de 0,22 × 0,31 m : aucune tête n'offre une cible plus grosse ou plus petite |
| Visage | yeux (ou glyphe) visibles de face et de 3/4, jamais cachés par un bord ou une visière |

**Gabarit dans les autres états.** Contrôle sur 12 images debout (idle, marche, course, sprint, tir, rechargement) et 4 images accroupies :

| État | Règle |
|---|---|
| Debout, en l'air | yeux entre 1,56 et 1,66 ; menton ≥ 1,43 ; sommet ≤ 1,80 ; mains et armes ≤ 1,38 tant que la visée reste entre −15° et +15° |
| Accroupi (et glissade, plongeon, roulade) | yeux entre 0,72 et 0,80, donc au-dessus du seuil de 0,70 ; sommet ≤ 0,92 visé, 0,95 au plus (WARN) |
| Atterrissage | écrasement du corps de 0,97 à 1,03 en Y pendant au plus 80 ms ; jamais d'écrasement de la tête |
| Emote de fin de manche | libre (on ne tire plus) |

Accroupi, la bande headshot ne mesure que 0,20 m, soit moins qu'une tête :
- on garde les yeux et le front dans la bande ; la bouche et le menton comptent comme corps ;
- les clips UAL `Crouch_Idle` et `Crouch_Fwd` sont à mesurer. S'ils dépassent 0,95 m, on génère une pose accroupie basse dédiée (buste penché de 40 à 45°, tête relevée), comme `FP_Hold` ;
- si cette pose casse la lecture, la décision revient au gameplay (§14). On n'élargit pas la tolérance.

**Ce qui a le droit de casser la silhouette :**

| Élément | Où | Limite |
|---|---|---|
| Cheveux, couvre-chef, oreilles, yeux, feuilles, flamme | dans l'enveloppe de tête | jamais au-dessus de 1,80 m ni plus large que 0,34 m ; aucune mèche sous 1,47 m, sinon on la lirait comme de la tête dans la zone du corps |
| Col, capuche, bandana, collerette | entre 1,38 et 1,48 m | le menton reste visible de face |
| Épaulettes, sangles, brassard d'équipe | sous 1,38 m | largeur hors tout ≤ 0,60 m |
| Manteau, poncho, jupe, pans | au plus 0,10 m au-delà du corps ; bas à au moins 0,35 m du sol | les jambes restent lisibles en course |
| Sac, soufflet, cloche dorsale | au plus 0,18 m derrière le dos ; sommet sous 1,36 m | rien ne dépasse au-dessus des épaules : fini le sac à antenne |
| Gadgets de capacité portés | ceinture, cuisse, buste | au plus 0,08 m d'épaisseur |
| Arme | en main seulement ; étui à la hanche ou à la cuisse | aucune arme portée dans le dos |

Règles générales :
- rien de plus fin que 4 cm sur la silhouette ;
- en idle, en marche et en course, tout reste dans le rayon de 0,40 m de la capsule. Seule exception, le canon de l'arme en main : il doit dépasser pour qu'on lise « il me vise » ;
- l'aire de silhouette de chaque agent, de face comme de profil, reste à ± 10 % de la moyenne du roster.

**Mesure :** CHK-22 à CHK-25 (§11), par `check_asset.py` sur le GLB et par les turntables.

### 4.2 Langage de formes

**Une forme par rôle**, lue sur le torse et la posture :

| Rôle | Forme | Lecture | Agents |
|---|---|---|---|
| Entrée | V (triangle pointe en bas), diagonales vers l'avant | épaules plus larges que les hanches, buste penché de 4 à 6°, appuis légers | Vif (V fin), Choc (V massif) |
| Contrôle | rectangle, verticales, symétrie | bloc posé d'aplomb, centre de gravité au milieu | Vanne (carré posé), Guet (rectangle étroit) |
| Soutien | A (trapèze pointe en haut), courbes | base large (jupe, poncho), épaules douces | Roseau (A long), Verrou (A de poncho) |

**Un crochet de tête par agent**, unique dans le roster et lisible de face **et** de profil :
- bulbe-flamme (Vif) ;
- dôme de cloche (Choc) ;
- suroît à long rabat (Vanne) ;
- tête nue à bec crochu et haut-de-forme, sur collerette (Guet) ;
- bec en poignard et huppe couchée (Roseau) ;
- deux yeux ronds sous un chapeau rejeté (Verrou).

C'est ce crochet qui nomme l'agent à 40 m.

**Humains et créatures, même monde :**
- même encre, mêmes biseaux, mêmes deux bandes ;
- le non-humain se lit par la tête, la peau et les mains, jamais par un gabarit différent ;
- le roster compte **trois Éveillés** (Guet, Roseau, Verrou) et **trois humains** (Vif, Choc, Vanne) — lore §4.0. L'originalité est un pilier : aucun futur agent ne fait passer les non-humains sous la moitié.

**Trois masses : 60 / 30 / 10.**
- 60 % : la tenue (peau nue comprise), dans la couleur secondaire de l'agent, entre L 0,45 et 0,80.
- 30 % : l'équipement, en charbon `#2A2522`, en cuir `#6B4A2E` ou en fonte.
- 10 % : un accent clair, à L ≤ 0,93. C'est l'albédo maximal : les blancs 3D sont en émail crème `#E6E1D6`, jamais dans le papier d'interface `#F4EDE1`.
- La **couleur-clé** couvre au moins la moitié de la tête visible (cheveux, casque, peau, plumage) et au plus 15 % du corps, sans exception.

**Rondeurs dans le corps, angles dans l'équipement.** Les vêtements sont des volumes pleins à 3 à 5 grands plis ; boucles, plaques et gadgets sont biseautés.

**Brassard d'équipe** (conservé de v2) : un panneau d'épaule sous 1,38 m, bleu allié `#3B8BFF` + ● ou couleur de surbrillance ennemie + ▼. C'est la seule zone du corps recolorée par l'équipe.

### 4.3 Silhouette lisible à 40 m

- **Distance de référence :** en 1080p, FOV horizontal 90° (vertical 58,7°), un agent de 1,80 m mesure **43 px** de haut à 40 m, et sa tête (0,31 m) **7 à 8 px**. À 20 m : 86 px et 15 px.
- **Tests binaires**, de face et de profil :
  - corps entiers rendus à 43 px de haut : IoU entre deux agents ≤ **0,85** ;
  - têtes détourées rendues à 64 px de haut : IoU entre deux têtes ≤ **0,75** ;
  - aire de silhouette à ± 10 % de la moyenne du roster, par équité ;
  - test à l'aveugle : 9 personnes sur 10 nomment l'agent d'après sa silhouette noire de 64 px.
- **La tête se détache :** ΔL ≥ 0,15 entre la tête (couleur-clé) et le col ou le haut du torse juste dessous. La cible se lit de la même façon pour tous.
- **Pose de tir :** arme tenue sous 1,38 m, canon vers l'avant, visible de profil. La ligne bras + arme doit dire « il me vise » à 30 m.

### 4.4 Les six agents

> **Révision 3.2 (2026-09-24).** Le roster suit désormais [`docs/LORE.md`](LORE.md) (« La Ruée vers la Braise ») : histoire, factions, relations et répliques y sont. Ce paragraphe ne garde que le dessin.
> - Roc est remplacé par **Vanne** (humaine, ingénieure de l'Ardente) et Baume par **Roseau** (héronne éveillée, passeuse du Palud).
> - Guet quitte la tête de dé pour devenir un **vautour éveillé**. Le d20 devient son emblème.
> - Vif, Choc et Verrou restent. Vif et Verrou suivent leurs modèles 3D approuvés.
> - Les couleurs-clés ne changent pas : Vanne reprend celle de Roc, Roseau celle de Baume. `AgentDatabase.gd` n'a donc pas à changer de couleurs, seulement de noms.

Toutes les teintes ont été vérifiées : en OKLCH, elles sont hors des bandes réservées (300–355° et 105–145°, au-delà de C 0,08). Le texte d'autocollant atteint un contraste d'au moins 4,5:1 sur la couleur-clé, en encre `#1A1410` ou en papier `#F4EDE1` selon le cas.

| Agent | Rôle | Nature | Faction (lore) | Crochet (tête / corps) | Couleur-clé | Texte sur la clé | Démarche |
|---|---|---|---|---|---|---|---|
| **Vif** | Entrée | humaine, douée | Francs | flamme en banane / V fin | `#EE6A24` vermillon-orange (h 44°) | encre 5,8:1 | course légère, skip |
| **Choc** | Entrée | humain, doué | Francs (Foire) | dôme de cloche / V massif | `#BE2D25` rouge alarme (h 28°) | papier 5,0:1 | strut de boxeur |
| **Vanne** | Contrôle | humaine | Ardente | suroît à long rabat / carré posé | `#F2B51D` jaune de chrome (h 83°) | encre 9,9:1 | pas mesuré, métronome |
| **Guet** | Contrôle | Éveillé, vautour | Francs (la Cote) | tête nue à bec crochu et haut-de-forme, sur collerette / rectangle étroit | `#5157B8` indigo (h 277°) | papier 5,3:1 | tiptoe |
| **Roseau** | Soutien | Éveillée, héronne | Palud | bec en poignard et huppe couchée / A long | `#2E9C8A` sarcelle (h 180°) | encre 5,4:1 | pas d'affût : genou haut, pied posé lentement |
| **Verrou** | Soutien | Éveillé, dendrobate | Palud | yeux ronds et chapeau rejeté / A de poncho | `#2A5FC4` cobalt (h 262°) | papier 5,1:1 | pas chaloupé |

Les couleurs de v2 et de `AgentDatabase.gd` sont remplacées (tâche ART-14) :
- Guet `(0.55,0.75,0.42)` tombait dans la bande verte réservée (h ≈ 130°) ;
- Verrou `(0.5,0.42,0.68)` frôlait la bande violette.

Dans le HUD, les couleurs d'agent n'apparaissent **jamais** (§8.3). Elles vivent dans les menus, la sélection et la fin de match.

**Crochets de tête, de face et de profil.** Aucun doublon, et c'est ce qui nomme l'agent à 40 m :
- **Vif :** bulbe de flamme, couché vers l'arrière.
- **Choc :** dôme de cloche lisse, évasé à la mâchoire.
- **Vanne :** suroît. De profil, il dessine une coquille : bord relevé devant, long rabat derrière.
- **Guet :** petite tête nue au bec crochu, haut-de-forme de travers, posée sur une collerette claire.
- **Roseau :** le seul profil en flèche : bec devant, huppe derrière.
- **Verrou :** deux yeux ronds sous un chapeau rejeté.

**Règles de l'éveil pour le dessin des trois Éveillés** (lore §2.2, « la forme d'éveil ») :
- **Mains :** quatre doigts. L'annulaire et l'auriculaire d'UAL-G pilotent le même doigt.
- **Corps :** jambes humaines chaussées (bottes, cuissardes) ; ni ailes, ni queue, ni pattes d'oiseau visibles.
- **Plumes, écailles, taches :** des volumes pleins d'au moins 4 cm, ou des décalques ; jamais de plumes fines.
- **Couleur-clé :** elle est portée par la peau ou le plumage de la tête.

**L'emblème et le jeton.** Chaque jouteur porte à la ceinture son jeton de Sauf-conduit : une boucle ronde en laiton de 6 cm, frappée de son emblème. À l'élimination, c'est ce jeton qui tombe et roule (§9.5). Les emblèmes :

| Agent | Emblème |
|---|---|
| Vif | l'allumette |
| Choc | la cloche fêlée |
| Vanne | le volant de vanne |
| Guet | le d20 |
| Roseau | le flotteur |
| Verrou | le chapeau |

**Resynchronisé (tâches NAR-02, NAR-03).** §3 (univers BRIC-À-BRAC remplacé par `LORE.md`), §4.2 (crochets et décompte non-humains/humains), §4.6 (démarches), §4.7 (manches et mains des bras en vue FP), §9.5 (emblèmes), §1 (thèse), §4.5 (matières de peau), §4.8 (tableau v3 → v3.1), §9.6 (matières des murs), §12.2 (fiches ART-14, ART-17) et §14 (risque 10) citent désormais Vanne, Roseau et le Guet vautour ; les commentaires de `scripts/agents/abilities/DashAbility.gd` et `WallAbility.gd` aussi (`RenewalAbility.gd` citait déjà Roseau).

**Encore à resynchroniser (hors périmètre de NAR-02/NAR-03) :**
- `docs/style/concepts/`, `docs/assets/ASSET_PLAN.md`, `docs/style/character_prompts.md` : à vérifier séparément ;
- le sous-titre du document (« Bric-à-brac peint », ligne 1) est un nom de code de style partagé avec `docs/style/tokens.json`, `scripts/core/LevelLook.gd`, `scripts/ui/Comic.gd` et `scripts/ui/MainMenu.gd` (hors des fichiers possédés par NAR-03) : à renommer en bloc si le nom doit disparaître partout, sinon à garder comme codename de style distinct de l'univers du lore.

---

#### Vif — « l'Allumette »

- **Rôle :** Entrée — Ruée, Éblouissement, Tremplin, Résurgence.
- **Qui :** Lison Barral, humaine, 19 ans, coureuse de concessions de Val-Poussière. Sa chevelure a pris feu dans un terril de La Fosse et ne s'est jamais éteinte (lore §4).
- **En une ligne :** elle part avant le coup de feu et s'excuse après.
- **Référence :** le modèle 3D approuvé `assets/models/characters/vif.glb`.
- **Motif (l'allumette) :** ses cheveux sont une flamme d'allumette sculptée, pleine et rigide, sans particules. C'est une banane couchée vers l'arrière.
  - Racine `#B8421A`, masse vermillon `#EE6A24`, pointe ambre `#F2C53D`.
  - La flamme monte de 5 cm au plus au-dessus du crâne et reste dans l'enveloppe.
- **Tenue :**
  - blouson de survêtement court couleur braise `#9A4A2C`, col zippé montant jusqu'au menton, bandes crème `#EBDDC0` sur les manches ;
  - haut de sport sombre et legging long charbon `#2A2522` ;
  - baskets montantes crème `#E6E1D6` à semelle vermillon, poignets de cuir ;
  - peau `#D29A6E`, yeux ambre, sourcils épais ;
  - brassard-grattoir `#8A4B2E` sur l'avant-bras gauche.
- **Palette :** `#EE6A24` clé · `#9A4A2C` tenue · `#2A2522` équipement · `#D29A6E` peau · `#F2C53D` accent.
- **Gadgets :**
  - une cartouchière en travers du buste, sous 1,38 m, porte 4 allumettes-flash de phosphore de braise de 5 cm de diamètre (Éblouissement) ;
  - la boîte d'allumettes à ressort d'étoile, cadeau de Choc, est clipsée à la hanche (Tremplin) ;
  - la boucle-jeton est frappée de l'allumette.
- **Armes de prédilection :** Rafale, Éclair. Autocollant signature : une bande de grattoir sur le garde-main.
- **Crochet de silhouette :** la flamme au-dessus d'un V fin, des jambes longues, un profil penché vers l'avant.
- **Voix et animation :**
  - débit rapide, rire bref ;
  - idle nerveux : elle tapote du pied et sautille ;
  - cadence ×1,15, buste penché de 6° ;
  - en course, la flamme se couche un peu plus (os `COS-`, dans l'enveloppe).
- **Pose signature :** elle gratte une allumette sur son brassard, souffle dessus et fait un clin d'œil.

#### Choc — « la Cloche »

- **Rôle :** Entrée — Charge, Piège-choc, Mur d'assaut, Déferlante.
- **Qui :** Anatole Kessi, humain, 34 ans, élevé par la Foire des Francs, champion de la baraque de boxe. Le jour où il a fendu la cloche du Tape-la-cloche, coulée dans un bronze d'éclat, ses poings se sont mis à sonner (lore §4).
- **En une ligne :** il frappe d'abord, il sonne la fin du round ensuite.
- **Motif (la cloche) :**
  - son casque de boxe est un dôme de cloche en émail rouge `#BE2D25`, **brillant**, ouvert sur le visage, de 0,24 m de large ;
  - une mentonnière en laiton `#D9A21B` a la forme d'un battant ;
  - **la Cloche fêlée**, celle du Tape-la-cloche refondue, est vissée à son harnais entre les omoplates (sommet ≤ 1,36 m). Elle sonne à chaque Charge.
- **Tenue :**
  - gilet d'entraînement matelassé crème `#E6E1D6`, sans manches, à col matelassé montant et liseré rouge ; dans le dos, en décalque, « FOIRE DES FRANCS » ;
  - short satiné rouge à ceinture crème, sur un collant de compression charbon `#2A2522` ;
  - bottines de boxe crème à lacets rouges ;
  - bandages et mitaines de combat ouvertes, charbon à manchette rouge (×1,15 ; les doigts restent libres pour la poignée) ;
  - peau `#6B4330`, barbe courte taillée, sourcils bas.
- **Palette :** `#BE2D25` clé · `#E6E1D6` tenue · `#6B4330` peau · `#2A2522` équipement · `#D9A21B` laiton.
- **Gadgets :**
  - une ceinture de 3 clochettes-mines coulées dans le bronze fêlé (Piège-choc) ;
  - la Cloche fêlée dans le dos ;
  - la boucle-jeton est frappée de la cloche ;
  - le volet peint de sa baraque (Mur d'assaut) n'est pas porté : il se déploie.
- **Armes de prédilection :** Fracas, Magnum.
- **Crochet de silhouette :** le dôme de cloche au-dessus du V le plus large du roster (0,60 m aux épaules), des épaules musclées mais tombantes, de gros poings.
- **Voix et animation :**
  - voix grave de bonimenteur ;
  - épaules qui roulent et rebond de boxeur continu en idle (± 2 cm) ;
  - démarche en strut.
- **Pose signature :** garde haute, deux sautillements, puis il frappe la Cloche fêlée du poing, par-dessus l'épaule.

#### Vanne — « la Digue »

- **Rôle :** Contrôle — Mur, Fumée, Piquet, Forteresse. Ce sont les capacités de l'ancien Roc, renommées dans `AgentDatabase.gd` (AGT-09, lore §9).
- **Qui :** Odile Valat, humaine, 41 ans, ingénieure en chef des ouvrages hydrauliques de l'Ardente. Sa mère a co-inventé le Sauf-conduit ; elle, elle dessine le Grand Barrage (lore §4).
- **En une ligne :** elle ferme les rivières pour allumer les villes.
- **Motif (la vanne, le barrage) :**
  - **le suroît** ciré jaune de chrome `#F2B51D` porte la clé : il couvre au moins la moitié de la tête visible, de face comme de profil. Le bord est relevé devant, pour dégager le front et les yeux. Le rabat arrière descend vers la nuque et s'arrête à 1,50 m au plus bas. Le sommet est à 1,80 m, la largeur à 0,33 m au plus ;
  - lunettes rondes cerclées de laiton `#D9A21B`, avec un reflet dur ;
  - un carré auburn `#5A2E22` dépasse du suroît aux tempes. Aucune mèche sous 1,47 m.
- **Tenue :**
  - **le col** est un col roulé épais bleu de Prusse `#2E4A6B`, de 1,40 à 1,48 m. Le ΔL avec le suroît est de 0,41 ;
  - combinaison de toile écrue `#BFAE86`, coupe carrée, manches retroussées ;
  - écussons bleu de Prusse au soleil-comète de l'Ardente sur les épaules (sous 1,38 m) ;
  - bande de chevrons jaune et encre sur l'avant-bras droit. Elle ne va jamais sur l'épaule, pour ne pas concurrencer le brassard d'équipe ;
  - gantelets de cuir `#6B4A2E`, bottes de caoutchouc charbon `#2A2522` ;
  - peau `#D8A27E`, taches de rousseur en décalque.
- **Palette :** `#F2B51D` clé · `#BFAE86` toile · `#2E4A6B` bleu de Prusse · `#2A2522` équipement · `#6B4A2E` cuir · `#D9A21B` laiton.
- **Gadgets :**
  - **la coffreuse** à béton-braise, plate, plaquée au dos (0,16 m de profondeur, sommet ≤ 1,34 m), avec un gros tuyau annelé de 4 cm de diamètre au moins vers l'avant-bras gauche (Mur, Forteresse) ;
  - une gourde d'acier à la hanche : elle y jette un éclat (Fumée) ;
  - le lanceur de piquet d'arpenteur, plaqué sur la cuisse droite (≤ 0,08 m ; Piquet) ;
  - la boucle-jeton en volant de vanne.
- **Armes de prédilection :** Percuteur, Semeuse.
- **Crochet de silhouette :** le suroît au-dessus d'un carré posé (0,56 m aux épaules). C'est le seul couvre-chef à rabat du roster.
- **Voix et animation :**
  - voix posée, phrases courtes et chiffrées ;
  - pas mesuré de métronome, cadence ×1,0, buste droit ;
  - en idle, elle essuie ses lunettes puis lit un manomètre au poignet ;
  - à l'atterrissage, la coffreuse lâche une bouffée de vapeur crème dans le dos, sous les épaules.
- **Pose signature :** elle tourne d'un quart un volant de vanne invisible, et un « CLONK » sourd lui répond.

#### Guet — « le Dé »

- **Rôle :** Contrôle — Rideau, Poste avancé, Œil, Vision totale.
- **Qui :** « Aurélien de Haut-Vol », vautour fauve éveillé du Col du Vautour, la cinquantaine. Ancien Guetteur, il relayait les nouvelles par signaux de fumée ; il est devenu bookmaker à Saint-Ombre. Il a gagné la parole et perdu le ciel (lore §4).
- **En une ligne :** il a déjà vu ta main, et il relance quand même.
- **Motif (le vautour dandy ; le d20 devient l'emblème) :**
  - **la tête nue** de vautour : crâne de 0,24 m de large, peau lisse indigo `#5157B8`. C'est la clé, et elle couvre au moins la moitié de la tête visible ;
  - bec crochu ivoire `#D8CFB8` à pointe encre, qui dépasse de 0,09 m au plus devant le visage ; la tête fait 0,36 m de profondeur au plus ;
  - sourcils lourds, yeux or `#F2C53D` sur la ligne de 1,62 m ;
  - un petit haut-de-forme écrasé, charbon à ruban bordeaux, penché, touche 1,80 m ;
  - **la collerette** de plumes crème `#E6E1D6` fait office de col : 5 à 7 grosses plumes-volumes d'au moins 4 cm, de 1,38 à 1,47 m, sur 0,42 m de large au plus. Le ΔL avec la tête est de 0,41. De face, le dessous du bec reste visible au-dessus de la collerette.
- **Tenue :**
  - gilet bordeaux `#8E2F42` passepoilé or, nœud papillon or sous la collerette ;
  - queue-de-pie courte charbon `#2A2522`, pans au-dessus du genou ; pantalon charbon rayé ; guêtres crème ;
  - gants blancs `#E6E1D6` à quatre doigts ; manchettes de plumes brun sombre `#3B2F2A` aux poignets, 0,04 m d'épaisseur au plus ;
  - pas d'ailes, pas de queue.
- **Palette :** `#5157B8` clé · `#8E2F42` bordeaux · `#E6E1D6` collerette et gants · `#2A2522` habit · `#D8CFB8` bec · `#F2C53D` or.
- **Gadgets :**
  - une chaîne de montre en or, au bout de laquelle pend le d20 (Œil : il le lance) ;
  - un perchoir à ressort d'étoile plié à la hanche (Poste avancé) ;
  - des fusées de signal des Guetteurs dans la poche intérieure (Rideau) ;
  - la boucle-jeton frappée du d20.
- **Armes de prédilection :** Faucheur, Marqueur.
- **Crochet de silhouette :** la seule tête du roster « posée sur un col », avec son haut-de-forme de travers. C'est aussi le rectangle le plus étroit (0,46 m aux épaules) ; la collerette et les pans de la queue-de-pie le ramènent dans les ± 10 % d'aire.
- **Voix et animation :**
  - murmure poli, jamais de hausse de ton ;
  - tiptoe ;
  - en idle, les mains dans le dos et un dé qui roule entre les doigts ;
  - la tête pivote par à-coups d'oiseau : rotation seule, sans sortir de l'enveloppe.
- **Pose signature :** il soulève son chapeau, lance le d20 et le rattrape sans regarder : « Vingt. »

#### Roseau — « la Passeuse »

- **Rôle :** Soutien — Apaisement, Voile, Brume, Sursaut. Ce sont les capacités de l'ancienne Baume, renommées dans `AgentDatabase.gd` (AGT-09, lore §9).
- **Qui :** Ysé, dite Roseau, héronne cendrée éveillée du Palud, 31 ans, petite-fille de Grand-Héron. Elle fait passer le baume, et des familles, à travers la brume (lore §4).
- **En une ligne :** elle plie, elle ne rompt pas.
- **Motif (le héron, la brume) :**
  - tête de héronne, crâne de 0,22 m de large, plumage sarcelle `#2E9C8A`. C'est la clé, et elle couvre au moins la moitié de la tête visible ;
  - masque crème `#EFE3C8` ;
  - bec en poignard ocre `#E0A43A`, qui dépasse de 0,14 m au plus devant le visage. Tête et huppe tiennent dans 0,36 m de profondeur ;
  - yeux jaunes `#F2C53D` à 1,62 m, prolongés par un trait d'encre ;
  - **la huppe** : trois plumes sombres `#1F2A33` fondues en une seule masse pleine, d'au moins 4 cm d'épaisseur, couchée vers l'arrière, sommet à 1,80 m. Jamais d'aigrette fine.
- **Tenue :**
  - **le col** est une écharpe tissée crème `#E6E1D6` à frise de triangles sarcelle, montée jusqu'à la mâchoire (1,40 à 1,48 m). Elle cache le long cou. Le ΔL avec la tête est de 0,28 ;
  - long manteau ciré gris ardoise `#6F8594`, col montant, ceinturé, fendu dans le dos. Il s'évase en A de 0,08 m au plus au-delà du corps et s'arrête au-dessus du genou, à 0,50 m du sol au moins ;
  - cuissardes charbon `#2A2522` ;
  - mitaines de cuir `#6B4A2E` sur des mains à quatre doigts, écailleuses et grises (`#7D8A8E`).
- **Palette :** `#2E9C8A` clé · `#6F8594` ciré · `#E6E1D6` écharpe · `#2A2522` équipement · `#E0A43A` bec · `#C8322B` flotteurs.
- **Gadgets :**
  - une cartouchière de 5 flotteurs-mouchards rouge et crème en travers du buste, sous 1,38 m (Voile) ;
  - deux bocaux de brume du Palud à la hanche droite (Brume) ;
  - une boîte de baume en fer à la ceinture (Apaisement, Sursaut) ;
  - une petite lanterne de laiton à la hanche gauche ;
  - la boucle-jeton frappée du flotteur, celui de Grand-Héron.
- **Armes de prédilection :** Marqueur, Pistolet.
- **Crochet de silhouette :** le seul profil en flèche du roster, sur un A long (manteau et cuissardes).
- **Voix et animation :**
  - voix grave et sèche, six mots par phrase au plus ;
  - pas d'affût : genou haut, pied posé lentement, cadence ×0,95 ;
  - pendant Apaisement, elle replie une jambe et tient sur une patte ; la hauteur des yeux ne change pas ;
  - en visée, la tête avance par à-coups : rotation seule.
- **Pose signature :** elle dévisse un bocal. La brume lui coule sur les bottes ; elle y disparaît jusqu'aux genoux et lève les yeux.

#### Verrou — « le Crapaud »

- **Rôle :** Soutien — Chausse-trape, Passerelle, Rempart, Bastion.
- **Qui :** dendrobate azuré éveillé, 30 ans. Premier Éveillé maréchal de la Charte, pour le district du Palud. Il a été élevé à Val-Poussière par le shérif Anselme Verrou, dont il porte le nom et l'étoile (lore §4).
- **En une ligne :** lent à dégainer, jamais pressé, jamais pris.
- **Référence :** le modèle 3D approuvé `assets/models/characters/verrou.glb` (planche : `assets/incoming/tripo/verrou_v1_preview/`). Cette fiche le décrit, elle ne le redessine pas.
- **Motif (la grenouille maréchal) :**
  - tête de grenouille de la taille d'une tête de jeu, large bouche au demi-sourire ;
  - deux gros yeux dorés `#F2C53D` à pupille noire, au sommet du crâne (jusqu'à 1,78 m) ;
  - peau cobalt `#2A5FC4`, **humide** (reflet), à taches d'encre `#1A1410` ; gorge bleu pâle `#A9C1DE`, qui remplace l'ocre de la v3.1 comme sur le modèle approuvé ;
  - chapeau de cowboy en cuir brun `#6B4A2E`, repoussé derrière les yeux, bord relevé sur les côtés, qui touche 1,80 m. Dans le lore, c'est pour passer sous la Toise.
  - **À mesurer :** sur le modèle approuvé, le bord du chapeau semble dépasser les 0,34 m de large de l'enveloppe. Si CHK-23 échoue, on resserre le bord dans Blender, et rien d'autre.
- **Tenue :**
  - poncho court grège `#CDBB98`, à col-capuche souple (c'est son col) et frise de triangles cobalt et crème (celle de la Mare-au-Tison). L'étoile de maréchal est épinglée **dessous**, invisible ;
  - chemise moutarde `#C98F3A` aux manches retroussées, gilet charbon `#2A2522` ;
  - avant-bras nus cobalt ; gantelets de cuir brun sombre `#4A3528` sans doigts ; mains de grenouille à 4 doigts à ventouses ;
  - jean marine `#2B3550`, bottes de cowboy charbon `#2F2A2A`.
- **Palette :** `#2A5FC4` clé · `#CDBB98` poncho · `#C98F3A` chemise · `#2B3550` jean · `#6B4A2E` cuir · `#1A1410` taches · `#F2C53D` yeux · `#E0574A` écrevisse.
- **Gadgets :**
  - un ceinturon de cuir à boucle d'acier ronde, qui est son jeton ;
  - un étui sur la hanche droite, avec le Magnum gainé de mue d'écrevisse corail `#E0574A` ;
  - une sacoche grise sur la hanche gauche, pour les plaques de glu (Chausse-trape) ;
  - le radeau-ressort (Passerelle) et la levée de roseau (Rempart, Bastion) ne sont pas portés : ils se déploient.
- **Armes de prédilection :** Magnum. Le skin signature « Écrevisse » est le sien.
- **Crochet de silhouette :** deux yeux ronds et un chapeau rejeté au sommet, le A du poncho.
- **Voix et animation :**
  - voix traînante et basse ;
  - pas chaloupé de cowboy ;
  - la gorge pulse en idle ; petit rebond de 3 cm à chaque arrêt.
- **Pose signature :** il repousse son chapeau d'un coup de langue.

### 4.5 Matériaux et shading des personnages

- **Shader :** `ink_toon` en mode personnage (§7.2) : 2 bandes, douceur 0,04, teinte d'ombre de la carte, **aucun grain**.
- **Par matière :**

| Matière | Douceur | Ombre | Reflet dur | Règles |
|---|---|---|---|---|
| Peau humaine | 0,06 | teinte de la carte mélangée à 0,25 (au lieu de 0,40), décalée de +8° vers le chaud ; sur une peau foncée, l'ombre reste à L ≥ 0,30 | non | nez, lèvres et paupières en géométrie simple ; pas de coque d'encre sur le nez ; sourcils d'au moins 1,5 cm ; sclère crème et iris sombre, le point le plus contrasté du visage |
| Peau de créature (grenouille) | 0,04 | comme le tissu | oui : peau humide, 2 taches de reflet au plus | taches en géométrie ou en décalque, jamais en bruit |
| Plumage (Roseau, Guet) | 0,05 | comme le tissu | non | duvet en géométrie ou en décalque ; jamais en bruit ; mains et pieds restent en peau de créature |
| Cheveux, flamme | 0,04 | comme le tissu | un reflet dur allongé | 3 à 7 mèches-volumes pleines ; aucune mèche de moins de 4 cm ; aucune carte de cheveux en alpha |
| Tissu | 0,04 | teinte de la carte à 0,40 | non | 3 à 5 grands plis modelés par vêtement ; coutures en biseau ou en décalque |
| Cuir | 0,04 | idem | satiné, 0,15 | arêtes éclaircies par le masque de convexité (vertex G) |
| Métal peint, fonte | 0,04 | idem | non | arêtes polies claires grâce au masque de convexité ; ni métal PBR ni reflet d'environnement |
| Émail, laque, laiton, or | 0,04 | idem | oui : force 0,35, taille 0,12 | casque de Choc, tête de Guet, rivets, boucles, étoile |

- **AO en vertex color** cuite dans Blender (canal R, min 0,60), sous le menton, sous le col et dans les plis.
- **Contours** (inchangés) :
  - coque d'encre `#1A1410` : 3 px jusqu'à 10 m, 2 px à 40 m, plancher de 1,5 px (1080p, mis à l'échelle hauteur/1080) ;
  - ennemi : coque de surbrillance de 3,5 → 2,5 px **qui ne s'efface jamais**, plus 1 px d'encre à l'extérieur (conservé de v2).
- **Rim de ciel :** fresnel 0,20, teinte de l'horizon de la carte. Il détache le personnage du fond et ne porte aucune information d'équipe.
- **Budgets :** au plus 15 000 triangles, dont 3 000 pour la tête (visage et cheveux compris) ; 384 px/m, et 512 px/m pour la tête ; biseau de 1 cm ; LOD à 25 et 50 m.
- **Chaîne de production :**
  1. concept, à partir de [`docs/style/character_prompts.md`](style/character_prompts.md) ;
  2. validation par l'utilisateur ;
  3. Tripo image→3D, **forme seule** ;
  4. nettoyage et retopologie dans Blender ;
  5. calage sur le gabarit et skinning sur UAL-G ;
  6. slots de matériau (`outfit`, `cloth`, `gear`, `skin`, `accent`) et masques vertex ;
  7. `check_asset.py` (CHK-23, CHK-25) ;
  8. turntable.

  Un maillage Tripo n'est jamais livré tel quel.

### 4.6 Personnalité d'animation

- **Base partagée :** les 46 actions UAL, sur UAL-G, pour tous les agents.
- **Couche additive par agent :** amplitude de rebond, inclinaison du buste, cadence de pas (×0,9 à ×1,15), idle unique et pose de kill (emote de 1,2 s, en fin de manche seulement).
- **Garde-fous de hitbox :**
  - debout, la couche additive ne fait jamais descendre les yeux sous 1,56 m ni le menton sous 1,43 m ;
  - aucune démarche accroupie ou voûtée hors de l'état Crouch ;
  - buste penché de 8° au plus ;
  - jamais d'écrasement de la tête.
- **Démarches** (planche de l'épingle 09) :

  | Agent | Démarche |
  |---|---|
  | Vif | course légère, skip |
  | Choc | strut |
  | Vanne | pas mesuré de métronome |
  | Guet | tiptoe |
  | Roseau | pas d'affût : genou haut, pied posé lentement |
  | Verrou | pas chaloupé de cowboy |

- **Anticipation et exagération sur les actions lisibles :**
  - Lancer de capacité : 120 ms d'anticipation visible en vue à la troisième personne.
  - Rechargement : le chargeur sort franchement du cadre.
  - Aucune exagération qui déplace la hitbox ou retarde un tir.

### 4.7 Bras à la première personne

- **Un seul gabarit :** les avant-bras d'UAL-G, la pose de tenue `FP_Hold` et des points de prise identiques pour les six agents. L'arme est au même endroit à l'écran quel que soit l'agent ; la couverture et le cadrage du §5.3 ne changent pas.
- **Ce qui change par agent :** la manche et la main.

  | Agent | Manche | Main |
  |---|---|---|
  | Vif | veste braise `#9A4A2C` à bande crème ; brassard-grattoir à gauche | peau `#D29A6E`, mitaine de course charbon |
  | Choc | bras nu `#6B4330`, bandages crème | mitaine de combat à manchette rouge |
  | Vanne | manche de toile écrue `#BFAE86`, chevrons jaune et encre à l'avant-bras droit | gantelet de cuir `#6B4A2E` |
  | Guet | manche retroussée crème, bouton de manchette or | gant blanc `#E6E1D6` à quatre doigts |
  | Roseau | manche de ciré gris ardoise `#6F8594` | mitaine de cuir `#6B4A2E` sur main écailleuse grise `#7D8A8E` à 4 doigts |
  | Verrou | avant-bras cobalt à taches | main de grenouille à 4 doigts, ventouses ocre, reflet humide |

- **Limites :**
  - volume d'au plus 2 cm autour de l'avant-bras d'UAL-G ; mains à ×1,15 au plus ;
  - couverture d'écran à ± 1 % de celle du gabarit ;
  - aucune surface de plus de 5 % de l'écran sous L 0,30. En vue FP, le charbon passe au cuir `#6B4A2E`, parce qu'il noircit de près ;
  - coque d'encre de 2 px constants ; jamais de couleur ni de surbrillance d'équipe.

### 4.8 Ce qui change par rapport à la v3

| Sujet | v3 | v3.1 |
|---|---|---|
| Concept | têtes-objets sur des corps de mascotte | héros athlétiques ; l'objet devient motif et emblème |
| Proportions | tête à 1:4,5 (0,40 m) | crâne à 1:7 (0,26 m), tête coiffée entre 1:6 et 1:6,5 |
| Règle de tête | la tête-objet remplit la boîte 1,40–1,80 m | au-dessus du col (1,40 m), le col et la tête, rien d'autre ; enveloppe commune de 0,34 × 0,36 m, aire de face de 0,046 à 0,058 m² |
| Hauteur | 1,80 m, plus 6 cm de chapeau tolérés | 1,80 m pile, tout compris (mise à l'échelle par la boîte englobante) |
| Repères | épaules à 1,30–1,34 m, entrejambe à 0,72 m, mains ×1,4, pieds ×1,3 | deltoïdes ≤ 1,38 m, yeux à 1,62 m, menton à 1,49 m, entrejambe à 0,84 m, mains et pieds ×1,15 |
| Squelette | UAL mis à l'échelle ×0,92, tête du mannequin supprimée | UAL-G : épaules abaissées, cou allongé, tête replacée, jambes intactes |
| Nouveautés | — | gabarit accroupi, yeux alignés sur la caméra, aire de silhouette à ± 10 %, longueur de bras commune, bras FP par agent |
| Nature | 6 objets | 3 non-humains (vautour, héronne, grenouille) et 3 humains (lore §4.0) |
| Animation | Verrou en démarche accroupie ; écrasement de la tête | pas chaloupé ; écrasement du corps seul, de 0,97 à 1,03 |
| Élimination | la tête-objet tombe et roule | l'emblème tombe et roule (§9.5) |
| Couleurs | — | clés inchangées ; blancs 3D en émail crème `#E6E1D6` (le papier `#F4EDE1` dépassait l'albédo maximal) ; nouvelles secondaires : Vif braise `#9A4A2C` et peau `#D29A6E`, Choc peau `#6B4330`, Vanne bleu de Prusse `#2E4A6B`, Guet bordeaux `#8E2F42` (L 0,40 → 0,45), Roseau ciré `#6F8594` |

**À resynchroniser (non fait dans cette révision) :**
- `docs/style/tokens.json` : les blocs `character` et `agents.*` (tête, forme, palette, démarche) et les seuils `checks.CHK-22` et `CHK-23` décrivent encore la v3. Tant qu'ils ne sont pas repris (tâche ART-10), `style_check` juge l'ancien gabarit.
- `tasks/backlog.yaml` : A3D-08 (têtes d'objet) est caduque ; ART-10, ART-11, ART-15, ART-16, ART-17, ART-19 et ART-43 sont à réaligner sur le §12 de cette bible, que `plan.py import` n'applique pas aux tâches existantes.
- `docs/style/concepts/` : les planches `vif_s*` et `verrou_s*` (têtes-objets) sont périmées.

## 5. Armes
<a id="5-armes"></a>

### 5.1 Langage de formes : « l'archétype d'abord, la blague ensuite »

1. **La silhouette de profil reste celle de l'archétype réel** : pistolet, revolver, SMG, fusil, pompe, sniper, mitrailleuse. Un joueur doit classer l'arme au premier coup d'œil.
   - Test : 9 personnes sur 10 la classent correctement à partir d'une silhouette noire de 64 px de large.
2. **Les éléments-clés sont exagérés** de ×1,2 à ×1,5 : chargeur, bouche, organe de visée, talon de crosse. Le reste est sobre.
3. **Une seule signature fantaisiste par arme**, tirée du monde de l'atelier et de la foire (tromblon, feutre-viseur, trémie de semoir). Elle ne doit jamais changer l'archétype.
4. **Matériaux** (tous hors bandes réservées ; aucun bleu, pour ne pas confondre avec l'allié) :
   - acier émaillé `#4A505C` ;
   - bois `#9C6A42` ;
   - laiton `#D9A21B` ;
   - émail crème `#E6E1D6` ;
   - un accent émaillé par arme, pris dans rouge `#C8322B`, orange `#E3872A`, jaune `#F2B51D`, sarcelle `#2E8C86` ou papier.
5. **Biseaux :** 3 mm en vue à la première personne (FP), 1 cm en vue à la troisième personne (TP). Normales pondérées, reflet dur uniquement sur l'émail et le laiton.
6. **Deux emplacements d'autocollant par arme** (flanc de crosse, chargeur), UV réservés à 512 px/m pour les cosmétiques (épingle 13).

### 5.2 Les dix armes

Ordre et identifiants : `WeaponDatabase.PATHS` (append-only).

| # | Arme | Catégorie | Archétype lisible | Signature fantaisiste | Accent | Onomatopée de kill |
|---|---|---|---|---|---|---|
| 0 | **Pistolet** | poing (gratuit) | pistolet compact carré | « pistolet de starter » : carcasse émail crème, bague de bouche rouge, grosse hausse carrée | rouge | PAN ! |
| 1 | **Magnum** | poing | revolver à canon long | barillet ×1,4 en laiton peint en roue de foire (6 cases rouge/crème), crosse bois | rouge/crème | PAN ! |
| 2 | **Rafale** | SMG | compact, chargeur droit long | chargeur ×1,3 orange, crosse en fil d'acier pliée, poignée avant en manivelle de moulin à café | orange | RATATA ! |
| 3 | **Marqueur** | fusil semi | fusil de précision court | le viseur est un **gros feutre marqueur** (capuchon rouge = cache-lentille), crosse bois, pochoir « X » | rouge | BAM ! |
| 4 | **Ravage** | fusil auto | fusil d'assaut, chargeur courbe | l'arme « héros » : garde-main émail rouge, chargeur courbe ×1,25, poignée de transport, plaque « 07 » | rouge | BAM ! |
| 5 | **Fracas** | pompe | pompe à tube | **bouche de tromblon** en laiton évasée ×1,5, pompe bois, cartouches rouges visibles sur le flanc | laiton | BRAOUM ! |
| 6 | **Faucheur** | sniper | verrou très long + lunette | lunette de Ø ×1,5 à bagues laiton, levier de culasse recourbé en **crochet de faux**, bipied replié | crème | CLAC ! |
| 7 | **Éclair** | SMG | très court, chargeur horizontal au-dessus | chargeur supérieur jaune chantier à pochoir éclair, bouche en bec | jaune | RATATA ! |
| 8 | **Semeuse** | lourde | mitrailleuse à bande + bipied | **trémie latérale de semoir** en tôle sarcelle, pochoir « GRAINES », bande en laiton, bipied déplié | sarcelle | TATATATA ! |
| 9 | **Percuteur** | fusil semi lourd | battle rifle | gros **chien apparent** façon levier, canon épais sous manchon perforé, chargeur court droit | orange | BAM ! |

**Distinguer les trois fusils à 64 px de large :**
- **Ravage :** chargeur courbe + poignée de transport.
- **Percuteur :** chien + manchon perforé + chargeur droit court.
- **Marqueur :** viseur-feutre haut + crosse bois pleine.

### 5.3 Cadrage à la première personne

Mesures en 16:9. Coordonnées normalisées de l'écran, (0,0) en haut à gauche.

| Règle | Cible |
|---|---|
| FOV du viewmodel | 54° vertical, fixe, indépendant du FOV monde (qui reste réglable) |
| Ancrage | quart inférieur droit ; la main de tir est visible, la crosse coupée par le bord droit ou le bas |
| Bout du canon à la hanche | x 0,58–0,64, y 0,56–0,64 |
| Zone centrale 20 % × 20 % | **vide** à la hanche (réticule, hitmarkers) |
| Couverture d'écran à la hanche | poing 7–10 %, SMG 11–15 %, fusils 13–17 %, pompe 15–19 %, sniper 15–19 %, lourde 18–22 % |
| Visée (ADS) | organe de visée centré, bord haut de la hausse à y 0,50 ± 0,02, couverture ≤ 28 % |
| Lunette (Faucheur) | overlay plein écran : anneau laiton, vignette encre, réticule encre filé papier 1 px ; hors de la lunette, noir encre à 100 % |
| Sprint | arme pivotée de 25° vers le bas et la gauche, couverture ≤ 20 % |
| Balancement / bob | sway ≤ 1,5°, bob 1,2 cm en marche et 2,5 cm en sprint ; divisés par 2 en mouvement réduit |
| Rechargement | le chargeur sort **entièrement** du cadre, anticipation ×1,2 ; lisible sans le son |
| Mains | manche et main de l'agent (§4.7), mains ×1,15 au plus : on sait qui l'on joue sans HUD |
| Contour | coque d'encre de 2 px constants (conservé de v2), jamais de surbrillance d'équipe |

Aujourd'hui (`fp_ravage`), l'arme est centrée et couvre le réticule, avec environ 25 % de couverture et le canon à x 0,52. C'est à corriger en ART-12.

### 5.4 Armes au sol et en vue à la troisième personne

- **Vue à la troisième personne :** 1 200–2 000 triangles. Les parties fines sont épaissies à ≥ 4 cm, la silhouette et l'accent sont identiques à la version FP.
- **Au sol :** coque d'encre de 2 px, rotation de 30°/s, flottement de 6 cm, anneau papier au sol (décalque, Ø 0,8 m). Le nom de l'arme apparaît en autocollant à ≤ 4 m.

## 6. Environnement
<a id="6-environnement"></a>

### 6.1 Le décor est un plateau peint

- **Le sol se tait, les objets parlent.** Chroma OKLCH :

  | Élément | Chroma max |
  |---|---|
  | Sol jouable | ≤ 0,10 |
  | Couvert, props | ≤ 0,18 |
  | Repères, enseignes | ≤ 0,20 |
  | Couleur-clé des agents | 0,10–0,20 |
  | Réservé à l'ennemi | 0,22–0,26 |

  Aujourd'hui, le sol de Wasteland est à C ≈ 0,15 en rendu : il devient `#D2A46C`, C 0,09.
- **Une couleur saturée par objet.** Un conteneur est rouge, point. Le reste de l'objet est de l'acier neutre, du bois ou de l'émail crème.
- **Des jouets biseautés, légèrement de guingois.**
  - Les verticales des « skins » (façades, silos, grues) penchent de 1 à 3° en alternance.
  - Les faîtières s'affaissent de 2 à 5 cm tous les 4 m.
  - **Le dessus d'un couvert reste droit et horizontal** : le peek doit être prévisible.
- **Le détail, c'est de la géométrie ou un décalque.** Rivets, pochoirs, numéros, rustines, autocollants, trims de bord. **Jamais du bruit.**
- **Les gravats et dégâts sont gros et biseautés** (épingle 22) : des morceaux de 10 à 40 cm, jamais des miettes.

### 6.2 Structure de valeurs

Mesures en OKLab L et C sur la capture finale, soleil de face ou de trois quarts.

| Plan | Distance | L | C | Rôle |
|---|---|---|---|---|
| Ciel zénith | — | 0,52–0,65 | 0,10–0,17 | cadre sombre en haut |
| Ciel horizon | — | 0,82–0,93 | ≤ 0,08 | fond clair pour les silhouettes de toit |
| Arrière-plan (coulisses) | > 60 m | 0,70–0,85 | ≤ 0,06 | noyé de brume, jamais d'ink noire |
| Plan moyen (façades, skins) | 15–60 m | 0,50–0,80 | 0,05–0,14 | là où vivent les repères |
| Premier plan : sol | 0–15 m | 0,60–0,78 | ≤ 0,10 | fond calme sous les corps |
| Premier plan : couverts, props | 0–15 m | 0,45–0,80 | ≤ 0,18 | dessus plus clair (+6 % L) que les flancs |
| Personnages | toutes | 0,45–0,72 (tenue) | 0,10–0,20 | se détachent du sol clair et des ombres sombres |
| Ombres (monde) | — | 0,62–0,70 × L éclairé, **jamais < 0,30** | teinte vers l'ombre de la carte | lisibles, jamais bouchées |
| Encre | — | 0,20 | — | seul noir de l'image |

**Zone morte à éviter :** les grands aplats (> 4 m²) à hauteur de joueur avec L entre 0,44 et 0,50 et C < 0,05, c'est-à-dire du gris moyen. Le Magenta y perd du contraste de luminance (vérifié : 2,5–2,7:1). Les ombres de pont gris de Cargo Ship sont dans ce cas. Elles restent lisibles par la teinte (ΔE_OK ≥ 34), et la checklist §11 contrôle les deux critères.

### 6.3 Lumière, ciel, brouillard, coulisses

- **Soleil :**
  - Une seule `DirectionalLight3D`, chaude, élévation 22–50° selon la carte (§6.4).
  - Azimut à 60–90° des lanes principales, jamais dans l'axe d'une ligne de vue de spawn.
  - Ombres portées nettes : `light_angular_distance` 0,5°, PSSM 4 splits, portée 120 m.
- **Rampe :** 2 bandes, bord doux (§7.2). Ombre = 0,62–0,70 × la valeur éclairée, teintée vers l'ombre de la carte (35–45 % de mélange). Plus de « 0,58 × teinte linéaire », qui rend les ombres à environ 0,40 × L (mesuré) : c'est la boue de §0.
- **Ambiance :** ciel à 0,18 d'énergie (au lieu de 0,25), SSAO rayon 0,8 m, intensité 1,0. La bounce sable est gardée à 0,12 en émission sur les faces tournées vers le bas.
- **Ciel peint** (`ink_sky.gdshader`) :
  - Dégradé zénith → horizon par carte, disque solaire net plus un halo doux.
  - **Gros** cumulus à base plate en deux tons, sans encre, à 6–30° d'élévation, couverture 30–35 %, échelle ×0,6 de l'actuelle : 3 à 5 masses lisibles par demi-ciel au lieu de 30 miettes.
- **Brouillard :**
  - Couleur de l'horizon mêlée à 40 % de la couleur du soleil (conservé).
  - 5 % à 35 m, 20 % à 150 m, 35 % à 300 m (densité exponentielle 0,00149, conservée).
  - Il ne touche jamais le ciel (`fog_sky_affect` 0).
- **Coulisses** (nouveau, obligatoire) : un anneau de silhouettes à plat entre 150 et 600 m, qui ferme l'horizon à 100 % sous 5° d'élévation.
  - Désert : mesas, derricks lointains, poteaux.
  - Port et cargo : mer, quais lointains, grues, cargos.
  - Ville : toits, cheminées.
  - Montagne : crêtes enneigées.
  - Rendu : `unshaded`, 2 à 3 teintes par carte, voilées vers l'horizon. Plus aucune vue où la carte flotte dans le vide.

### 6.4 Palettes par carte

Format :
- ciel : zénith → horizon ;
- soleil : couleur / élévation ;
- ombre : teinte ;
- sol ;
- matériaux (≤ 7, une couleur saturée par prop) ;
- repères.

Toutes les teintes ont été vérifiées :
- hors des bandes réservées ;
- anneau ennemi : WCAG ≥ 3:1 **ou** ΔE_OK ≥ 25 en vision normale ;
- pour chaque type de daltonisme, l'option recommandée garde un ΔE_OK min ≥ 9 : Citron pour protan et deutan, Magenta pour tritan.

Les heures de la journée de `MapCatalog` sont alignées sur celles-ci (tâche ART-22).

| # | Carte | Heure | Ciel | Soleil | Ombre | Sol | Matériaux | Repères |
|---|---|---|---|---|---|---|---|---|
| 01 | Port-Ferraille | matin, brume levée | `#4A8FE0` → `#D6ECF6` | `#FFF1D0` / 40° | `#5F71A8` | quai `#BBA98C` | coques `#2E8C86`, rouille `#B5562A`, ardoise `#56657A`, ocre `#C9853F`, os `#E6E1D6`, grue `#E3872A`, eau `#2A7F9E` | grue portique orange, phare rayé rouge/papier, cargo en cale sèche |
| 02 | Val-Poussière | heure dorée | `#3C7FD9` → `#F2D7A8` | `#FFC98A` / 28° | `#6A63A0` | terre battue `#C9A06E` | adobe `#D08F5A`, volets `#3FA3A0`, bois `#9C6A42`, clôtures `#C99A68`, tuiles `#B8553A`, cactus `#5E9A86`, clocher `#EDE4CF` | château d'eau, clocher blanc, enseigne du saloon |
| 03 | Saint-Ombre | fin d'orage, crépuscule (la plus sombre) | `#3F6F86` → `#F0B860` | `#FFB870` / 22° | `#3E4F7A` | pavés mouillés `#6E6A73` | brique `#A5492F`, fonte `#4A505C`, lampes `#FFB347` (émissif), enduit `#D9C7A5`, pierre `#8C7F72` | cheminée d'usine rayée, horloge éclairée, pont métallique |
| 04 | Col du Vautour | midi alpin | `#1F63D0` → `#CFE6F7` | `#FFF6E0` / 42° | `#6C86C8` | neige `#F1F4F8` (ombre `#A9BCE3`) | cabanes `#B83A2C`, barrières `#F2B51D`, roche `#7E7A86`, antenne `#E6E1D6` / `#C8322B` | antenne rayée, téléphérique jaune, statue du vautour |
| 05 | La Fosse | midi, carrière | `#3A80DC` → `#D3E7F5` | `#FFE0A6` / 50° | `#6072AE` | calcaire `#E3D3AE` | ocre `#C9853F`, engins `#F2B51D`, gradins `#CDBB94`, bois `#9C6A42` | pelleteuse jaune, blondin (grue à câble) |
| 06 | Le Belvédère | aube | `#5A8FD8` → `#FFD9A0` | `#FFD3A0` / 25° | `#5E6AA8` | toits-terrasses `#C9B79A` | tuiles `#C4603A`, zinc `#8FA3B0`, cheminées `#A5492F`, enduit `#EAD9BE` | dôme de zinc, antenne TV, enseigne « HÔTEL » éteinte |
| 07 | Wasteland | fin d'après-midi | `#2F74D8` → `#BFDDF2` | `#FFD99A` / 32° | `#5B6CA6` | sable `#D2A46C` | piste `#C58B4E`, rouille `#B5562A`, tôle `#4F7FA8`, bois `#9C6A42`, béton `#B8AFA0`, FUEL `#3E7BB5`, GAS `#B8322A` | auvent et panneau FUEL (spawn bleu), château d'eau, grue, derrick, GAS et réservoirs (spawn rouge) |
| 08 | Cargo Ship | fin de matinée au mouillage | `#3E86E0` → `#CDE8F8` | `#FFF0C8` / 45° | `#5A6EA8` | pont `#8D959B` | conteneurs `#C8322B` / `#2F63B8` / `#E3872A` / `#E6E1D6`, danger `#F2B51D` + encre, coque `#7E251D`, mer `#1E7FA0`, passerelle `#EDEBE4` | passerelle blanche + mât, grues de pont, mât de proue |

**Changements par rapport à v2 :**
- Le sable de Wasteland passe de `#D9A15C` (C 0,11) à `#D2A46C` (C 0,09).
- La coque de Cargo passe de `#A13326` à `#7E251D` (l'anneau Magenta passe de 2,6 à 3,1:1).
- Les ciels de `Cartoon._MAP_PALETTES` reviennent aux valeurs de conception : les assombrissements y compensaient l'exposition 0,42, supprimée en §7.5.
- Saint-Ombre passe de « nuit pluvieuse » à « fin d'orage » : le style ne vit pas la nuit.
- Cargo Ship passe de « crépuscule » à « fin de matinée », comme sa planche de référence.

### 6.5 Langage des props

| Famille | Thème | Exemples | Règle de forme |
|---|---|---|---|
| Skins (murs de lane) | tous | façades, conteneurs empilés, citernes, coques | hauts (≥ 3 m), une couleur, trims clairs en arête, pochoirs |
| Couverts | tous | caisses, conteneurs ouverts, bottes de foin, sacs de sable, capots de cale | **deux hauteurs seulement** : 1,1 m (accroupi) et ≥ 2,0 m (debout) ; dessus plus clair, bord biseauté bien encré |
| Décor fin (non-couvert) | tous | poteaux, clôtures, rambardes, panneaux | ≤ 0,15 m d'épaisseur ou ajouré à ≥ 50 % : **il doit avoir l'air de ne pas protéger** |
| Repères | un par zone | FUEL, GAS, grue, derrick, château d'eau, passerelle, phare | silhouette unique découpée sur le ciel, la couleur la plus saturée de la carte, lisible depuis ≥ 70 % de la surface jouable |
| Humour de plateau | tous | panneaux peints à la main, autocollants de l'émission, projecteurs en coulisse | jamais dans une lane, jamais à hauteur de tête d'agent (1,40–1,80 m) |

**Rien d'humanoïde entre 1,5 et 1,9 m** (conservé de v2) : pas de mannequin, de statue grandeur nature ni de silhouette de cible qui imiterait un agent.

### 6.6 Densité de texels, biseaux, budgets

| Élément | Densité | Biseau | Budget triangles (LOD0) | LODs |
|---|---|---|---|---|
| Architecture, skins (≥ 3 m) | 256 px/m (trim-sheet) | 6 cm, 2 segments | ≤ 6 000 par module | 50 % à 30 m, 20 % à 60 m |
| Props moyens (1–3 m : conteneur, caisse) | 256 px/m | 4 cm (conteneur), 2,5 cm (caisse) | 800–3 000 | 50 % à 25 m |
| Petits props (< 1 m) | 256 px/m | 1,2 cm | 200–800 | coupés à 40 m |
| Repères | 256 px/m + décalques 512 px/m | 6–8 cm | ≤ 15 000 | 50 % à 60 m |
| Décalques (pochoirs, autocollants, texte) | 512 px/m | — | quads | — |
| Terrain (triplanaire) | 1 répétition / 4 m, texture 1024² | — | — | — |
| Personnage | 384 px/m (tête 512 px/m) | 1 cm | ≤ 15 000 (tête ≤ 3 000) | 50 % à 25 m, 20 % à 50 m |
| Arme FP / TP | 512 px/m / 128 px/m | 3 mm / 1 cm | 8–12 000 (+ gants 5 000) / 1 200–2 000 | — |

**Budgets de carte :**

| Mesure | Bureau (1080p, cible 144 fps) | Steam Deck (800p, cible 60 fps) |
|---|---|---|
| Triangles visibles au pire endroit, ombres comprises | ≤ 2,5 M | ≤ 1,2 M |
| Draw calls | ≤ 1 500 | ≤ 800 |
| Matériaux shader uniques par carte | ≤ 24 | ≤ 24 |

- Props répétés en `MultiMesh`, décor statique fusionné par cellule de 16 m (conservé de v2).
- La variété vient des vertex colors et de la teinte d'instance, pas de nouveaux matériaux.
- Mesure de référence (Phase 0, `docs/PERF.md`) : 65 draw calls à 275 fps. Chaque tâche d'art qui touche une carte refait le benchmark.

### 6.7 Repères et lisibilité du couvert

1. **≥ 3 repères par carte 4v4** (≥ 2 en duel), chacun avec une silhouette unique, une couleur unique parmi les matériaux de la carte, et visible au-dessus des toits depuis ≥ 70 % de la surface jouable.
2. **Les spawns sont nommés par leur repère** : FUEL bleu et GAS rouge sur Wasteland ; passerelle et proue sur Cargo. Le repère du spawn allié ne peut pas être de la couleur ennemie.
3. **Couverts :**
   - Dessus éclairé + arête biseautée encrée.
   - Au moins 25 % de valeur d'écart entre le couvert et le sol derrière lui.
   - Hauteurs normalisées 1,1 / 2,0 m.
4. **Les silhouettes de toit se découpent sur l'horizon clair**, jamais sur un nuage : les cumulus restent au-dessus de 6°.
5. **Les zones de site** (plant/defuse, hardpoint) portent un grand décalque au sol (lettre A/B en pochoir de 2 m, jaune objectif `#F2C230` + encre). C'est le seul usage du jaune objectif dans le décor.

## 7. Rendu
<a id="7-rendu"></a>

### 7.1 Chaîne complète

```
Blender (bpy)                                    Godot 4.7 Forward+
─────────────                                    ──────────────────
forme biseautée + normales pondérées  ──►  ink_toon v3 : 2 bandes, ombre perceptuelle,
UV 256 px/m (trim-sheet)                   masques vertex (AO / arête / hauteur / zone),
vertex color "masks" RGBA :                lavis monde ±4 %, reflet dur (laqués)
  R = AO   G = arête convexe                       │
  B = gradient de hauteur  A = zone        ink_outline : coque persos / armes / pickups
                                                   │
décalques (pochoirs, autocollants) ──────► Decal / quads, 512 px/m
                                                   │
                                           ink_edges v3 (post) : silhouette profondeur
                                           + plis par normale (≤ 30 m)
                                                   │
                                           LevelLook : tonemap linéaire WYSIWYG,
                                           ciel v3, coulisses, brouillard léger
```

**Règle d'or :** aucune couleur n'est inventée par le moteur. L'albédo est la couleur. Le shader ne fait que 2 bandes de lumière, une teinte d'ombre et des masques cuits. Si un rendu est boueux, c'est l'asset qui est en tort, pas un réglage global à compenser.

### 7.2 `assets/shaders/ink_toon.gdshader`

| Paramètre | Actuel | Cible monde | Cible personnage | Note |
|---|---|---|---|---|
| `band_count` | 3 | **2** | **2** | épingles 08 et 18 : un ton de lumière, un ton d'ombre |
| `band_softness` | 0,05 | **0,10** | **0,04** | bord peint au monde, net aux persos |
| `shadow_strength` | 0,58 (× teinte linéaire) | **remplacé** par `shadow_value` = **0,66** | 0,66 | **ratio de L OKLab** ombre/éclairé ; en linéaire : albédo × lerp(1, teinte / lum(teinte), `shadow_tint_mix`) × 0,27–0,32 |
| `shadow_tint_mix` *(nouveau)* | — | **0,40** | 0,40 | teinte d'ombre de la carte à luminance normalisée |
| `hot_edge_chroma` | 0,15 | **0,20** | 0 | seulement au monde |
| `ground_bounce_strength` | 0,15 | **0,12** | 0,08 | — |
| `paint_grain_strength` | 0 / 0,02–0,06 (persos) | **0** | **0** | le grain se lit comme du bruit |
| `use_vertex_masks` *(nouveau)* | — | **true** (assets Blender) | true | lit `COLOR` RGBA |
| `ao_min` *(nouveau)* | — | **0,55** | 0,60 | R : multiplie l'albédo, de `ao_min` à 1 |
| `edge_highlight` *(nouveau)* | — | **0,15** | 0,08 | G : +15 % de valeur sur les arêtes convexes (biseaux) |
| `height_grad` *(nouveau)* | — | **0,88 → 1,04** | 0,94 → 1,02 | B : bas plus sombre, haut plus clair (objet normalisé) |
| `wash_scale` / `wash_strength` *(nouveau)* | — | **0,35 / 0,04** | 0 / 0 | lavis monde basse fréquence (période ≈ 2,9 m), ±4 % de valeur et ±3° de teinte : casse la répétition sans bruit |
| `gloss_strength` / `gloss_size` *(nouveau)* | — | 0 (sauf émail et laiton : 0,25 / 0,10) | **0,35 / 0,12** sur les laqués | reflet dur : `smoothstep(1 - size, 1 - size + 0,02, dot(N, H))`, couleur = mix(albédo, blanc, 0,7) |
| `rim_strength` (instance) | 0 / 0,6 (ennemi) | 0 | **0,20** teinte horizon ; ennemi **0,6** surbrillance (conservé) | détache le perso sans coder l'équipe |
| `use_triplanar` | true pour tout `painted()` | **terrain uniquement** | false | les props sont en UV (Blender) |
| `triplanar_scale` | 0,333 | **0,25** (1 rép. / 4 m) | — | — |
| `grime_strength` | 0,35 | **0,15**, terrain uniquement | 0 | — |

### 7.3 `assets/shaders/ink_outline.gdshader`

Les largeurs sont en px à 1080p, mises à l'échelle par hauteur/1080, et multipliées par 1,5 en « Encre renforcée ».

| Usage | 5 m | 10 m | 20 m | 30 m | 40 m | 60 m | 90 m | Paramètres |
|---|---|---|---|---|---|---|---|---|
| Personnage (allié / neutre) | 3,0 | 3,0 | 2,7 | 2,3 | 2,0 | 1,75 | 1,5 | `outline_width_px` 3 ; `falloff_far_px` 2 à 40 m ; `falloff_floor_px` 1,5 (conservé) |
| Ennemi : coque de surbrillance | 3,5 | 3,5 | 3,2 | 2,8 | 2,5 | 2,5 | 2,5 | ne s'efface jamais (conservé) |
| Ennemi : encre extérieure | +1 | +1 | +1 | +1 | +1 | +1 | +1 | conservé |
| Viewmodel, arme au sol | 2 | 2 | 2 | 2 | 2 | 2 | 2 | constant (conservé) |

- **Nouveau `bottom_weight` = 1,25** (personnages) : le trait s'épaissit de 25 % sous 0,3 m (pieds) pour ancrer le corps au sol, comme l'encre tremblée de l'épingle 06.
- **Pas de coque sur le décor :** c'est le post-process qui l'encre.

### 7.4 `assets/shaders/ink_edges.gdshader` + `scripts/core/InkPost.gd`

| Paramètre | Actuel | Cible | Note |
|---|---|---|---|
| `width_near_px` | 4,0 | **3,0** | 4 px empâte les biseaux de près |
| `width_near_m` | 10 | **8** | — |
| `width_far_px` | 1,5 | 1,5 | conservé |
| `width_far_m` | 60 | **50** | — |
| `opacity_far_floor` | 0,40 | **0,50** | à `opacity_far_m` |
| `opacity_far_m` | 90 | **100** | — |
| `fog_start_m` / `fog_end_m` / `fog_max_amount` | 35 / 120 / 0,30 | **40 / 150 / 0,35** | aligné sur le brouillard (§6.3) |
| `depth_edge_threshold` | 0,05 | 0,05 | recalibrer si un biseau de 6 cm à 5 m produit une double ligne |
| `crease_enabled` *(nouveau)* | — | **true** | plis par normale via `hint_normal_roughness_texture` (Forward+) : trace les arêtes de biseau et de boîte comme les épingles 18 et 22 |
| `crease_angle_deg` *(nouveau)* | — | **35** | angle minimum entre normales voisines |
| `crease_width_px` *(nouveau)* | — | **1,5** | — |
| `crease_fade_start_m` / `crease_fade_end_m` *(nouveau)* | — | **15 / 30** | les plis disparaissent avant d'empâter le lointain |
| `crease_opacity` *(nouveau)* | — | **0,85** | un poil plus léger que la silhouette |

Largeurs de silhouette qui en résultent : 3,0 px (≤ 8 m), 2,9 (10 m), 2,6 (20 m), 2,2 (30 m), 1,9 (40 m), 1,5 (≥ 50 m).

### 7.5 `scripts/core/LevelLook.gd` : Environment WYSIWYG

| Paramètre | Actuel | Cible | Pourquoi |
|---|---|---|---|
| `tonemap_mode` | FILMIC | **LINEAR** | le filmique compressait puis l'exposition 0,42 assombrissait : les hex ne voulaient plus rien dire |
| `tonemap_exposure` | 0,42 | **1,0** | — |
| `adjustment_enabled` (saturation 1,20, contraste 1,04) | true | **false** | la saturation se règle dans l'albédo, pas en post |
| `ambient_light_energy` | 0,25 | **0,18** | à calibrer avec la sonde ci-dessous |
| `ssao_radius` / `ssao_intensity` / `ssao_power` | 0,5 / 1,2 / 1,0 | **0,8 / 1,0 / 1,5** | contacts doux mais nets |
| `ssao_light_affect` | 0 | **0,15** | un peu de contact même au soleil |
| `fog_density` / `fog_sky_affect` | 0,00149 / 0 | conservé | — |
| `glow_enabled` | false | false | les lampes « brillent » par un halo géométrique peint, pas par bloom |
| `DirectionalLight3D` | ombres oui | `light_angular_distance` **0,5**, `directional_shadow_max_distance` **120**, PSSM 4 | ombres nettes, portée du jeu |

**Sonde de calibration** (tâche ART-01) : un cube albédo `#D2A46C` en plein soleil, face au soleil. En capture, sa L OKLab doit valoir celle de l'albédo ± 0,03. Sa face à l'ombre doit valoir 0,62–0,70 × cette L.

### 7.6 `assets/shaders/ink_sky.gdshader`

| Paramètre | Actuel | Cible |
|---|---|---|
| `cloud_scale` | 5,0 | **3,0** (3 à 5 grosses masses par demi-ciel) |
| `cloud_coverage` | 0,28 | **0,32** |
| `cloud_band_low_deg` / `high_deg` | 8 / 35 | **6 / 30** |
| largeur du seuil nuage (`threshold + 0,12`) | 0,12 | **0,04** (bord net, 2 tons francs) |
| `sun_disc_radius` | 0,018 | **0,025** |
| `sun_glow_radius` / `sun_glow_strength` | 0,12 / 0,45 | **0,15 / 0,35** |
| `ground_color` | horizon assombri | inutile une fois les coulisses posées (§6.3) ; garder en secours |

### 7.7 `scripts/core/Cartoon.gd`

- `_MAP_PALETTES` : valeurs v3 de `tokens.json` → `maps`. On ajoute `ground`, `backdrop_near`, `backdrop_far`, `fog`, et on supprime les assombrissements de compensation.
- `_TRIPLANAR_SCALE` : 1/3 → **1/4**, pour le terrain seulement.
- Une nouvelle fabrique `prop_uv(kind, tint)` sert les maillages Blender : UV + masques vertex, sans triplanaire. `painted()` est réservée au terrain.
- `_CHARACTER_GRAIN` : toutes les valeurs passent à **0**.
- `INK`, `ally_color()`, `enemy_color()` : **inchangés**.

### 7.8 `tools/textures/gen_textures.py` : v3

1. **Supprimer toute encre des albédos** : plus d'appel à `creases()` ni à `wavy_lines()` dans les `mat_*`. Les fonctions restent pour générer des **décalques** de fissures.
2. **Variation de valeur ≤ ±4 %**, `base_sigma` ≥ 200 px ; aucune tache de plus de 10 % de l'aire, sauf rouille en décalque.
3. **Produire trois familles au lieu de onze textures « tout-en-un » :**
   - **Terrain** 1024² : sable, pont, pavés, neige, calcaire, terre battue, quai.
   - **Trim-sheets** 1024² par thème (désert, port-cargo, ville, alpin) : bandes de planche, de tôle ondulée (rayures de valeur ±6 %, pas de flou), de rivets, de pochoirs, de bordure claire.
   - **Atlas de décalques** 2048² : pochoirs FUEL, GAS, numéros, flèches, « FRAGILE », « GRAINES » ; autocollants de l'émission ; impacts-étoiles ; brûlures ; coulures.

### 7.9 Conventions Blender (`tools/blender/make_*.py`)

| Étape | Réglage |
|---|---|
| Biseau | selon §6.6, `limit_method='ANGLE'` 30°, 2 segments (architecture) ou 1 (props) |
| Normales | modificateur `WEIGHTED_NORMAL` (`keep_sharp`), puis application |
| Vertex color `masks` (`COLOR_0`, RGBA) | R = AO cuit (Cycles, 16 échantillons, distance 0,5 m, remappé 0,55–1) ; G = convexité (faces de biseau à 1, le reste à 0) ; B = hauteur normalisée dans la boîte de l'objet ; A = zone de teinte (0 base, 0,33 accent, 0,66 métal, 1 décalque) |
| UV | projection à 256 px/m ; panneaux alignés sur le trim-sheet |
| Nommage des matériaux | `f"{id}_{slot}"` (conservé) : `base`, `accent`, `metal`, `glass`, `sign` |
| Export | glTF, `export_colors=True`, triangulé, LODs en `_lod1` et `_lod2` |

## 8. Interface
<a id="8-interface"></a>

### 8.1 Le système : « Le charbon informe, l'autocollant se choisit, la trame célèbre »

Deux références se contredisent en apparence.
- **Les planches** : pages sombres calmes, bandeaux pinceau rouges, titres blancs italiques.
- **Le tableau** : autocollants, barres inclinées colorées, hexagones, bulles BD, trame.

On ne les mélange pas au hasard. **Chaque couche a un rôle, et un élément n'appartient qu'à une couche.**

| Couche | Rôle | Vient de | Apparence | Où |
|---|---|---|---|---|
| **1. Charbon** | *informer* : lire, régler, comparer | planches Wasteland et Cargo | aplats charbon chauds, trait de 1 px, texte papier, bandeau pinceau rouge pour **le titre de page et les titres de section** | listes, réglages, descriptions, chips du HUD, killfeed, tableaux |
| **2. Autocollant** | *choisir, posséder* : ce qu'on sélectionne ou qui nous appartient | épingles 02, 10, 11, 15, 19 | forme **inclinée à 12°** ou **hexagone**, contour d'encre de 3 px, **ombre dure décalée** (6, 6) en encre, couleur de l'agent, de la carte ou du mode ; sélectionné = **liseré papier découpé** de 4 px | cartes agent, carte, mode, arme, cosmétique ; CTA principal ; hexagones de capacité (seul autocollant du HUD) ; pings |
| **3. Trame** | *célébrer* : un moment | épingle 05 (dosée) | trame de points 45°, éclat étoilé, onomatopée Bangers, brève, puis disparaît | match trouvé, verrouillage d'agent, manche gagnée, multi-kill, MVP, niveau de compte |

**Règles d'or :**

1. **Un écran = un bandeau pinceau de titre + au plus 3 bandeaux de section.** Le pinceau nomme, il ne décore pas.
2. **La couleur signifie quelque chose ou n'apparaît pas.**
   - Rouge pinceau : marque, action principale, vie basse.
   - Couleur-clé d'agent : cet agent.
   - Bleu : allié. Magenta ou Citron : ennemi. Jaune : objectif.
   - Aucune couleur décorative.
3. **Pas d'autocollant sur un autocollant, pas de panneau dans un panneau.** Un autocollant se colle sur le charbon.
4. **La trame ne dure pas.**
   - En match : ≤ 1,2 s, hors de la zone centrale (40 % × 40 %).
   - En menu : ≤ 2 s, puis elle se fige en aplat.
   - Jamais en permanence.
5. **Une seule inclinaison, 12°**, pour les formes (barres, boutons, onglets) *et* l'italique du texte. `Comic._ITALIC_SLANT` passe de 0,24 à **0,2126** = tan 12°.
6. **Pas de sang, pas de néon, pas de verre.** Le relief vient de l'ombre dure décalée, jamais d'un flou ni d'une lueur.

### 8.2 Jetons

**Couleur** (contrastes WCAG mesurés sur `panel`, sauf mention) :

| Jeton | Hex | Rôle | Contraste |
|---|---|---|---|
| `encre` | `#1A1410` | traits, ombres dures, texte sur fonds clairs | — |
| `charbon.bg` | `#14110F` | fond de page | papier dessus : 16,2 |
| `charbon.panel` | `#1E1A17` | panneau | papier dessus : 14,9 |
| `charbon.panel_hi` | `#2A2521` | survol, ligne paire | papier dessus : 13,0 |
| `charbon.rule` | `#3A332D` | trait de 1 px | 1,39 (décoratif) |
| `papier` | `#F4EDE1` | texte, liseré d'autocollant | 14,9 |
| `papier.dim` | `#B3AA9E` | texte secondaire | 7,5 |
| `papier.off` | `#726A60` | désactivé (toujours avec hachures + raison) | 3,25 |
| `pinceau` | `#C8242C` | marque, CTA, vie basse | blanc dessus : 5,6 ; papier dessus : 4,8 |
| `pinceau.presse` | `#9E1C22` | CTA pressé | blanc dessus : 7,6 |
| `allie` | `#3B8BFF` | allié (toujours avec ●) | 5,2 |
| `ennemi.magenta` | `#FF3DC8` | ennemi, défaut (toujours avec ▼) | 5,6 |
| `ennemi.citron` | `#C8FF1F` | ennemi, option (recommandée protan et deutan) | 14,6 |
| `objectif` | `#F2C230` | objectif, avertissement ⚠ | 10,3 ; encre dessus : 10,9 |
| `tete` | `#F28A1E` | chiffres de headshot | 6,9 |

- **Neutres teintés chaud** (h ≈ 55–60°, C ≤ 0,02) : ce sont les mêmes que l'encre. Les gris froids de v2 (`#101113`…) sont abandonnés.
- **Couleurs-clés d'agent :** §4.4, toujours avec leur couleur de texte (encre ou papier) validée ≥ 4,5:1.

**Typographie :**

| Usage | Police | Fichier |
|---|---|---|
| Titres, bandeaux, CTA | **Barlow Condensed ExtraBold Italic**, capitales | à ajouter : `BarlowCondensed-ExtraBoldItalic.ttf` (OFL, famille déjà présente) ; on remplace le faux italique par la vraie coupe |
| Libellés, onglets | Barlow Condensed SemiBold, capitales, interlettrage +2 % | présent |
| Nombres | Barlow Condensed ExtraBold (droit), chiffres tabulaires | présent |
| Boutons secondaires | Barlow Condensed Bold Italic | à ajouter : `BarlowCondensed-BoldItalic.ttf` (OFL) |
| Phrases | Barlow Semi Condensed Medium | présent |
| Onomatopées, logo | **Bangers** (OFL, Vernon Adams) | à ajouter : `Bangers-Regular.ttf` ; **remplace Protest Revolution**, dont le pochoir rugueux dit « manif punk », pas « BD pop » ; Bangers est la lettre SFX de comics, utilisée uniquement sur ≤ 6 mots |
| Lato | — | **retirée** (déjà décidé en v2) |

**Échelle** : ratio **1,25**, base **21 px à 1080p**. Le plancher de 21 px donne 14 px à 720p.

| Jeton | px 1080p | px 720p | Usage |
|---|---|---|---|
| `caption` | 21 | 14 | légendes, touches, plancher absolu |
| `body` | 26 | 17 | phrases, killfeed |
| `subtitle` | 33 | 22 | libellés importants, noms dans les listes |
| `label_lg` | 41 | 27 | timer, onglets principaux |
| `h3` | 51 | 34 | PV, titres de section |
| `h2` | 64 | 43 | munitions, titre de page |
| `h1` | 80 | 53 | nom d'agent, score de fin |
| `display` | 100 | 67 | VICTOIRE / DÉFAITE |
| `hero` | 125 | 83 | logo, onomatopée de moment |

Réglages d'interlignage :
- Titres : interligne 1,05, en capitales.
- Phrases : interligne 1,45, mesure ≤ 70 caractères.
- Nombres : chiffres tabulaires, jamais Bangers.

**Espacement** : grille de 6 (conservée) : 6, 12, 18, 24, 36, 48, 72, 96.

**Formes :**

| Jeton | Valeur (1080p) |
|---|---|
| `slant_deg` | 12° (décalage horizontal = 0,2126 × hauteur) |
| `radius.panel` | 2 |
| `radius.sticker` | 6 (cartes non inclinées : agents, armes) |
| `radius.slant` | 0 (barres inclinées) |
| `stroke.rule` | 1 |
| `stroke.sticker` | 3 (encre) |
| `stroke.diecut` | 4 (papier, état sélectionné, à l'extérieur de l'encre) |
| `shadow.hard` | décalage (6, 6), encre 100 %, flou 0 |
| `shadow.hard_small` | (3, 3) pour les chips et hexagones ≤ 72 px |
| `hex` | hexagone pointe en haut, Ø 72 (HUD) / 96 (menus), onglet de touche en bas à gauche Ø 30 (épingle 02) |
| `brush` | NinePatch du bandeau pinceau à 1,5 × la hauteur du titre, fin sèche à droite (64 px) ; **la queue en « poisson » actuelle est supprimée** |
| `halftone` | points de 4 px au pas de 8 px, 45°, encre à 18 % d'opacité ou pinceau |

**Mouvement :**

| Jeton | Durée | Courbe | Usage |
|---|---|---|---|
| `press` | 90 ms | cubic out | décalage de 3 px vers le bas-droite (l'autocollant s'écrase sur son ombre) |
| `focus` | 150 ms | cubic out | survol, focus |
| `slap` | 220 ms | **back out (surdépassement 1,2)** | l'autocollant se colle : échelle 1,08 → 1, rotation −3° → 0 ; la **seule** exception à la famille cubique, et c'est la signature |
| `wipe` | 280 ms | cubic out | bandeau pinceau de gauche à droite |
| `reveal` | 250 ms | cubic out | apparition de panneau (translation 24 px + fondu) |
| `page` | 400 ms | cubic in-out | changement d'écran, fin de match |
| `burst` | 600–1 200 ms | cubic out, puis maintien, puis cubic in | moments de trame |

- Décalage entre éléments d'une liste : 30 ms, au plus 6 éléments animés.
- **Mouvement réduit** (`Settings.reduced_motion`) : pas d'échelle, de rotation, de secousse ni de clignotement. Fondus de 120 ms seulement ; la trame est statique.

### 8.3 Règles du HUD

- **Zone centrale** 40 % × 40 % : uniquement le réticule, les hitmarkers, les arcs de dégâts et la lunette (conservé).
- **Chips :** tout élément de HUD repose sur un chip `charbon.bg` à 80 % d'alpha, radius 2. Du texte papier nu sur le ciel ne fait que 2,3:1.
- **Pas de couleur d'agent dans le HUD.** Seuls apparaissent l'allié, l'ennemi, l'objectif, le pinceau (vie basse < 30 %, ultime prêt) et le papier.
- **Hexagones de capacité** (le seul autocollant du HUD) :

  | État | Rendu |
  |---|---|
  | Prêt | papier, glyphe encre |
  | Recharge | charbon, remplissage radial papier à 35 %, secondes en `caption` |
  | Charges | pastilles ● sous l'hexagone |
  | Ultime prêt | pinceau + glyphe papier, pulsation d'échelle 1 → 1,05 à 1 Hz (aucune en mouvement réduit) |
  | Désactivé (Duel, Duo) | masqué |

- **Tailles à 1080p :**
  - minimap 240 ;
  - munitions `h2` 64 ;
  - PV `h3` 51 ;
  - timer `label_lg` 41 ;
  - killfeed `body` 26, 5 entrées ;
  - hexagones 72 ;
  - chips : 72 de haut.
- **Échelle d'interface** réglable de 80 à 120 %. Le plancher de 14 px à 720p est vérifié à 80 %, avec une échelle de base de 1,1 si nécessaire.
- **Marges de sécurité :**

  | Définition | Marge (px) |
  |---|---|
  | 1920 × 1080 | 48 |
  | 1280 × 720 | 32 |
  | 1280 × 800 (Deck) | 36 |

  Aucun texte essentiel dans ces marges.

### 8.4 États des composants

| État | Charbon (liste, réglage) | Autocollant (carte, CTA) | Hexagone |
|---|---|---|---|
| Défaut | `panel`, trait `rule` 1 px | couleur, encre 3 px, ombre (6, 6) | papier ou charbon selon l'état de jeu |
| Survol | `panel_hi` + puce pinceau à gauche | translation (−2, −2), ombre (8, 8), `focus` | liseré papier 2 px |
| Focus visible (manette, clavier) | trait papier 2 px, décalage 4 px | liseré papier découpé 4 px + flèche ▶ pinceau à gauche | idem survol + ▶ |
| Pressé | `panel` foncé de 4 % | translation (3, 3), ombre (3, 3), `press` | idem |
| Sélectionné | soulignement pinceau de 4 px | liseré papier découpé 4 px permanent + tampon « ✓ » encre | — |
| Désactivé | `papier.off` + hachures 45° encre à 25 % + **raison** (« 3 200 cr requis ») | désaturé à 30 %, ombre (2, 2), cadenas + raison | charbon + hachures |
| Chargement | barre pinceau qui se remplit ; après 1 s, « Connexion au serveur… 3 s » | squelette : autocollant charbon `panel_hi` sans ombre, pulsation d'opacité 0,6–1 à 1 Hz | — |
| Vide | phrase d'invite + action : « Aucun ami en ligne — INVITER » | autocollant pointillé papier.dim « + » | — |
| Erreur | ⚠ objectif + « ÉCHEC » + code + RÉESSAYER | tampon encre « RATÉ » incliné −8° | tremblement de 3 px sur 200 ms (aucun en mouvement réduit) |

### 8.5 Signatures sonores d'interface

Toutes sur le bus `UI`, à −12 dB par rapport aux armes. Au plus 2 simultanées. Jamais pendant un tir.

| Événement | Son | Durée |
|---|---|---|
| Survol, focus | tic de papier sec (clic filtré à 4 kHz) | 30 ms |
| Sélection | **« schlack »** d'autocollant qu'on colle | 120 ms |
| Retour | glissement de papier | 150 ms |
| Onglet | claquement de carton | 60 ms |
| Achat | petit « ka-ching » de caisse | 250 ms |
| Achat impossible | « bonk » mat de bois | 120 ms |
| Verrouillage d'agent | **DING** de cloche + tampon + phrase de l'agent | 600 ms |
| Match trouvé | roulement de caisse claire + « ooh » de foule | 1,2 s |
| Manche gagnée / perdue | fanfare de cuivres montante / trombone descendant | 1,5 s |
| Erreur | double « tut » grave | 200 ms |
| Ultime prêt | carillon court + voix de l'agent | 400 ms |

### 8.6 Maquettes filaires (1920 × 1080, marges de 48 px)

Légende :
- `▰▰` bandeau pinceau ;
- `/‾‾/` autocollant incliné de 12° ;
- `⬡` hexagone ;
- `[ ]` charbon ;
- `░` trame (moment).

**Menu principal**
```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│ ╔LES JOUTES╗ (logo Bangers, autocollant, ombre dure)           [● 3 amis] [⚙] [⏻]    │
│                                                                                       │
│  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾/                      ◯ disque solaire pinceau                  │
│ / JOUER            ▶ /   h1, pinceau         ◯   AGENT 3D sur podium                  │
│/____________________/                        ◯   (dernier joué, pose idle)            │
│   /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾/                                                                   │
│  / AGENTS         /  h3 charbon, survol → couleur agent      [ GROUPE ]                │
│  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾/                                           ● Toi  VIF  ★12          │
│ / ARSENAL        /                                           + inviter                 │
│ /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾/                                                                     │
│/ CASIER         /   (cosmétiques, verrouillé : « Bientôt »)  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾/    │
│/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾/                                            / DÉFI DU JOUR  2/3  /    │
│/ OPTIONS       /                                            /____________________/    │
│                                                                                       │
│ Dernière file : 4v4 Tactique · Wasteland            v0.3 · ping 18 ms · EU-Ouest      │
└───────────────────────────────────────────────────────────────────────────────────────┘
```
- JOUER relance la dernière file en un clic (UX-08).
- L'IP disparaît de la page : elle passe dans JOUER → Partie personnalisée.

**Jouer (choix du mode et de la carte)**
```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│ ▰▰▰ JOUER ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰  [✕]    │
│  /‾‾‾‾‾‾‾‾‾‾‾‾/ /‾‾‾‾‾‾‾‾‾‾‾‾/ /‾‾‾‾‾‾‾‾‾‾‾‾/ /‾‾‾‾‾‾‾‾‾‾‾‾/ /‾‾‾‾‾‾‾‾‾‾‾‾/            │
│ / 4V4        / / 4V4        / / DUEL       / / DUO        / / ENTRAÎNE-  /             │
│/ MATCH À    / / TACTIQUE   / / 1V1        / / 2V2        / / MENT       /              │
│/ MORT  ✓   / / pose/désam./ / sans capac./ / sans capac./ / solo       /               │
│‾‾‾‾‾‾‾‾‾‾‾‾  ‾‾‾‾‾‾‾‾‾‾‾‾   ‾‾‾‾‾‾‾‾‾‾‾‾   ‾‾‾‾‾‾‾‾‾‾‾‾   ‾‾‾‾‾‾‾‾‾‾‾‾                 │
│ ▰ CARTE ▰▰▰▰▰                                                                         │
│ ┌────────┐┌────────┐┌────────┐┌────────┐┌────────┐┌────────┐  vignettes rendu argile  │
│ │07 WAST.││08 CARGO││01 PORT ││02 VAL  ││03 ST-O.││04 COL  │  + callouts (épingle 20),│
│ │ ✓ ░░   ││        ││        ││        ││        ││        │  radius 6, ciel de la    │
│ └────────┘└────────┘└────────┘└────────┘└────────┘└────────┘  carte en bandeau haut   │
│ [ Bots  ●━━  ] [ Recrue | VÉTÉRAN | Élite ]      [ Partie personnalisée / IP… ]        │
│                                                     /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾/         │
│                                                    /  LANCER  ▶  (Entrée/A)  /  pinceau│
└───────────────────────────────────────────────────────────────────────────────────────┘
```

**Sélection d'agent** (mise en page de l'épingle 19)
```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│ ▰▰ CHOISIS TON AGENT ▰▰▰▰▰    ● Toi:VIF  ● Léa:?  ● Bot:VANNE  ● Bot:?      0:12     │
├──────────────┬────────────────────────────────────────────────────────────────────────┤
│ ROSTER       │ ░ fond = aplat couleur-clé de l'agent (#EE6A24), typo géante « VIF »   │
│ ⬡VIF ✓       │   en filigrane à 12 % (épingle 11)                                     │
│ ⬡CHOC        │                         AGENT 3D (rendu, pose        /‾‾‾‾‾‾‾‾‾‾‾‾‾/    │
│ ⬡VANNE (pris)│                         signature en boucle)        / VIF         /    │
│ ⬡GUET        │                                                    / L'ALLUMETTE /     │
│ ⬡ROSEAU      │                                                    ‾‾‾‾‾‾‾‾‾‾‾‾‾      │
│ ⬡VERROU      │                                                    ENTRÉE ◆            │
│ (autocollants│                                                                        │
│  96, tête    │  ⬡C RUÉE   ⬡Q ÉBLOUIS.   ⬡E TREMPLIN   ⬡X RÉSURGENCE                  │
│  qui déborde)│  [description de la capacité survolée, body 26, ≤ 70 car.]             │
│              │                                          /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾/        │
│              │                                         / VERROUILLER  ▶    / pinceau  │
└──────────────┴────────────────────────────────────────────────────────────────────────┘
```
- Pris par un coéquipier : désaturé + raison « Pris par Léa ».
- Verrouillage : moment de trame (DING, tampon « VERROUILLÉ », 1,0 s).

**Achat / équipement** (aligné sur UX-05 : grille catégories × armes, touches 1–5)
```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│ ▰▰ ÉQUIPEMENT ▰▰▰▰▰▰▰▰▰▰                                   CRÉDITS 3 900 cr   [✕ B]  │
├───────────┬───────────────────────────────────────────────┬───────────────────────────┤
│/1 POING  /│ ┌─────────┐ ┌─────────┐ ┌─────────┐           │ RAVAGE           2 900 cr │
│/2 SMG    /│ │silhouet.│ │silhouet.│ │silhouet.│           │ (vue de profil 3D, tourne)│
│/3 FUSILS✓/│ │ RAVAGE ✓│ │MARQUEUR │ │PERCUTEUR│  cartes   │ Dégâts     ▰▰▰▰▰▱▱        │
│/4 POMPE  /│ │ 2 900   │ │ 3 100   │ │ 3 150 🔒│  autocoll.│ Cadence    ▰▰▰▰▰▰▱        │
│/5 LOURDE /│ └─────────┘ └─────────┘ └─────────┘  radius 6 │ Portée     ▰▰▰▰▱▱▱        │
│/6 SNIPER /│  🔒 = désactivé + « 3 150 cr requis »         │ Chargeur   25 / 75        │
│           │                                               │ ⬡ ACHETER (Entrée/A)      │
├───────────┴───────────────────────────────────────────────┴───────────────────────────┤
│ SLOT 1 : RAVAGE   SLOT 2 : PISTOLET        Clic : équiper · Clic droit : revendre      │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

**HUD en match** (1920 × 1080 ; entre crochets, les positions en 1280 × 720)
```
┌─48px─────────────────────────────────────────────────────────────────────────── 48px─┐
│ ┌minimap 240┐          [● 7  |  1:42  |  5 ▼]  (label_lg)    [killfeed body 26, 5]   │
│ │  (160)    │          [ A ◆ objectif : 0:32 ]                  VIF ⟶ ▼GUET  PAF!    │
│ └───────────┘                                                                        │
│ LIEU : FUEL                                                                          │
│                     ┌───────── zone centrale 40 % × 40 % ─────────┐                  │
│                     │                  réticule                   │                  │
│                     │         hitmarkers · arcs de dégâts         │                  │
│                     └─────────────────────────────────────────────┘                  │
│                                                                                      │
│  [sous-titres / indices sonores, body 26, centrés bas, au-dessus des hexagones]      │
│ ┌PV ───────────────┐        ⬡C  ⬡Q  ⬡E   ⬡X                ┌ RAVAGE ─────────┐       │
│ │ 100  ▰▰▰▰▰▰▰▰▰▱  │        72 px (48 à 720p)               │   25 / 75       │       │
│ └h3 51 [34]────────┘        ●● charges                     └ h2 64 [43] ─────┘       │
└──────────────────────────────────────────────────────────────────────────────────────┘
```
- Munitions : chiffres pinceau si ≤ 25 %.
- PV : papier, puis pinceau sous 30 %, avec vignette de vie basse.

**Tableau des scores** (maintenir Tab ; barres inclinées de l'épingle 15)
```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│ ▰▰ 4V4 TACTIQUE · WASTELAND · MANCHE 9 ▰▰▰▰▰▰▰              ● 5  —  4 ▼               │
│  ● ALLIÉS                                  K   M   A   DÉG.  ÉCO     PING             │
│ ⬡/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾/                   │
│  / VIF  Toi                           14   6   3   2 104  3 900  18 / papier (toi)    │
│ ⬡/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾/                    │
│  / VANNE  Bot-Odile                    9   7   5   1 610  2 150  —  / charbon, tab ●  │
│  ▼ ENNEMIS                                                                            │
│ ⬡/ GUET  Ennemi 1                     11   8   2   1 880  4 400  41 / charbon, tab ▼  │
│  ... (tête de l'agent qui déborde du haut de la barre, 1,2 × la hauteur de ligne)     │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

**Fin de match**
```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│ ░░░░ ▰▰▰▰▰▰▰▰▰▰ VICTOIRE ▰▰▰▰▰▰▰▰▰▰ ░░░░ (display 100, wipe 280 ms, trame 1,5 s)      │
│                                   13 — 9                                              │
│  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾/   TON MATCH                    PROGRESSION              │
│ / MVP                       /    K/M/A  21 / 12 / 6            Compte ▰▰▰▰▰▱ niv. 7   │
│/ [agent 3D, aplat couleur  /     Dégâts 3 480 · Préc. 24 %     Vif ▰▰▱▱ maîtrise 2    │
│/  de l'agent, pose MVP]   /      Headshots 38 %                Défi 2/3 ✓             │
│‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾                                                            │
│  ● ALLIÉS (barres inclinées)       ▼ ENNEMIS (barres inclinées)                       │
│                          /‾‾‾‾‾‾‾‾‾‾‾‾‾‾/  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾/                      │
│                         / MENU        /  / REJOUER  ▶ (A)     / pinceau                │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

**Réglages** (tactilité de l'épingle 12, sans bois : charbon + fentes)
```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│ ▰▰ RÉGLAGES ▰▰▰▰▰▰▰        /JEU/ /COMMANDES/ /VIDÉO/ /AUDIO/ /ACCESSIBILITÉ/     ⬡✕   │
│ ┌─────────────────────────────────────────────┬─────────────────────────────────────┐ │
│ │ • SENSIBILITÉ            [══════■════] 1,20 │ APERÇU                              │ │
│ │ • FOV (horizontal 16:9)  [═══════■═══] 103° │ (réticule, couleur ennemie sur      │ │
│ │ • COULEUR ENNEMIE   [ MAGENTA ● ][ CITRON ] │  4 fonds de carte, encre ×1,5)      │ │
│ │ • ENCRE RENFORCÉE        [  OUI ●━━ ]       │                                     │ │
│ │ • ÉCHELLE D'INTERFACE    [═════■═════] 100% │ Description du réglage survolé,     │ │
│ │ • MOUVEMENT RÉDUIT       [ ━━● NON  ]       │ body 26, ≤ 70 car.                  │ │
│ └─────────────────────────────────────────────┴─────────────────────────────────────┘ │
│ [ RÉINITIALISER ]                                    /‾‾‾‾‾‾‾‾‾‾‾‾‾‾/ (autosave)      │
│                                                     / TERMINÉ ▶    /                  │
└───────────────────────────────────────────────────────────────────────────────────────┘
```
- Curseurs en **fente** encre avec un bouton papier de 24 × 36 px (cible ≥ 44 px avec la marge).
- Bouton de fermeture : hexagone pinceau ✕.

### 8.7 Adaptation 1280 × 720 et 1280 × 800

- Même mise en page, facteur 0,667 ; marge de sécurité 32 px (720p) ou 36 px (800p).
- Sélection d'agent : les descriptions de capacité passent en infobulle ; le roster reste une colonne.
- Achat : le panneau de détail passe sous la grille.
- HUD : minimap 160, killfeed 4 entrées, hexagones de 48 px.
- Aucun texte sous 14 px.

## 9. VFX
<a id="9-vfx"></a>

### 9.1 Principes

1. **Des formes plates, pas des particules floues.** Chaque effet est un petit dessin animé : 2 à 3 tons en aplat, un contour d'encre de 2 px (sauf traceurs et lueurs), des formes qu'on pourrait découper au ciseau (étoiles, bouffées rondes, gouttes, traits de vitesse).
2. **Animé « sur deux ».** Les formes avancent à 12 i/s (pas figé de 83 ms), comme un dessin animé. Traceurs, hitmarkers et chiffres de dégâts restent à la fréquence d'image, pour le jeu.
3. **Une palette VFX fermée**, toujours hors des bandes réservées :

   | Rôle | Couleurs |
   |---|---|
   | Flash | cœur papier `#FFF3D6`, jaune `#FFD24A`, orange `#F59A2E` |
   | Fumée et poussière | crème `#EDE4CF`, `#CFC3AC`, `#A99E8C` ; poussière `#E6D5B8` |
   | Étincelles | `#FFC24A` |
   | Soin | gel `#9FD8C8` + « + » papier |
   | Brûlure (décalque) | `#3A2E26` |
   | Rembourrage | `#F4EDE1` |
   | Confettis | couleurs-clés d'agent |

   Le Magenta et le Citron n'apparaissent **que** sur ce qui marque un ennemi.
4. **Le camp se lit par une marque, pas par l'effet.** Tout objet de capacité posé (mur, piège, tremplin, fumée) porte au sol un **anneau d'équipe** de 6 cm :
   - allié : bleu `#3B8BFF` avec des ● répétés ;
   - ennemi : surbrillance avec des ▼ répétés.

   L'objet garde les couleurs de son agent.
5. **Rien ne masque le réticule** plus de 80 ms, et aucun effet ne couvre plus de 8 % de l'écran à 1080p hors fumée.
6. **Budget :**
   - ≤ 64 particules par effet, ≤ 600 à l'écran ;
   - décalques en pool de 64 (FIFO), durée de vie 8 s, fondu de 1 s ;
   - effets en `GPUParticles3D` avec des quads maillés (pas de billboards flous).

### 9.2 Tir

| Effet | Forme | Couleurs | Timing | Règles |
|---|---|---|---|---|
| **Flash de bouche** (FP) | étoile à 4 ou 5 branches, rotation aléatoire ±25°, + un disque cœur | cœur `#FFF3D6`, anneau `#FFD24A`, pointes `#F59A2E`, contour encre 2 px | 3 images sur 50 ms | ≤ 6 % de l'écran ; taille : poing ×0,7, fusil ×1, pompe ×1,4 (évasé), lourde ×1,2 ; Faucheur : étoile longue horizontale |
| **Flash de bouche** (TP, vu par les autres) | même étoile, ×1,5 pour la lisibilité | idem | 50 ms | visible à 60 m (≥ 6 px) : c'est l'info de position |
| **Traceur** | trait de pinceau effilé (gros à l'arrière, pointu devant), 2,5 cm de large, 3 à 6 m de long | `#FFF3D6` à 90 %, bord encre à 40 % | vitesse visuelle 400 m/s, vie ≤ 80 ms | 1 sur 2 balles pour les automatiques, 1 plomb sur 3 pour le pompe ; part du bout du canon (GF-06) |
| **Douille** | petit cylindre laiton à biseau | `#D9A21B` + encre | tombe 0,6 s, rebond | FP seulement, ≤ 4 visibles |

### 9.3 Impacts

| Surface | Effet | Détail |
|---|---|---|
| Monde, générique | **étoile d'impact** décalquée (encre, Ø 12 cm, 6 branches irrégulières) + bouffée de poussière crème (3 ronds, 250 ms) + 3 à 5 éclats biseautés (1–4 cm) de la couleur de la surface | l'éclat reprend l'albédo sous l'impact |
| Métal | étoile + 4 à 6 étincelles `#FFC24A` en traits de vitesse, 150 ms | son « CLING » |
| Bois | étoile + 2 à 3 échardes `#C99A68` | — |
| Sable, neige | pas d'étoile : un « pouf » de poussière de la couleur du sol + un cratère décalqué Ø 15 cm | — |
| Verre | étoile blanche `#FFF3D6` + fissures radiales encre (décalque) | — |
| **Personnage (corps)** | **bouffée de rembourrage** `#F4EDE1` (4 ronds) + 2 confettis couleur-clé de l'agent touché | **jamais de rouge sang** ; lisible à 40 m (≥ 6 px) |
| **Personnage (tête)** | rembourrage + **anneau « CLONK »** orange tête `#F28A1E` (Ø 0,6 m, 120 ms) + 2 étoiles | le tireur seul voit l'anneau orange ; les autres ne voient que le rembourrage |

### 9.4 Retour de tir (HUD)

| Élément | Rendu | Timing |
|---|---|---|
| **Hitmarker** | 4 traits diagonaux papier, contour encre 2 px, 10 px de long, écart de 8 px (1080p) | 90 ms, sans animation d'échelle |
| **Hitmarker de headshot** | traits orange `#F28A1E` + petit anneau | 120 ms |
| **Confirmation de kill** | les traits passent en **pinceau**, punch d'échelle 1,3 → 1 (`slap` raccourci à 150 ms) + onomatopée de l'arme (Bangers, `label_lg` 41, papier + encre 3 px + ombre dure (3, 3)) à **x 0,72, y 0,38** : hors zone centrale, côté killfeed | onomatopée 700 ms (pop 90 ms, maintien, sortie 200 ms) ; en mouvement réduit : fondu seul |
| **Multi-kill** | « DOUBLÉ » / « TRIPLÉ » / « GRAND CHELEM » en `h3` sous l'onomatopée, sur une pastille de trame pinceau | ≤ 1,2 s au total |
| **Chiffres de dégâts** | Barlow Condensed ExtraBold (jamais Bangers), papier + contour encre 3 px ; headshot orange `#F28A1E` ×1,25 ; cumul par cible sur 0,8 s | montée de 40 px, 600 ms, sortie en fondu les 200 dernières ms |
| **Arcs de dégâts reçus** | arc pinceau à 60 % à 30 % du bord de la zone centrale, orienté vers la source | 800 ms |
| **Vie basse** | vignette pinceau à 25 % sur les bords (≤ 12 % de l'écran), pulsation à 1 Hz sous 30 % de PV | aucune pulsation en mouvement réduit |

### 9.5 Élimination : « REMBALLÉ »

Séquence complète, en 0,9 s :
1. L'agent s'écrase à 0,85 en Y sur 80 ms.
2. Il éclate en un **nuage de rembourrage** crème de 8 à 10 ronds, avec contour, plus 12 confettis couleur-clé. Le corps disparaît dans le nuage : le plateau l'a « remballé ».
3. Son **emblème tombe**, rebondit une fois et roule : une allumette géante (Vif), une cloche de ring (Choc), un volant de vanne (Vanne), un d20 (Guet), un flotteur (Roseau) ou un chapeau de cowboy (Verrou).
4. L'emblème disparaît en fondu à 2,0 s.

À savoir :
- Pas de ragdoll de corps, et aucune partie du corps ne reste au sol.
- L'emblème qui roule sert d'info : on voit où l'agent est mort.
- Côté victime : écran « REMBALLÉ » en bandeau pinceau + nom du tueur ▼ + arme.

### 9.6 Langage des capacités

| Primitive | Forme | Couleurs | Marque d'équipe | Timing |
|---|---|---|---|---|
| **Ruée / Charge / Piquet** | 3 bouffées de fumée rondes dans le sillage + 3 traits de vitesse encre | crème + encre ; Charge : onde « DING » en anneau papier | aucune (déplacement du corps) | 300 ms |
| **Éblouissement** | projectile objet (allumette) ; à la détonation, **étoile de flash plate** Ø 3 m, 2 images | `#FFF3D6` / `#FFD24A` | victime : écran blanc chaud `#FFF8EC`, retour en 1,5 s max | pré-détonation lisible de 0,4 s (grésillement + étincelle) |
| **Fumée / Rideau / Brume** | **nuages cel en 3 tons**, ronds, base plate, contour encre 2 px à l'extérieur ; opaques à 100 % au cœur, bord net | `#EDE4CF` / `#CFC3AC` / `#A99E8C` | anneau d'équipe au sol | déploiement 400 ms (bouffées qui gonflent sur deux), dissipation 600 ms par fragmentation |
| **Mur / Rempart / Mur d'assaut / Forteresse** | objet physique de l'agent (batardeau de béton-braise à chevrons pour le Mur et la Forteresse de Vanne, levée de roseau tressé et de vase-braise pour le Rempart de Verrou, volet peint de la baraque de boxe pour le Mur d'assaut de Choc) | couleurs de l'agent | anneau d'équipe + bande de 6 cm au pied du mur | pose en `slap` de 220 ms + poussière ; expiration : clignote 2 × 150 ms à −1 s, puis s'effondre en éclats |
| **Tremplin / Poste avancé / Passerelle** | ressort + plateau (boîte d'allumettes, gobelet à dés, planche) + chevrons décalqués ↑ | couleurs de l'agent + chevrons papier | anneau d'équipe | ressort qui oscille au repos (0,5 Hz) |
| **Piège étourdissant** | objet caché aux ennemis (clochette-mine, langue en ressort) ; visible des alliés avec un contour allié | couleurs de l'agent | contour allié | déclenchement : claque + étoiles |
| **Étourdissement** (victime) | **3 étoiles papier encrées** qui tournent autour de la tête (`StunStars.gd`) + onomatopée « BZZT » | papier + encre | — | durée de l'étourdissement ; aucune rotation en mouvement réduit |
| **Reveal** (Œil, Voile, Vision totale) | **bulle BD « ! »** au-dessus de la cible (épingle 02), contour encre, pointe vers la cible | bulle papier, « ! » encre, liseré de surbrillance ennemie | équipe du lanceur seulement | pop de 150 ms, maintien de 3 s, sans suivi (position figée) |
| **Soin** | gouttes de gel `#9FD8C8` montantes + « + » papier ; Sursaut : fleur jaune `#F2C53D` éclose en 8 pétales + onde | gel, papier, or | — | 500 ms |
| **Ultimes** | l'effet de base ×2 + **pastille de trame** Ø 4 m au sol, couleur de l'agent à 30 %, + onomatopée d'ultime (« DOOONG », « FERMÉ », « 20 NATUREL », « FLOUF ») | couleur de l'agent | anneau d'équipe | annonce : l'onomatopée apparaît chez tous les joueurs à portée de voix (≤ 40 m), c'est le contre-jeu |

## 10. Anti-patterns
<a id="10-anti-patterns"></a>

Chaque ligne décrit une faute vue dans le projet ou un piège probable. Si on la retrouve en revue, c'est un **FAIL**, pas une préférence.

**Monde**
- Des traits d'encre peints dans une texture d'albédo (fissures, veines, coutures). L'encre vient de la géométrie ou d'un décalque placé.
- Du bruit fbm multiplié par une teinte en guise de « peinture ». On obtient de la boue, pas un pinceau.
- Des corrections globales pour rattraper un asset : exposition 0,42, saturation 1,2, contraste. On corrige l'albédo.
- Un sol jouable plus saturé que les objets posés dessus (sable C > 0,10).
- Des murs-plans géants sans biseau, sans trim, sans rupture de silhouette ; des boîtes à arêtes vives.
- Des pièces qui flottent : coins de conteneurs, marches décollées des limons, props au-dessus du sol. Écart toléré ≤ 1 cm.
- Du triplanaire sur un prop. Le triplanaire est réservé au terrain.
- Une carte qui flotte dans le vide, ou un horizon « sol gris » visible.
- Des nuages en confettis (30 petits flocons). On veut 3 à 5 grosses masses.
- Du décor fin qui a l'air d'un couvert, ou un couvert qui a l'air traversable.
- Une silhouette humanoïde entre 1,5 et 1,9 m dans le décor.
- Une couleur saturée sur plus d'un élément par prop ; plus de 7 matériaux saturés par carte.
- Du vert feuille, du violet, du magenta ou du rose dans le décor, **même un peu** (lint des bandes réservées).
- De la nuit noire. Le style vit au soleil ; la carte la plus sombre est un crépuscule d'orage.

**Personnages et armes**
- Des mannequins interchangeables à la tête de 1:7,8 ; des pantalons noirs sur la moitié du corps.
- Une tête qui sort de son enveloppe (§4.1), ou des épaulettes, sangles ou armes portées au-dessus de 1,38 m.
- Un point le plus haut au-dessus de 1,80 m en pose de repos : tout le corps rétrécit à l'import.
- Une démarche accroupie ou voûtée hors de l'état Crouch ; un écrasement de la tête.
- Une mascotte à grosse tête, ou un humain générique sans crochet de tête ni motif.
- Du grain de peinture sur la peau ou le tissu.
- Une arme qui perd son archétype (un pompe qui ressemble à une trompette).
- Une arme au centre de l'écran à la hanche ; un viewmodel qui couvre plus de 22 %.
- Des couleurs d'équipe sur tout le corps. Seul le brassard est recoloré.
- Du sang, du gore, des cadavres persistants.

**Interface**
- Des lettres géantes à la place des portraits ; des colonnes de texte à la place d'hexagones de capacité.
- Un menu d'achat en tableur ; un champ IP en premier plan du menu principal ; un titre « FPS ».
- Un bandeau pinceau sur chaque bouton, ou plus de 4 bandeaux par écran. La « queue de poisson » du bandeau.
- Un autocollant posé sur un autocollant, un panneau dans un panneau.
- De la trame permanente, un collage BD plein écran, des onomatopées pendant la visée hors kill.
- Des couleurs d'agent dans le HUD de combat ; du rouge pour une erreur (l'erreur est ⚠ jaune).
- Du texte papier nu sur le ciel, sans chip.
- Une police hors de la liste ; Bangers sur des chiffres ou des phrases ; du faux italique quand la vraie coupe existe.
- Du glassmorphism, du flou d'arrière-plan, des lueurs néon, des dégradés violet-bleu.
- Des angles au hasard (8°, 15°, 20°). Il n'y en a qu'un : 12°.
- Un état manquant : focus manette invisible, désactivé sans raison, chargement sans indication.

**Effets**
- Des particules floues à alpha additif, du bloom, du « glow » générique.
- Un effet de camp codé par la couleur seule (sans ● ou ▼).
- Un flash qui couvre le réticule plus de 80 ms ; une fumée semi-transparente (on doit vraiment ne rien voir).

## 11. Checklist
<a id="11-checklist"></a>

### 11.1 Conventions de mesure

- Chaque contrôle est noté **PASS / WARN / FAIL** par `tools/review/style_check.py` (tâche ART-03), sur les captures de la revue (`map_shots`, `character_shots`, `char_ingame_shots`, `fp_shots`, `ui_shots`, turntables), les fichiers d'asset et les jetons (`docs/style/tokens.json`).
- **Colonne B :** B = bloquant (un FAIL bloque la sortie d'une vague art ou UI), I = indicatif.
- **Luminance et couleur :** OKLab / OKLCH calculés sur le sRGB des captures ; contraste selon WCAG 2.x (luminance relative).
- **Daltonisme :** simulation Machado 2009 à sévérité 1,0.
- **Définitions :** 1080p = 1920 × 1080, 720p = 1280 × 720. « Vue joueur » = caméra à 1,6 m, FOV horizontal 90°.
- **Masques** (ART-03 les fournit) :
  - HUD : rectangles des `Control` visibles ;
  - personnages : rendu d'un ID de calque ;
  - encre : pixels à L < 0,25, épaisseur ≤ 6 px.

### 11.2 Image et monde

| # | Contrôle | Seuil | Mesure | B |
|---|---|---|---|---|
| CHK-01 | Sonde de calibration WYSIWYG | face au soleil d'un cube `#D2A46C` : L = 0,75 ± 0,03 ; face à l'ombre = 0,62–0,70 × L éclairée | `tools/look_probe.gd` (ART-01) | B |
| CHK-02 | Pas de boue | dans les vues joueur : pixels hors HUD, hors personnages et hors encre avec 0,25 ≤ L < 0,33 : **≤ 5 %** | map_shots | B |
| CHK-03 | Encre dosée | pixels d'encre (L < 0,25, masque encre) : **2–9 %** de l'image en vue joueur | map_shots | I |
| CHK-04 | Sol calme | médiane du sol (tiers inférieur, hors HUD et personnages) : L 0,60–0,78 et C ≤ 0,10 | map_shots, vues spawn et centre | B |
| CHK-05 | Hiérarchie de chroma | C au 95ᵉ centile : sol ≤ 0,10, décor ≤ 0,20 ; aucun pixel de décor à C > 0,21 | map_shots + masque personnages | B |
| CHK-06 | Teintes réservées (image) | pixels de décor à C > 0,08 et h ∈ [300,355] ∪ [105,145] : **≤ 0,1 %** | map_shots | B |
| CHK-07 | Teintes réservées (données) | 0 couleur dans les bandes (C > 0,08) : `tokens.json` (hors `reserved`), `Cartoon._MAP_PALETTES`, `gen_textures.py`, manifestes de props, `AgentDatabase` | lint statique | B |
| CHK-08 | Albédos sans encre | textures `assets/textures/painted/*_albedo.png` et trim-sheets : 0 pixel à L < 0,25 (sauf `rubber*`) ; écart-type de L après flou gaussien de 2 px **≤ 0,04** | lint des fichiers | B |
| CHK-09 | Ombres lisibles | paires sol ombre/soleil échantillonnées : L(ombre) / L(soleil) **0,62–0,70** ; L(ombre) ≥ 0,30 ; teinte de l'ombre à ≤ 45° de la teinte d'ombre de la carte (si C > 0,03) | map_shots + look_probe | B |
| CHK-10 | Silhouette de décor | à 30 m, un cube de 2 m présente un contour continu ≥ 2 px (1080p) sur ≥ 90 % de son périmètre | look_probe | B |
| CHK-11 | Plis maîtrisés | aucune double ligne : 2 traits d'encre parallèles séparés de ≤ 3 px sur ≥ 20 px de long → FAIL | look_probe, biseau de 6 cm à 5 m | I |
| CHK-12 | Horizon fermé | vues aériennes : 0 % de pixels « ciel sous l'horizon » (`ground_color`) ; coulisses visibles sur 360° | map_shots aériennes | B |
| CHK-13 | Ciel lisible | ciel : 3 à 5 masses de nuages ≥ 1 % de l'écran par demi-ciel ; aucune masse sous 6° d'élévation | map_shots | I |
| CHK-14 | Repères | ≥ 3 repères (≥ 2 en duel) visibles au-dessus des toits depuis ≥ 70 % des points d'une grille de 4 m à 1,6 m | raycasts (ART-23 à ART-26) | B |
| CHK-15 | Couverts normés | 100 % des props `cover` : hauteur 1,10 ± 0,05 m ou ≥ 2,0 m ; \|ΔL\| couvert/sol ≥ 0,12 (éclairé **et** ombre, calculé sur les jetons) | `PropCatalog` + tokens | B |
| CHK-16 | Rien de flottant | écart entre la base d'un prop et le sol ≤ 1 cm ; aucune pièce d'asset déconnectée à plus de 1 cm de son parent | `check_asset.py` + scan de la scène | B |
| CHK-17 | Pas d'humanoïde parasite | aucun prop non-agent dont la boîte fait 1,5–1,9 m × ≤ 0,8 m × ≤ 0,8 m sans tag `ok_not_humanoid` | scan de la scène | I |

### 11.3 Lisibilité ennemie

| # | Contrôle | Seuil | Mesure | B |
|---|---|---|---|---|
| CHK-18 | Anneau ennemi : contraste | ennemi à 10, 20, 30 et 40 m devant les 3 fonds dominants de chaque carte : max(WCAG(surbrillance, fond), WCAG(encre, fond)) **≥ 3:1** dans ≥ 95 % des échantillons **et** ΔE_OK(surbrillance, fond) ≥ 20 dans 100 % | char_ingame_shots + échantillons de bord | B |
| CHK-19 | Anneau ennemi : daltonisme | option recommandée par type (Citron pour protan et deutan, Magenta pour tritan) : ΔE_OK simulé ≥ 9 contre toutes les couleurs de la carte | tokens + simulation | B |
| CHK-20 | Largeur de contour ennemi | ≥ 2,5 px à 40 m (1080p), sans interruption sur ≥ 90 % du périmètre | char_ingame_shots | B |
| CHK-21 | Exclusivité des couleurs ennemies | aucun pixel à ΔE_OK < 10 du Magenta ou du Citron en dehors des ennemis et du HUD ennemi | map_shots | B |
| CHK-22 | Taille à distance | un agent à 40 m mesure ≥ 40 px de haut (1080p, FOV 90°) et sa tête ≥ 7 px | char_ingame_shots | I |

### 11.4 Personnages et armes

| # | Contrôle | Seuil | Mesure | B |
|---|---|---|---|---|
| CHK-23 | Gabarit | hauteur de repos 1,80 ± 0,005 m, tout compris ; enveloppe de tête : z ∈ [1,47 ; 1,80], largeur ≤ 0,34, profondeur ≤ 0,36, aire de face 0,046–0,058 m² ; yeux à 1,62 ± 0,02 (sauf Verrou) ; au-dessus de 1,40 m, rien d'autre que le col et la tête (deltoïdes, sangles et armes ≤ 1,38) sur 12 images d'idle, marche, course, sprint, tir et rechargement ; accroupi, sur 4 images : yeux entre 0,72 et 0,80, sommet ≤ 0,92 (WARN jusqu'à 0,95) | `check_asset.py` sur le GLB | B |
| CHK-24 | Silhouettes distinctes et équitables | corps entiers en rendus binaires de 43 px : IoU deux à deux ≤ 0,85 ; têtes détourées à 64 px : IoU ≤ 0,75 ; aire de silhouette à ± 10 % de la moyenne du roster (face et profil) | turntable + script | B |
| CHK-25 | Budgets personnage | ≤ 15 000 triangles (tête ≤ 3 000), ≤ 4 matériaux, LOD1 et LOD2 présents | `check_asset.py` | B |
| CHK-26 | Couleurs d'agent | couleur-clé hors bandes réservées ; texte d'autocollant ≥ 4,5:1 sur la clé | tokens | B |
| CHK-27 | Shading personnage | `paint_grain_strength` = 0, `band_count` = 2, reflet uniquement sur les slots laqués | lint des matériaux au runtime | I |
| CHK-28 | Zone de visée libre | à la hanche : 0 pixel de viewmodel dans le carré central de 20 % × 20 % | fp_shots, masque viewmodel | B |
| CHK-29 | Couverture du viewmodel | selon la catégorie : poing 7–10 %, SMG 11–15 %, fusil 13–17 %, pompe 15–19 %, sniper 15–19 %, lourde 18–22 % ; ADS ≤ 28 % ; sprint ≤ 20 % | fp_shots | B |
| CHK-30 | Position du canon | bout du canon à la hanche : x 0,58–0,64, y 0,56–0,64 | fp_shots + marqueur `muzzle` | I |
| CHK-31 | Armes distinctes | silhouettes de profil de 64 px : IoU entre deux armes quelconques ≤ 0,80 | viewmodel_shots | I |

### 11.5 Interface

| # | Contrôle | Seuil | Mesure | B |
|---|---|---|---|---|
| CHK-32 | Taille de texte | tout texte visible : ≥ 21 px à 1080p et ≥ 14 px rendus à 720p (échelle d'interface à 100 %) | ui_shots (parcours de l'arbre) | B |
| CHK-33 | Contraste du texte | ≥ 4,5:1 contre le fond médian de son rectangle ; ≥ 3:1 si ≥ 33 px en gras | ui_shots | B |
| CHK-34 | Marges de sécurité | aucun `Control` de HUD dans les marges de 48 px (1080p), 32 px (720p) ou 36 px (800p) | ui_shots, HUD | B |
| CHK-35 | Zone centrale | dans le carré central de 40 % × 40 % : uniquement des nœuds du groupe `hud_center` (réticule, hitmarker, arcs, lunette) | ui_shots, HUD | B |
| CHK-36 | Discipline du pinceau | 1 bandeau de titre + ≤ 3 bandeaux de section par écran ; aucun bouton en pinceau hors CTA principal | ui_shots (types de nœuds) | B |
| CHK-37 | États complets | chaque contrôle interactif a les styles `hover`, `focus`, `pressed` et `disabled` ; chaque contrôle désactivé expose une raison (infobulle ou libellé) non vide | lint du thème + ui_shots | B |
| CHK-38 | Géométrie | formes inclinées à 12 ± 0,5° ; cisaillement italique 0,2126 ; ombres dures sans flou ; aucun `StyleBoxFlat` avec `shadow_size` > 0 | lint de `Comic.gd` et du thème | I |
| CHK-39 | Polices | seuls Barlow (Condensed et Semi Condensed) et Bangers sont chargés ; Bangers : ≤ 6 mots distincts, jamais de chiffre | lint des ressources | B |
| CHK-40 | HUD sans couleur d'agent | en match, dans les rectangles du HUD : 0 pixel à ΔE_OK < 8 d'une couleur-clé d'agent | ui_shots, HUD | I |
| CHK-41 | Mouvement | durées de tween de 90 à 400 ms (trame 600–1 200) ; en mouvement réduit : aucune interpolation d'échelle, de rotation ou de position | lint de `UiFx` + test | B |

### 11.6 Effets et performance

| # | Contrôle | Seuil | Mesure | B |
|---|---|---|---|---|
| CHK-42 | Flash de bouche | ≤ 6 % de l'écran, ≤ 50 ms, jamais dans le carré central de 10 % | fp_shots en rafale | B |
| CHK-43 | Fumée opaque | au centre d'une fumée : 0 % de visibilité (raycast vision) ; couleur à ΔE_OK ≤ 5 de `#EDE4CF` ; contour visible | sonde de capacités | B |
| CHK-44 | Marque d'équipe | tout objet de capacité posé porte un anneau d'équipe visible à 20 m (≥ 3 px) | gameplay_probe + capture | B |
| CHK-45 | Zéro sang | aucune couleur d'effet de dégât sur un personnage avec h ∈ [10°, 40°], C > 0,12 et L < 0,55 | lint des effets | B |
| CHK-46 | Performance | perf_bench, 1080p, configuration « recommandée » : moyenne ≥ 144 fps, 1 % bas ≥ 100 fps ; ≤ 1 500 draw calls ; ≤ 2,5 M triangles | perf_bench | B |
| CHK-47 | Mémoire | textures d'une carte ≤ 256 Mo de VRAM ; pool de décalques ≤ 64 | moniteurs de rendu | I |

**Barème :** une vague art ou UI est « livrable » si **0 FAIL bloquant** et au plus 3 WARN. `style_check` publie le score (PASS / total) dans le rapport de revue ; objectif ≥ 90 % sur Wasteland et Cargo Ship avant de toucher aux 6 autres cartes.

## 12. Backlog
<a id="12-backlog"></a>

### 12.1 Mode d'emploi

**Import :** le bloc ci-dessous s'importe avec `python tools/tasks/plan.py import docs/STYLE_BIBLE.md` (format strict de `extract_tasks`).

**Épopées :**
- E4 (art, 3D, VFX) par défaut ;
- E5 pour l'interface ;
- héritage des dépendances d'épopée (ART-00, OPS-03, RES-02).

**Dépendances vers le backlog existant :**
- A3D-02/03/04 : stylekit, migration des générateurs. A3D-08 (têtes d'objet) est caduque depuis la v3.1 (§4.8).
- UX-01/05/06/08/11 : fonctions d'écran.
- GF-06/07 : traceurs, confirmations.
- OPS-01 : chaîne de revue.

**Ordre voulu :** d'abord ce qui supprime la boue (ART-01 à 07), puis le lot 1 (Wasteland, Cargo, Vif, Verrou, HUD), noté par ART-50, puis le reste.

**Tailles :** S ≤ ½ jour d'agent, M ≈ 1 jour, L ≥ 2 jours.

**Top 5**, à lancer en premier (vague 1, fichiers disjoints) :

| Tâche | Contenu |
|---|---|
| ART-01 | Environnement WYSIWYG + sonde |
| ART-04 | Textures sans encre, trim-sheets, décalques |
| ART-03 | Scoreur de checklist |
| ART-30 | Jetons UI et polices |
| ART-08 | Contour v3 |

ART-02, puis ART-05, puis ART-06/07 suivent en vague 2.

### 12.2 Tâches

```yaml
  - id: ART-01
    epic: E4
    title: Environnement WYSIWYG (tonemap linéaire) et sonde de calibration look_probe
    priority: P0
    size: M
    depends_on: []
    files: [scripts/core/LevelLook.gd, tools/look_probe.gd, scenes/dev/look_probe.tscn, tests/rendering/test_level_look.gd]
    acceptance: LevelLook applique la table du §7.5 (tonemap LINEAR exposition 1.0, adjustment désactivé, ambiance 0.18, SSAO 0.8/1.0/1.5 et light_affect 0.15, soleil angular_distance 0.5, portée d'ombre 120 m, PSSM 4) ; tools/look_probe.gd rend un cube #D2A46C et un cube de 2 m à 30 m sur chaque carte et écrit look_probe.json ; L OKLab de la face éclairée = 0.75 ± 0.03 (CHK-01 partie éclairée PASS) ; le ratio d'ombre est mesuré et rapporté (PASS exigé seulement après ART-02).
    verify: ["godot --path . -s res://tools/look_probe.gd"]

  - id: ART-02
    epic: E4
    title: ink_toon v3 — 2 bandes, ombre perceptuelle, masques vertex, lavis monde, reflet dur
    priority: P0
    size: M
    depends_on: [ART-01]
    files: [assets/shaders/ink_toon.gdshader, tests/rendering/test_ink_toon_params.gd]
    acceptance: uniforms et valeurs par défaut du §7.2 (band_count 2, band_softness 0.10, shadow_value 0.66, shadow_tint_mix 0.40, use_vertex_masks, ao_min 0.55, edge_highlight 0.15, height_grad 0.88→1.04, wash_scale 0.35, wash_strength 0.04, gloss_strength, gloss_size, paint_grain 0) ; appels existants de Cartoon.gd inchangés et fonctionnels ; look_probe CHK-01 et CHK-09 PASS sur les 8 cartes.

  - id: ART-03
    epic: E4
    title: Scoreur automatique de la checklist de style (style_check) branché sur la revue
    priority: P0
    size: L
    depends_on: [OPS-01]
    files: [tools/review/style_check.py, tools/review/style_masks.gd, tests/review/test_style_check.py, tools/review/run_review.ps1]
    acceptance: style_check lit docs/style/tokens.json et note CHK-01 à CHK-47 (PASS/WARN/FAIL, « non mesuré » = WARN) sur les captures de revue, les fichiers d'asset et les jetons ; style_masks.gd produit les masques HUD, personnages et viewmodel ; étape style_check dans run_review.ps1 avec style_check.json et score PASS/total dans le rapport ; tests sur images synthétiques pour CHK-02, CHK-06, CHK-18 et CHK-32.
    verify: ["python tools/review/style_check.py --self-test"]

  - id: ART-04
    epic: E4
    title: gen_textures v3 — albédos sans encre, 7 terrains, 4 trim-sheets, atlas de décalques
    priority: P0
    size: M
    depends_on: []
    files: [tools/textures/gen_textures.py, assets/textures/painted/, assets/textures/trim/, assets/textures/decals/]
    acceptance: plus aucun appel creases() ou wavy_lines() dans un albédo ; terrains 1024² (sable #D2A46C, pont, pavés, neige, calcaire, terre battue, quai), trim-sheets 1024² (désert, port-cargo, ville, alpin) et atlas de décalques 2048² (pochoirs FUEL, GAS, numéros, flèches, FRAGILE, GRAINES, autocollants de l'émission, étoiles d'impact, brûlures, fissures, lettres A/B) ; CHK-08 PASS sur tous les fichiers ; sortie déterministe (deux exécutions produisent les mêmes octets).
    verify: ["python tools/textures/gen_textures.py"]

  - id: ART-05
    epic: E4
    title: Cartoon.gd v3 — palettes de carte v3, fabrique prop_uv, zéro grain, jetons générés
    priority: P0
    size: M
    depends_on: [ART-02]
    files: [scripts/core/Cartoon.gd, tools/style/gen_style_tokens.py, scripts/core/StyleTokens.gd, tests/rendering/test_map_palettes.gd]
    acceptance: _MAP_PALETTES reprend tokens.json maps (ciel, soleil, élévation, ombre, sol, coulisses, brouillard) sans assombrissement de compensation ; prop_uv(kind, tint) sert les maillages Blender (UV + masques vertex, sans triplanaire) ; _CHARACTER_GRAIN à 0 ; _TRIPLANAR_SCALE 1/4 ; StyleTokens.gd généré depuis docs/style/tokens.json par gen_style_tokens.py ; CHK-07 PASS ; INK, ally_color() et enemy_color() inchangés.

  - id: ART-06
    epic: E4
    title: Ciel v3 et coulisses d'horizon (anneau de silhouettes) sur les 8 cartes
    priority: P0
    size: M
    depends_on: [ART-01, ART-05]
    files: [assets/shaders/ink_sky.gdshader, scripts/core/LevelLook.gd, scripts/levels/Backdrop.gd, tools/blender/make_backdrops.py, assets/models/backdrops/]
    acceptance: paramètres de ciel du §7.6 ; anneau unshaded de 150 à 600 m par thème (désert, port-cargo, ville, montagne), posé selon MatchConfig.map_id, qui ferme l'horizon sous 5° ; CHK-12 et CHK-13 PASS sur les 8 cartes en vues aériennes et joueur ; au plus 40 draw calls ajoutés (perf_bench).

  - id: ART-07
    epic: E4
    title: ink_edges v3 — plis par normale et largeurs de silhouette recalibrées
    priority: P1
    size: M
    depends_on: [ART-01]
    files: [assets/shaders/ink_edges.gdshader, scripts/core/InkPost.gd]
    acceptance: paramètres du §7.4 (3.0 px jusqu'à 8 m puis 1.5 px à 50 m et au-delà, opacité plancher 0.5 à 100 m, brouillard 40/150/0.35) ; plis via hint_normal_roughness_texture (angle 35°, 1.5 px, fondu 15 à 30 m, opacité 0.85) ; CHK-10 et CHK-11 PASS ; surcoût GPU au plus 0.4 ms à 1080p (perf_bench). TECH-05 reprendra les mêmes paramètres.

  - id: ART-08
    epic: E4
    title: ink_outline v3 — poids bas des personnages et table de largeurs par distance
    priority: P0
    size: S
    depends_on: []
    files: [assets/shaders/ink_outline.gdshader, tests/rendering/test_outline_widths.gd]
    acceptance: uniform bottom_weight (1.25 sous 0.3 m) ; largeurs du §7.3 à ±0.1 px (fonction de largeur testée à 5, 10, 20, 30, 40, 60 et 90 m) ; la coque de surbrillance ennemie ne descend jamais sous 2.5 px (base de CHK-20).

  - id: ART-09
    epic: E4
    title: Heures du jour et descriptions des cartes alignées sur la bible
    priority: P2
    size: S
    depends_on: []
    files: [scripts/levels/maps/MapCatalog.gd]
    acceptance: Saint-Ombre « Fin d'orage au crépuscule, pavés et piliers industriels. » ; Cargo Ship « Porte-conteneurs au mouillage, fin de matinée. » ; les autres descriptions sont cohérentes avec le §6.4 ; tests de MapCatalog verts.

  - id: ART-10
    epic: E4
    title: Gabarit personnage v3.1 (squelette UAL-G, col à 1.40 m, crâne 1:7) et contrôle de gabarit
    priority: P1
    size: L
    depends_on: [A3D-04]
    files: [tools/blender/make_characters.py, tools/blender/check_asset.py, assets/models/characters/, docs/style/tokens.json]
    acceptance: squelette UAL-G du §4.1 (deltoïdes au plus 1.38 m, menton 1.49 m, yeux 1.62 m, jambes UAL intactes, 46 animations conservées) partagé par les 6 agents et fp_arms ; blockout neutre du gabarit à 1.80 m de haut tout compris ; check_asset.py mesure CHK-23 debout (12 images) et accroupi (4 images), CHK-24 (aire à ±10 %) et CHK-25 ; blocs character, agents et CHK-22/23 de tokens.json resynchronisés sur le §4 ; turntable 4 vues dans assets/models/characters/_review/.

  - id: ART-11
    epic: E4
    title: Agents lot 1 — Vif (humaine) et Verrou (grenouille), du concept au GLB, planche de validation
    priority: P1
    size: M
    depends_on: [ART-10]
    files: [tools/blender/make_characters.py, assets/models/characters/, docs/style/concepts/, docs/style/reviews/]
    acceptance: concepts générés avec docs/style/character_prompts.md et validés par l'utilisateur avant toute 3D ; forme Tripo nettoyée, calée sur le gabarit et skinnée sur UAL-G ; palettes, matières et reflets des §4.4 et §4.5 ; CHK-23 et CHK-25 PASS ; planche turntable, silhouettes à 43 px, têtes à 64 px et vue en match à 20 m déposée dans docs/style/reviews/agents_lot1.png pour validation par l'utilisateur.

  - id: ART-17
    epic: E4
    title: Agents lot 2 — Choc (humain), Vanne (humaine, ingénieure), Guet (vautour éveillé), Roseau (héronne éveillée)
    priority: P1
    size: L
    depends_on: [ART-11]
    files: [tools/blender/make_characters.py, assets/models/characters/, docs/style/concepts/]
    acceptance: ne démarre qu'après l'accord explicite de l'utilisateur sur agents_lot1.png ; 4 agents conformes au §4.4, même chaîne que ART-11 ; CHK-23, CHK-24 (IoU des corps au plus 0.85 à 43 px, des têtes au plus 0.75 à 64 px, aire à ±10 % sur les 6 agents) et CHK-25 PASS.

  - id: ART-12
    epic: E4
    title: Cadrage du viewmodel — FOV fixe 54°, arme à droite, carré central libre
    priority: P1
    size: M
    depends_on: []
    files: [scripts/player/ViewModel.gd, tools/fp_shots.gd]
    acceptance: FOV vertical du viewmodel fixé à 54° quel que soit le FOV monde ; positions hanche, ADS et sprint par catégorie selon le §5.3 ; fp_shots produit un masque viewmodel ; CHK-28 et CHK-29 PASS et CHK-30 au moins WARN pour les 10 armes.

  - id: ART-13
    epic: E4
    title: Les 10 armes v3 — archétype lisible, signature fantaisiste, emplacements d'autocollant
    priority: P1
    size: L
    depends_on: [A3D-03, ART-20]
    files: [tools/blender/make_weapons.py, assets/models/weapons/]
    acceptance: 10 armes selon le §5.2 (FP 8 à 12k triangles, TP 1.2 à 2k, biseaux 3 mm et 1 cm, un accent émaillé, 2 emplacements d'autocollant à 512 px/m, marqueur muzzle) ; CHK-31 PASS ; planche de silhouettes de profil à 64 px jointe au rapport, classée correctement 9 fois sur 10 en test à l'aveugle.

  - id: ART-14
    epic: E4
    title: Couleurs d'agent v3 et rim de ciel des personnages
    priority: P1
    size: S
    depends_on: []
    files: [scripts/agents/AgentDatabase.gd, scripts/player/PlayerLook.gd, tests/agents/test_agent_palette.gd]
    acceptance: AgentConfig.color égal aux couleurs-clés de tokens.json agents (Vif #EE6A24, Choc #BE2D25, Vanne #F2B51D, Guet #5157B8, Roseau #2E9C8A, Verrou #2A5FC4) ; PlayerLook applique la palette de tenue par slot et un rim horizon de 0.20 (le rim ennemi de 0.6 reste inchangé) ; le test vérifie qu'aucune couleur d'agent ne tombe dans une bande réservée et que le texte d'autocollant atteint au moins 4.5:1 (CHK-26).

  - id: ART-15
    epic: E4
    title: Personnalité d'animation par agent (démarche, idle, rebond) dans les limites du gabarit
    priority: P2
    size: M
    depends_on: [ART-10]
    files: [scripts/player/CharacterAnimator.gd, resources/agents/anim/]
    acceptance: profils additifs par agent selon le §4.6 (rebond, inclinaison, cadence de ×0.9 à ×1.15, idle unique) ; un test vérifie que, debout, les yeux restent au moins à 1.56 m et le menton au moins à 1.43 m pour chaque profil ; aucun écrasement de tête, écrasement du corps de 0.97 à 1.03 pendant au plus 80 ms ; en mouvement réduit, le gameplay est inchangé.

  - id: ART-16
    epic: E4
    title: Gants et manches FP par agent
    priority: P2
    size: M
    depends_on: [A3D-03, ART-10]
    files: [tools/blender/make_gloves.py, assets/models/characters/fp_gloves*]
    acceptance: 6 variantes selon le §4.7 (manche et main par agent, mains ×1.15 au plus, main de grenouille à 4 doigts pour Verrou) sur les avant-bras d'UAL-G, avec les mêmes points de prise qu'aujourd'hui ; couverture d'écran à ±1 % du gabarit ; fp_shots : CHK-28 toujours PASS.

  - id: ART-20
    epic: E4
    title: Stylekit v3 — masques vertex RGBA, biseaux par classe, normales pondérées, LOD
    priority: P1
    size: M
    depends_on: [A3D-02]
    files: [tools/blender/stylekit.py, tools/blender/check_asset.py]
    acceptance: fonctions du §7.9 (biseau par classe du §6.6, WEIGHTED_NORMAL, COLOR_0 avec R = AO cuit, G = convexité, B = hauteur, A = zone, export LOD1 et LOD2) ; check_asset vérifie COLOR_0, les budgets et l'absence de pièce flottante (CHK-16) ; le prop d'exemple montre des arêtes éclaircies et un AO de contact dans look_probe.

  - id: ART-21
    epic: E4
    title: Props v3 Wasteland et Cargo Ship (skins, couverts, repères) en jouets biseautés
    priority: P1
    size: L
    depends_on: [ART-20, ART-04, A3D-03]
    files: [tools/blender/make_props.py, assets/models/props/]
    acceptance: catalogue de maps-spec-v2 §3.1 pour ces deux thèmes refait selon les §6.5 et §6.6 (une couleur saturée par prop, pochoirs en décalque, couverts à 1.1 ou au moins 2.0 m, décor fin d'au plus 0.15 m ou ajouré, budgets par classe) ; CHK-15 et CHK-16 PASS ; une planche turntable par prop.

  - id: ART-22
    epic: E4
    title: Props v3 des autres thèmes (port, adobe, ville, alpin, carrière, toits)
    priority: P2
    size: L
    depends_on: [ART-21]
    files: [tools/blender/make_props.py, assets/models/props/]
    acceptance: mêmes règles qu'ART-21 pour les props des 6 autres cartes (§6.4 matériaux et repères) ; CHK-15 et CHK-16 PASS ; planches turntable.

  - id: ART-23
    epic: E4
    title: Wasteland v3 de bout en bout (palette, repères, décalques, coulisses)
    priority: P1
    size: L
    depends_on: [ART-02, ART-05, ART-06, ART-07, ART-21, ART-27]
    files: [scripts/levels/maps/layouts/wasteland.gd, scenes/levels/maps/wasteland.tscn]
    acceptance: palette du §6.4 (sol #D2A46C), repères FUEL, château d'eau, grue, derrick, GAS et réservoirs visibles (CHK-14) ; style_check sur les 10 vues de map_shots au moins 90 % PASS et 0 FAIL bloquant parmi CHK-02 à CHK-21 ; CHK-46 PASS ; aucune modification de la géométrie jouable (tests de Layouts verts).

  - id: ART-24
    epic: E4
    title: Cargo Ship v3 de bout en bout (conteneurs par quadrant, coque #7E251D, mer, coulisses)
    priority: P1
    size: L
    depends_on: [ART-02, ART-05, ART-06, ART-07, ART-21, ART-27]
    files: [scripts/levels/maps/layouts/cargo_ship.gd, scenes/levels/maps/cargo_ship.tscn]
    acceptance: palette du §6.4 (une couleur de conteneur par quadrant, coque #7E251D, pont #8D959B, danger #F2B51D) ; repères passerelle, grues et mât de proue (CHK-14) ; style_check au moins 90 % PASS et 0 FAIL bloquant parmi CHK-02 à CHK-21 ; CHK-46 PASS ; géométrie jouable inchangée.

  - id: ART-25
    epic: E4
    title: Repeindre Port-Ferraille, Val-Poussière et Saint-Ombre en v3
    priority: P2
    size: L
    depends_on: [ART-22, ART-23, ART-24]
    files: [scripts/levels/maps/dressing/PortFerrailleDressing.gd, scripts/levels/maps/dressing/ValPoussiereDressing.gd, scripts/levels/maps/dressing/SaintOmbreDressing.gd]
    acceptance: palettes et repères du §6.4 ; style_check au moins 90 % PASS et 0 FAIL bloquant pour chaque carte ; CHK-46 PASS.

  - id: ART-26
    epic: E4
    title: Repeindre Col du Vautour, La Fosse et Le Belvédère en v3
    priority: P2
    size: L
    depends_on: [ART-22, ART-23, ART-24]
    files: [scripts/levels/maps/dressing/ColDuVautourDressing.gd, scripts/levels/maps/dressing/LaFosseDressing.gd, scripts/levels/maps/dressing/LeBelvedereDressing.gd]
    acceptance: palettes et repères du §6.4 (au moins 2 repères pour les arènes de duel) ; style_check au moins 90 % PASS et 0 FAIL bloquant pour chaque carte ; CHK-46 PASS.

  - id: ART-27
    epic: E4
    title: Décalques de sites A/B et de zones d'objectif
    priority: P1
    size: S
    depends_on: [ART-04]
    files: [scripts/levels/maps/SiteDecals.gd, scripts/levels/maps/MapSetup.gd]
    acceptance: lettre pochoir de 2 m jaune objectif #F2C230 cernée d'encre sur chaque site snd et hardpoint des cartes 4v4 ; c'est le seul usage du jaune objectif dans le décor ; lettre d'au moins 20 px de haut vue depuis l'entrée du site à 15 m.

  - id: ART-30
    epic: E5
    title: Jetons UI v3 et polices (vraies italiques Barlow, Bangers) dans Comic.gd
    priority: P0
    size: M
    depends_on: []
    files: [scripts/ui/Comic.gd, resources/fonts/]
    acceptance: couleurs (neutres chauds, papier, pinceau), échelle 21 × 1.25, espacement de 6, formes, ombres dures et durées de tokens.json ; ajout de BarlowCondensed-ExtraBoldItalic, BarlowCondensed-BoldItalic et Bangers-Regular avec leurs licences OFL ; plus aucune référence à Protest Revolution ni à Lato ; _ITALIC_SLANT à 0.2126 en repli ; CHK-38 et CHK-39 PASS ; ui_shots sans casse de mise en page en 1080p et 720p.

  - id: ART-31
    epic: E5
    title: Kit de composants autocollant (bandeau v3, barre inclinée, carte, hexagone, bulle, trame)
    priority: P0
    size: L
    depends_on: [ART-30]
    files: [scripts/ui/BrushHeader.gd, scripts/ui/kit/, assets/shaders/ui_halftone.gdshader, assets/ui/brush/, scenes/dev/ui_kit_gallery.tscn]
    acceptance: composants des §8.2 et §8.4 avec leurs 9 états (défaut, survol, focus visible, pressé, sélectionné, désactivé avec raison, chargement, vide, erreur) ; bandeau pinceau sans queue en poisson ; galerie scenes/dev/ui_kit_gallery.tscn capturée par ui_shots en 1080p et 720p ; CHK-33, CHK-37 et CHK-38 PASS.

  - id: ART-32
    epic: E5
    title: Menu principal et écran Jouer v3
    priority: P1
    size: M
    depends_on: [ART-31, UX-08]
    files: [scripts/ui/MainMenu.gd, scenes/ui/main_menu.tscn]
    acceptance: maquettes du §8.6 (JOUER en un clic, IP déplacée dans Partie personnalisée, logo autocollant, agent 3D devant le disque solaire, cartes de mode et de carte en autocollants avec vignettes) ; CHK-32 à CHK-37 PASS en 1080p et 720p.

  - id: ART-33
    epic: E5
    title: Sélection d'agent v3 (aplat couleur-clé, roster, hexagones, verrouillage)
    priority: P1
    size: M
    depends_on: [ART-31, ART-38, UX-11]
    files: [scripts/ui/AgentSelectScreen.gd, scripts/ui/AgentMenu.gd]
    acceptance: maquette du §8.6 (roster à gauche, aplat de la couleur-clé et nom en filigrane à 12 %, agent 3D en pose signature, 4 hexagones, bouton VERROUILLER incliné, choix des coéquipiers) ; verrouillage avec moment de trame d'au plus 1.0 s et fondu seul en mouvement réduit ; CHK-32 à CHK-37 PASS.

  - id: ART-34
    epic: E5
    title: Achat et Arsenal v3 (cartes-armes, panneau de détail, états verrouillés)
    priority: P1
    size: M
    depends_on: [ART-31, UX-05]
    files: [scripts/ui/BuyMenu.gd, scripts/ui/ArsenalMenu.gd]
    acceptance: maquette du §8.6 (onglets inclinés 1 à 6, cartes-autocollants avec silhouette et prix, désactivé avec « N cr requis », détail avec barres de stats et rotation de l'arme) ; CHK-32 à CHK-37 PASS en 1080p et 720p.

  - id: ART-35
    epic: E5
    title: HUD v3 (chips charbon, hexagones de capacité, échelle 21, marges de sécurité)
    priority: P1
    size: L
    depends_on: [ART-31, UX-01]
    files: [scripts/ui/GameHUD.gd, scripts/ui/hud/AbilityBar.gd, scripts/ui/hud/AmmoPanel.gd, scripts/ui/hud/HealthPanel.gd, scripts/ui/hud/ScorePanel.gd, scripts/ui/hud/RoundPanel.gd, scripts/ui/hud/KillfeedPanel.gd, scripts/ui/ComicChip.gd, scripts/ui/ComicBar.gd]
    acceptance: règles et maquette HUD des §8.3 et §8.6 (tailles, hexagones et leurs états, vie basse en pinceau, munitions basses, positions en 1080p, 720p et 800p) ; CHK-32, CHK-33, CHK-34, CHK-35 et CHK-40 PASS.

  - id: ART-36
    epic: E5
    title: Tableau des scores, écran « REMBALLÉ » et fin de match v3
    priority: P1
    size: M
    depends_on: [ART-31, UX-01]
    files: [scripts/ui/hud/ScoreboardPanel.gd, scripts/ui/hud/EndPanel.gd, scripts/ui/hud/DeathPanel.gd]
    acceptance: maquettes du §8.6 (barres inclinées par joueur avec onglets ● et ▼, ligne du joueur local en papier, carte MVP sur l'aplat de l'agent, VICTOIRE ou DÉFAITE en display 100 avec wipe) ; écran de mort « REMBALLÉ » avec tueur ▼ et arme ; CHK-32 à CHK-37 PASS.

  - id: ART-37
    epic: E5
    title: Réglages et pause v3 (onglets inclinés, curseurs en fente, aperçu)
    priority: P2
    size: M
    depends_on: [ART-31, UX-06]
    files: [scripts/ui/OptionsMenu.gd, scripts/ui/PauseMenu.gd]
    acceptance: maquette du §8.6 (aperçu de la couleur ennemie sur 4 fonds de carte, encre renforcée ×1.5, échelle d'interface de 80 à 120 %, mouvement réduit) ; cibles d'au moins 44 px ; CHK-32 à CHK-37 PASS.

  - id: ART-38
    epic: E5
    title: Portraits d'agents (rendus 3D détourés pour roster, tableau et killfeed)
    priority: P1
    size: S
    depends_on: [ART-17]
    files: [tools/portrait_shots.gd, assets/ui/portraits/]
    acceptance: pour chaque agent, 3 formats (roster 192², tableau 96² avec la tête qui déborde, killfeed 48²) sur fond transparent, contour encre de 3 px et ombre dure ; générés par script de façon déterministe.

  - id: ART-39
    epic: E5
    title: Sons d'interface (tic, schlack, ka-ching, DING, fanfare)
    priority: P2
    size: S
    depends_on: []
    files: [tools/audio/gen_ui_sfx.py, assets/audio/sfx/ui/]
    acceptance: les 11 sons du §8.5 générés procéduralement (durées à ±20 %), normalisés à -12 dB par rapport aux armes ; branchement par UiFx (UX-12), Audio.gd n'est pas modifié ici.
    verify: ["python tools/audio/gen_ui_sfx.py"]

  - id: ART-40
    epic: E4
    title: Kit VFX peint — flash de bouche, traceurs, impacts, poussière, étincelles, décalques
    priority: P1
    size: L
    depends_on: [GF-06, ART-04]
    files: [scripts/vfx/ComicFx.gd, scripts/vfx/DecalPool.gd, assets/vfx/, assets/shaders/fx_flat.gdshader, scripts/combat/ImpactFx.gd]
    acceptance: effets des §9.2 et §9.3 animés sur deux (12 i/s) avec contour encre de 2 px et la palette VFX fermée ; pool de 64 décalques FIFO ; rembourrage et confettis sur les personnages, jamais de sang (CHK-45) ; CHK-42 PASS ; au plus 64 particules par effet.

  - id: ART-41
    epic: E5
    title: Retour de tir v3 — hitmarkers, confirmation de kill, onomatopées, chiffres de dégâts
    priority: P1
    size: M
    depends_on: [GF-07, ART-30]
    files: [scripts/ui/hud/HitMarker.gd, scripts/ui/hud/HitFeedback.gd, scripts/ui/hud/KillWordBurst.gd, scripts/ui/hud/DamageNumber3D.gd, scripts/combat/Weapon.gd]
    acceptance: tableau du §9.4 (tailles, couleurs, durées, onomatopée à x 0.72 et y 0.38 hors zone centrale, cumul des dégâts sur 0.8 s, fondu seul en mouvement réduit) ; Weapon._spawn_damage_number délègue à DamageNumber3D ; CHK-35 et CHK-41 PASS.

  - id: ART-42
    epic: E4
    title: Capacités v3 — objets d'agent, fumée cel opaque, reveal en bulle, anneau d'équipe
    priority: P1
    size: L
    depends_on: [ART-40, ART-20, ART-17]
    files: [scripts/agents/AbilityController.gd, scripts/player/StunStars.gd, tools/blender/make_ability_props.py, assets/models/abilities/]
    acceptance: tableau du §9.6 pour les 12 capacités (objets de l'agent, fumée à 3 tons opaque, étoiles d'étourdissement, bulle « ! », gouttes de soin, onomatopées d'ultime) ; CHK-43 et CHK-44 PASS ; tailles et collisions des objets répliqués inchangées (tests des agents verts).

  - id: ART-43
    epic: E4
    title: Élimination « REMBALLÉ » — rembourrage, confettis, emblème qui roule
    priority: P1
    size: M
    depends_on: [ART-40, ART-17]
    files: [scripts/vfx/PoofFx.gd, scripts/player/CharacterBody.gd, assets/models/emblems/]
    acceptance: séquence du §9.5 en 0.9 s (écrasement, nuage de rembourrage, 12 confettis de la couleur-clé, corps qui disparaît dans le nuage, emblème de l'agent qui rebondit puis disparaît en fondu à 2.0 s), sans ragdoll ; aucune couleur de sang (CHK-45) ; au plus 64 particules.

  - id: ART-19
    epic: E4
    title: Planches concept IA des 6 agents et de 2 décors depuis le prompt kit (optionnel)
    priority: P3
    size: M
    depends_on: [A3D-10, A3D-09]
    files: [assets/concepts/]
    acceptance: ne démarre qu'après l'accord de l'utilisateur (A3D-10) ; 6 concepts d'agent de face en A-pose générés avec docs/style/character_prompts.md et 2 vues de décor générées avec les prompts du §13, provenance enregistrée selon A3D-09 ; usage de référence seulement, jamais d'asset livré tel quel.

  - id: ART-50
    epic: E4
    title: Revue style du lot 1 — Wasteland, Cargo Ship, Vif, Verrou, HUD, notée et comparée
    priority: P1
    size: S
    depends_on: [ART-03, ART-11, ART-23, ART-24, ART-35]
    files: [docs/style/reviews/lot1.md]
    acceptance: rapport avec le score style_check par carte (au moins 90 %, 0 FAIL bloquant), une planche avant/après sur les mêmes poses de caméra que le diagnostic du §0 et les écarts restants rédigés en tâches ART au format strict.
```

## 13. Prompts
<a id="13-prompts"></a>

### 13.1 Mode d'emploi

- **Usage :** génération d'images de concept et de textures. Réservé à ART-19 et à la tâche A3D-10, après accord de l'utilisateur, avec provenance enregistrée (A3D-09).
- **Langue :** les prompts sont en anglais, parce que les modèles d'image y répondent mieux.
- **Aucun nom de jeu, de studio ou d'artiste existant** : on décrit le style, on ne l'emprunte pas.
- **Composition d'un prompt :** texte du prompt, puis le **suffixe de style**, puis le **négatif**.

**Suffixe de style** (à coller à la fin de chaque prompt) :
```
flat cel-shaded 3D render, two-tone lighting (one lit tone, one shadow tone), cool blue-violet shadows (#5C6EA8), bold dark-brown ink outlines (#1A1410) thicker on the silhouette and thinner inside, chunky bevelled toy-like shapes, clean solid colour blocks, a single hard glossy highlight only on lacquered parts, warm late-afternoon sun, saturated but controlled palette, no texture noise, readable silhouette
```

**Négatif :**
```
photorealistic, PBR, grunge, dirt noise, painted cracks, gradients everywhere, blur, bloom, neon, glassmorphism, purple, magenta, pink, lime green, leaf green, blood, gore, text watermark, logo of existing brands, thin spindly details, chibi 1:2 proportions, anime face on a human head
```

### 13.2 Prompts

**Agents :** les prompts des six agents (concept de face pour l'image→3D dans Tripo Studio, avec le gabarit du §4.1) sont dans [`docs/style/character_prompts.md`](style/character_prompts.md). Les prompts 1 à 3 de la v3 (têtes-objets) sont retirés ; la numérotation des autres est conservée.

4. **Rue de Wasteland (key art, hauteur joueur)**
   ```
   first-person eye-level view down a desert fuel-stop street, calm flat sand ground (#D2A46C), chunky bevelled shacks with corrugated blue tin (#4F7FA8) and rust-orange panels (#B5562A), a tall FUEL billboard and canopy as landmark, water tower and lattice crane silhouettes against a big blue sky (#2F74D8 to #BFDDF2) with 3 large flat-bottomed cumulus clouds, distant mesa silhouettes closing the horizon, long cool blue-violet shadows, clear lanes, cover crates at waist height and head height, no people
   ```
5. **Planche de props « jouets biseautés »**
   ```
   game prop sheet on neutral background, 12 chunky bevelled toy-like props for a cargo ship map: shipping containers in single solid colours (red #C8322B, blue #2F63B8, orange #E3872A, cream #E6E1D6) with stencilled numbers, hazard-striped hatch covers, bollards, deck crane, lifeboat, crates; each prop one saturated colour plus neutral steel, soft ambient-occlusion in creases, lighter bevelled edges, isometric 3/4 view, consistent scale with a 1.8 m human silhouette
   ```
6. **Texture de terrain répétable**
   ```
   seamless tileable top-down ground texture, desert sand #D2A46C, very low contrast (value variation under 4 percent), large soft patches only, a few small flat pebble shapes slightly darker, no lines, no cracks, no ink, no noise grain, stylized flat painted look, 1024x1024
   ```
7. **Trim-sheet par thème**
   ```
   game trim sheet texture 1024x1024, horizontal strips for stylized architecture: corrugated tin (flat value stripes, no blur), wooden planks with clean gaps, riveted steel band, painted concrete band, light bevel edge strip, stencil-friendly plain strip; flat solid colours in a warm desert palette, no dirt noise, no black ink lines, tileable horizontally
   ```
8. **Atlas de décalques (pochoirs et autocollants)**
   ```
   decal atlas on transparent background, spray-stencil words FUEL, GAS, FRAGILE, GRAINES, big stencil letters A and B, container numbers, arrows, comic impact stars, scorch marks, a round broadcast sticker badge reading LES JOUTES, all in flat solid colours with crisp edges, slightly imperfect hand-cut stencil spacing
   ```
9. **Écran d'interface (sélection d'agent)**
   ```
   game UI mockup 16:9, agent selection screen, charcoal warm-dark background (#14110F), a large flat colour field in the agent key colour behind a 3D character render, huge italic condensed agent name as a faint typographic poster, roster of hexagonal sticker portraits on the left, four hexagon ability icons with key tabs, a red brush-stroke header top-left, sticker-style buttons slanted 12 degrees with thick ink outline and hard offset black shadow, clean readable condensed sans-serif typography
   ```
10. **Planche VFX**
    ```
    stylized VFX sheet on dark background, flat cel-shaded cartoon effects: 5-point muzzle-flash stars (cream core, yellow ring, orange tips) with ink outline, tapered brush-stroke tracers, round cream smoke puffs in 3 tones with flat bottoms, comic impact stars, stuffing-cotton burst with coloured confetti, speed lines, spiral stun stars; 12 fps hand-drawn animation frames laid out in rows
    ```

## 14. Risques
<a id="14-risques"></a>

Classés par gravité.

1. **Un seul gabarit pour des humains et des créatures.** Le seuil à 1,40 m impose des épaules tombantes et un col haut. Mal dosé, ça donne des cous de girafe ou des bustes tassés.
   - *Garde-fous :* ART-10 livre d'abord le gabarit neutre. ART-11 ne produit que Vif (humaine) et Verrou (créature), avec une planche de validation ; ART-17 (les 4 autres) attend un accord explicite.
   - *Repli, si le rendu déplaît :* relever le seuil de headshot vers 1,47 m (`HEAD_HEIGHT_RATIO` ≈ 0,82), ce qui autorise des épaules réalistes. C'est une décision de gameplay (TTK, équilibrage), pas d'art.
2. **La capsule ment plus que le dessin.**
   - Elle fait 0,80 m de large, alors qu'un corps en fait 0,46 à 0,60 : on peut faire un headshot dans le vide à côté d'une tête.
   - Accroupi, sa bande headshot (0,20 m) est plus petite qu'une tête.
   - La sonde du 2026-09-24 a montré que sa forme est partagée entre tous les joueurs (§4.1).
   - *Mesures :* corriger le partage de la forme (tâche de code à part) ; mesurer l'accroupi (CHK-23).
   - *Recommandation durable :* une hitbox commune attachée à UAL-G (sphère de tête sur `DEF-head`, capsules de torse et de membres), identique pour les six agents et séparée de la capsule de déplacement.
   - *Repli pour l'accroupi :* si aucune pose ne tient les yeux entre 0,72 et 0,80 m avec le sommet sous 0,95 m, relever `crouch_height` vers 1,00 m et revoir les couverts de 1,10 m.
3. **La génération de formes peut faire « figurine ».** Tripo donne vite une silhouette, mais une forme mal nettoyée produit l'effet jouet en vinyle des concepts rejetés (`docs/style/concepts/lot1_contact.png`).
   - *Garde-fous :* prompts sans socle ni rendu plastique (`character_prompts.md`), forme seule, retopologie, biseaux, reflet dur réservé aux laqués, AO en vertex color, poses et démarches fortes.
   - *Le test :* la revue compare les turntables à l'épingle 08. Si c'est moins lisible qu'une guimauve en 2 tons, c'est un échec.
4. **Le tonemap linéaire écrête.** Albédos clairs (crème `#E6E1D6`, neige `#F1F4F8`), rebond et reflets peuvent dépasser 1,0.
   - *Règles :* albédo à L ≤ 0,93 ; soleil d'énergie 1,0 ; aucun émissif au-delà de 1,2 hors lampes.
   - *Sécurité :* CHK-01 attrape la dérive.
5. **Le Magenta sur les ombres grises neutres.** Sur les ombres de pont de Cargo, le contraste de luminance tombe à 2,5–2,7:1 ; la lisibilité y repose sur la teinte (ΔE_OK ≥ 34).
   - *Daltonisme :* protan contre le ciel de Wasteland (ΔE 2,9), tritan Citron contre les ciels pâles (ΔE 3,9).
   - *Mesures :* le premier lancement (UX-09) propose le test de couleur ennemie ; les options Citron et Magenta restent recommandées par type de daltonisme ; la forme (▼, anneau d'encre) porte le reste. CHK-18 et CHK-19 bloquent.
6. **Coût des plis en post-process sur le Steam Deck.** Normales et profondeur, plus des boucles de dilatation.
   - *Budget :* ≤ 0,4 ms à 1080p (ART-07) ; au-delà, on désactive les plis au-delà de 15 m ou via le préréglage « Deck ».
   - *À savoir :* TECH-05 (compositor) est la voie durable.
7. **Deux documents de style qui divergent.** A3D-01 (`docs/ART_3D.md`) écrit une « bible 3D » en parallèle.
   - *Règle :* `STYLE_BIBLE.md` + `tokens.json` font foi ; ART_3D.md doit citer les jetons, jamais les redéfinir. `style_check` lit les jetons, pas les documents.
8. **L'humour contre le sérieux compétitif.** Des cosmétiques bruyants peuvent casser la lisibilité.
   - *Règles :* tout cosmétique passe CHK-06, CHK-21 et CHK-24 ; jamais de rim, de contour ou de lueur colorés ; les autocollants restent dans leurs emplacements UV.
   - *Outil :* FUN-08 (`cosmetic_lint`) doit appeler `style_check`.
9. **Bangers est un cliché de la BD.** Limité à ≤ 6 onomatopées et au logo, avec un contour et une ombre dure maison. S'il fatigue, on le remplace sans toucher au reste : une seule référence dans `Comic.gd`.
10. **Le nom « LES JOUTES » est une proposition.** Il faut vérifier les marques avant tout logo définitif ; aucune tâche ne grave le nom dans le code.
11. **La cohérence entre agents parallèles.** Plusieurs agents Sonnet vont exécuter ces tâches. Le seul rempart est la mesure : `style_check` (ART-03) doit exister avant ART-23 et ART-24, sinon le lot 1 sera jugé à l'œil, ce qui est justement ce qui a produit le diagnostic du §0.
