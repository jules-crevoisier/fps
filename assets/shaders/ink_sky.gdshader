// ink_sky.gdshader
// Big blue sky (design.md v2 SS4 "Lighting script", retuned v3 per
// STYLE_BIBLE.md SS7.6): a zenith-to-horizon gradient (per-map colours, set
// by LevelLook.gd from Cartoon.map_palette()), a soft warm sun disc, and
// painted, FLAT-BOTTOMED cumulus clouds sitting only 6-30 degrees above the
// horizon at ~32% coverage (3 to 5 big, legible masses per half-sky instead
// of v2's "30 crumbs") -- below 6 degrees is plain haze, so the coulisses
// ring (scripts/levels/Backdrop.gd) and rooftop/building silhouettes stay
// readable against it. No ink line on the clouds (v1's dark ring is gone:
// "Clouds: ... no ink").
//
// ART-76 (docs/research/09_wasteland_vertical_slice.md SS d.6, CHK-13 "3 a
// 5 masses nuageuses par demi-ciel, aucune sous 6 degres") re-verified this
// exact cloud band/coverage/scale against that criterion: the values below
// were already the ones calibrated for it (see the v3 note above and
// cloud_coverage's own comment further down) and are RELOCKED by
// tests/levels/test_backdrop.gd rather than re-tuned blind -- changing them
// again needs a fresh render + tools/review/style_check.py pass, not a
// guess from reading the noise math alone.
shader_type sky;

uniform vec4 sky_zenith_color : source_color = vec4(0.243, 0.525, 0.878, 1.0);   // #3E86E0
uniform vec4 sky_horizon_color : source_color = vec4(0.804, 0.910, 0.973, 1.0);  // #CDE8F8
uniform float horizon_blur : hint_range(0.01, 0.4) = 0.12;
uniform vec4 ground_color : source_color = vec4(0.45, 0.42, 0.37, 1.0);

// v3 (STYLE_BIBLE.md SS7.6, tache ART-06) : disque plus large + halo plus
// doux mais moins intense -- un soleil peint plus present sans laver le ciel.
uniform vec4 sun_color : source_color = vec4(1.0, 0.941, 0.784, 1.0); // #FFF0C8
uniform float sun_disc_radius : hint_range(0.005, 0.1) = 0.025;
uniform float sun_glow_radius : hint_range(0.02, 0.4) = 0.15;
uniform float sun_glow_strength : hint_range(0.0, 1.0) = 0.35;

// Cumulus band v3 (STYLE_BIBLE.md SS7.6) : 3 a 5 GROSSES masses lisibles par
// demi-ciel (cloud_scale 5.0 -> 3.0, moins de cellules de bruit par demi-tour
// de ciel) au lieu de "30 miettes" v2, bande plus basse/etroite (6-30 deg au
// lieu de 8-35) et bord de seuil plus net (0.04 au lieu de 0.12 : 2 tons
// francs, pas un dégradé mou) -- couverture 0.32 (un poil plus dense que
// 0.28 pour rester a 3-5 masses malgre l'echelle reduite, cf CHK-13).
uniform vec4 cloud_lit_color : source_color = vec4(1.0, 0.973, 0.925, 1.0);   // #FFF8EC
uniform vec4 cloud_shade_color : source_color = vec4(0.655, 0.722, 0.878, 1.0); // #A7B8E0
uniform float cloud_band_low_deg : hint_range(0.0, 30.0) = 6.0;
uniform float cloud_band_high_deg : hint_range(10.0, 60.0) = 30.0;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.32;
uniform float cloud_scale : hint_range(1.0, 20.0) = 3.0;
// Largeur du seuil de bord de nuage (STYLE_BIBLE.md SS7.6 "0,12 -> 0,04") :
// bord net, deux tons francs plutot qu'un flou -- voir son usage plus bas
// (`threshold + cloud_edge_width`).
uniform float cloud_edge_width : hint_range(0.01, 0.2) = 0.04;

// Cheap 3D value noise (seamless on a sky dome: it's a function of the
// EYEDIR unit vector, not a wrapped 2D UV, so there is no seam to hide).
float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

float cloud_fbm(vec3 p) {
	float total = 0.0;
	float amp = 0.55;
	float freq = 1.0;
	for (int i = 0; i < 4; i++) {
		total += value_noise3(p * freq) * amp;
		freq *= 2.05;
		amp *= 0.5;
	}
	return total;
}

void sky() {
	float up = clamp(EYEDIR.y, -1.0, 1.0);

	// Base zenith/horizon/ground gradient.
	float to_top = smoothstep(0.0, 0.65, up);
	vec3 col = mix(sky_horizon_color.rgb, sky_zenith_color.rgb, to_top);
	col = mix(ground_color.rgb, col, smoothstep(-horizon_blur, horizon_blur, up));

	// Cumulus band: only between cloud_band_low_deg and cloud_band_high_deg.
	float elev_deg = degrees(asin(up));
	float band_t = clamp(
		(elev_deg - cloud_band_low_deg) / max(cloud_band_high_deg - cloud_band_low_deg, 0.001),
		0.0, 1.0
	);
	// Hard cutoff near the band's bottom (a FLAT base, silhouetted against
	// the haze) and a soft fade near its top (a wispy upper edge).
	float base_cut = smoothstep(0.0, 0.06, band_t);
	float top_fade = 1.0 - smoothstep(0.7, 1.0, band_t);
	float density = cloud_fbm(EYEDIR * cloud_scale) * base_cut * top_fade;
	float threshold = 1.0 - clamp(cloud_coverage, 0.0, 1.0);
	float cloud_mask = smoothstep(threshold, threshold + cloud_edge_width, density);

	// 2-tone shading: the flat underside is the cool shade tone, the puffy
	// upper part is the warm lit tone -- a hard-ish step, not a gradient,
	// for a painted-cel look rather than a photographic soft blend.
	float tone = smoothstep(0.30, 0.40, band_t);
	vec3 cloud_color = mix(cloud_shade_color.rgb, cloud_lit_color.rgb, tone);
	col = mix(col, cloud_color, cloud_mask);

	// Warm sun: a soft disc + a wider, gentle glow halo.
	if (LIGHT0_ENERGY > 0.0) {
		float d = distance(EYEDIR, LIGHT0_DIRECTION);
		float glow = smoothstep(sun_glow_radius, 0.0, d) * sun_glow_strength;
		col = mix(col, sun_color.rgb, glow);
		float disc = smoothstep(sun_disc_radius, sun_disc_radius * 0.6, d);
		col = mix(col, sun_color.rgb, disc);
	}

	COLOR = col;
}
