## tools/blender/examples/make_sample_prop.py
## Exemple minimal d'usage de tools/blender/lib/toonkit.py : construit une
## caisse en bois (coins renforcés en métal) + un baril, les exporte dans
## UN SEUL .glb, puis prouve la boucle complète (voir docs/3D_PIPELINE.md) :
##   1) blender -b -P tools/blender/examples/make_sample_prop.py
##   2) blender -b -P tools/blender/check_asset.py -- --in <sortie> --budget-tris 800
##   3) blender -b -P tools/blender/turntable.py -- --in <sortie>
## Ne modifie aucun générateur existant ; ne fait que consommer toonkit.
##
## Budgets/biseaux : docs/STYLE_BIBLE.md §6.6 "Petits props (< 1 m)" — 256
## px/m, biseau 1,2 cm, 200-800 tris (LOD0). Les deux props ici en font
## chacun partie (caisse 0,8 m, baril 0,85 m de haut).
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))
import toonkit  # noqa: E402

OUT_PATH = os.path.join(toonkit.repo_root(), "assets", "models", "_samples", "sample_props.glb")

CRATE_SIZE = (0.8, 0.8, 0.8)
CRATE_BEVEL = 0.012          # §6.6 "petits props" : biseau 1,2 cm
CRATE_POST = 0.05            # section des renforts de coin (métal)

BARREL_RADIUS = 0.32
BARREL_HEIGHT = 0.85
BARREL_BEVEL = 0.012
BARREL_BAND_HEIGHTS = (-0.30, 0.0, 0.30)  # relatif au centre du fût


def build_crate():
	wood_mat = toonkit.toon_material("wood_planks", toonkit.palette("wood_planks"), kind="wood_planks")
	metal_mat = toonkit.toon_material("metal", toonkit.palette("painted_metal"), kind="metal")

	body = toonkit.rounded_box(size=CRATE_SIZE, bevel_width=CRATE_BEVEL, segments=1, name="Crate_Body")
	body.data.materials.append(wood_mat)

	posts = []
	half_x, half_y, half_z = (s / 2.0 for s in CRATE_SIZE)
	post_len = CRATE_SIZE[2] + 0.02  # dépasse très légèrement en haut/bas, façon cornière métallique
	for sx in (-1, 1):
		for sy in (-1, 1):
			post = toonkit.rounded_box(size=(CRATE_POST, CRATE_POST, post_len),
				bevel_width=0.004, segments=1, name="Crate_Post")
			post.data.materials.append(metal_mat)
			post.location = (sx * (half_x - CRATE_POST / 2.0), sy * (half_y - CRATE_POST / 2.0), 0.0)
			posts.append(post)

	crate = toonkit.join([body] + posts)
	crate.name = "Crate"
	toonkit.bake_vertex_ao(crate)
	toonkit.curvature_edge_mask(crate)
	toonkit.apply_transforms(crate)
	toonkit.set_origin_bottom(crate)
	# PAS de second apply_transforms ici : il re-baierait cette translation et
	# décalerait l'origine hors du centre-bas (piège déjà rencontré une fois
	# en écrivant ce script — voir docs/3D_PIPELINE.md §5). Un simple
	# décalage de node laissé tel quel s'exporte très bien en glTF.
	crate.location.x = -0.7  # écarte les deux props l'un de l'autre dans le .glb
	return crate


def build_barrel():
	metal_mat = toonkit.toon_material("painted_metal", toonkit.palette("painted_metal"), kind="painted_metal")
	band_mat = toonkit.toon_material("metal", toonkit.palette("graphite"), kind="metal")

	body = toonkit.tapered_cylinder(r1=BARREL_RADIUS, r2=BARREL_RADIUS * 0.96, depth=BARREL_HEIGHT,
		segments=16, name="Barrel_Body")
	body.data.materials.append(metal_mat)
	toonkit.add_bevel(body, width=BARREL_BEVEL, segments=1)
	toonkit.weighted_normals(body, sharp_angle_deg=30.0)

	bands = []
	for z in BARREL_BAND_HEIGHTS:
		band = toonkit.tapered_cylinder(r1=BARREL_RADIUS + 0.015, r2=BARREL_RADIUS + 0.015, depth=0.035,
			segments=16, name="Barrel_Band")
		band.data.materials.append(band_mat)
		band.location = (0.0, 0.0, z)
		bands.append(band)

	barrel = toonkit.join([body] + bands)
	barrel.name = "Barrel"
	toonkit.bake_vertex_ao(barrel)
	toonkit.curvature_edge_mask(barrel)
	toonkit.apply_transforms(barrel)
	toonkit.set_origin_bottom(barrel)
	barrel.location.x = 0.7  # voir la remarque équivalente dans build_crate()
	return barrel


def main() -> None:
	toonkit.reset_scene()
	crate = build_crate()
	barrel = build_barrel()
	print(f"SAMPLE_PROP tris crate={toonkit.tri_count(crate)} barrel={toonkit.tri_count(barrel)}")
	toonkit.export_glb(OUT_PATH, [crate, barrel])


if __name__ == "__main__":
	main()
