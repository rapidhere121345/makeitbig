# Hardware GPU Visual Acceptance - High-Resolution Stress Round - 2026-10-20 (R2)

Round one: [GPU_VISUAL_2026-10-20.md](GPU_VISUAL_2026-10-20.md). At 1920×1080 (Xvfb `:97` + NVIDIA vendor library; engine.log records RTX 4080 SUPER), two vision models each performed one interactive pass **serially**, with only one game instance at a time: glm-5.3-flash#max (`build/current/gpu-visual-r2-glm/`, about 40 minutes) and deepseek-flash#low (`build/current/gpu-visual-r2-ds/`). Protocol as before: play_session window commands and frame-by-frame screenshot inspection.

## Conclusions

- **No artifacts at 1.5× fractional scaling:** both independently found no blur, uneven aliasing, or flicker in HUD text, sprite edges, or icons at inspected magnifications.
- All five town facilities, both combat rooms, results, dialogue, and bridge-rail boundaries were traversed without text truncation or panel overflow.

## Cross-Checks and Fixes

| # | Severity | Finding | Verification | Treatment |
|---|---|---|---|---|
| 1 | Serious | **Frozen post-victory controls, remaining enemies attacking, internal pickup error key:** after elite-hunt victory, `active()` cut Manual movement despite a loot window requiring approach + F; surviving fan-shot hunters kept attacking; `loot_out_of_range` was unlocalized | DeepSeek reproduced | Fixed: `collect_commands` retains movement during victory + open loot window, while attacks stay locked; CombatPhasePort adds `room_terminal_locked()` and skips terminal enemy AI phases; pickup errors localized for out of range, already requested, and closed window |
| 2 | Serious | **Foreground reveal failed on hardware:** snow-covered rocks completely hid the hero at Mira's dialogue point. Search began at `mounted_scene`, but foreground nodes had been reparented to the world presenter, so DFS missed them (`node=false`, diagnostic log evidence) | DeepSeek reproduced; flash pixel difference confirmed 100% opacity | Fixed: search from SceneRuntime, whose subtree contains both mounted scene and presenter. Afterward `node=true`; flash reinspection confirmed translucent coverage, visible ghost silhouette, and identifying features. One Loadout shed position could not be reached due to collision and was not reproduced; no action there |
| 3 | Normal | **Dialogue/progression Esc failed:** button copy advertised Esc but no Shortcut was bound; focused controls consumed it | Both reproduced; DeepSeek found broader scope | Fixed: direct ESC Shortcuts on dialogue "Talk later Esc" and progression "Back Esc" |
| 4 | Normal | **Kill label overlapped damage numbers at the same point** | Both reproduced | Fixed: widened death-text offset from 15 to 34px |
| 5 | Medium | Long room-entry text hard-clipped by right panel in salvage ring | DeepSeek | Fixed: RoomStartLabel uses `clip_text + OVERRUN_TRIM_ELLIPSIS` |
| 6 | Polish | Close-contact friend/foe readability, snow hero contrast, content margins, stale objective, entry-card fade residue | Single report or low risk | Backlogged |

## Notes

- DeepSeek could not reach GLM's "invisible hero in Loadout shed" position because collision blocked it, so that case was judged not an issue. The resulting search-root fix (2) nevertheless made reveal work for all foreground pieces.
- "Locked Tempering Anvil still interactive" and "nameplate remains unverified after training" could not be classified as intentional; design confirmation remains needed.

## Gate

Deliver after full `container_test.sh` passes (600/600 matrix, historical replay goldens unchanged), both platform exports, and Linux empty-directory smoke.
