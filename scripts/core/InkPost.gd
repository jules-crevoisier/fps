## InkPost.gd
## Post-traitement plein écran "encre" (ink_edges.gdshader) : un quad qui
## recouvre tout l'écran en clip-space, attaché à la caméra LOCALE uniquement
## (PlayerCamera.gd l'instancie pour le joueur propriétaire seulement — les
## autres pairs n'ont pas ce coût). Bascule en direct sur `Settings.ink_edges`
## via un sondage basse fréquence (un réglage d'options n'a pas besoin d'une
## réaction à la frame près).
##
## Technique (Godot 4.7, doc "Advanced post-processing") : le quad est un
## enfant DIRECT de la caméra et son `extra_cull_margin` est mis au maximum,
## car le culling par AABB (CPU) ne sait pas que le vertex shader recouvre
## tout l'écran quelle que soit la transformation du nœud — sans ça, le quad
## disparaît dès que la caméra ne regarde plus vers son origine locale.
##
## IMPORTANT — un quad plein écran n'appartient PAS qu'à sa caméra parente :
## comme son vertex() écrit `POSITION` directement en clip-space (ignorant
## MODEL/VIEW), N'IMPORTE QUELLE autre Camera3D de la scène qui l'a dans son
## frustum (cull_mask par défaut = tous les calques, `extra_cull_margin` en
## plus) le RENDRA aussi, recouvrant alors TOUT SON écran du post-traitement
## voulu pour une autre caméra (repéré via tools/screenshot.gd : une caméra
## externe voyait le quad du joueur local et se retrouvait re-peinte).
## On se rend donc invisible dès qu'on n'est plus la caméra RÉELLEMENT active
## du viewport (`Viewport.get_camera_3d()`), pas seulement `Camera3D.current`.
##
## v3 (docs/STYLE_BIBLE.md §7.4, tâche ART-07) : le contour d'encre du décor
## (silhouette par profondeur + plis par normale — voir ink_edges.gdshader)
## prend sa couleur d'encre sur Cartoon.INK et sa teinte de brume lointaine
## sur la carte courante (Cartoon.map_palette(MatchConfig.map_id)
## ["sky_horizon"]) — le shader mélange les deux vers cette teinte au même
## rythme que le brouillard monde de LevelLook (§6.3/§7.4 : 40 → 150 m),
## rafraîchies au même sondage basse fréquence que `Settings.ink_edges`. Les
## largeurs/opacités de silhouette et les paramètres de pli (angle, largeur,
## fondu, opacité) restent des défauts du shader — ce script ne pilote QUE
## `enabled`/`ink_color`/`haze_color`, comme en v2.
class_name InkPost
extends MeshInstance3D

const _SHADER := preload("res://assets/shaders/ink_edges.gdshader")
const _POLL_INTERVAL := 0.5
const _MAX_CULL_MARGIN := 16384.0

var _mat: ShaderMaterial
var _poll_t: float = 0.0

func _ready() -> void:
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)  # VERTEX.xy in [-1, 1] -> couvre tout le clip-space.
	mesh = qm
	_mat = ShaderMaterial.new()
	_mat.shader = _SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = _MAX_CULL_MARGIN
	_apply_setting()

func _process(delta: float) -> void:
	# Chaque frame (pas seulement au sondage de Settings.ink_edges) : voir la
	# note ci-dessus, ceci doit rester réactif si une AUTRE caméra devient
	# active (ex. cet outil de capture, un futur mode spectateur/killcam).
	visible = get_viewport().get_camera_3d() == get_parent()
	_poll_t += delta
	if _poll_t < _POLL_INTERVAL:
		return
	_poll_t = 0.0
	_apply_setting()

func _apply_setting() -> void:
	if _mat:
		_mat.set_shader_parameter("enabled", Settings.ink_edges)
		_mat.set_shader_parameter("ink_color", Cartoon.INK)
		_mat.set_shader_parameter("haze_color", Cartoon.map_palette(MatchConfig.map_id)["sky_horizon"])
