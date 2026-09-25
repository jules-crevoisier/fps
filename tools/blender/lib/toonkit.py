## tools/blender/lib/toonkit.py
## Bibliothèque bpy réutilisable pour la production d'assets stylisés
## (voir docs/3D_PIPELINE.md pour la boucle complète generate -> check ->
## turntable -> export). Factorise ce que make_weapons.py / make_props.py /
## make_characters.py / make_gloves.py réinventent chacun un peu différemment
## (reset de scène, matériaux, bevel, export .glb) — CES QUATRE FICHIERS NE
## SONT PAS MODIFIÉS ici, ils continuent de fonctionner tels quels ; ce module
## sert aux PROCHAINS générateurs (et aux scripts turntable.py/check_asset.py
## de ce même dossier).
##
## Import depuis un script lancé par `blender -b -P tools/blender/xxx.py` :
##     import os, sys
##     sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
##     import toonkit
##
## Convention d'axes — PLUS SIMPLE que make_weapons.py/make_props.py à
## dessein : toutes les primitives de ce module construisent DIRECTEMENT dans
## le repère natif de Blender, Z-up (Z = haut/axe long, X/Y = horizontal).
## AUCUNE rotation manuelle n'est nécessaire nulle part : `export_glb()`
## passe `export_yup=True` à l'exporteur glTF, qui convertit AUTOMATIQUEMENT
## et TOUJOURS ce Z-up natif vers le Y-up attendu par le fichier .glb/Godot
## (Blender Z -> glTF Y, Blender -Y -> glTF Z, Blender X -> glTF X) — c'est le
## comportement standard de l'exporteur, pas quelque chose que ce module doit
## imiter à la main. (make_weapons.py/make_props.py, eux, écrivent leurs
## coordonnées comme si Y était déjà "haut" par lisibilité, puis appliquent
## UNE rotation +90°/X manuelle pour obtenir la géométrie Z-up réelle avant ce
## même export_yup=True — un choix d'écriture qui leur est propre, pas un
## contrat de ce module : ici, `size`/`radius`/`height`/`depth` sont TOUJOURS
## en coordonnées Blender réelles, Z = vertical.)
##
## API bpy 5.2 vérifiée par sondage avant écriture (voir rapport de tâche) :
## - `bpy.types.Mesh.color_attributes` (domain CORNER, type BYTE_COLOR) +
##   `bpy.ops.paint.vertex_color_dirt` (sous `temp_override(object=obj)`, PAS
##   besoin de passer en mode Vertex Paint en arrière-plan) pour l'AO/
##   courbure peintes en sommet.
## - `export_scene.gltf(export_vertex_color='ACTIVE', export_all_vertex_colors=True)`
##   exporte TOUTES les color_attributes de la mesh (COLOR_0, COLOR_1, …) dès
##   que l'objet a au moins un matériau assigné — vérifié : sans matériau sur
##   l'objet, aucune couleur de sommet n'est exportée (branche "no_materials"
##   de l'exporteur), d'où le warning si `export_glb()` reçoit un objet sans
##   matériau.
## - Modifier SKIN (+ `mesh.skin_vertices[0].data[i].radius`) + SUBSURF pour
##   une capsule ronde sans bmesh maison (plus simple/robuste qu'un
##   cône+hémisphères cousus à la main).
## - Modifier WEIGHTED_NORMAL : la propriété `Mesh.use_auto_smooth`
##   n'existe plus (retirée en 4.1+) — on marque les arêtes dures nous-mêmes
##   via `bmesh` (angle entre faces adjacentes) plutôt que
##   `object.shade_auto_smooth()` (qui ajoute son propre modifieur "Smooth by
##   Angle" — un rouage de plus à gérer pour rien ici).
import bpy
import bmesh
import json
import math
import os
import random as _random
from mathutils import Vector

# ---------------------------------------------------------------------------
# Chemins / repère du dépôt
# ---------------------------------------------------------------------------

def repo_root() -> str:
	"""Racine du dépôt (contient project.godot), calculée depuis CE fichier
	(tools/blender/lib/toonkit.py -> lib -> blender -> tools -> racine)."""
	here = os.path.dirname(os.path.abspath(__file__))
	return os.path.dirname(os.path.dirname(os.path.dirname(here)))


# ---------------------------------------------------------------------------
# Scène
# ---------------------------------------------------------------------------

def reset_scene() -> None:
	"""Repart d'une scène vide (objets + data-blocks orphelins) — même recette
	que `_clear_scene()` dans make_weapons.py/make_props.py/make_gloves.py,
	élargie aux images/textures/node groups qu'un script toonkit peut créer
	(palette de secours, bruit du `blob()`, bake AO)."""
	for o in list(bpy.data.objects):
		bpy.data.objects.remove(o, do_unlink=True)
	purge_collections = (
		bpy.data.meshes, bpy.data.materials, bpy.data.curves,
		bpy.data.images, bpy.data.textures, bpy.data.node_groups,
		bpy.data.lights, bpy.data.cameras,
	)
	for coll in purge_collections:
		for block in list(coll):
			if block.users == 0:
				coll.remove(block)
	scene = bpy.context.scene
	scene.render.engine = 'BLENDER_EEVEE'
	scene.render.use_freestyle = False


# ---------------------------------------------------------------------------
# Palette (docs/style/tokens.json avec repli)
# ---------------------------------------------------------------------------

# Repli : docs/STYLE_BIBLE.md §6.4/§7.7 ("INK, ally_color(), enemy_color() :
# inchangés" — donc identiques à scripts/core/Cartoon.gd) pour les tokens
# "monde", et les couleurs plates KIND_COLORS de make_props.py pour les
# familles de matériaux peints (aperçu fidèle — le rendu texturé réel vient
# de Cartoon.painted() au runtime, ces valeurs ne servent qu'à un .glb/aperçu
# Blender lisibles). `shadow_tint`/`sand_dirt` alignés sur la carte Wasteland
# (§6.4, vaisseau-amiral) — v3 a changé ces deux hex par rapport à
# Cartoon.gd/make_props.py (sable #D9A15C -> #D2A46C, cf. §6.4 "Changements").
# À TENIR SYNCHRONE avec STYLE_BIBLE.md si sa palette bouge ; docs/
# 3D_PIPELINE.md documente ce repli et son statut (utilisé tant que
# docs/style/tokens.json n'existe pas).
_FALLBACK_PALETTE = {
	"ink": "#1a1410",
	"paper": "#e6e1d6",
	"paper_shade": "#c9c2b2",
	"graphite": "#6e6558",
	"shadow_tint": "#5b6ca6",
	"container_red": "#c8322b",
	"container_blue": "#2f63b8",
	"container_orange": "#e3872a",
	"container_white": "#e6e1d6",
	"painted_metal": "#5c6b78",
	"rust": "#6b3821",
	"corrugated_metal": "#8c8e91",
	"container_paint": "#8c4d33",
	"wood_planks": "#735230",
	"sand_dirt": "#d2a46c",
	"cracked_concrete": "#9e9a8f",
	"asphalt": "#262628",
	"ship_deck": "#4d5761",
	"rubber_tire": "#1a1a1c",
	"dirty_glass": "#8cb8c4",
	"accent": "#c73d24",
	"sign": "#dcd0a8",
}

_tokens_cache = None  # None = pas encore tenté, {} = tenté et absent, dict = chargé
_fallback_note_printed = False


def _hex_to_rgba(hex_str: str) -> tuple:
	h = hex_str.lstrip("#")
	if len(h) == 6:
		h += "ff"
	r, g, b, a = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4, 6))
	return (r, g, b, a)


def _coerce_color(value) -> tuple:
	if isinstance(value, str):
		return _hex_to_rgba(value)
	if isinstance(value, (list, tuple)):
		vals = list(value)
		if len(vals) == 3:
			vals.append(1.0)
		if max(vals) > 1.0:  # 0-255 plutôt que 0-1
			vals = [v / 255.0 for v in vals[:3]] + [vals[3] / 255.0 if vals[3] > 1.0 else vals[3]]
		return tuple(vals)
	raise ValueError(f"toonkit.palette: valeur de token illisible: {value!r}")


def _load_tokens() -> dict:
	global _tokens_cache
	if _tokens_cache is not None:
		return _tokens_cache
	path = os.path.join(repo_root(), "docs", "style", "tokens.json")
	if not os.path.isfile(path):
		_tokens_cache = {}
		return _tokens_cache
	try:
		with open(path, "r", encoding="utf-8") as f:
			data = json.load(f)
		# Formes acceptées : {"nom": "#hex"} à plat, ou {"colors": {...}}.
		_tokens_cache = data.get("colors", data) if isinstance(data, dict) else {}
	except (OSError, ValueError) as exc:
		print(f"TOONKIT_WARN docs/style/tokens.json illisible ({exc}) — repli sur la palette de secours")
		_tokens_cache = {}
	return _tokens_cache


def palette(name: str) -> tuple:
	"""Couleur RGBA (0..1) du token `name`. Lit docs/style/tokens.json s'il
	existe (clé exacte ou sous "colors"), sinon la palette de repli
	`_FALLBACK_PALETTE` (tokens Cartoon.gd/make_props.py, voir commentaire
	ci-dessus) — un avertissement one-shot signale l'usage du repli, pour ne
	jamais faire silencieusement dériver le rendu de la vraie palette du jeu."""
	global _fallback_note_printed
	tokens = _load_tokens()
	if name in tokens:
		return _coerce_color(tokens[name])
	if not _fallback_note_printed:
		print("TOONKIT_NOTE docs/style/tokens.json absent ou incomplet — "
			"palette de repli toonkit._FALLBACK_PALETTE utilisée (voir docs/3D_PIPELINE.md)")
		_fallback_note_printed = True
	if name in _FALLBACK_PALETTE:
		return _coerce_color(_FALLBACK_PALETTE[name])
	print(f"TOONKIT_WARN token de palette inconnu \"{name}\" — gris neutre renvoyé")
	return (0.6, 0.6, 0.6, 1.0)


# ---------------------------------------------------------------------------
# Matériaux — deux vocabulaires de "kind" reconnus, tous deux issus de
# docs/STYLE_BIBLE.md (référence unique, CLAUDE.md) :
# - §7.9 "Conventions Blender" (CIBLE v3, nommage `f"{id}_{slot}"`) : les 5
#   slots génériques "base"/"accent"/"metal"/"glass"/"sign" — c'est le
#   vocabulaire à préférer pour un NOUVEAU générateur.
# - §6.4/scripts/core/Cartoon.gd `_PAINTED` (ACTUEL, ce qui tourne
#   vraiment aujourd'hui) : les kinds peints texturés (painted_metal, rust,
#   corrugated_metal, container_paint, wood_planks, sand_dirt,
#   cracked_concrete, asphalt, ship_deck, rubber_tire, dirty_glass) — encore
#   nécessaires pour qu'un .glb reste compatible avec `Cartoon.painted()` tel
#   qu'il existe MAINTENANT (la migration vers les masks RGBA de §7.2/§7.9
#   n'est pas faite : ce module ne l'anticipe pas, il ne fait qu'exposer les
#   deux bakes vertex-color demandés par ce fichier, voir `bake_vertex_ao`/
#   `curvature_edge_mask`).
# - "skin"/"cloth"/"outfit"/"gear" : slots `Cartoon.character_surface`.
# - "flat" (défaut) : tout le reste (body/grip/glove/cuff/… des générateurs
#   armes/gants — recolorés par Cartoon.character()/prop() au runtime, pas
#   par un "kind" peint) ; alias de "base".
# ---------------------------------------------------------------------------

_KIND_PRESETS = {
	# -- v3 (§7.9) : 5 slots génériques --
	"base":             {"roughness": 0.7, "metallic": 0.0},
	"accent":           {"roughness": 0.4, "metallic": 0.1},
	"metal":            {"roughness": 0.4, "metallic": 0.3},
	"glass":            {"roughness": 0.1, "metallic": 0.0, "alpha": 0.75},
	"sign":             {"roughness": 0.75, "metallic": 0.0},
	# -- actuel (Cartoon._PAINTED) : familles de textures peintes --
	"painted_metal":    {"roughness": 0.45, "metallic": 0.2},
	"rust":             {"roughness": 0.75, "metallic": 0.1},
	"corrugated_metal": {"roughness": 0.6, "metallic": 0.2},
	"container_paint":  {"roughness": 0.5, "metallic": 0.1},
	"wood_planks":      {"roughness": 0.8, "metallic": 0.0},
	"sand_dirt":        {"roughness": 0.9, "metallic": 0.0},
	"cracked_concrete": {"roughness": 0.85, "metallic": 0.0},
	"asphalt":          {"roughness": 0.9, "metallic": 0.0},
	"ship_deck":        {"roughness": 0.55, "metallic": 0.15},
	"rubber_tire":      {"roughness": 0.9, "metallic": 0.0},
	"dirty_glass":      {"roughness": 0.1, "metallic": 0.0, "alpha": 0.75},
	# -- Cartoon.character_surface --
	"skin":             {"roughness": 0.6, "metallic": 0.0},
	"cloth":            {"roughness": 0.8, "metallic": 0.0},
	"outfit":           {"roughness": 0.8, "metallic": 0.0},
	"gear":             {"roughness": 0.35, "metallic": 0.05},
	# -- défaut --
	"flat":             {"roughness": 0.7, "metallic": 0.0},
}


def toon_material(name: str, color, kind: str = "flat") -> "bpy.types.Material":
	"""Matériau Principled BSDF nommé exactement `name` (= le nom de slot que
	scripts/core/Cartoon.gd doit reconnaître pour un prop peint — voir
	`_KIND_PRESETS` — ou un nom de slot libre pour armes/perso/gants).
	`color` : RGB(A) 0..1 (alpha optionnel, def. 1.0). `kind` choisit juste les
	réglages PBR d'APERÇU (roughness/metallic/alpha) ; le rendu peint réel
	vient de Cartoon.painted()/character() au runtime — ce module ne pose que
	des teintes plates lisibles telles quelles dans le .glb brut.

	Pose aussi `kind` en propriété personnalisée `mat["toonkit_kind"]` (ID-
	property, ignorée par le rendu, survit à l'export/réimport glTF en
	"extras" sans effet) : c'est la source de vérité que lit
	`bake_vertex_masks` (§7.9) pour calculer le canal A (zone de teinte) d'un
	polygone à partir de son matériau, sans dépendre du NOM du matériau (libre
	pour un slot d'arme/perso) — voir `ZONE_BY_KIND`."""
	if len(color) == 3:
		color = (color[0], color[1], color[2], 1.0)
	preset = _KIND_PRESETS.get(kind)
	if preset is None:
		print(f"TOONKIT_WARN kind de matériau inconnu \"{kind}\" — repli sur \"flat\"")
		preset = _KIND_PRESETS["flat"]
	alpha = preset.get("alpha", color[3])
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	mat.diffuse_color = (color[0], color[1], color[2], alpha)
	if alpha < 1.0:
		mat.blend_method = 'BLEND'
	bsdf = mat.node_tree.nodes.get("Principled BSDF") if mat.node_tree else None
	if bsdf is not None:
		bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
		bsdf.inputs["Roughness"].default_value = preset["roughness"]
		if "Metallic" in bsdf.inputs:
			bsdf.inputs["Metallic"].default_value = preset["metallic"]
		if "Alpha" in bsdf.inputs:
			bsdf.inputs["Alpha"].default_value = alpha
	mat["toonkit_kind"] = kind
	return mat


# ---------------------------------------------------------------------------
# Contexte d'opérateur — helper interne : la plupart des opérateurs bpy.ops
# utilisés ici (bevel/skin apply, transform_apply, origin_set, join, dirt)
# exigent un objet actif + sélectionné, y compris en arrière-plan.
# ---------------------------------------------------------------------------

def _select_only(objs) -> None:
	bpy.ops.object.select_all(action='DESELECT')
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]


def _apply_modifier(obj, modifier) -> None:
	with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
		bpy.ops.object.modifier_apply(modifier=modifier.name)


# ---------------------------------------------------------------------------
# Géométrie — bevel, normales pondérées, transforms, origine, fusion
# ---------------------------------------------------------------------------

def add_bevel(obj, width: float = 0.01, segments: int = 2, angle_limit_deg: float = 30.0):
	"""Bevel appliqué (pas laissé en modifieur) — silhouette chunky/BD nette,
	limite par ANGLE (pas par poids d'arête : aucun poids à poser à la main
	sur la géométrie procédurale). Réglages docs/STYLE_BIBLE.md §7.9/§6.6 :
	30° par défaut ; `segments=2` pour de l'architecture/des skins (≥ 3 m),
	l'appelant passe `segments=1` pour un petit prop. Ne touche PAS au
	lissage des faces (voir `weighted_normals` pour un rendu lissé + arêtes
	dures) — par défaut les faces restent plates (facettes nettes), cohérent
	avec le style existant."""
	if width <= 0.0:
		return obj
	mod = obj.modifiers.new("bevel", type='BEVEL')
	mod.width = width
	mod.segments = segments
	mod.limit_method = 'ANGLE'
	mod.angle_limit = math.radians(angle_limit_deg)
	_apply_modifier(obj, mod)
	obj.data.update()
	return obj


def weighted_normals(obj, weight: int = 50, sharp_angle_deg: float = 30.0):
	"""Lissage "hard-surface" (docs/STYLE_BIBLE.md §7.9 : "modificateur
	WEIGHTED_NORMAL (keep_sharp), puis application") : faces lissées + arêtes
	dures marquées par angle (recalcul bmesh — `Mesh.use_auto_smooth` n'existe
	plus depuis 4.1, et `object.shade_auto_smooth()` ajoute un modifieur
	"Smooth by Angle" séparé à gérer en plus ; marquer nous-mêmes
	`edge.use_edge_sharp` est plus direct) puis modifieur WEIGHTED_NORMAL
	(pondéré par aire de face, `keep_sharp=True` : les arêtes marquées dures
	restent facettées, le reste se lisse) appliqué immédiatement — les
	normales personnalisées qui en résultent sont bakées dans la mesh et
	suivent telles quelles à l'export glTF (attribut NORMAL). `sharp_angle_deg`
	par défaut = le même 30° que `add_bevel` (§7.9/§6.6) : un bord biseauté à
	30° reste facetté, le reste (arrondis de bevel, formes organiques) se
	lisse."""
	me = obj.data
	me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
	bm = bmesh.new()
	bm.from_mesh(me)
	bm.edges.ensure_lookup_table()
	threshold = math.radians(sharp_angle_deg)
	for e in bm.edges:
		if len(e.link_faces) != 2:
			e.smooth = False  # bord ouvert (non-manifold) : toujours une arête dure
			continue
		try:
			angle = e.calc_face_angle()
		except ValueError:
			angle = 0.0
		e.smooth = angle < threshold
	bm.to_mesh(me)  # écrit `edge.smooth` -> `Mesh.edges[i].use_edge_sharp` (inverse), vérifié par sondage
	bm.free()
	mod = obj.modifiers.new("weighted_normal", type='WEIGHTED_NORMAL')
	mod.weight = weight
	mod.keep_sharp = True
	_apply_modifier(obj, mod)
	me.update()
	return obj


# ---------------------------------------------------------------------------
# Classes d'assets (docs/STYLE_BIBLE.md §6.6 "Densité de texels, biseaux,
# budgets") — un identifiant de classe par ligne du tableau, factorisant le
# triplet biseau/budget de triangles/paliers de LOD qu'un générateur devrait
# sinon recopier à la main depuis la bible à chaque nouvel asset. §7.9
# ("Conventions Blender") renvoie explicitement à ce tableau pour le biseau
# ("Biseau | selon §6.6 ...") : `bevel_for_class` EST cette convention.
# ---------------------------------------------------------------------------

# largeur (m) / segments — add_bevel() prend les mêmes unités.
BEVEL_CLASSES = {
	"architecture":   {"width": 0.06,  "segments": 2},  # architecture, skins (>= 3 m)
	"landmark":       {"width": 0.07,  "segments": 2},  # repères : 6-8 cm, milieu retenu
	"prop_container":  {"width": 0.04,  "segments": 1},  # props moyens (1-3 m), conteneur
	"prop_crate":      {"width": 0.025, "segments": 1},  # props moyens (1-3 m), caisse
	"prop_small":      {"width": 0.012, "segments": 1},  # petits props (< 1 m)
	"character":       {"width": 0.01,  "segments": 1},  # personnage
	"weapon_fp":       {"width": 0.003, "segments": 1},  # arme première personne
	"weapon_tp":       {"width": 0.01,  "segments": 1},  # arme troisième personne
}

# budget de triangles LOD0 (m/M = min/max, quand la bible donne une plage ;
# `head_max`/`gloves_max` = sous-budgets internes documentés par la bible,
# à vérifier séparément par l'appelant — check_asset.py ne connaît que le
# total d'un fichier, pas la répartition tête/gants à l'intérieur).
TRI_BUDGETS = {
	"architecture":   {"max": 6000},
	"landmark":       {"max": 15000},
	"prop_container": {"min": 800, "max": 3000},
	"prop_crate":     {"min": 800, "max": 3000},
	"prop_small":     {"min": 200, "max": 800},
	"character":      {"max": 15000, "head_max": 3000},
	"weapon_fp":      {"min": 8000, "max": 12000, "gloves_max": 5000},
	"weapon_tp":      {"min": 1200, "max": 2000},
}

# paliers de LOD : liste de (ratio_triangles, distance_declenchement_m), dans
# l'ordre où `export_glb_with_lods` doit les exporter (_lod1, _lod2, ...).
# Liste vide = pas de LOD géométrique pour cette classe (armes : jamais
# évoquées au §6.6 ; petits props : "coupés à 40 m", une bascule de
# visibilité côté scène, pas un maillage décimé).
LOD_CLASSES = {
	"architecture":   [(0.50, 30.0), (0.20, 60.0)],
	"landmark":       [(0.50, 60.0)],
	"prop_container": [(0.50, 25.0)],
	"prop_crate":     [(0.50, 25.0)],
	"prop_small":     [],
	"character":      [(0.50, 25.0), (0.20, 50.0)],
	"weapon_fp":      [],
	"weapon_tp":      [],
}


def _class_table_lookup(table: dict, asset_class: str, table_name: str) -> dict:
	if asset_class not in table:
		raise ValueError(
			f"toonkit: classe d'asset inconnue {asset_class!r} pour {table_name} "
			f"(docs/STYLE_BIBLE.md §6.6) — attendu l'un de {sorted(table)}")
	return table[asset_class]


def tri_budget_for_class(asset_class: str) -> dict:
	"""Budget de triangles LOD0 (§6.6) de `asset_class` — copie défensive du
	dict de `TRI_BUDGETS` (l'appelant peut la modifier sans corrompre la
	table). Lève `ValueError` sur une classe inconnue : contrairement à un nom
	de matériau ou de token de palette (vocabulaire ouvert, un repli silencieux
	est acceptable), les classes d'assets sont un ensemble fermé, fixé par la
	bible — une classe mal orthographiée est une erreur de script à corriger,
	pas une variation créative légitime à tolérer."""
	return dict(_class_table_lookup(TRI_BUDGETS, asset_class, "TRI_BUDGETS"))


def lod_table_for_class(asset_class: str) -> list:
	"""Paliers de LOD (§6.6) de `asset_class`, `[(ratio, distance_m), ...]`
	dans l'ordre `_lod1`, `_lod2`, ... — liste vide si la classe n'a pas de LOD
	géométrique (voir `LOD_CLASSES`). Même politique d'erreur que
	`tri_budget_for_class`."""
	return list(_class_table_lookup(LOD_CLASSES, asset_class, "LOD_CLASSES"))


# Attribut FACE (booléen, stocké en INT — pas de type BOOLEAN natif dans les
# calques bmesh) temporaire posé par `_bevel_apply_tagged` : 1 sur une face
# créée par le biseau, 0 sur une face d'origine. Consommé et SUPPRIMÉ par
# `bake_vertex_masks` (canal G, §7.9) — ce n'est pas un attribut destiné à
# l'export, juste un relais entre deux étapes du pipeline ; le préfixe "_"
# évite toute collision avec un nom d'attribut applicatif (UVMap, etc.) sans
# pour autant le faire ressortir dans le .glb : `export_glb` n'exporte que les
# COULEURS de sommet et les attributs génériques _préfixés_ **présents au
# moment de l'export** (voir son docstring) — tant que ce calque est retiré
# avant cet appel (ce que fait `bake_vertex_masks`), il ne fuit jamais.
_BEVEL_FACE_ATTR = "_bevel_face"


def _bevel_apply_tagged(obj, width: float, segments: int, angle_limit_deg: float = 30.0):
	"""Biseau appliqué équivalent à `add_bevel` (même sélection d'arêtes ANGLE
	que `weighted_normals` : angle entre les deux faces adjacentes >=
	`angle_limit_deg`, cf. son calcul via `calc_face_angle()`) mais qui, à la
	différence d'un modificateur BEVEL + `modifier_apply` (aucune information
	sur la géométrie créée n'est renvoyée par cette voie), passe par
	`bmesh.ops.bevel` directement : l'opérateur bmesh renvoie explicitement
	les faces qu'il vient de créer (`result["faces"]`, vérifié par sondage —
	strips latéraux ET patchs de coin), qu'on tague ici à 1 dans l'attribut
	FACE temporaire `_BEVEL_FACE_ATTR` (le reste des faces, à 0) — c'est la
	donnée EXACTE (pas une heuristique) que `bake_vertex_masks` lit ensuite
	pour son canal G ("faces de biseau à 1, le reste à 0", §7.9).
	`offset_type='OFFSET'` reproduit le réglage implicite d'`add_bevel` (le
	modificateur BEVEL prend cette valeur par défaut, vérifié par sondage) :
	les deux fonctions biseautent avec la même largeur perçue pour un même
	`width`. Aucune arête au-dessus du seuil (mesh déjà tout en douceur) :
	no-op silencieux, comme `add_bevel(width=0)`."""
	if width <= 0.0:
		return obj
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	bm.edges.ensure_lookup_table()
	threshold = math.radians(angle_limit_deg)
	sharp_edges = []
	for e in bm.edges:
		if len(e.link_faces) != 2:
			continue
		try:
			angle = e.calc_face_angle()
		except ValueError:
			continue
		if angle >= threshold:
			sharp_edges.append(e)
	bevel_face_indices = set()
	if sharp_edges:
		result = bmesh.ops.bevel(bm, geom=sharp_edges, offset=width, offset_type='OFFSET',
			segments=segments, affect='EDGES', clamp_overlap=True, loop_slide=True)
		bm.faces.index_update()
		bevel_face_indices = {f.index for f in result.get("faces", [])}
	bm.faces.ensure_lookup_table()
	layer = bm.faces.layers.int.get(_BEVEL_FACE_ATTR)
	if layer is None:
		layer = bm.faces.layers.int.new(_BEVEL_FACE_ATTR)
	for f in bm.faces:
		f[layer] = 1 if f.index in bevel_face_indices else 0
	bm.to_mesh(me)
	bm.free()
	me.update()
	return obj


def bevel_for_class(obj, asset_class: str, angle_limit_deg: float = 30.0):
	"""Biseau §7.9/§6.6 : applique (`_bevel_apply_tagged`, voir sa docstring
	pour le tag de convexité qui en résulte) la largeur et le nombre de
	segments de `BEVEL_CLASSES[asset_class]`. C'est le point d'entrée v3 à
	préférer à `add_bevel` pour tout nouveau générateur qui appellera ensuite
	`bake_vertex_masks` (son canal G a besoin du tag posé ici — sans lui, il
	retombe sur une heuristique moins précise, voir `bake_vertex_masks`).
	Lève `ValueError` sur une classe inconnue (voir `tri_budget_for_class`)."""
	spec = _class_table_lookup(BEVEL_CLASSES, asset_class, "BEVEL_CLASSES")
	return _bevel_apply_tagged(obj, width=spec["width"], segments=spec["segments"],
		angle_limit_deg=angle_limit_deg)


def apply_transforms(obj):
	"""Applique position/rotation/échelle dans les données de la mesh (repère
	objet = repère monde ensuite) — nécessaire avant `export_glb` si le
	pipeline appelant a positionné l'objet par `obj.location`/`rotation_euler`
	plutôt qu'en écrivant directement les sommets (export_glb() passe déjà
	`export_apply=True`, qui applique les MODIFIEURS restants, mais pas la
	transform de l'objet lui-même — d'où cet appel séparé)."""
	with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
		bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	return obj


def set_origin_bottom(obj):
	"""Replace l'origine de l'objet au centre de sa base (bas de la boîte
	englobante) SANS déplacer sa géométrie — convention "origine au sol"
	partagée par tous les générateurs existants (props/perso : base au sol,
	armes/gants : point de contact). Travaille dans le repère Z-up natif de
	Blender (avant toute rotation d'export Y-up) : "bas" = Z minimal, "centre"
	= milieu XY — ce qui correspond bien au Y minimal/au sol une fois exporté
	en Y-up."""
	corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
	min_z = min(c.z for c in corners)
	cx = sum(c.x for c in corners) / 8.0
	cy = sum(c.y for c in corners) / 8.0
	cursor = bpy.context.scene.cursor
	saved = cursor.location.copy()
	cursor.location = Vector((cx, cy, min_z))
	with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
		bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
	cursor.location = saved
	return obj


def join(objs):
	"""Fusionne plusieurs objets mesh en un seul (celui qui reçoit devient
	`objs[0]`) ; renvoie l'objet fusionné tel quel si `len(objs) <= 1`."""
	objs = list(objs)
	if len(objs) == 0:
		raise ValueError("toonkit.join: liste d'objets vide")
	if len(objs) == 1:
		return objs[0]
	with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs,
			selected_objects=objs, object=objs[0]):
		bpy.ops.object.join()
	return objs[0]


# ---------------------------------------------------------------------------
# Vertex color : AO peinte + masque de courbure
# ---------------------------------------------------------------------------

def _dirt_bake(obj, attr_name: str, dirt_angle_deg: float, clean_angle_deg: float,
		blur_iterations: int, dirt_only: bool) -> "bpy.types.Attribute":
	me = obj.data
	existing = me.color_attributes.find(attr_name)
	attr = me.color_attributes[existing] if existing != -1 else me.color_attributes.new(
		name=attr_name, type='BYTE_COLOR', domain='CORNER')
	idx = me.color_attributes.find(attr_name)
	me.color_attributes.active_color_index = idx
	me.color_attributes.render_color_index = idx
	with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj]):
		bpy.ops.paint.vertex_color_dirt(
			blur_strength=1.0, blur_iterations=blur_iterations,
			clean_angle=math.radians(clean_angle_deg), dirt_angle=math.radians(dirt_angle_deg),
			dirt_only=dirt_only, normalize=True)
	return attr


def bake_vertex_ao(obj, attr_name: str = "AO", blur_iterations: int = 4):
	"""Occlusion ambiante peinte dans un attribut de couleur ("AO", domaine
	CORNER) via l'opérateur "Dirty Vertex Colors" (`paint.vertex_color_dirt`) :
	plage d'angle large (0-180°) + flou -> gradient d'occlusion doux (creux
	sombres, arêtes exposées claires), le classique "faux GI" peint à la main
	sans passer par un bake de lightmap. `export_glb()` l'inclut automatique-
	ment (glTF `COLOR_0`/`COLOR_1`, voir son docstring) — libre au shader
	Godot consommateur de la multiplier sur l'albédo."""
	return _dirt_bake(obj, attr_name, dirt_angle_deg=0.0, clean_angle_deg=180.0,
		blur_iterations=blur_iterations, dirt_only=False)


def curvature_edge_mask(obj, attr_name: str = "Curvature"):
	"""Masque de courbure (2e attribut de couleur) : même opérateur que
	`bake_vertex_ao` mais plage d'angle resserrée et SANS flou -> ne réagit
	qu'aux variations de normale locales et immédiates (arêtes/plis), pas au
	relief large -> approxime une carte de courbure/cavité (utile pour des
	surbrillances peintes sur les arêtes convexes, "highlight" façon
	BD/Borderlands) sans motif de bruit procédural ni bake externe. Reconnu
	comme une HEURISTIQUE (pas un vrai calcul de courbure différentielle) —
	suffisant pour un style peint stylisé, documenté dans docs/3D_PIPELINE.md."""
	return _dirt_bake(obj, attr_name, dirt_angle_deg=0.0, clean_angle_deg=25.0,
		blur_iterations=0, dirt_only=True)


# ---------------------------------------------------------------------------
# Masque vertex RGBA unifié v3 (docs/STYLE_BIBLE.md §7.9, ligne "Vertex color
# `masks` (COLOR_0, RGBA)") — remplace, pour un NOUVEAU générateur, le couple
# `bake_vertex_ao`/`curvature_edge_mask` ci-dessus (deux attributs séparés,
# convention A3D-02 encore utilisée par `fixtures/build_stylekit_test_prop.py`
# et son test gdUnit4 — CES DEUX FONCTIONS RESTENT donc telles quelles, elles
# ne sont ni appelées ni modifiées par ce qui suit) par UN SEUL attribut de
# couleur nommé "masks", codant 4 informations indépendantes dans ses 4
# canaux — c'est LUI que `export_glb` sort en `COLOR_0` glTF dès lors qu'il
# est l'attribut de couleur ACTIF (`active_color_index`, posé ci-dessous).
# ---------------------------------------------------------------------------

# A = zone de teinte par "kind" de matériau (§7.9 : "0 base, 0,33 accent, 0,66
# métal, 1 décalque" — les 4 slots v3 du §7.9 "Nommage des matériaux" :
# base/accent/metal/sign, "sign" portant les décalques/pochoirs). Les kinds
# hors de cette liste (vieux vocabulaire §6.4/Cartoon._PAINTED, ou slots
# perso skin/cloth/outfit/gear) sont rangés du côté le plus proche : neutre
# (base) ou fonte/laiton (metal/gear) — absents de la table §7.9, donc un
# choix de ce module, documenté ici plutôt que deviné silencieusement.
ZONE_BY_KIND = {
	"base": 0.0, "flat": 0.0, "skin": 0.0, "cloth": 0.0, "outfit": 0.0,
	"accent": 0.33, "glass": 0.33,
	"metal": 0.66, "gear": 0.66,
	"sign": 1.0,
}

MASKS_ATTR = "masks"


def _material_zone(mat) -> float:
	"""Zone (canal A) d'un matériau : lit d'abord `mat["toonkit_kind"]` (posé
	par `toon_material`, source de vérité — voir sa docstring), et à défaut
	(matériau posé à la main, hors de ce module) retombe sur le SUFFIXE de son
	nom, `f"{id}_{slot}"` étant la convention §7.9. `mat is None` (aucun
	matériau sur ce slot de polygone) : zone 0 (base), comme un défaut neutre."""
	if mat is None:
		return 0.0
	kind = mat.get("toonkit_kind")
	if kind is None:
		kind = mat.name.rsplit("_", 1)[-1]
	if kind in ZONE_BY_KIND:
		return ZONE_BY_KIND[kind]
	print(f"TOONKIT_WARN matériau \"{mat.name}\" : kind \"{kind}\" hors de la table de zone "
		"§7.9 (base/accent/metal/sign) — zone 0 (base) par défaut")
	return 0.0


def bake_vertex_masks(obj, attr_name: str = MASKS_ATTR, ao_distance: float = 0.5,
		ao_samples: int = 16, ao_min: float = 0.55):
	"""Bake le masque vertex RGBA unifié (§7.9) dans l'attribut de couleur
	`attr_name` (BYTE_COLOR, domaine CORNER, posé comme attribut de couleur
	ACTIF — c'est lui que l'export glTF place en `COLOR_0`) :

	- **R = AO cuit.** Un VRAI bake Cycles (`bpy.ops.object.bake(type='AO',
	  target='VERTEX_COLORS')`, cible vérifiée par sondage disponible en
	  arrière-plan sans UV requise) — pas l'heuristique "Dirty Vertex Colors"
	  de `bake_vertex_ao` ci-dessus. `ao_samples` (`scene.cycles.samples`) et
	  `ao_distance` (`scene.world.light_settings.distance`, le réglage que
	  Cycles réutilise pour la distance de son pass AO, vérifié par sondage)
	  reproduisent "Cycles, 16 échantillons, distance 0,5 m" du §7.9. Le
	  résultat brut (0 = occlus, 1 = dégagé) est remappé sur `[ao_min, 1]`
	  ("remappé 0,55-1" du §7.9) : `ao_min + brut * (1 - ao_min)`.
	- **G = convexité.** Binaire, "faces de biseau à 1, le reste à 0" (§7.9).
	  Lit l'attribut FACE temporaire `_BEVEL_FACE_ATTR` posé par
	  `_bevel_apply_tagged` (donc par `bevel_for_class`) s'il est présent —
	  tag EXACT, pas une approximation — puis le SUPPRIME (il n'a plus d'usage
	  après cette lecture, voir sa docstring). Absent (l'appelant a biseauté
	  avec `add_bevel`, pas `bevel_for_class`, ou l'objet n'a aucun biseau
	  tagué) : retombe sur `curvature_edge_mask` (heuristique de courbure déjà
	  éprouvée par A3D-02), binarisée à un seuil bas (> 0,02) — un `TOONKIT_NOTE`
	  signale ce repli, pour qu'il ne passe jamais inaperçu en production.
	- **B = hauteur normalisée** dans la boîte ENGLOBANTE LOCALE de l'objet
	  (coordonnées de sommet AVANT toute transform d'objet — cohérent avec la
	  convention Z-up native de ce module, voir l'en-tête de fichier) :
	  `(z - min_z) / (max_z - min_z)`, bas = 0, haut = 1.
	- **A = zone de teinte**, par polygone, via son matériau (`_material_zone`,
	  voir sa docstring et `ZONE_BY_KIND`) — tous les coins (loops) d'un même
	  polygone reçoivent la même valeur.

	Bascule `scene.render.engine`/`scene.cycles.samples`/
	`world.light_settings.distance`/la sélection sur CYCLES pour la durée du
	bake Cycles, puis restaure l'état précédent (un appelant qui enchaîne
	plusieurs props, ou un rendu EEVEE après coup, n'est pas affecté).
	Renvoie l'attribut de couleur créé/mis à jour."""
	me = obj.data
	if not me.materials or all(slot is None for slot in me.materials):
		print(f"TOONKIT_WARN \"{obj.name}\": aucun matériau assigné — le canal A (zone) "
			"de bake_vertex_masks vaudra 0 (base) partout")

	existing = me.color_attributes.find(attr_name)
	attr = me.color_attributes[existing] if existing != -1 else me.color_attributes.new(
		name=attr_name, type='BYTE_COLOR', domain='CORNER')
	idx = me.color_attributes.find(attr_name)
	me.color_attributes.active_color_index = idx
	me.color_attributes.render_color_index = idx

	# -- R : AO cuite Cycles --------------------------------------------
	scene = bpy.context.scene
	prev_engine = scene.render.engine
	prev_samples = getattr(scene.cycles, "samples", None)
	world = scene.world
	if world is None:
		world = bpy.data.worlds.new("World")
		scene.world = world
	prev_ao_distance = world.light_settings.distance
	prev_selected = list(bpy.context.selected_objects)
	prev_active = bpy.context.view_layer.objects.active
	scene.render.engine = 'CYCLES'
	import gpu_compute  # même dossier lib/ ; GPU + moitié des cœurs (poste utilisable)
	gpu_compute.use_gpu_for_cycles(scene)
	scene.cycles.samples = ao_samples
	world.light_settings.distance = ao_distance
	_select_only([obj])
	try:
		with bpy.context.temp_override(object=obj, active_object=obj,
				selected_objects=[obj], selected_editable_objects=[obj]):
			bpy.ops.object.bake(type='AO', target='VERTEX_COLORS', margin_type='EXTEND')
	finally:
		scene.render.engine = prev_engine
		if prev_samples is not None:
			scene.cycles.samples = prev_samples
		world.light_settings.distance = prev_ao_distance
		_select_only(prev_selected or [obj])
		if prev_active is not None:
			bpy.context.view_layer.objects.active = prev_active

	for i in range(len(attr.data)):
		raw = attr.data[i].color[0]
		attr.data[i].color = (ao_min + raw * (1.0 - ao_min), 0.0, 0.0, 1.0)

	# -- G : convexité (biseau tagué, ou repli heuristique) --------------
	bevel_attr = me.attributes.get(_BEVEL_FACE_ATTR)
	if bevel_attr is not None:
		for poly in me.polygons:
			g = 1.0 if bevel_attr.data[poly.index].value else 0.0
			for li in poly.loop_indices:
				c = attr.data[li].color
				attr.data[li].color = (c[0], g, c[2], c[3])
		me.attributes.remove(bevel_attr)
	else:
		print(f"TOONKIT_NOTE \"{obj.name}\": aucun tag de biseau ({_BEVEL_FACE_ATTR!r}) — "
			"bevel_for_class n'a pas été utilisé ; G retombe sur l'heuristique de courbure "
			"(curvature_edge_mask, binarisée)")
		tmp_name = "__masks_convex_tmp"
		tmp_attr = curvature_edge_mask(obj, attr_name=tmp_name)
		for i in range(len(attr.data)):
			raw = tmp_attr.data[i].color[0]
			g = 1.0 if raw > 0.02 else 0.0
			c = attr.data[i].color
			attr.data[i].color = (c[0], g, c[2], c[3])
		me.color_attributes.remove(me.color_attributes[me.color_attributes.find(tmp_name)])
		idx = me.color_attributes.find(attr_name)
		me.color_attributes.active_color_index = idx
		me.color_attributes.render_color_index = idx

	# -- B : hauteur normalisée (boîte locale) ---------------------------
	zs = [v.co.z for v in me.vertices]
	min_z, max_z = min(zs), max(zs)
	span = max(max_z - min_z, 1e-9)
	for poly in me.polygons:
		for li in poly.loop_indices:
			vidx = me.loops[li].vertex_index
			b = (me.vertices[vidx].co.z - min_z) / span
			c = attr.data[li].color
			attr.data[li].color = (c[0], c[1], b, c[3])

	# -- A : zone de teinte (matériau du polygone) -----------------------
	for poly in me.polygons:
		mat = me.materials[poly.material_index] if poly.material_index < len(me.materials) else None
		a = _material_zone(mat)
		for li in poly.loop_indices:
			c = attr.data[li].color
			attr.data[li].color = (c[0], c[1], c[2], a)

	me.update()
	return attr


def apply_stylekit_shading(obj, asset_class: str, angle_limit_deg: float = 30.0):
	"""Enchaîne, dans l'ordre exigé par §7.9, tout le pipeline de rendu v3
	pour `obj` : `bevel_for_class` (biseau + tag de convexité) ->
	`weighted_normals` (normales pondérées, arêtes dures conservées) ->
	`smooth_normal_attrs` (normale lissée pour la coque de contour, voir sa
	docstring) -> `bake_vertex_masks` (masque RGBA unifié, consomme le tag de
	convexité posé par `bevel_for_class`). Point d'entrée unique recommandé à
	un nouveau générateur plutôt que d'enchaîner les 4 appels à la main (et de
	risquer de les inverser — `bake_vertex_masks` perd son tag exact de
	convexité si `weighted_normals` ou `smooth_normal_attrs` sont appelés
	AVANT `bevel_for_class`, par exemple). `sharp_angle_deg` de
	`weighted_normals` reçoit le même `angle_limit_deg` que le biseau, comme
	le fait `rounded_box`/`weighted_normals` par défaut ailleurs dans ce
	module (§7.9 : même seuil 30° pour les deux réglages). Renvoie `obj`."""
	bevel_for_class(obj, asset_class, angle_limit_deg=angle_limit_deg)
	weighted_normals(obj, sharp_angle_deg=angle_limit_deg)
	smooth_normal_attrs(obj)
	bake_vertex_masks(obj)
	return obj


# ---------------------------------------------------------------------------
# Normale lissée pour la coque de contour (docs/research/06_ai_3d_pipeline.md
# §B3 : "l'écart principal chez nous") — voir `smooth_normal_attrs` ci-dessous.
# ---------------------------------------------------------------------------

# Nom de l'attribut générique (CORNER, FLOAT_VECTOR). Préfixe "_" volontaire :
# c'est la convention glTF pour un attribut applicatif personnalisé, ET la
# condition exacte que pose l'opérateur d'export pour le reprendre (propriété
# `export_attributes` de `bpy.ops.export_scene.gltf`, sondée avant écriture —
# description RNA : "Export Attributes (when starting with underscore)").
SMOOTH_NORMAL_ATTR = "_smooth_normal"


def smooth_normal_attrs(obj, attr_name: str = SMOOTH_NORMAL_ATTR):
	"""Stocke, dans un attribut de mesh générique (domaine CORNER, type
	FLOAT_VECTOR, nom préfixé par "_" — voir `SMOOTH_NORMAL_ATTR`), la normale
	MOYENNE des faces adjacentes à chaque SOMMET (par position, sans tenir
	compte des arêtes dures marquées par `weighted_normals`/`add_bevel`) —
	c'est la normale d'extrusion que doit utiliser la coque de contour
	inversée (`assets/shaders/ink_outline.gdshader`), PAS la normale facettée
	bakée dans l'attribut `NORMAL` standard par `weighted_normals`.

	Pourquoi un attribut séparé : `weighted_normals` marque des arêtes dures
	par angle, ce qui fait que l'exporteur glTF DOIT dupliquer les sommets le
	long de ces arêtes (1 normale par sommet exigée par le format) — une coque
	inversée qui extrude selon CETTE normale facettée se fend visuellement à
	chaque arête vive (les deux moitiés dupliquées s'écartent chacune selon sa
	propre normale). En calculant ici la moyenne par POSITION de sommet (via
	bmesh, sur la topologie AVANT toute duplication d'export) et en écrivant
	la MÊME valeur sur tous les coins (loops) qui partagent cette position, les
	deux côtés d'une arête dure reçoivent une normale d'extrusion identique —
	la coque reste continue même si `NORMAL` (facetté) diffère de part et
	d'autre. Documenté comme l'écart principal du pipeline maison face à une
	sortie IA/scan (docs/research/06_ai_3d_pipeline.md §B3), généralisé ici à
	TOUT prop construit par ce module (biseauté ou non).

	Appeler APRÈS toute opération qui change la géométrie finale (bevel,
	weighted_normals) : la moyenne est calculée sur le maillage TEL QU'IL EST
	au moment de l'appel, pas anticipée. `export_glb` exporte cet attribut dès
	lors que l'opérateur reçoit `export_attributes=True` (voir sa docstring) —
	rien à faire côté appelant au-delà de cet appel.

	Sommets sans face liée (cas dégénéré, jamais rencontré sur les primitives
	de ce module mais possible sur un import externe) : on retombe sur la
	normale de sommet déjà calculée par Blender plutôt que de planter."""
	me = obj.data
	bm = bmesh.new()
	bm.from_mesh(me)
	bm.verts.ensure_lookup_table()
	per_vertex = []
	for v in bm.verts:
		if v.link_faces:
			n = Vector((0.0, 0.0, 0.0))
			for f in v.link_faces:
				n += f.normal
			if n.length > 1e-9:
				n.normalize()
			else:
				n = Vector(v.normal)
		else:
			n = Vector(v.normal) if v.normal.length > 1e-9 else Vector((0.0, 0.0, 1.0))
		per_vertex.append(n)
	bm.free()

	existing = me.attributes.get(attr_name)
	if existing is not None:
		me.attributes.remove(existing)
	attr = me.attributes.new(name=attr_name, type='FLOAT_VECTOR', domain='CORNER')
	for loop in me.loops:
		attr.data[loop.index].vector = per_vertex[loop.vertex_index]
	me.update()
	return obj


# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------

def rounded_box(size=(1.0, 1.0, 1.0), bevel_width: float = 0.05, segments: int = 3,
		name: str = "RoundedBox"):
	"""Boîte aux arêtes arrondies (cube mis à l'échelle + bevel appliqué) —
	`size` = (X, Y, Z) en coordonnées Blender réelles (Z = vertical, voir
	en-tête de fichier)."""
	bm = bmesh.new()
	verts = list(bmesh.ops.create_cube(bm, size=1.0)["verts"])
	bmesh.ops.scale(bm, vec=Vector(size), verts=verts)
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	obj = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(obj)
	add_bevel(obj, width=bevel_width, segments=segments)
	return obj


def capsule(radius: float = 0.3, height: float = 1.0, name: str = "Capsule"):
	"""Capsule debout (axe Z, le "haut" natif de Blender — voir en-tête de
	fichier) via modifieur SKIN (rayon posé aux 2 sommets d'une arête unique)
	+ SUBSURF, tous deux appliqués — bien plus robuste qu'un cône+hémisphères
	cousus main en bmesh (voir rapport de tâche : technique vérifiée par
	sondage). `height` est la hauteur HORS calottes (comme un cylindre + 2
	demi-sphères de `radius`)."""
	bm = bmesh.new()
	half = max(height, 0.0) / 2.0
	v0 = bm.verts.new((0.0, 0.0, -half))
	v1 = bm.verts.new((0.0, 0.0, half))
	bm.edges.new((v0, v1))
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	obj = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(obj)

	skin = obj.modifiers.new("skin", type='SKIN')
	for item in obj.data.skin_vertices[0].data:
		item.radius = (radius, radius)
	sub = obj.modifiers.new("sub", type='SUBSURF')
	sub.levels = 2
	sub.render_levels = 2
	for mod in (skin, sub):
		_apply_modifier(obj, mod)
	obj.data.update()
	return obj


def tapered_cylinder(r1: float = 0.3, r2: float = 0.15, depth: float = 1.0,
		segments: int = 12, name: str = "TaperedCylinder"):
	"""Cylindre/tronc de cône debout, axe Z (`create_cone` construit déjà son
	cône sur cet axe par défaut — vérifié par sondage, aucune rotation à
	faire) — `r2 == r1` donne un cylindre droit. Faces plates (aucun bevel/
	lissage appliqué : à poser ensuite via `add_bevel`/`weighted_normals` si
	besoin)."""
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
		radius1=r1, radius2=r2, depth=depth)
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	obj = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(obj)
	return obj


def blob(radius: float = 0.5, subdiv: int = 2, noise_strength: float = 0.15,
		seed: int = 0, name: str = "Blob"):
	"""Forme organique/bosselée : icosphère + SUBSURF + DISPLACE (texture de
	bruit "CLOUDS"), tous deux appliqués. `seed` fait varier la forme de façon
	déterministe (décale la mesh dans le champ de bruit avant le displace,
	puis la replace — le bruit est infini/procédural, PAS une image, donc
	pas de seed natif côté texture Blender)."""
	bm = bmesh.new()
	bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
	rng = _random.Random(seed)
	offset = Vector((rng.uniform(-50.0, 50.0), rng.uniform(-50.0, 50.0), rng.uniform(-50.0, 50.0)))
	bmesh.ops.translate(bm, vec=offset, verts=list(bm.verts))
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	obj = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(obj)

	sub = obj.modifiers.new("sub", type='SUBSURF')
	sub.levels = subdiv
	sub.render_levels = subdiv
	_apply_modifier(obj, sub)
	# `strength == 0` rend le modifieur DISPLACE "désactivé" du point de vue
	# de Blender (son propre `isDisabled` interne, vérifié par sondage) —
	# `modifier_apply` refuse alors de l'appliquer ("Modifier is disabled").
	# Un appelant qui veut une sphère lisse SANS bosses (`noise_strength=0`,
	# ex. la tête de la silhouette d'échelle de turntable.py) doit donc
	# pouvoir le faire sans erreur : on saute simplement l'étape displace.
	if noise_strength > 1e-6:
		tex = bpy.data.textures.new(f"{name}_noise", type='CLOUDS')
		tex.noise_scale = radius * 1.5
		disp = obj.modifiers.new("disp", type='DISPLACE')
		disp.texture = tex
		disp.strength = noise_strength
		disp.mid_level = 0.5
		disp.direction = 'NORMAL'
		_apply_modifier(obj, disp)
	obj.data.update()
	# Reposition au centre d'origine (annule le décalage utilisé pour varier
	# le champ de bruit, voir plus haut) sans toucher au repère de l'objet.
	bm2 = bmesh.new()
	bm2.from_mesh(obj.data)
	bmesh.ops.translate(bm2, vec=-offset, verts=list(bm2.verts))
	bm2.to_mesh(obj.data)
	bm2.free()
	obj.data.update()
	return obj


# ---------------------------------------------------------------------------
# Export / mesure
# ---------------------------------------------------------------------------

def tri_count(objs) -> int:
	"""Nombre de triangles (ngons comptés en éventail, `max(0, n-2)`) —
	formule identique à make_props.py, pour des budgets comparables entre
	pipelines."""
	if hasattr(objs, "data"):
		objs = [objs]
	total = 0
	for obj in objs:
		total += sum(max(0, len(p.vertices) - 2) for p in obj.data.polygons)
	return total


def _asset_attribute_report(objs) -> dict:
	"""Attributs de mesh réellement présents sur `objs` au moment de l'export
	— utilisé par `export_glb` pour le rapport JSON (docs/research/
	06_ai_3d_pipeline.md §B3 : "un JSON (tris, bbox, slots, attributs
	présents) que les tests peuvent vérifier"). Lit l'état RÉEL de la mesh
	(pas un simple souvenir de quelles fonctions ont été appelées) : un objet
	construit sans passer par `smooth_normal_attrs`/`bake_vertex_ao`/
	`curvature_edge_mask`/`bake_vertex_masks` ressort correctement à `False`."""
	color_names = set()
	custom_names = set()
	for obj in objs:
		me = obj.data
		for a in me.color_attributes:
			color_names.add(a.name)
		for a in me.attributes:
			if a.name.startswith("_"):
				custom_names.add(a.name)
	return {
		"smooth_normal": SMOOTH_NORMAL_ATTR in custom_names,
		"ao": "AO" in color_names,
		"curvature": "Curvature" in color_names,
		"masks": MASKS_ATTR in color_names,
		"color_attributes": sorted(color_names),
		"custom_attributes": sorted(custom_names),
	}


def export_glb(path: str, objs, write_report: bool = True) -> str:
	"""Exporte `objs` (un objet ou une liste) en un seul .glb Godot-friendly :
	Y-up, modifieurs appliqués, matériaux inclus, TOUTES les color_attributes
	présentes (AO/Curvature bakées par ce module — voir leur docstring : sans
	matériau assigné sur l'objet, l'exporteur glTF n'exporte AUCUNE couleur de
	sommet, d'où l'avertissement ci-dessous), tous les attributs génériques
	préfixés par "_" (`export_attributes=True` — voir `smooth_normal_attrs` :
	c'est ce qui fait sortir `_smooth_normal` dans le .glb, en attribut
	personnalisé glTF ; côté Godot, un tel attribut ressort en CUSTOM sur la
	mesh importée), sans caméra ni lumière ni animation. Crée les dossiers
	manquants. Affiche `TOONKIT_EXPORT_OK` (au format `NOM tris=N -> chemin`,
	même convention `_OK` que les générateurs existants) et renvoie `path`.

	`write_report=True` (défaut) écrit en plus un rapport JSON à côté du .glb
	(même chemin, extension `.json`) : nombre de tris, noms d'objets, et les
	3 attributs stylekit (`smooth_normal`/`ao`/`curvature`, booléens — voir
	`_asset_attribute_report`) réellement présents sur la mesh exportée. Un
	appelant qui ne veut pas de ce fichier (ex. un export jetable) passe
	`write_report=False`."""
	if hasattr(objs, "data"):
		objs = [objs]
	objs = list(objs)
	if not objs:
		raise ValueError("toonkit.export_glb: aucune géométrie à exporter")
	for obj in objs:
		if not obj.data.materials:
			print(f"TOONKIT_WARN \"{obj.name}\" n'a aucun matériau assigné — "
				"ses éventuelles color_attributes (AO/Curvature) NE seront PAS exportées")
	os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
	_select_only(objs)
	bpy.ops.export_scene.gltf(
		filepath=path,
		export_format='GLB',
		use_selection=True,
		export_apply=True,
		export_yup=True,
		export_materials='EXPORT',
		export_vertex_color='ACTIVE',
		export_all_vertex_colors=True,
		export_attributes=True,
		export_cameras=False,
		export_lights=False,
		export_animations=False,
	)
	tris = tri_count(objs)
	print(f"TOONKIT_EXPORT_OK {os.path.basename(path)} tris={tris} -> {path}")
	if write_report:
		report = _asset_attribute_report(objs)
		report["file"] = os.path.basename(path)
		report["objects"] = [o.name for o in objs]
		report["tris"] = tris
		report_path = os.path.splitext(path)[0] + ".json"
		with open(report_path, "w", encoding="utf-8") as f:
			json.dump(report, f, indent=2, ensure_ascii=False)
		print(f"TOONKIT_REPORT_OK {report_path}")
	return path


# ---------------------------------------------------------------------------
# Export multi-LOD (docs/STYLE_BIBLE.md §7.9 "Export : ... LODs en _lod1 et
# _lod2", paliers ratio/distance du §6.6 — voir `LOD_CLASSES`).
# ---------------------------------------------------------------------------

def _duplicate_objects(objs) -> list:
	"""Copie superficielle de chaque objet de `objs` (`obj.copy()` +
	`obj.data.copy()` — SA PROPRE mesh-data : sans ce second `.copy()`, les
	deux objets partageraient la même mesh et décimer la copie décimerait
	aussi l'original) liée à la collection courante. Utilisé par
	`export_glb_with_lods` pour ne jamais toucher aux objets d'origine reçus
	en argument."""
	dups = []
	for obj in objs:
		dup = obj.copy()
		dup.data = obj.data.copy()
		bpy.context.scene.collection.objects.link(dup)
		dups.append(dup)
	return dups


def _remove_objects(objs) -> None:
	"""Retire `objs` de la scène et purge leur mesh-data devenue orpheline
	(chaque copie de `_duplicate_objects` a la sienne, `users == 0` après le
	retrait de l'objet) — nettoyage symétrique, pour qu'`export_glb_with_lods`
	ne laisse aucune géométrie fantôme dans `bpy.data` après son appel."""
	meshes = [obj.data for obj in objs]
	for obj in objs:
		bpy.data.objects.remove(obj, do_unlink=True)
	for me in meshes:
		if me.users == 0:
			bpy.data.meshes.remove(me)


def export_glb_with_lods(path: str, objs, asset_class: str, write_report: bool = True) -> dict:
	"""Exporte le LOD0 (`export_glb(path, objs, ...)`, comportement inchangé)
	PUIS un fichier `_lod1`/`_lod2` par palier de `lod_table_for_class(asset_class)`
	(§6.6/§7.9), dans l'ordre. Pour chaque palier `(ratio, distance_m)` : une
	COPIE de `objs` (jamais les objets d'origine, voir `_duplicate_objects`)
	reçoit un modificateur DECIMATE appliqué (`ratio=ratio` ; `decimate_type`
	reste sur son défaut `'COLLAPSE'`, vérifié par sondage — la décimation
	générique, sans pré-requis de topologie particulier contrairement à
	`'UNSUBDIV'`/`'DISSOLVE'`), puis `export_glb` l'exporte sous
	`{base}_lod{N}{ext}` ; la copie est supprimée aussitôt après
	(`_remove_objects`). Cette fonction ne laisse ni les objets d'origine ni
	de copie temporaire dans un état différent d'avant son appel — seuls des
	fichiers sont produits sur le disque.

	`asset_class` sans palier de LOD (`lod_table_for_class` renvoie `[]` —
	armes, petits props "coupés" plutôt que LODés, §6.6) : seul le LOD0 sort,
	`résultat["lods"]` est une liste vide, ce n'est pas une erreur.

	Renvoie `{"lod0": chemin_lod0, "lods": [{"path", "ratio", "distance_m",
	"tris"}, ...]}`."""
	if hasattr(objs, "data"):
		objs = [objs]
	objs = list(objs)
	lod0_path = export_glb(path, objs, write_report=write_report)
	result = {"lod0": lod0_path, "lods": []}
	base, ext = os.path.splitext(path)
	for i, (ratio, distance_m) in enumerate(lod_table_for_class(asset_class), start=1):
		dups = _duplicate_objects(objs)
		try:
			for dup in dups:
				mod = dup.modifiers.new(f"lod{i}_decimate", type='DECIMATE')
				mod.ratio = ratio
				_apply_modifier(dup, mod)
			lod_path = f"{base}_lod{i}{ext}"
			export_glb(lod_path, dups, write_report=write_report)
			result["lods"].append({
				"path": lod_path, "ratio": ratio, "distance_m": distance_m,
				"tris": tri_count(dups),
			})
		finally:
			_remove_objects(dups)
	return result
