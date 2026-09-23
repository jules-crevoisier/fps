## Ability.gd
## Capacité de base (façon Valorant). Chaque capacité concrète hérite de cette
## classe et surcharge `activate_local()` et/ou `activate_server()`. Les
## métadonnées (cooldown, charges, ultime) sont lues par l'AbilityController
## qui gère l'état runtime (AbilityState : timers, charges) et l'autorité
## réseau (prédiction propriétaire + validation serveur).
class_name Ability
extends Resource

## Emplacement / touche : "C", "Q", "E" (capacités) ou "X" (ultime).
@export var slot: String = "C"
@export var display_name: String = "Capacité"
## Courte description affichée dans les écrans de sélection/agents. Le
## contre-jeu de chaque capacité est documenté dans docs/AGENTS.md.
@export var description: String = ""
## Cooldown entre deux usages (s).
@export var cooldown: float = 8.0
## Nombre de charges (utilisations avant cooldown global).
@export var charges: int = 1
## Ultime : se charge par points au lieu d'un cooldown.
@export var is_ultimate: bool = false
## Points nécessaires pour l'ultime.
@export var ult_cost: int = 7

## Exécuté côté PROPRIÉTAIRE dès l'activation locale (prédiction) : mouvement,
## cosmétique — jamais d'effet de jeu autoritaire (vie, etc.). `player` = le
## joueur qui utilise la capacité. À surcharger dans les capacités concrètes.
func activate_local(_player: PlayerController) -> void:
	pass

## Vérification SERVEUR additionnelle avant de consommer une charge/l'ultime
## (ex. HealAbility : hors-combat depuis 3 s). true par défaut (aucune
## condition) ; à surcharger dans les capacités concrètes qui en ont besoin.
func can_activate_server(_player: PlayerController) -> bool:
	return true

## Exécuté côté SERVEUR une fois l'activation validée (AbilityState
## autoritaire) : effets de jeu (soin, dégâts, spawn répliqué...). `aim_dir`
## est la direction de visée du propriétaire, déjà validée (finie, normalisée)
## par AbilityController — sert à calculer une cible depuis la vue serveur
## (fumée, tremplin, piège, œil...). À surcharger dans les capacités concrètes.
func activate_server(_player: PlayerController, _aim_dir: Vector3) -> void:
	pass
