## ColDuVautourDressing.gd
## Col du Vautour dress list (maps-spec-v2.md §6 "Col du Vautour" + brief
## theme "mountain outpost: sandbags, rocks, antenna, fences"). The map
## already HAS an antenna (Kit's own `antenna` piece, west side, plus a
## `Radar` box east) from `Layouts.col_du_vautour()` — untouched here — so
## this list covers the rest: sandbags, rocks, fences, poles.
##
## Layout reference (`Layouts.col_du_vautour()`, read-only): bounds
## (-38,-25)..(38,25), x-mirror. Every entry is `collide = false`: the
## sandbags sit on the Bunker roof, and Bunker O/Bunker E's own hardpoint
## zones are 10x4x10 boxes CENTRED ON the bunkers — tall enough (y -0.5..3.5)
## to reach the roof at y3 — so a solid prop there would sit inside the
## capture volume. Everything else is loose atmosphere kept off Site A
## "Crête" (18..26 on x) and the Depot/RockA footprints.
class_name ColDuVautourDressing
extends RefCounted

static func entries() -> Array:
	var out: Array = []

	# "corrugated_shed on the Depot" — roof accent, both mirrored depots.
	out.append({"prop": "corrugated_shed", "pos": Vector3(-15.0, 4.55, 10.0), "rot_y": 0.0, "collide": false})
	out.append({"prop": "corrugated_shed", "pos": Vector3(15.0, 4.55, 10.0), "rot_y": 180.0, "collide": false})

	# "sandbag_wall on the bunker roof edges" (Bunker roof top = y3).
	for x in [-11.3, 11.3]:
		for z in [-3.0, 3.0]:
			out.append({"prop": "sandbags", "pos": Vector3(x, 3.275, z), "rot_y": 90.0, "collide": false})

	# "power_pole line on the crest", clear of Site A "Crête" (x 18..26).
	for x in [-34.0, -30.0, 30.0, 34.0]:
		out.append({"prop": "power_pole", "pos": Vector3(x, 3.0, -18.5), "rot_y": 0.0, "collide": false})

	# Rock clutter layered near the existing RockA walls (theme "rocks").
	out.append({"prop": "rock_medium", "pos": Vector3(-15.5, 2.0, -17.0), "rot_y": 40.0, "collide": false})
	out.append({"prop": "rock_medium", "pos": Vector3(15.5, 2.0, -17.0), "rot_y": -40.0, "collide": false})

	# Chainlink fence line near the pine tree-line (theme "fences").
	out.append({"prop": "fence_chainlink", "pos": Vector3(-24.0, 0.0, 17.2), "rot_y": 0.0, "collide": false})
	out.append({"prop": "fence_chainlink", "pos": Vector3(24.0, 0.0, 17.2), "rot_y": 0.0, "collide": false})

	return out
