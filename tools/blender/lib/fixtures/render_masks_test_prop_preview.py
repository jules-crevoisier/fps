## tools/blender/lib/fixtures/render_masks_test_prop_preview.py
## Rendu de vérification VISUELLE du masque vertex RGBA unifié (ART-20,
## docs/STYLE_BIBLE.md §7.9) sur `masks_test_prop.glb` — tient lieu de
## `look_probe` (ART-01, pas encore livré dans ce dépôt au moment de cette
## tâche : `tools/look_probe.gd` n'existe pas encore, voir rapport de tâche)
## pour prouver par l'image, et pas seulement par les valeurs du rapport
## JSON, que le prop d'exemple "montre des arêtes éclaircies et un AO de
## contact" (critère d'acceptation ART-20).
##
## Matériau de PREVIEW seulement (Emission = albédo × R (AO) + G (surbrillance
## d'arête blanche) — approxime `edge_highlight`/`ao_min` de §7.2 sans
## réimplémenter tout `ink_toon`, juste assez pour qu'un oeil humain voie les
## deux effets sur un rendu EEVEE) : ce script ne modifie ni n'exporte
## aucun asset, il ne fait QUE lire `masks_test_prop.glb` (régénéré par
## `build_masks_test_prop.py`) et écrire une image à côté.
##
##   blender -b --factory-startup --python-exit-code 1 \
##       -P tools/blender/lib/fixtures/render_masks_test_prop_preview.py
## Sortie : tools/blender/lib/fixtures/masks_test_prop_preview.png.
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import bpy  # noqa: E402
import toonkit  # noqa: E402

GLB_PATH = os.path.join(HERE, "masks_test_prop.glb")
OUT_PNG = os.path.join(HERE, "masks_test_prop_preview.png")


def main() -> None:
	toonkit.reset_scene()
	bpy.ops.import_scene.gltf(filepath=GLB_PATH)
	prop = next(o for o in bpy.context.scene.objects if o.type == 'MESH')

	# Sol de contexte (même rôle que dans build_masks_test_prop.py : montrer
	# où le prop touche le sol) — pas de matériau spécial requis, un gris neutre.
	bpy.ops.mesh.primitive_plane_add(size=4.0, location=(0.0, 0.0, 0.0))
	floor = bpy.context.active_object
	floor.data.materials.append(toonkit.toon_material("floor_preview", (0.55, 0.55, 0.55), kind="base"))

	# Matériau de PREVIEW : lit l'attribut de couleur réimporté ("Color", voir
	# check_asset.py — le nom d'export "masks" ne survit pas au réimport
	# glTF, seul l'INDEX 0/actif compte) et sort R (AO) et G (convexité) en
	# émission — aucun éclairage requis, aucune ambiguïté d'exposition.
	mat = bpy.data.materials.new("MasksPreview")
	mat.use_nodes = True
	nt = mat.node_tree
	for n in list(nt.nodes):
		nt.nodes.remove(n)
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	emit = nt.nodes.new("ShaderNodeEmission")
	attr = nt.nodes.new("ShaderNodeAttribute")
	attr.attribute_type = 'GEOMETRY'
	attr.attribute_name = prop.data.color_attributes[0].name
	sep = nt.nodes.new("ShaderNodeSeparateColor")
	combine = nt.nodes.new("ShaderNodeCombineColor")
	nt.links.new(attr.outputs["Color"], sep.inputs["Color"])
	# R brut est déjà remappé sur [0,55 ; 1] par bake_vertex_masks (§7.9) —
	# l'écart contact/non-contact y est réel mais visuellement discret ; une
	# puissance exagère le contraste pour CETTE preview seulement (jamais
	# fait dans toonkit.py lui-même, qui livre la valeur brute du §7.9).
	contrast = nt.nodes.new("ShaderNodeMath")
	contrast.operation = 'POWER'
	contrast.inputs[1].default_value = 6.0
	nt.links.new(sep.outputs["Red"], contrast.inputs[0])
	# Canal B (bleu) = AO contrastée (gris froid, contact nettement plus
	# sombre) ; canal R (rouge) = AO contrastée + G (l'arête de biseau
	# ressort en ROUGE VIF sur fond gris-bleu — bien plus lisible qu'un
	# blanc-sur-blanc).
	mul = nt.nodes.new("ShaderNodeMath")
	mul.operation = 'MULTIPLY'
	mul.inputs[1].default_value = 0.8
	nt.links.new(contrast.outputs[0], mul.inputs[0])
	add = nt.nodes.new("ShaderNodeMath")
	add.operation = 'ADD'
	nt.links.new(mul.outputs[0], add.inputs[0])
	nt.links.new(sep.outputs["Green"], add.inputs[1])
	nt.links.new(add.outputs[0], combine.inputs["Red"])
	nt.links.new(mul.outputs[0], combine.inputs["Green"])
	nt.links.new(mul.outputs[0], combine.inputs["Blue"])
	nt.links.new(combine.outputs["Color"], emit.inputs["Color"])
	nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
	prop.data.materials.clear()
	prop.data.materials.append(mat)

	# Vue orthographique de face (droit sur une face du cube, pas de coin en
	# perspective) : la fine bande de biseau (1,2 cm sur un cube de 0,4 m)
	# ressort sans ambiguïté comme un LISERÉ sur les 4 bords d'une face
	# par ailleurs plate, et le bas de cette même face montre le contact au
	# sol (AO plus sombre) — la perspective d'un coin de cube, elle,
	# raccourcit les faces de façon inégale et peut faire paraître une bande
	# de biseau aussi large qu'une face plate à l'écran (vérifié par sondage
	# lors de l'écriture de ce script : la DONNÉE du masque est correcte,
	# seul le cadrage en coin trompait l'oeil).
	bpy.ops.object.camera_add(location=(0.0, -1.4, 0.2), rotation=(1.5708, 0.0, 0.0))
	cam_data = bpy.context.active_object.data
	cam_data.type = 'ORTHO'
	cam_data.ortho_scale = 0.55
	cam = bpy.context.active_object
	bpy.context.scene.camera = cam

	scene = bpy.context.scene
	scene.render.engine = 'BLENDER_EEVEE'
	scene.render.resolution_x = 512
	scene.render.resolution_y = 512
	scene.render.filepath = OUT_PNG
	scene.render.image_settings.file_format = 'PNG'
	bpy.ops.render.render(write_still=True)
	print(f"MASKS_PREVIEW_OK {OUT_PNG}")


if __name__ == "__main__":
	main()
