# Round 4a contract — training & tutorial, map ambience, combat feedback

Read first: `.orchestrator/session.md`, `.orchestrator/contract-p0.md` (network rules),
`.orchestrator/design.md` (locked art/UI direction), `docs/ROADMAP.md` (P3.11, P3.12, P5.1, P5.2).
Godot 4.7 typed GDScript, French strings/comments, no TODO/placeholder. Tests first for pure
logic. Gates: your tests green, WHOLE suite green (`bash tools/test.sh`), `--check-only -s` on your
scripts, headless boot (`--quit-after 300`) of main_menu, test_arena, one map per mode and your new
scenes with zero SCRIPT/SHADER ERROR, `tools/net_smoke.gd` ok=true, `tools/bot_smoke.gd` still
reports kills > 0 and errors=0. `GODOT_BIN=/c/Users/srko/Desktop/Godot_v4.7-stable_win64.exe`.
Screenshots → `C:/Users/srko/AppData/Local/Temp/claude/C--Users-srko-Desktop-fps/02e156fb-5e66-4722-9835-071a024d62a9/scratchpad/shots/r4/`.

A character-art builder is concurrently writing `tools/blender/make_characters.py`,
`assets/models/characters/**`, `tools/character_shots.gd` — nobody else touches those.

| Slice | Owns (write) |
|---|---|
| **R4-TRAIN** | new `scenes/levels/training/**`, new `scripts/training/**`, `tests/training/**`, `scripts/ui/MainMenu.gd` (training entry only) |
| **R4-AMB** | `tools/audio/**`, `assets/audio/**`, `scripts/core/Audio.gd`, `tests/audio/**` |
| **R4-FX** | `scripts/ui/GameHUD.gd`, `scripts/ui/hud/**`, `scripts/ui/{Comic,ComicBurst}.gd`, `scripts/combat/Health.gd`, `tests/ui/**` |

## R4-TRAIN — Terrain d'entraînement (P5.1/P5.2)
A new training scene (replaces test_arena as the menu's "Terrain d'entraînement"; keep test_arena
untouched — tools depend on it) built with the map kit (`scripts/levels/maps/Kit.gd`, read only)
in the "encre et papier" look, offline host like today (GameWorld, agent select skipped, free buy):
1. **Parcours de mouvement** guided step by step with on-screen prompts (French, key labels from
   the player's real bindings via Settings/DisplayServer): sprint, slide, slide-cancel,
   slide-jump, air-strafe, dolphin dive over a gap, roll on landing to cancel the fall stun,
   dive across an 8 m gap. Each step detects success from the player's state machine/velocity.
2. **Contre-la-montre**: a timed movement course with checkpoints, best time saved locally
   (user://), ghost-free, restart key; three medal times (Or/Argent/Bronze).
3. **Stand de tir**: static and moving dummies at 5/15/30/50 m, hit/headshot stats and DPS
   readout, weapon rack (all 10 weapons), reset button.
4. **Capacités**: a corner where each agent's abilities can be tried against dummies.
Pure logic (step detection, timer/medals, stats) tested in tests/training/. Screenshots of each area.

## R4-AMB — ambiences et musique (P3.12)
Generate (same fixed-seed synthesis pipeline as `tools/audio/gen_sfx.py`) one seamless 60–90 s
ambience loop per map (Port-Ferraille: water lapping, distant gulls, metal creaks; Val-Poussière:
dry wind, shutters, distant windchime; Saint-Ombre: rain, drips, far thunder; Col du Vautour:
mountain wind gusts, flag flapping; La Fosse: quarry wind, gravel trickles; Le Belvédère: city
dawn hush, birds) plus a short match music sting set (match start, last minute, victory, defeat)
and an in-game low-intensity percussive loop for the last minute. `Audio.gd` plays the ambience
of `MatchConfig.map_id` when a map scene is current (Music/SFX buses, respecting Settings
volumes), crossfades on scene change, silences it in menus (menu loop instead). Same loudness
checks as before. Tests for pure helpers.

## R4-FX — retours de combat (P3.11 + HUD)
1. Server-confirmed hit marker at the crosshair (ink tick, headshot variant heavier, kill variant
   = cross), 120–200 ms, driven by `Weapon.hit_confirmed` of the local player.
2. Damage direction indicator: ink wedge on a ring around the centre pointing toward the damage
   source, fading over 1 s. Add to Health a server → owner authority RPC carrying
   `(amount, source_position)` when a player takes damage (keep the existing `damaged` server
   signal); the local HUD listens.
3. Low-health ink vignette (hatching creeping from the edges under 35 % HP, pulse ≤ 1 Hz,
   disabled when Settings reduced motion exists — read `Settings.get("reduced_motion")` safely).
4. Kill feedback: on a LOCAL kill, a hand-lettered sound word (Protest Revolution) — "PAF!",
   "BLAM!", "CRAC!" (headshot), "VLAN!" — in a small ComicBurst, ≤ 300 ms (60 in / 180 hold / 60
   out), placed OUTSIDE the centre 40 %×40 % zone, one at a time; killfeed entry highlighted.
5. Respect design.md: centre zone clean except the crosshair/hit marker, motion rules, ink/paper
   tokens. Pure helpers tested in tests/ui/ (angle → wedge, fade curves, word choice).
   Screenshots of each feedback element (use a debug trigger).
