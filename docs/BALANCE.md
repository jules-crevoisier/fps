# Équilibrage des armes (BALANCE.md)

Généré par `tools/balance_table.gd` — ne pas éditer à la main, relancer :
```
$GODOT_BIN --headless --path . -s res://tools/balance_table.gd
```

HP = 100. TTK = temps pour tuer (ms), calculé par `WeaponMath.ttk_ms` : (tirs - 1) / cadence.
« — » = hors de portée efficace (au-delà de `max_range`, dégâts nuls).

## Note sur la règle de niche

Le contrat demande que chacune des 10 armes soit "strictement la meilleure" dans au moins une des 5 bandes de distance ([0-6], [6-15], [15-30], [30-50], [50+] m). Avec 8 armes principales (hors les 2 sidearms Pistolet/Magnum) et seulement 5 bandes, c'est mathématiquement impossible : une bande n'a qu'un seul "meilleur TTK corps" à la fois, donc au plus 5 armes peuvent remporter une bande, jamais 8. Les 5 armes dont le rôle est de dominer une portée (Fracas, Rafale, Ravage, Marqueur, Faucheur) remportent chacune une bande — voir le tableau des champions plus bas, vérifié par `tests/balance/test_ttk_bands.gd`. Les 3 nouvelles armes (Éclair, Semeuse, Percuteur) ont une niche alternative propre et testée (mobilité, plus gros chargeur, 2 têtes à toute distance) plutôt que de se disputer une bande déjà prise.

## Championnes par bande (TTK corps au point médian, hors sidearms)

| Bande | Point médian | Championne | TTK corps |
|---|---|---|---|
| 0-6 m | 3.0 m | Fracas | 0.0 ms |
| 6-15 m | 10.5 m | Rafale | 384.6 ms |
| 15-30 m | 22.5 m | Ravage | 400.0 ms |
| 30-50 m | 40.0 m | Marqueur | 428.6 ms |
| 50 m+ | 65.0 m | Faucheur | 500.0 ms |

## Arsenal (10 armes)

| Arme | Catégorie | Coût | Niche |
|---|---|---|---|
| Pistolet | Arme de poing | 0 | Secours gratuit |
| Magnum | Arme de poing | 750 | 2 têtes / 3 corps, toute distance |
| Rafale | SMG | 1700 | Roi du close-range (0-15 m) |
| Marqueur | Fusil | 3100 | Roi du 30-50 m |
| Ravage | Fusil | 2900 | Roi du 15-30 m, polyvalent |
| Fracas | Fusil à pompe | 1850 | One-shot ≤ 4 m |
| Faucheur | Sniper | 4600 | Roi du 50 m+, one-shot tête |
| Éclair | SMG | 1650 | SMG mobilité (rush) |
| Semeuse | Lourde | 3200 | LMG, plus gros chargeur |
| Percuteur | Fusil | 3150 | DMR, 2 têtes toute distance |

## Munitions par règle (GF-21, docs/research/10_ammo_kits_input.md §2.2/§2.3)

« Réserve manche » (`WeaponConfig.reserve_ammo`) sert au Litige et au Duel/Duo (rechargée à chaque manche, `Inventory.RULE_ROUND`). « Réserve arène » (`WeaponConfig.arena_reserve_ammo`, `Inventory.RULE_ARENA`) sert à la Mêlée et à la Borne — plus généreuse (×5 chargeurs, sauf Semeuse déjà à 300 et Faucheur ×4) car une vie d'arène tient plusieurs affrontements sans repasser par la boutique. L'entraînement (`Inventory.RULE_INFINITE`) n'a pas de colonne : sa réserve est un sentinelle volontairement énorme (aucune session ne peut l'épuiser).

| Arme | Chargeur | Réserve manche | Réserve arène |
|---|---|---|---|
| Pistolet | 12 | 60 | 60 |
| Magnum | 6 | 24 | 30 |
| Rafale | 32 | 96 | 160 |
| Marqueur | 20 | 80 | 100 |
| Ravage | 25 | 75 | 125 |
| Fracas | 6 | 24 | 30 |
| Faucheur | 5 | 15 | 20 |
| Éclair | 26 | 104 | 130 |
| Semeuse | 100 | 200 | 200 |
| Percuteur | 12 | 48 | 60 |

## Pistolet

- Catégorie : Arme de poing (Hitscan)
- Coût : 0 crédits
- Pourquoi : Arme de secours gratuite : TTK correct (550-700 ms) à bout portant, dégâts qui chutent vite. Toujours en poche, aucun slot consommé.

| Distance | TTK corps | TTK tête |
|---|---|---|
| 0 m | 592.6 ms | 148.1 ms |
| 5 m | 592.6 ms | 148.1 ms |
| 10 m | 592.6 ms | 148.1 ms |
| 15 m | 592.6 ms | 148.1 ms |
| 20 m | 592.6 ms | 148.1 ms |
| 30 m | 592.6 ms | 148.1 ms |
| 40 m | 592.6 ms | 148.1 ms |
| 50 m | 740.7 ms | 296.3 ms |
| 70 m | 740.7 ms | 296.3 ms |

## Magnum

- Catégorie : Arme de poing (Hitscan)
- Coût : 750 crédits
- Pourquoi : Sidearm à gros dégâts : tue toujours en 2 têtes ou 3 corps, quelle que soit la distance dans sa portée — la précision prime sur la cadence.

| Distance | TTK corps | TTK tête |
|---|---|---|
| 0 m | 909.1 ms | 454.5 ms |
| 5 m | 909.1 ms | 454.5 ms |
| 10 m | 909.1 ms | 454.5 ms |
| 15 m | 909.1 ms | 454.5 ms |
| 20 m | 909.1 ms | 454.5 ms |
| 30 m | 909.1 ms | 454.5 ms |
| 40 m | 909.1 ms | 454.5 ms |
| 50 m | 909.1 ms | 454.5 ms |
| 70 m | 909.1 ms | 454.5 ms |

## Rafale

- Catégorie : SMG (Hitscan)
- Coût : 1700 crédits
- Pourquoi : SMG qui domine le close-range (0-15 m) : cadence élevée, dégâts qui s'effondrent après 14 m. Le pick d'entrée standard.

| Distance | TTK corps | TTK tête |
|---|---|---|
| 0 m | 384.6 ms | 307.7 ms |
| 5 m | 384.6 ms | 307.7 ms |
| 10 m | 384.6 ms | 307.7 ms |
| 15 m | 384.6 ms | 307.7 ms |
| 20 m | 461.5 ms | 307.7 ms |
| 30 m | 615.4 ms | 461.5 ms |
| 40 m | 692.3 ms | 461.5 ms |
| 50 m | 692.3 ms | 461.5 ms |
| 70 m | 692.3 ms | 461.5 ms |

## Marqueur

- Catégorie : Fusil (Hitscan)
- Coût : 3100 crédits
- Pourquoi : Fusil semi précis, roi du 30-50 m : gros dégâts par tir, chute de dégâts tardive (35-70 m). Puni le mouvement (viser à l'arrêt).

| Distance | TTK corps | TTK tête |
|---|---|---|
| 0 m | 428.6 ms | 285.7 ms |
| 5 m | 428.6 ms | 285.7 ms |
| 10 m | 428.6 ms | 285.7 ms |
| 15 m | 428.6 ms | 285.7 ms |
| 20 m | 428.6 ms | 285.7 ms |
| 30 m | 428.6 ms | 285.7 ms |
| 40 m | 428.6 ms | 285.7 ms |
| 50 m | 428.6 ms | 285.7 ms |
| 70 m | 571.4 ms | 428.6 ms |

## Ravage

- Catégorie : Fusil (Hitscan)
- Coût : 2900 crédits
- Pourquoi : Fusil auto polyvalent, meilleur en 15-30 m : équilibre cadence/dégâts/recul, le pick « sûr » qui reste correct partout.

| Distance | TTK corps | TTK tête |
|---|---|---|
| 0 m | 400.0 ms | 300.0 ms |
| 5 m | 400.0 ms | 300.0 ms |
| 10 m | 400.0 ms | 300.0 ms |
| 15 m | 400.0 ms | 300.0 ms |
| 20 m | 400.0 ms | 300.0 ms |
| 30 m | 500.0 ms | 300.0 ms |
| 40 m | 500.0 ms | 400.0 ms |
| 50 m | 600.0 ms | 400.0 ms |
| 70 m | 600.0 ms | 400.0 ms |

## Fracas

- Catégorie : Fusil à pompe (Shotgun)
- Coût : 1850 crédits
- Pourquoi : Pompe : one-shot garanti jusqu'à 4 m avec tous les plombs, quasi inutile au-delà de 15-18 m. Cadence lente, à réserver au close-quarters.

| Distance | TTK corps | TTK tête |
|---|---|---|
| 0 m | 0.0 ms | 0.0 ms |
| 5 m | 0.0 ms | 0.0 ms |
| 10 m | 833.3 ms | 0.0 ms |
| 15 m | 1666.7 ms | 833.3 ms |
| 20 m | 2500.0 ms | 833.3 ms |
| 30 m | 2500.0 ms | 833.3 ms |
| 40 m | 2500.0 ms | 833.3 ms |
| 50 m | — | — |
| 70 m | — | — |

## Faucheur

- Catégorie : Sniper (Sniper)
- Coût : 4600 crédits
- Pourquoi : Sniper à lunette : one-shot à la tête sur toute sa portée utile, domine au-delà de 50 m. Visée (ADS) la plus lente du jeu (0,38 s) et chargeur le plus petit (5 balles) pour compenser sa puissance.

| Distance | TTK corps | TTK tête |
|---|---|---|
| 0 m | 500.0 ms | 0.0 ms |
| 5 m | 500.0 ms | 0.0 ms |
| 10 m | 500.0 ms | 0.0 ms |
| 15 m | 500.0 ms | 0.0 ms |
| 20 m | 500.0 ms | 0.0 ms |
| 30 m | 500.0 ms | 0.0 ms |
| 40 m | 500.0 ms | 0.0 ms |
| 50 m | 500.0 ms | 0.0 ms |
| 70 m | 500.0 ms | 0.0 ms |

## Éclair

- Catégorie : SMG (Hitscan)
- Coût : 1650 crédits
- Pourquoi : SMG « mobilité » : ADS le plus rapide des deux SMG (0,13 s contre 0,16 s pour le Rafale), portée plus courte que le Rafale. Le pick rush / flank, moins cher.

| Distance | TTK corps | TTK tête |
|---|---|---|
| 0 m | 471.7 ms | 283.0 ms |
| 5 m | 471.7 ms | 283.0 ms |
| 10 m | 566.0 ms | 283.0 ms |
| 15 m | 660.4 ms | 377.4 ms |
| 20 m | 754.7 ms | 377.4 ms |
| 30 m | 849.1 ms | 471.7 ms |
| 40 m | 849.1 ms | 471.7 ms |
| 50 m | 849.1 ms | 471.7 ms |
| 70 m | 849.1 ms | 471.7 ms |

## Semeuse

- Catégorie : Lourde (Hitscan)
- Coût : 3200 crédits
- Pourquoi : Mitrailleuse légère (LMG) : le plus gros chargeur du jeu (100 balles), tir soutenu pour tenir un couloir. Lourde : le rechargement le plus long du jeu (4,2 s).

| Distance | TTK corps | TTK tête |
|---|---|---|
| 0 m | 454.5 ms | 272.7 ms |
| 5 m | 454.5 ms | 272.7 ms |
| 10 m | 454.5 ms | 272.7 ms |
| 15 m | 454.5 ms | 272.7 ms |
| 20 m | 454.5 ms | 272.7 ms |
| 30 m | 454.5 ms | 272.7 ms |
| 40 m | 636.4 ms | 363.6 ms |
| 50 m | 727.3 ms | 454.5 ms |
| 70 m | 818.2 ms | 545.5 ms |

## Percuteur

- Catégorie : Fusil (Hitscan)
- Coût : 3150 crédits
- Pourquoi : Fusil de précision semi-auto (DMR) : tue en 2 têtes à toute distance comme le Magnum, sans la lunette ni le coût du Faucheur — la précision « milieu de gamme ».

| Distance | TTK corps | TTK tête |
|---|---|---|
| 0 m | 465.1 ms | 232.6 ms |
| 5 m | 465.1 ms | 232.6 ms |
| 10 m | 465.1 ms | 232.6 ms |
| 15 m | 465.1 ms | 232.6 ms |
| 20 m | 465.1 ms | 232.6 ms |
| 30 m | 465.1 ms | 232.6 ms |
| 40 m | 465.1 ms | 232.6 ms |
| 50 m | 465.1 ms | 232.6 ms |
| 70 m | 697.7 ms | 232.6 ms |

