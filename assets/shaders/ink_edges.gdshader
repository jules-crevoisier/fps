// ink_edges.gdshader
// World post-pass: SILHOUETTE + CREASE ink lines on the decor (STYLE_BIBLE.md
// v3 §7.4, tâche ART-07). Historique : design.md v2 SS3 avait retiré la
// famille "plis par normale/courbure" de v1 (le post ne dessinait plus que
// la silhouette, voir l'ancien commentaire ci-dessous conservé pour le
// contexte de la transparence). v3 RÉINTRODUIT les plis, mais en lisant le
// buffer normale/rugosité du moteur (`hint_normal_roughness_texture`,
// Forward+ uniquement -- doc Godot 4.7 "Screen-reading shaders") au lieu
// d'un pochoir cuit dans l'albédo, pour tracer les arêtes de biseau et de
// boîte (docs/STYLE_BIBLE.md §1 "L'encre suit l'objet"). Toujours un quad
// plein écran attaché à la caméra du joueur local (InkPost.gd) ; silhouette
// (bord de profondeur) et pli (bord de normale) sont deux pistes de calcul
// indépendantes, combinées dans fragment().
//
// STYLE_BIBLE.md §7.4 -- silhouette : 3,0 px jusqu'à 8 m puis 1,5 px à 50 m
// et au-delà ; opacité 100 % jusqu'à un plancher de 50 % à 100 m (jamais
// invisible) ; brouillard : les contours lointains prennent la teinte de
// brume, de 40 m à 35 % max à 150 m (aligné sur le brouillard monde de
// LevelLook, §6.3). Plis : arêtes dont l'angle entre normales voisines
// dépasse 35°, 1,5 px, disparaissent entre 15 et 30 m (jamais empâtés au
// lointain), opacité 0,85.
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
// ink line. The fix (still true in v3, and covered by
// tests/rendering/test_ink_edges_transparency.gd): never touch the scene
// colour at all -- output ink colour with ALPHA = the edge mask (0 off an
// edge -- fully transparent, lets everything drawn under OR after it show
// through untouched) and never read `hint_screen_texture`. Depth AND
// normal-roughness textures (both captured during the Forward+ depth
// pre-pass) are enough for silhouette AND crease -- the scene's own colour
// is never needed.
//
// CHK-11 ("aucune double ligne") : un biseau assez marqué déclenche À LA
// FOIS la silhouette (bord de profondeur) ET le pli (bord de normale) au
// même endroit -- si chacun dessinait sa propre bande de pixels, on verrait
// deux traits d'encre parallèles décalés d'un pixel ou deux plutôt qu'un
// seul. Le pli est donc masqué là où la silhouette répond déjà
// (`crease *= 1.0 - edge`) : la silhouette a toujours priorité, le pli ne
// comble que les arêtes SANS discontinuité de profondeur (un biseau doux,
// une arête de boîte qui n'occulte rien).
shader_type spatial;
render_mode blend_mix, unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_roughness_tex : hint_normal_roughness_texture, repeat_disable, filter_nearest;

uniform bool enabled = true;
// #1A1410 (Cartoon.INK) -- set at runtime by InkPost.gd.
uniform vec4 ink_color : source_color = vec4(0.1020, 0.0784, 0.0627, 1.0);
// Current map's horizon/haze colour -- set at runtime by InkPost.gd from
// Cartoon.map_palette(). Far outlines tint toward this, matching the fog.
uniform vec4 haze_color : source_color = vec4(0.851, 0.910, 0.965, 1.0);

uniform float width_near_px : hint_range(1.0, 8.0) = 3.0;
uniform float width_far_px : hint_range(0.5, 8.0) = 1.5;
uniform float width_near_m : hint_range(1.0, 50.0) = 8.0;
uniform float width_far_m : hint_range(1.0, 150.0) = 50.0;

uniform float opacity_far_floor : hint_range(0.0, 1.0) = 0.5;
uniform float opacity_far_m : hint_range(1.0, 200.0) = 100.0;

uniform float fog_start_m : hint_range(1.0, 200.0) = 40.0;
uniform float fog_end_m : hint_range(1.0, 300.0) = 150.0;
uniform float fog_max_amount : hint_range(0.0, 1.0) = 0.35;

uniform float depth_edge_threshold : hint_range(0.005, 1.0) = 0.05;

// Plis par normale (STYLE_BIBLE.md §7.4, nouveau v3) -- arêtes de biseau ou
// de boîte, jamais un vrai bord d'occlusion (voir crease_response plus bas,
// et la note CHK-11 ci-dessus pour l'exclusion mutuelle avec la silhouette).
uniform bool crease_enabled = true;
uniform float crease_angle_deg : hint_range(1.0, 90.0) = 35.0;
uniform float crease_width_px : hint_range(0.5, 8.0) = 1.5;
uniform float crease_fade_start_m : hint_range(1.0, 100.0) = 15.0;
uniform float crease_fade_end_m : hint_range(1.0, 200.0) = 30.0;
uniform float crease_opacity : hint_range(0.0, 1.0) = 0.85;

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

// Normale VUE (view-space, décodée du buffer normale/rugosité capturé
// pendant le pré-passe de profondeur -- doc Godot 4.7 "Screen-reading
// shaders" : xyz en [0,1] -> [-1,1] ; w = rugosité, non utilisée ici).
// `normalize()` protège le produit scalaire de crease_response contre une
// légère dénormalisation d'échantillonnage (le buffer stocke des normales
// déjà unitaires, mais un dot() sur un vecteur non unitaire ne serait plus
// un vrai cosinus d'angle).
vec3 sample_view_normal(vec2 uv) {
	vec3 n = texture(normal_roughness_tex, uv).rgb * 2.0 - 1.0;
	return normalize(n);
}

// Réponse de pli (arête de biseau/boîte) : 1.0 si l'angle entre la normale
// du centre et celle d'un voisin dépasse `crease_angle_deg` (comparaison en
// cosinus -- moins cher qu'un acos par échantillon : plus l'angle est
// grand, plus dot() est PETIT, d'où le seuil inversé `1.0 - step(...)`).
// Ne regarde QUE les normales -- l'exclusion des vrais bords d'occlusion
// (déjà couverts par la silhouette) se fait en aval, dans fragment().
float crease_response(vec2 uv, vec2 texel, vec3 center_normal, float cos_threshold) {
	vec3 l = sample_view_normal(uv - vec2(texel.x, 0.0));
	vec3 r = sample_view_normal(uv + vec2(texel.x, 0.0));
	vec3 u = sample_view_normal(uv - vec2(0.0, texel.y));
	vec3 dn = sample_view_normal(uv + vec2(0.0, texel.y));
	float e = 0.0;
	e = max(e, 1.0 - step(cos_threshold, dot(center_normal, l)));
	e = max(e, 1.0 - step(cos_threshold, dot(center_normal, r)));
	e = max(e, 1.0 - step(cos_threshold, dot(center_normal, u)));
	e = max(e, 1.0 - step(cos_threshold, dot(center_normal, dn)));
	return e;
}

// 1.0 jusqu'à `crease_fade_start_m`, 0.0 au-delà de `crease_fade_end_m`,
// interpolé linéairement entre les deux (STYLE_BIBLE.md §7.4 : "les plis
// disparaissent avant d'empâter le lointain").
float crease_fade(float dist_m) {
	float t = clamp((dist_m - crease_fade_start_m) / max(crease_fade_end_m - crease_fade_start_m, 0.001), 0.0, 1.0);
	return 1.0 - t;
}

void fragment() {
	// Pas de `return` anticipé : Godot interdit `return` dans fragment() — on
	// branche donc sur `enabled` pour tout le corps de la fonction. Le repli
	// (désactivé, ou aucun bord) est ALPHA = 0 : un quad plein écran mais
	// entièrement transparent ne touche à RIEN de ce qui est dessous.
	float edge = 0.0;
	float crease = 0.0;
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

		if (crease_enabled) {
			vec3 n_c = sample_view_normal(SCREEN_UV);
			float cos_threshold = cos(radians(crease_angle_deg));
			for (int i = 1; i <= 8; i++) {
				if (float(i) > crease_width_px) { break; }
				crease = max(crease, crease_response(SCREEN_UV, px * float(i), n_c, cos_threshold));
			}
			// La silhouette a priorité (voir la note CHK-11 en tête de
			// fichier) : un pli qui coïncide avec un vrai bord d'occlusion
			// ne rajoute pas une seconde bande de pixels à côté.
			crease *= (1.0 - edge) * crease_opacity * crease_fade(l_c);
		}

		// Opacity floors at 50% by 100 m instead of fading to nothing
		// (STYLE_BIBLE.md §7.4) -- outlines stay legible at range instead of
		// disappearing. Applies to the silhouette only: the crease has its
		// own independent fade (crease_fade), already folded in above.
		float t_op = clamp(l_c / max(opacity_far_m, 0.001), 0.0, 1.0);
		float opacity = mix(1.0, opacity_far_floor, t_op);
		edge *= opacity;

		// Far outlines pick up the haze colour, ramping in with the same
		// fog window used by LevelLook's world fog (40 m -> 150 m, 35% max,
		// §6.3). Creases fade out at 30 m, well before fog starts, so this
		// tint never visibly reaches them.
		float fog_amount = clamp((l_c - fog_start_m) / max(fog_end_m - fog_start_m, 0.001), 0.0, 1.0) * fog_max_amount;
		tinted_ink = mix(ink_color.rgb, haze_color.rgb, fog_amount);
	}

	// ONLY the ink line is drawn (ALBEDO + ALPHA = the combined edge mask)
	// -- the scene's own colour is never read or re-output, so this quad
	// can never blot out a transparent object drawn under or after it,
	// whatever the transparent draw order turns out to be that frame.
	ALBEDO = tinted_ink;
	ALPHA = clamp(max(edge, crease), 0.0, 1.0);
}
