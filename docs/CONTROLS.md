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

## Disposition clavier (AZERTY / QWERTY)

Les touches sont en **position physique** : ZQSD fonctionne donc tel quel sur
AZERTY. L'**affichage** des touches s'adapte automatiquement à la disposition de
l'OS via `DisplayServer.keyboard_get_label_from_physical()` (affiche « Z » sur
AZERTY, « W » sur QWERTY…). Un switch **AZERTY / QWERTY** dans Options permet de
forcer une disposition logique si besoin.

## Menu Options (deux pages)

Accessible depuis le menu principal et le menu pause (Échap / Start).

**Page Clavier / Souris**
- Sensibilité souris
- Champ de vision (FOV)
- Switch de disposition AZERTY / QWERTY
- Remap de toutes les touches (clique une action → appuie sur la nouvelle touche)

**Page Manette**
- Sensibilité du stick droit
- Inversion de l'axe Y
- Remap des boutons (clique une action → appuie sur un bouton manette)
- Sticks et gâchettes (déplacement / visée / tir) sont fixes

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
| Disposition clavier | Options › Clavier | `Settings.layout` (azerty/qwerty) |
| Remap touches/boutons | Options (2 pages) | persistant par action |

> Pour le tick compétitif, le netcode et le test à 2 fenêtres, voir
> [`MULTIPLAYER.md`](MULTIPLAYER.md).
