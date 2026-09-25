// ink_toon.gdshader
// "Peint au soleil, encre gras" v3 (docs/STYLE_BIBLE.md §7.2, tâche ART-02).
// Remplace v2's ramp à 3 bandes / ombre en teinte linéaire brute par : 2
// bandes par défaut ("un ton de lumière, un ton d'ombre"), une ombre calée
// sur un RATIO PERCEPTUEL (OKLab L, `shadow_value`) plutôt qu'un facteur
// linéaire arbitraire, des masques vertex peints (AO/arête/hauteur, bakés
// par tools/blender/make_*.py, §7.9), un lavis monde basse fréquence qui
// casse la répétition des textures triplanaires, et un reflet dur optionnel
// pour les surfaces laquées. Ink lui-même reste dans les TEXTURES PEINTES
// (tools/textures/gen_textures.py) -- toujours aucune hachure procédurale.
//
// Trois façons d'utiliser ce shader (toutes construites par Cartoon.gd,
// scripts/core/) -- INCHANGÉES par ce rework, seuls les défauts/la formule
// de lumière changent :
//  - world()/prop()/character(): `albedo_color` plat, `use_albedo_texture`
//    false.
//  - painted(kind, tint): `use_albedo_texture` + `use_triplanar` true, une
//    texture peinte échantillonnée en ESPACE MONDE (Godot 4.7 docs, "Large
//    world coordinates" : les coordonnées triplanaires sont calculées dans
//    vertex() et passées par varying, jamais reconstruites en fragment() --
//    voir `world_pos`/`world_normal`) ; `albedo_color` agit comme une
//    TEINTE multiplicative (rouge/bleu/orange conteneur, etc.).
//  - character_surface(kind, color): couleur plate + `paint_grain_strength`
//    > 0, un léger bruit EN ESPACE OBJET (`VERTEX` brut, pas skinné, pas
//    `world_pos`) pour un rendu peint à la main sur peau/tissu/équipement --
//    en espace objet exprès : un personnage bouge, un bruit lié à la
//    position monde "nagerait" sur le maillage en marchant.
//
// Rampe de lumière (§7.2) : `band_count` bandes (2 par défaut). Le bord
// entre deux bandes ("terminator") reçoit un boost de chroma
// (`hot_edge_chroma`) pour lire comme un trait peint à la main, jamais un
// cran plat -- généralisé ici à N'IMPORTE QUEL nombre de bandes (proximité
// de la frontière ENTIÈRE la plus proche dans l'espace `step_pos`), plus
// l'ancien schéma v2 qui ne fonctionnait qu'avec une bande médiane distincte
// (band_count=3 impair) et n'a plus de sens à band_count=2.
//
// Ombre perceptuelle (§7.2) : `shadow_value` est la cible de RATIO OKLab L
// ombre/éclairé (0,66 par défaut, §7.5 "0,62-0,70 x la valeur éclairée"),
// converti en facteur linéaire par `pow(shadow_value, -1.5)` dans light() --
// voir ce commentaire pour la dérivation et pourquoi l'exposant n'est PAS le
// +3,0 qu'une dérivation OKLab pure (L d'une couleur mise à l'échelle par un
// facteur linéaire k scale en gros par k^(1/3), poids OKLab ~1 en somme)
// suggérerait au premier abord. La teinte d'ombre (bleu-violet, "jamais
// gris") se mélange ensuite à ce gris via `shadow_tint_mix`, normalisée par
// sa propre luminance (`teinte / lum(teinte)`) pour qu'elle ne rajoute PAS
// sa propre noirceur par-dessus le facteur déjà calibré par `shadow_value`.
//
// CALIBRATION RÉELLE (rapport de tâche ART-02, tools/look_probe.gd) : la
// dérivation OKLab pure (exposant +3,0, facteur linéaire 0,66^3 = 0,2875,
// dans la fourchette 0,27-0,32 que §7.2 documente) suppose que `light()` est
// la SEULE source de valeur d'une surface non éclairée. En pratique, Godot
// ajoute AUTOMATIQUEMENT une contribution d'ambiance/radiance-map à partir
// du ciel de l'Environment -- fortement DIRECTIONNELLE (une face tournée
// vers le ciel/soleil en reçoit beaucoup, une face tournée vers le sol/à
// l'opposé du soleil presque rien) -- qu'un `light()` personnalisé ne peut
// ni lire ni réécrire (aucun `AMBIENT_LIGHT` accessible en fragment()/light(),
// seul le render_mode tout-ou-rien `ambient_light_disabled` existe -- mesuré :
// le désactiver entièrement RETIRE plus de valeur qu'il n'en ajoutait à la
// face à l'ombre, abaissant le ratio mesuré encore davantage). Mesuré sur les
// 8 cartes (`Cartoon._MAP_PALETTES`) via `tools/look_probe.gd` : cette
// ambiance automatique, à elle seule (AVANT toute contribution de
// `shadow_value`), plafonne déjà le ratio OKLab L ombre/éclairé à ~0,60-0,62
// -- juste SOUS la borne basse de la cible §7.5 (0,62). L'exposant +3,0
// (facteur 0,2875, un ASSOMBRISSEMENT supplémentaire) enfonce donc le ratio
// mesuré à ~0,56-0,58, loin sous la cible. Remonter l'exposant vers 0 (donc
// vers un facteur 1,0, "pas d'assombrissement du tout" au-delà de l'ambiance
// automatique) plafonne à ~0,60-0,62 -- encore insuffisant. Seul un facteur
// linéaire SUPÉRIEUR à 1,0 (donc un exposant NÉGATIF) comble l'écart :
// -1,5 (facteur 0,66^-1,5 ~= 1,866) mesure 0,63-0,66 sur les 8 cartes, avec
// marge des deux bords -- voir le rapport de tâche pour le tableau complet.
// `shadow_value` reste la cible de ratio SÉMANTIQUE et le SEUL réglage
// exposé (0,66 par défaut, §7.2) ; l'exposant -1,5 est la constante de
// calibration, interne à ce shader, qui fait correspondre cette cible au
// pipeline de rendu RÉEL du projet (mesuré, pas dérivé analytiquement).
//
// Masques vertex (§7.1/§7.9, `use_vertex_masks`) : `COLOR` peint par le
// pipeline Blender, R=AO (assombrit vers `ao_min`), G=arête convexe
// (éclaircit de `edge_highlight`), B=gradient de hauteur (interpole
// `height_grad_min` -> `height_grad_max`). A=zone est lu par d'autres
// systèmes (décalques, etc.), pas par ce shader. Un maillage SANS COLOR
// bakée lit (1,1,1,1) (défaut Godot) -- un facteur SCALAIRE identique sur
// toute la surface, donc neutre pour tout ratio ombre/lumière.
//
// Lavis monde (§7.2, `wash_scale`/`wash_strength`) : bruit de valeur 3D
// lissé (interpolation trilinéaire, jamais un `floor()` à facettes) en
// ESPACE MONDE, +/-4% de valeur par défaut et une légère rotation de teinte
// (+/-3°, fixe) -- casse la répétition triplanaire sans lire comme du bruit.
//
// Reflet dur (§7.2, `gloss_strength`/`gloss_size`) : surfaces laquées
// uniquement (0 par défaut, inactif). Calculé dans light() (a besoin de
// `LIGHT`) et ajouté à DIFFUSE_LIGHT plutôt qu'à SPECULAR_LIGHT -- ce
// shader déclare `specular_disabled`, qui désactive le calcul spéculaire
// intégré de Godot.
//
// Teinte du soleil dans light() (§7.2, CHK-01) : seule la TEINTE de
// `LIGHT_COLOR` nourrit la rampe, jamais son intensité brute -- mais
// "teinte seule" doit vouloir dire une LUMINANCE transmise constante (1,0),
// pas juste un canal max remis à 1,0. RETOUR VÉRIFICATEUR (ART-02,
// tools/look_probe.gd, `lit_L` hors de la fenêtre CHK-01 0,72-0,78 sur
// 5/8 cartes) : normaliser par le CANAL MAX (`LIGHT_COLOR / max(R,G,B)`)
// préserve bien le RATIO teinte, mais laisse la luma 601 du résultat
// dépendre de la SATURATION du soleil -- un rouge pur (1,0,0), déjà à son
// canal max, n'a qu'une luma de 0,299 : la teinte "hue-only" assombrissait
// donc en fait la surface d'autant que le soleil de la carte était saturé,
// un effet secondaire jamais voulu par ce commentaire. `Cartoon.
// _MAP_PALETTES` (hors périmètre ART-02) donne 5 des 8 cartes des
// `sun_color` assez chauds/saturés pour faire chuter `lit_L` sous la
// cible par ce seul mécanisme. Corrigé en normalisant par la LUMA de
// `LIGHT_COLOR` (voir light()) plutôt que son canal max : la teinte
// résultante a alors TOUJOURS une luma de 1,0 (seuls les rapports R:G:B
// varient), donc une vraie transmission hue-only, `lit_L` indépendant de
// la saturation du soleil. N'affecte PAS le ratio `shadow_ratio` déjà
// calibré ci-dessus (calibration `shadow_value`/pow(.,-1.5)) : cette
// teinte multiplie `ramp` de façon identique côté éclairé et côté ombre
// (même carte, même soleil) -- un facteur d'échelle commun aux deux.
//
// Personnages gardent leur couleur d'équipe/ennemi via les instance uniforms
// `rim_color`/`rim_strength` (Cartoon.set_rim) -- inchangé par ce rework.
//
// TECH-04 (contour ennemi au stencil, docs/research/07_godot_tech.md C1) :
// délibérément AUCUN render_mode de stencil ici, malgré la piste de
// recherche ("écriture stencil dans la passe ink_toon" -- voir
// tests/rendering/test_enemy_outline.gd, qui verrouille cette absence).
// Ce shader est PARTAGÉ par TOUT le monde/décor (`Cartoon.world()`/
// `painted()`/`prop_uv()`), pas seulement les personnages -- une écriture
// stencil systématique marquerait le buffer à la même valeur pour le décor
// ET les personnages, rendant le contour de surbrillance ennemi (assets/
// shaders/ink_outline.gdshader, lecture "différent de" au stencil)
// invisible dès qu'il passe devant un mur/sol peint (déjà marqué à la même
// valeur) -- une régression pire que le bug visé. Le stencil vit
// entièrement dans ink_outline.gdshader (coque contre coque, jamais coque
// contre décor) ; voir son en-tête pour le détail. Aucun uniform ne peut
// rendre une déclaration de ce type conditionnelle par instance ici : c'est
// un état de pipeline fixé à la compilation du `.gdshader`, partagé par
// tous ses usages.
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

// -- Lighting ramp (§7.2) -----------------------------------------------
// v3 default: 2 -- "un ton de lumière, un ton d'ombre" (épingles 08/18).
uniform float band_count : hint_range(2.0, 4.0, 1.0) = 2.0;
// v3 default: 0.10 (bord peint au monde) -- 0.04 (net, personnages) reste un
// réglage par appel, Cartoon.gd ne le pose pas encore (hors périmètre ART-02).
uniform float band_softness : hint_range(0.0, 0.25) = 0.10;

// Blue-violet coloured shadow -- never grey, never under 45% of lit value.
uniform vec4 shadow_tint : source_color = vec4(0.361, 0.431, 0.659, 1.0); // #5C6EA8
// Cible perceptuelle (ratio OKLab L ombre/éclairé, §7.5 : 0,62-0,70) --
// remplace l'ancien `shadow_strength` (facteur linéaire brut). Converti en
// facteur linéaire par `pow(shadow_value, -1.5)` dans light() -- voir l'en-tête
// (calibration empirique contre l'ambiance automatique de Godot).
uniform float shadow_value : hint_range(0.50, 0.85) = 0.66;
// Part de `shadow_tint` (normalisée par sa propre luminance, donc à valeur
// constante) mélangée dans l'ombre -- le reste reste gris (facteur `shadow_value`
// pur), pour que la teinte de carte ne rajoute pas sa propre noirceur.
uniform float shadow_tint_mix : hint_range(0.0, 1.0) = 0.40;

// Bord entre deux bandes ("terminator") : +20% chroma par défaut (monde
// uniquement -- 0 aux personnages, réglage par appel hors périmètre ART-02).
uniform float hot_edge_chroma : hint_range(0.0, 0.5) = 0.20;
uniform float hot_edge_strength : hint_range(0.0, 1.0) = 1.0;

// Approximates design.md's "+15% sand bounce" ambient: a soft warm fill on
// downward-facing surfaces (undersides catch light bounced off the ground),
// independent of any real light so it also shows fully in shadow.
uniform vec4 ground_bounce_color : source_color = vec4(0.851, 0.631, 0.361, 1.0); // Sable #D9A15C
uniform float ground_bounce_strength : hint_range(0.0, 0.4) = 0.12;

// Object-space paint grain (character_surface() slots -- design.md SS6
// "Detail: base noise <= +/-6%"). 0 by default: painted() textures already
// carry their own baked detail and don't need this on top.
uniform float paint_grain_strength : hint_range(0.0, 0.12) = 0.0;

// -- Masques vertex peints (§7.1/§7.9) : COLOR RGBA = AO / arête convexe /
// gradient de hauteur / zone, bakés par tools/blender/make_*.py. Un maillage
// sans COLOR bakée lit (1,1,1,1) (défaut Godot) -- neutre : facteur scalaire
// identique sur toute la surface, donc sans effet sur un ratio ombre/lumière.
uniform bool use_vertex_masks = true;
// R (AO) : de `ao_min` (creux) à 1 (plein) -- multiplie l'albédo.
uniform float ao_min : hint_range(0.0, 1.0) = 0.55;
// G (arête convexe) : +`edge_highlight` de valeur sur les biseaux.
uniform float edge_highlight : hint_range(0.0, 0.5) = 0.15;
// B (gradient de hauteur, objet normalisé) : bas plus sombre, haut plus clair.
uniform float height_grad_min : hint_range(0.5, 1.0) = 0.88;
uniform float height_grad_max : hint_range(1.0, 1.5) = 1.04;

// -- Lavis monde (§7.2) : bruit de valeur 3D lissé en ESPACE MONDE, casse la
// répétition triplanaire sans lire comme du bruit. `wash_scale` = fréquence
// (1 / période en mètres, ex. 0,35 -> période ~2,9 m). 0 par défaut sur
// `wash_strength` désactiverait tout calcul (voir fragment()).
uniform float wash_scale : hint_range(0.05, 2.0) = 0.35;
uniform float wash_strength : hint_range(0.0, 0.15) = 0.04;

// -- Reflet dur (§7.2) : surfaces laquées uniquement (Cartoon.painted_for_slot
// futur -- hors périmètre ART-02), 0 par défaut donc totalement inactif ici.
uniform float gloss_strength : hint_range(0.0, 1.0) = 0.0;
uniform float gloss_size : hint_range(0.01, 0.5) = 0.10;

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

// Smooth 3D value noise (trilinear-interpolated hash lattice, Hermite fade)
// -- unlike hash13() sampled through floor() (paint_grain_strength's fine
// object-space texel grain), the world wash needs a SOFT low-frequency field
// (period ~= 1 / wash_scale, ~2.9 m by default) : a raw floor()-hash would
// facet into flat-shaded blocks at that scale instead of a gentle wash.
// Returns [0, 1].
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

// Standard RGB<->HSV (Sam Hocevar's branchless form) -- used by the world
// wash to nudge hue by a few degrees alongside its value swing.
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

// Fixed hue swing for the world wash (§7.2 "+/-3° de teinte") -- not a
// tunable uniform, only `wash_scale`/`wash_strength` are exposed.
const float WASH_HUE_MAX_DEG = 3.0;

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

	// Vertex masks (§7.1/§7.9): COLOR baked by the Blender pipeline. A mesh
	// without baked COLOR reads Godot's default (1,1,1,1) -- ao_min->1 at
	// R=1 is 1 (no-op), but G=1/B=1 would still apply edge_highlight/
	// height_grad_max as a flat multiplier; harmless (uniform scalar, same
	// on every face) but only meaningful once real masks are baked (§7.9).
	if (use_vertex_masks) {
		base.rgb *= mix(ao_min, 1.0, COLOR.r);
		base.rgb *= 1.0 + edge_highlight * COLOR.g;
		base.rgb *= mix(height_grad_min, height_grad_max, COLOR.b);
	}

	// World wash (§7.2): low-frequency value + hue noise in WORLD SPACE,
	// breaks up triplanar texture repetition without reading as grain.
	if (wash_strength > 0.0) {
		float w = value_noise3(world_pos * wash_scale) * 2.0 - 1.0; // [-1, 1]
		base.rgb = clamp(base.rgb * (1.0 + w * wash_strength), 0.0, 1.0);
		vec3 hsv = rgb2hsv(base.rgb);
		hsv.x = fract(hsv.x + w * (WASH_HUE_MAX_DEG / 360.0));
		base.rgb = hsv2rgb(hsv);
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

	// Perceptual shadow (§7.2): `shadow_value` is a target ratio of OKLab L
	// (shadow / lit), not a raw linear factor -- see the file header for the
	// full derivation, why the exponent is -1.5 (not the naive OKLab +3.0),
	// and the tools/look_probe.gd measurements that calibrate it.
	// `shadow_tint` is normalised by its OWN luma before mixing in, so it
	// only steers HUE -- it never adds its own darkening on top of the
	// factor `shadow_value` already calibrates.
	float shadow_linear = pow(clamp(shadow_value, 0.0, 1.0), -1.5);
	float tint_luma = dot(shadow_tint.rgb, vec3(0.299, 0.587, 0.114));
	vec3 tint_norm = shadow_tint.rgb / max(tint_luma, 0.001);
	vec3 shadow_color = ALBEDO * mix(vec3(1.0), tint_norm, shadow_tint_mix) * shadow_linear;
	vec3 ramp = mix(shadow_color, ALBEDO, banded);

	// Hot edge: a soft region straddling the NEAREST interior band boundary
	// gets extra chroma, so the light/shadow break reads as a hand-painted
	// line rather than a flat cut. Generalised over `step_pos` (not a fixed
	// "middle band" index, which only existed for an odd band_count) so it
	// still works at the v3 default band_count=2 -- there the sole interior
	// boundary (step_pos=1) IS the light/shadow break itself. Gated by
	// ATTENUATION so it never lights up deep inside a cast shadow, where
	// `band_index` alone can't tell "terminator" from "dark".
	float nearest_boundary = clamp(round(step_pos), 1.0, bands - 1.0);
	float boundary_dist = abs(step_pos - nearest_boundary);
	float is_terminator = 1.0 - smoothstep(0.0, 0.5, boundary_dist);
	is_terminator *= smoothstep(0.05, 0.3, ATTENUATION);
	float luma = dot(ramp, vec3(0.299, 0.587, 0.114));
	vec3 hot = luma + (ramp - luma) * (1.0 + hot_edge_chroma);
	ramp = mix(ramp, hot, is_terminator * hot_edge_strength);

	// WYSIWYG toon : seule la TEINTE du soleil nourrit la rampe, jamais son
	// intensité brute -- les scènes de carte n'ont pas à régler
	// `DirectionalLight3D.light_energy` contre les maths de bande de ce
	// shader. Normalisée par sa LUMA (601), pas par son canal max (voir
	// l'en-tête du fichier, CHK-01) : `light_tint` a alors TOUJOURS une luma
	// de 1,0 quelle que soit la saturation de `LIGHT_COLOR` -- seuls les
	// rapports R:G:B (la teinte) varient, donc `lit_L`/`shadow_L` ne
	// dépendent plus, à tort, de la saturation du soleil de la carte.
	float light_luma = dot(LIGHT_COLOR, vec3(0.299, 0.587, 0.114));
	vec3 light_tint = LIGHT_COLOR / max(light_luma, 0.001);
	DIFFUSE_LIGHT += ramp * light_tint;

	// Hard gloss (§7.2, lacquered surfaces only -- gloss_strength defaults
	// to 0, fully inert). Needs LIGHT (light()-only) for the half-vector, so
	// it can't live in fragment() like the rim. Added to DIFFUSE_LIGHT, not
	// SPECULAR_LIGHT: this shader declares `specular_disabled`, which turns
	// off Godot's built-in specular pass entirely.
	if (gloss_strength > 0.0) {
		vec3 half_vec = normalize(LIGHT + VIEW);
		float ndoth = clamp(dot(NORMAL, half_vec), 0.0, 1.0);
		float spec = smoothstep(1.0 - gloss_size, 1.0 - gloss_size + 0.02, ndoth);
		vec3 gloss_color = mix(ALBEDO, vec3(1.0), 0.7);
		DIFFUSE_LIGHT += gloss_color * spec * gloss_strength * ATTENUATION * light_tint;
	}
}
