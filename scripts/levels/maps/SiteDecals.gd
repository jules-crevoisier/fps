## SiteDecals.gd
## ART-27 : « lettre pochoir de 2 m jaune objectif #F2C230 cernée d'encre sur
## chaque site snd et hardpoint des cartes 4v4 » (docs/STYLE_BIBLE.md §6.7
## point 5, docs/style/tokens.json "world.site_decal" : letter_height_m=2.0,
## color=#F2C230, outline=#1A1410, min_px_at_15m=20). Appelé UNIQUEMENT par
## `MapSetup._build_markers` — voir MapSetup.gd, SiteA/SiteB/Hardpoint.
##
## `OBJECTIVE_YELLOW` (= `#F2C230`) n'apparaît nulle part ailleurs dans le
## DÉCOR (STYLE_BIBLE.md l.867, "c'est le seul usage du jaune objectif") :
## ne réutilise jamais cette teinte hors de ce fichier. Elle EXISTE ailleurs
## dans le dépôt, hors décor : `scripts/dev/TargetWasteland.gd::_GOLD` (outil
## dev, exclu des builds) et `scripts/ui/Comic.gd::OBJECTIVE`/`WARNING`
## (jeton HUD/UI). Le critère d'acceptation ne porte QUE sur le décor du
## monde (dressing) : ces deux usages ne le contredisent donc pas. Revue
## ART-27 : ne jamais reformuler ça, dans un rapport de tâche, en "cette
## teinte n'apparaît nulle part ailleurs dans les .gd du dépôt" — affirmation
## plus large que le critère réel, et factuellement fausse telle quelle.
##
## Deux façons de poser le même « décalque au sol », choisies par contrainte
## de ressources plutôt que par goût :
##
## - Sites A/B (`place_site_letter`) : réutilise le pochoir DÉJÀ encré/jauni
##   de `assets/textures/decals/decal_atlas.png` (clés "site_a"/"site_b",
##   posées par `tools/textures/gen_textures.py::build_site_letter` — même
##   pipeline que `DecalPool.gd`, hors de mon périmètre cette tâche mais déjà
##   au bon gabarit : 2 m de haut, jaune + encre déjà fusionnés dans la même
##   image).
## - Hardpoint (`place_hardpoint_letter`) : UN SEUL décalque par carte — le
##   mode Hardpoint n'a qu'UNE zone qui TÉLÉPORTE entre ses points de rotation
##   (`HardpointMode._set_zone` : `_zone.global_position = points[index]...`),
##   pas une zone par point ; STYLE_BIBLE §6.7 point 5 dit d'ailleurs "chaque
##   site... hardpoint" (singulier), jamais "chaque point hardpoint". Aucun
##   pochoir "H" n'existe dans l'atlas (`GLYPHS` de gen_textures.py ne connaît
##   que les lettres de FUEL/GAS/FRAGILE/GRAINES/A/B et les chiffres) et je ne
##   possède pas ce fichier pour lui en ajouter un. Les chiffres "num_0".."9"
##   EXISTENT bien dans l'atlas mais (a) tout-encre, sans remplissage jaune
##   (recolorer une texture déjà noire par une multiplication albedo_color ne
##   peut pas l'éclaircir vers du jaune), et (b) bakés à `word_cell=16` — une
##   fois étirés à 2 m de haut comme un site A/B (`site_cell=48`), 3x moins
##   denses, visiblement plus flous. `Label3D` est EXPRESSÉMENT déconseillé
##   dans ce projet pour du texte posé APRÈS coup dans une scène de jeu déjà
##   en place (`scripts/training/TrainingBuilder.gd` : "un Label3D neuf...
##   reste invisible à l'écran... accroc moteur propre à Label3D dans ce
##   contexte de rendu D3D12/Forward+" — reproduit indépendamment sur 4
##   fichiers de ce dépôt). Solution retenue : reproduire à l'identique
##   l'algorithme de `gen_textures.py` (glyphe matriciel 5x7, cell=48,
##   contour dilaté outline_px=6 -- LES MÊMES PARAMÈTRES que "site_a"/
##   "site_b", donc un rendu de même densité/même style) mais CÔTÉ GDScript,
##   dans une `Image`/`ImageTexture` construite une seule fois à l'exécution
##   (même patron que `Comic.hatch_texture`/`GameHUD` : `Image.create` +
##   `set_pixel` + `ImageTexture.create_from_image`, déjà utilisé ailleurs
##   dans ce projet) — un `MeshInstance3D`/`QuadMesh` ordinaire, sans
##   dépendance à un fichier hors de mon périmètre, sans le risque `Label3D`
##   ci-dessus.
class_name SiteDecals
extends RefCounted

const OBJECTIVE_YELLOW := Color("F2C230")
const INK := Color("1A1410")

## docs/style/tokens.json "world.site_decal.letter_height_m" — hauteur totale
## du bloc lettre + contour (même convention que le canevas "site_a"/"site_b"
## de l'atlas, qui inclut déjà son contour dans ses dimensions).
const LETTER_HEIGHT_M := 2.0

## Décale le décalque au-dessus du sol pour éviter le z-fighting avec la
## géométrie du niveau (même ordre de grandeur que `DecalPool._basis_for_
## normal`'s `pos + n * 0.01`, un peu plus généreux car ce décalque est
## permanent, pas un impact éphémère).
const _GROUND_EPSILON_M := 0.02

const _ATLAS_TEX_PATH := "res://assets/textures/decals/decal_atlas.png"
const _ATLAS_JSON_PATH := "res://assets/textures/decals/decal_atlas.json"

## Lettre de site -> clé de `decal_atlas.json` (tools/textures/gen_textures.py
## ::build_site_letter). Seules "A"/"B" existent : ce sont les deux seuls
## sites SND déclarés par `Layouts.gd`/les fichiers `layouts/*.gd`.
const _ATLAS_KEYS := {"A": "site_a", "B": "site_b"}

## nom -> Rect2 en pixels de l'atlas ; chargé une seule fois, comme
## `DecalPool._ensure_regions_loaded`.
static var _atlas_tex: Texture2D
static var _regions: Dictionary = {}

## Glyphe "H" (Hardpoint) généré une seule fois, réutilisé sur toutes les
## cartes/parties (identique partout, aucune raison de le regénérer).
static var _hardpoint_tex: ImageTexture

# ----------------------------------------------------------------------
#  Sites A/B — pochoir pré-encré de l'atlas (déjà jaune + encre)
# ----------------------------------------------------------------------
## Pose la lettre de site ("A" ou "B") à plat sur le sol, centrée en XZ sur
## `floor_pos` (espace local à `parent`, Y = niveau du sol). Sans effet (et un
## avertissement) si l'atlas est absent ou si `letter` n'est pas "A"/"B".
## `approach_dir` : direction horizontale (X/Z, longueur quelconque, Y ignoré)
## « entrée -> site » utilisée pour orienter la lettre (voir `_flat_basis`) ;
## `Vector3.ZERO` (ou une direction dégénérée) retombe sur l'ancienne base
## fixe. Fournie par l'appelant (`MapSetup._entrance_dir`) — ce fichier ne
## connaît ni les spawns ni la géométrie de la carte.
static func place_site_letter(parent: Node3D, letter: String, floor_pos: Vector3, approach_dir: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	if not _ATLAS_KEYS.has(letter):
		push_error("SiteDecals: lettre de site inconnue \"%s\" (A/B seulement)" % letter)
		return null
	_ensure_atlas_loaded()
	var key: String = _ATLAS_KEYS[letter]
	if _atlas_tex == null or not _regions.has(key):
		return null
	var rect: Rect2 = _regions[key]
	var atlas_tex := AtlasTexture.new()
	atlas_tex.atlas = _atlas_tex
	atlas_tex.region = rect
	var inst := _build_flat_decal("SiteDecal%s" % letter, atlas_tex, floor_pos, approach_dir)
	parent.add_child(inst)
	return inst

static func _ensure_atlas_loaded() -> void:
	if not _regions.is_empty():
		return
	if not ResourceLoader.exists(_ATLAS_TEX_PATH):
		push_warning("SiteDecals: atlas de décalques introuvable (%s)" % _ATLAS_TEX_PATH)
		return
	_atlas_tex = load(_ATLAS_TEX_PATH)
	var f := FileAccess.open(_ATLAS_JSON_PATH, FileAccess.READ)
	if f == null:
		push_warning("SiteDecals: decal_atlas.json introuvable (%s)" % _ATLAS_JSON_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SiteDecals: decal_atlas.json illisible")
		return
	var decals: Dictionary = (parsed as Dictionary).get("decals", {})
	for key in decals:
		var d: Dictionary = decals[key]
		_regions[String(key)] = Rect2(float(d["x"]), float(d["y"]), float(d["w"]), float(d["h"]))

# ----------------------------------------------------------------------
#  Hardpoint — glyphe "H" généré (voir en-tête de fichier, pourquoi)
# ----------------------------------------------------------------------
## Pose le décalque Hardpoint (lettre "H") à plat sur le sol, centrée en XZ
## sur `floor_pos` (espace local à `parent` — voir MapSetup.gd : `parent` est
## la zone `Area3D` elle-même pour suivre sa téléportation entre points de
## rotation, PAS `MapSetup`). `approach_dir` : voir `place_site_letter` — la
## zone téléportant entre plusieurs points, l'appelant y passe une direction
## représentative de l'ensemble des points (pas un seul), voir
## `MapSetup._entrance_dir`. `parent` a une rotation identité (posé par
## `_make_zone`, seule `position` est réglée) donc une direction calculée
## dans l'espace de `MapSetup` reste valable telle quelle dans celui de
## `parent`.
static func place_hardpoint_letter(parent: Node3D, floor_pos: Vector3, approach_dir: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	_ensure_hardpoint_texture()
	var inst := _build_flat_decal("HardpointDecal", _hardpoint_tex, floor_pos, approach_dir)
	parent.add_child(inst)
	return inst

static func _ensure_hardpoint_texture() -> void:
	if _hardpoint_tex != null:
		return
	_hardpoint_tex = ImageTexture.create_from_image(_build_h_glyph_image())

## Glyphe matriciel 5 colonnes x 7 lignes — même convention que `GLYPHS` de
## tools/textures/gen_textures.py (`'X'` = encre/jaune, `'.'` = vide), lettre
## "H" originale (pas dans ce dict Python, absente de l'atlas).
const _H_ROWS := ["X...X", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"]

## Mêmes paramètres que `build_site_letter("A"/"B", site_cell=48,
## site_outline_px=6)` côté Python : rend "H" à la MÊME densité/au MÊME style
## de contour que les sites A/B (canevas final 252x348, identique).
const _GLYPH_CELL_PX := 48
const _OUTLINE_PX := 6

static func _build_h_glyph_image() -> Image:
	var base := _glyph_mask(_H_ROWS, _GLYPH_CELL_PX)
	var padded := _pad_mask(base, _OUTLINE_PX)
	var outline := _dilate_mask(padded, _OUTLINE_PX)
	var h: int = outline.size()
	var w: int = (outline[0] as PackedByteArray).size()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in h:
		var outline_row: PackedByteArray = outline[y]
		var base_row: PackedByteArray = padded[y]
		for x in w:
			if outline_row[x] == 0:
				continue
			img.set_pixel(x, y, OBJECTIVE_YELLOW if base_row[x] == 1 else INK)
	return img

## Agrandit chaque case du motif 5x7 `rows` (bool via 'X'/'.') en un bloc
## `cell x cell` plein — même principe que `glyph_mask`/`np.kron` côté Python.
## Renvoie `Array[PackedByteArray]` (0/1), une entrée par ligne de pixels.
static func _glyph_mask(rows: Array, cell: int) -> Array:
	var out: Array = []
	for row_str in rows:
		var expanded := PackedByteArray()
		for ch in String(row_str):
			var bit := 1 if ch == "X" else 0
			for _i in cell:
				expanded.append(bit)
		for _i in cell:
			out.append(expanded.duplicate())
	return out

## Ajoute `pad` pixels transparents (0) de chaque côté — même rôle que le
## `np.zeros(...)`/`padded[outline_px:outline_px+h, ...] = base` de
## `build_site_letter`.
static func _pad_mask(mask: Array, pad: int) -> Array:
	var h: int = mask.size()
	var w: int = (mask[0] as PackedByteArray).size()
	var out_w := w + pad * 2
	var out: Array = []
	for _i in pad:
		var empty := PackedByteArray()
		empty.resize(out_w)
		out.append(empty)
	for y in h:
		var row := PackedByteArray()
		row.resize(out_w)
		var src: PackedByteArray = mask[y]
		for x in w:
			row[x + pad] = src[x]
		out.append(row)
	for _i in pad:
		var empty2 := PackedByteArray()
		empty2.resize(out_w)
		out.append(empty2)
	return out

## Dilatation binaire par un carré de côté `2*radius+1` (même résultat que
## `scipy.ndimage.binary_dilation(padded, structure=ones((2r+1,2r+1)))` côté
## Python), en deux passes séparables (horizontale puis verticale) pour
## rester en O(w*h*radius) plutôt que O(w*h*radius²) — un carré plein est
## séparable (max sur une ligne, puis max sur une colonne du résultat).
static func _dilate_mask(mask: Array, radius: int) -> Array:
	var h: int = mask.size()
	var w: int = (mask[0] as PackedByteArray).size()
	var horiz: Array = []
	for y in h:
		var src: PackedByteArray = mask[y]
		var row := PackedByteArray()
		row.resize(w)
		for x in w:
			var lo := maxi(0, x - radius)
			var hi := mini(w - 1, x + radius)
			var v := 0
			for k in range(lo, hi + 1):
				if src[k] == 1:
					v = 1
					break
			row[x] = v
		horiz.append(row)
	# Passe verticale construite ligne par ligne (comme la passe horizontale
	# ci-dessus et `_pad_mask`) : `PackedByteArray` est un type VALEUR, donc
	# muter `(out[y] as PackedByteArray)[x]` par un double-indiçage à travers
	# un cast n'écrit QUE dans une copie temporaire (jamais dans `out` — bug
	# constaté et corrigé, voir smoke test) ; on assigne ici une seule case
	# locale (`row2[x] = ...`) puis on `append()` la ligne complète.
	var out: Array = []
	for y in h:
		var lo2 := maxi(0, y - radius)
		var hi2 := mini(h - 1, y + radius)
		var row2 := PackedByteArray()
		row2.resize(w)
		for x in w:
			var v2 := 0
			for k in range(lo2, hi2 + 1):
				var r: PackedByteArray = horiz[k]
				if r[x] == 1:
					v2 = 1
					break
			row2[x] = v2
		out.append(row2)
	return out

# ----------------------------------------------------------------------
#  Commun — mesh plat, posé face au ciel
# ----------------------------------------------------------------------
## `MeshInstance3D`/`QuadMesh` non éclairé, alpha, dimensionné à
## `LETTER_HEIGHT_M` de haut (largeur déduite du ratio w/h de `texture`),
## posé À PLAT sur le sol (normale +Y) et TOURNÉ AUTOUR DE CET AXE selon
## `approach_dir` — voir `_flat_basis`. PAS ajouté à `parent` (fait par
## l'appelant, qui choisit le bon espace local — voir les deux fonctions
## `place_*` ci-dessus).
static func _build_flat_decal(name: String, texture: Texture2D, floor_pos: Vector3, approach_dir: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = name
	var tex_size := texture.get_size()
	var height := LETTER_HEIGHT_M
	var width := height * (float(tex_size.x) / float(tex_size.y))
	var qm := QuadMesh.new()
	qm.size = Vector2(width, height)
	mesh_inst.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.albedo_texture = texture
	mesh_inst.material_override = mat
	mesh_inst.basis = _flat_basis(Vector3.UP, approach_dir)
	mesh_inst.position = floor_pos + Vector3.UP * _GROUND_EPSILON_M
	return mesh_inst

## Base orthonormée dont l'axe Z est `normal` (le décalque reste À PLAT,
## posé sur le sol — `QuadMesh` fait face à +Z local, voir `_build_flat_
## decal`) et dont l'axe Y (la hauteur IMPRIMÉE de la lettre, 2 m, celle que
## le critère ART-27 mesure en pixels à l'écran) est aligné sur
## `tall_axis_hint` plutôt que fixé au repère du monde.
##
## Pourquoi (revue ART-27, run réel) : ce décalque est plat au sol, donc sa
## hauteur APPARENTE à l'écran, vue depuis l'entrée d'un site à distance/
## angle rasants (15 m, oeil à 1,7 m), dépend presque entièrement de la
## PROJECTION EN PROFONDEUR (radiale, vers/depuis la caméra) de son axe
## imprimé de 2 m -- PAS de sa taille réelle : un axe imprimé tangentiel
## (perpendiculaire à la ligne de vue) se lit comme un déplacement
## HORIZONTAL à l'écran (quasi aucune hauteur), alors qu'un axe imprimé
## RADIAL (aligné sur la ligne de vue) se lit comme la hauteur VERTICALE
## voulue -- exactement le renfoncement de "STOP" peint au sol, allongé
## dans le sens de la circulation pour rester lisible d'un pare-brise bas et
## oblique. L'ancien code appelait `_flat_basis(Vector3.UP)` seul :
## `up.cross(n)` avec `n = UP` dégénère TOUJOURS sur le même repli
## (`Vector3.RIGHT`, faute de pouvoir choisir "up" perpendiculaire à un `n`
## déjà vertical), donc un axe imprimé FIXE au monde (mesuré : Y du monde),
## qui ne s'aligne avec la ligne de vue réelle d'ENTRÉE d'un site précis que
## par COÏNCIDENCE si l'orientation de cette carte s'y prête -- mesuré
## géométriquement (même technique que tools/look_probe.gd,
## Camera3D.unproject_position) : 12,7 à 20,3 px selon le seul azimut
## d'approche, sous la cible tokens.json world.site_decal.min_px_at_15m=20
## pour la plupart des azimuts. `tall_axis_hint` (fourni par l'appelant,
## voir `MapSetup._entrance_dir` -- CE fichier ne connaît ni les spawns ni
## la géométrie de carte) est la direction horizontale RÉELLE entrée->site :
## aligner l'axe imprimé dessus place la lecture au sommet de cette
## fourchette (~20 px, la valeur mesurée pour un alignement quasi exact)
## plutôt que d'espérer une coïncidence de repère monde.
static func _flat_basis(normal: Vector3, tall_axis_hint: Vector3 = Vector3.ZERO) -> Basis:
	var n := normal.normalized()
	# Projette l'indice sur le plan perpendiculaire à `n` (Gram-Schmidt) --
	# au cas où l'appelant fournirait un vecteur pas parfaitement horizontal.
	var y := tall_axis_hint - n * tall_axis_hint.dot(n)
	if y.length_squared() < 0.0001:
		# Repli : aucune direction d'approche exploitable (site confondu
		# avec son unique spawn le plus proche, ou aucun `approach_dir`
		# fourni) -- ancienne formule, indépendante de toute direction
		# d'approche, seulement dépendante de la normale.
		var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.999 else Vector3.RIGHT
		var x_fallback := up.cross(n)
		if x_fallback.length_squared() < 0.0001:
			x_fallback = Vector3.RIGHT.cross(n)
		y = n.cross(x_fallback)
	y = y.normalized()
	var x := y.cross(n).normalized()
	return Basis(x, y, n)
