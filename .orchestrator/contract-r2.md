# Round 2 contract — visible game: ink look, 3D weapons, sound, modes, balance, agents

Read first: `.orchestrator/session.md`, `.orchestrator/contract-p0.md` (network rules still apply),
`docs/ROADMAP.md` §1, §4, §6 (Phases 2–3). Godot 4.7, typed GDScript, French comments and
user-facing strings, no TODO, no placeholder content, no `print` spam. Tests with gdUnit4:
`GODOT_BIN=/c/Users/srko/Desktop/Godot_v4.7-stable_win64.exe bash tools/test.sh res://tests/<your folder>`.
Write your tests FIRST from the acceptance below, see them red, then implement; never weaken a
test to make it pass. Before reporting, every slice must: pass its test folder, `--check-only -s`
each script it wrote, and boot `scenes/levels/test_arena.tscn` + `scenes/ui/main_menu.tscn`
headless (`--quit-after 300`) with zero `SCRIPT ERROR`.

Art thesis (locked): **"encre et papier, joueurs en couleur"** — graphic novel, heavy ink, hatching
in shadows, paper tones; environments desaturated with 2–3 muted hues per map; players, team
colours and gameplay effects are the only saturated things. Ally = blue `#3D7BFF`-ish; enemy =
player choice red (default) / yellow / purple, always paired with a shape cue.

## Ownership (disjoint — never write a file you don't own)

| Slice | Owns (write) |
|---|---|
| **R-A rendering** | `assets/shaders/**`, `scripts/core/{Cartoon,InkPost,LevelLook,Settings}.gd`, `scripts/player/{PlayerCamera,PlayerLook}.gd`, `scripts/levels/{ArenaBuilder,CompMapBuilder,GulagBuilder}.gd`, `scripts/world/TrainingDummy.gd`, `scripts/ui/OptionsMenu.gd`, `tests/rendering/**`, `tools/screenshot.gd` |
| **R-A2 weapons 3D** | `tools/blender/**`, `assets/models/weapons/**`, `scripts/player/{ViewModel,ThirdPersonWeapon}.gd`, `scripts/combat/Weapon.gd`, `scripts/world/WorldWeapon.gd`, `scenes/player/player.tscn`, `tests/combat/test_weapon_fx.gd` |
| **R-E audio** | `tools/audio/**`, `assets/audio/**`, `scripts/core/Audio.gd`, `default_bus_layout.tres`, `project.godot`, `tests/audio/**` |
| **R-B1 modes** | `scripts/modes/**`, `scripts/networking/GameWorld.gd`, `scripts/combat/Health.gd`, `scripts/player/PlayerController.gd`, `scripts/ui/{GameHUD,BuyMenu,MainMenu}.gd`, `scenes/levels/*.tscn` except benchmark, new `scenes/levels/{snd_map,duel_arena}.tscn`, `tests/modes/**` |
| **R-B2 balance** | `resources/weapons/**`, `scripts/combat/{WeaponConfig,WeaponDatabase,WeaponMath}.gd`, `tests/balance/**`, `tools/balance_table.gd`, `docs/BALANCE.md` |
| **R-B3 agents** | `scripts/agents/**`, `scripts/ui/{AgentSelectScreen,AgentMenu}.gd`, `tests/agents/**` |

## Cross-slice interfaces (implement exactly; others code against them)

**Cartoon (R-A, land this FIRST, within your first steps):**
`Cartoon.mat(color: Color, _outline: float = 0.0) -> Material` (kept for old callers, now the ink
world material) · `Cartoon.world(color: Color) -> ShaderMaterial` · `Cartoon.prop(color: Color) -> ShaderMaterial`
(thin outline) · `Cartoon.character(color: Color, outline_px: float = 3.0) -> ShaderMaterial` (thick
outline) · `Cartoon.set_rim(g: GeometryInstance3D, color: Color, strength: float) -> void` ·
`Cartoon.ally_color() -> Color`, `Cartoon.enemy_color() -> Color` (from `Settings.enemy_color`) ·
constants `INK`, `PAPER`, `SHADOW_TINT`.
**Settings (R-A):** static vars `enemy_color: int` (0 rouge, 1 jaune, 2 violet), `ink_edges: bool`,
`volume_master`, `volume_sfx`, `volume_music` (0..1), persisted like the others; OptionsMenu gets
the controls.
**PlayerLook (R-A)** `scripts/player/PlayerLook.gd`, a `Node` child of the player named `Look`:
applies `Cartoon.character` to the body mesh, team/enemy rim relative to the LOCAL player (retry
until the local player exists), hides the body for the local player, `cast_shadow = OFF` on bodies.
**Weapon (R-A2):** signals `fired(cfg: WeaponConfig)` and `reload_started(cfg: WeaponConfig)` (owner
only), `hit_confirmed(pos: Vector3, dmg: float, headshot: bool)` (shooter only),
`remote_fired(cfg: WeaponConfig, origin: Vector3, dirs: Array)` (every peer except the shooter,
from a server broadcast of ACCEPTED shots, `unreliable_ordered`, also spawns the remote tracer).
Server API: `server_set_loadout(ids: Array[int]) -> void`, `server_refill_ammo() -> void`,
`server_current_ids() -> Array[int]` (all push sync to the owner). In `_server_buy`, if the node
in group `game_mode` has `server_try_purchase(peer_id: int, weapon_id: int) -> bool`, call it and
reject when false. After an accepted shot call `Health.end_spawn_protection()` when present.
**Health (R-B1):** server signal `damaged(amount: float, attacker_id: int)`, `regen_enabled: bool`,
`spawn_protection(seconds: float)`, `end_spawn_protection()`, `regen_delay = 4.0`.
**PlayerController (R-B1):** remove the capsule material + local mesh hiding from `_ready` (moved to
PlayerLook); add `movement_locked: bool` honoured by the movement states/physics, set by server →
owner RPC `net_set_locked(locked: bool)` (sender must be 1).
**Game mode node (R-B1):** property `abilities_enabled: bool` (Duel/Duo false) and
`buy_phase: bool`; `server_try_purchase` on SnD.
**AbilityController (R-B3):** signal `ability_used(slot: String, ability_name: String)` (owner);
disables activation when the `game_mode` node has `abilities_enabled == false`;
`request_activate(i: int, aim_dir: Vector3)` (server validates normalized/finite).
`server_add_ult(points)` stays; R-B1's GameWorld calls it from `Health.damaged` (attacker gets
`amount * 0.05` points) and on kills.
**player.tscn (R-A2):** add `ViewModel` (Node3D, script ViewModel.gd) under `Head/Camera3D`,
`ThirdPersonWeapon` (Node3D) on the body at hand height, `Look` (Node, script
`res://scripts/player/PlayerLook.gd` from R-A).
**project.godot (R-E):** add autoloads `Sfx="*res://scripts/core/Audio.gd"` and
`Look="*res://scripts/core/LevelLook.gd"` (R-A's script) and the bus layout. Input action for
plant/defuse: reuse existing `pickup` (F) — no new actions this round.

## R-A rendering — acceptance
1. `ink_toon.gdshader`: stepped ramp in `light()` (2–4 bands), shadow tint never black, world-space
   procedural hatching in shadow (cross-hatch in the deepest band), subtle paper grain, optional
   albedo texture, rim via `instance uniform` (0 for world).
2. `ink_outline.gdshader`: inverted hull `next_pass`, screen-constant pixel width, ink colour.
3. `ink_edges.gdshader` + `InkPost.gd`: full-screen depth+normal edge pass (Forward+) for
   environment lines, fading with distance, paper overlay; attached to the local camera only;
   toggle `Settings.ink_edges`.
4. `ink_sky.gdshader` + `LevelLook.gd` autoload: whenever a `WorldEnvironment` enters the tree,
   apply the ink sky, tonemap, paper ambient, light fog, no glow; directional light shadows on for
   static world. Main menu included.
5. Level builders use per-map muted palettes; no team hue in environments. Training dummies styled.
6. Pure logic tested in `tests/rendering/` (e.g. palette/enemy colour selection, rim relation).
7. `tools/screenshot.gd`: `godot --path . -s res://tools/screenshot.gd -- --scene=<res path> --out=<png> [--pos=x,y,z --look=x,y,z]`
   renders windowed and saves a PNG. Save shots of test_arena, comp_map, arena_1v1 and main menu to
   `C:/Users/srko/AppData/Local/Temp/claude/C--Users-srko-Desktop-fps/02e156fb-5e66-4722-9835-071a024d62a9/scratchpad/shots/`.
8. Re-run the benchmark windowed; report the BENCH line (baseline 274.8 avg / 180 low1). Keep ≥ 144 avg.

## R-A2 weapons 3D — acceptance
1. `tools/blender/make_weapons.py` (run `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python tools/blender/make_weapons.py`)
   builds 7 chunky stylised guns (one per current weapon id, file name = weapon file stem, e.g.
   `ravage.glb`), bevelled bold shapes readable in silhouette, material slots `body`, `grip`,
   `metal`, `accent`, origin at the grip, barrel along −Z, an empty named `Muzzle`. Deterministic.
2. ViewModel: current weapon model at ~0.3 m (never clips: player radius 0.4), `Cartoon.character`
   materials; procedural animation: mouse-lag sway, walk/sprint bob from player velocity and state,
   sprint pose, ADS centring, recoil kick with spring return on `fired`, reload dip over
   `reload_time` on `reload_started`, equip rise on `weapon_changed`, slide tilt; ink-star muzzle
   flash (~50 ms) at `Muzzle`. Local player only.
3. ThirdPersonWeapon shows the held weapon on other players; WorldWeapon uses the model.
4. Remote shot FX broadcast + signals above; `test_weapon_fx.gd` covers the pure parts you add.
5. Screenshots (via R-A's `tools/screenshot.gd` once it exists, else your own capture) of the
   viewmodel for 3 weapons, saved to the scratchpad `shots/` folder.

## R-E audio — acceptance
1. `tools/audio/gen_sfx.py` (numpy/scipy, fixed seeds, 48 kHz 16-bit WAV) generates every sound
   below into `assets/audio/sfx/<name>_<n>.wav` (2–4 variations each where it matters):
   gunshots per weapon class (pistol, magnum, smg, rifle, marksman, shotgun, sniper) with a
   transient + body + tail and a `_far` low-passed variant; reload out/in; dry fire; equip;
   hitmarker; headshot; kill confirm; damage taken; death; footsteps walk/sprint (4 each); jump;
   land; slide loop; dive whoosh; roll; stun twinkle (cartoon); dash; heal; wall slam; ult; smoke;
   flash; UI hover/click/back/buy; round start/win/lose stingers; hardpoint tick; bomb beep/plant/
   defuse. Plus `assets/audio/music/menu_loop.ogg` or `.wav` (60–90 s seamless ambient loop in the
   ink/paper mood). Loud but not clipping (peak −1 dBFS), consistent loudness per category.
2. `Audio.gd` autoload `Sfx`: buses Master/Music/SFX/UI (bus layout file), pooled players,
   `play_ui(name)`, `play_local(name)`, `play_at(name, pos)`; random variation + ±5 % pitch.
   Auto-wires: every `BaseButton` entering the tree (hover/focus + pressed), the local player's
   Weapon (`fired`, `reload_started`, `hit_confirmed`, `weapon_changed`), Health (damage, death),
   AbilityController `ability_used`, footsteps by polling the local player's state/velocity,
   every other player's `remote_fired` (3D, `_far` beyond 30 m) and their footsteps (3D, audible,
   competitive "play by sound"). Volumes from `Settings.volume_*` (poll ≤ 2 Hz). Menu music in the
   main menu only.
3. `tests/audio/`: pure helpers (e.g. name → variation pick, distance → near/far choice, cadence).

## R-B1 modes — acceptance
1. Pure `RoundState.gd` (phases BUY/PREROUND → LIVE → POST, timers, round wins, side swap,
   match point, overtime) and `Economy.gd` (start 800, win 3000, loss 1900/2400/2900 streak, kill
   200, plant 300, cap 9000, purchase validation) with tests first in `tests/modes/`.
2. `RoundMode` base on `GameMode`; `SnDMode` (4v4, attackers/defenders, first to 6, swap after 5,
   buy phase 15 s, round 90 s, one bomb carried by a random attacker, dropped on death and
   re-pickable, plant 4 s / defuse 7 s holding `pickup` inside site A/B, bomb 45 s, survivors keep
   weapons, dead reset to pistol, credits); `DuelMode` (1v1 or 2v2, first to 6, 40 s rounds then
   a central capture zone (3 s hold wins), forced identical loadout rotating every 2 rounds, no
   abilities, no regen during rounds, preround 3 s).
3. TDM 50 kills or 10 min; Hardpoint 250 pts or 10 min, 60 s hills, next hill announced 15 s
   ahead; respawn TDM 3 s, HP 5 s; 1 s spawn protection ended by firing; match timer in GameMode.
4. GameWorld: respawn policy per mode, round resets (full HP, team spawns, lock during
   BUY/PREROUND via `net_set_locked`), ult charge from damage and kills.
5. New scenes `snd_map.tscn` (comp map geometry + sites + spawns) and `duel_arena.tscn`
   (gulag geometry); MainMenu lists TDM 4v4, Hardpoint 4v4, R&D 4v4, Duel 1v1, Duo 2v2.
6. HUD: match/round timer, round score, phase banner, alive counts, credits, plant/defuse progress,
   bomb state, overtime; BuyMenu shows credits and prices, only usable when allowed.
7. Extend `tools/net_smoke.gd` is NOT yours — do not edit it.

## R-B2 balance — acceptance
1. 10 weapons: the 7 existing + 3 new (append to `PATHS`, never reorder), each the best in at
   least one range band among primaries ([0–6], [6–15], [15–30], [30–50], [50+] m); niche written
   in `docs/BALANCE.md`.
2. HP 100. Primaries: optimal body TTK 350–500 ms, headshot-only TTK 250–350 ms. Pistol 550–700 ms;
   Magnum kills in 2 heads or 3 bodies; shotgun one-shot ≤ 4 m with all pellets; sniper one-shot to
   the head, body 2 shots (upper-torso zone comes with hitboxes, P1.3).
3. New data fields in `WeaponConfig` (documented, used next round by Weapon.gd):
   `recoil_pattern: PackedVector2Array`, `pattern_shots: int`, `move_spread_add`, `air_spread_add`,
   `sprint_to_fire`, `slide_to_fire` (≈0.38), `dive_to_fire` (≈0.46), `ads_time`; values filled
   for all 10 weapons.
4. `tests/balance/test_ttk_bands.gd` asserts every band above and the niche rule;
   `tools/balance_table.gd` regenerates the TTK-by-distance table in `docs/BALANCE.md`.

## R-B3 agents — acceptance
1. 6 agents, 3 roles (Entrée, Contrôle, Soutien) × 2, each with C/Q/E + X ultimate, every ability
   with `description` and a written counterplay (in `docs/AGENTS.md` table — you may edit that
   doc). Keep "Vif" and "Roc" names or rename consistently.
2. Effects only from these primitives, all server-authoritative per contract-p0: movement impulse
   (local), heal (server; the basic heal only works if the player took no damage for 3 s),
   server-spawned objects replicated to all (wall, hard-edged ink smoke sphere ≤ 12 s, jump pad,
   stun trap that sends the victim to `Stun` via `state_machine.transition_to("Stun", {"duration": d})`
   on the victim's owner), flash (server checks line of sight + facing from body yaw, victims get
   a paper-white screen fade ≤ 1.5 s), reveal (team sees ink "!" markers through walls ≤ 3 s).
   Server computes targets from its own view + validated `aim_dir`.
3. Ult charge from damage/kills (GameWorld calls `server_add_ult`), time trickle ≤ 0.1 pt/s.
4. Agent select screen and Agents menu show role, description and the 4 abilities.
5. Tests in `tests/agents/` for new pure logic (out-of-combat heal rule, aim_dir validation,
   flash facing check, target selection helpers).
