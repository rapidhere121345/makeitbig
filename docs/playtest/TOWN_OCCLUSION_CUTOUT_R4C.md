# Hearthside Occlusion Cutout and Collision Expansion Acceptance - R4C

- Date: 2026-10-21
- Operator: Paseo opencode (GLM) hardware-vision inspector, one-off delegation, no other agents created.
- Purpose: A, replace whole-piece tiered fading with a soft elliptical hole around a covered character, keeping the rest opaque; B, expand collision (lamps 2.5→5.5, trunks/posts 5.625→8.5; R4B logs/Board fixes retained). Scope: cutouts and collision only.
- Session: `build/current/town-cutout-r4c/`;84 captured frames +13 `zoom_*` crops. Reused tutorial-complete base save. `aborted-0029/` holds an interrupted 00:29 attempt, an earlier reproduction of the same shader error; later evidence is authoritative here.
- Environment: host Xvfb `:97`,1920×1080×24, xdpyinfo confirmed and started this round; NVIDIA PRIME offload. Entry: `MIB_PLAY_SESSION_DIR=build/current/town-cutout-r4c ./scripts/play_session_window.sh --nvidia --display :97`. Engine: `Godot Engine v4.7.2.stable.official.ed1daf0bf` / `OpenGL API 3.3.0 NVIDIA 595.91.07 - Compatibility - Using Device: NVIDIA - NVIDIA GeForce RTX 4080 SUPER`. Window 1280×720, `tools/play_session.py` command.json input/frame snapshots,258 movement/observation commands.
- Exit: `{"quit":true}`, runner.exit.json status=0, no Godot process left.
- Method: hero coordinates from state.json `town.hero_world_position()`; static polygons/circles in `content/rooms/town/hearthside.spatial.json`, hero radius 6.0, expected circle contact radius+6.0. `screen=(world−camera_off)*2`, `camera_off=clamp(floor(hero)−(320,222),0,world−(640,360))`. Cutouts judged visually and in enlarged crops.

## Verdict Overview

**A (cutouts): fail, never active.** `occluder_cutout.gdshader` uses `##` comments, while Godot 4.7.2 shaders accept only `//` or `/* */`. First occlusion sync fails compilation (engine.log:13/25, backtrace `town_presenter.gd:342 _apply_occluder_cutout`). Material silently falls back to opaque drawing; presenter forces `piece.modulate.a = 1.0` after removing whole-piece fade. **Covered heroes/residents vanish completely without cutout, fading, or readability**, a clear regression from R4B. B collision expansion matches numeric expectations and passes.

## Item Verdicts

| # | Check | Verdict | Key coordinates / evidence |
| --- | --- | --- | --- |
| 1 | Soft character-local holes, opaque surroundings, smooth closure, separate actor holes | **Fail** | No hole at any checked location; covered hero/residents unreadable. `061` `063` `071` `080` `085` `091` `135` `151`, corresponding zooms; source overview calls these eight coverage positions |
| 2 | Torso-centered hole, upper-body radius, no drift/flicker | **Fail, unassessable: no hole** | Shader uncompiled, holes/hole_count ineffective. No hole or flicker across 258 observed frames; engine.log:13,25 and same frames |
| 3 | Expanded contact clearances, no penetration/sticking; wedge(564,664) traversable | **Pass, numeric exactness; upper pole/sprite overlap is existing style, reduced** | Lamp 11.5: lamp_10(444.17,511.78), lamp_8 deck(1198.66,735.74), lamp_7(894.55,771.01). Post 14.76→east tangent, post_4 north(384.82,492.53). South trunk 14.5 at(819.49,770.94); southwest 14.5 at(249.03,744.89). Wedge slides without pause, stops(565.74,653.94)/(564.31,645.60), same R4B. Frames `013`/zoom, `016`/zoom, `134`/zoom, `135`, `151`, `041`–`044`/zoom, `045` |
| 4 | East cliff block, inaccessible slit, visible Board NPC, correct y-sort, opaque uncovered art | **Partial: A breaks Board NPC** | East shore(1419.0,673.52); reef east(1516.0,859.67)→(1516.0,829.13), north blocked(1442.40,829.13); north boundary 823.125+6.0 exact. Board north(296.10,294.87), R4B(296.20,294.85). Hero(322.11,290.78) and iven(278,300.9) swallowed, only 2–3 boot pixels. Cart y-sort correct(427.53,793.96); uncovered art opaque through fallback, not feature. `101` `103` `114`–`121` `072`–`074` `071`/zoom_071 `140`/zoom `142` `000` `060` |

### Coverage Detail (All Without Holes)

| Piece | Hero world position | Appearance | Evidence |
| --- | --- | --- | --- |
| loadout east | (543.11,239.07) | Only 1–2px hair below barrels; body gone | `061` `zoom_061_loadout_hero_sliver` |
| tree_wood rock/pine | (525.85,316.02) | Completely invisible; R4B same area readable | `062` `063` `zoom_063_tree_wood_hidden` |
| Contract noticeboard | (322.11,290.78) | Hero invisible, only iven boots remain | `071` `zoom_071_contract_hero_iven` |
| forge west | (913.70,285.51) | Thin head strip through waterwheel gap, no hole | `080` `zoom_080_forge_hero_fragment` |
| forge chimney approach | (1077.94,335.87) | Mostly gone, shoulder through natural gap | `081` `082` |
| proxy west | (1292.08,365.28) |2–3px hand/bow tip at pine edge | `084` `085` `zoom_085_proxy_hero_sliver` |
| tree_east rock, multiple actors | (1267.19,438.17), mira(1260,452.8) | Hero bow-hand pixels only; Mira gone; neither has individual hole, unlike readable R4B pair | `090` `091` `zoom_091_tree_east_two_actors` |
| tree_south canopy | (819.49,770.94) | Invisible; exact trunk contact 14.5 | `135` `zoom_135_tree_south_hidden` |
| tree_southwest canopy | (249.03,744.89) | Invisible; no discernible closure after 4/30 frames because mechanism absent | `151` `152` `153` `zoom_151_tree_sw_hidden` |
| wood_south fence pocket | (565.74,653.94)/(567.61,664.86)/(566.18,656.53) | Swallowed by logs, unlike R4B reveal | `044` `045` `049` `050` |

### Collision Numbers (B)

| Collider | Expected r+6.0 | Observed | Deviation | Verdict |
| --- | --- | --- | --- | --- |
| lamp_10(433,509.06) r5.5 |11.5 |(444.17,511.78), distance 11.500 |0.00 |Pass |
| lamp_8(1208,742.5) r5.5 |11.5 |(1198.66,735.74),11.500 |0.00 |Pass, incidental deck-middle recheck |
| lamp_7(902,780) r5.5 |11.5 |(894.55,771.01),11.675 |≤0.2 step quantization |Pass |
| training_post_4(379,507.19) r8.5 |14.5 |North(384.82,492.53),15.77; tangent top y492.53≈507.19−14.5 |≤1.3 quantization |Pass |
| tree_south_trunk(805,771.56) r8.5 |14.5 |(819.49,770.94),14.500 |0.00 |Pass |
| tree_southwest_trunk(250,759.38) r8.5 |14.5 |(249.03,744.89),14.486 |0.01 |Pass |
| wood_south triangle(554,632)(640,618)(661,660) |Edge 6.0 |All approaches≥6.0, no penetration; pocket funnels to same stop |— |Pass |
| Wedge(564,664) |— |LEFT from(754.83,705.02) passes old stuck area via(657.35,699.79)/(570.92,668.37), stops(565.74,653.94); DOWN+LEFT exits immediately |— |Pass |

Feel: no ground-contact clipping after expansion; lamp_10 foot/base gap≥5px. The 24px-wide torso still overlaps upper thin-pole/trunk sprites by single-digit pixels, same style but reduced from old radius. Zero torso overlap would require larger radii or accepting the style, outside this round.

### Regression Detail (4)

- East cliff **pass**: northeast shore east/south stops(1419.0,673.52), old R4(1516,679) direction inaccessible. Reef east stops(1516.0,859.67). Northern stop(1516.0,829.13) is 10.05px east of R4B(1505.95,829.13), from different approach: east along southern y≈860 then north, versus direct east. North boundary 829.125=823.125+6.0 and hard-block behavior agree; collision data unchanged since R4B. Owner may inspect guardpost/reef surfaces; not an overrun.
- Slit **pass**: Board north(296.10,294.87) vs R4B(296.20,294.85); old(289.7,229.1) inaccessible.
- Board NPC **fail**: A hides iven; passed R4B, should return with cutout fix because actor inside Board art box needs its own hole.
- y-sort **pass**: cart(427.53,793.96)/(415.35,791.22) front/back correct; open-ground oren/taren normal.
- No empty-ground false holes **qualified pass**: all frames opaque, but through shader fallback rather than feature behavior; must recheck after fix.

## Root Cause and Suggested Fix (No Code/Asset Changes)

`src/presentation/occlusion/occluder_cutout.gdshader:3-6` uses `##`. Shader language has no # comments:

```text
SHADER ERROR: Tokenizer: Unknown character #35: '#'   (occluder_cutout.gdshader:3)
ERROR: Shader compilation failed.
```

Compilation failure occurs through `_apply_occluder_cutout → set_code`. Reproduced in 00:29 interrupted attempt and current session, same file mtime 00:22 unchanged. GLES3 Compatibility silently falls back to ordinary drawing; `town_presenter.gd` alpha 1.0 and removal of whole-piece fade make covered characters unreadable. Change four `##` lines to `//` (or remove). Recheck all coverage locations, open/close timing (`inner_alpha = lerp(1, 0.18, 1−eased)` easing already present), and multiple actor holes (`occluder_holes` aggregation already present) on the same route.

## Summary

B collision expansion (lamps 5.5, trunks/posts 8.5) **passes numbers and feel**: deviations≤1.3px, mostly 0; wedge slides, logs/fence/Board no penetration or new sticking, R4B stops reproduced. A **fails** due to comment-triggered shader compilation failure: all covered actors, including Board iven and tree_east Mira, unreadable, regressing R4B fade. Other regressions pass. No code/assets changed; only report and session evidence added.

## Notes

- 97 frames in ignored `build/current/town-cutout-r4c/frames/`; world design pixels; zooms are2× nearest-neighbor crops.
- Interrupted 00:29 attempt in `aborted-0029/`, including engine.log/state.json and same shader error. Current logs/state are independent clean restart records.
- Contact quantization≤2.5px comes from full 2.43px per-frame steps with whole blocked-frame rejection: deterministic integration, not collision error.
- 258 commands without silent engine exit. Xvfb `:97` created for acceptance remained afterward; host display services are host-managed.
