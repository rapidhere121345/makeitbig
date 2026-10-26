# Native Primitive Fade - Partial Two-Region Acceptance - 2026-10-23

Status: **verified partial native acceptance of the primitive fade in two
town regions (Loadout building and tree_south); the rest of the town still
runs legacy occlusion — no whole-town art-migration claim.** No overall town
PASS. The full gate now PASSES and the local publication completed
([final gate record](NATIVE_FADE_FINAL_GATE_20261023.md)); live endpoint
verification stays outstanding there. Closed so far: C5 and B8 (corrected
continuation runs), B9 (geometry classification, not a contact pass), and
the E/F/G evidence below. The shore's second sustained-contact leg and the
G-stage NW corner (INFO, no claim) remain open coverage limits.

## Runs (read exactly from the artifacts)

| Run | Phases | Checks | Finish state |
| --- | --- | --- | --- |
| `town-r2-preparation/runs/20261023T091126Z` | A, H (native-fade H trial) | 13 pass / 0 fail / 0 info | reason `complete`, `CHECKPOINT.json`: "H CLEAN"; D,C,B,E,F,G deferred |
| `runs/20261023T091651Z` | A, D, C (partial) | 33 pass / 1 fail / 1 info | reason `gate failed: C5_fence_corner` |
| `runs/20261023T092620Z` | A, B | 18 pass / 1 fail / 0 info | reason `gate failed: B8_westgate_pushW` (short-edge sample count) |
| `runs/20261023T094241Z` | A, C5T, B8T | 7 pass / 1 fail / 0 info | reason `gate failed: B9_tar_pushN_fromSouth`; E/F/G not run |
| `runs/20261023T095403Z` | A, B9T, E, F1 attempt | 20 pass / 1 fail / 0 info | reason `gate failed: F1_departure` (acceptance-confirmation card); F2/G not run |
| `runs/20261023T102637Z` | F, G (three driver stages, one serve session) | raw 20 rows: 14 pass / 5 info / 1 fail | final-stage `SUMMARY.json` 10/0/1 covers only the FREST/G stage; earlier stage summaries 5/1/0 (selector failure) and 3/0/0 |

Both: post_boss fixture-based profile, private display `:205`, sentinel stop,
`cleanup.json` reaped / auth removed / Xvfb exit 0, override.cfg created and
removed per run (fail-closed policy). Renderer llvmpipe — CPU correctness
evidence only, no performance claims.

## What the acceptance covers (strict contract, verified in state)

- The fade contract is exact and independent per piece: open state
  `weight 1.0`, `piece_alpha 0.25 == target_alpha 0.25 == faded_alpha 0.25`
  (transition 0.18 s), closed state `weight 0.0`, alpha 1.0 — checked in
  every `POLICY_EVIDENCE` record, not inferred from pixels.
- The actor stays fully opaque: `town_render.primitive_fade…actors
  {"town/ranger": 1.0}` and `actor_modulates` all 1.0 while the piece fades.
- `common_excluded_from_effect_rows: true` everywhere: the only common-layer
  evidence in these runs is its absence from fade effect rows; live
  common-base proof lives separately in the headless/preview lanes
  ([preview acceptance](TOWN_PRIMITIVE_FADE_SAMPLE_ACCEPTANCE_20261023.md)).
- Two regions only: `town/native/loadout` (fade volume polygon
  (624,105.0625)–(799,186.0625)) and `town/native/tree_south` (triangle
  volume); every other native piece is legacy.

## Run 1 (A/H) — verified facts

A1 route/spawn pass; A2 calibration 2.0 px/frame. H1 T11 position
(666.312, 256.947), roof closed at front (`open_rows` empty); west cycles
c1–c5 clean (`nav_ok_all`, no behind misses, no open-at-front, no hold
losses); west exact-Y sweep crosses the baseline, transition y 199.347
(2 open / 8 closed samples); north open and held-final evidence at the .25
contract; T26 (791.73, 765.716) tree_south open with coverage 0.3159 and
clean cycles; H3 exit settled closed (`open_rows` empty).

## Run 2 (A/D/C) — verified facts, failures retained

- A: navstart reached within 1.8 px (pass); calibration 2.04 px/frame.
- D: fire edge-contact pass (start clearance 24.466, hold clearance 6.0);
  lamp4 circle-contact pass (min radial clearance 0.001 over 90 hold
  frames); D3 loadout behind open at .25 / front closed at 1.0; D5 roof hold
  and held-final at .25; D6 south-face block, corner NW and NE contacts
  pass; D7 Loadout facility opens (approach_ok true, distance 33.06, route
  `loadout`) and returns; D8 Taren dialogue opens (speaker `Taren`) and
  closes — a real resident, unlike Round-2's speaker-null evidence.
- C1 shore: blocked (signed clearance 6.0), escape 57.6 px, reapproach
  clearance 7.2 (delta 0.3). Slide leg `+` is **INFO, not pass**: projection
  33.62 px of a 37.123 px segment leaves only 3.51 px of room —
  insufficient; the opposite leg `−` passed (29.75 px along edge, 14 rows
  within the finite edge). Only one sustained-contact leg is proven; do not
  claim both.
- C3 tree south: behind/front/held evidence — tree_south opens behind
  (expect_open true, open true), loadout stays closed; trunk contact probes
  from N/S/E/W pass; exact-Y sweep passes (transition y 773.35).
- C4 two occluders: the executed pair is `training_east_south` +
  `training_south`, both open (overlap 1845) after the intended
  forge/forge_chimney pair produced only one open row. These are **two open
  legacy training pieces, not two primitive fades** — it is not two-fade
  evidence.
- C5: fence edge-block passes (hold clearance 6.0), but
  **`C5_fence_corner` FAILS**: expected a convex bound SE corner with a
  legal standpoint; binding `arrival_storage_fence`, picked vertex
  (706.0, 736.875) over base segments 000–003, note "no silent fallback to a
  different corner". The corner attempt failed before movement: the picked
  SE vertex's bisector start is bad near the adjacent gate. Parent's
  offline d19 analysis: a same-vertex SE with the NW ray reversed is
  possible; **no corrected executed PASS existed at that point** — the
  continuation run below supplies it.

## Continuation runs — C5 and B8 closed

**`092620Z` (A/B, 18 pass / 1 fail).** Board opens and returns
(approach_ok); Leia dialogue opens with speaker `Leia`, two pages, and
closes (B2x now records a real speaker, pages 2, closed — evidence-only note
retained); Training opens and returns; training-north and
training-east-south south-face blocks and NW corners pass; B5 circle contact
110 hold frames pass; Iven dialogue opens/closes; cart block passes. The one
failure is `B8_westgate_pushW`: `legs_ok: false` — the short edge produced
too few moving samples under the original probe form (hold_effective 10,
tangent progress 3.142/6.283). No runtime fix was made between runs.

**`094241Z` (A/C5T/B8T, 7 pass / 1 fail).** Corrected C5 corner **passes**:
mode `opposite_input_ray`, same vertex (706.0, 736.875),
`contact_at == reversal_origin == (711.006, 740.208)`, `same_corner_escape:
true`, `contact_pos_verified: true`, clearance gain **41.497**. Corrected
B8 **passes**: short-edge mode `short_edge_calibrated_strokes` records 2
moving samples in each stroke with finite-edge progress 5.304 / 6.283, every
stroke at clearance 6.0; B8 corner NW passes with
`contact_at == reversal_origin == (616.495, 767.199)`, same-corner escape
true, gain **29.735**. The new failure is `B9_tar_pushN_fromSouth`:
`contact_reached: false`, min radial clearance 31.913 after 120 approach
frames, `nav_ok: false` — the south approach point sits inside
southwest_forest, so the tree arrival is unreachable from the south; a legal
north approach is pending. E/F/G were not run.

Both continuation runs: post_boss fixture, `cleanup.json` reaped / auth
removed / Xvfb exit 0; session `engine.log` and `window-owner.log` re-scanned
here with the standing error patterns — 0 hits each. The parent verified the
records and viewed `B2x_leia_protected_dialog_open`,
`B4_training_east_south_blockSface_end`, `C5_fence_corner_reverse`, and
`B8_westgate_pushW_end`. The failed original attempts (091651Z C5, 092620Z
B8) stay preserved above; no history rewrite.

## Continuation runs — E, B9 classification, F/G (095403Z, 102637Z)

**`095403Z` (A/B9T/E, 20 pass / 1 fail / 0 info).** B9 closes as a
**continuous-geometry classification, not a contact pass**: the target trunk
(`town/static/tree_arrival_trunk`, center (282.0, 868.125), combined radius
14.50 per the 094241Z record's own expected field) is classified untouchable
— `B9_tar_trunk_untouchable` records `reachable_contact_angles: 0`, and the
south approach point (282.0, 896.13) sits inside `southwest_forest/006`
(clearance −26.348), matching the 094241Z failure. The parent's independent
geometry review puts the forest at distance 12.762729 with max contact
clearance 2.437271 (< 6) — no legal contact corridor exists, so no contact
pass is claimed. E passes: Mira dialogue opens (speaker `Mira`, distance
13.09) and closes; E1x INFO evidence records 4 standpoints, approach angle
103, pages 3, closed, occlusion scores [7,7,7,7]; the tree_east north push
(label `E2_teast_pushN`) holds 110 frames; Oren dialogue opens and closes;
proxy and forge facilities open and
return (distances 36.72 / 35.57); forge chimney block passes (start
clearance 21.698); tree_wood north is classified unavailable (label
`E7_twood_north_unavailable`, point (541.0, 327.31), clearance 0.17,
collider `wood_contract_base/000`) with the tree_wood push contact pass
(`E7_twood_pushN_fromSouth`); E8 two occluders uses the same legacy training pair as
C4 — still not two-fade evidence. The run stopped at `F1_departure`
(`CHECKPOINT.json`: "stopped at F1_departure (harness:
acceptance-confirmation card)"; F2/G not run): `F1_board_open` passed, the
departure failed on the route contract (picked true, start_clicked true).
Cleanup reaped / auth removed / Xvfb exit 0; `engine.log` and
`window-owner.log` re-scanned here — 0 hits each.

**`102637Z` (F/G — three driver stages in one serve session).** The raw
`results.jsonl` is the append-only union across stages: **20 rows — 14
pass / 5 info / 1 fail** — and the initial failure is retained. The observed
sequence only: before the click the focus window was the root PointerRoot
(window 1) while the pointer already sat over the game window (child
2097155); after the click the focus became the game window and the popup was
open, yet the contract text stayed "Graduation Trial · AUTO" — the cause is
**not isolated** to the PointerRoot focus state. The retry — game window
focused, plus a hover nudge per the driver's retry sequence — clicked the
same [215, 549] and PASSED, selecting **"Side · Targeted Equipment"** by an
actual X11 click; the mode popup read **Manual** and `F1_mode_manual_verified`
passed. Departure passed (route `arena`, `routes_seen ["arena"]` — the
current arena observed, contract picked, start and confirm clicked); the
abandon-path screenshot (Escape / Tab ×5 / Enter ×2) records "Confirm
Abandon · Forfeit Rewards" in the rendered menu per the parent's viewing —
the confirmation prompt's `state.json` controls show the arena HUD (HP 112 /
112, "Room 1/3 · Salvage Ring · Hunt Elites", "MANUAL [Locked]", Leave), not
that string. Return passed via route `result`, then result-to-base. G stage:
per-axis camera clamps pass — west camera (0, 30.911), north (108.799, 0),
SE (896, 600); resize to (1600, 900) and back to (1280, 720) pass.
`G1c` NW corner is **INFO — `reachable_cells_satisfying: 0`, unreachable, no
claim**. `G4_loadout_1600` and `G6_wide_arrival_1280` are capture-only (no
check rows). Per-stage summaries: 032659 5/1/0 (the selector failure),
032725 3/0/0, 032923 10/0/1; the run's `SUMMARY.json` equals the 032923
file — it covers the final FREST/G stage only, not the whole session. The
parent viewed `F2_confirmation_prompt`, `G4_loadout_1600`, and
`G6_wide_arrival_1280` and accepted them, inspected the rows and raw logs,
and verified the cleanup JSON (reaped / auth removed / Xvfb exit 0); this
record re-scanned `engine.log` and `window-owner.log` — 0 hits each.

All failed attempts stay preserved (091651Z C5, 092620Z B8, 094241Z B9
south, 095403Z F1_departure, and the 102637Z first selector click), plus
five harness-only UI attempts that produced no successful F2/G — 100036Z
and 100335Z stopped at `F1_departure`; 101439Z, 101916Z, and 102326Z
stopped at `F1_mode_manual`. No history rewrite, no runtime fix between
runs. The final-gate launcher's first attempt
(`native-fade-final-gate-prep/runs/20261023T103125Z`) failed before any
engine stage — `RESULT.json` records `stages: []`, exit 1, with the
aggregate step's own error in `manifest.final.err` (a file redirected onto
itself); an ignored-runner repair was authorized (`freeze_drift: false`, no
runtime drift), the gate was relaunched, and it now PASSES — recorded in
[the final gate record](NATIVE_FADE_FINAL_GATE_20261023.md), not here.

## Hashes and preserved evidence (current, not the old freeze)

Scene `content/rooms/town/hearthside.tscn`
`c21070c233b51c553a6a493f9ba0a3120efe01c96d21efce374d4a4e623f9f47`; manifest
`content/rooms/town/hearthside.spatial.json`
`913353fa313671e1f19e37f1b10b9dee9eb45260418560a2b618d2e9c7e67439`; new
runtime policy `src/presentation/occlusion/primitive_fade_controller.gd`
`c0e000d95934b84d8a7c451a1f04325cbfe1fe53195548852281b90674791198`
(presenter `town_presenter.gd`
`86cbc161da325bbf80c9afd637b5731ab222166359f87737821e2d4583055778`).
These are fresh hashes of the current checkout — earlier lanes' frozen
fixture hashes do not apply here. Per-run fixture copies are hashed in each
run's `fixture-copy.json` (post_boss `FIXTURE.json`
`83616fd9…1e594`); fixture saves are fixture-based (debug stage ladder
through real settlement code), never human-playtime evidence. Preserved
stale-travel spawn-fallback test evidence:
`tests/test_town_runtime.gd` `_test_old_travel_rejected` (a saved travel
position at (750,230), former floor now inside the Loadout envelope, must be
rejected by `restore_travel` with no partial commit, hero kept on the
published spawn).

## Parent review and scans

The parent inspected run-1 frames H1_T11_readability, north-roof open,
west hold, H2_T26_arrive/tree-behind, and run-2 D3 behind/front, C3 behind,
C5 fence block, and accepted the captured states: readable hero, solid
base, credible backing, ordinary quarter fade. The parent scanned both raw
engine logs (no script/parse errors, no shader compile/bind failures); this
record re-scanned them with the same patterns — 0 hits each.

## Not accepted by this record

Both-legs sustained shore contact; any B9 contact pass (classification
only); the G-stage NW corner (INFO, unreachable — no claim); whole-town fade
migration; live-verified online availability (publication completed locally
and is recorded in [the final gate record](NATIVE_FADE_FINAL_GATE_20261023.md),
with operator tailnet verification still outstanding).
Crosslinks:
[preview fade acceptance](TOWN_PRIMITIVE_FADE_SAMPLE_ACCEPTANCE_20261023.md),
[sample acceptance](TOWN_LOADOUT_SAMPLE_ACCEPTANCE_20261023.md),
[Round-2 runs](TOWN_ROUND2_20261023.md),
[silhouette fixture](TOWN_SILHOUETTE_ACCEPTANCE_20261023.md).
