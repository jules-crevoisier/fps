# Audit de bugs — FPS (revue complète du code de gameplay)

Date : 2026-09-23/24. Consolidé par le lead à partir de six audits par tranche (core, joueur,
agents/capacités, HUD, modes/économie, réseau) + revue du dernier commit. Les menus sont audités
à part dans `docs/audit/bugs_ui.md`, les bots dans `docs/audit/bots.md`.

Méthode : lecture intégrale de chaque fichier de la tranche + recoupement avec les appelants ;
exécutions headless de `tools/bot_smoke.gd` et `tools/net_smoke.gd`. Bruit écarté : « material is
null » en headless, messages de fin de process tué par timeout.

Sévérités : **Bloquant** (partie cassée ou bloquée), **Majeur** (comportement faux visible en
session normale), **Mineur** (cosmétique ou cas limite).

## Déjà traité

- `GameWorld.gd` : après un « Rejoindre » raté, la branche qui abandonnait le pair obsolète
  n'hébergeait pas ensuite → état incohérent (`is_host()` faux). **Corrigé** (appel à `net.host()`).
- Connus et déjà au backlog : délai sprint→tir mort (`BUG-K01`), son `reload_in` fantôme (`BUG-K02`).

## Tableau des bugs

| id | Gravité | Ce que voit le joueur | Cause (fichier:ligne) | Correctif | Confiance |
|---|---|---|---|---|---|
| BUG-01 | Bloquant | Match à mort / Hardpoint à égalité à la fin du temps : la partie ne se termine jamais, revanche impossible | `scripts/modes/GameMode.gd:36-42` n'appelle `_try_decide_by_score()` (`:54-59`) qu'à l'instant où le temps expire ; à égalité rien ne le rappelle | Mort subite gérée par `GameMode` : après expiration, re-tenter chaque tick, le prochain point décide | probable |
| BUG-02 | Bloquant | Un client qui rejoint charge SA carte/SON mode choisis dans le menu, pas ceux de l'hôte | `scripts/ui/MainMenu.gd:648-707` applique la config locale avant `change_scene_to_file` ; aucune synchro serveur→client de `MatchConfig` (le commentaire de `scripts/core/MatchConfig.gd:1-6` l'affirme à tort) | Le serveur envoie mode/carte/scène à l'authentification ; le client charge ce qu'il reçoit | probable |
| BUG-03 | Majeur | Murs, fumées, tremplins, pièges et marqueurs d'une manche survivent dans la suivante | `scripts/agents/AbilityController.gd:227-477` : objets détruits seulement par leur minuterie ; rien ne les nettoie dans `scripts/modes/RoundMode.gd:68-73,167-171` | Groupe `round_props`, vidé au passage en phase d'achat et au reset de match | confirmé |
| BUG-04 | Majeur | L'ultime se charge tout seul en ~16 s, même mort ou en phase d'achat | `scripts/agents/AbilityState.gd:11` `ult_charge_rate = 0.45` (contrat : ≤ 0,1) ; tick inconditionnel `AbilityController.gd:71-78` | 0,1 pt/s, pas de charge mort ni hors phase active ; `refill()` des charges de base au début de manche | confirmé |
| BUG-05 | Majeur | Capacité affichée « en recharge » jusqu'à 22 s alors que le serveur l'a refusée (mort pendant l'appui) | `AbilityController.gd:160-183` : 5 retours anticipés sans `_push_state(owner_id)` | Resynchroniser le propriétaire sur tout refus | probable |
| BUG-06 | Majeur | La fumée ne protège pas des balles alors que sa description le promet ; les capacités lancées à travers une fumée explosent sur sa surface ; une arme lâchée flotte sur une fumée | Fumée en couche `VISION` exclue de `SHOT_MASK` (`scripts/core/PhysicsLayers.gd:12`) mais les rayons de `FlashAbility.gd:24`, `SmokeAbility.gd:25`, `StunBurstAbility.gd:23`, `StunTrapAbility.gd:30`, `RevealAbility.gd:49`, `JumpPadAbility.gd:29`, `scripts/world/WorldWeapon.gd:179` n'ont pas de masque | Décision : la fumée bloque la VUE seulement (norme Valorant/CS). Rayons physiques → `SHOT_MASK` ; docs corrigées | confirmé |
| BUG-07 | Majeur | Après une réapparition ou un début de manche : étourdi (étoiles) ou roulade forcée sans chute ; saut involontaire | `scripts/player/PlayerController.gd:332-347` ne remet pas à zéro `_air_peak_y`, `_was_on_floor`, `_roll_buffer_timer`, `_jump_buffer_timer`, `_coyote_timer` ; `slide_jumped` jamais effacé sur le chemin Roll/Stun (`:280-294`) | Tout réinitialiser dans `_do_respawn()` et dans les branches Roll/Stun | confirmé |
| BUG-08 | Majeur | Fin de glissade sous un plafond bas : le joueur se relève dans le décor ; plongeon bloqué à vie sous un obstacle | `scripts/player/states/Slide.gd:82-93`, `Roll.gd:24-31`, `Stun.gd:29-35` ne testent pas `is_blocked_above()` ; `Dive.gd:21-29` sans délai de sortie | Rester accroupi si bloqué ; minuterie de sécurité ~1 s dans Dive | probable |
| BUG-09 | Majeur | Tableau des scores (Tab) qui scintille et consomme du CPU, même sous l'écran de fin | `scripts/ui/GameHUD.gd:207-211` reconstruit `ScoreboardPanel.refresh()` (`:46-59`) chaque image | Reconstruire seulement si l'instantané change | confirmé |
| BUG-10 | Majeur | Bombe perdue pour la manche si le porteur se déconnecte ; aucun porteur si les attaquants n'ont pas fini d'apparaître ; barre de désamorçage fantôme après déconnexion | `scripts/modes/SnDMode.gd:186-204,220-227,252-260,346-357` | Lâcher la bombe si le porteur n'existe plus ; réattribuer au début du live ; purger la progression des absents | confirmé |
| BUG-11 | Majeur | Revanche sur carte asymétrique : les camps restent inversés et le bandeau « CHANGEMENT DE CÔTÉ » s'affiche d'emblée ; Hardpoint ne repart pas du point 0 | `scripts/modes/TDMMode.gd:30-31`, `HardpointMode.gd:16-26` : pas de `reset_match()` | Surcharger `reset_match()` et répliquer | confirmé |
| BUG-12 | Majeur | Duel/Duo : si personne ne tient seul la zone après le temps, la manche ne finit jamais | `scripts/modes/DuelMode.gd:76-127` : aucune limite après `_capture_active` | Plafond de 45 s puis mort subite (prochain kill), sinon victoire aux PV restants | probable |
| BUG-13 | Majeur | Le réglage « échelle d'interface » ne fait rien | `scripts/core/Settings.gd:46` jamais lu hors sauvegarde | Appliquer à la fenêtre (`content_scale_factor`) et en direct depuis les options | confirmé |
| BUG-14 | Mineur | Fichier de réglages corrompu → souris morte/inversée ou FOV aberrant | `Settings.gd:68-71` charge sensibilités et FOV sans borne | Bornes au chargement comme pour le volume | confirmé |
| BUG-15 | Mineur | Sons coupés toujours sur le même canal quand le pool sature | `scripts/core/Audio.gd:453-457` renvoie `pool[0]` | Voler le plus ancien (tourniquet) | confirmé |
| BUG-16 | Mineur | « Rejouer » ne fait rien si la partie a été recréée | `GameHUD.gd:324-330` teste `== null` sans `is_instance_valid` | Même garde qu'en `:187` | probable |
| BUG-17 | Mineur | Compteur « VIVANTS » et barre de pose restent affichés sans mode actif | `GameHUD.gd:192-205` ne masque pas `RoundPanel` | `update_round(null)` / masquage explicite | probable |
| BUG-18 | Mineur | Clignotement d'une image des pastilles de munitions / capacités au ramassage | `scripts/ui/hud/AmmoPanel.gd:64-68`, `AbilityBar.gd:23-42` (`queue_free` + `add_child` ; ternaire mort `:41-42`) | Mettre à jour les nœuds en place | probable |
| BUG-19 | Mineur | Marqueur « kill » affiché sur un tir non mortel juste après un kill | `GameHUD.gd:285-293` + `HitFeedback.gd:37-41` apparient par fenêtre de temps | Couvert par `GF-07` (drapeau kill envoyé par le serveur) | probable |
| BUG-20 | Mineur | Secousse brusque de la caméra au début d'un étourdissement | `scripts/player/PlayerCamera.gd:20,56` : `_dizzy_t` jamais remis à zéro | Remettre à zéro sur le front d'entrée en Stun | confirmé |
| BUG-21 | Mineur | Tremplin ou piège posé sur la tête d'un joueur | `JumpPadAbility.gd:28-33`, `StunTrapAbility.gd:29-34` n'excluent que le lanceur | Rayon de pose limité au décor | probable |

Vérifié sans problème : contrôles d'autorité RPC des modes, double fin de manche, économie
négative, divisions par zéro de `FrameStats`, ordre des autoloads, bus audio, connexions de
signaux au respawn, validations serveur des capacités (visée, cône, cibles).

## Tâches

```
- id: BUG-01
  title: Mort subite quand un match à mort ou Hardpoint est à égalité à la fin du temps
  files: [scripts/modes/GameMode.gd, tests/modes/test_game_mode_tiebreak.gd]
  depends_on: []
  size: S
  acceptance: test — scores égaux à l'expiration, puis un point marqué : winner fixé au tick suivant ; aucune partie ne reste sans vainqueur plus de 1 tick après un changement de score ; bandeau « MORT SUBITE » exposé par le mode

- id: BUG-02
  title: Le client charge la carte et le mode de l'hôte, pas sa sélection locale
  files: [scripts/networking/NetworkManager.gd, scripts/core/MatchConfig.gd, scripts/ui/MainMenu.gd, tests/networking/test_match_config_sync.gd]
  depends_on: []
  size: M
  acceptance: le serveur transmet mode_id, map_id et scène au client authentifié ; le client change de scène avec ces valeurs ; test unitaire de la sérialisation + net_smoke ok=true avec un client qui avait choisi une autre carte

- id: BUG-04
  title: Charge d'ultime plafonnée à 0,1 pt/s, gelée mort ou hors phase active, et recharge des capacités en début de manche
  files: [scripts/agents/AbilityState.gd, tests/agents/test_ability_state.gd]
  depends_on: []
  size: S
  acceptance: ult_charge_rate = 0.1 ; tick(delta, active:=false) n'ajoute rien ; refill() remet charges et recharges de base au maximum sans toucher à l'ultime ; tests verts

- id: BUG-03
  title: Nettoyage des objets de capacités et resynchronisation sur refus serveur
  files: [scripts/agents/AbilityController.gd, scripts/modes/RoundMode.gd, scripts/networking/GameWorld.gd, tests/agents/test_round_props_cleanup.gd]
  depends_on: [BUG-04]
  size: M
  acceptance: murs/fumées/tremplins/pièges/marqueurs dans le groupe round_props, vidé au passage en achat et au reset ; AbilityState.refill() appelé au début de manche ; _server_activate resynchronise le propriétaire sur chaque refus ; tick d'ultime passé inactif quand le joueur est mort ou hors phase LIVE ; tests verts

- id: BUG-06
  title: Fumée = vue seulement — rayons physiques des capacités et des armes au sol ignorent la couche VISION
  files: [scripts/agents/abilities/FlashAbility.gd, scripts/agents/abilities/SmokeAbility.gd, scripts/agents/abilities/StunBurstAbility.gd, scripts/agents/abilities/StunTrapAbility.gd, scripts/agents/abilities/RevealAbility.gd, scripts/agents/abilities/JumpPadAbility.gd, scripts/world/WorldWeapon.gd, docs/AGENTS.md, tests/agents/test_ability_rays.gd]
  depends_on: []
  size: S
  acceptance: tous les rayons de trajectoire/pose utilisent PhysicsLayers.SHOT_MASK ; les rayons de pose n'acceptent que le décor (pas les joueurs) ; docstrings et docs/AGENTS.md disent « bloque la vue, pas les balles » ; test : un flash lancé à travers une fumée atteint le point visé

- id: BUG-07
  title: Réapparition propre — réinitialiser chute, tampons de saut/roulade et slide_jumped
  files: [scripts/player/PlayerController.gd, tests/player/test_respawn_state_reset.gd]
  depends_on: []
  size: S
  acceptance: après respawn depuis une hauteur ou en l'air, aucun Stun/Roll/saut au premier tick ; slide_jumped effacé sur les chemins Roll/Stun ; tests verts

- id: BUG-08
  title: Sorties d'états sous plafond bas et délai de sécurité du plongeon
  files: [scripts/player/states/Slide.gd, scripts/player/states/Roll.gd, scripts/player/states/Stun.gd, scripts/player/states/Dive.gd, tests/player/test_state_exits.gd]
  depends_on: []
  size: S
  acceptance: Slide/Roll/Stun passent en Crouch si is_blocked_above() ; Dive sort en Roll ou au sol après 1 s max ; tests verts ; gameplay_probe sans régression

- id: BUG-09
  title: HUD — rafraîchissements inutiles et gardes manquantes (tableau des scores, munitions, capacités, manche, revanche)
  files: [scripts/ui/GameHUD.gd, scripts/ui/hud/ScoreboardPanel.gd, scripts/ui/hud/AmmoPanel.gd, scripts/ui/hud/AbilityBar.gd, scripts/ui/hud/RoundPanel.gd]
  depends_on: []
  size: S
  acceptance: ScoreboardPanel ne reconstruit que si l'instantané change ; pastilles mises à jour en place ; RoundPanel masqué sans mode ; _on_replay garde is_instance_valid ; ternaire mort retiré ; ui_shots sans régression

- id: BUG-10
  title: Bombe — porteur déconnecté, attribution tardive, progression fantôme
  files: [scripts/modes/SnDMode.gd, tests/modes/test_snd_disconnect.gd]
  depends_on: []
  size: S
  acceptance: porteur disparu → bombe DROPPED à sa dernière position ; porteur attribué au début du live si absent ; entrées de désamorçage des absents purgées ; tests verts

- id: BUG-11
  title: Revanche — réinitialiser changement de côté et point Hardpoint
  files: [scripts/modes/TDMMode.gd, scripts/modes/HardpointMode.gd, tests/modes/test_rematch_reset.gd]
  depends_on: []
  size: S
  acceptance: reset_match() remet sides_swapped, side_swap_notice, _point_index, _rotate_timer et réplique ; tests verts

- id: BUG-12
  title: Duel/Duo — fin garantie d'une manche en impasse sur la zone
  files: [scripts/modes/DuelMode.gd, tests/modes/test_duel_stalemate.gd]
  depends_on: []
  size: S
  acceptance: 45 s après l'activation de la zone sans capture, mort subite ; si toujours rien 20 s plus tard, victoire à la somme de PV restants (égalité → défenseurs) ; test vert

- id: BUG-13
  title: Réglages — appliquer l'échelle d'interface et borner sensibilités et FOV au chargement
  files: [scripts/core/Settings.gd, scripts/ui/OptionsMenu.gd, tests/ui/test_settings_migration.gd]
  depends_on: []
  size: S
  acceptance: ui_scale appliqué à la fenêtre au démarrage et en direct ; mouse/gamepad sensitivity et fov bornés dans load_all ; tests verts

- id: BUG-20
  title: Caméra — pas de saut d'angle à l'entrée en étourdissement
  files: [scripts/player/PlayerCamera.gd]
  depends_on: []
  size: S
  acceptance: _dizzy_t remis à zéro sur le front d'entrée en Stun ; rotation.z continue (test ou sonde)
```
