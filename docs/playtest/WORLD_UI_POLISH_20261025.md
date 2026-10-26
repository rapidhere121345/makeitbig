# World and UI polish — 2026-10-25

Status: rendered acceptance, frozen full build and local publication passed.
Build: `20261025-105508-5f4edd733ff5`.

## Player-visible changes

- Quieter slate town header and news panels, a readable two-line objective, and
  measured encounter-heading fit. The complete boss name and Report control fit
  within their panels.
- Four original native 32px skill icons, clearer key/name/state rows, compact
  arrow wakes, impact sparks, mark diamonds and mobility accents. The accepted
  actor sheets supply the complete character body; old procedural clothing
  repaint is removed, with only stride dust and release accents retained.
- Fifty low ground decorations: 32 in town and 18 across the combat ground
  presentation. Ferns, mushrooms, votives and rune fragments draw below actors,
  scenery and telegraphs; they add no collision or interaction authority.
- Keyboard entry focus on talents, facilities and the ending action, with
  existing focus preserved during refresh. Facility workspace scrollbars expose
  long inventories and protocols.
- All 15 talent names have dedicated readable captions below compact medallions.
  Allocation, refund, reset, inspection and tier-gate behavior remain authoritative.

Ground-footprint padding 5, whole-object reveal alpha 128/255, opaque actors,
projectile geometry, damage, cooldowns and animation contracts are retained.
The baseline comparison checked 420 files under game, systems, runtime and
room content with zero changes from release `20261025-054740-5f4edd733ff5`.

## Original art and reproduction

Eight assets were generated using the built-in image generation tool. Exact
prompts, original sources and hashes are retained under
`docs/art-production/world-polish-20261025/`. The accepted world calibration was
used as a style reference; its pixels were not cut out for these assets.

`tools/art_pipeline/world_polish_v01/build.py --verify` verifies byte-identical
packing. Eight import sidecars preserve their Godot UIDs and disable alpha-border
processing. All 53 generated textures match their source RGBA8 pixels after
import. Runtime art is in `art/production/p1/world_polish_v01/` and placements
are in `content/presentation/world_dressing.json`.

## Rendered acceptance

Evidence root: `build/current/world-polish-20261025/`.

| Scope | Evidence | Result |
| --- | --- | --- |
| Production UI routes | `review/run-20261025T103322Z/GATE.json` | 330 checks, 0 failures, 32 PNGs; import, parse and renderer exit 0 |
| Mounted combat and real skill actions | `arena-render/run-20261025T095848Z/FINAL_REPORT.json` | 148 required checks passed; 26 PNGs; engine exit 0 |
| Targeted syntax/import/combat checks | `validation/20261025T095312Z/exits.tsv` | All actual exits 0; no script/shader errors |
| Facility entry and full facility suite | `validation/facility-focus/exits-r2.tsv` | Both actual exits 0 |
| Final talent layout and authority | `validation/final-talents/exits.tsv` | Character, progression icons and real talent refresh all exit 0 |

UI captures cover title, tutorial, town, dialogue, settings, contract, loadout,
talents, training, forge, proxy, journal, combat HUD, arena pause, results and
ending at 1280×720 and 1600×900. Every state also receives a 1024×768 layout and
focus probe, without an additional screenshot. The Proxy scroll test sends wheel
events to the mounted viewport, reaches its final section and returns to the top.
Talent checks use all 15 real authored names and verify full text, rendered lines,
board bounds and separation from every medallion. Allocation colors were checked
before and after a real profile allocation, then the fixture was reset.

The UI harness uses production GameRoot route APIs with fresh/run-local saves;
it is not a complete human input playthrough. A real mounted Auto contract
settles before Results and Ending are captured. The separate arena harness uses
actual player-cast requests and simulation ticks for Mark, Dash, Dodge, arrow
release and damage, plus enemy windup, boss telegraph, ring and corridor routes.
Later talent/facility/Report UI fixes do not change its skill or world evidence;
the final UI run covers the resulting interface.

Both rendered runs retain source snapshots with no drift and verify private
Xvfb process, authentication, socket, lock and override cleanup. Rendering uses
CPU Mesa/llvmpipe: this proves visual correctness, not hardware performance.

## Failed attempts and limits retained

- UI run `095555Z` exposed a real Report-button overflow and missing initial
  facility focus, plus a harness race while Auto settled during screenshots.
  Tutorial and town arrival intentionally own movement input rather than GUI
  focus; those false-positive requirements were corrected from source behavior.
- Runs `101305Z` and `102320Z` exposed long talent names and overlapping caption
  geometry. The final layout gives captions separate space; the final gate
  continues to reject medallion overlap and incomplete names.
- Frozen gate `20261025T103523Z` stopped at three obsolete source-shape assertions
  in `test_combat_marks`: circle mark and large dodge brackets. The test now
  checks the accepted diamond, ground-level dodge ticks, target health/expiry
  and simulation active window. The bounded targeted rerun exited 0; no product
  code changed in this correction. A fresh full gate is required.
- Frozen gate `20261025T104033Z` passed the combat-mark regression, then stopped
  at the old workbench expectation that facility scrollbar chrome be hidden.
  The facility workspace now joins detail readers and dropdowns in requiring
  visible chrome; all overflow and interaction checks remain. Its targeted
  rerun exited 0. Both failed gates retained identical before/after inputs.
- Earlier parse/authentication attempts and their raw logs remain preserved.
  SWE's `check_polish.log` exited 0 while containing a subsequently fixed parse
  error; it is not accepted as a clean syntax gate. The parent rerun and frozen
  gate supersede it.
- Arena acceptance records one informational corridor parking shortfall: one
  live enemy for two planned parks. It makes no two-enemy assertion there.
- Arena shutdown logs retain 67 ObjectDB instances and six resources in use.
  Process/display cleanup passed; memory-clean fixture shutdown is not claimed.
- Windows export is verified as an artifact; native Windows execution is not
  claimed. No live release endpoint is probed by this task.

## Frozen build and release

Frozen gate `20261025T104519Z` passed: check exit 0, complete container build
exit 0 (500 seconds), no script/shader/parse errors, no leftover stage processes.
The full suite includes 600/600 encounter victories, 30/60/144Hz deterministic
replay and matching presentation-off replay. Fresh Linux export smoke passed
from an empty directory; Windows execution is not claimed.

Before/after freeze: `2723339f95da285ec5e4ecbde9d6a2222959057df448ab0c104bda7009514192` (identical).

| Export | Bytes | SHA256 |
| --- | ---: | --- |
| Linux | 128658272 | `01a8fda736c69fd03d2045de23122cfe79eaa010d52cc4210e65a6323d853a93` |
| Windows | 164266544 | `f234071835128c9266417fe99fbbba7dfda27ab679c81c791d0067e9be62b13b` |

Published locally as `20261025-105508-5f4edd733ff5` at the canonical `release-online/`
root for [the release page](http://192.0.2.10:18080/). Packaging, index, static site,
`release.sh verify --deep`, deployment validation and stage check passed.
All six prior builds remain; seven builds verify with SHA256. No pruning,
host-network changes or live endpoint probes were performed.

Evidence: `build/current/native-fade-final-gate-prep/runs/20261025T104519Z/`
and `build/current/world-polish-20261025/publication/publication.json`.
The package includes its exact input manifest and gate/export provenance;
the revision suffix identifies a dirty working tree, not a new commit.

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
