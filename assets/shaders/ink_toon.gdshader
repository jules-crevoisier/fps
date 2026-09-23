// ink_toon.gdshader
// "Peint au soleil, encre gras" (.orchestrator/design.md v2, SS4/SS6) -- the
// PAINTED toon material. Replaces v1's desaturated "encre et papier" ramp:
// the world stays loud (rust/sand/containers), colour is reserved for
// enemies only. Ink itself now lives in the PAINTED TEXTURES (baked seam/
// curvature lines, see tools/textures/gen_textures.py) rather than in a
// procedural hatching overlay -- v1's hatching and paper grain are gone
// entirely (design.md SS3 "so:" / SS6 "Rules: Ink").
//
// Three ways to use this shader (all built by Cartoon.gd, scripts/core/):
//  - world()/prop()/character(): flat `albedo_color`, `use_albedo_texture`
//    false -- unchanged from v1's call shape, still just a flat tint.
//  - painted(kind, tint): `use_albedo_texture` + `use_triplanar` true, a
//    painted material from the library sampled in WORLD SPACE (Godot 4.7
//    docs, "Large world coordinates": triplanar/world coords must be
//    computed in vertex() and passed via a varying, not reconstructed in
//    fragment() -- see `world_pos`/`world_normal` below) with `albedo_color`
//    now acting as a multiplicative TINT (e.g. container red/blue/orange).
//  - character_surface(kind, color): flat colour + `paint_grain_strength` >
//    0, a light OBJECT-SPACE noise (from raw, un-skinned `VERTEX`, not
//    `world_pos`) for a hand-painted feel on skin/cloth/gear -- object-space
//    on purpose: characters move, so grain tied to world position would
//    visibly crawl across the mesh as they walk.
//
// Lighting ramp (design.md SS4 "Lighting script"): three bands by default,
// the MIDDLE ("terminator") band gets a +15% chroma boost so the light/
// shadow break reads as a hand-painted edge, not a flat cutoff. Shadow =
// albedo x a coloured tint (blue-violet family, "never grey") at 55-60% of
// the lit value, with `shadow_strength`'s hint_range hard-floored at 0.45
// so it can never crush toward black. A small downward-facing EMISSION term
// approximates the doc's "15% sand bounce" ambient without needing a second
// light. Characters keep their team/enemy colour via the `rim_color`/
// `rim_strength` instance uniforms (Cartoon.set_rim) -- untouched by this
// rework.
shader_type spatial;
render_mode blend_mix, cull_back, specular_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo_texture = false;

// Triplanar (world-space) sampling for painted() materials -- Godot 4.7 docs
// "BaseMaterial3D.uv1_triplanar": blend by the surface normal, read 3 times.
uniform bool use_triplanar = false;
uniform float triplanar_scale : hint_range(0.02, 2.0) = 0.33;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;

// Grime overlay (tools/textures/gen_textures.py's *_grime.png masks):
// darkens the base albedo where the mask is bright, independent tiling
// scale so the grime doesn't lock-step with the albedo repeat.
uniform sampler2D grime_texture : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform bool use_grime_texture = false;
uniform float grime_scale : hint_range(0.02, 2.0) = 0.6;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.35;

// -- Lighting ramp (design.md SS4) ------------------------------------------
uniform float band_count : hint_range(2.0, 4.0, 1.0) = 3.0;
uniform float band_softness : hint_range(0.0, 0.25) = 0.05;

// Blue-violet coloured shadow -- never grey, never under 45% of lit value.
uniform vec4 shadow_tint : source_color = vec4(0.361, 0.431, 0.659, 1.0); // #5C6EA8
uniform float shadow_strength : hint_range(0.45, 0.60) = 0.58;

// Terminator ("middle band") hot edge: +15% chroma by default.
uniform float hot_edge_chroma : hint_range(0.0, 0.5) = 0.15;
uniform float hot_edge_strength : hint_range(0.0, 1.0) = 1.0;

// Approximates design.md's "+15% sand bounce" ambient: a soft warm fill on
// downward-facing surfaces (undersides catch light bounced off the ground),
// independent of any real light so it also shows fully in shadow.
uniform vec4 ground_bounce_color : source_color = vec4(0.851, 0.631, 0.361, 1.0); // Sable #D9A15C
uniform float ground_bounce_strength : hint_range(0.0, 0.4) = 0.15;

// Object-space paint grain (character_surface() slots -- design.md SS6
// "Detail: base noise <= +/-6%"). 0 by default: painted() textures already
// carry their own baked detail and don't need this on top.
uniform float paint_grain_strength : hint_range(0.0, 0.12) = 0.0;

instance uniform vec4 rim_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
instance uniform float rim_strength : hint_range(0.0, 3.0) = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 object_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Raw model-space position (NOT multiplied by MODEL_MATRIX): fixed
	// relative to the mesh's own surface, so it rides along with a moving/
	// skinned character instead of sliding across it like world_pos would.
	object_pos = VERTEX;
}

// Stable 3D hash (no flicker frame-to-frame, no dependency on screen res).
float hash13(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

// Triplanar lookup: 3 axis-aligned projections blended by |normal|^sharpness
// (Godot 4.7 docs, BaseMaterial3D triplanar). World-space UVs, so adjacent
// meshes sharing a material tile seamlessly with no per-mesh UV authoring.
vec4 triplanar_sample(sampler2D tex, vec3 pos, vec3 nrm, float scale) {
	vec3 blend = pow(abs(nrm), vec3(triplanar_sharpness));
	blend /= max(blend.x + blend.y + blend.z, 0.0001);
	vec4 cx = texture(tex, pos.zy * scale);
	vec4 cy = texture(tex, pos.xz * scale);
	vec4 cz = texture(tex, pos.xy * scale);
	return cx * blend.x + cy * blend.y + cz * blend.z;
}

void fragment() {
	vec4 base = albedo_color;
	if (use_albedo_texture) {
		vec4 tex_color = use_triplanar
			? triplanar_sample(albedo_texture, world_pos, world_normal, triplanar_scale)
			: texture(albedo_texture, UV);
		base *= tex_color;
		if (use_grime_texture) {
			vec4 grime = use_triplanar
				? triplanar_sample(grime_texture, world_pos, world_normal, grime_scale)
				: texture(grime_texture, UV);
			base.rgb *= mix(1.0, 1.0 - grime.r, grime_strength);
		}
	}

	if (paint_grain_strength > 0.0) {
		float grain = hash13(floor(object_pos * 220.0)) - 0.5;
		base.rgb = clamp(base.rgb + grain * paint_grain_strength, 0.0, 1.0);
	}

	ALBEDO = base.rgb;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;

	// Ground bounce: only the underside of geometry (normal pointing down)
	// picks it up, and it is NOT gated by any light -- it is ambient bounce.
	float bounce_mask = clamp(-world_normal.y, 0.0, 1.0);
	EMISSION = ground_bounce_color.rgb * ALBEDO * bounce_mask * ground_bounce_strength;

	if (rim_strength > 0.0) {
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		EMISSION += rim_color.rgb * fres * rim_strength;
	}
}

void light() {
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float bands = max(band_count, 2.0);
	float step_pos = ndotl * bands;
	float band_index = clamp(floor(step_pos), 0.0, bands - 1.0);
	float frac_edge = smoothstep(0.5 - band_softness, 0.5 + band_softness, fract(step_pos));
	float banded = clamp(band_index / bands + frac_edge / bands, 0.0, 1.0);
	// Shadow maps fall straight into the darkest band -- ATTENUATION already
	// carries occlusion, so it directly scales the ramp's lit fraction.
	banded *= ATTENUATION;

	vec3 shadow_color = ALBEDO * shadow_tint.rgb * shadow_strength;
	vec3 ramp = mix(shadow_color, ALBEDO, banded);

	// Hot edge: the ramp's MIDDLE band (design.md SS4) gets extra chroma, so
	// the light/shadow break reads as a hand-painted line rather than a flat
	// cut. Gated by ATTENUATION so it never lights up deep inside a cast
	// shadow, where `band_index` alone can't tell "terminator" from "dark".
	float mid_index = floor((bands - 1.0) * 0.5);
	float is_terminator = 1.0 - clamp(abs(band_index - mid_index), 0.0, 1.0);
	is_terminator *= smoothstep(0.05, 0.3, ATTENUATION);
	float luma = dot(ramp, vec3(0.299, 0.587, 0.114));
	vec3 hot = luma + (ramp - luma) * (1.0 + hot_edge_chroma);
	ramp = mix(ramp, hot, is_terminator * hot_edge_strength);

	// WYSIWYG toon: only the light's HUE feeds the ramp (normalized by its
	// max channel), not its raw intensity -- level scenes don't tune
	// DirectionalLight3D energy against this shader's own band math.
	vec3 light_tint = LIGHT_COLOR / max(max(LIGHT_COLOR.r, max(LIGHT_COLOR.g, LIGHT_COLOR.b)), 0.001);
	DIFFUSE_LIGHT += ramp * light_tint;
}
