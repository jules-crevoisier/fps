// ink_ground.gdshader
// Sol procédural peint (docs/STYLE_BIBLE.md v3 §6/§7, tâche ART-85) --
// consommé UNIQUEMENT par scripts/levels/ground/GroundBuilder.gd (le
// maillage en grille qu'il construit). Contrat : "même éclairage 2 tons,
// ombre teintée et encre que ink_toon.gdshader, mais mélange de 4 textures
// peintes en triplanaire selon les poids".
//
// -- Rampe de lumière / ombre perceptuelle -----------------------------
// Copie EXACTE du bloc light()/shadow de ink_toon.gdshader (bandes,
// shadow_value -> pow(.,-1.5), teinte d'ombre normalisée par sa luma, bord
// chaud) : voir ink_toon.gdshader pour la dérivation complète et la
// calibration (ART-02, tools/look_probe.gd) -- pas redupliquée ici. Ce
// fichier ne duplique QUE ce que Godot exige (pas d'#include en shading
// language) ; toute retouche à la formule de lumière doit rester en phase
// avec ink_toon.gdshader (fichier hors du périmètre de cette tâche).
// L'encre elle-même reste le post-process d'écran commun (ink_edges.gdshader
// + InkPost.gd), qui encre déjà TOUT ce qui est rendu (reliefs de piste/
// ornières/jupes compris, via depth+normal) -- rien à ajouter ici.
//
// -- Mélange 4 textures (§7.2 "textures actuelles de assets/textures/
// painted/, remplacées plus tard par ART-79B sous les mêmes noms") --------
// `COLOR` (peint par GroundBuilder._build_geometry, PAS les masques AO/
// arête/hauteur d'ink_toon) porte les 4 poids de mélange NORMALISÉS
// (somme = 1, GroundBuilder.weights_at()) : R = sable, G = terre battue,
// B = piste, A = roche -- même ordre que le commentaire du contrat "sable /
// terre battue / piste / roche". Chaque rôle a son propre triplanar_sample
// (le sol a des pentes -- bords d'ornière, jupes de terre -- où une
// projection UV plate se déformerait) plus une teinte `tint_*` (posée par
// GroundBuilder via `Cartoon.effective_tint`, cohérente avec la palette de
// la carte courante) : deux rôles peuvent partager le MÊME fichier texture
// avec des teintes différentes tant que la bibliothèque peinte ne compte pas
// encore 4 matières dédiées au terrain (voir le commentaire de
// GroundBuilder._material -- ART-79B les remplacera sous les mêmes chemins).
//
// -- Lavis monde (identique à ink_toon.gdshader §7.2) --------------------
// Même bruit de valeur/teinte basse fréquence en espace MONDE que
// ink_toon : casse la répétition triplanaire (1 répétition / `triplanar_
// scale` mètres) sans lire comme du bruit procédural (STYLE_BIBLE §0.1 :
// "jamais du bruit" dans l'ENCRE/le détail -- ce lavis reste un très léger
// dégradé de valeur/teinte, pas un détail).
shader_type spatial;
render_mode blend_mix, cull_back, specular_disabled;

// -- 4 textures peintes mélangées par poids de sommet --------------------
uniform sampler2D tex_sand : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_dirt : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_track : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rock : source_color, filter_linear_mipmap, repeat_enable;

uniform vec4 tint_sand : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 tint_dirt : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 tint_track : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 tint_rock : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Terrain seul (STYLE_BIBLE §7.2 "triplanar_scale : 1/3 -> 1/4 (1 répétition
// / 4 m), pour le terrain seulement") : 0.25 par défaut, comme
// Cartoon._TRIPLANAR_SCALE.
uniform float triplanar_scale : hint_range(0.02, 2.0) = 0.25;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;

// -- Rampe de lumière (copie ink_toon.gdshader §7.2, "2 tons") ------------
uniform float band_count : hint_range(2.0, 4.0, 1.0) = 2.0;
uniform float band_softness : hint_range(0.0, 0.25) = 0.10;
uniform vec4 shadow_tint : source_color = vec4(0.361, 0.431, 0.659, 1.0); // #5C6EA8
uniform float shadow_value : hint_range(0.50, 0.85) = 0.66;
uniform float shadow_tint_mix : hint_range(0.0, 1.0) = 0.40;
uniform float hot_edge_chroma : hint_range(0.0, 0.5) = 0.20;
uniform float hot_edge_strength : hint_range(0.0, 1.0) = 1.0;

// -- Lavis monde (copie ink_toon.gdshader §7.2) ---------------------------
uniform float wash_scale : hint_range(0.05, 2.0) = 0.35;
uniform float wash_strength : hint_range(0.0, 0.15) = 0.04;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// -- Fonctions utilitaires (copies exactes de ink_toon.gdshader : pas
// d'#include en shading language Godot -- voir ce fichier pour les
// commentaires détaillés de chacune) -------------------------------------
float hash13(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

vec4 triplanar_sample(sampler2D tex, vec3 pos, vec3 nrm, float scale) {
	vec3 blend = pow(abs(nrm), vec3(triplanar_sharpness));
	blend /= max(blend.x + blend.y + blend.z, 0.0001);
	vec4 cx = texture(tex, pos.zy * scale);
	vec4 cy = texture(tex, pos.xz * scale);
	vec4 cz = texture(tex, pos.xy * scale);
	return cx * blend.x + cy * blend.y + cz * blend.z;
}

float value_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	float nxy0 = mix(nx00, nx10, u.y);
	float nxy1 = mix(nx01, nx11, u.y);
	return mix(nxy0, nxy1, u.z);
}

vec3 rgb2hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

const float WASH_HUE_MAX_DEG = 3.0;

void fragment() {
	// COLOR = 4 poids de mélange normalisés (R sable / G terre battue /
	// B piste / A roche, GroundBuilder.weights_at()) -- jamais les masques
	// AO/arête/hauteur d'ink_toon (voir en-tête). Un maillage sans COLOR
	// bakée lirait (1,1,1,1) (défaut Godot) -- normalisé ci-dessous, ça
	// retomberait sur un mélange égal des 4 textures plutôt qu'un crash,
	// mais GroundBuilder peint TOUJOURS COLOR (jamais ce cas en pratique).
	vec4 w = COLOR;
	float w_sum = max(w.r + w.g + w.b + w.a, 0.0001);
	w /= w_sum;

	vec3 c_sand = triplanar_sample(tex_sand, world_pos, world_normal, triplanar_scale).rgb * tint_sand.rgb;
	vec3 c_dirt = triplanar_sample(tex_dirt, world_pos, world_normal, triplanar_scale).rgb * tint_dirt.rgb;
	vec3 c_track = triplanar_sample(tex_track, world_pos, world_normal, triplanar_scale).rgb * tint_track.rgb;
	vec3 c_rock = triplanar_sample(tex_rock, world_pos, world_normal, triplanar_scale).rgb * tint_rock.rgb;
	vec3 base = c_sand * w.r + c_dirt * w.g + c_track * w.b + c_rock * w.a;

	// Lavis monde (ink_toon.gdshader §7.2) : casse la répétition triplanaire.
	if (wash_strength > 0.0) {
		float ws = value_noise3(world_pos * wash_scale) * 2.0 - 1.0; // [-1, 1]
		base = clamp(base * (1.0 + ws * wash_strength), 0.0, 1.0);
		vec3 hsv = rgb2hsv(base);
		hsv.x = fract(hsv.x + ws * (WASH_HUE_MAX_DEG / 360.0));
		base = hsv2rgb(hsv);
	}

	ALBEDO = base;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

// Copie exacte de ink_toon.gdshader::light() (bandes + ombre perceptuelle +
// bord chaud) -- voir ce fichier pour la dérivation/calibration complète.
// Ni reflet dur ni rebond de sol ni contour de rim ici : aucun rôle pour un
// sol (surfaces laquées / dessous d'objet / halo d'équipe).
void light() {
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float bands = max(band_count, 2.0);
	float step_pos = ndotl * bands;
	float band_index = clamp(floor(step_pos), 0.0, bands - 1.0);
	float frac_edge = smoothstep(0.5 - band_softness, 0.5 + band_softness, fract(step_pos));
	float banded = clamp(band_index / bands + frac_edge / bands, 0.0, 1.0);
	banded *= ATTENUATION;

	float shadow_linear = pow(clamp(shadow_value, 0.0, 1.0), -1.5);
	float tint_luma = dot(shadow_tint.rgb, vec3(0.299, 0.587, 0.114));
	vec3 tint_norm = shadow_tint.rgb / max(tint_luma, 0.001);
	vec3 shadow_color = ALBEDO * mix(vec3(1.0), tint_norm, shadow_tint_mix) * shadow_linear;
	vec3 ramp = mix(shadow_color, ALBEDO, banded);

	float nearest_boundary = clamp(round(step_pos), 1.0, bands - 1.0);
	float boundary_dist = abs(step_pos - nearest_boundary);
	float is_terminator = 1.0 - smoothstep(0.0, 0.5, boundary_dist);
	is_terminator *= smoothstep(0.05, 0.3, ATTENUATION);
	float luma = dot(ramp, vec3(0.299, 0.587, 0.114));
	vec3 hot = luma + (ramp - luma) * (1.0 + hot_edge_chroma);
	ramp = mix(ramp, hot, is_terminator * hot_edge_strength);

	float light_luma = dot(LIGHT_COLOR, vec3(0.299, 0.587, 0.114));
	vec3 light_tint = LIGHT_COLOR / max(light_luma, 0.001);
	DIFFUSE_LIGHT += ramp * light_tint;
}
