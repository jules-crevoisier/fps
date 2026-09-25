# Plan de production des assets IA (Tripo) — hors personnages

> Version 1.0 — 2026-09-24. Statut : **proposition à valider par l'utilisateur**.
> Périmètre : armes, environnement, objets de jeu, objets de capacités, animations. Les personnages sont traités ailleurs (`docs/3D_PIPELINE.md` §7).
> Manifestes exécutables : `tools/ai3d/manifests/wave1.yaml` à `wave4.yaml`, **95 assets**, générés depuis la même source de données que les tableaux du §6 (aucun écart possible entre ce plan et les YAML).
> Lu avant d'écrire : `STYLE_BIBLE.md` (§4.1, §5, §6, §7.9, §9, §11, §12, §14), `style/tokens.json`, `WEAPONS.md`, `AGENTS.md`, `AgentDatabase.gd` et `abilities/*.gd`, `AbilityController.gd`, `MapCatalog.gd`, `.orchestrator/maps-spec-v2.md`, `PropCatalog.gd`, `props/manifest.json`, `layouts/wasteland.gd` et `cargo_ship.gd`, `SnDMode.gd`, `HardpointMode.gd`, `AI_TOOLS.md`, `research/06_ai_3d_pipeline.md`, `3D_PIPELINE.md` §7, **`LORE.md` v1.0**, et la CLI `tripo` 0.5.1 (`docs --llm`, `--topic commands/*`, `batch`, `make`, `anim`, 95 `--dry-run`).
> Références visuelles : `.orchestrator/refs/wasteland_hero.png`, `cargo_ship_hero.png`, et les épingles 08, 18 et 22 lues par la bible §2. Aucune skill de design web n'a servi (périmètre 3D).

## Sommaire

0. Direction
1. Ce que la CLI fait vraiment
2. Chaîne par asset et portes
3. Règles de lisibilité
4. Budgets et texels par classe
5. Crédits
6. Inventaire par catégorie
7. Vague 1
8. Animations
9. Risques
10. Décisions demandées

---

## 0. Direction : « Tripo sculpte, la palette peint »

**Thèse.** L'IA ne livre que la forme. Chaque asset part d'un concept en **blocs de couleur francs, une couleur par pièce**. Ces blocs servent à **découper le maillage en slots**, puis la texture Tripo est jetée. La couleur finale est celle du slot (`tokens.json` → `Cartoon.painted_for_slot`), l'encre vient de la géométrie (biseaux, post-process) et le détail vient des décalques. La collision reste la vérité : le visuel IA épouse la boîte Kit ou la boîte de la capacité, jamais l'inverse.

**Pourquoi c'est la seule voie qui tient à 95 assets :**
- une texture Tripo cuit de l'ombrage et du bruit : elle échoue CHK-08 (albédo sans encre, écart-type de L ≤ 0,04) et ramène exactement la « boue » du diagnostic §0 ;
- une texture unique par prop casse le batch : `PropCatalog.place_many` pose **un** matériau par MultiMesh, et la bible plafonne à 24 matériaux par carte ;
- un seul conteneur généré sert les cinq teintes de quadrant (rouille, ardoise, ocre, sarcelle, os), et un seul tremplin sert d'autres agents en changeant la teinte du slot ;
- la couleur du prompt n'a plus besoin d'être exacte : elle doit seulement **séparer** les pièces. C'est ce que l'image fait bien et ce que la 3D IA rate le plus souvent.

**Rejeté :** garder la texture peinte de Tripo comme le fait la voie personnages (`3D_PIPELINE.md` §7). C'est acceptable sur six héros uniques, mais ruineux sur 95 props qui doivent se lire ensemble, se batcher et passer CHK-08.

**Le suffixe de style imposé** (dans chaque `prompt` et chaque `image_prompt`) :
`stylized painted cel-shaded game asset, chunky bevelled readable shapes, clean solid colour blocks, flat two-tone lighting, bold dark ink outlines implied by clean silhouettes, no text/logos, single object centered on plain background, no base/pedestal unless the object is a base`

**Alignement sur `LORE.md` v1.0** (le document existait à la fin de ce travail ; il reste une proposition) :

| Objet | Avant (bible v3) | Après (LORE v1.0) |
|---|---|---|
| Bombe SnD | charge générique | **« la Mèche »**, charge de braise dont la mèche ne s'éteint pas ; hublot d'éclat, sceaux de plomb |
| Désamorceur | outil générique | **cisailles coupe-mèche** : « couper la mèche » |
| Balise Hardpoint | 4 balises aux coins | **« la Borne »** de l'arpenteur, une seule au centre, jalon fin lisible de loin |
| Emblèmes « REMBALLÉ » | 6 objets 3D | **1 jeton de laiton** qui roule + 6 emblèmes en décalque |
| Murs | plaques rivetées, coin de ring, foin, rideau « FERMÉ » | béton-braise (Vanne), volet de baraque (Choc), levée de roseau (Verrou), « le Barrage » (ultime de Vanne) |
| Tremplins | ressort + plateau | boîte d'allumettes (Vif), perchoir (Guet), radeau de roseaux (Verrou), tous sur **ressort d'étoile** |
| Pièges | clochette-mine, langue-ressort | clochette de bronze fêlé (Choc), glu des dendrobates (Verrou) |
| Projectiles et marqueurs | génériques | allumette-flash (Vif), d20 (Guet), flotteur-mouchard (Roseau) |
| Bastion | modèle dédié | levée de Verrou mise à l'échelle (1,25 ; 1,08 ; 1,125), dans la plage 0,8–1,25 : **0 crédit** |

Toute la vague 3 porte la mention « ne pas lancer avant validation de LORE.md ». Roc et Baume y sont déjà Vanne et Roseau.

---

## 1. Ce que la CLI fait vraiment (tripo-cli 0.5.1)

| Constat | Source | Conséquence dans les manifestes |
|---|---|---|
| La CLI choisit **P1** dès que `face_limit ≤ 20 000` et **retire** `smart_low_poly` | `tripo make … -p smart_low_poly=true --dry-run` → `"P1 does not support smart_low_poly (removed)"` | Le runner force `--model tripo-v3.1` ; les 95 dry-runs le vérifient (modèle `v3.1-20260211`, `smart_low_poly: true`, `face_limit` intact) |
| `quad=true` force une sortie **FBX** | avertissement du dry-run : « quad topology cannot be stored in GLB » | `ai_restyle.py` importe du FBX ; l'export final reste en glTF |
| Bornes `smart_low_poly` : 500–20 000 triangles, 500–10 000 quads | `tripo docs --topic commands/generate` | quad → `face_limit = budget_tris / 2` ; sous 1 200 tris : triangles, `face_limit ≥ 500`, puis décimation Blender au budget |
| `pbr` vaut `true` par défaut et force la texture | idem | `pbr=false` partout (la bible exclut le PBR) |
| `negative_prompt` ≤ 255 caractères, route texte seulement | idem | constante `negative_prompt` en tête de chaque manifeste (223 caractères) |
| `image-to-model` n'accepte **pas** de prompt | idem (paramètres par endpoint) | route `image` = `text-to-image` puis porte de revue, puis `image-to-model` ; le `prompt` sert de provenance et de repli texte |
| `export_orientation` n'est pas hérité par les étapes suivantes | idem, avertissement | aucune orientation ni `auto_size` côté Tripo : tout se règle dans Blender |
| `tripo batch run` attend `jobs: [{input, name, for, then, params}]` et reprend là où il s'est arrêté grâce à `<manifeste>.state.json` | `tripo docs --topic commands/batch` | nos 13 clés sont traduites par un runner (1 entrée → 1 à 3 appels) ; la route texte peut être émise telle quelle en manifeste `tripo batch` |
| **Aucune grille de prix v3.1 dans la CLI.** Seuls chiffres : P2 100–130, smartsegment 55/85, splat 30, et un **exemple** de chaîne à 145 (110 + 30 + 5) | `commands/generate`, `commands/process`, `commands/make` | règle d'estimation et porte de calibration (§5) |
| Codes de sortie stables : 4 crédits, 5 politique de contenu, 6 échec remboursé, 9 débit | `tripo docs --llm` | le runner s'arrête sur 4 et reformule sur 5 (le prompt de la bombe évite « bomb/explosive ») |

---

## 2. Chaîne par asset et portes

```
manifeste waveN.yaml
  │  (runner : --dry-run d'abord, "valid": true exigé)
  ├─ route=text ──────────────► text-to-model v3.1 ────────────────────────────┐
  ├─ route=image ─► text-to-image ─► G1 planche de concepts ─► image-to-model ─┤
  └─ route=multiview ─► text-to-image ─► G1 ─► image-to-multiview ─► multiview ┤
                                                                                ▼
  assets_src/ai_raw/<id>/ (FBX si quad, preview.png, task.json) + provenance.json (A3D-09)
                                                                                │ G2 preview.png relu
                                                                                ▼
  tools/blender/ai_restyle.py (A3D-07) : nettoyage, échelle scale_m, origine au pied,
  quantification Lab texture → slots, texture jetée, pièces séparées (armes, objets de jeu),
  biseau par classe, WEIGHTED_NORMAL, COLOR_0 (AO, arête, hauteur, zone), LOD1/LOD2,
  collisions, marqueurs (Muzzle, Foregrip)
                                                                                │ G3 check_asset.py + turntable
                                                                                ▼
  assets/models/<famille>/<id>.glb + ligne manifest.json ─► G4 prop_shots / fp_shots / map_shots + style_check
```

| Porte | Qui | Critère d'arrêt |
|---|---|---|
| **G1 concepts** | Claude sur la planche, l'utilisateur tranche | silhouette lisible à 64 px (armes) ou 43 px (props), une couleur par pièce, fond uni, aucun texte, aucune teinte des bandes réservées. Un concept refusé coûte ≈ 10 cr ; une 3D refusée en coûte 45 |
| **G2 3D brute** | Claude sur `preview.png` | forme conforme au concept, pas de membrure fondue, pas de socle parasite. Sinon `tripo redo` (nouvelle graine) ; au 2ᵉ échec : multiview |
| **G3 asset** | `check_asset.py` | budget de triangles, COLOR_0 présent, aucune pièce flottante (CHK-16), bbox = `scale_m` ± 2 %, skin dans la plage 0,8–1,25 par axe |
| **G4 en jeu** | `style_check` | CHK-06, 10, 14, 15, 16, 17, 29, 31 et 44 selon la famille (§3) |

**Dépendances.** On peut générer la vague 1 avant que `ai_restyle.py` existe : les sorties brutes restent dans `assets_src/`, hors du jeu. Rien n'entre dans `assets/models/` sans A3D-07 (restyle), ART-20 (stylekit et `check_asset`) et A3D-09 (provenance, licence, section IA de `THIRD_PARTY_LICENSES.md`).

**Tâches à créer dans le backlog** (hors de ce document) : le runner `tools/ai3d/run_wave.py` (traduction CLI, portes, plafond de crédits, reprise) ; la séparation des pièces mobiles des armes dans `ai_restyle.py` ; les branchements `MapSetup`/`Kit` pour les nouveaux skins (auvent + poteaux, socle de grue de pont, `hatch_pile`) ; `SnDMode` (cisailles tenues, mèche qui raccourcit) ; `HardpointMode` (Borne au centre).

---

## 3. Règles de lisibilité appliquées à chaque asset

### 3.1 Hauteurs de couvert

Rappels du gabarit (bible §4.1, CHK-23) : yeux debout à 1,62 m, ligne de headshot à 1,40 m, sommet accroupi ≤ 0,92 m, yeux accroupis entre 0,72 et 0,80 m.

| Classe | Ce qu'elle fait au gabarit | Assets | Règle |
|---|---|---|---|
| **0,9 m** | cache un joueur accroupi ; il ne peut pas tirer par-dessus | `cv_barrel` | couvert bas de repli, jamais sur une lane longue |
| **1,1 m** | accroupi caché ; debout, on tire par-dessus, torse et tête exposés | `cv_crate_low`, `cv_sandbag_wall`, `cs_hatch_pile`, `cv_ember_crate` | le couvert « accroupi » de référence (CHK-15) |
| **1,4 m** | debout, **seule la tête dépasse** : la position « tête seule » | `wl_car_sedan_wreck`, `cs_windlass` | rare et déclarée ; relue en revue de lisibilité |
| **1,8 m** | cache un joueur debout, qui ne voit pas par-dessus | `cv_crate_2`, `cv_crate_stack`, `cv_barrel_cluster`, `wl_car_pickup_wreck` | chapeau et cheveux dans les 1,80 m de la Toise : aucun dépassement |
| **≥ 2,0 m** | mur plein | skins d'épaves, cuves, conteneurs, murs de capacité | dessus horizontal |

**Écart avec la bible à trancher.** CHK-15 n'accepte aujourd'hui que 1,10 ± 0,05 m ou ≥ 2,0 m. Les classes 0,9, 1,4 et 1,8, déjà présentes dans `maps-spec-v2` et donc dans la collision, échoueraient. Proposition : élargir CHK-15 à {0,9 ; 1,1 ; 1,4 ; 1,8 ; ≥ 2,0} ± 0,05, en réservant 1,4 aux positions déclarées. Ce plan ne touche ni à la bible ni aux jetons.

### 3.2 Le visuel épouse la collision

- **Skin sur une boîte Kit** : le visuel reste dans la boîte à ± 5 cm, avec une échelle de 0,8 à 1,25 par axe (§8.15 du spec). Rien ne dépasse au-dessus, et **aucun jour visible sous un couvert plein** (écart ≤ 0,15 m). D'où les prompts « solid down to the ground », les vitres condamnées des épaves, le plateau du pick-up rempli jusqu'au bord et les fûts serrés.
- **Murs de capacité** : ils remplissent la boîte de `WallAbility`/`BastionAbility` (4,0 × 2,6 × 0,4 ; 3,2 × 2,4 × 0,35 ; 7,0 × 3,4 × 0,5), dessus droit et horizontal. L'anneau d'équipe et la bande de 6 cm restent en code ou en décalque (CHK-44).
- **Tremplins** : empreinte ≤ Ø 2,2 m, hauteur visuelle ≤ 0,40 m. Ce ne sont jamais des couverts.
- **Décor au-dessus de 2,2 m** (auvent, enseignes, flèches de grue) : n'entre jamais dans l'espace praticable.

### 3.3 Décor fin, humanoïdes, repères

- **Décor fin** : ≤ 0,15 m d'épaisseur ou ajouré à ≥ 50 % (derrick, grues, antennes, clôtures, Toise, jalon de la Borne). Les membrures IA font ≥ 0,15 m (≥ 0,1 m pour l'antenne TV), sinon elles disparaissent à 60 m ou fondent à la génération.
- **Rien d'humanoïde entre 1,5 et 1,9 m** (CHK-17) : `wl_fuel_pump` (0,8 × 0,6 × 1,6) est pile dans le gabarit, d'où chapeau large, tuyau et tag `ok_not_humanoid` ; `dc_toise` est un cadre ajouré et porte le tag aussi.
- **Repères** : silhouette unique sur le ciel, visibles au-dessus des toits depuis ≥ 70 % de la carte (CHK-14), la couleur la plus saturée de la carte. Le spawn allié ne porte jamais la couleur de l'autre camp : pas de rouge GAS près de FUEL (`wl_tanker_wreck` passe en crème et bleu tôle).

### 3.4 Couleur, encre, texte

- **Bandes réservées** : aucune teinte h ∈ [300°, 355°] ∪ [105°, 145°] avec C > 0,08. Deux verrous : le générateur des manifestes refuse tout mot de couleur à risque dans les prompts (green, purple, violet, magenta, pink, lime, olive, lavender, chartreuse, khaki, leaf), et la quantification ne peut produire que des teintes de slot déjà dans `tokens.json`. Le cactus et les feuilles sont sarcelle (`#5E9A86`, `#2E9C8A`), le d20 indigo `#5157B8` (h ≈ 275°).
- **Chroma** : props ≤ 0,18, repères ≤ 0,20, une seule couleur saturée par objet. La rouille est un décalque, pas une deuxième couleur.
- **Ni encre ni texte dans la géométrie ou l'albédo.** FUEL, GAS, « 07 », « GRAINES », HÔTEL, « Au Premier Jeton », le damier de la Commission, les chevrons de l'Ardente, les numéros de conteneurs et la frise du Palud sont tous des décalques (atlas 512 px/m). Les panneaux sont générés **vierges**.

### 3.5 Armes

- **L'archétype d'abord** : profil réel lisible à 64 px (CHK-31) ; distinction des trois fusils écrite dans chaque entrée ; évasement du Fracas ≤ ×1,5 (anti-pattern « pompe-trompette »).
- **Pièces mobiles séparées** par une boîte par arme dans `ai_restyle.py`, avec les trous rebouchés : chargeurs, pompe, culasse, barillet, chien, couvercle de trémie. C'est ce qui permet le rechargement « chargeur entièrement hors cadre » (§5.3) avec l'animation procédurale actuelle.
- **Marqueurs** `Muzzle` et `Foregrip`, mêmes noms que les GLB actuels (lus par `ViewModel.gd`). Slots `<id>_body|grip|metal|accent`, qui est la convention actuelle.
- **Deux zones de décalque** à 512 px/m (flanc, chargeur) pour les cosmétiques (LORE §7 : sponsors inventés, Radio-Joute).
- **TP et arme au sol** : décimation Blender du modèle FP vers 1 200–2 000 triangles, parties fines épaissies à ≥ 4 cm, **0 crédit**.
- **Vue FP** : on voit le flanc **gauche** de l'arme. Les concepts sont donc cadrés en trois-quarts gauche, et la trémie de la Semeuse est à gauche.

---

## 4. Budgets et texels par classe

| Classe | Triangles LOD0 | Texels | Biseau | LOD |
|---|---|---|---|---|
| Arme FP | 8 000–12 000 | 512 px/m (décalques) ; TP 128 px/m | 3 mm (TP 1 cm) | TP 1 200–2 000 par décimation |
| Repère | ≤ 15 000 | 256 px/m + décalques 512 px/m | 6–8 cm | 50 % à 60 m |
| Skin ≥ 3 m | ≤ 6 000 | 256 px/m (trim-sheet 1024²) | 6 cm, 2 segments | 50 % à 30 m, 20 % à 60 m |
| Prop moyen 1–3 m | 800–3 000 | 256 px/m | 4 cm conteneur, 2,5 cm caisse | 50 % à 25 m |
| Petit prop < 1 m | 200–800 | 256 px/m | 1,2 cm | coupé à 40 m |
| Décor fin | 500–1 500 | 256 px/m | 1,2 cm | coupé à 45 m (visibility range décor de PropCatalog) |
| Objet de jeu* | 1 200–3 000 | 512 px/m | 5 mm | — (vu de près) |
| Objet de capacité* | 400–5 000 | 256 px/m | 2,5 cm | 50 % à 25 m |

`face_limit` suit une seule règle : à partir de 1 200 triangles de budget, quad avec `face_limit` = budget / 2 ; en dessous, triangles avec `face_limit` ≥ 500 (plancher de `smart_low_poly`), puis décimation Blender au budget.

\* Deux classes sont **proposées** par ce plan, faute d'entrée dans la bible §6.6 :
- **objet de jeu**, vu à 1 m pendant la pose ou la coupe de la Mèche ;
- **objet de capacité**, vu de 2 à 30 m.

---

## 5. Crédits : règle d'estimation, calibration, budgets

**Règle** (appliquée à chaque entrée) :
- **45 cr** par génération 3D : la grille donnée (20 image→3D + 10 smart low-poly + 5 quad + 10 texture HD) ;
- **+10 cr** pour la route `image` (text-to-image ; la recherche 06 donne 5 à 15, la CLI ne dit rien) ;
- **+20 cr** pour la route `multiview` (text-to-image + image-to-multiview, estimation) ;
- **+15 % de réserve de relance** par vague.

Nous ne payons **jamais** la texture HD (texture standard, jetée après découpage) : ces 10 cr restent dans l'estimation comme marge.

**Calibration obligatoire.** La CLI ne publie pas de grille v3.1, et son exemple de sortie affiche 110 cr pour un seul `text_to_model`. Le premier job de la vague 1 est donc `gp_bomb`. On lit son `credits_breakdown` : s'il dépasse 1,3 × 55 cr, **on s'arrête** et on réestime avant de lancer les 23 autres. Au pire (×2,5), la vague 1 coûterait ≈ 3 300 cr : c'est la porte qui l'évite.

**Budget par vague :**

| Vague | Contenu | Assets | Estimation | + réserve 15 % |
|---|---|---|---|---|
| 1 | armes FP, repères Wasteland et Cargo Ship, la Mèche (bombe), la Borne (balise de zone) | 24 | 1 320 | 1 518 |
| 2 | désamorceur, kit de couverts communs, props Wasteland et Cargo Ship | 21 | 1 025 | 1 179 |
| 3 | objets de capacités, jeton du Sauf-conduit | 16 | 880 | 1 012 |
| 4 | repères des 6 autres cartes, dressing Wasteland et Cargo Ship | 34 | 1 700 | 1 955 |
| Pilote animation | rig v1.0 + 10 presets (§8.4) | — | 125 | 125 |
| **Total** | | **95** | **5 050** | **5 789** |

≈ 58 $ au total (1 cr = 0,01 $). Chaque vague tient sous 2 000 cr. Le compte Tripo affichait 0 crédit à la connexion (`AI_TOOLS.md`) : la recharge est à faire par l'utilisateur (`tripo topup`), et seul le **plan payant** cède les droits commerciaux (recherche 06).

**Budget par catégorie** (hors réserve) :

| Catégorie | Assets | Crédits |
|---|---|---|
| Armes | 10 | 550 |
| Props Wasteland | 26 | 1 310 |
| Props Cargo Ship | 12 | 590 |
| Props communs, couverts et décor commun | 11 | 505 |
| Objets de jeu | 4 | 220 |
| Objets de capacités | 15 | 825 |
| Autres cartes (P2) | 17 | 925 |
| Pilote animation (§8.4) | — | 125 |

---

## 6. Inventaire par catégorie

Légende : **V** vague, **P** priorité. **Post-traitement** : `SLP` smart low-poly (v3.1 forcé), `+Q` quad (FBX), `fl` valeur de `face_limit` passée à Tripo (quads si `+Q`), `T` texture standard servant de source des slots. **Collision** : « Kit » = la collision appartient à la carte et l'asset n'est qu'un skin ; « code » = la capacité construit sa propre collision. Les `notes` de chaque entrée YAML donnent les slots, les pièces séparées, les décalques et les contrôles.

#### Armes

| id | V | P | Rôle en jeu | Lisibilité | Tris (classe) | Texels | Route | Post-traitement | Collision | cr |
|---|---|---|---|---|---|---|---|---|---|---|
| `wpn_pistolet` | 1 | P0 | Arme de poing gratuite (slot 0) | Profil de pistolet compact carré ; couverture hanche 7–10 % | 8 000 · Arme FP | 512 px/m (décalques) ; TP 128 px/m | image | SLP+Q fl 4 000 · T | aucune | 55 |
| `wpn_magnum` | 1 | P0 | Revolver (slot 1), gros dégâts semi | Barillet ×1,4 lisible de profil ; couverture 7–10 % | 9 000 · Arme FP | 512 px/m (décalques) ; TP 128 px/m | image | SLP+Q fl 4 500 · T | aucune | 55 |
| `wpn_rafale` | 1 | P0 | SMG auto (slot 2) | Chargeur droit long ×1,3 orange ; couverture 11–15 % | 10 000 · Arme FP | 512 px/m (décalques) ; TP 128 px/m | image | SLP+Q fl 5 000 · T | aucune | 55 |
| `wpn_marqueur` | 1 | P0 | Fusil semi précis (slot 3) | Viseur-feutre haut + crosse bois pleine (≠ Ravage/Percuteur) | 10 000 · Arme FP | 512 px/m (décalques) ; TP 128 px/m | image | SLP+Q fl 5 000 · T | aucune | 55 |
| `wpn_ravage` | 1 | P0 | Fusil d'assaut « héros » (slot 4) | Chargeur courbe + poignée de transport | 11 000 · Arme FP | 512 px/m (décalques) ; TP 128 px/m | image | SLP+Q fl 5 500 · T | aucune | 55 |
| `wpn_fracas` | 1 | P0 | Fusil à pompe (slot 5), 12 plombs | Reste un pompe : évasement ≤ ×1,5, canon droit | 10 000 · Arme FP | 512 px/m (décalques) ; TP 128 px/m | image | SLP+Q fl 5 000 · T | aucune | 55 |
| `wpn_faucheur` | 1 | P0 | Sniper à verrou (slot 6), lunette | Lunette Ø ×1,5 + levier en crochet de faux | 12 000 · Arme FP | 512 px/m (décalques) ; TP 128 px/m | image | SLP+Q fl 6 000 · T | aucune | 55 |
| `wpn_eclair` | 1 | P0 | SMG très court (slot 7), chargeur supérieur | Chargeur horizontal au-dessus, bouche en bec | 10 000 · Arme FP | 512 px/m (décalques) ; TP 128 px/m | image | SLP+Q fl 5 000 · T | aucune | 55 |
| `wpn_semeuse` | 1 | P0 | Mitrailleuse à bande (slot 8), bipied | Trémie latérale gauche (flanc vu en FP) | 12 000 · Arme FP | 512 px/m (décalques) ; TP 128 px/m | image | SLP+Q fl 6 000 · T | aucune | 55 |
| `wpn_percuteur` | 1 | P0 | Fusil semi lourd (slot 9) | Chien apparent + manchon perforé + chargeur droit court | 11 000 · Arme FP | 512 px/m (décalques) ; TP 128 px/m | image | SLP+Q fl 5 500 · T | aucune | 55 |
| **Sous-total** | | | | | | | | | | **550** |

#### Props Wasteland

| id | V | P | Rôle en jeu | Lisibilité | Tris (classe) | Texels | Route | Post-traitement | Collision | cr |
|---|---|---|---|---|---|---|---|---|---|---|
| `wl_fuel_billboard` | 1 | P0 | Repère du spawn bleu + bouclier de spawn | Plein jusqu'au sol, dessus droit ; FUEL en décalque | 4 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 2 000 · T | Kit (boîte 0,6 × 5 × 3,5) | 55 |
| `wl_canopy_station` | 1 | P0 | Repère FUEL (auvent de la place bleue) | Décor au-dessus de 3,8 m ; poteaux = poteaux Kit | 5 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 2 500 · T | Kit (poteaux + dalle) | 55 |
| `wl_water_tower` | 1 | P0 | Repère ouest (sur le Réservoir) | Silhouette sur le ciel ; ajouré sous la cuve | 8 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 4 000 · T | aucune (décor) | 55 |
| `wl_oil_derrick` | 1 | P0 | Repère rouge, site A (butte) | Treillis ajouré ≥ 50 % ; seuls les pieds couvrent | 12 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 6 000 · T | Kit (4 DerrickLeg) | 55 |
| `wl_crane_lattice` | 1 | P0 | Repère neutre central (grue) | Rien entre y 5,7 et 7,8 au-dessus du deck | 15 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 7 500 · T | Kit (mât + CraneDeck) | 55 |
| `wl_gas_billboard` | 1 | P0 | Repère du spawn rouge (toit du GasOffice) | Au-dessus de 3,2 m ; GAS en décalque | 3 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 1 500 · T | aucune (décor de toit) | 55 |
| `wl_tank_horizontal` | 1 | P0 | Repère rouge « réservoirs » + couvert debout | Plein jusqu'au sol (écart ≤ 0,15 m) | 3 000 · Skin ≥ 3 m | 256 px/m (trim-sheet 1024²) | image | SLP+Q fl 1 500 · T | Kit (boîte 3 × 3,5 × 5) | 55 |
| `wl_fuel_pump` | 2 | P1 | Couvert sous l'auvent FUEL | Gabarit humanoïde CHK-17 : tête large + tag | 1 500 · Prop moyen 1–3 m | 256 px/m | image | SLP+Q fl 750 · T | boîte 0,8 × 1,6 × 0,6 | 55 |
| `wl_car_sedan_wreck` | 2 | P1 | Couvert « Épaves » (CarSedan, CarBlue) | Classe 1,4 : seule la tête dépasse ; vitres pleines | 2 500 · Prop moyen 1–3 m | 256 px/m | image | SLP+Q fl 1 250 · T | Kit (1,9 × 1,4 × 4,4) | 55 |
| `wl_car_pickup_wreck` | 2 | P1 | Couvert « Épaves » (CarPickup) | Plateau rempli jusqu'au bord | 3 000 · Prop moyen 1–3 m | 256 px/m | multiview | SLP+Q fl 1 500 · T | Kit (5,2 × 1,8 × 2,1) | 65 |
| `wl_bus_wreck` | 2 | P1 | Couvert debout, lane nord | Vitres condamnées ; couvert ≥ 2,0 | 4 000 · Skin ≥ 3 m | 256 px/m (trim-sheet 1024²) | multiview | SLP+Q fl 2 000 · T | Kit (3 × 3 × 9) | 65 |
| `wl_tanker_wreck` | 2 | P1 | Couvert côté bleu (place FUEL) | Pas de rouge GAS près du spawn bleu | 3 500 · Skin ≥ 3 m | 256 px/m (trim-sheet 1024²) | image | SLP+Q fl 1 750 · T | Kit (8 × 3 × 2,5) | 55 |
| `wl_tank_skid` | 2 | P1 | Couvert, ferme de cuves GAS | Plein jusqu'au sol | 2 500 · Skin ≥ 3 m | 256 px/m (trim-sheet 1024²) | text | SLP+Q fl 1 250 · T | Kit (2 × 3,5 × 4) | 45 |
| `wl_pipe_manifold` | 2 | P1 | Couvert, ferme de cuves GAS | Bloc dense : jours ≤ 0,1 m | 3 000 · Skin ≥ 3 m | 256 px/m (trim-sheet 1024²) | text | SLP+Q fl 1 500 · T | Kit (3 × 3,5 × 4) | 45 |
| `wl_shack_awning` | 4 | P2 | Auvents de portes | Posé à y 2,6, ≤ 0,3 m de relief | 1 200 · Prop moyen 1–3 m | 256 px/m | text | SLP+Q fl 600 · T | aucune (décor ≥ 2,6 m) | 45 |
| `wl_corrugated_shed` | 4 | P2 | Bardage de l'entrepôt | ≤ 0,1 m de relief sur le mur Kit | 1 500 · Prop moyen 1–3 m | 256 px/m | text | SLP+Q fl 750 · T | Kit (bardage) | 45 |
| `wl_power_pole` | 4 | P2 | Poteaux électriques (lignes de rue) | Décor fin ≤ 0,4 m | 1 200 · Décor fin | 256 px/m | text | SLP+Q fl 600 · T | aucune (décor fin) | 45 |
| `wl_junk_pile` | 4 | P2 | Fouillis de rue | Pièces de 10–40 cm, jamais des miettes | 700 · Petit prop < 1 m | 256 px/m | text | SLP fl 700 · T | aucune | 45 |
| `wl_scrap_sheets` | 4 | P2 | Tôles appuyées au mur | Décor fin | 500 · Petit prop < 1 m | 256 px/m | text | SLP fl 500 · T | aucune | 45 |
| `wl_cable_spool` | 4 | P2 | Dressing chantier | Petit prop | 800 · Petit prop < 1 m | 256 px/m | text | SLP fl 800 · T | aucune | 45 |
| `wl_street_lamp` | 4 | P2 | Lampadaires | Fût ≤ 0,15 m | 700 · Décor fin | 256 px/m | text | SLP fl 700 · T | aucune (décor fin) | 45 |
| `wl_cactus` | 4 | P2 | Dressing désert | Teinte sarcelle, jamais vert feuille | 800 · Petit prop < 1 m | 256 px/m | text | SLP fl 800 · T | aucune | 45 |
| `wl_fence_wood` | 4 | P2 | Clôtures | Ajouré ≥ 50 % | 500 · Décor fin | 256 px/m | text | SLP fl 500 · T | aucune (décor fin) | 45 |
| `wl_fence_broken` | 4 | P2 | Clôtures cassées | Ajouré ≥ 50 % | 500 · Décor fin | 256 px/m | text | SLP fl 500 · T | aucune (décor fin) | 45 |
| `wl_tyre_ground` | 4 | P2 | Pneu au sol | Petit prop | 500 · Petit prop < 1 m | 256 px/m | text | SLP fl 500 | aucune | 45 |
| `wl_bottle_crates` | 4 | P2 | Dressing bar | Petit prop | 700 · Petit prop < 1 m | 256 px/m | text | SLP fl 700 · T | aucune | 45 |
| **Sous-total** | | | | | | | | | | **1 310** |

#### Props Cargo Ship

| id | V | P | Rôle en jeu | Lisibilité | Tris (classe) | Texels | Route | Post-traitement | Collision | cr |
|---|---|---|---|---|---|---|---|---|---|---|
| `cs_ship_mast` | 1 | P0 | Repère passerelle + mât de proue (2 instances) | Emprise ≤ 1 × 1 m sur le toit praticable | 5 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 2 500 · T | aucune (décor) | 55 |
| `cs_deck_crane` | 1 | P0 | Repère « grues de pont » (socles + grue de quai) | Fût = socle Kit ; cabine et flèche au-dessus de 3 m | 8 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 4 000 · T | Kit (socle 2 × 5,6 × 3,5) | 55 |
| `cs_lifeboat_davits` | 1 | P0 | Repère « passerelle blanche » (canots) | Hors espace praticable | 4 000 · Prop moyen 1–3 m | 256 px/m | image | SLP+Q fl 2 000 · T | aucune (décor) | 55 |
| `cs_container_40` | 1 | P0 | Boucliers rayés, îlots, piles (repère + masse visuelle) | Ondulations en géométrie ; une couleur par conteneur | 3 000 · Prop moyen 1–3 m | 256 px/m | image | SLP+Q fl 1 500 · T | Kit (2,44 × 2,6 × 12,2) | 55 |
| `cs_container_20` | 1 | P0 | Coins, ancres, piles de poupe | Idem 40 ft | 2 500 · Prop moyen 1–3 m | 256 px/m | image | SLP+Q fl 1 250 · T | Kit (2,44 × 2,6 × 6,1) | 55 |
| `cs_container_open20` | 2 | P1 | Variante ouverte (container_20_open) | Portes ouvertes = décor | 2 500 · Prop moyen 1–3 m | 256 px/m | text | SLP+Q fl 1 250 · T | Kit (skin) | 45 |
| `cs_hatch_cover` | 2 | P1 | Couvert debout (HatchAft/Fore) | Couvert ≥ 2,0 ; dessus clair | 2 500 · Prop moyen 1–3 m | 256 px/m | text | SLP+Q fl 1 250 · T | Kit (4 × 2,5 × 3) | 45 |
| `cs_hatch_pile` | 2 | P1 | Couvert accroupi (HatchPile) | Classe 1,1 | 2 000 · Prop moyen 1–3 m | 256 px/m | text | SLP+Q fl 1 000 · T | Kit (4 × 1,2 × 1,6) | 45 |
| `cs_windlass` | 2 | P1 | Couvert au gaillard (Windlass) | Classe 1,4 : debout, tête seule exposée | 2 500 · Prop moyen 1–3 m | 256 px/m | text | SLP+Q fl 1 250 · T | Kit (2,5 × 1,4 × 2,5) | 45 |
| `cs_bollard` | 4 | P2 | Bittes d'amarrage | ≤ 0,7 m | 600 · Petit prop < 1 m | 256 px/m | text | SLP fl 600 · T | aucune (décor fin) | 45 |
| `cs_gangway` | 4 | P2 | Échelle de coupée (décor extérieur) | Hors espace praticable | 1 500 · Prop moyen 1–3 m | 256 px/m | text | SLP+Q fl 750 · T | aucune (hors bord) | 45 |
| `cs_life_ring` | 4 | P2 | Bouée (dressing) | Petit prop | 500 · Petit prop < 1 m | 256 px/m | text | SLP fl 500 · T | aucune | 45 |
| **Sous-total** | | | | | | | | | | **590** |

#### Props communs, couverts et décor commun

| id | V | P | Rôle en jeu | Lisibilité | Tris (classe) | Texels | Route | Post-traitement | Collision | cr |
|---|---|---|---|---|---|---|---|---|---|---|
| `cv_crate_2` | 2 | P1 | Couvert debout (toutes cartes, alias crate_2) | Classe 1,8 : cache un joueur debout | 1 500 · Prop moyen 1–3 m | 256 px/m | text | SLP+Q fl 750 · T | boîte 2 × 1,8 × 2 | 45 |
| `cv_crate_low` | 2 | P1 | Couvert accroupi (toutes cartes) | Classe 1,1 : accroupi caché, debout tire au-dessus | 1 200 · Prop moyen 1–3 m | 256 px/m | text | SLP+Q fl 600 · T | boîte 2 × 1,1 × 2 | 45 |
| `cv_crate_stack` | 2 | P1 | Couvert debout étroit (chicanes) | Classe 1,8 ; aucun jour entre caisses | 1 500 · Prop moyen 1–3 m | 256 px/m | text | SLP+Q fl 750 · T | boîte 1,5 × 1,8 × 1,5 | 45 |
| `cv_barrel` | 2 | P1 | Fût isolé (couvert bas, dressing) | Classe 0,9 : cache un accroupi, sans tir | 800 · Petit prop < 1 m | 256 px/m | text | SLP fl 800 · T | cylindre/boîte 0,6 × 0,9 | 45 |
| `cv_barrel_cluster` | 2 | P1 | Couvert debout (Drums, CourtDrums…) | Jours entre fûts ≤ 0,1 m | 2 500 · Prop moyen 1–3 m | 256 px/m | text | SLP+Q fl 1 250 · T | boîte 2,4 × 1,8 × 1,2 | 45 |
| `cv_pallet_stack` | 2 | P1 | Couvert debout (Port-Ferraille) | Bloc plein, dessus plat | 3 000 · Prop moyen 1–3 m | 256 px/m | text | SLP+Q fl 1 500 · T | boîte 3 × 2,4 × 5 | 45 |
| `cv_sandbag_wall` | 2 | P1 | Couvert accroupi (Col du Vautour) | Classe 1,1 ; dessus horizontal | 1 500 · Prop moyen 1–3 m | 256 px/m | text | SLP+Q fl 750 | boîte 3 × 1,1 × 1 | 45 |
| `cv_tyre_stack` | 2 | P1 | Dressing ; couvert de coin à La Fosse | Hauteur à trancher : spec 1,0 / manifeste 1,20 | 800 · Petit prop < 1 m | 256 px/m | text | SLP fl 800 | boîte 0,9 × 1,0 × 0,9 | 45 |
| `cv_rock_cluster` | 2 | P1 | Skin de roches (murets, Log) | Échelle 0,8–1,25 par axe | 1 500 · Prop moyen 1–3 m | 256 px/m | text | SLP+Q fl 750 | Kit (skin) | 45 |
| `dc_toise` | 4 | P2 | La Toise de la Commission au point d'apparition | Cadre ajouré : tag ok_not_humanoid | 1 500 · Décor fin | 256 px/m | image | SLP+Q fl 750 · T | aucune (décor fin) | 55 |
| `cv_ember_crate` | 4 | P2 | Caisse d'éclats scellée au plomb (Port-Ferraille, cales) | Couvert 1,1 | 1 200 · Prop moyen 1–3 m | 256 px/m | text | SLP+Q fl 600 · T | boîte 1,2 × 1,1 × 1,2 | 45 |
| **Sous-total** | | | | | | | | | | **505** |

#### Objets de jeu

| id | V | P | Rôle en jeu | Lisibilité | Tris (classe) | Texels | Route | Post-traitement | Collision | cr |
|---|---|---|---|---|---|---|---|---|---|---|
| `gp_bomb` | 1 | P0 | « La Mèche » du Litige (SnD) : portée, posée, coupée | Lisible à 30 m posée ; vue à 1 m au désamorçage | 3 000 · Objet de jeu* | 512 px/m | image | SLP+Q fl 1 500 · T | boîte 0,45 × 0,3 × 0,3 (ramassage) | 55 |
| `gp_borne` | 1 | P0 | « La Borne » (Hardpoint) : une au centre de la zone | Jalon ≤ 0,1 m : ne coupe aucune ligne de vue | 1 200 · Objet de jeu* | 512 px/m | image | SLP+Q fl 600 · T | aucune (se déplace) | 55 |
| `gp_defuser` | 2 | P1 | Cisailles « coupe-mèche » tenues pendant le désamorçage (7 s) | Lisible en FP et en TP | 2 000 · Objet de jeu* | 512 px/m | image | SLP+Q fl 1 000 · T | aucune | 55 |
| `gp_jeton` | 3 | P1 | Jeton qui saute et roule à l'élimination | Lisible à 20 m : bord émissif + VFX | 800 · Objet de jeu* | 512 px/m | image | SLP fl 800 · T | code (cylindre) | 55 |
| **Sous-total** | | | | | | | | | | **220** |

#### Objets de capacités

| id | V | P | Rôle en jeu | Lisibilité | Tris (classe) | Texels | Route | Post-traitement | Collision | cr |
|---|---|---|---|---|---|---|---|---|---|---|
| `ab_vanne_wall` | 3 | P1 | Mur (Vanne, ex-Roc) : batardeau de béton-braise | Remplit la boîte ±5 cm, dessus horizontal | 3 000 · Objet de capacité* | 256 px/m | image | SLP+Q fl 1 500 · T | code (boîte 4,0 × 2,6 × 0,4) | 55 |
| `ab_vanne_barrage` | 3 | P1 | Forteresse, dite « le Barrage » (ultime de Vanne) | Ferme un couloir, sans jour | 5 000 · Objet de capacité* | 256 px/m | image | SLP+Q fl 2 500 · T | code (boîte 7,0 × 3,4 × 0,5) | 55 |
| `ab_choc_shutter` | 3 | P1 | Mur d'assaut (Choc) : volet de sa baraque de boxe | Pose en slap 220 ms, dessus horizontal | 2 500 · Objet de capacité* | 256 px/m | image | SLP+Q fl 1 250 · T | code (boîte 3,2 × 2,4 × 0,35) | 55 |
| `ab_verrou_levee` | 3 | P1 | Rempart (Verrou) ; Bastion par mise à l'échelle | Idem | 3 000 · Objet de capacité* | 256 px/m | image | SLP+Q fl 1 500 · T | code (boîte 4,0 × 2,6 × 0,4) | 55 |
| `ab_vif_matchbox_pad` | 3 | P1 | Tremplin (Vif) : boîte d'allumettes à ressort | Hauteur ≤ 0,40 m : jamais un couvert | 1 500 · Objet de capacité* | 256 px/m | image | SLP+Q fl 750 · T | code (cylindre Ø 2,2 × 0,6) | 55 |
| `ab_guet_perch_pad` | 3 | P1 | Poste avancé (Guet) : perchoir à ressort | Hauteur ≤ 0,40 m | 1 500 · Objet de capacité* | 256 px/m | image | SLP+Q fl 750 · T | code (cylindre Ø 2,2 × 0,6) | 55 |
| `ab_verrou_raft_pad` | 3 | P1 | Passerelle (Verrou) : radeau de roseaux à ressort | Hauteur ≤ 0,40 m | 1 500 · Objet de capacité* | 256 px/m | image | SLP+Q fl 750 · T | code (cylindre Ø 2,2 × 0,6) | 55 |
| `ab_choc_bell_trap` | 3 | P1 | Piège-choc (Choc) : clochette de bronze fêlé | Invisible aux ennemis, contour allié | 800 · Objet de capacité* | 256 px/m | image | SLP fl 800 · T | code (zone 1,4 × 0,15 × 1,4) | 55 |
| `ab_verrou_glue_trap` | 3 | P1 | Chausse-trape (Verrou) + piège du Bastion : glu | Hauteur ≤ 0,1 m ; invisible aux ennemis | 800 · Objet de capacité* | 256 px/m | image | SLP fl 800 · T | code (zone 1,4 × 0,15 × 1,4) | 55 |
| `ab_vif_flash_match` | 3 | P1 | Éblouissement (Vif) : allumette-flash | Visible 0,4 s avant détonation | 600 · Objet de capacité* | 256 px/m | image | SLP fl 600 · T | aucune (projectile) | 55 |
| `ab_guet_d20` | 3 | P1 | Œil (Guet) : le d20 lancé marque le reveal | La bulle « ! » reste un VFX | 800 · Objet de capacité* | 256 px/m | image | SLP fl 800 · T | code (sphère) | 55 |
| `ab_roseau_float` | 3 | P1 | Voile (Roseau, ex-Baume) : flotteur-mouchard | Éclate en voile de poussière (VFX) | 600 · Objet de capacité* | 256 px/m | image | SLP fl 600 · T | aucune (projectile) | 55 |
| `ab_vanne_canteen` | 3 | P2 | Fumée (Vanne) : gourde où tombe l'éclat | Nuage = VFX cel opaque | 600 · Objet de capacité* | 256 px/m | image | SLP fl 600 · T | aucune | 55 |
| `ab_guet_signal_pot` | 3 | P2 | Rideau (Guet) : pot de signal des Guetteurs | Idem | 600 · Objet de capacité* | 256 px/m | image | SLP fl 600 · T | aucune | 55 |
| `ab_roseau_mist_jar` | 3 | P2 | Brume (Roseau) : bocal de brume du Palud | Idem | 600 · Objet de capacité* | 256 px/m | image | SLP fl 600 · T | aucune | 55 |
| **Sous-total** | | | | | | | | | | **825** |

#### Autres cartes (P2)

| id | V | P | Rôle en jeu | Lisibilité | Tris (classe) | Texels | Route | Post-traitement | Collision | cr |
|---|---|---|---|---|---|---|---|---|---|---|
| `pf_gantry_crane` | 4 | P2 | Repère Port-Ferraille (grue portique) | Jambes = pièces Kit ; treillis ajouré | 15 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 7 500 · T | Kit (jambes) | 55 |
| `pf_lighthouse` | 4 | P2 | Repère Port-Ferraille (phare) | Rayures rouge/papier en géométrie | 8 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 4 000 · T | aucune (décor) | 55 |
| `pf_freight_wagon` | 4 | P2 | Couvert Port-Ferraille (Wagon) | Plein jusqu'au sol (jupe sous caisse) | 3 500 · Skin ≥ 3 m | 256 px/m (trim-sheet 1024²) | text | SLP+Q fl 1 750 · T | Kit (2,8 × 3 × 10) | 45 |
| `vp_belfry` | 4 | P2 | Repère Val-Poussière (clocher blanc) | Silhouette sur le ciel doré | 8 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 4 000 · T | aucune (décor) | 55 |
| `vp_saloon_sign` | 4 | P2 | Repère Val-Poussière (enseigne du saloon) | Au-dessus de 2,6 m ; texte en décalque | 2 500 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 1 250 · T | aucune (décor) | 55 |
| `vp_stagecoach` | 4 | P2 | Couvert Val-Poussière (Stagecoach) | Roues pleines, jupe : pas de jour dessous | 3 500 · Skin ≥ 3 m | 256 px/m (trim-sheet 1024²) | multiview | SLP+Q fl 1 750 · T | Kit (2,6 × 2,8 × 6) | 65 |
| `so_factory_chimney` | 4 | P2 | Repère Saint-Ombre (cheminée rayée) | Rayures en géométrie | 6 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 3 000 · T | aucune (décor) | 55 |
| `so_clock_tower` | 4 | P2 | Repère Saint-Ombre (horloge éclairée) | Cadran vierge, émissif en code | 8 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 4 000 · T | aucune (décor) | 55 |
| `so_morris_column` | 4 | P2 | Couvert Saint-Ombre (colonnes Morris) | Ø ≥ 1,2 m : pas de gabarit humanoïde | 1 500 · Prop moyen 1–3 m | 256 px/m | text | SLP+Q fl 750 · T | Kit (skin) | 45 |
| `cdv_radio_antenna` | 4 | P2 | Repère Col du Vautour (antenne rayée) | Treillis ajouré, membrures ≥ 0,15 m | 8 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 4 000 · T | aucune (décor) | 55 |
| `cdv_cable_car` | 4 | P2 | Repère Col du Vautour (téléphérique jaune) | Suspendu, hors espace praticable | 3 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 1 500 · T | aucune (décor) | 55 |
| `cdv_vulture_statue` | 4 | P2 | Repère Col du Vautour (statue) | Non humanoïde, ≥ 3 m | 6 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 3 000 · T | aucune (décor) | 55 |
| `lf_excavator` | 4 | P2 | Repère La Fosse (pelleteuse jaune) | Chenilles pleines | 6 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 3 000 · T | Kit (skin) | 55 |
| `lf_cable_crane_tower` | 4 | P2 | Repère La Fosse (blondin) | Treillis ajouré | 8 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 4 000 · T | aucune (décor) | 55 |
| `lb_zinc_dome` | 4 | P2 | Repère Le Belvédère (dôme de zinc) | Silhouette sur le ciel d'aube | 6 000 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 3 000 · T | aucune (décor) | 55 |
| `lb_tv_antenna` | 4 | P2 | Repère Le Belvédère (antenne TV) | Décor fin ≤ 0,15 m | 2 500 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 1 250 · T | aucune (décor) | 55 |
| `lb_hotel_sign` | 4 | P2 | Repère Le Belvédère (enseigne HÔTEL éteinte) | Lettres en décalque | 2 500 · Repère | 256 px/m + décalques 512 px/m | image | SLP+Q fl 1 250 · T | aucune (décor) | 55 |
| **Sous-total** | | | | | | | | | | **925** |

#### Hors Tripo (bpy ou texture, 0 crédit)

« Tout en IA » s'arrête là où l'IA dégrade le jeu :

| Élément | Pourquoi pas Tripo |
|---|---|
| deck_railing / ship_railing, balcony_railing, fence_chainlink | Éléments fins répétés et tuilés : l'IA produit du palmé, bpy est exact et aligné sur les bords Kit. |
| stairs_ladder, exterior_stairs, marches Kit | Collision fine (marches) : la géométrie doit coïncider au centimètre avec les pas Kit. |
| wires_catenary, câbles de grue et de téléphérique | Courbes : une courbe bpy biseautée fait mieux et coûte 0. |
| pipe_straight, pipe_elbow, lashing_bar | Modules tuilés dont les extrémités doivent se raccorder exactement. |
| shopfront_* (5 façades Wasteland) | Leurs portes et fenêtres doivent coïncider avec les ouvertures Kit : une façade IA les masquerait. |
| hull_bow / hull_mid / hull_stern | Jamais vues depuis le pont (commentaire de cargo_ship.gd) : 0 valeur joueur. |
| Coulisses d'horizon (mesas, quais, toits) | Silhouettes plates unshaded (§6.3), pas des volumes. |
| Décalques, trim-sheets, terrains | Textures : gen_textures.py / atlas de décalques, pas de la 3D. |
| VFX (bouffées, étoiles, traceurs) | Formes plates découpables (§9.1) : meshes bpy, pas Tripo. |
| Armes TP / au sol (pickups) | Décimation Blender du modèle FP (1 200–2 000 tris), parties fines épaissies à ≥ 4 cm. |

---

## 7. Vague 1 : le lot qui change l'image

**Contenu (24 assets, 1 320 cr + réserve = 1 518 cr ≤ 2 000) :**
- **les 10 armes FP**, dont Éclair, Semeuse et Percuteur, qui n'ont encore aucun GLB ;
- **7 repères de Wasteland** : panneau et auvent FUEL, château d'eau, derrick, grue, panneau GAS, cuves ;
- **5 repères de Cargo Ship** : mât (passerelle et proue), grue de pont, canots, conteneurs 40 et 20 pieds, c'est-à-dire les « boucliers rayés » que `maps-spec-v2` classe parmi les repères ;
- **la Mèche** (bombe SnD) ;
- **la Borne** (balise de zone).

**Ordre d'exécution :**
1. `gp_bomb` seul, **calibration** des crédits (§5).
2. Les 23 concepts restants (`text-to-image`, ≈ 230 cr), puis une **planche unique** relue en porte G1. On refait les concepts refusés ; aucune 3D n'est lancée avant cette porte.
3. La 3D des armes, puis le restyle de **Ravage** seul, bout en bout jusqu'à `fp_shots`. Cela valide la séparation des pièces et le découpage en slots avant les neuf autres.
4. La 3D des repères, puis le restyle et `map_shots` des deux cartes.

**Écarté de la vague 1, et pourquoi :**
- la superstructure de passerelle (`bridge_superstructure`) : le toit est une position de pouvoir praticable, et une superstructure IA l'occuperait ou masquerait les ouvertures Kit. La passerelle reste Kit, et le mât porte le repère ;
- les coques : jamais vues depuis le pont ;
- les couverts génériques : vague 2, parce qu'ils existent déjà en bpy et ne changent pas la lecture d'un repère.

---

## 8. Animations

### 8.1 Ce que couvre le set Quaternius UAL (46 clips, lus dans `vif.glb`)

| Besoin | Clips présents | État |
|---|---|---|
| Locomotion | `Idle_Loop`, `Walk_Loop`, `Walk_Formal_Loop`, `Jog_Fwd_Loop`, `Sprint_Loop`, `Crouch_Idle_Loop`, `Crouch_Fwd_Loop`, `Jump_Start/Loop/Land`, `Roll`, `Roll_RM`, `Swim_*` | couvert en avant ; **aucun pas latéral ni marche arrière** dédiés |
| Tir en vue TP | `Pistol_Idle_Loop`, `Pistol_Aim_Down/Neutral/Up`, `Pistol_Shoot`, `Pistol_Reload` | **pistolet seulement** : `CharacterAnimator` applique cette pose aux 10 armes |
| Impacts | `Hit_Chest`, `Hit_Head` | couvert |
| Capacités | `Spell_Simple_Enter/Idle_Loop/Shoot/Exit`, `Punch_*`, `Push_Loop` | partiel : **aucun lancer** d'objet, aucune pose au sol |
| Objectifs | `Interact`, `PickUp_Table`, `Fixing_Kneeling` | pose de la Mèche et coupe utilisables |
| Social | `Dance_Loop`, `Idle_Talking_Loop`, `Sitting_*` | une seule danse |
| Hors sujet | `Death01` (pas de corps : REMBALLÉ), `Driving_Loop`, `Sword_*`, `Idle_Torch_Loop`, `A_TPose` | — |

### 8.2 Ce qui manque, par impact

1. **Tenue d'arme à deux mains** (repos, visée haut/neutre/bas, tir, rechargement) pour les fusils, le pompe, le sniper et la lourde. C'est le plus gros mensonge actuel : un ennemi qui tient un fusil comme un pistolet ment sur son arme.
2. **Lancer** (allumette-flash, d20, flotteur, fumées) et **pose au sol** (tremplins, pièges, Mèche).
3. **Pas latéraux et marche arrière.**
4. **Poses signature** (sélection, verrouillage, MVP), **idles de sélection** par agent, **émotes et célébrations** vendues en cosmétiques (LORE §7 : poses de verrouillage et de kill).
5. **FP par arme** : rechargement avec le chargeur hors cadre, pompe, culasse, barillet, équipement, inspection. Aujourd'hui, `AnimState` anime tout en procédural sur des gants rigides (`fp_gloves.glb` n'a ni os ni clip).

### 8.3 Ce que Tripo peut fournir (d'après la CLI)

- `tripo anim retarget --help` : `--animation <name...>` « preset:walk preset:run ... (≤5, billed per animation) », plus `--animate-in-place`.
- `retarget` n'accepte qu'un **« rig task id only »** (`commands/process`). Il faut donc d'abord `tripo anim rig`, qui pose **son** squelette (`--spec tripo|mixamo`), pas notre UAL-G.
- **Presets du rig v2.0/2.5** (défaut de la CLI) : `idle walk run dive climb jump slash shoot hurt fall turn`, soit 11 clips.
- **Presets du rig v1.0** (bipède, `-p model=v1.0-20240301`) : plus de 90 clips, dont `victory_celebration`, `cheer`, `clap`, `bow`, `greet_01…04`, `fold_arms`, `laugh_01/02`, `dance_01…06`, `defeat_02/03`, `standing_relax`, `look_around`, `cast_a_spell`, `shoot`, `fire`.
- **Aucun import d'animation personnalisée, aucune tenue d'arme par catégorie, aucun rig FP.**

**Verdict.** Tripo peut fournir des émotes, des célébrations et des idles génériques. Il ne peut fournir aucun des manques 1, 2, 3 et 5, ni des poses signature propres à un agent.

### 8.4 Recommandation

1. **Gameplay en TP (manques 1 à 3) : pas de Tripo.** UAL-G reste l'unique squelette. On complète d'abord avec **UAL2** (CC0, 130 clips, recherche 06), en vérifiant la présence d'une tenue de fusil et d'un lancer avant toute autre voie. Ce qui manque encore est clé en bpy par script sur UAL-G. 0 crédit.
2. **FP (manque 5) : pas de Tripo.** On garde `AnimState` procédural et on exige des armes à pièces séparées (§3.5) : c'est cette séparation, pas une anim IA, qui débloque le rechargement lisible. 0 crédit.
3. **Émotes (manque 4) : pilote Tripo borné à ≈ 125 cr.**
   - Un seul `rig` v1.0 `--spec mixamo` du **mannequin neutre du gabarit commun**. La Toise fait que tous les agents ont la même charpente, donc un rig sert les six.
   - Deux appels `retarget` de 5 presets : `victory_celebration`, `cheer`, `clap`, `bow`, `greet_01`, `fold_arms`, `laugh_01`, `dance_01`, `standing_relax`, `look_around`.
   - Reciblage vers UAL-G à l'import Godot par `BoneMap` + `SkeletonProfileHumanoid` : le squelette Mixamo et les os `DEF-*` de Rigify se mappent sur le même profil humanoïde (le `BoneMap` DEF-* est à écrire une fois).
   - **Critère :** pas de main qui traverse la tête ou le torse, pieds ancrés, lisible dans `character_shots`. Sinon on arrête : 125 cr perdus au plus.
4. **Poses signature et idles de sélection définitifs : clés bpy par agent**, écrites à partir des fiches du LORE §4 et des jetons `agents.*.animation` (cadence, `lean_deg`, idle). Exemple : Roseau se tient sur une patte au repos, et Vif part « avant le coup de feu ». Aucun preset générique ne sait faire ça ; c'est pourtant ce qui vend un héros.

---

## 9. Risques

1. **Coût réel inconnu.** Aucune grille v3.1 dans la CLI, et l'exemple de la CLI est 2 à 3 fois au-dessus de la grille de travail. *Parade :* calibration sur `gp_bomb`, plafond `credit_cap` par manifeste, arrêt sur le code 4.
2. **Treillis qui fondent** (derrick, grue, antenne, portique) : les générateurs 3D ratent les membrures fines. *Parade :* prompts « very thick chunky beams, only three levels of X braces » (le style « jouet » l'autorise), porte G2, relance en multiview. Au 3ᵉ échec, on repasse en bpy ; le coût est borné par la réserve.
3. **Maillages soudés.** Les pièces mobiles des armes, de la Mèche et des cisailles sortent fondues dans la coque. *Parade :* découpe par boîte et rebouchage dans `ai_restyle`. Si ça ne tient pas sur Ravage (étape 3 du §7), on génère les chargeurs à part : +45 cr par arme, soit +450 cr.
4. **Style hétérogène sur 95 générations.** *Parade :* même suffixe, même cadrage de concept, porte G1 sur planche, texture jetée et palette imposée. Le test reste celui de la bible §14.3 : si un asset est moins lisible que la guimauve deux tons de l'épingle 08, c'est un échec.
5. **Écart CHK-15** (0,9, 1,4 et 1,8 m) : les couverts conformes à la collision échouent le contrôle tel qu'il est écrit. À trancher avant la vague 2 (§10).
6. **Politique de contenu** (code 5) sur les armes et la charge. Les prompts évitent « bomb » et « explosive » ; les armes sont décrites comme des objets de jeu stylisés. À surveiller dès la calibration.
7. **Droits et Steam.** Seul le plan payant de Tripo cède les droits. Une provenance par asset (outil, modèle, date, prompt, sha256 du concept) va dans `THIRD_PARTY_LICENSES.md`, et la déclaration Steam « contenu IA pré-généré » est obligatoire.
8. **Lore non validé.** La vague 3 est bloquée tant que `LORE.md` n'est pas validé. Les repères P2 mélangent encore la bible et le lore (grue de Port-Ferraille orange ou jaune de l'Ardente).
9. **Branchements hors de ce plan.** L'auvent + poteaux, le socle de grue de pont, `cs_hatch_pile`, la Borne au centre et les cisailles tenues exigent des changements dans `MapSetup`, `Kit`, `SnDMode` et `HardpointMode`. Sans eux, les assets restent au garage.

---

## 10. Décisions demandées à l'utilisateur

1. **Valider la direction** : forme IA, texture jetée, couleur par slot (§0).
2. **Financer la vague 1** : ≈ 1 520 cr (≈ 15 $) après la calibration, sur un **plan payant**.
3. **CHK-15** : accepter les classes 0,9, 1,1, 1,4, 1,8 et ≥ 2,0 m (§3.1).
4. **`cv_tyre_stack`** : hauteur 1,0 m (spec) ou 1,20 m (manifeste actuel) ?
5. **Valider `LORE.md` v1.0**, ce qui débloque la vague 3, et trancher la couleur de la grue de Port-Ferraille.
6. **Animations** : feu vert pour le pilote d'émotes à 125 cr (§8.4) ; le reste se fait sans Tripo.
