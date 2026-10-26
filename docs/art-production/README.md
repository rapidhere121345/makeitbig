# Current Art Sources and Maintenance

The authoritative production resources are those read by runtime code in `art/production/p1/`. This directory retains original images, actual prompts, provenance, and recipes for current assets; the recorded generator is the built-in image_gen. Source images retain their original bytes; recipes perform cropping, background removal, nearest-neighbor scaling, and atlas arrangement.

| Current resource | Retained source |
| --- | --- |
| Road-facing forge/equipment shop and alternate wall runs | [Town order provenance and prompts](town-order-20261026/provenance.json); deterministic recipe in `tools/art_pipeline/town_order_v01/packing_config.json` uses the shared world-expansion packer |
| Winding town terrain, bridges, perimeter and residential variants; distinct combat floors | [World expansion](world-expansion-20261025/README.md): original sources, prompts, pinned hashes and deterministic packing |
| Town and battlefield ground and whole-object scenery | [Generated world v02](generated-world-v02/README.md): angled `perspective-20261024/` sources (the earlier front-facing set was retired on 2026-10-26), exact prompts/hashes, deterministic packing and aligned opaque/transparent pairs |
| Ranger, enemy families, articulated boss and five resident animations | [Actor redraw](actor-redraw-20261024/README.md): prompts, sources and provenance; runtime `art/production/p1/actors_v02/` is built by `tools/art_pipeline/actors_v02/build.py` (the resident compiler still reads the `npc_*_raw.png` sheets kept in `generated-world-v02/sources/`) |
| Hamlet style, concept and life references | `p1-hamlet-style-r13/`, `p1-hamlet-concept-v02/`, `p1-hamlet-life-v01/` |
| Retained battlefield actors and historical scene compatibility assets | `p1-combat-style-r13/`; `p1-scene-rework-v01/`, `p1-calibration-v01/` |
| Ranger and enemy action atlases (frame contracts and base atlases under the actors_v02 styled art) | `p1-ranger-actions-v01/recipe.final.json`, [p1-enemy-actions-v01](p1-enemy-actions-v01/README.md), and corresponding sources |
| Equipment, skills, navigation, talents, Law Tokens | `p1-early-loop-v01/`, `p1-equipment-readability-v02/`, `p1-hub-navigation-v01/`, `p1-icon-expansion-v01/` |
| UI materials | Original images, prompts, and packing maps in `p1-ui-style-r13/` |
| Title, loop, and return | `p1-title-concept-v02/`, `p1-title-life-v01/`, `p1-hearth-return-v01/` |
| Five dialogue portraits | `p1-story-portraits-r14/`: v03 original, prompts, current crop recipe, and FROZEN import manifest only |
| Ground and visual references | `p1-ground-refine-v01/`; production reference originals and prompts retained in `concepts/` |

Concept references do not directly replace runtime textures. `concepts/` is retained as art design, including `r13/hearthside-town-composition-v01.png`, the Hearthside composition original that supplied palette, materials and camera reference to the generated worlds; it is kept as a design reference, not as a source of runtime pixels. Font provenance and original license are in [PROVENANCE.md](../../art/fonts/PROVENANCE.md) and [LICENSE-noto-cjk.txt](../../art/fonts/LICENSE-noto-cjk.txt); generated-image provenance is not a third-party license.

Maintenance checks: `scripts/test.sh` invokes `tests/test_scene_atmosphere.gd` and `tests/test_workbench_layout.gd`. The former depends on scene lighting, town, battlefield, return presentation scripts, and `ground_refine_v01/ground.png`; the latter on `facility_screen.gd` and `tests/test_facility_screen.gd`. Production resources and external dependencies are unchanged. The current font comes from a pinned upstream Medium file; the old Regular repacking script was removed with historical outputs. Portrait import checks use the current FROZEN manifest. Old screenshots, GIFs, project copies, candidates, and acceptance reports do not belong in these directories.
