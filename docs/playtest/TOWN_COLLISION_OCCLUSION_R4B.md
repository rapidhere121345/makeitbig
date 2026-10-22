# Hearthside Collision and Occlusion Fix Recheck - R4B

- Date: 2026-10-20
- Operator: Paseo opencode (GLM) hardware-vision acceptance inspector, one-off delegation, no further agents created.
- Purpose: recheck R4 findings (`TOWN_COLLISION_OCCLUSION_SURVEY.md`) and newly prioritize fully covered/no-reveal remnants. Scope: **collision and occlusion only**, not UI/color/layout.
- Session: `build/current/town-collision-r4b/`, 77 evidence images in `frames/`; reused R4 base save with tutorial complete, entering Hearthside directly.
- Environment: host Xvfb `:97`, 1920×1080×24, `xdpyinfo` confirmed, NVIDIA PRIME offload. Entry: `MIB_PLAY_SESSION_DIR=build/current/town-collision-r4b ./scripts/play_session_window.sh --nvidia --display :97`. First engine.log lines: `Godot Engine v4.7.2.stable.official.ed1daf0bf` / `OpenGL API 3.3.0 NVIDIA 595.91.07 - Compatibility - Using Device: NVIDIA - NVIDIA GeForce RTX 4080 SUPER`. Window 1280×720; `tools/play_session.py` command.json directional input and per-frame snapshots.
- Exit: `{"quit":true}` normal, `runner.exit.json` status=0, no remaining Godot process.
- Method: hero world coordinates from `state.json` (`town.hero_world_position()`). Collision numerically cross-checked with static polygons/circles in `content/rooms/town/hearthside.spatial.json`, hero radius 6.0. Reveal judged by enlarged pixels and precise covered/away world-coordinate mapping: camera follows hero, `screen=(world−hero)*2+(639,443)`, clamped at bounds. Opaque asset edges checked in `content/rooms/town/layers/*.png`.

## Item Verdicts

| # | Recheck | Verdict | Key coordinates (world pixels) | Evidence frames |
| --- | --- | --- | --- | --- |
| 1 | arrival northwest fence × wood_south wedge (564,664): holding LEFT no longer sticks | **Pass** | Start (755.2,697.7), about previous (750,696); slides past old stuck point (567.1,661.9) without pause; settles (564.31,645.60), 6.0 from west fence face and 17.1 from wood_south collision: single-face contact, no wedge. DOWN/RIGHT/UP immediately exit | `101_wedge_start_750_696` `102_wedge_slide_pin_564_645` `zoom_102_wedge_pin` `103_wedge_exit_downleft` `zoom_103_wedge_exit` |
| 2 | East bridge cliff: eastward at y≈678 no longer reaches slope (1516,679) | **Pass** | Diagonal bridge center passes (1162.5,683.9), slope ≈0.56; y≈678 is outside walkable surface east of x≈1250. Southeast landing (1442.9,829.5) to reef stops (1505.95,829.13), hard east boundary. UP and UP+RIGHT from landing/reef all blocked; (1516,679) lies inside cliff collision and is unreachable | `701_bridge_east_push` `702_bridge_se_row` `zoom_702_se_row` `703_bridge_row678_east` `704_bridge_east_block` `705_bridge_se_end` |
| 3 | wood_south: northern approach stops outside visual upper edge (y<630), no hero painted on logs | **Pass** | Stops (560.77,624.82), <630 versus previous 641.72. Sprite bottom 628.82 intersects opaque logs only in 3-4 world columns x[581,585], ≤7px versus previous depth 22.7px. Correct y-sort places logs in front where appropriate, without overpainting. Actual coverage in fence pocket (568,666) correctly detects cover and reveals logs | `301_woodsouth_N_press` `302_woodsouth_N_settled` `303_woodsouth_N_more` `304_woodsouth_N_rest` `zoom_304_center` `zoom_304_contact` `zoom_103_pile_window` |
| 4 | Contract roof slit: base collision blocks access to roof coverage | **Pass** | contract_base top moved 234.4→223, joined to contract_roof x[100,418] y[122,223], closing gap. North push stops at base south face (296.20,294.85), distance 6.0. Old slit (289.7,229.1) inaccessible from south (limit ≈y295); forest edge/base west close west gap to ≤0.5px at y≈235, impassable in test; roof/forest block north | `403_contract_north_push` `405_contract_strip_north` `406_contract_strip_rest` `zoom_406_contract_face` |
| 5 | Reveal regression: loadout/forge/proxy tall parts fade by tier; hero readable, noticeboard NPC visible | **Pass** | loadout (544.5,228.4): left building translucent, hero fully readable. forge (925.3,272.9)/(1182.8,350.0): shed/chimney pieces fade. proxy (1298.1,405.4): local tower reveal, rest solid. Board (317.4,291.5): iven (278,300.9) visible in front, head/robe/boots complete | `501_loadout_under_eaves` `zoom_501_loadout_fade` `502_forge_west_under` `zoom_502_forge_west` `504_forge_chimney_stand` `zoom_504_chimney` `508_proxy_r4point` `zoom_508_proxy_r4point` `510_board_npc` `zoom_510_board_npc` |
| 6 | New sweep: accessible building/canopy art boxes reveal; fully covered/no-reveal remnants? | **Pass, none found** | All eight coverage positions reveal/fade by tier; below | Below |

### Item 6 Coverage Detail

| Piece | Hero position | Presentation | Quantification / evidence |
| --- | --- | --- | --- |
| tree_wood (rock + pine) | (526.94,315.75) | Rock reveals locally; outside-window pixels unchanged between frames, histogram 2033/2317 px Δ≈0, changed region matches window | `603_tree_wood_canopy` `zoom_603_tree_wood` `604_tree_wood_clear` |
| tree_east (boulder, feet (1241,458.4)) | (1255.76,439.54) | Covered rock brightness +12.1 vs away control +2.4; Mira in same rock also correctly revealed | `608_tree_east_cover` `zoom_608_tree_east_cover` `609_tree_east_clear` |
| commons_fire (feet (790,501.6)) | (804.56,429.94) | Brazier/logs/smoke reveal together; readable hero | `606_commons_fire_north` `zoom_606_fire` |
| tree_south (feet (805,771.6)) | (820.79,768.91) | Subject dims by tier, readable silhouette; canopy +5.6 brightness within footprint window, outside −3/−5 noise | `612_tree_south_covered` `zoom_612_tree_south` `611_tree_south_cover` `613_tree_south_away` |
| tree_southwest (feet (250,759.4)) | (261.64,697.82) | Canopy correctly in front; window edge +22.1 brightness, hero readable | `617_tree_sw_covered` `zoom_617_tree_sw` `618_tree_sw_clear` |
| cart (feet (401,810.9)) | (414.05,790.93) | Cart correctly covers calves, y-sort correct; low graze/partial coverage without readability issue | `615_cart_covered` `zoom_615_cart` `616_cart_settled` `zoom_616_cart` |
| wood_south control (feet (614,675)) | (560.77,624.82) | Coverage below graze threshold 0.15: no reveal/dimming, as contracted | `304_woodsouth_N_rest` |
| lamp_7 thin-pole control (feet (902,780)) | (897.59,762.51) | Pole correctly in front; no anomaly | `610_tree_south_canopy` `zoom_610_tree_south` |

Mechanism: local window in the covering piece plus tiered subject dimming (0.15/0.45 thresholds, alpha 1.0→0.4), matching `src/presentation/occlusion/occlusion_controller.gd`. No fading below graze is contracted. Buildings, canopies, brazier, and Mira validated the chain.

## Summary

All four R4 issues (wedge blockage, east cliff overrun, wood_south collision/occlusion, Contract roof slit) rechecked **fixed**. Positive reveal regressions for loadout/forge/proxy/noticeboard NPC pass. Eight new fully-covered/no-reveal checks found **no remnants**. No code or assets changed; only this report was added in that round.

## Notes

- Item 1: LEFT's natural stop (564.31,645.60) is normal west-fence-face contact, not a soft lock; log-collision clearance 17.1px, all four directions escape. Westward routing goes north/south of logs; fence/log gap intentionally closed.
- Item 2: bridge is one diagonal corridor plus southeast landing/reef with stone bases and guardposts, designed terrain. Reef east boundary ≈1506-1513 at y829 blocks; all UP attempts blocked; R4 point (1516,679) unreachable.
- Item 3: stop is inside visual AABB (top 615), but opaque logs rise northeast from (554,632). Hero bottom 628.82 meets only 3-4 local columns by ≤7px, no readability issue. Tighten footprint further only if requiring the whole row outside the box; current y<630/no-overpainting criterion passes.
- No silent Godot exit during ~180 commands; R4 long-session stability issue not reproduced.
- All 77 frames: `build/current/town-collision-r4b/frames/`, ignored. Coordinates are world design pixels; `zoom_*` are enlarged crops of corresponding frames.
