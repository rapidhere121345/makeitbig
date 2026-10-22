# Hardware GPU Acceptance R3 - Backlog Fix Recheck

- Date: 2026-10-20
- Operator: Paseo opencode provider, `zhipuai-coding-plan/glm-5.3-flash` thinking=high (supplemental vision model, not Devin GLM)
- Display: Xvfb `:97` 1920×1080, window 1280×720
- Engine/renderer: Godot 4.7.2 stable; engine.log records `OpenGL API 3.3.0 NVIDIA 595.91.07 - Compatibility - Using Device: NVIDIA - NVIDIA GeForce RTX 4080 SUPER`
- Audio: Dummy driver
- Session: `build/current/gpu-visual-r3-glm/` (62 frames + 307 inputs), normal exit status=0
- Detailed GLM report: [GPU_VISUAL_2026-10-20-R3-GLM.md](GPU_VISUAL_2026-10-20-R3-GLM.md)

## Scenarios

Title → tutorial → Hearthside (five facilities, Iven/Mira/Leia dialogue including player lines, nameplates, occlusion reveal) → Recent panel scrolling → Contract departure confirmation → two Contracts/four rooms all won in Manual → two results pages → discoveries/progression.

## Fix Verdicts

| Fix | Verdict |
| --- | --- |
| Dialogue column anchored to interaction target ([E] mismatch) | Pass: player lines show Talking to Mira - Title; third-party lines remain anchored |
| Report last-line clipping | Pass: complete final line and bottom space |
| Recent panel final scrolled line | Pass: no clipped pixels at bottom |
| Concept-border/gate debug-line appearance | Pass: corner posts + ticks; pillars + threshold + arrow |
| Stale out-of-range toast contradicting in-range status | Pass: disappears in same frame as entry into range |
| Training "verified" nameplate | Partial: untrained save consistently unverified in three places; design-side positive screenshot still needs an exponential-build save |

Incidental checks passed for stale objectives, occlusion reveal, and R2 Esc/victory-freeze regressions; the sweep reported no text truncation or artifacts.

## New Findings (Backlogged)

1. Normal: final line of results report's Next Step evidence card clips to half-height.
2. Polish: room-result checkboxes remain empty on victory.
3. Needs confirmation: no F pickup window in two Manual wins, unlike R2 (possibly drop position/window timing, not an established regression).

## Code Validation

- `tests/run_all.gd` aggregate passed without SCRIPT ERROR; `test_enemy_runtime` adds `_test_melee_stuck_escape_intent` to pin geometric stuck-enemy escape (`melee_escape_slot` / `melee_annulus_escape`).
- `./scripts/check.sh` passed; `./scripts/container_build.sh` all green (tests, 600/600 victory matrix, exports, smoke); replay golden unchanged: `b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`.
