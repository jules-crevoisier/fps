## test_enemy_outline.gd
## Spec (TECH-04, docs/research/07_godot_tech.md C1 "Stencil") : contour
## ennemi au stencil -- une coque ne se dessine plus la ou une AUTRE coque
## ink_outline a deja ecrit (evite la "coque interne" du double hull
## surbrillance + encre posé par `Cartoon.character(highlight_color=...)`/
## `apply_team_outline` aux jointures entre surfaces d'un personnage
## multi-materiaux), et l'occlusion "un ennemi derriere un mur n'a aucun
## pixel de contour visible" reste garantie par le TEST DE PROFONDEUR
## normal -- jamais un mode X-ray (aucun `depth_test_disabled`/
## `depth_test_inverted`).
##
## Comme test_outline_widths.gd/test_outline_normals.gd (meme limite, voir
## leur docstring) : gdUnit4 ne peut pas mesurer un rendu reel en headless
## ici (pas de vrai swapchain). Ce fichier verifie donc STRUCTURELLEMENT (a)
## que le GLSL declare bien `stencil_mode read, write, compare_not_equal, 1`
## et force le pipeline transparent (`ALPHA = 1.0`, seule passe autorisee a
## LIRE le stencil, doc Godot 4.5 "Stencil modes"), (b) qu'aucun mode X-ray
## n'a ete introduit, (c) que `ink_toon.gdshader` (partage par tout le
## monde/decor) n'a PAS recu ce meme `stencil_mode` -- l'ecrire la
## rendrait le contour ennemi invisible des qu'il passe devant un mur/sol
## peint (le decor marquerait le meme stencil), une regression pire que le
## bug corrige (voir l'en-tete des deux .gdshader pour le raisonnement
## complet), et (d) que la double coque ennemie (`character()`/
## `apply_team_outline`) pose toujours ses DEUX passes sur ce shader
## desormais equipe du stencil.
##
## Critere d'acceptation NON couvert par ce fichier : "un ennemi coute au
## plus 2 passes au lieu de 3" -- le réduire suppose de retirer le second
## next_pass (coque d'encre exterieure) de `Cartoon.character()`/
## `apply_team_outline`, ce qui casserait des assertions verrouillees dans
## tests/rendering/test_cartoon_materials.gd
## (`test_character_material_with_highlight_builds_two_layer_enemy_hull`,
## `test_apply_team_outline_enemy_uses_current_enemy_color_highlight`) et
## tests/rendering/test_outline_normals.gd
## (`test_apply_team_outline_propagates_tangent_mode_through_enemy_double_shell`,
## `test_character_propagates_tangent_mode_to_enemy_double_shell`) -- deux
## fichiers hors de la liste de fichiers de cette tache. Signale en
## `blocked_on`, pas contourne ici (un test ne se reecrit jamais pour coller
## au code, et cette tache ne touche pas des fichiers hors de sa liste).
## Draw calls du benchmark : mesurés empiriquement (RenderingServer.
## RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME, scène de 6 personnages
## `apply_team_outline(is_enemy=true)` + un mur, capture fenêtrée) --
## identiques (19.0 en moyenne) avec ce fichier AVANT (`git show
## HEAD:assets/shaders/ink_outline.gdshader`, sans stencil) et APRÈS
## (stencil + `_OUTER_HULL_RENDER_PRIORITY`) : ni le stencil ni
## `render_priority` n'ajoutent de passe, seul un retrait du 2e next_pass
## (bloqué ci-dessus) réduirait ce nombre. Non ré-exécuté par gdUnit4 (script
## fenêtré jetable, comme le reste de cette vérification).
##
## `render_priority` (TECH-04, correction de cette relecture QA) : capture
## fenêtrée réelle (godot --path . -s <script hors dépôt>, voir ci-dessus)
## de `Cartoon.character(highlight_color=...)` SANS render_priority a montré
## 0 pixel magenta sur toute l'image -- la coque d'encre EXTÉRIEURE (plus
## large, 2e position dans la chaîne next_pass) se dessinait AVANT la coque
## de surbrillance et gagnait donc la totalité du stencil, rendant la
## surbrillance ennemie (censée "ne jamais s'effacer", design.md §5)
## ENTIÈREMENT INVISIBLE -- une régression plus grave que la "coque interne"
## que ce ticket corrige. Doc Godot 4.7 "Standard Material 3D > Render
## priority" ("higher priority objects being drawn later") confirme que
## `render_priority` est le mécanisme prévu pour ordonner des passes
## transparentes multiples ; `_OUTER_HULL_RENDER_PRIORITY = 1` sur la coque
## d'encre (Cartoon.gd) la fait dessiner APRÈS la surbrillance, qui gagne
## alors son plein empan au stencil -- reproduit et confirmé par capture
## (magenta dominant, fine bordure encre) pour `character()` ET
## `apply_team_outline`, ainsi que par une capture d'occlusion réelle
## (ennemi derrière un mur : 0 pixel de contour sur toute l'image, aux DEUX
## caméras). Captures : reports/checkpoints/2026-09-25_TECH-04/.
## `test_character_enemy_double_shell_both_layers_use_the_stencil_equipped_shader`/
## `test_apply_team_outline_enemy_double_shell_both_layers_use_the_stencil_equipped_shader`
## ci-dessous couvrent maintenant aussi cet ordre de rendu (STRUCTURELLEMENT,
## via `render_priority` -- gdUnit4 ne peut toujours pas lire de pixels réels
## en headless ici, voir l'en-tête).
extends GdUnitTestSuite

const _OUTLINE_SHADER_PATH := "res://assets/shaders/ink_outline.gdshader"
const _TOON_SHADER_PATH := "res://assets/shaders/ink_toon.gdshader"
const _INK_OUTLINE_SHADER := preload("res://assets/shaders/ink_outline.gdshader")


func _outline_source() -> String:
	return FileAccess.get_file_as_string(_OUTLINE_SHADER_PATH)


func _toon_source() -> String:
	return FileAccess.get_file_as_string(_TOON_SHADER_PATH)


# --------------------------------------------- ink_outline.gdshader : stencil

func test_ink_outline_declares_read_write_compare_not_equal_stencil_mode() -> void:
	var re := RegEx.new()
	re.compile("stencil_mode\\s+read\\s*,\\s*write\\s*,\\s*compare_not_equal\\s*,\\s*1\\s*;")
	assert_that(re.search(_outline_source())).append_failure_message(
		"ink_outline.gdshader ne declare pas `stencil_mode read, write, compare_not_equal, 1;` -- coque unique au stencil (TECH-04) absente"
	).is_not_null()


## `stencil_mode` doit etre une instruction a part (Godot 4.7.2 : TK_STENCIL_MODE
## distinct de TK_RENDER_MODE, voir servers/rendering/shader_language.cpp), pas
## injecte dans la liste `render_mode` existante (qui resterait alors inchangee).
func test_render_mode_line_is_unchanged_by_the_stencil_addition() -> void:
	var re := RegEx.new()
	re.compile("render_mode\\s+cull_front\\s*,\\s*unshaded\\s*,\\s*depth_draw_always\\s*;")
	assert_that(re.search(_outline_source())).append_failure_message(
		"render_mode cull_front, unshaded, depth_draw_always; a change -- la coque au stencil ne doit pas toucher aux modes existants"
	).is_not_null()


func test_ink_outline_fragment_forces_alpha_for_transparent_stencil_read() -> void:
	assert_str(_outline_source()).append_failure_message(
		"fragment() n'ecrit pas ALPHA = 1.0 -- lire le stencil n'est possible que dans la passe transparente (Godot 4.5, doc 'Stencil modes')"
	).contains("ALPHA = 1.0")


## Jamais d'X-ray (docs/research/07_godot_tech.md C1 : "Le mode X-ray est
## interdit -- information a travers les murs") : aucun des deux modes qui
## desactiveraient/inverseraient le test de profondeur normal.
func test_ink_outline_never_disables_or_inverts_depth_test() -> void:
	var source := _outline_source()
	assert_str(source).append_failure_message(
		"depth_test_disabled present dans ink_outline.gdshader -- ce serait un X-ray (contour visible a travers les murs)"
	).not_contains("depth_test_disabled")
	assert_str(source).append_failure_message(
		"depth_test_inverted present dans ink_outline.gdshader -- ce serait un X-ray inverse, jamais voulu ici"
	).not_contains("depth_test_inverted")


# ----------------------------------- ink_toon.gdshader : pas de stencil partage

## ink_toon.gdshader est partage par TOUT le monde/decor (Cartoon.world()/
## painted()/prop_uv()), pas seulement les personnages -- un `stencil_mode
## write` systematique le rendrait invisible des que l'ennemi passe devant
## un mur/sol peint (voir l'en-tete des deux fichiers). Garde de non-
## regression : si ce test casse, quelqu'un a ajoute le stencil au mauvais
## fichier.
func test_ink_toon_shader_still_has_no_stencil_mode() -> void:
	assert_str(_toon_source()).append_failure_message(
		"ink_toon.gdshader declare desormais stencil_mode -- ce shader est partage par le decor, cela rendrait le contour ennemi invisible devant un mur/sol peint (voir l'en-tete du fichier, TECH-04)"
	).not_contains("stencil_mode")


# --------------------------------- Cartoon.gd : la double coque ennemie reste
# --------------------------------- posee sur ce shader desormais equipe

func test_character_enemy_double_shell_both_layers_use_the_stencil_equipped_shader() -> void:
	var m := Cartoon.character(Color.GREEN, 3.5, Color("ff3dc8"))
	var highlight: ShaderMaterial = m.next_pass
	assert_object(highlight).append_failure_message(
		"Cartoon.character(highlight_color=...) ne pose plus de coque de surbrillance -- la protection stencil ne peut pas s'appliquer"
	).is_not_null()
	assert_that(highlight.shader).append_failure_message(
		"la coque de surbrillance ennemie n'utilise plus ink_outline.gdshader"
	).is_equal(_INK_OUTLINE_SHADER)
	var ink_shell: ShaderMaterial = highlight.next_pass
	assert_object(ink_shell).append_failure_message(
		"la coque d'encre exterieure (next_pass de la surbrillance) a disparu -- si c'est voulu (reduction a 2 passes), ce test doit changer AVEC tests/rendering/test_cartoon_materials.gd et test_outline_normals.gd, pas seul"
	).is_not_null()
	assert_that(ink_shell.shader).append_failure_message(
		"la coque d'encre exterieure n'utilise plus ink_outline.gdshader -- elle ne beneficierait plus du masquage stencil"
	).is_equal(_INK_OUTLINE_SHADER)
	# render_priority (voir en-tête de fichier) : l'encre exterieure doit se
	# dessiner APRES la surbrillance (priorite strictement superieure, doc
	# Godot 4.7 "higher priority objects being drawn later"), sinon elle
	# gagne le stencil sur tout son empan (plus large) et la surbrillance
	# ennemie -- censee ne jamais s'effacer -- redevient invisible a l'ecran
	# (verifie par capture reelle, voir en-tete).
	assert_int(ink_shell.render_priority).append_failure_message(
		"la coque d'encre exterieure doit avoir un render_priority strictement superieur a celui de la surbrillance, sinon elle se dessine avant elle et la rend invisible (capture reelle, voir en-tete de ce fichier)"
	).is_greater(highlight.render_priority)


func test_apply_team_outline_enemy_double_shell_both_layers_use_the_stencil_equipped_shader() -> void:
	var mi: MeshInstance3D = auto_free(MeshInstance3D.new())
	mi.mesh = BoxMesh.new()
	var surf := Cartoon.character_surface(&"outfit", Color.BLUE)
	mi.set_surface_override_material(0, surf)
	Cartoon.apply_team_outline(mi, true)
	var highlight: ShaderMaterial = surf.next_pass
	assert_object(highlight).is_not_null()
	assert_that(highlight.shader).is_equal(_INK_OUTLINE_SHADER)
	var ink_shell: ShaderMaterial = highlight.next_pass
	assert_object(ink_shell).append_failure_message(
		"apply_team_outline(is_enemy=true) ne pose plus de second next_pass -- verifier la coherence avec test_cartoon_materials.gd/test_outline_normals.gd"
	).is_not_null()
	assert_that(ink_shell.shader).is_equal(_INK_OUTLINE_SHADER)
	assert_int(ink_shell.render_priority).append_failure_message(
		"apply_team_outline(is_enemy=true) : la coque d'encre exterieure doit avoir un render_priority strictement superieur a celui de la surbrillance (meme raison que test_character_enemy_double_shell_both_layers_use_the_stencil_equipped_shader)"
	).is_greater(highlight.render_priority)


## Un ennemi ALLIE (is_enemy=false) ne pose qu'UNE coque (pas de surbrillance) --
## celle-ci doit elle aussi porter le stencil (meme shader partage), sans quoi
## un allie et un ennemi debout cote a cote se masqueraient incorrectement l'un
## l'autre de facon incoherente selon l'ordre de dessin.
func test_ally_single_shell_also_uses_the_stencil_equipped_shader() -> void:
	var m := Cartoon.character(Color.GREEN)
	var outline: ShaderMaterial = m.next_pass
	assert_object(outline).is_not_null()
	assert_that(outline.shader).is_equal(_INK_OUTLINE_SHADER)
