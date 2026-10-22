# Hardware GPU Visual Acceptance - Fix Recheck - 2026-10-20 (R3-GLM)

Third interactive hardware-GPU pass, focused on six fixes and full-flow regression. Previous record: [GPU_VISUAL_2026-10-20-R2.md](GPU_VISUAL_2026-10-20-R2.md). Same method: Xvfb display + NVIDIA PRIME offload hardware rendering, play_session window protocol injecting inputs and inspecting screenshots frame by frame. Ignored evidence directory: `build/current/gpu-visual-r3-glm/`, 62 frames and 307 input records.

## Environment

| Item | Value |
| --- | --- |
| Display | Xvfb `:97`, 1920×1080×24 (`xdpyinfo` connection confirmed) |
| Entry | `MIB_PLAY_SESSION_DIR=build/current/gpu-visual-r3-glm ./scripts/play_session_window.sh --nvidia --display :97` |
| Renderer | First two engine.log lines: `Godot Engine v4.7.2.stable.official` / `OpenGL API 3.3.0 NVIDIA 595.91.07 - Compatibility - Using Device: NVIDIA - NVIDIA GeForce RTX 4080 SUPER` |
| Window | 1280×720 (runner default; no higher-resolution stress this round) |
| Exit | `runner.exit.json` status=0; existing ObjectDB/resource-leak exit warnings, recorded previously and not introduced here |

## Six Fix Verdicts

| # | Fix | Verdict | Frame evidence |
| --- | --- | --- | --- |
| 1 | Dialogue character column anchored to interaction target | **Pass** | `017`: Mira dialogue line 2/4 is spoken by Wanderer; title is Wanderer, column is **Talking to Mira - Close the Door First**, formerly Wanderer - Wanderer. `021`: Mira is a third-party speaker in Leia line 2/3, while column stays Talking to Leia - Where to Put the Stool. Esc closure (`018`) works |
| 2 | Training nameplate "verified" semantics | **Partial, save-progress limited** | See below |
| 3 | Last Tab-report line clipping | **Pass** | Enlarged `053`/`054`: complete "Growth type Unverified - iteration length g=80", clear bottom whitespace, scrollbar at bottom |
| 4 | Last "Recent" panel line against edge | **Pass** | `030`/`031`: 25 extra scroll notches after the bottom produce pixel difference None, confirming the end; clear space between final shortcut line and buttons |
| 5 | Arena concept border / gate markers | **Pass** | Enlarged `039`: copper corner dots and perpendicular 34px ticks, no complete wireframe. `040`: gate has two square pillars, threshold line, and inward arrow, not a U-shaped debug line |
| 6 | Stale out-of-range hint | **Pass** | `037`: firing out of range shows "Target out of range - move closer" and matching top status. Stand still as enemy approaches; in `038`, badge disappears in the same frame the top changes to in range, without contradiction |

### Fix 2: Verified Nameplate

- Fresh, untrained save: nameplate, combat report, and Recent progression all agree on unverified/… (`010`/`019`/`064`/`030`), as expected for an untrained save.
- Training was completed once (`022`/`023`); default build converged rather than grew exponentially. Nameplate stayed unverified, consistent with growth conclusion and report "Growth type Unverified," demonstrating unified derivation.
- **Exponential path could not be triggered:** the exponential calibration preset selector exists only in the legacy loadout without real equipment data (`facility_screen.gd _build_loadout` branch), not the current save UI. Other verified conditions (first Colossus kill, Auto victory, early completion) are later in the chapter. Recommend a positive "nameplate=verified" screenshot using an exponential-preset save or auto-smoke pipeline.

## Regression Sweep (All Passed)

- **Title to tutorial:** approach, dodge, and piercing-hit exercises complete; no clipped text in `001`-`005`.
- **Five Hearthside facilities:** visited and read Contract Board, Loadout, Tempering Anvil, Training, Proxy Bay signs. Proxy Bay correctly says it opens after first Colossus kill (`058`); Anvil says Law Token Forge locked - complete main step 04 (`061`).
- **Dialogue:** all four Mira and three Leia lines inspected; portraits, page numbers, and buttons do not overlap. Esc closes dialogue, discoveries, and progression (R2 regression).
- **Occlusion reveal:** hero and Mira behind rocks; covering region becomes brighter/translucent, showing silhouette and white hood/bow (`059`/`060` enlarged). R2 reveal fix reproduces well on hardware.
- **Departure:** Contract page (`032`) and confirmation card (`033`) lay out normally; Manual-lock notice correct.
- **Combat:** completed main 01/02 in Manual, four rooms total. Damage numbers ("232" in `055`) readable without health-bar overlap. Enemy pursuit works without stuck turning. No post-victory control freeze; results open directly (R2 fix 1 passes).
- **Two results pages** (`048`/`056`): rewards, room progress, duration/kills/casts readable.
- **Discoveries/progression** (`062`/`063`): normal layout; chapter objective advances from completed First Hunt to compare returned equipment, incidentally validating `_displayed_objective_text` stale-objective fix.
- No artifacts, ghosting, color anomalies, or fractional-scale blur observed throughout.

## New Findings

| # | Severity | Symptom | Reproduction | Recommendation |
| --- | --- | --- | --- | --- |
| 1 | Normal | Expanded results report clips the final Next Step card line to half-height (`049` full / `050` enlarged, residual text below continue research at Training) | Any Contract victory, results, report details | Add bottom gutter or ellipsis like Tab report / Recent |
| 2 | Polish | Room 1 to Room 2 checkboxes remain empty despite both rooms won, mildly contradicting Victory below (`048`) | Same | Confirm intent; otherwise check on victory |
| 3 | Needs confirmation | Neither victory showed approach + F loot window; results opened directly, unlike R2 | Main 01/02 Manual, kiting may already have crossed drop points | Specifically check loot-window triggers, drop distance, and automatic pickup semantics |

## Notes

- Build-details modal consuming Return to Base clicks is normal modal behavior. Its buttons are absent from play_session scanning, a protocol blind spot rather than a game defect; raw-coordinate clicking closes it.
- Kills occurred but no exact kill frame was captured, so R2 fix 4's kill-text offset was not rechecked; previous round already has pixel evidence.
- Existing snow-contrast and close-contact overlap backlog items remain visible; these are unfixed items, not regressions.
- Delivery gate: acceptance only, no code changes this round. Full `container_test.sh` and exports rely on the latest all-green build record.
