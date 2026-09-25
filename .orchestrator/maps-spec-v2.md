# Maps spec v2: Cargo Ship, Wasteland, repaint of the six (P2.7)

Level-design contract, 2026-09-23, transcribed from `.orchestrator/refs/cargo_ship_*.png` and `wasteland_*.png`. A scratch model checked every number: spawn line of sight, 2D sightline caps, 3D perch-to-spawn rays, SnD ratios, gaps, slopes. Build the tables exactly. `maps-spec.md` (v1) applies unless overridden here.

```
goal: Add the user's two flagship maps as pure layout data, and re-dress the six v1 maps with props and painted materials without moving collision.
approach: v1 pipeline (Layouts → Kit → MapSetup). Props are `prop` pieces or a `skin` on a box/container; collision stays Kit. Water is a server kill volume. Wasteland's asymmetry is balanced by measured parity plus a TDM/Hardpoint half-time swap.
rejected: Blender map scenes with baked collision: untestable by the pure layout tests, collision drifts from the navmesh bake.
contract:
- Layouts.cargo_ship() / wasteland() -> v1 dict + {asymmetric, kill_volumes: [{pos,size}], perimeter: [Vector2]}
- piece += {mat?, skin?, solid?}; new piece {type:"prop", prop, pos (floor contact), rot_y (k·π/12), cover?}
- PropCatalog.PROPS: name -> {path, size: Vector3(w,h,d), cover, thin}
files:
- scripts/levels/maps/Layouts.gd — edit — two maps; skin/mat on the six (§6)
- scripts/levels/maps/PropCatalog.gd — create — §3
- scripts/levels/maps/Kit.gd, MapSetup.gd — edit — §7
- scripts/levels/maps/MapCatalog.gd — edit — two entries, `asymmetric`
- scripts/modes/TDMMode.gd, HardpointMode.gd — edit — half-time swap
- scripts/networking/GameWorld.gd — edit, owner R3-IN — safest spawn
- scenes/levels/maps/cargo_ship.tscn, wasteland.tscn — create
- tests/maps/test_layouts.gd, test_navmesh.gd, test_kit.gd — edit; tests/maps/test_props.gd, tests/modes/test_halftime.gd — create
acceptance: §8
order: tdd → build → e2e
risks: §9
done_when: §8 green on eight maps, map_shots of both new maps reviewed, ≤ 150 static draw calls
```

## 1. Reading the sheets

**Cargo Ship.**
- **Kept:** a north–south hull (drawn 48 × 66 m, built 50 × 68 m), two holds split by a spine, the bridge north flanked by stacks, bow stacks, and spawns west/east at the spine ends (the red arrows).
- **Symmetry:** "symmetric" plus "bridge at one end" only works with the centreline as the mirror axis, so the bridge is equidistant. The offset holds were regularised to an x-mirror.
- **Panels:** orange cover became the corner and anchor stacks; green high paths became gangways, island tops and the spine top; sightlines converge on the spine centre (hardpoint 1).
- **Improved:** a chicane container wall on the spine, 3-high spawn shields, and every deck line ≤ 28 m.

**Wasteland.**
- **Scale:** 0.058 m per sheet pixel, 80 × 43 m.
- **Kept, west to east:** the FUEL cross-plaza compound, the water-tower and peaked-shack pair, the crane shed, the north wreck, the derrick rise and its ramp, the GAS courtyard, the warehouse arm, the south rocks, the centre cars.
- **Paths:** the winding main path, plus the north dune and south rim paths.
- **Improved:**
  - The ramp is axis-aligned.
  - Spawn shields are added.
  - Blue's FUEL roof and dune offset red's derrick, and distances are tuned to parity (§5.6).

## 2. Conventions (delta from v1 §2)

- `L12.2/x 2h` means stacked 2 high from the stated floor. `solid` means one collision box instead of the 4–6-body shell.
- `mat` is a painted-material key (§3.2) that overrides `color_key`; the role column shows it. `skin` replaces the visual and keeps Kit collision; scale is 0.8–1.25 per axis. `dress` is visual only and never enters walkable space between y+0.1 and y+2.2 unless `thin`.
- Props rotate in 15° steps. Pieces keep rot_y 0, except skinned vehicles (k·π/2).
- Legend additions: `~` water (kill), `W` wreck, `L` mast. Building letters are named per map. The upper view sits right of the ground view.

## 3. Props and painted materials

### 3.1 Prop catalogue

- Footprints are w × d × h in metres.
- **cover:** a collision box of that size, bottom on the floor. **visual:** no collision.
- `PropCatalog.gd` maps each name to `assets/models/props/<file>.glb`, with aliases for the props builder's names.

| Prop | w×d×h | Role | Used on |
|---|---|---|---|
| container_20 / _40 | 2.44×6.1×2.6 / 2.44×12.2×2.6 | skin | colours rust, slate, ochre, teal, bone; `_open` variant |
| crate_2 / crate_low / crate_stack | 2×2×1.8 / 2×2×1.1 / 1.5×1.5×1.8 | cover | crates |
| barrel_cluster / barrel | 2.4×1.2×1.8 / 0.6×0.6×0.9 | cover / visual | drums |
| pallet_stack / sandbag_wall | 3×5×2.4 / 3×1×1.1 | cover | Port / Col |
| tyre_stack / bollard | 0.9×0.9×1.0 / 0.6×0.6×0.7 | visual, thin | dressing |
| hatch_cover / windlass | 4×3×2.5 / 2.5×2.5×1.4 | cover | Cargo |
| deck_crane | 2×3.5×5.6 + jib | skin | Cargo |
| ship_hull / ship_bridge_dress | 50×68×9 / 12×10×3 | visual | Cargo |
| ship_railing | 4×0.1×1.1 | visual, tiled | bulwarks |
| ship_mast / lifeboat / gangway | 1×1×12 / 2.5×7×2.5 / 1.2×8×4 | visual | Cargo, outboard |
| fuel_pump / canopy_station | 0.8×0.6×1.6 / 7×5.5×0.3 | cover / skin | Wasteland |
| sign_fuel / sign_gas | 0.6×3.5×5 / 6×0.4×2.5 | skin / visual | billboard / roof |
| shack_awning / shack_roof_peak / corrugated_shed | 6×2×0.3 / w×d×1.5 / per wall | visual | door sides at y 2.6, roofs, cladding ≤ 0.1 m proud |
| tank_horizontal / tank_skid / pipe_manifold | 3×5×3.5 / 2×4×3.5 / 3×4×3.5 | skin | tank farm |
| pipe_run / power_pole | 6×0.6×0.6 / 0.4×0.4×9 | visual, thin | walls ≥ 2.4 m, streets |
| water_tower / oil_derrick / crane_lattice | 3.6×3.6×9 / 5×5×16 / 1.6×1.6×16 + 18 m jib | dress | landmarks |
| car_sedan_wreck / car_pickup_wreck | 1.9×4.4×1.4 / 2.1×5.2×1.8 | skin | cars |
| bus_wreck / tanker_wreck | 3×9×3 / 2.5×8×3 | skin | Wasteland |
| freight_wagon / stagecoach / rock_cluster | 2.8×10×3 / 2.6×6×2.8 / per box | skin | Port / Val / rocks |

### 3.2 Painted materials

- **Material:** `Cartoon.world(tint)` with `use_albedo_texture` and `assets/textures/painted/<tex>.png`.
  - The texture is 512², tileable and value-only, box-mapped at 2 m per tile.
  - Chroma stays the tint's (design.md law: decor C ≤ 0.05).
- **Fallback:** a missing texture gives today's flat tint.
- **Batching:** Kit batches by (tint, tex).
- **Textures:** concrete, planks, cobbles, stone, slate, snow, rock, sand, adobe, steel_plate, grating, corrugated, zinc, tile, plaster.

## 4. Cargo Ship — feeder at anchor at dusk, 50 × 68 m, x-mirror on the centreline, bounds (−25,−36)…(25,32)

A container feeder in open water. Spawns sit on the side decks, and two 2.6 m-deep holds are split by a container spine. The bridge stands north and the bow stacks south.
**What makes it different:** overboard kills. Three heights (holds −2.6, deck 0, tops 2.6) plus two perches (bridge roof 6.4, bow perch 5.2). No deck line is over 28 m.
**Palette:**
- floor #8C8A82 steel_plate · wall #5B4F4B steel_plate · cover #8E6E66 rust · platform #5F5C57 grating · accent #D9D4C8 plaster.
- `mat` keys: slate #63707C, ochre #9C8C6C, teal #627A75, bone #BDB5A4, sea #54606A. All C ≤ 0.05.

```
ground (, = hold -2.6)      upper (u 2.6, 2 wing 3.2, R roof 6.4, P perch 5.2)
~~~~~~.C.BBBBBBB.C.~~~~~~   ~~~~~~...RRRRRRR...~~~~~~   z-36 bridge
~~~~~~.C.BBBBBBB.C.~~~~~~   ~~~~~~...RRRRRRR...~~~~~~
~~~~~~.C.BBBBBBB.C.~~~~~~   ~~~~~~...RRRRRRR...~~~~~~
~~~~~~...BBB3BBB...~~~~~~   ~~~~~~...RRRRRRR...~~~~~~
~~~~~~...BBBBBBB...~~~~~~   ~~~~~~2222RRRRR2222~~~~~~
~~~~~~s..BBBBBBB..s~~~~~~   ~~~~~~2222RRRRR2222~~~~~~
~~~~~~s...........s~~~~~~   ~~~~~~s...........s~~~~~~
......soo.......oos......   ......s...........s......   z-22 aft deck
C......oo..===..oo...X..C   .........................
C...C...............C...C   .........................
C...C=======,=======C...C   .........................
C...Crrrrr,,o,,rrrrrC...C   .........................   north hold
....C,,,,CCCCCCC,,,,C....   ....u....uuuuuuu....u....
.ossC,,,,CCCCCCC,,,,Csso.   ..ssu----uuuuuuu----uss..   z-10
....C##,,,,,,,,,,,##C....   ....u...............u....
..##.##,,,,,,,,,,,##.##..   .........................
.a##........o........##b.   .........................
.a##ssCCCCCCCCCCCCCss##b.   ....ssuuuuu###uuuuuss....
.a##ssCCCCCC1CCCCCCss##b.   ....ssuuuuu###uuuuuss....   z0 spine
.a##........o........##b.   .........................
..##.##,,,,,,,,,,,##.##..   .........................
.....##,,,,,,,,,,,##.....   .........................   south hold
....C,,,,CCCCCCC,,,,C....   ....u....uuuuuuu....u....
.ossC,,2,CCCCCCC,4,,Csso.   ..ssu....uuuuuuu....uss..   z10
C...C,,,,,,,s,,,,,,,C...C   ....u.......s.......u....
C...Crrrrr,,s,,rrrrrC...C   ............s............
C...C=======s=======C...C   ............s............
C...C...ooo...ooo...CY..C   .........................   fore deck
........ooo...ooo........   .........................
~~~~..ss.........ss..~~~~   ~~~~..ss.........ss..~~~~   z22 bow
~~~~.=ss.........ss=.~~~~   ~~~~..ss.........ss..~~~~
~~~~.=CCCCCCCCCCCCC=.~~~~   ~~~~..uuu^^PPP^^uuu..~~~~
~~~~~~~~#########~~~~~~~~   ~~~~~~~~uuuuuuuuu~~~~~~~~   z28 forecastle
~~~~~~~~#########~~~~~~~~   ~~~~~~~~uuuuuuuuu~~~~~~~~
```

```
SideDeck      box       (-19.5,-1.55,0)x(11,3.1,44)          floor·M   top 0, hull block to -3.1
AftDeck       box       (0,-1.55,-18.5)x(28,3.1,7)           floor
Spine         box       (0,-1.55,0)x(28,3.1,8)               floor
ForeDeck      box       (0,-1.55,19.5)x(28,3.1,5)            floor
Stern         box       (0,-1.55,-29)x(26,3.1,14)            floor
Bow           box       (0,-1.55,25)x(34,3.1,6)              floor
Forecastle    box       (0,-0.25,30)x(18,5.7,4)              wall      top 2.6
HoldFloorN    box       (0,-3.1,-9.5)x(28,1,11)              plat      top -2.6
HoldFloorS    box       (0,-3.1,10.5)x(28,1,13)              plat      top -2.6
Bulwark       fence h1.1 on every hull edge (forecastle at y2.6) + (-12.2,2.6,28)>(-9,2.6,28)·M   wall  skin ship_railing
Coaming       fence     (-14,0,z)>(-2,0,z)h1, z -15/-4/4/17   plat·M    4 m gap at x 0
HoldRampN     ramp      (-14,0,-13.5)>(-6,-2.6,-13.5)w2.5    plat·M    SLIDE 18°
HoldRampS     ramp      (-14,0,15)>(-6,-2.6,15)w3            plat·M    SLIDE 18°
PedestalN/S   box       (-13,0.2,∓5.75)x(2,5.6,3.5)          wall·M    skin deck_crane
IslandN       container (0,-1.3,-10.72|-8.28) L12.2/x 2h     slate     solid, top 2.6
IslandS       container (0,-1.3,9.28|11.72) L12.2/x 2h       ochre     solid, top 2.6
AnchorN/S     container (-15.32,1.3,-9.5|10.5) L6.1/z        teal·M    solid, top 2.6
LashStair     stairs    (-20.5,0,z)>(-16.54,2.6,z)w2         plat·M    33°, z -9.5/10.5
GangwayN      catwalk   (-14.1,2.6,-9.5)>(-6.1,2.6,-9.5)w2   plat·M    anchor → island
CornerN/S     container (-15.32,1.3,-15.6|16.6) L6.1/z 2h    rust·M    solid
OutboardN/S   container (-23.78,1.3,∓16) L6.1/z 2h           bone·M    solid
Shield        container (-19.22,1.3,0) L12.2/z 3h            rust·M    solid, top 7.8, middle tier slate
SpineMid      container (0,1.3,0) L12.2/x                    ochre     solid, top 2.6
SpineEnd      container (-9.15,1.3,0) L6.1/x                 ochre·M   solid
SpineCap      container (0,3.9,0) L6.1/x                     bone      top 5.2
SpineStair    stairs    (-16.5,0,0)>(-12.2,2.6,0)w2          plat·M    31°
PassCrate     box       (-6,0.9,∓1.97)x(1.5,1.8,1.5)         cover·M   skin crate_stack
PassCrateC    box       (0,0.9,∓3.19)x(1.5,1.8,1.5)          cover     chicane, 1.22 m gaps
ForeStair     stairs    (0,0,17.5)>(0,2.6,12.94)w2           plat      30°, over the trench
BowRow        container (0,1.3,26.78) L12.2/x                slate     solid, top 2.6
BowRowSide    container (-9.15,1.3,26.78) L6.1/x             slate·M   solid
BowPerch      container (0,3.9,26.78) L6.1/x                 rust      solid, top 5.2
BowStair      stairs    (-11,0,21.5)>(-11,2.6,25.56)w2       plat·M    33°
PerchStair    stairs    (-7.5,2.6,26.78)>(-3.05,5.2,26.78)w2 plat·M    30°
Windlass      box       (-14.5,0.7,26)x(2.5,1.4,2.5)         cover·M   skin windlass
Bridge        bld2      (0,3.2,-30)x(12,6.4,10)              acc       f2; doors S0, W0/E0 off -3, W1/E1 off 3.5; windows S; roof_access, parapet 1.0, stair N
WingW         box       (-9.5,3.075,-26.5)x(7,0.25,3)        plat·M    top 3.2
WingRail      fence     (-13,3.2,-28)>(-6,3.2,-28) and >(-13,3.2,-25) h1   wall·M
WingStair     stairs    (-11.5,0,-20.5)>(-11.5,3.2,-25)w2    plat·M    35°
SternStack    container (-10,1.3,-32.9) L6.1/z 2h            teal·M    solid
HatchAft      box       (-8,1.25,-19.5)x(4,2.5,3)            cover·M   skin hatch_cover
HatchFore     box       (-6,1.25,19.5)x(4,2.5,3)             cover·M   skin hatch_cover
HatchPile     box       (0,0.6,-19.5)x(4,1.2,1.6)            cover     skin hatch_cover
DeckCrate     box       (-22.5,0.9,-9.5|10.5)x(2,1.8,2)      cover·M   skin crate_2
Drums         box       (0,-1.7,-13.5|15)x(2.4,1.8,1.2)      cover     skin barrel_cluster
Sea           box       (0,-6.5,-2)x(160,1,160)              sea       visual_only
KillSea       kill      (0,-8,-2)x(160,6,160)                -         y -11..-5
dress: ship_hull (0,-3.1,-2); ship_bridge_dress; ship_mast (0,6.4,-33),(0,2.6,30.5); lifeboat (±14.5,3,-31); gangway (±26,-2,0)
```

**Lanes** (west–east)
- North, aft deck: ≤ 28 m (Ravage). Bridge interior: 6–12 m (Rafale).
- Mid, spine: passages ≤ 17 m (Rafale), wall-top halves ≤ 10 m, hold trenches ≤ 28 m.
- South, fore deck: ≤ 19 m.
- Elevated: bridge roof ↔ bow perch and fore deck, 51–52 m. This is the only Faucheur line.
- Flanks: both hold floors, and the side corridors (x ±14..18).

**Power positions**
- **Bridge roof (6.4).** Sees the aft deck, the north hold and the spine.
  - Counters: one 1.6 m interior ramp; wing stairs into the wheelhouse below.
  - It is blind to the spawns and the corridors (3D-checked), the cap hides the south hold, and the 1.0 m parapet shows heads to the bow perch at 51 m.
- **Bow perch (5.2).** No cover. Answered by the bridge roof and by the bow-row halves 4–9 m away. Two 2 m stairs.
- **Island and spine tops (2.6).** They see each other and the anchors, so none controls a hold.

**Movement**
- **Slide:** four hold ramps (18°, 8 m) from the side decks.
- **Dive:** south island end (x ±6.1) → south anchor (x ±14.1), 8.0 m at 2.6.
  - A sprint jump falls into the hold (h 6.6, 1.0 s stun).
  - Island → spine top is 5.84 m north and 6.84 m south: slide-jump.
- **Stun decision:** bridge roof → deck (h ≈ 7.8, 1.2 s), → wing (0.6 s), a timed roll, or the interior ramps (~5 s).
- **Water:** clearing the 1.1 m bulwark takes a deliberate jump, and it drowns you.

**Markers**
- **Spawns:**
  - Team 0 at (−22.7,1,z) for z −3/−1/1/3. The z < 0 pair looks at (−18,1,−12), the z > 0 pair at (−18,1,12). Team 1 is the mirror.
  - 45.4 m apart; the shields block every pair; no perch sees a spawn.
- **Hardpoints:** 1 Échine (0,1.5,0) → 2 Cale S-O (−10,−1.1,10.5) → 3 Timonerie (0,4.2,−30) → 4 Cale S-E (10,−1.1,10.5). Timonerie's zone (y 2.2–6.2) excludes the roof and the deck.

| Site | Position | Size | Attack | Defence | Ratio |
|---|---|---|---|---|---|
| A (Château) | (18,1.5,−19) | 8×3×6 | 44.9 m (5.5 s) | 19.6 m (2.4 s) | 2.29 |
| B (Proue) | (18,1.5,19) | 8×3×6 | 44.9 m | 19.6 m | 2.29 |

**Modes:** tdm, hardpoint, snd. **Landmarks:** the white bridge (mast, lifeboats), the striped shields, the bow mast, the deck cranes.
**Performance:** 6 Kit materials (containers are skins) and ~23 prop MultiMeshes: ~60 static draw calls, ~180 StaticBody3D.

## 5. Wasteland — desert fuel stop at noon, 80 × 43 m, asymmetric, bounds (−40,−25)…(40,18)

A fuel stop grown into a shanty town. Blue spawns west at the FUEL station, red east at the GAS tank farm, and a derrick stands on the north-east rise.
**What makes it different:** the only asymmetric map, with a winding main road, a derrick rise, a crane and chained roofs.
**Palette:**
- floor #C2B190 sand · wall #8A6F5E planks · cover #7C7F7A corrugated · platform #7E6A56 planks · accent #5E5246 planks.
- `mat` keys: rock #8C7A66, adobe #A68F74. All C ≤ 0.05.

Buildings: F FUEL house, G garage, H shack, E reservoir, K chapel, S crane shed, O GAS office, B blocks, V warehouse.

```
ground                                    upper (R 6.4, u 3.2 / rise 4.5, P 5.6, T overhead)
###################.W.....#######...####  ..........................uuuuuuu.......  z-25
###################.W.....#######...####  ..........................uuuuuuu.......
###################.W.....###X##ssss####  ..........................uuuuuussss....  rise
###################.W.....######ssss####  ..........................uuuuuussss....
###################.W.....rrr.......####  ..........................^^^...........  z-17
###################.L.....rrr.......####  .....^^^^uuuu^^^^^^.......^^^...........  dune
.....rrrr^^^^rrrrrr.SSSS..rrr.......####  .....^^^^uuuu^^^^^^.P^^u..^^^...........  z-13
...FFFF..GGGGEEE....3SSS..rrr.......####  ...RRRR..uuuuuuu....PPuu..^^^...........
...FFFF..GGGGEEE....SSSS..rrr..OOOO.####  ...RRR----uuuuTT....uuuu..^^^..uuuu.....  z-9
...FFFF..GGGGEEE....SSSS..rrBB.OOOO.oo..  ...RRRR..uuuuuTT....uuuu..^^^..uuuu.....
..............s.....s.......BB..s..ooo..  ..............s.....s...........s.......  z-5
......WWWW....sKKK..s..oo...BB..s..oo...  ..............s.....s...........s.......
aa....WWWW...2.KKK..........BB..so....bb  ................................s.......  z-1 street
aa.............KKK..........BB.==o....bb  ........................................
...HHHH............W....VVVVV..o...oo...  .........TTTT...........................  z3 canopy
...HHHH............W....VVVVV..o...oo...  .........TTTT...........................
...HHHH.....#####...1...VVYVV.BBBB......  .........TTTT...........................  z7 (4 = Y)
............#####....WW.VVVVV.BBBB......  ........................................
............#####..........oo...........  ........................................  z11
###################....##..oo.....######  ........................................  rim
###################....##.........######  ........................................
########################################  ........................................  z17
```

```
Ground        box       (0,-1,-3.5)x(80,2,43)                floor     top 0
CliffW/E      box       (∓40.5,3,-3.5)x(1,6,43)              rock      skin rock_cluster
CliffS        box       (0,3,18.5)x(82,6,1)                  rock
MassifNW      box       (-21,3,-19.5)x(38,6,11)              rock      x -40..-2, z -25..-14
CliffN        box       (15.5,3,-25.5)x(35,6,1)              rock
MassifNE      box       (36.5,3,-16.5)x(7,6,17)              rock      x 33..40, z -25..-8
Perimeter     inv_wall  inner faces of the six above, h20    -         NEW
RockS         box       (-11,1.5,10.25)x(9,3,5.5)            rock
RockRimSW     box       (-21.5,1.5,15.5)x(37,3,5)            rock
RockSC        box       (8,1.5,15.5)x(4,3,5)                 rock
RockSE        box       (34,1.5,15.5)x(12,3,5)               rock
FuelHouse     bld2      (-30,3.2,-7.5)x(6,6.4,6)             wall      f2; doors S0, E0, E1; windows S; roof_access, parapet 1.0, stair W
Garage        bld2      (-17.5,1.6,-7.5)x(7,3.2,6)           wall      f1; doors S0 w3, W0; flat roof
FuelPlank     catwalk   (-27,3.2,-7.5)>(-21,3.2,-7.5)w1.5    plat      FUEL F2 → garage roof
Shack         bld2      (-30,1.6,5.5)x(6,3.2,6)              wall      f1; doors N, E; dress shack_awning, shack_roof_peak
CanopyPost    box       (-20.5|-14.5,1.9,3|7.5)x(0.3,3.8,0.3)  acc     4 posts
CanopyRoof    box       (-17.5,3.95,5.25)x(7,0.3,5.5)        acc       skin canopy_station
Pump          box       (-19|-16,0.8,5.25)x(0.8,1.6,0.6)     cover     skin fuel_pump
FuelBillboard box       (-33.5,2.5,-1)x(0.6,5,3.5)           cover     skin sign_fuel; spawn shield, 1.75 m gaps
TankerWreck   box       (-24,1.5,-1)x(8,3,2.5)               cover     skin tanker_wreck
DuneMound     box       (-17.5,1.6,-12.25)x(7,3.2,3.5)       rock      top 3.2 = garage roof
DuneUp        ramp      (-29,0,-12.25)>(-21,3.2,-12.25)w3.5  rock      22°
DuneSlide     ramp      (-14,3.2,-12.25)>(-2,0,-12.25)w3.5   rock      SLIDE 15°
Reservoir     bld2      (-10.5,1.6,-7.5)x(5,3.2,5)           adobe     f1; doors S, W; flat roof
ResStair      stairs    (-11.5,0,-0.5)>(-11.5,3.2,-5)w1.5    plat      35°
WaterTower    water_tower @(-10.5,3.2,-7.5)                  acc       dress water_tower
Chapel        bld2      (-7.5,1.6,0)x(5,3.2,6)               adobe     f1; doors N, S; dress shack_roof_peak
CraneShed     bld2      (3.5,1.6,-9.5)x(7,3.2,8)             cover     f1; doors S, E; flat roof
ShedStairS    stairs    (0.75,0,-1)>(0.75,3.2,-5.5)w1.5      plat      35°, only shed stair
CraneDeck     box       (1.5,5.475,-11.5)x(3,0.25,3)         plat      top 5.6
CraneStair    stairs    (6.5,3.2,-11.5)>(3,5.6,-11.5)w1.5    plat      34°
CraneRail     fence     y5.6 h1 on edges z -13, x 0, z -10   wall
CraneMast     box       (1.5,8,-14.3)x(1.6,16,1.6)           acc       dress crane_lattice
BusWreck      box       (1,1.5,-20)x(3,3,9)                  cover     skin bus_wreck
DerrickRise   box       (19,2.25,-21)x(12,4.5,8)             rock      top 4.5
DerrickRamp   ramp      (15,4.5,-17)>(15,0,-6)w4             plat      SLIDE 22°
RiseStair     stairs    (31,0,-19)>(25,4.5,-19)w2            plat      36.9°
DerrickLeg    box       (20.5|23.5,9.5,-22.5|-19.5)x(0.4,10,0.4)  acc  dress oil_derrick
GasOffice     bld2      (26.5,1.6,-7)x(7,3.2,5)              wall      f1; doors S, W; flat roof; dress sign_gas
OfficeStair   stairs    (24.5,0,0)>(24.5,3.2,-4.5)w1.5       plat      35°
WestBlock     bld2      (18.75,1.6,-2)x(3.5,3.2,8)           wall      f1; doors E, W
Warehouse     bld2      (13,1.6,7)x(8,3.2,8)                 cover     f1; doors W, E, N; dress corrugated_shed
SouthBlock    bld2      (24,1.6,9.5)x(8,3.2,4)               wall      f1; door N; dress shack_awning
TankN/S       box       (31.5,1.75,-3|5)x(3,3.5,5)           cover     skin tank_horizontal; 3 m gap
TankMid       box       (27,1.75,1)x(2,3.5,4)                cover     skin tank_skid
Manifold      box       (34.5,1.75,-6)x(3,3.5,4)             cover     skin pipe_manifold
CourtDrums    box       (24,0.6,2)x(2,1.2,2)                 cover     skin barrel_cluster
CourtCrates   box       (22.5,0.9,5)x(2,1.8,2)               cover     skin crate_2
PlainCrates   box       (8,0.9,-2)x(2,1.8,2)                 cover     skin crate_2
CarSedan      box       (-1,0.7,4.5)x(1.9,1.4,4.4)           cover     skin car_sedan_wreck
CarPickup     box       (4,0.9,9.5)x(5.2,1.8,2.1)            cover     skin car_pickup_wreck, rot π/2
CarBlue       box       (2.5,0.8,13)x(4.4,1.6,1.9)           cover     skin car_sedan_wreck, rot π/2
DockCrates    box       (16,0.9,13)x(3,1.8,2)                cover     skin crate_2
dress: power_pole ×6 on z -3.5 and z 11; pipe_run on the tanks; tyre_stack, barrel by doors
```

**Lanes** (west–east)
- **North:** DuneSlide → north path → BusWreck → ramp foot, ≤ 30 m (Ravage, Marqueur).
- **Mid:** street (spawn → chapel, 30 m) → Épaves ≤ 25 m → warehouse 8 m (Fracas) → courtyard ≤ 12 m (Rafale).
- **South:** plaza south arm → RockS edge → rim strip (z 11.5–18), in segments ≤ 18 m.
- **Elevated:** FUEL roof ↔ rise, 51 m. The only 50+ line, joining the two sides' power positions. FUEL roof ↔ crane is 32 m, crane ↔ rise 20 m.
- **Flanks:**
  - Blue: DuneUp → dune top → DuneSlide.
  - Red: the rim strip.
  - Both: the reservoir → shed dive, the warehouse, the WestBlock passage.

**Power positions**
- **FUEL roof (6.4), blue home.** One interior ramp; flanked by the plank and the garage roof. Blind to the courtyard and the red spawn. Answered by the rise (51 m) and the crane (32 m).
- **Derrick rise (4.5, 96 m²), red forward, site A.** One 4 m slide ramp and a 2 m stair. The crane sees its whole top at 20 m; the only cover is the derrick legs.
- **Crane deck (5.6, 9 m², rails), neutral.** One 1.5 m stair. Seen from the FUEL roof, the rise and the reservoir roof. A dive from the reservoir lands under it.

**Movement**
- **Slide:** DuneSlide (15°, 12 m, blue side) and DerrickRamp (22°, 11 m, red side). Both point at the centre.
- **Dive:** reservoir roof (x −8) → shed roof (x 0), 8.0 m at 3.2 over z −10..−5.5. A sprint jump lands on the ground: 0.6 s stun.
- **Stun decision:** drop off the rise's west edge (h ≈ 5.9, 0.87 s) or slide the ramp (no stun). FUEL roof → plaza costs 1.2 s, against ~4 s of ramps.

**Markers**
- **Spawns:**
  - Team 0: (−36.5,1,±1) and (−38.5,1,±1). The z −1 spawns look at (−33,1,−3.6), the z +1 spawns at (−33,1,1.6).
  - Team 1: (36.5,1,±1) and (38.5,1,±1), looking at (33,1,1).
  - 73 m apart, every pair blocked. Only each team's own roof (FUEL, GAS office, ≤ 14 m) sees its spawn.
- **Hardpoints:** 1 Épaves (0,1.5,7) → 2 Réservoir (−13,1.5,−1) → 3 Grue (1,4.7,−9.5) → 4 Hangar (13,1.5,7). Leanings: neutral, blue, neutral, red. The Grue zone (y 2.7–6.7) holds the shed roof and the crane deck.

| Site (red half) | Position | Size | Attack | Defence | Ratio |
|---|---|---|---|---|---|
| A (Derrick) | (19,6.0,−21) | 8×3×6 | 60.5 m (7.4 s) | 28.4 m (3.5 s) | 2.13 |
| B (Hangar) | (13,1.5,7) | 6×3×6 | 51.0 m (6.2 s) | 25.5 m (3.1 s) | 2.00 |

**Modes:** tdm, hardpoint, snd; `asymmetric: true`. **Landmarks:** the FUEL billboard and canopy, the water tower, the crane, the derrick, the GAS sign and tanks.
**Performance:** 7 Kit materials and ~24 prop types: ~80 static draw calls, ~210 StaticBody3D.

### 5.6 Why the asymmetry is fair

1. **SnD.** Attackers always take side 0 (west) and defenders side 1 (east). After round 6, the existing `RoundState.sides_swapped` and `GameWorld.spawn_side_for` swap the teams' roles, so each team plays both. Target attack win rate: 45–55 % per site.
2. **TDM and Hardpoint.** On an asymmetric map the mode sets `sides_swapped` once, at 50 % of the time limit or when the leader reaches half the score limit, whichever comes first.
   - Living players stay put; the next respawn uses the new side.
   - HUD cartouche: "CHANGEMENT DE CÔTÉ".
   - Every respawn picks the side's point furthest from the nearest living enemy.
3. **Measured parity.** Straight-line here; the tests use navmesh paths (§8.14).

| Metric | Blue | Red | Gap | Limit |
|---|---|---|---|---|
| Spawn → Épaves (first contact) | 38.2 | 38.2 | 0 % | ≤ 8 % |
| Σ spawn → 4 hardpoints | 153.3 | 151.9 | 0.9 % | ≤ 10 % |
| Own leaning hardpoint | 24.5 | 25.5 | 4 % | ≤ 15 % |
| Spawn → crane deck | 40.7 | 37.8 | 7.7 % | ≤ 10 % |
| High-ground index Σ(area × h ≥ 2.5 m) | 522 | 544 | 4 % | ≤ 10 % |

- The index counts:
  - blue: FUEL roof 36 × 6.4, garage roof 42 × 3.2, dune 24.5 × 3.2, reservoir 25 × 3.2;
  - red: rise 96 × 4.5, office 35 × 3.2.
- The shed and crane are neutral.

## 6. Repaint of the six existing maps

Geometry, collision, markers and validation stay identical (§8.16). Each map gets `mat` per palette key (tints unchanged from v1), `skin` on the listed pieces, and `dress`.

- **Port-Ferraille**
  - **Materials:** floor concrete · wall stone · cover steel_plate · platform grating · accent steel_plate.
  - **Skins:**
    - Containers: Tube0 container_40 slate, C1 rust, Perch*/Step container_20 ochre, Shield* container_40 bone/rust.
    - Wagon freight_wagon, PalletStack pallet_stack, CableDrum barrel_cluster.
    - Crates: QuayCrate*, YardCrate2 and SiteACrate crate_low; YardCrate, SiteABox and SiteBBox crate_2; TrenchCrate crate_stack.
  - **Dress:** bollard ×8 on z −21.8, tyre_stack fenders, crane_lattice on the gantry legs, power_pole ×2 by the south wall.
- **Val-Poussière**
  - **Materials:** floor sand · wall planks · cover planks · platform adobe · accent planks.
  - **Skins:** Stagecoach stagecoach, Barrels barrel_cluster, Trough crate_low, Log rock_cluster.
  - **Dress:**
    - shack_awning on the street-side doors; sign boards above 2.6 m, ≤ 0.3 m proud.
    - water_tower on the Kit tower; power_pole ×4 in the back alley.
- **Saint-Ombre**
  - **Materials:** floor cobbles · wall slate · cover steel_plate · platform stone · accent steel_plate.
  - **Skins:** BollardPile barrel_cluster, if within the scale range.
  - **Dress:** bollard ×6 on x 31.5, pipe_run on the mill, barrel by the lock hut.
  - **Stays painted** (no fitting prop): Morris columns, pews, statue.
- **Col du Vautour**
  - **Materials:** floor snow · wall rock · cover planks · platform rock · accent steel_plate.
  - **Skins:** Sandbags sandbag_wall, Crates crate_2, SiteBCrate crate_low.
  - **Dress:** corrugated_shed on the Depot, sandbag_wall on the bunker roof edges, power_pole line on the crest.
- **La Fosse**
  - **Materials:** floor stone · wall rock · cover planks · platform rock · accent steel_plate.
  - **Skins:** RimCrate crate_low, TerraceBlock crate_2, PitBlock barrel_cluster.
  - **Dress:** crane_lattice on the headframes, pipe_run under the conveyor, tyre_stack in the pit corners.
- **Le Belvédère**
  - **Materials:** floor zinc · wall plaster · cover tile · platform zinc · accent steel_plate.
  - **Skins:** none (no vehicle fits the 2×3×1.4 Cart).
  - **Dress:** water_tower on the Kit tanks, power_pole ×2 at the street ends.

## 7. Kit, MapSetup and mode additions (exact API)

1. **PropCatalog.gd.** `const PROPS` and `static func info(name: String) -> Dictionary`. A missing file falls back to a batched box in the `cover` tint, so headless tests need no `.glb`.
2. **Kit.build_piece:**
   - **`prop`:** a cover collision box of `size` at pos + (0, h/2, 0) with rot_y. The visual goes to `PropBatcher`: one MultiMeshInstance3D per mesh, `Cartoon.world`, no outline pass.
   - **`skin`:** today's collision, with the visual scaled into `PropBatcher`. Asserts the scale range.
   - **`solid`:** one box collision.
   - **`mat`:** read `palette[mat]` before `color_key`.
   - **`piece_footprint`:** covers `prop`.
3. **Kill volumes.** MapSetup builds a server-only `KillVolume` Area3D per entry, masked to players.
   - `body_entered` calls `Health.apply_damage(max_health * 10.0, 0)` once, skipping dead players. Killfeed cause: "noyade".
   - The owner's `fall_limit` is set to the volume bottom − 2 as a backstop.
4. **Perimeter.** Invisible walls 20 m high along `perimeter`.
5. **Half-time.**
   - Pure `HalfTime.should_swap(elapsed_s: float, limit_s: float, score_a: int, score_b: int, score_limit: int) -> bool`.
   - `TDMMode` and `HardpointMode` get `var sides_swapped := false`, set once on asymmetric maps and replicated like `RoundMode`.
6. **Safe spawn.** Pure `SpawnPick.safest(points: Array[Vector3], enemies: Array[Vector3], cursor: int) -> int` maximises the distance to the nearest living enemy; ties go to the cursor. Used by `_get_spawn_position`.

## 8. Validation

1–10. **v1 §5, for cargo_ship and wasteland:**
- **Mirror mode:** Cargo "x". Wasteland is covered by §8.14 instead.
- **2D caps:** Cargo x ≤ 30, z ≤ 30 (measured 28.2 / 25.9). Wasteland x ≤ 32, z ≤ 30 (30.0 / 28.5).
- **Physics eye rays (floor + 1.6):** the same caps, except the declared elevated lines, bridge roof ↔ bow and FUEL roof ↔ rise, ≤ 52 m.
- **SLIDE_RAMPS:** HoldRampN/NM/S/SM; DuneSlide, DerrickRamp.
- **DESIGN_GAPS:** (6.1,2.6,10.5) ↔ (14.1,2.6,10.5); (−8,3.2,−7.5) ↔ (0,3.2,−7.5).
- **HEADROOM_PAIRS:** WingW/Stern, GangwayN/HoldFloorN, FuelPlank/Ground, CanopyRoof/Ground.

11. **Kill volumes.**
    - KillSea's top is ≤ −5 and ≥ 2 m below every navmesh polygon; no polygon lies inside it.
    - A player body placed at (0,−7,−40) is dead within 1 s: respawned in TDM, out until round end in SnD.
    - A bot ordered to the stern stays on deck.
12. **Edges.**
    - Every Cargo deck edge and water-facing walkable top has a fence ≥ 1.0 m.
    - Wasteland's perimeter walls reach y 20. No walkable surface plus a 1.4 m jump clears a cliff.
13. **Perch blindness.** 3D rays from the §4/§5 perch eye grids to every spawn ≥ 20 m away are blocked:
    - Cargo: bridge roof, wings, bow perch, spine top, islands, bow row, forecastle.
    - Wasteland: FUEL roof, garage, dune, reservoir, shed roof, crane, rise, office.
14. **Asymmetry (Wasteland), on navmesh paths:**
    - Épaves parity ≤ 8 %; Σ hardpoints ≤ 10 %; leaning pair ≤ 15 %; crane ≤ 10 %.
    - No two adjacent hardpoints lean the same way.
    - High-ground index within 10 %.
    - SnD path ratio 1.5–3.0 at both sites.
15. **Props.**
    - Every name is in PropCatalog; skin scale is 0.8–1.25 per axis; cover collision equals the catalogue size.
    - Visual props never overlap navmesh from y+0.1 to y+2.2 unless `thin`.
16. **Repaint invariance.** A snapshot of every collision shape (type, transform, size) and every marker on the six v1 maps is identical before and after §6.
17. **Performance.**
    - ≤ 150 draw calls in map_shots (Kit, props, zones, sea); ≤ 10 Kit materials.
    - Every prop used 3 or more times is a MultiMesh.
    - ≤ 400 StaticBody3D.
18. **Half-time.**
    - Pure tests for `HalfTime` and `SpawnPick`.
    - A team-0 respawn on wasteland after the swap lands on side 1.
    - Symmetric maps never swap.
19. **Catalogue.** MapCatalog lists both maps with [tdm, hardpoint, snd], size 4v4; `asymmetric` is true only on wasteland.

## 9. Risks

- **Chroma.** The sheets' red and blue containers and signs are held at C ≤ 0.05 (design.md §3) so they never read as team colours. Ask the user before raising them.
- **Straightened shapes.** The diagonal derrick ramp and the offset holds were straightened. Diagonals need oriented footprints in the 2D tests.
- **Faucheur lines.** The two 51 m lines are deliberate; watch the Faucheur pick rate.
- **Wasteland balance.** Track the per-site SnD win rate and how the TDM swap feels. If the FUEL roof dominates, lower its parapet to 0.6.
- **Prop names.** They may drift from the builder's files. PropCatalog aliases absorb this, and unknown names fail §8.15.
- **Kill-volume latency.** The server Area3D sees the replicated position, so a laggy client may drown late.
