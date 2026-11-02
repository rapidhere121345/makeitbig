# Tests

Headless regression suites for the Godot project. `scripts/test.sh` is the only
gate; this page explains how it finds tests and where new ones belong.

## Discovery and pass criterion

- `scripts/test.sh` runs every `tests/**/test_*.gd` whose `extends` chain ends
  in `SceneTree` as `godot --headless --path . --script res://<file>`. A test may
  extend another test (`res://tests/...`) and still counts.
- A `test_*.gd` that is not a SceneTree script (`extends RefCounted` with
  `run() -> Array[String]`) must be preloaded by `tests/run_all.gd`, which runs
  them as one batch. Otherwise the gate fails it as an orphan.
- Python tests, art-pipeline verifiers (Python and Godot-side), and the replay
  hash checks run in the same gate.
- A test passes only with exit 0 and no output line starting with
  `SCRIPT ERROR:` (a runtime error can abort a test early while Godot still
  exits 0, so the gate scans the log for it).
- Files not named `test_*.gd` (fixtures, fakes, `run_all.gd`) are never
  discovered; the gate invokes `run_game_flow_smoke.gd` explicitly.

## Layout

- `tests/` (top level): most suites, one `test_<subject>.gd` per subject, plus
  `run_all.gd` and `run_game_flow_smoke.gd`.
- `tests/unit/`: small, self-contained units (core helpers, UI kit, display and
  style policies, view models).
- `tests/application/`: application-layer suites (profile, sessions, forge,
  equipment, campaign, result and drop settlement).
- `tests/simulation/`: fakes and the world factory for the simulation kernel
  suites (not tests themselves).
- `tests/helpers/`: shared test support: `assert.gd`, state-suite and domain
  fixtures, spatial and world-asset manifest fixtures, callable ports, scene
  expectations.
- `tests/python/`: Python tests for repo tooling (English check, devbox
  preflight, play session, macOS export, release platforms, battleground
  authoring). The gate runs every `tests/python/test_*.py`.

Name a suite after its subject, not after an art or review round (`_r13`,
`_r14`); names that match a runtime art pack such as `ui_style_r13` are fine.

## Where new tests go

Put a new test next to the code layer it covers: `tests/unit/` for isolated
units, `tests/application/` for application services, the top level for
cross-system or scene-level suites. Name it `test_*.gd` so it is discovered, and
put reusable fixtures in `tests/helpers/` (or the matching fixture directory).
After adding a `.gd` file, run `godot --headless --path . --import` and commit
the `.uid`.

## Assert helper

`tests/helpers/assert.gd` holds `Assert.expect(condition, message, failures)`,
which appends `message` to `failures` when `condition` is false.

```gdscript
const Assert := preload("res://tests/helpers/assert.gd")
Assert.expect(count == 3, "three entries", failures)  # failures: Array[String]
```

New tests call it directly. Older suites keep a one-line `_expect` wrapper that
forwards to it, so their many call sites did not change. Suites whose helper
also counts checks, prefixes `FAIL: `, or prints keep their own local `_expect`.

## Running tests

Through `./scripts/with_env.sh` (portable environment; UID 1000, never root):

```bash
# one test (exit 0 and no "SCRIPT ERROR:" line means pass)
timeout 600 ./scripts/with_env.sh godot --headless --path . --script res://tests/unit/test_collections.gd
# full gate (about 20-25 minutes locally); must end with "test gate passed"
./scripts/with_env.sh ./scripts/test.sh
```

## Replay golden hash

The gate runs the deterministic `--auto-smoke` replay at 30, 60, and 144 Hz and
with presentation off, and every run must produce the golden hash
`EXPECTED_HASH` in `scripts/test.sh` (currently `c7353c04...`). Test-only
changes must never change it. Update it only in a commit that intentionally
changes simulation behavior, and say so in the message; never to make a failing
gate pass.
