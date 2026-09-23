## SaintOmbreDressing.gd
## Saint-Ombre dress list (maps-spec-v2.md §6 "Saint-Ombre" + brief theme
## "old town at night: pipes, power poles, crates, lamps from existing kit").
## No standalone "lamp" prop exists in the 41-prop manifest — the brief's
## "lamps from existing kit" is read as leaning on Kit's OWN silhouettes
## (BellTower, LockHut, the viaduct piers), which this slice cannot touch
## (`Kit.gd`/`Layouts.gd` are read-only here); pipes/poles/crates below are
## real manifest props standing in for the rest of that theme.
##
## Layout reference (`Layouts.saint_ombre()`, read-only): bounds
## (-32,-26)..(32,26), z-mirror (unlike the other four maps, which mirror on
## x). Every entry is `collide = false` — wall-mounted pipes, a quay-edge
## bollard row, and loose clutter kept clear of Mill/LockHut/BollardPile.
class_name SaintOmbreDressing
extends RefCounted

static func entries() -> Array:
	var out: Array = []

	# "bollard x6 on x 31.5" along the canal edge, skipping z=0 (LockHut/
	# BollardPile already sit there).
	for z in [-20.0, -12.0, -4.0, 4.0, 12.0, 20.0]:
		out.append({"prop": "bollard", "pos": Vector3(31.5, 0.0, z), "rot_y": 0.0, "collide": false})

	# "pipe_run on the mill" along its east wall (Mill: (11.5,4.5,-11)
	# size(17,9,10), east face x=20 — both mirrored mills at z=-11 and z=11).
	for z in [-14.0, -11.0, -8.0, 8.0, 11.0, 14.0]:
		out.append({"prop": "pipe_straight", "pos": Vector3(20.3, 6.0, z), "rot_y": 0.0, "collide": false})

	# "barrel by the lock hut" (LockHut: (23,1.5,0) size(6,3,4), single/
	# centred — not mirrored).
	out.append({"prop": "oil_drum", "pos": Vector3(26.4, 0.45, 0.0), "rot_y": 0.0, "collide": false})

	# Power poles flanking the tunnel-ramp entrance (theme "power poles").
	out.append({"prop": "power_pole", "pos": Vector3(-10.0, 0.0, -17.0), "rot_y": 0.0, "collide": false})
	out.append({"prop": "power_pole", "pos": Vector3(-10.0, 0.0, 17.0), "rot_y": 0.0, "collide": false})

	# Crates beside the bollard pile (theme "crates").
	out.append({"prop": "wooden_crate", "pos": Vector3(27.0, 0.0, -3.0), "rot_y": 20.0, "collide": false})
	out.append({"prop": "wooden_crate", "pos": Vector3(27.0, 0.0, 3.0), "rot_y": -20.0, "collide": false})

	return out
