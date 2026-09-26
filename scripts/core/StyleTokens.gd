## StyleTokens.gd
## Nettoyage du prototype 2026-09-26 ("clean absolument tout") : le générateur
## (tools/style/gen_style_tokens.py) et sa source (docs/style/tokens.json) ont
## été supprimés avec le reste de l'outillage de style -- cette table est
## désormais maintenue à la main directement ici.
##
## Palette par carte (MatchConfig.map_id) : ciel (sky_zenith/sky_horizon),
## soleil (sun_color/sun_elevation_deg), ombre (shadow_tint), sol (ground),
## coulisses (backdrop_near/backdrop_far) et brouillard (fog) -- voir la
## docstring de gen_style_tokens.py pour la provenance/formule de chaque cle.
## Cartoon.gd (scripts/core/Cartoon.gd) est le SEUL consommateur en jeu ;
## LevelLook.gd/InkPost.gd/PlayerLook.gd lisent Cartoon.map_palette(), jamais
## StyleTokens directement (une seule facade publique, voir Cartoon.gd SS7.7).
class_name StyleTokens
extends RefCounted

const DEFAULT_MAP_ID := "shipment"

## tokens.json "reserved" : bandes de teinte OKLCH interdites a toute
## couleur de base (monde, personnage, cosmetique) au-dela de ce seuil de
## chroma -- exclusives a la surbrillance ennemie (Magenta/Citron).
const RESERVED_HUE_BANDS_DEG: Array = [[300.0, 355.0], [105.0, 145.0]]
const RESERVED_CHROMA_THRESHOLD := 0.08

const MAP_PALETTES: Dictionary = {
	"port_ferraille": {
		"sky_zenith": Color("4a8fe0"),
		"sky_horizon": Color("d6ecf6"),
		"sun_color": Color("fff1d0"),
		"sun_elevation_deg": 40.0,
		"shadow_tint": Color("5f71a8"),
		"ground": Color("bba98c"),
		"backdrop_near": Color("b2c7df"),
		"backdrop_far": Color("d6ecf6"),
		"fog": Color("e6eee7"),
	},
	"val_poussiere": {
		"sky_zenith": Color("3c7fd9"),
		"sky_horizon": Color("f2d7a8"),
		"sun_color": Color("ffc98a"),
		"sun_elevation_deg": 28.0,
		"shadow_tint": Color("6a63a0"),
		"ground": Color("c9a06e"),
		"backdrop_near": Color("c9b4a6"),
		"backdrop_far": Color("f2d7a8"),
		"fog": Color("f7d19c"),
	},
	"saint_ombre": {
		"sky_zenith": Color("3f6f86"),
		"sky_horizon": Color("f0b860"),
		"sun_color": Color("ffb870"),
		"sun_elevation_deg": 22.0,
		"shadow_tint": Color("3e4f7a"),
		"ground": Color("6e6a73"),
		"backdrop_near": Color("bb9868"),
		"backdrop_far": Color("f0b860"),
		"fog": Color("f6b866"),
	},
	"col_du_vautour": {
		"sky_zenith": Color("1f63d0"),
		"sky_horizon": Color("cfe6f7"),
		"sun_color": Color("fff6e0"),
		"sun_elevation_deg": 42.0,
		"shadow_tint": Color("6c86c8"),
		"ground": Color("f1f4f8"),
		"backdrop_near": Color("b1c9e9"),
		"backdrop_far": Color("cfe6f7"),
		"fog": Color("e2ecee"),
	},
	"la_fosse": {
		"sky_zenith": Color("3a80dc"),
		"sky_horizon": Color("d3e7f5"),
		"sun_color": Color("ffe0a6"),
		"sun_elevation_deg": 50.0,
		"shadow_tint": Color("6072ae"),
		"ground": Color("e3d3ae"),
		"backdrop_near": Color("b0c4e0"),
		"backdrop_far": Color("d3e7f5"),
		"fog": Color("e5e4d5"),
	},
	"le_belvedere": {
		"sky_zenith": Color("5a8fd8"),
		"sky_horizon": Color("ffd9a0"),
		"sun_color": Color("ffd3a0"),
		"sun_elevation_deg": 25.0,
		"shadow_tint": Color("5e6aa8"),
		"ground": Color("c9b79a"),
		"backdrop_near": Color("cfb8a2"),
		"backdrop_far": Color("ffd9a0"),
		"fog": Color("ffd7a0"),
	},
	"shipment": {
		"sky_zenith": Color("2f74d8"),
		"sky_horizon": Color("bfddf2"),
		"sun_color": Color("ffd99a"),
		"sun_elevation_deg": 32.0,
		"shadow_tint": Color("5b6ca6"),
		"ground": Color("d2a46c"),
		"backdrop_near": Color("a1bbdb"),
		"backdrop_far": Color("bfddf2"),
		"fog": Color("d9dbcf"),
	},
	"cargo_ship": {
		"sky_zenith": Color("3e86e0"),
		"sky_horizon": Color("cde8f8"),
		"sun_color": Color("fff0c8"),
		"sun_elevation_deg": 45.0,
		"shadow_tint": Color("5a6ea8"),
		"ground": Color("8d959b"),
		"backdrop_near": Color("abc3e0"),
		"backdrop_far": Color("cde8f8"),
		"fog": Color("e1ebe5"),
	},
}
