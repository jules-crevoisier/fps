# Licences tierces

Tout élément qui n'a pas été créé pour ce projet est listé ici, avec sa source et sa
licence. Un asset sans ligne dans ce fichier ne doit pas entrer dans le jeu.

## Livré avec le jeu

| Élément | Chemin | Source | Licence | Texte |
|---|---|---|---|---|
| Police Protest Revolution (Regular) | `resources/fonts/ProtestRevolution-Regular.ttf` | The Protest Project Authors — https://fonts.google.com/specimen/Protest+Revolution | SIL Open Font License 1.1 | [`resources/fonts/OFL-ProtestRevolution.txt`](resources/fonts/OFL-ProtestRevolution.txt) |
| Police Barlow Condensed (SemiBold, Bold, ExtraBold) — l'ExtraBold sert aussi de base à l'italique DA v2 (titres/bandeaux pinceau), dérivée en code via `FontVariation.variation_transform` (cisaillement synthétique, voir `Comic.font_title_italic()`) : aucun fichier italique séparé | `resources/fonts/BarlowCondensed-*.ttf` | Jeremy Tribby — https://github.com/jpt/barlow | SIL Open Font License 1.1 | [`resources/fonts/OFL-Barlow.txt`](resources/fonts/OFL-Barlow.txt) |
| Police Barlow Semi Condensed (Medium) | `resources/fonts/BarlowSemiCondensed-Medium.ttf` | Jeremy Tribby — https://github.com/jpt/barlow | SIL Open Font License 1.1 | [`resources/fonts/OFL-Barlow.txt`](resources/fonts/OFL-Barlow.txt) |
| Police Lato 2.007 (Black, Bold, Semibold) — repli glyphes non couverts UNIQUEMENT (DA v2, design.md §11 : « Lato est abandonné » de l'usage direct) | `resources/fonts/Lato-*.ttf` | tyPoland, Łukasz Dziedzic — https://www.latofonts.com | SIL Open Font License 1.1 | [`resources/fonts/OFL.txt`](resources/fonts/OFL.txt) |
| Moteur Godot 4.7 | (runtime) | https://godotengine.org | MIT | https://godotengine.org/license |
| Maillage + squelette + animations des 6 agents et des avant-bras FP (kitbash gear par-dessus le mannequin "Universal Animation Library" Standard) | `assets/models/characters/*.glb` | Quaternius — https://quaternius.com | CC0 1.0 | https://creativecommons.org/publicdomain/zero/1.0/ |

## Outils de développement (non livrés dans les builds joueurs)

| Élément | Chemin | Source | Licence | Texte |
|---|---|---|---|---|
| gdUnit4 6.2.1 | `addons/gdUnit4/` | https://github.com/godot-gdunit-labs/gdUnit4 | MIT | [`addons/gdUnit4/LICENSE`](addons/gdUnit4/LICENSE) |

## Règles

- Licences acceptées pour le contenu livré : CC0, MIT, Apache-2.0, OFL, BSD, ou licence
  commerciale achetée (preuve d'achat archivée hors du dépôt).
- Pas de licence « non commerciale », pas de licence qui interdit l'usage dans un jeu
  vendu ou free-to-play.
- Polices : vérifier que l'intégration dans un jeu est permise (les polices Blambot,
  même gratuites, exigent une licence payante pour le jeu vidéo).
