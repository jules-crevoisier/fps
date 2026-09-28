// scope_vignette.gdshader
// Habillage plein écran de la lunette (tâche "quatre armes", 2026-09-28,
// Aiguille — ScopeOverlay.gd) : cercle de visée clair au centre, vignette
// sombre qui s'assombrit vers le bord, puis noir plein (tube de la lunette)
// au-delà du rayon -- AUCUNE lecture de `screen_texture` (contrairement à
// death_tint.gdshader) : l'intérieur du cercle reste totalement TRANSPARENT
// (alpha 0), la scène 3D en dessous se voit donc telle quelle, sans
// désaturation/teinte -- seul l'alpha varie ici. Lu par un ColorRect plein
// écran (ScopeOverlay.gd, `_mask`) ; l'anneau d'encre + la croix simple sont
// dessinés PAR-DESSUS par un Control frère distinct (`_marks`, _draw()
// classique), jamais par ce shader -- un trait dessiné SOUS ce masque
// disparaîtrait sous le noir plein à son propre rayon.
shader_type canvas_item;

uniform float radius_px = 420.0;
uniform float vignette_width_px = 110.0;
uniform vec4 ink_color : source_color = vec4(0.106, 0.063, 0.188, 1.0);

void fragment() {
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 px = SCREEN_UV * screen_size - screen_size * 0.5;
	float d = length(px);
	float inner = radius_px - vignette_width_px;
	float a = clamp((d - max(inner, 0.0)) / max(vignette_width_px, 0.001), 0.0, 1.0);
	if (d >= radius_px) {
		a = 1.0;
	}
	COLOR = vec4(ink_color.rgb, a);
}
