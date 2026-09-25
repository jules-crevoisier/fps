## tools/blender/lib/fixtures/build_masks_test_prop.py
## Génère le "prop de test" du masque vertex RGBA unifié v3 (ART-20,
## docs/STYLE_BIBLE.md §7.9) : exerce toute la chaîne ajoutée par cette tâche
## sur un petit prop — `toonkit.bevel_for_class` (biseau §6.6, tag exact des
## faces de biseau) -> `weighted_normals` -> `smooth_normal_attrs` ->
## `bake_vertex_masks` (COLOR_0 : R = AO cuit Cycles, G = convexité, B =
## hauteur, A = zone de teinte) — posé au contact d'un sol de référence pour
## qu'un VRAI contact d'occlusion existe à bake (comparer
## `build_stylekit_test_prop.py`, A3D-02 : ce prop-ci flotte seul, sans sol,
## et ne peut donc prouver aucun "AO de contact"). Le sol n'est PAS exporté :
## il ne sert qu'à donner à Cycles une géométrie à occlure pendant le bake.
##
## Ce script ne fait PARTIE d'aucun générateur de production
## (`make_props.py` etc. ne sont pas modifiés, voir docs/3D_PIPELINE.md) :
## c'est une fixture reproductible, dans le même esprit que
## `build_stylekit_test_prop.py` (A3D-02), pour un futur test gdUnit4 et pour
## la vérification visuelle dans `look_probe` (ART-01 — pas encore livré au
## moment de cette tâche, voir rapport de tâche ART-20 : "arêtes éclaircies"
## et "AO de contact" sont ici prouvés par les valeurs du rapport JSON et par
## `render_masks_test_prop_preview.py`, en attendant que `look_probe.gd`
## existe). Régénérée par :
##   blender -b --factory-startup --python-exit-code 1 \
##       -P tools/blender/lib/fixtures/build_masks_test_prop.py
## Sortie : tools/blender/lib/fixtures/masks_test_prop.glb (+ .json).
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import bpy  # noqa: E402
import toonkit  # noqa: E402

OUT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "masks_test_prop.glb")

# Petit prop (§6.6 "petits props (< 1 m)" : biseau 1,2 cm, 200-800 tris),
# classe consommée par `bevel_for_class`/`tri_budget_for_class` ci-dessous.
SIZE = (0.4, 0.4, 0.4)
ASSET_CLASS = "prop_small"


def main() -> None:
	toonkit.reset_scene()

	# Sol de référence — non exporté (voir OUT_PATH plus bas : seul `prop`
	# est passé à `toonkit.export_glb`), juste un occludeur pour le bake AO.
	bpy.ops.mesh.primitive_plane_add(size=4.0, location=(0.0, 0.0, 0.0))
	floor = bpy.context.active_object
	floor.name = "MasksTestFloor"
	floor.data.materials.append(toonkit.toon_material(
		"floor_base", toonkit.palette("cracked_concrete"), kind="base"))

	# `bevel_width=0.0` neutralise le biseau interne de `rounded_box` (simple
	# no-op, voir `add_bevel`) : le biseau réel est posé juste après par
	# `bevel_for_class`, seule voie qui tague les faces de biseau consommées
	# par `bake_vertex_masks` (canal G — voir sa docstring).
	prop = toonkit.rounded_box(size=SIZE, bevel_width=0.0, segments=1, name="MasksTestProp")
	prop.location = (0.0, 0.0, SIZE[2] / 2.0)  # posé pile sur le sol, contact plein

	mat_base = toonkit.toon_material("base", toonkit.palette("painted_metal"), kind="base")
	mat_accent = toonkit.toon_material("accent", toonkit.palette("accent"), kind="accent")
	prop.data.materials.append(mat_base)
	prop.data.materials.append(mat_accent)
	# Une face sur deux en zone "accent" : preuve que le canal A (zone) suit
	# le matériau DU POLYGONE, pas une valeur unique posée pour tout l'objet.
	for i, poly in enumerate(prop.data.polygons):
		poly.material_index = 1 if i % 2 == 0 else 0

	toonkit.bevel_for_class(prop, ASSET_CLASS)
	toonkit.weighted_normals(prop, sharp_angle_deg=30.0)
	toonkit.smooth_normal_attrs(prop)
	toonkit.bake_vertex_masks(prop)
	toonkit.apply_transforms(prop)
	toonkit.set_origin_bottom(prop)

	print(f"MASKS_TEST_PROP tris={toonkit.tri_count(prop)} classe={ASSET_CLASS}")
	toonkit.export_glb(OUT_PATH, prop)


if __name__ == "__main__":
	main()
