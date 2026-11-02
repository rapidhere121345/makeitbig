# Battlefield plates and materials

This package contains five complete combat environment plates, five outpainted
backing plates, two auxiliary material textures, and a shoreline stone sprite. The plates include their
painted banks and cliffs; the auxiliary resources remain prepared materials.
The original generated PNGs are retained in `sources/`; generation
prompts and SHA-256 digests are recorded in `provenance.json`. The recipe in
`tools/art_pipeline/battlefields_v01/packing_config.json` pins each source digest.

The 2026-11-01 audit found that the retained source PNG bytes differed from the
original generation digests. Their cause of change is unknown. Recompiling all
13 active sources reproduced all 14 existing runtime PNGs byte for byte. The
active recipe and runtime manifest now pin the retained files; original
`provenance.json` remains unchanged. See
[the source reconciliation record](SOURCE_RECONCILIATION_20261101.json) for old
and current source digests and verified output hashes. This establishes runtime
reproducibility, not byte identity with the original generated sources.

From the repository root, rebuild and verify the runtime package with:

```sh
./scripts/with_env.sh python3 -I tools/art_pipeline/world_expansion_v01/pack.py --config tools/art_pipeline/battlefields_v01/packing_config.json
./scripts/with_env.sh python3 -I tools/art_pipeline/world_expansion_v01/pack.py --config tools/art_pipeline/battlefields_v01/packing_config.json --verify
./scripts/with_env.sh python3 -B -m unittest discover -s tools/art_pipeline/battlefields_v01/tests
```

The shared compiler uniformly scales each floor to width 1024 with nearest
sampling and center-crops to 1024×640. Material textures are uniformly scaled
to 1024×1024 from the full square sources. The initial five plate sources are
retained as superseded provenance; the revised river plate includes the river
and bridge. Each 1536×1024 backing is an unscaled crop of its full generated
source, prompted with the corresponding 1024×640 floor centered at [256, 192].
The generated center is approximate; runtime overlays the original floor to
preserve its authored terrain alignment. The output manifest records each source, digest, and exact
transform. Ground and material output pixels must be opaque. The shoreline sprite
is packed as opaque and translucent variants with a shared 160×72 canvas and
anchor at [80, 64]. Import sidecars disable alpha border repair to preserve
source colors.
