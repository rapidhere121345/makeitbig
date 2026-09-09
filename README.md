# Make It Big

A low-cost pixel-action looter prototype about discovering hidden growth laws and turning ordinary RPG equipment into exponential and power-tower Builds.

## Current vertical slice

- Godot 4.7.2, GDScript, one project for Linux and Windows.
- Manual and autonomous contract modes are mutually exclusive.
- Ranger `Piercing Arrow` demonstrates the `R = 2p` branching threshold.
- Huge event counts use symbolic values instead of spawning astronomical objects.
- Diagnostic probabilities and equipped generation parameters are loaded from validated JSON content, not duplicated in scene code.
- Manual input and the white proxy feed one command stream into a fixed 30-tick authority simulation.
- Deterministic drops, visible Destiny Forge previews, explainable proxy refusals, and checksum-protected A/B saves are connected to the playable loop.

The base screen offers convergent (`p=.49`), critical (`p=.50`) and exponential (`p=.61`) diagnostic Builds. The exponential preset currently defeats the symbolic `10^12` boss in roughly 63 simulated seconds; the other presets still deal positive damage but are intentionally impractical. Manual contracts have a deterministic 35% chance to award one extra Fate Die. There is no offline progress.

## Design baseline

- Local: [`docs/GAME_DESIGN_FINAL_v1.0.md`](docs/GAME_DESIGN_FINAL_v1.0.md)
- Feishu: https://kcnyu4auynd5.feishu.cn/docx/XAwWdIXofoKb1Vx8hDtczQosnKd

The local Markdown keeps the content appendices as native tables; the Feishu version stores those same catalogs in one searchable monospaced appendix to stay under Feishu's document-block limit.

## Run

Open the repository root in Godot 4.7.2 and run the main scene, or use:

```bash
godot --path .
```

Run headless checks:

```bash
./scripts/test.sh
```

On Windows use `./scripts/test.ps1`. In addition to six unit suites, both scripts replay the entire automated contract at 30, 60, and 144Hz and require identical comprehensive state hashes.

Fast scene and end-to-end automation checks:

```bash
godot --headless --path . -- --smoke
godot --headless --path . -- --auto-smoke
```

The automation smoke prints a canonical semantic-state hash. The CI workflow repeats that replay in the exported Linux and Windows executables and rejects a cross-platform hash mismatch.

Build both desktop targets after installing matching export templates:

```bash
./scripts/export_all.sh
```

On Windows PowerShell:

```powershell
./scripts/export_all.ps1
```

The product design baseline is in `docs/GAME_DESIGN_FINAL_v1.0.md`.

Generated desktop artifacts are placed at `build/linux/make-it-big.x86_64` and `build/windows/make-it-big.exe`. The Windows executable is built on Linux from the official matching template; the included CI workflow boots it again on a real Windows runner.
