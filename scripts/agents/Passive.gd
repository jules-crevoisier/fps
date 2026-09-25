## Passive.gd
## Passif d'agent (Resource) : capacité TOUJOURS active, sans touche ni charge
## ni cooldown -- branchée via AgentConfig.passive (docs/research/
## 10_ammo_kits_input.md §3.5, "Socle commun à construire (AGT-01)"). Chaque
## agent concret surcharge le sous-ensemble de hooks qui le concerne (ex.
## res://scripts/agents/passives/short_fuse.gd pour "Mèche courte" de Vif) ;
## l'implémentation par défaut ici ne fait rien -- un agent SANS passif garde
## `AgentConfig.passive == null`, et AbilityController garde ses propres
## gardes (`agent.passive != null`) avant d'appeler quoi que ce soit.
##
## `player` désigne TOUJOURS le PROPRIÉTAIRE du passif (l'agent qui le
## possède), jamais une victime/un ennemi -- y compris pour `modify_cc_duration`,
## qui réduit/allonge un contrôle SUBI par ce joueur (ex. Tête de cloche de
## Choc, -40% sur étourdissement/éblouissement/ralentissement subis).
##
## Appelants (contract-r3.md, cross-slice) :
##  - on_spawn : AbilityController._ready(), côté SERVEUR uniquement.
##  - on_kill/on_assist : AbilityController.server_on_kill/server_on_assist
##    (point d'entrée pour un futur appelant, ex. GameWorld._record_kill via
##    `ab.has_method("server_on_kill")`, hors fichiers possédés ici).
##  - modify_cc_duration : AbilityController.net_apply_stun/net_apply_flash,
##    CHEZ LA VICTIME (avant application de la durée reçue).
##  - spread_mult/on_air : appelants futurs (WeaponFeel/Air.gd, hors fichiers
##    possédés par ce contrat) -- le hook existe déjà et est testé isolément.
class_name Passive
extends Resource

@export var display_name: String = ""
@export var description: String = ""

## SERVEUR, au spawn de `player` (une fois par vie -- voir GameWorld._spawn_player).
func on_spawn(_player: PlayerController) -> void:
	pass

## SERVEUR, quand `player` vient de réaliser une ÉLIMINATION sur `victim_id`.
func on_kill(_player: PlayerController, _victim_id: int) -> void:
	pass

## SERVEUR, quand `player` obtient une ASSISTANCE sur `victim_id`
## (AssistTracker.assists_for_kill : >= 40 dégâts dans les 5 s avant la mort).
func on_assist(_player: PlayerController, _victim_id: int) -> void:
	pass

## Multiplicateur (jamais un delta additif) appliqué à la durée d'un CONTRÔLE
## SUBI par le propriétaire de ce passif (étourdissement, éblouissement,
## ralentissement) -- ex. Tête de cloche de Choc : `return duration * 0.6`.
## 1.0 par défaut (aucun effet).
func modify_cc_duration(duration: float) -> float:
	return duration

## Multiplicateur de dispersion d'arme pour `player` (ex. Sang-froid de
## Verrou : -30% immobile/accroupi). 1.0 par défaut (aucun effet).
func spread_mult(_player: PlayerController) -> float:
	return 1.0

## Appelé CHAQUE tick physique tant que `player` est en l'air (ex. Planeur de
## Guet). Ne fait rien par défaut.
func on_air(_player: PlayerController, _delta: float) -> void:
	pass
