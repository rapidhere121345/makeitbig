# Hearthside Modular Foundation and GPU Greybox Acceptance

Date: 2026-10-22. Scope: sample validation of the new authoring contract, reveal states, and actual runtime chain.
**Status: technical foundation implemented; production town art reconstruction and finished-visual acceptance incomplete.**

## Implementation Checklist

- [x] Fixed old cutout shader's repeated texture multiplication, proven by GPU pixel regression.
- [x] Added `EnvironmentObjectDefinition` / `Placement` / `Baker`: multiple instances per resource, deterministic expansion, one translation, atomic rejection of conflicts.
- [x] Complete-ground validation, shared full/revealed/mask canvas checks, presentation content fingerprints.
- [x] Unified actor/native sort rank and stable ID; frame and plan use one comparator.
- [x] Authored reveal controller: immutable full mask, precise head/chest checks, maximum demand across subjects, entry/exit thresholds,150ms transition; no reuse of old alpha tiers.
- [x] Common structure drawn once; full/revealed composited once with premultiplied interpolation.
- [x] New flow protects only player and current conversation resident; legacy cutouts retain compatibility path.
- [x] GPU shader comparisons and three mounted greybox walks, fixes, and rechecks.
- [ ] Production independent ground, buildings, trees, and facilities.
- [ ] Whole-town layout/art migration and finished first-chapter visual acceptance.

Two Paseo subagents used `devin/gpt-6-1-sol-medium` / `medium`, `bypass`, without further delegation: shader/GPU validation and object-authoring components respectively. Parent integrated, reviewed code/images, and owned final gates.

## Runtime Chain

`tools/modular_town_preview.gd` generates clearly labeled GREYBOX test images from scratch, assembles a 960×640 native scene and spatial manifest, and runs through existing `TownController → SceneRuntime → MovementResolver / projector → TownPresenter`.
Real Ranger assets,640×360 logical viewport,1280×720 integer 2x display. Legal `place_hero` sets starting points; authoritative ticks handle walking/edge contact. No separate movement model; no old-town image crops passed off as new art.

`TownController.mount` accepts optional scene/manifest paths; default game entry unchanged. `TownSceneRoot.modular_environment_objects` defaults false; sample explicitly enables it, old town still loads.

## GPU Evidence and Repeated Visual Review

All environments: Godot 4.7.2, X11, Compatibility/OpenGL 3.3, NVIDIA 595.91.07/RTX 4080 SUPER, Dummy audio. Displays exclusively created/cleaned by operator; successful sessions below exited 0.

| Session | Actual checks | Conclusion and limits |
| --- | --- | --- |
| Shader before/after, `:111` | Colored translucent texture, modulate/self_modulate, inside/outside pixels | Original RGBA error 0.145098, exit 1; fixed error 0, exit 0 |
| authored R1, `:111` | Composite references, two occluders, empty mask areas, multi-subject grazing, three-second hold | Normal/intermediate/revealed errors all 0; shader check, not scene acceptance |
| mounted R2, `:111` |60 checks/14 frames; actual mount/character, building block, front/back trees, translated instance, camera, doorway return | Technical checks pass; floating roof strips/canopy fragments fail revealed-form review |
| mounted R3, `:113` | Connected beams/posts and complete trunk, same route,60 checks/14 frames | Technical pass; parent inspection found beam crossing head/chest, still unreadable |
| mounted R4, `:113` | Low post sections, no high beam; same 60 checks/14 frames | Greybox visual pass: readable head/chest, wall bases/trunk retained, no floating fragments, gray holes, or missing ground; not production-art quality acceptance |

Parent actually opened R2/R3/R4 normal/revealed, tree front/back, wall-contact, and doorway screenshots. R4 `03_open.png` has no beam crossing the actor. `09_second_tree_camera_pan.png` retains complete trunk and independent second-instance reveal. Doorway/reverse frames show no new sticking. Two similar amber doorway arrows remain existing guidance UI, recorded but unchanged.

30/120Hz **input frame deltas** each take 60 simulation ticks for doorway return to `[600,440]`. This compares authoritative trajectories, not a claim of measured 120 GPU FPS. Idle animation may change still-character frame hashes; reveal weight stays 1 for three seconds.

Evidence:

- `build/current/cutout_gpu_before_111.log`, `cutout_gpu_after_111.log`
- `build/current/authored-reveal-r1/`: four pixel-comparison sets, logs, REPORT
- `build/current/modular-town-preview-r2/REPORT.json`, `VISUAL_REPORT.txt`; successful scene/14 frames in `mounted/`, initial missing-author-setting failure retained
- `build/current/modular-town-preview-r3/`; `build/current/modular-town-r3-engine.log` and `.exit`
- `build/current/modular-town-preview-r4/`; `build/current/modular-town-r4-engine.log` and `.exit`

R2 initially rejected for missing `SortRoot.y_sort_enabled`; corrected sample author settings passed without bypassing production validation. Explicit headless GPU requests return `GPU SKIP` / exit 2 and cannot count as visual passes.

## Code Validation

Passed: project `check.sh`, object-authoring tests,212 legacy-town contract negatives, town geometry/runtime, world asset digest, targeted world occlusion. New object tests included in `scripts/test.sh` and `scripts/test.ps1`.

Review added rejection of negative rank, horizontal/vertical flips, and author z-index/tint/hidden overrides absent from fingerprints. Unsupported transforms fail rather than being guessed/repaired at runtime. Pure-ground art enters presentation digest without claiming an occlusion channel.

First `container_build.sh` won all 600 matrix rooms but parent edited `town_scene_root.gd` during execution, triggering `frozen runtime/content changed during run`. This parallel-execution mistake is not a build pass or story-test flake. Final frozen-source gate follows.

Final addendum: independent GPT 6.1 Sol subagent ran as ordinary uid=1000 in a separate process group; completed 2026-10-22 10:09:50 -07:00, exit **0**. `modular-container-build-verified.log` and matching `.exit` record:

- `PASS test_environment_object.gd`
- `STORY_READING_FLOW PASS`
- `PASS test_repeatable_encounter_matrix.gd rooms=600 seeds=0..99 outcomes={"victory":600} ticks=33894`
- `test gate passed: exit 0, no GDScript runtime errors`
- Windows/Linux exports completed, `SCENE_SMOKE_PASS ... route=title`
- `host build flow passed`

Another earlier main-session run stopped at 510 rooms after tool-wait interruption, with no exit file; not counted as passing. Final independent evidence: `build/current/modular-container-build-verified.{log,exit,pid,pgid}`. Some existing tests still emit ObjectDB/resource cleanup warnings at exit; no zero-warning claim.

## Production Blockers and Boundaries

Neither main session nor either subagent had `image_gen`/image-generation tools; discovered MCP/plugins exposed none. No undisclosed service, credential searching, or renamed old cutouts. Programmatic rectangles, trees, and grids are explicitly greybox tests, not production art.

New components accept **explicitly authored final movement_envelopes**, adding no automatic margin and avoiding duplicate hero-radius expansion. Footprints are authored ground-contact data. Automatic expansion, whole-town clearance, and cross-layout travel migration remain unimplemented. Complete-ground checks prove alpha coverage, not correct painted content; production assets and playtesting must verify that.

When unblocked, produce the first independent set using the [asset brief](../art-production/TOWN_MODULAR_ASSET_BRIEF.md), replace greybox resources, recheck the same runtime chain, then migrate closed regions/the whole town.
