# GPU Window Playtest and Redesign UX Acceptance - 2026-10-18

Three NVIDIA host-window rounds cover the current Ranger first chapter: art hierarchy, Chinese UI readability, combat decisions, Hearthside occlusion, Contract entry, results, and input feedback. Playtesting did not change simulation, runtime, systems, content, tests, release, or deployment directories.

## Environment and Entry

- `DISPLAY=:0`, X11 window.
- Godot `4.7.2.stable.official.ed1daf0bf`.
- Startup confirmed `OpenGL API 3.3.0 NVIDIA 595.91.07 - Compatibility - Using Device: NVIDIA - NVIDIA GeForce RTX 4080 SUPER`.
- `Dummy` audio.
- Actual entry:

  ```bash
  source scripts/project_env.sh
  __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia \
    "$GODOT_BIN" --display-driver x11 --rendering-method gl_compatibility \
    --audio-driver Dummy --path "$MIB_PROJECT_ROOT" \
    --script res://tools/play_session.gd
  ```

## Three Rounds: Steps and Results

### Round 1: 1280×720 Basic Flow, Occlusion, Discovery

Session: `build/current/gpu-ux-review-20261018-final/`, with full-flow evidence in `build/current/acceptance-20261018/round-a-0512/`. Clicked New Game - Enter the Coldfield; used arrows/`D` to move, `Shift` to dodge, `Space` or mouse to cast, then Enter Hearthside. Walked `WASD` around walls, fences, and logs to confirm position-dependent front/back occlusion. `E` opened Contracts; Accept Contract - Depart and Confirm Departure - Enter began Manual combat.

At 1280×720, entry hint, top HP/room information, upper-right exit/report, and lower-right skills stayed safe. After the entry hint faded, enemies, target rings, arrows, and damage appeared together. `Space` with movement/dodge changed enemy health. Opening the report exposed duplicated normal-room target/alive information, weak range distinction, and retained button focus that could reopen Report on the next `Space`.

### Round 2: Post-Fix 1280×720 to 1600×900

Session: `build/current/gpu-ux-review-20261018-final-after/`. Repeated title, tutorial, town traversal, and Contract confirmation. Opened `Report TAB` in combat, checked target summary, then resized to 1600×900 to inspect report/skill-bar positions.

Duplicate target line disappeared. Target name, current/max health, and in/out-of-range status were unclipped at both resolutions. At 1600×900, report did not cover skills; transition card was centered with clear hierarchy. Evidence: `round3-summary-dedup-1280.png`, `round3-summary-dedup-1600.png`.

### Round 3: Focus Regression, Second Room, 1600×900 Results

Session: `build/current/gpu-ux-review-20261018-final-post/`. Repeated title, tutorial, and town traversal, adjusting multiple `WASD` segments around walls/logs until reaching the Board; no simulation-data jump. Opened and closed `Report TAB`, then pressed `Space` for 10 frames to confirm no retained report-button keyboard focus; UI operations did not change enemies. Resized to 1600×900, reopened report, then completed both rooms with `Space + Shift` and directional attacks through transition to results.

Final `route=result`, `window=(1600,900)`. Victory, rooms 2/2, kills/casts, Depart Again, and Return to Base were visible. The target line was highlighted light, with amber out-of-range feedback, separating immediate decisions from ordinary gray text. Evidence: `round3-final-1600-summary.png`, `round3-result-1600.png`, `input.jsonl`.

## Findings and Implemented Fixes

- Normal rooms formerly showed only remaining targets, obscuring current target/health/range in melee overlap. Valid targets now show name, current/max health, and range; absent targets fall back to remaining count, with distinct shootable/out-of-range colors.
- Normal-room Boss damage duplicated target/alive data; that meaningless row is hidden. Boss rooms retain real Boss damage.
- Report, exit, and skill buttons no longer take keyboard focus, avoiding subsequent `Space` as UI confirmation.
- UI hit testing accepts the event's screen coordinates. Hits on interactive HUD controls promote UI ownership, avoiding stale-hover click-through. Explicit caller HUD ownership retains priority; held world-drag/pause-over-HUD semantics remain unchanged.
- No Chinese clipping, skill overflow, report-over-skills overlap, or squeezed results buttons at 1280×720 or 1600×900.
- Town snow, tower, fences, logs, and character depth were clear. World arrow hides at the Board; local interaction guides the next step.
- Brief combat-entry coverage of center is intentional room-entry feedback and automatically clears rather than persistently blocking decisions.

## Changed Files

- `src/presentation/arena_hud.gd`: retains target colors, removes normal-room duplicates, adds event-coordinate HUD hit query.
- `src/presentation/combat_input_adapter.gd`: remembers mouse-move coordinates; supplements UI hit testing while preserving explicit HUD ownership and Manual command boundaries.
- `src/presentation/combat_presentation_controller.gd`: pointer-ownership queries accept optional event coordinates, returning only presentation readings.
- `docs/playtest/GPU_WINDOW_2026-10-18_REDESIGN_UX_REVIEW.md`: independent round record.

## Evidence Index

All are ignored local build/playtest evidence:

- 1280 tutorial/Contract/combat: `build/current/gpu-ux-review-20261018-final/round1-tutorial-complete-1280.png`, `round1-contract-1280.png`, `round1-contract-confirm-1280.png`, `round1-combat-1280.png`.
- 1280/1600 reports: `build/current/gpu-ux-review-20261018-final-after/round3-summary-dedup-1280.png`, `round3-summary-dedup-1600.png`.
- 1600 combat/results: `build/current/gpu-ux-review-20261018-final-post/round3-final-1600-summary.png`, `round3-result-1600.png`.
- GPU/stages: `build/current/gpu-ux-review-20261018-engine-capture-2/engine.log`, `build/current/gpu-ux-review-20261018-final-post/input.jsonl`, `build/current/gpu-ux-review-20261018-final-post/state.json`.

## Commands and Results

- `source scripts/project_env.sh && ./scripts/check.sh`: passed, including `PASS tools/play_session.py syntax`.
- `git diff --check`: passed.
- Targeted presentation tests all PASS: `test_arena_hud.gd`, `test_combat_presentation_boundary.gd`, `test_arena_combat_presenter.gd`, `test_input_feedback_transients.gd`, `test_presentation_occlusion_boundary.gd`, `test_tutorial_pointer_cast.gd`, `test_manual_combat_input.gd`.
- Full test entry:

  ```bash
  MIB_TEST_TIMEOUT_SEC=1800 \
    MIB_TEST_LOG=build/current/container-test-final.log \
    ./scripts/container_test.sh
  ```

- Full result: `test gate passed: exit 0, no GDScript runtime errors`. 600 rooms / 100 seeds repeated-combat matrix, auto replay, and results regression passed. Existing ObjectDB/resource cleanup warnings remain. `CAPTURE_FAIL` / `AUTO_SMOKE_FAIL` are expected negative headless-capture cases, not script errors.
- `./scripts/container_export.sh`: passed; export packages generated.
- `./scripts/container_smoke.sh`: passed, `SCENE_SMOKE_PASS framework=routes,builds,contract,persistence route=title`.
- `./scripts/release.sh all --note "GPU UX acceptance 2026-10-18 final"`: passed; generated build for final HEAD and refreshed `build/releases/`. Actual ID: `build/releases/index.json`.
- `./scripts/release.sh verify --deep`: passed, SHA256 verified for 20 builds.
- `./deploy/tailscale/validate.sh`: passed; static validation only, no host network exposure enabled or changed.
- All three playtest processes exited normally via `MIB_PLAY_SESSION_DIR=... python3 tools/play_session.py '{"quit":true}'`; no Godot windows remained.

## Unresolved Limits

- Stable pointer firing in a real GPU window is not fully accepted. Event coordinates prevent obvious HUD clicks becoming world attacks, but close moving targets, blank clicks, and rapid motion still lack a stable attributable firing regression.
- `Dummy` audio; no real sound, mixing, or audiovisual-sync acceptance.
- Windows hardware and post-publication acceptance were excluded as requested; no `release/` or `deploy/` changes.
