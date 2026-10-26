# Provenance — p1-town-modular-v01

Status: **four raw candidates retained. The checkpoint-2 pack (upper_full,
upper_revealed, shadow) is parent-accepted for advancing to the rendered
sample stage ONLY — in-engine validation and shipped-town integration are
pending, and nothing is runtime-integrated.** On 2026-10-22 candidate 01 was
packed into the checkpoint-1 `common` layer (parent-accepted for the sample
stage at checkpoint 1) and the two guide-edit upper raws were packed with one
shared guide-edit normalization into the checkpoint-2 layers plus the
code-authored `shadow.contact` slab — see [PROCESSING.md](PROCESSING.md) for
the acceptance record, the reviewed sheet paths, and the two separate source
spaces (candidate-01 raw 155/24 vs guide-edit 419/80). All raw files below
remain byte-identical (hashes re-verified before each pack). Common candidate
02 remains unpacked; the two upper edits were one generator stage per
variant, per the parent's instruction. A pine common candidate (request A
of [PINE_SPEC.md](PINE_SPEC.md)) was generated on 2026-10-22, packed, and
is parent-accepted as drawn (common layer only, sample stage) and installed
at the runtime art path; a pine upper candidate (request B) and a compact
common v02 candidate (request C) were generated the same day, and their
**accepted v02 assembly install** (compact base + B-crown canopy cut at
y96 + code-authored contact shadow, static rendered-sample scope, not
engine/native acceptance) landed at the runtime art paths on 2026-10-22 —
see the pine sections below.

## Generation

Executed by the parent with the parent's built-in image generation tool
(`image_gen`). The tool did not expose a model identifier; none is invented here.

| Field | Candidate 01 | Candidate 02 |
| --- | --- | --- |
| Use case | stylized-concept (new image) | precise-object-edit of candidate 01 |
| Tool settings | `transparent_background=true`; no reference image arguments | `transparent_background=true`; `num_last_images_to_include=1` (the only image input was candidate 01) |
| Reference input | none as image input; the parent visually consulted `art/production/p1/hamlet_town/town.png` for palette/atmosphere while writing the request only | candidate 01 only |
| Request text | [PROMPTS.md](PROMPTS.md), candidate 01 section, verbatim | [PROMPTS.md](PROMPTS.md), candidate 02 section, verbatim |
| Raw source | `/home/dev/.codex/generated_images/01a165a0-131e-7690-be00-610833ac1143/exec-547cc5b8-8f40-40f6-90e8-16379a623ab9.png` | `/home/dev/.codex/generated_images/01a165a0-131e-7690-be00-610833ac1143/exec-83d085e1-598d-4fc2-866c-9e52a22c877b.png` |
| Retained copy | `sources/loadout_common_candidate_01.png` | `sources/loadout_common_candidate_02.png` |
| Copy verified | byte-identical (`cmp`) | byte-identical (`cmp`) |
| SHA-256 | `2e7dd83a010e0be94ec17b504de075b69c71ca13050c0b14ae2ad2a504ed758a` | `22c590aa46ba6238b1b390f76008201b1dcb7e606bc3c0a7c1ae5cf455872a1a` |
| Size | 562861 bytes | 567027 bytes |

## Upper-layer generation (guide edits, 2026-10-22)

Executed by the parent with the same built-in `image_gen` tool against the
checkpoint-1 calibration guides produced by `make_guides.py`. Each variant had
exactly one generator stage. No model identifier was exposed.

| Field | Upper candidate 01 (roof) | Upper candidate 02 (roof-off) |
| --- | --- | --- |
| Use case | precise-object-edit | precise-object-edit |
| Tool settings | `transparent_background=true` | `transparent_background=true` |
| Reference input | `build/current/p1-town-modular-v01/checkpoint-1/loadout_roof_guide_256x224.png` (ignored build output) | `build/current/p1-town-modular-v01/checkpoint-1/loadout_stubs_guide_256x224.png` (ignored build output) |
| Request text | [PROMPTS.md](PROMPTS.md), upper candidate 01 section, verbatim | [PROMPTS.md](PROMPTS.md), upper candidate 02 section, verbatim |
| Raw source | `/home/dev/.codex/generated_images/01a165a0-131e-7690-be00-610833ac1143/exec-fb22f320-29ea-4784-8bf5-9bd711408394.png` | `/home/dev/.codex/generated_images/01a165a0-131e-7690-be00-610833ac1143/exec-42c63d53-5a60-4b83-8572-999c1a8c3085.png` |
| Retained copy | `sources/loadout_upper_candidate_01.png` | `sources/loadout_upper_candidate_02.png` |
| Copy verified | byte-identical (`cmp`) | byte-identical (`cmp`) |
| SHA-256 | `1d1711572c66901d190c1f1d0920e0199e20c198a1d9e0eebdc99526fc8a3f14` | `c10d04f299048b915ce6d081dc74f9d589046c69b26bebe200575102d75bf382` |
| Size | 918875 bytes | 366082 bytes |
| Canvas | 1341x1173 | 1341x1173 |

Hashes cover the retained copies and were verified equal to the raw sources
before any inspection. Inspection was read-only
([CANDIDATE_REVIEW.md](CANDIDATE_REVIEW.md)); no pixel of any retained file
was altered. The upper raws' edited facades were discarded at the seam cut
during packing — the accepted `common` layer was never replaced (its hash is
pinned in `build_upper.py` and re-verified at every build).

The old town illustration is reference/atmosphere only, never an object source
or cutout, per the [sample spec](../TOWN_LOADOUT_SAMPLE_SPEC.md) and the
[delivery brief](../TOWN_MODULAR_ASSET_BRIEF.md).

## Pine generation (request A of PINE_SPEC.md, 2026-10-22)

Executed by the parent with the same built-in `image_gen` tool against the
stage-1 pine guide produced by `make_pine_guides.py`. Exactly one generator
stage. No model identifier was exposed. The raw stays retained and
unmodified. Its deterministic pack was **parent-accepted as drawn on
2026-10-22** (scope: the common layer, for sample assembly - the 9 px
upward trunk top is accepted because the canopy covers it; the 2 px high
feet and 1 px left drift are accepted; not pixel-identical guide geometry)
and installed at `art/production/p1/town_modular_v01/pine_common.png`,
SHA-256 `7aa70586ccd908d50ce97451534ff8f1f37c433ba3b9e72e13a7c2f8f50333a2`
(96x144, 6498 bytes; pinned in `build_pine.py` and re-verified on every
run). Recipe, measured deviations and review paths:
[PROCESSING.md](PROCESSING.md), pine section. No canopy art, shadow or
definition exists yet; request B (upper/canopy) runs against the stage-2
guide built from exactly this accepted common.

| Field | Pine candidate 01 (common) |
| --- | --- |
| Use case | precise-object-edit |
| Tool settings | `transparent_background=true` |
| Reference input | `build/current/p1-town-modular-v01/pine-checkpoint-1/pine_common_guide_96x144.png` (ignored build output, SHA `fac6ba86649a70b7de557a55403cc48fe2aff8d04df37c848df3f0b6f36e5ab1`) |
| Request text | [PROMPTS.md](PROMPTS.md), pine candidate 01 section, verbatim from `request-a.json` |
| Raw source | `/home/dev/.codex/generated_images/01a165a0-131e-7690-be00-610833ac1143/exec-ea7716d7-13fa-4f0e-b1d1-744dd8760bf8.png` |
| Retained copy | `sources/pine_common_candidate_01.png` |
| Copy verified | byte-identical (`cmp`) |
| SHA-256 | `b23b9675357c8e305d8a7e7ad4fb00885c432f0f53cf21bdf9dffa3856dde5fb` |
| Size | 1030211 bytes |
| Canvas | 1024x1536 (exactly 2:3, matching the 96x144 design canvas; uniform scale 32/3) |

Alpha characterization (measured read-only before any pack): the raw
contains no alpha-255 pixel; its opaque band is 250..254 (13.33% of the
canvas), a 200..249 edge fringe rings the object, and a broad faint wash at
alpha 31 or below spans much of the canvas - the halo seen in review. The
pack proposal binarizes at 250, discarding the fringe and wash wholesale;
no pixel of the retained file is altered.

## Pine generation (request B of PINE_SPEC.md, 2026-10-22)

Executed by the parent with the same built-in `image_gen` tool against the
stage-2 canopy guide produced by `make_pine_guides.py` (the accepted common
with the reserved canopy disc composited on top). Exactly one generator
stage; the executed text is the parent's tightened variant, recorded
verbatim in [PROMPTS.md](PROMPTS.md). The candidate is **retained
unaccepted**: a full-tree uniform pack proposal, the seam/common risk
assessment and the compact-base (common v02) proposal exist only under the
ignored pine checkpoint build directory, and no runtime asset was
overwritten - the accepted v01 common stays installed unchanged.

| Field | Pine upper candidate 01 |
| --- | --- |
| Use case | precise-object-edit |
| Tool settings | `transparent_background=true` |
| Reference input | `build/current/p1-town-modular-v01/pine-checkpoint-1/pine_canopy_guide_96x144.png` (ignored build output, SHA `1dc59fd45842d654ba77cc3684573500a19a64d0de74c43296405b5fe97777a2`) |
| Request text | [PROMPTS.md](PROMPTS.md), pine candidate 01 (upper) section, verbatim from `request-b.json` |
| Raw source | `/home/dev/.codex/generated_images/01a165a0-131e-7690-be00-610833ac1143/exec-f03c5a6d-a5cd-4ac7-ba3c-99480f716c23.png` |
| Retained copy | `sources/pine_upper_candidate_01.png` |
| Copy verified | byte-identical (`cmp`) |
| SHA-256 | `f1bd90ecaca3c23d2c38efc2933d61dbf84fbe9a395fafae2d7bdb7a16199ce9` |
| Size | 1516629 bytes |
| Canvas | 1024x1536 (exactly 2:3 again; the same uniform scale 32/3 applies) |

The raw returned a complete repainted tree (crown + trunk + roots in one
sprite), not the reference's v01 pixels - measured and recorded in
[PINE_SPEC.md](PINE_SPEC.md); its alpha structure matches candidate A (no
alpha-255; opaque band 250..254) and the pack proposal binarizes at 250
exactly as before. No pixel of the retained file is altered.

## Pine generation (request C of PINE_SPEC.md, 2026-10-22)

Executed by the parent (root imagegen) against the v02 base guide produced
by `make_pine_guides.py` stage 3 (the B-derived pack with the crown mass
flattened). Exactly one generator stage; the executed text is the parent's
tightened variant, recorded verbatim in [PROMPTS.md](PROMPTS.md). The
retained copy was made by the parent and verified byte-identical by this
lane. **Accepted as drawn on 2026-10-22** for the rendered sample stage
(static art scope, not engine/native acceptance; recorded without a
fulltownpass run) and installed by `build_pine_v02.py`: the packed base at
`art/production/p1/town_modular_v01/pine_common_v02.png` (SHA-256
`815160150d4142c138ac0a789d68564d07e7565290d0fd4f995854fec8083392`) and
the B-crown canopy cut at its measured crown bottom row y96 at
`pine_canopy_v02.png` (SHA-256
`93833b1f79bcc5d4609f9078d15e0486a2190d9c7de07ff73fa7f41cd27947c0`;
B's trunk rows discarded wholesale — an explicit redesign cut, never a
transfer of the tall v01 common, which stays installed unchanged). The
small contact shadow `pine_shadow_v02.png` (SHA-256
`061aa4f895e0a1768a5855cb4b201a5295a4e8d2295ccacee1e4d6273222c42b`) is
**code-authored** (deterministic constants; color family sampled from the
accepted `loadout_shadow.png`) — no generator was involved in it. Two new
definitions were authored pending ca validation:
`content/environment_objects/town_pine_v02.tres` and
`content/environment_objects/town_loadout_fade_v01.tres` (the fade-policy
sibling; `town_loadout_v01.tres` itself is unchanged). Processing and
acceptance details: [PROCESSING.md](PROCESSING.md), pine v02 section.

| Field | Pine common v02 candidate 01 |
| --- | --- |
| Use case | precise-object-edit |
| Tool settings | `transparent_background=true` (request-c.json records no tool or model identifier) |
| Reference input | `build/current/p1-town-modular-v01/pine-checkpoint-1/pine_common_v02_guide_96x144.png` (ignored build output, SHA `f79679ff0a9c3df0bca6eef4eded63f838a11e3ca48c8d5571e6de4052b03e5d`) |
| Request text | [PROMPTS.md](PROMPTS.md), pine common v02 candidate 01 section, verbatim from `request-c.json` |
| Raw source | `/home/dev/.codex/generated_images/01a165a0-131e-7690-be00-610833ac1143/exec-f07b859a-eabe-412d-88f7-ddb5ac39f0fc.png` |
| Retained copy | `sources/pine_common_v02_candidate_01.png` (copied by the parent) |
| Copy verified | byte-identical (`cmp`, re-verified by this lane) |
| SHA-256 | `e2fd870180d40b514d1558bd5949ff7efae991add5e664dc7d76cb71d5d3aadf` |
| Size | 709073 bytes |
| Canvas | 1024x1536 (exactly 2:3 again; the same uniform scale 32/3 applies) |

Alpha structure matches the earlier pine raws (no alpha-255; opaque band
250..254, fringe and faint wash below the threshold discarded at pack).
No pixel of the retained file is altered.
