# Comprehensive Hardware GPU Window Acceptance - 2026-10-18

Three host-window playtests after presentation fixes, using real NVIDIA rendering rather than fabricated screenshots.

## Host and Startup Evidence

- Display: DISPLAY=:0, X11; xdpyinfo connected successfully.
- Godot: 4.7.2.stable.official.ed1daf0bf.
- Renderer: OpenGL API 3.3.0 NVIDIA 595.91.07 - Compatibility.
- GPU: NVIDIA GeForce RTX 4080 SUPER.
- Audio: Dummy; acceptance covers visuals, input, feedback timing, and UI behavior only.
- Startup:

  ~~~bash
  source scripts/project_env.sh
  __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia \
    "$GODOT_BIN" --display-driver x11 --rendering-method gl_compatibility \
    --audio-driver Dummy --path "$MIB_PROJECT_ROOT" \
    --script res://tools/play_session.gd
  ~~~

- Direct startup evidence: build/current/gpu-ux-review-20261018-engine-capture-2/engine.log; exit.txt records capture_exit=0.
- Each round's input.jsonl and state.json are in ignored build/current/ directories.

## Round 1: 1280×720 Complete Flow and Discovery

Evidence: build/current/acceptance-20261018/round-a-0512/ and build/current/gpu-ux-review-20261018-final/.

Steps: title to tutorial; D movement, Shift dodge, mouse target/cast; after tutorial, enter Hearthside. Multiple WASD segments around walls, fences, and logs reach the Contract Board; E opens Contracts, confirmation enters Manual. Movement, clicks, and Space advance two rooms and results.

Result: title, tutorial, town, and Contract page readable at 1280×720 without Chinese clipping. Town depth clear; UI does not cover interaction points. Combat exposed duplicated normal-room target/alive counts, weak range distinction, and possible retained Report-button keyboard focus.

Screenshots:

- build/current/gpu-ux-review-20261018-final/round1-tutorial-complete-1280.png
- build/current/gpu-ux-review-20261018-final/round1-contract-1280.png
- build/current/gpu-ux-review-20261018-final/round1-contract-confirm-1280.png
- build/current/gpu-ux-review-20261018-final/round1-combat-1280.png
- build/current/acceptance-20261018/round-a-0512/result-1600x900.png

## Round 2: Fix Recheck and 1600×900 Layout

Evidence: build/current/gpu-ux-review-20261018-final-after/.

Repeated title, tutorial, town route, and Contract entry. Opened Report in combat to inspect normal-room target summary, then resized to 1600×900 to check scrolling panel, skills, and transition.

Result: duplicate target row removed; target name, current/max health, and range status unclipped at 1280×720 and 1600×900. Right report stays clear of skills; transition card centered with clear hierarchy.

Screenshots:

- build/current/gpu-ux-review-20261018-final-after/round3-summary-dedup-1280.png
- build/current/gpu-ux-review-20261018-final-after/round3-summary-dedup-1600.png

## Round 3: Focus Regression, Second Room, 1600×900 Results

Evidence: build/current/gpu-ux-review-20261018-final-post/.

Repeated tutorial and town route. Opened/closed Report, pressed Space for 10 frames to confirm no focus-induced reopening; resized to 1600×900 to inspect target line, skills, pause, and right panel; completed both rooms and results.

Result: final route=result, window=(1600,900). Victory, rooms 2/2, kill/cast statistics, Depart Again, and Return to Base fully visible. Target is light-colored in range, amber out of range.

Screenshots/logs:

- build/current/gpu-ux-review-20261018-final-post/round3-final-1600-summary.png
- build/current/gpu-ux-review-20261018-final-post/round3-result-1600.png
- build/current/gpu-ux-review-20261018-final-post/input.jsonl
- build/current/gpu-ux-review-20261018-engine-capture-2/engine.log

## Findings and Implemented Fixes

- Hide meaningless normal-room Boss damage row, removing duplicate target summary.
- Add target-state colors for in/out of range.
- Exit, Report, and skill buttons reject keyboard focus so Space after a tool click is not consumed by GUI.
- Presentation rechecks interactive control hits with event coordinates and passes them into HUD queries, reducing stale-hover click-through.

Changed files:

- src/presentation/arena_hud.gd
- src/presentation/combat_input_adapter.gd
- src/presentation/combat_presentation_controller.gd
- docs/playtest/GPU_WINDOW_2026-10-18_UX_ACCEPTANCE.md

No changes to src/game, src/runtime, src/systems, content, tests, release, or deploy. Alpha, Y-sort, Sprite bounds, and UI state were not allowed to influence simulation facts.

## Validation Commands and Results

- Targeted tests passed: test_arena_hud.gd, test_combat_presentation_boundary.gd, test_arena_combat_presenter.gd, test_input_feedback_transients.gd, test_presentation_occlusion_boundary.gd, test_tutorial_pointer_cast.gd.
- scripts/check.sh passed, including tools/play_session.py syntax probe.
- git diff --check passed.
- All three GPU sessions exited 0. Existing ObjectDB instances were leaked / resources still in use warnings remained; no SCRIPT ERROR.

## Unresolved Limits

- Windows hardware and post-publication acceptance skipped as requested.
- Dummy audio; no real sound, mixing, or audiovisual-sync acceptance.
- Mouse aiming against close moving targets, blank clicks, and rapidly moving targets still lacks a stable attributable regression path. This round confirms event coordinates stop obvious UI click-through; complete mouse combat feel needs a later independent playtest.
