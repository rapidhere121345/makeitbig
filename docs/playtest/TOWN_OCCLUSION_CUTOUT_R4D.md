# Hearthside Occlusion Cutout Recheck - R4D

- Date: 2026-10-21
- Operator: Paseo opencode (GLM) hardware-vision acceptance inspector, one-off delegation, no further agents.
- Purpose: recheck R4C's failed cutout. `##` comments caused shader compile failure and opaque fallback; confirmed four lines changed to `//` at `src/presentation/occlusion/occluder_cutout.gdshader:3-6`. Reused R4C route, retaining R4B/R4C collision expansion. Scope: shader compilation, cutouts, collision regression; no code/assets changed.
- Session: `build/current/town-cutout-r4d/`, three window sessions sharing tutorial-complete base save:
  - session1, `engine.session1.log`: replayed all 258 R4C input.jsonl commands with per-command frames `000.png`–`257.png`; found south-shore crevice below.
  - session2, `engine.session2.log`: targeted loadout/tree_wood/Board/forge/proxy/tree_east/east cliff/reef/deck/tree_south/tree_sw attempts, `p2_*` frames.
  - session3, `engine.session3.log`: replayed commands 0–159 to south shore(776.2,815.0), then tree_southwest contact, open/close strips, stability, cart evidence.
  -436 frames including zoom crops. Commands: `drive_positions.session*.jsonl`, `replay3.jsonl`.
- Environment: host Xvfb `:97`,1920×1080×24, NVIDIA PRIME offload. All three logs record `Godot Engine v4.7.2.stable.official.ed1daf0bf` / `OpenGL API 3.3.0 NVIDIA 595.91.07 - Compatibility - Using Device: NVIDIA - NVIDIA GeForce RTX 4080 SUPER`. Window 1280×720; `MIB_PLAY_SESSION_DIR=build/current/town-cutout-r4d ./scripts/play_session_window.sh --nvidia --display :97`, `tools/play_session.py` protocol.
- Exit: all three `{"quit":true}` normal, runner.exit.json status=0, `pgrep godot` empty.

## Verdict Overview

**Cutout passes.** None of three logs contains SHADER ERROR / Tokenizer / Shader compilation failed, unlike R4C engine.log:13/25. All checked coverage locations (loadout, tree_wood, Board, forge west/chimney, proxy west, tree_east, wood_south pocket, tree_south, tree_southwest, cart) show readable actors through soft elliptical holes while surroundings stay opaque. R4C hair-only hero, boot-only iven, invisible Mira all recover. Centers track torso anchors 22px above feet; soft radius matches design; still frames are pixel-stable without drift/flicker. Shared occluders give hero/residents separate anchor-based holes.

**Collision expansion regression passes.** Lamp/trunk/post contact deviates≤0.25px from r+6.0. Wedge corridor/funnel stop, cliff stop, reef east/north boundaries match R4C, mostly within 0.01px.

**New finding, not this change's regression:** south-shore(790.58,874.11) polygon crevice permits entry but not exit; all 8 one-frame directions rejected after session1 replay. Nearest expanded circle, tree_south_trunk, is 103.6px away. Existing south_forest/003 and shore polygons create terrain risk; owner review recommended, no changes made.

## Verdict Table

| # | Check | Verdict | Key evidence |
| --- | --- | --- | --- |
| 1 | Shader compilation, no error/tokenizer messages | **Pass** | Each engine.session1/2/3.log grep count 0, all contain RTX 4080 SUPER OpenGL 3.3.0. R4C engine.log:13,25 had `SHADER ERROR: Tokenizer: Unknown character #35: '#'` / `ERROR: Shader compilation failed.`; not reproduced |
| 2 | Readable soft holes, opaque surroundings, smooth closure without residue | **Pass** | Source overview calls ten coverage locations; details below. Wedge 084→085 opens on entry,096→102 changes with coverage,104 exits. `p2_43_tree_sw_close_00–07` / `p2_43_tree_sw_open_00–07` show gradual closure/opening without ghosting |
| 3 | Mira/iven/wood pocket/south and southwest trees/cart | **Pass** | Mira `p2_09`/`zoom_p2_09_pair`, independent holes in shared rock. Iven `zoom_p2_04_iven` full body vs R4C zoom_071 boots. Wood `095`/`zoom_phase1_woodpocket_overlay`; south `p2_24`/zoom; southwest `p2_43_tree_sw_pin`; cart `p2_44` |
| 4 | Torso center, upper-body radius, no camera drift/flicker, separate actors | **Pass** | Overlay center feet+(0,-22), r30 design/60 window px, feather±9 matches actual. Wedge 085–088/090–091/094/100–101 head bright-pixel count 298. `p2_43_tree_sw_stability_0–5` max channel delta 0 vs baseline. `p2_09` holes follow respective anchors |
| 5 | Lamp~11.5, tree/post~14.5, wedge traversable, cliff blocked, no new sticking | **Pass, one existing crevice newly found** | Numbers below. Cliff basin slides back to stop under northwest pressure but UP+LEFT escapes twice, as R4C. South crevice separately attributed below |

## Coverage Detail

| Piece | Hero world position | Appearance | Evidence |
| --- | --- | --- | --- |
| loadout east eaves |(529.40,239.16) |Local soft hole, full hero readable; R4C(543.11,239.07) hair-only |`p2_01_loadout_eaves`, `zoom_p2_01_loadout`, compare `town-cutout-r4c/frames/zoom_061_loadout_hero_sliver` |
| tree_wood rock/pine |(521.07,317.18) |Canopy hole reveals upper body |`p2_03_tree_wood_deep`, `zoom_p2_03_tree_wood` |
| Contract noticeboard |(324.59,290.39) |Hero and paper-holding iven(278,300.94) readable; R4C 2–3 boot pixels |`p2_04_contract_board`, `zoom_p2_04_board`, `zoom_p2_04_iven`, compare `zoom_071_contract_hero_iven` |
| forge west, below wheel |(914.76,283.29) |Readable vs R4C thin head gap |`p2_06_forge_west`, `zoom_p2_06_forge` |
| forge chimney approach |(1077.38,332.48) |Readable vs R4C shoulder-only |`p2_07_forge_chimney`, `zoom_p2_07_chimney` |
| proxy west |(1296.40,366.42) |Readable vs R4C 2–3 hand/bow pixels;4.3px east of old point, slightly shallower coverage |`p2_08_proxy_west`, `zoom_p2_08_proxy` |
| tree_east hero/Mira shared rock |(1267.99,442.55), Mira(1260.00,452.81) |Separate centers screen(744,401)/(728,422). Mira more deeply covered but distinguishable through 18% inner retention; previously invisible |`p2_09_tree_east_mira`, `zoom_p2_09_tree_east`, `zoom_p2_09_pair` |
| wood_south pocket/wedge |(564.31,645.60) |Hole reveals hero, matches predicted circle |`095`, `zoom_phase1_woodpocket_overlay`, sequence 084–104 |
| tree_south canopy |(782.70,786.20) |Southwest edge reveals hero/bow vs R4C(819.49,770.94) invisible. Exact north contact not reached, see methods |`p2_24_tree_south_cover`, `zoom_p2_24_tree_south` |
| tree_southwest canopy |(261.78,750.51), trunk distance 14.74 |Upper-body soft hole, rest opaque; previously invisible |`p2_43_tree_sw_pin`, close/open 00–07 strips |
| cart |(422.83,781.01) |Head/torso readable above cart, legs correctly covered by y-sort, no swallowing; same relationship as R4C zoom_140 |`p2_44_cart_y_sort` |

## Timing and Stability

- **Opening:** wedge 082→085, hero(572.9,670.0)→funnel(564.3,645.6); logs open from 085.
- **Tracking:**092–099 positions(566.2,656.5)→(565.1,650.1)→(582.6,657.2)→(582.9,675.4)→(575.9,672.5)→(566.5,658.6); `zoom_s1_096_wedge_track` shows translated hole and opaque rest.
- **Closing:**100–104 southeast departure, `zoom_s1_102_wedge_leave` partially covered/narrowed hole to `zoom_s1_104_wedge_out` fully out/opaque logs, no ghosting.
- **tree_sw strips:** `drive_positions.session9.jsonl`, close 00–07/open 00–07. Eight outward steps trunk distance 27.4→103.0, inward 91.6→14.5. Recorded head bright counts close 12→8→198→564→608→546→410→354; open 556→624→596→546→264→0→0→16, interpreted in the original report as gradual opening/closure with coverage. At contact,18% retention is dark but visually readable despite low threshold count (`p2_43_tree_sw_pin`).
- **Still stability:** nine wedge samples head count 298; `p2_43_tree_sw_stability_0–5`, hero trunk distance 14.54, max channel delta 0, five identical comparisons. Six tree_south-edge frames after p2_40 have identical position.

## Collision Numbers

| Collider | Expected | Observed | Deviation | Verdict |
| --- | --- | --- | --- | --- |
|lamp_10(433,509.0625) r5.5 |11.5 |(440.036,518.159),11.500 |0.000 |Pass |
|lamp_8(1208,742.5) r5.5 |11.5 |(1198.663,735.744),11.525, same R4C(1198.66,735.74) |+0.025 |Pass |
|training_post_4(379,507.1875) r8.5 |14.5 |(393.520,508.059),14.547 east tangent |+0.047 |Pass |
|tree_southwest_trunk(250,759.375) r8.5 |14.5 |(261.783,750.511),14.740 |+0.240 |Pass |
|Wedge funnel |R4C(564.31,645.60) |(564.3087,645.5998) |0.00 |Pass |
|Wedge corridor middle |R4C(657.35,699.79)/(570.92,668.37) |(660.30,700.80)/(572.90,670.00) |≈3.0/2.3 |Pass |
|East cliff |R4C(1419.0,673.52) |(1419.0,673.5201) |0.00 |Pass |
|Reef east |x1516.0, same R4C |1516.0 |0.00 |Pass |
|Reef north, water_north 823.125+6.0 |y829.125 |829.1251 |+0.0001 |Pass |
|Board north |R4C(296.10,294.87) |(298.24,294.53) |d≈2.16, step quantization |Pass |

Wedge(564,664) traverses in one pass, session1 frames 080–090; logs/fence/Board no penetration. Northwest pressure returns east-cliff basin to(1419.0,673.52), but UP+LEFT escapes twice to(1306.6,498.0)/(1329.2,520.6), as R4C, not new sticking.

## New Finding: Existing South-Shore Crevice Soft Lock

- Position(790.5753,874.1072), central south-shore rock platform under cliff, session1 frames 163/170.
- Replay enters from(907.8,766.5) via(796.1,829.0). All8 one-frame directions, including diagonals, BLOCKED; about 100 subsequent directional commands move no pixel.
- Nearest static geometry: south_forest/003 polygon, vertex distance 18.8px. Nearest expanded circle tree_south_trunk center 103.6px away, expansion 2.875px, influence≤14.5+2.875px, unrelated. Entry route stays≥45.8px from trunk. Existing south_forest/* and shore polygons form crevice; whole-frame movement rejection without axis sliding traps it. Owner should review entrance; no data changed.

## Method Caveats

- **Cross-session nondeterminism:** movement integrated by render frames; same command 100 replay lands(564.31,645.60) in session1 but(111.35,433.01) in session3. R4C frame numbers cannot align directly with current command numbers. Cross-session claims use geometry-forced wedge/cliff/reef stops, exactly reproduced, and current measurements only.
- **tree_south north contact not reached:** LEFT from east y≈771 slides around trunk to southwest canopy edge(782.7,786.2)/(737.6,786.2) in two sessions. Canopy-edge frames plus southwest trunk distance 14.74 establish trunk collision/canopy reveal, not exact old north point.
- **Invalid phase2 loadout stability set:** p2_02_loadout_stability_* moved without input(529.40,239.16)→(574.20,239.16), suspected external-driver lost release. Excluded; stability relies on wedge and p2_43_tree_sw_stability_*.
- **Cart posture differs:** current(422.83,781.01) about 13px north of R4C(427.53,793.96), so old deep coverage not reproduced. Verdict limited to readable hero, correct y-sort, no swallowing.

## Summary

After `## → //`, every checked coverage location has torso-centered soft holes, opaque surroundings, anchor tracking, gradual exit closure, and zero still drift. R4C hidden hero/Mira/iven locations are readable, with separate holes per actor sharing a piece. Collision regression retained: contact≤0.25px, boundary stops exact, wedge traversable, cliff blocked. New existing south-shore soft lock(790.58,874.11) recorded for owner, judged unrelated to current changes. Sessions exited normally. No code/assets changed; git status matched takeover except this report and evidence directory.

## Notes

- 436 ignored frames: `build/current/town-cutout-r4d/frames/`; zooms 2× nearest-neighbor; `zoom_phase1_woodpocket_overlay` adds predicted circles, red=r, orange=r+feather.
- Logs: engine.session1.log replay/trap investigation, engine.session2.log targeted inspection, engine.session3.log truncated replay/wrapup; all shader-error-free with NVIDIA line.
- Commands/coordinates: `drive_positions.session1..9.jsonl`, `replay3.jsonl`, `phase*_results.json`.
- Xvfb `:97` retained afterward; display services host-managed.
