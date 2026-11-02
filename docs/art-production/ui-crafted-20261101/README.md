# Crafted UI materials

The source files in `sources/` are byte-for-byte copies of the generated images supplied for this package. Their original generation session was `/home/dev/.codex/generated_images/01a19751-6298-7fa3-9a46-fb8bf0faf12c/`:

| Source | Original file | SHA-256 |
| --- | --- | --- |
| `workshop_original.png` | `exec-3d1d33be-0429-4c42-8e2e-2a29ca1d8cb9.png` | `af6c8180c968f7710db377d67456ce18d8410ad0b848fbbe36ed0b45c8409a04` |
| `action_original.png` | `exec-546efa23-ea3f-4dcc-8aa5-89dab254a139.png` | `c34455c0eec435b6c74c2fff6edf944798bb8f78fd1fafe109c997ad99134dcd` |
| `crest_original.png` | `exec-ad5eee65-b625-40b5-ac98-e8a788bc5fe6.png` | `bd7a1048920046a58785cb3e3a324ab8de57bdd2d21949093664b0085786e39c` |

The packer uses Pillow nearest-neighbor resizing without palette quantization or painting. It crops the workshop to the centered exact 16:9 source rectangle `[4, 2, 1668, 938]`, then fits it to 1280×720. The action crop is determined by source alpha greater than 1, removing outer alpha-1 noise; retained pixels inside that crop are not altered before nearest-neighbor resizing. The result is 512×56. The crest still uses the full nonzero-alpha bounding box and is fitted inside a 160×160 transparent canvas with an eight-pixel inset. The source plaque has nonzero alpha at both horizontal image edges, and the crest has it at the left and bottom edges. Nearest sampling can omit individual source pixels during downscaling.

The runtime manifest records source and output hashes, exact crop, scale, offset, alpha bounds and resource paths. PNG import sidecars use the existing `world_expansion_v01` sidecar generator, with no invented UID and alpha-border processing disabled. Generation prompts are recorded separately by the requester.

From the repository root, regenerate and then verify:

```sh
build/toolchain/python/bin/python tools/art_pipeline/ui_crafted_v01/build.py
build/toolchain/python/bin/python tools/art_pipeline/ui_crafted_v01/build.py --verify
```

Verification recompiles in memory and compares the sources, output PNG bytes, sidecars, and manifest. It does not invoke Godot or modify files. Source hashes are pinned in `recipe.json`; an altered source fails verification.
