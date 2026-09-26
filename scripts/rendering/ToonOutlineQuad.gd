## ToonOutlineQuad.gd
## Contour post-traitement plein écran (art/style/toon_style.json v2 "outline") --
## voir assets/shaders/toon_bd_outline.gdshader pour la technique ("Full screen
## quad", Godot 4.7 docs "Advanced post-processing") et le choix vs CompositorEffect
## (art/style/README.md). Posé par `ToonStyle.add_outline_pass(camera)` : CE nœud
## est un `MeshInstance3D` enfant direct de la `Camera3D` visée, jamais instancié
## à la main ailleurs.
##
## Le vertex shader court-circuite la transformation standard
## (`POSITION = vec4(VERTEX.xy, 1.0, 1.0)`) pour couvrir tout l'écran en espace
## clip -- son AABB réel (calculé par Godot à partir du VRAI transform local, qui
## ignore ce court-circuit) ne correspond donc à RIEN d'utile pour le frustum
## culling CPU : `custom_aabb` est mis à une boîte énorme (doc Godot 4.7,
## `GeometryInstance3D.custom_aabb` : "especially useful to avoid unexpected
## culling when using a shader to offset vertices" -- exactement ce cas) pour
## qu'il ne disparaisse jamais par erreur.
class_name ToonOutlineQuad
extends MeshInstance3D

const _SHADER := preload("res://assets/shaders/toon_bd_outline.gdshader")
## Assez grande pour ne jamais être culled (position/échelle locale réelles n'ont
## aucune importance, voir la doc de la classe), assez petite pour rester dans les
## limites d'un AABB simple (float32).
const _HUGE := 1.0e6

var _material: ShaderMaterial

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)  # VERTEX.xy doit couvrir -1..1 (voir le shader).
	mesh = quad
	_material = ShaderMaterial.new()
	_material.shader = _SHADER
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-_HUGE, -_HUGE, -_HUGE), Vector3.ONE * _HUGE * 2.0)
	extra_cull_margin = 16384.0
	# Ordre d'ajout à l'arbre non garanti par rapport à Viewport._ready -- get_viewport()
	# est néanmoins toujours valide ici (CE nœud est déjà entré dans l'arbre pour que
	# _ready() tourne, donc son Viewport existe).
	get_viewport().size_changed.connect(_update_viewport_size)
	_update_viewport_size()

func _exit_tree() -> void:
	var vp := get_viewport()
	if vp and vp.size_changed.is_connected(_update_viewport_size):
		vp.size_changed.disconnect(_update_viewport_size)

func _update_viewport_size() -> void:
	if _material == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	_material.set_shader_parameter("viewport_size", Vector2(vp.get_visible_rect().size))

## Pousse les paramètres du contour (art/style/toon_style.json "outline", voir
## ToonStyle.gd) sur le matériau -- clés = noms des `uniform` du shader.
func configure(params: Dictionary) -> void:
	if _material == null:
		return
	for key in params.keys():
		_material.set_shader_parameter(key, params[key])
