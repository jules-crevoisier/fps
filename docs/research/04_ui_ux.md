# 04 — UI/UX : HUD, menus, réglages, accessibilité, onboarding

> Statut : REMPLI (recherche du 2026-09-23). Les chiffres marqués *(hypothèse)* sont nos
> propositions ; les autres sont sourcés.
> Contexte : retour joueur du 23/09 — « l'interface n'a pas l'air ok », « il faut un jeu
> polish, là ce n'est pas jouable ». Code lu : `scripts/ui/**`, `scripts/core/Settings.gd`,
> `scripts/player/PlayerCamera.gd`, `project.godot`, `.orchestrator/design.md` §11–13.

## 1. Résumé (10 lignes)

1. **Bug de lisibilité majeur : le HUD suppose que l'équipe 0 est toujours alliée.** C'est le cas du killfeed, du score, du scoreboard, de la page de fin et du compteur de vivants. Dès que le joueur est en équipe 1 (client, R&D après changement de camp), alliés et ennemis sont inversés.
2. **FOV trop large : 90° *vertical*** (Godot garde la hauteur par défaut), soit ≈ 121° horizontal en 16:9, avec jusqu'à +20° en slide. Valorant est figé à 103° h (70,53° v) et Overwatch plafonne à 103° h. D'où un effet fish-eye et des ennemis minuscules : une cause probable du « pas jouable ».
3. Le viseur est codé en dur. Valorant propose contour, point central, lignes intérieures et extérieures, erreur de mouvement et de tir, et des codes de viseur partageables.
4. Il n'y a ni minimap (pourtant prévue à 240 px dans `design.md` §12) ni callouts : le joueur ne sait pas où il est.
5. Menu principal : « JOUER (héberger) » et un champ IP `127.0.0.1` au premier niveau, ça fait prototype. GAG : on doit pouvoir lancer une partie sans traverser plusieurs niveaux de menus.
6. Réglages manquants : affichage (mode, échelle de rendu, vsync, limite d'images), multiplicateur de sensibilité ADS, maintien ou bascule, sous-titres et indices visuels du son, audio mono, volumes voix/UI/ambiance, secousses et effets de FOV.
7. Menu d'achat : liste texte sans raccourcis numériques ni « racheter ». CS2 achète en 2 touches (catégorie, puis arme) et propose l'achat automatique.
8. Pas de système de ping. En 4v4 avec des inconnus ou des bots, le ping contextuel d'Apex, pensé en jouant micros coupés, est devenu la norme.
9. Tailles de texte : 20 px minimum à 1080p respecte le XAG 101 PC (18 px). Sur Steam Deck, il faut **≥ 36 px à 200 DPI** d'après le XAG pour appareils mobiles : l'échelle d'UI par défaut doit monter sur Deck.
10. Direction visuelle : garder le « Persona 5 » (bandeaux inclinés, contraste fort, animations sans latence), mais le HUD en jeu doit rester minimal, comme Hi-Fi Rush qui a longtemps testé sans UI.

## 2. Findings (sources inline)

### 2.1 Disposition du HUD et hiérarchie d'information

- **Convention des hero shooters** (captures de la [Game UI Database](https://www.gameuidatabase.com/)) :
  - **Valorant** : score, timer et portraits vivants/morts en haut au centre ; minimap en haut à gauche ; killfeed en haut à droite ; vie, capacités et munitions en bas au centre.
  - **Overwatch 2** : vie en bas à gauche, capacités en bas à droite, ultime en bas au centre.
  - **Apex** : minimap en haut à gauche, escouade en bas à gauche, arme en bas à droite.
  - Notre maquette (`design.md` §12) suit ce schéma, sauf la minimap, absente du code.
- **Hiérarchie** : le centre (40 % × 40 %) ne sert qu'à l'action (viseur, hitmarkers, arcs de dégâts). C'est déjà notre règle, à garder.
- **Hi-Fi Rush** : l'équipe a longtemps développé *sans UI*. Elle cherchait à faire passer l'information par le monde et l'animation plutôt que par des invites (« how can we convey as much as possible without saying, 'hey, press here' »), et le métronome d'UI est optionnel ([Unreal Engine — interview Tango](https://www.unrealengine.com/en-US/developer-interviews/hi-fi-rush-was-inspired-by-shaun-of-the-dead-and-futurama)).
- **Splatoon** : icônes à forte chroma, fonds de modales à faible chroma, et une typo propre au jeu car aucune police existante ne collait au concept ([Hai-iro, How Nintendo designed Splatoon](https://medium.com/haiiro-io/how-nintendo-designed-switch-and-splatoon-d1a14b9cc2de)). Même règle que notre `design.md` : fonds charcoal, couleurs réservées au sens.

### 2.2 Viseur, hitmarkers, retours de combat

- **Réglages de viseur Valorant** ([ProSettings](https://prosettings.net/blog/best-valorant-crosshair/), [AimCodes](https://aimcodes.com/en/valorant-crosshair-settings/)) :
  - couleur ;
  - contour (on/off, opacité, épaisseur) ;
  - point central (taille, opacité) ;
  - lignes intérieures et extérieures (longueur, épaisseur, écart, opacité) ;
  - erreur de mouvement et de tir (souvent désactivées par les pros) ;
  - **codes de viseur** en import/export.
- **Chez nous** : 4 traits de 2 px, écart 5, longueur 7, contour 1 px, blanc (`GameHUD._build_crosshair`). Les hitmarkers, arcs de dégâts, onomatopées et la vignette de vie basse existent déjà : c'est le bon socle.

### 2.3 Killfeed, scoreboard, bannières de manche

- **Killfeed standard** : tueur (couleur de son équipe *relative au joueur*), icône d'arme ou de capacité, icône headshot, victime (couleur de *son* équipe). Chez nous, toute la ligne prend la couleur du tueur, sans arme ni headshot (`KillfeedPanel.push`).
- **Couleurs relatives au joueur** : allié et ennemi se calculent par rapport à l'équipe locale, jamais par rapport à l'indice d'équipe. C'est le principe « never hue alone » de `design.md` §9, qui suppose que le glyphe ●/▼ est juste.
- **Scoreboard** : agent, pseudo, K/D/A, score d'objectif, ping, badge BOT ; la ligne du joueur local est surlignée.
- **Fin de match** : « VICTOIRE / DÉFAITE » pour *toi*, pas « ÉQ.1 GAGNE » (`ScorePanel.update`).

### 2.4 Sélection d'agent

- **Valorant** : grille d'agents, choix visibles par l'équipe, verrouillage, compte à rebours ; un tutoriel obligatoire précède la première sélection ([Riot — Beginner's Guide](https://playvalorant.com/en-us/news/announcements/beginners-guide/), [Valorant Wiki — Range](https://valorant.fandom.com/wiki/Range)).
- **Chez nous** (`AgentSelectScreen.gd`) : 15 s, grille, aperçu des capacités, verrouillage. Il manque :
  1. les choix des coéquipiers et un indicateur de composition par rôle ;
  2. la présélection du dernier agent joué ;
  3. un aperçu animé de chaque capacité *(hypothèse : clip de 3–5 s)*.

### 2.5 Menu d'achat (vitesse)

- **CS2** a repris une grille façon Valorant, mais garde l'achat en **2 touches** (1–5 pour la catégorie, puis 1–5 pour l'arme), les binds d'achat et l'**achat automatique** d'un loadout préparé hors match. La revente n'est possible que pendant la phase d'achat, tant qu'on n'a pas tiré ([AltChar](https://www.altchar.com/game-news/cs2-changes-buy-menu-to-look-more-like-valorants-a24fE4h5hTvN), [guided.news](https://guided.news/en/guides/counter-strike-2-loadout-buy-menu-weapon-categories-guide/), [critfeed](https://critfeed.com/cs2-buy-menu/)).
- **Cible** *(hypothèse)* : un achat complet en ≤ 2 s et ≤ 3 appuis ; « Racheter le dernier loadout » sur une touche ; grille catégories × armes, prix et coût restant affichés.

### 2.6 Flux des menus et FTUE (5 premières minutes)

- **GAG, niveau basique** ([gameaccessibilityguidelines.com/basic](https://gameaccessibilityguidelines.com/basic/)) : on lance le jeu sans traverser plusieurs niveaux de menus ; tutoriels interactifs ; langage simple ; réglages sauvegardés ; fonctionnalités d'accessibilité expliquées en jeu.
- **Valorant** :
  - Basic Training obligatoire à la première connexion ;
  - match d'entraînement contre bots en option ;
  - modes courts pour débutants : Spike Rush, ≈ 8 min, 4 manches, armes aléatoires, sans économie ([Hotspawn](https://www.hotspawn.com/valorant/guide/valorant-guide-for-beginners), [Riot](https://playvalorant.com/en-us/news/announcements/beginners-guide/)).
- **Première session proposée** *(hypothèse, à valider au playtest P5)* :
  1. écran de bienvenue : langue, luminosité, sensibilité avec la conversion depuis un autre jeu, couleur ennemie ;
  2. tutoriel de mouvement, ≤ 3 min (existe, P5.1) ;
  3. Arène TDM contre bots RECRUE, 5 min ;
  4. écran de fin qui propose « Jouer en ligne » ou « Stand de tir ».

### 2.7 Réglages qu'un shooter PC doit avoir

- **Sensibilité** : le cm/360 est l'unité portable ; il faut un multiplicateur ADS séparé et un FOV identique pour garder la mémoire musculaire ([Aimlabs — PC Sensitivity Guide](https://support.aimlabs.com/hc/en-us/articles/38493112353815-PC-Sensitivity-Guide), [Ubisoft R6 — FOV and Input Sensitivity](https://www.ubisoft.com/en-au/game/rainbow-six/siege/news-updates/6kY6b5JByBY3P6vQWWinla/fov-and-input-sensitivity)). Proposer « Importer depuis Valorant/CS2/Overwatch » : convertisseur fondé sur le cm/360.
- **FOV** : Valorant est figé à 103° horizontal en 16:9 (70,53° vertical) ; Overwatch 2 plafonne à 103° h ; Apex propose 70–110 dans sa propre notation ([fovcalculatorpro](https://fovcalculatorpro.com/blogs/best-fov-settings-cs2-valorant-apex/), [Esports Tales](https://www.esportstales.com/overwatch/the-best-fov-field-of-view)). Godot : `Camera3D.fov` est vertical par défaut (`keep_aspect = KEEP_HEIGHT`) ([Godot — Camera3D](https://docs.godotengine.org/en/stable/classes/class_camera3d.html)).
- **Affichage** : Godot recommande `canvas_items` + `expand` avec une base 1920×1080 (déjà fait dans `project.godot`) et d'**exposer l'échelle de rendu 3D** séparément de l'UI ([Godot — Multiple resolutions](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html)).
- **Liste minimale** *(synthèse GAG + standards du genre)* :
  - **Contrôles** : sensibilité souris, sensibilité ADS, sensibilité manette, inversion Y, zones mortes, remappage, maintien ou bascule (accroupi, ADS, marche).
  - **Vue** : FOV (horizontal), secousses de caméra, balancement de tête, effets de FOV dynamique.
  - **Affichage** : mode fenêtre, échelle de rendu, vsync, limite d'images, préréglages graphiques, luminosité.
  - **Audio** : volumes principal/effets/musique/voix/UI/ambiance, audio mono.
  - **Accessibilité** : sous-titres, indices visuels des sons, couleur ennemie, taille de l'UI, mouvement réduit.
  - **Divers** : afficher FPS et réseau ; réinitialiser par page.

### 2.8 Accessibilité (GAG, XAG) et manette

- **GAG basique** ([source](https://gameaccessibilityguidelines.com/basic/)) :
  - **Moteur** : remappage, sensibilité réglable, contrôles simples, UI utilisable avec le même périphérique que le jeu, grandes cibles espacées.
  - **Vision** : contraste élevé, taille de police lisible par défaut, jamais d'information par la couleur seule, FOV par défaut adapté.
  - **Audition** : jamais d'information par le son seul ; volumes séparés effets/voix/musique ; sous-titres lisibles.
  - **Général** : réglages sauvegardés, accessibilité documentée en jeu.
- **XAG 101 — texte** ([Microsoft Learn](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/101)) :
  - **PC : ≥ 18 px à 1080p** (hauteur de corps, descendante à ascendante) ; console : ≥ 26 px à 1080p ;
  - **écrans à forte densité : 18 px à 100 DPI, 36 px à 200 DPI**, puis au prorata ;
  - texte redimensionnable **jusqu'à 200 %** sans perte d'information ;
  - au moins une police sans empattement ; version non stylisée pour les polices décoratives ;
  - blocs de texte : ≤ 80 caractères par ligne, interligne ≥ 1,5 ;
  - texte en casse normale proposé (les libellés de 1–2 mots sont exemptés).
- **Ping contextuel (Apex)** : Respawn a joué un mois micros coupés, sous pseudos aléatoires, pour mettre au point le ping. Un appui marque le point et déclenche une réplique du personnage ; le maintien ouvre une roue (« ennemi ici », « j'y vais ») ([Game Developer](https://www.gamedeveloper.com/design/respawn-played-with-muted-mics-to-get-i-apex-legends-i-smart-comms-system-just-right), [How-To Geek](https://www.howtogeek.com/how-one-battle-royale-shooter-overhauled-communication-in-online-games/)). EA a ouvert les brevets du ping ([Digital Thriving Playbook](https://digitalthrivingplaybook.org/example/overview-of-collaborative-ping-systems/)).

### 2.9 Direction visuelle (Persona 5, Splatoon 3, Borderlands 3, Hi-Fi Rush)

- **Persona 5** : Masayoshi Sutou a surtout travaillé la couleur de l'interface face à la palette rouge du jeu, et a retenu un texte noir et blanc. Les mots sont alignés sur une oblique pour guider l'œil, avec un contour épais pour le contraste. Chaque entrée de menu est animée, et les données d'UI restent en mémoire résidente pour s'afficher **sans latence** ([Persona Central — interview](https://personacentral.com/persona-5-interview-ui-design-sound-music/), [Medium — Menus with personality and readability](https://medium.com/@fruitcupkun/persona-5-menus-with-personality-and-readability-d6db2e0b253e)).
- **À retenir pour nous** :
  - les bandeaux rouges au pinceau vont aux **menus et transitions**, jamais au HUD de combat ;
  - chaque transition ≤ 250 ms et interruptible ; rien ne bloque la saisie ;
  - obliques et contraste fort, mais une seule oblique par écran *(hypothèse)*.

### 2.10 UI dans Godot 4.x (Theme, conteneurs, ancres, Tweens)

- `canvas_items` + `expand` + base 1920×1080 : déjà en place (`project.godot`). Les ancres gèrent les coins, les conteneurs gèrent les listes ([Godot docs](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html)).
- **Theme** : `resources/ui/ui_theme.tres` est défini globalement, mais la plupart des styles sont posés en code par `Comic.gd`. Les contrôles natifs (HSlider, OptionButton, LineEdit, ScrollContainer) risquent de garder un rendu par défaut. Il faut tout centraliser dans le Theme (types de variation), et garder `Comic.gd` pour les tokens seulement.
- **Juice** : utiliser `create_tween()` avec `set_trans(Tween.TRANS_CUBIC)` et une courbe unique (cubique, 150/200/250/400 ms selon `design.md` §13) ; réduire aux fondus si `Settings.reduced_motion`. Aujourd'hui, seuls 8 appels à `create_tween` existent dans `scripts/ui`.

## 3. Tableaux de métriques

### 3.1 FOV

| Jeu | Horizontal 16:9 | Vertical | Réglable |
|---|---|---|---|
| Valorant | 103° | 70,53° | non |
| Overwatch 2 | ≤ 103° | ≤ 71° | oui |
| **Nous aujourd'hui** | **≈ 121°** (+ sprint 5, slide 9, vitesse 6 : jusqu'à ≈ 136°) | **90°** (+20) | oui (en vertical, sans le dire) |
| **Cible** *(hypothèse)* | **103° par défaut**, curseur 80–120 | converti | oui ; effets dynamiques ≤ +5°, désactivables |

### 3.2 Texte (XAG 101) vs nous

| Contexte | Minimum XAG | Nous | Verdict |
|---|---|---|---|
| PC 1080p | 18 px | 20 px (`Comic.SIZE_FLOOR`), 25 px corps | OK |
| Steam Deck 1280×800, 7″ (≈ 215 DPI) | ≈ 36–39 px physiques | 20 × 0,667 = 13 px | **Trop petit** : échelle d'UI par défaut ≈ 1,5 sur Deck, et le mode « grand texte » à 2,0 |
| Redimensionnement | jusqu'à 200 % | curseur 0,8–1,5 | Étendre à 2,0 |

### 3.3 Menu d'achat

| Mesure | CS2 | Nous | Cible *(hypothèse)* |
|---|---|---|---|
| Appuis pour acheter une arme | 2 (catégorie + arme) | clic ou flèches dans une liste | ≤ 2 |
| Racheter le loadout précédent | autobuy / binds | non | 1 touche |
| Revente | pendant la phase d'achat, avant le premier tir | ? | idem |

### 3.4 Profondeur de menus (clics jusqu'en match)

| Parcours | Nous | Cible *(hypothèse)* |
|---|---|---|
| Lancement → partie contre bots | onglet JOUER → carte mode → carte → « JOUER (héberger) » ≈ 3–4 | 1 (« Jouer » lance le dernier mode, ou Arène vs bots au premier lancement) |
| Lancement → options | 1 | 1 |
| En jeu → options | Échap → Options = 2 | 2 |

## 4. Écarts avec notre jeu

1. **HUD relatif à l'équipe 0** : `scripts/ui/hud/KillfeedPanel.gd` (`killer_team == 0` = allié), `ScorePanel.gd` (score 0 toujours marqué ●, « ÉQ.%d GAGNE »), `ScoreboardPanel.gd`, `EndPanel.gd`, `RoundPanel.gd` (vivants 0 — 1). Faux dès que le joueur local est en équipe 1.
2. **FOV vertical de 90°** : `scripts/core/Settings.gd` (`fov = 90.0`), `scripts/player/PlayerCamera.gd` (`_update_fov`, ajouts sprint/slide/vitesse), `scenes/player/player.tscn` (`fov = 90.0`, pas de `keep_aspect`) ; `docs/MOVEMENT.md` §10 à mettre à jour.
3. **Viseur figé** : `scripts/ui/GameHUD.gd` (`_build_crosshair`).
4. **Pas de minimap ni de nom de zone** : `scripts/ui/GameHUD.gd`, `design.md` §12 (minimap 240 px) jamais implémentée.
5. **Options incomplètes** : `scripts/ui/OptionsMenu.gd` (4 pages) et `scripts/core/Settings.gd`. Manquent : sensibilité ADS, maintien/bascule, affichage (mode, échelle de rendu, vsync, limite d'images, préréglages), volumes voix/UI/ambiance, audio mono, sous-titres, indices visuels des sons, secousses/bob/FOV dynamique, stats réseau, réinitialisation. Échelle d'UI plafonnée à 1,5.
6. **Menu principal de prototype** : `scripts/ui/MainMenu.gd` (`"▶  JOUER (héberger)"`, `_ip_field.text = "127.0.0.1"`, « Rejoindre » au premier niveau).
7. **Menu d'achat lent** : `scripts/ui/BuyMenu.gd` (liste « nom — catégorie · prix », sans touches 1–5 ni rachat).
8. **Sélection d'agent solitaire** : `scripts/ui/AgentSelectScreen.gd` (pas de choix d'équipe visibles, pas de dernier agent présélectionné).
9. **Killfeed pauvre** : ni arme, ni headshot, ni couleur de la victime (`KillfeedPanel.push`).
10. **Pas de ping ni de roue de communication** : rien dans `scripts/ui/` ni `scripts/player/`.
11. **Pas de premier lancement guidé** : le tutoriel de mouvement existe (`scripts/training/MovementTutorial.gd`), mais rien ne l'impose ni ne l'enchaîne.
12. **Styles en code plutôt qu'en Theme** : `scripts/ui/Comic.gd` et `resources/ui/ui_theme.tres`, d'où un risque de contrôles natifs non stylés (sliders, listes).

## 5. Tâches

```
- id: UX-01
  title: HUD relatif au joueur local (allié/ennemi calculés depuis l'équipe locale) + killfeed enrichi (arme/capacité, headshot, couleur de la victime) + VICTOIRE/DÉFAITE
  files: [scripts/ui/Comic.gd, scripts/ui/hud/KillfeedPanel.gd, scripts/ui/hud/ScorePanel.gd, scripts/ui/hud/ScoreboardPanel.gd, scripts/ui/hud/EndPanel.gd, scripts/ui/hud/RoundPanel.gd, scripts/ui/GameHUD.gd, tests/ui/test_team_relative.gd]
  depends_on: []
  size: M
  acceptance: fonction pure `Comic.is_ally(team, local_team)` testée ; avec un joueur local en équipe 1, le killfeed colore en ALLY les kills de l'équipe 1, le score affiche ● à gauche pour l'équipe 1, la page de fin affiche « VICTOIRE » si l'équipe 1 gagne ; une entrée de killfeed contient l'icône de l'arme (ou de la capacité) et ✦ en cas de headshot ; captures `tests/ui/capture_shots.gd` régénérées pour les deux équipes.
- id: UX-02
  title: FOV exprimé en horizontal 16:9 (défaut 103°, curseur 80–120), converti en vertical pour Camera3D ; effets de FOV dynamique plafonnés à +5° et désactivables
  files: [scripts/core/Settings.gd, scripts/player/PlayerCamera.gd, scripts/ui/OptionsMenu.gd, scenes/player/player.tscn, docs/MOVEMENT.md, tests/player/test_fov.gd]
  depends_on: []
  size: S
  acceptance: fonction pure `hfov_to_vfov(103, 16/9)` = 70,5 ± 0,1 ; au lancement la Camera3D a fov ≈ 70,5 (KEEP_HEIGHT) ; sprint + slide + vitesse max n'ajoutent pas plus de 5° ; l'option « Effets de FOV » à off les supprime ; les anciens réglages sauvegardés (90 vertical) sont migrés vers 103 horizontal.
- id: UX-03
  title: Éditeur de viseur (couleur, contour, point central, lignes intérieures/extérieures, écart, opacité) avec aperçu et code importable/exportable
  files: [scripts/ui/hud/Crosshair.gd, scripts/ui/CrosshairEditor.gd, scripts/core/Settings.gd, scripts/ui/OptionsMenu.gd, scripts/ui/GameHUD.gd, tests/ui/test_crosshair_code.gd]
  depends_on: []
  size: M
  acceptance: Crosshair.gd dessine via `_draw()` à partir d'un dictionnaire de réglages ; `encode()`/`decode()` font l'aller-retour sans perte (test) ; 4 préréglages (Défaut, Point, Croix fine, Croix épaisse) ; l'aperçu change en temps réel sur un fond ciel + un fond sable ; persistant dans `user://settings.cfg`.
- id: UX-04
  title: Minimap (240 px à 1080p) dessinée depuis Layouts + nom de la zone courante sous la minimap
  files: [scripts/ui/hud/Minimap.gd, scripts/ui/hud/LocationLabel.gd, scripts/ui/GameHUD.gd, tests/ui/test_minimap.gd]
  depends_on: [LD-04]
  size: L
  acceptance: la minimap rend les empreintes des pièces Layouts (sol, murs, couverts) en top-down, oriente le joueur, montre les alliés (●) et les ennemis révélés (▼) seulement ; ennemis non révélés jamais affichés (le serveur n'envoie rien de plus) ; nom de zone mis à jour ≤ 250 ms après le changement ; ≤ 0,3 ms CPU par image au benchmark.
- id: UX-05
  title: Menu d'achat rapide — grille catégories × armes, touches 1–5 puis 1–5, « Racheter » (R), revente avant le premier tir
  files: [scripts/ui/BuyMenu.gd, tests/ui/test_buy_menu.gd]
  depends_on: []
  size: M
  acceptance: en R&D, B → 3 → 2 achète la 2e arme de la 3e catégorie ; R rachète le loadout de la manche précédente si les crédits suffisent, sinon ⚠ + raison ; toute la navigation marche à la manette ; test scene-runner : achat complet en ≤ 3 événements d'entrée.
- id: UX-06
  title: Options complètes — Affichage (mode fenêtre, échelle de rendu 50–100 %, vsync, limite d'images 60/144/240/illimitée, préréglage graphique dont Steam Deck), sensibilité ADS, maintien/bascule (accroupi, ADS, marche), secousses et head-bob, volumes voix/UI/ambiance, audio mono, afficher FPS/réseau, réinitialiser la page
  files: [scripts/core/Settings.gd, scripts/ui/OptionsMenu.gd, scripts/player/PlayerCamera.gd, scripts/core/Audio.gd, tests/core/test_settings.gd]
  depends_on: [UX-02]
  size: L
  acceptance: chaque réglage est persisté puis relu (test aller-retour de Settings) et appliqué sans redémarrage ; la limite d'images est visible dans PerfOverlay ; audio mono = canal gauche = droit (test de bus) ; « Réinitialiser » remet les valeurs par défaut de la page seulement ; toutes les pages sont navigables au clavier et à la manette avec un focus visible.
- id: UX-07
  title: Accessibilité — sous-titres et indices visuels des sons (pas, capacités ennemies, bombe), échelle d'UI jusqu'à 2,0, défaut 1,5 sur Steam Deck
  files: [scripts/ui/hud/SoundCues.gd, scripts/ui/hud/Subtitles.gd, scripts/core/Settings.gd, scripts/ui/OptionsMenu.gd, scripts/ui/GameHUD.gd, scripts/core/Audio.gd]
  depends_on: [UX-06]
  size: M
  acceptance: option « Indices visuels des sons » : un arc directionnel s'affiche pour les pas ennemis à ≤ 15 m et pour chaque capacité ennemie audible, en respectant la zone centrale ; sous-titres de 25 px minimum à 1080p sur un fond à 80 % ; sur Steam Deck (détection 1280×800), l'échelle d'UI vaut 1,5 au premier lancement ; aucun texte ne sort de l'écran à l'échelle 2,0 (captures 1280×800 et 1920×1080).
- id: UX-08
  title: Menu principal en 1 clic — « JOUER » lance la dernière file (ou Arène vs bots au premier lancement) ; héberger/IP déplacés dans « Partie personnalisée »
  files: [scripts/ui/MainMenu.gd, scripts/core/MatchConfig.gd, tests/ui/test_main_menu.gd]
  depends_on: []
  size: M
  acceptance: le bouton principal a le focus au démarrage et lance une partie en 1 activation ; le champ IP et « Rejoindre » n'apparaissent que dans « Partie personnalisée » ; le dernier mode, la dernière carte et la difficulté sont mémorisés ; chaque état (chargement > 1 s, vide, erreur + Réessayer) est présent et capturé.
- id: UX-09
  title: Premier lancement guidé (FTUE) — langue/luminosité/sensibilité (import cm/360 depuis Valorant/CS2/Overwatch)/couleur ennemie → tutoriel de mouvement → TDM vs bots RECRUE → écran « et maintenant ? »
  files: [scripts/ui/FirstRunFlow.gd, scripts/core/Settings.gd, scripts/core/SensitivityConvert.gd, scripts/ui/MainMenu.gd, tests/core/test_sensitivity_convert.gd]
  depends_on: [UX-02, UX-08]
  size: M
  acceptance: le flux ne s'affiche qu'au premier lancement (drapeau dans settings.cfg) et reste passable à tout moment ; la conversion de sensibilité est testée (même cm/360 à FOV égal pour 3 jeux sources) ; un testeur neuf est en match en ≤ 5 min après le lancement (chronométré en playtest).
- id: UX-10
  title: Système de ping contextuel (appui = marque au sol / ennemi / objet ; maintien = roue « ennemi ici », « j'y vais », « défendez », « besoin d'aide ») avec nom de zone
  files: [scripts/player/PingController.gd, scripts/ui/hud/PingMarkers.gd, scripts/ui/hud/PingWheel.gd, scripts/networking/GameWorld.gd, tests/player/test_ping.gd]
  depends_on: [LD-04]
  size: L
  acceptance: le ping est envoyé au serveur, qui le relaie à l'équipe seule (jamais à l'adversaire, testé) ; au plus 3 pings par 5 s et par joueur ; un marqueur affiche icône + distance + zone (« ENNEMI — CALE S-O ») pendant 6 s ; les bots alliés réagissent aux pings « défendez » et « j'y vais » ; utilisable à la manette (roue au stick).
- id: UX-11
  title: Sélection d'agent d'équipe — choix des coéquipiers visibles, composition par rôle, dernier agent présélectionné, aperçu de capacité animé
  files: [scripts/ui/AgentSelectScreen.gd, scripts/networking/GameWorld.gd, scripts/agents/AgentDatabase.gd]
  depends_on: []
  size: M
  acceptance: les choix et verrouillages des coéquipiers s'affichent en ≤ 200 ms (réplication serveur) ; deux coéquipiers ne peuvent pas verrouiller le même agent ; un bandeau indique les rôles manquants (Entrée/Contrôle/Soutien) ; à l'ouverture, le dernier agent joué est survolé ; timer inchangé (15 s).
- id: UX-12
  title: Kit de motion UI (UiFx) et Theme centralisé — transitions ≤ 250 ms cubiques, fondus seuls en mouvement réduit, styles des contrôles natifs dans ui_theme.tres
  files: [scripts/ui/UiFx.gd, resources/ui/ui_theme.tres, scripts/ui/Comic.gd, scripts/ui/MainMenu.gd, scripts/ui/PauseMenu.gd, scripts/ui/OptionsMenu.gd]
  depends_on: []
  size: M
  acceptance: API `UiFx.reveal(node)`, `UiFx.wipe(bar)`, `UiFx.press(button)` utilisées par les menus principaux ; aucune transition ne bloque l'entrée (on peut cliquer pendant l'animation) ; avec `reduced_motion`, seules les opacités s'animent ; HSlider, OptionButton, LineEdit et ScrollContainer ont un style v2 (captures).
```
