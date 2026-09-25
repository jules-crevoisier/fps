## tools/blender/lib/fixtures/build_stylekit_test_prop.py
## Génère le "prop de test" utilisé par tests/rendering/test_stylekit_assets.gd
## (A3D-02, critère d'acceptation) : un petit prop biseauté qui exerce TOUTE
## la chaîne toonkit — biseau, normales pondérées (arêtes dures), normale
## lissée pour le contour, AO et courbure en couleurs de sommet — puis
## l'exporte en .glb + rapport JSON à côté (`export_glb`, voir toonkit.py).
##
## Ce script ne fait PARTIE d'aucun générateur de production (`make_props.py`
## etc. ne sont pas modifiés, voir docs/3D_PIPELINE.md) : il sert UNIQUEMENT
## de fixture reproductible pour le test gdUnit4 ci-dessus, régénérée par :
##   blender -b --factory-startup --python-exit-code 1 \
##       -P tools/blender/lib/fixtures/build_stylekit_test_prop.py
## Sortie : tools/blender/lib/fixtures/stylekit_test_prop.glb (+ .json).
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import toonkit  # noqa: E402

OUT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "stylekit_test_prop.glb")

# Petit prop (§6.6 "petits props (< 1 m)" : biseau 1,2 cm, 200-800 tris) —
# une boîte arrondie suffit à exercer arêtes dures (coins du bevel) ET faces
# planes (les 6 faces d'origine), donc à faire la preuve que la normale
# lissée reste continue de part et d'autre d'une arête vive.
SIZE = (0.4, 0.4, 0.4)
BEVEL_WIDTH = 0.012


def main() -> None:
	toonkit.reset_scene()
	mat = toonkit.toon_material("base", toonkit.palette("painted_metal"), kind="metal")
	prop = toonkit.rounded_box(size=SIZE, bevel_width=BEVEL_WIDTH, segments=1, name="StylekitTestProp")
	prop.data.materials.append(mat)

	toonkit.weighted_normals(prop, sharp_angle_deg=30.0)
	toonkit.smooth_normal_attrs(prop)
	toonkit.bake_vertex_ao(prop)
	toonkit.curvature_edge_mask(prop)
	toonkit.apply_transforms(prop)
	toonkit.set_origin_bottom(prop)

	print(f"STYLEKIT_TEST_PROP tris={toonkit.tri_count(prop)}")
	toonkit.export_glb(OUT_PATH, prop)


if __name__ == "__main__":
	main()
