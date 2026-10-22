# English Migration and Devbox Preparation — 2026-10-22

## Scope

Prepare the existing first-chapter Ranger demo for an English-language
continuation in the local devbox. The game checkout remains at
`/data/paseo-makeitbig/project`; the operator will later authorize migration to
`/data/claude/workspace/makeitbig`. That destination is not created or activated
by this preparation. No production
town art was generated or replaced, and the modular-town foundation is not
presented as the completed town remake.

## English Source and Data

- Runtime, authored game content, tests, tools, release-page copy, and maintained
  documentation are English.
- The automated guard checks raw Han, decoded JSON keys/values, and escaped
  GDScript. Four authentic legal/provenance originals remain byte-identical,
  with English explanations and SHA256 pins; see `docs/ENGLISH_ONLY.md`.
- Three legacy forge-operation aliases remain accepted only as escaped domain
  inputs, with compatibility tests. Story parsing supports named ASCII-colon
  dialogue, ordinary colon prose, and the historical fullwidth delimiter.
- Independent comparison of 13 changed content/art JSON files passes:
  unchanged schemas, array lengths, IDs/other ASCII strings, numbers, booleans,
  and geometry; the authored town layout digest changes intentionally.
- Native town scene changes are five display-label lines. No tracked PNG,
  font, or audio bytes changed. Save schema remains 10.
- Full systems/world/story documents retain their substantive specifications,
  formulas, historical qualifications, and implemented-versus-planned boundary.
  Actual historical prompt bodies and original licenses were not rewritten.

Evidence: ignored `build/current/english-json-invariants.json`.

## Real CPU-Rendered UI Acceptance

Environment: original host, UID 1000, Godot
`4.7.2.stable.official.ed1daf0bf`, authenticated owned Xvfb `:147`, Mesa
26.0.8 / llvmpipe LLVM 21.1.8, OpenGL 4.5. No NVIDIA offload or hardware
performance claim. The owned display is stopped after acceptance.

Two initial production-route runs at 1280x720 and 1600x900 exposed real
English-expansion defects despite successful headless checks:

- Equipped badges wrapped below small inventory tiles.
- Inscribe/Rewrite split into fragments in narrow Forge buttons.
- Compact HUD status, target/range, and empty-skill states were hard-clipped.
- Point pluralization and lower-is-better guidance were incorrect/redundant.
- Contract build-details borders and pager labels needed bounded fit fixes.

Corrections retain the established visual style, font sizes, stable IDs,
navigation, economy, and unlock rules. Concise badges/states/pagers preserve
full explanations in tooltips. Clearing is not mislabeled as cleared, and
empty combat slots remain distinct from quest-locked slots.

### Successful Rerenders

Evidence root: ignored `build/current/english-visual-20261024/`.
The directory tag is an artifact name; actual log timestamps identify the run.

| Check | Result |
| --- | --- |
| Fresh core routes, 1280x720 | exit 0; 26 production PNGs |
| Fresh core routes, 1600x900 | exit 0; 26 production PNGs |
| Display-backed facility probe | PASS, exit 0; 5 PNGs |
| Final affected Forge/pager delta, 1280x720 | exit 0; 8 PNGs |
| Final affected Forge/pager delta, 1600x900 | exit 0; 8 PNGs |

Core rerenders cover title, tutorial, Hearthside, Leia dialogue, all four
Journal tabs, character, loadout, Forge, training/proxy, a training trial,
contract/detail/confirmation, actual combat HUD, abandon, and settlement.
The final affected-only rerenders follow the last pager/singular-token/Roman
tier copy change; they are not falsely described as another full-route run.
Source fingerprints remain unchanged during each capture batch.

Unlocked Forge setup uses the existing production auto-smoke/App commands,
salvages a legitimate non-equipped fixture item for its token, then forecasts,
selects, focuses Confirm, and cancels. This is explicit state-fixture
acceptance, not a manual quest playthrough or a committed Forge transaction.

Parent-reviewed examples:

- `final-1280/12_loadout.png`
- `final-1280/14_forge.png`
- `final-1280/24_combat_hud.png`
- `final-delta-1280/03_selected_future_commit_copy.png`

`acceptance.json` indexes routes, exits, renderer logs, screenshots, and fixture
limits. Live Control scans found no Han. Hover tooltip strings were checked;
popup geometry and every positive token count were not separately captured.
The route harnesses retain shutdown warnings for 31 ObjectDB instances and
10 resources: successful exits are not a memory-soak certification.

## Full Frozen Host Gate

The definitive gate is `./scripts/container_build.sh`, not the pre-English
foundation result. Delivery evidence is
`build/current/english-container-build-release.{log,exit,pid,pgid}`.
**PASS, explicit exit 0.** UID 1000, PID/PGID 4006124, start
2026-10-22T12:15:51-07:00, finish 12:24:04-07:00. The process group is empty.
Frozen source/configuration fingerprints match before and after:
`2a5e20862fb5dbb43da4de817385b3a1af6c799c89f0727e8e380890588ecfd9`.

| Gate | Evidence |
| --- | --- |
| English guard | 697 files; four pinned originals |
| Python policy/preflight tests | 7 + 10 pass |
| Story reading flow | `STORY_READING_FLOW PASS` |
| Workbench and room integration | Both pass, including the regressions described below |
| Repeatable encounter matrix | 600 rooms, seeds 0..99, 600 victories, 33,894 ticks |
| GDScript runtime-error gate | Exit 0; no `SCRIPT ERROR:` lines |
| Linux and Windows exports | Fresh output from matching Godot 4.7.2 templates |
| Native Linux empty-directory launch | `SCENE_SMOKE_PASS`, exit 0 |
| Overall wrapper | `host build flow passed`; explicit exit file contains 0 |

Game export hashes:

| Platform | Bytes | SHA256 |
| --- | ---: | --- |
| Linux x86-64 | 123996232 | `cdf6dc5ae52f1e153830dc37f9a3edab4059c720a6c6fb61a5ebe6be612307b7` |
| Windows x86-64 | 159604504 | `135e8afc1fd1002f4afb28fe2407cf6887f70c9c1bf1fba0d8d672d5c8601490` |

These are original-host game exports, distinct from the tiny devbox fixture
artifacts. Windows export is not a claim of native Windows execution.

Earlier attempts are preserved honestly:

- `english-container-build-final`: exit 1 before Godot tests, caused by the
  Python fixture inheriting the real engine path while mocking its expected
  hash. The fixture now isolates that environment variable.
- `english-container-build-verified`: deliberately stopped with exit 143
  before edits, to correct Windows mocking of absent `os.geteuid` and prevent
  Windows line-ending conversion of pinned originals. It is not a passed gate.
- `english-container-build-delivery`: exit 1 at the original first-screen
  workbench assertions. A nonempty Forge snapshot without optional `ok` received
  both a generic and compact mark. The renderer now matches the builder's
  nonempty-data branch; assertions remain intact. Added missing/true/false `ok`
  and empty-data regressions pass, as do workbench and facility suites.
- `english-container-build-accepted`: exit 1 on the integration test's old
  `Room 2 / 2` visible-text expectation. The compact face intentionally uses
  `Room 2/2`; its full tooltip retains spaced metadata. The corrected test
  requires both surfaces and the clear-foes objective, and passes independently.

The fixes pass all 10 preflight and 7 English-policy tests under the actual
project environment. `.gitattributes` preserves the four original byte streams.
The 10 preflight tests also pass with the POSIX-only `os.geteuid` attribute
removed, exercising the corrected portable mock. This is not native Windows
game execution.

## Local Release Verification

Runtime/content changes are committed as `fc338029b8d5`. After that clean
commit, the fresh game exports were packaged into the new isolated, ignored
root `build/current/english-release-check.eeQ5Ul`, build ID
`20261022-192931-fc338029b8d5`.

The required local sequence passes: `release.sh package`, `index`, `site`,
`verify --deep`, `deploy/tailscale/validate.sh`, and
`stage_release_page.sh --check`. The index step is required before site
generation. Both download checksums match the game export hashes above.
Evidence: `build/current/english-release-verification.log` and the isolated
root's `index.json`, build metadata, and `SHA256SUMS`.

No `prune`, live `build/releases/` update, server, Tailscale exposure, remote
upload, or deployment occurred. The existing release history remains untouched.

## Devbox Facilities and Boundaries

See `docs/DEVBOX_READINESS.md` for exact paths, versions, evidence, and limits.

- Approved resources are now 8 vCPU / 16 GiB RAM plus an 8 GiB swap allowance.
  PID/start time did not change. No container restart/recreation occurred.
- Official Godot and matching Linux/Windows templates are installed offline.
  The isolated CPU prefix includes Xvfb/Mesa and matched Python 3.14.4/Pillow
  12.1.1. PNG pixel round-trip and FreeType checks pass.
- A separate tiny target fixture imports, exports both platforms, and runs
  its native Linux ELF from an empty directory; all four checks exit 0.
  The game source was not copied. Windows PE validation is not native execution.
- Root remains read-only, UID is 1000, capabilities remain dropped,
  no-new-privileges remains enabled, IPC stays private, existing network/mount
  visibility is unchanged, and no ports are published.
- No proxy/DNS bypass, external download, new mount/device/network, host
  desktop socket, credential access, or existing-project modification occurred.
- Actual devbox GLX/Godot shader rendering remains **unverified**. The narrow
  exception for owned temporary X11 IPC is pending; the launcher refuses
  without approval. No target display or listener was started.

The operator must persist approved resource limits in the authoritative
container configuration before a later recreation. This task does not edit
the AF Infra control plane or silently weaken sandbox policy.

## Remaining Limits

The legacy sliced-town image baker still emits false/false cutaway/fade flags
while the shipped legacy manifest expects true/true. English migration keeps
the shipped flags and all image bytes; no complete legacy cold-generation pass
is claimed. See `tools/town_layers/README.md`.

Native Windows smoke/replay, actual devbox graphics, production town art,
signing/hosting/ACL review, and publication remain distinct operator or future
acceptance steps. No Tailscale exposure or deployment was performed here.
