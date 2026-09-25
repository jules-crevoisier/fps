# Contrôles, options & manette

## Mapping par défaut

| Action | Clavier / Souris | Manette (Xbox) |
|--------|------------------|----------------|
| Déplacement | W / A / S / D | Stick gauche |
| Visée | Souris | Stick droit |
| Sauter | Espace | A |
| Marche lente (sinon **sprint auto**) | Shift (maintenu) | L3 |
| Accroupi / Slide | Ctrl (maintien) | B |
| Dive / Landing-roll | V | LB |
| Tirer | Clic gauche | RT |
| Viser (ADS) | Clic droit | LT |
| Recharger | R | X |
| Arme 1 / 2 / 3 | 1 / 2 / 3 | — |
| Arme suivante / préc. | Molette | Y / — |
| Lâcher l'arme (drop) | G | D-pad bas |
| Ramasser / échanger | F | R3 |
| Boutique (training) | B | Select |
| Pause | Échap | Start |
| Menus : valider / retour | Entrée / Échap | A / B |
| Menus : navigation | Flèches | D-pad / stick gauche |

Les bindings vivent dans `project.godot` (source unique). Les **overrides** du
joueur sont sauvegardés dans `user://settings.cfg` (`scripts/core/Settings.gd`).

## Disposition clavier (Auto / AZERTY / QWERTY)

Les touches sont **toujours en position physique**, dans tous les cas : ZQSD
fonctionne donc tel quel sur AZERTY, quel que soit le réglage ci-dessous — ce
réglage ne change **jamais aucune liaison**, seulement l'**étiquette affichée**
sur les touches (`Settings.label_for_physical`).

- **Auto** (défaut) : l'affichage s'adapte à la disposition RÉELLE de l'OS via
  `DisplayServer.keyboard_get_label_from_physical()` (affiche « Z » sur
  AZERTY, « W » sur QWERTY…).
- **AZERTY** / **QWERTY** : force l'étiquette affichée, sans consulter l'OS —
  utile quand celui-ci ment (clavier US avec Windows en français, bureau à
  distance…).

La rangée de chiffres n'est jamais retraduite (elle reste « 1 »…« 0 », jamais
« & »/« é »/« " »).

Un ancien fichier de sauvegarde qui avait re-lié les touches de déplacement en
clavier **logique** (l'ancien switch, avant cette version) est migré au
chargement vers une liaison physique équivalente ; l'ancien réglage "qwerty"
(défaut de l'époque, sans rapport avec le clavier réel du joueur) redevient
"Auto". Le bouton « Réinitialiser cette page » ne force plus jamais QWERTY :
il remet les 4 touches de déplacement à leur défaut physique de
`project.godot` et le mode d'affichage à "Auto".

## Menu Options (quatre pages)

Accessible depuis le menu principal et le menu pause (Échap / Start). Chaque
page a son bouton « Réinitialiser cette page » (ne remet à zéro que cette page).

**Page Clavier / Souris**
- Sensibilité souris
- Champ de vision (FOV)
- Mode d'affichage clavier Auto / AZERTY / QWERTY (libellés seulement)
- Sensibilité en visée (ADS), maintien ou bascule (accroupi/ADS/marche)
- Remap de toutes les touches (clique une action → appuie sur la nouvelle touche)

**Page Manette**
- Sensibilité du stick droit
- Inversion de l'axe Y
- Remap des boutons (clique une action → appuie sur un bouton manette)
- Sticks et gâchettes (déplacement / visée / tir) sont fixes

**Page Affichage & Son**
- Mode fenêtre, échelle de rendu 3D, vsync, limite d'images, préréglage
  graphique (dont Steam Deck), contours d'arête, overlay FPS/réseau
- Volumes maître/effets/musique/interface/voix/ambiance, audio mono

**Page Accessibilité**
- Couleur ennemi (Magenta/Citron), échelle d'interface (Steam Deck)
- Mouvement réduit, secousses de caméra, balancement de tête (head-bob)

Le scroll **suit la sélection** (`follow_focus`) ; maintenir haut/bas (stick ou
D-pad) fait défiler en continu.

## Navigation manette dans les menus

Les actions `ui_*` sont définies (clavier + manette) : **A** valide, **B** revient,
**D-pad / stick gauche** déplacent la sélection. Chaque menu pose le focus sur son
premier élément à l'ouverture.

## Réglages disponibles (résumé)

| Réglage | Où | Détail |
|---------|----|--------|
| Sensibilité souris | Options › Clavier | `Settings.mouse_sensitivity` |
| Sensibilité manette | Options › Manette | `Settings.gamepad_sensitivity` |
| Inversion Y | Options › Manette | `Settings.invert_y` |
| FOV | Options › Clavier | `Settings.fov` |
| Mode d'affichage clavier | Options › Clavier | `Settings.layout` (auto/azerty/qwerty) |
| Remap touches/boutons | Options (2 pages) | persistant par action |

> Pour le tick compétitif, le netcode et le test à 2 fenêtres, voir
> [`MULTIPLAYER.md`](MULTIPLAYER.md).
