// toon_bd_outline.gdshader
// Contour post-traitement (art/style/toon_style.json v2 "outline") -- coeur du
// second ingrédient Borderlands identifié par la recherche lead : un trait NOIR
// FIN par-dessus toute la scène (silhouettes ET plis), Sobel sur profondeur +
// normales, PAS un contour par objet (ink_outline.gdshader, next_pass, retiré du
// pipeline pour tout ce qui utilise toon_bd.gdshader).
//
// Implémentation : "spatial full-screen quad" (Godot 4.7 docs, "Advanced
// post-processing" > "Full screen quad") plutôt qu'un CompositorEffect RD -- ce
// choix est documenté dans art/style/README.md (§ Pourquoi pas un
// CompositorEffect) : la technique du quad plein écran est explicitement citée
// comme repli valide par le contrat de tâche, s'appuie sur les hints
// `hint_depth_texture`/`hint_normal_roughness_texture` DÉJÀ éprouvés dans ce
// moteur/version (aucune API RenderingDevice bas niveau à faire fonctionner à
// l'aveugle), et correspond au type d'implémentation de la référence citée par le
// JSON (godotshaders.com "3D edge detection shader Borderlands style").
//
// Posé par ScriptRendering/ToonOutlineQuad.gd (lui-même piloté par
// ToonStyle.add_outline_pass(camera)) : un MeshInstance3D enfant de la Camera3D,
// QuadMesh 2x2, dont `vertex()` court-circuite la transformation standard
// (POSITION = vec4(VERTEX.xy, 1.0, 1.0) -- recette officielle "Full screen quad",
// compatible Z inversé Godot 4.3+) pour couvrir tout l'écran en espace clip, quel
// que soit son transform local réel (seule sa présence dans l'arbre + un
// `extra_cull_margin` large lui évitent d'être culled -- voir ToonOutlineQuad.gd).
shader_type spatial;
render_mode unshaded, fog_disabled, blend_mix, cull_disabled, depth_test_disabled;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_roughness_texture : hint_normal_roughness_texture, repeat_disable, filter_nearest;

group_uniforms outline;
uniform vec4 outline_color : source_color = vec4(0.0549, 0.0392, 0.0706, 1.0);
uniform float width_px_at_1080p = 1.5;
uniform float min_width_px = 1.0;
uniform float depth_threshold = 0.015;
uniform float normal_threshold_deg = 30.0;
uniform float fade_start_m = 25.0;
uniform float fade_end_m = 70.0;

// Poussé par ToonOutlineQuad.gd à chaque frame/redimensionnement (repli fiable :
// ne dépend pas de la disponibilité d'un VIEWPORT_SIZE dans ce contexte de quad).
uniform vec2 viewport_size = vec2(1920.0, 1080.0);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// Reconstruction espace vue (Godot 4.7 docs, "Visualize linear depth or world
// space coordinates") -- profondeur non-linéaire -> position vue via la matrice
// de projection inverse, disponible nativement dans un shader spatial (pas besoin
// de la pousser nous-mêmes, contrairement à `viewport_size`).
// `inv_proj` en paramètre (jamais INV_PROJECTION_MATRIX lu ici) : voir la
// note de toon_bd.gdshader::_halftone_mask, même contrainte du moteur.
vec3 _view_pos(vec2 uv, float depth, mat4 inv_proj) {
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
	vec4 view = inv_proj * vec4(ndc, 1.0);
	return view.xyz / view.w;
}

void fragment() {
	float px = max(width_px_at_1080p * (viewport_size.y / 1080.0), min_width_px);
	vec2 texel = px / viewport_size;

	float d_c = texture(depth_texture, SCREEN_UV).x;
	vec3 vp_c = _view_pos(SCREEN_UV, d_c, INV_PROJECTION_MATRIX);
	vec3 n_c = normalize(texture(normal_roughness_texture, SCREEN_UV).xyz * 2.0 - 1.0);

	float cos_threshold = cos(radians(normal_threshold_deg));
	float edge = 0.0;
	vec2 offsets[4] = vec2[](vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0));
	for (int i = 0; i < 4; i++) {
		vec2 uv2 = SCREEN_UV + offsets[i] * texel;
		float d2 = texture(depth_texture, uv2).x;
		vec3 vp2 = _view_pos(uv2, d2, INV_PROJECTION_MATRIX);
		// Seuil RELATIF (proportionnel à la distance) : un écart absolu fixe
		// serait soit invisible au loin (précision de profondeur), soit trop
		// sensible de près (toute la géométrie courbe "grenaille").
		float rel_diff = abs(vp_c.z - vp2.z) / max(abs(vp_c.z), 0.05);
		if (rel_diff > depth_threshold) {
			edge = 1.0;
		}
		vec3 n2 = normalize(texture(normal_roughness_texture, uv2).xyz * 2.0 - 1.0);
		if (dot(n_c, n2) < cos_threshold) {
			edge = 1.0;
		}
	}

	float dist_m = -vp_c.z; // vue Godot : -Z devant la caméra.
	float fade = 1.0 - smoothstep(fade_start_m, fade_end_m, dist_m);

	ALBEDO = outline_color.rgb;
	ALPHA = edge * outline_color.a * fade;
}
