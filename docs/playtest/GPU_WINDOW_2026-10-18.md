# Hardware GPU Window Playtest - 2026-10-18

## Entry and Evidence

- Display: `DISPLAY=:0`, X11; `xdpyinfo` connected successfully.
- Godot: `4.7.2.stable.official.ed1daf0bf`.
- Renderer: `OpenGL API 3.3.0 NVIDIA 595.91.07 - Compatibility`.
- GPU: `NVIDIA GeForce RTX 4080 SUPER`.
- Audio: `Dummy`.
- Window entry:

  ```bash
  source scripts/project_env.sh
  MIB_PLAY_SESSION_DIR=build/current/gpu-playtest-20261018 \
    __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia \
    "$GODOT_BIN" --display-driver x11 --rendering-method gl_compatibility \
    --audio-driver Dummy --path "$MIB_PROJECT_ROOT" \
    --script res://tools/play_session.gd
  ```

- Startup output: ignored `build/current/gpu-playtest-20261018/postfix-engine.log`; normal exit code `0`.
- Events/results: `build/current/gpu-playtest-20261018/log/session-1792268966952-3162760.jsonl`.
- Screenshots: `town-after-victory.png`, `combat-1280-target.png`, `combat-1600-target.png`, `combat-1600-summary.png`, `result-victory.png`.

## Actual Steps and Observations

1. Entered tutorial from title; moved with `D`, dodged with `Shift`, clicked a target to cast, then entered Hearthside.
2. Walked multiple `WASD` segments to the Contract Board, observing front/back occlusion at walls, fences, and logs; opened Contracts with `E`. `[E / Space] Enter Contract Board` was visible without UI obscuring the character.
3. Chose `Manual` and main step 02, Priorities Under Pressure. Cast with `Space` and dodged with `Shift` at 1280×720; completed two rooms with victory.
4. Original issue: normal rooms showed only Remaining targets N. Overlapping melee enemies, target ring, sprites, and hit effects made current target and remaining health hard to identify.
5. At 1280×720 after the fix, the entry hint disappeared and the top showed `Current target  Charging Raider  ·  420 / 420  ·  In range`, falling back to `Remaining targets  0` after the kill. Both matched the visible target.
6. Resized to 1600×900. Target line remained complete; `Report TAB` stayed readable on the right and clear of the bottom skill bar. Clicking Report changed only the summary panel/focus, not enemy health or combat, confirming UI clicks did not leak into world attacks.
7. Fixed main step 02 result: `Victory`, `Elapsed 19.80 seconds`, `Kills 4`, `Casts 13`, `Room progress 2/2`. Return to Base went to Hearthside; growth points rose from 2 to 3. Event log records `Manual`, both rooms `victory`, and `result -> base`.

## Changes in This Round

- `src/presentation/combat_presentation_frame_builder.gd`: projects public enemy name/current/max health from existing presentation-target selection, still sourced from the authoritative snapshot.
- `src/presentation/arena_hud.gd`: normal-room target bar shows target, health, and range; no valid target falls back to remaining count. Boss ratio logic unchanged.
- `docs/playtest/GPU_WINDOW_2026-10-18.md`: records hardware-window steps, observations, and evidence.

No changes to `src/runtime/**`, `src/systems/**`, test authority, release configuration, or deployment files. Existing workspace changes to `docs/GRAPHICAL_VALIDATION.md` were preserved.

## Checks

- `source scripts/project_env.sh; ./scripts/check.sh`: passed.
- `git diff --check`: passed.
- Targeted Godot checks all passed: `test_arena_hud.gd`, `test_combat_presentation_boundary.gd`, `test_presentation_production_assembly.gd`, `test_input_feedback_transients.gd`, `test_arena_combat_presenter.gd`, `test_presentation_occlusion_boundary.gd`.
- Godot still printed existing `ObjectDB instances were leaked` / `resources still in use` exit warnings. Window exit code remained `0`; warnings were not treated as playtest pass criteria.

## Unresolved Limits

- Keyboard Manual was the reliably rechecked path. Pointer aiming with blank clicks, close targets, and moving targets did not yield sufficiently stable attributable reproduction. No input/combat authority changes were made across the presentation boundary; this path still needs separate acceptance.
- Release-page builds, exports, and publication commits belong to the parent agent's release workflow. This record covers only real-GPU windows and presentation rechecks.
