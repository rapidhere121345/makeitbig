# Make It Big Environment Workflow

This guide describes the authorized devbox checkout at
`/data/claude/workspace/makeitbig` and the portable environment contract.
The original `/data/paseo-makeitbig/project` remains a rollback copy.
Paseo manages agents and workspaces; project scripts validate source and produce
deliverables. They do not create containers, install packages, or change networking.

## Pinned Baseline

| Setting | Value |
| --- | --- |
| Current checkout | `/data/claude/workspace/makeitbig` |
| Scoped launcher | `/data/claude/workspace/.tools/make-it-big/portable-cpu/bin/mib-godot` |
| Official engine | `/data/claude/workspace/.tools/make-it-big/godot-4.7.2/godot` |
| Godot | `4.7.2.stable.official.ed1daf0bf` |
| Linux binary SHA256 | `8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e` |
| Renderer | Godot GL Compatibility, CPU Mesa llvmpipe |
| Physics step | 30 Hz |
| Godot data | `$XDG_DATA_HOME`; defaults to `build/host-xdg/data` if not already set |
| Export templates | `$XDG_DATA_HOME/godot/export_templates/4.7.2.stable` |
| Test state | Ignored `build/test-state/` |
| Play session | Ignored `build/current/play-session/` |

Source the isolated prefix's `env.sh`, then `scripts/project_env.sh`, and use
`mib_godot` or `"$GODOT_BIN"`. `scripts/with_env.sh <command...>` does both for a
single command (it sources the prefix's `env.sh` when it exists, or the file named
by `MIB_PORTABLE_ENV`), so agents can run one test without `source`:

```bash
./scripts/with_env.sh godot --headless --path . --script res://tests/test_x.gd
./scripts/with_env.sh ./scripts/check.sh
```

The prefix chooses its matching loader and CPU
libraries without changing global library paths. The project verifies the
official engine's version and SHA256. Native-host fallbacks remain portable
compatibility options, not the devbox's installation method.

## Standard Entry

```bash
cd /data/claude/workspace/makeitbig
source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
source scripts/project_env.sh
printf '%s\n' "$GODOT_BIN"
mib_godot --version
```

`project_env.sh` verifies Godot, links an existing template fallback when available, creates writable state directories, and defines `mib_godot` and `mib_require_export_templates`. It does not download anything. Do not run tests as root or commit `.godot/`, `build/`, or `user://` data.

For an isolated runtime launcher, set `GODOT_BIN` to the launcher and
`MIB_GODOT_BINARY_PATH` to the actual official engine. Version probing goes
through the launcher, while SHA256 verification reads the raw engine. This
supports the devbox's scoped matching-loader wrapper without weakening the
engine pin or modifying the official executable.

## Python Launcher Contract

The portable prefix's `python3` is a wrapper that starts its Python through
the prefix's matching loader; the raw interpreter binary cannot start under
the host's older glibc, so `sys.executable` is not directly spawnable there.
`project_env.sh`'s `mib_resolve_test_python` (used by `check.sh`, `test.sh` and
`play_session_window.sh`) resolves the working launcher (`command -v python3`) once
and exports it as `MIB_TEST_PYTHON`, and the subprocess test harness re-enters
Python through that launcher. `MIB_TEST_PYTHON` may be set deliberately to
check with a different interpreter; a value that is not an executable file
fails the check instead of being substituted.

Running that harness directly under portable Python still needs the explicit
launcher, for example:

```bash
MIB_TEST_PYTHON="$MIB_CPU_PREFIX/bin/python3" \
  python3 tests/python/test_play_session_tool.py
```

Without `MIB_TEST_PYTHON` the harness uses `sys.executable`, which is correct
for normal/system Python. Do not work around a launcher mismatch by exporting
global library paths or installing the portable runtime system-wide.

## Acceptance Gate

The project builds on Linux only. Run the complete check, test, export, and
empty-directory Linux smoke gate:

```bash
./scripts/with_env.sh ./scripts/build.sh
```

`build.sh` runs these stages in order and stops at the first failure; each also runs
on its own:

```bash
./scripts/check.sh    # bash -n, Python syntax, check_english, world_manifest --check, bounded Godot --check-only
./scripts/test.sh     # complete test gate
./scripts/export.sh   # template check, Linux and Windows exports
./scripts/smoke.sh    # exported Linux binary from an empty directory
```

None of them start Docker or touch networking. `test.sh` runs Python tests
(`tests/python/`, the art-pipeline suites and read-only verifiers), the repository
policy checks, `godot --import`, every discovered Godot test, `tests/run_game_flow_smoke.gd`, and the
30/60/144 Hz and presentation-off replay hash checks. Godot tests are discovered:
each `tests/**/test_*.gd` that extends `SceneTree` (directly or through another
`res://tests/` script) runs with `--headless --script`; `run()`-style suites are
aggregated by `tests/run_all.gd`, and a `test_*.gd` that is neither fails as an
orphan. `SKIP_TESTS` in `scripts/test.sh` lists the display-only tests. Every test
runs even after a failure; the summary names the failures and the exit status is
non-zero. The gate has a total timeout (`MIB_TEST_TIMEOUT_SEC`, default 1800), a
per-test timeout (`MIB_TEST_CASE_TIMEOUT_SEC`, default 600), a log
(`MIB_TEST_LOG`, default `build/current/test.log`), and fails if any output line
starts with `SCRIPT ERROR:`.

`--` separates engine options from game arguments. The exported executable accepts:

```bash
build/current/linux/make-it-big.x86_64 --headless -- --smoke
```

Templates must exactly match the editor version. Both Linux and Windows release templates are required for the dual-platform gate.

## Windowed Playtesting

For window input and captures, use the same Godot binary:

```bash
cd /data/claude/workspace/makeitbig
source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
source scripts/project_env.sh
"$GODOT_BIN" --editor --path .
```

The editor command requires an already approved, authenticated private display.
Do not use the host desktop or enable unauthenticated/TCP X11 access. Stop owned
display processes and remove only their own IPC/authentication artifacts.

Playtest tools share the checkout and `build/current/play-session/`. Record the actual display and renderer for X11/Xvfb runs. A virtual display is not a physical desktop session. See [graphical validation](GRAPHICAL_VALIDATION.md).

## Moving to Another Environment

After the operator moves the checkout, run the read-only prerequisite checker before sourcing the environment:

```bash
python3 scripts/devbox_preflight.py --profile all --json
```

Configure portable paths explicitly when needed:

```bash
export GODOT_BIN="/your/tools/godot"
export MIB_GODOT_TEMPLATE_FALLBACK="/your/templates/4.7.2.stable"
source scripts/project_env.sh
./scripts/build.sh
```

Do not copy host-specific symlinks, `.godot/`, or test saves as installation substitutes. The new environment must regenerate imports and pass its own tests. See [devbox readiness](DEVBOX_READINESS.md) for current acceptance and separate follow-up work.

## Troubleshooting

- Missing Godot: set `GODOT_BIN` to the pinned executable or install it on PATH.
- Missing templates: check `version.txt` and both release template files in the configured directory.
- Preserve uncommitted work. Never use `git reset --hard`, `git clean`, or overwrite another session's checkout.
- Do not restart OCX, Paseo, or Jingwei from project scripts.

For each delivery, record the Godot version, `git rev-parse HEAD`, full test result, replay hash, exports, and empty-directory Linux smoke. Infrastructure health belongs in operator records, not game-test claims.
