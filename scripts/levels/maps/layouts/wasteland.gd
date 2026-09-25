## wasteland.gd
## Wasteland v4 (LD-40) — docs/research/11_wasteland_v4_layout.md §9 (spec
## verrouillée par le lead, §12 décisions utilisateur 2026-09-25 : « on veut
## un FPS rapide ... du fight tout le temps ... retour au combat pas trop
## long » -> « c'est good pour moi pour la map »). Remplace le damier v3
## (mauvaise lisibilité, 51 % de toits jouables, docs/research/
## 11_wasteland_v4_layout.md §2) par 3 lanes lisibles entre deux cours de
## spawn — Grand-Rue (longue portée, Crossfire/Crash), Intérieurs (courte
## portée, Terminal/Highrise), Canyon (flanc serré, Raid) — qui convergent
## sur un centre disputé (la place de la Gare + le Wagon, l'avion de
## Terminal). La v3 est GARDÉE, gelée, sous `wasteland_v3.gd` (§12.6, banc de
## comparaison bots, `MapSetup._data_for("wasteland_v3")`), jamais dans
## `MapCatalog.gd` (hors de mon périmètre) : absente de la liste jouable.
##
## Symétrie MIROIR STRICTE du gameplay x -> -x (§12.2) : la moitié ouest
## (`_west()`, transcrite depuis la SOURCE UNIQUE des coordonnées,
## docs/research/img/wasteland_v4_plan.py) est reflétée par `_mirror_piece`
## (portes/fenêtres E<->W, offsets N/S inversés, `stair_side`, PP1->PP2,
## PP3->PP4) pour produire la moitié est — jamais retranscrite à la main,
## pour ne jamais laisser deux moitiés diverger. Le CENTRE (`_center()`)
## n'est jamais mirroré : il est déjà symétrique par construction (Wagon,
## Descente, Poste, Diligence, château d'eau centrés sur x=0). Décor
## asymétrique (§12.2) : grue+FUEL bleu à l'ouest, derrick+GAS rouge à l'est
## — mêmes constantes Cartoon.CONTAINER_BLUE/RED que Cargo Ship.
##
## Toits JAMAIS praticables (§12.3, RÉVISÉ le 2026-09-25 — remplace la
## version LD-40 encore visible dans l'historique) : chaque `building2`
## passe `roof_pitch_deg: Kit.ROOF_PITCH_DEG` (Kit.gd, LD-44) — deux pans BAS
## (25-30°, faîte plafonnée à la corniche + 3 m, `Kit.ROOF_MAX_RISE`) au lieu
## des 60° d'origine, qui faisaient monter le faîtage des Saloons à 20,3 m et
## cachaient le château d'eau et la silhouette de la ville derrière les
## Échoppes/Saloons (docs/art/WASTELAND_V4_ART_PLAN.md §1 « B0 »). À 25-30°,
## la pente seule ne suffit plus à exclure le toit du bake Recast
## (`MapSetup.AGENT_MAX_SLOPE`, 46° — 25-30° est EN-DESSOUS) : `building2()`
## pose donc AUSSI, automatiquement, un volume invisible « player_clip »
## au-dessus de chaque pan (`Kit.roof_clip_volumes`, voir son commentaire et
## docs/COLLISION_LAYERS.md) — heurté par les joueurs/bots, traversé par les
## tirs/grenades/capacités de lancer, jamais un minuteur « Retour au
## combat ». Seuls les ÉTAGES (galeries du Saloon, étage de l'Hôtel/la
## Banque) restent praticables : ce sont des dalles internes de `building2`,
## jamais le toit.
##
## "modes" (nouveau champ additif, §7 "Barrières Duel/Duo") : une pièce
## déclarant `"modes": [...]` (sous-ensemble de `MatchConfig.MODES`) n'est
## posée QUE si `MatchConfig.mode_id` y figure — filtré en fin de `data()`
## par `_filter_pieces_for_mode`, jamais construit ni mesuré autrement.
## Absente (toutes les autres pièces) = posée dans tous les modes, comme
## avant.
class_name WastelandLayout
extends RefCounted

# ======================================================================
#  Constructeurs de pièces — même vocabulaire que le modèle Python (source
#  unique des coordonnées) : x0/x1 (bornes en x), z0/z1, y0/y1 (bornes
#  verticales), traduits ici en pos/size Kit (centre + étendue). Garder ces
#  helpers alignés sur wasteland_v4_plan.py mot pour mot évite toute erreur
#  d'arithmétique de conversion, vérifiable pièce par pièce contre le §9 du
#  doc de recherche.
# ======================================================================
static func _mat_for(role: String) -> String:
	match role:
		"floor":
			return "floor"
		"rock":
			return "rock"
		"solid", "wall":
			return "wall"
		"slab":
			return "platform"
		"leg", "accent":
			return "accent"
		_:
			return "cover"  # rôle par défaut du modèle Python (couverts, low compris)

static func _box(n: String, x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, role: String = "cover") -> Dictionary:
	return {
		"type": "box", "name": n,
		"pos": Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5),
		"size": Vector3(x1 - x0, y1 - y0, z1 - z0),
		"color_key": _mat_for(role),
	}

static func _floor_piece(n: String, x0: float, x1: float, z0: float, z1: float, top: float) -> Dictionary:
	# Épaisseur 2 m, dessus affleurant à `top` — même convention que l'ancien
	# `Ground` (wasteland_v3.gd) : un sol séparé par plateau/canyon (jamais un
	# seul sol plat) est ce qui rend le canyon lisible en creux pour Recast.
	return {
		"type": "box", "name": n,
		"pos": Vector3((x0 + x1) * 0.5, top - 1.0, (z0 + z1) * 0.5),
		"size": Vector3(x1 - x0, 2.0, z1 - z0),
		"color_key": "floor",
	}

static func _door(side: String, off: float = 0.0, w: float = 1.6, floor_idx: int = 0) -> Dictionary:
	return {"side": side, "offset": off, "w": w, "floor": floor_idx}

## `pp` (facultatif) : nom de position forte (PP1..PP5, §6 du doc) — copié
## tel quel dans la pièce, purement documentaire pour `wasteland.gd`
## lui-même (les tests localisent leurs propres coordonnées de sommet, comme
## l'ancien PF1..PF5 de test_wasteland.gd) ; utile surtout pour que
## `_mirror_piece` sache renommer PP1->PP2/PP3->PP4 sans table externe.
static func _bld(n: String, x0: float, x1: float, z0: float, z1: float, h: float, floors: int, doors: Array, windows: Array, stair_side: String = "N", pp: String = "") -> Dictionary:
	var d: Dictionary = {
		"type": "building2", "name": n,
		"pos": Vector3((x0 + x1) * 0.5, h * 0.5, (z0 + z1) * 0.5),
		"size": Vector3(x1 - x0, h, z1 - z0),
		"floors": floors, "doors": doors, "windows": windows,
		"roof_access": false, "parapet": 0.0, "stair_side": stair_side,
		"color_key": "wall",
		"roof_pitch_deg": Kit.ROOF_PITCH_DEG,
	}
	if pp != "":
		d["pp"] = pp
	return d

static func _ramp_piece(n: String, start: Vector3, end: Vector3, w: float) -> Dictionary:
	return {"type": "ramp", "name": n, "start": start, "end": end, "width": w, "color_key": "platform"}

static func _stairs_piece(n: String, start: Vector3, end: Vector3, w: float) -> Dictionary:
	return {"type": "stairs", "name": n, "start": start, "end": end, "width": w, "color_key": "platform"}

static func _fence_piece(n: String, ax: float, az: float, bx: float, bz: float, h: float, base: float = 0.0) -> Dictionary:
	return {"type": "fence", "name": n, "start": Vector3(ax, base, az), "end": Vector3(bx, base, bz), "height": h, "color_key": "wall"}

# ======================================================================
#  Miroir x -> -x (§12.2) : EAST = WEST.map(_mirror_piece). CENTER n'y passe
#  jamais (déjà symétrique). Même règle que wasteland_v4_plan.py::_mirror.
# ======================================================================
const _NAME_MIRROR := {"Hotel": "Banque", "CiterneFUEL": "CiterneGAS"}
const _PP_MIRROR := {"PP1": "PP2", "PP3": "PP4"}

static func _mirror_name(n: String) -> String:
	if _NAME_MIRROR.has(n):
		return _NAME_MIRROR[n]
	if n.ends_with("W"):
		return n.substr(0, n.length() - 1) + "E"
	# "W" suivi d'un chiffre final (ex. "AbreuvoirW1" -> "AbreuvoirE1").
	var re := RegEx.new()
	re.compile("W(\\d)$")
	var m := re.search(n)
	if m:
		return n.substr(0, m.get_start()) + "E" + m.get_string(1)
	return n

static func _mirror_side(s: String) -> String:
	match s:
		"W":
			return "E"
		"E":
			return "W"
		_:
			return s

static func _mirror_piece(p: Dictionary) -> Dictionary:
	var q: Dictionary = p.duplicate(true)
	q["name"] = _mirror_name(String(p["name"]))
	if p.has("pos"):
		var pos: Vector3 = p["pos"]
		q["pos"] = Vector3(-pos.x, pos.y, pos.z)
	if p.has("start"):
		var st: Vector3 = p["start"]
		q["start"] = Vector3(-st.x, st.y, st.z)
	if p.has("end"):
		var en: Vector3 = p["end"]
		q["end"] = Vector3(-en.x, en.y, en.z)
	if String(p.get("type", "")) == "building2":
		var doors: Array = []
		for entry in (p.get("doors", []) as Array):
			var d: Dictionary = entry
			var side := _mirror_side(String(d.get("side", "N")))
			var off: float = float(d.get("offset", 0.0))
			if side == "N" or side == "S":  # inchangé par le swap E<->W -> l'offset (le long de x) s'inverse
				off = -off
			doors.append({"side": side, "offset": off, "w": d.get("w", 1.6), "floor": d.get("floor", 0)})
		q["doors"] = doors
		var windows: Array = []
		for w in (p.get("windows", []) as Array):
			windows.append(_mirror_side(String(w)))
		q["windows"] = windows
		q["stair_side"] = _mirror_side(String(p.get("stair_side", "N")))
		if p.has("pp"):
			q["pp"] = _PP_MIRROR.get(String(p["pp"]), String(p["pp"]))
	return q

# ======================================================================
#  "modes" (§7 "Barrières Duel/Duo") : filtré en dernier, jamais mesuré
#  autrement qu'à travers cette fonction.
# ======================================================================
static func _filter_pieces_for_mode(pieces: Array) -> Array:
	var out: Array = []
	for entry in pieces:
		var p: Dictionary = entry
		var modes: Array = p.get("modes", [])
		if modes.is_empty() or MatchConfig.mode_id in modes:
			out.append(p)
	return out

# ======================================================================
#  Falaises (bornes de la carte, décor + collision — le mur invisible réel
#  est posé par `MapSetup._build_perimeter` depuis `data()["perimeter"]`,
#  ci-dessous) : purement décoratives/bloquantes, hors du plateau/canyon
#  praticables.
# ======================================================================
static func _cliffs() -> Array:
	return [
		_box("CliffN", -44.0, 44.0, -26.0, -25.0, 0.0, 6.0, "rock"),
		_box("CliffS", -44.0, 44.0, 20.0, 21.0, -2.0, 4.0, "rock"),
		_box("CliffW", -45.0, -44.0, -25.0, 20.0, -2.0, 6.0, "rock"),
		_box("CliffE", 44.0, 45.0, -25.0, 20.0, -2.0, 6.0, "rock"),
	]

# ======================================================================
#  Centre (§9 "Terrain et centre") — jamais mirroré, déjà symétrique.
# ======================================================================
static func _center() -> Array:
	var out: Array = [
		_floor_piece("G_PlateauC", -2.0, 2.0, -25.0, 8.0, 0.0),
		_floor_piece("G_Canyon", -44.0, 44.0, 12.0, 20.0, -2.0),
		_box("Poste", -4.0, 4.0, -25.0, -16.0, 0.0, 6.4, "solid"),
		_box("Diligence", -3.0, 3.0, -16.0, -11.0, 0.0, 3.4, "solid"),
		_bld("Wagon", -6.0, 6.0, -2.5, 0.5, 3.4, 1,
			[_door("W"), _door("E"), _door("S", -3.0), _door("S", 3.0)], ["N"], "N", "PP5"),
		_ramp_piece("Descente", Vector3(0, 0, 8), Vector3(0, -2, 13), 4.0),
		_box("Pompe", -1.5, 1.5, 5.0, 7.5, 0.0, 2.4, "solid"),
		_box("MuretGouletO", -2.5, -2.0, 7.5, 12.0, 0.0, 2.0, "wall"),
		_box("MuretGouletE", 2.0, 2.5, 7.5, 12.0, 0.0, 2.0, "wall"),
		_box("PiedChateauNO", -2.0, -1.6, 3.8, 4.2, 0.0, 8.0, "leg"),
		_box("PiedChateauNE", 1.6, 2.0, 3.8, 4.2, 0.0, 8.0, "leg"),
		_box("PiedChateauSO", -2.0, -1.6, 6.8, 7.2, 0.0, 8.0, "leg"),
		_box("PiedChateauSE", 1.6, 2.0, 6.8, 7.2, 0.0, 8.0, "leg"),
		# Cuve du château d'eau (§8 "repère visible de partout") — "sans
		# échelle" (§9) : aucune rampe n'y mène, Recast ne la relie donc
		# jamais au sol praticable (même garantie que le pitched roof, par
		# construction plutôt que par pente).
		_box("ChateauCuve", -1.8, 1.8, 3.7, 7.3, 8.0, 12.0, "accent"),
	]
	return out

# ======================================================================
#  Moitié ouest (§9 "Moitié ouest (l'est en miroir)") — transcrite depuis
#  wasteland_v4_plan.py (source unique des coordonnées).
# ======================================================================
static func _west() -> Array:
	return [
		_floor_piece("G_PlateauW", -44.0, -2.0, -25.0, 12.0, 0.0),
		_bld("ForgeW", -36.0, -29.0, -25.0, -15.0, 3.6, 1,
			[_door("S", 0.0, 2.0), _door("W", 3.0)], ["W"]),
		_bld("Hotel", -26.0, -16.0, -25.0, -19.0, 6.4, 2,
			[_door("S", -2.5), _door("S", 2.5), _door("W", -2.25, 1.6, 1), _door("E", -2.25, 1.6, 1)], ["S"], "N", "PP1"),
		_stairs_piece("StairImpasseW", Vector3(-27.25, 0, -18.5), Vector3(-27.25, 3.2, -23.5), 1.5),
		_box("PalierImpasseW", -28.0, -26.0, -25.0, -23.5, 3.0, 3.2, "slab"),
		_stairs_piece("StairPassageW", Vector3(-15.25, 0, -18.5), Vector3(-15.25, 3.2, -23.5), 1.5),
		_box("PalierPassageW", -16.0, -14.0, -25.0, -23.5, 3.0, 3.2, "slab"),
		_bld("MagasinW", -13.0, -4.0, -25.0, -19.0, 3.6, 1,
			[_door("S", -3.0), _door("S", 3.0), _door("W", 1.0)], []),
		_box("CiterneFUEL", -43.0, -39.0, -15.0, -11.0, 0.0, 2.8, "solid"),
		_box("CaisseFUEL", -37.0, -35.0, -4.0, 0.0, 0.0, 2.2),
		_box("CharretteW", -26.0, -23.0, -13.0, -9.5, 0.0, 2.2),
		_box("AbreuvoirW1", -31.0, -29.0, -11.5, -10.5, 0.0, 1.1, "low"),
		_box("AbreuvoirW2", -12.0, -10.0, -17.5, -16.5, 0.0, 1.1, "low"),
		_box("CaissesW", -20.0, -18.5, -16.0, -14.5, 0.0, 1.1, "low"),
		# LD-43 (retour vérificateur, stuck_time_ratio 3,4-3,6 % pour un plafond
		# de 2 %) : portes d'EchoppesW/SaloonW élargies de 1,6 à 2,4 m — le
		# HAUT de la fourchette VERROUILLÉE §4 "largeur des lanes... intérieurs :
		# portes 1,6 à 2,4 m" (docs/research/11_wasteland_v4_layout.md), jamais
		# un dépassement du spec. Ces deux bâtiments sont ceux de la lane
		# Intérieurs (WastelandBots._lane_interieurs, hors de mon périmètre :
		# "Echoppes ouest, porte O"/"SaloonW, entrée O"), la plus chargée par
		# construction (2 bots sur 4 par équipe y sont affectés,
		# TDMMode._LANE_BY_MOD4, hors de mon périmètre) : élargir SES portes
		# (jamais celles de Hotel/MagasinW, sur la lane Grand-Rue, déjà moins
		# chargée) réduit la congestion bot-contre-bot aux embrasures sans
		# toucher au tracé, à la taille des bâtiments ni aux pièces à
		# coordonnées verrouillées (Pompe/MuretGoulet, §9). Miroir automatique
		# (`_mirror_piece`) : EchoppesE/SaloonE reçoivent la même largeur.
		_bld("EchoppesW", -34.0, -20.0, -9.0, 5.0, 3.6, 1,
			[_door("W", -3.0, 2.4), _door("W", 3.0, 2.4), _door("N", -4.0, 2.4), _door("E", 0.0, 2.4), _door("S", 4.0, 2.4)], []),
		_box("EchoppesMurW1", -27.125, -26.875, -9.0, -3.0, 0.0, 3.6, "wall"),
		_box("EchoppesMurW2", -27.125, -26.875, -1.0, 5.0, 0.0, 3.6, "wall"),
		_box("ComptoirW", -31.0, -29.0, 0.0, 1.0, 0.0, 1.1, "low"),
		_bld("SaloonW", -16.0, -8.0, -11.0, 5.0, 6.4, 2,
			[_door("N", 0.0, 2.4), _door("W", -3.0, 2.4), _door("E", 4.5, 2.4), _door("E", 0.0, 2.4, 1), _door("W", 0.0, 2.4, 1)], ["N", "S"], "S", "PP3"),
		_stairs_piece("StairRuelleW", Vector3(-16.75, 0, 3), Vector3(-16.75, 3.2, -3), 1.5),
		_box("BalconW", -8.0, -6.0, -9.0, -1.0, 2.95, 3.2, "slab"),
		_fence_piece("RampeBalconW", -6.0, -9.0, -6.0, -1.0, 1.0, 3.2),
		_stairs_piece("StairGalerieW", Vector3(-7, 0, -15), Vector3(-7, 3.2, -9), 1.5),
		_box("TonneauxW", -7.5, -5.5, 3.0, 5.0, 0.0, 2.0),
		_box("TraversesW", -5.0, -3.0, 0.5, 2.5, 0.0, 2.0),
		_box("PileTraversesNW", -6.0, -4.0, -7.5, -6.0, 0.0, 2.0),
		_box("RemiseW", -30.0, -26.0, 5.0, 8.5, 0.0, 2.6),
		_fence_piece("ClotureW", -37.0, 6.0, -33.0, 6.0, 1.1),
		_box("CuveW", -13.0, -10.0, 7.5, 12.0, 0.0, 2.4),
		_box("ChariotMineW", -37.0, -34.0, 8.5, 12.0, 0.0, 2.2),
		_box("CaissesQuaiW", -20.0, -18.0, 9.0, 11.0, 0.0, 2.0),
		_fence_piece("ParapetW1", -44.0, 11.9, -41.0, 11.9, 1.1),
		_fence_piece("ParapetW2", -38.0, 11.9, -19.0, 11.9, 1.1),
		_fence_piece("ParapetW3", -16.0, 11.9, -2.5, 11.9, 1.1),
		_ramp_piece("RampeCanyonW1", Vector3(-40, 0, 13), Vector3(-34, -2, 13), 2.0),
		# LD-43 : élargie de 2 à 4 m (largeur SEULE, tracé start/end inchangé) —
		# seule modification qui corrige, PAR LA GÉOMÉTRIE, le couloir Canyon
		# côté bleu à 6,6 s (plafond 6,5 s, cible §4 "4 à 7 s par lane") sans
		# jamais relever le plafond du test. Diagnostic (bake réel, isolé
		# rampe par rampe sur cette tâche) : la rampe W1 n'a AUCUN effet sur ce
		# chemin (jamais empruntée par le proxy spawn->Gué, côté bleu ni
		# rouge) ; élargir W2 seule suffit et reproduit tel quel le résultat
		# obtenu en élargissant W1+W2 ensemble — gain mesuré bleu 6,63 s ->
		# 6,41 s, rouge inchangé (6,36 s), écart mirroir 1,1 % (plafond 8 %).
		# Miroir automatique (`_mirror_piece`, E2 reçoit la même largeur) :
		# respecte "en miroir des deux côtés" sans dupliquer la pièce à la main.
		# Connu et accepté : élargie à 4 m, cette rampe déborde jusqu'à z=15
		# (contre z=14 à 2 m de large) et chevauche le point de connaissance
		# bot "RampeCanyonW2 / Ruelle ouest" (Vector3(-15, -1.5, 14.7),
		# `WastelandBots._lane_canyon()`, hors de mon périmètre de fichiers) —
		# `tests/ai/test_wasteland_bot_data.gd::test_bot_knowledge_corridor_
		# points_...` (hors de mon périmètre) régresse d'un seul point sur 31
		# (décalage mesuré 0,88 m pour une tolérance de 0,5 m). Signalé au
		# lead (rendu de tâche, blocked_on) plutôt que corrigé ici : nécessite
		# de toucher wasteland_bots.gd, hors de ma liste de fichiers.
		_ramp_piece("RampeCanyonW2", Vector3(-18, 0, 13), Vector3(-12, -2, 13), 4.0),
		_box("RocherS1W", -31.0, -27.0, 15.5, 20.0, -2.0, 1.8, "rock"),
		_box("RocherN1W", -24.0, -21.0, 12.0, 16.5, -2.0, 1.8, "rock"),
		_box("RocherS2W", -10.0, -7.0, 15.5, 20.0, -2.0, 1.8, "rock"),
		_box("RocherGueW", -4.0, -2.5, 12.0, 16.5, -2.0, 1.8, "rock"),
	]

# ======================================================================
#  Barrières Duel/Duo (§7, nouveau champ "modes") : une box (2.6 m) plus un
#  mur invisible (12 m), en 3 lignes symétriques — Grand-Rue (x=±13),
#  bouches des Ruelles (z=−9, x±16 à ±20) et arrière-cours/canyon (x=±20,
#  z 5 à 20). Le périmètre Duel/Duo réduit se referme donc sur x ∈ [−20,20]
#  pour z ∈ [−9,20] et x ∈ [−13,13] sur la Grand-Rue (§7 "Périmètre"),
#  laissant Hôtel/Banque/Échoppes/Forges hors zone. Simplification assumée
#  (hors des critères d'acceptation chiffrés de cette tâche) : les 2
#  panneaux de porte (Échoppes côté Ruelle, Magasin côté Passage) du §7 ne
#  sont pas posés ici — les 3 lignes ci-dessous ferment déjà le périmètre
#  au sol ; à affiner par la tâche qui verrouillera les métriques Duel/Duo
#  chiffrées (§4 "sol praticable ≈ 1200 m², ≤ 4 s"), hors du périmètre de LD-40.
# ======================================================================
static func _duel_duo_barriers() -> Array:
	var out: Array = []
	for side in [1.0, -1.0]:
		var s: float = side
		out.append({"type": "box", "name": "BarriereRue%d" % int(s), "pos": Vector3(13.0 * s, 1.3, -15.0), "size": Vector3(0.5, 2.6, 8.0), "color_key": "wall", "modes": ["duel", "duo"]})
		out.append({"type": "invisible_wall", "name": "BarriereRueWall%d" % int(s), "start": Vector3(13.0 * s, 0, -19), "end": Vector3(13.0 * s, 0, -11), "height": 12.0, "modes": ["duel", "duo"]})
		out.append({"type": "box", "name": "BarriereRuelle%d" % int(s), "pos": Vector3(18.0 * s, 1.3, -9.0), "size": Vector3(4.0, 2.6, 0.5), "color_key": "wall", "modes": ["duel", "duo"]})
		out.append({"type": "invisible_wall", "name": "BarriereRuelleWall%d" % int(s), "start": Vector3(16.0 * s, 0, -9), "end": Vector3(20.0 * s, 0, -9), "height": 12.0, "modes": ["duel", "duo"]})
		out.append({"type": "box", "name": "BarriereCanyon%d" % int(s), "pos": Vector3(20.0 * s, 1.3, 12.5), "size": Vector3(0.5, 2.6, 15.0), "color_key": "wall", "modes": ["duel", "duo"]})
		out.append({"type": "invisible_wall", "name": "BarriereCanyonWall%d" % int(s), "start": Vector3(20.0 * s, 0, 5), "end": Vector3(20.0 * s, 0, 20), "height": 12.0, "modes": ["duel", "duo"]})
	return out

# ======================================================================
#  Marqueurs (§9 "Marqueurs", §7 "Modes") — jamais mirorés à la main : les
#  positions est/ouest sont écrites explicitement, symétriques par
#  construction (comme le modèle Python).
# ======================================================================
static func _team_spawns() -> Dictionary:
	var sp0: Array = []
	var sp1: Array = []
	for z in [-8.0, -4.0, 0.0, 4.0]:
		sp0.append(Layouts._spawn(Vector3(-41, 1, z), Vector3(-36, 1, z)))
		sp1.append(Layouts._spawn(Vector3(41, 1, z), Vector3(36, 1, z)))
	return {0: sp0, 1: sp1}

## §7 "Spawns neutres : 24 (12 par moitié, en miroir)" — y=1 au sol, −1 dans
## le canyon (z >= 12, §9 "Marqueurs").
## LD-41, 2e passage (note de tâche (a)) : 4 des 5 poches de la cour de spawn
## (indices 0/2/3/4 ci-dessous, x = ∓41 à l'origine) dépassaient les 5 s
## spawn -> front (pire cas 5,69 s pour x = ±41, z = -2, cf. rapport QA du
## 1er passage) — rapprochées du front en les décalant vers l'est (x -41 ->
## -36,5/-38) tout en restant dans des couloirs dégagés (jamais dans
## ForgeW/CiterneFUEL/CaisseFUEL/EchoppesW, cf. leurs bornes ci-dessus) :
## marge de 0,5 m côté ForgeW (mur ouest à x=-36) et de 1 m côté CaisseFUEL
## (mur ouest à x=-37, d'où le décalage combiné x/z de l'index 3 pour sortir
## de sa bande z -4..0). Index 0 aussi remonté en z (-20 -> -18, toujours
## dans la bande z de ForgeW/hors de celle de CiterneFUEL) pour dégager une
## marge de sécurité sous la cible de 5 s (mesuré à 5,01 s au ras de la cible
## avec x seul ajusté). Index 1, 5 à 11 : déjà <= 5 s (1er passage), inchangés.
static func _tdm_spawns() -> Array:
	var west_pts: Array = [
		Vector2(-36.5, -18), Vector2(-38.5, -17), Vector2(-36.5, -8), Vector2(-36.5, -6), Vector2(-39, 4),
		Vector2(-39, 7.5), Vector2(-42, 15.5), Vector2(-42, 18.5), Vector2(-31, -5), Vector2(-24, 1),
		Vector2(-32.5, -21), Vector2(-23, 8.5),
	]
	var out: Array = []
	for p in west_pts:
		var v: Vector2 = p
		for s in [1.0, -1.0]:
			var x: float = v.x * s
			var y: float = -1.0 if v.y >= 12.0 else 1.0
			out.append({"pos": Vector3(x, y, v.y)})
	return out

static func data() -> Dictionary:
	var pieces: Array = []
	pieces.append_array(_cliffs())
	pieces.append_array(_center())
	var west := _west()
	pieces.append_array(west)
	for p in west:
		pieces.append(_mirror_piece(p))
	pieces.append_array(_duel_duo_barriers())
	pieces = _filter_pieces_for_mode(pieces)

	return {
		"id": "wasteland", "name": "Wasteland",
		"palette": WastelandLook.palette(),
		"pieces": pieces,
		"spawns": _team_spawns(),
		"tdm_spawns": _tdm_spawns(),
		# §7 "Hardpoint : 3 zones, ordre P1 -> P2 -> P3 -> P1" — P1 Wagon
		# (neutre), P2 Magasin ouest (maison bleue), P3 Gué est, sur le BORD
		# du canyon (§12.4, décision : pas au fond). `hardpoint_sizes`
		# (LD-22, tableau parallèle) : emprise réelle par zone (§7).
		# LD-41, 2e passage (note de tâche (b)) : parité "zone maison" mesurée
		# à 11,4 % (bleu->P2 36,6 m, rouge->P3 32,5 m), au-delà de la cible
		# +/-10 % — SEULE modification de ce fichier pour ce critère (aucune
		# géométrie touchée) : P2.x rapproché du spawn bleu de 2 m (-8,5 ->
		# -10,5, reste dans MagasinW, x in [-13,-4]) et P3.x éloigné du spawn
		# rouge de 1 m (15 -> 14, reste sur le bord du canyon, z/y inchangés,
		# §12.4) pour ramener le gap sous la cible avec une marge contre le
		# bruit de bake Recast documenté par le test.
		"hardpoints": [Vector3(0, 1.7, -1), Vector3(-10.5, 1.8, -22), Vector3(14, -0.5, 17)],
		"hardpoint_sizes": [Vector3(14, 3.4, 5), Vector3(8.5, 3.6, 5.5), Vector3(6, 3, 5)],
		"site_a": {"pos": Vector3(21, 1.5, -22), "size": Vector3(8, 3, 4)},
		"site_b": {"pos": Vector3(21, 1.5, 8.5), "size": Vector3(6, 3, 5)},
		"duel_zone": {"pos": Vector3(0, 1.5, -6), "size": Vector3(6, 3, 4)},
		"bounds": {"min": Vector2(-44, -25), "max": Vector2(44, 20)},
		# §12.2 "symétrie miroir STRICTE du gameplay" : contrairement à la v3
		# (asymétrique, bascule de mi-temps TDM/Hardpoint), la v4 n'a pas
		# besoin d'échanger les côtés — les deux moitiés sont déjà
		# équivalentes par construction (`MapSetup._build_game_mode`).
		"asymmetric": false,
		"perimeter": [
			Vector2(-44, -25), Vector2(44, -25), Vector2(44, 20), Vector2(-44, 20),
		],
	}
