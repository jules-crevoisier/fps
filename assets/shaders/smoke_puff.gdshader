// smoke_puff.gdshader — bouffée de fumigène BD : aplat deux tons (clair dessus, ombre
// dessous, limite nette), indépendant de l'éclairage de la carte. Avec toon_bd, la face
// à l'ombre prenait l'ambiance bleue du ciel et le nuage virait au bleu ciel (revue
// captures 2026-09-27). Opaque : le fumigène doit cacher ce qu'il y a derrière ; le
// contour encré vient du post-traitement plein écran, comme pour le reste du jeu.
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 lit_color : source_color = vec3(0.93, 0.91, 0.87);
uniform vec3 shade_color : source_color = vec3(0.71, 0.68, 0.65);
// Lumière « de dessus », un peu de biais : l'ombre tombe sous chaque bouffée.
uniform vec3 light_dir_world = vec3(0.35, 1.0, 0.25);
uniform float edge_softness : hint_range(0.0, 0.3) = 0.04;
uniform float shade_bias : hint_range(-1.0, 1.0) = -0.15;

void fragment() {
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float d = dot(n_world, normalize(light_dir_world)) - shade_bias;
	float t = smoothstep(-edge_softness, edge_softness, d);
	ALBEDO = mix(shade_color, lit_color, t);
}
