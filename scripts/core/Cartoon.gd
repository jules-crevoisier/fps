## Cartoon.gd
## Direction artistique cartoon : couleurs plates, vives et TOUJOURS lisibles.
## Chaque matériau a un léger plancher d'émission (≈ self-illumination) pour qu'aucune
## surface ne tombe jamais dans le noir total, même mal éclairée — look BD propre.
class_name Cartoon
extends RefCounted

## Matériau cartoon : albédo saturé + plancher d'émission anti-noir.
static func mat(color: Color, _outline: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.metallic = 0.0
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.3
	return m
