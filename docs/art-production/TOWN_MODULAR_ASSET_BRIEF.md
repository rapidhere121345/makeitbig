# Hearthside Modular Asset Delivery Brief

Date: 2026-10-22. Status: **pending production specification**.
Companion [spatial/art reconstruction design](../rebuild/TOWN_SPATIAL_ART_REDESIGN.md).
Not provenance for generated assets: actual production must retain sources, model/tool, parameters, raw outputs, reviewed processing, and output SHA.

## 1. Art Direction and Production Order

Retain snow, dark wood, stone, cold gray-blue environment, warm amber light, and existing Ranger scale. Old whole-town illustration is color/atmosphere reference only.

First finish a character-scaled greybox and camera/pixel-density calibration sheet; then independent objects. Lock three-quarter overhead view, parallel projection, light direction, density. Generator must not reinvent perspective per object. Calibration explicitly draws ground axes, character feet, doorways, wall height, contact surfaces; "isometric" alone is insufficient.

World uses design pixels,640×360 viewport. Retain 48×48 actor animation canvas as initial ruler; canvas size is not physical body width. Confirm suggested dimensions in sample, then freeze; no nonuniform stretching to fit.

## 2. First Sample Package

| Group | Initial suggestion | Separate required deliveries |
| --- | --- | --- |
| Continuous ground |960×640 sample, possibly tiled |Complete snow/stone base without trees/buildings/fences/their fixed shadows; path-edge decals |
| Loadout building |About 256×224 shared canvas |Base/complete lower, roof/upper, designed roof-off structure, contact shadows; exterior service socket |
| Pine |About 96×128 shared canvas |Complete trunk/low branches/roots, canopy, revealed state, separate shadow |
| Fence/gate |About 64×64 per segment, revised by calibration |Straight/corner/posts, own feet per segment, real doorway clearance |
| Logs |About 96×64 |Complete independent pile, contact edge, shadow; usually no reveal |
| Review output |Fixed camera/scale |Isolated, assembled, all uppers removed, hero front/back/side preview sets |

No initial whole-town panorama, dozens of candidates, or all-facility replacement. Building/tree/fence samples must prove layering, ground occupancy, and revealed appearance in runtime before expanding the series.

The corrected first-sample numbers for the loadout building — 256×224 canvas, placement (148,148), layer/socket contracts, and alignment rules — are fixed in [TOWN_LOADOUT_SAMPLE_SPEC.md](TOWN_LOADOUT_SAMPLE_SPEC.md). The packed sample exists under `art/production/p1/town_modular_v01/` and `content/environment_objects/town_loadout_v01.tres`; its rendered-sample preview was accepted on 2026-10-23 ([acceptance record](../playtest/TOWN_LOADOUT_SAMPLE_ACCEPTANCE_20261023.md)), and shipped-town integration is pending. Four raw candidates remain retained unaccepted under [p1-town-modular-v01/](p1-town-modular-v01/) — exact requests in its PROMPTS.md, packing recipe and accepted deviations in its PROCESSING.md. The remaining ground/pine/fence/log sample scope below is unchanged.

## 3. What a Revealed Version Means

Roof removal exposes credible beam/post sections, rear low walls/floor, or complete exterior ground. First-chapter interactions stay in exterior service zones; no full interior gameplay needed. Shared full/roof-off content must come from one reviewed layer set.

Trees retain complete trunk/low branches/roots/contact while removing/retracting upper canopy. No gray translucent blobs. Rocks do not become perforated sponges; excessive coverage requires revised walkable area and rock shape.

Minimum:

```text
ground (always present)
shadow/contact (owned per part, not baked twice)
common/base (shared by both states, drawn once)
upper_full / upper_revealed (exclusive states, shared canvas/pivot)
```

upper_revealed may be empty only with complete lower content and approved upper-off appearance. Do not independently generate unconstrained full/revealed versions: doorposts, textures, perspective, dimensions drift. Lock lower/camera, generate/edit upper from same composition, then align pixels and hand-correct as needed. Generator does not replace assembly review.

## 4. Minimum Package Data

Field responsibilities below; serialization follows project Resource/native-scene conventions, not a second hand-maintained room layout.

| Field | Author/source | Validation |
| --- | --- | --- |
|asset_id / revision |Production package |Stable, unique; revision recorded per art change |
|logical_canvas / origin |Calibration/canvas |Same both states; transparent trimming does not move origin |
|parts |Reviewed layers |Texture, local offset, layer category, sort anchor, rank per part |
|footprint |Greybox base |Finite legal ground contour, reviewed overlaid on contact art |
|movement_margin |Author parameter |Baker expands once; report abnormal concavity/narrow routes |
|reveal_mode |Author choice |none or authored_variant, no automatic circular holes |
|reveal_mask |Full upper coverage |Exclude shadows/halos/ground; AABB broad phase only; same full mask after switching |
|lower_content |Lower asset references |No transparent holes or old-structure residue in exposed regions |
|interaction / approach |Facility design |Preserve ID, reachable foot center, sensible facing, door clearance |
|source / processing / hashes |Actual production log |Traceable originals, reproducible processing; no false deterministic-service claim |

Art informs footprint design but PNG alpha must not auto-generate collision: canopy/roof/shadow/snow pixels are not ground occupancy. asset_id has no room coordinates; rooms reference stable placement_id. Expanded placement_id/part_id matches plan/drawing. Full/revealed textures and masks, references and content SHA, all enter presentation validation; supports_cutaway=true alone proves nothing.

## 5. Generation Constraint Templates

Replace bracketed placeholders for every actual request; retain exact parameters/reference images with outputs. Calibration must be greybox-exported or purpose-drawn; never crop old-town buildings as new-object subjects. These are future-request templates, not records of executed prompts.

### Independent Object, Full

```text
Purpose: production asset for an independently placeable 2D game environment object.
Object: [for example, snowy pine-wood Loadout building, exterior service area, no people].
Reference: [approved camera calibration] for view, scale, ground axes, lighting;
           [style sheet] only for cold gray-blue snow, dark wood/stone, amber light, pixel density.
Fixed canvas: [size]; ground origin: [coordinates]; footprint template: [contour].
Draw the complete object without neighboring buildings, streets, landscape composition, other occluders.
Do not crop roof, base, rear outline. Align base to the given footprint.
Transparent background; no people, UI, text, frame, grid, scale marks.
Deliver object shadows separately as specified; no street/other-object shadows within the object.
```

### Complete Lower / Revealed Version

```text
Use the same locked canvas, camera, origin, approved lower layers; move no shared structure.
Deliver: [roof-off low walls/beam-post structure, or canopy-off complete trunk/low branches].
Paint structure hidden by upper parts in the normal state; not mere erasure or alpha reduction.
Retain established base, contact edges, materials, light direction.
Show complete independent object without neighbors or environment ground.
Provide directly overlayable same-origin version for later pixel-alignment review.
```

### Ground

```text
Follow approved greybox routes to deliver continuous winter snow/stone-road base.
No buildings, trees, logs, lamps, fences, people, or their fixed shadows.
Future object positions still need complete ground, never transparent holes.
Deliver cliff/shore modules separately; walkable top surfaces must match footprint template.
Do not enrich composition with undefined main-road obstacles.
```

Transparency, dimensions, and layering depend on actual tools. Composite-only outputs are not qualified multilayer packages: complete lower/aligned layers must be supplied. Background removal cleans independent objects only, not whole-town illustration segmentation into production layers.

## 6. Before Import

1. Store raw output and actual request; runtime PNGs derive from recorded processing.
2. Lock canvas/origin, align reference actor; no normal/revealed size jumps.
3. Inspect transparent/snow edges and color contamination on neutral, black, white, gray backgrounds; no dirty fringes.
4. Move object on continuous ground; no building residue/fixed shadow at old position.
5. Hide uppers and see complete lower; transparency without underplate fails.
6. Overlay footprint, movement envelope, actor radius, interaction positions; review margins/routes, then hide overlay and judge route readability.
7. Render single states, transitions, and two-object overlap; only then batch whole-town assets.

Automatic gates check files, anchors, masks, reproducible processing. Visual review checks form, material, contact, roof-off state. Both must pass; one test PASS substitutes for neither.

## 7. Implemented Interface and Preview

Technical foundation/GPU greybox iterations: [2026-10-22 implementation record](../playtest/TOWN_MODULAR_FOUNDATION_20261022.md).
Source defines actual EnvironmentObjectDefinition fields: asset_id, canvas_size, visual_parts, ground_parts, footprints, movement_envelopes, sockets. Instances translate only; sort rank nonnegative integer. Revealed texture/mask share full canvas. Mask reads **alpha**, not grayscale brightness. Current authors deliver final movement envelopes explicitly, without automatic expansion.

Reproduce the greybox with X11 and a working OpenGL renderer; DISPLAY must point to an existing exclusive validation display. CPU Mesa/llvmpipe with Xvfb is accepted for rendered-pixel, UI, collision, and occlusion correctness. A discrete GPU is not required. Record the actual renderer and do not infer hardware performance from software-rendered checks.

```bash
source scripts/project_env.sh
"$GODOT_BIN" --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path "$MIB_PROJECT_ROOT" \
  --script res://tools/modular_town_preview.gd -- \
  --output=res://build/current/modular-town-preview-new
```

Output must be a new res://build/ subdirectory, containing scene, manifest, synthetic test images, screenshots, checks. It is explicitly labeled GREYBOX and cannot replace production-art review.

On an NVIDIA host, PRIME offload environment variables may be added when deliberately validating that renderer. Historical RTX evidence in the implementation report remains hardware-specific; it is not a prerequisite for future correctness acceptance.
