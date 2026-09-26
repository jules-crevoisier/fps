// toon_bd.gdshader
// Style "BD façon Borderlands" (art/style/toon_style.json v2, tâche "tirer vraiment
// sur Borderlands" 2026-09-26) -- remplace la rampe à bandes plates de
// ink_toon.gdshader par un éclairage RÉEL sharpened_lambert (recherche lead : Borderlands
// n'est pas un cel-shading à bandes -- voir toon_style.json.shading.note) :
//   - `shading` : smoothstep resserré (largeur `sharpness`) autour d'un terminator
//     (`terminator`), sur N·L wrappé (`wrap`) x ombre portée (ATTENUATION).
//   - `shadow_tint` : la zone d'ombre n'est jamais un simple noircissement -- c'est
//     l'ALBÉDO dont la teinte est décalée (`hue_shift_deg`) et la saturation
//     accentuée (`saturation_mult`), assombri par `shadow_value`.
//   - `rim` : liseré chaud fresnel, uniquement du côté éclairé (`lit_side_only`,
//     gate = `lit_amount` du terminator ci-dessus).
//   - `specular` : reflet doux fixe (indépendant du glossiness importé -- ce shader
//     n'a pas de carte de rugosité, `specular.size/softness/intensity` du JSON).
//   - `halftone` : trame en pointillés en espace écran, présente mais OFF par défaut
//     (toon_style.json halftone.enabled=false) -- gardée pour des effets ponctuels.
// Le CONTOUR (encre) n'est PAS ici : toon_style.json.outline.method =
// "post_process_sobel" -- géré entièrement par le pass plein écran
// (assets/shaders/toon_bd_outline.gdshader + scripts/rendering/ToonOutlineQuad.gd),
// jamais par un `next_pass` par matériau comme l'ancien ink_outline.gdshader.
//
// Compat. équipe (PlayerLook.gd/Cartoon.set_rim) : `rim_color`/`rim_strength` sont
// des `instance uniform` -- Cartoon.set_rim(mesh, color, strength) continue de
// fonctionner tel quel sur un mesh utilisant CE shader (flash de hit, rim
// allié/ennemi) sans dépendre d'un nom de paramètre par kind. Le contour d'ÉQUIPE
// (coque colorée ennemie) reste porté par `Cartoon.apply_team_outline` via
// `next_pass` sur le matériau -- mécanisme agnostique du shader de base, inchangé.
//
// Tous les paramètres ci-dessous ont pour valeur par défaut EXACTEMENT
// art/style/toon_style.json v2 (voir ToonStyle.gd, source unique qui les pousse à
// l'exécution) -- les défauts ici ne sont qu'un filet si le matériau est utilisé
// sans passer par ToonStyle (ex. prévisualisation éditeur).
shader_type spatial;
// Pas de `specular_disabled` : rim/reflet/flash passent par SPECULAR_LIGHT dans
// light(). SPECULAR = 0 dans fragment() coupe déjà les reflets d'environnement.
render_mode blend_mix, cull_back;

group_uniforms albedo;
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool use_albedo_texture = false;

group_uniforms shading;
uniform float wrap : hint_range(0.0, 1.0) = 0.1;
uniform float terminator : hint_range(0.0, 1.0) = 0.45;
uniform float sharpness : hint_range(0.001, 1.0) = 0.12;
uniform float shadow_value : hint_range(0.0, 1.0) = 0.42;

group_uniforms shadow_tint;
uniform float shadow_hue_shift_deg = -8.0;
uniform float shadow_saturation_mult : hint_range(0.0, 3.0) = 1.25;

group_uniforms rim;
uniform bool rim_enabled = true;
uniform float rim_power : hint_range(0.5, 8.0) = 4.0;
uniform float rim_threshold : hint_range(0.0, 1.0) = 0.55;
uniform float rim_softness : hint_range(0.001, 1.0) = 0.08;
uniform float rim_intensity : hint_range(0.0, 2.0) = 0.25;
uniform vec4 rim_tint : source_color = vec4(1.0, 0.9137, 0.7216, 1.0);
uniform bool rim_lit_side_only = true;

group_uniforms specular;
uniform bool specular_enabled = true;
uniform float specular_size : hint_range(0.0, 1.0) = 0.18;
uniform float specular_softness : hint_range(0.001, 1.0) = 0.12;
uniform float specular_intensity : hint_range(0.0, 2.0) = 0.25;
uniform vec4 specular_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

group_uniforms halftone;
uniform bool halftone_enabled = false;
uniform float halftone_cell_px = 7.0;
uniform float halftone_angle_deg = 45.0;
// Pas de `VIEWPORT_SIZE` builtin dans ce contexte (fragment() d'un shader
// spatial standard, confirmé par un échec de compilation à l'exécution --
// contrairement au quad plein écran de toon_bd_outline.gdshader, qui reçoit sa
// propre `viewport_size` explicite pour la même raison) : ToonStyle.gd la pose
// une fois à la création du matériau (DisplayServer, jamais mise à jour au
// redimensionnement -- acceptable, la trame est une option DÉSACTIVÉE par
// défaut, jamais le contour lui-même).
uniform vec2 viewport_size = vec2(1920.0, 1080.0);

group_uniforms team_compat;
// Cartoon.set_rim(mesh, color, strength) -- PlayerLook.gd (rim de repos allié/
// ennemi, flash de hit GF-10). Additif, indépendant de `rim_enabled` ci-dessus :
// inerte tant qu'aucun appelant ne pose `rim_strength` > 0 (défaut 0).
instance uniform vec4 rim_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
instance uniform float rim_strength = 0.0;

// -- HSV (domaine public, Sam Hocevar) -- teinte/saturation de la zone d'ombre. --
vec3 _rgb2hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 _hsv2rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

// Ombre colorée (toon_style.json shadow_tint) : décalage de teinte + saturation
// accrue sur l'ALBÉDO lui-même -- jamais un simple facteur gris, jamais une
// couleur d'ombre indépendante de l'objet (deux objets de couleurs différentes
// gardent des ombres de teintes différentes, cohérentes avec leur propre albédo).
vec3 _shadow_tint(vec3 albedo) {
	vec3 hsv = _rgb2hsv(max(albedo, vec3(0.0)));
	hsv.x = fract(hsv.x + shadow_hue_shift_deg / 360.0);
	hsv.y = clamp(hsv.y * shadow_saturation_mult, 0.0, 1.0);
	return _hsv2rgb(hsv);
}

// Trame en pointillés plein écran (toon_style.json halftone, OFF par défaut) --
// cellule en px À 1080p, mise à l'échelle par la hauteur RÉELLE du viewport (même
// convention que le contour post-process, voir ToonOutlineQuad.gd).
// `screen_uv` est passé en paramètre (jamais lu directement ici) : les
// builtins de contexte fragment (SCREEN_UV, INV_PROJECTION_MATRIX...) ne sont
// PAS visibles depuis une fonction globale séparée dans ce moteur/version
// (vérifié à l'exécution -- "Unknown identifier" sinon), seulement DANS
// vertex()/fragment()/light() eux-mêmes. Même contrainte, même parade dans
// toon_bd_outline.gdshader::_view_pos.
float _halftone_mask(vec3 albedo, vec2 screen_uv) {
	float luma = dot(albedo, vec3(0.299, 0.587, 0.114));
	float cell = max(halftone_cell_px * (viewport_size.y / 1080.0), 1.0);
	float a = radians(halftone_angle_deg);
	vec2 px = screen_uv * viewport_size;
	vec2 rotated = vec2(px.x * cos(a) - px.y * sin(a), px.x * sin(a) + px.y * cos(a));
	vec2 cell_uv = mod(rotated, cell) / cell - 0.5;
	float dist = length(cell_uv);
	float radius = clamp(1.0 - luma, 0.0, 1.0) * 0.7;
	return 1.0 - smoothstep(radius - 0.05, radius + 0.05, dist);
}

void vertex() {
}

void fragment() {
	vec4 base = albedo_color;
	if (use_albedo_texture) {
		base *= texture(albedo_texture, UV);
	}
	if (halftone_enabled) {
		base.rgb *= mix(0.35, 1.0, _halftone_mask(base.rgb, SCREEN_UV));
	}
	ALBEDO = base.rgb;
	// Jamais d'écriture d'ALPHA : elle bascule le matériau dans la passe transparente,
	// hors du pré-passage profondeur/normales -- plus de contour post-traitement ni
	// d'ombres portées (même piège que l'ancien dev_grid « murs transparents »).
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;

	// -- compat. Cartoon.set_rim (liseré d'équipe / flash de touche) ---------
	// Une seule fois par pixel (EMISSION), jamais par lumière. Force <= 1 (liseré
	// d'équipe 0.6, ciel 0.2) : fine bande nette sur la silhouette. Force > 1
	// (flash de touche 2.0, mannequin 1.4) : la bande s'élargit à tout le corps.
	if (rim_strength > 0.0) {
		float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float band = smoothstep(0.84, 0.90, fres);
		float cover = mix(band, 1.0, clamp(rim_strength - 1.0, 0.0, 1.0));
		EMISSION += rim_color.rgb * cover * min(rim_strength, 1.0);
	}
}

void light() {
	// -- sharpened_lambert (toon_style.json shading) ------------------------
	float ndotl = dot(NORMAL, LIGHT);
	float wrapped = clamp((ndotl + wrap) / (1.0 + wrap), 0.0, 1.0);
	// "N·L × ombre portée" (JSON note) : ATTENUATION porte déjà l'ombre projetée
	// pour une DirectionalLight3D (voir LevelLook.gd/ink_toon.gdshader, même
	// moteur/version -- pas de distance à atténuer sur un soleil).
	float shaded = wrapped * ATTENUATION;
	float lit_amount = smoothstep(terminator - sharpness * 0.5, terminator + sharpness * 0.5, shaded);

	// Doc Godot 4.7 (spatial shader, light built-ins) : LIGHT_COLOR est déjà
	// multiplié par PI (« / PI » dans l'exemple Lambert officiel), et le moteur
	// multiplie ENSUITE DIFFUSE_LIGHT par l'albédo. La rampe s'exprime donc en
	// facteur relatif à l'albédo (1 = plein éclairage) : l'ombre teintée devient
	// le rapport ombre_teintée / albédo, que le moteur remultiplie par l'albédo.
	vec3 light_rgb = LIGHT_COLOR / PI;
	vec3 shadow_col = _shadow_tint(ALBEDO) * clamp(shadow_value, 0.0, 1.0);
	vec3 shadow_ratio = shadow_col / max(ALBEDO, vec3(0.02));
	vec3 ramp = mix(shadow_ratio, vec3(1.0), lit_amount);
	DIFFUSE_LIGHT += ramp * light_rgb;

	// Rim, reflet et flash d'équipe : lumière ajoutée, pas teintée par l'albédo
	// -> SPECULAR_LIGHT (non multiplié par l'albédo).
	// -- rim chaud, côté éclairé seulement (toon_style.json rim) -------------
	if (rim_enabled) {
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
		float band = smoothstep(rim_threshold - rim_softness * 0.5, rim_threshold + rim_softness * 0.5, fres);
		float side = rim_lit_side_only ? lit_amount : 1.0;
		SPECULAR_LIGHT += rim_tint.rgb * band * rim_intensity * side * light_rgb;
	}

	// -- reflet doux fixe (toon_style.json specular) -------------------------
	if (specular_enabled) {
		vec3 half_vec = normalize(LIGHT + VIEW);
		float ndoth = clamp(dot(NORMAL, half_vec), 0.0, 1.0);
		float spec = smoothstep(1.0 - specular_size, 1.0 - specular_size + specular_softness, ndoth);
		SPECULAR_LIGHT += specular_tint.rgb * spec * specular_intensity * ATTENUATION * light_rgb;
	}

}
