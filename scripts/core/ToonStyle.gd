## ToonStyle.gd
## Style "BD façon Borderlands" (2026-09-26, « il faut tirer vraiment sur
## Borderlands ») -- SOURCE UNIQUE consommée : art/style/toon_style.json v2 (relu
## en entier avant toute valeur en dur ici -- ne JAMAIS recopier un nombre du JSON
## sans passer par ce chargeur, sinon les deux divergent silencieusement).
##
## Recherche lead (voir toon_style.json.references) : Borderlands N'EST PAS un
## cel-shading à bandes plates. Le look vient de quatre ingrédients (voir le champ
## JSON correspondant) :
##  1. textures peintes qui portent DÉJÀ l'encre (traits/hachures) -- baked par
##     art/style/blender/ink_bake.py, jamais généré par CE shader.
##  2. un contour NOIR FIN en post-traitement (Sobel profondeur+normales) --
##     `add_outline_pass`, assets/shaders/toon_bd_outline.gdshader.
##  3. un éclairage RÉEL à ombres affûtées (rampe resserrée, pas de paliers) --
##     `toon_material`, assets/shaders/toon_bd.gdshader.
##  4. des couleurs très saturées + un étalonnage -- `environment`/`setup_environment`.
##
## Portée de cette tranche (contrat lead, ne PAS étendre sans nouvelle demande) :
## Verrou (joueur + bots, scripts/player/PlayerLook.gd), l'arme Ravage + les gants
## viewmodel (scripts/player/ViewModel.gd -- seule arme de WeaponDatabase.PATHS
## aujourd'hui), et la carte Shipment (scenes/levels/maps/shipment.tscn +
## scripts/core/LevelLook.gd). Le reste du jeu (autres agents, Cartoon.gd,
## ink_toon.gdshader) N'EST PAS touché par cette tranche -- voir art/style/README.md
## "Portée" pour le détail de ce qui reste sur l'ancien pipeline et pourquoi.
class_name ToonStyle
extends RefCounted

const JSON_PATH := "res://art/style/toon_style.json"
const SHADER := preload("res://assets/shaders/toon_bd.gdshader")

const _OUTLINE_NODE_NAME := "ToonOutlineQuad"

static var _cache: Dictionary = {}

## JSON complet (mis en cache après le premier appel -- un seul `FileAccess` par
## process). Dictionnaire vide (jamais `null`) si le fichier est introuvable ou
## invalide : les appelants retombent alors sur les valeurs par défaut du shader
## lui-même (qui reproduisent le JSON v2 au moment de l'écriture, voir
## assets/shaders/toon_bd.gdshader) plutôt que de planter.
static func style() -> Dictionary:
	if _cache.is_empty():
		_cache = _load_style()
	return _cache

static func _load_style() -> Dictionary:
	if not FileAccess.file_exists(JSON_PATH):
		push_error("ToonStyle : introuvable (%s)" % JSON_PATH)
		return {}
	var f := FileAccess.open(JSON_PATH, FileAccess.READ)
	if f == null:
		push_error("ToonStyle : échec d'ouverture (%s)" % JSON_PATH)
		return {}
	var text := f.get_as_text()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ToonStyle : JSON invalide (%s)" % JSON_PATH)
		return {}
	return parsed

## Force un rechargement (tests, ou édition du JSON en cours de session éditeur --
## jamais nécessaire en jeu, le style ne change pas en cours de partie).
static func reload_style() -> Dictionary:
	_cache = {}
	return style()

static func _hex(value: String, fallback: Color = Color.WHITE) -> Color:
	if value.is_empty():
		return fallback
	return Color(value)

static func _section(name: StringName) -> Dictionary:
	var s := style()
	var v = s.get(name, {})
	return v if v is Dictionary else {}

# ---------------------------------------------------------------------------
#  Matériau (toon_bd.gdshader) -- ingrédients 3/4 (éclairage réel + rim/spéculaire).
# ---------------------------------------------------------------------------

## `albedo_tex` (nullable) : texture peinte conservée telle quelle (jamais
## retexturée) -- `color` reste une TEINTE multiplicative (blanc = neutre), jamais
## un remplacement de la texture. Sans texture, `color` est l'albédo plein (cas
## Shipment : blocs de couleur plate, voir `apply_to`).
static func toon_material(albedo_tex: Texture2D, color: Color = Color.WHITE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("albedo_color", color)
	if albedo_tex != null:
		m.set_shader_parameter("albedo_texture", albedo_tex)
		m.set_shader_parameter("use_albedo_texture", true)

	var shading := _section(&"shading")
	m.set_shader_parameter("wrap", shading.get("wrap", 0.1))
	m.set_shader_parameter("terminator", shading.get("terminator", 0.45))
	m.set_shader_parameter("sharpness", shading.get("sharpness", 0.12))
	m.set_shader_parameter("shadow_value", shading.get("shadow_value", 0.42))

	var tint := _section(&"shadow_tint")
	m.set_shader_parameter("shadow_hue_shift_deg", tint.get("hue_shift_deg", -18.0))
	m.set_shader_parameter("shadow_saturation_mult", tint.get("saturation_mult", 1.25))

	var rim := _section(&"rim")
	m.set_shader_parameter("rim_enabled", rim.get("enabled", true))
	m.set_shader_parameter("rim_power", rim.get("power", 4.0))
	m.set_shader_parameter("rim_threshold", rim.get("threshold", 0.55))
	m.set_shader_parameter("rim_softness", rim.get("softness", 0.08))
	m.set_shader_parameter("rim_intensity", rim.get("intensity", 0.25))
	m.set_shader_parameter("rim_tint", _hex(rim.get("color", "#FFE9B8")))
	m.set_shader_parameter("rim_lit_side_only", rim.get("lit_side_only", true))

	var spec := _section(&"specular")
	m.set_shader_parameter("specular_enabled", spec.get("enabled", true))
	m.set_shader_parameter("specular_size", spec.get("size", 0.18))
	m.set_shader_parameter("specular_softness", spec.get("softness", 0.12))
	m.set_shader_parameter("specular_intensity", spec.get("intensity", 0.25))
	m.set_shader_parameter("specular_tint", _hex(spec.get("color", "#FFFFFF")))

	var half := _section(&"halftone")
	m.set_shader_parameter("halftone_enabled", half.get("enabled", false))
	m.set_shader_parameter("halftone_cell_px", half.get("cell_px_at_1080p", 7.0))
	m.set_shader_parameter("halftone_angle_deg", half.get("angle_deg", 45.0))
	# Pas de `VIEWPORT_SIZE` dans ce contexte de fragment (voir toon_bd.gdshader) --
	# posé une fois ici (jamais mis à jour au redimensionnement, sans conséquence :
	# la trame est désactivée par défaut, jamais le contour post-process lui-même,
	# qui lui suit vraiment le viewport via ToonOutlineQuad._update_viewport_size).
	var window := DisplayServer.window_get_size()
	if window.x > 0 and window.y > 0:
		m.set_shader_parameter("viewport_size", Vector2(window))
	return m

## Texture + teinte déjà posées sur `material` (StandardMaterial3D importé d'un
## glTF peint, ou ShaderMaterial legacy -- dev_grid/ink_toon/ink_ground, qui
## portent tous un paramètre `albedo_color` et parfois `albedo_texture`, même
## convention de nom). `null`/blanc si rien d'exploitable -- jamais une erreur.
static func _extract_albedo(material: Material) -> Dictionary:
	if material is StandardMaterial3D:
		var std := material as StandardMaterial3D
		return {"texture": std.albedo_texture, "color": std.albedo_color}
	if material is ShaderMaterial:
		var sm := material as ShaderMaterial
		var tex = sm.get_shader_parameter("albedo_texture")
		var col = sm.get_shader_parameter("albedo_color")
		return {
			"texture": tex if tex is Texture2D else null,
			"color": col if col is Color else Color.WHITE,
		}
	return {"texture": null, "color": Color.WHITE}

## Parcourt `node` (récursif) et remplace le matériau de CHAQUE MeshInstance3D
## rencontré par un `toon_material` équivalent, en conservant la texture d'albédo
## et la teinte du matériau remplacé -- jamais la géométrie/les UV, jamais autre
## chose que le matériau. Couvre les deux formes rencontrées dans ce dépôt :
## `material_override` (géométrie procédurale, ex. les blocs de shipment.tscn) et
## matériau par surface (`mesh.surface_get_material`/`surface_override_material`,
## ex. un glTF Tripo comme verrou.glb/ravage.glb).
static func apply_to(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		_swap_mesh_materials(node as MeshInstance3D)
	for child in node.get_children():
		apply_to(child)

static func _swap_mesh_materials(mi: MeshInstance3D) -> void:
	if mi.material_override != null:
		var info := _extract_albedo(mi.material_override)
		mi.material_override = toon_material(info["texture"], info["color"])
		return
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var src: Material = mi.get_surface_override_material(i)
		if src == null:
			src = mi.mesh.surface_get_material(i)
		var info := _extract_albedo(src)
		mi.set_surface_override_material(i, toon_material(info["texture"], info["color"]))

# ---------------------------------------------------------------------------
#  Environnement + soleil -- ingrédients 3/4 (éclairage réel) et 4/4 (étalonnage).
# ---------------------------------------------------------------------------

## Environment autonome (testable sans arbre de scène) : ciel plat (JSON n'a pas
## de shader de ciel dédié -- v2 se concentre sur matériaux+contour, contrairement
## à l'ancien ink_sky v3), ambiance couleur, étalonnage saturation/contraste du
## JSON (`grading`) via `adjustment_*` -- volontairement PAS le tonemap Filmic
## (désaturerait les hautes lumières, contredirait "couleurs qui crient").
static func environment() -> Environment:
	var light := _section(&"light")
	var grading := _section(&"grading")
	var palette := _section(&"palette")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _hex(palette.get("sky_blue", "#6FB6FF"))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _hex(light.get("ambient_color", "#5A6FA8"))
	env.ambient_light_energy = light.get("ambient_strength", 0.35)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = grading.get("saturation", 1.25)
	env.adjustment_contrast = grading.get("contrast", 1.12)
	env.adjustment_brightness = 1.0
	env.glow_enabled = false
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.0
	env.ssao_power = 1.5
	return env

## Direction du soleil depuis azimut/élévation (même convention que
## LevelLook._sun_direction : azimut mesuré depuis +X monde, élévation au-dessus
## de l'horizon) -- dupliquée ici à dessein (art/style/toon_style.json est une
## source de vérité SÉPARÉE de docs/style/tokens.json, voir la doc de classe :
## cette tranche ne touche pas à l'ancien pipeline).
static func _sun_direction(elevation_deg: float, azimuth_deg: float) -> Vector3:
	var elev := deg_to_rad(elevation_deg)
	var az := deg_to_rad(azimuth_deg)
	var horiz := cos(elev)
	var vert := -sin(elev)
	return Vector3(horiz * cos(az), vert, horiz * sin(az)).normalized()

static func apply_sun(sun: DirectionalLight3D) -> void:
	if sun == null:
		return
	var light := _section(&"light")
	sun.light_color = _hex(light.get("sun_color", "#FFF1DC"))
	sun.light_energy = light.get("sun_energy", 1.2)
	sun.shadow_enabled = light.get("shadows", true)
	var dir := _sun_direction(light.get("sun_elevation_deg", 50.0), light.get("sun_azimuth_deg", 135.0))
	# `Vector3.ZERO`, jamais `sun.global_position` (LevelLook._apply_key_light,
	# même moteur/version, même doc) : `node_added` peut appeler ceci AVANT que
	# le nœud soit réellement `is_inside_tree()`, et `look_at_from_position` ne
	# regarde que la ROTATION du triplet donné -- la position n'a aucune
	# importance pour une lumière directionnelle, `global_position` échouerait
	# silencieusement (fallback identité) hors arbre pour rien.
	sun.look_at_from_position(Vector3.ZERO, dir, Vector3.UP)

## Point d'entrée combiné demandé par le contrat (`setup_environment(world_env,
## sun)`) -- les deux paramètres sont optionnels/nullables pour rester appelable
## partiellement (ex. tests, ou une scène sans soleil dédié).
static func setup_environment(world_env: WorldEnvironment, sun: DirectionalLight3D) -> void:
	if world_env != null:
		world_env.environment = environment()
	apply_sun(sun)

# ---------------------------------------------------------------------------
#  Contour post-traitement -- ingrédient 2/4 (assets/shaders/toon_bd_outline.gdshader).
# ---------------------------------------------------------------------------

static func outline_params() -> Dictionary:
	var o := _section(&"outline")
	return {
		"outline_color": _hex(o.get("color", "#0E0A12")),
		"width_px_at_1080p": float(o.get("width_px_at_1080p", 1.5)),
		"min_width_px": float(o.get("min_width_px", 1.0)),
		"depth_threshold": float(o.get("depth_threshold", 0.015)),
		"normal_threshold_deg": float(o.get("normal_threshold_deg", 30.0)),
		"fade_start_m": float(o.get("fade_start_m", 25.0)),
		"fade_end_m": float(o.get("fade_end_m", 70.0)),
	}

## Pose (ou retrouve, idempotent) le quad de contour comme enfant de `camera` --
## voir scripts/rendering/ToonOutlineQuad.gd pour la technique. Renvoie le nœud
## (rarement utile à l'appelant, surtout pratique pour les tests).
static func add_outline_pass(camera: Camera3D) -> ToonOutlineQuad:
	if camera == null:
		return null
	var existing := camera.get_node_or_null(_OUTLINE_NODE_NAME)
	var quad: ToonOutlineQuad = existing if existing is ToonOutlineQuad else null
	if quad == null:
		quad = ToonOutlineQuad.new()
		quad.name = _OUTLINE_NODE_NAME
		camera.add_child(quad)
	quad.configure(outline_params())
	return quad
