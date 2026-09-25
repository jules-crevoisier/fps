# Phase 0 contract — foundations & server authority

Engine: Godot 4.7 (GDScript, typed). Tests: gdUnit4 6.2.1 in `tests/`, run with
`GODOT_BIN=/c/Users/srko/Desktop/Godot_v4.7-stable_win64.exe bash tools/test.sh [res://tests/<path>]`
(exit 0 = pass, 100 = failures). Code comments and user-facing strings stay in French like the
rest of the repo. No TODO, no placeholder, no untyped `var x = load(...)` in new code.

## Global rules (all slices)

- **Gameplay component nodes have the SERVER (peer 1) as multiplayer authority**: `Health`
  (already), `Weapon`, `Abilities`. The player root keeps the owner as authority (movement
  synchronizer). Owner-only input is gated with `player.is_multiplayer_authority()`.
- **Client → server requests**: `@rpc("any_peer", "call_remote", "reliable")` handlers that only
  forward to a `_server_*(sender_id: int, ...)` method. Every `_server_*` method checks
  `multiplayer.is_server()` and `sender_id == player_owner_id` (player node name `.to_int()`).
  Callers use a wrapper: if `multiplayer.is_server()` call `_server_*(multiplayer.get_unique_id(), ...)`
  directly, else `request_*.rpc_id(1, ...)`. (Host player and offline training go through the
  same server path.)
- **Server → client pushes**: `@rpc("authority", ...)` on server-authority nodes. On nodes whose
  authority is not the server (player root), use `any_peer` + guard
  `multiplayer.get_remote_sender_id() == 1`.
- **All gameplay timers run in `_physics_process`** (fixed 60 Hz tick), never `_process`.
- Pure logic lives in `RefCounted` classes with no scene-tree access, so tests can drive it.

## Pure classes (tests are written against these signatures)

### `scripts/combat/WeaponDatabase.gd` (existing, add)
- IDs = index in `PATHS` (append-only order). `static func get_by_id(id: int) -> WeaponConfig`
  (null if out of range), `static func id_of(c: WeaponConfig) -> int` (-1 if unknown),
  `static func default_loadout_ids() -> Array[int]` (ids of "Ravage", "Pistolet").

### `scripts/combat/WeaponMath.gd` — `class_name WeaponMath extends RefCounted`, static only
- `const HEAD_HEIGHT := 1.4`
- `static func damage_at(dist: float, c: WeaponConfig) -> float` — full `damage` up to
  `falloff_start`, `damage_min` from `falloff_end`, linear in between (exact current behaviour).
- `static func is_headshot(hit_y: float, body_origin_y: float) -> bool` — `hit_y > body_origin_y + HEAD_HEIGHT`.
- `static func shot_damage(c: WeaponConfig, dist: float, headshot: bool) -> float` — damage_at ×
  (headshot_mult if headshot) × max(1, pellets) (all pellets hit).
- `static func shots_to_kill(c: WeaponConfig, dist: float, hp: float, headshot: bool) -> int` — ceil(hp / shot_damage).
- `static func ttk_ms(c: WeaponConfig, dist: float, hp: float, headshot: bool) -> float` —
  (shots_to_kill − 1) / fire_rate × 1000.

### `scripts/combat/Inventory.gd` — `class_name Inventory extends RefCounted`
- `const EMPTY := -1`; `var slots: Array[int]`, `var mag: Array[int]`, `var reserve: Array[int]`,
  `var current: int`, `var reloading: bool`, `var reload_left: float`.
- `_init(slot_count: int = 2)` — all slots EMPTY, current 0.
- `set_loadout(ids: Array[int])` — fills slots in order (extra ids ignored), full mag/reserve,
  current = first non-empty slot (0 if none), not reloading.
- `current_id() -> int`, `has_weapon(id) -> bool`, `free_slot() -> int` (-1 if none).
- `add_into_free(id) -> int` — slot index or -1; full ammo; if current slot is EMPTY, current = that slot.
- `replace_current(id) -> int` — returns displaced id (EMPTY if none); full ammo; cancels reload.
- `give(id) -> int` — free slot if any else current slot; equips it; returns displaced id (EMPTY if a free slot was used); cancels reload.
- `remove_current() -> int` — returns removed id (EMPTY if none); zeroes ammo; current = first non-empty slot (unchanged if none); cancels reload.
- `equip(slot) -> bool` — false if out of range, same slot, EMPTY slot or reloading.
- `can_fire() -> bool` — current non-EMPTY, not reloading, mag > 0.
- `consume_round() -> bool` — decrements mag when `can_fire()`.
- `start_reload() -> bool` — false if reloading, EMPTY, mag full or reserve 0; else reload_left = config reload_time.
- `tick(delta) -> bool` — advances reload; true on the tick it completes (mag += min(needed, reserve)).
- `to_dict() -> Dictionary`, `static func from_dict(d: Dictionary) -> Inventory` — lossless round trip.
- Weapon stats come from `WeaponDatabase.get_by_id`.

### `scripts/combat/RateLimiter.gd` — `class_name RateLimiter extends RefCounted` (token bucket)
- `_init(rate_per_sec: float, burst: float)` — bucket starts full.
- `try_take(now_sec: float, cost: float = 1.0) -> bool` — refill `min(burst, tokens + (now − last) × rate)`
  (no refill if now < last), take cost if available.

### `scripts/combat/FireClock.gd` — `class_name FireClock extends RefCounted`
- `_init(rate_per_sec: float)`, `set_rate(rate)`, `reset()`.
- `tick(delta: float, trigger: bool) -> int` — shots allowed this tick (0 or 1 at rates ≤ tick
  rate). Carries the fractional remainder while the trigger is held so that the AVERAGE rate
  matches `rate` (±1 shot over 1 s at 60 Hz, e.g. 13.3/s → 13 or 14 shots). The first shot after
  an idle period fires immediately. While idle, the clock cools down to "ready" without banking
  extra shots.

### `scripts/combat/ShotValidator.gd` — `class_name ShotValidator extends RefCounted`, static only
- `const ORIGIN_TOLERANCE := 3.0` (m; covers replication lag until lag compensation, P1.3).
- `static func is_valid(origin: Vector3, head_pos: Vector3, dirs: Array, expected_pellets: int) -> bool`
  — origin finite and within tolerance of head_pos; `dirs.size() == max(1, expected_pellets)`;
  each dir is a finite `Vector3` of length in [0.99, 1.01].

### `scripts/agents/AbilityState.gd` — `class_name AbilityState extends RefCounted`
- `_init(abilities: Array)` (Array of `Ability`), `var ult_charge_rate: float = 0.45`.
- `tick(delta)` — non-ult: when a charge is missing and cooldown > 0, cooldown decreases; at 0 →
  +1 charge, and cooldown restarts if still below max. Ult: points += delta × rate, capped at ult_cost.
- `can_activate(i) -> bool`, `try_activate(i) -> bool` — non-ult consumes a charge (starting the
  cooldown if charges were full); ult requires points ≥ ult_cost and resets points to 0. False for
  bad index.
- `add_ult(points: float)` (capped), `charges(i) -> int`, `cooldown_left(i) -> float`, `ult_points() -> float`.
- `to_dict()` / `apply_dict(d)` for server → owner correction.

### `scripts/core/FrameStats.gd` — `class_name FrameStats extends RefCounted`
- `_init(capacity: int = 600)` ring buffer of frame times (ms).
- `add(frame_ms: float)`, `count() -> int`, `avg_fps() -> float`, `p99_ms() -> float`
  (99th percentile frame time, nearest-rank), `low_1pct_fps() -> float` (= 1000 / p99_ms),
  `clear()`. Empty → all getters return 0.

## Slice ownership (disjoint)

| Slice | Files it may write |
|---|---|
| TDD | `tests/**` only |
| S1a combat | `scripts/combat/{Weapon,WeaponDatabase,WeaponMath,Inventory,RateLimiter,FireClock,ShotValidator}.gd`, `scripts/world/WorldWeapon.gd`, `scripts/ui/BuyMenu.gd` |
| S1b abilities/health/world | `scripts/agents/**`, `scripts/combat/Health.gd`, `scripts/networking/GameWorld.gd`, `scripts/player/PlayerController.gd`, `scenes/player/player.tscn` |
| S2 CI | `.github/**`, `export_presets.cfg`, `.gitignore`, `docs/TESTING.md` |
| S3 perf | `scripts/core/{PerfOverlay,FrameStats}.gd`, `scripts/levels/Benchmark.gd`, `scenes/levels/benchmark.tscn`, `project.godot` |

## S1a acceptance (combat authority)
1. Server rejects a shot when: sender ≠ owner; shooter dead; `weapon_id ≠` server inventory
   `current_id()`; server inventory cannot fire (empty mag / reloading); RateLimiter refuses
   (rate = fire_rate, burst = 2); `ShotValidator.is_valid` false (head_pos = `player.head.global_position`).
   Accepted shots consume a server round. Rejections increment `rejected_shots: int`.
2. Inventory is server-authoritative: buy (`buy_enabled` read from the `match` group node, default
   allowed when absent), pickup (world weapon exists, armed, within 2.0 m of the player on the
   server), drop, swap, equip and reload go through `_server_*` handlers; the server pushes the full
   inventory to the owner (`_sync_inventory(d: Dictionary)`) after each change and after any
   rejected shot. The owner predicts locally for responsiveness and adopts the server state on sync.
3. World weapons are networked: server allocates a uid, spawns on all peers
   (`WorldWeapon.uid`, static registry `WorldWeapon.find(uid)`), despawns on all peers on pickup.
   Clients only *request* pickups (auto when a slot is free, F to swap), never mutate inventory.
4. Weapon timers in `_physics_process`; automatic fire driven by `FireClock`.
5. Backward-compatible read API for `GameHUD.gd` / `PlayerCamera.gd` (not in this slice):
   `cfg()`, `current_aim_fov()`, `is_scoped()`, signals `ammo_changed(ammo, reserve)`,
   `weapon_changed(cfg)`, and read-only views `weapons: Array` (WeaponConfig or null per slot),
   `mag: Array`, `reserve_a: Array`, `current: int`.
6. `_show_hit` is server → shooter only. `_damage_at` replaced by `WeaponMath`.

## S1b acceptance (abilities, health, match)
1. `PlayerController._enter_tree`: after the recursive owner authority, set authority 1 on
   `Health`, `Weapon` and `Abilities`. `net_respawn` ignores callers other than peer 1.
2. Agent identity: `PlayerController.agent_index: int = -1` and `team` replicated at spawn only
   (SceneReplicationConfig `spawn = true`, `replication_mode = 0`). Clients send their
   `AgentDatabase.selected_index` in `_request_spawn(agent_index)`; the server clamps invalid
   values to 0; the host uses its own selection. `AgentDatabase.get_by_index(i) -> AgentConfig`.
3. `Ability` gets `activate_local(player)` (owner: movement/cosmetics) and
   `activate_server(player)` (server: gameplay effects); `activate()` is removed. Heal: server
   heals `HealAbility.AMOUNT` (60). Surge: server heals to max, owner jumps. Wall: server builds
   the barrier from its own view of the player transform with constants in `WallAbility`
   (size, distance, duration, colour) and broadcasts it; clients can no longer choose size/position.
   Dash: owner only.
4. `AbilityController` keeps a server `AbilityState` (authoritative) and an owner copy
   (prediction). Owner: if the local state allows, `activate_local` + local `try_activate` +
   request; server: `_server_activate(sender, i)` checks owner, alive, `try_activate`, runs
   `activate_server`, then pushes `to_dict()` to the owner. Ult charge on kills =
   `server_add_ult(points)` called by `GameWorld` (server-side, then pushed). `slot_info()` API
   unchanged for the HUD. Timers in `_physics_process`.
5. `Health.request_heal` removed; `heal(amount)` stays server-only API.
6. `GameWorld`: `@export var buy_enabled: bool = true`; `request_reset` only runs when there is no
   game mode or the mode has a winner (`winner != -1`), and only for a sender present in `player_info`.

## S3 acceptance (perf)
- `project.godot`: `physics/common/physics_ticks_per_second=60` explicit; autoload
  `Perf="*res://scripts/core/PerfOverlay.gd"` (F3 toggles: fps, frame ms, 1 % low, draw calls,
  physics tick, ping when client). Uses `FrameStats`.
- `scenes/levels/benchmark.tscn`: comp map geometry + 8 dummies, 3 s warm-up then 20 s scripted
  camera path; prints one line `BENCH avg_fps=… low1=… p99_ms=… draw_calls=… objects=…` and writes
  `user://benchmark_<unix>.json`, then quits.
