# Make It Big

Make It Big is a pixel-art dark-fantasy loot demo built with Godot 4.7.2. Play a bow-wielding Wanderer, prepare equipment and builds in Hearthside, explore the old roads of the frozen wastes, and challenge the Threshold Colossus.

The playable scope is the Ranger's first chapter: tutorial, Hearthside exploration, five residents, chapter contracts, equipment comparison, talents, Training, Law Token forging, Manual/Auto combat, and the return to town after the Colossus. Later chapters, two additional classes, and higher-tier endgame systems remain plans.

## Run

With Godot installed:

```bash
git clone https://github.com/rapidhere121345/makeitbig.git
cd makeitbig
godot --path .
```

The current native host checkout uses:

```bash
cd /data/paseo-makeitbig/project
source scripts/project_env.sh
./scripts/container_build.sh
```

See the [environment workflow](docs/HOST_WORKFLOW.md) for the pinned version, writable directories, export templates, and staged commands. Preparing a different host or devbox? Check [devbox readiness](docs/DEVBOX_READINESS.md) first. Nothing automatically migrates the project or installs system packages.

## Controls

| Action | Input |
| --- | --- |
| Move | WASD / arrow keys |
| Shoot | Space for assisted aim; left-click to target an enemy |
| Dodge | Shift / Ctrl / right mouse button |
| Skills | Q: Hunter's Mark; E: Dash (requires unlock) |
| Hearthside | E / Space near a facility to enter; E near a resident to talk; C: character; J: journal |
| Reading and menus | E / Enter: advance; Esc: back; F1: settings; Tab in combat: report |

Choose Manual or Auto when departing; the mode stays fixed for that contract. Loot enters the backpack before you compare and equip it. Forge previews are free; only confirming the forge spends Law Tokens.

## Test and Export

The full gate runs tests, Linux/Windows exports, and smoke-tests the Linux release executable from an empty directory:

```bash
./scripts/container_test.sh
./scripts/container_export.sh
./scripts/container_smoke.sh
```

With the Godot environment already configured, the underlying commands are:

```bash
./scripts/test.sh
./scripts/export_all.sh
```

The Linux executable is `build/current/linux/make-it-big.x86_64`; the Windows executable is `build/current/windows/make-it-big.exe`. Exporting Windows is not native Windows acceptance. Public CI provides Windows smoke and cross-platform replay checks.

## Release Page

After a passing build, generate and validate the static release page:

```bash
./scripts/release.sh all
./scripts/release.sh verify
```

The ignored `build/releases/` directory can be served as a static site. Each build includes Windows/Linux downloads, `build.json`, and `SHA256SUMS`. `all` retains the latest 20 valid builds and can delete older ones; review and approve retention before running it against existing release history. See [the release workflow](docs/RELEASE_WORKFLOW.md) for templates and naming.

The existing host's tailnet-only page is <https://example-runtime.tail99c4e8.ts.net:8448>. This is not a devbox publication endpoint or a guarantee of current availability.

For Tailscale access, validate `build/releases/` with `./deploy/tailscale/stage_release_page.sh`, then have the host operator configure exposure as described in the [Tailscale guide](deploy/tailscale/README.md).

## Documentation

- [AGENTS.md](AGENTS.md): scope, sources of truth, and collaboration rules.
- [docs/](docs/README.md): systems, narrative, environment workflow, and art production.
- [Graphical validation](docs/GRAPHICAL_VALIDATION.md): windowed and headless acceptance.
- [Release workflow](docs/RELEASE_WORKFLOW.md): release pages, retention, and exposure.
- [Devbox readiness](docs/DEVBOX_READINESS.md): target prerequisites and actual audit status.
- [English-only policy](docs/ENGLISH_ONLY.md): vocabulary, compatibility, and pinned authentic originals.
- [content/](content/) and `src/`: implemented content and runtime behavior.

Save schema is 10. Production saves use Godot's `user://saves`; playtest tools use separate directories. Design documents describe targets, not promises of implemented features. Code, content, and tests determine actual behavior.

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
