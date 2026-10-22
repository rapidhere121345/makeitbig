# Hearthside Placed-Object Collision and Occlusion Survey - R4

- Date: 2026-10-20
- Operator: Paseo opencode (GLM) hardware-vision inspector.
- Environment: host Xvfb `:97` (1920x1080), NVIDIA PRIME offload; Godot 4.7.2; `OpenGL 3.3.0 NVIDIA 595.91.07 - Compatibility - Using Device: NVIDIA - NVIDIA GeForce RTX 4080 SUPER`, recorded atop `build/current/town-collision-r4/engine.log`.
- Session: `build/current/town-collision-r4/`, `tools/play_session.py` command protocol, `frames/` evidence.
- Scope: **collision** (penetration, invisible walls, edge consistency) and **occlusion** (missing/false reveal, y-sort) only; no appearance/UI review.
- Method: command.json directional input and per-frame snapshots; hero world coordinates from state.json `town.hero_world_position()`. Enlarged pixels cross-checked against sprite feet/y-sort anchors in `content/rooms/town/layers/manifest.json` and static polygons in `hearthside.spatial.json`.

## Per-Object Results

### 1. wood_south Logs

Large pile by arrival fence; feet `(614,675)`, visual x[553,662] y[615,679].

- Collision: **footprint too loose above, tight below**. Northern approach stops `(582.55,641.72)`, exactly 6.0 from `wood_south_base/000` (hero radius, polygon works), but **18.7px into the visual**. Feet correspond to local(29,27), opaque wood `(70,47,34,255)`; that column starts world y623. Southern approach stops near visual bottom (bbox 684.4→feet≈678). North/south contact differs by about 36 world pixels.
- Occlusion: **render/reveal coupling abnormal**. Hero feet 641.7 < log feet 675, so pure-y SortRoot `world_presenter._sort_child_precedes` should draw logs later over hero. Actual frame shows hero and orange outline above opaque wood:52 orange pixels in world strip y623–641.7. `stable_bindings` registers `town/native/wood_south` for occlusion (all 35 native pieces registered), but detects no cover/reveal. This agrees with rendering yet looks like standing on logs, violating expected behind-object coverage/reveal.
- Severity: **Medium**.
- Evidence: `frames/001_fence_N_approach.png`, `frames/zoom_001_pile.png`.

### 2. arrival_storage_fence Northwest × wood_south Converging Wedge

- Collision: **blocking stuck state**. Hold LEFT from `(750,696)`; slide along fence into narrowing wedge between NW fence and log southwest edge, stop `(564.36,663.70)`. Distance to `arrival_storage_fence_base/002` is 5.39 (hero circle overlaps polygon 0.6), to `wood_south_base/001`6.00. All four directions and Shift/Ctrl dodge fail; only scene restart escapes.
- Occlusion: not applicable.
- Severity: **Blocking**, reproducible by westward travel along fence north side.
- Evidence: `frames/002_fence_E_approach.png`.

### 3. contract Board and Roof

Board feet `(285,300.9)`, roof visual y[122,223].

- Collision: contract_base blocks normally; east contact `(280.4,338.6)`, north top contact `(289.7,229.1)`; no penetration/invisible wall.
- Occlusion: **accessible under-roof slit without reveal** between base top y234.4 and roof collision. At `(289.7,229.1)`, opaque tiles hide upper body in roof/board-wall visual area without fade, unlike item 4.
- Noticeboard NPC recheck **passed**: iven `(278,300.9)`, almost same y as board feet, clearly visible (`frames/001_contract_board_E_approach.png`); historical bubble-only hiding not reproduced.
- tree_board trunk `(144,224.1)`, r5.625: Board base, NW forest, and wall block direct trunk contact. Hero stops `(173.2,229.1)` / `(401.3,229.1)` on base north edge. Canopy included here: at first point, board/eaves hide nearly all but hat tip without reveal. Circle fit extrapolated from post_4 with same r5.625.
- Severity: medium-low; remote but freely reachable. Worst coverage: `frames/004_tree_board_S.png`.
- Evidence: `frames/001_contract_roof_behind.png`, `frames/zoom_contract_roof_behind.png`, `frames/zoom_contract_board_E.png`, `frames/004_tree_board_S.png`.

### 4. loadout House

Feet `(671,262.5)`, visual x[490,793] y[30,259].

- Collision: west wall blocks normally; narrowed bottom footprint allows standing in residual wall-base art `(589.0,243.2)` without hard penetration.
- Occlusion: **positive**. Whole building fades at wall-base/barrel/crate visuals; boxes/shield region clearly translucent, hero readable.
- Severity: no issue.
- Evidence: `frames/001_loadout_under_eaves.png`, `frames/zoom_loadout_eaves.png`.

### 5. training_post_4

Position `(379,507.2)`, r5.625.

- Collision: **circle matches art**. Pulsed south approach yields center distance 12.0, expected 6+5.625=11.625 within tolerance. Diagonal approach slides smoothly with no penetration/invisible wall. Small circle and sliding require pulsing to stop directly, a behavior not defect.
- Occlusion: post correctly covers lower hero standing north/behind it.
- Severity: no issue.
- Evidence: `frames/001_post4_S_press.png`, `frames/zoom_post4_press.png`.

### 6. forge Buildings

Base bottom≈347, sprite feet `(1068,320.6)`, chimney feet `(1205,358.1)`.

- Collision: southern forge_base contact `(1091.6,356.9)` agrees with polygon distance, no penetration/invisible wall.
- Occlusion: **positive**. At `(1239.2,330.3)` inside shed/chimney art, components fade and hero fully readable. Hero feet 356.9 > forge feet 320.6 correctly places building behind.
- Severity: no issue.
- Evidence: `frames/001_forge_S_press.png`, `frames/002_forge_chimney_occlusion.png`, `frames/zoom_chimney.png`.

### 7. proxy Tower

Body collision x[1312,1508] y[103,410.6], feet `(1400,494.1)`.

- Collision: solid upper/middle tower blocks entry; west contact `(1306.0,372.3)` exactly 6.0 from body polygon. proxy_base y[420.9,497.8] blocks southwest approach `(1299.6,440.2)`. No penetration/invisible wall. **No passage beneath tower/tall pieces is intentional collision design**, normal.
- Occlusion: **positive**. At west visual edge tower fades; hero and Proxy Bay / opens after first Colossus kill label readable.
- Severity: no issue.
- Evidence: `frames/003_proxy_tower_S.png`, `frames/004_proxy_tower_occlusion.png`, `frames/zoom_tower_occ.png`.

### 8. East Bridge Cliff/Waterfall

water_north_bridge east section, east of route endpoint `(1430,852)`. (The source report's bridge paragraphs are grouped under their numbered heading here.)

- Collision: **missing boundary blocker**. At y≈678, eastward movement from `(1431.9,678.7)` continues 84px to `(1516.0,678.7)` near world east edge, inside water_north_bridge bbox x[1150,1536] y[524.1,823.1] and cliff art. Hero stands on steep cliff pixels by waterfall. Bridge south edge itself blocks normally from `(1427.9,678.6)`.
- Occlusion: not applicable.
- Severity: **medium-high**, conspicuous cliff/waterfall entry; add cliff blockers or tighten bridge east end.
- Evidence: `frames/003_bridge_E_water_edge.png`, `frames/zoom_bridge_E.png`.

### 9. lamp_0

Position `(410,265.3)`, r2.5, sample for all 11 lamps. Source lamp paragraphs are grouped here.

- Collision: usable circle. Northward path offset8.7px passes beside pole, center distance 8.7 vs required 8.5, margin 0.2, no clipping. Required 8.5 vs half-width≈5 is normally tight, not undersized penetration.
- Occlusion: **positive**. Pole and arm correctly render in front of hero feet 229.1 in visual region.
- Severity: no issue.
- Evidence: `frames/006_lamp0_S.png`, `frames/zoom_lamp0.png`.

## Summary

| # | Object | Collision | Occlusion | Severity |
| --- | --- | --- | --- | --- |
| 1 | wood_south | Loose top/tight bottom;18.7px into visual | Inverted rendering and no cover/reveal | Medium |
| 2 | NW fence/log wedge | Fully stuck, including dodge | — | Blocking |
| 3 | Contract roof/tree canopy | Normal | Accessible opaque slit, worst only hat tip | Medium-low |
| 4 | loadout | Normal | Reveal normal | None |
| 5 | training_post_4 | Matching circle | Correct | None |
| 6 | forge/chimney | Normal | Reveal normal | None |
| 7 | proxy | Tower blocked by design | Reveal normal | None |
| 8 | East bridge cliff/waterfall | Missing cliff block, slope accessible | — | Medium-high |
| 9 | lamp_0, sample of 11 | Usable, no clipping | Correctly in front | None |

Frequency as reported:1 blocking wedge,1 medium-high bridge boundary,1 medium log collision+occlusion,1 medium-low roof/canopy slit,4 positive categories. Main clusters: **arrival fence/log corner**, where wood_south footprint is too small and render/reveal do not follow y-sort together (#1/#2), and **east cliff**, missing static water/cliff boundary (#8). Tall-piece reveal (loadout/forge/proxy) and small-object coverage (post/lamps) generally work.

## Notes

- One silent Godot exit mid-survey, no engine.log error/stack. Restarted and continued; evidence remains valid, but monitor long-session stability.
- Direct trunk contacts unavailable for tree_east/lamp_9/tree_board due to water/Board/forest route deflection. Circle conclusions extrapolate same-parameter post_4 r5.625 and lamp_0 r2.5; sampled conclusions only.
- 45 evidence frames in ignored `build/current/town-collision-r4/frames/`. World design pixels; `screen = (world - camera) × 2`.
- Normal `{"quit": true}` exit, runner.exit.json status=0.
