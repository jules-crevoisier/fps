# Déclaration de contenu IA — Steamworks (brouillon)

> Statut : **BROUILLON**, à remplir dans le vrai formulaire Steamworks au moment de la
> création de la fiche produit (aucun app ID n'existe encore, voir `docs/ROADMAP.md`
> P4.1/P6.5). Ce document n'est pas un avis juridique — à revérifier contre la page
> Steamworks en vigueur au moment du dépôt, la politique ayant déjà changé une fois
> (règle réécrite le 16/01/2026, voir `docs/research/06_ai_3d_pipeline.md` §10). Source :
> `docs/research/06_ai_3d_pipeline.md`.

## Pourquoi ce fichier

Steamworks impose, dans le questionnaire de dépôt d'une fiche produit, de déclarer tout
contenu généré par IA intégré au jeu, avec une distinction entre :

- **contenu pré-généré** : produit avant la sortie, revu par l'équipe, figé dans les
  fichiers du jeu (c'est notre seul cas — voir plus bas) ;
- **contenu généré en direct** : produit par un système IA pendant que la personne joue
  (aucun système de ce type dans ce projet — pas d'IA générative embarquée à l'exécution ;
  les bots utilisent `player.input`/du comportement scripté, pas un modèle génératif).

Une case à cocher déclarant l'usage déclenche l'affichage d'un encart « AI Generated
Content Disclosure » sur la fiche magasin, avec le texte que nous fournissons.

## Ce qui est réellement généré par IA dans ce projet

- **Portée** : uniquement la **forme géométrique brute** de certains props/têtes de
  personnage 3D (voir `docs/research/06_ai_3d_pipeline.md` §A6 « garder la forme, jeter
  le rendu »), via une **API payante** (Tripo en principal — voir `docs/AI_TOOLS.md`).
  Optionnellement, des **images de concept 2D** (orthographiques, fond neutre) servant
  d'entrée à cette génération 3D, via un modèle de diffusion local de la liste blanche
  (FLUX.1 schnell ou SDXL — voir `THIRD_PARTY_LICENSES.md` § Contenu généré par IA).
- **Ce qui n'est PAS généré par IA** : le rendu final livré au joueur. Chaque forme IA
  passe par notre pipeline de restylage (nettoyage du maillage, décimation au budget,
  transfert de palette vers nos slots de matière, normales lissées pour l'encrage,
  AO/courbure en couleurs de sommet) puis par le shader `ink_toon`/`Cartoon.gd` — la
  texture et l'éclairage sortis bruts de l'outil IA sont jetés. Aucun texte, dialogue,
  voix, musique ou code n'est généré par IA à ce jour.
- **Aucune IA générative à l'exécution** : rien n'est généré pendant une partie. Tous les
  assets IA sont produits hors ligne, revus visuellement (turntable Blender + capture
  Godot, voir `docs/research/06_ai_3d_pipeline.md` §A6 point 6), puis committés comme
  fichiers statiques (`.glb`) au même titre qu'un asset modélisé à la main.
- **Traçabilité** : chaque asset IA porte une provenance (`<nom>.provenance.json` — outil,
  version, prompt, date, base légale) vérifiée automatiquement par
  `tools/ai3d/licence_check.py` (voir `THIRD_PARTY_LICENSES.md`), qui refuse aussi tout
  usage d'un outil de la liste noire ci-dessous.

## Outils explicitement exclus (jamais utilisés, quelle que soit la voie d'accès)

| Outil | Raison de l'exclusion |
|---|---|
| Hunyuan3D (toutes versions 2.x, y compris via un hébergeur tiers ou blender-mcp) | Licence Tencent qui exclut l'UE, le Royaume-Uni et la Corée du Sud — y compris pour l'*affichage* des sorties |
| FLUX.1 [dev] | Licence non commerciale |
| Qwen-Image-2.1 | Licence de recherche |

`tools/ai3d/licence_check.py` fait échouer le contrôle si une provenance cite l'un de ces
outils, ce qui rend cette déclaration vérifiable en continu plutôt que déclarative sur
l'honneur.

## Brouillon de texte pour l'encart Steam

À adapter aux champs exacts du formulaire Steamworks au moment du dépôt (le nom précis
des champs peut avoir changé) :

> Certains éléments visuels 3D (accessoires de décor, têtes de personnage stylisées) ont
> été amorcés par une génération de forme 3D par IA (service payant, droits commerciaux
> acquis), puis intégralement retravaillés à la main et par nos propres scripts : nettoyage
> du maillage, retopologie/décimation, remplacement complet de la texture et de l'éclairage
> par notre pipeline de rendu peint (cel-shading encré). Aucun contenu n'est généré par IA
> pendant le jeu. Aucun texte, dialogue, voix ou musique n'est généré par IA.

## À faire au moment du dépôt réel

- [ ] Recopier ce texte (ou sa version alors à jour) dans le formulaire Steamworks réel et
      vérifier qu'aucune case du questionnaire n'a changé de sens depuis le 2026-09-24.
- [ ] Vérifier qu'aucun asset livré ne provient d'un plan gratuit Tripo/Meshy qui ne cède
      pas les droits commerciaux (voir `docs/research/06_ai_3d_pipeline.md` §A2) — preuve
      d'achat/abonnement archivée hors du dépôt.
- [ ] Relancer `python tools/ai3d/licence_check.py` sur l'état final des assets livrés et
      obtenir un code de sortie 0 avant tout dépôt de build.
- [ ] Si un usage d'IA générative en direct est ajouté un jour (ex. dialogue de bot par
      LLM), revenir sur ce document : ce cas relève de la case « contenu généré en
      direct », pas « pré-généré », et peut imposer des obligations supplémentaires
      (modération, filtrage) — non couvert ici tant que ça n'existe pas.
