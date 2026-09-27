// death_tint.gdshader
// Habillage de l'écran de mort (contrat lead 2026-09-27, "DEATH SCREEN") :
// désature la vue derrière l'interface, la teinte de rouge (multiply) puis
// pose une trame de points (halftone) en vignette -- épargnée au centre,
// marquée sur les bords (comme la maquette reports/ui/mockups/death.html,
// .grey/.tint/.dotsr). Lu par un ColorRect plein écran (DeathScreen.gd) :
// `screen_texture` capture tout ce qui a déjà été dessiné derrière ce
// ColorRect (scène 3D + HUD sous-jacent), voir docs Godot 4.7
// "Screen-reading shaders" (hint_screen_texture / SCREEN_UV).
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float desaturate : hint_range(0.0, 1.0) = 0.75;
uniform vec4 tint_color : source_color = vec4(0.910, 0.224, 0.180, 0.5);
uniform float dot_pitch_px : hint_range(4.0, 64.0) = 20.0;
uniform float dot_radius_ratio : hint_range(0.0, 1.0) = 0.32;
uniform vec4 dot_color : source_color = vec4(0.106, 0.063, 0.188, 1.0);
uniform float vignette_inner : hint_range(0.0, 1.5) = 0.2;
uniform float vignette_outer : hint_range(0.0, 1.5) = 0.95;
uniform vec2 screen_size = vec2(1920.0, 1080.0);

void fragment() {
	vec3 c = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;

	// désaturation partielle (garde un peu de la couleur d'origine).
	float gray = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(gray), desaturate);

	// teinte rouge « multiply » (mix vers le produit c*tint, pondéré par l'alpha).
	c = mix(c, c * tint_color.rgb, tint_color.a);

	// trame de points -- pas en pixels ÉCRAN (indépendant du zoom UI).
	vec2 px = SCREEN_UV * screen_size;
	vec2 cell = mod(px, vec2(dot_pitch_px)) - vec2(dot_pitch_px) * 0.5;
	float d = length(cell) / (dot_pitch_px * 0.5);
	float dot_mask = 1.0 - smoothstep(dot_radius_ratio, dot_radius_ratio + 0.2, d);

	// vignette : centre épargné (K.O./carte du tueur y restent lisibles), bords couverts.
	vec2 centered = SCREEN_UV - vec2(0.5, 0.45);
	centered.x *= screen_size.x / max(screen_size.y, 1.0);
	float r = length(centered) * 2.0;
	float vig = smoothstep(vignette_inner, vignette_outer, r);

	c = mix(c, dot_color.rgb, dot_mask * vig * dot_color.a * 0.6);

	COLOR = vec4(c, 1.0);
}
