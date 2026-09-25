// ink_outline.gdshader
// Ink hull: inverted-hull outline (design.md v2 SS5 "Outlines") posed as a
// `next_pass` on an ink_toon material, or chained again for the enemy
// highlight's outer ink ring (Cartoon.character(highlight_color=...)).
// Standard Godot 4 technique -- extrude along the vertex normal in CLIP
// SPACE at a constant width in PIXELS, independent of camera distance
// (`cull_front`: only the inside of the inflated shell is visible, framing
// the object).
//
// Normale d'extrusion (docs/research/07_godot_tech.md C1, TECH-03) : extruder
// selon NORMAL (facettee) fend la coque a chaque arete vive des props/armes
// (facets, use_smooth=False) -- les deux moities dupliquees par l'export
// glTF s'ecartent chacune selon sa propre normale de face. `tools/blender/
// lib/toonkit.py smooth_normal_attrs` bake donc une normale MOYENNE par
// SOMMET (continue de part et d'autre d'une arete dure) dans un attribut
// glTF personnalise `_smooth_normal`, expose cote Godot en canal CUSTOM0
// (voir tests/rendering/test_stylekit_assets.gd) pour un mesh STATIQUE.
// Un mesh SKINNE (Skeleton3D) ne peut pas la lire dans CUSTOM0 : Godot
// skinne NORMAL et TANGENT selon la pose AVANT vertex(), mais jamais les
// attributs CUSTOM (recopies tels quels, en pose de repos) -- l'utiliser sur
// un perso anime fendrait le contour comme avec NORMAL. Pour un skinne, la
// normale lissee est donc plutot ecrite dans TANGENT (qui suit la pose ;
// cette coque ne fait ni normal map ni eclairage, TANGENT n'y sert a rien
// d'autre) : `Cartoon.apply_team_outline()` active `use_smooth_normal_tangent`
// quand le mesh porte des poids d'os (Mesh.ARRAY_FORMAT_BONES). Dans les
// deux cas, si l'attribut choisi est absent (mesh pas encore reconstruit par
// stylekit, ou sans UV) -- lu a (0,0,0) par Godot -- on retombe sur NORMAL.
//
// Distance falloff (design.md SS5, "Characters: ink #1A1410 hull, 3 px to
// 10 m, 2 px at 40 m, 1.5 px floor"): OFF by default (props/pickups/
// viewmodel and the enemy highlight hull all want a FLAT width -- SS5:
// "Viewmodel and pickups: 2 px ink", "Enemies: ... that never fades").
// Cartoon.character()'s default (ally/plain) outline turns it on. Below
// `falloff_far_m` it is linear from `outline_width_px` at `falloff_near_m`
// down to `falloff_far_px` at `falloff_far_m`; beyond that it decays
// exponentially toward `falloff_floor_px` with a half-life of
// `falloff_decay_half_life_m` (STYLE_BIBLE.md SS7.3 v3: calibrated so the
// character table lands within +/-0.1 px at 60 m and 90 m -- the previous
// fixed-factor asymptote drifted to 0.20 px off by 90 m). Always clamped so
// it can never go below the floor.
//
// TECH-04 (docs/research/07_godot_tech.md C1, tests/rendering/
// test_enemy_outline.gd) : coque UNIQUE au stencil (Godot 4.5+,
// `stencil_mode`) -- evite la "coque interne" du double contour ennemi
// (surbrillance PUIS encre, `Cartoon._team_outline_pass`/`character(
// highlight_color=...)`, deux next_pass chaines) : le second hull (encre)
// ne dessine plus ses pixels la ou le PREMIER hull (surbrillance) a deja
// ecrit -- l'ancien bug : deux coques extrudees a des largeurs differentes
// depuis la meme surface se chevauchent de facon incorrecte aux plis
// concaves/jointures entre surfaces d'un personnage multi-materiaux (peau/
// tenue/equipement, voir apply_team_outline qui pose un next_pass par
// surface). `stencil_mode read, write, compare_not_equal, 1` : un hull ne
// se dessine (et ne marque le stencil a 1) que la ou le stencil n'est PAS
// DEJA a 1 -- le premier hull a couvrir un pixel donne "gagne", le second
// s'efface silencieusement au lieu de le repeindre en double.
//
// PAS touche a ink_toon.gdshader (mesure, hors de ce fichier) : ce shader
// est PARTAGE par tout le monde/decor (`Cartoon.world()`/`painted()`) --
// un stencil ecrit systematiquement la rendrait le contour ennemi INVISIBLE
// des qu'il passe devant un mur/sol peint (le decor aurait deja pose le
// stencil a 1 partout), une regression bien pire que le bug corrige ici.
// Le stencil de CE fichier ne connait donc QUE les autres hulls
// ink_outline, jamais la silhouette reelle du corps -- l'occlusion "un
// ennemi derriere un mur n'a aucun pixel de contour visible" reste
// entierement le fait du TEST DE PROFONDEUR normal (jamais desactive ni
// inverse -- aucun mode X-ray), inchange par ce ticket. Reduire les 3 passes ennemies (base + surbrillance +
// encre) a 2 supposerait de retirer ce second next_pass cote Cartoon.gd --
// hors de portee ici, cette chaine est verrouillee par des tests d'un autre
// fichier (tests/rendering/test_cartoon_materials.gd,
// test_outline_normals.gd) hors de la liste de fichiers de cette tache.
//
// Lire le stencil n'est possible QUE dans la passe TRANSPARENTE (Godot 4.5,
// doc "Stencil modes" : "You can only read from the stencil buffer in the
// transparent pass") -- fragment() ecrit donc desormais ALPHA = 1.0 pour
// faire passer ce shader dans le pipeline transparent (seule condition qui
// autorise la lecture) : toujours totalement opaque a l'oeil, blend_mix
// (par defaut) avec alpha=1 equivaut a un simple ecrasement, pas de
// transparence visuelle.
shader_type spatial;
render_mode cull_front, unshaded, depth_draw_always;
stencil_mode read, write, compare_not_equal, 1;

// #1A1410 locked (Cartoon.INK, design.md SS5) -- always overwritten by the
// material builder in Cartoon.gd; this default only matters if the shader
// is used standalone.
uniform vec4 outline_color : source_color = vec4(0.1020, 0.0784, 0.0627, 1.0);
uniform float outline_width_px : hint_range(0.0, 16.0) = 3.0;

// TECH-03 : quel canal porte la normale lissee. false (defaut, statique) ->
// CUSTOM0.xyz ; true (skinne) -> TANGENT. Pose par Cartoon.gd selon le mesh,
// jamais a la main sur un usage standalone.
uniform bool use_smooth_normal_tangent = false;

uniform bool distance_falloff = false;
uniform float falloff_near_m : hint_range(1.0, 50.0) = 10.0;
uniform float falloff_far_m : hint_range(1.0, 100.0) = 40.0;
uniform float falloff_far_px : hint_range(0.5, 16.0) = 2.0;
uniform float falloff_floor_px : hint_range(0.5, 16.0) = 1.5;
uniform float falloff_decay_half_life_m : hint_range(1.0, 100.0) = 20.0;

// STYLE_BIBLE.md SS7.3 v3 : le trait des personnages s'épaissit de
// `bottom_weight` sous `bottom_weight_height_m` (pieds, espace local -- les
// meshes de personnages ont leur origine au sol) pour ancrer le corps au
// sol, comme l'encre tremblée de l'épingle 06.
uniform float bottom_weight : hint_range(1.0, 2.0) = 1.25;
uniform float bottom_weight_height_m : hint_range(0.0, 2.0) = 0.3;

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float width_px = outline_width_px;
	if (distance_falloff) {
		float dist = -view_pos.z;
		float t_near_far = clamp((dist - falloff_near_m) / max(falloff_far_m - falloff_near_m, 0.001), 0.0, 1.0);
		float w = mix(outline_width_px, falloff_far_px, t_near_far);
		if (dist > falloff_far_m) {
			float decay = pow(0.5, (dist - falloff_far_m) / max(falloff_decay_half_life_m, 0.001));
			w = falloff_floor_px + (falloff_far_px - falloff_floor_px) * decay;
		}
		width_px = max(w, falloff_floor_px);
	}
	if (VERTEX.y < bottom_weight_height_m) {
		width_px *= bottom_weight;
	}
	vec4 clip_position = PROJECTION_MATRIX * view_pos;
	// Normale lissee si l'attribut choisi est reellement peuple (longueur
	// significative), sinon repli sur NORMAL (facettee) -- voir en-tete de
	// fichier. `TANGENT` est deja en espace modele (comme NORMAL) a ce stade
	// de vertex(), donc directement comparable/transformable de la meme facon.
	vec3 smooth_normal_candidate = use_smooth_normal_tangent ? TANGENT : CUSTOM0.xyz;
	vec3 extrude_source = NORMAL;
	if (length(smooth_normal_candidate) > 0.5) {
		extrude_source = normalize(smooth_normal_candidate);
	}
	vec3 clip_normal = normalize((PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(extrude_source, 0.0))).xyz);
	// Largeur constante a l'ecran : l'offset en clip-space est mis a l'echelle
	// par clip_position.w (distance) pour compenser la division perspective,
	// et par 1/VIEWPORT_SIZE pour convertir des pixels en unites NDC.
	vec2 offset_px = clip_normal.xy * width_px;
	clip_position.xy += offset_px / VIEWPORT_SIZE * clip_position.w * 2.0;
	POSITION = clip_position;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	// TECH-04 : force le pipeline transparent -- seule voie autorisee a LIRE
	// le stencil (voir l'en-tete). Alpha plein : aucune transparence
	// visuelle, juste le routage de passe qu'exige `stencil_mode read`.
	ALPHA = 1.0;
}
