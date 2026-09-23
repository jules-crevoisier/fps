## Cartoon.gd
## Direction artistique v2 « Peint au soleil, encré gras » (.orchestrator/
## design.md) — remplace v1 « encre et papier » (rejetée : elle désaturait
## tout le décor). v2 garde le monde SATURÉ (rouille/sable/conteneurs sous un
## grand ciel bleu) et réserve la couleur à l'ennemi. L'encre vit désormais
## DANS les textures peintes (tools/textures/gen_textures.py bake les traits
## de couture/courbure) plutôt que dans une hachure procédurale — v1 avait
## une hachure + un grain papier, tous deux supprimés ici (design.md §3/§6).
##
## `Cartoon.mat()` reste l'ancien point d'entrée pour les appelants déjà en
## place (WorldWeapon.gd, MainMenu.gd) : signature inchangée. `world()`/
## `prop()`/`character()` gardent aussi leur forme d'appel v1 (couleur plate)
## pour tous les appelants existants (ArenaBuilder.gd, AbilityController.gd,
## ThirdPersonWeapon.gd, ViewModel.gd, TrainingDummy.gd, Kit.gd, …) — cette
## tranche n'a pas le droit de toucher ces fichiers. `Cartoon.painted(kind,
## tint)` est LA nouvelle capacité (surfaces triplanaires texturées, voir
## assets/shaders/ink_toon.gdshader) : ajoutée, rien retiré.
class_name Cartoon
extends RefCounted

## -- Jetons monde (design.md §4/§6) ----------------------------------------

## Contour à l'encre : brun chaud sombre, jamais noir pur.
const INK := Color("1a1410")
## Jetons hérités de v1, conservés car lus par des fichiers hors de cette
## tranche (ThirdPersonWeapon.gd/ViewModel.gd : "body" du viewmodel ;
## tools/character_shots.gd : sol de test) — recalés sur des neutres v2
## (Conteneurs « blanc/crème » #E6E1D6) plutôt que sur l'ancien papier crème,
## pour que ces appelants restent dans la nouvelle palette sans être modifiés
## ici.
const PAPER := Color("e6e1d6")
const PAPER_SHADE := Color("c9c2b2")
const GRAPHITE := Color("6e6558")
## Teinte d'ombre par défaut — famille bleu-violet (design.md §4 : « jamais
## gris »). Les préréglages par carte (voir `map_palette()`) la remplacent ;
## ceci est la valeur du préréglage par défaut/vaisseau-amiral.
const SHADOW_TINT := Color("5c6ea8")

## Teintes conteneurs (design.md §6 « Conteneurs ») pour
## `Cartoon.painted(&"container_paint", tint)`.
const CONTAINER_RED := Color("c8322b")
const CONTAINER_BLUE := Color("2f63b8")
const CONTAINER_ORANGE := Color("e3872a")
const CONTAINER_WHITE := Color("e6e1d6")

const _INK_TOON_SHADER := preload("res://assets/shaders/ink_toon.gdshader")
const _INK_OUTLINE_SHADER := preload("res://assets/shaders/ink_outline.gdshader")

## Métres par répétition de texture (triplanaire) — un panneau/conteneur
## typique fait ~2-3 m de large (design.md §6 : « Triplanar : terrain (4 m)
## et grandes structures (2 m) »). Un peu plus fin (3 m) pour rester correct
## sur les petits props texturés aussi.
const _TRIPLANAR_SCALE := 1.0 / 3.0
const _GRIME_SCALE := 1.0 / 1.6

# -- Bibliothèque de textures peintes (tools/textures/gen_textures.py) ------
const _TEX_PAINTED_METAL := preload("res://assets/textures/painted/painted_metal_albedo.png")
const _TEX_PAINTED_METAL_GRIME := preload("res://assets/textures/painted/painted_metal_grime.png")
const _TEX_RUST := preload("res://assets/textures/painted/rust_albedo.png")
const _TEX_CORRUGATED_METAL := preload("res://assets/textures/painted/corrugated_metal_albedo.png")
const _TEX_CORRUGATED_METAL_GRIME := preload("res://assets/textures/painted/corrugated_metal_grime.png")
const _TEX_CONTAINER_PAINT := preload("res://assets/textures/painted/container_paint_albedo.png")
const _TEX_CONTAINER_PAINT_GRIME := preload("res://assets/textures/painted/container_paint_grime.png")
const _TEX_WOOD_PLANKS := preload("res://assets/textures/painted/wood_planks_albedo.png")
const _TEX_WOOD_PLANKS_GRIME := preload("res://assets/textures/painted/wood_planks_grime.png")
const _TEX_SAND_DIRT := preload("res://assets/textures/painted/sand_dirt_albedo.png")
const _TEX_CRACKED_CONCRETE := preload("res://assets/textures/painted/cracked_concrete_albedo.png")
const _TEX_CRACKED_CONCRETE_GRIME := preload("res://assets/textures/painted/cracked_concrete_grime.png")
const _TEX_ASPHALT := preload("res://assets/textures/painted/asphalt_albedo.png")
const _TEX_SHIP_DECK := preload("res://assets/textures/painted/ship_deck_albedo.png")
const _TEX_SHIP_DECK_GRIME := preload("res://assets/textures/painted/ship_deck_grime.png")
const _TEX_RUBBER_TIRE := preload("res://assets/textures/painted/rubber_tire_albedo.png")
const _TEX_DIRTY_GLASS := preload("res://assets/textures/painted/dirty_glass_albedo.png")

## kind -> {albedo, grime|null}. Kinds match tools/textures/gen_textures.py's
## `MATERIALS` dict one-for-one.
const _PAINTED: Dictionary = {
	&"painted_metal": {"albedo": _TEX_PAINTED_METAL, "grime": _TEX_PAINTED_METAL_GRIME},
	&"rust": {"albedo": _TEX_RUST, "grime": null},
	&"corrugated_metal": {"albedo": _TEX_CORRUGATED_METAL, "grime": _TEX_CORRUGATED_METAL_GRIME},
	&"container_paint": {"albedo": _TEX_CONTAINER_PAINT, "grime": _TEX_CONTAINER_PAINT_GRIME},
	&"wood_planks": {"albedo": _TEX_WOOD_PLANKS, "grime": _TEX_WOOD_PLANKS_GRIME},
	&"sand_dirt": {"albedo": _TEX_SAND_DIRT, "grime": null},
	&"cracked_concrete": {"albedo": _TEX_CRACKED_CONCRETE, "grime": _TEX_CRACKED_CONCRETE_GRIME},
	&"asphalt": {"albedo": _TEX_ASPHALT, "grime": null},
	&"ship_deck": {"albedo": _TEX_SHIP_DECK, "grime": _TEX_SHIP_DECK_GRIME},
	&"rubber_tire": {"albedo": _TEX_RUBBER_TIRE, "grime": null},
	&"dirty_glass": {"albedo": _TEX_DIRTY_GLASS, "grime": null},
}

## -- Palettes par carte (design.md §7) --------------------------------------
## Une seule table (ici, pas dupliquée dans LevelLook.gd) : `world()`/
## `painted()` la consultent pour `shadow_tint`, LevelLook.gd pour le ciel/
## soleil/lumière. Clé = MatchConfig.map_id. "wasteland" et "cargo_ship" sont
## les cartes vaisseau-amiral (§7) : pas encore construites (aucun .tscn),
## la clé reste prête pour quand elles le seront. "" (aucune carte choisie —
## test_arena, comp_map, tdm_map, arènes, benchmark, menu principal) retombe
## sur Wasteland, la carte par défaut du thesis (§1).
const _MAP_PALETTES: Dictionary = {
	"wasteland": {
		# Darkened from design.md's raw §7 hex (#2F74D8/#BFDDF2): measured
		# against wasteland_hero.png (scratchpad/compare_regions.py, dev
		# target scene) the raw hex rendered far brighter in HSV "value" than
		# the reference's actual sky, which reads as a moody, fairly dark
		# mid-blue with sun-side contrast doing the work -- not a flat bright
		# fill. See LevelLook.build_environment()'s tonemap_exposure comment
		# for the other half of this fix.
		"sky_zenith": Color("265dad"), "sky_horizon": Color("a8c2d5"),
		"sun_color": Color("ffd99a"), "sun_elevation_deg": 32.0,
		"shadow_tint": Color("5b6ca6"),
	},
	"cargo_ship": {
		# Kept close to design.md's raw §7 hex (only lightly darkened, unlike
		# "wasteland"): measured against cargo_ship_hero.png (scratchpad/
		# compare_regions.py, target_cargo.tscn) its "late morning at sea"
		# sky reads notably BRIGHTER than Wasteland's (val 0.76 vs 0.51) --
		# a clear, high sky, not a moody one -- so the same global
		# tonemap_exposure cut needs less raw-colour compensation here.
		"sky_zenith": Color("4693ee"), "sky_horizon": Color("d8eefc"),
		"sun_color": Color("fff0c8"), "sun_elevation_deg": 45.0,
		"shadow_tint": Color("5a6ea8"),
	},
	"port_ferraille": {
		"sky_zenith": Color("4a8fe0"), "sky_horizon": Color("d6ecf6"),
		"sun_color": Color("fff1d0"), "sun_elevation_deg": 40.0,
		"shadow_tint": Color("5f71a8"),
	},
	"val_poussiere": {
		"sky_zenith": Color("3c7fd9"), "sky_horizon": Color("f2d7a8"),
		"sun_color": Color("ffc98a"), "sun_elevation_deg": 28.0,
		"shadow_tint": Color("6a63a0"),
	},
	"saint_ombre": {
		"sky_zenith": Color("3f6f86"), "sky_horizon": Color("f0b860"),
		"sun_color": Color("ffb870"), "sun_elevation_deg": 25.0,
		"shadow_tint": Color("3e4f7a"),
	},
	"col_du_vautour": {
		"sky_zenith": Color("1f63d0"), "sky_horizon": Color("cfe6f7"),
		"sun_color": Color("fff6e0"), "sun_elevation_deg": 42.0,
		"shadow_tint": Color("6c86c8"),
	},
	"la_fosse": {
		"sky_zenith": Color("3a80dc"), "sky_horizon": Color("d3e7f5"),
		"sun_color": Color("ffe0a6"), "sun_elevation_deg": 50.0,
		"shadow_tint": Color("6072ae"),
	},
	"le_belvedere": {
		"sky_zenith": Color("5a8fd8"), "sky_horizon": Color("ffd9a0"),
		"sun_color": Color("ffd3a0"), "sun_elevation_deg": 25.0,
		"shadow_tint": Color("5e6aa8"),
	},
}
const _DEFAULT_MAP_ID := "wasteland"

## Palette de la carte `map_id` (design.md §7), ou celle de la carte par
## défaut si `map_id` est vide/inconnu (jamais un dictionnaire vide : tous
## les appelants — Cartoon et LevelLook — peuvent indexer sans vérifier).
static func map_palette(map_id: String) -> Dictionary:
	if _MAP_PALETTES.has(map_id):
		return _MAP_PALETTES[map_id]
	return _MAP_PALETTES[_DEFAULT_MAP_ID]

## Couleur "allié" (design.md §11, jeton UI `ally`), fixe. Toujours
## accompagnée d'un indice de forme (●) dans le HUD — accessibilité
## daltonisme (design.md §9).
static func ally_color() -> Color:
	return Color("3b8bff")

## Couleur "ennemi", choisie par le joueur (Settings.enemy_color). design.md
## v2 §9 : 0 Magenta (défaut), 1 Citron — remplace le rouge/jaune/magenta de
## v1 (ces teintes retombaient dans les bandes désormais réservées au monde).
## Toute valeur hors {0, 1} (y compris l'ancien index 2, le temps que
## Settings.gd/OptionsMenu.gd soient mis à jour) retombe sur Magenta.
static func enemy_color() -> Color:
	match Settings.enemy_color:
		1:
			return Color("c8ff1f")  # citron
		_:
			return Color("ff3dc8")  # magenta (défaut)

## Matériau "monde" : décor, sol, murs — rampe peinte, pas de contour, rim à
## 0 (aucun halo). Teinte d'ombre tirée de la carte courante
## (MatchConfig.map_id) sauf si l'appelant la change ensuite.
static func world(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _INK_TOON_SHADER
	m.set_shader_parameter("albedo_color", color)
	m.set_shader_parameter("shadow_tint", _current_shadow_tint())
	return m

## Alias de noms de matériau -> kind canonique de `_PAINTED` (donc de
## tools/textures/gen_textures.py). SOURCE UNIQUE consultée par `painted()`
## ET `painted_for_slot()` : la bibliothèque de props (assets/models/props/**,
## manifest.json) nomme ses slots différemment (`corrugated`, `container`,
## `wood`, `sand`, `concrete`, `rubber`, `glass`, …) — les deux vocabulaires
## ne doivent jamais diverger. Chaque nom canonique s'alias aussi vers
## lui-même, pour que `painted()` accepte indifféremment l'un ou l'autre.
const _KIND_ALIASES: Dictionary = {
	&"painted_metal": &"painted_metal",
	&"rust": &"rust",
	&"corrugated": &"corrugated_metal",
	&"corrugated_metal": &"corrugated_metal",
	&"container": &"container_paint",
	&"container_paint": &"container_paint",
	&"wood": &"wood_planks",
	&"wood_planks": &"wood_planks",
	&"sand": &"sand_dirt",
	&"sand_dirt": &"sand_dirt",
	&"concrete": &"cracked_concrete",
	&"cracked_concrete": &"cracked_concrete",
	&"asphalt": &"asphalt",
	&"ship_deck": &"ship_deck",
	&"rubber": &"rubber_tire",
	&"rubber_tire": &"rubber_tire",
	&"glass": &"dirty_glass",
	&"dirty_glass": &"dirty_glass",
}

## Matériau "peint" : surface texturée (tools/textures/gen_textures.py),
## échantillonnée en triplanaire monde (aucun UV à poser à la main — les
## props/decors partagent la même texture sans couture). `tint` multiplie
## l'albédo échantillonné : `Color.WHITE` (défaut) rend la texture telle
## quelle, une teinte de conteneur (CONTAINER_RED, …) recolore le socle
## quasi neutre de `container_paint`. `kind` accepte le nom canonique OU
## l'alias de la bibliothèque de props (`_KIND_ALIASES`) ; un kind inconnu
## avertit et retombe sur `world(tint)` (comportement sûr, jamais un crash
## de niveau).
static func painted(kind: StringName, tint: Color = Color.WHITE) -> ShaderMaterial:
	var canonical: StringName = _KIND_ALIASES.get(kind, &"")
	var m := world(effective_tint(canonical, tint))
	var entry: Dictionary = _PAINTED.get(canonical, {})
	if entry.is_empty():
		push_warning("Cartoon.painted: kind peint inconnu \"%s\"" % kind)
		return m
	m.set_shader_parameter("use_albedo_texture", true)
	m.set_shader_parameter("albedo_texture", entry["albedo"])
	m.set_shader_parameter("use_triplanar", true)
	m.set_shader_parameter("triplanar_scale", _TRIPLANAR_SCALE)
	var grime: Texture2D = entry.get("grime")
	if grime != null:
		m.set_shader_parameter("use_grime_texture", true)
		m.set_shader_parameter("grime_texture", grime)
		m.set_shader_parameter("grime_scale", _GRIME_SCALE)
	return m

## Kinds dont la texture est un socle NEUTRE fait pour être recoloré (conteneurs,
## métal peint) : la teinte s'applique en entier.
const TINTABLE_KINDS: Array[StringName] = [&"container_paint", &"painted_metal"]
## Part de la teinte gardée sur les textures déjà colorées (sable, bois, rouille…).
const BAKED_TINT_INFLUENCE := 0.2

## Teinte réellement appliquée à une texture peinte. Les textures déjà
## colorées (sable ocre, planches brunes, rouille…) ne doivent pas être
## multipliées par une couleur de palette du même ton : la multiplication les
## assombrit deux fois (bug « Wasteland boueuse »). Elles ne gardent qu'un
## léger reflet de la teinte ; seuls les socles neutres (TINTABLE_KINDS) la
## prennent en entier.
static func effective_tint(canonical_kind: StringName, tint: Color) -> Color:
	if canonical_kind in TINTABLE_KINDS or canonical_kind == &"":
		return tint
	var t := Color.WHITE.lerp(tint, BAKED_TINT_INFLUENCE)
	t.a = tint.a
	return t

## Matériau pour UN slot nommé de la bibliothèque de props
## (assets/models/props/**, manifest.json) : accepte directement ses noms de
## slot (via le même alias table que `painted()`, `_KIND_ALIASES`), plus deux
## slots qui ne sont PAS des matériaux texturés :
##  - `accent` : painted_metal tintable (la couleur d'accent du prop).
##  - `sign`   : pas de texture — la couleur du panneau (texte/pictogramme)
##    doit rester EXACTE ; la multiplier sur une texture peinte la
##    dénaturerait, donc un matériau plat (`world(tint)`).
## Un slot inconnu qui n'est ni `accent` ni `sign` retombe sur `painted()`
## (donc sur son propre avertissement + repli `world(tint)`).
static func painted_for_slot(slot_name: String, tint: Color = Color.WHITE) -> Material:
	match slot_name:
		"sign":
			return world(tint)
		"accent":
			return painted(&"painted_metal", tint)
		_:
			return painted(StringName(slot_name), tint)

## Matériau "prop" : objets ramassables / décor interactif — même socle que
## `world()` + un contour d'encre plat (design.md §5 : « Viewmodel et
## pickups : 2 px d'encre », pas de falloff par distance).
static func prop(color: Color) -> ShaderMaterial:
	var m := world(color)
	m.next_pass = _outline_pass(INK, 2.0)
	return m

## Matériau "personnage" : joueurs, mannequins d'entraînement, armes visibles.
## Sans `highlight_color` (défaut, allié) : même socle qu'avant — un contour
## d'encre qui s'amenuise avec la distance (design.md §5 : 3 px jusqu'à 10 m,
## 2 px à 40 m, plancher 1.5 px). Avec `highlight_color` (ennemi) : coque
## teintée qui NE s'estompe jamais + une fine coque d'encre de 1 px juste à
## l'extérieur (design.md §5 « Enemies ») — le rim fresnel qui l'accompagne
## (« matching fresnel rim at 0.6 ») reste `Cartoon.set_rim(mesh, color,
## 0.6)`, déjà l'API existante, pas une nouvelle capacité ici.
static func character(color: Color, outline_px: float = 3.0, highlight_color: Color = Color(0.0, 0.0, 0.0, 0.0)) -> ShaderMaterial:
	var m := world(color)
	if highlight_color.a > 0.0:
		var highlight := _falloff_outline_pass(highlight_color, outline_px, outline_px * (2.5 / 3.5), outline_px * (2.5 / 3.5))
		highlight.next_pass = _falloff_outline_pass(INK, outline_px + 1.0, outline_px * (2.5 / 3.5) + 1.0, outline_px * (2.5 / 3.5) + 1.0)
		m.next_pass = highlight
	else:
		m.next_pass = _falloff_outline_pass(INK, outline_px, outline_px * (2.0 / 3.0), max(outline_px * (1.5 / 3.0), 1.0))
	return m

## Compat. : ancien point d'entrée. `_outline` est ignoré (les appelants
## historiques ne dessinaient déjà aucun contour dédié) ; renvoie le matériau
## monde à base de shader.
static func mat(color: Color, _outline: float = 0.0) -> Material:
	return world(color)

## Matériau de "slot" personnage (peau/tenue/tissu/équipement/accent) —
## teinte plate + un léger grain peint EN ESPACE OBJET (design.md §6
## « Detail: base noise <= ±6% ») : pas de triplanar monde ici, les
## personnages bougent et une texture plaquée en espace monde "nagerait" sur
## le maillage à chaque pas. `kind` module juste l'intensité du grain (le
## tissu/équipement en a un peu plus que la peau) ; un kind inconnu retombe
## sur une valeur médiane sûre.
const _CHARACTER_GRAIN: Dictionary = {
	&"skin": 0.02,
	&"cloth": 0.045,
	&"outfit": 0.045,
	&"gear": 0.06,
	&"accent": 0.03,
}
static func character_surface(kind: StringName, color: Color) -> ShaderMaterial:
	var m := world(color)
	m.set_shader_parameter("paint_grain_strength", _CHARACTER_GRAIN.get(kind, 0.04))
	return m

## Contour d'équipe complet posé en `next_pass` sur CHAQUE surface de `g` (un
## mannequin/personnage a souvent plusieurs surfaces — peau, tenue, équipement
## — chacune avec son propre matériau `character_surface()` ; un pass par
## surface, car l'extrusion "coque inversée" d'ink_outline.gdshader n'étend
## QUE la géométrie de SA surface). Fonctionne sur un maillage skinné
## (Skeleton3D) sans rien de spécial côté shader : Godot applique le skinning
## à VERTEX/NORMAL AVANT que vertex() ne s'exécute, donc l'extrusion voit
## déjà les sommets posés.
##
## Allié : contour d'encre qui s'amenuise avec la distance (comme
## `character()` sans `highlight_color` : 3 px à 10 m, 2 px à 40 m, plancher
## 1.5 px). Ennemi : coque de surbrillance (Cartoon.enemy_color(), suit
## Settings.enemy_color — Magenta/Citron) 3.5 px à 10 m -> plancher 2.5 px
## qui « ne s'efface jamais » (design.md §5), + une fine coque d'encre 1 px
## plus large qu'elle À CHAQUE distance (donc toujours juste à l'extérieur,
## pas seulement au plus près). Le rim fresnel assorti (« matching fresnel
## rim at 0.6 ») est `Cartoon.set_rim(g, enemy_color(), 0.6)` côté appelant —
## déjà l'API existante, pas dupliquée ici.
static func apply_team_outline(g: GeometryInstance3D, is_enemy: bool) -> void:
	var mi := g as MeshInstance3D
	if mi == null or not is_instance_valid(mi) or mi.mesh == null:
		return
	var next_pass := _team_outline_pass(is_enemy)
	for i in range(mi.mesh.get_surface_count()):
		var surface_mat: Material = mi.get_surface_override_material(i)
		if surface_mat == null:
			surface_mat = mi.mesh.surface_get_material(i)
		if surface_mat == null:
			continue
		surface_mat.next_pass = next_pass

static func _team_outline_pass(is_enemy: bool) -> ShaderMaterial:
	if is_enemy:
		var highlight := _falloff_outline_pass(enemy_color(), 3.5, 2.5, 2.5)
		highlight.next_pass = _falloff_outline_pass(INK, 4.5, 3.5, 3.5)
		return highlight
	return _falloff_outline_pass(INK, 3.0, 2.0, 1.5)

## Halo de reconnaissance (allié/ennemi) sur UNE instance de géométrie — ne
## touche jamais le matériau partagé : `rim_color`/`rim_strength` sont des
## "instance uniform" (une valeur par GeometryInstance3D, pas par Material),
## donc plusieurs joueurs peuvent partager le même ShaderMaterial character()
## tout en ayant chacun leur propre couleur de rim.
static func set_rim(g: GeometryInstance3D, color: Color, strength: float) -> void:
	if g == null or not is_instance_valid(g):
		return
	g.set_instance_shader_parameter("rim_color", color)
	g.set_instance_shader_parameter("rim_strength", strength)

static func _outline_pass(color: Color, width_px: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _INK_OUTLINE_SHADER
	m.set_shader_parameter("outline_color", color)
	m.set_shader_parameter("outline_width_px", width_px)
	return m

## Contour d'encre dont la largeur s'amenuise avec la distance caméra (voir
## ink_outline.gdshader `distance_falloff`) : `near_px` jusqu'à 10 m, puis
## approche de `far_px`/`floor_px` au-delà (les deux égaux => un plancher
## strict, jamais plus fin — c'est le « ne s'efface jamais » des ennemis).
static func _falloff_outline_pass(color: Color, near_px: float, far_px: float, floor_px: float) -> ShaderMaterial:
	var m := _outline_pass(color, near_px)
	m.set_shader_parameter("distance_falloff", true)
	m.set_shader_parameter("falloff_near_m", 10.0)
	m.set_shader_parameter("falloff_far_m", 40.0)
	m.set_shader_parameter("falloff_far_px", far_px)
	m.set_shader_parameter("falloff_floor_px", floor_px)
	return m

## Teinte d'ombre de la carte en cours (MatchConfig.map_id), ou celle de la
## carte par défaut. Lue en dépendance passive (comme LevelLook.gd) — jamais
## écrite ici.
static func _current_shadow_tint() -> Color:
	return map_palette(MatchConfig.map_id)["shadow_tint"]
