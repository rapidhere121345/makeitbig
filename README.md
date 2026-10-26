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

The authorized devbox checkout uses the existing isolated CPU toolchain:

```bash
cd /data/claude/workspace/makeitbig
source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
source scripts/project_env.sh
./scripts/container_build.sh
```

See the [environment workflow](docs/HOST_WORKFLOW.md) for the pinned version,
writable directories, export templates, and staged commands. The original
`/data/paseo-makeitbig/project` checkout is retained for rollback. Preparing
another environment? Check [devbox readiness](docs/DEVBOX_READINESS.md) first.
Project scripts do not migrate files, install system packages, or change the
devbox's network and visibility restrictions.

## Controls

| Action | Input |
| --- | --- |
| Move | WASD / arrow keys |
| Shoot | Space for assisted aim; left-click to target an enemy |
| Dodge | Shift / Ctrl / right mouse button |
| Skills | Q: Hunter's Mark; E: Dash (requires unlock) |
| Hearthside | E / Space near a facility or the Expedition Gate to enter; E near a resident to talk; C: character; J: journal |
| Reading and menus | E / Enter: advance; Esc: back; F1: settings; Tab in combat: report |

Choose Manual or Auto when departing; the mode stays fixed for that contract. Loot enters the backpack before you compare and equip it. Forge previews are free; only confirming the forge spends Law Tokens.

Hearthside's river is crossed at its two bridges; water, mountain edges and
scenery bases block movement. The Expedition Gate opens Contracts. In combat,
cleared wards are visual feedback: room settlement and the Leave action control
departure.

Hearthside’s Forge and Loadout face their roads, bridge landings are kept clear,
and the eastern wall replaces the crowded pine boundary. See the
[town performance and layout acceptance](docs/playtest/TOWN_PERFORMANCE_LAYOUT_20261026.md)
for measured CPU improvements and validation limits.

Live characters have a one-pixel silhouette outline, a light rim, and raised
brightness: warm gold for the Ranger, teal for residents, and coral for enemies.
Contact shadows anchor actors and scenery to the ground and bridge decks.
Lamps and hearths cast local pools of light, with restrained illumination on
nearby sprites and combat warnings drawn above the ground effects.

F1 opens settings. Choose **English** or **Simplified Chinese**, change menu scale
(100%, 115%, 125%), or select windowed/fullscreen display settings. Language changes
apply immediately, including during a paused battle, and preferences survive restart.
Presets include 16:10 laptops, 1440p, ultrawide, 4K, and 5K when they fit the display.
Fullscreen uses the desktop resolution; the game view keeps its 16:9 proportions.

**Balanced** rendering is the default: at 4K the game uses a 1080p offscreen target
with uniform integer enlargement. **Native Resolution** keeps the finest game text;
**Performance** uses a smaller target. Reading panels always render at native
resolution, and paused game surfaces are cached while settings are open. Menu scale
increases reading size where the window has enough space for the two-column pages.

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

The current publish URL, supplied by the operator, is <http://192.0.2.10:18080/>.

For Tailscale access, validate `build/releases/` with `./deploy/tailscale/stage_release_page.sh`, then have the host operator configure exposure as described in the [Tailscale guide](deploy/tailscale/README.md).

## Documentation

- [AGENTS.md](AGENTS.md): scope, sources of truth, and collaboration rules.
- [docs/](docs/README.md): systems, narrative, environment workflow, and art production.
- [Graphical validation](docs/GRAPHICAL_VALIDATION.md): windowed and headless acceptance.
- [Release workflow](docs/RELEASE_WORKFLOW.md): release pages, retention, and exposure.
- [Devbox readiness](docs/DEVBOX_READINESS.md): target prerequisites and actual audit status.
- [Source language and localization](docs/LANGUAGE_POLICY.md): vocabulary, compatibility, and pinned authentic originals.
- [content/](content/) and `src/`: implemented content and runtime behavior.

Save schema is 10. Production saves use Godot's `user://saves`; playtest tools use separate directories. Design documents describe targets, not promises of implemented features. Code, content, and tests determine actual behavior.

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
