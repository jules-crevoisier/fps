## AudioOcclusion.gd
## Occlusion PURE d'un son positionnel 3D (tâche "son", 2026-09-27, point 3) :
## un raycast auditeur -> source (calque PhysicsLayers.WORLD, throttlé/mis en
## cache par l'appelant — voir Audio._poll_occlusion) donne un résultat brut
## `PhysicsDirectSpaceState3D.intersect_ray` ({} = rien touché) ; ce fichier
## décide seulement CE QUE ce résultat implique pour le mix (assombrissement
## du filtre de distance + atténuation additionnelle, contrat lead
## "-4..-6 dB" / "~1200 Hz"), jamais le raycast lui-même (voir l'« applicateur »
## impur dans Audio.gd, qui reste seul à toucher l'arbre de scène/la physique).
class_name AudioOcclusion
extends RefCounted

## Coupure (Hz) par défaut derrière un mur — assez basse pour assourdir
## nettement (contrat lead) sans devenir un son étouffé au point d'être méconnaissable.
const DEFAULT_OCCLUDED_CUTOFF_HZ := 1200.0
## Atténuation (dB, négatif) par défaut derrière un mur — milieu de la
## fourchette "-4..-6 dB" du contrat.
const DEFAULT_OCCLUDED_VOLUME_OFFSET_DB := -5.0

## Un raycast auditeur -> source a-t-il touché quelque chose (donc source
## occluse) ? `hit` = résultat brut de `intersect_ray` ({} = rayon libre).
static func is_occluded_from_hit(hit: Dictionary) -> bool:
	return not hit.is_empty()

## Coupure (Hz) du filtre de distance à appliquer : `open_hz` (déjà la valeur
## catégorie, voir SpatialAudioParams) si dégagé, `closed_hz` si occlus —
## jamais l'inverse (un son occlus ne doit jamais sonner PLUS clair qu'à
## découvert).
static func occluded_cutoff_hz(occluded: bool, open_hz: float, closed_hz: float = DEFAULT_OCCLUDED_CUTOFF_HZ) -> float:
	return closed_hz if occluded else open_hz

## Atténuation (dB, additive — 0 = aucun effet) à ajouter au volume déjà
## calculé (distance/équipe/etc.) quand la source est occluse.
static func occluded_volume_offset_db(occluded: bool, amount_db: float = DEFAULT_OCCLUDED_VOLUME_OFFSET_DB) -> float:
	return amount_db if occluded else 0.0
