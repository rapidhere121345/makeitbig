# Archive: Devbox Migration, Cleanup Gate and GitHub Release Migration (2026-10-22 to 2026-10-28)

These three reports were consolidated on 2026-11-01 because the work they
describe is complete and its still-valid procedures live elsewhere: the
environment contract in [HOST_WORKFLOW.md](../HOST_WORKFLOW.md) and the release
process in [RELEASE_WORKFLOW.md](../RELEASE_WORKFLOW.md). Each entry keeps the
date, scope, commands, results, hashes, versions and remaining limitations. They
are historical records, not the current checkout's test status. The full original
texts remain in Git at `228556b` under `docs/playtest/`; use
`git show 228556b:docs/playtest/<FILE>.md` when exact wording is needed. Ignored
`build/current/` and `build/archive/` evidence directories named below may no
longer exist.

## DEVBOX_MIGRATION_20261022

### Scope and transfer

- The operator authorized network/English rechecks followed by migration. The
  working checkout became `/data/claude/workspace/makeitbig` in the existing
  `example-devbox`; the original native checkout was left unchanged. No
  container, network, mount or public service was created.
- An offline Git bundle preserved complete reachable history (bundle SHA256
  `7ab5b5c35c45c8d45f68b281794eb2c34ba8966c6c6dceddef21771591f0c22c`). The clone
  started at `6d9c253dd57744a29f58e97fb2d01fce26d2dd68`; source tree
  `67721cf39c88ee305c4c821dddc7b15d1d5c02d9` matched the original. Origin was the
  workspace-local bundle, not an authenticated upstream, and no push occurred.
- Private Git configuration, credentials, production saves, old build output and
  `.godot` were not copied; imports and exports were generated anew.

### Network and English checks

- The HTTPS proxy resolved to the approved `code-egress`; GitHub was not bypassed.
  Positive checks: control-plane health HTTP 200; GitHub HTTPS HTTP 200, proxy
  CONNECT 200, TLS verification result 0. No direct-egress, prohibited-host,
  provider-key or credential probes were run; this is not a penetration audit.
- English audit: 697 files initially, zero unexpected Han findings; four pinned
  authentic license/provenance originals deliberately unchanged. After the entry
  documents were updated, 699 files and zero errors. Historical Git objects and
  user-generated text are not claimed Han-free.
- Sixteen production-route captures scanned at 1280x720 and 1600x900: zero
  unexpected Han nodes in visible control text and tooltips.

### Target full gate

- UID 1000, PID/PGID 216293, 2026-10-22T14:28:07-07:00 to 14:36:28-07:00,
  `build/current/migration-full-gate.exit` = 0. Fingerprint of tracked and
  untracked runtime inputs matched before/after:
  `8fefecbd859e54b1e90b9b016d5b2e34b70b30f2e342509359067fe35060b1f4`.
- English/policy/preflight checks, import, aggregate tests, story reading flow,
  workbench layout, room integration and the 600-room matrix (600 victories,
  seeds 0..99, 33,894 ticks) passed with no `SCRIPT ERROR:` lines; fresh
  Linux/Windows exports and the native Linux empty-directory launch passed,
  ending with `host build flow passed`.

| Artifact | Bytes | SHA256 |
| --- | ---: | --- |
| Linux x86-64 | 123996232 | `31ffd13facee596cc510eb73ffbdd03fa0560f76a4a2e7ee8319aead088dad07` |
| Windows x86-64 | 159604504 | `a46a9b13a75cd414c7ac291e53d046c1713ec615ad48296be8cf4a9e86081fa8` |

These were fresh target exports, not expected to be byte-identical to earlier
host exports. The Windows export is not native Windows execution.

### Graphical acceptance

- Godot 4.7.2 on Mesa llvmpipe (LLVM 21.1.8, OpenGL 4.5), owned private display
  `:199`, TCP disabled, private authentication.
- `migration-graphics.z_81c3sm/report.json`: exit 0 for title, tutorial,
  Hearthside, loadout, forge, training, proxy and contract at both resolutions
  (16 PNGs); requested and actual routes agreed. Setup used public capture
  fixtures, not a human quest playthrough or an unlocked Forge victory.
- The display-backed facility concept/detail probe also passed (five PNGs at
  1280x720 and 1024x576, frame and 18px-font audits clean). The owned Xvfb
  (PID/group 229179) was reaped with exit 0 and left no socket, lock or cookie.
- The earlier `migration-graphics.ej3x4kjs/` attempt is retained: the ad-hoc
  harness chose an authentication path the portable wrappers override. The
  harness was corrected to use the toolchain's private path; no access-control,
  proxy, permission or game-code workaround was added.

### Local release check and resources

- Ignored root `build/current/migration-release-check.QgN5c1`, build
  `20261022-214356-6d9c253dd577`: package/index/site generation, SHA256 deep
  verification, Tailscale static validation and staging `--check` passed (all
  since retired with the HTTP page). No releases were pruned or published.
- At the operator's request the devbox was raised from 8 CPU-equivalents and
  16 GiB RAM to 16 CPU-equivalents and 32 GiB RAM, keeping an 8 GiB swap
  allowance (`MemorySwap=40 GiB`); CPU is a quota, not exclusive cores. PID
  2198395 and start time `2026-10-22T04:28:00.728272595Z` were unchanged, the
  selected network/privilege/mount-count/IPC snapshots matched, Linux smoke
  repeated successfully, and the release-prerequisite audit reported `ready`.
- Sanitized audit records were kept under ignored
  `build/current/migration-audit/`. The operator was to sync the new working
  path and resource policy into the authoritative infrastructure configuration
  before any future recreation; no registry, Compose or unrelated-project edits
  were made.
- Remaining limits at the time: native Windows acceptance, long-run/performance
  certification, production town art, legacy cold-bake drift, signing/hosting/ACL
  review and publication.
- Superseded by: [HOST_WORKFLOW.md](../HOST_WORKFLOW.md) (environment contract),
  and the GitHub Release migration below.

## CLEANUP_LAUNCHER_ACCEPTANCE_20261022

- Scope: final full gate after the docs/tests cleanup and the `check.sh`
  `MIB_TEST_PYTHON` launcher fix. Validation-only: no tracked edits, commits,
  releases or infrastructure changes. Evidence in
  `build/current/validation-final-20261022T224827Z/`, HEAD
  `1d7e013537097c248afde886333eb0d285e350e5`, UID 1000, portable environment.
- Outcome: PASS.
  - `./scripts/check.sh` exit 0; `./scripts/container_build.sh` exit 0 (script
    since removed); test gate exit 0 with 0 `SCRIPT ERROR:` lines.
  - Matrix: `rooms=600 seeds=0..99 outcomes={"victory":600} ticks=33894`.
  - Replay golden
    `b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b` matched at
    30, 60 and 144 Hz and presentation-off 60 Hz.
  - Exports: Linux `make-it-big.x86_64` `6ee26db7...bc7f` (123996232 B), Windows
    `make-it-big.exe` `43f1e5aa...7f9` (159604504 B); Windows is export
    validation only.
  - Empty-directory Linux smoke: `SCENE_SMOKE_PASS framework=routes,builds,
    contract,persistence route=title`, then `host build flow passed`.
  - Freeze equality: identical 1204 files across `src/ content/
    art/production/p1/ project.godot export_presets.cfg scripts/ tests/`,
    manifest SHA256
    `edde10f058e639c45c8b7dadd8dd294a6498e64afd57a4af7b1b4c35f64f06b3`.
  - `ERROR:`/`WARNING:` lines matched the accepted baseline in kind and count
    (negative-fixture markers and Godot shutdown diagnostics only).
- Checklist closed in that pass: docs/tests cleanup (superseded reports removed,
  recoverable from `1d7e013`); `check.sh` launcher contract; modular greybox
  calibration (see the
  [town archive](ARCHIVE_TOWN_FADE_AND_WORLD_V02_20261022-23.md#town_modular_calibration_20261022));
  generation review of two raw Loadout base candidates (verbatim requests,
  matching source/copy hashes, provenance and corrected measurements, exit 0; the
  `docs/art-production/p1-town-modular-v01/` records were removed in `dc06c08`
  with the retired modular sample art and remain in Git history).
  Neither candidate was accepted for runtime: candidate 02 improved pixel
  density but drifted in composition, and both needed alpha/density/alignment
  correction.
- Limits: fixture-based validation, not a human playthrough; no native Windows
  execution; no performance or memory claims. The remaining modular asset
  package and town migration (plan steps 3-6) were pending.
- Superseded by: the world-expansion and town-order work in
  [WORLD_EXPANSION_20261025.md](WORLD_EXPANSION_20261025.md) and
  [TOWN_PERFORMANCE_LAYOUT_20261026.md](TOWN_PERFORMANCE_LAYOUT_20261026.md).

## GITHUB_RELEASE_MIGRATION_20261028

### Migration

- Scope: retire the HTTP release page and move downloads to versioned GitHub
  Releases. The operator confirmed the old server was already stopped; no host
  service, networking, container boundary or agent lifecycle operation was part
  of the work. Page templates, staging/server helpers and the host exposure
  example were removed. (The temporary compatibility validator was later removed
  too; the historical note lives in [RELEASE_WORKFLOW.md](../RELEASE_WORKFLOW.md).)
- New tags publish only after the full Linux gate and native Windows, ARM64 Mac
  and Intel Mac smoke/replay checks pass. The publisher uploads all six files to a
  draft, then publishes, so a failed upload cannot publish a partial release.
  Existing releases are never replaced or pruned; only the release job receives
  `contents: write` through the ephemeral Actions token.

### Local evidence

- Nine package/publisher regressions passed: all platforms, intact Mac ZIP, Linux
  execute mode, complete checksums, tampering, missing platforms, invalid tags,
  overwrite refusal, and safe draft/upload/publication sequencing.
- Real Linux/Windows/Mac packaging and checksum/archive verification ran in an
  isolated output root (`package.log`); shell/Python/Godot parsing, language
  policy and manifest freshness (`static.log`), workflow YAML parsing and the
  retired-page validator also passed.
- Frozen local gate (`RESULT.json`): PASS 2026-10-28T17:06:49Z to 17:20:18Z, all
  1482 frozen inputs unchanged; 216-step suite, 600 encounters, replay hashes,
  Linux/Windows exports and empty-directory Linux smoke passed; the existing
  Universal Mac ZIP passed real package verification. Archive-location docs were
  edited after the gate; runtime/content and packaging code were unchanged.

### Archive

- The old publication directory moved to
  `build/archive/release-online-20261028/`: all 29 files match the pre-move
  SHA256 manifest (`ARCHIVE.json`), the former root is absent, and binary history
  was preserved without pruning. Evidence is under ignored
  `build/current/github-release-migration-20261028/`.

### Tagged source and publication

- Tag `v0.1.0` at source commit `240cf7709e5f6fbcc8ef3bad53633c728ce6321f`.
  [Run 40734945204](https://github.com/rapidhere121345/makeitbig/actions/runs/40734945204)
  passed all six jobs (build, macOS package, Intel macOS smoke, ARM64 macOS smoke,
  Windows smoke, release publication). The hosted full gate passed 216 steps with
  zero failures. The Linux export and native Windows, ARM64 Mac and Intel Mac
  replays matched the pinned state hash
  `b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`. Both Mac
  jobs verified the Universal architectures and strict ad-hoc signature before
  startup and replay. Later branch commits recorded validation with `[skip ci]`.
- [Release v0.1.0](https://github.com/rapidhere121345/makeitbig/releases/tag/v0.1.0)
  was published at 2026-10-28T17:44:07Z as a stable release with all six assets
  (nonzero sizes and digests confirmed through the GitHub API; `PUBLISHED.json`
  retains the response, `ci-publisher.log` the verify/upload/publish sequence).

| Asset | Bytes | SHA256 |
| --- | ---: | --- |
| `build.json` | 732 | `8656e2fc7f9eb4e1cb6d4f6f0f297665423c86170f6bbac6ba6c4341b2b7f721` |
| `make-it-big-linux-x86_64.tar.gz` | 81155357 | `1c35d11b078cea118b75f005df29ea908167c3c9f956bb961e5dbb25194a46a6` |
| `make-it-big-macos-universal.zip` | 113314370 | `211f2c2e27c3e710d32d826d06322c3549620a4ae8569cfd931430afb04a7fea` |
| `make-it-big-windows-x86_64.zip` | 90866215 | `77e9c6a13928d10d565591f50cdd8190031a4626c6c33cecaf119109c5f69ffe` |
| `RELEASE_NOTES.md` | 881 | `757b9bbecba7992238097bf6a4c2a25d250ae73ed5999bfdcc2be7e38820ed6b` |
| `SHA256SUMS` | 453 | `b135300d9d47503b3efe34568290c983e97768c44617e49b0512d3525dd43214` |

- Limits: headless native checks do not establish GPU performance, audio or a new
  graphical play-through.
- Superseded by: [macOS support](MACOS_SUPPORT_20261028.md) and the current
  [release workflow](../RELEASE_WORKFLOW.md).

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
