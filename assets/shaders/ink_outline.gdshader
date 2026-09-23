// ink_outline.gdshader
// Ink hull: inverted-hull outline (design.md v2 SS5 "Outlines") posed as a
// `next_pass` on an ink_toon material, or chained again for the enemy
// highlight's outer ink ring (Cartoon.character(highlight_color=...)).
// Standard Godot 4 technique -- extrude along the vertex normal in CLIP
// SPACE at a constant width in PIXELS, independent of camera distance
// (`cull_front`: only the inside of the inflated shell is visible, framing
// the object).
//
// Distance falloff (design.md SS5, "Characters: ink #1A1410 hull, 3 px to
// 10 m, 2 px at 40 m, 1.5 px floor"): OFF by default (props/pickups/
// viewmodel and the enemy highlight hull all want a FLAT width -- SS5:
// "Viewmodel and pickups: 2 px ink", "Enemies: ... that never fades").
// Cartoon.character()'s default (ally/plain) outline turns it on. The 3
// breakpoints are a piecewise approximation: linear from `outline_width_px`
// at `falloff_near_m` down to `falloff_far_px` at `falloff_far_m`, then an
// asymptotic further approach toward `falloff_floor_px` beyond that --
// clamped so it can never go below the floor.
shader_type spatial;
render_mode cull_front, unshaded, depth_draw_always;

// #1A1410 locked (Cartoon.INK, design.md SS5) -- always overwritten by the
// material builder in Cartoon.gd; this default only matters if the shader
// is used standalone.
uniform vec4 outline_color : source_color = vec4(0.1020, 0.0784, 0.0627, 1.0);
uniform float outline_width_px : hint_range(0.0, 16.0) = 3.0;

uniform bool distance_falloff = false;
uniform float falloff_near_m : hint_range(1.0, 50.0) = 10.0;
uniform float falloff_far_m : hint_range(1.0, 100.0) = 40.0;
uniform float falloff_far_px : hint_range(0.5, 16.0) = 2.0;
uniform float falloff_floor_px : hint_range(0.5, 16.0) = 1.5;

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float width_px = outline_width_px;
	if (distance_falloff) {
		float dist = -view_pos.z;
		float t_near_far = clamp((dist - falloff_near_m) / max(falloff_far_m - falloff_near_m, 0.001), 0.0, 1.0);
		float w = mix(outline_width_px, falloff_far_px, t_near_far);
		float t_beyond = clamp((dist - falloff_far_m) / max(falloff_far_m, 0.001), 0.0, 1.0);
		w = mix(w, falloff_floor_px, t_beyond * 0.6);
		width_px = max(w, falloff_floor_px);
	}
	vec4 clip_position = PROJECTION_MATRIX * view_pos;
	vec3 clip_normal = normalize((PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(NORMAL, 0.0))).xyz);
	// Largeur constante a l'ecran : l'offset en clip-space est mis a l'echelle
	// par clip_position.w (distance) pour compenser la division perspective,
	// et par 1/VIEWPORT_SIZE pour convertir des pixels en unites NDC.
	vec2 offset_px = clip_normal.xy * width_px;
	clip_position.xy += offset_px / VIEWPORT_SIZE * clip_position.w * 2.0;
	POSITION = clip_position;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
