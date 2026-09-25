# Round 3 contract — bots, real maps, graphic-novel UI

Read first: `.orchestrator/session.md`, `.orchestrator/contract-p0.md` (network rules — still law),
`.orchestrator/contract-r2.md` (interfaces now in place), `.orchestrator/design.md` (art/UI
direction, locked), `docs/ROADMAP.md` §4 (numbers). Godot 4.7, typed GDScript, French comments
and strings, no TODO, no placeholder content. Tests first for pure logic, red then green, never
weaken a test. Gates before reporting: your test folder green, the WHOLE suite still green
(`bash tools/test.sh`), `--check-only -s` on your scripts, headless boot (`--quit-after 300`) of
`scenes/ui/main_menu.tscn`, `scenes/levels/test_arena.tscn` and your new scenes with zero
SCRIPT/SHADER ERROR, and the 2-process test `tools/net_smoke.gd` still `ok=true`.
Godot: `GODOT_BIN=/c/Users/srko/Desktop/Godot_v4.7-stable_win64.exe`.
Screenshots go to `C:/Users/srko/AppData/Local/Temp/claude/C--Users-srko-Desktop-fps/02e156fb-5e66-4722-9835-071a024d62a9/scratchpad/shots/r3/`;
look at them yourself (Read the PNG) and iterate.

Shared foundation already written by the lead: `scripts/core/MatchConfig.gd` (mode_id, map_id,
team_size, bots_enabled, bot_difficulty, set_mode). Everyone reads it; only the UI slice's menu writes it.

## Ownership (disjoint)

| Slice | Owns (write) |
|---|---|
| **R3-IN input + bots + weapon feel** | new `scripts/player/PlayerInput.gd`, new `scripts/ai/**`, `scripts/player/{PlayerController,PlayerCamera,ViewModel}.gd`, `scripts/player/states/**`, `scripts/combat/Weapon.gd`, `scripts/agents/AbilityController.gd`, `scripts/world/WorldWeapon.gd`, `scripts/modes/**`, `scripts/networking/GameWorld.gd`, `scenes/player/player.tscn`, `tests/ai/**`, `tests/input/**`, `tools/bot_smoke.gd` |
| **R3-MAPS** | new `scripts/levels/maps/**`, new `scenes/levels/maps/**`, `tests/maps/**`, `tools/map_shots.gd` |
| **R3-UI** | `scripts/ui/**` except `OptionsMenu.gd`, `resources/ui/**`, `resources/fonts/**`, `THIRD_PARTY_LICENSES.md`, `project.godot`, `tests/ui/**` |

Still running from round 2: the rendering builder owns `assets/shaders/**`, `scripts/core/{Cartoon,InkPost,LevelLook,Settings}.gd`,
`scripts/player/PlayerLook.gd`, the three old level builders, `TrainingDummy.gd`, `OptionsMenu.gd`. Don't edit those.

## Cross-slice interfaces

- **PlayerInput (R3-IN)**: `Node` child `Input` of the player, `process_physics_priority = -100`.
  Fields for the current physics tick: `move: Vector2` (Input.get_vector convention),
  `look_delta: Vector2` (yaw, pitch radians — bots), `jump_pressed/held`, `crouch_pressed/held`,
  `walk_held`, `dive_pressed`, `fire_pressed/held`, `aim_held`, `reload_pressed`,
  `pickup_pressed/held`, `drop_pressed`, `weapon_slot_pressed: int` (-1 none),
  `weapon_next_pressed`, `weapon_prev_pressed`, `ability_pressed: String` ("" or C/Q/E/X),
  `is_bot: bool`, `reads_devices: bool`. Humans on their own machine gather from `Input` with
  EXACTLY today's gating (combat actions only while the mouse is captured). All gameplay code
  reads `player.input`, never `Input` (UI code may keep reading `Input`).
- **Local human vs authority**: `PlayerController.is_local_human() -> bool` (authority AND not a
  bot). Camera current, mouse capture, `local_player` group, HUD, ViewModel, PlayerCamera effects
  are for the local human only. Bots are server-owned players (authority 1) named with ids
  ≥ 9001, `player_info[id].name = "BOT <nom>"`, `is_bot = true` replicated at spawn.
  Server-side request wrappers must use the player's owner id when the server simulates that
  player itself (host or bot), never blindly `multiplayer.get_unique_id()`.
- **Bots need**: a `NavigationRegion3D` in group `nav_region`, baked before `GameWorld._ready`
  spawns bots (R3-MAPS guarantees it in new maps; R3-IN bakes one at runtime from static colliders
  when a scene has none, e.g. test_arena). Objectives from the mode node: every mode exposes
  `bot_goal_for(team: int) -> Vector3` (hardpoint zone, bomb site / planted bomb, duel zone,
  nearest enemy for TDM) — R3-IN adds it to the modes it owns.
- **MapCatalog (R3-MAPS)** `scripts/levels/maps/MapCatalog.gd`: `static func all() -> Array[Dictionary]`
  with keys `id`, `name`, `description`, `scene` (res path), `modes` (Array of mode ids),
  `size` ("4v4" or "duel"); `static func default_for(mode_id: String) -> Dictionary`.
- **Map scenes (R3-MAPS)** `scenes/levels/maps/<id>.tscn`: root `Node3D` with `GameWorld.gd`
  (same children/exports as `scenes/levels/snd_map.tscn`: WorldEnvironment, DirectionalLight3D,
  Players, PlayerSpawner, HUD, PauseMenu, BuyMenu) plus a `MapSetup` node
  (`scripts/levels/maps/MapSetup.gd`) that, in `_enter_tree`, builds geometry, markers
  (`SpawnPoints` with `team` meta, `HardpointPoints`, `SiteA`/`SiteB` Area3D, `DuelZone` Area3D,
  `Hardpoint` Area3D), the baked `NavigationRegion3D`, and instantiates the mode node named
  `GameMode` from `MatchConfig.mode_id` (TDMMode, HardpointMode with rotate_interval 60,
  SnDMode, DuelMode) wired to those markers — before GameWorld's `_ready`.
- **UI (R3-UI)** reads MapCatalog for map choice, writes MatchConfig, then changes scene to the
  map's `scene`. `DuelMode.requested_team_size` is replaced by `MatchConfig.team_size` (R3-IN
  updates DuelMode; R3-UI stops writing the old static).

## R3-IN — acceptance
1. PlayerInput + refactor of every gameplay `Input.*` read (PlayerController, 9 states, Weapon,
   AbilityController, ViewModel, PlayerCamera, WorldWeapon pickup, SnDMode plant/defuse). Human
   feel must be unchanged: same actions, same gating, same responsiveness (mouse look stays in
   `_unhandled_input`).
2. Bots: `scripts/ai/BotBrain.gd` (+ helpers). Server spawns bots to fill both teams up to
   `MatchConfig.team_size` when `bots_enabled`; bots leave when humans join (replaced).
   Behaviour: navmesh pathing, objective play via `bot_goal_for`, target acquisition with line of
   sight, human-like reaction time and aim error per difficulty (Recrue ~450 ms, Vétéran ~300 ms,
   Élite ~200 ms, error shrinking while tracking), strafing, occasional slide/jump/crouch,
   reloads, weapon from the mode's rules (SnD buys with its credits), rare ability use,
   no wall-hacks (only what it can see or hear). They go through the SAME server validation as
   humans. Pure parts tested in `tests/ai/` (reaction model, aim error, target choice).
3. `tools/bot_smoke.gd`: headless host, TDM on a new map if present else test_arena, 7 bots,
   120 s → prints `BOT_SMOKE kills=<n> errors=0 rejected_shots=<n>`; kills > 0 and zero script errors.
4. Weapon feel from the balance data: apply `recoil_pattern`/`pattern_shots` then random, move and
   air spread adds, `sprint_to_fire` / `slide_to_fire` / `dive_to_fire` delays, `ads_time`. Server
   keeps validating; predictions stay consistent.

## R3-MAPS — acceptance
1. Modular kit (`Kit.gd`): walls, floors, ramps, stairs, containers (ribbed, doors), crates,
   building shells with window/door openings and roofs, catwalks with rails, pillars, barriers,
   fences, decorative silhouettes (crane, water tower, antenna) — all `StaticBody3D` + matching
   collision + `Cartoon.world/prop` materials, palettes from design.md.
2. Six layouts from design.md: Port-Ferraille, Val-Poussière, Saint-Ombre, Col du Vautour (4v4,
   compact ~70×50 m playable, 3 lanes, preferred range per lane, 2 height levels, ramps for slides
   and drops for dives, one long sniper lane max, spawns at opposite ends facing the fight,
   ≥ 4 hardpoint positions, 2 bomb sites with attack travel ≈ 2× defence travel) and La Fosse,
   Le Belvédère (duel arenas ~25×25 m, symmetric, central capture zone). Every 4v4 map supports
   tdm/hardpoint/snd; arenas support duel/duo.
3. `tests/maps/`: pure validation of every layout (markers in bounds, 4+ spawns per team, team
   spawns ≥ 40 m apart on 4v4 maps, no direct line between spawns through open space, 2 sites,
   ≥ 4 hardpoints, arena symmetry) + a headless test that bakes each navmesh and checks paths
   exist spawn→objectives.
4. `tools/map_shots.gd`: a top-down and two player-height views per map; review them.

## R3-UI — acceptance (follow design.md exactly)
1. Fonts from the lead's downloads (copy from
   `C:/Users/srko/AppData/Local/Temp/claude/C--Users-srko-Desktop-fps/02e156fb-5e66-4722-9835-071a024d62a9/scratchpad/downloads/fonts/`):
   Protest Revolution (titles, sound words, agent names), Barlow Condensed 600/700/800 and
   Barlow Semi Condensed 500 (UI, numbers) into `resources/fonts/` with their OFL.txt; update
   `THIRD_PARTY_LICENSES.md`. Lato may stay only as a fallback.
2. `project.godot` display: authoring base 1920×1080, stretch `canvas_items` + `expand`, a sane
   windowed default size; UI scale option ready (Deck default 115 %).
3. Rewrite `Comic.gd` into the graphic-novel token set (ink/paper/graphite, ally blue as the only
   UI accent, radius 0, strokes 3/6/9, 6-px spacing scale, hard ink offset shadow, hatching for
   disabled/cooldown/empty, halftone only on lobby/end backdrops). Update the theme resource.
4. Restyle and split (P0.7): GameHUD into components (health, ammo, abilities, score/timer/phase,
   killfeed, scoreboard, round/bomb/credits, death/end panels); the corner debug text only on F3.
   Centre 40 %×40 % stays clean; sound words ≤ 300 ms, never in the centre.
5. Menus: MainMenu (lobby + play card: mode, map from MapCatalog, bots on/off, difficulty, host,
   join, training), BuyMenu, PauseMenu, ArsenalMenu, AgentSelectScreen, AgentMenu, end-of-match
   as a comic page. All states: hover, focus-visible (gamepad), pressed, disabled, loading, empty,
   error. Gamepad navigation everywhere.
6. Texts ≥ 13 px at 1280×800. Screenshots at 1920×1080 and 1280×800 of: lobby, play card, HUD in
   match, buy menu, agent select, end page. Tests in `tests/ui/` for pure helpers (formatting,
   layout maths, token contrast).
