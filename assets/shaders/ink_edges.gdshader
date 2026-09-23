// ink_edges.gdshader
// World post-pass: SILHOUETTE-ONLY ink lines on the decor (design.md v2 SS3
// "post draws silhouettes" -- v1's extra normal/curvature "crease" family
// and the paper-grain/wash overlay are both gone; baked textures carry
// their own ink now, see tools/textures/gen_textures.py). A full-screen quad
// attached to the local player's camera (InkPost.gd); depth-only occlusion
// edges (a true silhouette = a depth discontinuity), using the curvature
// (2nd derivative) of linear depth so a grazing floor or a close-up
// viewmodel doesn't get painted as one giant "edge" (Godot 4.7 docs,
// "Advanced post-processing": depth texture + INV_PROJECTION_MATRIX to
// reconstruct linear depth from SCREEN_UV).
//
// design.md v2 SS5 "Decor silhouettes (post)": 4 px up to 10 m, 1.5 px at
// 60 m (held beyond); 100% opacity up to 10 m, down to a 40% FLOOR at 90 m
// (never fully invisible, unlike v1's fade-to-nothing). SS4 "Fog": tints far
// outlines toward the haze colour, ramping in from 35 m to 30% at 120 m.
//
// IMPORTANT (fixed after a report from the training/character slice, which
// hit it via Label3D never rendering with InkPost on): this quad sits in
// the TRANSPARENT pass at the near plane, so back-to-front sorting draws it
// LAST among every transparent object on screen that frame (damage
// numbers, Label3D, tracers, muzzle flashes, any alpha VFX). The old
// version read `hint_screen_texture` (a snapshot taken BEFORE the
// transparent pass, i.e. opaque-only) and wrote it back as ALBEDO with no
// ALPHA set -- which defaults to 1.0, fully opaque. Drawn last, opaque,
// full-screen: it blotted out every transparent object with the
// pre-transparent opaque image, whether or not that pixel was even near an
// ink line. Since v2 only ever needs to ADD ink lines (never repaint the
// scene -- v1's paper wash is gone), the fix is to stop touching the scene
// colour at all: output ink colour with ALPHA = the edge mask (0 off an
// edge -- fully transparent, lets everything drawn under OR after it show
// through untouched) and drop `screen_tex`/`hint_screen_texture` entirely.
// Depth (and, if ever needed, normal) textures are enough for a silhouette
// pass.
shader_type spatial;
render_mode blend_mix, unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

uniform bool enabled = true;
// #1A1410 (Cartoon.INK) -- set at runtime by InkPost.gd.
uniform vec4 ink_color : source_color = vec4(0.1020, 0.0784, 0.0627, 1.0);
// Current map's horizon/haze colour -- set at runtime by InkPost.gd from
// Cartoon.map_palette(). Far outlines tint toward this, matching the fog.
uniform vec4 haze_color : source_color = vec4(0.851, 0.910, 0.965, 1.0);

uniform float width_near_px : hint_range(1.0, 8.0) = 4.0;
uniform float width_far_px : hint_range(0.5, 8.0) = 1.5;
uniform float width_near_m : hint_range(1.0, 50.0) = 10.0;
uniform float width_far_m : hint_range(1.0, 150.0) = 60.0;

uniform float opacity_far_floor : hint_range(0.0, 1.0) = 0.4;
uniform float opacity_far_m : hint_range(1.0, 200.0) = 90.0;

uniform float fog_start_m : hint_range(1.0, 200.0) = 35.0;
uniform float fog_end_m : hint_range(1.0, 300.0) = 120.0;
uniform float fog_max_amount : hint_range(0.0, 1.0) = 0.3;

uniform float depth_edge_threshold : hint_range(0.005, 1.0) = 0.05;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// Profondeur linéaire (distance à la caméra, en mètres) à partir de la
// profondeur non-linéaire (reverse-Z) échantillonnée à `uv`.
float linear_depth(float d, vec2 uv, mat4 inv_proj) {
	vec4 view_pos = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	view_pos.xyz /= view_pos.w;
	return -view_pos.z;
}

float sample_linear_depth(vec2 uv, mat4 inv_proj) {
	return linear_depth(texture(depth_tex, uv).r, uv, inv_proj);
}

// Silhouette response (true depth discontinuity = occlusion edge). Uses the
// SECOND derivative (curvature) of linear depth, not a first-derivative
// ratio: on a flat plane seen at a grazing angle -- or anything very close
// to the camera, like a viewmodel -- `l + r - 2*c` stays ~0 regardless of
// slope or distance, while a ratio of first derivatives explodes in both
// those cases (measured in-game in the v1 pass: it painted whole surfaces
// as "edge"). Curvature only fires at genuine one-pixel-in-front /
// one-pixel-behind breaks.
float depth_response(vec2 uv, vec2 texel, float center_depth, mat4 inv_proj) {
	float l = sample_linear_depth(uv - vec2(texel.x, 0.0), inv_proj);
	float r = sample_linear_depth(uv + vec2(texel.x, 0.0), inv_proj);
	float u = sample_linear_depth(uv - vec2(0.0, texel.y), inv_proj);
	float dn = sample_linear_depth(uv + vec2(0.0, texel.y), inv_proj);
	float curvature = abs(l + r - 2.0 * center_depth) + abs(u + dn - 2.0 * center_depth);
	float rel = curvature / max(center_depth, 0.05);
	return step(depth_edge_threshold, rel);
}

void fragment() {
	// Pas de `return` anticipé : Godot interdit `return` dans fragment() — on
	// branche donc sur `enabled` pour tout le corps de la fonction. Le repli
	// (désactivé, ou aucun bord) est ALPHA = 0 : un quad plein écran mais
	// entièrement transparent ne touche à RIEN de ce qui est dessous.
	float edge = 0.0;
	vec3 tinted_ink = ink_color.rgb;

	if (enabled) {
		float d_c = texture(depth_tex, SCREEN_UV).r;
		float l_c = linear_depth(d_c, SCREEN_UV, INV_PROJECTION_MATRIX);
		vec2 px = 1.0 / VIEWPORT_SIZE;

		// This pixel's own local outline width (px), interpolated by ITS
		// depth, then dilate the depth-edge test out to that many samples --
		// a near, thick line close up; a thin one far away; held at
		// `width_far_px` beyond `width_far_m`.
		float t_width = clamp((l_c - width_near_m) / max(width_far_m - width_near_m, 0.001), 0.0, 1.0);
		float width_px = mix(width_near_px, width_far_px, t_width);

		for (int i = 1; i <= 8; i++) {
			if (float(i) > width_px) { break; }
			edge = max(edge, depth_response(SCREEN_UV, px * float(i), l_c, INV_PROJECTION_MATRIX));
		}

		// Opacity floors at 40% by 90 m instead of fading to nothing (design.md
		// v2 SS5) -- outlines stay legible at range instead of disappearing.
		float t_op = clamp(l_c / max(opacity_far_m, 0.001), 0.0, 1.0);
		float opacity = mix(1.0, opacity_far_floor, t_op);
		edge *= opacity;

		// Far outlines pick up the haze colour, ramping in with the same
		// fog window used by LevelLook's world fog (35 m -> 120 m, 30% max).
		float fog_amount = clamp((l_c - fog_start_m) / max(fog_end_m - fog_start_m, 0.001), 0.0, 1.0) * fog_max_amount;
		tinted_ink = mix(ink_color.rgb, haze_color.rgb, fog_amount);
	}

	// ONLY the ink line is drawn (ALBEDO + ALPHA = the edge mask) -- the
	// scene's own colour is never read or re-output, so this quad can never
	// blot out a transparent object drawn under or after it, whatever the
	// transparent draw order turns out to be that frame.
	ALBEDO = tinted_ink;
	ALPHA = clamp(edge, 0.0, 1.0);
}
