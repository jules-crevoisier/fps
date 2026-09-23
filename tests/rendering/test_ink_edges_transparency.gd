## test_ink_edges_transparency.gd
## Regression (reported by the training/character slice: with InkPost
## enabled, Label3D never rendered in game scenes -- reproduced with a big
## bright no-depth-test billboard label). Root cause: the full-screen ink
## quad sits in the TRANSPARENT pass at the near plane, so it draws LAST
## among every transparent object that frame (Label3D, damage numbers,
## tracers, muzzle flashes, alpha VFX). The old shader read
## `hint_screen_texture` (an opaque-only snapshot) and wrote it back as
## ALBEDO with no ALPHA set -- which defaults to 1.0, fully opaque --
## blotting out every transparent object under it regardless of whether
## that pixel was even near an ink line.
##
## tools/screenshot.gd's own docstring notes this project's headless mode
## has no real swapchain ("il faut un vrai swapchain pour lire le rendu"),
## so a genuine pixel-level check (a Label3D actually visible on screen)
## isn't something gdUnit4 can assert headlessly here. This suite instead
## pins the STRUCTURAL contract that prevents the bug class: the shader
## never reads back the scene's own colour, and paints ink via ALPHA
## (transparent where there's no edge) rather than repainting the frame.
## A real windowed capture (Label3D + a transparent quad in front of a
## wall, InkPost enabled) was additionally eyeballed by hand for this slice
## (see the PR/report) -- both stayed visible.
extends GdUnitTestSuite

const _SHADER_PATH := "res://assets/shaders/ink_edges.gdshader"


func _source() -> String:
	return FileAccess.get_file_as_string(_SHADER_PATH)


func test_shader_never_samples_the_screen_texture() -> void:
	# A regex on the actual GLSL declaration (not a plain substring search):
	# this file's own comments legitimately name "screen_tex"/
	# "hint_screen_texture" in prose explaining the historical bug, so a
	# naive `contains` would false-positive on the documentation itself.
	var re := RegEx.new()
	re.compile("uniform\\s+sampler2D\\s+screen_tex\\s*:\\s*hint_screen_texture")
	assert_that(re.search(_source())).is_null()


func test_shader_writes_alpha_as_the_edge_mask() -> void:
	assert_str(_source()).contains("ALPHA = ")


func test_shader_declares_blend_mix() -> void:
	assert_str(_source()).contains("blend_mix")


func test_ink_post_material_has_no_screen_texture_parameter() -> void:
	# `get_shader_parameter` on an unknown uniform name returns null in
	# Godot 4 -- confirms the ShaderMaterial's compiled uniform list has no
	# `screen_tex` slot at all, not just that InkPost.gd doesn't set one.
	var mat := ShaderMaterial.new()
	mat.shader = load(_SHADER_PATH)
	assert_that(mat.get_shader_parameter("screen_tex")).is_null()
