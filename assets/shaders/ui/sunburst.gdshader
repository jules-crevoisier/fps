// sunburst.gdshader
// Fond du salon (reports/ui/mockups/ui.css .sky/.dots-light/.burst) en UN seul
// shader canvas_item réutilisable : dégradé diagonal + trame de points (toujours
// actifs) + rayons de soleil BD optionnels (centrés sur `burst_center`, utilisés
// derrière un héros/une arme sur la scène d'armurerie). `rect_size_px` doit être
// tenu à jour par l'appelant (voir MenuWidgets.sunburst_background) pour que le
// cercle de rayons et le pas de la trame restent en PIXELS RÉELS quelle que
// soit la taille du Control porteur.
shader_type canvas_item;

uniform vec4 grad_top : source_color = vec4(0.235, 0.608, 1.0, 1.0);
uniform vec4 grad_mid : source_color = vec4(0.180, 0.545, 1.0, 1.0);
uniform vec4 grad_bottom : source_color = vec4(0.114, 0.373, 0.839, 1.0);
uniform float grad_mid_stop : hint_range(0.0, 1.0) = 0.45;
uniform float grad_angle_deg = 160.0;

uniform bool dots_enabled = true;
uniform vec4 dot_color : source_color = vec4(1.0, 1.0, 1.0, 0.18);
uniform float dot_spacing_px = 16.0;
uniform float dot_radius_px = 4.0;

uniform bool burst_enabled = false;
uniform vec2 burst_center = vec2(0.5, 0.5);
uniform float burst_radius_px = 590.0;
uniform vec4 burst_color_a : source_color = vec4(1.0, 0.847, 0.290, 1.0);
uniform vec4 burst_color_b : source_color = vec4(1.0, 0.698, 0.122, 1.0);
uniform float burst_wedge_deg = 9.0;
uniform float burst_inner_fade = 0.38;
uniform float burst_outer_fade = 0.72;

uniform vec2 rect_size_px = vec2(1920.0, 1080.0);

void fragment() {
	vec2 px = UV * rect_size_px;

	float rad = radians(grad_angle_deg);
	vec2 dir = normalize(vec2(sin(rad), -cos(rad)));
	float t = clamp(dot(UV - 0.5, dir) + 0.5, 0.0, 1.0);
	vec4 col = t < grad_mid_stop
		? mix(grad_top, grad_mid, t / max(grad_mid_stop, 0.001))
		: mix(grad_mid, grad_bottom, (t - grad_mid_stop) / max(1.0 - grad_mid_stop, 0.001));

	if (burst_enabled) {
		vec2 center_px = burst_center * rect_size_px;
		vec2 d = px - center_px;
		float dist = length(d);
		float ang = degrees(atan(d.y, d.x));
		ang = mod(ang + 360.0, 360.0);
		float seg = mod(ang, burst_wedge_deg * 2.0);
		vec4 ray_col = seg < burst_wedge_deg ? burst_color_a : burst_color_b;
		float fade = smoothstep(burst_inner_fade * burst_radius_px, burst_outer_fade * burst_radius_px, dist);
		col = mix(ray_col, col, fade);
	}

	if (dots_enabled) {
		vec2 cell = mod(px, dot_spacing_px) - dot_spacing_px * 0.5;
		float dd = length(cell);
		float dot_mask = 1.0 - smoothstep(dot_radius_px - 1.0, dot_radius_px, dd);
		col.rgb = mix(col.rgb, dot_color.rgb, dot_mask * dot_color.a);
	}

	COLOR = col;
}
