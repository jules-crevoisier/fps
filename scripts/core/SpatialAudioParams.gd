## SpatialAudioParams.gd
## Table PURE catégorie -> réglages `AudioStreamPlayer3D` (tâche "son",
## 2026-09-27, point 2 "spatialisation 3D par catégorie") : unit_size,
## max_distance, modèle d'atténuation, filtre de distance (assombrissement),
## panoramique, doppler — une entrée par catégorie de son plutôt qu'un réglage
## unique pour tout le pool 3D partagé (voir Audio._pool3d/`play_at`, qui
## applique cette table à CHAQUE lecture puisque les lecteurs sont réutilisés
## d'un son à l'autre). `apply_to` est le petit applicateur IMPUR (pose les
## propriétés sur un vrai nœud) — tout le reste de ce fichier est pur/testable
## sans arbre de scène.
class_name SpatialAudioParams
extends RefCounted

const _DEFAULT := {
	"unit_size": 1.0,
	"max_distance": 20.0,
	"attenuation_model": 0,  # AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE (évite une dépendance de classe au chargement).
	"attenuation_filter_cutoff_hz": 5000.0,
	"attenuation_filter_db": -24.0,
	"panning_strength": 1.0,
}

## Coup de feu : entendu à travers toute la carte (contrat lead) —
## `max_distance = 0.0` (Godot : aucune coupure de distance, l'atténuation
## seule fait le travail), assombrissement léger par défaut (l'occlusion,
## voir AudioOcclusion, l'assombrit bien plus derrière un mur).
const _GUNSHOT := {
	"unit_size": 1.0, "max_distance": 0.0, "attenuation_model": 0,
	"attenuation_filter_cutoff_hz": 6000.0, "attenuation_filter_db": -18.0, "panning_strength": 1.0,
}
## Pas — portées contrat lead : "~15 m marche" / "~30 m sprint" (repère
## tactique, un sprint s'entend de plus loin qu'une marche prudente).
const _FOOTSTEP_WALK := {
	"unit_size": 1.0, "max_distance": 15.0, "attenuation_model": 0,
	"attenuation_filter_cutoff_hz": 5000.0, "attenuation_filter_db": -20.0, "panning_strength": 1.0,
}
const _FOOTSTEP_SPRINT := {
	"unit_size": 1.0, "max_distance": 30.0, "attenuation_model": 0,
	"attenuation_filter_cutoff_hz": 5000.0, "attenuation_filter_db": -20.0, "panning_strength": 1.0,
}
## Objet lancé en vol (pin/throw/bounce) : petit et proche, portée courte —
## on ne l'entend pas depuis l'autre bout de la carte comme une explosion.
const _GRENADE := {
	"unit_size": 0.5, "max_distance": 22.0, "attenuation_model": 0,
	"attenuation_filter_cutoff_hz": 5000.0, "attenuation_filter_db": -20.0, "panning_strength": 1.0,
}
## Détonation (frag/flash/smoke) : grosse source, entendue à travers toute la
## carte comme un coup de feu (contrat lead), unit_size plus large (champ
## proche moins agressif pour un joueur tout près de l'impact).
const _EXPLOSION := {
	"unit_size": 2.0, "max_distance": 0.0, "attenuation_model": 0,
	"attenuation_filter_cutoff_hz": 6000.0, "attenuation_filter_db": -18.0, "panning_strength": 1.0,
}

## Nom de son (base, sans suffixe de variation/`_far`) -> catégorie de la
## table ci-dessous.
static func category_for_sound(name: String) -> String:
	if name.begins_with("gunshot_"):
		return "gunshot"
	if name.begins_with("footstep_"):
		return "footstep_sprint" if name.contains("sprint") else "footstep_walk"
	if name in ["grenade_pin", "grenade_throw", "grenade_bounce"]:
		return "grenade"
	if name in ["explosion", "flash", "smoke"]:
		return "explosion"
	return "default"

static func params_for(category: String) -> Dictionary:
	match category:
		"gunshot":
			return _GUNSHOT
		"footstep_walk":
			return _FOOTSTEP_WALK
		"footstep_sprint":
			return _FOOTSTEP_SPRINT
		"grenade":
			return _GRENADE
		"explosion":
			return _EXPLOSION
		_:
			return _DEFAULT

## Applicateur IMPUR : pose les réglages de `category` sur un vrai
## AudioStreamPlayer3D (pool partagé, voir Audio.play_at) — doppler
## systématiquement désactivé (aucun de ces sons ne doit décaler de hauteur
## avec la vitesse relative, contrat lead : "doppler off").
static func apply_to(player: AudioStreamPlayer3D, category: String) -> void:
	var p := params_for(category)
	player.unit_size = p["unit_size"]
	player.max_distance = p["max_distance"]
	player.attenuation_model = p["attenuation_model"]
	player.attenuation_filter_cutoff_hz = p["attenuation_filter_cutoff_hz"]
	player.attenuation_filter_db = p["attenuation_filter_db"]
	player.panning_strength = p["panning_strength"]
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
