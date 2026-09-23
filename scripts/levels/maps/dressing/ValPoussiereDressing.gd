## ValPoussiereDressing.gd
## Val-Poussière dress list (maps-spec-v2.md §6 "Val-Poussière" + design.md
## §8 "Desert"/theme brief "frontier town: shacks, signs, barrels, wrecks,
## water tower"). `sign_fuel`/`shack_awning`-style items from the spec's own
## §3.1 catalogue have no direct model in the real 41-prop manifest, so
## `shop_sign` (an actual manifest prop) stands in for "sign boards", and the
## Kit-built water tower gets a real `water_tower.glb` skin instead of a
## second structure.
##
## Layout reference (`Layouts.val_poussiere()`, read-only): bounds
## (-40,-24)..(40,24), x-mirror. Every entry is `collide = false` — signs
## mounted above 2.6 m, a skin over the already-collidable Kit water tower,
## and loose clutter kept clear of the Hotel/Saloon/Store/Barber/PumpHouse
## footprints.
class_name ValPoussiereDressing
extends RefCounted

const _ADOBE := Color("d08f5a")   # design.md §7 Val-Poussière "Adobe"

static func entries() -> Array:
	var out: Array = []

	# "sign boards above 2.6 m, <=0.3 m proud" on the Hotel/Store facades.
	out.append({"prop": "shop_sign", "pos": Vector3(-21.0, 2.9, -6.3), "rot_y": 0.0, "collide": false})
	out.append({"prop": "shop_sign", "pos": Vector3(21.0, 2.9, -6.3), "rot_y": 0.0, "collide": false})
	out.append({"prop": "shop_sign", "pos": Vector3(-21.0, 2.9, 5.7), "rot_y": 180.0, "collide": false})
	out.append({"prop": "shop_sign", "pos": Vector3(21.0, 2.9, 5.7), "rot_y": 180.0, "collide": false})

	# "water_tower on the Kit tower" — real-model skin at the same position
	# as Layouts' `water_tower` piece (already sitting on PumpHouse's roof).
	out.append({"prop": "water_tower", "pos": Vector3(0.0, 3.0, -19.5), "rot_y": 0.0, "collide": false})

	# "power_pole x4 in the back alley" (the strip between the buildings and
	# the west/east walls).
	out.append({"prop": "power_pole", "pos": Vector3(-36.0, 0.0, -5.0), "rot_y": 0.0, "collide": false})
	out.append({"prop": "power_pole", "pos": Vector3(-36.0, 0.0, 5.0), "rot_y": 0.0, "collide": false})
	out.append({"prop": "power_pole", "pos": Vector3(36.0, 0.0, -5.0), "rot_y": 0.0, "collide": false})
	out.append({"prop": "power_pole", "pos": Vector3(36.0, 0.0, 5.0), "rot_y": 0.0, "collide": false})

	# Wrecks flanking the culvert (design.md §8 "wrecks").
	out.append({"prop": "sedan_wreck", "pos": Vector3(10.0, -1.5, 23.0), "rot_y": 30.0, "collide": false, "tint": _ADOBE})
	out.append({"prop": "sedan_wreck", "pos": Vector3(-10.0, -1.5, 23.0), "rot_y": -30.0, "collide": false, "tint": _ADOBE})

	# Extra drums beside the existing "Barrels" cover piece.
	out.append({"prop": "oil_drum", "pos": Vector3(-23.0, 0.45, 3.5), "rot_y": 0.0, "collide": false})
	out.append({"prop": "oil_drum", "pos": Vector3(23.0, 0.45, 3.5), "rot_y": 0.0, "collide": false})

	# Crate clutter south of the pump house, clear of its 4x3x3 footprint.
	out.append({"prop": "wooden_crate", "pos": Vector3(3.5, 0.0, -17.0), "rot_y": 10.0, "collide": false, "tint": _ADOBE})
	out.append({"prop": "wooden_crate", "pos": Vector3(-3.5, 0.0, -17.0), "rot_y": -10.0, "collide": false, "tint": _ADOBE})

	return out
