# World expansion and modern displays — 2026-10-25

Status: implementation, targeted checks, rendered acceptance and the frozen full
build passed. Certified Windows and Linux exports were published locally as
`20261025-190800-5f4edd733ff5`; all seven prior release builds were preserved.

## Frozen build and publication

Gate `build/current/native-fade-final-gate-prep/runs/20261025T185701Z/` passed:
syntax stage exit 0 (5 seconds), `container_build.sh` exit 0 (616 seconds),
and no leftover stage processes. The complete test script captured the town
native contract, geometry, generated layout and runtime suites, plus spatial
kernel and actor motor regressions. The wedge test logged 96 contact ticks and
40 reverse ticks with every endpoint clear. The live expedition gate reached
Contracts with exactly one signal.

The encounter matrix passed 600/600 victories. Automation replay hashes matched
at 30, 60 and 144 Hz and with presentation disabled:
`b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`.
Both platform exports completed and the Linux executable passed its smoke test
from an empty temporary directory. Raw logs contain no script or parse errors;
the shutdown resource diagnostics described below remain.

Before/after frozen input manifests are identical:
`4a0f0cbe9a5c0af5990e5ede730492c5f80c154f9ecb3ac8377afe1ae4a012c5`.
The checkout is dirty; the manifest identifies the certified inputs rather than
claiming the Git revision alone describes them.

| Export | Bytes | SHA-256 |
| --- | ---: | --- |
| Linux x86_64 | 134568168 | `e56a0d993878ee513b008d93b7314b8e883f14fcd5e572801104cd951fc23f09` |
| Windows x86_64 | 170176440 | `fc68f4b9c98fad98ba0df704f63eeafa98e1d6054e26e6dbb111a946a93cfb99` |

Publication recomputed the frozen manifest and both export hashes, packaged those
exact files, regenerated the index/page, and passed `release.sh verify --deep`,
`deploy/tailscale/validate.sh` and `stage_release_page.sh --check`. Eight builds
now verify, including every prior build; no pruning ran. Evidence is under
`build/current/world-expansion-20261025/publication/` and the release's
`provenance/` directory. The canonical page is [the demo release page](http://192.0.2.10:18080/).
The live endpoint was not probed and native Windows execution was not tested.

Independent Fable review accepted the final gate, publication hashes and the
matching rendered packets. No concrete behavior defects remain open from that
review; the disclosed polish and validation limits below remain.

## Implemented scope

Hearthside has a winding river with two differently oriented, walkable bridges,
mountain borders, wall sections at mountain passes and southern gates, an eastern
pine-and-fence perimeter, and four houses split between two facade orientations.
The main north-bank settlement is naturally enclosed; the southern outskirts
still terminate at the map boundary and are not claimed as a continuous wall.
The arrival and bridge routes follow the actual crossings. The expedition arch
has an authored exit socket: E / Space opens the existing Contract screen.
It does not bypass contract selection or start combat directly.

Water and cliff polygons are authored into the native scene. Only the measured
bridge decks cut through the water barrier. Bridges remain opaque ground art;
houses, plants, walls and gate towers use feet sorting and whole-object reveal
at alpha 128/255. Rectangular and convex polygon ground footprints receive the
same 5px padding, excluding projected roofs and walls. Bridge decks and terrain
are not padded. Actor body radii are unchanged.

Five facilities, their 48px interaction radii, resident placements and the hero
spawn remain unchanged. Four older scenery placements were moved off the banks
or water; the exact moves are in the town layout recipe. Five low decorations
were also moved onto dry ground. These decorations have no collision authority.

The existing court, causeway and ritual-ring combat layouts now have separate
floor art, boundary treatments, entry thresholds and decoration lists. Their
authoritative geometry and gameplay digests are unchanged. Combat wards indicate
contested versus cleared state; the gates remain blocked. Room settlement and
the existing Leave action still control room advancement.

Display settings offer fitting presets through 1440p, ultrawide and 4K, retain
custom current window sizes, and clamp requests to usable screen bounds.
Fullscreen uses the desktop resolution. PixelStage keeps its existing uniform
nearest-neighbor scaling and field of view; ultrawide displays have side borders.
The 640×360 town world viewport remains intentional and unchanged.

## Sources and reproduction

Ten selected assets have original image-generation sources, exact prompts and
SHA-256 records under `docs/art-production/world-expansion-20261025/`. Three
superseded drafts remain as provenance, including the rejected straight river.
The compiler's deterministic verification and 18 synthetic packing tests pass;
all 69 generated runtime textures match their source RGBA8 pixels after import.

`tools/world_manifest/author_town_expansion.py --check` reports 4,036 route
samples, 74 static shapes, 39 expansion-owned shapes, 69 sprites, five facilities,
one gateway and zero failures. The installed scene matches its recipe. These
offline checks are separate from mounted movement tests.

## Targeted validation

| Scope | Evidence | Result |
| --- | --- | --- |
| Display policy, settings, PixelStage, root and pointer | `build/current/display-20261025T090921/ledger.txt` | All actual exits 0; display policy 51 checks and PixelStage 281 checks |
| Distinct combat rooms and mounted regressions | `build/current/combat-rooms/20261025T164603Z/exits.tsv` | 19 final targets exit 0; no script/parse errors |
| Town authoring, bake, movement, native contract | `build/current/world-expansion-v01/town-layout/logs/` | Final logs pass; exit ledger was transcribed afterward from shell output |
| Final migrated presentation and gateway regressions | `build/current/world-expansion-20261025/validation/20261025T172745Z/exits.tsv` | Check plus ten tests exit 0; no script/parse errors |

Town runtime checks continuously cross both bridges in both directions, press
against each deck edge and reverse, reject water/cliff placements, contact the
bank, walk under the gate arch and behind a wall, and reject tower and wall bases.
The production-gateway regression uses freshly mounted scene metadata at
`(1364,905)`: one activation emits exactly one request, reaches Contracts, and
leaves persistent progression unchanged.

The combat presentation boundary checks active, defeat and victory states through
RoomRules, Main's snapshot and the mounted presentation controller. Only victory
sets `room_cleared`; presentation leaves the authority hash unchanged. This is a
controlled terminal projection, not proof of winning a live encounter.

## Rendered acceptance

Two scoped llvmpipe runs provide all 16 captures:

| Scope | Run under `build/current/world-expansion-20261025/render/arena/` | Result |
| --- | --- | --- |
| Town | `run-20261025T184827Z` | 247 checks, 6/6 PNGs, 1,691 moved ticks; exit 0 |
| Combat and modern displays | `run-20261025T185047Z` | 10/10 PNGs; arena and display exits 0 |

Both GATE reports pass with empty source-drift lists; all 223 shared snapshot
inputs have matching hashes. Their owned engines, Xvfb, auth, socket, lock and
resource overrides were cleaned up. Town uses the production GameRoot, mounted
TownRuntime and continuous fixed-tick movement without position writes. Both
bridges pass both-way travel and side-contact/reverse checks. The new house
blocks at its base, fades behind the hero, and restores at the reachable front
point (42,918). The actual E key opens Contracts at the expedition gate.

Display captures are 1920x1080, 2560x1440, 3440x1440 and 3840x2160. Ultrawide has
440px ink side bars; the pause launcher stays inside the stage and scales with
its HUD. The routed synthetic pointer test measures zero error through the live
stage. These are software-rendered correctness checks, not GPU/FPS benchmarks.
Arena wards-down uses a controlled real RoomRules terminal projection; enemy
windup and the boss telegraph use their production action paths.

Final visual review accepted the town and the corrected court approach, gate
curb gap, causeway edges and Pause placement. Remaining nonblocking polish notes
are the flat relic-slab dressing and deliberate bridge/gatehouse overlap.

## Render review corrections

The first corrected arena/display packet (`run-20261025T180544Z`) passed 49 arena
and 26 display checks, but its town driver did not parse. Review confirmed the gate
curb opening, removed causeway end-cap seam, complete entry text, and correct
1080p/1440p/ultrawide/4K stage mapping. Ultrawide pointer mapping reported zero
error. This packet is not overall acceptance.

Review additionally found the root-window Pause button in the ultrawide border.
It now anchors inside PixelStage and scales with the HUD; actual-control bounds
regressions pass at five sizes in `validation/pause-stage-20261025T181942Z`.
The court edge remains beyond the spawn camera; a visible approach treatment is
now implemented along the checked spawn-to-entry segment without changing the
entry point, camera or collision. Its final targeted check, room scenes and
occlusion runs pass with clean raw logs in `combat-rooms/20261025T182057Z-runner2`.

## Contact precision regression

Town capture `run-20261025T182624Z` exposed an invalid motor endpoint at the
south-west house/tree wedge. The house remained clear; a skin/float32 offset
left the hero 0.000195px inside the neighbouring tree's radius test. The next tick
then rejected its own starting position, preventing reversal. The resolver now
checks its final environment clearance and retains the already-validated tick
start if the proposed endpoint is invalid. No footprint, layout or tolerance was
changed. The mounted 96-contact/40-reverse regression failed before the fix and
passes afterward. Five targeted suites (town runtime, spatial kernel, actor motor,
combat blockers and seven spawn profiles) pass with clean raw logs at
`validation/wedge-after-20261025T183606Z`. The final full gate recaptured this
under a frozen tree; the before/after diagnostic jobs briefly overlapped during
collection, so they are not claimed as exclusive-engine acceptance.

## Failed attempts and limits

- Full-gate launch `20261025T185252Z` stopped after a passing syntax stage,
  before the build stage, when its detached output stream closed. Its FAIL
  report is retained. The next launch redirects all runner output to a durable
  file; no product change was made for this interruption.
- The initial approach-runner test attempt (`combat-rooms/20261025T182027Z-runner`)
  printed PASS and exited 0 but logged a script error reading a missing report
  key. That attempt is rejected. The report key was added and the raw-log-clean
  rerun retained separately; PASS markers alone are not acceptance.
- Town run `183852Z` confirmed the corrected corner contact, then failed a
  front-restore fixture destination beyond the legal map edge (y>=927, while
  boundary 928 minus hero radius 6 permits y<=922). The replacement capture probe
  uses the reachable front-side point (42,918), outside the house's reveal box;
  continuous movement and actual fade restoration remain required.
- Subsequent ignored town harness attempts exposed parse inference, a wrong scene
  property lookup, and an initial-window-size assumption. These attempts are
  retained and are not represented as product movement failures.
- The first arena/display capture attempts retained six arena frames and passed
  49 arena checks, but are diagnostic, not final acceptance. Display capture hit
  an array-to-Vector2i conversion error in the ignored harness and timed out;
  town did not run. Process/display cleanup and no source drift were confirmed.
  Visual review found off-screen court entry slabs, a curb across the gate opening,
  causeway end-cap seams and clipped entry guidance. The guidance now uses concise
  authored text; the real HUD font-width regression passed in
  `validation/entry-copy-20261025T175644Z`. The final packets above supersede these attempts. The three combat fixes passed
  `check.sh`, room scenes, world occlusion and room catalog checks with actual
  exits 0 in `build/current/combat-rooms/20261025T175734Z-fixes/`.

- Parent targeted attempt `20261025T172502Z` failed two obsolete ground assertions
  that treated the two bridge decks as extra background patches. The corrected
  tests require one base surface, two mounted opaque bridges, and no runtime
  background patches. Its new ward fixture also tried assigning getter-only
  battle flags; it now uses the real RoomRules projection API. All first-attempt
  logs are retained.
- The combat lane overwrote its first obsolete-helper parse-error log with the
  passing rerun. Its final log and exit ledger remain; the missing first log is
  not claimed as retained evidence.
- Mounted test shutdowns retain ObjectDB/resource diagnostics. The targeted
  presentation-boundary run reports 43 objects and ten resources at exit despite
  exit 0. No clean-memory or long-session stability claim is made.
- Exported packs may contain imported textures without loose PNG files. The
  combat floor loader checks PNG byte hashes when those files are readable;
  editor hash validation is not represented as exported-pack hash validation.
- Final rendered shutdown diagnostics remain: arena reports 57 ObjectDB instances
  and six resources in use; display reports 27 instances and ten resources.
  Both exit 0. The harness raw-error count excludes those shutdown messages;
  no clean-memory claim is made. Native Windows execution remains separate.

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
