# Make It Big Environment Workflow

This guide describes the native checkout at `/data/paseo-makeitbig/project` and the portable environment contract. Paseo manages agents and workspaces; project scripts validate source and produce deliverables. They do not create containers, install packages, or change host networking.

## Pinned Baseline

| Setting | Value |
| --- | --- |
| Current checkout | `/data/paseo-makeitbig/project` |
| Current host binary | `/data/paseo-makeitbig/bin/godot` |
| Godot | `4.7.2.stable.official.ed1daf0bf` |
| Linux binary SHA256 | `8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e` |
| Renderer | Godot GL Compatibility |
| Physics step | 30 Hz |
| Godot data | `$XDG_DATA_HOME`; defaults to `build/host-xdg/data` if not already set |
| Export templates | `$XDG_DATA_HOME/godot/export_templates/4.7.2.stable` |
| Test state | Ignored `build/test-state/` |
| Play session | Ignored `build/current/play-session/` |

Source `scripts/project_env.sh`, then use `mib_godot` or `"$GODOT_BIN"`. It resolves an explicit `GODOT_BIN`, the workspace's `../bin/godot`, PATH entries, and a legacy host fallback; it verifies the version and binary SHA256. The legacy paths are conveniences for this host, not requirements on a new machine.

## Standard Entry

```bash
cd /data/paseo-makeitbig/project
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

## Acceptance Gate

Run the complete test/export/empty-directory Linux smoke gate:

```bash
./scripts/container_build.sh
```

The `container_*` names are historical compatibility entry points. They run in the current environment without starting Docker. For bounded stages:

```bash
./scripts/container_test.sh
./scripts/container_export.sh
./scripts/container_smoke.sh
```

`--` separates engine options from game arguments. The exported executable accepts:

```bash
build/current/linux/make-it-big.x86_64 --headless -- --smoke
```

Templates must exactly match the editor version. Both Linux and Windows release templates are required for the dual-platform gate.

## Windowed Playtesting

For window input and captures, use the same Godot binary:

```bash
cd /data/paseo-makeitbig/project
source scripts/project_env.sh
"$GODOT_BIN" --editor --path .
```

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
./scripts/container_build.sh
```

Do not copy host-specific symlinks, `.godot/`, or test saves as installation substitutes. The new environment must regenerate imports and pass its own tests. See [devbox readiness](DEVBOX_READINESS.md) for the audited target and remaining provisioning work.

## Troubleshooting

- Missing Godot: set `GODOT_BIN` to the pinned executable or install it on PATH.
- Missing templates: check `version.txt` and both release template files in the configured directory.
- Preserve uncommitted work. Never use `git reset --hard`, `git clean`, or overwrite another session's checkout.
- Do not restart OCX, Paseo, or Jingwei from project scripts.

For each delivery, record the Godot version, `git rev-parse HEAD`, full test result, replay hash, exports, and empty-directory Linux smoke. Infrastructure health belongs in operator records, not game-test claims.
