## SurfaceSound.gd
## Classification PURE de la surface d'un collider (tâche "son", 2026-09-27,
## points 6/7 "impacts/whizz" + "pas sur métal") : convention que l'auteur de
## carte (l'utilisateur, voir CLAUDE.md — il construit lui-même les cartes)
## peut poser EXPLICITEMENT sur n'importe quel collider avec
## `collider.set_meta("surface", "metal")` (ou "concrete"…) — priorité
## absolue sur le nom du nœud. Sans méta : repli sur une heuristique de NOM
## (conteneur/container -> métal, contrat lead) ; "concrete" par défaut sinon
## (dalle/route/rocher — tout ce qui n'est pas explicitement du métal).
class_name SurfaceSound
extends RefCounted

const METAL := "metal"
const CONCRETE := "concrete"

## Mots-clés de nom (déjà en minuscules) qui comptent comme du métal en
## l'absence de méta "surface" — conteneurs de Shipment en premier lieu.
const _METAL_NAME_KEYWORDS := ["container", "conteneur", "metal", "metallique", "tole"]

static func surface_of(collider: Object) -> String:
	if collider == null:
		return CONCRETE
	if collider.has_method("has_meta") and collider.has_meta("surface"):
		var tagged := str(collider.get_meta("surface")).to_lower()
		if tagged != "":
			return tagged
	var n := ""
	if "name" in collider:
		n = str(collider.name).to_lower()
	for kw in _METAL_NAME_KEYWORDS:
		if n.contains(kw):
			return METAL
	return CONCRETE

## Surface -> nom logique du son d'impact (Audio.gd/assets/audio/sfx).
static func impact_sound_for(surface: String) -> String:
	return "impact_metal" if surface == METAL else "impact_concrete"

## Nom de pas de base ("footstep_walk"/"footstep_sprint") + surface -> variante
## métal si besoin ("footstep_metal_walk"/"footstep_metal_sprint") — inchangé
## sur toute autre surface (béton = son historique). Chaîne vide inchangée
## (aucun pas ce tick, voir Audio.footstep_sound_name).
static func footstep_sound_for(base_name: String, surface: String) -> String:
	if base_name == "" or surface != METAL:
		return base_name
	return base_name.replace("footstep_", "footstep_metal_")
