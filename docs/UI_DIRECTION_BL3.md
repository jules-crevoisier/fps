# Direction UI v4 — « Encre, jaune, italique » (inspirée de Borderlands 3)

v4.0 · 2026-09-25 · **à valider** · remplace l'UI v2/v3 « charbon + pinceau rouge » (`.orchestrator/design.md`
§11-13), jugée « amateur, illisible, encombrée ». Skills : `redesign-existing-projects` (audit) + `impeccable`.

## 1. Thèse

**Le HUD flotte sur le monde, le menu crie.** En jeu, aucun texte en boîte : il tient par l'encre (contour 3 px +
ombre dure). Hors jeu, peu d'éléments, énormes, en capitales italiques. Un angle (12°) pour les lignes, un coin coupé
(45°) pour les contenants, **une seule couleur qui désigne : le jaune** (« toi, choisi, agis maintenant »).

- **Rejeté :** les panneaux holographiques bleus translucides de l'ECHO : le bleu est notre allié, la translucidité
  sur la 3D recrée le bruit, et ce serait un costume.
- **Pas copié :** logo, icônes, cadres ECHO, polices propriétaires de Gearbox. On garde les principes, pas les assets.

## 2. Ce que BL3 fait vraiment (observé sur captures réelles)

- **HUD sans cadres.** Bouclier (cyan) et vie (rouge) sont deux barres penchées en bas à gauche, avec un gros chiffre
  italique. Les munitions sont en bas à droite : chargeur énorme, réserve petite, pas de barre oblique. La minimap
  est en haut à droite, dans un cadre à coins coupés. Tout le reste est événementiel ([HUD][iig-hud], [HUD 3][iig-hud3]).
- **Menu principal.** Quatre mots en capitales italiques très grasses, alignés à gauche sur la scène 3D, et l'élément
  choisi fait deux fois la taille des autres. Pas de bouton, pas de fond ([menu][iig-menu]).
- **Sélection.** Héros en 3D ; le nom choisi en encre sur un **coup de pinceau jaune**, les autres en blanc
  ([sélection][iig-sel]). En liste, la ligne active est pleine jaune, texte noir, vignette d'icône ([Quick Change][iig-char]).
- **Moments héros et cartes.** Titre de boss géant, rouge, encré, ombre décalée ([boss][iig-enemy]) ; cartes d'objet
  à coins coupés, cadre à la couleur de rareté, gros score ([boutique][iig-store], [rareté][fandom-rarity]).
- **Typo.** Titres lignée **Compacta Bold** ([HipFonts][hipfonts]) ; rôles moteur `HeadFont` / `BodyFont` /
  `NumbersFont` ([config BL2][blcm]) ; texte courant « Willow Body », sans humaniste en casse mixte ([dafont][dafont]).
- **Icônes** monochromes teintées selon l'état ([Kale Menges][menges]) ; HUD itéré en équipe ([processus][bailey]).

## 3. Diagnostic : pourquoi l'UI actuelle fait « amateur » et « encombré »

Captures `reports/checkpoints/2026-09-25_UX-21/*_after.jpg` + `ui_shots.gd` (menu, options, achat, scores, mort, fin).

1. **Des boîtes partout.** 7 rectangles de fonds différents dans le HUD (minimap, VITALITÉ, munitions, score, une par
   ligne du fil) se battent avec le décor. BL3 n'en a aucun.
2. **Six familles de formes sans angle commun.** Hexagones (capacités), rectangles radius 2 (panneaux), onglets penchés
   (achat), bandeaux pinceau déchirés (titres), pastilles rondes (charges), capsule (score). Rien ne rime.
3. **Hiérarchie plate.** Les tailles se tassent (21/26/33) et tout est en SemiBold. La sélection d'agent montre 6 cartes
   × 7 lignes de même corps, puis un paragraphe de 6 lignes sur 1 800 px (~200 caractères par ligne, la norme est 70).
4. **Couleurs sans sens.** Le rouge sert à la fois de marque, de vie basse, de pressé et de titre. La barre de vie et
   les barres de stats sont en **bleu allié**. Le jaune ne sert qu'aux « rôles manquants ».
5. **L'action principale est invisible.** « VERROUILLER » et « Rejouer » sont des barres sombres, pareilles au fond.
6. **Valeurs de debug et bruit.** On voit « 999999 », « 0% », « • • » sous les capacités, « Premier à 50 éliminations »
   en permanence, « [RAVAGE] » entre crochets, « (toi) », et des libellés d'options à ~16 px.
7. **Grille absente.** Cartes d'agent arrêtées à 58 % de la largeur sous une description pleine largeur ; lignes
   d'options de 1 800 px ; HUD visible sous le menu d'achat ; minimap = carré noir vide.

### 4.1 Typographie — une seule famille, Barlow (OFL 1.1), plus Bangers pour les onomatopées

| Rôle (BL3) | Police (fichier) | Licence | Statut | Usage |
|---|---|---|---|---|
| Titre / Head | Barlow Condensed **Black Italic** ([repo][barlow]) | OFL 1.1 | **à ajouter** | titres, menu, noms, VICTOIRE |
| Chiffres / Numbers | Barlow Condensed ExtraBold Italic | OFL 1.1 | présent | vie, munitions, score, minuteur (tabulaires) |
| Bouton / label | Barlow Condensed Bold Italic | OFL 1.1 | présent | boutons, noms de capacités, onglets |
| Méta / légende | Barlow Condensed SemiBold, capitales, +8 à 12 % d'approche | OFL 1.1 | présent | sur-titres, touches, fil |
| Texte / Body | Barlow Semi Condensed Medium, casse mixte, droit | OFL 1.1 | présent | phrases, descriptions |
| Onomatopée | Bangers | OFL 1.1 | présent | mot de kill seulement, 1 à l'écran |

- **Pourquoi Barlow Condensed.** C'est le sosie libre le plus proche de la tête BL3 (lignée Compacta) : grotesque
  condensée aux panses carrées arrondies, avec une **vraie italique** et des chiffres tabulaires.
- **Rejetées :** Anton (plus proche en proportions, mais sans italique ni graisse : l'oblique forcé fait bon marché),
  Sofia Sans Extra Condensed (une 2ᵉ famille).
- **Échelle.** Ratio **1,333** (quarte), base 21 = plancher : **21 · 28 · 37 · 50 · 66 · 88 · 118 · 157** px en
  1080p, × 0,667 en 720p (plancher 14 px).
- **Règles :** 3 tailles par écran au plus, deux tailles voisines sautent un cran ; interlignage 1,05 titre / 1,45
  texte, mesure 45 à 70 caractères ; titres et labels en capitales italiques, phrases en casse mixte droite, chiffres
  toujours italiques ; sur la 3D, contour d'encre 3 px + ombre dure (3, 3), 5 px + (6, 6) dès 88 px.

### 4.2 Couleurs — 5 cœurs + équipes (+ rareté pour les cosmétiques)

| Jeton | Hex | Rôle | Contraste |
|---|---|---|---|
| `ink` | #1A1410 | contours, ombres, texte sur jaune | 15,7:1 avec `paper` |
| `plate` | #1E1A17 | plaques de menu, opaques ou à 88 % | — |
| `paper` | #F4EDE1 | texte principal (`paper_dim` #B3AA9E en secondaire, 7,5:1) | 14,9:1 sur `plate` |
| `signal` | #FFCE1F | **seule couleur qui désigne** : sélection, CTA, focus, objectif, ultime prêt, ta ligne du fil | encre dessus 12,3:1 ; OKLCH h = 90,7° |
| `vital` | #E8392E | vie, dégâts, erreur | 4,2:1 sur `plate` (composant ≥ 3) |
| `ally` / `enemy` | #3B8BFF ● / #FF3DC8 ▼ (option #C8FF1F) | équipes, toujours avec leur glyphe | 5,2 / 5,6:1 |
| rareté (hors match) | #E6E1D6 · #35C2A5 · #5AA9FF · #8E6CFF · #FF8A1F | commun → légendaire | teintes 86/175/252/290/55° |

- **Rareté.** Le vert et le violet de BL3 tombent dans nos bandes réservées (105–145° et 300–355°), d'où la sarcelle et
  le violet à 290°.
- **Règles :** jamais de couleur d'équipe ou d'agent sur un décor ; le rouge n'est plus la marque (c'est le jaune) ;
  les couleurs-clés d'agent n'apparaissent qu'en portrait.

### 4.3 Formes

- **Les lignes penchent** (parallélogramme à 12°, cisaillement 0,2126) : boutons, barres, onglets, tags, tuiles de
  capacité, tuiles d'agent, plaque du minuteur.
- **Les contenants ont des coins coupés** (45°, 16 px, 22 px pour la minimap), en haut à droite et en bas à gauche :
  cartes, panneaux, modales.
- **Pas d'autre forme** (hexagones, pastilles supprimés) ; rayon 0 sauf touches (4 px) ; jamais de plaque dans une plaque.
- **Traits :** `ink` 3 px (plaques, tuiles, texte sur 3D), sélection `signal` 4 à 5 px, titres ≥ 88 px 5 px ; plus
  aucun filet de 1 px.
- **Ombres dures** (encre pleine, flou 0) : (3, 3) petits éléments, (6, 6) plaques et CTA, (8, 8) moments héros.

### 4.4 Espacement

**Grille de 6** conservée (×2/3 = entiers en 720p) : 6 · 12 · 18 · 24 · 36 · 48 · 72 · 96. Marges : HUD 48 (720p 32),
menus 96 (64). Menus sur 12 colonnes de 120 + gouttière 24, alignés à gauche ; rien n'est centré par défaut.

### 4.5 Trame, pinceau, texture : limites strictes

- **Trame** (points de 4 px, pas de 8, 45° ; encre 18 à 45 % ou jaune derrière un héros) : 1 zone par écran (2 en
  mort/fin), jamais sous du texte de moins de 28 px, jamais dans le HUD en jeu.
- **Pinceau jaune :** 1 par écran, derrière l'élément choisi principal (menu, nom d'agent) ; bandeaux rouges supprimés.
  **Rayures de danger** (jaune/encre, 45°) : barres de chargement seulement.

### 4.6 États (tous obligatoires)

- **Repos** `plate` + `paper` · **survol** `plate_hi` #2E2823, languette `signal` 6 px à gauche, +8 px en 150 ms ·
  **choisi** fond `signal`, texte `ink`, ombre (6, 6) · **focus manette** survol + contour `paper` 3 px décalé de 4 px
  (lisible même sur un élément choisi) · **pressé** translation (3, 3), ombre (3, 3), 90 ms.
- **Désactivé** `paper_off` #726A60 + hachures 45° + raison (« Rôle pris par BOT Alizé ») · **chargement** rayures de
  danger, puis « Connexion au serveur… 3 s » après 1 s · **vide** une phrase + une action (« Aucun ami en ligne —
  Inviter ») · **erreur** tag `vital` « ÉCHEC » + code + « Réessayer ».

### 4.7 Mouvement : un coup de poing, puis le silence

- **Entrée :** glissement de 32 px le long de l'axe à 12° + fondu, 220 ms, cubique `(0.215, 0.61, 0.355, 1)`,
  décalage 30 ms, 6 éléments au plus. **Page :** balayage penché jaune puis encre, 280 ms.
- **Claque** (sélection, verrouillage, mot de kill, ultime prêt) : ×1,08 → ×1 et −3° → 0 en 220 ms, back-out 1,2 —
  seule courbe non cubique. **Chiffres :** chargeur ×1,15 → ×1 en 90 ms par tir ; vie perdue en `paper`, 400 ms
  d'attente puis vidange en 300 ms.
- **Mouvement réduit :** fondus de 120 ms seulement ; ni échelle, ni rotation, ni glissement, ni tremblement ; le
  balayage devient un fondu enchaîné, les rayures sont fixes.

## 5. HUD — 1920×1080 et 1280×720 (maquette `bl3_hud.png`)

| Ancre | Élément | 1080p | 720p | Présence |
|---|---|---|---|---|
| haut-gauche | minimap à coins coupés, flèche `signal`, ● alliés, ▼ ennemis repérés, « N » | 240 px | 160 | permanente |
| sous la minimap | nom de zone (21 caps) | 21 | 14 | 3 s au changement de zone |
| haut-centre | ● 23 (66, `ally`) · plaque penchée 7:42 (37) · 19 ▼ (66, `enemy`) | h 52 | h 35 | permanente |
| haut-droite | fil : noms 28, arme 21 sans crochets, sans boîte ; ta ligne sur plaque + languette `signal` | 4 lignes | 3 | 5 s par ligne |
| bas-gauche | croix `vital`, vie 66 italique, barre penchée 330×26, crans à 25 % | 66 | 44 | permanente |
| bas-centre | C · A · E (tuiles penchées 72) + X (88) ; charges = barrettes, recharge = chiffre 37 | 72/88 | 48/59 | permanente |
| bas-droite | chargeur 88, réserve 37 `paper_dim`, nom d'arme 21 | 88 | 59 | permanente |
| (0,61 ; 0,31) | mot de kill Bangers 88 + ▼ victime 28 | 88 | 59 | 700 ms |
| centre 40 % | réticule, marqueurs de touche, dégâts 3D uniquement | — | — | — |

**Règles de désencombrement (bloquantes) :**

1. **Zéro fond derrière le texte du HUD.** La lisibilité vient de l'encre et de l'ombre.
2. **Six ancres fixes, pas une de plus.** Tout le reste disparaît en 3 s au plus.
3. **On supprime ce que la forme dit déjà :** « VITALITÉ », « Premier à 40 » (→ scores), « 0% », « (toi) », slots.
4. **Pas de valeur de debug.** Une réserve infinie s'affiche « ∞ », une charge vide est une barrette creuse.
5. **Le jaune ne sert qu'à l'action immédiate.** Pas plus de trois éléments jaunes simultanés dans le HUD.

## 6. Écrans

- **Menu principal** (`bl3_menu.png`) : scène Wasteland plein cadre, agent choisi debout en 3D à droite (encre 4 px),
  dégradé d'encre à gauche. Pile à x = 120 : l'élément choisi en 118 px encre sur pinceau jaune + résumé en 28, les
  autres en 66 `paper`. Carte à coins coupés en bas à gauche (vignette penchée, « 07 · WASTELAND », description du
  catalogue), plaque joueur en haut à droite, touches en bas à droite. Rien d'autre.
- **Sélection d'agent** (`bl3_agent_select.png`) : héros 3D à gauche sur un éclat de trame jaune. Colonne d'info à
  droite : nom 157 encre sur pinceau, tag de rôle, accroche 28, kit en 5 lignes (tuile 64 + touche + nom 37 + une
  ligne de 28 ; le texte long passe en info-bulle au focus). En bas : 6 tuiles penchées, seule la choisie garde sa
  couleur-clé (autres éteintes à 32 %, prises à 62 % + « PRIS »), CTA jaune « VERROUILLER » 560×104. En-tête : 4 puces
  d'équipe, tag « IL MANQUE : SOUTIEN », minuteur 88.
- **Achat / arsenal :** plein écran opaque, HUD **masqué** ; onglets penchés 1 à 5 ; cartes d'armes à coins coupés
  240×150 (silhouette encre à produire, nom 37, prix 28) ; détail à droite (nom 66, prix en tag `signal` ou barré
  `vital`, 3 barres de stats penchées `paper`, plus de bleu) ; CTA « ACHETER » jaune ; « Gratuit » une seule fois.
- **Tableau des scores :** plaque unique alignée à 240 px ; en-tête mode · carte · « Premier à 40 » et score 118 bleu
  contre magenta ; lignes de 54 px zébrées `plate`/`plate_hi` sans filets (portrait 48, nom, É/M/A tabulaires, score,
  ping) ; ta ligne pleine `signal`, texte encre.
- **Mort :** monde désaturé à 60 % ; « REMBALLÉ » en 157 `vital`, contour 5, ombre (8, 8), −6° (titre de boss) ;
  carte du tueur (portrait, ▼ nom, arme, « Il lui restait 34 PV ») ; barre à rayures « Retour dans 3 s ».
- **Fin :** « VICTOIRE » `signal` sur encre ou « DÉFAITE » `paper` sur `vital` en 157, score 40–27 en 118, carte MVP
  (rendu 3D), « REJOUER » en CTA jaune, « MENU » en plaque.
- **Options :** onglets penchés ; lignes de 60 px sur 1 100 px max (libellé 28, contrôle à 480 px, pas au bord) ;
  curseur à piste penchée `signal`, bascule OUI / NON ; aide de la ligne focalisée à droite (comme BL3).
- **Pause :** la pile du menu principal (66 px) sur le jeu assombri à 70 %, sans cadre.

## 7. Changements de `docs/style/tokens.json`

| Clé | Avant | Après |
|---|---|---|
| `type.ratio` / `type.scale_px_1080` | 1,25 · 21/26/33/41/51/64/80/100/125 | **1,333 · 21/28/37/50/66/88/118/157** |
| `type.fonts.title` / `.number` | ExtraBoldItalic `to_add` / ExtraBold droit | **BlackItalic** `to_add` (OFL) / **ExtraBoldItalic** tabulaire |
| `type.fonts.label` / `.onomatopoeia` | SemiBold / Bangers `to_add` | `button` BoldItalic + `meta` SemiBold +0,10 / Bangers `present` |
| `color.pinceau.brush` (marque) / `color.ui.vital` | #C8242C / — | **`color.ui.signal` #FFCE1F** / **#E8392E** (vie, dégâts, erreur) |
| `color.game.objective` / `color.charbon.rule` | #F2C230 / #3A332D | alias de `signal` / supprimé (plus de filet) |
| `color.rarity` | — | #E6E1D6 / #35C2A5 / #5AA9FF / #8E6CFF / #FF8A1F (hors match) |
| `shape.radius` / `shape.chamfer_px` | panel 2 · sticker 6 / — | tout à **0**, `keycap` 4 / **16** (minimap 22), haut-droit + bas-gauche |
| `shape.stroke` | rule 1 · focus 2 · sticker 3 · diecut 4 | `ink` 3 · `select` 4 · `display` 5 · `focus` 3 (+4 de décalage) |
| `shape.hex` | hud 72 / menu 96 | supprimé → `hud.ability_tile` 72, `ult_tile` 88 (penchées) |
| `shape.brush` | `max_per_screen` 4, `dry_tail` 64 | → `swash` : jaune, `max_per_screen` 1, sélection seulement |
| `shape.halftone` | dot 4 / pitch 8 / 45° / 0,18 | idem + `max_zones` 1 (2 mort/fin), `min_text_px` 28, `hud` false |
| `hud.chip` | fond #14110F à 80 %, h 72 | **supprimé** (zéro boîte) |
| `hud.sizes_px_1080` | ammo 64 · hp 51 · timer 41 · killfeed 26 | ammo 88 (+ réserve 37) · hp 66 · timer 37 (scores 66) · killfeed 28 (arme 21) |
| `hud.killfeed_entries` / `hud.kill_word_pos` | 5 (720p 4) / [0,72 ; 0,38] | 4 (720p 3), `row_ttl_ms` 5000 / [0,61 ; 0,31] |
| `motion` | — | + `slide_px` 32 (axe 12°), `number_punch` 90 ms ×1,15, `hp_chip` 400 + 300 ms |
| `space` | grille 6 | inchangé ; + `menu_margin` 96 / 64, `menu_columns` 12×120 + 24 |

## 8. Maquettes et prompts d'image

`docs/ui_mockups/bl3_{hud,menu,agent_select}.png` (1920×1080, PIL) sur de vraies captures : coin beauté Wasteland,
viewmodel, agents détourés, portraits et icônes du dépôt. Prompts de paintover (anglais) :

1. *HUD* — « 16:9 FPS screenshot, hand-painted cel-shaded western desert town street, thick black ink outlines,
   blue sky. Borderlands-3-inspired HUD with NO background boxes: bottom-left slanted red health bar and huge white
   italic '72' outlined in black; bottom-center four 12°-slanted ability tiles with cream icons, the last one solid
   yellow; bottom-right giant italic ammo '25' with small grey '125'; top-left chamfered minimap; top-center
   '23 | 7:42 | 19' in blue and magenta; short kill feed top-right. Heavy condensed italic sans, hard offset black
   shadows, palette #1A1410 / #F4EDE1 / #FFCE1F / #E8392E. Clean AAA UI, no logos. »
2. *Menu* — « 16:9 game main menu over a painted cel-shaded desert street at golden hour, one stylized hero with
   flame-shaped orange hair standing right, thick ink outlines. Left-aligned stack of huge condensed black-italic
   capitals: 'JOUER' in black on a dry yellow brush swash with a one-line subtitle, then 'AGENTS', 'ARSENAL',
   'OPTIONS', 'QUITTER' in warm white with black outline and hard drop shadow. Dark chamfered map card
   '07 · WASTELAND' bottom-left, slanted player plate top-right, key hints bottom-right. Minimal, no logo. »
3. *Sélection* — « 16:9 hero-shooter character select, dark warm charcoal background. Left: full-body cel-shaded
   young woman with flame hair and red track jacket, thick ink outline, over a yellow halftone comic burst. Right:
   giant black-italic 'VIF' in black on a yellow brush swash, small 'ENTRÉE' tag, five ability rows (slanted dark
   tiles, cream icons, keycaps, bold italic names, one-line descriptions; ultimate tile yellow). Bottom: six slanted
   portrait tiles, only the selected one in full colour with a yellow border; big yellow slanted 'VERROUILLER'. »

## 9. Risques honnêtes

- **Contour d'encre en `Label`** (`outline_size` 3) : il épaissit l'approche ; en 720p, descendre à 2 px, jamais moins.
- **Conflit de jaune :** la couleur-clé de Vanne (#F2B51D) est jaune. Parade : tuiles non choisies éteintes, tuile
  choisie levée et contourée. À vérifier avec Vanne sélectionnée.
- **Viewmodel :** l'arme occupe le tiers droit ; les munitions tiennent par l'encre, jamais par un fond.
- **Police à ajouter :** Barlow Condensed Black Italic (OFL) ; en attendant ExtraBold Italic + `embolden` 0,6.
- **Français long :** « ÉBLOUISSEMENT » en 37 px ≈ 250 px ; tester chaque libellé contre sa colonne.

## Sources

BL3 : [HUD][iig-hud] · [HUD 3][iig-hud3] · [menu][iig-menu] · [sélection][iig-sel] · [Quick Change][iig-char] ·
[boss][iig-enemy] · [boutique][iig-store] · [Game UI DB][gameui] · [rareté][fandom-rarity] · [processus HUD][bailey] ·
[icônes][menges]. Typo : [HipFonts][hipfonts] · [Compacta][compacta] · [GFxUI.INT][blcm] · [dafont][dafont] ·
[Barlow][barlow].

[iig-hud]: https://interfaceingame.com/screenshots/borderlands-3-hud/
[iig-hud3]: https://interfaceingame.com/screenshots/borderlands-3-hud-3/
[iig-menu]: https://interfaceingame.com/screenshots/borderlands-3-main-menu/
[iig-sel]: https://interfaceingame.com/screenshots/borderlands-3-character-selection/
[iig-char]: https://interfaceingame.com/screenshots/borderlands-3-character/
[iig-enemy]: https://interfaceingame.com/screenshots/borderlands-3-enemy/
[iig-store]: https://interfaceingame.com/screenshots/borderlands-3-store/
[fandom-rarity]: https://borderlands.fandom.com/wiki/Rarity
[hipfonts]: https://hipfonts.com/borderlands-font/
[compacta]: https://en.wikipedia.org/wiki/Compacta_(typeface)
[blcm]: https://github.com/BLCM/BLCMods/blob/master/Borderlands%202%20mods/Ugyuu/JPN%20UI%20Font/GFxUI.INT
[dafont]: https://www.dafont.com/forum/read/160731/borderlands-2-interface-font
[menges]: https://icon-ninja.artstation.com/projects/lVbN6o
[bailey]: https://www.artstation.com/artwork/RYxk9D
[gameui]: https://www.gameuidatabase.com/gameData.php?id=2088
[barlow]: https://github.com/jpt/barlow
