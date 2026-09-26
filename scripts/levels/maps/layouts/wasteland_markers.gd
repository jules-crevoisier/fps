## wasteland_markers.gd
## LD-41 (docs/research/11_wasteland_v4_layout.md §7 "Modes"/§8 "Repères de
## callout"/§9 "Marqueurs") — données bots-agnostiques ajoutées PAR-DESSUS
## `WastelandLayout.data()` (fusionnées additivement par `MapSetup
## ._assemble_wasteland` : ne comble QUE les clés que `wasteland.gd`, LD-40,
## ne déclare pas déjà lui-même — voir son commentaire "La fusion devient
## donc additive"). `wasteland.gd` possède désormais `tdm_spawns`,
## `hardpoints`, `site_a`, `site_b`, `duel_zone` (§9 "Marqueurs", hors de mon
## périmètre) : ce fichier fournit ce qu'il NE déclare PAS — `strong_positions`
## (PF1-PF5/PP1-PP5, requises pour la règle de sécurité "jamais visible depuis
## une position forte adverse à <= 20 m", §7 "Notation"), `callouts` (§8) et
## `hp_entries` (§7, "Entrées" par zone Hardpoint, 3-4 routes d'approche
## réelles par zone, PAS un comptage radial générique — voir l'en-tête de
## `_hp_entries()`).
##
## REMPLACE le contrat v3 (LD-21, damier Crête/Grand-Rue/Ravin/PF1-PF5 sur
## l'ancienne géométrie 80 x 43 m) : la v3 est gelée sous `wasteland_v3.gd`/
## `WastelandLayoutV3`, jamais assemblée avec ce fichier (`MapSetup._data_for`,
## "wasteland_v3" reste autonome). `_tdm_spawns()` est conservée ici comme UN
## SEUL point d'accès statique (compat pour tout code qui l'appelait encore
## directement plutôt que de lire `WastelandLayout.data()["tdm_spawns"]`) :
## elle DÉLÈGUE à `WastelandLayout._tdm_spawns()`, jamais une copie à la main,
## pour ne jamais laisser deux listes de 24 points diverger.
##
## PURE (Dictionary/Vector3/AABB, aucun nœud) — même discipline que l'ancien
## fichier v3 : `WastelandLayout.gd` (la géométrie v4, déjà verrouillée par
## LD-40) EST la dépendance légitime ici (contrairement à `Layouts.gd`,
## toujours hors sujet pour Wasteland), puisque `strong_positions` et
## `hp_entries` n'ont de sens que rapportés à SA géométrie réelle (portes,
## étages, zones Hardpoint).
class_name WastelandMarkers
extends RefCounted

## Un spawn {pos, look} — même schéma que `Layouts._spawn`/`MapSetup
## ._build_markers` (`s.get("look", pos)` : "look" est optionnel, un spawn
## sans regard explicite ne tourne simplement pas).
static func _spawn(pos: Vector3, look: Vector3) -> Dictionary:
	return {"pos": pos, "look": look}


# ======================================================================
#  Positions fortes (§6 "un étage, 5 positions fortes, un contre chacune" :
#  PP1 Hôtel, PP2 Banque, PP3/PP4 galeries des Saloons, PP5 Wagon) —
#  nécessaires ICI pour la règle de sécurité des spawns (§7 "Notation...
#  Jamais visible depuis une position forte adverse à <= 20 m", même clé
#  `strong_positions` que les 6 maps v1 et que l'ancien contrat v3).
#  PP1/PP2/PP3/PP4 : MÊMES valeurs que `tests/maps/test_wasteland.gd::
#  _PP_POSITIONS` (LD-40, sommet praticable de l'étage/la galerie, y = 3,2 m)
#  — copiées, jamais redérivées, pour ne jamais diverger du contrat déjà
#  verrouillé par les tests d'accès de LD-40. PP5 Wagon (§6 "au sol, 0 m") :
#  même point que `hardpoints[0]` (centre du Wagon, y = 1,7 m = mi-hauteur du
#  couloir) et que le point "inside" de `test_wasteland.gd::
#  test_pp5_wagon_has_four_functional_door_paths` — PP5 n'a pas d'étage
#  propre, son "sommet praticable" est son sol intérieur.
# ======================================================================
static func _strong_positions() -> Array:
	return [
		Vector3(-21, 3.2, -22),  # PP1 Hôtel (étage)
		Vector3(21, 3.2, -22),  # PP2 Banque (miroir, étage)
		Vector3(-12, 3.2, -3),  # PP3 Galerie du Saloon ouest
		Vector3(12, 3.2, -3),  # PP4 Galerie du Saloon est (miroir)
		Vector3(0, 1.7, -1),  # PP5 Le Wagon (au sol, PAS un étage)
	]


# ======================================================================
#  28 callouts (§8 "Repères de callout... un repère unique par quartier") —
#  damier de 4 rangées (bandes z : Grand-Rue/façades, Intérieurs+Place,
#  Arrière-cours, Canyon, §5 "Les lanes") x 7 colonnes (ouest lointain,
#  ouest, centre-ouest, centre, centre-est, est, est lointain), MÊME
#  PRINCIPE que le damier v1 (`Layouts._callout_grid`) mais reconstruit
#  PUREMENT ICI (voir en-tête : dépendre de `Layouts.gd` serait fragile,
#  fichier hors de mon périmètre et en restructuration par une autre tâche
#  de cette même vague). La première/dernière bande de chaque axe s'étend à
#  ±`_CALLOUT_MARGIN` au-delà des `bounds` déclarés (capte toute géométrie
#  en bord de carte : rampes, débords, falaises), une bande Y unique
#  `_CALLOUT_Y` couvre large le point le plus haut (grue/derrick, décor,
#  hors gameplay) et le plus bas (canyon, y = -2) de la carte. Les bornes de
#  colonnes/rangées sont "meilleur effort" (§8 ne fixe aucune grille
#  chiffrée) : elles suivent d'aussi près que possible les empreintes RÉELLES
#  de `wasteland.gd` (§9 "Spec du blockout") ; la clé du contrat n'est pas
#  l'alignement pixel-parfait mais "chaque quartier a un nom unique, <= 14
#  caractères, et le damier couvre >= 95 % du navmesh réel"
#  (`test_navmesh_coverage_at_least_95_percent`).
# ======================================================================
const _CALLOUT_MARGIN := 2000.0
const _CALLOUT_Y := Vector2(-20.0, 40.0)

static func _callout_grid(xs: Array, zs: Array, names: Array) -> Array:
	var xedges: Array = [-_CALLOUT_MARGIN]
	xedges.append_array(xs)
	xedges.append(_CALLOUT_MARGIN)
	var zedges: Array = [-_CALLOUT_MARGIN]
	zedges.append_array(zs)
	zedges.append(_CALLOUT_MARGIN)
	var out: Array = []
	for row in range(zedges.size() - 1):
		var row_names: Array = names[row]
		for col in range(xedges.size() - 1):
			var x0: float = xedges[col]
			var x1: float = xedges[col + 1]
			var z0: float = zedges[row]
			var z1: float = zedges[row + 1]
			var aabb := AABB(Vector3(x0, _CALLOUT_Y.x, z0), Vector3(x1 - x0, _CALLOUT_Y.y - _CALLOUT_Y.x, z1 - z0))
			out.append({"name": String(row_names[col]), "aabb": aabb})
	return out

## Bandes z : Grand-Rue/façades (z < -9, Forge/Hôtel/Magasin/Banque/Poste,
## §5 "①"), Intérieurs + Place (-9 à 5, Échoppes/Ruelle/Saloons/Place, §5
## "②"), Arrière-cours (5 à 12, Remise/Cuve/Chariot de mine, §5 "arrière-
## cours"), Canyon (>= 12, §5 "③"). Bandes x, symétriques autour de x = 0 :
## lointain (< -34/> 34, cours de spawn), quartier (± 34 à ± 20), centre-
## quartier (± 20 à ± 8), centre (± 8, Poste/Diligence/Wagon/Château d'eau/
## Descente, tous compris dans |x| <= 6 au §9).
static func _callouts() -> Array:
	return _callout_grid(
		[-34.0, -20.0, -8.0, 8.0, 20.0, 34.0], [-9.0, 5.0, 12.0],
		[
			["Cour FUEL", "Forge", "Hotel", "Poste", "Banque", "Marechal", "Cour GAS"],
			["Piste Ouest", "Echoppes", "Saloon Bleu", "Place", "Saloon Rouge", "Bazar", "Piste Est"],
			["Chariot Mine", "Remise", "Cuve", "Chateau Eau", "Cuve Est", "Remise Est", "Chariot Est"],
			["Eolienne", "Canyon Ouest", "Rampe Ouest", "Descente", "Rampe Est", "Canyon Est", "Wagonnet"],
		]
	)


## ======================================================================
##  Entrées par zone Hardpoint (§7 "Entrées (>= 3)", colonne du tableau des
##  3 zones) — contrairement aux positions fortes (petites plates-formes
##  ENCLAVÉES) ou aux sites SnD, les 3 zones Hardpoint v4 sont des places
##  OUVERTES au sol ou à flanc de canyon : un comptage radial de "portails"
##  (comme `test_snd_timings.gd::_count_entries`) y renvoie 1 seul portail
##  géant dès que la place est dégagée sur tout son pourtour — méthode
##  inadaptée à un espace sans mur (même limite que documentée par l'ancien
##  fichier v3). On déclare donc ici les 3-4 ROUTES D'APPROCHE RÉELLES de
##  chaque zone (§7, colonne "Entrées"), comme points {pos}, chacune vérifiée
##  par le test (`test_hp_zone_entries_are_on_the_navmesh_reachable_and_
##  distinct`) : sur le navmesh (projection), joignable par un chemin RÉEL
##  depuis le centre de zone, et distincte des autres entrées de la même
##  zone (>= 3 m). Clés "P1"/"P2"/"P3" : mêmes noms que le tableau §7 et que
##  l'ordre de `WastelandLayout.data()["hardpoints"]` (index 0=P1 Wagon,
##  1=P2 Magasin ouest, 2=P3 Gué est), jamais les lettres A/B/C de l'ancien
##  contrat v3 (zones différentes, ordre différent).
## ======================================================================
static func _hp_entries() -> Dictionary:
	return {
		# P1 Wagon (§9 "Wagon (PP5, HP P1)... portes O0, E0, S0 offset -3,
		# S0 offset +3") : les 4 ouvertures du wagon (§7 "4 ouvertures du
		# wagon et la place tout autour"), un point juste devant chacune.
		"P1": [
			Vector3(-8, 1.7, -1),  # porte ouest
			Vector3(8, 1.7, -1),  # porte est
			Vector3(-3, 1.7, 2),  # porte sud, offset -3
			Vector3(3, 1.7, 2),  # porte sud, offset +3
		],
		# P2 Magasin ouest (§9 "MagasinW... S0 offset -3 ; S0 offset +3 ;
		# O0 offset +1") : "2 portes au sud, 1 porte à l'ouest (Passage)"
		# (§7) — la porte ouest donne sur `StairPassageW` (§9, x = -15,25).
		"P2": [
			Vector3(-11.5, 1.8, -17.5),  # porte sud, offset -3
			Vector3(-5.5, 1.8, -17.5),  # porte sud, offset +3
			Vector3(-15.0, 1.8, -21.0),  # porte ouest, vers le Passage
		],
		# P3 Gué est (§9 "Gué" mirroré : RocherS2E/RampeCanyonE2/CaissesQuaiE)
		# : "canyon ouest, canyon est, rampe est 2, chute depuis l'arrière-
		# cour" (§7) — 4 routes d'approche réelles, aucune n'est une porte.
		"P3": [
			Vector3(9, -0.5, 17),  # canyon ouest (le long du lit du canyon)
			Vector3(22, -0.5, 17),  # canyon est
			Vector3(15, -1.0, 13.5),  # rampe est 2 (RampeCanyonE2, miroir)
			Vector3(19, -0.3, 12.3),  # chute depuis l'arrière-cour (ParapetE2, miroir)
		],
	}


static func data() -> Dictionary:
	return {
		"strong_positions": _strong_positions(),
		"callouts": _callouts(),
		"hp_entries": _hp_entries(),
	}
