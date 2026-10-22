# Hardware GPU Visual Acceptance - R1/R2 Fix Round - 2026-10-20

Covers initial acceptance and rechecks of spatial truth (blockers), town occlusion, and visual fixes. Two independent vision models reviewed images and enlarged evidence: glm-5.3-flash#max primary and deepseek-flash#low secondary. The `tools/play_session` window protocol drove input and capture.

## Environment

- Godot 4.7.2.stable.official.ed1daf0bf, X11 window 1280×720, Dummy audio.
- Renderer: `OpenGL API 3.3.0 NVIDIA 595.91.07 - Using Device: NVIDIA - NVIDIA GeForce RTX 4080 SUPER` (first engine.log line; RTX evidence meets the standard).
- Display: Xvfb `:97` + NVIDIA vendor library (host desktop X server unavailable that day; permitted alternate entry, PRIME offload active).
- Ignored session directories: `build/current/gpu-visual-r1r2/` (28 initial frames), `gpu-visual-r1r2-fixverify/`, `gpu-visual-final/` (rechecks).

## Initial Findings and Treatment

| # | Severity | Finding (reviewers agreed) | Treatment |
|---|---|---|---|
| 1 | Blocking | 8-10 solid white/light-gray hard-edged polygons exactly match new combat colliders: blocker Polygon2D nodes rendered default white without `visible=false` | Fixed 39 nodes; `RoomAssetRoot` contract adds fail-closed `static_blocker_visible` check; `test_combat_structure_blockers.gd` asserts invisibility |
| 2 | Serious | Hero completely swallowed while walking in town (09-2 banner/rocks, 09-8/9 logs/pines, no silhouette); graded transparency never visible | Two roots fixed: (a) dimming an entirely hidden subject is visually ineffective; refactored to occluder reveal (OcclusionController occluder registry reuses levels; TownPresenter reveals foreground while subject stays opaque); (b) floating facility nameplates actually hid the hero (280×72 dark Training/unverified plate); added nameplate reveal, tweening to 0.25 when hero cells intersect plate rectangle |
| 3 | Normal | Hero feet overlap wall-top stone pixels during wall sliding, appearing inside the wall | R4 tuning backlog, footprint/art alignment, untreated |
| 4 | Polish | Stale out-of-range toast contradicts in-range status | Backlogged |
| 5 | Polish | Inconsistent movement/hit indicator colors; training-target bar changes color but not width | Backlogged |

## Recheck Results (gpu-visual-final)

- **White blocks: 7/7 frames clean.** Tower base, ruined walls, and gatehouse have normal textured/snow-capped/shadowed art; no clipping along tower west and ruined wall.
- Tutorial → town → Contract → combat works end to end, including click/Space casting, damage 720→488.116, hero hit -5.
- `test_presentation_production_assembly` covers nameplate and foreground reveal (probe drives occluder alpha while subject stays opaque), alongside code review.

## Interactive Final Acceptance (deepseek-flash#low, Self-Driven)

Reviewer launched the RTX session, sent input, captured and inspected frames directly. About 30 `ds-*` evidence frames are in the same directory:

- **White-block fix passed:** five combat panoramas have only 0-26 white pixels, all text antialiasing; towers, walls, and broken beams show normal art.
- **Nameplate reveal passed:** fades on northern approach, restores on departure, repeatedly triggers. Feedback raised reveal alpha from 0.25 to 0.35 so background no longer disappears entirely.
- **Wall sliding passed:** smooth lateral movement without sticking; 3-5px foot/low-wall-top overlap remains R4 backlog.
- **Flow/free exploration passed:** town → Board → departure → results → return works; damage numbers, dialogue, bestiary, and results layout normal.
- "Unreadable departure confirmation" proved a **protocol artifact**: its 0.10s fade tween freezes halfway when play_session pauses between commands. Continuous play does not exhibit it (`contract_screen.gd:855`).

New backlog: Recent panel scroll-edge clipping; interaction/dialogue mismatch ([E] Iven → Wanderer); noticeboard hides NPC except bubble; concept borders/gates look like debug lines; report final-line clipping; no observed health loss while surrounded for 200+ ticks (gameplay, reproduction pending).

## Conclusion

Blocking and serious issues were fixed and independently rechecked by both models; polish remains backlogged. Evidence frames are in the ignored directories above; this document is the durable record.
