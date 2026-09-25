# Audit de bugs — UI menus (reprise de la tranche échouée)

Date : 2026-09-24
Périmètre (repris après l'interruption, tranche redistribuée par le lead) :
`scripts/ui/MainMenu.gd`, `AgentSelectScreen.gd`, `AgentMenu.gd`,
`ArsenalMenu.gd`, `BuyMenu.gd`, `OptionsMenu.gd`, `PauseMenu.gd`,
`SpeedHUD.gd`. Axes : capture souris/focus, persistance des réglages, pause
en multijoueur, disposition à 1280x720, flux qui n'aboutissent pas.

Pour resituer un correctif dans le reste du HUD/jeu (ex. `GameHUD.gd`), voir
`docs/audit/bugs.md` (autre tranche, compilée séparément — ne pas dupliquer
ici). Les manques de fonctionnalités déjà planifiés (minimap, FOV horizontal,
FTUE, éditeur de viseur, etc.) sont suivis dans `docs/research/04_ui_ux.md`
(UX-01 à UX-12) et ne sont pas re-listés ici : ce fichier ne couvre que des
défauts de comportement concrets, pas des fonctionnalités manquantes.

Vérifié et jugé correct dans ce périmètre (pour éviter de re-chercher) : la
capture souris à l'entrée en jeu après l'écran de sélection d'agent
(`AgentSelectScreen.gd` laisse la souris visible, mais
`PlayerController.gd:168-170` la recapture inconditionnellement dès que le
personnage local entre dans l'arbre — pas un bug) ; la persistance des
réglages elle-même (`OptionsMenu.gd` appelle bien `Settings.save_all()` /
lit bien `Settings.*` à la construction pour les 4 pages) ; le pause en
multijoueur ne fige pas l'arbre de scène (`PauseMenu.gd` ne touche jamais
`get_tree().paused`, et `PlayerInput.gd:71` arrête de lire les périphériques
dès que `Input.mouse_mode != CAPTURED`, donc ouvrir Pause fige bien
SEULEMENT le joueur local, jamais les autres joueurs).

Sévérités : **Bloquant** / **Majeur** / **Mineur** (voir `bugs.md` pour la
définition complète).

## Tableau des bugs

| id | Sévérité | Symptôme (joueur) | Repro | Cause racine (fichier:ligne) | Correctif proposé | Confiance |
|----|----------|--------------------|-------|------------------------------|--------------------|-----------|
| BUG-U01 | Majeur | En pleine partie, fermer le menu Pause alors que le menu d'Achat était resté ouvert en dessous recapture la souris (curseur caché) alors que le menu d'Achat est toujours affiché à l'écran — impossible de cliquer sur une arme tant qu'on n'a pas rouvert/refermé un menu pour "reset" l'état. Réciproquement, la touche B (achat) reste active MÊME quand Pause est ouvert, et peut ouvrir/fermer l'Achat sous l'overlay de Pause. | 1) En SnD pendant la phase d'achat, ouvrir le menu Achat (B). 2) Appuyer sur Échap pour ouvrir Pause par-dessus. 3) Fermer Pause (Échap ou "Reprendre"). | `scripts/ui/PauseMenu.gd:92-97` (`_close()` fait `Input.mouse_mode = CAPTURED` sans vérifier si `BuyMenu._open` est vrai) et `scripts/ui/BuyMenu.gd:166-171` (`_close()` fait l'inverse, sans vérifier Pause) ; `scripts/ui/PauseMenu.gd:66-80` (`_unhandled_input` ne consomme que "pause"/"ui_cancel", laisse passer "buy_menu" vers `scripts/ui/BuyMenu.gd:125-134`) ; `scripts/ui/GameHUD.gd:311-322` fait le même genre d'écriture directe et non coordonnée sur `Input.mouse_mode` pour l'écran de fin de match. | Centraliser l'état "un overlay modal est ouvert" (ex. compteur partagé ou petit `UiModalStack` sur un groupe "ui_modal") : chaque overlay s'enregistre à l'ouverture / se désenregistre à la fermeture, et `Input.mouse_mode` n'est recapturé que quand la pile est vide. Faire consommer "buy_menu" par Pause pendant qu'il est ouvert (ou vérifier `PauseMenu._open` dans `BuyMenu._unhandled_input`). | confirmé |
| BUG-U04 | Majeur | Déplacer un curseur de réglage (sensibilité, FOV, volumes, échelle d'UI…) dans Options donne une sensation saccadée/hachée pendant le glissé, à chaque session dès qu'on touche un réglage. | Ouvrir Options → Clavier/Souris (ou Affichage & Son) → glisser lentement un slider (ex. Sensibilité souris) d'un bout à l'autre. | `scripts/ui/OptionsMenu.gd` : chaque `HSlider.value_changed` (ex. lignes 144-145 sensibilité souris, 153-154 FOV, 183-184 sensibilité manette, 266-269 échelle UI, et les 3 volumes via `_volume_row` lignes 284-292/219-228) appelle `Settings.save_all()` à CHAQUE frame de glissé (le signal se déclenche en continu pendant un drag) ; `scripts/core/Settings.gd:100-122` (`save_all`) recrée un `ConfigFile` complet et fait un `cfg.save(PATH)` synchrone sur disque à chaque appel — soit des dizaines d'écritures disque par seconde pendant qu'on tient un slider. | Découpler la sauvegarde de l'input : sauvegarder en mémoire immédiatement (déjà fait via `Settings.mouse_sensitivity = x` etc.) mais reporter `save_all()` — soit sur `value_changed` avec un `Timer`/debounce (~300-500 ms d'inactivité), soit uniquement sur `drag_ended` (signal natif de `Range`/`Slider` en fin de glissé) au lieu de `value_changed`. | confirmé |
| BUG-U02 | Majeur | En train de réassigner une touche clavier ("Appuyez…"), cliquer n'importe où avec la souris (y compris sur un autre bouton, un onglet, ou "Retour") ne fait PAS ce qu'on attend : ça réassigne silencieusement l'action au bouton de souris cliqué à la place, et le clic n'active pas le bouton visé (le menu ne se ferme pas, l'onglet ne change pas). Rien à l'écran n'indique qu'Échap est la seule façon d'annuler. | Options → Clavier/Souris → cliquer sur "Touches" pour une action (le bouton affiche "Appuyez…") → au lieu d'appuyer sur une touche, cliquer sur "Retour" ou un autre onglet. | `scripts/ui/OptionsMenu.gd:343-361` (`_input`) : en mode écoute clavier (`_listening_kind == "kb"`), la branche `elif event is InputEventMouseButton and event.pressed: Settings.set_binding(...)` capture TOUT clic souris comme nouvelle touche et appelle `accept_event()` (ligne 361), donc le clic n'atteint jamais le bouton visé ; le seul indice pour annuler (Échap, ligne 349) n'est pas affiché au joueur (texte "Appuyez…" à la ligne 310, sans mention d'Échap). | Restreindre la capture au clavier réel pendant l'écoute "kb" (retirer la branche `InputEventMouseButton`, ou ne l'accepter que si le clic est en dehors de tout `Control` interactif), et afficher "Appuyez sur une touche (Échap pour annuler)". | confirmé |
| BUG-U03 | Majeur | À la manette ou au clavier seul (sans souris), impossible de voir les armes au-delà du haut de la liste dans le menu Arsenal — aucune touche ne fait défiler la liste. | Ouvrir Arsenal depuis le menu principal (onglet ARSENAL) à la manette ou au clavier seul, essayer de faire défiler avec le stick/D-pad/flèches vers le bas. | `scripts/ui/ArsenalMenu.gd:71-103` (`_weapon_card`) : chaque plaque d'arme ne contient que des `Label`/`ComicBar` (aucun `Button`, aucun `focus_mode` réglé) ; le seul élément focusable de tout l'écran est "Retour" (ligne 40-45, 69). Sans second élément focusable, les flèches/le stick n'ont nulle part où déplacer le focus, et `_scroll.follow_focus` (aucun équivalent au défilement tenu de `scripts/ui/OptionsMenu.gd:312-333`) n'a rien à suivre — contrairement à `AgentMenu.gd` qui fonctionne car chaque carte a un bouton "Choisir" focusable. Avec 10 armes (`scripts/combat/WeaponDatabase.gd:7-18`) contre un panneau qui tient 2-3 plaques à l'écran, une bonne partie de la liste est definitivement hors d'atteinte sans souris. | Donner `focus_mode = Control.FOCUS_ALL` à chaque plaque d'arme (ou ajouter un bouton invisible par ligne) pour que le focus/`follow_focus` puisse s'y déplacer, ou reprendre le handler de défilement tenu d'`OptionsMenu.gd` (`_process`, lignes 312-333) sur le `ScrollContainer` de l'Arsenal. | confirmé |

## Tâches

```
- id: BUG-U01
  title: "Coordonner Input.mouse_mode entre les overlays (Pause/Achat/fin de match) et gater les actions modales"
  files: [scripts/ui/PauseMenu.gd, scripts/ui/BuyMenu.gd, scripts/ui/GameHUD.gd]
  depends_on: []
  size: M
  acceptance: "ouvrir Achat puis Pause par-dessus puis fermer Pause laisse le menu Achat cliquable (souris visible) ; la touche B n'ouvre/ne ferme plus Achat pendant que Pause est affiché ; fermer le dernier overlay ouvert recapture la souris exactement une fois."

- id: BUG-U04
  title: "Ne plus écrire settings.cfg sur disque à chaque frame de glissé d'un slider"
  files: [scripts/ui/OptionsMenu.gd, scripts/core/Settings.gd]
  depends_on: []
  size: S
  acceptance: "glisser un slider (sensibilité/FOV/volume/échelle UI) du min au max ne déclenche plus qu'UN SEUL `cfg.save(PATH)` (au relâchement ou après un court debounce), avec la valeur en mémoire déjà à jour pendant le glissé ; aucune régression sur le rechargement au prochain lancement."

- id: BUG-U02
  title: "Corriger le vol de rebind clavier par un clic souris dans OptionsMenu"
  files: [scripts/ui/OptionsMenu.gd]
  depends_on: []
  size: S
  acceptance: "pendant l'écoute d'une touche clavier, cliquer sur 'Retour' ou un onglet effectue bien cette action au lieu de réassigner un bouton de souris ; le bouton en écoute affiche un indice explicite pour annuler (Échap)."

- id: BUG-U03
  title: "Rendre le menu Arsenal défilable au clavier/à la manette"
  files: [scripts/ui/ArsenalMenu.gd]
  depends_on: []
  size: S
  acceptance: "depuis 'Retour', appuyer répétément sur bas (clavier ou manette) atteint la dernière arme de la liste sans utiliser la souris ; le ScrollContainer suit le focus jusqu'en bas."
```
