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

The authorized devbox checkout uses the existing isolated CPU toolchain; run
everything through `scripts/with_env.sh`:

```bash
cd /data/claude/workspace/makeitbig
./scripts/with_env.sh ./scripts/build.sh
```

The [environment workflow](docs/HOST_WORKFLOW.md) is the single reference for the
pinned Godot version, writable directories, export templates, single-test
commands, and moving to a new host. Project scripts do not migrate files,
install system packages, or change the devbox's network and visibility
restrictions.

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

After the tutorial, combat tasks span two or three stages across five terrain battlefields: Snowbound Road, River Crossing, Ruined Village, Slate Quarry, and Colossus Approach. Riverbanks, quarry ledges, and ruined structures define movement and cover; campaign battles have no circular arena boundary. Repeatable tasks visit three different battlefields. After clearing a stage and collecting loot, choose **Next Stage** to advance or **Finish Task** after the final battle.

Hearthside's river is crossed at its two bridges; water, mountain edges and
scenery bases block movement. The Expedition Gate opens Contracts. In combat,
high ruins stop arrows while low stones and water block movement only. The task
action advances after stage clearance; leaving during combat abandons the task.

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

The project builds on Linux only. `./scripts/build.sh` is the delivery gate: it
runs `check.sh` (static checks), `test.sh` (complete test gate), `export.sh`
(Linux, Windows, and Universal macOS exports) and `smoke.sh` (empty-directory
Linux boot) in order and stops at the first failure. Stage details, timeouts and
logs are in the [environment workflow](docs/HOST_WORKFLOW.md); test discovery
and layout are in [tests/README.md](tests/README.md).

Exports land in `build/current/`: `linux/make-it-big.x86_64`,
`windows/make-it-big.exe` and `macos/make-it-big-macos-universal.zip` (Apple
Silicon ARM64 + Intel; see [macOS setup and validation](docs/MACOS.md)).
Cross-exporting does not establish native acceptance; CI provides native smoke
and replay checks.

## GitHub Releases

Download Windows, Linux, and Universal macOS builds from
[GitHub Releases](https://github.com/rapidhere121345/makeitbig/releases); each
release includes platform archives, `SHA256SUMS`, and source/build metadata.
Pushing a new `vX.Y.Z` tag publishes after the CI gates pass; see the
[release workflow](docs/RELEASE_WORKFLOW.md).

## Documentation

- [AGENTS.md](AGENTS.md): scope, sources of truth, and collaboration rules.
- [docs/](docs/README.md): systems, narrative, environment workflow, and art production.
- [Graphical validation](docs/GRAPHICAL_VALIDATION.md): windowed and headless acceptance.
- [Release workflow](docs/RELEASE_WORKFLOW.md): GitHub Releases, version tags, archives, and checksums.
- [Environment workflow](docs/HOST_WORKFLOW.md): pinned toolchain, build gate stages, and moving to a new host.
- [Source language and localization](docs/LANGUAGE_POLICY.md): vocabulary, compatibility, and pinned authentic originals.
- [content/](content/) and `src/`: implemented content and runtime behavior.

Save schema is 10. Production saves use Godot's `user://saves`; playtest tools use separate directories. Design documents describe targets, not promises of implemented features. Code, content, and tests determine actual behavior.
