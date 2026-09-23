## PortFerrailleDressing.gd
## Port-Ferraille dress list (maps-spec-v2.md §6 "Port-Ferraille" +
## design.md §8 "Port" theme: containers, gantry cranes, bollards, crates,
## lifebuoys). Real prop names only (assets/models/props/manifest.json,
## cargo_ship + wasteland sets) — the spec's own §3.1 catalogue names
## (`bollard`, `tyre_stack`, `crane_lattice`->`gantry_crane`, `power_pole`)
## already match 1:1 or via `PropCatalog.ALIASES`.
##
## Layout reference (`Layouts.port_ferraille()`, read-only): bounds
## (-36,-22)..(36,18), x-mirror. Every entry below is `collide = false`
## (quay-edge/wall dressing, or a visual skin over Kit geometry — GantryLegN/
## S, CapstanHouse — that already owns its own collision).
class_name PortFerrailleDressing
extends RefCounted

const _HULL_TEAL := Color("2e8c86")   # design.md §7 Port-Ferraille "hulls"
const _QUAY_TAN := Color("bba98c")    # design.md §7 Port-Ferraille "Quay"

static func entries() -> Array:
	var out: Array = []

	# "bollard x8 on z -21.8" — north quay edge, inside the water-facing wall
	# (QuayEdge invisible wall sits at z=-22.2).
	for x in [-28.0, -20.0, -12.0, -4.0, 4.0, 12.0, 20.0, 28.0]:
		out.append({"prop": "bollard", "pos": Vector3(x, 0.0, -21.8), "rot_y": 0.0, "collide": false})

	# "tyre_stack fenders" along both quay walls (WestWall / its x-mirror).
	for z in [-15.0, -5.0, 5.0, 15.0]:
		out.append({"prop": "tyre_stack", "pos": Vector3(-35.8, 0.0, z), "rot_y": 90.0, "collide": false, "tint": _HULL_TEAL})
		out.append({"prop": "tyre_stack", "pos": Vector3(35.8, 0.0, z), "rot_y": 90.0, "collide": false, "tint": _HULL_TEAL})

	# "crane_lattice on the gantry legs" -> a gantry_crane trolley riding the
	# existing beam/cab (GantryBeam/CraneCab, centred, not mirrored).
	out.append({"prop": "gantry_crane", "pos": Vector3(0.0, 6.0, -11.0), "rot_y": 0.0, "collide": false, "tint": _HULL_TEAL})

	# "power_pole x2 by the south wall".
	out.append({"prop": "power_pole", "pos": Vector3(-20.0, 0.0, 17.0), "rot_y": 0.0, "collide": false, "tint": _QUAY_TAN})
	out.append({"prop": "power_pole", "pos": Vector3(20.0, 0.0, 17.0), "rot_y": 0.0, "collide": false, "tint": _QUAY_TAN})

	# Extra yard clutter beside the existing YardCrate/YardCrate2 cover.
	out.append({"prop": "wooden_crate", "pos": Vector3(-15.0, 0.0, 9.0), "rot_y": 15.0, "collide": false, "tint": _QUAY_TAN})
	out.append({"prop": "wooden_crate", "pos": Vector3(15.0, 0.0, 9.0), "rot_y": -15.0, "collide": false, "tint": _QUAY_TAN})
	out.append({"prop": "pallet", "pos": Vector3(-6.0, 0.0, 6.0), "rot_y": 0.0, "collide": false})
	out.append({"prop": "pallet", "pos": Vector3(6.0, 0.0, 6.0), "rot_y": 0.0, "collide": false})

	# Lifebuoys on the capstan house walls (design.md §8 "lifebuoys").
	out.append({"prop": "life_ring", "pos": Vector3(1.6, 2.0, -14.5), "rot_y": 90.0, "collide": false, "tint": _HULL_TEAL})
	out.append({"prop": "life_ring", "pos": Vector3(-1.6, 2.0, -14.5), "rot_y": -90.0, "collide": false, "tint": _HULL_TEAL})

	return out
