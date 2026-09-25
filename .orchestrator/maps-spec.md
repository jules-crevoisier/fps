# Maps spec: six distinct layouts (P2.6)

Level-design contract, 2026-09-23. Every number was checked in a scratch model: spawn line of sight, spawn distance, SnD ratios, arena symmetry, longest sightlines. Build the tables exactly; invent nothing.

```
goal: Replace the shared skeleton in Layouts.gd with six hand-authored layouts that read as places and play differently.
approach: Pure data, one static func per map, pieces and markers exactly as tabled. 4v4 maps mirror-symmetric (x; z for Saint-Ombre), SnD dressing on the defender half. Arenas point-symmetric. Five small Kit additions.
rejected: Hand-placed .tscn now. Not purely testable. Export to scenes after playtest.
contract:
- Layouts.<id>() -> {id, name, palette{floor,wall,cover,platform,accent}, pieces, spawns{0:[{pos,look}],1:[..]}, hardpoints (rotation order), site_a/site_b{pos,size}, duel_zone{pos,size}, bounds{min,max}}
- piece: {type,name,color_key, pos+size | start+end+width[,height,steps,thickness], axis?, ends_open?, floors?, doors?, windows?, roof_access?, parapet?, slit?, visual_only?}
files:
- scripts/levels/maps/Layouts.gd — edit — six layouts; delete skeleton_4v4/skeleton_duel
- scripts/levels/maps/Kit.gd — edit — §4
- scripts/levels/maps/MapSetup.gd — edit — accent key, visual_only
- tests/maps/test_layouts.gd, test_kit.gd, test_navmesh.gd — edit — §5
- scripts/networking/GameWorld.gd — edit, 1 line, owner R3-IN — SnD spawn by role (§4.6)
acceptance: §5 per map
order: tdd → build → e2e
risks: §6
done_when: §5 green on six maps, map_shots reviewed, ≤ 120 draw calls
```

## 1. Principles (research)

- **Lanes and chokes.** One choke per lane; no single spot covers every choke. Mix short and long sightlines. Keep cover light, because abilities add their own. Add verticality only where the mechanics use it. Sources: [LDB Map balance](https://book.leveldesignbook.com/process/combat/balance), [LDB Flow](https://book.leveldesignbook.com/process/layout/flow).
- **Keep power positions, give each a counter.** Use climbable buildings and the space between them as routes. Source: [Activision, Smith & Cecot, MW 2019](https://blog.activision.com/call-of-duty/2019-08/Modern-Warfare-Multiplayer-First-Look-Creating-Multiplayer-Maps).
- **Off-site power positions that drop onto objectives, and one landmark per district.** Source: [Riot, The Creation of Split](https://playvalorant.com/en-us/news/dev/the-creation-of-split/).
- **Readability.** Players must answer where am I, where do I go, how do I get there. Source: [Pascal Luban](https://www.gamedeveloper.com/design/multiplayer-level-design-in-depth-part-2-the-rules-of-map-design).
- **Movement shooters.** Lanes are momentum roads that converge on intersections. Source: [William Wells, Titanfall 2](https://www.linkedin.com/pulse/how-titanfall-2s-multiplayer-level-design-gets-you-moving-wells). Here that means a slide ramp from every spawn, dive gaps as risky shortcuts, and drops where the stun is a real choice.

## 2. Conventions (all maps)

- **Axes.** Metres, x east, z south (north = −z), y up, origin at the centre. Every piece has rot_y 0. Containers take `axis`; buildings list door sides.
- **`·M` (mirror).** Also place the twin at (−x,y,z) on Port, Val and Col; at (x,y,−z) on Saint-Ombre; at (−x,y,−z) in the arenas. Mirror both endpoints of ramps, stairs, catwalks and fences, and mirror door sides (E↔W, N↔S).
- **Table format:** `name type centre x size | start>end w/h role notes`. Roles map to palette keys (`plat` = platform, `acc` = accent). `bld2` = Kit `building2` (§4); `f1`/`f2` = 1 or 2 floors. `L12.2/z` = container length and axis.
- **Movement** (defaults, ballistic):
  - A sprint jump rises 1.36 m and covers 5.9 m flat.
  - A dive covers 10.4 m flat, 11.5 m with a 0.9 m drop.
  - A slide-jump at 12 m/s covers 8.6–9.1 m.
  - **GAP = 8.0 m flat:** a dive clears it, a max slide-jump barely clears it, a sprint jump fails.
- **Stun.** Fall stun = 0.5 + 2·clamp((h−4)/10, 0, 1) s, with h measured from the air peak. Dive landings roll, so they never stun.
- **Heights.**
  - Jumpable ledge ≤ 1.0 m. Low cover 1.0–1.2 m. Full cover ≥ 1.8 m.
  - **Players have no step-up.** Any rise over 0.15 m needs a ramp or a ≤ 1.0 m jump.
  - Headroom ≥ 2.2 m.
- **Slopes.** Slide ramps 11–27°. Walkable ≤ 37°. The navmesh bakes up to 46°.
- **Markers.**
  - Spawn y = floor + 1; `look` is the point the spawn faces.
  - Hardpoint y = floor + 1.5, in a 10×4×10 zone. Site y = floor + 1.5.
  - SnD: team 0 attacks, team 1 defends, and both sites sit on the team-1 half.
- **Accent colours** (a new palette key; OKLCH C ≤ 0.05): Port #3E4843, Val #6B5A48, Saint-Ombre #2F3439, Col #4A4741, Fosse #4C4740, Belvédère #6A6461.
- **ASCII legend** (1 char = 2 m, north at the top):
  - Ground: `.` y0 · `,` sunken · `:` terrace · `t` tunnel below.
  - Cover: `#` solid ≥ 2.4 m · `o` cover ≥ 1.8 m · `=` low cover · `C` container · `W` wagon · letters = enterable buildings.
  - Routes and props: `r` ramp · `s` stairs · `-` deck · `|` fence · `n` culvert · `L` pole · `~` water.
  - Markers: `a`/`b` spawns · `X`/`Y` sites · `1–4` hardpoints · `Z` duel zone.
  - Upper level: `u` walkable top · `^` slope · `P` dive-only perch · `R` roof with parapet · `2` second floor · `T` overhead, not walkable.

## 3. The maps

### 3.1 Port-Ferraille — foggy docks, 72 × 40 m, x-mirror, bounds (−36,−22)…(36,18)

A gantry crane straddles a container yard, and a freight-rail trench cuts the south. Water lies north of z −22.
**What makes it different: three decks.** Trench at −2.5, yard at 0, crane rail at 6.0. You slide through the container tubes, and no line is longer than 36 m.

```
...............o....o..=............   z-22 (quay edge, water beyond)
.....==........o....o........==.....
..........==...o.##.o...=X..........
..........==.....##.....==o.........
.................##.................
......ssss........3.......ssss......   crane rail overhead z-12.5..-9.5
....................................
.........CCCCCC......CCCCCC.........
..a..C...........CC...........C...b.
.....C...........CC...........C.....
..a..C......CC...C1...CC......C...b.
..a..C......CC...CC...CC......C...b.
.....C......CC...CC...CC......C.....
..a..C......CC...CC...CC......C...b.
.........o.....=....=.....o.........
.................oo.................
.rrrrrr,,=,,,,,,===,,,,,,,=,,rrrrrr.   trench y-2.5
.rrrrrr,,,,WWWWWW,,WWWWWW,,,,rrrrrr.
.rrrrrr,,,,W2WWWW,,WWWWWY,,,,rrrrrr.
.rrrrrr,,,,,,,,,,==,,,,,,,,=,rrrrrr.   z18 south wall
upper (y 2.6–11):
.........TTTTTTTTTTTTTTTTTT.........   gantry beam y11, rail deck y6 below it
......sssTTTTTTTTTTTTTTTTTTsss......
.........TTTTTTTTTTTTTTTTTT.........
.........uuuuuu......uuuuuu.........   C1 tops 2.6
.....#...........uu...........#.....   shields 5.2, Tube0 top 2.6
.....#......uP...uu...Pu......#.....   P perch 5.2 (dive-only), u Step 2.6
```

```
Ground        box       (0,-1.75,-6)x(72,3.5,32)           floor     top 0
TrenchFloor   box       (0,-3,14)x(44,1,8)                 floor     top -2.5
RampFill      box       (-35,-1.75,14)x(2,3.5,8)           floor·M
TrenchRamp    ramp      (-34,0,14)>(-22,-2.5,14)w8         plat·M    SLIDE 11.8°
SouthWall     box       (0,2,18.5)x(72,9,1)                wall      warehouse facades
WestWall      box       (-36.5,1.75,-2)x(1,10.5,40)        wall·M
QuayEdge      inv_wall  (-36,0,-22.2)>(36,0,-22.2)h8       -         NEW
Water         box       (0,-2.5,-30)x(80,1,16)             wall      visual_only
CapstanHouse  box       (0,1.5,-14.5)x(3,3,5)              wall
PalletStack   box       (-5,1.2,-19.5)x(3,2.4,5)           cover·M   chicane w/ CapstanHouse (2 m gaps)
QuayCrate     box       (-14,0.55,-16)x(2,1.1,2)           cover·M
QuayCrate2    box       (-24,0.55,-19)x(2,1.1,2)           cover·M
RailDeck      box       (0,5.875,-11)x(32,0.25,3)          plat      top 6.0
RailN         fence     (-16,6,-12.45)>(16,6,-12.45)h1     wall
RailS1        fence     (-16,6,-9.55)>(-10.5,6,-9.55)h1    wall·M    gap |x| 7.5–10.5 = dive gate
RailS2        fence     (-7.5,6,-9.55)>(0,6,-9.55)h1       wall·M
RailStairs    stairs    (-24,0,-11)>(-16,6,-11)w2.5        plat·M    12 steps, ramp collision 37°
GantryLegN    box       (-16.6,5.5,-12.8)x(0.6,11,0.6)     acc·M
GantryLegS    box       (-16.6,5.5,-9.2)x(0.6,11,0.6)      acc·M
GantryBeam    box       (0,11.3,-11)x(34,0.6,4)            acc       landmark
CraneCab      box       (0,9.5,-11)x(4,2.5,4)              acc       2.25 m clear over deck
Jib           box       (0,11.3,-20)x(1.2,0.6,14)          acc       over water
Tube0         container (0,1.3,-0.5) L12.2/z               cover     ends_open 2
C1            container (-12,1.3,-7.5) L12.2/x             cover·M   ends_open 2, under-rail tube
PerchLow      container (-9,1.3,2.05) L6.1/z               cover·M   closed
PerchHigh     container (-9,3.9,2.05) L6.1/z               cover·M   closed, top 5.2, dive-only
Step          container (-11.44,1.3,2.05) L6.1/z           cover·M   closed, top 2.6
PlankRamp     ramp      (-17,0,2.05)>(-12.66,2.6,2.05)w1.5 plat·M    31°
ShieldLow     container (-25,1.3,0) L12.2/z                cover·M   closed
ShieldHigh    container (-25,3.9,0) L12.2/z                cover·M   closed, spawn shield 5.2
YardCrate     box       (-17,0.9,7.5)x(2,1.8,2)            cover·M
YardCrate2    box       (-5,0.55,7.5)x(2,1.1,2)            cover·M
Bollard       box       (0,1.2,9)x(2,2.4,2)                cover     blocks lip line
Wagon         box       (-8,-1,14)x(10,3,2.8)              cover·M   top 0.5, hop from lip
StepHigh      box       (0,-1.5,11)x(2,2,2)                cover     trench exit, rises 1.0
StepLow       box       (-2,-2,11)x(2,1,2)                 cover
CableDrum     box       (0,-1.6,16.8)x(2,1.8,2.4)          cover
SignalBoard   box       (0,1.75,14)x(0.4,2.5,8)            acc       y0.5–3 over trench, walk under
TrenchCrate   box       (-17,-1.9,11.2)x(1.6,1.2,1.6)      cover·M
SiteACrate    box       (11,0.6,-20.5)x(3,1.2,1.5)         cover
SiteABox      box       (17,1,-15)x(2,2,2)                 cover
SiteBBox      box       (19,-1.5,16.5)x(2,2,2)             cover
```

**Lanes**
- North quay: lines ≤ 31 m, Ravage.
- Mid yard: ≤ 18 m, tubes 12 m, Rafale and Fracas.
- South trench: ≤ 36 m, broken by the wagons.
- Flanks: the C1 tube under the rail, and hops across the wagon tops.

**Power positions**
- **Rail (6.0).** Overlooks the quay and the yard. Counters: exposed on every side; two 2.5 m stair chokes; C1 runs underneath unseen; the perch shoots it level from 8.5 m.
- **Perch (5.2), dive-only.** Counters: no cover, and it is seen from the rail and the far perch (18 m).

**Movement**
- **Slide:** two trench ramps, 12 m each, and slide-throughs in Tube0 and C1.
- **Dive:** from the rail gate to the perch, 8.5 m out and 0.8 m down. A sprint jump reaches only 6.7 m and ends in a 6.1 m fall.
- **Stun decision:** drop from the rail to the ground (0.9 s) or to the Step container (no stun).

**Markers**
- **Team 0 spawns:** (−32,1,−4.5) and (−32,1,−1.5), looking at (−24,1,−14); (−32,1,1.5) and (−32,1,4.5), looking at (−22,1,12).
- **Team 1 spawns:** the mirror.
- **Spawn safety:** the shields and Tube0 block every pair; spawns are 64 m apart.
- **Hardpoints:** 1 Conteneur (0,1.5,−0.5) → 2 Tranchée O (−12,−1.2,14) → 3 Rail (0,7.5,−11) → 4 Tranchée E (12,−1.2,14).
- **SnD sites** (distances straight-line):

| Site | Position | Size | Attack | Defence | Ratio |
|---|---|---|---|---|---|
| A (quay) | (14,1.5,−17) | 8×3×8 | 49 m (6.0 s) | 25 m (3.0 s) | 1.98 |
| B (trench) | (12,−1,14) | 8×3×8 | 46 m | 25 m | 1.89 |

**Landmarks:** the gantry beam and cab, the striped spawn stacks, the jib.

### 3.2 Val-Poussière — frontier town at noon, 80 × 48 m, x-mirror, bounds (−40,−24)…(40,24)

A sun-bleached main street between false fronts, with corrals to the north and a dry arroyo to the south.
**What makes it different:** the map's only sniper lane (the 56 m main street), two-floor enterable buildings with roof routes, and an arroyo for sliding.
Buildings: B = stable/barber, H = hotel, S = saloon, K = store (the Bank on the east side).

```
.................|....|.................   z-24 corrals, pump house + water tower
.................|.##.|.................
...................##...................
.................|....|.................
.......HHHHH.SSSSS....SSSSS.HHHHH.......
.......HHHHH.SSSSS....SSSSS.HHHHH.......
.......HHHHH--S2SS....SS4S--HHHHH.......
.......HHHHH.SSSSS....SSSSS.HHHHH.......
...BBB.HHHHH.SSSSS....SSSSS.HHHHH.BBB...
.a.BBB......==............==......BBB.b.   main street z-6..6
...BBB............................BBB...
.a.BBB............oooo............BBB.b.
...BBB............oo1o............BBB...
.a.BBB............................BBB.b.
...BBB............................BBB...
.a.BBB.KKKKK.BBBBB....BBBBB.KKKKK.BBB.b.
.......KKKKK.BBBBB....BBBBB.KKKKK.......
.......KKKKK--BBBB....BBBB--KXKKK.......
.......KKKKK.BBBBB....BBBBB.KKKKK.......
.......KKKKK.BBBBB....BBBBB.KKKKK.......
.......rrrrrr,,,,,....,,,,,rrrrrr.......   arroyo y-3
.......rrrrrr,,,,,nnnn,,,,,rrrrrr.......
.......rrrrrr,,,,,nn3n,,,,,rYrrrr.......
.......rrrrrr,,==,....,==,,rrrrrr.......
upper: R hotel roof 6.4 (parapet); u saloon/barber/stable roofs 3.2; 2 store F2 3.2; - planks 3.2
.......RRRRR.uuuuu....uuuuu.RRRRR.......   8 m gap between saloon roofs = dive gap
.......RRRRR--uuuu....uuuu--RRRRR.......
.......22222--uuuu....uuuu--22222.......   8 m gap between barber roofs = dive gap
```

```
Ground        box       (0,-1.75,-4)x(80,3.5,40)           floor     top 0
ArroyoFloor   box       (0,-3.5,20)x(28,1,8)               floor     top -3
ArroyoRamp    ramp      (-26,0,20)>(-14,-3,20)w8           plat·M    SLIDE 14°
ArroyoFill    box       (-33,-1.75,20)x(14,3.5,8)          floor·M
SouthWall     box       (0,1.5,24.5)x(80,9,1)              wall      mesa cliff
NorthWall     box       (0,3,-24.5)x(80,6,1)               wall
WestWall      box       (-40.5,2.5,0)x(1,11,49)            wall·M
Stable        bld2      (-31,2,0)x(6,4,14)                 wall·M    f1, doors W+E (spawn→street)
Hotel         bld2      (-21,3.2,-11)x(10,6.4,10)          wall·M    f2, roof_access, parapet 1.0, doors S+N, F2 door E
Saloon        bld2      (-8.5,1.6,-11)x(9,3.2,10)          wall·M    f1, flat roof no parapet, doors S+N
HotelPlank    catwalk   (-16,3.2,-11)>(-13,3.2,-11)w1.5    plat·M    hotel F2 → saloon roof
Store         bld2      (-21,3.2,11)x(10,6.4,10)           wall·M    f2, no roof access, doors N+S, F2 door E; east = Bank
Barber        bld2      (-8.5,1.6,11)x(9,3.2,10)           wall·M    f1, flat roof, doors N+S
StorePlank    catwalk   (-16,3.2,11)>(-13,3.2,11)w1.5      plat·M    store F2 → barber roof
Stagecoach    box       (0,1.4,0)x(6,2.8,2.6)              cover     breaks the street centre
Trough        box       (-14,0.5,-4.8)x(3,1,1)             cover·M
Barrels       box       (-24,0.6,4.8)x(1.2,1.2,1.2)        cover·M
PumpHouse     box       (0,1.5,-19.5)x(4,3,3)              wall
WaterTower    water_tower @(0,3,-19.5)                       acc       on PumpHouse, landmark
CorralA       fence     (-5,0,-24)>(-5,0,-20.5)h1.6        wall·M    chicane
CorralB       fence     (-5,0,-18)>(-5,0,-16)h1.6          wall·M
EmbankN       box       (0,-1.5,17.25)x(6,3,2.5)           floor     top 0
EmbankS       box       (0,-1.5,22.75)x(6,3,2.5)           floor     top 0
CulvertRoof   box       (0,-0.3,20)x(6,0.6,3)              floor     culvert z18.5–21.5, 2.4 m clear
Palisade      box       (0,1.5,20)x(0.3,3,8)               wall      blocks the arroyo overview
Log           box       (-8,-2.4,22.5)x(4,1.2,1.5)         cover·M
```

**Lanes**
- North back alley and roofs: ≤ 31 m (the corral chicane).
- Main street: 56 m along z ±2..6, Faucheur.
- Arroyo: about 41 m through the culvert.
- Flanks: through the stables, the planks and roofs, and the culvert.

**Power positions**
- **Hotel roof (6.4).** Covers the whole street. Counters: one stair choke; the opposite hotel, and the store/Bank floor-2 windows at 22 m; the stagecoach splits the street; the back-alley N door.
- **Saloon roofs.** Counter: exposed to both hotels.

**Movement**
- **Slide:** two arroyo ramps.
- **Dive:** saloon to saloon and barber to barber, 8 m at 3.2 m. A failed sprint jump means a 0.6 s stun.
- **Stun decision:** hotel roof to the street (1.3 s) versus about 5 s of stairs.

**Markers**
- **Spawns:** x ∓37, z −6/−2/2/6, looking at (∓28,1,z). The stables block every pair; spawns are 74 m apart.
- **Hardpoints:** 1 Diligence (0,1.5,0) → 2 Saloon O (−8.5,1.5,−11) → 3 Ponceau (0,−1.5,20) → 4 Saloon E (8.5,1.5,−11).
- **SnD sites:**

| Site | Position | Size | Attack | Defence | Ratio |
|---|---|---|---|---|---|
| A (Banque, inside) | (19,1.5,11) | 6×3×6 | 57 m (7.0 s) | 21 m (2.6 s) | 2.70 |
| B (arroyo ramp) | (16,−1,20) | 8×3×6 | 57 m | 29 m | 1.95 |

**Landmarks:** the water tower (y 12), the hotel roofs, the stagecoach.

### 3.3 Saint-Ombre — rainy industrial old town, 64 × 52 m, z-mirror (team 0 north), bounds (−32,−26)…(32,26)

Wet cobbles, a church square with a memorial, a mill, and a broken rail viaduct over the canal quay.
**What makes it different:** kinked streets (nothing over 34 m), a tunnel under the square as the flank, and a viaduct with an 8 m break. The fight runs north–south.
Buildings: B = atelier, E = church.

```
###########....................~   z-26, team 0 spawn yard
###########.........a.aa.a.s...~
###########................s...~
###................o.......s...~   Rue Haute z-20..-16, Morris columns
###...................o....s...~
###...BBBBBBr|...#########.....~
###...BBBBBBr|...#########.....~
###...BBBBBBr|...#########...2.~   r = tunnel ramp (slot x-9..-5)
###...BBBBBBr|...#########.....~
###...BBBBBBr|...#########.....~
###........ttt......EEEEEE...o.~   square + annex z-6..6
###........ttt......EEEEEE.....~
######.....#######..EEEEEE###.oo   plinth/statue, lock hut, bollards
######.....#3#1###..EEEEEE###.oo
###........ttt......EEEEEE.....~
###........ttt......EEEEEE...o.~
###...BBBBBBr|...#########.....~
###...BBBBBBr|...#########.....~
###...BBBBBBr|...#########.....~
###...BBBBBBr|...#########...X.~
###...BBBBBBr|...#########.....~
###..Y................o....s...~
###................o.......s...~
###########................s...~
###########.........b.bb.b.s...~
###########....................~
upper: 2 atelier F2 3.2; - viaduct/tribune/balcony 4.5; ^ nave ramps; T bell tower
...........................s.--.   viaduct N half z-22..-4
......222222.................--.
....................^^^^^....--.
...................--...........   balcony x6..8 + tribune x8..10, y4.5
...................--...T.......   8 m viaduct gap z-4..4 (x26..30)
```

```
GroundW       box       (-20.5,-2,0)x(23,4,52)             floor     top 0
GroundE       box       (10.5,-2,0)x(31,4,52)              floor     top 0
SlotFill      box       (-7,-2,-21)x(4,4,10)               floor·M
TunnelRamp    ramp      (-7,0,-16)>(-7,-3.5,-6)w4          plat·M    SLIDE 19°
TunnelFloor   box       (-7,-4,0)x(4,1,12)                 floor     top -3.5
TunnelCeiling box       (-7,-0.25,0)x(4,0.5,12)            wall      headroom 3.0
Canal         box       (32.5,-2.5,0)x(5,1,60)             wall      visual_only
CanalEdge     inv_wall  (32,0,-26)>(32,0,26)h10            -         NEW
NWBlock       box       (-21,4.5,-23)x(22,9,6)             wall·M
WOuter        box       (-29,4.5,-12)x(6,9,16)             wall·M
WOuterMid     box       (-29,4.5,0)x(6,9,8)                wall
JogBlock      box       (-23,4.5,0)x(6,9,4)                wall      kinks Rue des Tanneurs
Atelier       bld2      (-14.5,3.2,-11)x(11,6.4,10)        wall·M    f2, doors N+S, F2 windows N+S
SlotWall      fence     (-5,0,-16)>(-5,0,-7)h1.1           wall·M
Mill          box       (11.5,4.5,-11)x(17,9,10)           wall·M
Church        bld2      (14,4,0)x(12,8,12)                 wall      f1 h8, doors W+E 2.4×3, upper W door y4.5 w2 h2.4
Tribune       box       (9,4.375,0)x(2,0.25,12)            plat      top 4.5
Balcony       box       (7,4.375,0)x(2,0.25,8)             plat      top 4.5
BalconyRail   fence     (6,4.5,-4)>(6,4.5,4)h1             wall
NaveRamp      ramp      (18,0,-5)>(9,4.5,-5)w1.5           plat·M    27°
BellTower     box       (17,11,0)x(3,14,3)                 acc       y4–18, landmark
Pew           box       (14,0.5,-3)x(5,1,1.2)              cover·M
Plinth        box       (-3,1.5,0)x(12,3,2)                wall      mid blocker
Statue        box       (-3,4.5,0)x(1.5,3,1.5)             acc
Morris1       box       (7,1.75,-19)x(2,3.5,2)             cover·M
Morris2       box       (13,1.75,-17)x(2,3.5,2)            cover·M
LockHut       box       (23,1.5,0)x(6,3,4)                 wall
BollardPile   box       (30,1.2,0)x(4,2.4,3)               cover
ViaductDeck   box       (28,4.375,-13)x(4,0.25,18)         plat·M    top 4.5
ViaductRail   fence     (30,4.5,-22)>(30,4.5,-4)h1         wall·M    canal side only
PierGap       box       (27,2.125,-4.75)x(2,4.25,1.5)      cover·M
Pier          box       (28,2.125,-13)x(1.5,4.25,1.5)      cover·M
ViaductStairs stairs    (23,0,-24)>(23,4.5,-16)w2          plat·M    ramp collision 29°
ViaductLanding box       (25,4.375,-16)x(2,0.25,2)          plat·M
```

**Lanes** (north–south)
- West: Rue des Tanneurs, ≤ 23 m.
- Mid: avenue, square and plinth, ≤ 34 m.
- East: the quay under the viaduct, ≤ 24 m.
- Flank: the tunnel (a slide in, then 22 m of cover).

**Power positions**
- **Church balcony (4.5).** Counters: two ramp chokes; the atelier's floor-2 windows (20 m); the plinth; tunnel pushes.
- **Viaduct half.** Counters: point-blank shots across the break, an open inner side, one stair.

**Movement**
- **Slide:** two tunnel ramps.
- **Dive:** the viaduct break, 8 m at 4.5 m. A failure ends in a 0.9 s stun.
- **Stun decision:** jump the balcony rail into the square (0.9 s) or take the ramps.

**Markers**
- **Spawns:** x 9/12/15/18 at z ∓23, looking at (x,1,∓16). The church blocks every pair; spawns are 46 m apart.
- **Hardpoints:** 1 Place (−3,1.5,0) → 2 Quai N (26,1.5,−12) → 3 Crypte (−7,−2,0) → 4 Quai S (26,1.5,12).
- **SnD sites:**

| Site | Position | Size | Attack | Defence | Ratio |
|---|---|---|---|---|---|
| A (Quai) | (26,1.5,12) | 8×3×8 | 37 m (4.5 s) | 17 m (2.0 s) | 2.23 |
| B (Carrefour) | (−21,1.5,17) | 10×3×6 | 53 m | 35 m | 1.51 (path ≈ 2) |

**Landmarks:** the bell tower (y 18), the statue, the viaduct piers.

### 3.4 Col du Vautour — snowy outpost, 76 × 50 m, x-mirror, bounds (−38,−25)…(38,25)

An outpost split by a gorge 7 m deep, with one rope bridge and a snowfield below the crests.
**What makes it different:** every crossing is a decision:
- slide the snowfield and dive the 8 m narrows;
- cross the bridge past the bunkers;
- or slide down into the gorge and climb out.

Buildings: K = bunker, D = depot, B = refuge.

```
uuuuu##uuu^^^^^^^,,,,^^^^^^^uuu##uuuuu   z-25 crest y3, snowfield ^, narrows 8 m
uuuuu##uuu^^^^^^^,,,,^^^^^^^uuu##uuuuu
uuuuuuuuuu^##^^^^,,,,^^^^##^uuuuuuuuuu
uuuuuuuuuu^##^^^^,,,,^^^^##^uuuuuuuuuu
uuuuuuuuuu^##^^^^,,,,^^^^##^uuXuuuuuuu
uuuuuuuuuu^##^^^^,,,,^^^^##^uuuuuuuuuu
rrrruuuuuu^##^##^,,,,^##^##^uuuuuurrrr
rrrr..........##,,,,,,##..........rrrr   gorge x-5..5, floor y-7
rrrr..........##,,##,,##..........rrrr
rrrr....oo......,,,,,,......oo....rrrr
...........KKK..,,,,,,..KKK...........
...........KKK..,,,,,,..KKK...........
...........K2K..===1==..K4K...........   bridge y0
.........==KKK..,,,,,,..KKK==.........
...BBBB....KKK..,,,,,,..KKK....BBBB...
.a.BBBB...DDD...,,,,,,...DDD...BBBB.b.
.a.BBBB...DDD...##,,##...DDD...BBBB.b.
...BBBB...DDD...,,,,,,...DDD...BBBB...
.a.BBBB...DDD...,,,3,,.Y.DDD...BBBB.b.
.a.BBBB...DDD...,,,,,,...DDD...BBBB.b.
...BBBB..rrrrrrrr,##,rrrrrrrr..BBBB...   notch ramps to gorge, needle
......##.rrrrrrrr,##,rrrrrrrr.##......
......##.rrrrrrrr,##,rrrrrrrr.##......
......##......#.,,,,,,.#......##......
......##......#.,,,,,,.#......##......
upper: u crest 3.0; ^ snowfield 3→0; 2 refuge F2 + roof; T needle top y5 (gorge floor −7)
```

```
PlateauOuter  box       (-29,-4,0)x(18,8,50)               floor·M   top 0
PlateauInnerN box       (-12.5,-4,-4.75)x(15,8,40.5)       floor·M
PlateauInnerS box       (-12.5,-4,22.75)x(15,8,4.5)        floor·M
NarrowsLedge  box       (-4.5,-4,-18.5)x(1,8,13)           floor·M   gorge 8 m wide at z<-12
GorgeFloor    box       (0,-7.5,0)x(10,1,50)               floor     top -7, kill-free
NotchRamp     ramp      (-20,0,18)>(-5,-7,18)w5            plat·M    SLIDE 25°
Snowfield     ramp      (-18,3,-18.5)>(-4,0,-18.5)w13      plat·M    SLIDE 12°, thickness 3
Crest         box       (-28,1.5,-18.5)x(20,3,13)          floor·M   top 3
CrestRamp     ramp      (-34,0,-6)>(-34,3,-12)w6           plat·M    27°
RockA         box       (-14,2.5,-16.5)x(4,5,9)            wall·M
RockB         box       (-26,4.5,-22.75)x(3,3,4.5)         wall·M    caps snowfield at 49 m
Bridge        catwalk   (-5.5,0,0)>(5.5,0,0)w3             plat      rails 1.0
Pylon         box       (-5.8,3,-2)x(0.6,6,0.6)            acc·M
PylonS        box       (-5.8,3,2)x(0.6,6,0.6)             acc·M
Bunker        bld2      (-13,1.5,0)x(4,3,10)               wall·M    f1, door W, slit windows E (sill 1.2, h0.3)
BridgeRock    box       (-8,1.5,-9.5)x(3,3,5)              wall·M
Pines         box       (-24,2.5,21)x(2,5,8)               wall·M
PinesRim      box       (-9,2.5,22.5)x(3,5,4)              wall·M
Needle        box       (0,-1,17.5)x(3,12,5)               acc       rock spire, landmark
Refuge        bld2      (-28,3.2,10)x(6,6.4,14)            wall·M    f2, roof_access, doors W+E; spawn shield
Antenna       antenna   @(-28,6.4,10)                      acc       west only; east: box (28,7.9,10) (3,3,3) radar
GorgeRockC    box       (0,-5.5,-8)x(4,3,3)                wall
GorgeRockS    box       (-3.5,-5.5,8)x(3,3,3)              wall·M
Sandbags      box       (-18,0.55,2)x(3,1.1,1)             cover·M
Crates        box       (-20,0.9,-6)x(2,1.8,2)             cover·M
Depot         bld2      (-15,1.6,10)x(6,3.2,10)            wall·M    f1, doors N+S+E
SiteBCrate    box       (9,0.6,12)x(3,1.2,1.5)             cover
```

**Lanes**
- North snowfield: 49 m, Marqueur and Faucheur.
- Mid bridge: 22 m bunker to bunker.
- South gorge: ≤ 20 m.
- The gorge floor runs under the bridge and links all three lanes.

**Power positions**
- **Bunker slits.** Counters: blind to the north and south; a rear door; the snowfield and gorge exits come up behind it.
- **Crest and Rock B.** Counters: Rock A mid-slope; a 12 m/s slide is hard to track.

**Movement**
- **Slide:** snowfield ×2 and notch ramps ×2.
- **Dive:** the narrows (8 m). A max slide-jump off the snowfield also clears it.
- **Stun decision:** jump into the gorge (1.1–1.4 s) or take the notch ramp.

**Markers**
- **Spawns:** x ∓35, z 5/8/11/14, looking at (∓24,1,z). The refuge blocks every pair; spawns are 70 m apart.
- **Hardpoints:** 1 Pont (0,1.5,0) → 2 Bunker O (−13,1.5,0) → 3 Gorge (0,−5.5,12) → 4 Bunker E (13,1.5,0).
- **SnD sites:**

| Site | Position | Size | Attack | Defence | Ratio |
|---|---|---|---|---|---|
| A (Crête) | (22,4.5,−17) | 8×3×8 | 63 m (7.7 s) | 30 m (3.6 s) | 2.12 |
| B (Dépôt) | (9,1.5,11) | 6×3×8 | 44 m | 26 m | 1.69 |

**Landmarks:** the Needle spire, the west antenna and east radar, the bridge pylons.

### 3.5 La Fosse — quarry pit arena, 28 × 28 m, point-symmetric, bounds ±14

A limestone pit in three tiers (rim 0, terrace −2.5, pit −5), with a broken conveyor bridging the rim.
**What makes it different:** the zone is low ground. You take it by coming down; jumping straight in is punished.

```
.........==.LL   z-14
.........==.LL
.#oo:rrrrr::..
a#oo:rrrrr::..
.#::,,,,,,::..
a#::r=,,rr::..
.#---r,,r---..   conveyor y0, gap x-4..4
..---r,Zr---#.
..::rr,,=r::#b
..::,,,,,,::#.
..::rrrrr:oo#b
..::rrrrr:oo#.
LL.==.........
LL.==.........
upper: conveyor halves only (y 0 over pit −5)
```

```
RimN          box       (0,-3,-12)x(28,6,4)                floor·M   top 0
RimW          box       (-12,-3,0)x(4,6,20)                floor·M
TerraceN      box       (0,-4.25,-8)x(20,3.5,4)            floor·M   top -2.5
TerraceW      box       (-8,-4.25,0)x(4,3.5,12)            floor·M
PitFloor      box       (0,-5.5,0)x(12,1,12)               floor     top -5
WallN         box       (0,2,-14.5)x(29,8,1)               wall·M
WallW         box       (-14.5,2,0)x(1,8,28)               wall·M
RimRamp       ramp      (-4,0,-8)>(6,-2.5,-8)w4            plat·M    SLIDE 14°
PitRamp       ramp      (-4.5,-2.5,-4)>(-4.5,-5,4)w3       plat·M    SLIDE 17°
Conveyor      catwalk   (-10,0,0)>(-4,0,0)w2               plat·M    open end = dive gap
Outcrop       box       (-10.5,1.5,-5)x(1,3,8)             wall·M    spawn shield
PitBlock      box       (-2.5,-4.25,-2.5)x(1.5,1.5,1.5)    cover·M   in zone
TerraceBlock  box       (-8,-1.4,-8)x(2,2.2,2)             cover·M
RimCrate      box       (6,0.6,-12)x(2,1.2,2)              cover·M
Headframe     box       (12,5,-12)x(2,10,2)                acc·M     landmark
```

**Lanes:** the rim ring (24 m across), the terrace ring (6–15 m), the pit (0–6 m, Fracas).

**Power position:** the conveyor, 5 m above the zone. Counters: seen from the whole rim, only 2 m wide, and point-blank from the other half.

**Movement**
- **Slide:** rim ramps ×2 and pit ramps ×2.
- **Dive:** the conveyor gap, 8 m.
- **Stun decision:** jump from the rim into the pit (1.0 s) or chain the ramps.

**Markers**
- **Spawns:** (−12.5,1,−7) and (−12.5,1,−3) facing (0,1,z); team 1 at (12.5,1,7) and (12.5,1,3). The outcrops block every pair.
- **Duel zone:** (0,−3,0), size 6×4×6.

**Landmarks:** the headframes, the conveyor.

### 3.6 Le Belvédère — rooftops at dawn, 30 × 24 m, point-symmetric, bounds (−15,−12)…(15,12)

Two zinc roofs face each other across an 8 m street. A footbridge joins them, with a gazebo podium in the middle.
**What makes it different:** the zone is high ground over a void. Falling means a stun and a 10 m ramp climb back up. The ASCII uses a 32-wide frame; `|` is the parapet.

```
|uuuuu,,,ruuuuu|   z-12, roofs y5 (u), street y0 (,)
|^^^^u,,,ruu=uu|
|^^^^u,=,ruu=uu|
|uuuuu,,,ruuuuu|
|auuuu,,,ruuuub|
|uuuuu-ZZ-uuuuu|   footbridge y5, podium 5.9 + gazebo
|uuuuu-ZZ-uuuuu|
|auuuur,,,uuuub|
|uu=uur,=,u^^^^|
|uu=uur,,,u^^^^|
|uuuuur,,,uuuuu|
```

```
BlockW        box       (-9.5,2.5,0)x(11,5,24)             floor·M   roof top 5
Street        box       (0,-0.5,0)x(8,1,24)                floor     kill-free
GateN         box       (0,2,-12.5)x(8,4,1)                wall·M
EdgeW         inv_wall  (-15,5,-12)>(-15,5,12)h8           -·M       NEW
EdgeN         inv_wall  (-15,5,-12)>(15,5,-12)h8           -·M
ParapetW      box       (-14.8,5.55,0)x(0.4,1.1,24)        wall·M
BridgeDeck    box       (0,4.875,0)x(8,0.25,4)             plat      top 5
BridgeRailN   fence     (-2,5,-2)>(-4,5,-2)h1              wall·M
BridgeRailN2  fence     (2,5,-2)>(4,5,-2)h1                wall·M
Podium        box       (0,5.45,0)x(4,0.9,4)               plat      top 5.9
GazeboPillar  box       (-1.8,7.1,-1.8)x(0.3,2.4,0.3)      acc·M
GazeboPillar2 box       (1.8,7.1,-1.8)x(0.3,2.4,0.3)       acc·M
GazeboRoof    box       (0,8.45,0)x(5,0.3,5)               acc
StreetRamp    ramp      (-3,0,12)>(-3,5,2)w2               plat·M    27°, street→roof
ZincSlope     ramp      (-14,6.5,-8)>(-7,5,-8)w4           plat·M    SLIDE 12°, thickness 1.6
Chimney       box       (-10,6.5,0)x(1.5,3,9)              wall·M    spawn shield
Skylight      box       (-9,5.5,8)x(3,1,2)                 cover·M
Cart          box       (1,0.7,7)x(2,1.4,3)                cover·M
WaterTower    water_tower @(-13,5,9)                         acc·M     twin rot_y π
```

**Lanes:** the footbridge (8 m), the north and south roof edges (15–26 m), the street (a punishment lane).

**Power position:** the podium, which is the zone. Counters: seen from both roofs at 6–10 m, and the pillars are too thin to hide behind.

**Movement**
- **Slide:** the zinc slopes, and the street ramps as fast drops.
- **Dive:** roof to roof, 8 m.
- **Stun decision:** jump from the roof edge to the street (0.7–1.0 s) or use the bridge.

**Markers**
- **Spawns:** (∓13,6,±4), facing (0,6,0). The chimneys block every pair; spawns are 26 m apart.
- **Duel zone:** (0,7.4,0), size 4×3×4.

**Landmarks:** the gazebo, the water tanks, the chimneys.

**Performance (all maps)**
- Five materials, so ≤ 10 static draw calls including the outline pass. ≤ 3 zone meshes.
- Treads, container ribs and window frames are visual-only.
- StaticBody3D estimates: Port 180, Val 300, Saint-Ombre 160, Col 220, arenas 50. Cap: 400.

## 4. Kit additions (exact API)

1. **`building2`:**
   ```
   static func building2(parent, batcher, center: Vector3, size: Vector3, color: Color,
       floors: int, doors: Array[Dictionary], windows: Array[String],
       roof_access: bool, parapet: float, slit := false, nm := "Bld")
   ```
   - A door is `{side:"N|S|E|W", floor:int, y:=-1.0, offset:=0.0, w:=1.6, h:=2.4}`; `y` overrides `floor`.
   - Walls 0.25 m. Floor slabs every 3.2 m, with a 2×6 m stair hole.
   - One 28° ramp collision per storey, along the N wall (or the back wall), with visual treads. Add one more to the roof when `roof_access`.
   - Windows 1.2×1.0 m, sill 1.0 m, every 3 m, on every floor of the listed sides. With `slit`, windows are sill 1.2 m × 0.3 m. Windows are shoot-through only.
   - The roof is walkable. Parapet thickness is 0.2 m.
2. **`stairs`:** visual treads, plus ONE ramp collision from start to end.
3. **`container(..., axis := "z", ends_open := 1)`:**
   - `axis "x"` means rot_y = π/2.
   - `ends_open` is 0, 1 or 2. An open end is a full 2.2 × 2.36 m opening.
   - Ribs are visual-only.
4. **`invisible_wall(parent, start, end, height)`:** collision only, 0.2 m thick. Also a `visual_only` flag on `box`.
5. **Fixes:**
   - `piece_footprint` handles rot_y multiples of π/2 exactly, uses height for the fence top, and covers `building2` and `axis`.
   - `water_tower`, `antenna` and `crane` accept `rot_y`.
   - MapSetup reads the `accent` palette key.
6. **GameWorld (owner R3-IN).** In SnD, `spawn_team = team if not sides_swapped else 1 - team`. Without it, attackers spawn on the sites from round 6.

## 5. Validation (builder tests, every map)

1. **Counts and bounds.** Markers in bounds. ≥ 4 spawns per team (≥ 2 in arenas). ≥ 4 hardpoints in the tabled order. 5 palette keys.
2. **Spawn distance.** Team spawns ≥ 40 m apart on 4v4 maps, ≥ 24 m in arenas.
3. **Spawn line of sight.** The footprint test (with the §4 fixes) passes. NEW: a physics raycast between every spawn pair at y + 0.7 must hit geometry.
4. **Sightline caps.** Sample eye-level rays (floor + 1.6) along each lane axis at 1 m spacing, per floor band. Longest clear ray:
   - Port ≤ 36 m.
   - Val ≤ 56 m within z∈[−6,6], ≤ 42 m elsewhere.
   - Saint-Ombre ≤ 35 m.
   - Col ≤ 50 m within z∈[−25,−20.5], ≤ 40 m elsewhere.
   - Arenas ≤ 30 m.
5. **SnD ratios.** The straight-line ratio is 1.4–3.2. NEW: the navmesh path ratio is 1.5–3.0.
6. **Navmesh.** Both spawns reach every hardpoint and both sites; in arenas, the zone.
7. **Hardpoint zones.** Each holds ≥ 40 m² of navmesh at its floor, and mirror pairs alternate in the rotation.
8. **Arenas.** Point symmetry (rot_y + π on twins), zone at the origin.
9. **Movement.**
   - SLIDE ramps are 11–27° and ≥ 7 m long. Walkable ramps ≤ 37°.
   - No unramped rise of 0.15–1.0 m on a navmesh path.
   - Headroom ≥ 2.2 m under the tunnel, culvert, cab and signal board.
   - Each gap is 8.0 ± 0.1 m. A headless MovementConfig sim shows the dive lands and the sprint jump fails.
10. **Performance.** ≤ 120 draw calls in the map_shots views, ≤ 6 materials, ≤ 400 StaticBody3D.

## 6. Risks

- **Movement ranges.** The ranges are ballistic estimates. If the sim disagrees, retune GAP globally.
- **building2.** It is the biggest job. If it slips, ship its collision first and windows later.
- **Arena feel.** Point-symmetric arenas can feel artificial. Break it only with non-colliding decals.
- **Saint-Ombre site B.** Its straight-line ratio is close to 1.4. Track its round win rate (45–55 %).
- **Contrast.** The Jaune enemy colour is weak on snow and limestone (design.md risk 1). Run the greyscale gate on Col and La Fosse first.
