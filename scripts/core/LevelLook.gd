## LevelLook.gd
## Autoload "Look" (la ligne d'autoload dans project.godot est ajoutée par la
## tranche audio R-E — ce script doit exister et fonctionner dès qu'elle est
## câblée). Restyle AUTOMATIQUEMENT tout WorldEnvironment qui entre dans
## l'arbre — chaque scène de niveau et le menu principal ont le leur — avec
## l'ambiance v2 « Peint au soleil, encré gras » (.orchestrator/design.md
## §4) : grand ciel bleu stylisé (ink_sky.gdshader), soleil chaud, ambiance
## fraîche + un soupçon de saturation, brouillard chaud léger, PAS de glow
## (le glow casserait l'aplat peint). Toute DirectionalLight3D qui entre dans
## l'arbre reçoit la direction/couleur du soleil de la carte courante (le
## décor statique a besoin de ses ombres portées : c'est ATTENUATION qui
## pilote la rampe à paliers d'ink_toon.gdshader).
##
## Préréglages PAR CARTE (design.md §7), sélectionnés par MatchConfig.map_id.
## La table elle-même vit dans Cartoon.map_palette() (une seule source pour
## le ciel ET la teinte d'ombre des matériaux, voir Cartoon.gd) — ce fichier
## ne fait que la CONSOMMER pour construire l'Environment/le ciel/la lumière.
##
## Tout est appliqué par CODE au runtime : aucune scène .tscn n'est modifiée,
## chaque builder de niveau garde sa propre géométrie/lumières/caméra.
class_name LevelLook
extends Node

const _SKY_SHADER := preload("res://assets/shaders/ink_sky.gdshader")

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		_style(node)
	elif node is DirectionalLight3D:
		_apply_key_light(node)

## Matériau de ciel peint — isolé en fonction statique pure (mêmes réglages à
## chaque appel pour une `map_id` donnée, aucun état) pour rester testable
## sans arbre de scène. `map_id` vide/inconnu retombe sur la carte par défaut
## (Cartoon.map_palette()).
static func build_sky_material(map_id: String = "") -> ShaderMaterial:
	var palette := Cartoon.map_palette(map_id)
	var m := ShaderMaterial.new()
	m.shader = _SKY_SHADER
	m.set_shader_parameter("sky_zenith_color", palette["sky_zenith"])
	m.set_shader_parameter("sky_horizon_color", palette["sky_horizon"])
	m.set_shader_parameter("sun_color", palette["sun_color"])
	# Below-horizon fallback (visible past a map's own terrain -- an open
	# edge, or any elevated/aerial view where real geometry doesn't reach
	# down to the sky dome's "ground" hemisphere): warm the horizon colour
	# toward dirt (design.md §6 "Grime" #6B5236) rather than a flat unrelated
	# grey. FIXED (lead review, real-map capture): darkening this by 55%
	# made it read ~0.35 in HSV value against a ~0.66-0.83 sky -- a gap wide
	# enough to show as an ugly dark RING right at the horizon in any
	# unobstructed/aerial view (reproduced with a bare Camera3D sweep: the
	# transition band was darker than both the sky above AND this fill
	# below it reads at the bottom of frame). Only a mild darken now, so the
	# horizon-to-ground transition stays a gentle warm fade.
	var horizon: Color = palette["sky_horizon"]
	m.set_shader_parameter("ground_color", horizon.darkened(0.15).lerp(Color("6b5236"), 0.25))
	return m

## Environment v2 : ciel peint par carte, ambiance fraîche depuis le ciel +
## un soupçon de saturation, tonemap filmique, brouillard chaud léger, pas de
## glow. `map_id` vide/inconnu retombe sur la carte par défaut.
static func build_environment(map_id: String = "") -> Environment:
	var palette := Cartoon.map_palette(map_id)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = build_sky_material(map_id)
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Zénith à 25% (design.md §4 « Ambient: zenith at 25% ») — le "+15% de
	# rebond sable" complémentaire n'est PAS ici : c'est une approximation
	# locale par surface (EMISSION sur les faces tournées vers le bas) dans
	# ink_toon.gdshader, pas un réglage global d'Environment.
	env.ambient_light_energy = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Godot's FILMIC tonemapper internally pre-multiplies by 2.0 before
	# compressing (docs, `tonemap_exposure`: "values ... multiplied by 2.0
	# ... for TONE_MAPPER_FILMIC ... to produce a similar apparent brightness
	# as TONE_MAPPER_LINEAR") -- left at the default 1.0 exposure, that blew
	# every region (sky/buildings/ground) 0.3-0.45 too bright in HSV value
	# against wasteland_hero.png (measured with scratchpad/compare_regions.py
	# — see the dev target scenes), crushing contrast and reading as a washed
	# grey-blue haze instead of a punchy sunlit frontier. Compensated here.
	env.tonemap_exposure = 0.42
	env.glow_enabled = false
	# Filmic/AgX (design.md §4) : Filmic retenu — AgX désature volontairement
	# les hautes lumières (c'est son but), ce qui va à l'encontre du thesis
	# « le monde reste fort » pour un ciel/sable déjà très saturés (vérifié
	# en jeu : AgX y lavait le bleu du ciel et l'orange du sable).
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.20
	env.adjustment_brightness = 1.0
	# Pulled back from 1.12 (lead review, real-map capture): adjustment_contrast
	# is applied to the FINAL pixel, after tonemap_exposure already cut
	# brightness hard (0.42) -- stacked on top of shadowed geometry (this
	# shader's own shadow floor, 45-60% of albedo) that combination crushed
	# darker level materials toward pure black instead of a readable cool
	# shadow. A gentler contrast still gives the ramp's hot edge some punch
	# without blocking up the shadows.
	env.adjustment_contrast = 1.04
	env.fog_enabled = true
	# Warmed toward the sun colour rather than the pale horizon blue on its
	# own -- a straight horizon-blue fog reads as a cool haze even at low
	# density ("no blue veil in the first 60 m" -- lead review). Distant
	# ink outlines (InkPost/Cartoon.map_palette) still tint toward the pure
	# horizon colour, so the two effects don't fight each other.
	env.fog_light_color = palette["sky_horizon"].lerp(palette["sun_color"], 0.4)
	# RECALIBRATED (lead review: "Cargo washed by fog/haze in aerial views" --
	# aerial/long views see 200-500+ m, and Godot 4's fog has no depth cap, so
	# a pure exponential tuned only for "30% at 120 m" keeps climbing toward
	# 100% well within normal sightlines: the old 0.002972 hit 59% at 300 m,
	# 77% at 500 m). Recalibrated for a genuine LIGHT haze even at distance --
	# amount(d) = 1 - exp(-k*d); target amount(150 m) = 0.20
	# => k = -ln(0.80)/150 ~= 0.001487. amount(35 m) ~= 0.05 (still no veil in
	# the first 60 m -- amount(60 m) ~= 0.085), amount(300 m) ~= 0.36,
	# amount(500 m) ~= 0.53 -- a light, slowly-building haze instead of a wall.
	env.fog_density = 0.001487
	env.fog_sun_scatter = 0.05
	# `fog_sky_affect` vaut 1.0 par défaut dans Godot : le brouillard obscurcit
	# alors le CIEL LUI-MÊME (rendu à une distance quasi infinie, donc le
	# fondu exponentiel y sature à 100 %), ce qui remplacerait tout le
	# dégradé/soleil/nuages d'ink_sky.gdshader par un aplat `fog_light_color`
	# (diagnostiqué en jeu sur la v1). Le brouillard ne doit voiler que le
	# DÉCOR, jamais le ciel lui-même.
	env.fog_sky_affect = 0.0
	env.ssao_enabled = true
	env.ssao_radius = 0.5
	env.ssao_intensity = 1.2
	env.ssao_power = 1.0
	return env

## Direction du soleil pour une élévation donnée (degrés au-dessus de
## l'horizon), azimut diagonal fixe (X=Z) pour qu'une boîte alignée aux axes
## montre 3 faces à 3 tons distincts (retour DA v1, toujours valable). Une
## DIRECTION (via `look_at`) plutôt que des `rotation_degrees` : l'ordre des
## angles d'Euler de Godot (YXZ) rend l'angle réellement obtenu imprévisible
## par le calcul à la main (mesuré en jeu sur v1).
static func _sun_direction(elevation_deg: float) -> Vector3:
	var elev := deg_to_rad(elevation_deg)
	var horiz := cos(elev)
	var vert := -sin(elev)
	return Vector3(horiz * 0.70711, vert, horiz * 0.70711).normalized()

func _apply_key_light(light: DirectionalLight3D) -> void:
	var palette := Cartoon.map_palette(MatchConfig.map_id)
	light.shadow_enabled = true
	light.light_color = palette["sun_color"]
	# `look_at` exige que le nœud soit déjà dans l'arbre (global_position) ;
	# `node_added` peut arriver avant ça. `look_at_from_position` n'a pas
	# cette contrainte (seule la ROTATION compte pour une lumière
	# directionnelle, la position ne sert à rien) et fonctionne dans les
	# deux cas.
	light.look_at_from_position(Vector3.ZERO, _sun_direction(palette["sun_elevation_deg"]), Vector3.UP)

func _style(we: WorldEnvironment) -> void:
	we.environment = build_environment(MatchConfig.map_id)
	var parent := we.get_parent()
	if parent == null:
		return
	for sibling in parent.get_children():
		if sibling is DirectionalLight3D:
			_apply_key_light(sibling)
