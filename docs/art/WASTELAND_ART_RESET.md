# Wasteland — remise à plat de l'art (2026-09-24)

Verdict utilisateur : « les modèles dans les maps et le design des maps… on est vachement loin d'un jeu
polish ». Cible visuelle unique : `.orchestrator/refs/wasteland_hero.png` (vue de rue du bas).

## Diagnostic (preuves)

| Cause | Preuve |
|---|---|
| La map est construite en primitives de code | `scripts/levels/maps/layouts/wasteland.gd` pose des `box` ; `Kit.water_tower()` = cylindre + cône + 3 pieds (1 860 tris) |
| Les modèles Tripo payés ne sont pas dans la map | 7 repères `assets/incoming/tripo/studio/wl_*.glb` (texture peinte 2048², 2,4–5,6 k tris, planches/échelle/contreventements) : aucune référence dans `scripts/levels` |
| L'import IA jette la peinture | `tools/blender/ai_restyle.py` : texture IA « jetée », remplacée par UNE couleur de palette, remesh voxel global, un seul « kind » dominant par objet |
| Matières procédurales floues | `assets/textures/painted/*` viennent de `tools/textures/gen_textures.py` (bruit) |

## Décisions

1. **Peinture conservée.** Les assets Tripo d'environnement gardent leur albédo peint (redimensionné, jamais
   quantifié). Le shader `ink_toon` sait déjà lire `albedo_texture`. `ai_restyle.py` reste réservé aux cas où
   une palette plate est voulue.
2. **Bibliothèque de matières peintes à la main** (Nano Banana dans Tripo Studio, rendues raccordables par
   script) qui remplace une par une les textures de `gen_textures.py` sous les MÊMES noms de fichiers : toute
   la géométrie existante en profite sans changer de code.
3. **Hybride géométrie** : l'espace jouable (murs, sols, escaliers, couverts) reste un kit bpy précis pour la
   collision, mais avec du vrai détail (planches une à une, encadrements en retrait, bandeaux, chanfreins) et
   les matières peintes. Repères, épaves, silhouettes de fond = Tripo texturé.
4. **Coin beauté d'abord.** Un tronçon de ~30 m de Grand-Rue amené au niveau final, capturé au cadrage de la
   référence, validé par l'utilisateur en côte à côte AVANT d'étendre à toute la map.

## Budget Tripo (enveloppe ART-74 redistribuée, plafond 1 520 cr)

| Poste | Crédits |
|---|---|
| Matières peintes (planches de 4, 2 images/gén.) | ≤ 240 |
| Enseignes et décalques peints | ≤ 120 |
| Épaves et repères manquants (Smart Mesh + texture) | ≤ 1 160 |

## Tâches

ART-79 (lead, matières) → ART-79B (raccord + remplacement) ; ART-80 (import peint) ; ART-82 (coin beauté,
dépend de 79B + 80) ; puis ART-73/75/77 réutilisent ces briques ; ART-78 exige le côte à côte.
