## LaFosseDressing.gd
## La Fosse dress list (maps-spec-v2.md §6 "La Fosse" + brief theme "quarry:
## rocks, crane, pipes, drums"). All three "Dress:" lines from the spec map
## onto real manifest props via `PropCatalog.ALIASES` (`crane_lattice` ->
## `gantry_crane`, `pipe_run` -> `pipe_straight`) or 1:1 (`tyre_stack`).
##
## Layout reference (`Layouts.la_fosse()`, read-only): bounds ±14,
## point-symmetric ("p": mirror is `(-x, y, -z)`). This is the ONE map in the
## slice with `collide = true` entries — the pit-corner tyre stacks — because
## the brief's rule ("collide=true only where there's already cover of
## similar footprint, or out of the playable lanes") is cleanly checkable
## here: an arena has only two marker kinds (`spawns`, `duel_zone`, per
## maps-spec.md §5 "Markers"), and the corners sit outside both:
##   - duel_zone (0,-3,0) size(6,4,6) -> half-extents 3x3 on x/z; a corner at
##     (5.5,5.5) clears it by 2.5 m even before padding for the prop's own
##     0.6 m bounding radius (tyre_stack footprint 0.9x1.2x0.9).
##   - both spawn pairs sit at x=+-12.5 (team-0 z in [-7,-3], team-1 z in
##     [3,7]) — 7+ m from every corner.
## `tests/maps/test_dressing.gd` checks this arithmetic generically (spawn +
## objective-zone exclusion boxes) rather than re-deriving it by hand.
class_name LaFosseDressing
extends RefCounted

const _OCHRE := Color("c9853f")     # design.md §7 La Fosse "ochre"
const _LIMESTONE := Color("e3d3ae") # design.md §7 La Fosse "Limestone"

static func entries() -> Array:
	var out: Array = []

	# "tyre_stack in the pit corners" — all four corners of PitFloor
	# ((0,-5.5,0) size(12,1,12), top y=-5), 2 base entries + their
	# point-symmetric twins.
	out.append({"prop": "tyre_stack", "pos": Vector3(5.5, -4.4, 5.5), "rot_y": 45.0, "collide": true, "tint": _OCHRE})
	out.append({"prop": "tyre_stack", "pos": Vector3(-5.5, -4.4, -5.5), "rot_y": 45.0, "collide": true, "tint": _OCHRE})
	out.append({"prop": "tyre_stack", "pos": Vector3(5.5, -4.4, -5.5), "rot_y": -45.0, "collide": true, "tint": _OCHRE})
	out.append({"prop": "tyre_stack", "pos": Vector3(-5.5, -4.4, 5.5), "rot_y": -45.0, "collide": true, "tint": _OCHRE})

	# "crane_lattice on the headframes" -> gantry_crane silhouette wrapping
	# the existing Headframe pole (12,5,-12) and its point-symmetric twin.
	out.append({"prop": "gantry_crane", "pos": Vector3(12.0, 0.0, -12.0), "rot_y": 0.0, "collide": false, "tint": _LIMESTONE})
	out.append({"prop": "gantry_crane", "pos": Vector3(-12.0, 0.0, 12.0), "rot_y": 180.0, "collide": false, "tint": _LIMESTONE})

	# "pipe_run under the conveyor" — `collide = false`: the conveyor's open
	# end (x in [-4,4]) IS the map's dive gap (maps-spec.md §3.5 "Movement"),
	# so nothing solid goes anywhere near it; these sit under each conveyor
	# HALF instead (west: x -10..-4, east mirror: x 4..10).
	out.append({"prop": "pipe_straight", "pos": Vector3(-8.0, -0.3, 0.0), "rot_y": 90.0, "collide": false})
	out.append({"prop": "pipe_straight", "pos": Vector3(-6.0, -0.3, 0.0), "rot_y": 90.0, "collide": false})
	out.append({"prop": "pipe_straight", "pos": Vector3(8.0, -0.3, 0.0), "rot_y": 90.0, "collide": false})
	out.append({"prop": "pipe_straight", "pos": Vector3(6.0, -0.3, 0.0), "rot_y": 90.0, "collide": false})

	return out
