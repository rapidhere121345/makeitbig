# Ground contact and local lighting — 2026-10-25

Status: complete. Final visual review and frozen full gate passed; build
`20261026-043825-5f4edd733ff5` is packaged on the existing release page.

## Intent and scope

The user accepted the expanded town and requested shadows and lighting so actors
and scenery feel attached to the floor. The visual priorities are grounded feet,
quiet dark-fantasy light, native pixel edges, and readable combat warnings.

`grounding_effects.gd` draws cached procedural contact masks and local light pools.
Static contact masks follow the lowest opaque contour within the lower part of
each source sprite, excluding detached high roof/canopy pixels. Masks are derived
from alpha without changing any authored PNG. Actor shadows use small feathered
pixel ellipses at the authoritative feet; they do not follow animation bobbing.

Town mounts one `TownGrounding` node in GroundEffects above the ground and bridge
decks, below dressing, scenery and actors. It grounds all sortable environmental
sprites and the Ranger/five residents. Lamps, forge/hearth, house fronts and the
proxy receive restrained warm or cool ground spill. The low relic/votive/plant
dressing has its own contact seam, with small emissive pools where appropriate.

Town sprite illumination uses RGB self modulation with alpha one. Existing
modulate alpha and reveal materials remain separate. Arena actual action-frame
draws and structures receive bounded RGB illumination from the existing tower
and ruin lights; hit flashes retain priority. Arena contact shadows replace the
old broad trapezoids. All effects remain below combat telegraphs and the HUD.

These are stylized contact shadows and local color spill, not physically traced
lighting. No camera, physics, water collision, animation timing or source-art
contract changes are intended.

The native scene contract is validated before presentation applies its RGB tint;
authored scene defaults remain white. `grounding_report` identifies this as a
presenter-owned override, not an authored geometry/material change. Static masks
use resource paths when available and a 128-entry least-recently-used bound, so
repeated mounts cannot grow the retained mask set without limit. Sprite response
uses the same vertical light footprint as the drawn ground pool.

## Targeted evidence

`build/current/grounding-20261025/validation/` contains the syntax log and
`exits-1.tsv`. Six scripts exited zero with no script/parse errors:

- `test_grounding`: real town mount, feet alignment, bridge/actor layer order,
  camera-independent anchors, unchanged authority, alpha preservation, source
  pixel preservation, contour exclusion and overlapping-light color budget.
- `test_world_dressing`, `test_world_occlusion`, `test_arena_actor_presenter`,
  `test_scene_atmosphere`, `test_combat_presentation_boundary`.

The full gate will recapture these together with the existing combat and town
movement suites. Graphical strength/readability is judged from rendered scenes,
not inferred from these headless checks.

Review follow-ups were applied before the first rendered run: bounded mask cache,
matched pool/tint falloff, and corrected offsets for clipped source regions.
`test_grounding-2.log`/`exits-2.tsv` cover the cache reload stress, source-region
alignment and light boundary cases as well as the mounted checks above.

`validation/source-png-invariance.json` compares all 171 runtime PNGs recorded
by the prior accepted full gate (`20261025T185701Z`): none changed. The new
shadows and illumination are generated during presentation.

## Rendered evidence

`build/current/grounding-20261025/render/run-20261026T040757Z/` passed with
17/17 PNGs (10 town, 7 arena), engine exits 0/0, no raw engine errors and no
source drift. Private Xvfb/auth/socket/lock and resource-override cleanup passed.
The town report records 316 passing checks and 1,851 moved ticks; the arena
report records 61 passing required checks and zero failures. The corridor's
optional two-enemy parking fixture had only one live enemy.

The images include town arrival at 1280 and 2560, bridge midpoint and bank
views, ghosted house and base contact, relic dressing, expedition gate, three
combat floors, enemy windup and boss warning. Same-mounted-view probes compare
visible versus hidden ground-effect layers and find changed pixels around hero
feet, house/relic bases and lamp pools. These are not old/new camera-aligned
pixel comparisons. Actors remain alpha one; paired reveal and motor traversal
checks still pass. Contact shadows are small, local light stays restrained,
and combat warnings remain distinguishable.

Earlier failed attempts are preserved. Their failures were in the ignored
capture drivers: type inference, viewport-size bookkeeping, a missing returned
probe flag, array-to-vector conversion and a missing capture invocation. No
production changes were needed to resolve them.

Rendering used CPU Mesa/llvmpipe. This proves visual behavior, not hardware FPS.
Before the full freeze, a bounded editor import exited zero with a clean raw
error scan and generated the three new script UID sidecars; source behavior and
art remained unchanged.

Visual review then found that boots covered too much of the actor contact
ellipse. `draw_contact` now shifts the patch two world pixels downward, exposing
a seam below the boots while its upper rows still meet the feet. Sizes and
strengths are unchanged. `test_grounding-3.log` passed with exit zero and no raw
errors. Full gate `20261026T041310Z` was intentionally interrupted (exit 143)
before this edit; its runner confirmed the owned build process group was empty.
That interrupted gate is retained and is not acceptance evidence.

The offset-only refresh (`041653Z`) again passed all 17 captures, but remained
too faint in the reviewer's fixed-standing comparisons. The final candidate
uses a denser stepped contact core and a 21×9, 0.60-strength Ranger/resident
patch; light-pool falloff is unchanged. Other arena actor patch sizes/strengths
remain as authored for their silhouettes. Targeted grounding and arena actor
tests both exited zero with clean raw logs (`exits-4.tsv`).

Final packet `run-20261026T042244Z` passed 17/17 captures, town 316/316 checks
with 1,851 moved ticks, and all required arena checks; raw errors and source
drift were zero and owned renderer cleanup passed. Review accepted the denser
contact core: fixed-framing comparisons against `040757Z` showed mean luminance
drops of 15.1/255 on the bridge contact and 17.6/255 at the gate, with both
patches visibly attached beneath the boots. The town resident also gained a
clear contact seam. Pools, reveal alpha, HUD and telegraph readability remained
unchanged. The previous offset-only candidate is superseded by this packet.

The renderer's raw-error counter excludes shutdown leak diagnostics. The final
arena log reports 57 ObjectDB instances and six resources still in use at exit,
with engine exit zero, matching the previously disclosed arena capture counts.
No clean-memory or hardware-performance claim is made.

## Full gate and publication

`build/current/native-fade-final-gate-prep/runs/20261026T042652Z/RESULT.json`
records PASS: syntax/check stage exit 0 in six seconds, full container build
exit 0 in 612 seconds, and zero leftover process groups. The before/after
freeze is identical:
`dcd1a870dd455c6721c6be8a16a43da32c283e2ba69c8145c19c69d8e3415541`.
The log has no script, parse or compile errors. Expected capture-contract
headless negatives are preserved in the log and do not indicate regressions.

The gate recaptured grounding, native town/geometry, gateway, wedge-contact,
display, combat-room and authority checks. It verified all 69 exact imported
RGBA8 images and deterministic art packs. All 600 encounter cases won; the
30/60/144 Hz and presentation-disabled replays matched the accepted hash
`b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`.
Both exports completed, and the Linux executable passed the empty-directory
scene smoke test. Independent final review accepted the packet.

| Export | Bytes | SHA256 |
| --- | ---: | --- |
| Linux | 134,582,640 | `e0c60f0d6c650400063e73846af7582f7e5e372821bf8fae4965309e5736e917` |
| Windows | 170,190,912 | `db3c3b141a609f10559d2319bb89ca71b6b2e447b3cfd3f56cbcde968d099a60` |

`build/current/grounding-20261025/publication/publication.json` records build
`20261026-043825-5f4edd733ff5`, the certified freeze and exact export hashes.
The no-prune publication preserved all eight prior builds. Release deep verify
SHA-checked nine builds; Tailscale static validation and staging checks passed.
The existing download page is <http://192.0.2.10:18080/>. No host networking
changed; the live endpoint was not probed and native Windows execution is not
claimed. The revision identifies a dirty working tree; its precise contents
are recorded in the packaged freeze manifest, not represented as a new commit.

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
