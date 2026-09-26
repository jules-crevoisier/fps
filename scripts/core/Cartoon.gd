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
## tint)` (terrain, triplanaire monde) et `Cartoon.prop_uv(kind, tint)`
## (props/décor Blender, UV posée à la main — STYLE_BIBLE.md v3 §7.7, tâche
## ART-05) sont les fabriques de surfaces texturées : ajoutées, rien retiré.
##
## v3 (STYLE_BIBLE.md, tâche ART-05) : `_MAP_PALETTES` est désormais GÉNÉRÉE
## (`StyleTokens.gd`, depuis `docs/style/tokens.json`, voir sa section
## dédiée plus bas) — plus aucun hex de carte recopié/retouché à la main
## ici. `_CHARACTER_GRAIN` passe à 0 partout (§4.2 « aucun grain », CHK-27).
## `INK`, `ally_color()` et `enemy_color()` sont inchangés par cette tranche.
##
## ART-04B (2026-09-24) : les 17 `preload()` de la bibliothèque de textures
## peintes (juste plus bas) pointaient encore vers leurs noms v2
## (`<kind>_albedo.png`/`<kind>_grime.png`) alors que `tools/textures/
## gen_textures.py` v3 ne les régénérait plus que comme un pont de
## compatibilité temporaire — supprimer ce pont sans d'abord repointer ces
## `preload()` (résolus au PARSE, pas à l'exécution) aurait cassé le chargement
## de tout le projet. Repointés vers `material_<kind>_*.png` (mêmes 11 kinds,
## mêmes 6 grimes, même contenu v3 sans encre — voir le commentaire de la
## bibliothèque plus bas) ; `PAINTED_MATERIALS`/`_remove_stale_v2_outputs()`
## dans gen_textures.py suppriment maintenant les 17 anciens fichiers.
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
## Wasteland v7 greybox (2026-09-26, "carte block jouable") : grille
## triplanaire monde, jamais de texture peinte — voir `dev_grid()` plus bas.
const _DEV_GRID_SHADER := preload("res://assets/shaders/dev_grid.gdshader")

## Mètres par répétition de texture (triplanaire, terrain SEULEMENT — §7.2/
## §7.7 : « triplanar_scale : 1/3 → 1/4 (1 répétition / 4 m), pour le terrain
## seulement » ; les props peints passent par `prop_uv()`, en UV Blender, sans
## triplanaire).
const _TRIPLANAR_SCALE := 1.0 / 4.0
const _GRIME_SCALE := 1.0 / 1.6

# -- Bibliothèque de textures peintes (tools/textures/gen_textures.py,
# `PAINTED_MATERIALS`) ------------------------------------------------------
## ART-04B (2026-09-24) : ces 17 fichiers s'appelaient `<kind>_albedo.png` /
## `<kind>_grime.png` (noms v2) ; gen_textures.py v3 les régénérait déjà sans
## encre sous ces mêmes noms, uniquement pour que CES `preload()` (résolus au
## PARSE de ce fichier par Godot 4) ne cassent pas — les vrais fichiers v2
## avaient déjà disparu. Renommés ici en `material_<kind>_*.png` pour que
## gen_textures.py puisse enfin supprimer ce pont de compatibilité (voir son
## `PAINTED_MATERIALS` / `_remove_stale_v2_outputs()`) : `grep "textures/
## painted/" scripts/` ne doit plus renvoyer aucun des 17 noms v2.
const _TEX_PAINTED_METAL := preload("res://assets/textures/painted/material_painted_metal_albedo.png")
const _TEX_PAINTED_METAL_GRIME := preload("res://assets/textures/painted/material_painted_metal_grime.png")
const _TEX_RUST := preload("res://assets/textures/painted/material_rust_albedo.png")
const _TEX_CORRUGATED_METAL := preload("res://assets/textures/painted/material_corrugated_metal_albedo.png")
const _TEX_CORRUGATED_METAL_GRIME := preload("res://assets/textures/painted/material_corrugated_metal_grime.png")
const _TEX_CONTAINER_PAINT := preload("res://assets/textures/painted/material_container_paint_albedo.png")
const _TEX_CONTAINER_PAINT_GRIME := preload("res://assets/textures/painted/material_container_paint_grime.png")
const _TEX_WOOD_PLANKS := preload("res://assets/textures/painted/material_wood_planks_albedo.png")
const _TEX_WOOD_PLANKS_GRIME := preload("res://assets/textures/painted/material_wood_planks_grime.png")
const _TEX_SAND_DIRT := preload("res://assets/textures/painted/material_sand_dirt_albedo.png")
const _TEX_CRACKED_CONCRETE := preload("res://assets/textures/painted/material_cracked_concrete_albedo.png")
const _TEX_CRACKED_CONCRETE_GRIME := preload("res://assets/textures/painted/material_cracked_concrete_grime.png")
const _TEX_ASPHALT := preload("res://assets/textures/painted/material_asphalt_albedo.png")
const _TEX_SHIP_DECK := preload("res://assets/textures/painted/material_ship_deck_albedo.png")
const _TEX_SHIP_DECK_GRIME := preload("res://assets/textures/painted/material_ship_deck_grime.png")
const _TEX_RUBBER_TIRE := preload("res://assets/textures/painted/material_rubber_tire_albedo.png")
const _TEX_DIRTY_GLASS := preload("res://assets/textures/painted/material_dirty_glass_albedo.png")

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

## -- Palettes par carte (STYLE_BIBLE.md v3 §7.7) ----------------------------
## Une seule table (ici, pas dupliquée dans LevelLook.gd) : `world()`/
## `painted()`/`prop_uv()` la consultent pour `shadow_tint`, LevelLook.gd pour
## le ciel/soleil/lumière. Clé = MatchConfig.map_id. "" (aucune carte choisie
## — test_arena, comp_map, tdm_map, arènes, benchmark, menu principal) retombe
## sur Wasteland, la carte par défaut du thesis (§1).
##
## GÉNÉRÉE : `StyleTokens.MAP_PALETTES` (scripts/core/StyleTokens.gd) vient de
## `tools/style/gen_style_tokens.py`, qui transcrit `docs/style/tokens.json`
## "maps" SANS AUCUNE retouche à la main (§7.7 « on supprime les
## assombrissements de compensation ») — l'ancien assombrissement manuel de
## Wasteland/Cargo Ship ici (mesuré contre le tonemap Filmic v2, obsolète
## depuis que LevelLook.gd est passé au LINÉAIRE WYSIWYG, §7.5) est supprimé :
## ce fichier ne fait plus que POINTER vers la table générée, jamais la
## dupliquer. `ground`/`backdrop_near`/`backdrop_far`/`fog` (ajoutés par ce
## générateur, §7.7) ne sont pas encore consommés ici (terrain/coulisses :
## ART-06/tâches suivantes), mais font déjà partie de la même table unique.
const _MAP_PALETTES: Dictionary = StyleTokens.MAP_PALETTES
const _DEFAULT_MAP_ID := StyleTokens.DEFAULT_MAP_ID

## Palette de la carte `map_id` (STYLE_BIBLE.md v3 §7.7), ou celle de la carte
## par défaut si `map_id` est vide/inconnu (jamais un dictionnaire vide :
## tous les appelants — Cartoon et LevelLook — peuvent indexer sans vérifier).
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
	# Wasteland v7 greybox : "kind" canonique dédié, jamais un socle de
	# `tools/textures/gen_textures.py` — voir `dev_grid()`/`painted()`.
	&"dev_grid": &"dev_grid",
}

## Wasteland v7 greybox (2026-09-26, "carte block jouable" — reste
## `scripts/levels/maps/layouts/wasteland.gd`/`wasteland_look.gd`) : grille
## triplanaire monde (1 m mineure / 5 m majeure, `assets/shaders/
## dev_grid.gdshader`), teintée EXACTEMENT par `color` (aucune dilution —
## contrairement à `painted()`, jamais de texture peinte à recoloriser).
## Ajoutée ici plutôt que dans `Kit.gd`/`MapSetup.gd` (hors du périmètre de
## cette tâche) : `Kit.build_piece`/`GeoBatcher.flush` choisissent déjà le
## matériau via le même pipeline "kind" (`palette["<rôle>_kind"]` ->
## `Cartoon.painted(kind, col)`) — un kind canonique "dev_grid" suffit à
## rediriger CE chemin existant vers ce nouveau matériau, sans toucher au
## dispatcher partagé par les 7 autres cartes.
static func dev_grid(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _DEV_GRID_SHADER
	m.set_shader_parameter("albedo_color", color)
	return m

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
	if canonical == &"dev_grid":
		return dev_grid(tint)
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

## Matériau "prop peint, UV Blender" (STYLE_BIBLE.md v3 §7.7) : sert les
## maillages `tools/blender/make_*.py` (props/décor) qui apportent leur
## PROPRE UV (§7.9 : projection 256 px/m, panneaux alignés sur le
## trim-sheet) — JAMAIS triplanaire, contrairement à `painted()` (§7.2/§7.7 :
## « use_triplanar : terrain uniquement » ; `use_triplanar` reste donc à son
## défaut shader `false`, seul `painted()` le met explicitement à `true`).
## Les masques vertex `COLOR_0` (AO/arête convexe/gradient de hauteur, bakés
## par le même pipeline Blender, §7.1/§7.9) sont déjà lus par défaut par
## `world()` (`use_vertex_masks` vaut `true` par défaut dans le shader) —
## rien à poser ici non plus. Même bibliothèque de textures (`_PAINTED`),
## mêmes alias de kind (`_KIND_ALIASES`) et même règle de teinte
## (`effective_tint`, évite le double assombrissement des textures déjà
## colorées) que `painted()` ; un kind inconnu avertit et retombe sur
## `world(tint)`, comme `painted()`. Ni `triplanar_scale` ni `grime_scale` à
## poser : `fragment()` (ink_toon.gdshader) échantillonne
## `texture(albedo_texture, UV)`/`texture(grime_texture, UV)` — jamais
## `triplanar_sample()` — dès que `use_triplanar` est `false`, donc l'UV du
## maillage pilote seule la répétition/l'alignement du grime.
static func prop_uv(kind: StringName, tint: Color = Color.WHITE) -> ShaderMaterial:
	var canonical: StringName = _KIND_ALIASES.get(kind, &"")
	var m := world(effective_tint(canonical, tint))
	var entry: Dictionary = _PAINTED.get(canonical, {})
	if entry.is_empty():
		push_warning("Cartoon.prop_uv: kind peint inconnu \"%s\"" % kind)
		return m
	m.set_shader_parameter("use_albedo_texture", true)
	m.set_shader_parameter("albedo_texture", entry["albedo"])
	var grime: Texture2D = entry.get("grime")
	if grime != null:
		m.set_shader_parameter("use_grime_texture", true)
		m.set_shader_parameter("grime_texture", grime)
	return m

## Matériau "prop peint Tripo" (ART-80, docs/art/WASTELAND_ART_RESET.md,
## tools/blender/ai_import_painted.py) : comme `prop_uv()` mais pour une
## texture qui n'appartient PAS à la bibliothèque partagée `_PAINTED` — un
## repère importé (assets/models/props/wasteland/tripo/*.glb) porte SA
## PROPRE texture bakée, unique et conservée depuis Tripo Studio (jamais un
## des 11 kinds génériques de palette), donc jamais un nom de kind ici mais
## directement la `Texture2D` déjà extraite du matériau importé (voir
## `texture_from_imported_material`). UV Blender posée à la main par Tripo
## Studio (jamais triplanaire, comme `prop_uv`) ; contour d'encre plat
## habituel (`prop()`), pas de rim (repère de décor statique, pas un
## personnage). `albedo` à `null` (matériau importé sans texture — couleur
## plate résiduelle, cas dégénéré jamais rencontré sur ces 7 repères) retombe
## sur un `world(tint)` sans texture, jamais un crash.
static func painted_texture_prop(albedo: Texture2D, tint: Color = Color.WHITE) -> ShaderMaterial:
	var m := world(tint)
	if albedo != null:
		m.set_shader_parameter("use_albedo_texture", true)
		m.set_shader_parameter("albedo_texture", albedo)
	m.next_pass = _outline_pass(INK, 2.0)
	return m

## Texture2D déjà branchée en albédo sur `material` — un `StandardMaterial3D`
## est ce que l'import glTF de Godot construit pour un matériau Principled
## BSDF <- Image Texture comme ceux qu'écrit
## `tools/blender/ai_import_painted.py::keep_painted_materials` (ART-80).
## `null` si `material` n'est pas un `StandardMaterial3D` ou ne porte aucune
## texture d'albédo (matériau plat résiduel) — jamais une erreur, voir
## `painted_texture_prop`.
static func texture_from_imported_material(material: Material) -> Texture2D:
	var std := material as StandardMaterial3D
	if std == null:
		return null
	return std.albedo_texture

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
##
## `mesh` (TECH-03, optionnel, défaut `null`) : le viewmodel (arme + gants en
## 1re personne, ViewModel.gd/ThirdPersonWeapon.gd) appelle `character()`
## directement, sans passer par `apply_team_outline()` — un viewmodel skinné
## (Skeleton3D pour l'animation des mains) se fendrait donc à ses arêtes vives
## exactement comme un mesh d'équipe non couvert par TECH-03, faute de savoir
## qu'il est skinné. Un appelant qui connaît son `Mesh` (ces deux fichiers
## sont hors du périmètre de cette tâche, voir l'en-tête de ce fichier — la
## mise à jour des appels est signalée dans blocked_on) le passe ici pour
## router sur `_mesh_is_skinned()`, comme `apply_team_outline`. Défaut `null`
## => comportement inchangé (CUSTOM0) pour tout appel positionnel existant.
static func character(color: Color, outline_px: float = 3.0, highlight_color: Color = Color(0.0, 0.0, 0.0, 0.0), mesh: Mesh = null) -> ShaderMaterial:
	var m := world(color)
	var use_smooth_normal_tangent := mesh != null and _mesh_is_skinned(mesh)
	if highlight_color.a > 0.0:
		var highlight := _falloff_outline_pass(highlight_color, outline_px, outline_px * (2.5 / 3.5), outline_px * (2.5 / 3.5), use_smooth_normal_tangent)
		highlight.next_pass = _falloff_outline_pass(INK, outline_px + 1.0, outline_px * (2.5 / 3.5) + 1.0, outline_px * (2.5 / 3.5) + 1.0, use_smooth_normal_tangent, _OUTER_HULL_RENDER_PRIORITY)
		m.next_pass = highlight
	else:
		m.next_pass = _falloff_outline_pass(INK, outline_px, outline_px * (2.0 / 3.0), max(outline_px * (1.5 / 3.0), 1.0), use_smooth_normal_tangent)
	return m

## Compat. : ancien point d'entrée. `_outline` est ignoré (les appelants
## historiques ne dessinaient déjà aucun contour dédié) ; renvoie le matériau
## monde à base de shader.
static func mat(color: Color, _outline: float = 0.0) -> Material:
	return world(color)

## Matériau de "slot" personnage (peau/tenue/tissu/équipement/accent) —
## teinte plate, SANS grain (STYLE_BIBLE.md v3.1 §4.2 « même encre, mêmes
## biseaux, mêmes deux bandes » et §5.3 « aucun grain » ; CHK-27 exige
## `paint_grain_strength = 0`, §7.7 « _CHARACTER_GRAIN à 0 » — remplace le
## grain v2 par kind, "le détail vient de la géométrie ou d'un décalque,
## jamais d'un bruit" §1.1). Pas de triplanar monde ici non plus : les
## personnages bougent et une texture plaquée en espace monde "nagerait" sur
## le maillage à chaque pas. `kind` ne module plus rien (toutes les valeurs
## sont 0, y compris le repli d'un `kind` inconnu) ; la table reste indexée
## par kind pour que l'API de `character_surface()` n'ait pas à changer si
## un futur besoin de grain différencié revient.
const _CHARACTER_GRAIN: Dictionary = {
	&"skin": 0.0,
	&"cloth": 0.0,
	&"outfit": 0.0,
	&"gear": 0.0,
	&"accent": 0.0,
}
static func character_surface(kind: StringName, color: Color) -> ShaderMaterial:
	var m := world(color)
	m.set_shader_parameter("paint_grain_strength", _CHARACTER_GRAIN.get(kind, 0.0))
	return m

## Contour d'équipe complet posé en `next_pass` sur CHAQUE surface de `g` (un
## mannequin/personnage a souvent plusieurs surfaces — peau, tenue, équipement
## — chacune avec son propre matériau `character_surface()` ; un pass par
## surface, car l'extrusion "coque inversée" d'ink_outline.gdshader n'étend
## QUE la géométrie de SA surface). Fonctionne sur un maillage skinné
## (Skeleton3D) : Godot applique le skinning à VERTEX/NORMAL/TANGENT AVANT que
## vertex() ne s'exécute, donc l'extrusion voit déjà les sommets posés — mais
## PAS aux attributs CUSTOM, d'où `_mesh_is_skinned` ci-dessous qui bascule le
## shader sur la normale lissée portée par TANGENT plutôt que CUSTOM0 pour ce
## cas (TECH-03, voir l'en-tête d'ink_outline.gdshader).
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
	var next_pass := _team_outline_pass(is_enemy, _mesh_is_skinned(mi.mesh))
	for i in range(mi.mesh.get_surface_count()):
		var surface_mat: Material = mi.get_surface_override_material(i)
		if surface_mat == null:
			surface_mat = mi.mesh.surface_get_material(i)
		if surface_mat == null:
			continue
		surface_mat.next_pass = next_pass

## TECH-03 (docs/research/07_godot_tech.md C1) : un mesh est "skinné" (posé par
## un Skeleton3D, sommets pondérés par des os) dès qu'UNE de ses surfaces
## porte le format `Mesh.ARRAY_FORMAT_BONES` — détecté sur le mesh lui-même
## (jamais sur le nom du fichier appelant), pour rester correct quel que soit
## l'appelant d'`apply_team_outline`. Sert à choisir le canal de normale
## lissée d'`ink_outline.gdshader` (`use_smooth_normal_tangent`) : un skinné
## ne peut pas lire CUSTOM0 (non skinné par Godot), l'encre s'y fend en
## bougeant — voir en-tête du shader. `surface_get_format` n'existe que sur
## `ArrayMesh`/les meshes importés : un `PrimitiveMesh` (BoxMesh, SphereMesh…,
## utilisés par des tests et par du décor procédural) ne l'implémente pas
## («Nonexistent function», pas une valeur — vérifié à l'exécution) ; on le
## traite alors comme non skinné, ce qu'il est de toute façon (aucun
## `PrimitiveMesh` ne porte de poids d'os).
static func _mesh_is_skinned(mesh: Mesh) -> bool:
	if not mesh.has_method("surface_get_format"):
		return false
	for i in range(mesh.get_surface_count()):
		if (mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_BONES) != 0:
			return true
	return false

static func _team_outline_pass(is_enemy: bool, use_smooth_normal_tangent: bool = false) -> ShaderMaterial:
	if is_enemy:
		var highlight := _falloff_outline_pass(enemy_color(), 3.5, 2.5, 2.5, use_smooth_normal_tangent)
		highlight.next_pass = _falloff_outline_pass(INK, 4.5, 3.5, 3.5, use_smooth_normal_tangent, _OUTER_HULL_RENDER_PRIORITY)
		return highlight
	return _falloff_outline_pass(INK, 3.0, 2.0, 1.5, use_smooth_normal_tangent)

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

## TECH-04 (vérification par capture réelle, voir tests/rendering/
## test_enemy_outline.gd) : deux passes `ink_outline.gdshader` au MÊME
## `render_priority` (0 par défaut, jamais posé avant cette tâche) ne se
## dessinent PAS dans l'ordre de la chaîne `next_pass` -- capture fenêtrée
## empirique (godot --path . -s <script hors dépôt construisant `character()`
## avec highlight_color et deux caméras, l'une sans obstacle> ; magenta jamais
## présent, un seul pixel cyan/rouge visible selon lequel des deux passes
## était PLUS LARGE, quel que soit leur ordre dans `next_pass`) : sans un
## `render_priority` explicite, la coque d'encre EXTÉRIEURE (plus large, 4.5
## vs 3.5 px) se dessinait AVANT la coque de surbrillance (Cartoon.
## enemy_color()) et gagnait donc la totalité du stencil -- la surbrillance
## ennemie, censée "ne jamais s'effacer" (design.md §5), était rendue
## ENTIÈREMENT INVISIBLE (0 pixel magenta sur toute l'image), remplacée par
## un contour plat couleur encre -- une régression bien plus grave que la
## "coque interne" que TECH-04 corrige. Doc Godot 4.7 "Standard Material 3D >
## Render priority" : "Objects are sorted ... by render_priority, with higher
## priority objects being drawn later" -- documentation officielle du
## mécanisme prévu pour ordonner plusieurs passes transparentes, jamais
## utilisé nulle part ailleurs dans ce dépôt avant cette tâche (`grep -rn
## render_priority` ne renvoyait rien). `_OUTER_HULL_RENDER_PRIORITY` (1,
## strictement > 0, le défaut de la coque de surbrillance) force donc la
## coque d'encre extérieure à se dessiner APRÈS la surbrillance -- celle-ci
## gagne alors son plein empan au stencil, l'encre n'obtenant plus que
## l'anneau qui lui reste (le 1 px qui dépasse), exactement le rendu visé.
## Ne s'applique qu'aux DEUX passes du double hull ennemi (`character(
## highlight_color=...)`/`_team_outline_pass(is_enemy=true)`) : un contour
## simple (prop()/allié) n'a qu'UNE seule passe ink_outline, aucune
## ambiguïté d'ordre à résoudre, donc `render_priority` par défaut (0) partout
## ailleurs.
const _OUTER_HULL_RENDER_PRIORITY := 1

static func _outline_pass(color: Color, width_px: float, use_smooth_normal_tangent: bool = false, render_priority: int = 0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _INK_OUTLINE_SHADER
	m.set_shader_parameter("outline_color", color)
	m.set_shader_parameter("outline_width_px", width_px)
	m.set_shader_parameter("use_smooth_normal_tangent", use_smooth_normal_tangent)
	m.render_priority = render_priority
	return m

## Contour d'encre dont la largeur s'amenuise avec la distance caméra (voir
## ink_outline.gdshader `distance_falloff`) : `near_px` jusqu'à 10 m, puis
## approche de `far_px`/`floor_px` au-delà (les deux égaux => un plancher
## strict, jamais plus fin — c'est le « ne s'efface jamais » des ennemis).
## `use_smooth_normal_tangent` : voir `_mesh_is_skinned`/TECH-03.
static func _falloff_outline_pass(color: Color, near_px: float, far_px: float, floor_px: float, use_smooth_normal_tangent: bool = false, render_priority: int = 0) -> ShaderMaterial:
	var m := _outline_pass(color, near_px, use_smooth_normal_tangent, render_priority)
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
