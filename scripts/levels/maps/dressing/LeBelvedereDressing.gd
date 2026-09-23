## LeBelvedereDressing.gd
## Le Belvédère dress list (maps-spec-v2.md §6 "Le Belvédère" + brief theme
## "rooftops: water towers, pipes, antennas"). No standalone "antenna" prop
## exists in the manifest (the map's own Kit-built landmarks stay as-is,
## read-only here); water towers and pipes are real manifest props.
##
## Layout reference (`Layouts.le_belvedere()`, read-only): bounds
## (-15,-12)..(15,12), point-symmetric ("p"). Every entry is `collide =
## false`: the water towers are visual skins over the already-collidable Kit
## `water_tower` pieces, the roof pipes are pure atmosphere, and the two
## street-end poles sit on the Street piece (the map's own "punishment lane",
## which stays open on purpose).
class_name LeBelvedereDressing
extends RefCounted

static func entries() -> Array:
	var out: Array = []

	# "water_tower on the Kit tanks" — skin at the same positions as
	# Layouts' own `water_tower` pieces (rot_y 180 on the twin matches
	# maps-spec.md's "twin rot_y π" note for this landmark).
	out.append({"prop": "water_tower", "pos": Vector3(-13.0, 5.0, 9.0), "rot_y": 0.0, "collide": false})
	out.append({"prop": "water_tower", "pos": Vector3(13.0, 5.0, -9.0), "rot_y": 180.0, "collide": false})

	# "power_pole x2 at the street ends".
	out.append({"prop": "power_pole", "pos": Vector3(0.0, 0.0, -11.0), "rot_y": 0.0, "collide": false})
	out.append({"prop": "power_pole", "pos": Vector3(0.0, 0.0, 11.0), "rot_y": 0.0, "collide": false})

	# Roof pipework (theme "pipes"), both roof blocks.
	out.append({"prop": "pipe_valve", "pos": Vector3(-6.0, 5.15, 8.0), "rot_y": 0.0, "collide": false})
	out.append({"prop": "pipe_valve", "pos": Vector3(6.0, 5.15, -8.0), "rot_y": 180.0, "collide": false})
	out.append({"prop": "pipe_straight", "pos": Vector3(-9.0, 5.15, -8.0), "rot_y": 90.0, "collide": false})
	out.append({"prop": "pipe_straight", "pos": Vector3(9.0, 5.15, 8.0), "rot_y": 90.0, "collide": false})

	return out
