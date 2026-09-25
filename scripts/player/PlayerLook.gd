## PlayerLook.gd
## Nœud "Look" — enfant du joueur, nommé `Look`. Applique les matériaux
## "personnage" par slot (`Cartoon.character_surface`, outfit/cloth/gear/
## skin/accent — voir CharacterBody.gd) au CORPS 3D (remplace la capsule,
## R3-CHAR) : outfit/gear/skin/accent gardent la couleur exportée du modèle,
## cloth = couleur d'équipe RELATIVE au joueur LOCAL (bleu allié / couleur
## ennemi choisie en options), plus le contour d'équipe
## (`Cartoon.apply_team_outline`). Cache le corps pour le joueur local (vue
## FPS : la caméra est dedans), et coupe l'ombre portée du corps
## (cast_shadow OFF — évite les artefacts d'auto-ombre en vue FPS/TPS
## rapprochée).
##
## `team` est répliqué au spawn (SceneReplicationConfig, player.tscn) mais
## peut ne pas encore être synchronisé, et le joueur LOCAL (groupe
## "local_player", ajouté par PlayerController._ready) peut ne pas encore
## exister dans l'arbre au moment où CE corps y entre (ordre de spawn réseau
## non garanti) — le CORPS 3D lui-même (CharacterBody, chargement du glb de
## l'agent) peut aussi ne pas encore être prêt. On retente donc à intervalle
## régulier jusqu'à pouvoir résoudre les trois (voir `_resolve`). Une fois
## résolu pour un corps distant, on continue de rafraîchir à basse fréquence :
## ça absorbe gratuitement un changement d'équipe (ex. échange de camp en
## R&D) OU un changement d'option daltonisme (Settings.enemy_color) sans
## logique dédiée.
class_name PlayerLook
extends Node

const _RETRY_INTERVAL := 0.25
## Slots matériau exportés par tools/blender/make_characters.py (suffixe du
## nom de matériau, ex. "vif_cloth") — même convention que tools/
## character_shots.gd/ViewModel.gd/ThirdPersonWeapon.gd.
const _SLOTS := ["outfit", "cloth", "gear", "skin", "accent"]

## Épaisseur de contour de base (allié) et son multiplicateur ennemi — repère
## d'accessibilité indépendant de la couleur (design.md §12 : "Enemy contours
## are 50% thicker in 3D"). Constante de référence documentée/testée
## (`outline_px_for`) — l'épaisseur réelle du contour ennemi est appliquée par
## `Cartoon.apply_team_outline`, plus de sélection manuelle de px ici.
const _OUTLINE_PX_ALLY := 3.0
const _OUTLINE_PX_ENEMY_MULT := 1.5

## Rim de ciel (STYLE_BIBLE.md v3 §4.5 « Matériaux et shading des
## personnages » : "fresnel 0.20, teinte de l'horizon de la carte" ; jetons
## machine `docs/style/tokens.json` shader.ink_toon.character.rim_strength =
## 0.20 / rim_color = "map.sky_horizon"). Détache le personnage du fond de
## ciel et NE PORTE AUCUNE information d'équipe — contrairement au rim de
## surbrillance ennemi (0.6, `Cartoon.enemy_color()`), qui reste inchangé.
const _RIM_STRENGTH_SKY := 0.20

## GF-10 "Réaction visible de la cible" : flash de hit posé sur le rim
## (instance uniform, `Cartoon.set_rim` — jamais le matériau partagé) à chaque
## dégât confirmé (`Health.hit_reaction`, diffusé à TOUS les pairs) — blanc
## pour un coup normal, rouge pour un headshot. `HIT_FLASH_STRENGTH` dépasse
## largement le rim de repos (0.20 allié / 0.6 ennemi, voir
## `_apply_character_materials`) pour bien se lire comme un flash plutôt
## qu'un simple regain de contre-jour.
const HIT_FLASH_DURATION_S := 0.07  # 70 ms, contrat GF-10
const HIT_FLASH_STRENGTH := 2.0
const _HIT_FLASH_COLOR := Color.WHITE
## docs/style/tokens.json color.accents.red (#C8322B) — même hex que
## `Cartoon.CONTAINER_RED`, mais gardé en constante LOCALE : c'est ici le
## rouge d'accent générique, pas la couleur d'un matériau de décor.
const _HIT_FLASH_HEADSHOT_COLOR := Color("c8322b")

var _body: PlayerController
var _character_body: CharacterBody
var _mesh: MeshInstance3D
var _health: Health
var _t: float = 0.0
var _flash_time_left: float = 0.0   ## > 0 : flash de hit en cours (voir `_drive_hit_flash`).

func _ready() -> void:
	_body = get_parent() as PlayerController
	if _body:
		_character_body = _body.get_node_or_null("%CharacterModel") as CharacterBody
		_health = _body.get_node_or_null("Health") as Health
		if _health:
			_health.hit_reaction.connect(_on_hit_reaction)
	_resolve()

func _process(delta: float) -> void:
	_drive_hit_flash(delta)
	_t += delta
	if _t < _RETRY_INTERVAL:
		return
	_t = 0.0
	_resolve()

## Couleur du flash de hit (GF-10) : blanc pour un coup normal, rouge pour un
## headshot — logique pure, testable sans arbre de scène (même esprit que
## `rim_color_for`/`outline_px_for`).
static func hit_flash_color(headshot: bool) -> Color:
	return _HIT_FLASH_HEADSHOT_COLOR if headshot else _HIT_FLASH_COLOR

func _on_hit_reaction(headshot: bool) -> void:
	if _mesh == null or not is_instance_valid(_mesh):
		return
	Cartoon.set_rim(_mesh, hit_flash_color(headshot), HIT_FLASH_STRENGTH)
	_flash_time_left = HIT_FLASH_DURATION_S

## Fait avancer le flash de hit en cours et restaure le rim de repos
## (allié/ennemi) dès que `HIT_FLASH_DURATION_S` est écoulé — jamais plus
## longtemps, quel que soit le nombre de coups reçus depuis (chaque nouveau
## `hit_reaction` relance simplement `_flash_time_left`, voir `_on_hit_reaction`).
func _drive_hit_flash(delta: float) -> void:
	if _flash_time_left <= 0.0:
		return
	_flash_time_left -= delta
	if _flash_time_left <= 0.0:
		_flash_time_left = 0.0
		_restore_rest_rim()

## Rim de repos une fois le flash terminé : même calcul que la fin de
## `_apply_character_materials` (allié -> rim de ciel, ennemi -> couleur
## ennemie à 0.6) — factorisé dans `_apply_rest_rim` pour éviter de dupliquer
## ces deux constantes à deux endroits.
func _restore_rest_rim() -> void:
	if _mesh == null or not is_instance_valid(_mesh) or _body == null:
		return
	var local_player := _find_local_player()
	if local_player == null:
		return
	_apply_rest_rim(_mesh, not is_ally(local_player.team, _body.team))

## Relation allié/ennemi purement logique (testable sans arbre de scène) :
## deux joueurs sont alliés s'ils partagent la même équipe.
static func is_ally(local_team: int, body_team: int) -> bool:
	return local_team == body_team

## Couleur de rim correspondante : allié => bleu fixe, ennemi => couleur
## choisie dans les options (Settings.enemy_color via Cartoon.enemy_color()).
static func rim_color_for(ally: bool) -> Color:
	return Cartoon.ally_color() if ally else Cartoon.enemy_color()

## Épaisseur de contour (px écran) : repère d'accessibilité indépendant de la
## couleur — l'ennemi a un contour 50% plus épais (design.md §12).
static func outline_px_for(ally: bool) -> float:
	return _OUTLINE_PX_ALLY if ally else _OUTLINE_PX_ALLY * _OUTLINE_PX_ENEMY_MULT

## Teinte du rim de ciel (STYLE_BIBLE.md v3 §4.5) : l'horizon de la carte en
## cours, lue via `Cartoon.map_palette` — même source que
## `Cartoon._current_shadow_tint()` (MatchConfig.map_id, ou la carte par
## défaut si vide/inconnue, jamais un dictionnaire vide).
static func sky_rim_color() -> Color:
	return Cartoon.map_palette(MatchConfig.map_id)["sky_horizon"]

func _resolve() -> void:
	if _body == null or not is_instance_valid(_body):
		return
	if _character_body == null or not _character_body.is_model_ready():
		return  # Le corps 3D (glb de l'agent) n'est pas encore chargé : on retentera.
	if _mesh == null:
		_mesh = _character_body.get_body_mesh()
		if _mesh:
			_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var local_player := _find_local_player()
	if local_player == null:
		return  # Le joueur local n'est pas encore dans l'arbre : on retentera.

	if local_player == _body:
		# Vue FPS : on ne rend pas son propre corps (la caméra est dedans).
		if _mesh:
			_mesh.visible = false
		return

	if _mesh == null:
		return
	var ally := is_ally(local_player.team, _body.team)
	# Resynchronisé à CHAQUE résolution (pas seulement au changement
	# allié/ennemi) : absorbe gratuitement un changement d'équipe (échange de
	# camp) OU un changement d'option daltonisme (Settings.enemy_color) en
	# cours de partie — même intention que l'ancien re-sync de rim.
	_apply_character_materials(_mesh, ally)

func _find_local_player() -> PlayerController:
	var players := get_tree().get_nodes_in_group("local_player")
	return players[0] as PlayerController if not players.is_empty() else null

## Corps = couleur d'équipe SATURÉE sur le slot "cloth" (design.md §5 :
## "joueurs en équipe") — outfit/gear/skin/accent gardent la couleur peinte
## du modèle (même convention que tools/character_shots.gd). `_body.team` ne
## porte pas de préfixe d'agent dans le nom du matériau (ex. "vif_cloth") :
## on matche par SUFFIXE, comme ThirdPersonWeapon.gd/ViewModel.gd.
##
## Agents Tripo riggés (tools/blender/rig_tripo_character.py, ex. Verrou) :
## UN SEUL matériau nommé `*_tex` (pas de slots outfit/cloth/gear/skin/accent
## — le maillage Tripo garde sa propre texture 2K bakée). Contrairement aux
## slots plats des agents "maison", ce matériau n'est JAMAIS repeint en aplat
## (la texture porte déjà tout le détail peint) : `_apply_textured_material`
## garde `albedo_texture` (même technique que
## `tools/review/model_preview.gd::_restyle`, l'aperçu qui a validé ce
## modèle) et coupe le grain peint de `Cartoon.character_surface`
## (`paint_grain_strength = 0`, sinon le grain simulerait un détail que la
## texture a déjà). Le contour d'équipe (`apply_team_outline` ci-dessous)
## reste la SEULE information d'équipe portée par un agent Tripo — pas de
## recoloration de matériau, faute d'un slot "cloth" dédié sur ce maillage.
func _apply_character_materials(mesh: MeshInstance3D, ally: bool) -> void:
	if mesh.mesh == null:
		return
	var cloth_color := rim_color_for(ally)
	for i in mesh.mesh.get_surface_count():
		var mat: Material = mesh.mesh.surface_get_material(i)
		var name: String = mat.resource_name if mat else ""
		if name.ends_with("_tex"):
			mesh.set_surface_override_material(i, _textured_character_material(mat))
			continue
		for slot in _SLOTS:
			if name.ends_with("_%s" % slot):
				var color: Color
				if slot == "cloth":
					color = cloth_color
				else:
					var src := mat as BaseMaterial3D
					color = src.albedo_color if src else Color.WHITE
				mesh.set_surface_override_material(i, Cartoon.character_surface(slot, color))
				break
	var is_enemy := not ally
	Cartoon.apply_team_outline(mesh, is_enemy)
	# design.md §5 "Enemies" : coque de surbrillance + "a matching fresnel rim
	# at 0.6" — Cartoon.apply_team_outline pose la coque, le rim reste à la
	# charge de l'appelant (voir sa docstring). Inchangé par ART-14.
	_apply_rest_rim(mesh, is_enemy)

## Rim "de repos" (hors flash de hit, GF-10) : ennemi -> couleur ennemie à 0.6
## (« matching fresnel rim at 0.6 », design.md §5), allié -> rim de ciel à
## `_RIM_STRENGTH_SKY` (STYLE_BIBLE.md v3 §4.5 "Rim de ciel" : un allié n'avait
## auparavant aucun rim — seulement l'encre qui s'amenuise avec la distance —
## la v3 ajoute un fresnel teinté de l'horizon de la carte, qui ne porte
## AUCUNE information d'équipe, contrairement au rim ennemi). Factorisé pour
## être appelé aussi bien à la résolution des matériaux qu'à la fin du flash
## de hit (`_restore_rest_rim`).
func _apply_rest_rim(mesh: MeshInstance3D, is_enemy: bool) -> void:
	if is_enemy:
		Cartoon.set_rim(mesh, Cartoon.enemy_color(), 0.6)
	else:
		Cartoon.set_rim(mesh, sky_rim_color(), _RIM_STRENGTH_SKY)

## Matériau texturé (`*_tex`, ex. "verrou_tex") : garde la texture d'albédo
## du modèle source au lieu de la repeindre en aplat — même technique que
## `tools/review/model_preview.gd::_restyle` (l'aperçu en jeu qui a validé ce
## modèle avant intégration). `paint_grain_strength` est forcé à 0 (contrat
## ART-11 : "sans grain peint, la texture porte déjà le détail" — le grain de
## `Cartoon.character_surface` simulerait un détail que Tripo a déjà peint
## dans la texture 2K). Le contour d'équipe est appliqué normalement par
## l'appelant (`apply_team_outline`), inchangé.
func _textured_character_material(src_mat: Material) -> ShaderMaterial:
	var m := Cartoon.character_surface(&"outfit", Color.WHITE)
	m.set_shader_parameter("paint_grain_strength", 0.0)
	var src := src_mat as BaseMaterial3D
	if src:
		m.set_shader_parameter("albedo_color", src.albedo_color)
		if src.albedo_texture != null:
			m.set_shader_parameter("use_albedo_texture", true)
			m.set_shader_parameter("use_triplanar", false)
			m.set_shader_parameter("albedo_texture", src.albedo_texture)
	return m
