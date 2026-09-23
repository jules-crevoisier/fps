## CharacterBody.gd
## Corps 3D animé du joueur (remplace la capsule) — enfant "CharacterModel" de
## player.tscn (unique_name_in_owner : "%CharacterModel"). Instancie le glb de
## l'agent choisi (scripts/agents/AgentDatabase.gd, agent_index répliqué au
## spawn UNIQUEMENT — voir PlayerController.agent_index) : assets/models/
## characters/<agent_name en minuscules>.glb, rig "Rig/Skeleton3D" (os
## "DEF-..."), un seul MeshInstance3D à 5 surfaces (slots outfit/cloth/gear/
## skin/accent — voir tools/character_shots.gd, même convention de suffixe).
## Redimensionné pour matcher la capsule de collision (1.8 m, CapsuleShape3D
## inchangée), le modèle fait déjà face à -Z.
##
## Cette classe ne pose AUCUN matériau ni logique allié/ennemi (ça reste le
## rôle de PlayerLook, cf. contract-p0.md "Global rules" — un seul endroit
## qui résout allié/ennemi par rapport au joueur LOCAL) : elle expose juste le
## squelette/AnimationPlayer/mesh une fois chargés, via `model_ready` (signal)
## et `is_model_ready()` — CharacterAnimator/ThirdPersonWeapon/PlayerLook s'y
## abonnent au lieu de supposer un ordre de _ready() entre nœuds frères
## (défensif : le chargement est synchrone aujourd'hui, resterait correct si
## ça changeait).
class_name CharacterBody
extends Node3D

## Hauteur cible (m) — doit matcher `MovementConfig.stand_height` (la
## CapsuleShape3D de la collision, voir scenes/player/player.tscn). Dupliquée
## ici en constante (pas de dépendance à MovementConfig) : la mise à l'échelle
## du modèle est cosmétique, jamais utilisée pour la collision elle-même.
const TARGET_HEIGHT := 1.8
const MODEL_DIR := "res://assets/models/characters/"

## Émis une fois (au premier chargement réussi) — squelette/AnimationPlayer/
## mesh sont résolus et prêts à être consommés.
signal model_ready()

var _model: Node3D
var _skeleton: Skeleton3D
var _anim_player: AnimationPlayer
var _mesh: MeshInstance3D
var _ready_done: bool = false

func is_model_ready() -> bool:
	return _ready_done

func get_skeleton() -> Skeleton3D:
	return _skeleton

func get_anim_player() -> AnimationPlayer:
	return _anim_player

func get_body_mesh() -> MeshInstance3D:
	return _mesh

func _ready() -> void:
	var player := get_parent() as PlayerController
	if player == null:
		return
	# `agent_index` est répliqué SPAWN ONLY (SceneReplicationConfig) et posé
	# par GameWorld._spawn_player AVANT l'ajout à l'arbre (hôte/bot) ou via
	# l'application des propriétés "spawn" du MultiplayerSpawner (client
	# distant) — dans les deux cas, déjà valide ici (voir contract-p0.md /
	# docstring PlayerController.agent_index). -1 = pas de GameWorld
	# (entraînement hors-ligne) : repli sur la sélection locale, même
	# convention que AbilityController._resolve_agent.
	var index := player.agent_index
	if index < 0:
		index = AgentDatabase.selected_index
	var agent := AgentDatabase.get_by_index(index)
	_load_model(agent.agent_name.to_lower())

func _load_model(agent_name: String) -> void:
	var path := "%s%s.glb" % [MODEL_DIR, agent_name]
	if not ResourceLoader.exists(path):
		push_warning("CharacterBody: modèle introuvable pour \"%s\" (%s)" % [agent_name, path])
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("CharacterBody: échec du chargement de %s" % path)
		return
	_model = packed.instantiate() as Node3D
	add_child(_model)
	_skeleton = _find_typed(_model, "Skeleton3D") as Skeleton3D
	_anim_player = _find_typed(_model, "AnimationPlayer") as AnimationPlayer
	_mesh = _find_typed(_model, "MeshInstance3D") as MeshInstance3D
	if _mesh:
		# Voir ViewModel.gd/ThirdPersonWeapon.gd : marge de culling en garde
		# (AABB exportée parfois fausse par l'exporteur glTF).
		_mesh.extra_cull_margin = 2.0
	_scale_to_target_height()
	_ready_done = true
	model_ready.emit()

## Remet le modèle à l'échelle de `TARGET_HEIGHT` à partir de la hauteur de
## son AABB de repos (bind pose, disponible immédiatement — pas besoin
## d'attendre une frame de skinning, cf. tools/character_shots.gd sur le
## décalage d'une frame pour la CAMÉRA, différent : ici c'est la géométrie
## statique du ArrayMesh, indépendante de la pose jouée).
func _scale_to_target_height() -> void:
	if _mesh == null or _mesh.mesh == null:
		return
	var h: float = _mesh.mesh.get_aabb().size.y
	if h > 0.01:
		var s: float = TARGET_HEIGHT / h
		_model.scale = Vector3.ONE * s

func _find_typed(n: Node, class_name_str: String) -> Node:
	if n.get_class() == class_name_str:
		return n
	for c in n.get_children():
		var r := _find_typed(c, class_name_str)
		if r:
			return r
	return null
