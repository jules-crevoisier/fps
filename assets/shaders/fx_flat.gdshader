// fx_flat.gdshader
// Matériau "plat" partagé par ComicFx.gd (tâche ART-40, STYLE_BIBLE.md §9.1) :
// chaque effet VFX est "un petit dessin animé" — une silhouette DURE (pas de
// dégradé radial flou façon particule de fumée générique), 1 ton en aplat, un
// contour d'encre de 2 px "sauf traceurs et lueurs" (§9.1 #1/#3). Consommé par
// GPUParticles3D avec un QuadMesh comme draw_pass_1 (jamais un billboard flou,
// §9.1 #6) : la silhouette elle-même vient d'une distance de champ (SDF)
// évaluée en fragment() sur l'UV du quad plutôt que d'une texture peinte —
// aucun nouvel asset peint n'est nécessaire (voir ComicFx.gd, "assets/vfx/"
// reste vide : la seule texture de décalque du kit, déjà encrée, vient
// d'ART-04/assets/textures/decals/ et passe par DecalPool, pas par ce
// shader).
//
// `shape_kind` sélectionne la primitive (voir ComicFx.Shape, valeurs
// synchronisées à la main — ce fichier ne peut pas lire une énumération
// GDScript) :
//   0 DISC   — rond plein (bouffées de poussière/rembourrage, §9.3).
//   1 STREAK — capsule effilée le long de l'axe Y local (étincelles/éclats,
//              "traits de vitesse" §9.3) ; combiné à
//              GPUParticles3D.transform_align = Z_BILLBOARD_Y_TO_VELOCITY
//              côté ComicFx pour s'orienter dans le sens du déplacement.
//   2 STAR   — étoile à N branches (approximation polaire, pas une SDF exacte
//              — voir la note sur `sd_star` plus bas) : étoiles de tête,
//              éclats anguleux.
//   3 RECT   — rectangle (confettis, §9.3/§9.5).
//   4 RING   — anneau (CLONK du headshot, §9.3).
//
// Contour : bande d'encre calculée dans la MÊME passe (pas un `next_pass` de
// coque extrudée façon ink_outline.gdshader — cette technique suppose un
// silhouette de maillage qui épouse déjà la forme ; ici la silhouette est
// entièrement dessinée en fragment(), donc son contour l'est aussi, par un
// second seuil de distance juste à l'intérieur du bord).
//
// `billboard` (déf. true) : recopie manuelle du render_mode `billboard,
// billboard_keep_scale` intégré à Godot (MODELVIEW_MATRIX réécrit avec la
// rotation de la caméra, échelle du MODEL_MATRIX conservée) — en uniform
// plutôt qu'en render_mode fixe pour que CE MÊME shader puisse aussi servir
// à une marque posée à plat contre une surface (`billboard = false`) sans
// dupliquer le fichier.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque, diffuse_lambert, specular_disabled;

uniform int shape_kind : hint_range(0, 4) = 0;
uniform vec4 fill_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool draw_outline = true;
// #1A1410 (Cartoon.INK) recopié en dur : ce shader est utilisé hors de
// Cartoon.gd (ComicFx n'a pas le droit de dépendre de sa méthode privée
// _outline_pass) — voir ComicFx.gd.
uniform vec4 outline_color : source_color = vec4(0.1020, 0.0784, 0.0627, 1.0);
// Épaisseur du contour en PIXELS ÉCRAN réels (§9.1 #1 : "un contour d'encre
// de 2 px") — mesurée, pas approximée : convertie en unités de `d` (SDF, UV
// centré -1..1) via `fwidth(d)` dans fragment() (même technique que `aa`
// juste en dessous, qui anticrénèle déjà avec cette dérivée d'écran) —
// `outline_width_px * fwidth(d)` est la largeur, en unités de `d`, que
// couvre EFFECTIVEMENT `outline_width_px` pixels écran à l'endroit dessiné :
// la bande d'encre reste donc ~2 px quels que soient la distance caméra ou
// `size_m` du quad (QuadMesh, voir ComicFx.spawn_from_spec), contrairement à
// l'ancienne constante fixe en UV (0.16) qui n'était qu'un ordre de grandeur
// valable pour la taille habituelle de ces formes. Reste une approximation
// sur STAR (SDF non exacte, voir sd_star plus bas) comme `aa` déjà — assumé,
// voir sa note. Synchronisé depuis `ComicFx.OUTLINE_PX` par
// `ComicFx.shape_material()`, comme `outline_color` l'est déjà depuis
// `Cartoon.INK`, plutôt que de dépendre d'une coïncidence avec cette valeur
// par défaut.
uniform float outline_width_px : hint_range(0.0, 16.0) = 2.0;
uniform bool billboard = true;
// Multiplie ALBEDO/ALPHA par la couleur d'instance des particules (le
// "Color Ramp"/couleur initiale d'un ParticleProcessMaterial) quand vrai —
// laisse la forme à `fill_color` seul sinon (matériau réutilisé hors
// GPUParticles3D, ex. un flash à instance unique).
uniform bool use_instance_color = false;

// -- Primitives (STAR mise à part) : de vraies SDF 2D en UV centré ----------
uniform float star_points : hint_range(3.0, 10.0) = 5.0;
uniform float star_inner_ratio : hint_range(0.1, 0.9) = 0.45;
uniform float star_sharpness : hint_range(0.5, 6.0) = 2.0;
uniform vec2 rect_half_extent = vec2(0.6, 0.35);
uniform float ring_radius : hint_range(0.0, 1.0) = 0.75;
uniform float ring_thickness : hint_range(0.01, 0.5) = 0.14;

varying vec2 v_uv_centered;

void vertex() {
	v_uv_centered = UV * 2.0 - 1.0;
	if (billboard) {
		vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		mat4 mv = VIEW_MATRIX * mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), MODEL_MATRIX[3]);
		mv[0].xyz *= scale.x;
		mv[1].xyz *= scale.y;
		mv[2].xyz *= scale.z;
		MODELVIEW_MATRIX = mv;
	}
}

float sd_circle(vec2 p, float r) {
	return length(p) - r;
}

// Capsule verticale (segment (0,-0.82)-(0,0.82), rayon `r`) : le "trait de
// pinceau effilé" des étincelles/éclats (§9.2/§9.3).
float sd_streak(vec2 p, float r) {
	vec2 a = vec2(0.0, -0.82);
	vec2 b = vec2(0.0, 0.82);
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

float sd_box(vec2 p, vec2 half_extent) {
	vec2 d = abs(p) - half_extent;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sd_ring(vec2 p, float radius, float thickness) {
	return abs(length(p) - radius) - thickness;
}

// Étoile à N branches — APPROXIMATION polaire (rayon de bord modulé par
// cos(N * angle), pas la SDF exacte d'un polygone étoilé) : suffisant pour
// une petite forme "sur deux" vue moins de 300 ms, et bien moins cher qu'une
// vraie SDF de polygone à N sommets. `d` n'est donc pas une distance
// euclidienne stricte près des pointes (l'anticrénelage par dérivée y est un
// peu plus grossier) — c'est un compromis assumé, pas un bug.
float sd_star(vec2 p, float points, float inner_ratio, float sharpness) {
	float a = atan(p.y, p.x);
	float r = length(p);
	float lobe = max(cos(points * a), 0.0);
	float edge_r = mix(inner_ratio, 1.0, pow(lobe, sharpness));
	return r - edge_r;
}

void fragment() {
	vec2 p = v_uv_centered;
	float d;
	if (shape_kind == 1) {
		d = sd_streak(p, 0.30);
	} else if (shape_kind == 2) {
		d = sd_star(p, star_points, star_inner_ratio, star_sharpness);
	} else if (shape_kind == 3) {
		d = sd_box(p, rect_half_extent);
	} else if (shape_kind == 4) {
		d = sd_ring(p, ring_radius, ring_thickness);
	} else {
		d = sd_circle(p, 0.85);
	}

	float aa = max(fwidth(d), 0.001) * 1.5;
	float outside_alpha = 1.0 - smoothstep(0.0, aa, d);
	if (outside_alpha <= 0.004) {
		discard;
	}

	// `d` est une SDF (|gradient| ~= 1 en unités de `p`, hors STAR — voir la
	// note sur `outline_width_px` ci-dessus) : `fwidth(d)` mesure donc combien
	// d'unités de `d` couvre UN pixel écran ici, exactement comme pour `aa`.
	float px_to_d = max(fwidth(d), 0.0001);
	float outline_width_d = outline_width_px * px_to_d;
	float outline_band = draw_outline ? smoothstep(-outline_width_d, -outline_width_d + aa, d) : 0.0;
	vec3 instance_tint = use_instance_color ? COLOR.rgb : vec3(1.0);
	float instance_alpha = use_instance_color ? COLOR.a : 1.0;

	ALBEDO = mix(fill_color.rgb, outline_color.rgb, outline_band) * instance_tint;
	ALPHA = fill_color.a * outside_alpha * instance_alpha;
}
