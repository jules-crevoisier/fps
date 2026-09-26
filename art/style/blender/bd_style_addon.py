"""bd_style_addon.py -- petit add-on Blender "Style BD" : panneau dans la barre
latérale de la vue 3D (touche N, onglet "Style BD") avec deux boutons :
  - "Appliquer le style BD a la selection" -> toon_bd_nodes.apply_toon_bd_to_selection
    (+ pose un contour Line Art sur chaque maillage sélectionné).
  - "Scene d'apercu BD" -> toon_bd_nodes.setup_scene (soleil/ambiance/étalonnage
    depuis art/style/toon_style.json).

Installation (outil interne au dépôt, pas un add-on destiné à être distribué --
voir art/style/README.md) : le plus simple et le plus robuste est d'ouvrir CE
fichier dans l'onglet Scripting de Blender (Text Editor > Open, depuis
art/style/blender/bd_style_addon.py) puis "Run Script" -- il s'enregistre pour
la session en cours et retrouve ses fichiers frères (`toon_bd_nodes.py`/
`ink_bake.py`/`_style.py`) via son PROPRE chemin sur disque (`__file__`), donc
sans dépendre d'une installation "officielle" qui les laisserait derrière (une
installation via Preferences > Add-ons > Install... ne copie QUE ce fichier,
pas ses frères). Il peut aussi être activé de façon persistante en le
copiant -- avec ses trois frères -- dans le dossier addons de Blender.
"""
from __future__ import annotations

import os
import sys

bl_info = {
	"name": "Style BD (Borderlands)",
	"author": "FPS project",
	"version": (1, 0, 0),
	"blender": (5, 2, 0),
	"location": "View3D > Sidebar > Style BD",
	"description": "Applique le style BD (art/style/toon_style.json) aux materiaux/scene selectionnes",
	"category": "Material",
}

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if _THIS_DIR not in sys.path:
	sys.path.insert(0, _THIS_DIR)

import bpy  # noqa: E402

from toon_bd_nodes import (  # noqa: E402
	add_line_art_outline,
	apply_toon_bd_to_selection,
	build_toon_bd_node_group,
	setup_scene,
)
from _style import load_style  # noqa: E402


class BD_OT_apply_style(bpy.types.Operator):
	bl_idname = "bd_style.apply_to_selection"
	bl_label = "Appliquer le style BD a la selection"
	bl_description = "Reconstruit le materiau ToonBD (garde la texture peinte) + contour Line Art sur chaque maillage selectionne"
	bl_options = {"REGISTER", "UNDO"}

	def execute(self, context):
		style = load_style(force_reload=True)
		# Une seule reconstruction du groupe "ToonBD" avant la boucle par
		# matériau (voir la doc de `build_toon_bd_node_group` : reconstruire à
		# CHAQUE matériau invaliderait les couleurs déjà posées sur les
		# matériaux précédents de cette même sélection).
		build_toon_bd_node_group(style, force_rebuild=True)
		count = apply_toon_bd_to_selection(style)
		outlines = 0
		for obj in context.selected_objects:
			if obj.type == "MESH":
				add_line_art_outline(obj, style)
				outlines += 1
		self.report({"INFO"}, "Style BD : %d materiau(x), %d contour(s) Line Art" % (count, outlines))
		return {"FINISHED"}


class BD_OT_preview_scene(bpy.types.Operator):
	bl_idname = "bd_style.preview_scene"
	bl_label = "Scene d'apercu BD"
	bl_description = "Configure soleil/ambiance/etalonnage de la scene courante depuis art/style/toon_style.json"
	bl_options = {"REGISTER", "UNDO"}

	def execute(self, context):
		setup_scene(context.scene, load_style(force_reload=True))
		self.report({"INFO"}, "Scene d'apercu BD configuree")
		return {"FINISHED"}


class BD_PT_panel(bpy.types.Panel):
	bl_idname = "BD_PT_style_panel"
	bl_label = "Style BD"
	bl_space_type = "VIEW_3D"
	bl_region_type = "UI"
	bl_category = "Style BD"

	def draw(self, context):
		layout = self.layout
		layout.label(text="art/style/toon_style.json v2")
		layout.operator(BD_OT_apply_style.bl_idname, icon="MATERIAL")
		layout.operator(BD_OT_preview_scene.bl_idname, icon="WORLD")
		layout.separator()
		layout.label(text="Encrage : voir ink_bake.py (CLI, pas ce panneau).")


_CLASSES = (BD_OT_apply_style, BD_OT_preview_scene, BD_PT_panel)


def register() -> None:
	for cls in _CLASSES:
		bpy.utils.register_class(cls)


def unregister() -> None:
	for cls in reversed(_CLASSES):
		bpy.utils.unregister_class(cls)


if __name__ == "__main__":
	register()
