// minimap.gdshader
// Stylise la capture brute (SubViewport top-down, MinimapHUD.gd) comme la maquette validée
// (tools/ui/make_icons.py, reports/ui/renders/hud.png) : ce qui est COLORÉ (conteneurs, décor
// peint) garde sa teinte, saturée et éclaircie ; ce qui est gris (sol, murs de périmètre)
// devient l'encre violette du HUD -- sol #2B2244, reliefs clairs #4A3F6E. Le critère est la
// SATURATION, pas la luminance : un conteneur rouge sombre reste un conteneur.
shader_type canvas_item;

uniform vec4 floor_color : source_color = vec4(0.169, 0.133, 0.267, 1.0); // #2B2244
uniform vec4 wall_color : source_color = vec4(0.290, 0.247, 0.431, 1.0);  // #4A3F6E
uniform float saturation_threshold : hint_range(0.0, 1.0) = 0.16;
uniform float wall_brightness : hint_range(0.0, 1.0) = 0.5;
uniform float color_boost : hint_range(0.0, 3.0) = 1.6;
uniform float color_lift : hint_range(0.5, 2.0) = 1.15;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float mx = max(tex.r, max(tex.g, tex.b));
	float mn = min(tex.r, min(tex.g, tex.b));
	float sat = (mx - mn) / max(mx, 0.001);
	float mean = (tex.r + tex.g + tex.b) / 3.0;
	vec3 boosted = clamp((tex.rgb - vec3(mean)) * color_boost + vec3(mean) * color_lift, 0.0, 1.0);
	vec3 grey = mx > wall_brightness ? wall_color.rgb : floor_color.rgb;
	float colored = smoothstep(saturation_threshold - 0.03, saturation_threshold + 0.03, sat);
	COLOR = vec4(mix(grey, boosted, colored), tex.a);
}
