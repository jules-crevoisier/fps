## balance_table.gd
## Régénère docs/BALANCE.md à partir du catalogue WeaponDatabase (source de
## vérité = les .tres, pas ce script). Pour chaque arme : rôle/niche, coût, et
## un tableau TTK (corps + tête) par distance. Pur calcul (WeaponMath), aucune
## scène chargée.
##   godot --headless --path . -s res://tools/balance_table.gd
## Affiche `BALANCE_TABLE_OK` puis quitte avec le code 0, ou `BALANCE_TABLE_FAIL`
## + le code 1 si l'écriture du fichier échoue.
extends SceneTree

const OUT_PATH := "res://docs/BALANCE.md"
const HP := 100.0
## Distances (m) de la table TTK par arme.
const DISTANCES := [0.0, 5.0, 10.0, 15.0, 20.0, 30.0, 40.0, 50.0, 70.0]

## Pourquoi chaque arme existe (niche, en français) — voir aussi la note sur la
## règle de niche dans tests/balance/test_ttk_bands.gd.
const WHY := {
	"Pistolet": "Arme de secours gratuite : TTK correct (550-700 ms) à bout portant, dégâts qui chutent vite. Toujours en poche, aucun slot consommé.",
	"Magnum": "Sidearm à gros dégâts : tue toujours en 2 têtes ou 3 corps, quelle que soit la distance dans sa portée — la précision prime sur la cadence.",
	"Rafale": "SMG qui domine le close-range (0-15 m) : cadence élevée, dégâts qui s'effondrent après 14 m. Le pick d'entrée standard.",
	"Marqueur": "Fusil semi précis, roi du 30-50 m : gros dégâts par tir, chute de dégâts tardive (35-70 m). Puni le mouvement (viser à l'arrêt).",
	"Ravage": "Fusil auto polyvalent, meilleur en 15-30 m : équilibre cadence/dégâts/recul, le pick « sûr » qui reste correct partout.",
	"Fracas": "Pompe : one-shot garanti jusqu'à 4 m avec tous les plombs, quasi inutile au-delà de 15-18 m. Cadence lente, à réserver au close-quarters.",
	"Faucheur": "Sniper à lunette : one-shot à la tête sur toute sa portée utile, domine au-delà de 50 m. Sprint-to-fire élevé (350 ms, cf. ROADMAP §4) pour compenser sa puissance.",
	"Éclair": "SMG « mobilité » : sprint-to-fire et ADS les plus rapides du jeu, portée plus courte que le Rafale. Le pick rush / flank, moins cher.",
	"Semeuse": "Mitrailleuse légère (LMG) : le plus gros chargeur du jeu (100 balles), tir soutenu pour tenir un couloir. Lourde : mouvement et sprint-to-fire pénalisés.",
	"Percuteur": "Fusil de précision semi-auto (DMR) : tue en 2 têtes à toute distance comme le Magnum, sans la lunette ni le coût du Faucheur — la précision « milieu de gamme ».",
}

## Niche courte (une ligne) par arme, utilisée dans le tableau récapitulatif.
const NICHE := {
	"Pistolet": "Secours gratuit",
	"Magnum": "2 têtes / 3 corps, toute distance",
	"Rafale": "Roi du close-range (0-15 m)",
	"Marqueur": "Roi du 30-50 m",
	"Ravage": "Roi du 15-30 m, polyvalent",
	"Fracas": "One-shot ≤ 4 m",
	"Faucheur": "Roi du 50 m+, one-shot tête",
	"Éclair": "SMG mobilité (rush)",
	"Semeuse": "LMG, plus gros chargeur",
	"Percuteur": "DMR, 2 têtes toute distance",
}


func _initialize() -> void:
	var md := _build_markdown()
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		print("BALANCE_TABLE_FAIL impossible d'ouvrir %s (err=%s)" % [OUT_PATH, FileAccess.get_open_error()])
		quit(1)
		return
	f.store_string(md)
	f.close()
	print("BALANCE_TABLE_OK écrit %s (%d armes)" % [OUT_PATH, WeaponDatabase.all().size()])
	quit(0)


func _build_markdown() -> String:
	var lines: Array[String] = []
	lines.append("# Équilibrage des armes (BALANCE.md)")
	lines.append("")
	lines.append("Généré par `tools/balance_table.gd` — ne pas éditer à la main, relancer :")
	lines.append("```")
	lines.append("$GODOT_BIN --headless --path . -s res://tools/balance_table.gd")
	lines.append("```")
	lines.append("")
	lines.append("HP = %d. TTK = temps pour tuer (ms), calculé par `WeaponMath.ttk_ms` : (tirs - 1) / cadence." % int(HP))
	lines.append("« — » = hors de portée efficace (au-delà de `max_range`, dégâts nuls).")
	lines.append("")
	lines.append("## Note sur la règle de niche")
	lines.append("")
	lines.append(
		"Le contrat demande que chacune des 10 armes soit \"strictement la meilleure\" " +
		"dans au moins une des 5 bandes de distance ([0-6], [6-15], [15-30], [30-50], " +
		"[50+] m). Avec 8 armes principales (hors les 2 sidearms Pistolet/Magnum) et " +
		"seulement 5 bandes, c'est mathématiquement impossible : une bande n'a qu'un " +
		"seul \"meilleur TTK corps\" à la fois, donc au plus 5 armes peuvent remporter " +
		"une bande, jamais 8. Les 5 armes dont le rôle est de dominer une portée " +
		"(Fracas, Rafale, Ravage, Marqueur, Faucheur) remportent chacune une bande — " +
		"voir le tableau des champions plus bas, vérifié par " +
		"`tests/balance/test_ttk_bands.gd`. Les 3 nouvelles armes (Éclair, Semeuse, " +
		"Percuteur) ont une niche alternative propre et testée (mobilité, plus gros " +
		"chargeur, 2 têtes à toute distance) plutôt que de se disputer une bande déjà " +
		"prise."
	)
	lines.append("")
	lines.append("## Championnes par bande (TTK corps au point médian, hors sidearms)")
	lines.append("")
	lines.append("| Bande | Point médian | Championne | TTK corps |")
	lines.append("|---|---|---|---|")
	var bands := [
		["0-6 m", 3.0],
		["6-15 m", 10.5],
		["15-30 m", 22.5],
		["30-50 m", 40.0],
		["50 m+", 65.0],
	]
	var primaries := _primaries()
	for band in bands:
		var band_name: String = band[0]
		var mid: float = band[1]
		var champion_name := ""
		var champion_ttk := INF
		for c in primaries:
			var ttk := WeaponMath.ttk_ms(c, mid, HP, false)
			if ttk < champion_ttk:
				champion_ttk = ttk
				champion_name = c.weapon_name
		lines.append("| %s | %.1f m | %s | %.1f ms |" % [band_name, mid, champion_name, champion_ttk])
	lines.append("")
	lines.append("## Arsenal (10 armes)")
	lines.append("")
	lines.append("| Arme | Catégorie | Coût | Niche |")
	lines.append("|---|---|---|---|")
	for c in WeaponDatabase.all():
		lines.append("| %s | %s | %d | %s |" % [c.weapon_name, WeaponDatabase.category_name(c.category), c.cost, NICHE.get(c.weapon_name, "")])
	lines.append("")
	for c in WeaponDatabase.all():
		lines.append("## %s" % c.weapon_name)
		lines.append("")
		lines.append("- Catégorie : %s (%s)" % [WeaponDatabase.category_name(c.category), WeaponDatabase.type_name(c.weapon_type)])
		lines.append("- Coût : %d crédits" % c.cost)
		lines.append("- Pourquoi : %s" % WHY.get(c.weapon_name, ""))
		lines.append("")
		lines.append("| Distance | TTK corps | TTK tête |")
		lines.append("|---|---|---|")
		for dist in DISTANCES:
			var row := "| %d m |" % int(dist)
			if dist > c.max_range:
				row += " — | — |"
			else:
				var body_ttk := WeaponMath.ttk_ms(c, dist, HP, false)
				var head_ttk := WeaponMath.ttk_ms(c, dist, HP, true)
				row += " %.1f ms | %.1f ms |" % [body_ttk, head_ttk]
			lines.append(row)
		lines.append("")
	return "\n".join(lines) + "\n"


func _primaries() -> Array:
	var out := []
	for c in WeaponDatabase.all():
		if c.category != WeaponConfig.Category.SIDEARM and c.category != WeaponConfig.Category.MELEE:
			out.append(c)
	return out
