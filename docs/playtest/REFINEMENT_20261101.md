# Battlefield completion and refinement — 2026-11-01

This acceptance covers the existing uncommitted battlefield work plus the
refinements below. Earlier source/content changes were preserved. No commit,
tag, or release was created.

## Changes

- Terrain authoring compiles fresh field definitions in memory, reads shared
  structure recipes once, and validates reviewed plate hashes with explicit
  exceptions that remain active under Python `-O`. Repeated compilation leaves
  the placement definitions unchanged and reproduces all five native scenes
  byte for byte.
- Battlefield presentation rejects missing catalogs, missing room assets, and
  scenes belonging to another layout. Failed loads clear both layout and
  texture caches; a subsequent valid load recovers. Regression coverage checks
  wrong-layout reloads, cleared caches, recovery, and null catalogs.
- Auto retreat now checks static terrain when choosing its local direction.
  Previously, approach routed around terrain but retreat checked only the
  outer boundary and could repeatedly command movement into a blocker. Tests
  cover circular and polygon obstacles, deterministic decisions, reaching the
  safe distance band, and stopping when no clear retreat step exists. The
  actor motor remains movement authority. A read-only GLM 5.3 Flash review
  identified the retreat gap; it was independently reproduced before fixing.
- Preflight tests now use explicit disk-space fixtures instead of depending on
  the host temporary filesystem. A low-space fixture verifies rejection.

The 13 retained active battlefield source PNGs did not match the original
generation digests. Recompiling them reproduced all 14 runtime PNGs byte for
byte. Only active recipe/manifest source metadata was reconciled; source and
runtime image bytes and original provenance were preserved. The
[reconciliation record](../art-production/battlefields-20261028/SOURCE_RECONCILIATION_20261101.json)
records old/current source hashes and verified output hashes. The cause of the
source-byte drift remains unknown; output equivalence does not prove original
source-byte identity.

## Toolchain and reproduction

This session initially lacked the documented portable toolchain and old ignored
build evidence. The exact official Godot 4.7.2 executable and matching templates
were downloaded from `godotengine/godot-builds` into ignored `build/toolchain/`.
The engine matched the repository's pinned SHA-256. Pillow 12.1.1 was installed
in a project-local Python 3.12 virtual environment. No engine pin, container,
network boundary, system package, or service configuration was changed. Tests
ran as UID 1000.

With those local tools present, reproduce the successful gate using:

```bash
GODOT_BIN="$PWD/build/toolchain/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64" \
MIB_GODOT_TEMPLATE_FALLBACK="$PWD/build/toolchain/templates/4.7.2.stable" \
MIB_TEST_PYTHON="$PWD/build/toolchain/python/bin/python" \
PATH="$PWD/build/toolchain/python/bin:$PATH" \
./scripts/with_env.sh ./scripts/build.sh
```

## Frozen gate

The final build exited 0. Static checks, **221 test-gate checks with zero
failures**, Linux/Windows/Universal macOS exports, and the Linux empty-directory
smoke all passed. The macOS verifier confirmed ARM64 and x86_64, ad-hoc signing,
and Retina support. This closes the missing-macOS-template blocker recorded in
[the earlier battlefield report](BATTLEFIELDS_20261028.md).

The repeatable encounter matrix cleared **600/600 rooms**, using both templates
and seeds 0–99 (56,829 ticks). The 30, 60, and 144 Hz replays plus presentation-off
60 Hz all reached Ending with 1,849 boss ticks and 189 Auto ticks, retaining the
existing hash:

```text
c7353c04f81f9c497654a47fd4909fa20a72b49eff53cee3f7bde4d8d4b7df02
```

All 1,950 pinned input files remained unchanged through the final gate.
`build/current/refinement-delivery-inputs.json` has SHA-256
`2650a8e092d12fd63a2bc061409a90c3875960fc681106ced9f2c9f4f19ff328`.
The full raw log is `build/current/refinement-delivery-build.log`; the successful
test log is `build/current/test.log`. Earlier interrupted diagnostic runs are
retained separately and are not passing acceptance evidence.

| Output | Bytes | SHA-256 |
| --- | ---: | --- |
| `build/current/linux/make-it-big.x86_64` | 151,300,176 | `3a51d945351f52e86f567531f2d8dfc017904a93848af427fd5f8ca393f93373` |
| `build/current/windows/make-it-big.exe` | 186,908,448 | `b56d79e05af14525eb15bd758e7467dbb0554b9469411b84b7464fb3bb896c66` |
| `build/current/macos/make-it-big-macos-universal.zip` | 136,908,514 | `d004362b98b911c8aba69cf63ecbdf6c72e8ed0aa351373d1edaa7b4b4d4515e` |

## Limits

This run was headless. Native Windows/macOS execution, a new rendered human
playtest, audio, and long-run memory stability were not validated. Some tests
still print ObjectDB/resource cleanup warnings at shutdown; no GDScript runtime
errors occurred. Existing graphical acceptance remains historical evidence.
