// dev_grid.gdshader
// Wasteland v7 — greybox pur (2026-09-26, "carte block jouable"). Matériau de
// développement UNIQUE pour toute la géométrie générée par
// `scripts/levels/maps/layouts/wasteland.gd` depuis `data/maps/
// wasteland_plan.json` : grille triplanaire MONDE (lignes mineures tous les
// 1 m, majeures tous les 5 m — `data/maps/wasteland_plan.json`
// `materials.grid`), teintée par fonction (mur/sol/couvert/escalier/hors-
// limites — `materials.by_kind`). Aucune texture peinte : la lisibilité vient
// de la grille + de la couleur de rôle, jamais d'un bake externe.
//
// Consommé via `Cartoon.dev_grid()`/`Cartoon.painted()` (kind canonique
// "dev_grid", scripts/core/Cartoon.gd) — jamais directement instancié
// ailleurs, pour que toute la géométrie Wasteland partage EXACTEMENT le même
// shader (un seul répertorié ici, `materials.grid` de wasteland_plan.json
// n'a donc qu'UNE seule implémentation à respecter).
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec4 albedo_color : source_color = vec4(0.75, 0.72, 0.66, 1.0);
uniform float minor_spacing : hint_range(0.1, 10.0) = 1.0;
uniform float major_spacing : hint_range(0.5, 50.0) = 5.0;
uniform float minor_half_width : hint_range(0.0, 0.5) = 0.01;
uniform float major_half_width : hint_range(0.0, 0.5) = 0.025;
uniform float minor_darken : hint_range(0.0, 1.0) = 0.12;
uniform float major_darken : hint_range(0.0, 1.0) = 0.28;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Distance (m) au trait de grille le plus proche sur un axe 1D, pliée
// autour de chaque multiple de `spacing` — 0 pile sur la ligne, `spacing/2`
// à mi-chemin entre deux lignes.
float _grid_dist(float c, float spacing) {
	return abs(fract(c / spacing + 0.5) - 0.5) * spacing;
}

// 1.0 = pas de trait à ce pixel, 0.0 = pile sur le trait — anti-aliasé par
// `fwidth` (largeur d'un pixel projetée en unités monde), jamais un seuil
// dur qui scintillerait au loin.
float _line_mask(float d, float half_w) {
	float aa = max(fwidth(d), 0.0008);
	return smoothstep(half_w - aa, half_w + aa, d);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec3 w = n / max(n.x + n.y + n.z, 0.0001);

	// Triplanaire : une grille par paire d'axes (YZ pour une face qui
	// regarde X, XZ pour Y, XY pour Z), pondérée par la normale — un mur
	// vertical (normale sur X ou Z) ne voit jamais la grille "au sol" (XZ)
	// se répéter de travers sur sa propre face.
	float minor_yz = min(_line_mask(_grid_dist(world_pos.y, minor_spacing), minor_half_width),
			_line_mask(_grid_dist(world_pos.z, minor_spacing), minor_half_width));
	float minor_xz = min(_line_mask(_grid_dist(world_pos.x, minor_spacing), minor_half_width),
			_line_mask(_grid_dist(world_pos.z, minor_spacing), minor_half_width));
	float minor_xy = min(_line_mask(_grid_dist(world_pos.x, minor_spacing), minor_half_width),
			_line_mask(_grid_dist(world_pos.y, minor_spacing), minor_half_width));
	float minor = minor_yz * w.x + minor_xz * w.y + minor_xy * w.z;

	float major_yz = min(_line_mask(_grid_dist(world_pos.y, major_spacing), major_half_width),
			_line_mask(_grid_dist(world_pos.z, major_spacing), major_half_width));
	float major_xz = min(_line_mask(_grid_dist(world_pos.x, major_spacing), major_half_width),
			_line_mask(_grid_dist(world_pos.z, major_spacing), major_half_width));
	float major_xy = min(_line_mask(_grid_dist(world_pos.x, major_spacing), major_half_width),
			_line_mask(_grid_dist(world_pos.y, major_spacing), major_half_width));
	float major = major_yz * w.x + major_xz * w.y + major_xy * w.z;

	float darken = (1.0 - minor) * minor_darken + (1.0 - major) * major_darken;
	ALBEDO = albedo_color.rgb * clamp(1.0 - darken, 0.0, 1.0);
	// Jamais d'ALPHA ici : écrire ALPHA (même à 1) bascule Godot en pipeline
	// transparent, sans écriture de profondeur -> murs vus au travers (revue
	// lead 2026-09-26). Tout le greybox est opaque ; les volumes invisibles
	// (clip, murs anti-joueur) n'ont pas de rendu du tout.
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.3;
}
