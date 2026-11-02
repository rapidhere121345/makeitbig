# Chapter-one battleground acceptance — 2026-10-28

This work replaces campaign combat rooms with five terrain battlegrounds on
the working tree based on `97b63dcccd1c29ffeb6490d86fdbcf178fda9c92`.
Snowbound Road, River Crossing, Ruined Village, Slate Quarry, and Colossus
Approach each have a complete environment plate, native collision sources,
spawn sockets, and a baked spatial manifest. Rivers, cliff faces, and ruins
provide terrain constraints. Campaign movement no longer uses the legacy
circular or annular arena. The tutorial and legacy geometry fixtures remain.

Every regular fixed task has two stages; the Colossus task and repeatable
tasks have three. Repeatable tasks select three different battlegrounds.
The HUD and contract pages expose stage counts, **Next Stage**, and
**Finish Task**, including Simplified Chinese translations. Progression and
room settlement continue through the existing contract controller.

## Materials and reproducibility

The built-in image generation tool produced five complete environment plates,
five expanded backing plates, and three auxiliary material assets. Five
superseded initial plates are retained with their provenance. The active
runtime material pack lives in `art/production/p1/battlefields_v01/`; exact
prompts, source PNGs, reference hashes, source hashes, and transformations live
in [the production record](../art-production/battlefields-20261028/README.md).
The shared art compiler verifies the package byte for byte.

The reviewed 1024×640 floors remain opaque across their interiors. Their
1536×1024 generated backings fill the camera margins, with a 32-pixel join at
the floor edge. Camera overscan keeps the ranger visible near the map extent.
Collision contacts are authored separately against checksum-pinned floor
images in `environment_contacts.json` and `river_banks.json`; generated pixels
do not become collision authority. `author_battlegrounds.py --check` verifies
the native scene sources, and the battlefield regression compares each bake
with its stored manifest and catalog digests.

## Runtime checks

Auto receives validated static movement geometry and plans a deterministic
route around it. The actor motor retains movement authority. A new mounted
river regression places a stationary target on the other bank, requires Auto
to cross the bridge and cast, and compares repeated decisions. Proxy snapshot
validation rejects private binding identities and degenerate geometry.

The rendered camera and the lightweight input projection now select the same
battlefield mapping without requiring art to be loaded. Regressions compare
loaded and unloaded camera transforms at all five maps' edges. The production
controller test uses a visible, legally placed target and actual mouse input;
held Space, released input, pause, and pointer state transitions all pass.

## Rendered fixture review

The final fixture run used Godot 4.7.2, X11, authenticated private Xvfb with TCP
disabled, and Mesa llvmpipe software rendering. Its owned display and temporary
authentication were cleaned after exit. This is visual correctness evidence,
not hardware performance or a human playtest.

The final [29 captures and their verification](../../build/current/battlefield-work/visual/generated-outpaint-contacts/)
cover all five maps with and without entry overlays at 1280×720 and 1600×900,
the Chinese snowfield overlay, river and boss center views, river contact and
bridge movement, and all four snowfield edges. Exact capture inventory,
dimensions, and SHA-256 digests passed verification. The raw import/render logs
contain no script or shader errors, and the fixture exited 0. The ranger stays
fully visible at tested edges. The river bridge remained traversable from
`(640, 475.5625)` to `(885, 475.5625)`.

Some soft blending remains at the snowfield joins and a faint tonal transition
is visible at the far left of the Colossus water. These were accepted in the
captured views. Godot reported 226 ObjectDB instances and 10 resources remaining
at fixture shutdown; this review does not establish long-run memory stability.
Audio and native Windows/macOS execution were not reviewed here.

Rejected mirrored and flat-mist edge treatments, earlier art iterations, failed
replays, and interrupted gates remain under ignored
`build/current/battlefield-work/`. They are not passing acceptance evidence.

## Frozen regression and export results

`final-frozen-inputs.json` pins 1,951 runtime, content, test, tool, script,
production-art, and art-recipe files. Its SHA-256 is
`417724ee5e962eb713e72c2aec653ee4b635873cfd55e40eed1bbbbb9c9f0a20`.
Every pinned file remained unchanged through validation and export.

The prescribed `./scripts/with_env.sh ./scripts/build.sh` passed static checks
and the complete test gate: **220 passed, 0 failed**, with no GDScript runtime
errors. The production encounter matrix cleared **600/600** rooms across both
repeatable templates, seeds 0–99, and every authored layout/objective pair.
The 30, 60, and 144 Hz replays and the presentation-off 60 Hz replay all reached
Ending with the same state hash:
`c7353c04f81f9c497654a47fd4909fa20a72b49eff53cee3f7bde4d8d4b7df02`.
The golden intentionally changes with the new campaign stages, native terrain,
and Auto routing; each replay reports 1,849 boss ticks and 189 Auto ticks.

The all-target command then stopped because the local toolchain lacks
`4.7.2.stable/macos.zip`. Matching template download attempts through the
configured network failed during TLS negotiation. No engine version,
container boundary, or network configuration was changed. **The all-target
build is blocked at macOS export; it is not a full three-platform pass.**

With the same frozen inputs, `export.sh linux windows` and `smoke.sh` passed.
The exported Linux binary also ran the full replay from an empty temporary
directory with presentation enabled, reached Ending, and matched the golden.
The empty directory was removed after exit. Windows was exported but was not
executed natively. The pre-existing macOS ZIP is an older retained artifact
and is not a delivery from this change.

| Current output | Bytes | SHA-256 |
| --- | ---: | --- |
| `build/current/linux/make-it-big.x86_64` | 151,299,728 | `d5bd00757a190ab00731f4b9f76c60a73915d4316eb5f59e2fa87c455c93a45a` |
| `build/current/windows/make-it-big.exe` | 186,908,000 | `2fad289d16f13c9a23a1c395642c48758c73e54bfbba18d4fe38b17c72cfdbdb` |

Raw evidence: `final-build.log`, `final-desktop-export.log`,
`final-linux-smoke.log`, `exported-linux-replay.log`, the four hashes in
`build/test-state/`, and `DELIVERY.json` under the evidence root. The required
script syntax checks and final `git diff --check` passed. No release or commit
was created.
