## ImportedMapGeometry.gd
## Contrat pour la géométrie de carte IMPORTÉE (glTF exporté depuis Blender,
## 2026-09-28, Canyon Express) — Shipment reste une scène plate posée à la
## main (voir MapSetup.gd) ; ce script sert les cartes futures dont l'art +
## la collision viennent d'un .glb exporté par le lead (`bridge_autoexport.py`,
## voir CLAUDE.md « Où est quoi »).
##
## Convention côté export Blender (glTF) :
##  - collision : proxies posés comme StaticBody3D nommés `COL_<surface>_<Nom>`
##    (indice d'import Godot `-convcolonly` retiré du nom une fois importé,
##    confirmé par inspection de canyon_express.glb importé : chaque
##    `COL_*-convcolonly` devient un StaticBody3D `COL_*` avec pour SEUL
##    enfant un CollisionShape3D/ConvexPolygonShape3D, aucun mesh visible) —
##    `<surface>` est un jeton libre (metal/wood/rock/clip/…) traduit vers
##    `SurfaceSound.gd` (qui ne connaît que metal/concrete, voir
##    `_surface_token_from_name`) SAUF `clip` (voir ci-dessous).
##  - `clip` (Canyon Express, garde-corps en corde de la passerelle) : PAS un
##    mur normal -- bloque uniquement le CORPS des joueurs/bots
##    (PhysicsLayers.PLAYER_CLIP, le bit que `scenes/player/player.tscn` porte
##    déjà dans son `collision_mask` par défaut), jamais `PhysicsLayers.WORLD` :
##    un tir/une grenade/un rayon de vision de bot (PhysicsLayers.SHOT_MASK,
##    qui exclut PLAYER_CLIP) le traverse toujours. Voir `_configure_collider`.
##  - visuel : un StandardMaterial3D importé (glTF) reste tel quel tant que
##    son nœud racine ne porte pas la méta `imported_art = true` — SEULS ces
##    sous-arbres reçoivent `ToonStyle.apply_to(root, "world")` (profil décor :
##    pas de liseré/reflet sur des pans plats, voir ToonStyle._section).
##
## `prepare(root)` doit tourner AVANT le bake du navmesh (MapSetup._enter_tree) :
## Recast parse `PARSED_GEOMETRY_STATIC_COLLIDERS`, donc les StaticBody3D
## `COL_*` doivent déjà porter leurs calques définitifs à ce moment-là.
## Shipment (aucun StaticBody3D `COL_*`, aucun nœud `imported_art`) traverse
## cette fonction sans qu'elle ne touche à quoi que ce soit — comportement
## byte pour byte inchangé.
class_name ImportedMapGeometry
extends RefCounted

const _COL_PREFIX := "COL_"

## Point d'entrée unique — walk complet du sous-arbre de `root` : pose les
## calques physiques + la méta "surface" sur chaque proxy de collision
## `COL_*`, puis applique le style toon "world" à chaque sous-arbre marqué
## `imported_art = true`. `root` nul : aucun effet (jamais une erreur).
static func prepare(root: Node) -> void:
	if root == null:
		return
	_prepare_collision(root)
	_prepare_visuals(root)

# ---------------------------------------------------------------------------
#  Collision : StaticBody3D "COL_<surface>_<Nom>" -> méta "surface" + calques.
# ---------------------------------------------------------------------------

static func _prepare_collision(node: Node) -> void:
	if node is StaticBody3D and String(node.name).begins_with(_COL_PREFIX):
		_configure_collider(node as StaticBody3D)
	for child in node.get_children():
		_prepare_collision(child)

const _CLIP_TOKEN := "clip"

## Calques IDENTIQUES à ceux des StaticBody3D de Shipment (scenes/levels/maps/
## shipment.tscn n'en surcharge aucun -- confirmé par lecture directe de la
## scène) : les défauts moteur, soit PhysicsLayers.WORLD des deux côtés --
## un tir (PhysicsLayers.SHOT_MASK) et un rayon de vision de bot heurtent donc
## ce proxy exactement comme un mur de Shipment. SAUF `clip` (garde-corps de
## passerelle, Canyon Express) : PhysicsLayers.PLAYER_CLIP SEUL en layer
## (jamais WORLD) -- bloque le corps des joueurs/bots, jamais un tir/une
## ligne de vue (voir la doc de tête). `collision_mask` à 0 : ce corps
## STATIQUE ne « scanne » jamais lui-même -- Godot fait déjà collider deux
## corps dès qu'UN SEUL sens layer/mask correspond (le mask du joueur inclut
## déjà PLAYER_CLIP, voir scenes/player/player.tscn), la réciproque est donc
## inutile.
static func _configure_collider(body: StaticBody3D) -> void:
	var token := _raw_token_from_name(String(body.name))
	body.set_meta("surface", _surface_value_for(token))
	if token == _CLIP_TOKEN:
		body.collision_layer = PhysicsLayers.PLAYER_CLIP
		body.collision_mask = 0
		return
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = PhysicsLayers.WORLD

## Jeton BRUT entre `COL_` et le prochain `_` (le nom peut porter un suffixe
## libre après, ex. "COL_metal_CargoDoorLeft") -- "metal", "wood", "rock",
## "clip"… tel quel, jamais encore traduit vers une valeur SurfaceSound.
static func _raw_token_from_name(node_name: String) -> String:
	var rest := node_name.trim_prefix(_COL_PREFIX)
	return rest.split("_")[0].to_lower()

## Jeton brut -> valeur "surface" acceptée par SurfaceSound.gd. SurfaceSound
## ne distingue QUE metal/concrete (pas de variante bois dédiée, voir sa doc +
## tests/audio/test_surface_sound.gd `impact_sound_for("wood") ==
## "impact_concrete"`) : "wood"/"rock"/"clip"/tout jeton inconnu retombe donc
## sur CONCRETE, jamais une nouvelle valeur inventée ici (même un garde-corps
## `clip`, qu'aucun tir ne peut de toute façon jamais atteindre, porte une
## méta "surface" -- contrat de tâche : « chaque corps COL a une méta
## surface »).
static func _surface_value_for(token: String) -> String:
	if token == "metal":
		return SurfaceSound.METAL
	return SurfaceSound.CONCRETE

# ---------------------------------------------------------------------------
#  Visuel : sous-arbres marqués imported_art = true -> profil toon "world".
# ---------------------------------------------------------------------------

static func _prepare_visuals(node: Node) -> void:
	if node.has_meta("imported_art") and bool(node.get_meta("imported_art")):
		# `ToonStyle.apply_to` descend déjà tout le sous-arbre lui-même --
		# jamais la peine (ni correct) de redescendre ici après.
		ToonStyle.apply_to(node, "world")
		return
	for child in node.get_children():
		_prepare_visuals(child)
