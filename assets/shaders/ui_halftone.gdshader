// ui_halftone.gdshader
// Couche 3 « Trame » (docs/STYLE_BIBLE.md §8.1 « Le charbon informe,
// l'autocollant se choisit, la trame célèbre », §8.2 jeton `halftone` :
// « points de 4 px au pas de 8 px, 45°, encre à 18 % d'opacité ou pinceau »).
// Célèbre un moment (match trouvé, verrouillage d'agent, manche gagnée,
// multi-kill, MVP, niveau de compte) puis DISPARAÎT — règle d'or #4 (§8.1) :
// « la trame ne dure pas », jamais en permanence. Ce shader ne boucle jamais
// seul (aucune horloge interne) : c'est l'appelant (scripts/ui/kit/KitTrame.gd)
// qui anime `reveal` sur la fenêtre de temps autorisée (Comic.DUR_BURST_MIN/MAX,
// 600–1200 ms) puis le ramène à 0, et qui fige `freeze` à 1 en menu après le
// délai (§8.1 règle 4 « puis elle se fige en aplat ») — jamais en mouvement
// réduit, où « la trame est statique » (reveal fixé directement, sans tween).
shader_type canvas_item;

// Couleur du point — encre `#1A1410` par défaut (STYLE_BIBLE v3 §8.2 jeton
// `ink`) ; KitTrame.gd bascule vers `pinceau` `#C8242C` selon `ink_variant`.
uniform vec4 dot_color : source_color = vec4(0.101961, 0.0784314, 0.0627451, 1.0);
// Diamètre du point et pas de la grille, en pixels (jeton `halftone`).
uniform float dot_px = 4.0;
uniform float pitch_px = 8.0;
// Inclinaison de la grille — toujours 45° (jeton `halftone`, jamais un autre
// angle : STYLE_BIBLE v3 §8.1 règle 5 « une seule inclinaison, 12° » vise les
// FORMES/l'italique, la trame reste sur son propre angle dédié à 45°).
uniform float angle_deg = 45.0;
// Opacité de base des points (0.18 = encre par défaut, jeton `halftone`).
uniform float dot_opacity : hint_range(0.0, 1.0) = 0.18;
// Taille du rectangle porteur en pixels — poussée par KitTrame.gd
// (`material.set_shader_parameter("rect_size", size)` sur `resized`) : un
// shader canvas_item n'a pas nativement la taille locale du Control en
// pixels, seulement `UV` (0..1).
uniform vec2 rect_size = vec2(256.0, 256.0);
// Progression du moment (0..1) : révélation RADIALE depuis le centre du
// rectangle — jamais animée ici, voir note de classe.
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
// Mélange vers un aplat plein de `dot_color` (§8.1 règle 4, menus) : 0 = trame
// de points, 1 = aplat continu.
uniform float freeze : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 px = UV * rect_size;

	// Grille de points tournée à `angle_deg` : distance au point de grille le
	// plus proche -> disque de rayon `dot_px * 0.5`, bord anti-aliasé sur
	// ~1 px (jamais un flou natif de moteur — CHK-38 ne s'applique qu'aux
	// StyleBoxFlat, mais l'esprit "ombres/bords nets, le relief vient du
	// décalage" tient aussi ici : 1 px de anti-aliasing, pas un halo).
	float rad = radians(angle_deg);
	mat2 rot = mat2(vec2(cos(rad), -sin(rad)), vec2(sin(rad), cos(rad)));
	vec2 rotated = rot * px;
	vec2 cell = mod(rotated, pitch_px) - vec2(pitch_px * 0.5);
	float dist = length(cell);
	float dot_mask = 1.0 - smoothstep(dot_px * 0.5 - 1.0, dot_px * 0.5 + 1.0, dist);

	// Révélation radiale depuis le centre du rectangle (moment qui « éclate »
	// depuis son origine, cohérent avec ComicBurst.gd — étoile centrée).
	vec2 center = rect_size * 0.5;
	float max_r = max(length(rect_size) * 0.5, 0.0001);
	float d = length(px - center) / max_r;
	float reveal_mask = 1.0 - smoothstep(reveal, reveal + 0.06, d);

	float mask = mix(dot_mask, 1.0, freeze) * dot_opacity * reveal_mask;
	COLOR = vec4(dot_color.rgb, dot_color.a * mask);
}
