# World and UI polish — 2026-10-25

Eight original assets were generated with the built-in `image_gen` tool. The
exact prompts are in `prompts/`, original RGBA outputs in `sources/`. The style
reference was the project's accepted world calibration at
`../actor-redraw-20261024/references/accepted_world_calibration.png`; no pixels
were cut from that reference. Dark slate, copper, restrained amber and cold teal
continue the approved ancient magical world.

`tools/art_pipeline/world_polish_v01/build.py` packs four low ground details
(fern, mushrooms, votives, broken rune tablet) and four original combat icons.
It thresholds alpha at 240, trims transparent padding, uses one rational scale
for both axes with nearest sampling, and retains two native pixels of padding.
The import recipe is shared with `actors_v02`, preserving existing Godot UIDs
and disabling alpha-border processing. `--verify` compares every emitted PNG
and JSON byte without writing. `assets.json` records source and prompt hashes,
canvas, anchor, occupied bounds and the exact scale used.

Runtime art: `art/production/p1/world_polish_v01/`.
Placements: `content/presentation/world_dressing.json` — 32 town and 18 arena
details in native ground coordinates. These small ground objects draw beneath
actors, structures and telegraphs; they add no collision, interaction or actor
registry entries. Existing feet-based collision, reveal and room geometry stay
authoritative. The four skill bindings remain Piercing Arrow, Hunter's Mark,
Dash and Dodge, each on a 32×32 canvas with its original semantic slot ID.

Character work preserves the accepted actor sheets. The old procedural clothing
and equipment repaint was removed; the sprite now supplies its complete body,
with only stride dust and brief release/mobility accents layered around it.
Skill flight positions, timing, contact geometry and damage are unchanged.

Validation is recorded in `docs/playtest/WORLD_UI_POLISH_20261025.md` after the
rendered and frozen build gates finish. Software rendering is visual correctness
evidence, not a hardware performance benchmark.
