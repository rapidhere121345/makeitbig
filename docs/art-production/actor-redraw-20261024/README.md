# Chapter-one actor redraw

Original actor sources generated with the built-in image-generation tool to match the accepted dark, angled world. The reference calibration supplies camera and materials; no actor pixels are extracted from external games. The design uses slate, worn bronze, ash highlights and restrained magical color. The Ranger uses a teal mantle, the residents carry role-specific work props, enemy families have distinct silhouettes, and the Colossus has a broken-ring crown and violet core.

`prompts/` retains generation briefs. `sources/` retains original generator output; the explicitly rejected Mira draft is not selected. `provenance.json` identifies source hashes and original generator files. Runtime output belongs in `art/production/p1/actors_v02/`; its deterministic compiler is `tools/art_pipeline/actors_v02/build.py`.

The production contracts remain 68 Ranger action frames, 39 enemy action frames, 20 resident work frames and six articulated boss parts. Four static Ranger views and twelve enemy fallback views derive from the new action designs. Frame IDs, animation cadence, simulation timing, body radii and authoritative arrow sockets remain separate from artwork.

Technical packing thresholds generated transparency, locates complete poses, samples uniformly with nearest-neighbor scaling and places them at the existing anchors. It must not normalize crouched/dead frames independently, clip opaque pixels at nominal grid boundaries, or substitute old artwork when a new pack is missing. Imported textures retain exact RGBA pixels with `fix_alpha_border=false`.

Source sheets and packing checks are not rendered acceptance. Final in-game evidence, limitations and release certification are recorded separately under `docs/playtest/` after execution.
