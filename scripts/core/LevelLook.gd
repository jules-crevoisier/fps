## LevelLook.gd
## Autoload "Look" (la ligne d'autoload dans project.godot est ajoutée par la
## tranche audio R-E — ce script doit exister et fonctionner dès qu'elle est
## câblée). Restyle AUTOMATIQUEMENT tout WorldEnvironment qui entre dans
## l'arbre — chaque scène de niveau et le menu principal ont le leur — avec
## l'ambiance v3 « Bric-à-brac peint » (docs/STYLE_BIBLE.md §7.5) : ciel
## stylisé PAR CARTE (ink_sky.gdshader), soleil chaud, tonemap **LINÉAIRE**
## WYSIWYG (aucune compression/désaturation de post — l'albédo peint EST la
## couleur, voir §7.1 « Règle d'or »), brouillard chaud léger, contacts SSAO
## doux, PAS de glow (le glow casserait l'aplat peint). Toute DirectionalLight3D
## qui entre dans l'arbre reçoit la direction/couleur du soleil de la carte
## courante ainsi que sa configuration d'ombre (portée, PSSM, pénombre) — le
## décor statique a besoin de ses ombres portées : c'est ATTENUATION qui
## pilote la rampe à paliers d'ink_toon.gdshader.
##
## Préréglages PAR CARTE (§6.4/§7.7), sélectionnés par MatchConfig.map_id. La
## table elle-même vit dans Cartoon.map_palette() (une seule source pour le
## ciel ET la teinte d'ombre des matériaux, voir Cartoon.gd) — ce fichier ne
## fait que la CONSOMMER pour construire l'Environment/le ciel/la lumière.
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

## Environment v3 : ciel peint par carte, tonemap **linéaire WYSIWYG**
## (docs/STYLE_BIBLE.md §7.5 — remplace le filmique compressé + exposition
## assombrie de la v2, qui rendait les hex d'albédo illisibles : « les hex ne
## voulaient plus rien dire »), ambiance calibrée par `tools/look_probe.gd`
## (ART-01), brouillard chaud léger, contacts SSAO doux, pas de glow.
## `map_id` vide/inconnu retombe sur la carte par défaut.
static func build_environment(map_id: String = "") -> Environment:
	var palette := Cartoon.map_palette(map_id)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = build_sky_material(map_id)
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# §7.5 : 0,25 → 0,18. Calibré à la sonde (`tools/look_probe.gd`, ART-01) :
	# la face au soleil d'un cube albédo #D2A46C doit lire une L OKLab de
	# 0,75 ± 0,03 (CHK-01) une fois le tonemap linéaire appliqué ci-dessous.
	env.ambient_light_energy = 0.18
	# §7.5 : LINEAR remplace FILMIC. Le filmique compressait les hautes
	# lumières PUIS l'exposition à 0,42 assombrissait tout pour compenser --
	# la chaîne perdait alors toute correspondance directe albédo -> pixel
	# affiché (le but même de la sonde CHK-01). LINEAR + exposition 1,0 :
	# ce qui sort de l'albédo est ce qui s'affiche.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = false
	# §7.5 : adjustment_enabled → false par défaut (7 des 8 cartes). La
	# saturation/contraste de post (v2 : 1,20 / 1,04) cassait justement le
	# WYSIWYG que ce tonemap linéaire vise à garantir -- la saturation se
	# règle dans l'ALBÉDO (gen_textures.py, tokens.json), jamais en
	# post-traitement global. Exception ART-86 (Wasteland seule, étalonnage
	# courbe/saturation demandé par ce contrat) : voir le bloc `adjustment_*`
	# plus bas, qui règle la valeur définitive pour cette carte.
	env.fog_enabled = true
	# Warmed toward the sun colour rather than the pale horizon blue on its
	# own -- a straight horizon-blue fog reads as a cool haze even at low
	# density ("no blue veil in the first 60 m" -- lead review). Distant
	# ink outlines (InkPost/Cartoon.map_palette) still tint toward the pure
	# horizon colour, so the two effects don't fight each other.
	#
	# ART-86 : Wasteland seule reçoit un brouillard PAR CARTE (teinte, densité
	# de profondeur ET brouillard de hauteur) -- voir le commentaire de tête
	# de `WastelandLook` (ART-86) pour le calcul de chaque valeur. Comparaison
	# STRICTE sur `"wasteland"` (pas le repli `Cartoon.map_palette` sur chaîne
	# vide) : `tests/rendering/test_level_look.gd` verrouille les valeurs
	# PARTAGÉES ci-dessous sur l'appel à `map_id` vide, qui doit donc rester
	# sur cette branche `else`.
	if map_id == "wasteland":
		env.fog_light_color = WastelandLook.FOG_TINT_OCRE
		env.fog_density = WastelandLook.FOG_DENSITY
		env.fog_height = WastelandLook.FOG_HEIGHT_M
		env.fog_height_density = WastelandLook.FOG_HEIGHT_DENSITY
	else:
		env.fog_light_color = palette["sky_horizon"].lerp(palette["sun_color"], 0.4)
		# RECALIBRATED (lead review: "Cargo washed by fog/haze in aerial views"
		# -- aerial/long views see 200-500+ m, and Godot 4's fog has no depth
		# cap, so a pure exponential tuned only for "30% at 120 m" keeps
		# climbing toward 100% well within normal sightlines: the old 0.002972
		# hit 59% at 300 m, 77% at 500 m). Recalibrated for a genuine LIGHT
		# haze even at distance -- amount(d) = 1 - exp(-k*d);
		# target amount(150 m) = 0.20 => k = -ln(0.80)/150 ~= 0.001487.
		# amount(35 m) ~= 0.05 (still no veil in the first 60 m --
		# amount(60 m) ~= 0.085), amount(300 m) ~= 0.36, amount(500 m) ~= 0.53
		# -- a light, slowly-building haze instead of a wall.
		env.fog_density = 0.001487
		# `fog_height_density` par défaut à 0,0 dans Godot 4.7 (voir la doc de
		# la propriété) : aucun brouillard de hauteur tant qu'on ne le règle
		# pas -- les 7 autres cartes gardent donc ce comportement inchangé.
		env.fog_height = 0.0
		env.fog_height_density = 0.0
	env.fog_sun_scatter = 0.05
	# `fog_sky_affect` vaut 1.0 par défaut dans Godot : le brouillard obscurcit
	# alors le CIEL LUI-MÊME (rendu à une distance quasi infinie, donc le
	# fondu exponentiel y sature à 100 %), ce qui remplacerait tout le
	# dégradé/soleil/nuages d'ink_sky.gdshader par un aplat `fog_light_color`
	# (diagnostiqué en jeu sur la v1). Le brouillard ne doit voiler que le
	# DÉCOR, jamais le ciel lui-même.
	env.fog_sky_affect = 0.0
	# §7.5 : 0,5/1,2/1,0 → 0,8/1,0/1,5 -- contacts plus doux (rayon large,
	# intensité réduite) mais plus nets (puissance/gamma plus haute resserre
	# l'occlusion près des contacts réels). `ssao_light_affect` (0 → 0,15,
	# nouveau) : un peu d'occlusion visible même en plein soleil, pour que les
	# contacts au sol ne disparaissent pas sous la lumière directe.
	#
	# ART-86 : Wasteland reçoit un contact SSAO un peu plus marqué (voir
	# `WastelandLook`, ART-86) pour ancrer les props au sol -- delta modeste,
	# reste « léger » au sens de la bible. Même garde stricte que le
	# brouillard ci-dessus.
	env.ssao_enabled = true
	if map_id == "wasteland":
		env.ssao_radius = WastelandLook.SSAO_RADIUS
		env.ssao_intensity = WastelandLook.SSAO_INTENSITY
		env.ssao_power = WastelandLook.SSAO_POWER
		env.ssao_light_affect = WastelandLook.SSAO_LIGHT_AFFECT
	else:
		env.ssao_radius = 0.8
		env.ssao_intensity = 1.0
		env.ssao_power = 1.5
		env.ssao_light_affect = 0.15
	# ART-86 : étalonnage courbe/saturation demandé pour Wasteland seule (voir
	# `WastelandLook`, ART-86) -- volontairement modeste pour rester
	# compatible avec l'encre. Les 7 autres cartes gardent `adjustment_enabled
	# = false` (règle d'or WYSIWYG §7.5, verrouillée par
	# `test_environment_has_no_post_color_adjustment` sur l'appel à `map_id`
	# vide).
	if map_id == "wasteland":
		env.adjustment_enabled = true
		env.adjustment_saturation = WastelandLook.ADJUSTMENT_SATURATION
		env.adjustment_contrast = WastelandLook.ADJUSTMENT_CONTRAST
		env.adjustment_brightness = 1.0
	else:
		env.adjustment_enabled = false
	return env

## Azimut horizontal (degrés, mesuré depuis l'axe +X du monde) de la
## direction HORIZONTALE des rayons du soleil. 45.0 reproduit EXACTEMENT
## l'ancien azimut diagonal fixe (X=Z, "une boîte alignée aux axes montre 3
## faces à 3 tons distincts", retour DA v1) commun aux 8 cartes — toujours
## la valeur pour les 7 cartes autres que Wasteland (tests/rendering/
## test_level_look.gd::test_sun_direction_at_45_degrees_matches_v1_reference_vector).
## Seule Wasteland reçoit un azimut PROPRE À LA CARTE (ART-70,
## docs/research/09_wasteland_vertical_slice.md §b.2 V12/§d.6) : ses lanes
## principales suivent l'axe +X (spawns à x=±36,5..38,5), donc cet azimut se
## lit DIRECTEMENT comme l'angle avec les lanes, sans conversion — 70,0°,
## au milieu de la fourchette exigée par ce contrat et par
## `docs/style/tokens.json` (`shader.sun.azimuth_to_main_lanes_deg`:
## [60, 90]), reprend la valeur calibrée par la recherche ("il fait 70° avec
## les lanes est-ouest : aucune équipe ne sort de spawn à contre-jour").
const _SUN_AZIMUTH_DEG_DEFAULT := 45.0
const _SUN_AZIMUTH_DEG_WASTELAND := 70.0

## Même repli que `Cartoon.map_palette()` (StyleTokens.MAP_PALETTES/
## DEFAULT_MAP_ID) : un `map_id` vide ou inconnu (menu principal, arènes,
## tests) retombe sur Wasteland, la carte par défaut du thesis — l'azimut
## doit suivre EXACTEMENT le même repli que le ciel/soleil/sol déjà lus
## depuis cette carte (sans quoi un `map_id` vide afficherait la couleur/
## hauteur de soleil de Wasteland avec l'azimut diagonal d'une autre carte).
static func _sun_azimuth_deg(map_id: String) -> float:
	var effective := map_id if StyleTokens.MAP_PALETTES.has(map_id) else StyleTokens.DEFAULT_MAP_ID
	return _SUN_AZIMUTH_DEG_WASTELAND if effective == "wasteland" else _SUN_AZIMUTH_DEG_DEFAULT

## Direction du soleil pour une élévation et un azimut donnés (`azimuth_deg`
## par défaut : ancien azimut diagonal commun aux 8 cartes, voir la
## constante ci-dessus). Une DIRECTION (via `look_at`) plutôt que des
## `rotation_degrees` : l'ordre des angles d'Euler de Godot (YXZ) rend
## l'angle réellement obtenu imprévisible par le calcul à la main (mesuré en
## jeu sur v1).
static func _sun_direction(elevation_deg: float, azimuth_deg: float = _SUN_AZIMUTH_DEG_DEFAULT) -> Vector3:
	var elev := deg_to_rad(elevation_deg)
	var az := deg_to_rad(azimuth_deg)
	var horiz := cos(elev)
	var vert := -sin(elev)
	return Vector3(horiz * cos(az), vert, horiz * sin(az)).normalized()

func _apply_key_light(light: DirectionalLight3D) -> void:
	var map_id := MatchConfig.map_id
	var palette := Cartoon.map_palette(map_id)
	light.shadow_enabled = true
	light.light_color = palette["sun_color"]
	# §7.5 : ombres nettes (pénombre PCSS modérée) sur la portée de jeu --
	# `light_angular_distance` 0 → 0,5 (un léger adoucissement selon la
	# distance à l'occludeur, pas un flou géant), `directional_shadow_max_distance`
	# (défaut moteur 100 m) → 120 m, `directional_shadow_mode` explicite à
	# PSSM 4 (SHADOW_PARALLEL_4_SPLITS -- déjà la valeur par défaut du moteur,
	# fixée ici pour que le réglage soit une source de vérité plutôt qu'un
	# défaut implicite).
	#
	# ART-86 : Wasteland reçoit une pénombre plus fine (ombres plus franches,
	# voir `WastelandLook`, ART-86) -- `directional_shadow_max_distance`/
	# `directional_shadow_mode` restent la constante moteur partagée (hors
	# périmètre). Comparaison STRICTE sur `"wasteland"` (pas le repli de
	# `_sun_azimuth_deg`/`Cartoon.map_palette` sur chaîne vide) :
	# `tests/rendering/test_level_look.gd::test_key_light_matches_style_bible_shadow_table`
	# verrouille `light_angular_distance == 0,5` sur l'appel à `MatchConfig.map_id`
	# vide (défaut des tests), qui doit donc rester sur la branche partagée.
	light.light_angular_distance = WastelandLook.SHADOW_ANGULAR_DISTANCE if map_id == "wasteland" else 0.5
	light.directional_shadow_max_distance = 120.0
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# ART-86 : soleil plus rasant pour Wasteland seule (voir `WastelandLook`,
	# ART-86) -- remplace `palette["sun_elevation_deg"]` (32°, StyleTokens.gd,
	# hors périmètre) par une élévation plus basse pour cette carte
	# uniquement. Même garde stricte que ci-dessus.
	var elevation_deg: float = WastelandLook.SUN_ELEVATION_DEG if map_id == "wasteland" else palette["sun_elevation_deg"]
	# `look_at` exige que le nœud soit déjà dans l'arbre (global_position) ;
	# `node_added` peut arriver avant ça. `look_at_from_position` n'a pas
	# cette contrainte (seule la ROTATION compte pour une lumière
	# directionnelle, la position ne sert à rien) et fonctionne dans les
	# deux cas.
	light.look_at_from_position(Vector3.ZERO, _sun_direction(elevation_deg, _sun_azimuth_deg(map_id)), Vector3.UP)

func _style(we: WorldEnvironment) -> void:
	we.environment = build_environment(MatchConfig.map_id)
	var parent := we.get_parent()
	if parent == null:
		return
	for sibling in parent.get_children():
		if sibling is DirectionalLight3D:
			_apply_key_light(sibling)
	_add_backdrop(parent)

## Coulisses d'horizon (STYLE_BIBLE.md SS6.3, tâche ART-06,
## scripts/levels/Backdrop.gd) : un anneau de silhouettes par thème de
## carte, posé en enfant du même parent que le WorldEnvironment -- même
## logique "tout par CODE, aucune scène .tscn modifiée" que le reste de ce
## fichier. Gardé par nom ("Backdrop") : un `node_added` répété sur la même
## scène (ex. `_on_node_added` ré-appelé si une DirectionalLight3D entre
## APRÈS le WorldEnvironment, ce qui redéclenche `_style` -- non, seul
## WorldEnvironment appelle `_style` ; ce garde-fou couvre plutôt le cas
## d'un test qui appelle `_style`/`_on_node_added` deux fois sur le même
## arbre) ne pose jamais deux anneaux l'un sur l'autre.
##
## FIXED (relance QA, map_shots sur les 8 cartes) : `add_child` immédiat ici
## levait « Parent node is busy setting up children, `add_child()` failed »
## sur toutes les cartes -- `_add_backdrop` est appelé depuis `_on_node_added`,
## câblé sur `node_added`, qui se déclenche PENDANT que Godot instancie et
## attache les enfants d'une scène (le parent est alors "occupé"), donc AVANT
## que ce parent accepte un `add_child` synchrone. `call_deferred` retarde
## l'ajout à la prochaine idle frame, quand l'arbre n'est plus en cours de
## montage -- l'anneau n'était jusqu'ici JAMAIS posé (vérifié sur les 8
## map_shots). Puisque le nœud "Backdrop" n'existe pas encore entre l'appel et
## cette idle frame, `parent.has_node("Backdrop")` ne suffit plus comme garde
## anti-doublon (un second appel sur le même parent avant que le premier ajout
## différé s'exécute verrait encore `has_node` renvoyer faux) : on mémorise
## donc l'intention dès l'appel via une métadonnée sur le parent lui-même
## (même garde `has_meta`/`set_meta` que UiFx.gd `_uifx_press_wired` --
## rappelé plusieurs fois sur le même nœud), qui meurt avec le parent, sans
## état à nettoyer côté LevelLook.
const _BACKDROP_PENDING_META := "_backdrop_pending"

func _add_backdrop(parent: Node) -> void:
	if parent.has_node("Backdrop") or parent.has_meta(_BACKDROP_PENDING_META):
		return
	parent.set_meta(_BACKDROP_PENDING_META, true)
	parent.add_child.call_deferred(Backdrop.build(MatchConfig.map_id))
