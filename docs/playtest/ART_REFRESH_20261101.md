# Art consistency refresh — 2026-11-01

## Objective and scope

Replace demonstrably superseded material identities, starting with the title,
without changing gameplay. Design anchor:
`docs/art-production/generated-world-v02/perspective-20261024/DIRECTION.md`:
angled dark timber/stone, controlled pixel clusters, restrained amber/cyan, and
pixel density compatible with the current Ranger.

| Surface | Before | Replacement |
| --- | --- | --- |
| Title | Pale round tower, snow tent and floating masonry from the older concept family | New text-free road/forge/watchtower plate, packed to the existing 640x360 contract; stronger flat menu scrim; fire/smoke sockets repositioned |
| Facility marks | Superseded `hamlet_style_r13` building silhouettes | The actual board, east loadout, west forge, training dummy and proxy textures used by current town; fitted to existing mark canvases |
| Epilogue | Old tower/pipe/tent plate and detached repair-steam socket | Runtime composition of current town ground, timber forge and brazier; existing resident animations; Ranger on clear ground |

The title was generated using the built-in image generator. Its exact prompt,
original source, packing recipe and hashes are under
`docs/art-production/title-world-20261101/` and
`art/production/p1/title_world_v03/`. Rebuilding into a fresh ignored directory
produced byte-identical background PNG and atlas JSON.

The epilogue composition is documented in
`docs/art-production/hearth-return-20261101/README.md`. No new raster copies
were needed for facility marks or the epilogue.

## Cleanup

Removed the four files in the unused `title_concept_v02` runtime package and
the eight files in the unused `hearth_return_v01` runtime package, after scanning
runtime code, authored content, tests, scripts and tools for consumers. Original
sources, prompts, recipes and retired manifests remain under their historical
art-production directories. Shared `title_life_v01`, legacy-named actor atlases,
licenses and build dependencies remain intact. Corrected outdated source comments
in the tutorial, loadout preview and facility reader.

## Evidence

Raw evidence: `build/current/art-refresh-20261101/` (ignored).

- `title-final.png`: rendered new backdrop, readable copy/buttons, small fire and
  chimney effects positioned on the new art.
- `forge.png`: current timber forge mark inside the existing UI allocation.
- `ending-layout-fixture.png`: current-world illustration with resident actors
  and Ranger ground contact. This is an isolated mounted layout fixture, **not**
  a newly earned Colossus victory or persistence replay.
- Title and facility captures use the production route capture harness.
- Display: private authenticated Xvfb, TCP disabled, Mesa llvmpipe, Dummy audio.
  These are graphical correctness checks, not hardware performance/audio claims.
- Targeted title, facility-art, facility-layout, facility-screen, contract-screen,
  ending-screen and headless atmosphere checks passed. Existing shutdown leak
  diagnostics remain in the atmosphere log.

## Frozen delivery gate

Runtime/content/test/script/production-art fingerprint:
`060cc76532dd64469cdbc881889816724aa114b8ac625989f3821694bb5004da`.

- `scripts/build.sh`: exit 0, **221 passed / 0 failed**, 600-room matrix passed,
  replay hashes matched at 30/60/144 Hz and presentation-off 60 Hz.
- Linux, Windows, and Universal macOS exports completed; Linux empty-directory
  smoke passed. Native Windows/macOS execution remains unverified locally.
- Local `v0.1.1-art.1` archives packaged and verified; retired-page compatibility
  validation passed. Existing release archives were not overwritten.
- Exported Linux executable launched from an empty directory on the private
  display and produced `export-title.png` with `CAPTURE_PASS`; reviewed the image
  and log. No script or shader errors. Software-driver V-Sync warning retained.
- Frozen source fingerprint matched after the gate; `git diff --check` passed.

The first gate was deliberately stopped when a broad comment replacement was
found to have changed the tutorial target texture path. Restored the original
`legacy_enemies.png` path, passed tutorial-screen and story-integration checks,
then restarted the full gate from the beginning. Interrupted logs are retained;
only `final-build.log` and the successful exit records support acceptance.

Local packages: `build/releases/v0.1.1-art.1/`. Linux archive SHA-256:
`90bfe25d54fe950bce7bbcefdbf9fb15e21582b9b70d96c05f73a208d4dac6a1`.
All package hashes are in that directory's `SHA256SUMS`.

No public release, tag or commit was made. This is an uncommitted working-tree
candidate incorporating prior authorized work. Existing shutdown resource
warnings remain; audio and hardware GPU performance were not evaluated.
